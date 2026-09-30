#use "topfind";;
#require "yojson,cryptokit";;
#load "unix.cma";;

let max_files = 32
let max_bytes = 1_048_576
let max_total_bytes = 16_777_216

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

let regular stat = stat.Unix.st_kind = Unix.S_REG
let same_file a b = a.Unix.st_dev = b.Unix.st_dev && a.Unix.st_ino = b.Unix.st_ino
let same_stat a b =
  same_file a b &&
  a.Unix.st_size = b.Unix.st_size &&
  a.Unix.st_mtime = b.Unix.st_mtime &&
  a.Unix.st_ctime = b.Unix.st_ctime

let validate_timestamp ts =
  if String.length ts <> 14 then false
  else if ts.[8] <> '-' || ts.[13] <> '-' then false
  else
    let is_digit c = c >= '0' && c <= '9' in
    let digits = [0;1;2;3;4;5;6;7;9;10;11;12] in
    List.for_all (fun i -> is_digit ts.[i]) digits

let validate_relative_path rel_path =
  if rel_path = "" then failwith "invalid-path:empty"
  else if rel_path.[0] = '/' then failwith ("invalid-path:absolute-forbidden:" ^ rel_path)
  else if String.contains rel_path '\000' then failwith ("invalid-path:nul-forbidden:" ^ rel_path)
  else
    let parts = String.split_on_char '/' rel_path in
    if List.mem ".." parts || List.mem "." parts then
      failwith ("invalid-path:traversal-forbidden:" ^ rel_path)

let verify_no_symlink_components workspace rel_path =
  validate_relative_path rel_path;
  let parts = String.split_on_char '/' rel_path in
  let rec check_prefix current = function
    | [] -> ()
    | part :: rest ->
        let next = Filename.concat current part in
        let st =
          try Unix.lstat next
          with Unix.Unix_error (e, _, _) -> failwith ("path-stat-failed:" ^ next ^ ":" ^ Unix.error_message e)
        in
        if st.Unix.st_kind = Unix.S_LNK then
          failwith ("symlink-component-forbidden:" ^ next)
        else
          check_prefix next rest
  in
  check_prefix workspace parts

let sha_bounded_regular ~budget full_path =
  let listed =
    try Unix.lstat full_path
    with Unix.Unix_error (e, _, _) -> failwith ("file-stat-failed:" ^ full_path ^ ":" ^ Unix.error_message e)
  in
  if listed.Unix.st_kind = Unix.S_LNK then failwith ("symlink-forbidden:" ^ full_path);
  if not (regular listed) then failwith ("not-regular:" ^ full_path);
  if listed.Unix.st_size < 0 || listed.Unix.st_size > max_bytes then failwith ("file-size-exceeded:" ^ full_path);
  if !budget + listed.Unix.st_size > max_total_bytes then failwith ("aggregate-size-exceeded:" ^ full_path);
  let fd =
    try Unix.openfile full_path [Unix.O_RDONLY; Unix.O_NONBLOCK; Unix.O_CLOEXEC] 0
    with Unix.Unix_error (e, _, _) -> failwith ("open-failed:" ^ full_path ^ ":" ^ Unix.error_message e)
  in
  Fun.protect ~finally:(fun () -> Unix.close fd) (fun () ->
    let opened = Unix.fstat fd in
    if not (regular opened) || not (same_stat listed opened) then
      failwith ("file-identity-changed-at-open:" ^ full_path);
    let hash = Cryptokit.Hash.sha256 () in
    let expected_len = opened.Unix.st_size in
    let bytes = Bytes.create (min expected_len 16384) in
    let rec read_exact total =
      if total = expected_len then ()
      else
        let to_read = min (Bytes.length bytes) (expected_len - total) in
        let n =
          try Unix.read fd bytes 0 to_read
          with Unix.Unix_error (Unix.EINTR, _, _) -> 0
        in
        if n = 0 then failwith ("unexpected-eof-short-read:" ^ full_path)
        else begin
          hash#add_substring bytes 0 n;
          read_exact (total + n)
        end
    in
    read_exact 0;
    let closed = Unix.fstat fd in
    if not (regular closed) || not (same_stat opened closed) then
      failwith ("file-mutated-during-read:" ^ full_path);
    let final_listed =
      try Unix.lstat full_path
      with Unix.Unix_error (e, _, _) -> failwith ("final-stat-failed:" ^ full_path ^ ":" ^ Unix.error_message e)
    in
    if final_listed.Unix.st_kind = Unix.S_LNK then failwith ("final-symlink-forbidden:" ^ full_path);
    if not (regular final_listed) || not (same_stat opened final_listed) then
      failwith ("path-substituted-or-mutated:" ^ full_path);
    budget := !budget + expected_len;
    Cryptokit.transform_string (Cryptokit.Hexa.encode ()) hash#result)

let generate_manifest ~workspace ~out_dir ~timestamp ~base_commit files =
  if files = [] then failwith "reject-zero-progress:empty-file-list";
  if List.length files > max_files then failwith "source-count-limit-exceeded";
  if not (validate_timestamp timestamp) then failwith "invalid-timestamp-format";
  if String.contains out_dir '\000' || String.contains timestamp '/' || String.contains timestamp '\\' then
    failwith "path-escape-forbidden-in-out-dir-or-timestamp";
  let budget = ref 0 in
  let entries = List.map (fun rel_path ->
    verify_no_symlink_components workspace rel_path;
    let full_path = Filename.concat workspace rel_path in
    let digest = sha_bounded_regular ~budget full_path in
    `Assoc ["path", `String rel_path; "sha256", `String digest]
  ) files in
  let doc =
    `Assoc [
      "schema", `String "uos.ev02-governance-manifest/v1";
      "authority", `String "REPORT_ONLY";
      "admission", `String "NOT_GRANTED";
      "base_commit", `String base_commit;
      "file_count", `Int (List.length entries);
      "files", `List entries
    ] |> Yojson.Safe.pretty_to_string
  in
  let out_file = Printf.sprintf "%sev02-governance-manifest.json" timestamp in
  let out_path = Filename.concat out_dir out_file in
  write_exclusive out_path (doc ^ "\n");
  out_path

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
  let tmp_dir = Filename.temp_file "ev02-mnf-test-" "" in
  Sys.remove tmp_dir;
  make_dir tmp_dir;
  let file_a = Filename.concat tmp_dir "file_a.txt" in
  write_exclusive file_a "content_a";
  let b = ref 0 in
  let sha_a = sha_bounded_regular ~budget:b file_a in
  let expected_sha =
    Cryptokit.hash_string (Cryptokit.Hash.sha256 ()) "content_a"
    |> Cryptokit.transform_string (Cryptokit.Hexa.encode ())
  in
  if sha_a <> expected_sha then failwith "selftest failed: regular file sha mismatch";

  (* 1. Traversal path rejection *)
  expect_failure "traversal-path" "invalid-path:traversal-forbidden:" (fun () ->
    generate_manifest ~workspace:tmp_dir ~out_dir:(Filename.concat tmp_dir "out")
      ~timestamp:"20260930-1115-" ~base_commit:"c0" ["../file.txt"]);

  (* 2. Absolute path rejection *)
  expect_failure "absolute-path" "invalid-path:absolute-forbidden:" (fun () ->
    generate_manifest ~workspace:tmp_dir ~out_dir:(Filename.concat tmp_dir "out")
      ~timestamp:"20260930-1115-" ~base_commit:"c0" ["/etc/passwd"]);

  (* 3. Symlink file rejection *)
  let sym_a = Filename.concat tmp_dir "sym_a.txt" in
  Unix.symlink file_a sym_a;
  expect_failure "symlink-file" "symlink-component-forbidden:" (fun () ->
    generate_manifest ~workspace:tmp_dir ~out_dir:(Filename.concat tmp_dir "out")
      ~timestamp:"20260930-1115-" ~base_commit:"c0" ["sym_a.txt"]);

  (* 4. Symlink directory component rejection *)
  let real_sub = Filename.concat tmp_dir "real_sub" in
  make_dir real_sub;
  write_exclusive (Filename.concat real_sub "target.txt") "sub";
  let sym_sub = Filename.concat tmp_dir "sym_sub" in
  Unix.symlink real_sub sym_sub;
  expect_failure "symlink-directory-component" "symlink-component-forbidden:" (fun () ->
    generate_manifest ~workspace:tmp_dir ~out_dir:(Filename.concat tmp_dir "out")
      ~timestamp:"20260930-1115-" ~base_commit:"c0" ["sym_sub/target.txt"]);

  (* 5. Symlink in output directory ancestor rejection *)
  let sym_out = Filename.concat tmp_dir "sym_out" in
  Unix.symlink real_sub sym_out;
  expect_failure "symlink-out-dir" "symlink-in-output-dir-forbidden:" (fun () ->
    generate_manifest ~workspace:tmp_dir ~out_dir:(Filename.concat sym_out "sub")
      ~timestamp:"20260930-1115-" ~base_commit:"c0" ["file_a.txt"]);

  (* 6. Oversize file rejection *)
  let big_file = Filename.concat tmp_dir "big.txt" in
  write_exclusive big_file (String.make (max_bytes + 1) 'x');
  expect_failure "oversize-file" "file-size-exceeded:" (fun () ->
    generate_manifest ~workspace:tmp_dir ~out_dir:(Filename.concat tmp_dir "out")
      ~timestamp:"20260930-1115-" ~base_commit:"c0" ["big.txt"]);

  (* 7. Count limit rejection *)
  let many_files = List.init 35 (fun i ->
    let name = Printf.sprintf "file_%02d.txt" i in
    write_exclusive (Filename.concat tmp_dir name) "data";
    name
  ) in
  expect_failure "count-limit" "source-count-limit-exceeded" (fun () ->
    generate_manifest ~workspace:tmp_dir ~out_dir:(Filename.concat tmp_dir "out")
      ~timestamp:"20260930-1115-" ~base_commit:"c0" many_files);

  (* 8. Malformed and empty timestamp rejection *)
  expect_failure "empty-timestamp" "invalid-timestamp-format" (fun () ->
    generate_manifest ~workspace:tmp_dir ~out_dir:(Filename.concat tmp_dir "out")
      ~timestamp:"" ~base_commit:"c0" ["file_a.txt"]);
  expect_failure "malformed-timestamp" "invalid-timestamp-format" (fun () ->
    generate_manifest ~workspace:tmp_dir ~out_dir:(Filename.concat tmp_dir "out")
      ~timestamp:"bad-ts" ~base_commit:"c0" ["file_a.txt"]);

  (* 9. Zero-progress write rejection *)
  expect_failure "zero-progress-empty-list" "reject-zero-progress:empty-file-list" (fun () ->
    generate_manifest ~workspace:tmp_dir ~out_dir:(Filename.concat tmp_dir "out")
      ~timestamp:"20260930-1115-" ~base_commit:"c0" []);

  (* 10. Existing-target preservation / collision detection *)
  let out_dir = Filename.concat tmp_dir "out" in
  make_dir out_dir;
  let out1 = generate_manifest ~workspace:tmp_dir ~out_dir ~timestamp:"20260930-1115-" ~base_commit:"c0" ["file_a.txt"] in
  if not (Sys.file_exists out1) then failwith "selftest failed: manifest not generated";
  expect_failure "output-collision" "output-collision:" (fun () ->
    generate_manifest ~workspace:tmp_dir ~out_dir ~timestamp:"20260930-1115-" ~base_commit:"c0" ["file_a.txt"]);

  (* 11. Actual CLI exit observation: verify CLI with bad timestamp exits non-zero *)
  let dev_null = Unix.openfile "/dev/null" [Unix.O_WRONLY] 0 in
  let cli_pid = Unix.create_process "ocaml" [|"ocaml"; "tools/ev02_governance/write_manifest.ml"; "--timestamp"; "bad-ts"; "--base-commit"; "c0"|] Unix.stdin dev_null dev_null in
  let _, cli_status = Unix.waitpid [] cli_pid in
  Unix.close dev_null;
  (match cli_status with
   | Unix.WEXITED code when code <> 0 -> ()
   | _ -> failwith "selftest failed: CLI did not exit non-zero on invalid timestamp");

  print_endline "PASS write_manifest selftest: bounded_regular/traversal/absolute/symlink/symlink_dir/symlink_out_dir/oversize/count_limit/timestamp/zero_progress/collision/cli_exit"

let default_files = [
  "tools/ev02_governance/policy_surface_gate.ml";
  "tools/ev02_governance/directive_mapping_gate.ml";
  "tools/ev02_governance/run_checks.ml";
  "tools/ev02_governance/write_manifest.ml";
  "tools/ev02_governance/write_evidence.ml";
  "governance/agents/policy/20260909-1836-ev02-current-directive-rule-amendment.json";
]

let () =
  if not !Sys.interactive then begin
    let args = Array.to_list Sys.argv in
    if List.mem "--selftest" args then begin
      selftest ();
      exit 0
    end;
    let workspace = ref "." in
    let out_dir = ref "docs/reviews" in
    let timestamp = ref "" in
    let base_commit = ref "" in
    let custom_files = ref [] in
    let rec parse = function
      | [] -> ()
      | "--workspace" :: dir :: rest -> workspace := dir; parse rest
      | "--out-dir" :: dir :: rest -> out_dir := dir; parse rest
      | "--timestamp" :: ts :: rest -> timestamp := ts; parse rest
      | "--base-commit" :: commit :: rest -> base_commit := commit; parse rest
      | "--file" :: file :: rest -> custom_files := file :: !custom_files; parse rest
      | arg :: _ -> failwith ("unknown argument: " ^ arg)
    in
    (match args with _ :: rest -> parse rest | [] -> ());
    if !base_commit = "" then
      failwith "usage: write_manifest.ml --base-commit COMMIT --timestamp YYYYMMDD-HHSS- [--workspace DIR] [--out-dir DIR] [--file PATH ...]";
    if not (validate_timestamp !timestamp) then
      failwith "invalid timestamp format: must be YYYYMMDD-HHSS-";
    let files = if !custom_files = [] then default_files else List.rev !custom_files in
    let out_path = generate_manifest ~workspace:!workspace ~out_dir:!out_dir ~timestamp:!timestamp ~base_commit:!base_commit files in
    Printf.printf "Wrote manifest: %s\n" out_path
  end
