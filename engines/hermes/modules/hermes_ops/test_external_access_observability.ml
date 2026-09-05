open External_access_observability

let passed = ref 0
let failed = ref 0
let check name predicate =
  if predicate () then (incr passed; Printf.printf "PASS %s\n" name)
  else (incr failed; Printf.eprintf "FAIL %s\n" name)

let path = List.nth External_access_runtime.predictive_paths 6
let metric = List.hd path.metrics

let declaration ?parent_span_id ?(value = 20.) ?(outcome = Succeeded) () =
  { trace_id = String.make 32 'a'; span_id = String.make 16 'b'; parent_span_id;
    run_id = "run.external-access"; request_id = "request.external-access";
    intent_id = "intent.external-access"; attempt_id = Some "attempt.external-access";
    path_id = path.path_id; metric_id = metric.metric_id;
    observed_at_ns = 10_000_000_000L; duration_ns = 2_000_000L; value;
    outcome; rca_origin = Ops_capability.Control; hazard_id = "HZ-EA-TEST";
    event_code = "EA_EFFECT_OBSERVED"; source_digest = String.make 64 'c';
    prediction_verdict = External_access_runtime.Watch }

let () =
  check "EA-OBS-01 typed observation validates" (fun () ->
      Result.is_ok (observe (declaration ())));
  check "EA-OBS-02 unknown path and unsafe identity fail closed" (fun () ->
      let bad = { (declaration ()) with path_id = "unknown"; trace_id = "secret token" } in
      match observe bad with Error gaps -> List.length gaps >= 2 | Ok _ -> false);
  check "EA-OBS-03 trace parentage is exact" (fun () ->
      let child = { (declaration ~parent_span_id:(String.make 16 'b') ()) with
                    span_id = String.make 16 'd' } in
      match observe (declaration ()), observe child with
      | Ok parent, Ok child -> is_child ~parent ~child
      | _ -> false);
  check "EA-OBS-04 attributes are bounded and exclude unsafe payload keys" (fun () ->
      match observe (declaration ()) with
      | Error _ -> false
      | Ok item ->
          let attrs = attributes item in
          List.length attrs <= 20
          && List.for_all (fun (key, _) ->
               not (List.mem key [ "target"; "sql"; "prompt"; "credential"; "payload" ])) attrs);
  check "EA-OBS-05 every predictive path has exactly one logging contract" (fun () ->
      logging_coverage_gaps () = []
      && List.length logging_contracts
         = List.length External_access_runtime.predictive_paths);
  check "EA-OBS-06 logs preserve coordinate, OODA, plane, RCA, hazard, and trace" (fun () ->
      match observe (declaration ()) with
      | Error _ -> false
      | Ok item ->
          let record = log_record item in
          record.path_id = path.path_id
          && record.level = path.level && record.phase = path.phase
          && record.plane = path.plane && record.rca_origin = Ops_capability.Control
          && record.hazard_id = "HZ-EA-TEST" && record.trace_id = String.make 32 'a');
  check "EA-OBS-07 readback mismatch tunes investigation, never direct mutation" (fun () ->
      let readback_path = List.nth External_access_runtime.predictive_paths 7 in
      let readback_metric = List.hd readback_path.metrics in
      let item = observe
          { (declaration ~outcome:Failed ()) with path_id = readback_path.path_id;
            metric_id = readback_metric.metric_id; value = 1. } in
      match item with
      | Error _ -> false
      | Ok observation ->
          let recommendation = tune [ observation ] in
          recommendation.action = Investigate_readback
          && recommendation.execution = Recommendation_only
          && recommendation.evidence_ids <> []);
  check "EA-OBS-08 saturation recommends backpressure with bounded evidence" (fun () ->
      match observe (declaration ~value:99. ()) with
      | Error _ -> false
      | Ok item ->
          let recommendation = tune [ item ] in
          recommendation.action = Apply_backpressure
          && recommendation.execution = Recommendation_only
          && recommendation.confidence < 1.0);
  check "EA-OBS-09 full observability model validates" (fun () -> validate () = []);
  let self = Suite_telemetry.observe ~suite:"test_external_access_observability"
      ~passed:!passed ~failed:!failed ~skipped:0 in
  Printf.printf "SUMMARY %d passed, %d failed, 0 skipped\n" !passed !failed;
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_ops_capability ]);
  exit (Suite_telemetry.exit_code self)
