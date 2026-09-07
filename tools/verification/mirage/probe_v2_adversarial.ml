(* Independent invocation against the candidate with argv-list probe API.
   The executable fixture only impersonates an allowed basename; its provenance
   is deliberately invalid. None of these fixtures are Solo5 guest artifacts. *)
let rec mkdir path =
  if not (Sys.file_exists path) then (mkdir (Filename.dirname path); Unix.mkdir path 0o700)

let write path contents =
  mkdir (Filename.dirname path);
  let oc = open_out_bin path in
  Fun.protect ~finally:(fun () -> close_out oc) (fun () -> output_string oc contents)

let () =
  if Array.length Sys.argv <> 4 then
    failwith "usage: probe-v2-adversarial CONTROL FIXTURE_ROOT FIXTURE_EXECUTABLE";
  let control, root, fixture = Sys.argv.(1), Sys.argv.(2), Sys.argv.(3) in
  let guest = "test_hello.hvt" in
  write (Filename.concat root ("var/mirage/unikernels/" ^ guest)) (String.make 10_000 'X');
  let tender = Filename.concat root "solo5-hvt" in
  Unix.symlink fixture tender;
  Unix.putenv "PWD" root;
  let started = Unix.gettimeofday () in
  let receipt = Mirage_hypervisor_probe.run_tender_test (Some tender) guest [0] [control] in
  let json = match receipt with
    | None -> `Null
    | Some r -> `Assoc ["tender", `String r.tender; "unikernel", `String r.unikernel;
                        "exit_code", `Int r.exit_code; "output_snippet", `String r.output_snippet;
                        "passed", `Bool r.passed]
  in
  Yojson.Safe.pretty_to_channel stdout (`Assoc [
    "control", `String control; "expected_passed", `Bool false;
    "elapsed_seconds", `Float (Unix.gettimeofday () -. started);
    "observed", json]);
  print_newline ();
  match receipt with Some r when r.passed -> exit 1 | _ -> exit 0
