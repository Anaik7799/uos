(* Construct malformed evidence, then invoke the actual tools/uos gate externally.
   A file-size or substring recognizer cannot establish execution provenance. *)
let rec mkdir path =
  if not (Sys.file_exists path) then (mkdir (Filename.dirname path); Unix.mkdir path 0o700)

let write path contents =
  mkdir (Filename.dirname path);
  let oc = open_out_bin path in
  Fun.protect ~finally:(fun () -> close_out oc) (fun () -> output_string oc contents)

let () =
  if Array.length Sys.argv <> 2 then failwith "usage: gate-fixture EMPTY_DIRECTORY";
  let root = Sys.argv.(1) in
  let put path = write (Filename.concat root path) in
  List.iter (fun path -> put path "") [
    "engines/hermes/modules/hermes_mirage/mirage_hypervisor_probe.ml";
    "apps/cepaf_gleam/src/cepaf_gleam/services/mirage_hypervisor.gleam";
    "apps/cepaf_gleam/test/mirage_hypervisor_test.gleam";
    "docs/journal/20260907-1416-mirage-hypervisor-verification-and-codex-coordination-journal.md";
  ];
  List.iter (fun name -> put ("var/mirage/unikernels/" ^ name) (String.make 10_000 'X'))
    ["test_hello.hvt"; "test_hello.spt"; "test_hello.virtio"; "test_time.hvt";
     "test_ssp.hvt"; "test_ssp.spt"; "test_ssp.virtio"];
  put "var/mirage/receipts/hypervisors_probe.json"
    (String.make 500 'X' ^ "\nTHIS IS NOT JSON\n"
     ^ "\"overall_readiness\": \"solo5_hardware_virtualized_and_spt_verified\"\n"
     ^ "\"deployment_admission\": \"TENDERS_VERIFIED_PHYSICAL_EXECUTION\"\n"
     ^ "\"exit_code\": 0\n\"exit_code\": 83\n\"passed\": true\nSolo5: Bindings version\n")
