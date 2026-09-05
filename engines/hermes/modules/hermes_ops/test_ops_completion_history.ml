let passed = ref 0
let failed = ref 0

let check name f =
  match f () with
  | true -> incr passed
  | false -> incr failed; Printf.printf "FAILED: %s\n" name
  | exception exn ->
      incr failed;
      Printf.printf "FAILED: %s (raised %s)\n" name (Printexc.to_string exn)

let with_store f =
  let require_location = function
    | Ok value -> value
    | Error error -> failwith (Dependability_sqlite_test_protocol.string_of_error error)
  in
  let registry =
    Dependability_sqlite_test_protocol.create ~maximum_live:1 |> require_location
  in
  let registry, lease =
    Dependability_sqlite_test_protocol.acquire registry
      Dependability_sqlite_test_protocol.In_memory |> require_location
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
    (fun () ->
      match Ops_completion_history.open_store location with
      | Error message -> failwith message
      | Ok store ->
          Fun.protect ~finally:(fun () -> Ops_completion_history.close store)
            (fun () -> f store))

let source ?(clean = true) ?(config = String.make 64 'c') () =
  { Ops_observability.source_revision = String.make 40 'a'; source_clean = clean;
    configuration_digest = config; authority_digest = String.make 64 'b' }

let request =
  { Ops_command.request_id = "request-1"; action = Ops_command.Inventory;
    scope = Ops_command.Whole_system }

let observation surface output =
  Ops_command.dispatch ~execute:(fun _ -> Ok output) ~surface request

let event surface output =
  let observation = observation surface output in
  let telemetry =
    Ops_observability.event ~run_id:"run-1" ~started_ns:10L ~finished_ns:25L
      ~source:(source ()) observation
  in
  (telemetry, observation.receipt)

let () =
  check "O1 authority and configuration identities are SHA-256 digests" (fun () ->
      String.length (Ops_observability.configuration_digest ()) = 64
      && String.length (Ops_observability.authority_digest ()) = 64);
  check "O2 event carries every required typed observability dimension" (fun () ->
      let telemetry, receipt = event Ops_command.Ocaml_api "ok" in
      Ops_observability.validate telemetry = []
      && telemetry.duration_ns = 15L
      && telemetry.receipt_digest = receipt.digest
      && telemetry.fractal_coordinate = "L0/observe"
      && telemetry.ooda_phase = "observe");
  check "O3 event projects to an OTLP LogRecord without losing dimensions" (fun () ->
      let telemetry, _ = event Ops_command.Mcp "ok" in
      let json = Ops_observability.to_otel_json telemetry in
      Yojson.Safe.Util.member "timeUnixNano" json = `String "25"
      && Yojson.Safe.Util.member "severityText" json = `String "INFO"
      && match Yojson.Safe.Util.member "attributes" json with
         | `List attributes -> List.length attributes = 16
         | _ -> false);
  check "H1 one receipt can be observed through multiple surfaces without duplication" (fun () ->
      with_store (fun store ->
        let first_event, first_receipt = event Ops_command.Ocaml_api "ok" in
        let second_event, second_receipt = event Ops_command.Cli "ok" in
        Ops_completion_history.record store first_event first_receipt = Ok ()
        && Ops_completion_history.record store second_event second_receipt = Ok ()
        && match Ops_completion_history.counts store with
           | Ok { receipts = 1; observations = 2; interactions = 0 } -> true
           | _ -> false));
  check "H2 a request id cannot be replayed with a divergent immutable receipt" (fun () ->
      with_store (fun store ->
        let first_event, first_receipt = event Ops_command.Ocaml_api "ok" in
        let second_event, second_receipt = event Ops_command.Cli "changed" in
        Ops_completion_history.record store first_event first_receipt = Ok ()
        && match Ops_completion_history.record store second_event second_receipt with
           | Error message -> String.length message > 0
           | Ok () -> false));
  check "H3 exact-head admission rejects dirty or configuration-stale receipts" (fun () ->
      with_store (fun store ->
        let telemetry, receipt = event Ops_command.Ocaml_api "ok" in
        Ops_completion_history.record store telemetry receipt = Ok ()
        && Ops_completion_history.receipt_is_current store ~source:(source ())
             ~receipt_digest:receipt.digest = Ok true
        && Ops_completion_history.receipt_is_current store ~source:(source ~clean:false ())
             ~receipt_digest:receipt.digest = Ok false
        && Ops_completion_history.receipt_is_current store
             ~source:(source ~config:(String.make 64 'd') ()) ~receipt_digest:receipt.digest
           = Ok false));
  check "H3b current-success admission binds action, scope, verdict, and exact head" (fun () ->
      with_store (fun store ->
        let telemetry, receipt = event Ops_command.Ocaml_api "ok" in
        Ops_completion_history.record store telemetry receipt = Ok ()
        && Ops_completion_history.has_current_success store ~source:(source ())
             ~action:"inventory" ~scope:"whole-system" = Ok true
        && Ops_completion_history.has_current_success store ~source:(source ())
             ~action:"act" ~scope:"whole-system" = Ok false
        && Ops_completion_history.has_current_success store ~source:(source ~clean:false ())
             ~action:"inventory" ~scope:"whole-system" = Ok false));
  check "H4 prompt and agent interaction history is append-only and queryable" (fun () ->
      with_store (fun store ->
        let interaction =
          { Ops_completion_history.interaction_id = "interaction-1"; run_id = "run-1";
            actor = "user"; kind = Ops_completion_history.Prompt;
            body = "objective"; recorded_at_ns = 30L }
        in
        Ops_completion_history.append_interaction store interaction = Ok ()
        && Ops_completion_history.append_interaction store interaction = Ok ()
        && match Ops_completion_history.counts store with
           | Ok { receipts = 0; observations = 0; interactions = 1 } -> true
           | _ -> false));
  Printf.printf "ops_completion_history: %d passed, %d failed\n" !passed !failed;
  let self =
    Suite_telemetry.observe ~suite:"test_ops_completion_history" ~passed:!passed
      ~failed:!failed ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_ops_capability; Stanza.hermes_ops_governance; Stanza.hermes_ops_topology; Stanza.hermes_ops_completion_topology; Stanza.hermes_ops ]);
  exit (Suite_telemetry.exit_code self)
