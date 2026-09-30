#use "topfind";;
#require "unix,yojson,cryptokit,str,mtime.clock.os";;

(* Execute only the post-receive checker extracted from the bound source text.
   The original HTTP driver's top-level socket/process setup is never evaluated. *)

type run_result = {
  exit_code : int;
  stdout : string;
  stderr : string;
  timed_out : bool;
  output_truncated : bool;
  child_pid : int;
}

let monotonic_now () =
  Mtime_clock.now () |> Mtime.to_uint64_ns |> Int64.to_float |> fun ns -> ns /. 1_000_000_000.

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

let check_no_traversal label path =
  if String.contains path '\000' then failwith (label ^ " contains NUL byte");
  if String.contains path '\\' then failwith (label ^ " contains backslash");
  let segments = String.split_on_char '/' path in
  List.iter (fun seg ->
    if seg = ".." then failwith ("traversal .. forbidden in " ^ label ^ ": " ^ path)
  ) segments

let validate_source_ancestors source_path =
  check_no_traversal "source path" source_path;
  let abs_path =
    if Filename.is_relative source_path then Filename.concat (Sys.getcwd ()) source_path
    else source_path
  in
  let rec check_anc p =
    if p = "" || p = "/" || p = "." then ()
    else (
      check_anc (Filename.dirname p);
      let st =
        try Unix.lstat p
        with Unix.Unix_error (e, _, _) ->
          failwith ("source ancestor unreadable: " ^ p ^ ": " ^ Unix.error_message e)
      in
      if st.Unix.st_kind = Unix.S_LNK then
        failwith ("symlink forbidden in source ancestor: " ^ p);
      if st.Unix.st_kind <> Unix.S_DIR then
        failwith ("source ancestor not directory: " ^ p)
    )
  in
  check_anc (Filename.dirname abs_path);
  abs_path

let write_exclusive path s =
  check_no_traversal "output destination" path;
  (match Unix.lstat path with
   | exception Unix.Unix_error (Unix.ENOENT, _, _) -> ()
   | st ->
       if st.Unix.st_kind = Unix.S_LNK then failwith ("output-symlink-refused:" ^ path);
       failwith ("output-collision:" ^ path));
  let fd = Unix.openfile path [Unix.O_WRONLY; Unix.O_CREAT; Unix.O_EXCL; Unix.O_CLOEXEC] 0o600 in
  let c = Unix.out_channel_of_descr fd in
  Fun.protect ~finally:(fun () -> close_out_noerr c) (fun () -> output_string c s; flush c)

let sha s = Cryptokit.hash_string (Cryptokit.Hash.sha256 ()) s |> Cryptokit.transform_string (Cryptokit.Hexa.encode ())
let find s part = Str.search_forward (Str.regexp_string part) s 0
let require p s = if not p then failwith s

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
        Unix.execvp argv.(0) argv
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
  let timed_out = ref false in
  let output_truncated = ref false in
  let tmp = Bytes.create 65536 in
  try
    let rec pump () =
      if !out_open || !err_open then (
        let now = monotonic_now () in
        if now >= deadline then (
          timed_out := true;
          stop_group ()
        ) else (
          let remaining = deadline -. now in
          let readers = (if !out_open then [out_r] else []) @ (if !err_open then [err_r] else []) in
          let r_fds, _, _ = Unix.select readers [] [] (min remaining 0.05) in
          if r_fds = [] then (
            if monotonic_now () >= deadline then (
              timed_out := true;
              stop_group ()
            ) else pump ()
          ) else (
            List.iter (fun fd ->
              if fd = out_r && !out_open then (
                let n =
                  try Unix.read out_r tmp 0 65536
                  with Unix.Unix_error ((Unix.EAGAIN | Unix.EWOULDBLOCK | Unix.EINTR), _, _) -> -1
                in
                if n = 0 then (Unix.close out_r; out_open := false)
                else if n > 0 then (
                  if Buffer.length out_buf + n > max_bytes then (
                    let allowed = max 0 (max_bytes - Buffer.length out_buf) in
                    if allowed > 0 then Buffer.add_subbytes out_buf tmp 0 allowed;
                    output_truncated := true;
                    stop_group ();
                    (try Unix.close out_r with _ -> ());
                    out_open := false
                  ) else Buffer.add_subbytes out_buf tmp 0 n
                )
              ) else if fd = err_r && !err_open then (
                let n =
                  try Unix.read err_r tmp 0 65536
                  with Unix.Unix_error ((Unix.EAGAIN | Unix.EWOULDBLOCK | Unix.EINTR), _, _) -> -1
                in
                if n = 0 then (Unix.close err_r; err_open := false)
                else if n > 0 then (
                  if Buffer.length err_buf + n > max_bytes then (
                    let allowed = max 0 (max_bytes - Buffer.length err_buf) in
                    if allowed > 0 then Buffer.add_subbytes err_buf tmp 0 allowed;
                    output_truncated := true;
                    stop_group ();
                    (try Unix.close err_r with _ -> ());
                    err_open := false
                  ) else Buffer.add_subbytes err_buf tmp 0 n
                )
              )
            ) r_fds;
            if not !timed_out && not !output_truncated then pump ()
          )
        )
      )
    in
    pump ();
    if not !timed_out && not !output_truncated then (
      let rec wait_child () =
        let now = monotonic_now () in
        if now >= deadline then (
          timed_out := true;
          stop_group ()
        ) else if reap_child () then ()
        else (ignore (Unix.select [] [] [] 0.01); wait_child ())
      in
      wait_child ()
    );
    if not !timed_out && not !output_truncated then stop_group ();
    let exit_code =
      if !timed_out then 124
      else if !output_truncated then 125
      else match !child_status with
        | Some (Unix.WEXITED n) -> n
        | Some (Unix.WSIGNALED s) -> 128 + s
        | Some (Unix.WSTOPPED s) -> 128 + s
        | None -> 127
    in
    if !out_open then (try Unix.close out_r with _ -> ());
    if !err_open then (try Unix.close err_r with _ -> ());
    { exit_code; stdout = Buffer.contents out_buf; stderr = Buffer.contents err_buf;
      timed_out = !timed_out; output_truncated = !output_truncated; child_pid = pid }
  with exn ->
    (try stop_group () with _ -> ());
    if !out_open then (try Unix.close out_r with _ -> ());
    if !err_open then (try Unix.close err_r with _ -> ());
    raise exn

let run_verification ?stage source_path =
  let abs_source = validate_source_ancestors source_path in
  let source = read_regular ~max_bytes:1_048_576 abs_source in
  let stage =
    match stage with
    | Some s -> s
    | None ->
        let s = Filename.temp_dir "ev86-capture-fixtures-" "" in
        Unix.chmod s 0o700;
        s
  in
  let verif = Filename.concat stage "verification.json" in
  check_no_traversal "verification report destination" verif;
  (match Unix.lstat verif with
   | exception Unix.Unix_error (Unix.ENOENT, _, _) -> ()
   | st ->
       if st.Unix.st_kind = Unix.S_LNK then failwith ("output-symlink-refused:" ^ verif);
       failwith ("output-collision:" ^ verif));
  let checker =
    if String.contains source '\000' then failwith "NUL in checker source"
    else try
      let start = find source "let check_response " and stop = find source "let check name " in
      String.sub source start (stop - start)
    with Not_found ->
      let start = find source "let check name method_ path expected mime=let raw=request method_ path in " in
      let start = start + String.length "let check name method_ path expected mime=let raw=request method_ path in " in
      let stop = find source "let ()=Fun.protect" in
      "let check_response name method_ path expected mime raw = " ^ String.sub source start (stop - start)
  in
  require (not (try ignore (find checker "request "); true with Not_found -> false))
    "request execution must not enter fixture projection";
  let prelude = "#use \"topfind\";;\n#require \"unix,yojson,cryptokit,str\";;\nlet run=" ^ Printf.sprintf "%S" stage ^ "\nlet public_base=\"http://nas-1.tail55d152.ts.net:4100\"\nlet require p s=if not p then failwith s\nlet write p b=let c=open_out_bin p in Fun.protect ~finally:(fun()->close_out_noerr c)(fun()->output_string c b)\nlet sha b=Cryptokit.hash_string(Cryptokit.Hash.sha256())b |> Cryptokit.transform_string(Cryptokit.Hexa.encode())\n" in
  let fixtures = {|
let read p=let c=open_in_bin p in Fun.protect ~finally:(fun()->close_in_noerr c)(fun()->really_input_string c(in_channel_length c))
let checks=ref []
let fixture name method_ raw expected mime should_reject =
 let rejected=try ignore(check_response name method_ "/fixture" expected mime raw);false with _->true in
 require(rejected=should_reject)(name^" validation outcome");
 let p=run^"/http-"^name^".response" in
 require(Sys.file_exists p)("EV86_CAPTURE_BEFORE_ASSERT:"^name);
 require(read p=raw)("EV86_CAPTURE_EXACT_BYTES:"^name);
 checks:=`Assoc["case",`String name;"raw_sha256",`String(sha raw);"rejected",`Bool rejected]::!checks
let ()=
 fixture "wrong-status" "GET" "HTTP/1.1 200 OK\r\ncontent-length: 3\r\n\r\na\000b" 404 None true;
 fixture "missing-separator" "GET" "malformed-response\000" 404 None true;
 fixture "malformed-status" "GET" "not-HTTP\r\ncontent-length: 0\r\n\r\n" 404 None true;
 fixture "wrong-mime" "GET" "HTTP/1.1 404 Missing\r\ncontent-length: 3\r\ncontent-type: other\r\n\r\nfoo" 404 (Some "text/plain") true;
 fixture "wrong-length" "GET" "HTTP/1.1 404 Missing\r\ncontent-length: 9\r\n\r\nfoo" 404 None true;
 fixture "head-body" "HEAD" "HTTP/1.1 404 Missing\r\ncontent-length: 3\r\n\r\nfoo" 404 None true;
 fixture "malformed-content-length" "GET" "HTTP/1.1 404 Missing\r\ncontent-length: notanumber\r\n\r\nfoo" 404 None true;
 fixture "player" "GET" "HTTP/1.1 200 OK\r\ncontent-length: 12\r\ncontent-type: text/html; charset=utf-8\r\n\r\nHello World!" 200 (Some "text/html; charset=utf-8") true;
 fixture "player" "GET" "HTTP/1.1 200 OK\r\ncontent-length: 44\r\ncontent-type: text/html; charset=utf-8\r\n\r\n<audio controls><script>alert(1)</script></audio>" 200 (Some "text/html; charset=utf-8") true;
 fixture "player" "GET" "HTTP/1.1 200 OK\r\ncontent-length: 47\r\ncontent-type: text/html; charset=utf-8\r\n\r\n<audio controls src='http://evil.com/media/music/'>" 200 (Some "text/html; charset=utf-8") true;
 fixture "mp3" "GET" "HTTP/1.1 200 OK\r\ncontent-length: 4\r\ncontent-type: audio/mpeg\r\n\r\nbad!" 200 (Some "audio/mpeg") true;
 fixture "wav" "GET" "HTTP/1.1 200 OK\r\ncontent-length: 4\r\ncontent-type: audio/wav\r\n\r\nbad!" 200 (Some "audio/wav") true;
 fixture "valid" "GET" "HTTP/1.1 404 Missing\r\ncontent-length: 3\r\ncontent-type: text/plain\r\n\r\nfoo" 404 (Some "text/plain") false;
 Yojson.Safe.to_file(run^"/checks.json")(`List(List.rev!checks)); print_endline "PASS 13 local static-response capture fixtures"
|} in
  let projected = prelude ^ checker ^ fixtures in
  let test = Filename.concat stage "capture_fixture.ml" in
  write_exclusive test projected;
  let ocamlrun =
    let p = Filename.concat (Sys.getcwd ()) "toolchains/opam-ocaml/bin/ocamlrun" in
    if Sys.file_exists p then p else "ocamlrun"
  in
  let ocaml =
    let p = Filename.concat (Sys.getcwd ()) "toolchains/opam-ocaml/bin/ocaml" in
    if Sys.file_exists p then p else "ocaml"
  in
  let args = [| ocamlrun; ocaml; test |] in
  let res = run_bounded ~timeout:10.0 args in
  let stdout_file = Filename.concat stage "stdout.txt" in
  write_exclusive stdout_file res.stdout;
  let stderr_file = Filename.concat stage "stderr.txt" in
  write_exclusive stderr_file res.stderr;
  let report = `Assoc [
    "scope", `String "Post-receive source projection and local static response fixtures only; no driver setup, HTTP request, listener or live effect";
    "source_path", `String source_path;
    "source_sha256", `String (sha source);
    "checker_sha256", `String (sha checker);
    "projection_sha256", `String (sha projected);
    "stage", `String stage;
    "exit_code", `Int res.exit_code;
    "timed_out", `Bool res.timed_out;
    "output_truncated", `Bool res.output_truncated;
    "stdout", `String res.stdout;
    "stderr", `String res.stderr;
  ] in
  let report_str = Yojson.Safe.to_string report in
  write_exclusive verif report_str;
  print_endline verif;
  print_string res.stdout;
  if res.exit_code <> 0 then exit res.exit_code else ()

let rec remove_tree path =
  match Unix.lstat path with
  | exception Unix.Unix_error (Unix.ENOENT, _, _) -> ()
  | st ->
      if st.Unix.st_kind = Unix.S_DIR then (
        (try Unix.chmod path 0o700 with _ -> ());
        let entries = Sys.readdir path in
        Array.iter (fun e -> remove_tree (Filename.concat path e)) entries;
        Unix.rmdir path
      ) else (
        (try Unix.chmod path 0o600 with _ -> ());
        Unix.unlink path
      )

let selftest () =
  print_endline "=== test_ev86_capture selftest ===";
  (* 1. Falsifier nonzero: child exit status preserved *)
  let s_res = run_bounded ~timeout:2.0 [|"sh"; "-c"; "exit 42"|] in
  if s_res.exit_code <> 42 || s_res.timed_out then
    failwith (Printf.sprintf "selftest failed: nonzero exit code not preserved (code %d)" s_res.exit_code);
  print_endline "PASS: nonzero exit code preserved";

  (* 2. Falsifier output flood *)
  let b_res = run_bounded ~timeout:2.0 ~max_bytes:500 [|"sh"; "-c"; "while true; do echo -n '1234567890'; done"|] in
  if not b_res.output_truncated || b_res.exit_code <> 125 || String.length b_res.stdout <> 500 then
    failwith (Printf.sprintf "selftest failed: output flood (code %d, len %d, trunc %b)"
      b_res.exit_code (String.length b_res.stdout) b_res.output_truncated);
  print_endline "PASS: output flood truncated and stopped";

  (* Stable open-FD count across repeated floods *)
  let count_open_fds () =
    try
      let entries = Sys.readdir "/proc/self/fd" in
      Array.length entries
    with _ -> -1
  in
  let fds_initial = count_open_fds () in
  for _ = 1 to 5 do
    let r = run_bounded ~timeout:2.0 ~max_bytes:500 [|"sh"; "-c"; "while true; do echo -n '1234567890'; done"|] in
    if not r.output_truncated || r.exit_code <> 125 then
      failwith "selftest failed: repeated output flood did not truncate";
  done;
  let fds_after = count_open_fds () in
  if fds_initial > 0 && fds_after <> fds_initial then
    failwith (Printf.sprintf "selftest failed: open FD leak across repeated floods (before=%d, after=%d)" fds_initial fds_after);
  print_endline "PASS: stable open-FD count across repeated floods";

  (* 3. Falsifier close output-sleep *)
  let c_res = run_bounded ~timeout:0.05 [|"sh"; "-c"; "exec 1>&-; exec 2>&-; sleep 5"|] in
  if not c_res.timed_out || c_res.exit_code <> 124 then
    failwith (Printf.sprintf "selftest failed: close output-sleep timeout not detected (code %d)" c_res.exit_code);
  print_endline "PASS: close output-sleep timeout detected";

  (* 4. Falsifier descendant retains pipe/ignores TERM after leader exit *)
  let d_res = run_bounded ~timeout:0.1 [|"sh"; "-c"; "(trap '' TERM; sleep 30 &); sleep 0.001"|] in
  if not d_res.timed_out || d_res.exit_code <> 124 then
    failwith (Printf.sprintf "selftest failed: descendant retaining pipe not terminated (code %d)" d_res.exit_code);
  print_endline "PASS: descendant retaining pipe terminated with group";

  (* 5. Falsifier output collision *)
  let tmp = Filename.temp_file "collision-" "" in
  Sys.remove tmp;
  write_exclusive tmp "hello";
  let collision_refused =
    try write_exclusive tmp "overwrite"; false
    with Failure msg when String.starts_with ~prefix:"output-collision:" msg -> true
  in
  (try Unix.unlink tmp with _ -> ());
  if not collision_refused then failwith "selftest failed: output collision not refused";
  print_endline "PASS: output collision refused";

  (* 6. Falsifier output symlink destination refused and victim target preserved *)
  let tmp_tgt = Filename.temp_file "sym-victim-" "" in
  let c = open_out_bin tmp_tgt in output_string c "victim-target-bytes"; close_out c;
  let tmp_sym = Filename.temp_file "sym-dest-" "" in
  Sys.remove tmp_sym;
  Unix.symlink tmp_tgt tmp_sym;
  let sym_write_refused =
    try write_exclusive tmp_sym "overwrite"; false
    with Failure msg when String.starts_with ~prefix:"output-symlink-refused:" msg -> true
  in
  let tgt_bytes = read_regular ~max_bytes:1000 tmp_tgt in
  Unix.unlink tmp_sym;
  Unix.unlink tmp_tgt;
  if not sym_write_refused || tgt_bytes <> "victim-target-bytes" then
    failwith "selftest failed: symlink write refusal did not preserve victim target";
  print_endline "PASS: output symlink destination refused and victim target preserved";

  (* 7. Falsifier source path traversal .. and NUL rejected *)
  let trav_refused =
    try ignore (validate_source_ancestors "foo/../bar"); false
    with Failure msg when String.starts_with ~prefix:"traversal .. forbidden" msg -> true
  in
  let nul_refused =
    try ignore (validate_source_ancestors "foo\000bar"); false
    with Failure msg when String.starts_with ~prefix:"source path contains NUL byte" msg -> true
  in
  if not trav_refused || not nul_refused then
    failwith "selftest failed: traversal or NUL in source path not rejected";
  print_endline "PASS: source path traversal .. and NUL rejected";

  (* 8. Falsifier parent-symlink source ancestor refused *)
  let parent_tmp = Filename.temp_dir "parent-sym-test-" "" in
  let real_sub = Filename.concat parent_tmp "real" in
  Unix.mkdir real_sub 0o700;
  let dummy_src = Filename.concat real_sub "source.ml" in
  let c = open_out_bin dummy_src in output_string c "let x = 1\n"; close_out c;
  let link_sub = Filename.concat parent_tmp "link" in
  Unix.symlink real_sub link_sub;
  let parent_sym_refused =
    try ignore (validate_source_ancestors (Filename.concat link_sub "source.ml")); false
    with Failure msg when String.starts_with ~prefix:"symlink forbidden in source ancestor:" msg -> true
  in
  remove_tree parent_tmp;
  if not parent_sym_refused then
    failwith "selftest failed: parent-symlink source ancestor not refused";
  print_endline "PASS: parent-symlink source ancestor refused";

  (* 9. Falsifier report path regular collision refuses and preserves sentinel bytes *)
  let col_stage = Filename.temp_dir "report-reg-col-" "" in
  let col_verif = Filename.concat col_stage "verification.json" in
  let c = open_out_bin col_verif in output_string c "sentinel-report-bytes"; close_out c;
  let rep_col_refused =
    try run_verification ~stage:col_stage "tools/ev86_music_http.ml"; false
    with Failure msg when String.starts_with ~prefix:"output-collision:" msg -> true
  in
  let verif_bytes = read_regular ~max_bytes:1000 col_verif in
  remove_tree col_stage;
  if not rep_col_refused || verif_bytes <> "sentinel-report-bytes" then
    failwith "selftest failed: report regular collision did not preserve sentinel bytes";
  print_endline "PASS: report path regular collision refuses and preserves sentinel bytes";

  (* 10. Falsifier report path symlink collision refuses and preserves sentinel bytes *)
  let sym_stage = Filename.temp_dir "report-sym-col-" "" in
  let sym_target = Filename.temp_file "report-sym-target-" "" in
  let c = open_out_bin sym_target in output_string c "target-sentinel-bytes"; close_out c;
  let sym_verif = Filename.concat sym_stage "verification.json" in
  Unix.symlink sym_target sym_verif;
  let rep_sym_refused =
    try run_verification ~stage:sym_stage "tools/ev86_music_http.ml"; false
    with Failure msg when String.starts_with ~prefix:"output-symlink-refused:" msg -> true
  in
  let target_bytes = read_regular ~max_bytes:1000 sym_target in
  remove_tree sym_stage;
  Unix.unlink sym_target;
  if not rep_sym_refused || target_bytes <> "target-sentinel-bytes" then
    failwith "selftest failed: report symlink collision did not preserve sentinel bytes";
  print_endline "PASS: report path symlink collision refuses and preserves sentinel bytes";

  print_endline "ALL test_ev86_capture selftests passed"

let () =
  if Array.length Sys.argv < 2 then (
    prerr_endline "usage: ocaml tools/test_ev86_capture.ml <source_path> | --selftest";
    exit 1
  );
  if Sys.argv.(1) = "--selftest" then (
    selftest ();
    exit 0
  ) else (
    run_verification Sys.argv.(1)
  )
