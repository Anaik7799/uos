#use "topfind";;
#require "yojson,cryptokit,mtime.clock.os";;
#load "unix.cma";;

exception Timeout
exception OutputLimit

type run_result = {
  exit_code : int;
  stdout : string;
  stderr : string;
  output : string;
  timed_out : bool;
  output_truncated : bool;
  child_pid : int;
}

let rec make_dir path =
  if not (Sys.file_exists path) then begin
    let parent = Filename.dirname path in
    if parent <> path && not (Sys.file_exists parent) then make_dir parent;
    try Unix.mkdir path 0o755 with Unix.Unix_error (Unix.EEXIST, _, _) -> ()
  end

let verify_dir_no_symlinks dir =
  if String.contains dir '\000' then failwith ("invalid-path:nul-forbidden:" ^ dir);
  let rec check current parts =
    match parts with
    | [] -> ()
    | "" :: rest -> check (if current = "" then "/" else current) rest
    | part :: rest ->
        let next = if current = "" || current = "/" then current ^ part else Filename.concat current part in
        if Sys.file_exists next then begin
          let st =
            try Unix.lstat next
            with Unix.Unix_error (e, _, _) -> failwith ("path-stat-failed:" ^ next ^ ":" ^ Unix.error_message e)
          in
          if st.Unix.st_kind = Unix.S_LNK then
            failwith ("symlink-in-output-dir-forbidden:" ^ next)
        end;
        check next rest
  in
  let parts = String.split_on_char '/' dir in
  check "" parts

let write_exclusive path bytes =
  if String.length bytes = 0 then failwith ("reject-zero-progress-empty-output:" ^ path);
  let parent = Filename.dirname path in
  verify_dir_no_symlinks parent;
  make_dir parent;
  let fd =
    try Unix.openfile path [Unix.O_WRONLY; Unix.O_CREAT; Unix.O_EXCL; Unix.O_CLOEXEC] 0o644
    with Unix.Unix_error (Unix.EEXIST, _, _) -> failwith ("output-collision:" ^ path)
       | Unix.Unix_error (e, _, _) -> failwith ("open-failed:" ^ Unix.error_message e ^ ":" ^ path)
  in
  Fun.protect ~finally:(fun () -> Unix.close fd) (fun () ->
    let raw = Bytes.of_string bytes in
    let len = Bytes.length raw in
    let rec write_all off =
      if off = len then () else
      let n = Unix.write fd raw off (len - off) in
      if n <= 0 then failwith ("write-stalled-zero-bytes:" ^ path);
      write_all (off + n)
    in
    write_all 0)

let sha bytes =
  Cryptokit.hash_string (Cryptokit.Hash.sha256 ()) bytes
  |> Cryptokit.transform_string (Cryptokit.Hexa.encode ())

let run_bounded ?(timeout=60.0) ?(max_bytes=1_048_576) argv =
  let out_r, out_w = Unix.pipe ~cloexec:true () in
  let err_r, err_w = Unix.pipe ~cloexec:true () in
  let start_mono = Mtime_clock.now () in
  let pid = Unix.fork () in
  if pid = 0 then begin
    try
      ignore (Unix.setsid ());
      Unix.close out_r;
      Unix.close err_r;
      Unix.dup2 out_w Unix.stdout;
      Unix.dup2 err_w Unix.stderr;
      Unix.close out_w;
      Unix.close err_w;
      let exe = argv.(0) in
      Unix.execvp exe argv
    with _ -> Unix._exit 127
  end;
  Unix.close out_w;
  Unix.close err_w;
  let child_reaped = ref false in
  let group_stopped = ref false in
  let stop_group () =
    if not !group_stopped then begin
      group_stopped := true;
      (try Unix.kill (-pid) Sys.sigkill with Unix.Unix_error _ -> ());
      if not !child_reaped then
        (try Unix.kill pid Sys.sigkill with Unix.Unix_error _ -> ())
    end
  in
  let reap_child () =
    if !child_reaped then 0
    else begin
      let reap_start = Mtime_clock.now () in
      let rec loop () =
        let elapsed = Mtime.Span.to_float_ns (Mtime.span reap_start (Mtime_clock.now ())) /. 1e9 in
        if elapsed >= 2.0 then 255
        else
          match Unix.waitpid [Unix.WNOHANG] pid with
          | 0, _ ->
              Unix.sleepf 0.002;
              loop ()
          | _, status ->
              child_reaped := true;
              (match status with
               | Unix.WEXITED n -> n
               | Unix.WSIGNALED s -> 128 + s
               | Unix.WSTOPPED s -> 256 + s)
          | exception Unix.Unix_error (Unix.EINTR, _, _) -> loop ()
          | exception Unix.Unix_error (Unix.ECHILD, _, _) ->
              child_reaped := true;
              255
          | exception _ -> 255
      in
      loop ()
    end
  in
  let out_buf = Buffer.create (min max_bytes 4096) in
  let err_buf = Buffer.create (min max_bytes 4096) in
  let temp_bytes = Bytes.create 4096 in
  let out_open = ref true in
  let err_open = ref true in
  let out_truncated = ref false in
  try
    let rec read_pump () =
      let now_mono = Mtime_clock.now () in
      let elapsed = Mtime.Span.to_float_ns (Mtime.span start_mono now_mono) /. 1e9 in
      if elapsed >= timeout then raise Timeout;
      if not !out_open && not !err_open then ()
      else begin
        let remaining = timeout -. elapsed in
        let readers = (if !out_open then [out_r] else []) @ (if !err_open then [err_r] else []) in
        let readable, _, _ =
          try Unix.select readers [] [] (min remaining 0.05)
          with Unix.Unix_error (Unix.EINTR, _, _) -> ([], [], [])
        in
        List.iter (fun fd ->
          if fd = out_r && !out_open then begin
            let n = Unix.read out_r temp_bytes 0 (Bytes.length temp_bytes) in
            if n = 0 then (Unix.close out_r; out_open := false)
            else begin
              let cur_len = Buffer.length out_buf in
              if cur_len + n > max_bytes then begin
                let allowed = max 0 (max_bytes - cur_len) in
                if allowed > 0 then Buffer.add_subbytes out_buf temp_bytes 0 allowed;
                out_truncated := true;
                raise OutputLimit
              end else
                Buffer.add_subbytes out_buf temp_bytes 0 n
            end
          end else if fd = err_r && !err_open then begin
            let n = Unix.read err_r temp_bytes 0 (Bytes.length temp_bytes) in
            if n = 0 then (Unix.close err_r; err_open := false)
            else begin
              let cur_len = Buffer.length err_buf in
              if cur_len + n > max_bytes then begin
                let allowed = max 0 (max_bytes - cur_len) in
                if allowed > 0 then Buffer.add_subbytes err_buf temp_bytes 0 allowed;
                out_truncated := true;
                raise OutputLimit
              end else
                Buffer.add_subbytes err_buf temp_bytes 0 n
            end
          end
        ) readable;
        read_pump ()
      end
    in
    read_pump ();
    if !out_open then (try Unix.close out_r with Unix.Unix_error _ -> ());
    if !err_open then (try Unix.close err_r with Unix.Unix_error _ -> ());
    let rec wait_child_exit () =
      let now_mono = Mtime_clock.now () in
      let elapsed = Mtime.Span.to_float_ns (Mtime.span start_mono now_mono) /. 1e9 in
      if elapsed >= timeout then raise Timeout;
      match Unix.waitpid [Unix.WNOHANG] pid with
      | 0, _ ->
          Unix.sleepf 0.002;
          wait_child_exit ()
      | _, status ->
          child_reaped := true;
          let code = match status with
            | Unix.WEXITED n -> n
            | Unix.WSIGNALED s -> 128 + s
            | Unix.WSTOPPED s -> 256 + s
          in
          code
      | exception Unix.Unix_error (Unix.EINTR, _, _) -> wait_child_exit ()
      | exception Unix.Unix_error (Unix.ECHILD, _, _) ->
          failwith ("child-process-wait-failed:ECHILD:" ^ string_of_int pid)
    in
    let exit_code = wait_child_exit () in
    stop_group ();
    let s_out = Buffer.contents out_buf in
    let s_err = Buffer.contents err_buf in
    let output = if s_err = "" then s_out else if s_out = "" then s_err else s_out ^ "\n" ^ s_err in
    { exit_code; stdout = s_out; stderr = s_err; output; timed_out = false; output_truncated = false; child_pid = pid }
  with
  | Timeout ->
      stop_group ();
      let _ = reap_child () in
      if !out_open then (try Unix.close out_r with Unix.Unix_error _ -> ());
      if !err_open then (try Unix.close err_r with Unix.Unix_error _ -> ());
      let s_out = Buffer.contents out_buf in
      let s_err = Buffer.contents err_buf in
      let output = if s_err = "" then s_out else if s_out = "" then s_err else s_out ^ "\n" ^ s_err in
      { exit_code = 124; stdout = s_out; stderr = s_err; output; timed_out = true; output_truncated = false; child_pid = pid }
  | OutputLimit ->
      stop_group ();
      let _ = reap_child () in
      if !out_open then (try Unix.close out_r with Unix.Unix_error _ -> ());
      if !err_open then (try Unix.close err_r with Unix.Unix_error _ -> ());
      let s_out = Buffer.contents out_buf in
      let s_err = Buffer.contents err_buf in
      let output = if s_err = "" then s_out else if s_out = "" then s_err else s_out ^ "\n" ^ s_err in
      { exit_code = 125; stdout = s_out; stderr = s_err; output; timed_out = false; output_truncated = true; child_pid = pid }
  | exn ->
      stop_group ();
      let _ = reap_child () in
      if !out_open then (try Unix.close out_r with Unix.Unix_error _ -> ());
      if !err_open then (try Unix.close err_r with Unix.Unix_error _ -> ());
      raise exn


let field name = function `Assoc xs -> List.assoc_opt name xs | _ -> None
let str n j = match field n j with Some (`String x) -> Some x | _ -> None
let int n j = match field n j with Some (`Int x) -> Some x | _ -> None

let structured ~schema ~status ~cases (res : run_result) =
  match res.exit_code with
  | 0 ->
      (try
         let j = Yojson.Safe.from_string res.stdout in
         str "schema" j = Some schema && str "status" j = Some status && int "cases" j = Some cases
       with Yojson.Json_error _ -> false)
  | _ -> false

let mapping_hold (res : run_result) =
  match res.exit_code with
  | 1 ->
      (try
         let j = Yojson.Safe.from_string res.stdout in
         str "schema" j = Some "uos.ev02-directive-mapping/v1" &&
         str "status" j = Some "HOLD" &&
         (match field "rule_rows" j with
          | Some (`List x) -> List.length x = 38
          | _ -> false)
       with Yojson.Json_error _ -> false)
  | _ -> false


let rec lowercase_hex s i =
  if i = String.length s then true
  else match s.[i] with '0'..'9' | 'a'..'f' -> lowercase_hex s (i + 1) | _ -> false

let superset_rel = "governance/agents/policy/superset.toml"
let amendment_rel = "governance/agents/policy/20260909-1836-ev02-current-directive-rule-amendment.json"
let source_paths = [
  "tools/ev02_governance/run_checks.ml";
  "tools/ev02_governance/directive_mapping_gate.ml";
  "tools/ev02_governance/policy_surface_gate.ml";
  "governance/agents/policy/20260909-1836-ev02-current-directive-rule-amendment.json"
]
let max_staged_inputs = 258
let max_staged_bytes = 16_777_216

let regular stat = stat.Unix.st_kind = Unix.S_REG
let same_file a b = a.Unix.st_dev = b.Unix.st_dev && a.Unix.st_ino = b.Unix.st_ino
let same_stat a b =
  same_file a b &&
  a.Unix.st_size = b.Unix.st_size &&
  a.Unix.st_mtime = b.Unix.st_mtime &&
  a.Unix.st_ctime = b.Unix.st_ctime

let read_regular ~max_bytes path =
  let listed = try Unix.lstat path with Unix.Unix_error (e, _, _) -> failwith ("missing-or-unreadable:" ^ path ^ ":" ^ Unix.error_message e) in
  if listed.Unix.st_kind = Unix.S_LNK then failwith ("symlink-forbidden:" ^ path);
  if not (regular listed) then failwith ("not-regular:" ^ path);
  if listed.Unix.st_size < 0 || listed.Unix.st_size > max_bytes then failwith ("file-size-exceeded:" ^ path);
  let fd = try Unix.openfile path [Unix.O_RDONLY; Unix.O_NONBLOCK; Unix.O_CLOEXEC] 0
    with Unix.Unix_error (e, _, _) -> failwith ("open-refused:" ^ path ^ ":" ^ Unix.error_message e) in
  Fun.protect ~finally:(fun () -> Unix.close fd) (fun () ->
    let opened = Unix.fstat fd in
    if not (regular opened) || not (same_stat listed opened) then
      failwith ("file-identity-changed-at-open:" ^ path);
    let bytes = Bytes.create opened.Unix.st_size in
    let rec read_at offset =
      if offset = Bytes.length bytes then () else
      let read = Unix.read fd bytes offset (Bytes.length bytes - offset) in
      if read <= 0 then failwith ("short-read:" ^ path) else read_at (offset + read)
    in
    read_at 0;
    let closed = Unix.fstat fd in
    if not (regular closed) || not (same_stat opened closed) then
      failwith ("file-mutated-during-read:" ^ path);
    let final_listed = try Unix.lstat path with Unix.Unix_error (e, _, _) -> failwith ("final-stat-failed:" ^ path ^ ":" ^ Unix.error_message e) in
    if final_listed.Unix.st_kind = Unix.S_LNK then failwith ("final-symlink-forbidden:" ^ path);
    if not (regular final_listed) || not (same_stat opened final_listed) then
      failwith ("path-substituted-or-mutated:" ^ path);
    Bytes.to_string bytes)

let read_bounded_file path max_len = read_regular ~max_bytes:max_len path

let candidate_query ~workspace ~jj revision build =
  let selector = "commit_id(\"" ^ revision ^ "\")" in
  let argv = Array.of_list ([jj; "--ignore-working-copy"; "--no-pager"; "--color"; "never"; "-R"; workspace] @ build selector) in
  let c = run_bounded ~timeout:10. argv in
  match c.exit_code with
  | 0 -> c.stdout
  | _ -> failwith ("candidate-query-unavailable:" ^ revision)

let candidate_bytes ~workspace ~jj revision path =
  candidate_query ~workspace ~jj revision (fun selector -> ["file"; "show"; "-r"; selector; "-T"; ""; "--"; "root:" ^ path])

let candidate_kind ~workspace ~jj revision path =
  let listing = candidate_query ~workspace ~jj revision (fun selector ->
    ["file"; "list"; "-r"; selector; "-T"; "file_type ++ \" \" ++ path ++ \"\\n\""; "--"; "root:" ^ path]) in
  let prefix = match String.index_opt listing ' ' with Some at -> String.sub listing 0 at | None -> "" in
  if not (listing = prefix ^ " " ^ path ^ "\n" && List.mem prefix ["file"; "symlink"; "absent"]) then
    failwith ("candidate-invalid-kind:" ^ path);
  prefix

let bind_candidate ~workspace ~jj revision =
  if String.length revision <> 40 || not (lowercase_hex revision 0) then
    failwith "immutable-candidate-required";
  List.map (fun path ->
    let local = read_bounded_file (Filename.concat workspace path) 1_048_576 in
    let candidate = candidate_bytes ~workspace ~jj revision path in
    if local <> candidate then failwith ("workspace-bytes-differ:" ^ path);
    `Assoc [
      "path", `String path;
      "sha256", `String (sha local);
      "bytes", `Int (String.length local)
    ]) source_paths

let valid_rule_file file =
  file = Filename.basename file && Filename.check_suffix file ".md" && file <> "." && file <> ".." &&
  not (String.contains file '/') && not (String.contains file '\\') && String.length file <= 255

let amendment_files bytes =
  let json = try Yojson.Safe.from_string bytes with Yojson.Json_error _ -> failwith "candidate-amendment-json" in
  match json with
  | `Assoc fields ->
      begin match List.assoc_opt "rules" fields with
      | Some (`List rows) ->
          let files = rows |> List.map (function
            | `List [`String _; `String file; `String _] when valid_rule_file file -> file
            | _ -> failwith "candidate-amendment-rule-shape") |> List.sort_uniq String.compare in
          if files = [] || List.length files > 64 then failwith "candidate-rule-file-bound";
          files
      | _ -> failwith "candidate-amendment-rules"
      end
  | _ -> failwith "candidate-amendment-root"

let candidate_surface_paths ~workspace ~jj revision surface =
  let listing = candidate_query ~workspace ~jj revision (fun selector ->
    ["file"; "list"; "-r"; selector; "-T"; "path ++ \"\\n\""; "--"; "root:" ^ surface]) in
  let prefix = surface ^ "/" in
  let paths = String.split_on_char '\n' listing |> List.filter (fun path -> path <> "") in
  if List.length paths > 64 || List.length paths <> List.length (List.sort_uniq String.compare paths) then
    failwith "candidate-surface-entry-bound";
  List.iter (fun path ->
    if not (String.starts_with ~prefix path &&
      valid_rule_file (String.sub path (String.length prefix) (String.length path - String.length prefix))) then
      failwith ("candidate-surface-path:" ^ path)) paths;
  paths

type staged_manifest = {
  sealed_files : (string * string) list;
  required_absences : string list;
  expected_dirs : string list;
}

let rec directory_ancestors rel =
  let parent = Filename.dirname rel in
  if parent = "." || parent = "/" || parent = "" then []
  else parent :: directory_ancestors parent

let scan_staged_inventory ~expected_dirs root =
  let total_scanned = ref 0 in
  let max_total_entries = 10_000 in
  let files = ref [] in
  let dirs = ref [] in
  let rec scan depth rel_dir =
    if depth > 8 then failwith ("staged-inventory-depth-exceeded:" ^ rel_dir);
    let abs_dir = if rel_dir = "" then root else Filename.concat root rel_dir in
    let d = Unix.opendir abs_dir in
    let entries = ref [] in
    let rec read_entries () =
      incr total_scanned;
      if !total_scanned > max_total_entries then
        failwith ("staged-inventory-total-entry-limit-exceeded:" ^ string_of_int !total_scanned);
      match Unix.readdir d with
      | "." | ".." -> read_entries ()
      | entry -> entries := entry :: !entries; read_entries ()
      | exception End_of_file -> ()
    in
    Fun.protect ~finally:(fun () -> Unix.closedir d) (fun () -> read_entries ());
    List.iter (fun entry ->
      let rel_path = if rel_dir = "" then entry else Filename.concat rel_dir entry in
      let abs_path = Filename.concat root rel_path in
      let st =
        try Unix.lstat abs_path
        with Unix.Unix_error (e, _, _) -> failwith ("staged-stat-failed:" ^ rel_path ^ ":" ^ Unix.error_message e)
      in
      match st.Unix.st_kind with
      | Unix.S_LNK -> failwith ("staged-symlink-forbidden:" ^ rel_path)
      | Unix.S_REG -> files := rel_path :: !files
      | Unix.S_DIR ->
          if not (List.mem rel_path expected_dirs) then
            failwith ("staged-unexpected-dir:" ^ rel_path);
          dirs := rel_path :: !dirs;
          scan (depth + 1) rel_path
      | _ -> failwith ("staged-unsupported-kind:" ^ rel_path)
    ) (List.sort String.compare !entries)
  in
  scan 0 "";
  List.sort String.compare !files, List.sort String.compare !dirs

let remove_owned_tree path =
  if not (String.starts_with ~prefix:"/tmp/ev02-candidate-stage-" path) then
    failwith ("remove_owned_tree: refused unsafe non-staging path: " ^ path);
  if String.contains path '\000' || List.mem ".." (String.split_on_char '/' path) then
    failwith ("remove_owned_tree: path traversal forbidden: " ^ path);
  let total_entries = ref 0 in
  let max_entries = 10_000 in
  let rec rm depth dir =
    if depth > 8 then failwith ("remove_owned_tree: depth exceeded at " ^ dir);
    let st = Unix.lstat dir in
    if st.Unix.st_kind = Unix.S_LNK then
      failwith ("remove_owned_tree: symlink forbidden at " ^ dir)
    else if st.Unix.st_kind = Unix.S_DIR then begin
      let d = Unix.opendir dir in
      let entries = ref [] in
      let rec read_entries () =
        incr total_entries;
        if !total_entries > max_entries then
          failwith ("remove_owned_tree: total entry limit exceeded at " ^ dir);
        match Unix.readdir d with
        | "." | ".." -> read_entries ()
        | entry -> entries := entry :: !entries; read_entries ()
        | exception End_of_file -> ()
      in
      Fun.protect ~finally:(fun () -> Unix.closedir d) (fun () -> read_entries ());
      List.iter (fun entry ->
        let child = Filename.concat dir entry in
        rm (depth + 1) child
      ) (List.sort String.compare !entries);
      Unix.rmdir dir
    end else begin
      Unix.unlink dir
    end
  in
  if Sys.file_exists path then rm 0 path

let rec mkdirs path =
  if Sys.file_exists path then ()
  else (mkdirs (Filename.dirname path); try Unix.mkdir path 0o700 with Unix.Unix_error (Unix.EEXIST, _, _) -> ())

let private_stage () =
  let reservation = Filename.temp_file "ev02-candidate-stage-" ".reserve" in
  (try Sys.remove reservation with _ -> ());
  let root = reservation ^ ".d" in
  Unix.mkdir root 0o700;
  root

let stage_write root rel bytes =
  let target = Filename.concat root rel in
  mkdirs (Filename.dirname target);
  let fd = Unix.openfile target [Unix.O_WRONLY; Unix.O_CREAT; Unix.O_EXCL; Unix.O_CLOEXEC] 0o600 in
  let channel = Unix.out_channel_of_descr fd in
  Fun.protect ~finally:(fun () -> close_out_noerr channel) (fun () -> output_string channel bytes; flush channel)

let staged_bytes root rel expected =
  let path = Filename.concat root rel in
  let bytes = read_regular ~max_bytes:(String.length expected) path in
  if bytes <> expected then failwith ("staged-tamper:" ^ rel)

let stage_inputs ~workspace ~jj revision =
  let root = private_stage () in
  try
    let total = ref 0 in
    let sealed = ref [] in
    let required_absences = ref [] in
    let amendment = candidate_bytes ~workspace ~jj revision amendment_rel in
    let files = amendment_files amendment in
    let surfaces = [".agents/rules"; ".claude/rules"; ".gemini/rules"; ".codex/rules"] in
    let all_surface_paths = List.concat_map (candidate_surface_paths ~workspace ~jj revision) surfaces in
    List.iter (fun file ->
      List.iter (fun surface ->
        if not (List.mem (surface ^ "/" ^ file) all_surface_paths) then
          failwith ("candidate-mapped-file-missing:" ^ file))
        surfaces) files;
    List.iter (fun surface -> mkdirs (Filename.concat root surface)) surfaces;
    let rels = superset_rel :: amendment_rel :: all_surface_paths in
    if List.length rels > max_staged_inputs then failwith "candidate-input-count";
    let bindings = List.map (fun rel ->
      let kind = candidate_kind ~workspace ~jj revision rel in
      if kind = "file" then begin
        let bytes = candidate_bytes ~workspace ~jj revision rel in
        if !total + String.length bytes > max_staged_bytes then failwith "candidate-input-byte-quota";
        total := !total + String.length bytes;
        stage_write root rel bytes;
        sealed := (rel, bytes) :: !sealed;
        `Assoc [
          "path", `String rel;
          "candidate_kind", `String kind;
          "sha256", `String (sha bytes);
          "bytes", `Int (String.length bytes)
        ]
      end else begin
        required_absences := rel :: !required_absences;
        `Assoc [
          "path", `String rel;
          "candidate_kind", `String kind;
          "status", `String "UNSTAGED_HOLD"
        ]
      end) rels in
    let sealed_files = List.rev !sealed in
    let expected_dirs =
      let from_files = List.concat_map (fun (rel, _) -> directory_ancestors rel) sealed_files in
      let from_surfaces = List.concat_map directory_ancestors (List.map (fun s -> s ^ "/placeholder") surfaces) in
      (from_files @ from_surfaces) |> List.sort_uniq String.compare
    in
    let manifest = {
      sealed_files;
      required_absences = List.sort_uniq String.compare !required_absences;
      expected_dirs;
    } in
    root, Filename.concat root amendment_rel, bindings, manifest
  with exn ->
    (try remove_owned_tree root with _ -> ());
    raise exn

let verify_staged_manifest root manifest =
  (* 1. Check required absences *)
  List.iter (fun rel ->
    let abs_path = Filename.concat root rel in
    if Sys.file_exists abs_path then
      failwith ("staged-required-absence-present:" ^ rel)
  ) manifest.required_absences;
  (* 2. Verify all sealed files exist and match exact bytes *)
  List.iter (fun (rel, bytes) -> staged_bytes root rel bytes) manifest.sealed_files;
  (* 3. Scan disk inventory and verify no extraneous files or directories exist *)
  let disk_files, disk_dirs = scan_staged_inventory ~expected_dirs:manifest.expected_dirs root in
  let expected_files = List.map fst manifest.sealed_files |> List.sort String.compare in
  List.iter (fun f ->
    if not (List.mem f expected_files) then
      failwith ("staged-unexpected-file:" ^ f)
  ) disk_files;
  List.iter (fun f ->
    if not (List.mem f disk_files) then
      failwith ("staged-missing-file:" ^ f)
  ) expected_files;
  List.iter (fun d ->
    if not (List.mem d manifest.expected_dirs) then
      failwith ("staged-unexpected-dir:" ^ d)
  ) disk_dirs

type check = {
  id : string;
  expected_code : int;
  validate : (run_result -> bool) option;
  argv : string array;
}

let run_one ~out_dir ~timestamp check =
  let res = run_bounded check.argv in
  let output_filename = Printf.sprintf "%sev02-%s.out" timestamp check.id in
  let output_path = Filename.concat out_dir output_filename in
  let stdout_filename = Printf.sprintf "%sev02-%s.stdout" timestamp check.id in
  let stdout_path = Filename.concat out_dir stdout_filename in
  let stderr_filename = Printf.sprintf "%sev02-%s.stderr" timestamp check.id in
  let stderr_path = Filename.concat out_dir stderr_filename in
  let raw_empty = (res.output = "") in
  let stored_output = if raw_empty then "(no output)\n" else res.output in
  write_exclusive output_path stored_output;
  let stored_stdout = if res.stdout = "" then "(no output)\n" else res.stdout in
  write_exclusive stdout_path stored_stdout;
  let stored_stderr = if res.stderr = "" then "(no output)\n" else res.stderr in
  write_exclusive stderr_path stored_stderr;
  let code_pass = (res.exit_code = check.expected_code) in
  let validate_pass = match check.validate with Some v -> v res | None -> true in
  let control_pass = code_pass && validate_pass in
  `Assoc [
    "id", `String check.id;
    "argv", `List (Array.to_list check.argv |> List.map (fun s -> `String s));
    "exit_code", `Int res.exit_code;
    "expected_exit_code", `Int check.expected_code;
    "control_pass", `Bool control_pass;
    "timed_out", `Bool res.timed_out;
    "output_truncated", `Bool res.output_truncated;
    "raw_empty", `Bool raw_empty;
    "output_path", `String output_path;
    "output_sha256", `String (sha stored_output);
    "stdout_path", `String stdout_path;
    "stdout_sha256", `String (sha stored_stdout);
    "stderr_path", `String stderr_path;
    "stderr_sha256", `String (sha stored_stderr);
    "valid", `Bool control_pass
  ], control_pass


let execute_checks ~workspace ~out_dir ~timestamp ~source_commit ?(candidate_bindings=[]) ?(staged_bindings=[]) ?post_seal checks =
  if String.contains out_dir '\000' || String.contains timestamp '/' || String.contains timestamp '\\' then
    failwith "execute_checks: path-escape-forbidden-in-out-dir-or-timestamp";
  if checks = [] then failwith "execute_checks: reject-zero-progress-empty-checks";
  let rows = ref [] in
  let all_pass = ref true in
  List.iter (fun c ->
    let row, pass = run_one ~out_dir ~timestamp c in
    rows := row :: !rows;
    if not pass then all_pass := false
  ) checks;
  let rows = List.rev !rows in
  let checks_pass = !all_pass in
  let post_seal_pass = ref None in
  let post_seal_error = ref None in
  (match post_seal with
   | Some verify_fn ->
       begin try
         verify_fn ();
         post_seal_pass := Some true
       with exn ->
         post_seal_pass := Some false;
         post_seal_error := Some (Printexc.to_string exn)
       end
   | None -> ());
  let post_seal_ok = match !post_seal_pass with
    | Some b -> b
    | None -> true
  in
  let overall_pass = checks_pass && post_seal_ok in
  let doc =
    `Assoc [
      "schema", `String "uos.ev02-governance-checks/v1";
      "authority", `String "REPORT_ONLY";
      "admission", `String "NOT_GRANTED";
      "source_commit", `String source_commit;
      "candidate_bindings", `List candidate_bindings;
      "staged_bindings", `List staged_bindings;
      "checks_pass", `Bool checks_pass;
      "post_seal_pass", (match !post_seal_pass with Some b -> `Bool b | None -> `Null);
      "post_seal_error", (match !post_seal_error with Some err -> `String err | None -> `Null);
      "all_control_pass", `Bool overall_pass;
      "rows", `List rows
    ] |> Yojson.Safe.pretty_to_string
  in
  let summary_file = Printf.sprintf "%sev02-governance-checks.json" timestamp in
  let summary_path = Filename.concat out_dir summary_file in
  write_exclusive summary_path (doc ^ "\n");
  overall_pass

let validate_timestamp ts =
  if String.length ts <> 14 then false
  else if ts.[8] <> '-' || ts.[13] <> '-' then false
  else
    let is_digit c = c >= '0' && c <= '9' in
    let digits = [0;1;2;3;4;5;6;7;9;10;11;12] in
    List.for_all (fun i -> is_digit ts.[i]) digits

let expect_failure label expected_prefix thunk =
  let err =
    try ignore (thunk ()); None
    with
    | Failure msg -> Some msg
    | exn -> Some (Printexc.to_string exn)
  in
  match err with
  | None -> failwith ("selftest accepted invalid input (expected failure): " ^ label)
  | Some msg ->
      if not (String.starts_with ~prefix:expected_prefix msg) then
        failwith (Printf.sprintf "selftest %s failed with unexpected message: %s (expected prefix %s)" label msg expected_prefix)

let selftest () =
  (* Outer bounded guard: overall selftest cannot run more than 10 seconds.
     Since run_bounded uses Mtime_clock and no signal handlers, this outer timer is never disturbed. *)
  let outer_alarm = Sys.signal Sys.sigalrm (Sys.Signal_handle (fun _ -> failwith "selftest aborted by outer timeout guard")) in
  ignore (Unix.setitimer Unix.ITIMER_REAL { Unix.it_interval = 0.; it_value = 10.0 });
  Fun.protect ~finally:(fun () ->
    ignore (Unix.setitimer Unix.ITIMER_REAL { Unix.it_interval = 0.; it_value = 0. });
    Sys.set_signal Sys.sigalrm outer_alarm;
  ) (fun () ->
    (* 1. Basic command success *)
    let s_res = run_bounded ~timeout:2.0 [|"sh"; "-c"; "echo -n 'hello'"|] in
    if s_res.exit_code <> 0 || s_res.output <> "hello" || s_res.timed_out then
      failwith "selftest failed: basic command";

    (* 2. Command timeout test *)
    let t_res = run_bounded ~timeout:0.05 [|"sleep"; "5"|] in
    if not t_res.timed_out || t_res.exit_code <> 124 then
      failwith (Printf.sprintf "selftest failed: timeout not detected (code %d)" t_res.exit_code);

    (* 3. Adversarial child closes output and sleeps *)
    let c_res = run_bounded ~timeout:0.05 [|"sh"; "-c"; "exec 1>&-; exec 2>&-; sleep 5"|] in
    if not c_res.timed_out || c_res.exit_code <> 124 then
      failwith (Printf.sprintf "selftest failed: child closes output and sleeps (code %d)" c_res.exit_code);

    (* 4. Adversarial descendant holds pipe *)
    let d_res = run_bounded ~timeout:0.05 [|"sh"; "-c"; "(sleep 5 &); sleep 0.001"|] in
    if not d_res.timed_out || d_res.exit_code <> 124 then
      failwith (Printf.sprintf "selftest failed: descendant holds pipe (code %d)" d_res.exit_code);

    (* 5. Output flood test *)
    let b_res = run_bounded ~timeout:1.0 ~max_bytes:500 [|"sh"; "-c"; "while true; do echo -n '1234567890'; done"|] in
    if not b_res.output_truncated || b_res.exit_code <> 125 || String.length b_res.output <> 500 then
      failwith (Printf.sprintf "selftest failed: output flood (code %d, len %d, trunc %b)"
        b_res.exit_code (String.length b_res.output) b_res.output_truncated);

    (* 6. Chunked read test *)
    let k_res = run_bounded ~timeout:2.0 ~max_bytes:200_000 [|"sh"; "-c"; "printf '%0100000d' 0"|] in
    if k_res.timed_out || k_res.output_truncated || k_res.exit_code <> 0 || String.length k_res.output <> 100_000 then
      failwith (Printf.sprintf "selftest failed: chunked read (code %d, len %d)" k_res.exit_code (String.length k_res.output));

    (* 7. Child reap test: verify child process is fully reaped in both timeout and normal exit *)
    let reap_test_timeout =
      match Unix.waitpid [Unix.WNOHANG] t_res.child_pid with
      | exception Unix.Unix_error (Unix.ECHILD, _, _) -> true
      | _ -> false
    in
    if not reap_test_timeout then failwith "selftest failed: timeout child PID was not fully reaped";
    let reap_test_normal =
      match Unix.waitpid [Unix.WNOHANG] s_res.child_pid with
      | exception Unix.Unix_error (Unix.ECHILD, _, _) -> true
      | _ -> false
    in
    if not reap_test_normal then failwith "selftest failed: normal child PID was not fully reaped";

    (* 8. Negative observation: process group cleanup kills grandchild process *)
    let g_res = run_bounded ~timeout:0.05 [|"sh"; "-c"; "sleep 30 & echo $!; wait"|] in
    if not g_res.timed_out || g_res.exit_code <> 124 then
      failwith "selftest failed: process group test did not time out";
    let gc_pid_str = String.trim g_res.output in
    let gc_pid = try int_of_string gc_pid_str with _ -> failwith ("failed to parse grandchild pid: " ^ gc_pid_str) in
    let rec check_gc_reaped tries =
      try
        Unix.kill gc_pid 0;
        if tries <= 0 then failwith "selftest failed: grandchild process survived process group kill"
        else (Unix.sleepf 0.02; check_gc_reaped (tries - 1))
      with Unix.Unix_error (Unix.ESRCH, _, _) -> ()
    in
    check_gc_reaped 50;

    (* 9. Output collision, zero-progress, and symlink output-dir tests *)
    let tmp_dir = Filename.temp_file "ev02-coll-" "" in
    Sys.remove tmp_dir;
    make_dir tmp_dir;
    let test_file = Filename.concat tmp_dir "test.out" in
    write_exclusive test_file "initial content";
    expect_failure "collision" "output-collision:" (fun () ->
      write_exclusive test_file "overwrite attempt");
    expect_failure "zero-progress" "reject-zero-progress-empty-output:" (fun () ->
      write_exclusive (Filename.concat tmp_dir "empty.out") "");

    (* Symlink in output dir ancestor rejected *)
    let real_out = Filename.concat tmp_dir "real_out" in
    make_dir real_out;
    let sym_out = Filename.concat tmp_dir "sym_out" in
    Unix.symlink real_out sym_out;
    expect_failure "symlink-out-dir" "symlink-in-output-dir-forbidden:" (fun () ->
      write_exclusive (Filename.concat sym_out "file.out") "hello");

    (* 10. Control failure exit propagation *)
    let run_dir = Filename.concat tmp_dir "checks_test" in
    make_dir run_dir;
    let fail_check = { id = "should-fail"; expected_code = 0; validate = None; argv = [|"sh"; "-c"; "exit 42"|] } in
    let pass_check = { id = "should-pass"; expected_code = 0; validate = None; argv = [|"sh"; "-c"; "exit 0"|] } in
    let result_failed = execute_checks ~workspace:tmp_dir ~out_dir:run_dir ~timestamp:"20260930-1115-" ~source_commit:"c1" [fail_check] in
    if result_failed <> false then failwith "selftest failed: execute_checks returned true on failing control";
    let result_passed = execute_checks ~workspace:tmp_dir ~out_dir:run_dir ~timestamp:"20260930-1116-" ~source_commit:"c2" [pass_check] in
    if result_passed <> true then failwith "selftest failed: execute_checks returned false on passing control";

    (* 11. Stored-output digest alignment control for silent and nonempty commands *)
    let digest_dir = Filename.concat tmp_dir "digest_verify" in
    make_dir digest_dir;
    let silent_check = { id = "silent-cmd"; expected_code = 0; validate = None; argv = [|"sh"; "-c"; "exit 0"|] } in
    let nonempty_check = { id = "nonempty-cmd"; expected_code = 0; validate = None; argv = [|"sh"; "-c"; "echo hello-digest-verify"|] } in
    let digest_checks_ok = execute_checks ~workspace:tmp_dir ~out_dir:digest_dir ~timestamp:"20260930-1120-" ~source_commit:"c3" [silent_check; nonempty_check] in
    if not digest_checks_ok then failwith "selftest failed: digest verify checks failed";
    let summary_json_path = Filename.concat digest_dir "20260930-1120-ev02-governance-checks.json" in
    let summary_json = Yojson.Safe.from_file summary_json_path in
    let open Yojson.Safe.Util in
    let rows = summary_json |> member "rows" |> to_list in
    if List.length rows <> 2 then failwith "selftest failed: expected 2 rows in digest verify summary";
    List.iter (fun row ->
      let id = row |> member "id" |> to_string in
      let path = row |> member "output_path" |> to_string in
      let expected_sha = row |> member "output_sha256" |> to_string in
      let raw_empty = row |> member "raw_empty" |> to_bool in
      let ch = open_in_bin path in
      let len = in_channel_length ch in
      let disk_bytes = really_input_string ch len in
      close_in ch;
      let actual_sha = sha disk_bytes in
      if actual_sha <> expected_sha then
        failwith (Printf.sprintf "selftest failed: digest mismatch for %s: summary=%s actual=%s" id expected_sha actual_sha);
      if id = "silent-cmd" then begin
        if not raw_empty then failwith "selftest failed: silent-cmd was not raw_empty";
        if disk_bytes <> "(no output)\n" then failwith "selftest failed: silent-cmd stored bytes != '(no output)\\n'"
      end else if id = "nonempty-cmd" then begin
        if raw_empty then failwith "selftest failed: nonempty-cmd was raw_empty";
        if disk_bytes <> "hello-digest-verify\n" then failwith "selftest failed: nonempty-cmd stored bytes mismatch"
      end
    ) rows;

    (* 12. Timestamp validation *)
    if not (validate_timestamp "20260930-1115-") then failwith "selftest failed: valid timestamp rejected";
    if validate_timestamp "bad-timestamp" then failwith "selftest failed: bad timestamp accepted";
    if validate_timestamp "" then failwith "selftest failed: empty timestamp accepted";

    (* 13. Staging seal, directory inventory, required absence, and tamper refusal *)
    let staged_root = private_stage () in
    let staged_rel = "governance/agents/policy/superset.toml" in
    let staged_val = "[[directive]]\nid = \"DIR-X\"\n" in
    stage_write staged_root staged_rel staged_val;
    let test_manifest = {
      sealed_files = [staged_rel, staged_val];
      required_absences = ["docs/design/absent.json"];
      expected_dirs = ["governance"; "governance/agents"; "governance/agents/policy"];
    } in
    verify_staged_manifest staged_root test_manifest;

    (* 13a. Extra file tampering refused *)
    let extra_file = Filename.concat staged_root "governance/agents/policy/extra.toml" in
    let ch = open_out_bin extra_file in output_string ch "extra"; close_out ch;
    expect_failure "extra-file" "staged-unexpected-file:" (fun () ->
      verify_staged_manifest staged_root test_manifest);
    Sys.remove extra_file;

    (* 13b. Required absence violation refused *)
    let absent_file = Filename.concat staged_root "docs/design/absent.json" in
    mkdirs (Filename.dirname absent_file);
    let ch = open_out_bin absent_file in output_string ch "should not exist"; close_out ch;
    expect_failure "required-absence" "staged-required-absence-present:" (fun () ->
      verify_staged_manifest staged_root test_manifest);
    Sys.remove absent_file;
    Unix.rmdir (Filename.concat staged_root "docs/design");
    Unix.rmdir (Filename.concat staged_root "docs");

    (* 13c. Content tampering refused *)
    let ch = open_out_bin (Filename.concat staged_root staged_rel) in
    output_string ch "tampered"; close_out ch;
    expect_failure "tamper-content" "staged-tamper:" (fun () ->
      verify_staged_manifest staged_root test_manifest);
    remove_owned_tree staged_root;

    (* 13d. Bounded remove_owned_tree verification *)
    let tree_to_remove = private_stage () in
    stage_write tree_to_remove "sub/dir/test.txt" "hello";
    remove_owned_tree tree_to_remove;
    if Sys.file_exists tree_to_remove then failwith "selftest failed: remove_owned_tree failed to remove directory";
    expect_failure "unsafe-remove" "remove_owned_tree: refused unsafe" (fun () ->
      remove_owned_tree "/tmp/other_path");

    (* 13e. execute_checks post-seal failure creates failed receipt and returns false *)
    let post_seal_test_dir = Filename.concat tmp_dir "post_seal_test" in
    make_dir post_seal_test_dir;
    let post_pass_check = { id = "pass-cmd"; expected_code = 0; validate = None; argv = [|"sh"; "-c"; "exit 0"|] } in
    let post_fail () = failwith "post-seal-simulated-tamper" in
    let post_result = execute_checks ~workspace:tmp_dir ~out_dir:post_seal_test_dir ~timestamp:"20260930-1130-" ~source_commit:"c4" ~post_seal:post_fail [post_pass_check] in
    if post_result <> false then failwith "selftest failed: execute_checks returned true when post_seal failed";
    let post_summary_json = Filename.concat post_seal_test_dir "20260930-1130-ev02-governance-checks.json" |> Yojson.Safe.from_file in
    let post_seal_pass_field = post_summary_json |> Yojson.Safe.Util.member "post_seal_pass" |> Yojson.Safe.Util.to_bool in
    let all_ctrl_pass_field = post_summary_json |> Yojson.Safe.Util.member "all_control_pass" |> Yojson.Safe.Util.to_bool in
    if post_seal_pass_field <> false || all_ctrl_pass_field <> false then
      failwith "selftest failed: post_seal failure did not mark receipt as failed";

    (* 13f. Unexpected nested tree rejected before descent *)
    let staged_root2 = private_stage () in
    stage_write staged_root2 staged_rel staged_val;
    let rogue_nested = Filename.concat staged_root2 "unauthorized/sub/nested" in
    mkdirs rogue_nested;
    let ch = open_out_bin (Filename.concat rogue_nested "file.txt") in output_string ch "bad"; close_out ch;
    expect_failure "unexpected-nested-tree" "staged-unexpected-dir:" (fun () ->
      verify_staged_manifest staged_root2 test_manifest);
    remove_owned_tree staged_root2;

    (* 13g. Staging failure cleans up allocated root *)
    let simulated_staging_failed = ref false in
    let leaked_root = ref "" in
    begin try
      let root = private_stage () in
      leaked_root := root;
      try
        stage_write root "some/file.txt" "content";
        failwith "simulated-staging-error"
      with exn ->
        (try remove_owned_tree root with _ -> ());
        raise exn
    with Failure msg when msg = "simulated-staging-error" ->
      simulated_staging_failed := true
    end;
    if not !simulated_staging_failed then failwith "selftest failed: staging failure exception not caught";
    if Sys.file_exists !leaked_root then failwith "selftest failed: staging failure did not clean up root";

    (* 13h. Failed child check post-seal status observed (not unobserved PASS) *)
    let post_seal_failchild_dir = Filename.concat tmp_dir "post_seal_failchild" in
    make_dir post_seal_failchild_dir;
    let post_fail_check = { id = "fail-cmd"; expected_code = 0; validate = None; argv = [|"sh"; "-c"; "exit 1"|] } in
    let post_seal_called = ref false in
    let post_pass () = post_seal_called := true in
    let fc_result = execute_checks ~workspace:tmp_dir ~out_dir:post_seal_failchild_dir ~timestamp:"20260930-1135-" ~source_commit:"c5" ~post_seal:post_pass [post_fail_check] in
    if fc_result <> false then failwith "selftest failed: execute_checks returned true with failing child";
    if not !post_seal_called then failwith "selftest failed: post_seal was not run after child failure";
    let fc_summary_json = Filename.concat post_seal_failchild_dir "20260930-1135-ev02-governance-checks.json" |> Yojson.Safe.from_file in
    let fc_checks_pass = fc_summary_json |> Yojson.Safe.Util.member "checks_pass" |> Yojson.Safe.Util.to_bool in
    let fc_post_seal_pass = fc_summary_json |> Yojson.Safe.Util.member "post_seal_pass" |> Yojson.Safe.Util.to_bool in
    let fc_all_ctrl_pass = fc_summary_json |> Yojson.Safe.Util.member "all_control_pass" |> Yojson.Safe.Util.to_bool in
    if fc_checks_pass <> false || fc_post_seal_pass <> true || fc_all_ctrl_pass <> false then
      failwith "selftest failed: failed child check post-seal observation incorrect in receipt";

    (* 13i. Post-seal not provided reports null post_seal_pass *)
    let no_post_seal_dir = Filename.concat tmp_dir "no_post_seal" in
    make_dir no_post_seal_dir;
    let nps_pass_check = { id = "pass-cmd-nps"; expected_code = 0; validate = None; argv = [|"sh"; "-c"; "exit 0"|] } in
    let nps_result = execute_checks ~workspace:tmp_dir ~out_dir:no_post_seal_dir ~timestamp:"20260930-1140-" ~source_commit:"c6" [nps_pass_check] in
    if not nps_result then failwith "selftest failed: execute_checks returned false for passing check without post_seal";
    let nps_summary_json = Filename.concat no_post_seal_dir "20260930-1140-ev02-governance-checks.json" |> Yojson.Safe.from_file in
    let nps_post_seal_field_actual = nps_summary_json |> Yojson.Safe.Util.member "post_seal_pass" in
    if nps_post_seal_field_actual <> `Null then
      failwith "selftest failed: post_seal_pass was not null when post_seal was omitted";

    (* 14. Structured process result verification *)
    let split_res = run_bounded [|"sh"; "-c"; "echo '{\"schema\":\"test\",\"status\":\"PASS\",\"cases\":3}'"|] in
    if not (structured ~schema:"test" ~status:"PASS" ~cases:3 split_res) then
      failwith "selftest failed: structured validation failed on valid json";
    if structured ~schema:"test" ~status:"PASS" ~cases:4 split_res then
      failwith "selftest failed: structured validation passed on wrong cases";

    (* 15. mapping_hold control verification: require rule_rows=38 *)
    let rows_38 = List.init 38 (fun i -> `List [`String (string_of_int i); `String "file.md"; `String "anchor"]) in
    let m_hold_ok = { exit_code = 1; stdout = Yojson.Safe.to_string (`Assoc ["schema", `String "uos.ev02-directive-mapping/v1"; "status", `String "HOLD"; "rule_rows", `List rows_38]); stderr = ""; output = ""; timed_out = false; output_truncated = false; child_pid = 0 } in
    if not (mapping_hold m_hold_ok) then failwith "selftest failed: mapping_hold rejected valid 38-row HOLD";
    let m_hold_missing = { exit_code = 1; stdout = "{\"schema\":\"uos.ev02-directive-mapping/v1\",\"status\":\"HOLD\"}"; stderr = ""; output = ""; timed_out = false; output_truncated = false; child_pid = 0 } in
    if mapping_hold m_hold_missing then failwith "selftest failed: mapping_hold accepted missing rule_rows";
    let rows_37 = List.init 37 (fun i -> `List [`String (string_of_int i); `String "file.md"; `String "anchor"]) in
    let m_hold_37 = { exit_code = 1; stdout = Yojson.Safe.to_string (`Assoc ["schema", `String "uos.ev02-directive-mapping/v1"; "status", `String "HOLD"; "rule_rows", `List rows_37]); stderr = ""; output = ""; timed_out = false; output_truncated = false; child_pid = 0 } in
    if mapping_hold m_hold_37 then failwith "selftest failed: mapping_hold accepted 37-row HOLD";

    (* 16. read_regular stable reader verification *)
    let stable_test_path = Filename.concat staged_root "stable_test.txt" in
    stage_write staged_root "stable_test.txt" "stable-reader-test-content";
    let read_back = read_regular ~max_bytes:100 stable_test_path in
    if read_back <> "stable-reader-test-content" then failwith "selftest failed: read_regular read back wrong content";
    let oversize_refused = try ignore (read_regular ~max_bytes:5 stable_test_path); false with Failure _ -> true in
    if not oversize_refused then failwith "selftest failed: read_regular did not refuse oversize file";

    print_endline {|{"schema":"uos.ev02-harness/v2","status":"PASS","cases":11}|};
    print_endline "PASS run_checks selftest: monotonic_process_group/close_output_sleep/descendant_pipe/output_flood/reap/grandchild_kill/symlink_out_dir/chunked_read/collision/zero_progress/timestamp/digest_receipt_alignment/staging_seals/structured_checks/mapping_hold_shape/read_regular_bounds"
  )

let () =
  if not !Sys.interactive then begin
    let args = Array.to_list Sys.argv in
    if List.mem "--selftest" args || List.mem "--harness-selftest" args then begin
      selftest ();
      exit 0
    end;
    let workspace = ref "." in
    let out_dir = ref "docs/reviews" in
    let timestamp = ref "" in
    let source_commit = ref "" in
    let ocamlrun_opt = ref None in
    let ocaml_opt = ref None in
    let rec parse = function
      | [] -> ()
      | "--workspace" :: dir :: rest -> workspace := dir; parse rest
      | "--out-dir" :: dir :: rest -> out_dir := dir; parse rest
      | "--timestamp" :: ts :: rest -> timestamp := ts; parse rest
      | "--source-commit" :: commit :: rest -> source_commit := commit; parse rest
      | "--ocamlrun" :: exe :: rest -> ocamlrun_opt := Some exe; parse rest
      | "--ocaml" :: exe :: rest -> ocaml_opt := Some exe; parse rest
      | arg :: _ -> failwith ("unknown argument: " ^ arg)
    in
    (match args with _ :: rest -> parse rest | [] -> ());
    if !source_commit = "" then
      failwith "usage: run_checks.ml --source-commit COMMIT --timestamp YYYYMMDD-HHSS- [--workspace DIR] [--out-dir DIR]";
    if not (validate_timestamp !timestamp) then
      failwith "invalid timestamp format: must be YYYYMMDD-HHSS-";
    let ocamlrun = match !ocamlrun_opt with
      | Some p -> p
      | None ->
          let local = Filename.concat !workspace "toolchains/opam-ocaml/bin/ocamlrun" in
          if Sys.file_exists local then local else "ocamlrun"
    in
    let ocaml = match !ocaml_opt with
      | Some p -> p
      | None ->
          let local = Filename.concat !workspace "toolchains/opam-ocaml/bin/ocaml" in
          if Sys.file_exists local then local else "ocaml"
    in
    let policy = Filename.concat !workspace "tools/ev02_governance/policy_surface_gate.ml" in
    let mapping_gate = Filename.concat !workspace "tools/ev02_governance/directive_mapping_gate.ml" in
    let km_script = Filename.concat !workspace "tools/km-gate" in
    let km_exe = Filename.concat !workspace "tools/km_provenance/_build/default/km_gate.exe" in
    let km_cmd args =
      if Sys.file_exists km_exe then Array.append [|km_exe|] args
      else Array.append [|"bash"; km_script|] args
    in
    let jj =
      let candidates = [
        Filename.concat !workspace "toolchains/nix-profile/bin/jj";
        "/home/an/NAS-setup/uos/toolchains/nix-profile/bin/jj";
      ] in
      match List.find_opt Sys.file_exists candidates with
      | Some p -> p
      | None -> "jj"
    in
    let candidate_bindings = bind_candidate ~workspace:!workspace ~jj !source_commit in
    let staged_root, staged_mapping, staged_bindings, manifest =
      stage_inputs ~workspace:!workspace ~jj !source_commit in
    let exit_code =
      Fun.protect ~finally:(fun () ->
        remove_owned_tree staged_root
      ) (fun () ->
        verify_staged_manifest staged_root manifest;
        let checks = [
          { id = "policy-selftest"; expected_code = 0; validate = None; argv = [|ocamlrun; ocaml; policy; "--selftest"|] };
          { id = "policy-fixture-selftest"; expected_code = 0; validate = None; argv = [|ocamlrun; ocaml; policy; "--fixture-selftest"|] };
          { id = "policy-observation"; expected_code = 1; validate = None; argv = [|ocamlrun; ocaml; policy; "--observe"; staged_root|] };
          { id = "mapping-selftest"; expected_code = 0; validate = Some (structured ~schema:"uos.ev02-directive-mapping/v1" ~status:"PASS" ~cases:5); argv = [|ocamlrun; ocaml; mapping_gate; "--selftest"|] };
          { id = "mapping-fixture-selftest"; expected_code = 0; validate = Some (structured ~schema:"uos.ev02-directive-mapping/v1" ~status:"PASS" ~cases:13); argv = [|ocamlrun; ocaml; mapping_gate; "--fixture-selftest"|] };
          { id = "mapping-observation"; expected_code = 1; validate = Some mapping_hold; argv = [|ocamlrun; ocaml; mapping_gate; "--observe"; staged_root; staged_mapping|] };
          { id = "km-gate"; expected_code = 0; validate = None; argv = km_cmd [|"--gate"|] };
        ] in
        let post_seal () = verify_staged_manifest staged_root manifest in
        let all_pass = execute_checks ~workspace:!workspace ~out_dir:!out_dir ~timestamp:!timestamp ~source_commit:!source_commit ~candidate_bindings ~staged_bindings ~post_seal checks in
        if all_pass then 0 else 1
      )
    in
    exit exit_code
  end

