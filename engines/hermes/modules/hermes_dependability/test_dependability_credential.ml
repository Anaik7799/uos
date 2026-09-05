let passed = ref 0
let failed = ref 0

let check name condition =
  if condition then incr passed
  else begin
    incr failed;
    Printf.printf "FAILED: %s\n" name
  end

let get = function Ok value -> value | Error _ -> failwith "valid fixture refused"

let clock ?(lifetime_ns = 1_000_000_000L) () =
  Dependability_clock.observe ~max_pair_span_ns:1_000_000_000L ~lifetime_ns
  |> get

let rec after_expiry remaining lease_clock =
  if remaining = 0 then None
  else
    let now = clock () in
    if Int64.compare (Dependability_clock.monotonic_finished_ns now)
         (Dependability_clock.expires_monotonic_ns lease_clock) >= 0
    then Some now
    else after_expiry (remaining - 1) lease_clock

let () =
  check "C1 remote identities are bounded canonical names, never URLs"
    (List.for_all
       (fun value -> Result.is_error (Dependability_credential.remote value))
       [ ""; "Origin"; " origin"; "origin/path"; "https://example.test";
         String.make 65 'a' ]
     && Result.is_ok (Dependability_credential.remote "origin"));

  let origin = get (Dependability_credential.remote "origin") in
  let backup = get (Dependability_credential.remote "backup") in
  let ssh =
    Dependability_credential.declare ~remote:origin
      ~transport:Dependability_credential.Ssh_strict
  in
  let https =
    Dependability_credential.declare ~remote:backup
      ~transport:Dependability_credential.Https_tls13
  in
  check "C2 closed transport profiles bind endpoint host-key and TLS policy"
    (Dependability_credential.endpoint_policy ssh = Registered_ssh_endpoint
     && Dependability_credential.host_key_policy ssh = Pinned_host_key_required
     && Dependability_credential.tls_policy ssh = Tls_not_applicable
     && Dependability_credential.endpoint_policy https = Registered_https_endpoint
     && Dependability_credential.host_key_policy https = Host_key_not_applicable
     && Dependability_credential.tls_policy https = Tls_1_3_pinned_server);
  check "C3 strict scrub policy removes every inherited credential/config surface"
    (Dependability_credential.scrubbed_inheritance ssh
     = [ "HOME"; "XDG"; "GIT_CONFIG"; "SSH_AGENT"; "ASKPASS";
         "CREDENTIAL_HELPER" ]
     && String.length (Dependability_credential.scrub_policy_digest ssh) = 64);
  check "C4 remote and transport changes alter the declaration digest"
    (Dependability_credential.declaration_digest ssh
     <> Dependability_credential.declaration_digest https
     && Dependability_credential.configuration_id ssh
        = "JUJUTSU_CREDENTIAL_POLICY");

  let lease_clock = clock () in
  let lease =
    Dependability_credential.declare_unavailable ~clock:lease_clock ssh
  in
  check "C5 missing provider yields opaque nonauthorizing unavailable lease metadata"
    (Dependability_credential.status lease = Unavailable_observed
     && not (Dependability_credential.authorization_permitted lease)
     && Dependability_credential.matches_remote lease origin
     && not (Dependability_credential.matches_remote lease backup));
  check "C6 unavailable credential cannot validate as current authority"
    (Dependability_credential.validate_current ~now:(clock ()) lease
     = Error Dependability_credential.Credential_unavailable);
  let redacted = Dependability_credential.redacted_receipt lease in
  check "C7 durable projection contains only redacted identity metadata"
    (Dependability_credential.redacted_status redacted = Unavailable_observed
     && Dependability_credential.redacted_remote redacted = "origin"
     && String.length (Dependability_credential.redacted_digest redacted) = 64
     && String.length (Dependability_credential.lease_reference lease) = 64);

  let short_clock = clock ~lifetime_ns:1L () in
  let short =
    Dependability_credential.declare_unavailable ~clock:short_clock ssh
  in
  check "C8 monotonic expiry transitions unavailable metadata to absorbing expired"
    (match after_expiry 256 short_clock with
     | None -> false
     | Some now ->
         let expired = get (Dependability_credential.observe ~now short) in
         Dependability_credential.status expired = Expired
         && get (Dependability_credential.observe ~now:(clock ()) expired) == expired
         && Dependability_credential.validate_current ~now expired
            = Error Dependability_credential.Lease_expired);

  let revoked = Dependability_credential.revoke lease in
  check "C9 revocation is absorbing and never restores authorization"
    (Dependability_credential.status revoked = Revoked
     && get (Dependability_credential.observe ~now:(clock ()) revoked) == revoked
     && Dependability_credential.revoke revoked == revoked
     && not (Dependability_credential.authorization_permitted revoked));
  let cleaned = Dependability_credential.cleanup lease in
  check "C10 cleanup is absorbing across later revoke and observation"
    (Dependability_credential.status cleaned = Cleaned
     && get (Dependability_credential.observe ~now:(clock ()) cleaned) == cleaned
     && Dependability_credential.revoke cleaned == cleaned
     && Dependability_credential.cleanup cleaned == cleaned);
  check "C11 lifecycle transitions are redacted and digest-distinct"
    (Dependability_credential.lease_digest lease
     <> Dependability_credential.lease_digest revoked
     && Dependability_credential.lease_digest lease
        <> Dependability_credential.lease_digest cleaned
     && Dependability_credential.validate lease = Ok ()
     && Dependability_credential.validate revoked = Ok ()
     && Dependability_credential.validate cleaned = Ok ());
  check "C12 authority digest kills custody policy and lifecycle mutants"
    (String.length Dependability_credential.source_digest = 64
     && List.for_all
          (fun mutation ->
             Dependability_credential.source_digest
             <> Dependability_credential.For_test.source_digest_with_mutation
                  mutation)
          [ Dependability_credential.For_test.Drop_remote_binding;
            Drop_endpoint_policy; Drop_host_key_policy; Drop_tls_policy;
            Drop_scrub_policy; Permit_serialization; Promote_unavailable;
            Remove_expiry; Remove_revocation; Remove_cleanup ]);

  let self =
    Suite_telemetry.observe ~suite:"test_dependability_credential"
      ~passed:!passed ~failed:!failed ~skipped:0
  in
  print_string
    (Suite_telemetry.emit self
       ~targets:[ Stanza.hermes_dependability_credential ]);
  exit (Suite_telemetry.exit_code self)
