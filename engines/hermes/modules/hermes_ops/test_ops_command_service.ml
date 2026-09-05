let passed = ref 0
let failed = ref 0

let check name f =
  match f () with
  | true -> incr passed
  | false -> incr failed; Printf.printf "FAILED: %s\n" name
  | exception exn ->
      incr failed;
      Printf.printf "FAILED: %s (raised %s)\n" name (Printexc.to_string exn)

let request =
  { Ops_command.request_id = "audited-request"; action = Ops_command.Inventory;
    scope = Ops_command.Whole_system }

let with_location fixture f =
  let require_location = function
    | Ok value -> value
    | Error error -> failwith (Dependability_sqlite_test_protocol.string_of_error error)
  in
  let registry =
    Dependability_sqlite_test_protocol.create ~maximum_live:1 |> require_location
  in
  let registry, lease =
    Dependability_sqlite_test_protocol.acquire registry fixture |> require_location
  in
  let location =
    Dependability_sqlite_test_protocol.reference registry lease |> require_location
  in
  Fun.protect
    ~finally:(fun () ->
      match Dependability_sqlite_test_protocol.release registry lease with
      | Error _ -> ()
      | Ok (registry, _) ->
          ignore (Dependability_sqlite_test_protocol.cleanup registry))
    (fun () -> f location)

let () =
  check "D1 audited dispatch returns the canonical command observation" (fun () ->
      with_location Dependability_sqlite_test_protocol.In_memory (fun location ->
        match
          Ops_command_service.dispatch ~root:"." ~history_location:location
            ~execute:(fun _ -> Ok "audited") ~surface:Ops_command.Ocaml_api request
        with
        | Ok observation ->
            observation.surface = Ops_command.Ocaml_api
            && observation.receipt.verdict = Ops_command.Succeeded
        | Error _ -> false));
  check "D2 successful dispatch returns the receipt that the opaque history owner records" (fun () ->
      with_location Dependability_sqlite_test_protocol.In_memory (fun location ->
        match
          Ops_command_service.dispatch ~root:"." ~history_location:location
            ~execute:(fun _ -> Ok "audited") ~surface:Ops_command.Cli request
        with
        | Error _ -> false
        | Ok observation ->
            observation.receipt.request_id = request.request_id
            && observation.receipt.action = "inventory"
            && String.length observation.receipt.digest = 64));
  check "D3 a refused opaque audit location prevents command execution" (fun () ->
      with_location
        (Dependability_sqlite_test_protocol.Fault_injection
           Dependability_sqlite_test_protocol.Open_failure)
        (fun location ->
        let calls = ref 0 in
        let result =
          Ops_command_service.dispatch ~history_location:location
            ~execute:(fun _ -> incr calls; Ok "must-not-run")
            ~surface:Ops_command.Cli request
        in
        !calls = 0 && match result with Error _ -> true | Ok _ -> false));
  Printf.printf "ops_command_service: %d passed, %d failed\n" !passed !failed;
  let self =
    Suite_telemetry.observe ~suite:"test_ops_command_service" ~passed:!passed
      ~failed:!failed ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_ops_capability; Stanza.hermes_ops_governance; Stanza.hermes_ops_topology; Stanza.hermes_ops_completion_topology; Stanza.hermes_ops ]);
  exit (Suite_telemetry.exit_code self)
