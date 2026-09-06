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

let with_pid_file f =
  let file = Filename.temp_file "uos-process-supervisor-" ".pid" in
  Unix.unlink file;
  Fun.protect ~finally:(fun () -> if Sys.file_exists file then Unix.unlink file)
    (fun () -> f file)

let test_separate_streams () =
  let result = run_bounded short (shell "printf out; printf err >&2") in
  assert_true "separate streams exit" (result.termination = Exited 0);
  assert_true "separate streams stdout" (result.stdout = "out");
  assert_true "separate streams stderr" (result.stderr = "err");
  assert_true "separate streams reaped" result.children_reaped

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
    assert_true "timeout cleanup proof" result.children_reaped)

let test_normal_exit_closed_fd_descendant_cleanup () =
  with_pid_file (fun pid_file ->
    let result = run_bounded short (shell
      ("(exec 1>&- 2>&-; sleep 30) & child=$!; printf '%s' \"$child\" > " ^ Filename.quote pid_file ^ "; exit 0")) in
    assert_true "normal exit result" (result.termination = Exited 0);
    let pid = int_of_string (String.trim (In_channel.with_open_text pid_file In_channel.input_all)) in
    assert_true "closed-fd descendant cleanup" (eventually_gone pid 50);
    assert_true "closed-fd cleanup proof" result.children_reaped)

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
  reject "empty argv" short []

let tests = [
  ("separate streams", test_separate_streams);
  ("missing executable", test_missing_executable);
  ("timeout cleanup", test_timeout_cleans_group);
  ("normal-exit closed-fd cleanup", test_normal_exit_closed_fd_descendant_cleanup);
  ("stdout quota", test_stdout_quota);
  ("stderr quota", test_stderr_quota);
  ("invalid limits", test_invalid_limits);
]

let () =
  List.iter (fun (name, test) ->
    test ();
    Printf.printf "[PASS] %s\n%!" name
  ) tests
