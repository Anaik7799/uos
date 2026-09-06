#!/usr/bin/env -S opam exec -- ocaml
#use "./tests/acceptance/process_supervisor.ml";;

(* Acceptance tests for the bounded Linux subprocess supervisor.
   Each case drives a real child process; the production changes caught are:
   omitted stream draining, exec exceptions escaping, missing TERM/KILL, failure
   to sweep a surviving process group, lost per-stream quota enforcement, and
   acceptance of unsafe limits. *)

let fail name message = failwith (name ^ ": " ^ message)
let assert_true name value = if not value then fail name "assertion failed"

let short = {
  timeout_ms = 1_500;
  stdout_limit = 256;
  stderr_limit = 256;
  term_grace_ms = 100;
}

let shell script = ["/bin/sh"; "-c"; script]

let detached_sleep_command pid_file ready_file =
  let detached =
    "exec 1>&- 2>&-; printf %s \"$$\" > " ^ Filename.quote pid_file ^
    "; read -r _ _ _ _ pgrp session _ < /proc/self/stat; printf '%s %s' \"$pgrp\" \"$session\" > " ^
    Filename.quote ready_file ^ "; sleep 30"
  in
  "setsid /bin/sh -c " ^ Filename.quote detached ^
  " & child=$!; while [ ! -f " ^ Filename.quote ready_file ^ " ]; do sleep 0.01; done"

let is_gone pid =
  match Unix.kill pid 0 with
  | () -> false
  | exception Unix.Unix_error (Unix.ESRCH, _, _) -> true
  | exception Unix.Unix_error (Unix.EPERM, _, _) -> false

let rec eventually_gone pid attempts =
  if is_gone pid then true
  else if attempts = 0 then false
  else begin
    ignore (Unix.select [] [] [] 0.02);
    eventually_gone pid (attempts - 1)
  end

let read_pid file =
  try
    Some (int_of_string (String.trim (In_channel.with_open_text file In_channel.input_all)))
  with Sys_error _ | Failure _ -> None

let signal_fixture pid signal =
  try Unix.kill pid signal with Unix.Unix_error _ -> ()

let clean_fixture_pid pid =
  if not (is_gone pid) then begin
    signal_fixture pid Sys.sigterm;
    ignore (Unix.select [] [] [] 0.05);
    if not (is_gone pid) then signal_fixture pid Sys.sigkill;
    ignore (eventually_gone pid 50)
  end

let rec wait_for_file file attempts =
  if Sys.file_exists file then true
  else if attempts = 0 then false
  else begin
    ignore (Unix.select [] [] [] 0.01);
    wait_for_file file (attempts - 1)
  end

let marker_group_and_session file =
  match String.split_on_char ' ' (String.trim (In_channel.with_open_text file In_channel.input_all)) with
  | [pgrp; session] -> (int_of_string pgrp, int_of_string session)
  | _ -> fail "process marker" "detached fixture did not publish group/session"

let with_pid_file f =
  let file = Filename.temp_file "uos-process-supervisor-" ".pid" in
  Unix.unlink file;
  Fun.protect ~finally:(fun () ->
    (* A failed assertion must not hide a live fixture behind unlinking its PID. *)
    Option.iter clean_fixture_pid (read_pid file);
    if Sys.file_exists file then Unix.unlink file)
    (fun () -> f file)

let test_separate_streams () =
  let result = run_bounded short (shell "printf out; printf err >&2") in
  assert_true "separate streams exit" (result.termination = Exited 0);
  assert_true "separate streams stdout" (result.stdout = "out");
  assert_true "separate streams stderr" (result.stderr = "err");
  assert_true "separate streams subreaper proof" result.children_reaped

let test_missing_executable () =
  let result = run_bounded short ["/definitely/missing/uos-command"] in
  match result.termination with
  | Exited code -> assert_true "missing executable status" (code <> 0)
  | _ -> fail "missing executable" "must return a deterministic nonzero exit"

let test_timeout_cleans_group () =
  with_pid_file (fun pid_file ->
    let result = run_bounded { short with timeout_ms = 100 } (shell
      ("sleep 30 & child=$!; printf '%s' \"$child\" > " ^ Filename.quote pid_file ^ "; wait")) in
    assert_true "timeout result" (result.termination = Timed_out);
    let pid = int_of_string (String.trim (In_channel.with_open_text pid_file In_channel.input_all)) in
    assert_true "timeout child cleanup" (eventually_gone pid 50);
    assert_true "timeout subreaper proof" result.children_reaped)

let test_normal_exit_closed_fd_descendant_cleanup () =
  with_pid_file (fun pid_file ->
    let result = run_bounded short (shell
      ("(exec 1>&- 2>&-; sleep 30) & child=$!; printf '%s' \"$child\" > " ^ Filename.quote pid_file ^ "; exit 0")) in
    assert_true "normal exit result" (result.termination = Exited 0);
    let pid = int_of_string (String.trim (In_channel.with_open_text pid_file In_channel.input_all)) in
    assert_true "closed-fd descendant cleanup" (eventually_gone pid 50);
    assert_true "closed-fd subreaper proof" result.children_reaped)

let test_escaped_setsid_descendant_never_claims_reaped () =
  with_pid_file (fun pid_file ->
    let ready_file = Filename.temp_file "uos-process-supervisor-ready-" ".marker" in
    Unix.unlink ready_file;
    Fun.protect ~finally:(fun () -> if Sys.file_exists ready_file then Unix.unlink ready_file) (fun () ->
    let result = run_bounded short (shell
      (detached_sleep_command pid_file ready_file ^ "; exit 0")) in
    let pid = match read_pid pid_file with
      | Some pid -> pid
      | None -> fail "escaped setsid descendant" "fixture did not publish a PID"
    in
    assert_true "escaped descendant ready after detached setup" (wait_for_file ready_file 1);
    let pgrp, session = marker_group_and_session ready_file in
    assert_true "escaped descendant changed process group" (pgrp = pid && pgrp <> result.pid);
    assert_true "escaped descendant changed session" (session = pid && session <> result.pid);
    assert_true "escaped descendant is killed and reaped" (eventually_gone pid 50);
    assert_true "escaped descendant reaped proof" result.children_reaped))

let test_parent_abort_cleans_descendants () =
  with_pid_file (fun pid_file ->
    let ready_file = Filename.temp_file "uos-process-supervisor-abort-ready-" ".marker" in
    Unix.unlink ready_file;
    Fun.protect ~finally:(fun () -> if Sys.file_exists ready_file then Unix.unlink ready_file) (fun () ->
      let control_r, control_w = Unix.pipe ~cloexec:true () in
      let started = monotonic_now () in
      let helper = Unix.fork () in
      if helper = 0 then begin
        safe_close control_r;
        supervisor_entry started { short with timeout_ms = 5_000 } (shell
          (detached_sleep_command pid_file ready_file ^ "; wait")) control_w;
        safe_close control_w;
        exit 0
      end;
      safe_close control_w;
      Fun.protect ~finally:(fun () -> safe_close control_r; signal_fixture helper Sys.sigkill) (fun () ->
        assert_true "parent abort fixture ready" (wait_for_file ready_file 100);
        let child = match read_pid pid_file with
          | Some pid -> pid
          | None -> fail "parent abort fixture" "detached child did not publish a PID"
        in
        let pgrp, session = marker_group_and_session ready_file in
        assert_true "parent abort child detached" (pgrp = child && session = child);
        abort_supervisor ~grace:(seconds short.term_grace_ms) helper;
        assert_true "parent abort cleaned detached child" (eventually_gone child 50);
        let buffer = Buffer.create 512 in
        let bytes = Bytes.create 512 in
        let rec read_result () =
          match Unix.read control_r bytes 0 (Bytes.length bytes) with
          | 0 -> ()
          | count -> Buffer.add_subbytes buffer bytes 0 count; read_result ()
        in
        read_result ();
        let result : process_result = Marshal.from_bytes (Bytes.of_string (Buffer.contents buffer)) 0 in
        assert_true "parent abort cannot report full cleanup proof" (not result.children_reaped))))

let test_stdout_quota () =
  let result = run_bounded { short with stdout_limit = 3 } (shell "printf 1234") in
  assert_true "stdout quota termination" (result.termination = Output_limit);
  assert_true "stdout quota capture" (result.stdout = "123");
  assert_true "stdout quota truncation" result.stdout_truncated;
  assert_true "stderr remains complete" (not result.stderr_truncated)

let test_stderr_quota () =
  let result = run_bounded { short with stderr_limit = 3 } (shell "printf 1234 >&2") in
  assert_true "stderr quota termination" (result.termination = Output_limit);
  assert_true "stderr quota capture" (result.stderr = "123");
  assert_true "stderr quota truncation" result.stderr_truncated;
  assert_true "stdout remains complete" (not result.stdout_truncated)

let test_invalid_limits () =
  let reject name limits argv =
    match run_bounded limits argv with
    | _ -> fail name "must reject invalid input before spawning"
    | exception Invalid_argument _ -> ()
  in
  reject "zero timeout" { short with timeout_ms = 0 } (shell "exit 0");
  reject "negative stdout limit" { short with stdout_limit = -1 } (shell "exit 0");
  reject "negative stderr limit" { short with stderr_limit = -1 } (shell "exit 0");
  reject "negative TERM grace" { short with term_grace_ms = -1 } (shell "exit 0");
  reject "zero stdout limit" { short with stdout_limit = 0 } (shell "exit 0");
  reject "zero stderr limit" { short with stderr_limit = 0 } (shell "exit 0");
  reject "zero TERM grace" { short with term_grace_ms = 0 } (shell "exit 0");
  reject "huge timeout" { short with timeout_ms = max_int } (shell "exit 0");
  reject "huge stdout limit" { short with stdout_limit = max_int } (shell "exit 0");
  reject "huge stderr limit" { short with stderr_limit = max_int } (shell "exit 0");
  reject "huge TERM grace" { short with term_grace_ms = max_int } (shell "exit 0");
  reject "empty argv" short []

let tests = [
  ("separate streams", test_separate_streams);
  ("missing executable", test_missing_executable);
  ("timeout cleanup", test_timeout_cleans_group);
  ("normal-exit closed-fd cleanup", test_normal_exit_closed_fd_descendant_cleanup);
  ("escaped setsid containment", test_escaped_setsid_descendant_never_claims_reaped);
  ("parent abort cleanup", test_parent_abort_cleans_descendants);
  ("stdout quota", test_stdout_quota);
  ("stderr quota", test_stderr_quota);
  ("invalid limits", test_invalid_limits);
]

let () =
  List.iter (fun (name, test) ->
    test ();
    Printf.printf "[PASS] %s\n%!" name
  ) tests
