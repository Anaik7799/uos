#use "topfind";;
#require "yojson,cryptokit,mtime.clock.os";;
#load "unix.cma";;

exception Timeout
exception OutputLimit

type run_result = {
  exit_code : int;
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
  let r, w = Unix.pipe ~cloexec:true () in
  let start_mono = Mtime_clock.now () in
  let pid = Unix.fork () in
  if pid = 0 then begin
    try
      ignore (Unix.setsid ());
      Unix.close r;
      Unix.dup2 w Unix.stdout;
      Unix.dup2 w Unix.stderr;
      Unix.close w;
      let exe = argv.(0) in
      Unix.execvp exe argv
    with _ -> Unix._exit 127
  end;
  Unix.close w;
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
  let buf = Buffer.create (min max_bytes 4096) in
  let temp_bytes = Bytes.create 4096 in
  try
    let rec read_pump () =
      let now_mono = Mtime_clock.now () in
      let elapsed = Mtime.Span.to_float_ns (Mtime.span start_mono now_mono) /. 1e9 in
      if elapsed >= timeout then raise Timeout;
      let remaining = timeout -. elapsed in
      let readable, _, _ =
        try Unix.select [r] [] [] remaining
        with Unix.Unix_error (Unix.EINTR, _, _) -> ([], [], [])
      in
      if readable <> [] then begin
        let n = Unix.read r temp_bytes 0 (Bytes.length temp_bytes) in
        if n = 0 then () (* TRUE EOF: pipe closed *)
        else begin
          let cur_len = Buffer.length buf in
          if cur_len + n > max_bytes then begin
            let allowed = max 0 (max_bytes - cur_len) in
            if allowed > 0 then Buffer.add_subbytes buf temp_bytes 0 allowed;
            raise OutputLimit
          end else begin
            Buffer.add_subbytes buf temp_bytes 0 n;
            read_pump ()
          end
        end
      end else begin
        (* select returned empty or interrupted: keep looping until deadline or EOF *)
        read_pump ()
      end
    in
    read_pump ();
    (try Unix.close r with Unix.Unix_error _ -> ());
    (* Deadline monitored wait loop: bounds time through BOTH EOF and child exit *)
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
    { exit_code; output = Buffer.contents buf; timed_out = false; output_truncated = false; child_pid = pid }
  with
  | Timeout ->
      stop_group ();
      let _ = reap_child () in
      (try Unix.close r with Unix.Unix_error _ -> ());
      { exit_code = 124; output = Buffer.contents buf; timed_out = true; output_truncated = false; child_pid = pid }
  | OutputLimit ->
      stop_group ();
      let _ = reap_child () in
      (try Unix.close r with Unix.Unix_error _ -> ());
      { exit_code = 125; output = Buffer.contents buf; timed_out = false; output_truncated = true; child_pid = pid }
  | exn ->
      stop_group ();
      let _ = reap_child () in
      (try Unix.close r with Unix.Unix_error _ -> ());
      raise exn

type check = {
  id : string;
  expected_code : int;
  argv : string array;
}

let run_one ~out_dir ~timestamp check =
  let res = run_bounded check.argv in
  let output_filename = Printf.sprintf "%sev02-%s.out" timestamp check.id in
  let output_path = Filename.concat out_dir output_filename in
  let raw_empty = (res.output = "") in
  let stored_output = if raw_empty then "(no output)\n" else res.output in
  write_exclusive output_path stored_output;
  let control_pass = (res.exit_code = check.expected_code) in
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
    "output_sha256", `String (sha stored_output)
  ], control_pass

let execute_checks ~workspace ~out_dir ~timestamp ~source_commit checks =
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
  let doc =
    `Assoc [
      "schema", `String "uos.ev02-governance-checks/v1";
      "authority", `String "REPORT_ONLY";
      "admission", `String "NOT_GRANTED";
      "source_commit", `String source_commit;
      "all_control_pass", `Bool !all_pass;
      "rows", `List rows
    ] |> Yojson.Safe.pretty_to_string
  in
  let summary_file = Printf.sprintf "%sev02-governance-checks.json" timestamp in
  let summary_path = Filename.concat out_dir summary_file in
  write_exclusive summary_path (doc ^ "\n");
  !all_pass

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
    let fail_check = { id = "should-fail"; expected_code = 0; argv = [|"sh"; "-c"; "exit 42"|] } in
    let pass_check = { id = "should-pass"; expected_code = 0; argv = [|"sh"; "-c"; "exit 0"|] } in
    let result_failed = execute_checks ~workspace:tmp_dir ~out_dir:run_dir ~timestamp:"20260930-1115-" ~source_commit:"c1" [fail_check] in
    if result_failed <> false then failwith "selftest failed: execute_checks returned true on failing control";
    let result_passed = execute_checks ~workspace:tmp_dir ~out_dir:run_dir ~timestamp:"20260930-1116-" ~source_commit:"c2" [pass_check] in
    if result_passed <> true then failwith "selftest failed: execute_checks returned false on passing control";

    (* 11. Stored-output digest alignment control for silent and nonempty commands *)
    let digest_dir = Filename.concat tmp_dir "digest_verify" in
    make_dir digest_dir;
    let silent_check = { id = "silent-cmd"; expected_code = 0; argv = [|"sh"; "-c"; "exit 0"|] } in
    let nonempty_check = { id = "nonempty-cmd"; expected_code = 0; argv = [|"sh"; "-c"; "echo hello-digest-verify"|] } in
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

    print_endline "PASS run_checks selftest: monotonic_process_group/close_output_sleep/descendant_pipe/output_flood/reap/grandchild_kill/symlink_out_dir/chunked_read/collision/zero_progress/timestamp/digest_receipt_alignment"
  )

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
    let mapping = Filename.concat !workspace "governance/agents/policy/20260909-1836-ev02-current-directive-rule-amendment.json" in
    let km_script = Filename.concat !workspace "tools/km-gate" in
    let km_exe = Filename.concat !workspace "tools/km_provenance/_build/default/km_gate.exe" in
    let km_cmd args =
      if Sys.file_exists km_exe then Array.append [|km_exe|] args
      else Array.append [|"bash"; km_script|] args
    in
    let checks = [
      { id = "policy-selftest"; expected_code = 0; argv = [|ocamlrun; ocaml; policy; "--selftest"|] };
      { id = "policy-fixture-selftest"; expected_code = 0; argv = [|ocamlrun; ocaml; policy; "--fixture-selftest"|] };
      { id = "policy-observation"; expected_code = 1; argv = [|ocamlrun; ocaml; policy; "--observe"; !workspace|] };
      { id = "mapping-selftest"; expected_code = 0; argv = [|ocamlrun; ocaml; mapping_gate; "--selftest"|] };
      { id = "mapping-fixture-selftest"; expected_code = 0; argv = [|ocamlrun; ocaml; mapping_gate; "--fixture-selftest"|] };
      { id = "mapping-observation"; expected_code = 1; argv = [|ocamlrun; ocaml; mapping_gate; "--observe"; !workspace; mapping|] };
      { id = "km-gate"; expected_code = 0; argv = km_cmd [|"--gate"|] };
    ] in
    let all_pass = execute_checks ~workspace:!workspace ~out_dir:!out_dir ~timestamp:!timestamp ~source_commit:!source_commit checks in
    if not all_pass then exit 1 else exit 0
  end
