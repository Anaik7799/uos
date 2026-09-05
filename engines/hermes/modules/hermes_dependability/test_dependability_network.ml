let passed = ref 0
let failed = ref 0

let check name condition =
  if condition then incr passed
  else begin
    incr failed;
    Printf.eprintf "FAIL %s\n" name
  end

let get = function Ok value -> value | Error _ -> failwith "valid value refused"

let clock ?(lifetime_ns = 1_000_000_000L) () =
  get
    (Dependability_clock.observe
       ~max_pair_span_ns:Dependability_clock.maximum_pair_span_ns ~lifetime_ns)

let after_expiry receipt =
  let started = Dependability_clock.monotonic_started_ns receipt in
  let expiry = Dependability_clock.expires_monotonic_ns receipt in
  let delta = Int64.succ (Int64.sub expiry started) in
  let rec loop attempts =
    if attempts = 0 then None
    else
      match
        Dependability_clock.observe
          ~max_pair_span_ns:Dependability_clock.maximum_pair_span_ns
          ~lifetime_ns:(Int64.add delta 1_000_000_000L)
      with
      | Error _ -> None
      | Ok now ->
          if Int64.compare (Dependability_clock.monotonic_started_ns now) expiry > 0
          then Some now
          else loop (attempts - 1)
  in
  loop 100_000

let () =
  let origin = get (Dependability_credential.remote "origin") in
  let mirror = get (Dependability_credential.remote "mirror") in
  let ssh =
    Dependability_credential.declare ~remote:origin
      ~transport:Dependability_credential.Ssh_strict
  in
  let https =
    Dependability_credential.declare ~remote:origin
      ~transport:Dependability_credential.Https_tls13
  in
  let synchronization =
    Dependability_network.declare ~remote:origin
      Dependability_network.Remote_synchronization
  in
  let publication =
    Dependability_network.declare ~remote:origin
      Dependability_network.Remote_publication
  in
  let mirror_synchronization =
    Dependability_network.declare ~remote:mirror
      Dependability_network.Remote_synchronization
  in
  check "N1 closed network denominator is remote synchronization plus publication"
    (Dependability_network.all_operations
     = [ Dependability_network.Remote_synchronization;
         Dependability_network.Remote_publication ]);
  check "N2 declarations have closed positive bounded timeout and response policies"
    (List.for_all
       (fun request ->
          Dependability_network.timeout_ms request > 0
          && Dependability_network.timeout_ms request
             <= Dependability_network.maximum_timeout_ms
          && Dependability_network.max_response_bytes request > 0
          && Dependability_network.max_response_bytes request
             <= Dependability_network.maximum_response_bytes)
       [ synchronization; publication ]);
  check "N3 synchronization and publication retain distinct replay postures"
    (Dependability_network.idempotency synchronization
       = Dependability_network.Stable_request_identity_required
     && Dependability_network.idempotency publication
        = Dependability_network.Expected_remote_tip_cas_required);
  check "N4 request digest binds the closed remote operation before opaque custody observation"
    (Dependability_network.request_digest synchronization
     <> Dependability_network.request_digest publication
     && Dependability_network.request_digest synchronization
        <> Dependability_network.request_digest mirror_synchronization);
  let lease_clock = clock () in
  let ssh_lease =
    Dependability_credential.declare_unavailable ~clock:lease_clock ssh
  in
  let https_lease =
    Dependability_credential.declare_unavailable ~clock:lease_clock https
  in
  let observed =
    get
      (Dependability_network.observe ~now:(clock ()) ~lease:ssh_lease
         synchronization)
  in
  check "N5 current unavailable lease remains nonauthorizing unavailable network evidence"
    (Dependability_network.status observed
       = Dependability_network.Unavailable_observed
     && not (Dependability_network.network_permitted observed)
     && Dependability_network.redacted_remote observed = "origin"
     && Dependability_network.redaction observed
        = Dependability_network.Credentials_and_payloads_redacted);
  check "N6 endpoint host-key TLS policy is bound through the opaque credential lease digest"
    (Dependability_network.credential_lease_digest observed
     = Dependability_credential.lease_digest ssh_lease
     && Dependability_network.receipt_digest observed
        <> Dependability_network.receipt_digest
             (get
                (Dependability_network.observe ~now:(clock ()) ~lease:https_lease
                   synchronization)));
  check "N6b receipt binds its observation clock and current exact lease"
    (String.length (Dependability_network.observation_clock_digest observed) = 64
     && Dependability_network.validate_current ~now:(clock ()) ~lease:ssh_lease
          observed
        = Ok ()
     && Dependability_network.validate_current ~now:(clock ())
          ~lease:(Dependability_credential.cleanup ssh_lease) observed
        = Error Dependability_network.Invalid_credential_lease);
  check "N7 a lease for another named remote is refused before any network authority"
    (Dependability_network.observe ~now:(clock ())
       ~lease:(Dependability_credential.declare_unavailable ~clock:(clock ())
                 (Dependability_credential.declare ~remote:mirror
                    ~transport:Dependability_credential.Ssh_strict))
       synchronization
     = Error Dependability_network.Remote_lease_mismatch);
  let short_clock = clock ~lifetime_ns:1L () in
  let short_lease =
    Dependability_credential.declare_unavailable ~clock:short_clock ssh
  in
  check "N8 expiry is bound and cannot be represented as an available network receipt"
    (match after_expiry short_clock with
     | None -> false
     | Some now ->
         match Dependability_network.observe ~now ~lease:short_lease synchronization with
         | Ok receipt ->
             Dependability_network.status receipt = Dependability_network.Expired
             && not (Dependability_network.network_permitted receipt)
         | Error _ -> false);
  let expiring_clock = clock ~lifetime_ns:10_000_000L () in
  let expiring_lease =
    Dependability_credential.declare_unavailable ~clock:expiring_clock ssh
  in
  let before_expiry =
    get
      (Dependability_network.observe ~now:(clock ()) ~lease:expiring_lease
         synchronization)
  in
  check "N8b an unchanged unavailable lease cannot keep an old receipt current after expiry"
    (match after_expiry expiring_clock with
     | None -> false
     | Some now ->
         Dependability_network.validate_current ~now ~lease:expiring_lease
           before_expiry
         = Error Dependability_network.Invalid_credential_lease);
  let cleaned = Dependability_credential.cleanup ssh_lease in
  check "N9 credential cleanup is preserved as an absorbing nonauthorizing network status"
    (match Dependability_network.observe ~now:(clock ()) ~lease:cleaned synchronization with
     | Ok receipt ->
         Dependability_network.status receipt = Dependability_network.Cleaned
         && not (Dependability_network.network_permitted receipt)
     | Error _ -> false);
  check "N10 source digest kills binding, bounds, replay, redaction, expiry, and cleanup mutants"
    (String.length Dependability_network.source_digest = 64
     && List.for_all
          (fun mutation ->
             Dependability_network.source_digest
             <> Dependability_network.For_test.source_digest_with_mutation mutation)
          [ Dependability_network.For_test.Drop_remote_binding;
            Dependability_network.For_test.Drop_credential_binding;
            Dependability_network.For_test.Drop_timeout;
            Dependability_network.For_test.Widen_response_bound;
            Dependability_network.For_test.Drop_idempotency;
            Dependability_network.For_test.Drop_redaction;
            Dependability_network.For_test.Drop_expiry;
            Dependability_network.For_test.Drop_cleanup ]);
  let self =
    Suite_telemetry.observe ~suite:"test_dependability_network" ~passed:!passed
      ~failed:!failed ~skipped:0
  in
  print_string
    (Suite_telemetry.emit self
       ~targets:[ Stanza.hermes_dependability_network ]);
  exit (Suite_telemetry.exit_code self)
