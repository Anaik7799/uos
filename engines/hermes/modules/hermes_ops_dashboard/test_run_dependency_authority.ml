open Run_dependency_authority

let passed = ref 0
let failed = ref 0
let check name condition =
  if condition then incr passed
  else begin incr failed; Printf.printf "FAILED: %s\n" name end
let require_ok label = function Ok value -> value | Error _ -> failwith label

let digest character = String.make 64 character
let sha256 value =
  value |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex

let binding ?(execution_identity = digest '1') ?(activity_digest = digest '2')
    ?(producer_action_id = "action.producer")
    ?(consumer_action_id = "action.consumer")
    ?(request_digest = digest '3') ?(expires_at_ns = 200L) () =
  make_binding ~execution_identity ~activity_digest ~producer_action_id
    ~consumer_action_id ~request_digest ~expires_at_ns

let () =
  check "D01 production posture remains unavailable"
    (production_posture = `Implemented_unavailable);
  let owner = require_ok "owner"
      (For_test.durable_owner_current ~owner_id:"owner.dispatch"
         ~generation:1 ~owner_digest:(digest '4')) in
  let registry = require_ok "registry" (open_registry ~owner) in
  let sealed_binding = require_ok "binding" (binding ()) in
  let evidence = require_ok "evidence"
      (make_redacted_evidence ~disposition:Dependency_succeeded
         ~evidence_digest:(digest '5')) in
  let registry, carrier, first = require_ok "first issue"
      (issue_once registry ~binding:sealed_binding ~evidence ~now_ns:100L) in
  let registry, replay_carrier, replay = require_ok "replay issue"
      (issue_once registry ~binding:sealed_binding ~evidence ~now_ns:101L) in
  check "D02 exact issue and replay are stable"
    (not first.was_replayed && replay.was_replayed
     && first.receipt_id = replay.receipt_id
     && first.binding_digest = replay.binding_digest
     && first.evidence_digest = digest '5');
  check "D03 exact carrier resolves only to redacted evidence"
    (resolve registry ~owner ~binding:sealed_binding ~carrier ~now_ns:150L = Ok evidence
     && resolve registry ~owner ~binding:sealed_binding
          ~carrier:replay_carrier ~now_ns:150L
        = Ok evidence);
  let conflict = make_redacted_evidence ~disposition:Dependency_unavailable
      ~evidence_digest:(digest '6') |> require_ok "conflict evidence" in
  check "D04 changed evidence conflicts with an existing binding"
    (match issue_once registry ~binding:sealed_binding ~evidence:conflict
             ~now_ns:102L with
     | Error { code = Dependency_conflict; _ } -> true | _ -> false);
  let mismatches =
    [ binding ~execution_identity:(digest 'a') ();
      binding ~activity_digest:(digest 'b') ();
      binding ~producer_action_id:"action.other-producer" ();
      binding ~consumer_action_id:"action.other-consumer" ();
      binding ~request_digest:(digest 'c') ();
      binding ~expires_at_ns:201L () ]
  in
  check "D05 all six request bindings are exact"
    (List.for_all
       (fun candidate -> match candidate with
        | Error _ -> false
        | Ok candidate ->
            match resolve registry ~owner ~binding:candidate ~carrier
                    ~now_ns:150L with
            | Error { code = Dependency_binding_mismatch; _ } -> true
            | _ -> false)
       mismatches);
  let other_owner = require_ok "other owner"
      (For_test.durable_owner_current ~owner_id:"owner.dispatch"
         ~generation:2 ~owner_digest:(digest '7')) in
  check "D06 durable owner generation and digest are exact"
    (match resolve registry ~owner:other_owner ~binding:sealed_binding ~carrier
             ~now_ns:150L with
     | Error { code = Dependency_binding_mismatch; _ } -> true | _ -> false);
  check "D07 expiry is fail-closed"
    (match resolve registry ~owner ~binding:sealed_binding ~carrier ~now_ns:201L with
     | Error { code = Dependency_expired; _ } -> true | _ -> false);
  let foreign_registry = require_ok "foreign registry" (open_registry ~owner) in
  check "D08 carriers are process-local to one registry lineage"
    (match resolve foreign_registry ~owner ~binding:sealed_binding ~carrier
             ~now_ns:150L with
     | Error { code = Foreign_carrier; _ } -> true | _ -> false);
  check "D09 invalid identities and nonfuture expiry are refused"
    (Result.is_error (binding ~producer_action_id:"" ())
     && Result.is_error (binding ~consumer_action_id:"action.producer"
                           ~producer_action_id:"action.producer" ())
     && (match issue_once registry ~binding:sealed_binding ~evidence ~now_ns:200L with
         | Error { code = Dependency_expired; _ } -> true | _ -> false));
  let mutations =
    [ For_test.Drop_execution_identity; Drop_activity_digest;
      Drop_producer_action; Drop_consumer_action; Drop_request_digest;
      Drop_expiry; Drop_durable_owner ] in
  check "D10 source digest covers the exact seven-field authority denominator"
    (String.length source_digest = 64
     && List.for_all
          (fun mutation ->
            source_digest <> For_test.source_digest_with_mutation mutation)
          mutations);
  let rec fill_to_bound registry index =
    if index >= maximum_live_dependencies then registry
    else
      let next_binding =
        require_ok "bounded binding"
          (binding ~request_digest:(sha256 ("request-" ^ string_of_int index))
             ~expires_at_ns:300L ())
      in
      let registry, _, _ =
        require_ok "bounded issue"
          (issue_once registry ~binding:next_binding ~evidence ~now_ns:100L)
      in
      fill_to_bound registry (index + 1)
  in
  let full_registry = fill_to_bound registry 1 in
  let overflow_binding =
    require_ok "overflow binding"
      (binding ~request_digest:(sha256 "overflow") ~expires_at_ns:300L ())
  in
  check "D11 live carrier cardinality is fixed and fail-closed"
    (match
       issue_once full_registry ~binding:overflow_binding ~evidence ~now_ns:100L
     with
     | Error { code = Dependency_capacity_exhausted; _ } -> true
     | _ -> false);
  Printf.printf "run_dependency_authority: %d passed, %d failed\n"
    !passed !failed;
  let telemetry =
    Suite_telemetry.observe ~suite:"test_run_dependency_authority"
      ~passed:!passed ~failed:!failed ~skipped:0 in
  print_string (Suite_telemetry.emit telemetry ~targets:[ Stanza.hermes_ops_dashboard ]);
  exit (Suite_telemetry.exit_code telemetry)
