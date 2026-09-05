module Stan = Run_analysis.Stan_model

let checks = ref 0
let failures = ref 0
let check name condition =
  incr checks;
  if condition then Printf.printf "PASS %s\n" name
  else begin incr failures; Printf.eprintf "FAIL %s\n" name end

let provenance : Run_model.provenance =
  { source_revision = "external-access-stan"; source_clean = true;
    configuration_digest = String.make 64 'a'; authority_digest = String.make 64 'b';
    executable_digest = String.make 64 'c' }

let context () =
  match Run_safety.For_test.current_head_receipt ~run_id:"run-external-access-stan"
      ~provenance ~observed_at_ns:900L ~current_at_ns:1_000L ~expires_at_ns:2_000L with
  | Error issue -> failwith issue.Run_safety.message
  | Ok current_head ->
      match Run_safety.make_gate_context ~current_head
          ~request_id:"request-external-access-stan"
          ~activity_id:"activity.decide-intent"
          ~coordinate:{ Ops_capability.level = Ops_capability.L2; phase = Ops_capability.Decide }
          ~plane:Ops_capability.Control_plane with
      | Ok value -> value
      | Error issue -> failwith issue.Run_safety.message

let families = List.map External_access.resource_name External_access.resources

let observation index family =
  Stan.make_observation ~scenario_id:("scenario.external-access." ^ family)
    ~family_id:family ~sequence:1L
    ~verdict:(if index mod 4 = 0 then Stan.Failed else Stan.Passed)
    ~evidence_digest:(Digestif.SHA256.digest_string family |> Digestif.SHA256.to_hex)

let () =
  let context = context () in
  let observations =
    List.mapi observation families
    |> List.map (function Ok item -> item | Error gaps -> failwith (String.concat "; " gaps))
  in
  let input = Stan.make_input ~prior_alpha:1.0 ~prior_beta:1.0
      ~all_families:families ~observations in
  check "EA-STAN-01 complete population input validates" (Result.is_ok input);
  begin match input with
  | Error _ ->
      check "EA-STAN-02 analysis is report-only and complete" false;
      check "EA-STAN-03 exact receipt validates" false
  | Ok input ->
      begin match Stan.analyze context input with
      | Error _ ->
          check "EA-STAN-02 analysis is report-only and complete" false;
          check "EA-STAN-03 exact receipt validates" false
      | Ok receipt ->
          check "EA-STAN-02 analysis is report-only and complete"
            (receipt.authority = Run_safety.Analysis_only
             && receipt.coverage_complete && receipt.unmeasured_families = []
             && List.length receipt.summaries = List.length families);
          check "EA-STAN-03 exact receipt validates"
            (Result.is_ok (Stan.validate_receipt ~context receipt)
             && Result.is_ok (Stan.validate_exact ~context ~input receipt))
      end
  end;
  check "EA-STAN-04 missing families remain explicitly incomplete" ((fun () ->
      match Stan.make_input ~prior_alpha:1.0 ~prior_beta:1.0
              ~all_families:families ~observations:[ List.hd observations ] with
      | Error _ -> false
      | Ok sparse ->
          match Stan.analyze context sparse with
          | Error _ -> false
          | Ok receipt -> not receipt.coverage_complete
                          && List.length receipt.unmeasured_families = List.length families - 1) ());
  check "EA-STAN-05 pseudo-replicated evidence digest is refused" ((fun () ->
      let digest = String.make 64 'd' in
      match Stan.make_observation ~scenario_id:"scenario.a" ~family_id:"sqlite"
              ~sequence:1L ~verdict:Stan.Passed ~evidence_digest:digest,
            Stan.make_observation ~scenario_id:"scenario.b" ~family_id:"network"
              ~sequence:1L ~verdict:Stan.Passed ~evidence_digest:digest with
      | Ok left, Ok right ->
          Result.is_error (Stan.make_input ~prior_alpha:1.0 ~prior_beta:1.0
             ~all_families:[ "sqlite"; "network" ] ~observations:[ left; right ])
      | _ -> false) ());
  check "EA-STAN-06 invalid or overconfident priors fail closed"
    (Result.is_error (Stan.make_input ~prior_alpha:0.0 ~prior_beta:1.0
       ~all_families:families ~observations));
  let self = Suite_telemetry.observe ~suite:"test_external_access_stan"
      ~passed:(!checks - !failures) ~failed:!failures ~skipped:0 in
  Printf.printf "SUMMARY %d passed, %d failed, 0 skipped\n"
    (!checks - !failures) !failures;
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_ops_capability ]);
  exit (Suite_telemetry.exit_code self)
