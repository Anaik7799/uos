#use "topfind";;
#require "yojson,cryptokit";;
#load "unix.cma";;

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

let generate_evidence ~workspace ~out_dir ~timestamp ~source_commit ~source_change_id ~base_commit
    ~manifest_rel ~risk_rel ~active_receipt ~executions ~holds =
  if source_commit = "" || source_change_id = "" || base_commit = "" then
    failwith "commit-identifiers-missing";
  if not (validate_timestamp timestamp) then failwith "invalid-timestamp-format";
  if String.contains out_dir '\000' || String.contains timestamp '/' || String.contains timestamp '\\' then
    failwith "path-escape-forbidden-in-out-dir-or-timestamp";
  if String.contains active_receipt '\000' then
    failwith "invalid-path:nul-forbidden-in-active-receipt";
  List.iter (fun exec ->
    if String.contains exec '\000' then failwith "invalid-path:nul-forbidden-in-execution"
  ) executions;

  verify_no_symlink_components workspace manifest_rel;
  verify_no_symlink_components workspace risk_rel;

  let budget = ref 0 in
  let manifest_full = Filename.concat workspace manifest_rel in
  let manifest_sha = sha_bounded_regular ~budget manifest_full in
  let risk_full = Filename.concat workspace risk_rel in
  let risk_sha = sha_bounded_regular ~budget risk_full in

  let doc =
    `Assoc [
      "schema", `String "uos.ev02-governance-evidence-binding/v1";
      "authority", `String "REPORT_ONLY";
      "admission", `String "NOT_GRANTED";
      "source_commit", `String source_commit;
      "source_change_id", `String source_change_id;
      "base_commit", `String base_commit;
      "manifest", `Assoc [
        "path", `String manifest_rel;
        "sha256", `String manifest_sha;
      ];
      "risk", `Assoc [
        "path", `String risk_rel;
        "sha256", `String risk_sha;
        "active_receipt", `String active_receipt;
      ];
      "executions", `List (List.map (fun e -> `String e) executions);
      "holds", `List (List.map (fun h -> `String h) holds);
    ] |> Yojson.Safe.pretty_to_string
  in
  let out_file = Printf.sprintf "%sev02-governance-evidence-binding.json" timestamp in
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
  let tmp_dir = Filename.temp_file "ev02-evidence-test-" "" in
  Sys.remove tmp_dir;
  make_dir tmp_dir;
  let manifest_file = Filename.concat tmp_dir "manifest.json" in
  write_exclusive manifest_file "{\"manifest\":true}";
  let risk_file = Filename.concat tmp_dir "risk.json" in
  write_exclusive risk_file "{\"risk\":true}";

  (* 1. Verify regular sha and doc creation *)
  let out_dir = Filename.concat tmp_dir "out" in
  make_dir out_dir;
  let out1 = generate_evidence ~workspace:tmp_dir ~out_dir ~timestamp:"20260930-1115-"
    ~source_commit:"c1" ~source_change_id:"ch1" ~base_commit:"c0"
    ~manifest_rel:"manifest.json" ~risk_rel:"risk.json" ~active_receipt:"/tmp/active.json"
    ~executions:["test-exec.json"] ~holds:["hold 1"] in
  if not (Sys.file_exists out1) then failwith "selftest failed: evidence binding not created";

  (* 2. Traversal path rejection *)
  expect_failure "traversal-manifest" "invalid-path:traversal-forbidden:" (fun () ->
    generate_evidence ~workspace:tmp_dir ~out_dir ~timestamp:"20260930-1116-"
      ~source_commit:"c1" ~source_change_id:"ch1" ~base_commit:"c0"
      ~manifest_rel:"../manifest.json" ~risk_rel:"risk.json" ~active_receipt:""
      ~executions:[] ~holds:[]);
  expect_failure "traversal-risk" "invalid-path:traversal-forbidden:" (fun () ->
    generate_evidence ~workspace:tmp_dir ~out_dir ~timestamp:"20260930-1116-"
      ~source_commit:"c1" ~source_change_id:"ch1" ~base_commit:"c0"
      ~manifest_rel:"manifest.json" ~risk_rel:"../risk.json" ~active_receipt:""
      ~executions:[] ~holds:[]);

  (* 3. Absolute path rejection *)
  expect_failure "absolute-manifest" "invalid-path:absolute-forbidden:" (fun () ->
    generate_evidence ~workspace:tmp_dir ~out_dir ~timestamp:"20260930-1116-"
      ~source_commit:"c1" ~source_change_id:"ch1" ~base_commit:"c0"
      ~manifest_rel:"/etc/passwd" ~risk_rel:"risk.json" ~active_receipt:""
      ~executions:[] ~holds:[]);

  (* 4. Symlink rejection *)
  let sym_file = Filename.concat tmp_dir "manifest-sym.json" in
  Unix.symlink manifest_file sym_file;
  expect_failure "symlink-manifest" "symlink-component-forbidden:" (fun () ->
    generate_evidence ~workspace:tmp_dir ~out_dir ~timestamp:"20260930-1116-"
      ~source_commit:"c1" ~source_change_id:"ch1" ~base_commit:"c0"
      ~manifest_rel:"manifest-sym.json" ~risk_rel:"risk.json" ~active_receipt:""
      ~executions:[] ~holds:[]);

  (* 5. Symlink directory component rejection *)
  let real_sub = Filename.concat tmp_dir "real_sub" in
  make_dir real_sub;
  write_exclusive (Filename.concat real_sub "risk_sub.json") "{}";
  let sym_sub = Filename.concat tmp_dir "sym_sub" in
  Unix.symlink real_sub sym_sub;
  expect_failure "symlink-directory-component" "symlink-component-forbidden:" (fun () ->
    generate_evidence ~workspace:tmp_dir ~out_dir ~timestamp:"20260930-1116-"
      ~source_commit:"c1" ~source_change_id:"ch1" ~base_commit:"c0"
      ~manifest_rel:"manifest.json" ~risk_rel:"sym_sub/risk_sub.json" ~active_receipt:""
      ~executions:[] ~holds:[]);

  (* 6. Symlink in output directory ancestor rejection *)
  let sym_out = Filename.concat tmp_dir "sym_out" in
  Unix.symlink real_sub sym_out;
  expect_failure "symlink-out-dir" "symlink-in-output-dir-forbidden:" (fun () ->
    generate_evidence ~workspace:tmp_dir ~out_dir:(Filename.concat sym_out "sub")
      ~timestamp:"20260930-1116-" ~source_commit:"c1" ~source_change_id:"ch1" ~base_commit:"c0"
      ~manifest_rel:"manifest.json" ~risk_rel:"risk.json" ~active_receipt:""
      ~executions:[] ~holds:[]);

  (* 7. Oversize file rejection *)
  let big_file = Filename.concat tmp_dir "big.json" in
  write_exclusive big_file (String.make (max_bytes + 1) ' ');
  expect_failure "oversize-manifest" "file-size-exceeded:" (fun () ->
    generate_evidence ~workspace:tmp_dir ~out_dir ~timestamp:"20260930-1116-"
      ~source_commit:"c1" ~source_change_id:"ch1" ~base_commit:"c0"
      ~manifest_rel:"big.json" ~risk_rel:"risk.json" ~active_receipt:""
      ~executions:[] ~holds:[]);

  (* 8. Empty and malformed timestamp rejection *)
  expect_failure "empty-timestamp" "invalid-timestamp-format" (fun () ->
    generate_evidence ~workspace:tmp_dir ~out_dir ~timestamp:""
      ~source_commit:"c1" ~source_change_id:"ch1" ~base_commit:"c0"
      ~manifest_rel:"manifest.json" ~risk_rel:"risk.json" ~active_receipt:""
      ~executions:[] ~holds:[]);
  expect_failure "malformed-timestamp" "invalid-timestamp-format" (fun () ->
    generate_evidence ~workspace:tmp_dir ~out_dir ~timestamp:"bad-ts"
      ~source_commit:"c1" ~source_change_id:"ch1" ~base_commit:"c0"
      ~manifest_rel:"manifest.json" ~risk_rel:"risk.json" ~active_receipt:""
      ~executions:[] ~holds:[]);

  (* 9. Output collision rejection *)
  expect_failure "output-collision" "output-collision:" (fun () ->
    generate_evidence ~workspace:tmp_dir ~out_dir ~timestamp:"20260930-1115-"
      ~source_commit:"c1" ~source_change_id:"ch1" ~base_commit:"c0"
      ~manifest_rel:"manifest.json" ~risk_rel:"risk.json" ~active_receipt:"/tmp/active.json"
      ~executions:["test-exec.json"] ~holds:["hold 1"]);

  (* 10. Actual CLI exit observation: verify CLI with bad timestamp exits non-zero *)
  let dev_null = Unix.openfile "/dev/null" [Unix.O_WRONLY] 0 in
  let cli_pid = Unix.create_process "ocaml"
    [|"ocaml"; "tools/ev02_governance/write_evidence.ml"; "--timestamp"; "bad-ts";
      "--source-commit"; "c1"; "--source-change-id"; "ch1"; "--base-commit"; "c0";
      "--manifest"; "manifest.json"; "--risk"; "risk.json"|]
    Unix.stdin dev_null dev_null in
  let _, cli_status = Unix.waitpid [] cli_pid in
  Unix.close dev_null;
  (match cli_status with
   | Unix.WEXITED code when code <> 0 -> ()
   | _ -> failwith "selftest failed: CLI did not exit non-zero on invalid timestamp");

  print_endline "PASS write_evidence selftest: bounded_regular/traversal/absolute/symlink/symlink_dir/symlink_out_dir/oversize/timestamp/collision/cli_exit"

let default_holds = [
  "No immutable 38-family source/adaptation manifest";
  "Current policy surface observation: 33 union names, 32/32/32/33 per surface";
  "Current KM gate entropy HOLD";
  "No EV02 candidate-bound runtime/formal keys or authenticated independent review";
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
    let source_commit = ref "" in
    let source_change_id = ref "" in
    let base_commit = ref "" in
    let manifest_rel = ref "" in
    let risk_rel = ref "" in
    let active_receipt = ref "" in
    let executions = ref [] in
    let holds = ref default_holds in
    let rec parse = function
      | [] -> ()
      | "--workspace" :: dir :: rest -> workspace := dir; parse rest
      | "--out-dir" :: dir :: rest -> out_dir := dir; parse rest
      | "--timestamp" :: ts :: rest -> timestamp := ts; parse rest
      | "--source-commit" :: commit :: rest -> source_commit := commit; parse rest
      | "--source-change-id" :: ch :: rest -> source_change_id := ch; parse rest
      | "--base-commit" :: commit :: rest -> base_commit := commit; parse rest
      | "--manifest" :: path :: rest -> manifest_rel := path; parse rest
      | "--risk" :: path :: rest -> risk_rel := path; parse rest
      | "--active-receipt" :: receipt :: rest -> active_receipt := receipt; parse rest
      | "--execution" :: exec :: rest -> executions := exec :: !executions; parse rest
      | arg :: _ -> failwith ("unknown argument: " ^ arg)
    in
    (match args with _ :: rest -> parse rest | [] -> ());
    if !source_commit = "" || !source_change_id = "" || !base_commit = "" || !manifest_rel = "" || !risk_rel = "" then
      failwith "usage: write_evidence.ml --source-commit COMMIT --source-change-id ID --base-commit COMMIT --manifest PATH --risk PATH [--workspace DIR] [--out-dir DIR] [--timestamp YYYYMMDD-HHSS-] [--active-receipt PATH] [--execution PATH ...]";
    if not (validate_timestamp !timestamp) then
      failwith "invalid timestamp format: must be YYYYMMDD-HHSS-";
    let out_path = generate_evidence ~workspace:!workspace ~out_dir:!out_dir ~timestamp:!timestamp
      ~source_commit:!source_commit ~source_change_id:!source_change_id ~base_commit:!base_commit
      ~manifest_rel:!manifest_rel ~risk_rel:!risk_rel ~active_receipt:!active_receipt
      ~executions:(List.rev !executions) ~holds:!holds in
    Printf.printf "Wrote evidence binding: %s\n" out_path
  end
