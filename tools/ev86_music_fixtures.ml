#use "topfind";;
#require "unix,yojson,cryptokit";;

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

let string_contains ~sub s =
  let sub_len = String.length sub in
  let s_len = String.length s in
  if sub_len = 0 then true
  else if sub_len > s_len then false
  else
    let rec loop i =
      if i + sub_len > s_len then false
      else if String.sub s i sub_len = sub then true
      else loop (i + 1)
    in
    loop 0

let check_no_traversal label path =
  if String.contains path '\000' then failwith (label ^ " contains NUL byte");
  if String.contains path '\\' then failwith (label ^ " contains backslash");
  let segments = String.split_on_char '/' path in
  List.iter (fun seg ->
    if seg = ".." then failwith ("traversal .. forbidden in " ^ label ^ ": " ^ path)
  ) segments

let validate_stage_ancestors stage =
  check_no_traversal "stage" stage;
  if not (String.starts_with ~prefix:"/tmp/" stage) then
    failwith ("stage must be private /tmp directory: " ^ stage);
  let rec check_anc p =
    if p = "" || p = "/" || p = "." then ()
    else (
      check_anc (Filename.dirname p);
      let st = try Unix.lstat p with Unix.Unix_error (e, _, _) -> failwith ("stage ancestor unreadable: " ^ p ^ ": " ^ Unix.error_message e) in
      if st.Unix.st_kind = Unix.S_LNK then
        failwith ("symlink forbidden in stage: " ^ p);
      if st.Unix.st_kind <> Unix.S_DIR then
        failwith ("stage ancestor not directory: " ^ p);
      if p <> "/tmp" && st.Unix.st_uid <> Unix.getuid () then
        failwith ("stage ancestor not owned by current user: " ^ p)
    )
  in
  check_anc stage

let validate_source_ancestors path =
  check_no_traversal "source" path;
  let abs_path =
    if Filename.is_relative path then Filename.concat (Sys.getcwd ()) path
    else path
  in
  let rec check_anc p =
    if p = "" || p = "/" || p = "." then ()
    else (
      check_anc (Filename.dirname p);
      let st = try Unix.lstat p with Unix.Unix_error (e, _, _) -> failwith ("source ancestor unreadable: " ^ p ^ ": " ^ Unix.error_message e) in
      if st.Unix.st_kind = Unix.S_LNK then
        failwith ("symlink forbidden in source ancestor: " ^ p);
      if st.Unix.st_kind <> Unix.S_DIR then
        failwith ("source ancestor not directory: " ^ p)
    )
  in
  check_anc (Filename.dirname abs_path)

let rec mkdir_cases_sub root path =
  if not (String.starts_with ~prefix:root path) then
    failwith ("path outside cases root: " ^ path);
  check_no_traversal "cases subpath" path;
  if not (Sys.file_exists path) then (
    mkdir_cases_sub root (Filename.dirname path);
    try Unix.mkdir path 0o700 with Unix.Unix_error (Unix.EEXIST, _, _) -> ()
  );
  let st = Unix.lstat path in
  if st.Unix.st_kind = Unix.S_LNK then failwith ("symlink directory refused: " ^ path);
  if st.Unix.st_kind <> Unix.S_DIR then failwith ("expected directory: " ^ path);
  if st.Unix.st_uid <> Unix.getuid () then failwith ("cases directory not owned by current user: " ^ path)

let write_exclusive_file path content =
  check_no_traversal "destination file" path;
  (match Unix.lstat path with
   | exception Unix.Unix_error (Unix.ENOENT, _, _) -> ()
   | st ->
       if st.Unix.st_kind = Unix.S_LNK then failwith ("symlink destination refused: " ^ path);
       failwith ("exclusive write refused - file exists: " ^ path));
  let fd = Unix.openfile path [Unix.O_WRONLY; Unix.O_CREAT; Unix.O_EXCL; Unix.O_CLOEXEC] 0o600 in
  let c = Unix.out_channel_of_descr fd in
  Fun.protect ~finally:(fun () -> close_out_noerr c) (fun () -> output_string c content; flush c)

let write_exclusive root path content =
  mkdir_cases_sub root (Filename.dirname path);
  write_exclusive_file path content

let player = "docs/music/20260907-1052-swarm-durga-player.md"
let mix = "generated/20260907-1230-uos-hive-sings-full-mix.wav"

let generate_fixtures stage =
  validate_stage_ancestors stage;
  let content_dir = Filename.concat stage "content" in
  let root = Filename.concat content_dir "cases" in
  if Sys.file_exists root then failwith "fresh private cases required";
  let scope_path = Filename.concat stage "fixture-scope.json" in
  check_no_traversal "fixture scope" scope_path;
  (match Unix.lstat scope_path with
   | exception Unix.Unix_error (Unix.ENOENT, _, _) -> ()
   | st ->
       if st.Unix.st_kind = Unix.S_LNK then failwith ("symlink destination refused: " ^ scope_path);
       failwith ("exclusive write refused - file exists: " ^ scope_path));
  let player_source = Filename.concat content_dir player in
  validate_source_ancestors player_source;
  let source_st = try Unix.lstat player_source with Unix.Unix_error (e, _, _) ->
    failwith ("missing player source: " ^ player_source ^ ": " ^ Unix.error_message e) in
  if source_st.Unix.st_kind = Unix.S_LNK then failwith ("symlink forbidden in source: " ^ player_source);
  if source_st.Unix.st_kind <> Unix.S_REG then failwith ("not regular: " ^ player_source);
  if source_st.Unix.st_size > 2_097_152 then failwith ("source file size exceeds bound: " ^ player_source);
  if source_st.Unix.st_size <= 0 then failwith ("empty source file: " ^ player_source);

  let original = read_regular ~max_bytes:2_097_152 player_source in

  (* Create atomic owned cases root *)
  (try Unix.mkdir root 0o700 with Unix.Unix_error (Unix.EEXIST, _, _) -> failwith "fresh private cases required");
  let root_st = Unix.lstat root in
  if root_st.Unix.st_kind <> Unix.S_DIR || root_st.Unix.st_uid <> Unix.getuid () then
    failwith ("invalid cases root: " ^ root);

  let named n p = Filename.concat (Filename.concat root n) p in

  List.iter (fun n ->
    mkdir_cases_sub root (Filename.dirname (named n player))
  ) ["missing"; "symlink-file"; "directory"; "fifo"; "denied"; "zero-file"];

  write_exclusive root (named "exact-document" player) (original ^ String.make (2097152 - String.length original) ' ');
  write_exclusive root (named "oversize-document" player) (String.make 2097153 'x');
  write_exclusive root (named "denied" player) original;
  Unix.chmod (named "denied" player) 0o000;
  write_exclusive root (named "zero-file" player) "";
  Unix.mkdir (named "directory" player) 0o700;
  Unix.mkfifo (named "fifo" player) 0o600;
  Unix.symlink player_source (named "symlink-file" player);
  mkdir_cases_sub root (Filename.concat root "symlink-parent");
  Unix.symlink (Filename.concat content_dir "docs") (Filename.concat (Filename.concat root "symlink-parent") "docs");
  Unix.symlink content_dir (Filename.concat root "root-symlink");
  write_exclusive root (named "missing-studio" player) original;

  let a = "data:audio/mp3;base64," in
  write_exclusive root (named "invalid-base64" player) (a ^ "!\" " ^ a ^ "!\"");
  let fake = Cryptokit.transform_string (Cryptokit.Base64.encode_compact ()) (String.make 128 'x') in
  write_exclusive root (named "wrong-magic" player) (a ^ fake ^ "\" " ^ a ^ fake ^ "\"");
  write_exclusive root (named "duplicate-preview" player) (original ^ a ^ fake ^ "\"");
  write_exclusive root (named "single-preview" player) (a ^ fake ^ "\"");

  let wav bytes =
    let b = Bytes.make bytes '\000' in
    let put offset s = Bytes.blit_string s 0 b offset (String.length s) in
    let u16 i n = Bytes.set b i (Char.chr (n land 255)); Bytes.set b (i + 1) (Char.chr ((n lsr 8) land 255)) in
    let u32 i n = u16 i (n land 65535); u16 (i + 2) (n lsr 16) in
    put 0 "RIFF"; u32 4 (bytes - 8); put 8 "WAVEfmt "; u32 16 16; u16 20 1; u16 22 1;
    u32 24 22050; u32 28 44100; u16 32 2; u16 34 16; put 36 "data"; u32 40 (bytes - 44);
    Bytes.to_string b
  in
  write_exclusive root (named "exact-wav" mix) (wav 4194304);
  write_exclusive root (named "oversize-wav" mix) (String.make 4194305 'x');
  let bad = Bytes.of_string (wav 100) in
  Bytes.set bad 4 '\000';
  write_exclusive root (named "bad-wav-size" mix) (Bytes.to_string bad);

  let scope_json = Yojson.Safe.to_string (`Assoc [
    "scope", `String "Private read-refusal and exact-bound fixtures; zero-filled PCM is a structural fixture, no musical or playback evidence";
    "cases", `Int 18;
    "root", `String root
  ]) in
  write_exclusive_file scope_path scope_json;
  root

let rec remove_owned_tree path =
  match Unix.lstat path with
  | exception Unix.Unix_error (Unix.ENOENT, _, _) -> ()
  | st ->
      if st.Unix.st_kind = Unix.S_DIR then (
        (try Unix.chmod path 0o700 with _ -> ());
        let entries = Sys.readdir path in
        Array.iter (fun e -> remove_owned_tree (Filename.concat path e)) entries;
        Unix.rmdir path
      ) else (
        if st.Unix.st_kind <> Unix.S_LNK then (try Unix.chmod path 0o600 with _ -> ());
        Unix.unlink path
      )

let selftest () =
  print_endline "=== ev86_music_fixtures selftest ===";
  let tmp = Filename.temp_file "fixture-selftest-" "" in
  Sys.remove tmp;
  Unix.mkdir tmp 0o700;
  Fun.protect ~finally:(fun () -> remove_owned_tree tmp) (fun () ->
    let content = Filename.concat tmp "content" in
    Unix.mkdir content 0o700;
    let docs = Filename.concat content "docs" in
    Unix.mkdir docs 0o700;
    let music_dir = Filename.concat docs "music" in
    Unix.mkdir music_dir 0o700;
    let player_file = Filename.concat content player in
    let c = open_out_bin player_file in
    output_string c "# Test Player Document\n";
    close_out c;

    (* 1. Positive fixture generation *)
    let root = generate_fixtures tmp in
    if not (Sys.file_exists (Filename.concat tmp "fixture-scope.json")) then
      failwith "selftest failed: fixture-scope.json missing";
    if not (Sys.file_exists (Filename.concat root "exact-document")) then
      failwith "selftest failed: exact-document missing";
    print_endline "PASS: positive fixture generation";

    (* 2. Collision negative: rerun on existing root *)
    let collision_refused =
      try ignore (generate_fixtures tmp); false
      with Failure msg when String.starts_with ~prefix:"fresh private cases required" msg -> true
    in
    if not collision_refused then failwith "selftest failed: collision on existing root not refused";
    print_endline "PASS: root collision refused";

    (* Clean cases to test other falsifiers *)
    remove_owned_tree root;
    (try Unix.unlink (Filename.concat tmp "fixture-scope.json") with _ -> ());

    (* 3. Traversal negative *)
    let trav_refused =
      try ignore (generate_fixtures (tmp ^ "/../traversal")); false
      with Failure msg when string_contains ~sub:"traversal" msg -> true
    in
    if not trav_refused then failwith "selftest failed: traversal .. in stage not refused";
    print_endline "PASS: traversal .. in stage refused";

    (* 4. Symlink stage negative *)
    let sym_stage = Filename.temp_file "sym-stage-" "" in
    Sys.remove sym_stage;
    Unix.symlink tmp sym_stage;
    let sym_refused =
      Fun.protect ~finally:(fun () -> try Unix.unlink sym_stage with _ -> ()) (fun () ->
        try ignore (generate_fixtures sym_stage); false
        with Failure msg when string_contains ~sub:"symlink forbidden" msg -> true
      )
    in
    if not sym_refused then failwith "selftest failed: symlink stage not refused";
    print_endline "PASS: symlink stage refused";

    (* 5. Symlink source negative *)
    Unix.unlink player_file;
    let real_player = Filename.concat music_dir "real.md" in
    let c = open_out_bin real_player in output_string c "# Real\n"; close_out c;
    Unix.symlink real_player player_file;
    let sym_src_refused =
      try ignore (generate_fixtures tmp); false
      with Failure msg when string_contains ~sub:"symlink forbidden in source" msg -> true
    in
    Unix.unlink player_file;
    Unix.unlink real_player;
    if not sym_src_refused then failwith "selftest failed: symlink source not refused";
    print_endline "PASS: symlink source refused";

    (* 6. Non-regular FIFO source negative *)
    Unix.mkfifo player_file 0o600;
    let fifo_refused =
      Fun.protect ~finally:(fun () -> try Unix.unlink player_file with _ -> ()) (fun () ->
        try ignore (generate_fixtures tmp); false
        with Failure msg when string_contains ~sub:"not regular" msg -> true
      )
    in
    if not fifo_refused then failwith "selftest failed: non-regular source not refused";
    print_endline "PASS: non-regular source refused";

    (* 7. Oversize source negative *)
    let c = open_out_bin player_file in
    output_string c (String.make 2097153 'y');
    close_out c;
    let oversize_refused =
      Fun.protect ~finally:(fun () -> try Unix.unlink player_file with _ -> ()) (fun () ->
        try ignore (generate_fixtures tmp); false
        with Failure msg when string_contains ~sub:"source file size exceeds bound" msg -> true
      )
    in
    if not oversize_refused then failwith "selftest failed: oversize source not refused";
    print_endline "PASS: oversize source refused";

    (* 8. Exclusive write refusal negative *)
    let test_file = Filename.concat tmp "exclusive_test.txt" in
    write_exclusive tmp test_file "hello";
    let overwrite_refused =
      try write_exclusive tmp test_file "overwrite"; false
      with Failure msg when string_contains ~sub:"exclusive write refused" msg -> true
    in
    if not overwrite_refused then failwith "selftest failed: exclusive write overwrite not refused";
    print_endline "PASS: exclusive write refused victim overwrite";

    (* 9. Regular collision on fixture-scope.json preflight: victim bytes unchanged *)
    let victim_scope = Filename.concat tmp "fixture-scope.json" in
    let c = open_out_bin victim_scope in output_string c "victim-scope-bytes"; close_out c;
    let victim_refused =
      try ignore (generate_fixtures tmp); false
      with Failure msg when string_contains ~sub:"exclusive write refused" msg -> true
    in
    let scope_bytes = read_regular ~max_bytes:1000 victim_scope in
    Unix.unlink victim_scope;
    if not victim_refused || scope_bytes <> "victim-scope-bytes" then
      failwith "selftest failed: scope regular collision did not preserve victim bytes";
    print_endline "PASS: fixture-scope.json regular collision preserves victim bytes";

    (* 10. Symlink collision on fixture-scope.json preflight: victim bytes unchanged *)
    let target_file = Filename.concat tmp "victim_target.txt" in
    let c = open_out_bin target_file in output_string c "target-victim-bytes"; close_out c;
    Unix.symlink target_file victim_scope;
    let sym_victim_refused =
      try ignore (generate_fixtures tmp); false
      with Failure msg when string_contains ~sub:"symlink destination refused" msg -> true
    in
    let target_bytes = read_regular ~max_bytes:1000 target_file in
    Unix.unlink victim_scope;
    Unix.unlink target_file;
    if not sym_victim_refused || target_bytes <> "target-victim-bytes" then
      failwith "selftest failed: scope symlink collision did not preserve victim bytes";
    print_endline "PASS: fixture-scope.json symlink collision preserves victim bytes";

    (* 11. Parent-symlink source ancestor negative *)
    let parent_sym_root = Filename.concat tmp "anc_test" in
    Unix.mkdir parent_sym_root 0o700;
    let real_anc = Filename.concat parent_sym_root "real" in
    Unix.mkdir real_anc 0o700;
    let sym_anc = Filename.concat parent_sym_root "sym" in
    Unix.symlink real_anc sym_anc;
    let anc_src = Filename.concat sym_anc "player.md" in
    let c = open_out_bin (Filename.concat real_anc "player.md") in output_string c "# Test\n"; close_out c;
    let anc_sym_refused =
      try validate_source_ancestors anc_src; false
      with Failure msg when string_contains ~sub:"symlink forbidden in source ancestor" msg -> true
    in
    remove_owned_tree parent_sym_root;
    if not anc_sym_refused then failwith "selftest failed: parent-symlink source ancestor not refused";
    print_endline "PASS: parent-symlink source ancestor refused";

    (* 12. Direct exclusive write refusal on symlink *)
    let sym_victim_target = Filename.concat tmp "sym_target.txt" in
    let c = open_out_bin sym_victim_target in output_string c "target-bytes"; close_out c;
    let sym_victim_link = Filename.concat tmp "sym_link.txt" in
    Unix.symlink sym_victim_target sym_victim_link;
    let sym_overwrite_refused =
      try write_exclusive tmp sym_victim_link "overwrite"; false
      with Failure msg when string_contains ~sub:"symlink destination refused" msg -> true
    in
    let target_bytes_after = read_regular ~max_bytes:1000 sym_victim_target in
    Unix.unlink sym_victim_link;
    Unix.unlink sym_victim_target;
    if not sym_overwrite_refused || target_bytes_after <> "target-bytes" then
      failwith "selftest failed: exclusive write symlink overwrite not refused";
    print_endline "PASS: exclusive write refused victim symlink overwrite";

    print_endline "ALL ev86_music_fixtures selftests passed"
  )

let () =
  if Array.length Sys.argv < 2 then (
    prerr_endline "usage: ocaml tools/ev86_music_fixtures.ml <stage_dir> | --selftest";
    exit 1
  );
  if Sys.argv.(1) = "--selftest" then (
    selftest ();
    exit 0
  ) else (
    let stage = Sys.argv.(1) in
    let root = generate_fixtures stage in
    print_endline root
  )
