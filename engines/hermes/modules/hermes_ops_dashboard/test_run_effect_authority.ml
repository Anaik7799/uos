open Run_effect_authority

let passed = ref 0
let failed = ref 0

let check name condition =
  if condition then incr passed
  else begin
    incr failed;
    Printf.printf "FAILED: %s\n" name
  end

let result_or_fail label = function
  | Ok value -> value
  | Error _ -> failwith label

let lowercase_sha256 value =
  String.length value = 64
  && String.for_all
       (function '0' .. '9' | 'a' .. 'f' -> true | _ -> false)
       value

let sha256 value =
  value |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex

let evidence ~receipt_id output =
  result_or_fail "valid redacted evidence"
    (make_redacted_evidence ~receipt_id ~evidence_digest:(sha256 output)
       ~disposition:Evidence_succeeded)

let coordinate =
  { Ops_capability.level = Ops_capability.L3; phase = Ops_capability.Act }

let authority_digest = String.make 64 'a'

let admitted_activity =
  result_or_fail "admit canonical topology activity"
    (Run_topology.admit_activity
       ~stable_id:"activity.verify-sqlite-dependability")

let admitted_declaration = Run_topology.admitted_declaration admitted_activity

let admitted_target_id = admitted_declaration.target_component_id
let admitted_effect_kinds = admitted_declaration.effect_kinds

let admitted_target_authority_digest =
  expected_target_authority_digest ~activity:admitted_activity
    ~target_id:admitted_target_id ~accepted_kinds:admitted_effect_kinds

let register ?(target_id = admitted_target_id)
    ?(authority_digest = admitted_target_authority_digest)
    ?(accepted_kinds = admitted_effect_kinds) () =
  let apply_once ~idempotency_key request =
    match
      make_target_receipt ~idempotency_key ~request ~target_authority_digest:authority_digest
        ~disposition:First_applied
        ~evidence:(evidence ~receipt_id:("evidence." ^ idempotency_key)
                     "admitted-output")
    with
    | Ok receipt -> Ok receipt
    | Error diagnostic -> Error diagnostic.bytes
  in
  register_target ~activity:admitted_activity ~target_id ~authority_digest
    ~accepted_kinds ~apply_once
    ~query:(fun ~idempotency_key:_ -> Ok None)

let invalid_target_rejection = function
  | Error diagnostics ->
      diagnostics <> []
      && List.for_all
           (fun (item : diagnostic) -> item.code = Invalid_effect_target)
           diagnostics
  | Ok _ -> false

let admitted_identity_rejection = function
  | Error diagnostics ->
      diagnostics <> []
      && List.for_all
           (fun (item : diagnostic) ->
             item.code = Invalid_effect_target
             && item.rca_origin = Ops_capability.Control
             && item.hazard = Effect_target_invalid)
           diagnostics
  | Ok () -> false

let low_level_equivalent_target () =
  let apply_once ~idempotency_key request =
    match
      make_target_receipt ~idempotency_key ~request
        ~target_authority_digest:admitted_target_authority_digest
        ~disposition:First_applied
        ~evidence:(evidence ~receipt_id:("evidence." ^ idempotency_key)
                     "low-level-output")
    with
    | Ok receipt -> Ok receipt
    | Error diagnostic -> Error diagnostic.bytes
  in
  result_or_fail "make byte-equivalent low-level target"
    (make_target ~target_id:admitted_target_id
       ~authority_digest:admitted_target_authority_digest
       ~accepted_kinds:admitted_effect_kinds ~apply_once
       ~query:(fun ~idempotency_key:_ -> Ok None))

let request bytes =
  result_or_fail "valid request"
    (make_request ~effect_kind:Dependability_process_attempt
       ~request_bytes:bytes)

let receipt ~key ~request ~disposition ~output =
  result_or_fail "valid target receipt"
    (make_target_receipt ~idempotency_key:key ~request
       ~target_authority_digest:authority_digest ~disposition
       ~evidence:(evidence ~receipt_id:("evidence." ^ key) output))

let fixture_or_fail label = function
  | Ok value -> value
  | Error issue ->
      failwith
        (label ^ ": "
         ^ Dependability_sqlite_test_protocol.string_of_error issue)

let with_location body =
  let registry =
    fixture_or_fail "create SQLite fixture registry"
      (Dependability_sqlite_test_protocol.create ~maximum_live:1)
  in
  let registry, lease =
    fixture_or_fail "acquire in-memory SQLite fixture"
      (Dependability_sqlite_test_protocol.acquire registry
         Dependability_sqlite_test_protocol.In_memory)
  in
  let location =
    fixture_or_fail "resolve opaque SQLite fixture reference"
      (Dependability_sqlite_test_protocol.reference registry lease)
  in
  Fun.protect
    ~finally:(fun () ->
      let registry, _ =
        fixture_or_fail "release SQLite fixture lease"
          (Dependability_sqlite_test_protocol.release registry lease)
      in
      ignore
        (fixture_or_fail "clean SQLite fixture registry"
           (Dependability_sqlite_test_protocol.cleanup registry)))
    (fun () -> body location)

let with_database body =
  with_location (fun location ->
    let database =
      result_or_fail "open scoped database"
        (Dependability_sqlite.open_database ~location
           ~maximum_total_attempts:1)
    in
    Fun.protect
      ~finally:(fun () ->
        ignore (Dependability_sqlite.For_test.dispose database))
      (fun () -> body database))

type target_probe = {
  target : target;
  apply_calls : int ref;
  query_calls : int ref;
  durable_receipt : target_receipt option ref;
}

let make_counter_target ?(accepted_kinds = [ Dependability_process_attempt ])
    ?(increment_then_raise = false) ?(commit_then_raise = false)
    ?(commit_then_error = false) ?(post_apply_query_error = false)
    ?(wrong_receipt_key = None) ?initial_receipt () =
  let apply_calls = ref 0 in
  let query_calls = ref 0 in
  let durable_receipt = ref initial_receipt in
  let apply_once ~idempotency_key request =
    incr apply_calls;
    if increment_then_raise then
      failwith "counter incremented before receipt transport failed"
    else
      let receipt_key =
        match wrong_receipt_key with
        | None -> idempotency_key
        | Some key -> key
      in
      let committed =
        receipt ~key:receipt_key ~request ~disposition:First_applied
          ~output:(Printf.sprintf "counter=%d" !apply_calls)
      in
      durable_receipt := Some committed;
      if commit_then_raise then
        failwith "durable receipt committed before transport raised"
      else if commit_then_error then
        Error "durable receipt committed before transport returned Error"
      else Ok committed
  in
  let query ~idempotency_key =
    incr query_calls;
    if post_apply_query_error && !apply_calls > 0 then
      Error "post-apply target-native query unavailable"
    else
      match !durable_receipt with
      | Some receipt when String.equal receipt.idempotency_key idempotency_key ->
          Ok (Some receipt)
      | Some _ | None -> Ok None
  in
  let target =
    result_or_fail "valid target"
      (make_target ~target_id:"durable-counter"
         ~authority_digest ~accepted_kinds ~apply_once ~query)
  in
  { target; apply_calls; query_calls; durable_receipt }

let is_indeterminate_for key request_digest = function
  | Error (Indeterminate (Indeterminate_effect state, diagnostic)) ->
      String.equal state.idempotency_key key
      && String.equal state.request_digest request_digest
      && String.equal state.target_authority_digest authority_digest
      && state.no_replay
      && diagnostic.coordinate = coordinate
      && diagnostic.rca_origin = Ops_capability.Environment
      && diagnostic.hazard = Effect_outcome_uncertain
  | Error (Indeterminate ((Pending _ | Applied _), _)) -> false
  | Ok _
  | Error
      (Invalid_request _ | Key_reused_with_different_request _
      | Target_unavailable _ | Ledger_failure _) ->
      false

let () =
  let request_a = request "attempt=7\000sqlite" in
  let request_a_again = request "attempt=7\000sqlite" in
  let request_b = request "attempt=8\000sqlite" in
  Printf.printf "[tdd] topology-derived effect target registry\n";
  check "T1 target authority digest is stable lowercase SHA-256"
    (lowercase_sha256 admitted_target_authority_digest
     && admitted_target_authority_digest =
        expected_target_authority_digest ~activity:admitted_activity
          ~target_id:admitted_target_id
          ~accepted_kinds:admitted_effect_kinds);
  check "T2 wrong topology target id is rejected"
    (invalid_target_rejection (register ~target_id:"suiteWorker" ()));
  check "T3 substituted target authority digest is rejected"
    (invalid_target_rejection
       (register ~authority_digest:(String.make 64 'b') ()));
  check "T4 topology effect-kind omission is rejected"
    (invalid_target_rejection
       (register ~accepted_kinds:[ Dependability_process_attempt;
          Verification_suite_execution ] ()));
  check "T5 topology effect-kind substitution is rejected"
    (invalid_target_rejection
       (register ~accepted_kinds:[ Durable_artifact_publication ] ()));
  check "T6 duplicate topology effect kind is rejected"
    (invalid_target_rejection
       (register ~accepted_kinds:
          (Dependability_process_attempt :: admitted_effect_kinds) ()));
  begin match register () with
  | Error _ ->
      check "T7 canonical topology target is registered" false;
      check "T8 admitted interpreter opens only from the registry" false;
      check "T9 admitted interpreter applies through the low-level ledger" false;
      check "T10 canonical admitted interpreter identity validates" false;
      check "T11 byte-equivalent low-level interpreter is refused" false;
      check "T12 foreign activity digest is refused" false;
      check "T13 foreign topology digest is refused" false;
      check "T14 foreign target digest is refused" false;
      check "T15 foreign effect-denominator digest is refused" false
  | Ok registry ->
      check "T7 canonical topology target is registered" true;
      with_database (fun database ->
        match open_admitted_interpreter ~database ~registry ~coordinate with
        | Error _ ->
            check "T8 admitted interpreter opens only from the registry" false;
            check "T9 admitted interpreter applies through the low-level ledger" false;
            check "T10 canonical admitted interpreter identity validates" false;
            check "T11 byte-equivalent low-level interpreter is refused" false;
            check "T12 foreign activity digest is refused" false;
            check "T13 foreign topology digest is refused" false;
            check "T14 foreign target digest is refused" false;
            check "T15 foreign effect-denominator digest is refused" false
        | Ok interpreter ->
            check "T8 admitted interpreter opens only from the registry" true;
            check "T9 admitted interpreter applies through the low-level ledger"
              (match
                 apply_once interpreter ~idempotency_key:"admitted-attempt"
                   request_a
               with
               | Ok receipt ->
                   receipt.target_authority_digest =
                     admitted_target_authority_digest
                   && receipt.request_digest = request_a.request_digest
               | Error _ -> false);
            check "T10 canonical admitted interpreter identity validates"
              (Result.is_ok
                 (validate_admitted_interpreter ~activity:admitted_activity
                    interpreter));
            let identity_mutations =
              [ ("T12 foreign activity digest is refused",
                 For_test.Activity_digest);
                ("T13 foreign topology digest is refused",
                 For_test.Topology_authority_digest);
                ("T14 foreign target digest is refused",
                 For_test.Target_digest);
                ("T15 foreign effect-denominator digest is refused",
                 For_test.Effect_kinds_digest) ]
            in
            List.iter
              (fun (name, mutation) ->
                let mutant =
                  For_test.mutate_admitted_identity mutation interpreter
                in
                check name
                  (admitted_identity_rejection
                     (validate_admitted_interpreter
                        ~activity:admitted_activity mutant)))
              identity_mutations;
            close interpreter;
            let low_level =
              result_or_fail "open byte-equivalent low-level interpreter"
                (open_interpreter ~database
                   ~target:(low_level_equivalent_target ()) ~coordinate)
            in
            check "T11 byte-equivalent low-level interpreter is refused"
              (admitted_identity_rejection
                 (validate_admitted_interpreter ~activity:admitted_activity
                    low_level));
            close low_level)
  end;
  let target_schema = canonical_jj_target_registry_schema () in
  let bindings = jj_target_registry_bindings target_schema in
  let expected_actions =
    Run_topology.task7a_declaration_activities
    |> List.concat_map (fun activity ->
         Run_topology.declarative_activity_actions activity
         |> List.map (fun action -> (activity, action)))
  in
  check "T16 immutable action-target schema is exact and nonauthorizing"
    (List.length bindings = 107
     && List.length bindings = List.length expected_actions
     && Result.is_ok (validate_jj_target_registry_schema_exact target_schema)
     && lowercase_sha256 (jj_target_registry_schema_digest target_schema)
     && List.for_all2
          (fun
            ((activity : Run_topology.declarative_activity),
             (action : Run_topology.declarative_action))
            (binding : action_target_binding) ->
            binding.binding_activity_id = activity.stable_id
            && binding.binding_action_id = action.stable_id
            && binding.binding_target_component_id = action.target_component_id
            && binding.binding_effect_kind = action.effect_kind
            && binding.binding_target_authority_digest = None
            && binding.binding_target_authority_status
               = Concrete_target_authority_unavailable
            && lowercase_sha256 binding.binding_dependency_schema_id)
          expected_actions bindings);
  let schema_mutations =
    [ For_test.Drop_action_binding; Add_action_binding;
      Duplicate_action_binding; Reorder_action_bindings;
      Cross_activity_binding; Swap_target_component; Swap_effect_kind;
      Change_dependency_schema; Forge_target_authority ]
  in
  check "T17 every exact registry membership field is mutation-sensitive"
    (List.for_all
       (fun mutation ->
         let mutant = For_test.mutate_jj_target_registry_schema mutation in
         Result.is_error (validate_jj_target_registry_schema_exact mutant)
         && jj_target_registry_schema_digest mutant
            <> jj_target_registry_schema_digest target_schema)
       schema_mutations);
  let jj_registry = create_jj_target_registry () in
  let first_schema = prepare_jj_target_registry_schema_once jj_registry in
  let replay_schema = prepare_jj_target_registry_schema_once jj_registry in
  check "T18 exact schema replay is stable"
    (match first_schema, replay_schema with
     | Ok first, Ok replay ->
         not first.target_schema_was_replayed
         && replay.target_schema_was_replayed
         && first.target_schema_receipt_digest
            = replay.target_schema_receipt_digest
         && first.target_schema_binding_count = List.length bindings
     | _ -> false);
  check "T19 changed schema conflicts and conflict is absorbing"
    (match
       For_test.prepare_jj_target_registry_schema_with_mutation jj_registry
         For_test.Drop_action_binding,
       prepare_jj_target_registry_schema_once jj_registry
     with
     | Error first_conflict, Error replay_conflict ->
         jj_target_registry_schema_state jj_registry = Target_schema_conflict
         && List.for_all
              (fun diagnostic ->
                diagnostic.code = Target_registry_schema_conflict)
              (first_conflict @ replay_conflict)
     | _ -> false);
  check "T20 current view remains unavailable on exact Task-9 prerequisites"
    (jj_target_registry_current_posture = `Implemented_unavailable
     && target_registry_prerequisites
        = [ Concrete_target_authority_digests; Task9_target_current_views;
            Request_bound_phase_action_registry;
            Conditional_action_control_registry ]
     && match first_schema with
        | Error _ -> false
        | Ok receipt ->
            begin match
              close_jj_target_registry_current_unavailable jj_registry receipt
            with
            | Error unavailable ->
                unavailable.target_registry_missing_prerequisites
                = target_registry_prerequisites
            | Ok _ -> false
            end);
  check "T21 redacted evidence exposes only receipt identity/digest/disposition"
    (let item = evidence ~receipt_id:"evidence.non-authorizing" "secret-output" in
     evidence_receipt_id item = "evidence.non-authorizing"
     && evidence_digest item = sha256 "secret-output"
     && evidence_disposition item = Evidence_succeeded
     && Yojson.Safe.Util.member "evidenceDigest" (redacted_evidence_json item)
        = `String (sha256 "secret-output")
     && Yojson.Safe.Util.member "output" (redacted_evidence_json item) = `Null);
  check "E1 request identity is stable lowercase SHA-256 and content sensitive"
    (lowercase_sha256 request_a.request_digest
     && String.equal request_a.request_digest request_a_again.request_digest
     && not (String.equal request_a.request_digest request_b.request_digest));
  check "E2 empty request bytes fail closed"
    (match
       make_request ~effect_kind:Dependability_process_attempt
         ~request_bytes:""
     with
     | Error diagnostic ->
         diagnostic.code = Invalid_effect_request
         && diagnostic.hazard = Effect_request_invalid
     | Ok _ -> false);
  check "E3 target declares a nonempty duplicate-free closed effect-kind set"
    (match
       make_target ~target_id:"bad" ~authority_digest
         ~accepted_kinds:[]
         ~apply_once:(fun ~idempotency_key:_ _ -> Error "not called")
         ~query:(fun ~idempotency_key:_ -> Error "not called")
     with
     | Error diagnostic ->
         diagnostic.code = Invalid_effect_target
         && diagnostic.hazard = Effect_target_invalid
     | Ok _ -> false);
  with_database (fun database ->
    let probe = make_counter_target () in
    let interpreter =
      result_or_fail "open interpreter"
        (open_interpreter ~database ~target:probe.target ~coordinate)
    in
    let first_result =
      apply_once interpreter ~idempotency_key:"attempt-7" request_a
    in
    let replay_result =
      apply_once interpreter ~idempotency_key:"attempt-7" request_a
    in
    check "E4 first apply queries once, applies once, and persists exact receipt"
      (match first_result with
       | Ok first ->
           !(probe.query_calls) = 1 && !(probe.apply_calls) = 1
           && first.disposition = First_applied
           && String.equal first.idempotency_key "attempt-7"
           && String.equal first.request_digest request_a.request_digest
           && String.equal first.target_authority_digest authority_digest
           && lowercase_sha256 first.evidence.evidence_digest
           && String.equal first.evidence.evidence_receipt_id
                "evidence.attempt-7"
           && lowercase_sha256 first.receipt_digest
       | Error _ -> false);
    check "E5 replay returns byte-identical persisted receipt without target call"
      (match first_result, replay_result with
       | Ok first, Ok replay ->
           first = replay && !(probe.query_calls) = 1
           && !(probe.apply_calls) = 1
       | (Ok _ | Error _), (Ok _ | Error _) -> false);
    close interpreter;
    let restarted =
      result_or_fail "restart interpreter"
        (open_interpreter ~database ~target:probe.target ~coordinate)
    in
    let after_restart =
      apply_once restarted ~idempotency_key:"attempt-7" request_a
    in
    check "E6 caller-owned database makes restart replay durable and call-free"
      (match first_result, after_restart with
       | Ok first, Ok replay ->
           first = replay && !(probe.query_calls) = 1
           && !(probe.apply_calls) = 1
       | (Ok _ | Error _), (Ok _ | Error _) -> false);
    check "E7 query exposes the exact durable Applied state"
      (match first_result, query restarted ~idempotency_key:"attempt-7" with
       | Ok first, Ok (Some (Applied persisted)) -> persisted = first
       | (Ok _ | Error _),
         (Ok (Some (Pending _ | Indeterminate_effect _ | Applied _))
         | Ok None | Error _) ->
           false);
    check "E8 stable key with changed request digest is a permanent conflict"
      (match apply_once restarted ~idempotency_key:"attempt-7" request_b with
       | Error
           (Key_reused_with_different_request
             { idempotency_key; persisted_digest; observed_digest;
               diagnostic }) ->
           String.equal idempotency_key "attempt-7"
           && String.equal persisted_digest request_a.request_digest
           && String.equal observed_digest request_b.request_digest
           && diagnostic.coordinate = coordinate
           && diagnostic.rca_origin = Ops_capability.Control
           && diagnostic.hazard = Effect_identity_conflict
       | Ok _
       | Error
           (Invalid_request _ | Target_unavailable _ | Indeterminate _
           | Ledger_failure _) ->
           false);
    check "E9 conflict never re-enters the target"
      (!(probe.query_calls) = 1 && !(probe.apply_calls) = 1);
    close restarted);
  with_database (fun database ->
    let rejected_probe =
      make_counter_target ~accepted_kinds:[ Durable_artifact_publication ] ()
    in
    let interpreter =
      result_or_fail "open rejecting interpreter"
        (open_interpreter ~database ~target:rejected_probe.target ~coordinate)
    in
    check "E10 undeclared effect kind is rejected before ledger or target"
      (match apply_once interpreter ~idempotency_key:"wrong-kind" request_a with
       | Error (Invalid_request diagnostic) ->
           diagnostic.code = Effect_kind_not_accepted
           && diagnostic.hazard = Effect_kind_unauthorized
           && !(rejected_probe.query_calls) = 0
           && !(rejected_probe.apply_calls) = 0
       | Ok _
       | Error
           (Key_reused_with_different_request _ | Target_unavailable _
           | Indeterminate _ | Ledger_failure _) ->
           false);
    close interpreter);
  with_database (fun database ->
    let target_receipt =
      receipt ~key:"recovered" ~request:request_a ~disposition:Replayed
        ~output:"counter=previously-committed"
    in
    let probe = make_counter_target ~initial_receipt:target_receipt () in
    let interpreter =
      result_or_fail "open recovery interpreter"
        (open_interpreter ~database ~target:probe.target ~coordinate)
    in
    let recovered =
      apply_once interpreter ~idempotency_key:"recovered" request_a
    in
    check "E11 target-native query is called once and prevents duplicate apply"
      (match recovered with
       | Ok recovered ->
           recovered = target_receipt && !(probe.query_calls) = 1
           && !(probe.apply_calls) = 0
       | Error _ -> false);
    let replay =
      apply_once interpreter ~idempotency_key:"recovered" request_a
    in
    check "E12 recovered receipt is durably replayed without another query"
      (match recovered, replay with
       | Ok recovered, Ok replay ->
           replay = recovered && !(probe.query_calls) = 1
           && !(probe.apply_calls) = 0
       | (Ok _ | Error _), (Ok _ | Error _) -> false);
    close interpreter);
  with_database (fun database ->
    let probe = make_counter_target ~increment_then_raise:true () in
    let interpreter =
      result_or_fail "open indeterminate interpreter"
        (open_interpreter ~database ~target:probe.target ~coordinate)
    in
    let first = apply_once interpreter ~idempotency_key:"raise-after-apply" request_a in
    check "E13 increment-then-raise records Indeterminate with no replay"
      (is_indeterminate_for "raise-after-apply" request_a.request_digest first
       && !(probe.query_calls) = 2 && !(probe.apply_calls) = 1);
    let again = apply_once interpreter ~idempotency_key:"raise-after-apply" request_a in
    check "E14 same-process indeterminate state never calls target again"
      (is_indeterminate_for "raise-after-apply" request_a.request_digest again
       && !(probe.query_calls) = 2 && !(probe.apply_calls) = 1);
    close interpreter;
    let restarted =
      result_or_fail "restart indeterminate interpreter"
        (open_interpreter ~database ~target:probe.target ~coordinate)
    in
    let after_restart =
      apply_once restarted ~idempotency_key:"raise-after-apply" request_a
    in
    check "E15 restart preserves Indeterminate and no-replay call count"
      (is_indeterminate_for "raise-after-apply" request_a.request_digest
         after_restart
       && !(probe.query_calls) = 2 && !(probe.apply_calls) = 1);
    close restarted);
  with_database (fun database ->
    let probe = make_counter_target ~wrong_receipt_key:(Some "other-key") () in
    let interpreter =
      result_or_fail "open receipt-mismatch interpreter"
        (open_interpreter ~database ~target:probe.target ~coordinate)
    in
    let result = apply_once interpreter ~idempotency_key:"expected-key" request_a in
    check "E16 target receipt echo mismatch is indeterminate, never credited"
      (is_indeterminate_for "expected-key" request_a.request_digest result
       && !(probe.query_calls) = 1 && !(probe.apply_calls) = 1);
    let replay = apply_once interpreter ~idempotency_key:"expected-key" request_a in
    check "E17 malformed target receipt is never automatically replayed"
      (is_indeterminate_for "expected-key" request_a.request_digest replay
       && !(probe.query_calls) = 1 && !(probe.apply_calls) = 1);
    close interpreter);
  with_database (fun database ->
    let probe = make_counter_target ~commit_then_raise:true () in
    let interpreter =
      result_or_fail "open post-raise recovery interpreter"
        (open_interpreter ~database ~target:probe.target ~coordinate)
    in
    let recovered =
      apply_once interpreter ~idempotency_key:"committed-then-raised" request_a
    in
    check "E18 post-failure query recovers a receipt committed before raise"
      (match recovered with
       | Ok receipt ->
           String.equal receipt.idempotency_key "committed-then-raised"
           && receipt.disposition = First_applied
           && !(probe.query_calls) = 2 && !(probe.apply_calls) = 1
       | Error _ -> false);
    close interpreter;
    let restarted =
      result_or_fail "restart post-raise recovery interpreter"
        (open_interpreter ~database ~target:probe.target ~coordinate)
    in
    check "E19 recovered post-failure receipt is durable and call-free"
      (match
         recovered,
         apply_once restarted ~idempotency_key:"committed-then-raised"
           request_a
       with
       | Ok first, Ok replay ->
           first = replay && !(probe.query_calls) = 2
           && !(probe.apply_calls) = 1
       | (Ok _ | Error _), (Ok _ | Error _) -> false);
    close restarted);
  with_database (fun database ->
    let probe = make_counter_target ~commit_then_error:true () in
    let interpreter =
      result_or_fail "open post-Error recovery interpreter"
        (open_interpreter ~database ~target:probe.target ~coordinate)
    in
    check "E20 post-failure query recovers a receipt committed before Error"
      (match
         apply_once interpreter ~idempotency_key:"committed-then-error"
           request_a
       with
       | Ok receipt ->
           String.equal receipt.idempotency_key "committed-then-error"
           && !(probe.query_calls) = 2 && !(probe.apply_calls) = 1
       | Error _ -> false);
    close interpreter);
  with_database (fun database ->
    let probe =
      make_counter_target ~increment_then_raise:true
        ~post_apply_query_error:true ()
    in
    let interpreter =
      result_or_fail "open post-failure query-error interpreter"
        (open_interpreter ~database ~target:probe.target ~coordinate)
    in
    let first =
      apply_once interpreter ~idempotency_key:"raise-query-error" request_a
    in
    check "E21 post-failure query Error remains durably Indeterminate"
      (is_indeterminate_for "raise-query-error" request_a.request_digest first
       && !(probe.query_calls) = 2 && !(probe.apply_calls) = 1);
    close interpreter;
    let restarted =
      result_or_fail "restart post-failure query-error interpreter"
        (open_interpreter ~database ~target:probe.target ~coordinate)
    in
    let replay =
      apply_once restarted ~idempotency_key:"raise-query-error" request_a
    in
    check "E22 post-failure query Error is never automatically replayed"
      (is_indeterminate_for "raise-query-error" request_a.request_digest replay
       && !(probe.query_calls) = 2 && !(probe.apply_calls) = 1);
    close restarted);
  Printf.printf "Run_effect_authority: %d passed, %d failed\n" !passed !failed;
  let self =
    Suite_telemetry.observe ~suite:"test_run_effect_authority" ~passed:!passed
      ~failed:!failed ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_ops_dashboard ]);
  exit (Suite_telemetry.exit_code self)
