let failures = ref []

let check name condition =
  if not condition then failures := name :: !failures

let prepared consumer =
  match Jj_runtime_current_protocol.Owner_session.make "owner-session-1",
        Jj_runtime_current_protocol.Activation_generation.make 1,
        Jj_runtime_current_protocol.Activity_identity.make "activity-1",
        Jj_runtime_current_protocol.Source_transition_commitment.make "commitment-1",
        Jj_recovery_transition_port_protocol.Expiry.make "expiry-1" with
  | Ok owner_session, Ok activation_generation, Ok activity, Ok commitment, Ok expiry ->
      Jj_recovery_transition_port_protocol.prepare ~owner_session
        ~activation_generation ~activity ~commitment
        ~target:Jj_runtime_manifest.Target_transition ~consumer ~expiry
  | _ -> Error (Jj_error.make Jj_error.Noncanonical_identity ~detail:"test-fixture")

let () =
  check "RP1 typed transition reference preparation is nonauthorizing and bounded"
    (Result.is_ok (prepared Jj_action_kind.Activate_source_recovery_branch));
  check "RP2 non-transition frontier consumer is refused"
    (Result.is_error
       (prepared (Jj_action_kind.Set_activity_frontier Jj_action_kind.Reconciled_terminal)));
  check "RP3 prepared reference exposes only a nonempty canonical identity"
    (match prepared Jj_action_kind.Activate_source_recovery_branch with
     | Ok reference -> String.length (Jj_recovery_transition_port_protocol.prepared_key reference) > 0
     | Error _ -> false);
  List.iter (fun failure -> Printf.printf "FAILED: %s\n" failure) (List.rev !failures);
  let failed = List.length !failures in
  let passed = 3 - failed in
  let self = Suite_telemetry.observe ~suite:"test_jj_recovery_transition_port_protocol"
      ~passed ~failed ~skipped:0 in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_jj_protocol ]);
  exit (Suite_telemetry.exit_code self)
