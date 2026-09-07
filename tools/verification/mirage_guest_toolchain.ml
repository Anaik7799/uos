#!/usr/bin/env -S ocaml
#use "./tools/verification/solo5_toolchain.ml";;

(* A bounded compatibility observation of a real Mirage-generated HVT guest.
   The payload is an untrusted boot snapshot, not an application health proof. *)
let () =
  try
    if Array.length Sys.argv <> 2 then
      failwith "usage: mirage_guest_toolchain.ml <built-hvt-guest>";
    Unix.putenv "PATH" "/usr/bin:/bin";
    let guest = Sys.argv.(1) in
    let tender = prefix ^ "/bin/solo5-hvt" in
    let host_boot = String.trim (In_channel.with_open_text
      "/proc/sys/kernel/random/boot_id" In_channel.input_all) in
    let run_id = Printf.sprintf "capture-%d-%.0f" (Unix.getpid ())
      (Unix.gettimeofday () *. 1_000_000.) in
    let argv = [tender; "--mem=64"; guest;
      "--boot-id=" ^ host_boot; "--run-id=" ^ run_id] in
    let bindings = List.map file_binding [tender; guest] in
    let source_paths = ["tools/verification/mirage_guest_toolchain.ml";
      "tools/verification/solo5_toolchain.ml"; "tests/acceptance/process_supervisor.ml"] in
    let sources_before = List.map file_binding source_paths in
    let started = now_utc () in
    let result = run_bounded { limits with timeout_ms = 5_000 } argv in
    let unchanged = bindings = List.map file_binding [tender; guest] in
    let sources_unchanged = sources_before = List.map file_binding source_paths in
    let output = result.stdout ^ "\n" ^ result.stderr in
    let frames = List.filter (String.starts_with ~prefix:"UOS_MIRAGE_METRICS_V1\t")
      (lines output) in
    let identity_echo_matches = match frames with
      | [frame] -> (match String.split_on_char '\t' frame with
          | _schema :: boot :: run :: _ -> boot = host_boot && run = run_id
          | _ -> false)
      | _ -> false in
    let passed = completed result && unchanged && sources_unchanged
      && identity_echo_matches && result.termination = Exited 0
      && has output "Solo5: Bindings version v0.13.0"
      && has output "Solo5: solo5_exit(0) called"
      && List.length frames = 1
      && List.for_all (fun frame -> String.length frame <= 4096) frames
      && not (List.exists (String.starts_with ~prefix:"Solo5: ABORT:") (lines output)) in
    let receipt = `Assoc [
      "schema", `String "uos.mirage-guest-toolchain.v1";
      "started_at", `String started; "completed_at", `String (now_utc ());
      "host", `String (Unix.gethostname ()); "host_boot_id", `String host_boot;
      "capture_run_id", `String run_id;
      "argv", `List (List.map (fun s -> `String s) argv);
      "artifacts", `List bindings; "artifacts_unchanged", `Bool unchanged;
      "source_artifacts", `List sources_before;
      "source_artifacts_unchanged", `Bool sources_unchanged;
      "identity_echo_matches", `Bool identity_echo_matches;
      "checker", file_binding "tools/verification/mirage_guest_toolchain.ml";
      "binding_helper", file_binding "tools/verification/solo5_toolchain.ml";
      "supervisor", file_binding "tests/acceptance/process_supervisor.ml";
      "termination", termination_json result.termination;
      "duration_ms", `Float result.duration_ms;
      "timeout_ms", `Int 5_000; "stream_limit_bytes", `Int limits.stdout_limit;
      "children_reaped", `Bool result.children_reaped;
      "stdout_truncated", `Bool result.stdout_truncated;
      "stderr_truncated", `Bool result.stderr_truncated;
      "stdout", `String result.stdout; "stderr", `String result.stderr;
      "compatibility_passed", `Bool passed;
      "application_admitted", `Bool false;
      "scope", `String "One x86_64 HVT boot snapshot; no health, freshness, counter-continuity, RAM-saving or network-service admission" ] in
    print_endline (Yojson.Basic.pretty_to_string receipt);
    exit (if passed then 0 else 1)
  with error -> prerr_endline (Printexc.to_string error); exit 2
