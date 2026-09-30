#use "topfind";;
#require "unix,yojson,cryptokit,mtime.clock.os";;

let ws = Sys.getcwd ()
let current_revision = ref ""

let monotonic_now () =
  Mtime_clock.now () |> Mtime.to_uint64_ns |> Int64.to_float |> fun ns -> ns /. 1_000_000_000.

let sha b =
  Cryptokit.hash_string (Cryptokit.Hash.sha256 ()) b |> Cryptokit.transform_string (Cryptokit.Hexa.encode ())

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

let resolve_jj () =
  let candidates = [
    Filename.concat ws "toolchains/nix-profile/bin/jj";
    "/home/an/NAS-setup/uos/toolchains/nix-profile/bin/jj";
  ] in
  match List.find_opt Sys.file_exists candidates with
  | Some p -> p
  | None -> failwith "jj toolchain not found"

let jj_exe = resolve_jj ()

type process_result = {
  status : Unix.process_status;
  stdout : string;
  stderr : string;
}

let run_bounded ~timeout ?(max_bytes = 16_777_216) (argv : string array) =
  let out_r, out_w = Unix.pipe ~cloexec:true () in
  let err_r, err_w = Unix.pipe ~cloexec:true () in
  let pid =
    let p = Unix.fork () in
    if p = 0 then (
      try
        ignore (Unix.setsid ());
        Unix.dup2 out_w Unix.stdout;
        Unix.dup2 err_w Unix.stderr;
        Unix.close out_w;
        Unix.close out_r;
        Unix.close err_w;
        Unix.close err_r;
        Unix.execv argv.(0) argv
      with _ -> Unix._exit 127
    ) else p
  in
  Unix.close out_w;
  Unix.close err_w;
  Unix.set_nonblock out_r;
  Unix.set_nonblock err_r;
  let child_status = ref None in
  let reap_child () =
    match !child_status with
    | Some _ -> true
    | None ->
        match Unix.waitpid [Unix.WNOHANG] pid with
        | p, status when p = pid ->
            child_status := Some status;
            true
        | _ -> false
  in
  let group_alive () =
    try Unix.kill (-pid) 0; true
    with Unix.Unix_error (Unix.ESRCH, _, _) -> false
       | Unix.Unix_error _ -> false
  in
  let stop_group () =
    (try Unix.kill (-pid) Sys.sigterm with _ -> ());
    let t0 = monotonic_now () in
    let rec loop tries =
      let _ = reap_child () in
      if not (group_alive ()) && Option.is_some !child_status then ()
      else if tries <= 0 || monotonic_now () -. t0 > 0.5 then (
        (try Unix.kill (-pid) Sys.sigkill with _ -> ());
        let kt0 = monotonic_now () in
        let rec kloop ktries =
          let _ = reap_child () in
          if not (group_alive ()) && Option.is_some !child_status then ()
          else if ktries <= 0 || monotonic_now () -. kt0 > 0.5 then ()
          else (ignore (Unix.select [] [] [] 0.01); kloop (ktries - 1))
        in
        kloop 10
      ) else (
        ignore (Unix.select [] [] [] 0.01);
        loop (tries - 1)
      )
    in
    loop 10;
    let _ = reap_child () in
    if Option.is_none !child_status then
      failwith (Printf.sprintf "child process %d not reaped within deadline" pid);
    if group_alive () then
      failwith (Printf.sprintf "process group %d still alive after SIGKILL" pid)
  in
  let out_buf = Buffer.create 4096 in
  let err_buf = Buffer.create 4096 in
  let out_open = ref true in
  let err_open = ref true in
  let t0 = monotonic_now () in
  let deadline = t0 +. timeout in
  let tmp = Bytes.create 65536 in
  try
    let rec pump () =
      if !out_open || !err_open then (
        let now = monotonic_now () in
        if now >= deadline then failwith "timeout";
        let remaining = deadline -. now in
        let readers = (if !out_open then [out_r] else []) @ (if !err_open then [err_r] else []) in
        let r_fds, _, _ = Unix.select readers [] [] remaining in
        if r_fds = [] then failwith "timeout"
        else (
          List.iter (fun fd ->
            if fd = out_r && !out_open then (
              let n =
                try Unix.read out_r tmp 0 65536
                with Unix.Unix_error ((Unix.EAGAIN | Unix.EWOULDBLOCK | Unix.EINTR), _, _) -> -1
              in
              if n = 0 then (Unix.close out_r; out_open := false)
              else if n > 0 then (
                if Buffer.length out_buf + n > max_bytes then failwith "output-limit";
                Buffer.add_subbytes out_buf tmp 0 n
              )
            ) else if fd = err_r && !err_open then (
              let n =
                try Unix.read err_r tmp 0 65536
                with Unix.Unix_error ((Unix.EAGAIN | Unix.EWOULDBLOCK | Unix.EINTR), _, _) -> -1
              in
              if n = 0 then (Unix.close err_r; err_open := false)
              else if n > 0 then (
                if Buffer.length err_buf + n > max_bytes then failwith "output-limit";
                Buffer.add_subbytes err_buf tmp 0 n
              )
            )
          ) r_fds;
          pump ()
        )
      )
    in
    pump ();
    let rec wait_child () =
      let now = monotonic_now () in
      if now >= deadline then failwith "timeout";
      if reap_child () then ()
      else (ignore (Unix.select [] [] [] 0.01); wait_child ())
    in
    wait_child ();
    stop_group ();
    let status = match !child_status with
      | Some s -> s
      | None -> failwith "child exit status missing"
    in
    { status; stdout = Buffer.contents out_buf; stderr = Buffer.contents err_buf }
  with exn ->
    let stop_exn =
      try stop_group (); None
      with e -> Some e
    in
    if !out_open then (try Unix.close out_r with _ -> ());
    if !err_open then (try Unix.close err_r with _ -> ());
    match stop_exn with
    | Some e -> raise e
    | None -> raise exn

let rec mkdir p =
  if not (Sys.file_exists p) then (
    mkdir (Filename.dirname p);
    try Unix.mkdir p 0o755 with Unix.Unix_error (Unix.EEXIST, _, _) -> ()
  ) else (
    let st = Unix.lstat p in
    if st.Unix.st_kind = Unix.S_LNK then failwith ("symlink directory refused: " ^ p)
  )

let write p b =
  mkdir (Filename.dirname p);
  if Sys.file_exists p then (
    let st = Unix.lstat p in
    if st.Unix.st_kind = Unix.S_LNK then failwith ("symlink destination refused: " ^ p)
  );
  let fd = Unix.openfile p [Unix.O_WRONLY; Unix.O_CREAT; Unix.O_EXCL; Unix.O_CLOEXEC] 0o600 in
  let c = Unix.out_channel_of_descr fd in
  Fun.protect ~finally:(fun () -> close_out_noerr c) (fun () -> output_string c b; flush c)

let records = ref []
let total_staged_bytes = ref 0
let total_staged_files = ref 0
let max_total_staged_bytes = 134_217_728
let max_total_staged_files = 5000

let copy a b =
  if !total_staged_files >= max_total_staged_files then failwith "stage-file-count-exceeded";
  let bytes = read_regular ~max_bytes:16_777_216 a in
  if !total_staged_bytes + String.length bytes > max_total_staged_bytes then failwith "stage-byte-quota-exceeded";
  total_staged_bytes := !total_staged_bytes + String.length bytes;
  total_staged_files := !total_staged_files + 1;
  write b bytes;
  records := `Assoc [
    "source", `String a;
    "staged", `String b;
    "sha256", `String (sha bytes);
    "bytes", `Int (String.length bytes);
  ] :: !records

let total_tree_entries = ref 0
let max_tree_entries = 10_000

let rec tree depth a b =
  if depth > 8 then failwith ("stage-directory-depth-exceeded:" ^ a);
  let st = Unix.lstat a in
  match st.Unix.st_kind with
  | Unix.S_LNK -> failwith ("symlink refused in tree: " ^ a)
  | Unix.S_REG -> copy a b
  | Unix.S_DIR ->
      let d = Unix.opendir a in
      let entries = ref [] in
      let rec read_entries () =
        incr total_tree_entries;
        if !total_tree_entries > max_tree_entries then failwith ("stage-total-entries-exceeded:" ^ a);
        match Unix.readdir d with
        | "." | ".." -> read_entries ()
        | entry -> entries := entry :: !entries; read_entries ()
        | exception End_of_file -> ()
      in
      Fun.protect ~finally:(fun () -> Unix.closedir d) (fun () -> read_entries ());
      List.iter (fun n ->
        tree (depth + 1) (Filename.concat a n) (Filename.concat b n)
      ) (List.sort String.compare !entries)
  | _ -> failwith ("nonregular input " ^ a)

let candidate path dest =
  if !total_staged_files >= max_total_staged_files then failwith "stage-file-count-exceeded";
  let res =
    run_bounded ~timeout:30.0 [|
      jj_exe;
      "--ignore-working-copy";
      "file";
      "show";
      "-r";
      "commit_id(\"" ^ !current_revision ^ "\")";
      "root:" ^ path;
    |]
  in
  match res.status with
  | Unix.WEXITED 0 ->
      let bytes = res.stdout in
      if !total_staged_bytes + String.length bytes > max_total_staged_bytes then failwith "stage-byte-quota-exceeded";
      total_staged_bytes := !total_staged_bytes + String.length bytes;
      total_staged_files := !total_staged_files + 1;
      write dest bytes;
      records := `Assoc [
        "source", `String ("candidate:" ^ !current_revision ^ ":" ^ path);
        "staged", `String dest;
        "sha256", `String (sha bytes);
        "bytes", `Int (String.length bytes);
      ] :: !records
  | Unix.WEXITED code ->
      failwith (Printf.sprintf "candidate-fetch-failed: path=%s exit_code=%d stderr=%s" path code res.stderr)
  | Unix.WSIGNALED s ->
      failwith (Printf.sprintf "candidate-fetch-signaled: path=%s signal=%d stderr=%s" path s res.stderr)
  | Unix.WSTOPPED s ->
      failwith (Printf.sprintf "candidate-fetch-stopped: path=%s signal=%d" path s)

let verify_private_normalized_stage path =
  if not (String.starts_with ~prefix:"/tmp/" path) then
    failwith ("stage must be under /tmp: " ^ path);
  if String.contains path '\000' || String.contains path '\\' then
    failwith ("invalid characters in stage path: " ^ path);
  let parts = String.split_on_char '/' path in
  if List.mem "." parts || List.mem ".." parts || List.mem "" (List.tl parts) then
    failwith ("stage path not normalized: " ^ path);
  let rec check_ancestors cur = function
    | [] -> ()
    | p :: rest ->
        let next = if cur = "/" then "/" ^ p else cur ^ "/" ^ p in
        if Sys.file_exists next then (
          let st = Unix.lstat next in
          if st.Unix.st_kind = Unix.S_LNK then
            failwith ("stage path contains symlink ancestor: " ^ next)
        );
        check_ancestors next rest
  in
  check_ancestors "/" (List.filter (fun s -> s <> "") parts)

let run_selftest () =
  Printf.printf "=== ev86_music_stage selftest ===\n";
  (* Test 1: verify_private_normalized_stage path validation *)
  let invalid_paths = [
    "/var/tmp/stage";
    "/tmp/../var/stage";
    "/tmp/./stage";
    "/tmp/foo//bar";
    "/tmp/stage\000bad";
    "/tmp/stage\\bad";
  ] in
  List.iter (fun p ->
    match verify_private_normalized_stage p with
    | () -> failwith ("expected refusal for invalid path: " ^ p)
    | exception Failure _ -> ()
  ) invalid_paths;
  Printf.printf "PASS: verify_private_normalized_stage invalid path refusals\n";

  (* Test 2: root directory creation refuses EEXIST *)
  let temp_test_dir = Filename.temp_file "ev86_stage_test_" "" in
  Unix.unlink temp_test_dir;
  Unix.mkdir temp_test_dir 0o700;
  let eexist_refused =
    try
      (try Unix.mkdir temp_test_dir 0o700
       with Unix.Unix_error (Unix.EEXIST, _, _) ->
         failwith ("stage directory already exists (refuse unowned root): " ^ temp_test_dir));
      false
    with Failure msg when String.starts_with ~prefix:"stage directory already exists" msg ->
      true
  in
  Unix.rmdir temp_test_dir;
  if not eexist_refused then failwith "root creation failed to refuse EEXIST";
  Printf.printf "PASS: root creation refuses EEXIST\n";

  (* Test 3: total_tree_entries bounds check *)
  let saved_total = !total_tree_entries in
  total_tree_entries := max_tree_entries + 1;
  let test_dir = Filename.temp_file "ev86_tree_test_" "" in
  Unix.unlink test_dir;
  Unix.mkdir test_dir 0o700;
  let entries_bounded =
    try
      tree 0 test_dir (test_dir ^ "_dest");
      false
    with Failure msg when String.starts_with ~prefix:"stage-total-entries-exceeded" msg ->
      true
  in
  Unix.rmdir test_dir;
  total_tree_entries := saved_total;
  if not entries_bounded then failwith "tree failed to enforce max_tree_entries bound";
  Printf.printf "PASS: tree enforces global max_tree_entries bound\n";

  (* Test 4: run_bounded handles exit codes and stdout/stderr separation *)
  let res_echo = run_bounded ~timeout:5.0 [| "/bin/sh"; "-c"; "printf hello; printf err >&2; exit 0" |] in
  assert (res_echo.status = Unix.WEXITED 0);
  assert (res_echo.stdout = "hello");
  assert (res_echo.stderr = "err");
  Printf.printf "PASS: run_bounded stdout/stderr separation\n";

  (* Test 5: run_bounded nonzero exit code is preserved *)
  let res_err = run_bounded ~timeout:5.0 [| "/bin/sh"; "-c"; "printf failed >&2; exit 42" |] in
  assert (res_err.status = Unix.WEXITED 42);
  assert (res_err.stderr = "failed");
  Printf.printf "PASS: run_bounded nonzero exit code preserved\n";

  (* Test 6: run_bounded timeout kills process and raises timeout *)
  let timed_out =
    try
      let _ = run_bounded ~timeout:0.2 [| "/bin/sh"; "-c"; "sleep 10" |] in
      false
    with Failure msg when msg = "timeout" -> true
  in
  if not timed_out then failwith "expected timeout exception";
  Printf.printf "PASS: run_bounded timeout kills process group and raises timeout\n";

  (* Test 7: stop_group cleans up background process group descendants *)
  let background_group_killed =
    let res = run_bounded ~timeout:2.0 [| "/bin/sh"; "-c"; "sleep 10 >/dev/null 2>&1 & echo leader_done; exit 0" |] in
    assert (res.status = Unix.WEXITED 0);
    assert (String.trim res.stdout = "leader_done");
    true
  in
  if not background_group_killed then failwith "background process group test failed";
  Printf.printf "PASS: stop_group cleans up background process group descendants\n";

  Printf.printf "ALL ev86_music_stage selftests passed\n";
  exit 0

let () =
  if Array.length Sys.argv >= 2 && Sys.argv.(1) = "--selftest" then
    run_selftest ();
  if Array.length Sys.argv <> 3 then (
    Printf.eprintf "Usage: %s <revision-commit-id> <stage-dir> | --selftest\n" Sys.argv.(0);
    exit 1
  );
  let revision = Sys.argv.(1) in
  let stage = Sys.argv.(2) in
  current_revision := revision;
  verify_private_normalized_stage stage;
  if Sys.file_exists stage then
    failwith "fresh private full package required";
  if String.length revision <> 40 || not (String.for_all (fun c -> (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f')) revision) then
    failwith "full commit ID required";
  (try Unix.mkdir stage 0o700
   with Unix.Unix_error (Unix.EEXIST, _, _) ->
     failwith ("stage directory already exists (refuse unowned root): " ^ stage)
      | Unix.Unix_error (e, _, _) ->
     failwith ("failed to create stage root: " ^ stage ^ ": " ^ Unix.error_message e));
  List.iter (fun p -> candidate ("apps/indrajaal_gleam_web/src/" ^ p) (stage ^ "/full-package/src/" ^ p))
    ["indrajaal_gleam_web.gleam"; "indrajaal_gleam_web/types.gleam"; "indrajaal_web_ffi.erl"; "uos_web_runtime_ffi.erl"; "indrajaal/runtime_identity.gleam"; "indrajaal/ecology_service.gleam"; "indrajaal/ecology_http.gleam"; "indrajaal/homeostasis_http.gleam"; "indrajaal/music_files.gleam"];
  candidate "apps/indrajaal_gleam_web/gleam.toml" (stage ^ "/full-package/gleam.toml");
  List.iter (fun p -> candidate ("apps/indrajaal_gleam_web/test/" ^ p) (stage ^ "/full-package/test/" ^ p))
    ["music_files_test.gleam"; "music_http_probe.gleam"; "document_render_contract_test.gleam"];
  List.iter (fun p -> candidate p (stage ^ "/content/" ^ p))
    ["docs/music/20260907-1052-swarm-durga-player.md"; "docs/music/20260907-1145-cybernetic-raga-durga-and-22-shruti-studio.md"; "generated/20260907-1100-uos-hive-sings-yaman-teentaal.wav"; "generated/20260907-1230-uos-hive-sings-full-mix.wav"];
  let lib = Filename.concat ws "apps/indrajaal_gleam_web/build/dev/erlang" in
  if Sys.file_exists lib then (
    let st = Unix.lstat lib in
    if st.Unix.st_kind = Unix.S_LNK then failwith ("symlink refused in lib: " ^ lib);
    if st.Unix.st_kind = Unix.S_DIR then (
      let d = Unix.opendir lib in
      let entries = ref [] in
      let rec read_entries () =
        incr total_tree_entries;
        if !total_tree_entries > max_tree_entries then failwith ("stage-total-entries-exceeded:" ^ lib);
        match Unix.readdir d with
        | "." | ".." -> read_entries ()
        | entry -> entries := entry :: !entries; read_entries ()
        | exception End_of_file -> ()
      in
      Fun.protect ~finally:(fun () -> Unix.closedir d) (fun () -> read_entries ());
      List.iter (fun n ->
        let p = Filename.concat lib n in
        let st_p = Unix.lstat p in
        if st_p.Unix.st_kind = Unix.S_LNK then failwith ("symlink refused in lib dependency: " ^ p);
        if n <> "indrajaal_gleam_web" && st_p.Unix.st_kind = Unix.S_DIR then
          List.iter (fun sub ->
            let sp = Filename.concat p sub in
            if Sys.file_exists sp then tree 0 sp (stage ^ "/full-lib/" ^ n ^ "/" ^ sub)
          ) ["_gleam_artefacts"; "ebin"]
      ) (List.sort String.compare !entries)
    )
  );
  write (stage ^ "/full-bindings.json") (Yojson.Safe.pretty_to_string (`Assoc [
    "scope", `String "Full changed Indrajaal module type-check against realized dependency artifacts; dependency source admission not implied";
    "records", `List (List.rev !records);
  ]));
  print_endline (string_of_int (List.length !records) ^ " bindings")

