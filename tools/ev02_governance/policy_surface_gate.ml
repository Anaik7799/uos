#use "topfind";;
#require "yojson";;
#load "unix.cma";;

(* Bounded EV-02 policy-surface observation.
   Reports evidence only and deliberately cannot create an admission decision.
   Enforces strict bounds: no symlinks, regular files only, entry limits,
   file size and aggregate budget limits, and complete non-blocking reads. *)

type outcome = Pass | Hold of string list

let max_rules = 64
let max_bytes = 1_048_576
let max_total_bytes = 16_777_216
let max_dir_entries = 256
let surfaces = [".agents/rules"; ".claude/rules"; ".gemini/rules"; ".codex/rules"]

let sort_unique xs = List.sort_uniq String.compare xs
let contains xs value = List.mem value xs
let bounded_error label = raise (Failure ("invalid-input:" ^ label))
let regular stat = stat.Unix.st_kind = Unix.S_REG
let same_file a b = a.Unix.st_dev = b.Unix.st_dev && a.Unix.st_ino = b.Unix.st_ino
let same_stat a b =
  same_file a b &&
  a.Unix.st_size = b.Unix.st_size &&
  a.Unix.st_mtime = b.Unix.st_mtime &&
  a.Unix.st_ctime = b.Unix.st_ctime

let read_regular ~budget path =
  let listed =
    try Unix.lstat path
    with Unix.Unix_error (err, _, _) ->
      bounded_error ("missing-or-unreadable:" ^ path ^ ":" ^ Unix.error_message err)
  in
  if listed.Unix.st_kind = Unix.S_LNK then bounded_error ("symlink-forbidden:" ^ path);
  if not (regular listed) then bounded_error ("not-regular:" ^ path);
  if listed.Unix.st_size < 0 || listed.Unix.st_size > max_bytes then bounded_error "file-size";
  if !budget + listed.Unix.st_size > max_total_bytes then bounded_error "aggregate-size";
  let fd =
    try Unix.openfile path [Unix.O_RDONLY; Unix.O_NONBLOCK; Unix.O_CLOEXEC] 0
    with Unix.Unix_error (err, _, _) ->
      bounded_error ("open-refused:" ^ path ^ ":" ^ Unix.error_message err)
  in
  Fun.protect ~finally:(fun () -> Unix.close fd) (fun () ->
    let opened = Unix.fstat fd in
    if not (regular opened) || not (same_stat listed opened) then
      bounded_error ("file-identity-changed-at-open:" ^ path);
    let bytes = Bytes.create opened.Unix.st_size in
    let rec read_at offset =
      if offset = Bytes.length bytes then () else
      let read = Unix.read fd bytes offset (Bytes.length bytes - offset) in
      if read = 0 then bounded_error "short-read" else read_at (offset + read)
    in
    read_at 0;
    let closed = Unix.fstat fd in
    if not (regular closed) || not (same_stat opened closed) then
      bounded_error ("file-mutated-during-read:" ^ path);
    let final_listed =
      try Unix.lstat path
      with Unix.Unix_error (err, _, _) ->
        bounded_error ("final-stat-failed:" ^ path ^ ":" ^ Unix.error_message err)
    in
    if final_listed.Unix.st_kind = Unix.S_LNK then bounded_error ("final-symlink-forbidden:" ^ path);
    if not (regular final_listed) || not (same_stat opened final_listed) then
      bounded_error ("path-substituted-or-mutated:" ^ path);
    budget := !budget + Bytes.length bytes;
    Bytes.to_string bytes)

let list_rule_names path =
  let stat =
    try Unix.lstat path
    with Unix.Unix_error (err, _, _) ->
      bounded_error ("missing-rule-directory:" ^ path ^ ":" ^ Unix.error_message err)
  in
  if stat.Unix.st_kind = Unix.S_LNK then bounded_error ("surface-symlink:" ^ path);
  if stat.Unix.st_kind <> Unix.S_DIR then bounded_error ("surface-not-directory:" ^ path);
  let directory =
    try Unix.opendir path
    with Unix.Unix_error (err, _, _) ->
      bounded_error ("rule-directory-open:" ^ path ^ ":" ^ Unix.error_message err)
  in
  Fun.protect ~finally:(fun () -> Unix.closedir directory) (fun () ->
    let rec loop names seen entries =
      match Unix.readdir directory with
      | entry when entries >= max_dir_entries -> bounded_error "rule-directory-entry-limit"
      | entry ->
          if entry = "." || entry = ".." then loop names seen (entries + 1)
          else if String.contains entry '/' || String.contains entry '\000' then
            bounded_error ("invalid-entry-name:" ^ entry)
          else
            let entry_path = Filename.concat path entry in
            let entry_stat =
              try Unix.lstat entry_path
              with Unix.Unix_error (err, _, _) ->
                bounded_error ("stat-failed:" ^ entry_path ^ ":" ^ Unix.error_message err)
            in
            if entry_stat.Unix.st_kind = Unix.S_LNK then
              bounded_error ("rule-symlink-forbidden:" ^ entry_path)
            else if not (regular entry_stat) then
              bounded_error ("unsupported-entry-not-regular:" ^ entry_path)
            else if Filename.check_suffix entry ".md" && entry <> "README.md" then
              if seen >= max_rules then bounded_error "rule-directory-count"
              else loop (entry :: names) (seen + 1) (entries + 1)
            else loop names seen (entries + 1)
      | exception End_of_file -> sort_unique names
    in loop [] 0 0)

let replace_all ~needle ~replacement text =
  let n = String.length needle in
  if n = 0 then text else
  let b = Buffer.create (String.length text) in
  let rec go start =
    match String.index_from_opt text start needle.[0] with
    | None -> Buffer.add_substring b text start (String.length text - start)
    | Some i when i + n <= String.length text && String.sub text i n = needle ->
        Buffer.add_substring b text start (i - start); Buffer.add_string b replacement; go (i + n)
    | Some i -> Buffer.add_substring b text start (i - start + 1); go (i + 1)
  in go 0; Buffer.contents b

let normalize body =
  let header = "---\ntrigger: always_on\n---\n\n" in
  let body =
    if String.starts_with ~prefix:header body then
      String.sub body (String.length header) (String.length body - String.length header)
    else body
  in
  ["http://nas-1.tail55d152.ts.net:4100/docs/.agents/rules/";
   "http://nas-1.tail55d152.ts.net:4100/docs/.claude/rules/";
   "http://nas-1.tail55d152.ts.net:4100/docs/.gemini/rules/";
   "http://nas-1.tail55d152.ts.net:4100/docs/.codex/rules/";
   "http://nas-1.tail55d152.ts.net:4100/files/.agents/rules/";
   "http://nas-1.tail55d152.ts.net:4100/files/.claude/rules/";
   "http://nas-1.tail55d152.ts.net:4100/files/.gemini/rules/";
   "http://nas-1.tail55d152.ts.net:4100/files/.codex/rules/"]
  |> List.fold_left (fun text locator -> replace_all ~needle:locator ~replacement:"<surface-policy-link>/" text) body

let intersection = function
  | [] -> []
  | first :: rest -> List.filter (fun n -> List.for_all (List.mem n) rest) first

let evaluate ~directive_count inventories contents =
  let shared = intersection inventories in
  let errors = ref [] in
  if List.length shared > max_rules then errors := "rule-bound" :: !errors;
  if directive_count <> 38 then errors := "directive-count" :: !errors;
  List.iteri (fun index present ->
    if present <> shared then
      errors := ("missing-surface-" ^ string_of_int index) :: !errors) inventories;
  let first = match contents with [] -> [] | x :: _ -> x in
  if List.exists (fun values -> values <> first) contents then
    errors := "normalized-body-divergence" :: !errors;
  (* The canonical TOML enumerates directives but does not map any directive ID
     to a rule document. Do not infer that a file count establishes closure. *)
  errors := "no-directive-to-rule-mapping" :: !errors;
  match List.rev !errors with [] -> Pass | errors -> Hold errors

let parse_directive_count text =
  let lines = String.split_on_char '\n' text in
  List.fold_left (fun count line ->
    if String.trim line = "[[directive]]" then count + 1 else count) 0 lines

let observe root =
  let budget = ref 0 in
  let inventories = List.map (fun relative -> list_rule_names (Filename.concat root relative)) surfaces in
  let shared = intersection inventories in
  let contents = List.map (fun relative ->
    List.map (fun name ->
      let full_path = Filename.concat root (Filename.concat relative name) in
      let raw = read_regular ~budget full_path in
      name ^ "\000" ^ normalize raw) shared) surfaces in
  let superset_path = Filename.concat root "governance/agents/policy/superset.toml" in
  let superset_raw = read_regular ~budget superset_path in
  let count = parse_directive_count superset_raw in
  evaluate ~directive_count:count inventories contents, shared, inventories, count, contents

let divergent_names shared contents =
  List.mapi (fun index name ->
    let at index values = try List.nth values index with Failure _ -> "" in
    let baseline = match contents with [] -> "" | values :: _ -> at index values in
    if List.for_all (fun values -> at index values = baseline) contents then None else Some name) shared
  |> List.filter_map (fun x -> x)

let print_json outcome shared inventories directive_count contents =
  let divergent = divergent_names shared contents in
  let base_fields = [
    "schema", `String "uos.ev02-policy-surface/v1";
    "authority", `String "REPORT_ONLY";
    "admission", `String "NOT_GRANTED";
  ] in
  let doc = match outcome with
    | Pass ->
        `Assoc (base_fields @ [
          "status", `String "PASS";
          "directive_count", `Int directive_count;
          "shared_rule_files", `List (List.map (fun n -> `String n) shared);
          "surface_counts", `List (List.map (fun xs -> `Int (List.length xs)) inventories);
          "normalized_divergent_rule_files", `List (List.map (fun n -> `String n) divergent);
        ])
    | Hold errors ->
        `Assoc (base_fields @ [
          "status", `String "HOLD";
          "directive_count", `Int directive_count;
          "shared_rule_files", `List (List.map (fun n -> `String n) shared);
          "surface_counts", `List (List.map (fun xs -> `Int (List.length xs)) inventories);
          "normalized_divergent_rule_files", `List (List.map (fun n -> `String n) divergent);
          "errors", `List (List.map (fun e -> `String e) errors);
        ])
  in
  print_endline (Yojson.Safe.to_string doc)

let selftest () =
  let exact = ["a"; "b"] in
  let same = ["a\000one"; "b\000two"] in
  let check label actual =
    if not actual then failwith ("selftest failed: " ^ label) in
  let has expected = function Hold errors -> List.mem expected errors | Pass -> false in
  check "mapping-hold" (has "no-directive-to-rule-mapping"
    (evaluate ~directive_count:38 [exact; exact] [same; same]));
  check "missing" (has "missing-surface-0"
    (evaluate ~directive_count:38 [exact; ["a"]] [same; same]));
  check "directive-count" (has "directive-count"
    (evaluate ~directive_count:37 [exact; exact] [same; same]));
  check "divergence" (has "normalized-body-divergence"
    (evaluate ~directive_count:38 [exact; exact] [same; ["a\000one"; "b\000changed"]]));
  check "header-and-link-normalization"
    (normalize "---\ntrigger: always_on\n---\n\nSee http://nas-1.tail55d152.ts.net:4100/docs/.agents/rules/x" = "See <surface-policy-link>/x");
  check "normative-prose-retained"
    (normalize "MUST keep .agents/rules/x in this sentence" = "MUST keep .agents/rules/x in this sentence");
  (* Test malformed filename and error JSON encoding with low bytes (0x01), quotes, and backslashes *)
  let malformed_str = "malformed-error:\001\002\"quote\"\\backslash\nnewline" in
  let test_doc = `Assoc [
    "schema", `String "uos.ev02-policy-surface/v1";
    "authority", `String "REPORT_ONLY";
    "admission", `String "NOT_GRANTED";
    "status", `String "HOLD";
    "errors", `List [`String malformed_str];
  ] in
  let serialized = Yojson.Safe.to_string test_doc in
  let parsed = try Yojson.Safe.from_string serialized with _ -> failwith "malformed json parse failed" in
  (match parsed with
   | `Assoc fields ->
       (match List.assoc_opt "errors" fields with
        | Some (`List [`String s]) when s = malformed_str -> ()
        | _ -> failwith "malformed json structure error")
   | _ -> failwith "malformed json not assoc");
  print_endline "PASS policy-surface selftest: mapping/missing/directive-count/divergence/json-encoding"

let rec make_dir path =
  if not (Sys.file_exists path) then begin
    let parent = Filename.dirname path in
    if parent <> path && not (Sys.file_exists parent) then make_dir parent;
    try Unix.mkdir path 0o700 with Unix.Unix_error (Unix.EEXIST, _, _) -> ()
  end
let write_file path text =
  let fd = Unix.openfile path [Unix.O_WRONLY; Unix.O_CREAT; Unix.O_TRUNC; Unix.O_CLOEXEC] 0o644 in
  Fun.protect ~finally:(fun () -> Unix.close fd) (fun () ->
    let bytes = Bytes.of_string text in
    let len = Bytes.length bytes in
    let rec loop off =
      if off = len then () else
      let n = Unix.write fd bytes off (len - off) in
      loop (off + n)
    in loop 0)

let private_root label =
  let path = Filename.temp_file ("ev02-policy-" ^ label ^ "-") "" in
  Sys.remove path;
  Unix.mkdir path 0o700;
  path

let expect_refusal label thunk =
  try ignore (thunk ()); failwith ("selftest accepted: " ^ label)
  with Failure detail when String.starts_with ~prefix:"invalid-input:" detail -> ()

let fixture_selftest () =
  let root = private_root "valid" in
  make_dir (Filename.concat root "governance");
  make_dir (Filename.concat root "governance/agents");
  make_dir (Filename.concat root "governance/agents/policy");
  let superset = List.init 38 (fun i -> Printf.sprintf "[[directive]]\nid = \"DIR-%02d\"\n" (i + 1)) |> String.concat "" in
  write_file (Filename.concat root "governance/agents/policy/superset.toml") superset;
  List.iter (fun surface ->
    make_dir (Filename.concat root (Filename.dirname surface));
    make_dir (Filename.concat root surface);
    write_file (Filename.concat root (Filename.concat surface "rule.md")) "# Rule\nbody\n") surfaces;
  let outcome, shared, _, count, _ = observe root in
  if count <> 38 || shared <> ["rule.md"] then failwith "valid fixture observation mismatch";
  (match outcome with Hold ["no-directive-to-rule-mapping"] -> () | _ -> failwith "valid fixture must HOLD");

  (* Symlink rule file refusal *)
  let sym_root = private_root "sym-file" in
  make_dir (Filename.concat sym_root "governance/agents/policy");
  write_file (Filename.concat sym_root "governance/agents/policy/superset.toml") superset;
  List.iter (fun surface ->
    make_dir (Filename.concat sym_root surface);
    if surface = ".claude/rules" then begin
      let target = Filename.concat sym_root "target.md" in
      write_file target "# Target\n";
      Unix.symlink target (Filename.concat sym_root (Filename.concat surface "rule.md"))
    end else
      write_file (Filename.concat sym_root (Filename.concat surface "rule.md")) "# Rule\n") surfaces;
  let symlink_rule_path = Filename.concat sym_root ".claude/rules/rule.md" in
  let b = ref 0 in
  expect_refusal "symlink-rule-file" (fun () -> read_regular ~budget:b symlink_rule_path);
  expect_refusal "symlink-rule-file-in-observe" (fun () -> observe sym_root);

  (* Symlink rule directory refusal *)
  let dir_sym_root = private_root "sym-dir" in
  make_dir (Filename.concat dir_sym_root "governance/agents/policy");
  write_file (Filename.concat dir_sym_root "governance/agents/policy/superset.toml") superset;
  let real_dir = Filename.concat dir_sym_root "real_rules" in
  make_dir real_dir;
  write_file (Filename.concat real_dir "rule.md") "# Rule\n";
  make_dir (Filename.concat dir_sym_root ".agents");
  Unix.symlink real_dir (Filename.concat dir_sym_root ".agents/rules");
  make_dir (Filename.concat dir_sym_root ".claude/rules");
  make_dir (Filename.concat dir_sym_root ".gemini/rules");
  make_dir (Filename.concat dir_sym_root ".codex/rules");
  write_file (Filename.concat dir_sym_root ".claude/rules/rule.md") "# Rule\n";
  write_file (Filename.concat dir_sym_root ".gemini/rules/rule.md") "# Rule\n";
  write_file (Filename.concat dir_sym_root ".codex/rules/rule.md") "# Rule\n";
  expect_refusal "symlink-surface-dir" (fun () -> observe dir_sym_root);

  (* Oversize file refusal *)
  let over_root = private_root "oversize" in
  make_dir (Filename.concat over_root "governance/agents/policy");
  write_file (Filename.concat over_root "governance/agents/policy/superset.toml") superset;
  let big_content = String.make (max_bytes + 1024) 'z' in
  List.iter (fun surface ->
    make_dir (Filename.concat over_root surface);
    write_file (Filename.concat over_root (Filename.concat surface "rule.md"))
      (if surface = ".agents/rules" then big_content else "# Rule\n")) surfaces;
  expect_refusal "oversize-rule-file" (fun () -> observe over_root);

  (* Non-regular file in rule directory refusal *)
  let nonreg_root = private_root "nonreg" in
  make_dir (Filename.concat nonreg_root "governance/agents/policy");
  write_file (Filename.concat nonreg_root "governance/agents/policy/superset.toml") superset;
  List.iter (fun surface ->
    make_dir (Filename.concat nonreg_root surface);
    write_file (Filename.concat nonreg_root (Filename.concat surface "rule.md")) "# Rule\n";
    if surface = ".agents/rules" then
      make_dir (Filename.concat nonreg_root (Filename.concat surface "subfolder"))) surfaces;
  expect_refusal "non-regular-entry" (fun () -> observe nonreg_root);

  (* Stable metadata and path checks *)
  let s_stat = Unix.lstat (Filename.concat root "governance/agents/policy/superset.toml") in
  let mutated_mtime = { s_stat with Unix.st_mtime = s_stat.Unix.st_mtime +. 1.0 } in
  if same_stat s_stat mutated_mtime then failwith "same_stat accepted mutated mtime";
  let mutated_ctime = { s_stat with Unix.st_ctime = s_stat.Unix.st_ctime +. 1.0 } in
  if same_stat s_stat mutated_ctime then failwith "same_stat accepted mutated ctime";
  let substituted_ino = { s_stat with Unix.st_ino = s_stat.Unix.st_ino + 1 } in
  if same_stat s_stat substituted_ino then failwith "same_stat accepted substituted inode";

  print_endline "PASS policy-surface fixture selftest: valid/symlink-file/symlink-dir/oversize/non-regular/metadata"

let () =
  match Array.to_list Sys.argv with
  | [_; "--selftest"] -> selftest ()
  | [_; "--fixture-selftest"] -> fixture_selftest ()
  | [_; "--observe"; root] ->
      let outcome, shared, inventories, count, contents =
        try observe root
        with Failure detail ->
          let err_doc = `Assoc [
            "schema", `String "uos.ev02-policy-surface/v1";
            "authority", `String "REPORT_ONLY";
            "admission", `String "NOT_GRANTED";
            "status", `String "HOLD";
            "errors", `List [`String detail];
          ] in
          print_endline (Yojson.Safe.to_string err_doc);
          exit 1
      in
      print_json outcome shared inventories count contents;
      (match outcome with Pass -> exit 0 | Hold _ -> exit 1)
  | _ -> failwith "usage: policy_surface_gate.ml --selftest | --fixture-selftest | --observe ROOT"
