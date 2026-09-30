(* Independent controls call the exact candidate Mirage_hypervisor_probe module.
   Compile its .ml unchanged in an ignored build directory, then link this file.
   Fixtures are trusted local processes, never evidence of guest execution. *)

let rec mkdir path =
  if not (Sys.file_exists path) then (mkdir (Filename.dirname path); Unix.mkdir path 0o700)

let write path contents =
  mkdir (Filename.dirname path);
  let oc = open_out_bin path in
  Fun.protect ~finally:(fun () -> close_out oc) (fun () -> output_string oc contents)

let () =
  if Array.length Sys.argv <> 4 then
    failwith "usage: probe-adversarial CONTROL FIXTURE_ROOT FIXTURE_EXECUTABLE";
  let control = Sys.argv.(1) in
  let base = Sys.argv.(2) in
  let fixture = Sys.argv.(3) in
  let root = if control = "pwd-injection" then base ^ "; true #" else base in
  let guest = "test_hello.hvt" in
  write (Filename.concat root ("var/mirage/unikernels/" ^ guest)) "";
  Unix.putenv "PWD" root;
  let tender, args = match control with
    | "empty-guest" -> "/usr/bin/true", "Hello_Solo5"
    | "pwd-injection" -> "/usr/bin/false", "Hello_Solo5"
    | "silent-timeout" -> fixture, "silent-timeout"
    | "late-abort" -> fixture, "late-abort"
    | "large-line" -> fixture, "large-line"
    | _ -> failwith "unknown control"
  in
  let started = Unix.gettimeofday () in
  let receipt = Mirage_hypervisor_probe.run_tender_test (Some tender) guest [0] args in
  let evidence = `Assoc [
    "control", `String control;
    "expected_passed", `Bool false;
    "elapsed_seconds", `Float (Unix.gettimeofday () -. started);
    "observed", Mirage_hypervisor_probe.receipt_to_json receipt;
  ] in
  Yojson.Safe.pretty_to_channel stdout evidence;
  print_newline ();
  match receipt with
  | Some r when r.passed -> exit 1
  | _ -> exit 0
