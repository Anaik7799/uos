let checks = ref 0
let failures = ref 0

let check name condition =
  incr checks;
  if not condition then begin
    incr failures;
    Printf.eprintf "FAIL: %s\n" name
  end

let contains text needle =
  let width = String.length needle and length = String.length text in
  let rec loop index =
    index + width <= length
    && (String.sub text index width = needle || loop (index + 1))
  in
  width > 0 && loop 0

let find_substring text needle =
  let width = String.length needle and length = String.length text in
  let rec loop index =
    if index + width > length then None
    else if String.sub text index width = needle then Some index
    else loop (index + 1)
  in
  if width = 0 then Some 0 else loop 0

let expected_components =
  [ "runSupervisor"; "reteUlGate"; "ravenGate"; "stpaFmeaGate";
    "ruliadAnalyzer"; "stanReliability"; "z3FormalGate";
    "swarmExecutionBridge"; "suiteWorker"; "runEventStore";
    "resourceSampler"; "zenohRunBridge"; "dreamGateway";
    "bonsaiDashboard"; "uiIntentCompiler"; "uiEffectInterpreter";
    "webglRenderer"; "assuranceGate"; "completionGate" ]

let expected_effect_kinds =
  [ Run_topology.Dependability_process_attempt;
    Verification_suite_execution;
    Durable_artifact_publication;
    External_resource_observation;
    Repository_source_observation;
    Approval_nonce_consumption;
    Writer_lease_transition;
    Production_activation_transition;
    Network_scope_transition;
    Credential_lease_transition;
    Controlled_filesystem_materialization;
    Candidate_tree_verification;
    Jujutsu_observation;
    Jujutsu_local_mutation;
    Jujutsu_history_rewrite;
    Jujutsu_recovery;
    Jujutsu_remote_synchronization;
    Jujutsu_remote_publish;
    Formal_oracle_execution ]

let expected_effect_kind_ids =
  [ "dependability-process-attempt";
    "verification-suite-execution";
    "durable-artifact-publication";
    "external-resource-observation";
    "repository-source-observation";
    "approval-nonce-consumption";
    "writer-lease-transition";
    "production-activation-transition";
    "network-scope-transition";
    "credential-lease-transition";
    "controlled-filesystem-materialization";
    "candidate-tree-verification";
    "jujutsu-observation";
    "jujutsu-local-mutation";
    "jujutsu-history-rewrite";
    "jujutsu-recovery";
    "jujutsu-remote-synchronization";
    "jujutsu-remote-publish";
    "formal-oracle-execution" ]

let other_models () =
  Run_fpp_authority.models ()
  |> List.filter_map (fun (owner, model) ->
         if owner = Fpp_window_authority.Operations then None
         else Some (Fpp_window_authority.owner_name owner, model))

let manifest_equal left right = left = right

let canonical_activity () =
  match List.filter
      (fun (activity : Run_topology.declarative_activity) ->
        activity.stable_id = "activity.verify-sqlite-dependability")
      Run_topology.authority.activities with
  | [ activity ] -> activity
  | _ -> failwith "expected one canonical SQLite operations activity"

let with_activity activity =
  { Run_topology.authority with
    activities =
      List.map
        (fun (item : Run_topology.declarative_activity) ->
          if item.stable_id = "activity.verify-sqlite-dependability" then
            activity
          else item)
        Run_topology.authority.activities }

let check_activity_mutant name mutate =
  let canonical = canonical_activity () in
  let mutant = mutate canonical in
  check (name ^ " is rejected")
    (Run_topology.validate_authority (with_activity mutant) <> []);
  check (name ^ " changes the activity digest")
    (Run_topology.activity_digest_of mutant
     <> Run_topology.activity_digest_of canonical)

let action ~stable_id ~command_id ~assigned_agent_id ~dependency_ids
    ~selector_id ~required_capability_id ~effect_kind ~preparation_id =
  Run_topology.For_test.declarative_action ~stable_id ~command_id
    ~assigned_agent_id ~dependency_ids ~selector_id ~required_capability_id
    ~context_requirement_ids:
      [ "context.exact-head"; "context.assurance-bundle";
        "context.owned-run-event-store"; "context.resource-envelope" ]
    ~target_component_id:"runEventStore" ~effect_kind ~preparation_id

let exact_actions () =
  [ action ~stable_id:"action.sqlite.formal"
      ~command_id:"RunSqliteFormalGate" ~assigned_agent_id:"z3FormalGate"
      ~dependency_ids:[] ~selector_id:"miq.z3-formal"
      ~required_capability_id:"capability.formal-check"
      ~effect_kind:Run_topology.Dependability_process_attempt
      ~preparation_id:"prepare.sqlite.formal";
    action ~stable_id:"action.sqlite.stress"
      ~command_id:"RunSqliteStressGate" ~assigned_agent_id:"stpaFmeaGate"
      ~dependency_ids:[ "action.sqlite.formal" ]
      ~selector_id:"miq.stpa-fmea"
      ~required_capability_id:"capability.verify-full"
      ~effect_kind:Run_topology.Dependability_process_attempt
      ~preparation_id:"prepare.sqlite.stress";
    action ~stable_id:"action.sqlite.reliability"
      ~command_id:"RunSqliteReliabilityGate" ~assigned_agent_id:"ravenGate"
      ~dependency_ids:[ "action.sqlite.stress" ] ~selector_id:"miq.raven"
      ~required_capability_id:"capability.verify-full"
      ~effect_kind:Run_topology.Dependability_process_attempt
      ~preparation_id:"prepare.sqlite.reliability";
    action ~stable_id:"action.sqlite.full"
      ~command_id:"RunSqliteFullGate" ~assigned_agent_id:"reteUlGate"
      ~dependency_ids:[ "action.sqlite.reliability" ]
      ~selector_id:"miq.rete-ul"
      ~required_capability_id:"capability.fpp-check"
      ~effect_kind:Run_topology.Verification_suite_execution
      ~preparation_id:"prepare.sqlite.full";
    action ~stable_id:"action.sqlite.swarm-verification"
      ~command_id:"VerifySqliteDependabilitySwarm"
      ~assigned_agent_id:"reteUlGate"
      ~dependency_ids:[ "action.sqlite.full" ] ~selector_id:"miq.rete-ul"
      ~required_capability_id:"capability.fpp-check"
      ~effect_kind:Run_topology.Durable_artifact_publication
      ~preparation_id:"prepare.sqlite.swarm-verification" ]

let effect_kind_string = Run_topology.effect_kind_id

let json_strings values = `List (List.map (fun value -> `String value) values)

let expected_action_work_fields = function
  | Run_topology.Topology_gate ->
      [ ("workKind", `String "topology-gate") ]
  | Repository_build { profile; build_command } ->
      [ ("workKind", `String "repository-build");
        ("profileId", `String
           (match profile with Verification_fast -> "fast"
            | Verification_full -> "full"));
        ("buildCommand", `String build_command) ]
  | Repository_verification_suite { profile; suite_id; executable } ->
      [ ("workKind", `String "repository-verification-suite");
        ("profileId", `String
           (match profile with Verification_fast -> "fast"
            | Verification_full -> "full"));
        ("suiteId", `String suite_id);
        ("executable", `String executable) ]
  | (Clock_work _ | Filesystem_work _ | External_resource_work _
    | Repository_source_work _ | Approval_nonce_work _ | Writer_lease_work _
    | Network_scope_work _ | Credential_lease_work _
    | Activation_transition_work _ | Mutation_frontier_work _
    | Materialization_work _ | Candidate_verification_work _
    | Formal_oracle_work _ | Jujutsu_work _ | Jujutsu_readback_work _
    | Completion_receipt_work _) as work ->
      [ ("workKind", `String "closed-task7a-work");
        ("workId", `String (Run_topology.action_work_id work)) ]

let expected_action_json (item : Run_topology.declarative_action) =
  `Assoc
    ([ ("stableId", `String item.stable_id);
      ("commandId", `String item.command_id);
      ("assignedAgentId", `String item.assigned_agent_id);
      ("dependencyIds", json_strings item.dependency_ids);
      ("selectorId", `String item.selector_id);
      ("requiredCapabilityId", `String item.required_capability_id);
      ("contextRequirementIds", json_strings item.context_requirement_ids);
      ("targetComponentId", `String item.target_component_id);
      ("effectKind", `String (effect_kind_string item.effect_kind));
      ("preparationId", `String item.preparation_id) ]
     @ expected_action_work_fields item.work)

let exact_action_graph_json () =
  `List (List.map expected_action_json (exact_actions ()))

let rec normalize_json = function
  | `Assoc fields ->
      `Assoc
        (fields
         |> List.map (fun (name, value) -> (name, normalize_json value))
         |> List.sort (fun (left, _) (right, _) -> String.compare left right))
  | `List values -> `List (List.map normalize_json values)
  | value -> value

let exact_action_graph observed =
  normalize_json observed = normalize_json (exact_action_graph_json ())

let decoded_quoted_after marker text =
  match find_substring text marker with
  | None -> None
  | Some marker_index ->
      let start = marker_index + String.length marker in
      let length = String.length text in
      let buffer = Buffer.create 1_024 in
      let rec loop index escaped =
        if index >= length then None
        else
          let character = text.[index] in
          if character = '"' && not escaped then
            try Some (Scanf.unescaped (Buffer.contents buffer))
            with Scanf.Scan_failure _ -> None
          else begin
            Buffer.add_char buffer character;
            loop (index + 1) (character = '\\' && not escaped)
          end
      in
      loop start false

let action_graph_from_quoted ~activity_id marker text =
  let activity_line =
    String.split_on_char '\n' text
    |> List.find_opt (fun line -> contains line activity_id)
  in
  match Option.bind activity_line (decoded_quoted_after marker) with
  | None -> None
  | Some encoded ->
      begin
        try Some (Yojson.Safe.from_string encoded)
        with Yojson.Json_error _ -> None
      end

let action_graph_from_json ~activity_id ~container text =
  try
    match Yojson.Safe.from_string text with
    | `Assoc fields ->
        begin match List.assoc_opt container fields with
        | Some (`List elements) ->
            List.find_map
              (function
                | `Assoc fields
                  when List.assoc_opt "stableId" fields
                       = Some (`String activity_id) ->
                    List.assoc_opt "actions" fields
                | _ -> None)
              elements
        | _ -> None
        end
    | _ -> None
  with Yojson.Json_error _ -> None

let action_activity actions = { (canonical_activity ()) with actions }

let replace_action ?stable_id ?command_id ?assigned_agent_id ?dependency_ids
    ?selector_id ?required_capability_id ?context_requirement_ids
    ?target_component_id ?effect_kind ?preparation_id ?work
    (item : Run_topology.declarative_action) =
  Run_topology.For_test.declarative_action_work
    ~stable_id:(Option.value stable_id ~default:item.stable_id)
    ~command_id:(Option.value command_id ~default:item.command_id)
    ~assigned_agent_id:
      (Option.value assigned_agent_id ~default:item.assigned_agent_id)
    ~dependency_ids:(Option.value dependency_ids ~default:item.dependency_ids)
    ~selector_id:(Option.value selector_id ~default:item.selector_id)
    ~required_capability_id:
      (Option.value required_capability_id
         ~default:item.required_capability_id)
    ~context_requirement_ids:
      (Option.value context_requirement_ids
         ~default:item.context_requirement_ids)
    ~target_component_id:
      (Option.value target_component_id ~default:item.target_component_id)
    ~effect_kind:(Option.value effect_kind ~default:item.effect_kind)
    ~work:(Option.value work ~default:item.work)
    ~preparation_id:
      (Option.value preparation_id ~default:item.preparation_id)

let mutate_action_at index mutate actions =
  List.mapi (fun observed item -> if observed = index then mutate item else item)
    actions

let check_action_mutant name mutate =
  let canonical = action_activity (exact_actions ()) in
  let mutant = action_activity (mutate (exact_actions ())) in
  check (name ^ " is rejected independently")
    (Run_topology.validate_authority (with_activity mutant) <> []);
  check (name ^ " changes the activity digest")
    (Run_topology.activity_digest_of mutant
     <> Run_topology.activity_digest_of canonical);
  check (name ^ " changes the topology source digest")
    (Run_topology.source_digest_of (with_activity mutant)
     <> Run_topology.source_digest_of (with_activity canonical))

let repository_activity_id = "activity.verify-repository"
let repository_build_action_id = "action.verify-repository.build"
let repository_context_requirement_ids =
  [ "context.exact-head"; "context.assurance-bundle";
    "context.owned-run-event-store"; "context.resource-envelope" ]

let repository_miq_routes =
  [ { Run_topology.selector_id = "miq.raven";
      required_capability_id = "capability.verify-full";
      assigned_agent_id = "ravenGate" } ]

let repository_action ~stable_id ~command_id ~dependency_ids ~preparation_id
    ~work =
  Run_topology.For_test.declarative_action_work ~stable_id ~command_id
    ~assigned_agent_id:"ravenGate" ~dependency_ids ~selector_id:"miq.raven"
    ~required_capability_id:"capability.verify-full"
    ~context_requirement_ids:repository_context_requirement_ids
    ~target_component_id:"suiteWorker"
    ~effect_kind:Run_topology.Verification_suite_execution ~work
    ~preparation_id

let exact_repository_actions suites =
  let build =
    repository_action ~stable_id:repository_build_action_id
      ~command_id:"BuildRepositoryVerification" ~dependency_ids:[]
      ~preparation_id:"prepare.verify-repository.build.full"
      ~work:(Run_topology.Repository_build
        { profile = Run_topology.Verification_full;
          build_command = "dune build --pkg=disabled 2>&1" })
  in
  let suite_actions =
    List.map
      (fun (suite_id, executable) ->
        repository_action
          ~stable_id:("action.verify-repository.suite." ^ suite_id)
          ~command_id:("ExecuteRepositoryVerificationSuite." ^ suite_id)
          ~dependency_ids:[ repository_build_action_id ]
          ~preparation_id:("prepare.verify-repository.suite." ^ suite_id)
          ~work:(Run_topology.Repository_verification_suite
            { profile = Run_topology.Verification_full; suite_id; executable }))
      suites
  in
  build :: suite_actions

let exact_repository_activity suites =
  let actions = exact_repository_actions suites in
  { Run_topology.stable_id = repository_activity_id;
    bridge_component_id = "swarmExecutionBridge";
    target_component_id = "suiteWorker";
    target_state = "repository-verification-complete";
    intent = "Build and verify the complete repository suite denominator";
    constraints =
      [ "execute through Run_swarm_bridge only";
        "use the full Ops_verify discovery profile";
        "run the repository build exactly once before every suite";
        "treat every absent or skipped suite as unavailable" ];
    success_criteria =
      [ "the repository build succeeds";
        "every discovered full-profile suite executes exactly once";
        "the terminal receipt preserves every suite result" ];
    required_capability_ids = [ "capability.verify-full" ];
    context_requirement_ids = repository_context_requirement_ids;
    miq_routes = repository_miq_routes;
    effect_kinds = [ Run_topology.Verification_suite_execution ];
    command_ids =
      List.map
        (fun (item : Run_topology.declarative_action) -> item.command_id)
        actions;
    actions }

let repository_activity_from_authority () =
  List.find_opt
    (fun (item : Run_topology.declarative_activity) ->
      item.stable_id = repository_activity_id)
    Run_topology.authority.activities

let check_repository_action_mutant name suites mutate =
  let canonical = exact_repository_activity suites in
  let mutant = { canonical with actions = mutate canonical.actions } in
  let gaps =
    Run_topology.For_test.action_graph_gaps_for
      ~expected_actions:canonical.actions mutant
  in
  check (name ^ " is rejected by the exact repository action oracle")
    (gaps <> []);
  check (name ^ " changes the repository activity digest")
    (Run_topology.activity_digest_of mutant
     <> Run_topology.activity_digest_of canonical)

let () =
  Printf.printf "[red-green] typed operations topology\n";
  check "exact component denominator"
    (Run_topology.component_names = expected_components);
  check "Task7A effect-kind denominator is exact"
    (Run_topology.effect_kinds = expected_effect_kinds);
  check "Task7A effect-kind rendering denominator is exact"
    (List.map Run_topology.effect_kind_id Run_topology.effect_kinds
     = expected_effect_kind_ids);
  check "controlled lifecycle-state denominator is exact"
    (List.map Run_topology.controlled_lifecycle_state_id
       Run_topology.controlled_lifecycle_states
     = [ "declared"; "prepared"; "admitted"; "running"; "readback";
         "terminal"; "refused"; "indeterminate"; "stale" ]);
  check "conditional control-state denominator is exact"
    (List.map Run_topology.conditional_control_state_id
       Run_topology.conditional_control_states
     = [ "guarded"; "consume-ready"; "action-terminal";
         "decision-pending"; "continue-selected"; "branch-selected";
         "decision-indeterminate" ]);
  check "conditional control-event denominator is exact"
    (List.map Run_topology.conditional_control_event_id
       Run_topology.conditional_control_events
     = [ "prefix-complete"; "decision-committed"; "decision-replayed";
         "condition-not-selected-recorded"; "decision-refused" ]);
  check "conditional channel-kind denominator is exact"
    (List.map Run_topology.conditional_channel_kind_id
       Run_topology.conditional_channel_kinds
     = [ "bounded-family-prefix"; "decision-receipt";
         "selected-branch-identity"; "node-disposition" ]);
  check "Task7A topology remains implemented but execution-unavailable"
    (Run_topology.live_execution_posture = `Implemented_unavailable);
  check "operations FPP validates"
    (Fpp_model.validate Run_topology.model = []);
  let topology_gaps = Run_topology.validate () in
  List.iter (fun gap -> Printf.eprintf "TOPOLOGY GAP: %s\n" gap) topology_gaps;
  check "typed authority validates" (topology_gaps = []);
  check "all metrics have one FPP channel"
    (Run_topology.metric_channel_gaps () = []);
  check "requirements resolve to exactly one verifier"
    (Run_topology.requirement_gaps () = []);
  let interval_gaps = Run_topology.interval_gaps (other_models ()) in
  List.iter (Printf.eprintf "INTERVAL GAP: %s\n") interval_gaps;
  check "operations window is disjoint from every existing FPP model"
    (interval_gaps = []);
  check "no execution bypasses the swarm execution bridge"
    (Run_topology.execution_bypass_gaps Run_topology.authority = []);
  check "Dream Bonsai and WebGL cannot reach admission"
    (Run_topology.ui_admission_gaps Run_topology.authority = []);
  check "topology is non-vacuous"
    (Run_topology.authority.ports <> []
     && Run_topology.authority.channels <> []
     && Run_topology.authority.edges <> []
     && Run_topology.authority.requirements <> []);
  check "source digest is a lowercase SHA-256"
    (String.length Run_topology.source_digest = 64
     && String.equal Run_topology.source_digest
          (String.lowercase_ascii Run_topology.source_digest));
  begin match Run_topology.authority.components with
  | first :: rest ->
      let changed =
        { Run_topology.authority with
          components = { first with purpose = first.purpose ^ " changed" } :: rest }
      in
      check "source digest is sensitive to every authored component field"
        (Run_topology.source_digest_of changed <> Run_topology.source_digest)
  | [] -> check "digest mutant fixture exists" false
  end;

  Printf.printf "[tdd] closed admitted activity envelope\n";
  check "an empty activity lookup is refused"
    (Result.is_error (Run_topology.admit_activity ~stable_id:""));
  check "an unknown activity lookup is refused"
    (Result.is_error
       (Run_topology.admit_activity ~stable_id:"activity.unknown"));
  begin match Run_topology.admit_activity
      ~stable_id:"activity.verify-sqlite-dependability" with
  | Error _ -> check "canonical topology activity is admitted" false
  | Ok admitted ->
      let activity = Run_topology.admitted_declaration admitted in
      let digest = Run_topology.admitted_activity_digest admitted in
      check "canonical topology activity is admitted" true;
      check "admitted activity retains the authority digest"
        (Run_topology.admitted_activity_authority_digest admitted
         = Run_topology.source_digest);
      check "admitted activity digest binds the canonical declaration"
        (digest = Run_topology.activity_digest_of activity
         && String.length digest = 64
         && digest = String.lowercase_ascii digest);
      check "admitted target state is closed"
        (activity.target_state = "sqlite-dependability-verified");
      check "admitted capability denominator is exact"
        (activity.required_capability_ids =
           [ "capability.formal-check"; "capability.verify-full";
             "capability.fpp-check" ]);
      check "admitted context denominator is exact"
        (activity.context_requirement_ids =
           [ "context.exact-head"; "context.assurance-bundle";
             "context.owned-run-event-store"; "context.resource-envelope" ]);
      check "admitted MIQ route denominator is exact"
        (List.map (fun (route : Run_topology.miq_route) -> route.selector_id)
           activity.miq_routes
         = [ "miq.rete-ul"; "miq.raven"; "miq.stpa-fmea";
             "miq.z3-formal" ]);
      check "admitted effect-kind denominator is exact"
        (activity.effect_kinds =
           [ Run_topology.Dependability_process_attempt;
             Run_topology.Verification_suite_execution;
             Run_topology.Durable_artifact_publication ])
  end;
  check "missing canonical activity is rejected"
    (Run_topology.validate_authority
       { Run_topology.authority with activities = [] } <> []);
  check_activity_mutant "empty activity stable id"
    (fun item -> { item with stable_id = "" });
  check_activity_mutant "substituted activity stable id"
    (fun item -> { item with stable_id = "activity.substituted" });
  check_activity_mutant "empty bridge id"
    (fun item -> { item with bridge_component_id = "" });
  check_activity_mutant "substituted bridge id"
    (fun item -> { item with bridge_component_id = "suiteWorker" });
  check_activity_mutant "empty target id"
    (fun item -> { item with target_component_id = "" });
  check_activity_mutant "substituted target id"
    (fun item -> { item with target_component_id = "suiteWorker" });
  check_activity_mutant "empty target state"
    (fun item -> { item with target_state = "" });
  check_activity_mutant "substituted target state"
    (fun item -> { item with target_state = "sqlite-close-attempted" });
  check_activity_mutant "empty activity intent"
    (fun item -> { item with intent = "" });
  check_activity_mutant "missing constraints"
    (fun item -> { item with constraints = [] });
  check_activity_mutant "missing success criteria"
    (fun item -> { item with success_criteria = [] });
  check_activity_mutant "missing capability ids"
    (fun item -> { item with required_capability_ids = [] });
  check_activity_mutant "duplicate capability id"
    (fun item ->
      { item with required_capability_ids =
          "capability.formal-check" :: item.required_capability_ids });
  check_activity_mutant "unknown capability id"
    (fun item ->
      { item with required_capability_ids = [ "capability.unknown" ] });
  check_activity_mutant "missing context requirements"
    (fun item -> { item with context_requirement_ids = [] });
  check_activity_mutant "duplicate context requirement"
    (fun item ->
      { item with context_requirement_ids =
          "context.exact-head" :: item.context_requirement_ids });
  check_activity_mutant "unknown context requirement"
    (fun item ->
      { item with context_requirement_ids = [ "context.unknown" ] });
  check_activity_mutant "missing MIQ routes"
    (fun item -> { item with miq_routes = [] });
  check_activity_mutant "duplicate MIQ selector"
    (fun item ->
      match item.miq_routes with
      | first :: _ -> { item with miq_routes = first :: item.miq_routes }
      | [] -> item);
  check_activity_mutant "unknown MIQ selector"
    (fun item ->
      match item.miq_routes with
      | first :: rest ->
          { item with miq_routes =
              { first with selector_id = "miq.unknown" } :: rest }
      | [] -> item);
  check_activity_mutant "unknown MIQ capability"
    (fun item ->
      match item.miq_routes with
      | first :: rest ->
          { item with miq_routes =
              { first with required_capability_id = "capability.unknown" }
              :: rest }
      | [] -> item);
  check_activity_mutant "substituted MIQ agent"
    (fun item ->
      match item.miq_routes with
      | first :: rest ->
          { item with miq_routes =
              { first with assigned_agent_id = "suiteWorker" } :: rest }
      | [] -> item);
  check_activity_mutant "missing effect kinds"
    (fun item -> { item with effect_kinds = [] });
  check_activity_mutant "duplicate effect kind"
    (fun item ->
      { item with effect_kinds =
          Run_topology.Dependability_process_attempt :: item.effect_kinds });
  check_activity_mutant "substituted effect denominator"
    (fun item ->
      { item with effect_kinds =
          [ Run_topology.Verification_suite_execution ] });
  check_activity_mutant "missing command ids"
    (fun item -> { item with command_ids = [] });
  check_activity_mutant "duplicate command id"
    (fun item ->
      match item.command_ids with
      | first :: _ -> { item with command_ids = first :: item.command_ids }
      | [] -> item);
  check_activity_mutant "unknown command id"
    (fun item -> { item with command_ids = [ "RunUnknownGate" ] });

  Printf.printf "[tdd] topology-owned immutable action graph\n";
  let expected_actions = exact_actions () in
  let exact_action_activity = action_activity expected_actions in
  check "the independent exact five-action fixture satisfies the authority"
    (Run_topology.validate_authority (with_activity exact_action_activity) = []);
  check "the production activity exposes the exact ordered action denominator"
    ((canonical_activity ()).actions = expected_actions);
  check "the exact action order is Formal Stress Reliability Full Swarm"
    (List.map
       (fun (item : Run_topology.declarative_action) -> item.command_id)
       expected_actions
     = [ "RunSqliteFormalGate"; "RunSqliteStressGate";
         "RunSqliteReliabilityGate"; "RunSqliteFullGate";
         "VerifySqliteDependabilitySwarm" ]);
  check "each action digest is lowercase SHA-256 and unique"
    (let digests = List.map Run_topology.action_digest_of expected_actions in
     List.for_all
       (fun digest ->
         String.length digest = 64
         && digest = String.lowercase_ascii digest)
       digests
     && List.length digests = List.length (List.sort_uniq String.compare digests));
  check_action_mutant "empty action stable id"
    (mutate_action_at 0 (replace_action ~stable_id:""));
  check_action_mutant "duplicate action stable id"
    (mutate_action_at 1
       (replace_action ~stable_id:"action.sqlite.formal"));
  check_action_mutant "unknown action agent"
    (mutate_action_at 0
       (replace_action ~assigned_agent_id:"agent.unknown"));
  check_action_mutant "unknown action dependency"
    (mutate_action_at 1
       (replace_action ~dependency_ids:[ "action.sqlite.unknown" ]));
  check_action_mutant "self action dependency"
    (mutate_action_at 1
       (replace_action ~dependency_ids:[ "action.sqlite.stress" ]));
  check_action_mutant "duplicate action dependency"
    (mutate_action_at 1
       (replace_action
          ~dependency_ids:[ "action.sqlite.formal"; "action.sqlite.formal" ]));
  check_action_mutant "cyclic action dependency"
    (mutate_action_at 0
       (replace_action
          ~dependency_ids:[ "action.sqlite.swarm-verification" ]));
  check_action_mutant "action MIQ selector mismatch"
    (mutate_action_at 0 (replace_action ~selector_id:"miq.raven"));
  check_action_mutant "action capability mismatch"
    (mutate_action_at 0
       (replace_action ~required_capability_id:"capability.verify-full"));
  check_action_mutant "missing action context coverage"
    (mutate_action_at 0
       (replace_action
          ~context_requirement_ids:[ "context.exact-head" ]));
  check_action_mutant "wrong action target"
    (mutate_action_at 0
       (replace_action ~target_component_id:"suiteWorker"));
  check_action_mutant "wrong action effect"
    (mutate_action_at 0
       (replace_action ~effect_kind:Run_topology.Durable_artifact_publication));
  check_action_mutant "wrong action command"
    (mutate_action_at 0
       (replace_action ~command_id:"RunUnknownGate"));
  check_action_mutant "empty action preparation"
    (mutate_action_at 0 (replace_action ~preparation_id:""));
  check_action_mutant "wrong action preparation"
    (mutate_action_at 0
       (replace_action ~preparation_id:"prepare.sqlite.substituted"));
  check_action_mutant "omitted action denominator" (fun _ -> []);
  check_action_mutant "reordered action denominator" List.rev;

  Printf.printf "[tdd-red] closed full-repository verification activity\n";
  let repository_suites = Ops_verify.discover_suites Ops_verify.Full in
  let repository_actions = exact_repository_actions repository_suites in
  let repository_activity = exact_repository_activity repository_suites in
  let suite_ids = List.map fst repository_suites in
  check "Ops_verify full-suite authority is non-vacuous sorted and unique"
    (repository_suites <> []
     && suite_ids = List.sort String.compare suite_ids
     && suite_ids = List.sort_uniq String.compare suite_ids);
  check "repository action denominator is exactly build plus every full suite"
    (List.length repository_actions = 1 + List.length repository_suites
     && List.map
          (fun (item : Run_topology.declarative_action) -> item.stable_id)
          repository_actions
        = repository_build_action_id
          :: List.map
               (fun suite_id ->
                 "action.verify-repository.suite." ^ suite_id)
               suite_ids);
  check "repository build work binds the exact full profile and command"
    (match repository_actions with
     | first :: _ ->
         first.work =
           Run_topology.Repository_build
             { profile = Run_topology.Verification_full;
               build_command = "dune build --pkg=disabled 2>&1" }
         && first.dependency_ids = []
     | [] -> false);
  check "each repository suite work binds profile id executable and build dependency"
    (match repository_actions with
     | _build :: suite_actions ->
         List.map2
           (fun (action : Run_topology.declarative_action)
                (suite_id, executable) ->
             action.work =
               Run_topology.Repository_verification_suite
                 { profile = Run_topology.Verification_full;
                   suite_id; executable }
             && action.dependency_ids = [ repository_build_action_id ])
           suite_actions repository_suites
         |> List.for_all Fun.id
     | [] -> false);
  check "repository activity is not the SQLite dependability intent"
    (repository_activity.stable_id
       <> (canonical_activity ()).stable_id
     && repository_activity.target_component_id = "suiteWorker"
     && repository_activity.target_state = "repository-verification-complete"
     && repository_activity.intent <> (canonical_activity ()).intent);
  check "independent repository action fixture is structurally exact"
    (Run_topology.For_test.action_graph_gaps_for
       ~expected_actions:repository_actions repository_activity
     = []);
  check "repository activity lookup and admission are available"
    (match Run_topology.admit_activity ~stable_id:repository_activity_id with
     | Ok admitted ->
         Run_topology.admitted_declaration admitted = repository_activity
         && Run_topology.admitted_actions admitted = repository_actions
     | Error _ -> false);
  check "production authority carries the exact second repository activity"
    (repository_activity_from_authority () = Some repository_activity);
  check "production repository graph is the exact build-plus-suite denominator"
    (match repository_activity_from_authority () with
     | Some activity -> activity.actions = repository_actions
     | None -> false);
  check_repository_action_mutant "repository profile substitution"
    repository_suites
    (mutate_action_at 0
       (replace_action
          ~work:(Run_topology.Repository_build
            { profile = Run_topology.Verification_fast;
              build_command = "dune build --pkg=disabled 2>&1" })));
  check_repository_action_mutant "repository build command substitution"
    repository_suites
    (mutate_action_at 0
       (replace_action
          ~work:(Run_topology.Repository_build
            { profile = Run_topology.Verification_full;
              build_command = "dune build @check" })));
  check_repository_action_mutant "repository build omission"
    repository_suites
    (function _build :: rest -> rest | [] -> []);
  check_repository_action_mutant "repository suite omission"
    repository_suites
    (function build :: _suite :: rest -> build :: rest | actions -> actions);
  check_repository_action_mutant "repository suite identity substitution"
    repository_suites
    (mutate_action_at 1
       (fun item ->
         replace_action
           ~work:(Run_topology.Repository_verification_suite
             { profile = Run_topology.Verification_full;
               suite_id = "test_substituted";
               executable = "_build/default/test_substituted.exe" })
           item));
  check_repository_action_mutant "repository suite reordering"
    repository_suites
    (function
      | build :: first :: second :: rest -> build :: second :: first :: rest
      | actions -> actions);
  check_repository_action_mutant "repository suite dependency substitution"
    repository_suites
    (mutate_action_at 1 (replace_action ~dependency_ids:[]));
  check_repository_action_mutant "repository capability substitution"
    repository_suites
    (mutate_action_at 1
       (replace_action ~required_capability_id:"capability.verify-fast"));
  check_repository_action_mutant "repository context omission"
    repository_suites
    (mutate_action_at 1
       (replace_action ~context_requirement_ids:[ "context.exact-head" ]));
  check_repository_action_mutant "repository target substitution"
    repository_suites
    (mutate_action_at 1 (replace_action ~target_component_id:"runEventStore"));
  check_repository_action_mutant "repository effect substitution"
    repository_suites
    (mutate_action_at 1
       (replace_action ~effect_kind:Run_topology.Durable_artifact_publication));
  check_repository_action_mutant "repository command substitution"
    repository_suites
    (mutate_action_at 1
       (replace_action ~command_id:"ExecuteRepositoryVerificationSuite.unknown"));
  check_repository_action_mutant "repository MIQ selector substitution"
    repository_suites
    (mutate_action_at 1 (replace_action ~selector_id:"miq.rete-ul"));
  check_repository_action_mutant "repository MIQ agent substitution"
    repository_suites
    (mutate_action_at 1 (replace_action ~assigned_agent_id:"reteUlGate"));
  check_repository_action_mutant "repository preparation substitution"
    repository_suites
    (mutate_action_at 1
       (replace_action ~preparation_id:"prepare.verify-repository.substituted"));
  let rec consecutive = function
    | left :: ((right :: _) as rest) ->
        let component = List.find
            (fun item -> item.Fpp_model.comp_name = left.Fpp_model.of_component)
            Run_topology.model.components
        in
        right.Fpp_model.base_id
          = left.base_id + Fpp_model.id_span component
        && consecutive rest
    | _ -> true
  in
  check "instances start at 0x4000 and use computed half-open spans"
    (match Run_topology.model.instances with
     | first :: _ -> first.base_id = 0x4000 && consecutive Run_topology.model.instances
     | [] -> false);

  Printf.printf "[red-green] HZ-SQL-FIN-01 SQLite actor dependability\n";
  let event_store_component =
    List.find_opt
      (fun (item : Fpp_model.component) -> item.comp_name = "runEventStore")
      Run_topology.model.components
  in
  check "RunEventStore is an active actor"
    (match event_store_component with
     | Some item -> item.kind = Fpp_model.Active
     | None -> false);
  check "RunEventStore owns both lifecycle state machines"
    (match event_store_component with
     | Some item ->
         item.machines =
           [ ("statementFinalize", "StatementFinalizeLifecycle");
             ("databaseClose", "DatabaseCloseLifecycle") ]
     | None -> false);
  let state_names machine_name =
    List.find_map
      (function
        | Fpp_model.Internal_machine item when item.machine_name = machine_name ->
            Some (List.map (fun state -> state.Fpp_model.state_name) item.states)
        | _ -> None)
      Run_topology.model.machines
  in
  check "statement-finalize lifecycle states are explicit"
    (state_names "StatementFinalizeLifecycle"
     = Some [ "StatementOpen"; "StatementFinalizing"; "StatementFinalized";
              "StatementFinalizeFailed" ]);
  check "database-close lifecycle preserves blocked and re-elected states"
    (state_names "DatabaseCloseLifecycle"
     = Some [ "DatabaseOpen"; "DatabaseClosing"; "DatabaseCloseBlocked";
              "DatabaseClosed"; "ActorReelected" ]);
  let event_names =
    match event_store_component with
    | None -> []
    | Some item -> List.map (fun event -> event.Fpp_model.event_name) item.events
  in
  check "GC and SQLite fault events are modeled"
    (List.for_all
       (fun name -> List.mem name event_names)
       [ "GcReachedLiveStatement"; "SqliteFinalizeFault"; "SqliteCloseFault";
         "SqliteCloseBlocked" ]);
  let command_names =
    match event_store_component with
    | None -> []
    | Some item -> List.map (fun command -> command.Fpp_model.cmd_name) item.commands
  in
  check "formal stress reliability and full gates are commands"
    (List.for_all
       (fun name -> List.mem name command_names)
       [ "RunSqliteFormalGate"; "RunSqliteStressGate";
         "RunSqliteReliabilityGate"; "RunSqliteFullGate" ]);
  check "SQLite dependability verification is a declarative Swarm command"
    (List.mem "VerifySqliteDependabilitySwarm" command_names);
  let sqlite_metric_channels =
    [ "ops.dashboard.fpp.sqlite.statements.finalized";
      "ops.dashboard.fpp.sqlite.statement_finalize_failures";
      "ops.dashboard.fpp.sqlite.database_close_attempts";
      "ops.dashboard.fpp.sqlite.database_close_failures";
      "ops.dashboard.fpp.sqlite.gc_live_statement_faults";
      "ops.dashboard.fpp.sqlite.close_blockers";
      "ops.dashboard.fpp.sqlite.actor_reelections" ]
  in
  check "SQLite lifecycle metrics are mapped into FPP"
    (List.for_all
       (fun expected ->
         List.exists
           (fun (item : Run_topology.channel) -> item.fpp_name = expected)
           Run_topology.authority.channels)
       sqlite_metric_channels);
  check "HZ-SQL-FIN-01 is an executable covered requirement"
    (List.exists
       (fun (item : Run_topology.requirement) ->
         item.stable_id = "HZ-SQL-FIN-01"
         && item.verifier_id = "verify.operations.fpp"
         && List.mem "runEventStore" item.covered_elements
         && List.mem "activity.verify-sqlite-dependability" item.covered_elements)
       Run_topology.authority.requirements);
  check "SQLite verification activity is typed and bridge-mediated"
    (match List.filter
        (fun (item : Run_topology.declarative_activity) ->
          item.stable_id = "activity.verify-sqlite-dependability")
        Run_topology.authority.activities with
     | [ item ] ->
         item.stable_id = "activity.verify-sqlite-dependability"
         && item.bridge_component_id = "swarmExecutionBridge"
         && item.target_component_id = "runEventStore"
         && item.constraints <> [] && item.success_criteria <> []
     | _ -> false);
  let close_bypass_authority =
    let lifecycle_machines =
      List.map
        (fun (machine : Run_topology.lifecycle_machine) ->
          if machine.stable_id <> "DatabaseCloseLifecycle" then machine
          else
            { machine with
              states =
                List.map
                  (fun (state : Run_topology.lifecycle_state) ->
                    if state.stable_id <> "DatabaseClosing" then state
                    else
                      { state with
                        transitions =
                          List.map
                            (fun (transition : Run_topology.lifecycle_transition) ->
                              if transition.signal = "closeFailed" then
                                { transition with target_state = "DatabaseClosed" }
                              else transition)
                            state.transitions })
                  machine.states })
        Run_topology.authority.lifecycle_machines
    in
    { Run_topology.authority with lifecycle_machines }
  in
  check "close-failure-to-closed bypass mutant is killed"
    (Run_topology.sqlite_dependability_gaps_for close_bypass_authority <> []);

  Printf.printf "[mutation] topology killers\n";
  begin match Run_topology.authority.channels with
  | first :: rest ->
      let missing = { Run_topology.authority with channels = rest } in
      check "dropping one metric channel is detected"
        (Run_topology.metric_channel_gaps_for missing <> []);
      let duplicate = { Run_topology.authority with channels = first :: first :: rest } in
      check "duplicate stable channel identity is detected"
        (Run_topology.validate_authority duplicate <> [])
  | [] -> check "channel mutant fixture exists" false
  end;
  begin match Run_topology.authority.verifiers with
  | _ :: rest ->
      check "missing requirement verifier is detected"
        (Run_topology.requirement_gaps_for
           { Run_topology.authority with verifiers = rest } <> [])
  | [] -> check "verifier mutant fixture exists" false
  end;
  let bypass : Run_topology.edge =
    { stable_id = "edge.mutant.execution-bypass";
      from_component = "runSupervisor"; from_port = "admittedOut";
      to_component = "suiteWorker"; to_port = "workIn";
      kind = Run_topology.Execution }
  in
  check "direct supervisor-to-worker bypass is killed"
    (Run_topology.execution_bypass_gaps
       { Run_topology.authority with edges = bypass :: Run_topology.authority.edges }
     <> []);
  let ui_edge : Run_topology.edge =
    { stable_id = "edge.mutant.ui-admission";
      from_component = "dreamGateway"; from_port = "stateOut";
      to_component = "swarmExecutionBridge"; to_port = "intentIn";
      kind = Run_topology.Admission }
  in
  check "UI-to-admission edge is killed"
    (Run_topology.ui_admission_gaps
       { Run_topology.authority with edges = ui_edge :: Run_topology.authority.edges }
     <> []);
  let overlapped =
    match Run_topology.model.instances with
    | first :: rest ->
        { Run_topology.model with
          instances = { first with Fpp_model.base_id = 0x2000 } :: rest }
    | [] -> Run_topology.model
  in
  check "cross-model overlap mutant is killed"
    (Run_topology.interval_gaps
       (("operations-mutant", overlapped) :: other_models ()) <> []);
  let overflowed =
    match Run_topology.model.instances with
    | first :: rest ->
        { Run_topology.model with
          instances = { first with Fpp_model.base_id = max_int } :: rest }
    | [] -> Run_topology.model
  in
  check "overflowing half-open interval is rejected"
    (Run_topology.interval_gaps [ ("operations-overflow", overflowed) ]
     |> List.exists (fun gap -> contains gap "overflowing interval"));

  Printf.printf "[feature] deterministic MBSE projections\n";
  let sysml = Run_mbse.sysml_v2 () in
  let ttl = Run_mbse.oml_owl () in
  let mms = Run_mbse.openmbee_mms () in
  let fpp = Run_mbse.fpp_dictionary () in
  check "all MBSE projections are nonempty and derived"
    (Run_mbse.validate () = []
     && sysml <> "" && ttl <> "" && mms <> "" && fpp <> "");
  check "SysML manifest is exact"
    (match Run_mbse.manifest_of_sysml sysml with
     | Ok manifest -> manifest_equal manifest Run_mbse.manifest
     | Error _ -> false);
  check "Turtle manifest is exact"
    (match Run_mbse.manifest_of_turtle ttl with
     | Ok manifest -> manifest_equal manifest Run_mbse.manifest
     | Error _ -> false);
  check "MMS manifest is exact"
    (match Run_mbse.manifest_of_mms mms with
     | Ok manifest -> manifest_equal manifest Run_mbse.manifest
     | Error _ -> false);
  check "FPP dictionary manifest is exact"
    (match Run_mbse.manifest_of_fpp fpp with
     | Ok manifest -> manifest_equal manifest Run_mbse.manifest
     | Error _ -> false);
  check "every surface carries one common source digest"
    (List.for_all
       (fun text -> contains text Run_topology.source_digest)
       [ sysml; ttl; mms; fpp ]);
  let activity_field_names =
    [ "targetState"; "requiredCapabilityIds"; "contextRequirementIds";
      "miqRoutes"; "effectKinds"; "commandIds"; "constraints";
      "successCriteria" ]
  in
  check "every surface carries every declarative activity field"
    (List.for_all
       (fun text ->
         List.for_all (fun field -> contains text field) activity_field_names)
       [ sysml; ttl; mms; fpp ]);
  let activity_values =
    [ "sqlite-dependability-verified";
      "capability.formal-check"; "capability.verify-full";
      "capability.fpp-check"; "context.exact-head";
      "context.assurance-bundle"; "context.owned-run-event-store";
      "context.resource-envelope"; "miq.rete-ul"; "reteUlGate";
      "miq.raven"; "ravenGate"; "miq.stpa-fmea"; "stpaFmeaGate";
      "miq.z3-formal"; "z3FormalGate";
      "dependability-process-attempt"; "verification-suite-execution";
      "durable-artifact-publication" ]
  in
  check "every surface carries the exact topology activity values"
    (List.for_all
       (fun text ->
         List.for_all (fun value -> contains text value) activity_values)
       [ sysml; ttl; mms; fpp ]);
  Printf.printf "[tdd] exact MBSE action-carrier correspondence\n";
  let sqlite_activity_id = "activity.verify-sqlite-dependability" in
  let sysml_actions =
    action_graph_from_quoted ~activity_id:sqlite_activity_id
      "attribute actions : String = \"" sysml
  in
  let turtle_actions =
    action_graph_from_quoted ~activity_id:sqlite_activity_id "ops:actions \"" ttl
  in
  let mms_actions =
    action_graph_from_json ~activity_id:sqlite_activity_id ~container:"elements" mms
  in
  let fpp_actions =
    action_graph_from_json ~activity_id:sqlite_activity_id
      ~container:"operationsActivities" fpp
  in
  check
    "SysML carries the exact five ordered actions with every field and dependency"
    (Option.fold ~none:false ~some:exact_action_graph sysml_actions);
  check
    "Turtle carries the exact five ordered actions with every field and dependency"
    (Option.fold ~none:false ~some:exact_action_graph turtle_actions);
  check
    "OpenMBEE MMS carries the exact five ordered actions with every field and dependency"
    (Option.fold ~none:false ~some:exact_action_graph mms_actions);
  check
    "FPP dictionary carries the exact five ordered actions with every field and dependency"
    (Option.fold ~none:false ~some:exact_action_graph fpp_actions);
  let expected_graph = exact_action_graph_json () in
  let omitted_graph =
    match expected_graph with
    | `List (_ :: rest) -> `List rest
    | _ -> `List []
  in
  let substituted_graph =
    match expected_graph with
    | `List (`Assoc fields :: rest) ->
        `List
          (`Assoc
             (List.map
                (fun (name, value) ->
                  if name = "assignedAgentId" then
                    (name, `String "agent.substituted")
                  else (name, value))
                fields)
           :: rest)
    | _ -> `List []
  in
  let reordered_graph =
    match expected_graph with
    | `List actions -> `List (List.rev actions)
    | _ -> `List []
  in
  check "the MBSE action oracle rejects one omitted action"
    (not (exact_action_graph omitted_graph));
  check "the MBSE action oracle rejects a field substitution"
    (not (exact_action_graph substituted_graph));
  check "the MBSE action oracle rejects action reordering"
    (not (exact_action_graph reordered_graph));
  Printf.printf "[tdd-red] exact repository action graph on four MBSE surfaces\n";
  let repository_graph =
    `List (List.map expected_action_json repository_actions)
  in
  let exact_repository_graph observed =
    normalize_json observed = normalize_json repository_graph
  in
  let repository_sysml_actions =
    action_graph_from_quoted ~activity_id:repository_activity_id
      "attribute actions : String = \"" sysml
  in
  let repository_turtle_actions =
    action_graph_from_quoted ~activity_id:repository_activity_id
      "ops:actions \"" ttl
  in
  let repository_mms_actions =
    action_graph_from_json ~activity_id:repository_activity_id
      ~container:"elements" mms
  in
  let repository_fpp_actions =
    action_graph_from_json ~activity_id:repository_activity_id
      ~container:"operationsActivities" fpp
  in
  check "SysML carries the exact repository build-plus-suite denominator"
    (Option.fold ~none:false ~some:exact_repository_graph
       repository_sysml_actions);
  check "Turtle carries the exact repository build-plus-suite denominator"
    (Option.fold ~none:false ~some:exact_repository_graph
       repository_turtle_actions);
  check "OpenMBEE MMS carries the exact repository build-plus-suite denominator"
    (Option.fold ~none:false ~some:exact_repository_graph
       repository_mms_actions);
  check "FPP carries the exact repository build-plus-suite denominator"
    (Option.fold ~none:false ~some:exact_repository_graph
       repository_fpp_actions);
  let omitted_repository_graph =
    match repository_graph with
    | `List (build :: _suite :: rest) -> `List (build :: rest)
    | _ -> `List []
  in
  let substituted_repository_graph =
    match repository_graph with
    | `List (build :: `Assoc fields :: rest) ->
        `List
          (build
           :: `Assoc
                (List.map
                   (fun (name, value) ->
                     if name = "suiteId" then
                       (name, `String "test_substituted")
                     else (name, value))
                   fields)
           :: rest)
    | _ -> `List []
  in
  let reordered_repository_graph =
    match repository_graph with
    | `List (build :: first :: second :: rest) ->
        `List (build :: second :: first :: rest)
    | _ -> `List []
  in
  check "repository MBSE oracle rejects one omitted suite action"
    (not (exact_repository_graph omitted_repository_graph));
  check "repository MBSE oracle rejects one substituted suite field"
    (not (exact_repository_graph substituted_repository_graph));
  check "repository MBSE oracle rejects suite reordering"
    (not (exact_repository_graph reordered_repository_graph));
  check "surfaces are deterministic and timestamp-free"
    (sysml = Run_mbse.sysml_v2 ()
     && ttl = Run_mbse.oml_owl ()
     && mms = Run_mbse.openmbee_mms ()
     && fpp = Run_mbse.fpp_dictionary ()
     && not (contains sysml "generated_at")
     && not (contains ttl "generated_at")
     && not (contains mms "generated_at")
     && not (contains fpp "generated_at"));
  check "FPP surface is the JSON dictionary plus operations manifest"
    (match Yojson.Safe.from_string fpp with
     | `Assoc fields ->
         List.for_all (fun key -> List.mem_assoc key fields)
           [ "metadata"; "telemetryChannels"; "operationsModel" ]
     | exception Yojson.Json_error _ | _ -> false);
  let hostile = "quote=\" slash=\\ newline=\n tab=\t carriage=\r control=\001" in
  check "SysML escaping covers every adversarial byte"
    (Run_mbse.escape_sysml hostile
     = "quote=\\\" slash=\\\\ newline=\\n tab=\\t carriage=\\r control=\\u0001");
  check "Turtle escaping covers every adversarial byte"
    (Run_mbse.escape_turtle hostile
     = "quote=\\\" slash=\\\\ newline=\\n tab=\\t carriage=\\r control=\\u0001");

  Printf.printf "[formal] pure non-vacuous obligations\n";
  check "formal obligation registry validates" (Run_formal.validate () = []);
  let negated =
    List.filter
      (fun item -> item.Run_formal.kind = Run_formal.Negated_law)
      Run_formal.obligations
  in
  let controls =
    List.filter
      (fun item -> item.Run_formal.kind = Run_formal.False_control)
      Run_formal.obligations
  in
  check "every negated law expects Unsat"
    (negated <> []
     && List.for_all (fun item -> item.Run_formal.expected = Run_formal.Unsat) negated);
  check "every false control expects Sat"
    (controls <> []
     && List.for_all (fun item -> item.Run_formal.expected = Run_formal.Sat) controls);
  check "every formal query has a deterministic digest and timeout"
    (List.for_all
       (fun item ->
         String.length item.Run_formal.query_digest = 64
         && item.timeout_ms > 0
         && item.query_digest = Run_formal.digest_query item.smt2)
       Run_formal.obligations);
  begin match Run_formal.obligations with
  | first :: second :: rest ->
      check "dropping an entire law-control pair is rejected"
        (Run_formal.validate_obligations rest <> []);
      ignore (first, second)
  | _ -> check "formal pair mutant fixture exists" false
  end;
  begin match negated with
  | first :: rest ->
      check "wrong expected theorem result is rejected"
        (Run_formal.validate_obligations
           ({ first with expected = Run_formal.Sat } :: rest @ controls) <> [])
  | [] -> check "formal mutant fixture exists" false
  end;

  Printf.printf "run_model_surfaces: %d checks, %d failures\n" !checks !failures;
  let self =
    Suite_telemetry.observe ~suite:"test_run_model_surfaces"
      ~passed:(!checks - !failures) ~failed:!failures ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_ops_dashboard ]);
  exit (Suite_telemetry.exit_code self)
