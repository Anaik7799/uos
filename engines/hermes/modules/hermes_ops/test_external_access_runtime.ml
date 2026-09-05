open External_access_runtime

let passed = ref 0
let failed = ref 0

let check name predicate =
  if predicate () then (incr passed; Printf.printf "PASS %s\n" name)
  else (incr failed; Printf.eprintf "FAIL %s\n" name)

let child id restart =
  { child_id = id; role = Adapter_worker; restart;
    shutdown = Graceful 5_000; mailbox_capacity = 64;
    resource_budget_id = "budget." ^ id; recovery_id = "recovery." ^ id }

let supervisor strategy =
  make_supervisor
    { supervisor_id = "externalAccessSupervisor"; strategy;
      intensity = { max_restarts = 3; window_ms = 10_000 };
      children = [ child "sqlite" Permanent; child "network" Transient;
                   child "telemetry" Temporary ] }

let () =
  check "EA-OTP-01 pinned OTP 30 source is an explicit reference oracle" (fun () ->
      otp_reference.release = "30.0-rc0"
      && otp_reference.pin_file = "third_party/OTP30_PIN"
      && otp_reference.claim = Reference_model_not_equivalence);
  check "EA-OTP-02 supervisor construction is closed and valid" (fun () ->
      List.for_all (fun strategy -> Result.is_ok (supervisor strategy))
        [ One_for_one; One_for_all; Rest_for_one ]);
  check "EA-OTP-03 duplicate and unbounded children fail closed" (fun () ->
      Result.is_error
        (make_supervisor
           { supervisor_id = "bad"; strategy = One_for_one;
             intensity = { max_restarts = 0; window_ms = 0 };
             children = [ child "same" Permanent; child "same" Permanent ] }));
  check "EA-OTP-04 one-for-one isolates restart" (fun () ->
      match supervisor One_for_one with
      | Error _ -> false
      | Ok spec -> restart_set spec ~failed_child:"network" ~reason:Abnormal = [ "network" ]);
  check "EA-OTP-05 one-for-all preserves declared order" (fun () ->
      match supervisor One_for_all with
      | Error _ -> false
      | Ok spec -> restart_set spec ~failed_child:"network" ~reason:Abnormal
                   = [ "sqlite"; "network"; "telemetry" ]);
  check "EA-OTP-06 rest-for-one restarts suffix" (fun () ->
      match supervisor Rest_for_one with
      | Error _ -> false
      | Ok spec -> restart_set spec ~failed_child:"network" ~reason:Abnormal
                   = [ "network"; "telemetry" ]);
  check "EA-OTP-07 restart type semantics match OTP reference" (fun () ->
      match supervisor One_for_one with
      | Error _ -> false
      | Ok spec ->
          restart_set spec ~failed_child:"network" ~reason:Normal = []
          && restart_set spec ~failed_child:"telemetry" ~reason:Abnormal = []
          && restart_set spec ~failed_child:"sqlite" ~reason:Normal = [ "sqlite" ]);
  check "EA-OTP-08 restart intensity escalates predictably" (fun () ->
      match supervisor One_for_one with
      | Error _ -> false
      | Ok spec ->
          restart_decision spec ~now_ms:10_000 ~failure_times_ms:[ 1_000; 2_000 ]
          = Restart_allowed
          && restart_decision spec ~now_ms:10_000
               ~failure_times_ms:[ 1_000; 2_000; 9_999 ] = Escalate);
  check "EA-OTP-09 bounded mailbox rejects instead of growing" (fun () ->
      let mailbox = mailbox ~capacity:2 in
      match enqueue mailbox, enqueue mailbox with
      | Accepted, Accepted -> enqueue mailbox = Rejected_full
      | _ -> false);
  check "EA-OTP-10 resource scope closes all owned resources" (fun () ->
      let scope = scope [ "db"; "statement"; "socket" ] in
      close_scope scope;
      scope_open_resources scope = 0);
  check "EA-SAFETY-01 STPA covers all four UCA types" (fun () ->
      stpa_ucas |> List.map (fun item -> item.uca_type)
      |> List.sort_uniq compare
      = [ Not_provided; Provided_incorrectly; Wrong_timing; Applied_too_long ]);
  check "EA-SAFETY-02 every UCA has a mechanized constraint" (fun () ->
      stpa_ucas <> []
      && List.for_all (fun item -> item.constraint_ids <> []) stpa_ucas);
  check "EA-SAFETY-03 FMEA is total over critical runtime failure modes" (fun () ->
      validate_fmea () = [] && List.length fmea >= 10);
  check "EA-ASSURE-01 assurance tools have non-overlapping declared roles" (fun () ->
      validate_assurance () = [] && List.length assurance = 8);
  check "EA-PREDICT-01 predictive payload is bounded and actionable" (fun () ->
      let prediction = predict
          { signal = Mailbox_saturation; current_value = 62.; limit = 64.;
            derivative = 4.; confidence = 0.9 } in
      prediction.verdict = Intervention_recommended
      && prediction.horizon_ms > 0
      && prediction.hypotheses <> []
      && prediction.next_measurement <> ""
      && prediction.safe_action <> "");
  check "EA-PREDICT-02 weak evidence cannot become certainty" (fun () ->
      let prediction = predict
          { signal = Latency_growth; current_value = 10.; limit = 100.;
            derivative = 0.; confidence = 0.1 } in
      prediction.verdict = Insufficient_evidence
      && prediction.confidence <= 0.1);
  check "EA-PREDICT-03 authored paths cover fractals, components, communications, planes, and OODA" (fun () ->
      List.length predictive_paths = 80
      && predictive_coverage_gaps predictive_paths = []);
  check "EA-PREDICT-04 state rejects stale order and preserves bounded history" (fun () ->
      let path = List.hd predictive_paths in
      let metric = List.hd path.metrics in
      let store = create_state_store ~max_series:2 ~max_samples_per_series:3 in
      let sample observed_at_ns value =
        { path_id = path.path_id; metric_id = metric.metric_id; observed_at_ns;
          value; source_digest = String.make 64 'a'; run_id = "run.predictive" }
      in
      Result.is_ok (observe_sample store (sample 1_000_000_000L 10.))
      && Result.is_ok (observe_sample store (sample 2_000_000_000L 20.))
      && Result.is_ok (observe_sample store (sample 3_000_000_000L 30.))
      && observe_sample store (sample 2_500_000_000L 25.) = Error Non_monotonic_time
      && observe_sample store (sample 4_000_000_000L 40.) = Error Series_capacity_reached
      && List.length (samples store ~path_id:path.path_id ~metric_id:metric.metric_id) = 3);
  check "EA-PREDICT-05 current source-consistent state enables bounded forecast" (fun () ->
      let path = List.nth predictive_paths 6 in
      let metric = List.hd path.metrics in
      let store = create_state_store ~max_series:2 ~max_samples_per_series:4 in
      let add at value = observe_sample store
          { path_id = path.path_id; metric_id = metric.metric_id; observed_at_ns = at;
            value; source_digest = String.make 64 'b'; run_id = "run.predictive" } in
      ignore (add 1_000_000_000L 80.); ignore (add 2_000_000_000L 88.);
      ignore (add 3_000_000_000L 96.);
      let q = quality store ~now_ns:3_500_000_000L
          ~path_id:path.path_id ~metric_id:metric.metric_id in
      let forecast = predict_series store ~now_ns:3_500_000_000L
          ~path_id:path.path_id ~metric_id:metric.metric_id in
      q.prediction_ready && forecast.verdict = Intervention_recommended
      && forecast.confidence < 1.0);
  check "EA-RUNTIME-01 all structural runtime invariants hold" (fun () ->
      validate_runtime () = []);
  let self =
    Suite_telemetry.observe ~suite:"test_external_access_runtime"
      ~passed:!passed ~failed:!failed ~skipped:0
  in
  Printf.printf "SUMMARY %d passed, %d failed, 0 skipped\n" !passed !failed;
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_ops_capability ]);
  exit (Suite_telemetry.exit_code self)
