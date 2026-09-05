let failures = ref []
let outcome = ref (0, 0)
let check name condition = if not condition then failures := name :: !failures
let get = function Ok value -> value | Error _ -> failwith "valid fixture refused"

let contains ~needle value =
  let needle_length = String.length needle in
  let rec loop index =
    if index + needle_length > String.length value then false
    else if String.sub value index needle_length = needle then true
    else loop (index + 1)
  in
  needle_length = 0 || loop 0

let request value = get (Jj_id.Request.make value)
let repository value = get (Jj_id.Repository.make value)
let workspace value = get (Jj_id.Workspace.make value)

let field name value = { Jj_algebra.name; value }

let observation artifact requested public_identity =
  { Mainline_carrier_policy.artifact; requested; size_bytes = 16;
    deterministic = true; allowlisted_projection = true; public_identity }

let () =
  let canonical_left =
    get (Jj_algebra.canonicalize [ field "operation" "describe"; field "request" "r-1" ]) in
  let canonical_right =
    get (Jj_algebra.canonicalize [ field "request" "r-1"; field "operation" "describe" ]) in
  check "A1 canonicalization is independent of injected field order"
    (String.equal canonical_left canonical_right
     && Result.is_error
          (Jj_algebra.canonicalize [ field "operation" "a"; field "operation" "b" ]));

  let identity operation request_value =
    get
      (Jj_algebra.identity ~operation ~request:(request request_value)
         ~repository:(repository "repository-main")
         ~workspace:(workspace "workspace-main")) in
  let describe = identity Jj_operation.Describe "request-main" in
  let describe_again = identity Jj_operation.Describe "request-main" in
  let rebase = identity Jj_operation.Rebase "request-main" in
  let other_request = identity Jj_operation.Describe "request-other" in
  check "A2 semantic identities are deterministic and separated"
    (Jj_algebra.identity_digest describe = Jj_algebra.identity_digest describe_again
     && Jj_algebra.identity_separated describe rebase
     && Jj_algebra.identity_separated describe other_request);

  check "A3 policy conjunction is monotone and denial absorbing"
    (Jj_algebra.policy_monotone
       [ Jj_policy.Permit; Jj_policy.Deny Jj_policy.Stale_authority;
         Jj_policy.Permit ]
     && Jj_algebra.policy_conjunction
          [ Jj_policy.Permit; Jj_policy.Deny Jj_policy.Stale_authority ]
        = Jj_policy.Deny Jj_policy.Stale_authority);

  check "A4 missing approval or writer lease absorbs admission"
    (Jj_algebra.guard ~policy:Jj_policy.Permit ~approval:Jj_algebra.Approval_missing
       ~lease:Jj_algebra.Lease_valid = Jj_algebra.Refused Jj_algebra.Approval_absent
     && Jj_algebra.guard ~policy:Jj_policy.Permit ~approval:Jj_algebra.Approval_valid
          ~lease:Jj_algebra.Lease_stale = Jj_algebra.Refused Jj_algebra.Lease_absent
     && Jj_algebra.guard ~policy:Jj_policy.Permit ~approval:Jj_algebra.Approval_valid
          ~lease:Jj_algebra.Lease_valid = Jj_algebra.Guarded);

  let digest_a = String.make 64 'a' in
  let digest_b = String.make 64 'b' in
  check "A5 apply-once distinguishes first apply, replay, and conflict"
    (Jj_algebra.apply_once Jj_algebra.Unapplied ~effect_digest:digest_a
       = Ok (Jj_algebra.Applied digest_a, Jj_algebra.First_applied)
     && Jj_algebra.apply_once (Jj_algebra.Applied digest_a) ~effect_digest:digest_a
        = Ok (Jj_algebra.Applied digest_a, Jj_algebra.Replayed)
     && Jj_algebra.apply_once (Jj_algebra.Applied digest_a) ~effect_digest:digest_b
        = Error Jj_algebra.Apply_conflict);

  check "A6 output bounds derive from the operation declaration"
    (Jj_algebra.output_within_bound Jj_operation.Version ~output_bytes:0
     && Jj_algebra.output_within_bound Jj_operation.Version
          ~output_bytes:(Jj_operation.declaration Jj_operation.Version).budget.max_output_bytes
     && not
          (Jj_algebra.output_within_bound Jj_operation.Version
             ~output_bytes:((Jj_operation.declaration Jj_operation.Version).budget.max_output_bytes + 1)));

  check "A7 readback requires operation and state identity"
    (Jj_algebra.readback_matches ~expected_operation:Jj_operation.Describe
       ~observed_operation:Jj_operation.Describe ~expected_state:digest_a
       ~observed_state:digest_a
     && not
          (Jj_algebra.readback_matches ~expected_operation:Jj_operation.Describe
             ~observed_operation:Jj_operation.Rebase ~expected_state:digest_a
             ~observed_state:digest_a));

  check "A8 recovery operations retain their declared anchor"
    (Jj_algebra.recovery_anchor_valid Jj_operation.Partition_recover
       ~anchor:Jj_algebra.Partition_anchor
     && not
          (Jj_algebra.recovery_anchor_valid Jj_operation.Partition_recover
             ~anchor:Jj_algebra.No_anchor)
     && Jj_algebra.recovery_anchor_valid Jj_operation.Version
          ~anchor:Jj_algebra.No_anchor);

  let source =
    observation Mainline_carrier_policy.Source Mainline_carrier_policy.Track
      "modules/a.ml" in
  let credential =
    observation Mainline_carrier_policy.Credential Mainline_carrier_policy.Exclude
      "credential-redacted" in
  check "A9 source closure excludes private carriers"
    (match Jj_algebra.source_only [ source; credential ] with
     | Ok [ retained ] -> retained.Mainline_carrier_policy.artifact = Mainline_carrier_policy.Source
     | Ok _ | Error _ -> false);

  check "A10 redaction never projects private bytes"
    (let secret = "private-token" in
     let rendered = Jj_algebra.redact ~public_identity:"remote-main" ~private_value:secret in
     rendered <> secret && not (contains ~needle:secret rendered));

  let receipt =
    { Jj_algebra.operation_key = "describe"; disposition = "no-effect";
      state_digest = digest_a } in
  check "A11 four surfaces normalize to the same receipt"
    (List.for_all
       (fun surface -> Jj_algebra.surface_receipt surface receipt = receipt)
       [ Jj_algebra.Ocaml_api; Jj_algebra.Cli; Jj_algebra.Mcp; Jj_algebra.Zenoh ]);

  check "A12 no effect is possible before bridge admission"
    (Jj_algebra.effect_posture ~bridge:Jj_algebra.Bridge_unavailable
       ~requested_effect:true = Jj_algebra.Zero_effect
     && Jj_algebra.effect_posture ~bridge:Jj_algebra.Bridge_admitted
          ~requested_effect:true = Jj_algebra.Effect_prepared);

  check "A13 remote publication remains unavailable without proved CAS"
    (Jj_algebra.remote_publication ~operation:Jj_operation.Git_push
       ~cas:Jj_algebra.Cas_unproved = Jj_algebra.Publication_unavailable
     && Jj_algebra.remote_publication ~operation:Jj_operation.Git_push
          ~cas:Jj_algebra.Cas_proved = Jj_algebra.Publication_prepared
     && Jj_algebra.remote_publication ~operation:Jj_operation.Describe
          ~cas:Jj_algebra.Cas_proved = Jj_algebra.Not_remote_publication);

  check "A14 algebra registry is exact, injective, and digest-bound"
    (List.length Jj_algebra.laws = 13
     && List.length
          (List.sort_uniq String.compare (List.map Jj_algebra.law_id Jj_algebra.laws)) = 13
     && String.length Jj_algebra.source_digest = 64);

  let fragment = Jj_fpp.fragment in
  check "F1 FPP fragment derives exactly one row from each of 34 operations"
    (List.length (Jj_fpp.operations fragment) = 34
     && List.map Jj_fpp.operation (Jj_fpp.operations fragment) = Jj_operation.all);
  check "F2 every operation has one guarded typed command"
    (List.for_all
       (fun row -> Jj_fpp.command_guards (Jj_fpp.command row) <> [])
       (Jj_fpp.operations fragment));
  check "F3 command, response, event, and telemetry ports are total"
    (List.for_all
       (fun row ->
          List.map Jj_fpp.port_role (Jj_fpp.ports row)
          = [ Jj_fpp.Command_input; Jj_fpp.Command_response;
              Jj_fpp.Event_output; Jj_fpp.Telemetry_output ])
       (Jj_fpp.operations fragment));
  check "F4 state machine has guarded admission and terminal states"
    (List.for_all
       (fun row ->
          Jj_fpp.states row
          = [ Jj_fpp.Prepared; Jj_fpp.Admitted; Jj_fpp.Running;
              Jj_fpp.Readback_pending; Jj_fpp.Succeeded; Jj_fpp.Refused;
              Jj_fpp.Failed; Jj_fpp.Unavailable ])
       (Jj_fpp.operations fragment));
  check "F5 every row declares typed lifecycle events"
    (List.for_all (fun row -> List.length (Jj_fpp.events row) = 6)
       (Jj_fpp.operations fragment));
  check "F6 every row declares bounded channels and metrics"
    (List.for_all
       (fun row ->
          List.length (Jj_fpp.channels row) = 4
          && List.length (Jj_fpp.metrics row) = 4)
       (Jj_fpp.operations fragment));
  check "F7 FPP identifiers are globally injective"
    (let ids = Jj_fpp.identities fragment in
     List.length ids = List.length (List.sort_uniq String.compare ids));
  check "F8 FPP fragment inherits its owner and allocates no address window"
    (Jj_fpp.allocation fragment = Jj_fpp.Inherited_runtime_owner);
  check "F9 bridge-unavailable operations are modeled unavailable, never current"
    (List.for_all
       (fun row -> Jj_fpp.activation row <> Jj_fpp.Current)
       (Jj_fpp.operations fragment));
  check "F10 FPP source identity frames every derived row"
    (String.length Jj_fpp.source_digest = 64
     && Jj_fpp.digest fragment = Jj_fpp.source_digest
     && Jj_fpp.For_test.digest_with_operation_key Jj_operation.Describe "mutant"
        <> Jj_fpp.source_digest);

  List.iter (fun name -> Printf.printf "FAILED: %s\n" name) (List.rev !failures);
  let failed = List.length !failures in
  outcome := (24 - failed, failed)
