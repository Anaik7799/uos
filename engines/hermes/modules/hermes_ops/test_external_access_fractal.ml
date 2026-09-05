open External_access

let passed = ref 0
let failed = ref 0

let check name predicate =
  if predicate () then (incr passed; Printf.printf "PASS %s\n" name)
  else (incr failed; Printf.eprintf "FAIL %s\n" name)

let valid_intent resource =
  External_access.declare
    { intent_id = "intent.external-access.test";
      request_id = "request.external-access.test";
      owner_id = "hermes_external_access";
      adapter_id = External_access.adapter_id resource;
      resource; operation = External_access.Observe;
      purpose = "Exercise the controlled external-access contract";
      target_class = "repository-local-test-fixture";
      config_ids = [ "HERMES_EXTERNAL_ACCESS_TEST" ];
      authorization_id = "authorization.test.read-only";
      budget = { timeout_ms = 1_000; max_bytes = 4_096; max_attempts = 1 };
      redaction = External_access.Metadata_only;
      idempotency_key = "external-access-test";
      success_criteria = [ "typed receipt returned" ];
      recovery_id = "recovery.no-effect";
      coordinate = { Ops_capability.level = Ops_capability.L3; phase = Ops_capability.Decide } }

let () =
  check "EA-FRACTAL-01 eight resource families are closed" (fun () ->
      List.length External_access.resources = 8
      && List.sort_uniq compare External_access.resources
         = List.sort compare External_access.resources);
  check "EA-FRACTAL-02 every family declares and prepares" (fun () ->
      List.for_all
        (fun resource ->
          match valid_intent resource with
          | Error _ -> false
          | Ok intent ->
              External_access.intent_resource intent = resource
              && match External_access.prepare intent with Ok _ -> true | Error _ -> false)
        External_access.resources);
  check "EA-FRACTAL-03 invalid intent fails closed" (fun () ->
      match
        External_access.declare
          { intent_id = ""; request_id = ""; owner_id = ""; adapter_id = "";
            resource = Sqlite; operation = Write; purpose = ""; target_class = "";
            config_ids = []; authorization_id = "";
            budget = { timeout_ms = 0; max_bytes = 0; max_attempts = 0 };
            redaction = Secret; idempotency_key = ""; success_criteria = [];
            recovery_id = "";
            coordinate = { Ops_capability.level = Ops_capability.L4; phase = Ops_capability.Act } }
      with Error gaps -> List.length gaps >= 10 | Ok _ -> false);
  check "EA-FRACTAL-04 ontology is total L0-L6 plus LX" (fun () ->
      External_access.validate_ontology External_access.ontology = []
      && List.length External_access.ontology = 8);
  check "EA-FRACTAL-05 authored atlas is total" (fun () ->
      External_access.validate_atlas External_access.atlas = []
      && List.length External_access.atlas = 8);
  check "EA-FRACTAL-06 algebra is total and mutants are killed" (fun () ->
      External_access.validate_algebra () = []
      && List.for_all External_access.mutant_is_killed External_access.mutants);
  check "EA-FRACTAL-07 FPP correspondence is total" (fun () ->
      External_access.validate_fpp () = []
      && Fpp_model.validate External_access.fpp_model = []);
  check "EA-FRACTAL-08 bridge route is immutable and sole" (fun () ->
      match valid_intent Process with
      | Error _ -> false
      | Ok intent ->
          match External_access.prepare intent with
          | Error _ -> false
          | Ok prepared ->
              External_access.prepared_bridge_id prepared = "Run_swarm_bridge"
              && External_access.prepared_engine_calls prepared = 0
              && External_access.execution_status prepared
                 = External_access.Unavailable_observed);
  check "EA-FRACTAL-09 authority digest is SHA-256" (fun () ->
      String.length External_access.source_digest = 64);
  let self =
    Suite_telemetry.observe ~suite:"test_external_access_fractal"
      ~passed:!passed ~failed:!failed ~skipped:0
  in
  Printf.printf "SUMMARY %d passed, %d failed, 0 skipped\n" !passed !failed;
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_ops_capability ]);
  exit (Suite_telemetry.exit_code self)
