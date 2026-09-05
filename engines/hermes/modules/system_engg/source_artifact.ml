module Id : sig
  type t = private string
  val make : string -> (t, string) result
  val to_string : t -> string
  val compare : t -> t -> int
end = struct
  type t = string
  let make s =
    if Core.String.is_empty s then Error "Empty ID"
    else Ok s
  let to_string s = s
  let compare = String.compare
end

module Sha256 : sig
  type t = private Digestif.SHA256.t
  val of_hex : string -> (t, string) result
  val digest_file : string -> (t, string) result
  val to_hex : t -> string
  val equal : t -> t -> bool
end = struct
  type t = Digestif.SHA256.t
  let of_hex s =
    if String.length s <> 64 then Error "SHA-256 must be exactly 64 characters"
    else
      try Ok (Digestif.SHA256.of_hex s)
      with _ -> Error "Invalid hex SHA-256 string"
  let digest_file path =
    try
      Ok (Digestif.SHA256.digest_string (Core.In_channel.read_all path))
    with exn -> Error (Core.Exn.to_string exn)
  let to_hex t = Digestif.SHA256.to_hex t
  let equal = Digestif.SHA256.equal
end

module Git_oid : sig
  type algorithm = Sha1 | Sha256
  type t = private { algorithm : algorithm; hex : string }
  val of_hex : algorithm:algorithm -> string -> (t, string) result
  val algorithm : t -> algorithm
  val to_hex : t -> string
end = struct
  type algorithm = Sha1 | Sha256
  type t = { algorithm : algorithm; hex : string }
  let of_hex ~algorithm s =
    let len = match algorithm with Sha1 -> 40 | Sha256 -> 64 in
    if String.length s <> len then Error "Invalid OID length"
    else Ok { algorithm; hex = String.lowercase_ascii s }
  let algorithm t = t.algorithm
  let to_hex t = t.hex
end

module Relative_path : sig
  type t = private string
  val make : string -> (t, string) result
  val to_string : t -> string
end = struct
  type t = string
  let make s =
    if Core.String.is_empty s then Error "Empty path"
    else if Core.String.is_prefix s ~prefix:"/" then Error "Absolute path not allowed"
    else if Core.String.contains s '\\' then Error "Backslash path separator not allowed"
    else if Core.String.contains s '\000' then Error "NUL character not allowed"
    else
      let components = Core.String.split s ~on:'/' in
      if Core.List.exists components ~f:(fun c -> Core.String.is_empty c || Core.String.equal c "." || Core.String.equal c "..") then
        Error "Invalid path component"
      else Ok s
  let to_string s = s
end

type entry_kind = Regular | Executable | Symlink | Submodule | Lfs_pointer

type tree_entry = {
  path : Relative_path.t;
  kind : entry_kind;
  mode : int;
  blob_sha256 : Sha256.t option;
  symlink_target : string option;
  git_oid : Git_oid.t option;
}

type pin =
  | Blob_pin of { sha256 : Sha256.t; byte_count : int }
  | Git_tree_pin of {
      commit : Git_oid.t;
      tree_oid : Git_oid.t;
      canonical_tree_sha256 : Sha256.t;
      entry_count : int;
    }

type expected = {
  id : Id.t;
  locator : Uri.t;
  pin : pin;
}

type observation =
  | Observed_blob of { sha256 : Sha256.t; byte_count : int }
  | Observed_git_tree of {
      commit : Git_oid.t;
      tree_oid : Git_oid.t;
      canonical_tree_sha256 : Sha256.t;
      entry_count : int;
    }

type receipt = {
  expected : expected;
  observation : observation;
}

type verification_error =
  | Unknown_source_state of string
  | Digest_mismatch of { expected : string; observed : string }
  | Entry_count_mismatch of { expected : int; observed : int }
  | Type_mismatch of string
  | Path_error of string

let expect ~id ~locator ~pin = { id; locator; pin }

let pin expected = expected.pin

let put_be32 value =
  let buf = Bytes.create 4 in
  Bytes.set buf 0 (Char.chr (Core.Int.shift_right value 24 land 0xFF));
  Bytes.set buf 1 (Char.chr (Core.Int.shift_right value 16 land 0xFF));
  Bytes.set buf 2 (Char.chr (Core.Int.shift_right value 8 land 0xFF));
  Bytes.set buf 3 (Char.chr (value land 0xFF));
  Bytes.to_string buf

let canonical_tree entries =
  let errors = ref [] in
  (* Check case-fold collisions and duplicate paths *)
  let seen_paths = Hashtbl.create 17 in
  let seen_folds = Hashtbl.create 17 in
  List.iter (fun entry ->
    let p = Relative_path.to_string entry.path in
    let fold = String.lowercase_ascii p in
    if Hashtbl.mem seen_paths p then
      errors := Path_error ("Duplicate path: " ^ p) :: !errors;
    if Hashtbl.mem seen_folds fold then
      errors := Path_error ("Case-fold collision: " ^ p) :: !errors;
    Hashtbl.add seen_paths p ();
    Hashtbl.add seen_folds fold ()
  ) entries;
  
  if !errors <> [] then Error (List.rev !errors)
  else
    let sorted = List.sort (fun a b ->
      String.compare (Relative_path.to_string a.path) (Relative_path.to_string b.path)
    ) entries in
    let buf = Buffer.create 1024 in
    Buffer.add_string buf "SE-TREE\000V1";
    List.iter (fun entry ->
      let path_str = Relative_path.to_string entry.path in
      Buffer.add_string buf (put_be32 (String.length path_str));
      Buffer.add_string buf path_str;
      let kind_byte = match entry.kind with
        | Regular -> "\001"
        | Executable -> "\002"
        | Symlink -> "\003"
        | Submodule -> "\004"
        | Lfs_pointer -> "\005"
      in
      Buffer.add_string buf kind_byte;
      Buffer.add_string buf (put_be32 entry.mode);
      (* Git OID *)
      (match entry.git_oid with
       | None -> Buffer.add_string buf "\000"
       | Some oid ->
           Buffer.add_string buf "\001";
           let alg_byte = match oid.algorithm with Sha1 -> "\001" | Sha256 -> "\002" in
           Buffer.add_string buf alg_byte;
           Buffer.add_string buf (put_be32 (String.length oid.hex));
           Buffer.add_string buf oid.hex);
      (* Blob SHA-256 *)
      (match entry.blob_sha256 with
       | None -> Buffer.add_string buf "\000"
       | Some sha ->
           Buffer.add_string buf "\001";
           Buffer.add_string buf (Sha256.to_hex sha));
      (* Symlink target *)
      (match entry.symlink_target with
       | None -> Buffer.add_string buf "\000"
       | Some target ->
           Buffer.add_string buf "\001";
           Buffer.add_string buf (put_be32 (String.length target));
           Buffer.add_string buf target)
    ) sorted;
    Ok (Buffer.contents buf)

let run_command cmd =
  let l = Unix.open_process_in cmd in
  let res = ref [] in
  try
    while true do
      res := input_line l :: !res
    done;
    assert false
  with End_of_file ->
    let status = Unix.close_process_in l in
    (status, List.rev !res)

let observe_blob ~path =
  match Sha256.digest_file path with
  | Error e -> Error e
  | Ok sha256 ->
      try
        let byte_count = Core.Int64.to_int_exn (Core.In_channel.with_file path ~f:Core.In_channel.length) in
        Ok (Observed_blob { sha256; byte_count })
      with exn -> Error (Core.Exn.to_string exn)

let parse_git_entry line =
  (* Format of git ls-tree -r HEAD: <mode> <type> <object> \t <file> *)
  try
    let parts = Core.String.split line ~on:' ' in
    match parts with
    | mode_str :: _typ :: oid_str_and_file :: _ ->
        let mode = Core.Int.of_string ("0o" ^ mode_str) in
        let kind = match mode_str with
          | "100644" -> Regular
          | "100755" -> Executable
          | "120000" -> Symlink
          | "160000" -> Submodule
          | _ -> Regular
        in
        let subparts = Core.String.split oid_str_and_file ~on:'\t' in
        (match subparts with
         | oid_hex :: file_path :: _ ->
             let path = match Relative_path.make file_path with Ok p -> p | Error e -> failwith e in
             let git_oid = match Git_oid.of_hex ~algorithm:Sha1 oid_hex with Ok o -> Some o | Error e -> failwith e in
             Some { path; kind; mode; blob_sha256 = None; symlink_target = None; git_oid }
         | _ -> None)
    | _ -> None
  with _ -> None

let observe_git_tree ~root =
  let head_cmd = Printf.sprintf "git -C %s rev-parse HEAD" root in
  let tree_cmd = Printf.sprintf "git -C %s rev-parse HEAD^{tree}" root in
  let ls_cmd = Printf.sprintf "git -C %s ls-tree -r HEAD" root in
  match run_command head_cmd, run_command tree_cmd, run_command ls_cmd with
  | (Unix.WEXITED 0, [commit_hex]), (Unix.WEXITED 0, [tree_hex]), (Unix.WEXITED 0, ls_lines) ->
      let commit = match Git_oid.of_hex ~algorithm:Sha1 (String.trim commit_hex) with Ok o -> o | Error e -> failwith e in
      let tree_oid = match Git_oid.of_hex ~algorithm:Sha1 (String.trim tree_hex) with Ok o -> o | Error e -> failwith e in
      let entries = Core.List.filter_map ls_lines ~f:parse_git_entry in
      (match canonical_tree entries with
       | Error _e -> Error "Failed to compute canonical tree"
       | Ok canonical_str ->
           let canonical_tree_sha256 = Sha256.of_hex (Digestif.SHA256.to_hex (Digestif.SHA256.digest_string canonical_str)) |> (function Ok x -> x | Error e -> failwith e) in
           let entry_count = List.length entries in
           Ok (Observed_git_tree { commit; tree_oid; canonical_tree_sha256; entry_count }))
  | _ -> Error "Git commands failed to execute"

let verify expected observation =
  match expected.pin, observation with
  | Blob_pin e, Observed_blob o ->
      if e.byte_count <> o.byte_count then
        Error [Entry_count_mismatch { expected = e.byte_count; observed = o.byte_count }]
      else if not (Sha256.equal e.sha256 o.sha256) then
        Error [Digest_mismatch { expected = Sha256.to_hex e.sha256; observed = Sha256.to_hex o.sha256 }]
      else Ok { expected; observation }
  | Git_tree_pin e, Observed_git_tree o ->
      if e.entry_count <> o.entry_count then
        Error [Entry_count_mismatch { expected = e.entry_count; observed = o.entry_count }]
      else if not (Sha256.equal e.canonical_tree_sha256 o.canonical_tree_sha256) then
        Error [Digest_mismatch { expected = Sha256.to_hex e.canonical_tree_sha256; observed = Sha256.to_hex o.canonical_tree_sha256 }]
      else Ok { expected; observation }
  | _ -> Error [Type_mismatch "Pin type and observation type mismatch"]

let canonical_receipt receipt =
  let pin_str = match receipt.expected.pin with
    | Blob_pin p -> Printf.sprintf "blob_sha256=%s;bytes=%d" (Sha256.to_hex p.sha256) p.byte_count
    | Git_tree_pin p -> Printf.sprintf "commit=%s;tree=%s;tree_sha256=%s;count=%d"
                          (Git_oid.to_hex p.commit)
                          (Git_oid.to_hex p.tree_oid)
                          (Sha256.to_hex p.canonical_tree_sha256)
                          p.entry_count
  in
  Printf.sprintf "receipt:id=%s;locator=%s;pin=[%s]"
    (Id.to_string receipt.expected.id)
    (Uri.to_string receipt.expected.locator)
    pin_str

let receipt_digest receipt =
  Sha256.of_hex (Digestif.SHA256.to_hex (Digestif.SHA256.digest_string (canonical_receipt receipt))) |> (function Ok x -> x | Error e -> failwith e)