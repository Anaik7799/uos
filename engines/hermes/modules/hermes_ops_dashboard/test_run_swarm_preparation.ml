let checks = ref 0
let failures = ref 0

let check name condition =
  incr checks;
  if not condition then begin
    incr failures;
    Printf.eprintf
      "FAIL coordinate=L3/act rca=Implementation hazard=HZ-SWARM-BRIDGE-01 check=%s\n"
      name
  end

let result_or_fail label = function
  | Ok value -> value
  | Error errors -> failwith (label ^ ": " ^ String.concat "; " errors)

let sqlite_activity =
  result_or_fail "admit SQLite activity"
    (Run_topology.admit_activity
       ~stable_id:"activity.verify-sqlite-dependability")

let repository_activity =
  result_or_fail "admit repository activity"
    (Run_topology.admit_activity ~stable_id:"activity.verify-repository")

let execution_identity = String.make 64 'a'

let formal_process =
  Jj_action_kind.formal_process ~tool:Jj_action_kind.Gospel
    ~case:Jj_action_kind.Positive

let prepare activity action =
  Run_swarm_preparation.prepare ~execution_identity ~activity ~action
    ~input_payload:"dependency-result"

let rebuild ?stable_id ?preparation_id ?work
    (action : Run_topology.declarative_action) =
  let choose supplied original = Option.value supplied ~default:original in
  Run_topology.For_test.declarative_action_work
    ~stable_id:(choose stable_id action.stable_id)
    ~command_id:action.command_id ~assigned_agent_id:action.assigned_agent_id
    ~dependency_ids:action.dependency_ids ~selector_id:action.selector_id
    ~required_capability_id:action.required_capability_id
    ~context_requirement_ids:action.context_requirement_ids
    ~target_component_id:action.target_component_id
    ~effect_kind:action.effect_kind ~work:(choose work action.work)
    ~preparation_id:(choose preparation_id action.preparation_id)

let member name = function
  | `Assoc fields -> List.assoc_opt name fields
  | _ -> None

let request_work_matches action prepared =
  match Yojson.Safe.from_string prepared.Run_swarm_preparation.request_bytes,
        action.Run_topology.work
  with
  | json, Run_topology.Topology_gate ->
      member "work_kind" json = Some (`String "topology-gate")
  | json, Repository_build { profile; build_command } ->
      member "work_kind" json = Some (`String "repository-build")
      && member "profile_id" json =
           Some (`String (match profile with Verification_fast -> "fast"
                         | Verification_full -> "full"))
      && member "build_command" json = Some (`String build_command)
  | json, Repository_verification_suite { profile; suite_id; executable } ->
      member "work_kind" json =
        Some (`String "repository-verification-suite")
      && member "profile_id" json =
           Some (`String (match profile with Verification_fast -> "fast"
                         | Verification_full -> "full"))
      && member "suite_id" json = Some (`String suite_id)
      && member "executable" json = Some (`String executable)
  | json, work ->
      member "work_kind" json = Some (`String "closed-task7a-work")
      && member "work_id" json = Some (`String (Run_topology.action_work_id work))
  | exception Yojson.Json_error _ -> false

let work_projection_kind = function
  | Run_topology.Topology_gate -> "topology-gate"
  | Repository_build _ -> "repository-build"
  | Repository_verification_suite _ -> "repository-verification-suite"
  | Clock_work _ -> "clock"
  | Filesystem_work _ -> "filesystem"
  | External_resource_work _ -> "external-resource"
  | Repository_source_work _ -> "repository-source"
  | Approval_nonce_work _ -> "approval-nonce"
  | Writer_lease_work _ -> "writer-lease"
  | Network_scope_work _ -> "network-scope"
  | Credential_lease_work _ -> "credential-lease"
  | Activation_transition_work _ -> "activation-transition"
  | Mutation_frontier_work _ -> "mutation-frontier"
  | Materialization_work _ -> "materialization"
  | Candidate_verification_work _ -> "candidate-verification"
  | Formal_oracle_work _ -> "formal-oracle"
  | Jujutsu_work _ -> "jujutsu-operation"
  | Jujutsu_readback_work _ -> "jujutsu-readback"
  | Completion_receipt_work _ -> "completion-receipt"

let sha256_denominator values =
  values |> String.concat "\000" |> Digestif.SHA256.digest_string
  |> Digestif.SHA256.to_hex

let replace_first update (activity : Run_topology.declarative_activity) =
  match activity.actions with
  | [] -> activity
  | first :: rest -> { activity with actions = update first :: rest }

let registry_error activity =
  Result.is_error
    (Run_swarm_bridge.For_test.action_registry_from_declaration activity)

let () =
  Run_swarm_bridge.For_test.reset_engine_call_count ();
  let sqlite_actions = Run_topology.admitted_actions sqlite_activity in
  let repository_actions = Run_topology.admitted_actions repository_activity in
  let repository_declaration =
    Run_topology.admitted_declaration repository_activity
  in
  check "A01 topology admits the exact SQLite and repository denominators"
    (List.length sqlite_actions = 5 && List.length repository_actions = 281);
  let all_effect_kinds : Run_effect_authority.effect_kind list =
    [ Run_topology.Dependability_process_attempt;
      Run_topology.Verification_suite_execution;
      Run_topology.Durable_artifact_publication;
      Run_topology.External_resource_observation;
      Run_topology.Repository_source_observation;
      Run_topology.Approval_nonce_consumption;
      Run_topology.Writer_lease_transition;
      Run_topology.Production_activation_transition;
      Run_topology.Network_scope_transition;
      Run_topology.Credential_lease_transition;
      Run_topology.Controlled_filesystem_materialization;
      Run_topology.Candidate_tree_verification;
      Run_topology.Jujutsu_observation; Run_topology.Jujutsu_local_mutation;
      Run_topology.Jujutsu_history_rewrite; Run_topology.Jujutsu_recovery;
      Run_topology.Jujutsu_remote_synchronization;
      Run_topology.Jujutsu_remote_publish;
      Run_topology.Formal_oracle_execution ]
  in
  check "A01a effect authority manifest aliases all 19 topology effects"
    (all_effect_kinds = Run_topology.effect_kinds
     && List.length all_effect_kinds = 19
     && List.map Run_effect_authority.string_of_effect_kind all_effect_kinds
        = List.map Run_topology.effect_kind_id Run_topology.effect_kinds);
  let task7a_work_representatives =
    [ Run_topology.Clock_work Jj_action_kind.Acquire_clock;
      Filesystem_work Jj_action_kind.Observe_tree;
      External_resource_work Jj_action_kind.Observe_external_resource;
      Repository_source_work Jj_action_kind.Observe_repository_source;
      Approval_nonce_work Jj_action_kind.Consume_approval_nonce;
      Writer_lease_work Jj_action_kind.Acquire_writer_lease;
      Network_scope_work Jj_action_kind.Acquire_network_scope;
      Credential_lease_work Jj_action_kind.Acquire_credential_lease;
      Activation_transition_work
        Jj_action_kind.Activate_source_recovery_branch;
      Mutation_frontier_work
        (Jj_action_kind.Set_activity_frontier
           Jj_action_kind.Reconciled_terminal);
      Materialization_work Jj_action_kind.Materialize_candidate;
      Candidate_verification_work Jj_action_kind.Toolchain_check;
      Formal_oracle_work formal_process;
      Jujutsu_work
        { operation = Jj_operation.Version; role = Run_topology.Execute };
      Jujutsu_readback_work Jj_action_kind.Readback_jj_state;
      Completion_receipt_work Jj_action_kind.Reserve_completion_receipt ]
  in
  let observed_work_classes =
    List.map work_projection_kind task7a_work_representatives
  in
  let observed_completion_receipt_ids =
    [ Run_topology.Completion_receipt_work
        Jj_action_kind.Reserve_completion_receipt;
      Completion_receipt_work Jj_action_kind.Finalize_completion_receipt ]
    |> List.map Run_topology.action_work_id
  in
  check "A01b consumer covers the exact 16 work classes and both completion subkinds"
    (observed_work_classes = Run_topology.task7a_action_work_class_ids
     && List.length observed_work_classes = 16
     && sha256_denominator observed_work_classes
        = Run_topology.task7a_action_work_class_digest
     && observed_completion_receipt_ids
        = Run_topology.task7a_completion_receipt_work_ids
     && sha256_denominator observed_completion_receipt_ids
        = Run_topology.task7a_completion_receipt_work_digest);
  let source_mutations =
    [ Run_swarm_preparation.For_test.Drop_schema_version;
      Drop_activity_identity_field; Drop_topology_authority_field;
      Drop_action_identity_field; Drop_assignment_field; Drop_command_field;
      Drop_dependency_ids_field; Drop_dependency_input_field;
      Drop_execution_identity_field; Drop_action_digest_field;
      Drop_preparation_id_field; Drop_target_component_field;
      Drop_effect_kind_field; Reorder_request_fields; Drop_effect_denominator;
      Drop_work_class_denominator; Drop_completion_receipt_subdenominator;
      Drop_work_projection_fields; Drop_idempotency_fields;
      Enable_noncanonical_action ]
  in
  check "A01c preparation source identity binds every field and closed denominator"
    (String.length Run_swarm_preparation.source_digest = 64
     && List.for_all
          (fun mutation ->
            Run_swarm_preparation.source_digest
            <> Run_swarm_preparation.For_test.source_digest_with_mutation
                 mutation)
          source_mutations);
  let task7a_actions =
    List.concat_map
      (fun (activity : Run_topology.declarative_activity) -> activity.actions)
      Run_topology.task7a_declaration_activities
  in
  check "A01d non-admitted Task7A declarations cannot enter preparation"
    (task7a_actions <> []
     && List.for_all
          (fun action ->
            Result.is_error (prepare repository_activity action)
            && Result.is_error (prepare sqlite_activity action))
          task7a_actions);
  check "A02 canonical 281-action repository registry validates"
    (Result.is_ok
       (Run_swarm_bridge.For_test.action_registry_from_declaration
          repository_declaration));
  check "A03 foreign repository activity identity is rejected"
    (registry_error
       { repository_declaration with
         stable_id = "activity.verify-repository.foreign" });
  check "A04 duplicate repository action is rejected"
    (match repository_actions with
     | first :: second :: rest ->
         registry_error
           { repository_declaration with
             actions = first :: rebuild ~stable_id:first.stable_id second :: rest }
     | [] | [ _ ] -> false);
  check "A05 unknown repository action is rejected"
    (registry_error
       (replace_first
          (rebuild ~stable_id:"action.verify-repository.unknown")
          repository_declaration));
  check "A06 cross-activity action is rejected before execution"
    (match sqlite_actions with
     | sqlite_action :: _ ->
         registry_error
           (replace_first (fun _ -> sqlite_action) repository_declaration)
     | [] -> false);
  check "R02 every canonical repository action has a closed preparation"
    (List.for_all (fun action -> Result.is_ok (prepare repository_activity action))
       repository_actions);
  check "R03 every prepared request explicitly binds its typed work carrier"
    (List.for_all
       (fun action ->
         match prepare repository_activity action with
         | Ok prepared -> request_work_matches action prepared
         | Error _ -> false)
       repository_actions
     && List.for_all
          (fun action ->
            match prepare sqlite_activity action with
            | Ok prepared -> request_work_matches action prepared
            | Error _ -> false)
          sqlite_actions);
  begin match sqlite_actions, repository_actions with
  | sqlite_action :: _, repository_build :: repository_suite :: _ ->
      check "R04 a SQLite action is foreign to repository activity"
        (Result.is_error (prepare repository_activity sqlite_action));
      check "R05 a repository action is foreign to SQLite activity"
        (Result.is_error (prepare sqlite_activity repository_build));
      check "R06 an unknown action identity is rejected"
        (Result.is_error
           (prepare repository_activity
              (rebuild ~stable_id:"action.verify-repository.unknown"
                 repository_suite)));
      check "R07 substituted build work is rejected"
        (Result.is_error
           (prepare repository_activity
              (rebuild
                 ~work:(Run_topology.Repository_build
                   { profile = Verification_full;
                     build_command = "dune build @mutant" })
                 repository_build)));
      begin match repository_suite.work with
      | Run_topology.Repository_verification_suite
          { profile = _; suite_id; executable } ->
          check "R08 substituted verification profile is rejected"
            (Result.is_error
               (prepare repository_activity
                  (rebuild
                     ~work:(Run_topology.Repository_verification_suite
                       { profile = Verification_fast; suite_id; executable })
                     repository_suite)));
          check "R09 substituted suite executable is rejected"
            (Result.is_error
               (prepare repository_activity
                  (rebuild
                     ~work:(Run_topology.Repository_verification_suite
                       { profile = Verification_full; suite_id;
                         executable = executable ^ ".mutant" })
                     repository_suite)))
      | _ ->
          check "R08 repository suite mutation fixture exists" false;
          check "R09 repository suite mutation fixture exists" false
      end;
      check "R10 substituted preparation identity is rejected"
        (Result.is_error
           (prepare repository_activity
              (rebuild ~preparation_id:"prepare.verify-repository.mutant"
                 repository_suite)));
      check "R11 idempotency identity is activity-bound"
        (not
           (String.equal
              (Run_swarm_preparation.idempotency_key ~execution_identity
                 ~activity:sqlite_activity ~action:sqlite_action)
              (Run_swarm_preparation.idempotency_key ~execution_identity
                 ~activity:repository_activity ~action:sqlite_action)))
  | _ ->
      List.iter
        (fun name -> check name false)
        [ "R04 cross-activity fixture exists"; "R05 cross-activity fixture exists";
          "R06 unknown-action fixture exists"; "R07 build fixture exists";
          "R08 profile fixture exists"; "R09 executable fixture exists";
          "R10 preparation fixture exists"; "R11 activity identity fixture exists" ]
  end;
  check "A07 every registry and preparation rejection reaches zero engine calls"
    (Run_swarm_bridge.For_test.engine_call_count () = 0);
  Printf.printf "test_run_swarm_preparation: checks=%d failures=%d\n"
    !checks !failures;
  let self =
    Suite_telemetry.observe ~suite:"test_run_swarm_preparation"
      ~passed:(!checks - !failures) ~failed:!failures ~skipped:0
  in
  print_string
    (Suite_telemetry.emit self ~targets:[ Stanza.hermes_ops_dashboard ]);
  exit (Suite_telemetry.exit_code self)
