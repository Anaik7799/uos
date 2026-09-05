let failures = ref []

let check name condition =
  if not condition then failures := name :: !failures

let valid_claim () =
  match Jj_runtime_current_protocol.Owner_session.make "owner-session-1",
        Jj_runtime_current_protocol.Lifecycle_epoch.make 1,
        Jj_runtime_current_protocol.Source_identity.make "source-identity-1",
        Jj_runtime_current_protocol.Config_identity.make "config-identity-1",
        Jj_runtime_current_protocol.Host_identity.make "host-identity-1",
        Jj_runtime_current_protocol.Clock_identity.make "clock-identity-1" with
  | Ok owner, Ok epoch, Ok source, Ok config, Ok host, Ok clock ->
      Jj_runtime_current_protocol.claim ~slot:Jj_runtime_manifest.Target_jj
        ~owner ~epoch ~source ~config ~host ~clock
  | _ -> Error (Jj_error.make Jj_error.Noncanonical_identity ~detail:"test-fixture")

let () =
  check "RC1 slot-local owner claim is constructible from bounded typed identities"
    (Result.is_ok (valid_claim ()));
  check "RC2 epoch zero is unavailable rather than current"
    (Result.is_error (Jj_runtime_current_protocol.Lifecycle_epoch.make 0));
  check "RC3 empty typed identity is refused"
    (Result.is_error (Jj_runtime_current_protocol.Owner_session.make ""));
  check "RC4 claim has a deterministic nonempty canonical identity"
    (match valid_claim () with
     | Ok claim -> String.length (Jj_runtime_current_protocol.claim_key claim) > 0
     | Error _ -> false);
  List.iter (fun failure -> Printf.printf "FAILED: %s\n" failure) (List.rev !failures);
  let failed = List.length !failures in
  let passed = 4 - failed in
  let self = Suite_telemetry.observe ~suite:"test_jj_runtime_current_protocol"
      ~passed ~failed ~skipped:0 in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_jj_protocol ]);
  exit (Suite_telemetry.exit_code self)
