open Fpp_model
open Run_metrics

type component = { stable_id : string; purpose : string }
type direction = Input | Output
type port_kind = Intent | Evidence | State | Telemetry | Scene
type port = { stable_id : string; component_id : string; name : string;
  direction : direction; kind : port_kind; count : int }
type channel = { stable_id : string; component_id : string;
  metric_id : string option; fpp_name : string }
type edge_kind = Admission | Execution | Evidence_flow | State_flow | Projection
type edge = { stable_id : string; from_component : string; from_port : string;
  to_component : string; to_port : string; kind : edge_kind }
type verifier_kind = Fpp_validation | Metric_channel_mapping | Window_disjointness
  | Execution_mediation | Ui_admission_isolation | Projection_correspondence
  | Formal_nonvacuity
type verifier = { stable_id : string; kind : verifier_kind }
type lifecycle_transition = { signal : string; actions : string list;
  target_state : string }
type lifecycle_state = { stable_id : string;
  transitions : lifecycle_transition list }
type lifecycle_machine = { stable_id : string; component_id : string;
  instance_id : string; initial_state : string; states : lifecycle_state list }
type fault_severity = Fault_diagnostic | Fault_warning | Fault_fatal
type fault_event = { stable_id : string; component_id : string;
  severity : fault_severity; format : string }
type gate_kind = Formal_gate | Stress_gate | Reliability_gate | Full_gate
  | Swarm_verification
type gate_command = { stable_id : string; component_id : string;
  kind : gate_kind; intent_id : string }
type effect_kind = Dependability_process_attempt
  | Verification_suite_execution | Durable_artifact_publication
  | External_resource_observation | Repository_source_observation
  | Approval_nonce_consumption | Writer_lease_transition
  | Production_activation_transition | Network_scope_transition
  | Credential_lease_transition | Controlled_filesystem_materialization
  | Candidate_tree_verification | Jujutsu_observation
  | Jujutsu_local_mutation | Jujutsu_history_rewrite | Jujutsu_recovery
  | Jujutsu_remote_synchronization | Jujutsu_remote_publish
  | Formal_oracle_execution
type miq_route = { selector_id : string; required_capability_id : string;
  assigned_agent_id : string }
type verification_profile = Verification_fast | Verification_full
type jujutsu_action_role = Observe_before | Execute | Observe_after
type action_work = Topology_gate
  | Repository_build of {
      profile : verification_profile; build_command : string }
  | Repository_verification_suite of {
      profile : verification_profile; suite_id : string; executable : string }
  | Clock_work of Jj_action_kind.auxiliary_role
  | Filesystem_work of Jj_action_kind.auxiliary_role
  | External_resource_work of Jj_action_kind.auxiliary_role
  | Repository_source_work of Jj_action_kind.auxiliary_role
  | Approval_nonce_work of Jj_action_kind.auxiliary_role
  | Writer_lease_work of Jj_action_kind.auxiliary_role
  | Network_scope_work of Jj_action_kind.auxiliary_role
  | Credential_lease_work of Jj_action_kind.auxiliary_role
  | Activation_transition_work of Jj_action_kind.frontier_action
  | Mutation_frontier_work of Jj_action_kind.frontier_action
  | Materialization_work of Jj_action_kind.auxiliary_role
  | Candidate_verification_work of Jj_action_kind.candidate_step
  | Formal_oracle_work of Jj_action_kind.formal_process
  | Jujutsu_readback_work of Jj_action_kind.auxiliary_role
  | Completion_receipt_work of Jj_action_kind.auxiliary_role
  | Jujutsu_work of {
      operation : Jj_operation.t;
      role : jujutsu_action_role;
    }

type controlled_lifecycle_state =
  | Declared | Prepared | Admitted | Running | Readback | Terminal
  | Refused | Indeterminate | Stale

type conditional_control_state =
  | Guarded | Consume_ready | Action_terminal | Decision_pending
  | Continue_selected | Branch_selected | Decision_indeterminate

type conditional_control_event =
  | Prefix_complete | Decision_committed | Decision_replayed
  | Condition_not_selected_recorded | Decision_refused

type conditional_channel_kind =
  | Bounded_family_prefix | Decision_receipt | Selected_branch_identity
  | Node_disposition
type declarative_action = { stable_id : string; command_id : string;
  assigned_agent_id : string; dependency_ids : string list;
  selector_id : string; required_capability_id : string;
  context_requirement_ids : string list; target_component_id : string;
  effect_kind : effect_kind; preparation_id : string; work : action_work }
type declarative_activity = { stable_id : string; bridge_component_id : string;
  target_component_id : string; target_state : string; intent : string;
  constraints : string list; success_criteria : string list;
  required_capability_ids : string list; context_requirement_ids : string list;
  miq_routes : miq_route list; effect_kinds : effect_kind list;
  command_ids : string list; actions : declarative_action list }
type admitted_activity = { declaration : declarative_activity;
  activity_digest : string; authority_digest : string }
type requirement = { stable_id : string; statement : string; verifier_id : string;
  source : string; covered_elements : string list }
type execution_policy = { supervisor_component_id : string;
  bridge_component_id : string; worker_component_id : string;
  required_execution_edge_id : string }
type ui_isolation_policy = { ui_component_ids : string list;
  admission_component_ids : string list }
type model_policy = { fpp_model_name : string; fpp_topology_name : string;
  fpp_base_id : int; projection_surface_ids : string list }
type sqlite_transition_policy = { machine_id : string; source_state_id : string;
  signal_id : string; target_state_id : string; required_action_ids : string list }
type sqlite_policy = { machine_state_ids : (string * string list) list;
  required_transitions : sqlite_transition_policy list;
  fault_event_ids : string list; gate_command_ids : string list;
  activity_id : string; hazard_requirement_id : string }
type formal_policy = { execution : execution_policy;
  ui_isolation : ui_isolation_policy; model_contract : model_policy;
  sqlite : sqlite_policy }
type authority = { components : component list; ports : port list;
  channels : channel list; edges : edge list; verifiers : verifier list;
  lifecycle_machines : lifecycle_machine list; fault_events : fault_event list;
  gate_commands : gate_command list; activities : declarative_activity list;
  requirements : requirement list; formal_policy : formal_policy }

let component_names =
  [ "runSupervisor"; "reteUlGate"; "ravenGate"; "stpaFmeaGate";
    "ruliadAnalyzer"; "stanReliability"; "z3FormalGate";
    "swarmExecutionBridge"; "suiteWorker"; "runEventStore";
    "resourceSampler"; "zenohRunBridge"; "dreamGateway";
    "bonsaiDashboard"; "uiIntentCompiler"; "uiEffectInterpreter";
    "webglRenderer"; "assuranceGate"; "completionGate" ]

let component_purposes =
  [ ("runSupervisor", "Exact-head run lifecycle supervision");
    ("reteUlGate", "Bounded Rete_UL admission analysis");
    ("ravenGate", "Deterministic multi-criteria admission analysis");
    ("stpaFmeaGate", "STPA and FMEA safety admission");
    ("ruliadAnalyzer", "Bounded multiway rule-space analysis");
    ("stanReliability", "Report-only reliability annotation");
    ("z3FormalGate", "Non-vacuous topology obligation admission");
    ("swarmExecutionBridge", "Sole admitted Swarm execution boundary");
    ("suiteWorker", "One typed verification-suite work target");
    ("runEventStore", "Append-only run event authority");
    ("resourceSampler", "Fail-closed runtime resource observation");
    ("zenohRunBridge", "Typed control and data state projection");
    ("dreamGateway", "Bounded same-origin read gateway");
    ("bonsaiDashboard", "Pure operations read-model projection");
    ("uiIntentCompiler", "Closed UI intent projection compiler");
    ("uiEffectInterpreter", "Sole browser projection-effect interpreter");
    ("webglRenderer", "Typed WebGL1 scene projection");
    ("assuranceGate", "Exact receipt and assurance admission");
    ("completionGate", "Non-vacuous completion observation") ]

let components =
  List.map
    (fun stable_id ->
      { stable_id; purpose = List.assoc stable_id component_purposes })
    component_names

let port component_id name direction kind =
  { stable_id = "port." ^ component_id ^ "." ^ name;
    component_id; name; direction; kind; count = 1 }

let ports =
  [ port "runSupervisor" "stateIn" Input State;
    port "runSupervisor" "admittedOut" Output Intent;
    port "reteUlGate" "intentIn" Input Intent;
    port "reteUlGate" "intentOut" Output Intent;
    port "ravenGate" "intentIn" Input Intent;
    port "ravenGate" "intentOut" Output Intent;
    port "stpaFmeaGate" "intentIn" Input Intent;
    port "stpaFmeaGate" "intentOut" Output Intent;
    port "ruliadAnalyzer" "intentIn" Input Intent;
    port "ruliadAnalyzer" "intentOut" Output Intent;
    port "stanReliability" "intentIn" Input Intent;
    port "stanReliability" "intentOut" Output Intent;
    port "z3FormalGate" "intentIn" Input Intent;
    port "z3FormalGate" "intentOut" Output Intent;
    port "assuranceGate" "intentIn" Input Intent;
    port "assuranceGate" "admittedOut" Output Intent;
    port "swarmExecutionBridge" "intentIn" Input Intent;
    port "swarmExecutionBridge" "workOut" Output Intent;
    port "suiteWorker" "workIn" Input Intent;
    port "suiteWorker" "eventOut" Output Evidence;
    port "resourceSampler" "sampleOut" Output Telemetry;
    port "runEventStore" "eventIn" Input Evidence;
    port "runEventStore" "resourceIn" Input Telemetry;
    port "runEventStore" "receiptIn" Input Evidence;
    port "runEventStore" "supervisorStateOut" Output State;
    port "runEventStore" "zenohStateOut" Output State;
    port "runEventStore" "completionStateOut" Output State;
    port "zenohRunBridge" "stateIn" Input State;
    port "zenohRunBridge" "stateOut" Output State;
    port "dreamGateway" "stateIn" Input State;
    port "dreamGateway" "stateOut" Output State;
    port "bonsaiDashboard" "stateIn" Input State;
    port "bonsaiDashboard" "intentOut" Output Intent;
    port "uiIntentCompiler" "intentIn" Input Intent;
    port "uiIntentCompiler" "effectOut" Output Intent;
    port "uiEffectInterpreter" "effectIn" Input Intent;
    port "uiEffectInterpreter" "sceneOut" Output Scene;
    port "webglRenderer" "sceneIn" Input Scene;
    port "completionGate" "stateIn" Input State;
    port "completionGate" "receiptOut" Output Evidence ]

let edge stable_id kind from_component from_port to_component to_port =
  { stable_id; kind; from_component; from_port; to_component; to_port }

let edges =
  [ edge "edge.admission.supervisor-rete" Admission
      "runSupervisor" "admittedOut" "reteUlGate" "intentIn";
    edge "edge.admission.rete-raven" Admission
      "reteUlGate" "intentOut" "ravenGate" "intentIn";
    edge "edge.admission.raven-safety" Admission
      "ravenGate" "intentOut" "stpaFmeaGate" "intentIn";
    edge "edge.admission.safety-ruliad" Admission
      "stpaFmeaGate" "intentOut" "ruliadAnalyzer" "intentIn";
    edge "edge.admission.ruliad-stan" Admission
      "ruliadAnalyzer" "intentOut" "stanReliability" "intentIn";
    edge "edge.admission.stan-z3" Admission
      "stanReliability" "intentOut" "z3FormalGate" "intentIn";
    edge "edge.admission.z3-assurance" Admission
      "z3FormalGate" "intentOut" "assuranceGate" "intentIn";
    edge "edge.admission.assurance-bridge" Admission
      "assuranceGate" "admittedOut" "swarmExecutionBridge" "intentIn";
    edge "edge.execution.bridge-worker" Execution
      "swarmExecutionBridge" "workOut" "suiteWorker" "workIn";
    edge "edge.evidence.worker-store" Evidence_flow
      "suiteWorker" "eventOut" "runEventStore" "eventIn";
    edge "edge.telemetry.resource-store" Evidence_flow
      "resourceSampler" "sampleOut" "runEventStore" "resourceIn";
    edge "edge.state.store-supervisor" State_flow
      "runEventStore" "supervisorStateOut" "runSupervisor" "stateIn";
    edge "edge.state.store-zenoh" State_flow
      "runEventStore" "zenohStateOut" "zenohRunBridge" "stateIn";
    edge "edge.projection.zenoh-dream" Projection
      "zenohRunBridge" "stateOut" "dreamGateway" "stateIn";
    edge "edge.projection.dream-bonsai" Projection
      "dreamGateway" "stateOut" "bonsaiDashboard" "stateIn";
    edge "edge.projection.bonsai-compiler" Projection
      "bonsaiDashboard" "intentOut" "uiIntentCompiler" "intentIn";
    edge "edge.projection.compiler-interpreter" Projection
      "uiIntentCompiler" "effectOut" "uiEffectInterpreter" "effectIn";
    edge "edge.projection.interpreter-webgl" Projection
      "uiEffectInterpreter" "sceneOut" "webglRenderer" "sceneIn";
    edge "edge.state.store-completion" State_flow
      "runEventStore" "completionStateOut" "completionGate" "stateIn";
    edge "edge.evidence.completion-store" Evidence_flow
      "completionGate" "receiptOut" "runEventStore" "receiptIn" ]

let component_for_metric (declaration : Run_metrics.declaration) =
  match declaration.sources with
  | Run_metrics.Run_event :: _ ->
      if String.starts_with ~prefix:"run.suite." declaration.id
      then "suiteWorker" else "runSupervisor"
  | (Process_times | Ocaml_gc | Proc_status | Load_average) :: _ ->
      "resourceSampler"
  | Sqlite_store :: _ -> "runEventStore"
  | Zenoh_transport :: _ -> "zenohRunBridge"
  | Websocket_transport :: _ -> "dreamGateway"
  | Snapshot_reconciler :: _ -> "bonsaiDashboard"
  | Webgl_runtime :: _ -> "webglRenderer"
  | Admission_gate :: _ -> "completionGate"
  | Rete_ul_engine :: _ -> "reteUlGate"
  | Deterministic_mcda_v1 :: _ -> "ravenGate"
  | Safety_analysis :: _ -> "stpaFmeaGate"
  | Formal_analysis :: _ ->
      if String.starts_with ~prefix:"ruliad." declaration.id then "ruliadAnalyzer"
      else if String.starts_with ~prefix:"stan." declaration.id then "stanReliability"
      else "z3FormalGate"
  | Assurance_runner :: _ -> "assuranceGate"
  | [] -> "runSupervisor"

let metric_channels =
  List.map
    (fun (declaration : Run_metrics.declaration) ->
      { stable_id = declaration.fpp_channel;
        component_id = component_for_metric declaration;
        metric_id = Some declaration.id;
        fpp_name = declaration.fpp_channel })
    Run_metrics.all

let sqlite_metric_channels =
  List.map
    (fun name ->
      { stable_id = name; component_id = "runEventStore";
        metric_id = None; fpp_name = name })
    [ "ops.dashboard.fpp.sqlite.statements.finalized";
      "ops.dashboard.fpp.sqlite.statement_finalize_failures";
      "ops.dashboard.fpp.sqlite.database_close_attempts";
      "ops.dashboard.fpp.sqlite.database_close_failures";
      "ops.dashboard.fpp.sqlite.gc_live_statement_faults";
      "ops.dashboard.fpp.sqlite.close_blockers";
      "ops.dashboard.fpp.sqlite.actor_reelections" ]

let debug_channels =
  List.map
    (fun (intent : Debug_intent.t) ->
      { stable_id = intent.fpp.channel; component_id = intent.fpp.component;
        metric_id = None; fpp_name = intent.fpp.channel })
    Debug_intent.all

let debug_runtime_channels =
  [ ("ops.debug.runtime.open_intents", "completionGate");
    ("ops.debug.runtime.observations", "assuranceGate");
    ("ops.debug.runtime.hypotheses", "reteUlGate");
    ("ops.debug.runtime.eliminated_hypotheses", "ravenGate");
    ("ops.debug.runtime.discriminating_measurements", "ravenGate");
    ("ops.debug.runtime.established_causes", "assuranceGate");
    ("ops.debug.runtime.unresolved_residuals", "completionGate");
    ("ops.debug.runtime.stale_evidence", "assuranceGate");
    ("ops.debug.runtime.verification_cone_size", "ruliadAnalyzer");
    ("ops.debug.runtime.mutation_kills", "z3FormalGate");
    ("ops.debug.runtime.time_to_discrimination_ns", "ravenGate");
    ("ops.debug.runtime.time_to_closure_ns", "completionGate") ]
  |> List.map (fun (stable_id, component_id) ->
         { stable_id; component_id; metric_id = None; fpp_name = stable_id })

let status_channels =
  List.filter_map
    (fun component_id ->
      if List.exists
          (fun (item : channel) -> item.component_id = component_id)
          metric_channels
      then None
      else
        let stable_id = "ops.dashboard.fpp.component." ^ component_id ^ ".status" in
        Some { stable_id; component_id; metric_id = None; fpp_name = stable_id })
    component_names

let channels =
  metric_channels @ sqlite_metric_channels @ debug_channels
  @ debug_runtime_channels @ status_channels

let verifiers =
  [ { stable_id = "verify.operations.fpp"; kind = Fpp_validation };
    { stable_id = "verify.operations.metric-channels"; kind = Metric_channel_mapping };
    { stable_id = "verify.operations.id-windows"; kind = Window_disjointness };
    { stable_id = "verify.operations.execution-bridge"; kind = Execution_mediation };
    { stable_id = "verify.operations.ui-isolation"; kind = Ui_admission_isolation };
    { stable_id = "verify.operations.mbse-correspondence"; kind = Projection_correspondence };
    { stable_id = "verify.operations.formal-nonvacuity"; kind = Formal_nonvacuity } ]

let lifecycle_machines =
  [ { stable_id = "StatementFinalizeLifecycle";
      component_id = "runEventStore"; instance_id = "statementFinalize";
      initial_state = "StatementOpen";
      states =
        [ { stable_id = "StatementOpen";
            transitions =
              [ { signal = "requestFinalize"; actions = [ "beginFinalize" ];
                  target_state = "StatementFinalizing" };
                { signal = "gcReached"; actions = [ "recordGcFault" ];
                  target_state = "StatementFinalizeFailed" } ] };
          { stable_id = "StatementFinalizing";
            transitions =
              [ { signal = "finalizeSucceeded"; actions = [ "recordFinalized" ];
                  target_state = "StatementFinalized" };
                { signal = "finalizeFailed"; actions = [ "recordFinalizeFault" ];
                  target_state = "StatementFinalizeFailed" } ] };
          { stable_id = "StatementFinalized"; transitions = [] };
          { stable_id = "StatementFinalizeFailed";
            transitions =
              [ { signal = "retryFinalize"; actions = [ "beginFinalize" ];
                  target_state = "StatementFinalizing" } ] } ] };
    { stable_id = "DatabaseCloseLifecycle";
      component_id = "runEventStore"; instance_id = "databaseClose";
      initial_state = "DatabaseOpen";
      states =
        [ { stable_id = "DatabaseOpen";
            transitions =
              [ { signal = "requestClose"; actions = [ "attemptClose" ];
                  target_state = "DatabaseClosing" } ] };
          { stable_id = "DatabaseClosing";
            transitions =
              [ { signal = "closeSucceeded"; actions = [ "recordClosed" ];
                  target_state = "DatabaseClosed" };
                { signal = "closeFailed"; actions = [ "recordCloseBlocker" ];
                  target_state = "DatabaseCloseBlocked" } ] };
          { stable_id = "DatabaseCloseBlocked";
            transitions =
              [ { signal = "blockersReleased";
                  actions = [ "releaseBlockers"; "reelectActor" ];
                  target_state = "ActorReelected" } ] };
          { stable_id = "DatabaseClosed"; transitions = [] };
          { stable_id = "ActorReelected";
            transitions =
              [ { signal = "requestClose"; actions = [ "attemptClose" ];
                  target_state = "DatabaseClosing" } ] } ] } ]

let fault_events =
  [ { stable_id = "GcReachedLiveStatement"; component_id = "runEventStore";
      severity = Fault_fatal;
      format = "GC reached a statement before explicit finalization" };
    { stable_id = "SqliteFinalizeFault"; component_id = "runEventStore";
      severity = Fault_warning; format = "sqlite3_finalize returned a failure" };
    { stable_id = "SqliteCloseFault"; component_id = "runEventStore";
      severity = Fault_fatal; format = "sqlite3_close returned false" };
    { stable_id = "SqliteCloseBlocked"; component_id = "runEventStore";
      severity = Fault_warning;
      format = "database close remains blocked while actor stays alive" } ]
  @ List.map
      (fun (intent : Debug_intent.t) ->
        { stable_id =
            "DebugFailure_"
            ^ String.map
                (fun character ->
                  if
                    (character >= 'a' && character <= 'z')
                    || (character >= 'A' && character <= 'Z')
                    || (character >= '0' && character <= '9')
                  then character
                  else '_')
                intent.failure_family;
          component_id = intent.fpp.component; severity = Fault_diagnostic;
          format = intent.objective })
      Debug_intent.all

let gate_commands =
  [ { stable_id = "RunSqliteFormalGate"; component_id = "runEventStore";
      kind = Formal_gate; intent_id = "intent.sqlite.formal-gate" };
    { stable_id = "RunSqliteStressGate"; component_id = "runEventStore";
      kind = Stress_gate; intent_id = "intent.sqlite.stress-gate" };
    { stable_id = "RunSqliteReliabilityGate"; component_id = "runEventStore";
      kind = Reliability_gate; intent_id = "intent.sqlite.reliability-gate" };
    { stable_id = "RunSqliteFullGate"; component_id = "runEventStore";
      kind = Full_gate; intent_id = "intent.sqlite.full-gate" };
    { stable_id = "VerifySqliteDependabilitySwarm";
      component_id = "runEventStore"; kind = Swarm_verification;
      intent_id = "intent.sqlite.verify-dependability" } ]
  @ List.map
      (fun (intent : Debug_intent.t) ->
        { stable_id =
            "RunDebug_"
            ^ String.map
                (fun character ->
                  if
                    (character >= 'a' && character <= 'z')
                    || (character >= 'A' && character <= 'Z')
                    || (character >= '0' && character <= '9')
                  then character
                  else '_')
                intent.failure_family;
          component_id = intent.fpp.component; kind = Full_gate;
          intent_id = intent.stable_id })
      Debug_intent.all

let required_capability_ids =
  [ "capability.formal-check"; "capability.verify-full";
    "capability.fpp-check" ]

let context_requirement_ids =
  [ "context.exact-head"; "context.assurance-bundle";
    "context.owned-run-event-store"; "context.resource-envelope" ]

let miq_routes =
  [ { selector_id = "miq.rete-ul";
      required_capability_id = "capability.fpp-check";
      assigned_agent_id = "reteUlGate" };
    { selector_id = "miq.raven";
      required_capability_id = "capability.verify-full";
      assigned_agent_id = "ravenGate" };
    { selector_id = "miq.stpa-fmea";
      required_capability_id = "capability.verify-full";
      assigned_agent_id = "stpaFmeaGate" };
    { selector_id = "miq.z3-formal";
      required_capability_id = "capability.formal-check";
      assigned_agent_id = "z3FormalGate" } ]

let effect_kinds =
  [ Dependability_process_attempt; Verification_suite_execution;
    Durable_artifact_publication; External_resource_observation;
    Repository_source_observation; Approval_nonce_consumption;
    Writer_lease_transition; Production_activation_transition;
    Network_scope_transition; Credential_lease_transition;
    Controlled_filesystem_materialization; Candidate_tree_verification;
    Jujutsu_observation; Jujutsu_local_mutation; Jujutsu_history_rewrite;
    Jujutsu_recovery; Jujutsu_remote_synchronization;
    Jujutsu_remote_publish; Formal_oracle_execution ]

let sqlite_effect_kinds =
  [ Dependability_process_attempt; Verification_suite_execution;
    Durable_artifact_publication ]

let expected_actions : declarative_action list =
  [ { stable_id = "action.sqlite.formal";
      command_id = "RunSqliteFormalGate";
      assigned_agent_id = "z3FormalGate"; dependency_ids = [];
      selector_id = "miq.z3-formal";
      required_capability_id = "capability.formal-check";
      context_requirement_ids; target_component_id = "runEventStore";
      effect_kind = Dependability_process_attempt;
      preparation_id = "prepare.sqlite.formal"; work = Topology_gate };
    { stable_id = "action.sqlite.stress";
      command_id = "RunSqliteStressGate";
      assigned_agent_id = "stpaFmeaGate";
      dependency_ids = [ "action.sqlite.formal" ];
      selector_id = "miq.stpa-fmea";
      required_capability_id = "capability.verify-full";
      context_requirement_ids; target_component_id = "runEventStore";
      effect_kind = Dependability_process_attempt;
      preparation_id = "prepare.sqlite.stress"; work = Topology_gate };
    { stable_id = "action.sqlite.reliability";
      command_id = "RunSqliteReliabilityGate";
      assigned_agent_id = "ravenGate";
      dependency_ids = [ "action.sqlite.stress" ];
      selector_id = "miq.raven";
      required_capability_id = "capability.verify-full";
      context_requirement_ids; target_component_id = "runEventStore";
      effect_kind = Dependability_process_attempt;
      preparation_id = "prepare.sqlite.reliability"; work = Topology_gate };
    { stable_id = "action.sqlite.full";
      command_id = "RunSqliteFullGate"; assigned_agent_id = "reteUlGate";
      dependency_ids = [ "action.sqlite.reliability" ];
      selector_id = "miq.rete-ul";
      required_capability_id = "capability.fpp-check";
      context_requirement_ids; target_component_id = "runEventStore";
      effect_kind = Verification_suite_execution;
      preparation_id = "prepare.sqlite.full"; work = Topology_gate };
    { stable_id = "action.sqlite.swarm-verification";
      command_id = "VerifySqliteDependabilitySwarm";
      assigned_agent_id = "reteUlGate";
      dependency_ids = [ "action.sqlite.full" ];
      selector_id = "miq.rete-ul";
      required_capability_id = "capability.fpp-check";
      context_requirement_ids; target_component_id = "runEventStore";
      effect_kind = Durable_artifact_publication;
      preparation_id = "prepare.sqlite.swarm-verification";
      work = Topology_gate } ]

let sqlite_activity =
  { stable_id = "activity.verify-sqlite-dependability";
    bridge_component_id = "swarmExecutionBridge";
    target_component_id = "runEventStore";
    target_state = "sqlite-dependability-verified";
    intent = "Verify explicit SQLite statement finalization and close lifecycle dependability";
    constraints =
      [ "execute through Run_swarm_bridge only";
        "keep the actor live when sqlite3_close returns false";
        "release blockers and re-elect before retry";
        "treat missing formal or reliability evidence as unavailable" ];
    success_criteria =
      [ "all statements finalized exactly once";
        "database close succeeds after blocker release";
        "formal stress reliability and full gates agree" ];
    required_capability_ids;
    context_requirement_ids;
    miq_routes;
    effect_kinds = sqlite_effect_kinds;
    command_ids = List.map (fun (item : declarative_action) -> item.command_id)
        expected_actions;
    actions = expected_actions }

let repository_suites =
  [
    ("test_agent_bdd", "_build/default/modules/hermes_sysml/test_agent_bdd.exe");
    ("test_agent_chaos", "_build/default/modules/hermes_sysml/test_agent_chaos.exe");
    ("test_agent_fuzz", "_build/default/modules/hermes_sysml/test_agent_fuzz.exe");
    ("test_agent_property", "_build/default/modules/hermes_sysml/test_agent_property.exe");
    ("test_agent_tdd", "_build/default/modules/hermes_sysml/test_agent_tdd.exe");
    ("test_agent_time_hook", "_build/default/modules/system_engg/test_agent_time_hook.exe");
    ("test_anthropic_adapter", "_build/default/modules/hermes_harness/test_anthropic_adapter.exe");
    ("test_authority_manifest", "_build/default/modules/system_engg/test_authority_manifest.exe");
    ("test_baseline_triage", "_build/default/modules/hermes_wiki/src/tools/test_baseline_triage.exe");
    ("test_bedrock_converse", "_build/default/modules/hermes_harness/test_bedrock_converse.exe");
    ("test_blueprint", "_build/default/modules/hermes_harness/test_blueprint.exe");
    ("test_capability_catalog", "_build/default/modules/hermes_harness/test_capability_catalog.exe");
    ("test_challenger_e2e_framework", "_build/default/modules/hermes_harness/test_challenger_e2e_framework.exe");
    ("test_challenger_m1", "_build/default/modules/hermes_harness/test_challenger_m1.exe");
    ("test_challenger_m1_2", "_build/default/modules/hermes_harness/test_challenger_m1_2.exe");
    ("test_challenger_m2_1", "_build/default/modules/hermes_harness/test_challenger_m2_1.exe");
    ("test_challenger_m3_1", "_build/default/modules/hermes_harness/test_challenger_m3_1.exe");
    ("test_challenger_m3_2", "_build/default/modules/swarm/test_challenger_m3_2.exe");
    ("test_challenger_m5_2_stress", "_build/default/modules/swarm/test_challenger_m5_2_stress.exe");
    ("test_claude_artifacts", "_build/default/modules/hermes_wiki/test/test_claude_artifacts.exe");
    ("test_cli", "_build/default/modules/hermes_harness/test_cli.exe");
    ("test_codex_message_shapes", "_build/default/modules/hermes_harness/test_codex_message_shapes.exe");
    ("test_collateral_verifier", "_build/default/modules/system_engg/test_collateral_verifier.exe");
    ("test_context_compression", "_build/default/modules/hermes_agent_loop/test_context_compression.exe");
    ("test_context_engine", "_build/default/modules/hermes_agent_loop/test_context_engine.exe");
    ("test_context_engine_stress", "_build/default/modules/hermes_agent_loop/test_context_engine_stress.exe");
    ("test_contract_catalog", "_build/default/modules/hermes_harness/test_contract_catalog.exe");
    ("test_control_plane", "_build/default/modules/hermes_harness/test_control_plane.exe");
    ("test_converge", "_build/default/modules/hermes_harness/test_converge.exe");
    ("test_converge_formal", "_build/default/modules/hermes_harness/test_converge_formal.exe");
    ("test_conversation_loop", "_build/default/modules/hermes_agent_loop/test_conversation_loop.exe");
    ("test_core", "_build/default/modules/hermes_harness/test_core.exe");
    ("test_datarhei_vision", "_build/default/modules/swarm/test_datarhei_vision.exe");
    ("test_debug_system", "_build/default/modules/hermes_ops/test_debug_system.exe");
    ("test_dep_sheaf", "_build/default/modules/hermes_wiki/test/test_dep_sheaf.exe");
    ("test_dependability_abandonment_protocol", "_build/default/modules/hermes_dependability/test_dependability_abandonment_protocol.exe");
    ("test_dependability_approval", "_build/default/modules/hermes_dependability/test_dependability_approval.exe");
    ("test_dependability_approval_crypto", "_build/default/modules/hermes_dependability/test_dependability_approval_crypto.exe");
    ("test_dependability_authority_store", "_build/default/modules/hermes_dependability/test_dependability_authority_store.exe");
    ("test_dependability_clock", "_build/default/modules/hermes_dependability/test_dependability_clock.exe");
    ("test_dependability_completion_store", "_build/default/modules/hermes_dependability/test_dependability_completion_store.exe");
    ("test_dependability_core", "_build/default/modules/hermes_dependability/test_dependability_core.exe");
    ("test_dependability_credential", "_build/default/modules/hermes_dependability/test_dependability_credential.exe");
    ("test_dependability_dispatch_store", "_build/default/modules/hermes_dependability/test_dependability_dispatch_store.exe");
    ("test_dependability_filesystem", "_build/default/modules/hermes_dependability/test_dependability_filesystem.exe");
    ("test_dependability_graph", "_build/default/modules/hermes_dependability/test_dependability_graph.exe");
    ("test_dependability_meta", "_build/default/modules/hermes_dependability/test_dependability_meta.exe");
    ("test_dependability_network", "_build/default/modules/hermes_dependability/test_dependability_network.exe");
    ("test_dependability_owner_inventory", "_build/default/modules/hermes_dependability/test_dependability_owner_inventory.exe");
    ("test_dependability_process", "_build/default/modules/hermes_dependability/test_dependability_process.exe");
    ("test_dependability_process_protocol", "_build/default/modules/hermes_dependability/test_dependability_process_protocol.exe");
    ("test_dependability_recovery_vault", "_build/default/modules/hermes_dependability/test_dependability_recovery_vault.exe");
    ("test_dependability_sqlite_location", "_build/default/modules/hermes_dependability/test_dependability_sqlite_location.exe");
    ("test_dependability_surface", "_build/default/modules/hermes_dependability/test_dependability_surface.exe");
    ("test_dependability_topology", "_build/default/modules/hermes_dependability/test_dependability_topology.exe");
    ("test_dependability_writer_lease", "_build/default/modules/hermes_dependability/test_dependability_writer_lease.exe");
    ("test_dependency_smt", "_build/default/modules/hermes_harness/test_dependency_smt.exe");
    ("test_determinism_verifier", "_build/default/modules/hermes_harness/test_determinism_verifier.exe");
    ("test_diff_triage", "_build/default/modules/hermes_harness/test_diff_triage.exe");
    ("test_drift_rules", "_build/default/modules/hermes_harness/test_drift_rules.exe");
    ("test_dune_graph", "_build/default/modules/hermes_dune_graph/test_dune_graph.exe");
    ("test_evidence_import", "_build/default/modules/hermes_harness/test_evidence_import.exe");
    ("test_evidence_rollup", "_build/default/modules/hermes_harness/test_evidence_rollup.exe");
    ("test_evidence_store", "_build/default/modules/hermes_harness/test_evidence_store.exe");
    ("test_evolution_model", "_build/default/modules/hermes_harness/test_evolution_model.exe");
    ("test_exact_head_gate", "_build/default/modules/system_engg/test_exact_head_gate.exe");
    ("test_expect_posterior", "_build/default/modules/hermes_harness/test_expect_posterior.exe");
    ("test_external_access_census", "_build/default/modules/hermes_ops/test_external_access_census.exe");
    ("test_external_access_formal", "_build/default/modules/hermes_ops/test_external_access_formal.exe");
    ("test_external_access_fractal", "_build/default/modules/hermes_ops/test_external_access_fractal.exe");
    ("test_external_access_observability", "_build/default/modules/hermes_ops/test_external_access_observability.exe");
    ("test_external_access_otp_register", "_build/default/modules/hermes_ops/test_external_access_otp_register.exe");
    ("test_external_access_rete", "_build/default/modules/hermes_ops/test_external_access_rete.exe");
    ("test_external_access_runtime", "_build/default/modules/hermes_ops/test_external_access_runtime.exe");
    ("test_external_access_smt", "_build/default/modules/hermes_ops/test_external_access_smt.exe");
    ("test_external_access_stan", "_build/default/modules/hermes_ops/test_external_access_stan.exe");
    ("test_feature_model", "_build/default/modules/hermes_wiki/test/test_feature_model.exe");
    ("test_feature_register", "_build/default/modules/hermes_wiki/test/test_feature_register.exe");
    ("test_ffmpeg_swarm", "_build/default/modules/swarm/test_ffmpeg_swarm.exe");
    ("test_files_memory_units", "_build/default/modules/hermes_agent_loop/test_files_memory_units.exe");
    ("test_formal_coverage", "_build/default/modules/hermes_harness/test_formal_coverage.exe");
    ("test_formal_specs", "_build/default/modules/hermes_harness/test_formal_specs.exe");
    ("test_fpp_bdd", "_build/default/modules/hermes_harness/test_fpp_bdd.exe");
    ("test_fpp_fuzz", "_build/default/modules/hermes_harness/test_fpp_fuzz.exe");
    ("test_fpp_interp", "_build/default/modules/hermes_harness/test_fpp_interp.exe");
    ("test_fpp_model", "_build/default/modules/hermes_wiki/test/test_fpp_model.exe");
    ("test_fpp_performance", "_build/default/modules/hermes_harness/test_fpp_performance.exe");
    ("test_fpp_window_authority", "_build/default/modules/hermes_fpp_authority/test_fpp_window_authority.exe");
    ("test_fprime_smt", "_build/default/modules/hermes_harness/test_fprime_smt.exe");
    ("test_fractal_catalog", "_build/default/modules/hermes_harness/test_fractal_catalog.exe");
    ("test_fractal_countermeasures", "_build/default/modules/hermes_harness/test_fractal_countermeasures.exe");
    ("test_fractal_diagnostic", "_build/default/modules/hermes_harness/test_fractal_diagnostic.exe");
    ("test_fractal_ontology", "_build/default/modules/hermes_harness/test_fractal_ontology.exe");
    ("test_fractal_parity", "_build/default/modules/hermes_harness/test_fractal_parity.exe");
    ("test_gemini_schema", "_build/default/modules/hermes_harness/test_gemini_schema.exe");
    ("test_harness_config", "_build/default/modules/hermes_harness/test_harness_config.exe");
    ("test_harness_topology", "_build/default/modules/hermes_harness/test_harness_topology.exe");
    ("test_hermes_analysis", "_build/default/modules/hermes_harness/test_hermes_analysis.exe");
    ("test_hermes_httpd", "_build/default/modules/hermes_wiki/test/test_hermes_httpd.exe");
    ("test_hermes_imports", "_build/default/modules/hermes_harness/test_hermes_imports.exe");
    ("test_hermes_plan", "_build/default/modules/hermes_harness/test_hermes_plan.exe");
    ("test_hermes_rete", "_build/default/modules/hermes_harness/test_hermes_rete.exe");
    ("test_hermes_wiki", "_build/default/modules/hermes_wiki/test/test_hermes_wiki.exe");
    ("test_hermes_zenoh", "_build/default/modules/hermes_harness/test_hermes_zenoh.exe");
    ("test_homeostasis", "_build/default/modules/hermes_harness/test_homeostasis.exe");
    ("test_hz_nrm_01", "_build/default/modules/hermes_agent_loop/test_hz_nrm_01.exe");
    ("test_info_math", "_build/default/modules/hermes_harness/test_info_math.exe");
    ("test_interactive_cli_units", "_build/default/modules/hermes_agent_loop/test_interactive_cli_units.exe");
    ("test_inventory", "_build/default/modules/hermes_harness/test_inventory.exe");
    ("test_jj_action_kind", "_build/default/modules/hermes_vcs/test_jj_action_kind.exe");
    ("test_jj_bypass_quarantine", "_build/default/modules/hermes_vcs/test_jj_bypass_quarantine.exe");
    ("test_jj_campaign_action", "_build/default/modules/hermes_vcs/test_jj_campaign_action.exe");
    ("test_jj_command_contract", "_build/default/modules/hermes_vcs/test_jj_command_contract.exe");
    ("test_jj_completion_store_protocol", "_build/default/modules/hermes_vcs/test_jj_completion_store_protocol.exe");
    ("test_jj_dependency_schema", "_build/default/modules/hermes_vcs/test_jj_dependency_schema.exe");
    ("test_jj_fractal_authority", "_build/default/modules/hermes_vcs/test_jj_fractal_authority.exe");
    ("test_jj_intent", "_build/default/modules/hermes_vcs/test_jj_intent.exe");
    ("test_jj_operation", "_build/default/modules/hermes_vcs/test_jj_operation.exe");
    ("test_jj_partition", "_build/default/modules/hermes_vcs/test_jj_partition.exe");
    ("test_jj_policy", "_build/default/modules/hermes_vcs/test_jj_policy.exe");
    ("test_jj_receipt", "_build/default/modules/hermes_vcs/test_jj_receipt.exe");
    ("test_jj_recovery_schema", "_build/default/modules/hermes_vcs/test_jj_recovery_schema.exe");
    ("test_jj_recovery_transition_port_protocol", "_build/default/modules/hermes_vcs/test_jj_recovery_transition_port_protocol.exe");
    ("test_jj_recovery_transition_port_vault", "_build/default/modules/hermes_ops/test_jj_recovery_transition_port_vault.exe");
    ("test_jj_release_protocol", "_build/default/modules/hermes_vcs/test_jj_release_protocol.exe");
    ("test_jj_revset_manifest", "_build/default/modules/hermes_vcs/test_jj_revset_manifest.exe");
    ("test_jj_runtime_current_protocol", "_build/default/modules/hermes_vcs/test_jj_runtime_current_protocol.exe");
    ("test_jj_runtime_manifest", "_build/default/modules/hermes_vcs/test_jj_runtime_manifest.exe");
    ("test_jj_target_protocol", "_build/default/modules/hermes_vcs/test_jj_target_protocol.exe");
    ("test_jj_unavailable_runtime_registrar", "_build/default/modules/hermes_ops/test_jj_unavailable_runtime_registrar.exe");
    ("test_json_canonical", "_build/default/modules/hermes_agent_loop/test_json_canonical.exe");
    ("test_km_journal", "_build/default/modules/hermes_wiki/test/test_km_journal.exe");
    ("test_license_policy", "_build/default/modules/system_engg/test_license_policy.exe");
    ("test_lmstudio_continuous_swarm", "_build/default/modules/swarm/test_lmstudio_continuous_swarm.exe");
    ("test_lmstudio_dashboard_web", "_build/default/modules/swarm/test_lmstudio_dashboard_web.exe");
    ("test_lmstudio_expect", "_build/default/modules/swarm/test_lmstudio_expect.exe");
    ("test_lmstudio_live", "_build/default/modules/swarm/test_lmstudio_live.exe");
    ("test_lmstudio_monitor", "_build/default/modules/swarm/test_lmstudio_monitor.exe");
    ("test_mcp_units", "_build/default/modules/hermes_agent_loop/test_mcp_units.exe");
    ("test_message_hygiene", "_build/default/modules/hermes_harness/test_message_hygiene.exe");
    ("test_message_repairs", "_build/default/modules/hermes_agent_loop/test_message_repairs.exe");
    ("test_module_intent", "_build/default/modules/hermes_ops/test_module_intent.exe");
    ("test_ocaml_only_guard", "_build/default/modules/hermes_harness/test_ocaml_only_guard.exe");
    ("test_openrouter_contract", "_build/default/modules/hermes_harness/test_openrouter_contract.exe");
    ("test_openrouter_transport", "_build/default/modules/hermes_harness/test_openrouter_transport.exe");
    ("test_ops_capability", "_build/default/modules/hermes_ops/test_ops_capability.exe");
    ("test_ops_capability_gate", "_build/default/modules/hermes_ops/test_ops_capability_gate.exe");
    ("test_ops_command", "_build/default/modules/hermes_ops/test_ops_command.exe");
    ("test_ops_command_runtime", "_build/default/modules/hermes_ops/test_ops_command_runtime.exe");
    ("test_ops_command_service", "_build/default/modules/hermes_ops/test_ops_command_service.exe");
    ("test_ops_completion_history", "_build/default/modules/hermes_ops/test_ops_completion_history.exe");
    ("test_ops_completion_receipt_target", "_build/default/modules/hermes_ops/test_ops_completion_receipt_target.exe");
    ("test_ops_config", "_build/default/modules/hermes_ops/test_ops_config.exe");
    ("test_ops_config_fractal", "_build/default/modules/hermes_ops/test_ops_config_fractal.exe");
    ("test_ops_formal_staging", "_build/default/modules/hermes_ops/test_ops_formal_staging.exe");
    ("test_ops_governance", "_build/default/modules/hermes_ops/test_ops_governance.exe");
    ("test_ops_governance_formal", "_build/default/modules/hermes_ops/test_ops_governance_formal.exe");
    ("test_ops_governance_model", "_build/default/modules/hermes_ops/test_ops_governance_model.exe");
    ("test_ops_jj_target", "_build/default/modules/hermes_ops/test_ops_jj_target.exe");
    ("test_ops_mbse", "_build/default/modules/hermes_ops/test_ops_mbse.exe");
    ("test_ops_mcp", "_build/default/modules/hermes_ops/test_ops_mcp.exe");
    ("test_ops_mutate", "_build/default/modules/hermes_ops/test_ops_mutate.exe");
    ("test_ops_verification_target", "_build/default/modules/hermes_ops/test_ops_verification_target.exe");
    ("test_ops_verify", "_build/default/modules/hermes_ops/test_ops_verify.exe");
    ("test_ops_zenoh", "_build/default/modules/hermes_ops/test_ops_zenoh.exe");
    ("test_orientation_history", "_build/default/modules/hermes_harness/test_orientation_history.exe");
    ("test_parity_algebra", "_build/default/modules/hermes_harness/test_parity_algebra.exe");
    ("test_parity_compare", "_build/default/modules/hermes_harness/test_parity_compare.exe");
    ("test_parity_dashboard", "_build/default/modules/hermes_harness/test_parity_dashboard.exe");
    ("test_parity_ledger", "_build/default/modules/hermes_harness/test_parity_ledger.exe");
    ("test_parity_normalizer", "_build/default/modules/hermes_harness/test_parity_normalizer.exe");
    ("test_parity_tracker", "_build/default/modules/hermes_harness/test_parity_tracker.exe");
    ("test_path_safety", "_build/default/modules/hermes_harness/test_path_safety.exe");
    ("test_phase0_programme", "_build/default/modules/system_engg/test_phase0_programme.exe");
    ("test_posterior_assessment", "_build/default/modules/hermes_harness/test_posterior_assessment.exe");
    ("test_prompt_assembly", "_build/default/modules/hermes_agent_loop/test_prompt_assembly.exe");
    ("test_quint_frontier", "_build/default/modules/hermes_harness/test_quint_frontier.exe");
    ("test_r30_adoption", "_build/default/modules/hermes_harness/test_r30_adoption.exe");
    ("test_ratchet", "_build/default/modules/hermes_wiki/test/test_ratchet.exe");
    ("test_receipt_reliability", "_build/default/modules/hermes_harness/test_receipt_reliability.exe");
    ("test_reconcile", "_build/default/modules/hermes_wiki/test/test_reconcile.exe");
    ("test_redact_units", "_build/default/modules/hermes_agent_loop/test_redact_units.exe");
    ("test_reference_artifacts", "_build/default/modules/hermes_harness/test_reference_artifacts.exe");
    ("test_reference_capture", "_build/default/modules/hermes_harness/test_reference_capture.exe");
    ("test_render_baseline", "_build/default/modules/hermes_wiki/test/test_render_baseline.exe");
    ("test_replay_executor", "_build/default/modules/hermes_harness/test_replay_executor.exe");
    ("test_resource_envelope", "_build/default/modules/hermes_harness/test_resource_envelope.exe");
    ("test_retry_utils", "_build/default/modules/hermes_harness/test_retry_utils.exe");
    ("test_rocq_lattice", "_build/default/modules/hermes_harness/test_rocq_lattice.exe");
    ("test_route_resolution", "_build/default/modules/hermes_harness/test_route_resolution.exe");
    ("test_ruliad", "_build/default/modules/hermes_harness/test_ruliad.exe");
    ("test_ruliad_rules", "_build/default/modules/hermes_harness/test_ruliad_rules.exe");
    ("test_run_abandonment_authority", "_build/default/modules/hermes_ops_dashboard/test_run_abandonment_authority.exe");
    ("test_run_analysis", "_build/default/modules/hermes_ops_dashboard/test_run_analysis.exe");
    ("test_run_analysis_z3_worker", "_build/default/modules/hermes_ops_dashboard/test_run_analysis_z3_worker.exe");
    ("test_run_analysis_z3_worker_protocol", "_build/default/modules/hermes_ops_dashboard/test_run_analysis_z3_worker_protocol.exe");
    ("test_run_assurance", "_build/default/modules/hermes_ops_dashboard/test_run_assurance.exe");
    ("test_run_conditional_authority", "_build/default/modules/hermes_ops_dashboard/test_run_conditional_authority.exe");
    ("test_run_dependency_authority", "_build/default/modules/hermes_ops_dashboard/test_run_dependency_authority.exe");
    ("test_run_effect_authority", "_build/default/modules/hermes_ops_dashboard/test_run_effect_authority.exe");
    ("test_run_event_store", "_build/default/modules/hermes_ops_dashboard/test_run_event_store.exe");
    ("test_run_formal_relational", "_build/default/modules/hermes_ops_dashboard/test_run_formal_relational.exe");
    ("test_run_fpp_authority", "_build/default/modules/hermes_ops_dashboard/test_run_fpp_authority.exe");
    ("test_run_governance", "_build/default/modules/hermes_ops_dashboard/test_run_governance.exe");
    ("test_run_intelligence", "_build/default/modules/hermes_ops_dashboard/test_run_intelligence.exe");
    ("test_run_jj_authority", "_build/default/modules/hermes_ops_dashboard/test_run_jj_authority.exe");
    ("test_run_jj_candidate_activation", "_build/default/modules/hermes_ops/test_run_jj_candidate_activation.exe");
    ("test_run_jj_operator_runtime", "_build/default/modules/hermes_ops/test_run_jj_operator_runtime.exe");
    ("test_run_jj_runtime_registry", "_build/default/modules/hermes_ops_dashboard/test_run_jj_runtime_registry.exe");
    ("test_run_model", "_build/default/modules/hermes_ops_dashboard/test_run_model.exe");
    ("test_run_model_surfaces", "_build/default/modules/hermes_ops_dashboard/test_run_model_surfaces.exe");
    ("test_run_operator_authority", "_build/default/modules/hermes_ops_dashboard/test_run_operator_authority.exe");
    ("test_run_root_bootstrap", "_build/default/modules/hermes_ops_dashboard/test_run_root_bootstrap.exe");
    ("test_run_safety", "_build/default/modules/hermes_ops_dashboard/test_run_safety.exe");
    ("test_run_snapshot", "_build/default/modules/hermes_ops_dashboard/test_run_snapshot.exe");
    ("test_run_swarm_bridge", "_build/default/modules/hermes_ops_dashboard/test_run_swarm_bridge.exe");
    ("test_run_swarm_bridge_programme", "_build/default/modules/system_engg/test_run_swarm_bridge_programme.exe");
    ("test_run_swarm_preparation", "_build/default/modules/hermes_ops_dashboard/test_run_swarm_preparation.exe");
    ("test_runtime_coverage", "_build/default/modules/hermes_harness/test_runtime_coverage.exe");
    ("test_rust_rules", "_build/default/modules/hermes_harness/test_rust_rules.exe");
    ("test_session_fixture", "_build/default/modules/hermes_harness/test_session_fixture.exe");
    ("test_site_build", "_build/default/modules/hermes_harness/test_site_build.exe");
    ("test_skill_units", "_build/default/modules/hermes_agent_loop/test_skill_units.exe");
    ("test_slice_units", "_build/default/modules/hermes_agent_loop/test_slice_units.exe");
    ("test_smtml_alerts", "_build/default/modules/hermes_harness/test_smtml_alerts.exe");
    ("test_smtml_lattice", "_build/default/modules/hermes_harness/test_smtml_lattice.exe");
    ("test_sop_execution", "_build/default/modules/swarm/test_sop_execution.exe");
    ("test_sop_execution_containment", "_build/default/modules/swarm/test_sop_execution_containment.exe");
    ("test_sop_execution_stress", "_build/default/modules/swarm/test_sop_execution_stress.exe");
    ("test_source_artifact", "_build/default/modules/system_engg/test_source_artifact.exe");
    ("test_sqlite_lifecycle_model", "_build/default/modules/hermes_dependability/test_sqlite_lifecycle_model.exe");
    ("test_sqlite_lifecycle_smt", "_build/default/modules/hermes_dependability/test_sqlite_lifecycle_smt.exe");
    ("test_subagent_units", "_build/default/modules/hermes_agent_loop/test_subagent_units.exe");
    ("test_suite_telemetry", "_build/default/modules/hermes_harness/test_suite_telemetry.exe");
    ("test_swarm_bridge_reservation", "_build/default/modules/swarm/test_swarm_bridge_reservation.exe");
    ("test_swarm_chaos", "_build/default/modules/swarm/test_swarm_chaos.exe");
    ("test_swarm_fuzz", "_build/default/modules/swarm/test_swarm_fuzz.exe");
    ("test_swarm_unit", "_build/default/modules/swarm/test_swarm_unit.exe");
    ("test_sysml_algebra", "_build/default/modules/hermes_sysml/test_sysml_algebra.exe");
    ("test_system_engg_plan_bridge", "_build/default/modules/system_engg/test_system_engg_plan_bridge.exe");
    ("test_tool_hygiene", "_build/default/modules/hermes_toolchain/test_tool_hygiene.exe");
    ("test_tool_units", "_build/default/modules/hermes_agent_loop/test_tool_units.exe");
    ("test_toolchain_check", "_build/default/modules/hermes_toolchain/test_toolchain_check.exe");
    ("test_turn_budget", "_build/default/modules/hermes_harness/test_turn_budget.exe");
    ("test_turn_finalization", "_build/default/modules/hermes_agent_loop/test_turn_finalization.exe");
    ("test_turn_preflight", "_build/default/modules/hermes_harness/test_turn_preflight.exe");
    ("test_vision_fuzz", "_build/default/modules/hermes_vision/test_vision_fuzz.exe");
    ("test_vision_lifecycle", "_build/default/modules/swarm/test_vision_lifecycle.exe");
    ("test_vision_pipeline", "_build/default/modules/hermes_vision/test_vision_pipeline.exe");
    ("test_vision_swarm_adapter", "_build/default/modules/swarm/test_vision_swarm_adapter.exe");
    ("test_wiki_address", "_build/default/modules/hermes_wiki/test/test_wiki_address.exe");
    ("test_wiki_ast", "_build/default/modules/hermes_wiki/test/test_wiki_ast.exe");
    ("test_wiki_baseline", "_build/default/modules/hermes_wiki/test/test_wiki_baseline.exe");
    ("test_wiki_blocks", "_build/default/modules/hermes_wiki/test/test_wiki_blocks.exe");
    ("test_wiki_build", "_build/default/modules/hermes_wiki/test/test_wiki_build.exe");
    ("test_wiki_datastore", "_build/default/modules/hermes_wiki/test/test_wiki_datastore.exe");
    ("test_wiki_diagnostics", "_build/default/modules/hermes_wiki/test/test_wiki_diagnostics.exe");
    ("test_wiki_directive", "_build/default/modules/hermes_wiki/test/test_wiki_directive.exe");
    ("test_wiki_doctest", "_build/default/modules/hermes_wiki/test/test_wiki_doctest.exe");
    ("test_wiki_export", "_build/default/modules/hermes_wiki/test/test_wiki_export.exe");
    ("test_wiki_frontend", "_build/default/modules/hermes_wiki/test/test_wiki_frontend.exe");
    ("test_wiki_graph", "_build/default/modules/hermes_wiki/test/test_wiki_graph.exe");
    ("test_wiki_iface", "_build/default/modules/hermes_wiki/test/test_wiki_iface.exe");
    ("test_wiki_include", "_build/default/modules/hermes_wiki/test/test_wiki_include.exe");
    ("test_wiki_lifecycle", "_build/default/modules/hermes_wiki/test/test_wiki_lifecycle.exe");
    ("test_wiki_navsearch", "_build/default/modules/hermes_wiki/test/test_wiki_navsearch.exe");
    ("test_wiki_ordering", "_build/default/modules/hermes_wiki/test/test_wiki_ordering.exe");
    ("test_wiki_present", "_build/default/modules/hermes_wiki/test/test_wiki_present.exe");
    ("test_wiki_query", "_build/default/modules/hermes_wiki/test/test_wiki_query.exe");
    ("test_wiki_ref", "_build/default/modules/hermes_wiki/test/test_wiki_ref.exe");
    ("test_wiki_routes", "_build/default/modules/hermes_wiki/test/test_wiki_routes.exe");
    ("test_wiki_search", "_build/default/modules/hermes_wiki/test/test_wiki_search.exe");
    ("test_wiki_similarity", "_build/default/modules/hermes_wiki/test/test_wiki_similarity.exe");
    ("test_wiki_source_ext", "_build/default/modules/hermes_wiki/test/test_wiki_source_ext.exe");
    ("test_wiki_theme", "_build/default/modules/hermes_wiki/test/test_wiki_theme.exe");
    ("test_wiki_toc", "_build/default/modules/hermes_wiki/test/test_wiki_toc.exe");
    ("test_wiki_topology", "_build/default/modules/hermes_wiki/test/test_wiki_topology.exe");
    ("test_wiki_transclude", "_build/default/modules/hermes_wiki/test/test_wiki_transclude.exe");
    ("test_wiki_tyxml", "_build/default/modules/hermes_wiki/test/test_wiki_tyxml.exe");
    ("test_wiki_view", "_build/default/modules/hermes_wiki/test/test_wiki_view.exe");
    ("test_wiki_visibility", "_build/default/modules/hermes_wiki/test/test_wiki_visibility.exe");
    ("test_zellij_live", "_build/default/modules/hermes_zellij/test_zellij_live.exe");
    ("test_zellij_model", "_build/default/modules/hermes_zellij/test_zellij_model.exe");
    ("test_zellij_projection", "_build/default/modules/hermes_zellij/test_zellij_projection.exe") ]

let repository_miq_routes =
  [ { selector_id = "miq.raven";
      required_capability_id = "capability.verify-full";
      assigned_agent_id = "ravenGate" } ]

let repository_build_action_id = "action.verify-repository.build"

let repository_actions =
  let action ~stable_id ~command_id ~dependency_ids ~preparation_id work =
    { stable_id; command_id; assigned_agent_id = "ravenGate"; dependency_ids;
      selector_id = "miq.raven";
      required_capability_id = "capability.verify-full";
      context_requirement_ids; target_component_id = "suiteWorker";
      effect_kind = Verification_suite_execution; preparation_id; work }
  in
  action ~stable_id:repository_build_action_id
    ~command_id:"BuildRepositoryVerification" ~dependency_ids:[]
    ~preparation_id:"prepare.verify-repository.build.full"
    (Repository_build
       { profile = Verification_full;
         build_command = "dune build --pkg=disabled 2>&1" })
  :: List.map
       (fun (suite_id, executable) ->
         action ~stable_id:("action.verify-repository.suite." ^ suite_id)
           ~command_id:("ExecuteRepositoryVerificationSuite." ^ suite_id)
           ~dependency_ids:[ repository_build_action_id ]
           ~preparation_id:("prepare.verify-repository.suite." ^ suite_id)
           (Repository_verification_suite
              { profile = Verification_full; suite_id; executable }))
       repository_suites

let repository_activity =
  { stable_id = "activity.verify-repository";
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
    context_requirement_ids;
    miq_routes = repository_miq_routes;
    effect_kinds = [ Verification_suite_execution ];
    command_ids =
      List.map (fun (item : declarative_action) -> item.command_id)
        repository_actions;
    actions = repository_actions }

let activities = [ sqlite_activity; repository_activity ]

let requirements =
  [ { stable_id = "REQ-OPS-FPP-VALID";
      statement = "The operations topology is nonempty and FPP-valid.";
      verifier_id = "verify.operations.fpp";
      source = "modules/hermes_ops_dashboard/test_run_model_surfaces.ml";
      covered_elements = component_names };
    { stable_id = "REQ-OPS-METRIC-TOTAL";
      statement = "Every declared run metric resolves to exactly one FPP channel.";
      verifier_id = "verify.operations.metric-channels";
      source = "modules/hermes_ops_dashboard/test_run_model_surfaces.ml";
      covered_elements =
        List.map (fun (item : channel) -> item.stable_id) metric_channels };
    { stable_id = "REQ-OPS-ID-WINDOWS";
      statement = "The five-owner normative FPP allocation rows are present, representable, policy-conformant, and pairwise disjoint; unregistered actual-instance collisions are diagnosed separately.";
      verifier_id = "verify.operations.id-windows";
      source = "modules/hermes_ops_dashboard/test_run_model_surfaces.ml";
      covered_elements = component_names };
    { stable_id = "REQ-OPS-EXECUTION-BRIDGE";
      statement = "No operations execution path bypasses swarmExecutionBridge.";
      verifier_id = "verify.operations.execution-bridge";
      source = "modules/hermes_ops_dashboard/test_run_model_surfaces.ml";
      covered_elements = [ "swarmExecutionBridge"; "suiteWorker";
        "edge.execution.bridge-worker" ] };
    { stable_id = "REQ-OPS-UI-ISOLATION";
      statement = "Dream, Bonsai, intent, effect, and WebGL projections cannot reach admission.";
      verifier_id = "verify.operations.ui-isolation";
      source = "modules/hermes_ops_dashboard/test_run_model_surfaces.ml";
      covered_elements = [ "dreamGateway"; "bonsaiDashboard"; "uiIntentCompiler";
        "uiEffectInterpreter"; "webglRenderer" ] };
    { stable_id = "REQ-OPS-MBSE-CORRESPONDENCE";
      statement = "SysML, Turtle, MMS, and FPP carry one identical typed manifest.";
      verifier_id = "verify.operations.mbse-correspondence";
      source = "modules/hermes_ops_dashboard/run_mbse.ml";
      covered_elements =
        component_names @ List.map (fun (item : edge) -> item.stable_id) edges };
    { stable_id = "REQ-OPS-FORMAL-NONVACUITY";
      statement = "Each negated topology law is Unsat and every paired false control is Sat.";
      verifier_id = "verify.operations.formal-nonvacuity";
      source = "modules/hermes_ops_dashboard/run_formal.ml";
      covered_elements = [ "z3FormalGate"; "swarmExecutionBridge" ] };
    { stable_id = "HZ-SQL-FIN-01";
      statement =
        "RunEventStore finalizes every statement explicitly, keeps the actor alive on close failure, releases blockers, re-elects, and admits completion only through formal, stress, reliability, and full Swarm gates.";
      verifier_id = "verify.operations.fpp";
      source = "modules/hermes_ops_dashboard/test_run_model_surfaces.ml";
      covered_elements =
        [ "runEventStore"; "StatementFinalizeLifecycle";
          "DatabaseCloseLifecycle"; "GcReachedLiveStatement";
          "SqliteFinalizeFault"; "SqliteCloseFault"; "SqliteCloseBlocked";
          "RunSqliteFormalGate"; "RunSqliteStressGate";
          "RunSqliteReliabilityGate"; "RunSqliteFullGate";
          "VerifySqliteDependabilitySwarm";
          "activity.verify-sqlite-dependability" ] } ]

let formal_policy =
  { execution =
      { supervisor_component_id = "runSupervisor";
        bridge_component_id = "swarmExecutionBridge";
        worker_component_id = "suiteWorker";
        required_execution_edge_id = "edge.execution.bridge-worker" };
    ui_isolation =
      { ui_component_ids =
          [ "dreamGateway"; "bonsaiDashboard"; "uiIntentCompiler";
            "uiEffectInterpreter"; "webglRenderer" ];
        admission_component_ids =
          [ "runSupervisor"; "reteUlGate"; "ravenGate"; "stpaFmeaGate";
            "ruliadAnalyzer"; "stanReliability"; "z3FormalGate";
            "assuranceGate"; "swarmExecutionBridge"; "suiteWorker" ] };
    model_contract =
      { fpp_model_name = Fpp_window_authority.declared_model_name Fpp_window_authority.Operations;
        fpp_topology_name = "HermesOperations";
        fpp_base_id = Fpp_window_authority.window_base Fpp_window_authority.Operations;
        projection_surface_ids = [ "sysml-v2"; "oml-owl"; "openmbee-mms"; "fpp" ] };
    sqlite =
      { machine_state_ids =
          [ ("StatementFinalizeLifecycle",
             [ "StatementOpen"; "StatementFinalizing"; "StatementFinalized";
               "StatementFinalizeFailed" ]);
            ("DatabaseCloseLifecycle",
             [ "DatabaseOpen"; "DatabaseClosing"; "DatabaseCloseBlocked";
               "DatabaseClosed"; "ActorReelected" ]) ];
        required_transitions =
          [ { machine_id = "StatementFinalizeLifecycle";
              source_state_id = "StatementOpen"; signal_id = "requestFinalize";
              target_state_id = "StatementFinalizing";
              required_action_ids = [ "beginFinalize" ] };
            { machine_id = "StatementFinalizeLifecycle";
              source_state_id = "StatementOpen"; signal_id = "gcReached";
              target_state_id = "StatementFinalizeFailed";
              required_action_ids = [ "recordGcFault" ] };
            { machine_id = "StatementFinalizeLifecycle";
              source_state_id = "StatementFinalizing";
              signal_id = "finalizeSucceeded";
              target_state_id = "StatementFinalized";
              required_action_ids = [ "recordFinalized" ] };
            { machine_id = "StatementFinalizeLifecycle";
              source_state_id = "StatementFinalizing";
              signal_id = "finalizeFailed";
              target_state_id = "StatementFinalizeFailed";
              required_action_ids = [ "recordFinalizeFault" ] };
            { machine_id = "StatementFinalizeLifecycle";
              source_state_id = "StatementFinalizeFailed";
              signal_id = "retryFinalize";
              target_state_id = "StatementFinalizing";
              required_action_ids = [ "beginFinalize" ] };
            { machine_id = "DatabaseCloseLifecycle";
              source_state_id = "DatabaseOpen"; signal_id = "requestClose";
              target_state_id = "DatabaseClosing";
              required_action_ids = [ "attemptClose" ] };
            { machine_id = "DatabaseCloseLifecycle";
              source_state_id = "DatabaseClosing"; signal_id = "closeSucceeded";
              target_state_id = "DatabaseClosed";
              required_action_ids = [ "recordClosed" ] };
            { machine_id = "DatabaseCloseLifecycle";
              source_state_id = "DatabaseClosing"; signal_id = "closeFailed";
              target_state_id = "DatabaseCloseBlocked";
              required_action_ids = [ "recordCloseBlocker" ] };
            { machine_id = "DatabaseCloseLifecycle";
              source_state_id = "DatabaseCloseBlocked";
              signal_id = "blockersReleased";
              target_state_id = "ActorReelected";
              required_action_ids = [ "releaseBlockers"; "reelectActor" ] };
            { machine_id = "DatabaseCloseLifecycle";
              source_state_id = "ActorReelected"; signal_id = "requestClose";
              target_state_id = "DatabaseClosing";
              required_action_ids = [ "attemptClose" ] } ];
        fault_event_ids =
          [ "GcReachedLiveStatement"; "SqliteFinalizeFault"; "SqliteCloseFault";
            "SqliteCloseBlocked" ];
        gate_command_ids =
          [ "RunSqliteFormalGate"; "RunSqliteStressGate";
            "RunSqliteReliabilityGate"; "RunSqliteFullGate";
            "VerifySqliteDependabilitySwarm" ];
        activity_id = "activity.verify-sqlite-dependability";
        hazard_requirement_id = "HZ-SQL-FIN-01" } }

let authority =
  { components; ports; channels; edges; verifiers; lifecycle_machines;
    fault_events; gate_commands; activities; requirements; formal_policy }

let string_of_direction = function Input -> "input" | Output -> "output"
let string_of_port_kind = function Intent -> "intent" | Evidence -> "evidence"
  | State -> "state" | Telemetry -> "telemetry" | Scene -> "scene"
let string_of_edge_kind = function Admission -> "admission" | Execution -> "execution"
  | Evidence_flow -> "evidence" | State_flow -> "state" | Projection -> "projection"
let string_of_verifier_kind = function Fpp_validation -> "fpp-validation"
  | Metric_channel_mapping -> "metric-channel-mapping"
  | Window_disjointness -> "window-disjointness"
  | Execution_mediation -> "execution-mediation"
  | Ui_admission_isolation -> "ui-admission-isolation"
  | Projection_correspondence -> "projection-correspondence"
  | Formal_nonvacuity -> "formal-nonvacuity"
let string_of_fault_severity = function Fault_diagnostic -> "diagnostic"
  | Fault_warning -> "warning" | Fault_fatal -> "fatal"
let string_of_gate_kind = function Formal_gate -> "formal"
  | Stress_gate -> "stress" | Reliability_gate -> "reliability"
  | Full_gate -> "full" | Swarm_verification -> "swarm-verification"
let effect_kind_id = function
  | Dependability_process_attempt -> "dependability-process-attempt"
  | Verification_suite_execution -> "verification-suite-execution"
  | Durable_artifact_publication -> "durable-artifact-publication"
  | External_resource_observation -> "external-resource-observation"
  | Repository_source_observation -> "repository-source-observation"
  | Approval_nonce_consumption -> "approval-nonce-consumption"
  | Writer_lease_transition -> "writer-lease-transition"
  | Production_activation_transition -> "production-activation-transition"
  | Network_scope_transition -> "network-scope-transition"
  | Credential_lease_transition -> "credential-lease-transition"
  | Controlled_filesystem_materialization ->
      "controlled-filesystem-materialization"
  | Candidate_tree_verification -> "candidate-tree-verification"
  | Jujutsu_observation -> "jujutsu-observation"
  | Jujutsu_local_mutation -> "jujutsu-local-mutation"
  | Jujutsu_history_rewrite -> "jujutsu-history-rewrite"
  | Jujutsu_recovery -> "jujutsu-recovery"
  | Jujutsu_remote_synchronization -> "jujutsu-remote-synchronization"
  | Jujutsu_remote_publish -> "jujutsu-remote-publish"
  | Formal_oracle_execution -> "formal-oracle-execution"

let string_of_effect_kind = effect_kind_id

let effect_kind_of_jujutsu_operation operation =
  match (Jj_operation.declaration operation).effect_class with
  | Jj_operation.Effect_observation -> Jujutsu_observation
  | Jj_operation.Effect_local_mutation -> Jujutsu_local_mutation
  | Jj_operation.Effect_history_rewrite -> Jujutsu_history_rewrite
  | Jj_operation.Effect_recovery -> Jujutsu_recovery
  | Jj_operation.Effect_fetch -> Jujutsu_remote_synchronization
  | Jj_operation.Effect_remote_publish -> Jujutsu_remote_publish

let jujutsu_action_role_id = function
  | Observe_before -> "observe-before"
  | Execute -> "execute"
  | Observe_after -> "observe-after"

let controlled_lifecycle_states =
  [ Declared; Prepared; Admitted; Running; Readback; Terminal; Refused;
    Indeterminate; Stale ]

let controlled_lifecycle_state_id = function
  | Declared -> "declared"
  | Prepared -> "prepared"
  | Admitted -> "admitted"
  | Running -> "running"
  | Readback -> "readback"
  | Terminal -> "terminal"
  | Refused -> "refused"
  | Indeterminate -> "indeterminate"
  | Stale -> "stale"

let conditional_control_states =
  [ Guarded; Consume_ready; Action_terminal; Decision_pending;
    Continue_selected; Branch_selected; Decision_indeterminate ]

let conditional_control_state_id = function
  | Guarded -> "guarded"
  | Consume_ready -> "consume-ready"
  | Action_terminal -> "action-terminal"
  | Decision_pending -> "decision-pending"
  | Continue_selected -> "continue-selected"
  | Branch_selected -> "branch-selected"
  | Decision_indeterminate -> "decision-indeterminate"

let conditional_control_events =
  [ Prefix_complete; Decision_committed; Decision_replayed;
    Condition_not_selected_recorded; Decision_refused ]

let conditional_control_event_id = function
  | Prefix_complete -> "prefix-complete"
  | Decision_committed -> "decision-committed"
  | Decision_replayed -> "decision-replayed"
  | Condition_not_selected_recorded -> "condition-not-selected-recorded"
  | Decision_refused -> "decision-refused"

let conditional_channel_kinds =
  [ Bounded_family_prefix; Decision_receipt; Selected_branch_identity;
    Node_disposition ]

let conditional_channel_kind_id = function
  | Bounded_family_prefix -> "bounded-family-prefix"
  | Decision_receipt -> "decision-receipt"
  | Selected_branch_identity -> "selected-branch-identity"
  | Node_disposition -> "node-disposition"

let live_execution_posture = `Implemented_unavailable

let json_of_miq_route (route : miq_route) =
  `Assoc
    [ ("assignedAgentId", `String route.assigned_agent_id);
      ("requiredCapabilityId", `String route.required_capability_id);
      ("selectorId", `String route.selector_id) ]

let string_of_verification_profile = function
  | Verification_fast -> "fast"
  | Verification_full -> "full"

let auxiliary_work_id prefix role =
  prefix ^ ":" ^ Jj_action_kind.auxiliary_role_key role

let action_work_id = function
  | Topology_gate -> "topology-gate"
  | Repository_build { profile; build_command } ->
      let digest =
        build_command |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex
      in
      "repository-build:" ^ string_of_verification_profile profile ^ ":" ^ digest
  | Repository_verification_suite { profile; suite_id; executable } ->
      let digest =
        executable |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex
      in
      String.concat ":"
        [ "repository-verification-suite";
          string_of_verification_profile profile; suite_id; digest ]
  | Clock_work role -> auxiliary_work_id "clock" role
  | Filesystem_work role -> auxiliary_work_id "filesystem" role
  | External_resource_work role -> auxiliary_work_id "external-resource" role
  | Repository_source_work role -> auxiliary_work_id "repository-source" role
  | Approval_nonce_work role -> auxiliary_work_id "approval-nonce" role
  | Writer_lease_work role -> auxiliary_work_id "writer-lease" role
  | Network_scope_work role -> auxiliary_work_id "network-scope" role
  | Credential_lease_work role -> auxiliary_work_id "credential-lease" role
  | Activation_transition_work action ->
      "activation-transition:" ^ Jj_action_kind.frontier_action_key action
  | Mutation_frontier_work action ->
      "mutation-frontier:" ^ Jj_action_kind.frontier_action_key action
  | Materialization_work role -> auxiliary_work_id "materialization" role
  | Candidate_verification_work step ->
      "candidate-verification:" ^ Jj_action_kind.candidate_step_key step
  | Formal_oracle_work process ->
      "formal-oracle:" ^ Jj_action_kind.formal_process_key process
  | Jujutsu_readback_work role -> auxiliary_work_id "jujutsu-readback" role
  | Completion_receipt_work role ->
      auxiliary_work_id "completion-receipt" role
  | Jujutsu_work { operation; role } ->
      String.concat ":"
        [ "jujutsu"; (Jj_operation.declaration operation).key;
          jujutsu_action_role_id role ]

let action_work_gaps = function
  | Topology_gate -> []
  | Repository_build { build_command; _ } ->
      if String.trim build_command = "" then [ "repository build command is empty" ]
      else []
  | Repository_verification_suite { suite_id; executable; _ } ->
      [ if String.trim suite_id = "" then Some "repository suite id is empty" else None;
        if String.trim executable = "" then Some "repository suite executable is empty"
        else None ]
      |> List.filter_map Fun.id
  | Clock_work Jj_action_kind.Acquire_clock -> []
  | Filesystem_work (Jj_action_kind.Observe_tree | Observe_object) -> []
  | External_resource_work Jj_action_kind.Observe_external_resource -> []
  | Repository_source_work
      (Jj_action_kind.Observe_repository_source | Observe_release_bundle) -> []
  | Approval_nonce_work Jj_action_kind.Consume_approval_nonce -> []
  | Writer_lease_work
      (Jj_action_kind.Acquire_writer_lease | Renew_writer_lease
      | Release_writer_lease) -> []
  | Network_scope_work
      (Jj_action_kind.Acquire_network_scope | Release_network_scope) -> []
  | Credential_lease_work
      (Jj_action_kind.Acquire_credential_lease | Release_credential_lease) -> []
  | Activation_transition_work Jj_action_kind.Activate_source_recovery_branch -> []
  | Mutation_frontier_work
      (Jj_action_kind.Set_activity_frontier Jj_action_kind.Reconciled_terminal) -> []
  | Materialization_work
      (Jj_action_kind.Materialize_candidate | Write_partition | Restore_partition
      | Restore_sealed_record_preimage | Write_sealed_record_candidate
      | Remove_disposable_scope | Stage_recovery_set | Reconcile_recovery_set
      | Cleanup_recovery_set) -> []
  | Candidate_verification_work _ | Formal_oracle_work _ | Jujutsu_work _ -> []
  | Jujutsu_readback_work Jj_action_kind.Readback_jj_state -> []
  | Completion_receipt_work
      (Jj_action_kind.Reserve_completion_receipt
      | Finalize_completion_receipt) -> []
  | Clock_work _ -> [ "clock work carries a non-clock action" ]
  | Filesystem_work _ -> [ "filesystem work carries a non-observation action" ]
  | External_resource_work _ ->
      [ "external-resource work carries a different action" ]
  | Repository_source_work _ ->
      [ "repository-source work carries a different action" ]
  | Approval_nonce_work _ -> [ "approval work carries a non-consume action" ]
  | Writer_lease_work _ -> [ "writer-lease work carries a different action" ]
  | Network_scope_work _ -> [ "network-scope work carries a different action" ]
  | Credential_lease_work _ ->
      [ "credential-lease work carries a different action" ]
  | Activation_transition_work _ ->
      [ "activation work carries the terminal frontier action" ]
  | Mutation_frontier_work _ ->
      [ "mutation-frontier work carries the activation action" ]
  | Materialization_work _ ->
      [ "materialization work carries a non-materialization action" ]
  | Jujutsu_readback_work _ ->
      [ "Jujutsu readback work carries a non-readback action" ]
  | Completion_receipt_work _ ->
      [ "completion receipt work carries a non-completion action" ]

let task7a_action_work_class_id = function
  | Clock_work _ -> Some "clock"
  | Filesystem_work _ -> Some "filesystem"
  | External_resource_work _ -> Some "external-resource"
  | Repository_source_work _ -> Some "repository-source"
  | Approval_nonce_work _ -> Some "approval-nonce"
  | Writer_lease_work _ -> Some "writer-lease"
  | Network_scope_work _ -> Some "network-scope"
  | Credential_lease_work _ -> Some "credential-lease"
  | Activation_transition_work _ -> Some "activation-transition"
  | Mutation_frontier_work _ -> Some "mutation-frontier"
  | Materialization_work _ -> Some "materialization"
  | Candidate_verification_work _ -> Some "candidate-verification"
  | Formal_oracle_work _ -> Some "formal-oracle"
  | Jujutsu_work _ -> Some "jujutsu-operation"
  | Jujutsu_readback_work _ -> Some "jujutsu-readback"
  | Completion_receipt_work _ -> Some "completion-receipt"
  | Topology_gate | Repository_build _ | Repository_verification_suite _ -> None

let task7a_action_work_representatives =
  [ Clock_work Jj_action_kind.Acquire_clock;
    Filesystem_work Jj_action_kind.Observe_tree;
    External_resource_work Jj_action_kind.Observe_external_resource;
    Repository_source_work Jj_action_kind.Observe_repository_source;
    Approval_nonce_work Jj_action_kind.Consume_approval_nonce;
    Writer_lease_work Jj_action_kind.Acquire_writer_lease;
    Network_scope_work Jj_action_kind.Acquire_network_scope;
    Credential_lease_work Jj_action_kind.Acquire_credential_lease;
    Activation_transition_work Jj_action_kind.Activate_source_recovery_branch;
    Mutation_frontier_work
      (Jj_action_kind.Set_activity_frontier
         Jj_action_kind.Reconciled_terminal);
    Materialization_work Jj_action_kind.Materialize_candidate;
    Candidate_verification_work Jj_action_kind.Toolchain_check;
    Formal_oracle_work
      (Jj_action_kind.formal_process ~tool:Jj_action_kind.Gospel
         ~case:Jj_action_kind.Positive);
    Jujutsu_work { operation = Jj_operation.Version; role = Execute };
    Jujutsu_readback_work Jj_action_kind.Readback_jj_state;
    Completion_receipt_work Jj_action_kind.Reserve_completion_receipt ]

let task7a_action_work_class_ids =
  List.filter_map task7a_action_work_class_id task7a_action_work_representatives

let task7a_action_work_class_digest =
  task7a_action_work_class_ids |> String.concat "\000"
  |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex

let task7a_completion_receipt_work_ids =
  [ Jj_action_kind.Reserve_completion_receipt;
    Jj_action_kind.Finalize_completion_receipt ]
  |> List.map (fun role -> action_work_id (Completion_receipt_work role))

let task7a_completion_receipt_work_digest_of work_ids =
  work_ids |> String.concat "\000" |> Digestif.SHA256.digest_string
  |> Digestif.SHA256.to_hex

let task7a_completion_receipt_work_digest =
  task7a_completion_receipt_work_digest_of task7a_completion_receipt_work_ids

let task7a_bridge_unavailable = "task8-bridge-unavailable"
let task7a_target_unavailable = "task9-target-unavailable"

let task7a_target_of_work work =
  match task7a_action_work_class_id work with
  | None -> task7a_target_unavailable
  | Some class_id -> "task9-target." ^ class_id ^ ".unavailable"

let task7a_action ~activity_id ~ordinal ~dependency_ids ~effect_kind ~work =
  let suffix = string_of_int ordinal in
  { stable_id = activity_id ^ ".action." ^ suffix;
    command_id = activity_id ^ ".command." ^ suffix;
    assigned_agent_id = "task8-agent-unavailable";
    dependency_ids;
    selector_id = "task8-selector-unavailable";
    required_capability_id = "task8-capability-unavailable";
    context_requirement_ids = [ "task8-context-unavailable" ];
    target_component_id = task7a_target_of_work work;
    effect_kind;
    preparation_id = activity_id ^ ".preparation." ^ suffix;
    work }

let task7a_activity ~stable_id ~intent actions =
  { stable_id;
    bridge_component_id = task7a_bridge_unavailable;
    target_component_id = task7a_target_unavailable;
    target_state = "task9-target-current-unavailable";
    intent;
    constraints =
      [ "pure Task-7A declaration only";
        "Task-8 bridge admission remains unavailable";
        "Task-9 target mapping remains unavailable" ];
    success_criteria =
      [ "closed action denominator is exact";
        "no action is admitted or executable" ];
    required_capability_ids = [ "task8-capability-unavailable" ];
    context_requirement_ids = [ "task8-context-unavailable" ];
    miq_routes =
      [ { selector_id = "task8-selector-unavailable";
          required_capability_id = "task8-capability-unavailable";
          assigned_agent_id = "task8-agent-unavailable" } ];
    effect_kinds =
      actions
      |> List.map (fun (action : declarative_action) -> action.effect_kind)
      |> List.sort_uniq compare;
    command_ids =
      List.map (fun (action : declarative_action) -> action.command_id) actions;
    actions }

let task7a_operation_activity operation =
  let operation_key = (Jj_operation.declaration operation).key in
  let stable_id = "activity.jj." ^ operation_key in
  let before =
    task7a_action ~activity_id:stable_id ~ordinal:1 ~dependency_ids:[]
      ~effect_kind:Jujutsu_observation
      ~work:(Jujutsu_work { operation; role = Observe_before })
  in
  let execute =
    task7a_action ~activity_id:stable_id ~ordinal:2
      ~dependency_ids:[ before.stable_id ]
      ~effect_kind:(effect_kind_of_jujutsu_operation operation)
      ~work:(Jujutsu_work { operation; role = Execute })
  in
  let after =
    task7a_action ~activity_id:stable_id ~ordinal:3
      ~dependency_ids:[ execute.stable_id ] ~effect_kind:Jujutsu_observation
      ~work:(Jujutsu_work { operation; role = Observe_after })
  in
  task7a_activity ~stable_id
    ~intent:("Declare standalone Jujutsu operation " ^ operation_key)
    [ before; execute; after ]

let ordered_task7a_actions ~activity_id ~effect_kind works =
  let _, reversed =
    List.fold_left
      (fun (predecessor, actions) (ordinal, work) ->
        let dependency_ids =
          match predecessor with None -> [] | Some action_id -> [ action_id ]
        in
        let action =
          task7a_action ~activity_id ~ordinal ~dependency_ids ~effect_kind ~work
        in
        (Some action.stable_id, action :: actions))
      (None, []) (List.mapi (fun index work -> (index + 1, work)) works)
  in
  List.rev reversed

let task7a_candidate_activity =
  let stable_id = "activity.jj.candidate-verification" in
  let actions =
    Jj_action_kind.candidate_steps
    |> List.map (fun step -> Candidate_verification_work step)
    |> ordered_task7a_actions ~activity_id:stable_id
         ~effect_kind:Candidate_tree_verification
  in
  task7a_activity ~stable_id
    ~intent:"Declare exact ordered candidate verification steps" actions

type static_template_class =
  | Standalone_operation_template
  | Standalone_phase_template
  | Conditional_family_template
  | Candidate_verification_template

type static_template = {
  template_stable_id : string;
  template_class : static_template_class;
  template_schema_digest : string;
}

let digest_framed fields =
  fields |> String.concat "\000" |> Digestif.SHA256.digest_string
  |> Digestif.SHA256.to_hex

let static_template template_stable_id template_class schema_fields =
  { template_stable_id; template_class;
    template_schema_digest = digest_framed schema_fields }

let task7a_operation_templates =
  List.map
    (fun operation ->
      let operation_key = (Jj_operation.declaration operation).key in
      static_template ("template.jj.operation." ^ operation_key)
        Standalone_operation_template
        [ "standalone-operation-template-v1"; operation_key;
          Jj_operation.digest_of [ operation ] ])
    Jj_operation.all

let task7a_phase_templates =
  List.map
    (fun phase_kind ->
      let phase_id = Jj_campaign_action.standalone_phase_kind_id phase_kind in
      static_template ("template.jj.phase." ^ phase_id)
        Standalone_phase_template
        [ "standalone-phase-template-v1"; phase_id;
          Jj_campaign_action.standalone_phase_denominator_digest;
          Jj_campaign_action.source_digest ])
    Jj_campaign_action.standalone_phase_kinds

let task7a_conditional_templates =
  List.map
    (fun family_id ->
      static_template ("template.jj.conditional." ^ family_id)
        Conditional_family_template
        [ "conditional-family-template-v1"; family_id;
          Jj_campaign_action.source_digest ])
    [ "b-campaign"; "completion-reconcile" ]

let task7a_candidate_template =
  static_template "template.jj.candidate-verification"
    Candidate_verification_template
    [ "candidate-verification-template-v1";
      Jj_id.length_frame
        (List.map Jj_action_kind.candidate_step_key
           Jj_action_kind.candidate_steps);
      Jj_action_kind.source_digest ]

let task7a_static_templates =
  task7a_operation_templates @ task7a_phase_templates
  @ task7a_conditional_templates @ [ task7a_candidate_template ]

let task7a_static_template_digest_of templates =
  templates
  |> List.concat_map (fun template ->
       [ template.template_stable_id; template.template_schema_digest ])
  |> digest_framed

let task7a_static_template_digest =
  task7a_static_template_digest_of task7a_static_templates

let task7a_declaration_activities =
  List.map task7a_operation_activity Jj_operation.all
  @ [ task7a_candidate_activity ]

let expected_static_template_count = 34 + 10 + 2 + 1
let constructible_static_template_count =
  List.length task7a_static_templates

let task7a_declaration_gaps () =
  let gaps = ref [] in
  let add message = gaps := message :: !gaps in
  let unique_text values =
    List.length values = List.length (List.sort_uniq String.compare values)
  in
  let activity_ids =
    List.map
      (fun (activity : declarative_activity) -> activity.stable_id)
      task7a_declaration_activities
  in
  if List.length Jj_operation.all <> 34 then
    add "standalone Jujutsu operation denominator is not 34";
  if List.length task7a_declaration_activities <> List.length Jj_operation.all + 1
  then add "operation/candidate declaration denominator differs";
  if constructible_static_template_count <> expected_static_template_count then
    add "constructible static template denominator differs";
  let template_ids =
    List.map
      (fun (template : static_template) -> template.template_stable_id)
      task7a_static_templates
  in
  if not (unique_text template_ids) then add "Task-7A static template ids duplicate";
  if List.length task7a_phase_templates
     <> Jj_campaign_action.standalone_phase_count
  then add "standalone phase template denominator differs";
  if List.length task7a_conditional_templates <> 2 then
    add "conditional family template denominator differs";
  if List.length task7a_action_work_class_ids <> 16
     || not (unique_text task7a_action_work_class_ids)
  then add "Task-7A action-work class denominator differs";
  if task7a_completion_receipt_work_ids
     <> [ action_work_id
            (Completion_receipt_work
               Jj_action_kind.Reserve_completion_receipt);
          action_work_id
            (Completion_receipt_work
               Jj_action_kind.Finalize_completion_receipt) ]
  then add "completion receipt work denominator or order differs";
  if not (unique_text activity_ids) then add "Task-7A activity ids duplicate";
  let action_ids =
    task7a_declaration_activities
    |> List.concat_map (fun (activity : declarative_activity) ->
           List.map (fun (action : declarative_action) -> action.stable_id)
             activity.actions)
  in
  if not (unique_text action_ids) then add "Task-7A action ids duplicate";
  let expected_operation_ids =
    List.map
      (fun operation -> "activity.jj." ^ (Jj_operation.declaration operation).key)
      Jj_operation.all
  in
  let observed_operation_ids =
    activity_ids
    |> List.filter (fun id -> id <> task7a_candidate_activity.stable_id)
  in
  if observed_operation_ids <> expected_operation_ids then
    add "standalone Jujutsu operation activity denominator differs";
  List.iter2
    (fun operation activity ->
      match activity.actions with
      | [ before; execute; after ] ->
          begin
            match before.work, execute.work, after.work with
            | Jujutsu_work { operation = before_operation; role = Observe_before },
              Jujutsu_work { operation = execute_operation; role = Execute },
              Jujutsu_work { operation = after_operation; role = Observe_after }
              when before_operation = operation
                   && execute_operation = operation
                   && after_operation = operation -> ()
            | _ -> add (activity.stable_id ^ " operation role projection differs")
          end
      | _ -> add (activity.stable_id ^ " operation action denominator differs"))
    Jj_operation.all
    (List.filter
       (fun (activity : declarative_activity) ->
         activity.stable_id <> task7a_candidate_activity.stable_id)
       task7a_declaration_activities);
  let candidate_steps =
    task7a_candidate_activity.actions
    |> List.filter_map (fun (action : declarative_action) ->
           match action.work with
           | Candidate_verification_work step -> Some step
           | _ -> None)
  in
  if candidate_steps <> Jj_action_kind.candidate_steps then
    add "candidate verification five-step order differs";
  List.iter
    (fun (activity : declarative_activity) ->
      if activity.bridge_component_id <> task7a_bridge_unavailable
         || activity.target_component_id <> task7a_target_unavailable
      then add (activity.stable_id ^ " escapes unavailable lower posture");
      if activity.actions = [] then add (activity.stable_id ^ " has no actions");
      List.iter
        (fun (action : declarative_action) ->
          if action.target_component_id = task7a_target_unavailable then
            add (action.stable_id ^ " has no distinct unavailable target class");
          List.iter (fun gap -> add (action.stable_id ^ ": " ^ gap))
            (action_work_gaps action.work))
        activity.actions)
    task7a_declaration_activities;
  let admitted_ids =
    List.map (fun (activity : declarative_activity) -> activity.stable_id) activities
  in
  if List.exists (fun id -> List.mem id admitted_ids) activity_ids then
    add "Task-7A declaration entered the admitted activity registry";
  List.rev !gaps

type conditional_projection_prerequisite =
  | Public_ten_phase_enum
  | Occurrence_phase_ordinal_accessor
  | Conditional_node_identity_accessor
  | Conditional_guard_control_ids
  | Conditional_edge_label_accessor
  | Readback_completion_work_carriers
  | Multi_target_activity_schema
  | Conditional_activity_schema
  | Failure_recovery_policy_schema
  | Plan_dispatch_identity_schema

type conditional_projection_error =
  | Unsupported_campaign_auxiliary_role of Jj_action_kind.auxiliary_role

let conditional_projection_error_code = function
  | Unsupported_campaign_auxiliary_role role ->
      "unsupported-campaign-auxiliary-role:"
      ^ Jj_action_kind.auxiliary_role_key role

let conditional_projection_prerequisite_status _ = Ok ()

let conditional_projection_prerequisites =
  [ Public_ten_phase_enum; Occurrence_phase_ordinal_accessor;
    Conditional_node_identity_accessor; Conditional_guard_control_ids;
    Conditional_edge_label_accessor; Readback_completion_work_carriers;
    Multi_target_activity_schema; Conditional_activity_schema;
    Failure_recovery_policy_schema; Plan_dispatch_identity_schema ]

type conditional_control_projection = {
  control_node_id : string;
  control_node_kind : Jj_campaign_action.node_kind;
  control_guard_identity : string;
  control_parent_occurrence_id : string option;
  control_parent_ordinal : int option;
  control_decision_id : string option;
  control_prefix_id : string option;
  control_branch_ids : string list;
}

type conditional_edge_projection = {
  projected_edge_source_id : string;
  projected_edge_target_id : string;
  projected_edge_label : string;
  projected_edge_guard_identity : string;
}

type conditional_activity_projection = {
  projection_family : string;
  projection_activity : string;
  projection_plan : string;
  projection_dispatch : string;
  projection_external : declarative_action list;
  projection_controls : conditional_control_projection list;
  projection_edges : conditional_edge_projection list;
  projection_failure_policy : string;
  projection_recovery_edges : string list;
}

let work_and_effect_of_campaign_action (action : Jj_action_kind.t) =
  match action with
  | Jj_action_kind.Jujutsu_operation operation ->
      Ok
        (Jujutsu_work { operation; role = Execute },
         effect_kind_of_jujutsu_operation operation)
  | Auxiliary Acquire_clock ->
      Ok (Clock_work Acquire_clock, External_resource_observation)
  | Auxiliary Observe_external_resource ->
      Ok
        (External_resource_work Observe_external_resource,
         External_resource_observation)
  | Auxiliary (Observe_repository_source as role)
  | Auxiliary (Observe_release_bundle as role) ->
      Ok (Repository_source_work role, Repository_source_observation)
  | Auxiliary Consume_approval_nonce ->
      Ok (Approval_nonce_work Consume_approval_nonce, Approval_nonce_consumption)
  | Auxiliary (Acquire_writer_lease as role)
  | Auxiliary (Renew_writer_lease as role)
  | Auxiliary (Release_writer_lease as role) ->
      Ok (Writer_lease_work role, Writer_lease_transition)
  | Auxiliary (Observe_tree as role)
  | Auxiliary (Observe_object as role) ->
      Ok (Filesystem_work role, External_resource_observation)
  | Auxiliary (Acquire_network_scope as role)
  | Auxiliary (Release_network_scope as role) ->
      Ok (Network_scope_work role, Network_scope_transition)
  | Auxiliary (Acquire_credential_lease as role)
  | Auxiliary (Release_credential_lease as role) ->
      Ok (Credential_lease_work role, Credential_lease_transition)
  | Auxiliary
      ((Materialize_candidate | Write_partition | Restore_partition
       | Restore_sealed_record_preimage | Write_sealed_record_candidate
       | Remove_disposable_scope | Stage_recovery_set | Reconcile_recovery_set
       | Cleanup_recovery_set) as role) ->
      Ok (Materialization_work role, Controlled_filesystem_materialization)
  | Auxiliary Readback_jj_state ->
      Ok (Jujutsu_readback_work Readback_jj_state, Jujutsu_observation)
  | Auxiliary
      ((Reserve_completion_receipt | Finalize_completion_receipt) as role) ->
      Ok (Completion_receipt_work role, Durable_artifact_publication)
  | Auxiliary
      ((Verify_candidate_tree | Execute_jj_process | Execute_formal_oracle)
       as role) ->
      Error (Unsupported_campaign_auxiliary_role role)
  | Candidate_process step ->
      Ok (Candidate_verification_work step, Candidate_tree_verification)
  | Formal_process process ->
      Ok (Formal_oracle_work process, Formal_oracle_execution)
  | Frontier_action Activate_source_recovery_branch ->
      Ok
        (Activation_transition_work Activate_source_recovery_branch,
         Production_activation_transition)
  | Frontier_action
      (Set_activity_frontier Reconciled_terminal as frontier) ->
      Ok (Mutation_frontier_work frontier, Jujutsu_local_mutation)

let campaign_action ~dependencies
    (descriptor : Jj_campaign_action.occurrence_descriptor) =
  match work_and_effect_of_campaign_action descriptor.occurrence_action_identity with
  | Error _ as error -> error
  | Ok (work, effect_kind) ->
      Ok
        { stable_id = descriptor.stable_occurrence_id;
          command_id = "command." ^ descriptor.stable_occurrence_id;
          assigned_agent_id = "task8-agent-unavailable";
          dependency_ids = dependencies;
          selector_id = "task8-selector-unavailable";
          required_capability_id = "task8-capability-unavailable";
          context_requirement_ids =
            [ "phase:" ^ descriptor.occurrence_phase_id;
              "ordinal:" ^ string_of_int descriptor.occurrence_phase_ordinal ];
          target_component_id = task7a_target_of_work work;
          effect_kind;
          preparation_id = "preparation." ^ descriptor.stable_nonce_id;
          work }

let campaign_approval_consume ~dependencies consume =
  let role = Jj_campaign_action.approval_consume_action consume in
  let work = Approval_nonce_work role in
  let stable_id = Jj_campaign_action.approval_consume_id consume in
  { stable_id;
    command_id = "command." ^ stable_id;
    assigned_agent_id = "task8-agent-unavailable";
    dependency_ids = dependencies;
    selector_id = "task8-selector-unavailable";
    required_capability_id = "task8-capability-unavailable";
    context_requirement_ids =
      [ "parent-occurrence:"
        ^ Jj_campaign_action.approval_consume_parent_occurrence_id consume;
        "parent-ordinal:"
        ^ string_of_int
            (Jj_campaign_action.approval_consume_parent_ordinal consume) ];
    target_component_id = task7a_target_of_work work;
    effect_kind = Approval_nonce_consumption;
    preparation_id = "preparation." ^ stable_id;
    work }

let project_linear_occurrences ~approval_consumptions occurrences =
  let rec loop predecessor reversed = function
    | [] -> Ok (List.rev reversed)
    | occurrence :: rest ->
        let dependencies =
          match predecessor with None -> [] | Some stable_id -> [ stable_id ]
        in
        let descriptor = Jj_campaign_action.occurrence_descriptor occurrence in
        let consume =
          List.find_opt
            (fun consume ->
              String.equal
                (Jj_campaign_action.approval_consume_parent_occurrence_id
                   consume)
                descriptor.stable_occurrence_id)
            approval_consumptions
        in
        begin match consume with
        | None ->
            (match campaign_action ~dependencies descriptor with
             | Error _ as error -> error
             | Ok action ->
                 loop (Some action.stable_id) (action :: reversed) rest)
        | Some consume ->
            let consume_action =
              campaign_approval_consume ~dependencies consume
            in
            (match
               campaign_action ~dependencies:[ consume_action.stable_id ]
                 descriptor
             with
             | Error _ as error -> error
             | Ok action ->
                 loop (Some action.stable_id)
                   (action :: consume_action :: reversed) rest)
        end
  in
  loop None [] occurrences

let standalone_phase_activity request =
  let phase_kind = Jj_campaign_action.standalone_phase_kind request in
  let phase_id = Jj_campaign_action.standalone_phase_kind_id phase_kind in
  let plan_digest = Jj_campaign_action.standalone_projection_digest request in
  match
    Jj_campaign_action.standalone_phase_declarations request
    |> project_linear_occurrences
         ~approval_consumptions:
           (Jj_campaign_action.standalone_approval_consumptions request)
  with
  | Error _ as error -> error
  | Ok actions ->
      Ok
        (task7a_activity
           ~stable_id:("activity.jj.phase." ^ phase_id ^ "." ^ plan_digest)
           ~intent:("Project request-bound Jujutsu phase " ^ phase_id)
           actions)

let control_projection_of_node node =
  match Jj_campaign_action.conditional_node_descriptor node with
  | Jj_campaign_action.Consume_descriptor value ->
      Some
        { control_node_id = value.node_id;
          control_node_kind = Consume_node_kind;
          control_guard_identity =
            Jj_campaign_action.guard_descriptor_identity value.guard;
          control_parent_occurrence_id = Some value.parent_occurrence_id;
          control_parent_ordinal = Some value.parent_occurrence_ordinal;
          control_decision_id = None;
          control_prefix_id = None;
          control_branch_ids = [] }
  | Jj_campaign_action.Decision_descriptor value ->
      Some
        { control_node_id = value.node_id;
          control_node_kind = Decision_node_kind;
          control_guard_identity =
            Jj_campaign_action.guard_descriptor_identity value.guard;
          control_parent_occurrence_id = None;
          control_parent_ordinal = None;
          control_decision_id = Some value.control_id;
          control_prefix_id = Some value.prefix_id;
          control_branch_ids = value.branch_ids }
  | Jj_campaign_action.Action_descriptor _ -> None

let edge_projection edge =
  let descriptor = Jj_campaign_action.conditional_edge_descriptor edge in
  { projected_edge_source_id = descriptor.edge_source_id;
    projected_edge_target_id = descriptor.edge_target_id;
    projected_edge_label = descriptor.edge_label;
    projected_edge_guard_identity = descriptor.edge_guard_identity }

let project_conditional family_id plan =
  let nodes = Jj_campaign_action.conditional_nodes plan in
  let edges = Jj_campaign_action.guarded_edges plan in
  let dependencies target_id =
    edges
    |> List.filter_map (fun edge ->
         let descriptor = Jj_campaign_action.conditional_edge_descriptor edge in
         if String.equal descriptor.edge_target_id target_id then
           Some descriptor.edge_source_id
         else None)
  in
  let rec project_external reversed = function
    | [] -> Ok (List.rev reversed)
    | node :: rest ->
        begin match Jj_campaign_action.conditional_node_descriptor node with
        | Jj_campaign_action.Action_descriptor value ->
            begin match
              campaign_action
                ~dependencies:(dependencies value.node_id) value.occurrence
            with
            | Error _ as error -> error
            | Ok action -> project_external (action :: reversed) rest
            end
        | Jj_campaign_action.Consume_descriptor _
        | Jj_campaign_action.Decision_descriptor _ ->
            project_external reversed rest
        end
  in
  match project_external [] nodes with
  | Error _ as error -> error
  | Ok actions ->
      let plan_digest = Jj_campaign_action.conditional_projection_digest plan in
      let dispatch =
        digest_framed [ "conditional-dispatch-v1"; family_id; plan_digest ]
      in
      let projected_edges = List.map edge_projection edges in
      Ok
        { projection_family = family_id;
          projection_activity =
            "activity.jj.conditional." ^ family_id ^ "." ^ plan_digest;
          projection_plan = plan_digest;
          projection_dispatch = dispatch;
          projection_external = actions;
          projection_controls = List.filter_map control_projection_of_node nodes;
          projection_edges = projected_edges;
          projection_failure_policy = "closed-guarded-terminal-accounting";
          projection_recovery_edges =
            projected_edges
            |> List.filter_map (fun edge ->
                 if String.starts_with ~prefix:"branch:"
                      edge.projected_edge_label
                 then Some edge.projected_edge_label else None)
            |> List.sort_uniq String.compare }

let b_success_activity plan = project_conditional "b-campaign" plan
let completion_reconcile_activity plan =
  project_conditional "completion-reconcile" plan

let conditional_projection_family_id projection = projection.projection_family
let conditional_projection_activity_id projection = projection.projection_activity
let conditional_projection_plan_digest projection = projection.projection_plan
let conditional_projection_dispatch_key projection = projection.projection_dispatch
let conditional_projection_external_actions projection = projection.projection_external
let conditional_projection_internal_controls projection = projection.projection_controls
let conditional_projection_edges projection = projection.projection_edges
let conditional_projection_posture = `Implemented

let json_fields_of_action_work = function
  | Topology_gate -> [ ("workKind", `String "topology-gate") ]
  | Repository_build { profile; build_command } ->
      [ ("workKind", `String "repository-build");
        ("profileId", `String (string_of_verification_profile profile));
        ("buildCommand", `String build_command) ]
  | Repository_verification_suite { profile; suite_id; executable } ->
      [ ("workKind", `String "repository-verification-suite");
        ("profileId", `String (string_of_verification_profile profile));
        ("suiteId", `String suite_id);
        ("executable", `String executable) ]
  | work ->
      [ ("workKind", `String "closed-task7a-work");
        ("workId", `String (action_work_id work)) ]

let json_of_action (item : declarative_action) =
  `Assoc
    ([ ("assignedAgentId", `String item.assigned_agent_id);
      ("commandId", `String item.command_id);
      ("contextRequirementIds", `List
         (List.map (fun id -> `String id) item.context_requirement_ids));
      ("dependencyIds", `List
         (List.map (fun id -> `String id) item.dependency_ids));
      ("effectKind", `String (string_of_effect_kind item.effect_kind));
      ("preparationId", `String item.preparation_id);
      ("requiredCapabilityId", `String item.required_capability_id);
      ("selectorId", `String item.selector_id);
      ("stableId", `String item.stable_id);
      ("targetComponentId", `String item.target_component_id) ]
     @ json_fields_of_action_work item.work)

let json_of_activity (item : declarative_activity) =
  `Assoc
    [ ("actions", `List (List.map json_of_action item.actions));
      ("bridgeComponentId", `String item.bridge_component_id);
      ("commandIds", `List
         (List.map (fun command -> `String command) item.command_ids));
      ("constraints", `List
         (List.map (fun constraint_ -> `String constraint_) item.constraints));
      ("contextRequirementIds", `List
         (List.map (fun id -> `String id) item.context_requirement_ids));
      ("effectKinds", `List
         (List.map
            (fun kind -> `String (string_of_effect_kind kind))
            item.effect_kinds));
      ("intent", `String item.intent);
      ("miqRoutes", `List (List.map json_of_miq_route item.miq_routes));
      ("requiredCapabilityIds", `List
         (List.map (fun id -> `String id) item.required_capability_ids));
      ("stableId", `String item.stable_id);
      ("successCriteria", `List
         (List.map (fun criterion -> `String criterion)
            item.success_criteria));
      ("targetComponentId", `String item.target_component_id);
      ("targetState", `String item.target_state) ]

let task7a_declaration_digest_of
    ?(templates = task7a_static_templates)
    ?(work_class_ids = task7a_action_work_class_ids)
    ?(completion_work_ids = task7a_completion_receipt_work_ids)
    ?(conditional_control_schema = "external-actions-and-internal-controls")
    declarations =
  let prerequisite_codes =
    List.map
      (fun prerequisite ->
        match conditional_projection_prerequisite_status prerequisite with
        | Error error -> conditional_projection_error_code error
        | Ok () -> "available")
      conditional_projection_prerequisites
  in
  `Assoc
    [ ("constructibleDeclarations",
       `List (List.map json_of_activity declarations));
      ("expectedStaticTemplateCount", `Int expected_static_template_count);
      ("constructibleStaticTemplateCount",
       `Int constructible_static_template_count);
      ("staticTemplates",
       `List
         (List.map
            (fun template ->
              `List
                [ `String template.template_stable_id;
                  `String template.template_schema_digest ])
            templates));
      ("staticTemplateDigest",
       `String (task7a_static_template_digest_of templates));
      ("actionWorkClassIds",
       `List (List.map (fun class_id -> `String class_id) work_class_ids));
      ("completionReceiptWorkIds",
       `List (List.map (fun work_id -> `String work_id) completion_work_ids));
      ("conditionalControlSchema", `String conditional_control_schema);
      ("campaignDescriptorSourceDigest",
       `String Jj_campaign_action.source_digest);
      ("unavailablePrerequisites",
       `List (List.map (fun code -> `String code) prerequisite_codes));
      ("liveExecutionPosture", `String "implemented-unavailable") ]
  |> Yojson.Safe.to_string |> Digestif.SHA256.digest_string
  |> Digestif.SHA256.to_hex

let task7a_declaration_digest =
  task7a_declaration_digest_of task7a_declaration_activities

let json_of_authority (value : authority) =
  `Assoc
    [ ("components", `List (List.map (fun (item : component) -> `Assoc
         [ ("purpose", `String item.purpose); ("stableId", `String item.stable_id) ])
         value.components));
      ("ports", `List (List.map (fun (item : port) -> `Assoc
         [ ("componentId", `String item.component_id); ("count", `Int item.count);
           ("direction", `String (string_of_direction item.direction));
           ("kind", `String (string_of_port_kind item.kind));
           ("name", `String item.name); ("stableId", `String item.stable_id) ]) value.ports));
      ("channels", `List (List.map (fun (item : channel) -> `Assoc
         [ ("componentId", `String item.component_id); ("fppName", `String item.fpp_name);
           ("metricId", match item.metric_id with None -> `Null | Some id -> `String id);
           ("stableId", `String item.stable_id) ]) value.channels));
      ("edges", `List (List.map (fun (item : edge) -> `Assoc
         [ ("fromComponent", `String item.from_component);
           ("fromPort", `String item.from_port); ("kind", `String (string_of_edge_kind item.kind));
           ("stableId", `String item.stable_id); ("toComponent", `String item.to_component);
           ("toPort", `String item.to_port) ]) value.edges));
      ("verifiers", `List (List.map (fun (item : verifier) -> `Assoc
         [ ("kind", `String (string_of_verifier_kind item.kind));
           ("stableId", `String item.stable_id) ]) value.verifiers));
      ("lifecycleMachines", `List
         (List.map (fun (item : lifecycle_machine) -> `Assoc
            [ ("componentId", `String item.component_id);
              ("initialState", `String item.initial_state);
              ("instanceId", `String item.instance_id);
              ("stableId", `String item.stable_id);
              ("states", `List
                 (List.map (fun (state : lifecycle_state) -> `Assoc
                    [ ("stableId", `String state.stable_id);
                      ("transitions", `List
                         (List.map (fun (transition : lifecycle_transition) -> `Assoc
                            [ ("actions", `List
                                 (List.map (fun action -> `String action)
                                    transition.actions));
                              ("signal", `String transition.signal);
                              ("targetState", `String transition.target_state) ])
                            state.transitions)) ]) item.states)) ])
            value.lifecycle_machines));
      ("faultEvents", `List
         (List.map (fun (item : fault_event) -> `Assoc
            [ ("componentId", `String item.component_id);
              ("format", `String item.format);
              ("severity", `String (string_of_fault_severity item.severity));
              ("stableId", `String item.stable_id) ]) value.fault_events));
      ("gateCommands", `List
         (List.map (fun (item : gate_command) -> `Assoc
            [ ("componentId", `String item.component_id);
              ("intentId", `String item.intent_id);
              ("kind", `String (string_of_gate_kind item.kind));
              ("stableId", `String item.stable_id) ]) value.gate_commands));
      ("activities", `List
         (List.map json_of_activity value.activities));
      ("requirements", `List (List.map (fun (item : requirement) -> `Assoc
         [ ("coveredElements", `List (List.map (fun id -> `String id) item.covered_elements));
           ("source", `String item.source); ("stableId", `String item.stable_id);
           ("statement", `String item.statement); ("verifierId", `String item.verifier_id) ])
         value.requirements));
      ("formalPolicy", `Assoc
         [ ("execution", `Assoc
              [ ("bridgeComponentId", `String
                   value.formal_policy.execution.bridge_component_id);
                ("requiredExecutionEdgeId", `String
                   value.formal_policy.execution.required_execution_edge_id);
                ("supervisorComponentId", `String
                   value.formal_policy.execution.supervisor_component_id);
                ("workerComponentId", `String
                   value.formal_policy.execution.worker_component_id) ]);
           ("uiIsolation", `Assoc
              [ ("admissionComponentIds", `List
                   (List.map (fun id -> `String id)
                      value.formal_policy.ui_isolation.admission_component_ids));
                ("uiComponentIds", `List
                   (List.map (fun id -> `String id)
                      value.formal_policy.ui_isolation.ui_component_ids)) ]);
           ("modelContract", `Assoc
              [ ("fppBaseId", `Int value.formal_policy.model_contract.fpp_base_id);
                ("fppModelName", `String
                   value.formal_policy.model_contract.fpp_model_name);
                ("fppTopologyName", `String
                   value.formal_policy.model_contract.fpp_topology_name);
                ("projectionSurfaceIds", `List
                   (List.map (fun id -> `String id)
                      value.formal_policy.model_contract.projection_surface_ids)) ]);
           ("sqlite", `Assoc
              [ ("activityId", `String value.formal_policy.sqlite.activity_id);
                ("faultEventIds", `List
                   (List.map (fun id -> `String id)
                      value.formal_policy.sqlite.fault_event_ids));
                ("gateCommandIds", `List
                   (List.map (fun id -> `String id)
                      value.formal_policy.sqlite.gate_command_ids));
                ("hazardRequirementId", `String
                   value.formal_policy.sqlite.hazard_requirement_id);
                ("machineStateIds", `List
                   (List.map
                      (fun (machine_id, state_ids) -> `Assoc
                         [ ("machineId", `String machine_id);
                           ("stateIds", `List
                              (List.map (fun id -> `String id) state_ids)) ])
                      value.formal_policy.sqlite.machine_state_ids));
                ("requiredTransitions", `List
                   (List.map
                      (fun (item : sqlite_transition_policy) -> `Assoc
                         [ ("machineId", `String item.machine_id);
                           ("requiredActionIds", `List
                              (List.map (fun id -> `String id)
                                 item.required_action_ids));
                           ("signalId", `String item.signal_id);
                           ("sourceStateId", `String item.source_state_id);
                           ("targetStateId", `String item.target_state_id) ])
                      value.formal_policy.sqlite.required_transitions)) ]) ]) ]

let source_digest_of value =
  `Assoc
    [ ("authority", json_of_authority value);
      ("task7aDeclarationDigest", `String task7a_declaration_digest) ]
  |> Yojson.Safe.to_string
  |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex

let source_digest = source_digest_of authority

let activity_digest_of activity =
  activity |> json_of_activity |> Yojson.Safe.to_string
  |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex

let action_digest_of action =
  action |> json_of_action |> Yojson.Safe.to_string
  |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex

let admitted_activity_digest value = value.activity_digest
let admitted_activity_authority_digest value = value.authority_digest
let admitted_declaration value = value.declaration
let admitted_actions value = value.declaration.actions
let declarative_activity_actions value = value.actions

let fpp_type_of_channel (item : channel) =
  match item.metric_id with
  | None -> Prim (String (Some 64))
  | Some metric_id ->
      begin match Run_metrics.find metric_id with
      | None -> Prim U64
      | Some declaration ->
          match declaration.unit_ with
          | Run_metrics.Seconds | Ratio | Words -> Prim F64
          | State_unit -> Prim (String (Some 128))
          | Count | Nanoseconds | Bytes -> Prim U64
      end

let fpp_severity = function
  | Fault_diagnostic -> Diagnostic
  | Fault_warning -> Warning_hi
  | Fault_fatal -> Fatal

let fpp_machine (machine : lifecycle_machine) =
  let signals =
    machine.states
    |> List.concat_map (fun (state : lifecycle_state) -> state.transitions)
    |> List.map (fun (transition : lifecycle_transition) -> transition.signal)
    |> List.sort_uniq String.compare
    |> List.map (fun signal_name -> { signal_name; signal_type = None })
  in
  let actions =
    machine.states
    |> List.concat_map (fun (state : lifecycle_state) -> state.transitions)
    |> List.concat_map (fun (transition : lifecycle_transition) -> transition.actions)
    |> List.sort_uniq String.compare
  in
  Internal_machine
    { machine_name = machine.stable_id; signals; guards = []; actions;
      states =
        List.map
          (fun (state : lifecycle_state) ->
            { state_name = state.stable_id; entry = []; exit_ = [];
              transitions =
                List.map
                  (fun (transition : lifecycle_transition) ->
                    { on_signal = transition.signal; guard = None;
                      do_actions = transition.actions;
                      target = To_state transition.target_state })
                  state.transitions })
          machine.states;
      choices = []; initial = ([], machine.initial_state) }

let fpp_component (value : authority) (component : component) =
  let component_machines =
    List.filter
      (fun (item : lifecycle_machine) -> item.component_id = component.stable_id)
      value.lifecycle_machines
  in
  let component_commands =
    List.filter
      (fun (item : gate_command) -> item.component_id = component.stable_id)
      value.gate_commands
  in
  let component_events =
    List.filter
      (fun (item : fault_event) -> item.component_id = component.stable_id)
      value.fault_events
  in
  let component_debug_intents =
    List.filter
      (fun (item : Debug_intent.t) ->
        String.equal item.fpp.component component.stable_id)
      Debug_intent.all
  in
  let fpp_ports =
    value.ports
    |> List.filter (fun (item : port) ->
           String.equal item.component_id component.stable_id)
    |> List.map (fun (item : port) ->
           General { name = item.name; port = "OperationsFlow";
             direction = (match item.direction with Input -> Sync_input | Output -> Output);
             count = item.count })
  in
  let fpp_ports =
    fpp_ports
    @ if component_commands = [] && component_events = [] then []
      else [ Special Command_recv; Special Command_reg; Special Command_resp;
        Special Event_p; Special Telemetry_p ]
  in
  let fpp_channels =
    value.channels
    |> List.filter (fun (item : channel) ->
           String.equal item.component_id component.stable_id)
    |> List.mapi (fun chan_id (item : channel) ->
           { chan_name = item.fpp_name; chan_id; chan_type = fpp_type_of_channel item;
             update = On_change; chan_format = None; low = None; high = None })
  in
  { comp_name = component.stable_id;
    kind =
      (if
         component_machines = [] && component_commands = []
         && component_events = []
       then Passive
       else Active);
    ports = fpp_ports;
    commands =
      List.mapi
        (fun opcode (item : gate_command) ->
          { cmd_name = item.stable_id; opcode;
            cmd_kind = Async_cmd { priority = Some 20; queue_full = Block };
            cmd_params = [ ("intentId", Prim (String (Some 128))) ] })
        component_commands;
    events =
      List.mapi
        (fun event_id (item : fault_event) ->
          { event_name = item.stable_id; event_id;
            severity = fpp_severity item.severity; format = item.format;
            throttle = None })
        component_events;
    channels = fpp_channels;
    parameters =
      List.mapi
        (fun param_id (intent : Debug_intent.t) ->
          { param_name =
              "DEBUG_INTENT_"
              ^ String.map
                  (fun character ->
                    if
                      (character >= 'a' && character <= 'z')
                      || (character >= 'A' && character <= 'Z')
                      || (character >= '0' && character <= '9')
                    then Char.uppercase_ascii character
                    else '_')
                  intent.failure_family;
            param_id; param_type = Prim (String (Some 128));
            default = Some intent.stable_id;
            set_opcode = 128 + (2 * param_id);
            save_opcode = 129 + (2 * param_id); external_ = false })
        component_debug_intents;
    records = []; containers = []; internal_ports = []; machines = []; matched = [] }

let to_fpp_model (value : authority) =
  let fpp_components = List.map (fpp_component value) value.components in
  let rec instances next_base (components : Fpp_model.component list) =
    match components with
    | [] -> []
    | (component : Fpp_model.component) :: rest ->
        let active = component.kind = Active in
        let instance =
          { inst_name = component.comp_name; of_component = component.comp_name;
            base_id = next_base;
            queue_size = (if active then Some 32 else None);
            stack_size = (if active then Some 65_536 else None);
            inst_priority = (if active then Some 20 else None); cpu = None }
        in
        instance :: instances (next_base + Fpp_model.id_span component) rest
  in
  let fpp_instances =
    instances value.formal_policy.model_contract.fpp_base_id fpp_components in
  let endpoint ep_instance ep_port = { ep_instance; ep_port; ep_index = None } in
  let connections =
    List.map
      (fun (item : edge) ->
        { from_ = endpoint item.from_component item.from_port;
          to_ = endpoint item.to_component item.to_port })
      value.edges
  in
  let topology =
    { topo_name = value.formal_policy.model_contract.fpp_topology_name;
      members = List.map (fun item -> item.inst_name) fpp_instances;
      graphs = [ Direct { graph_name = "OperationsTypedFlow"; connections } ] }
  in
  let fpp_components =
    List.map
      (fun (component : Fpp_model.component) ->
        let machine_instances =
          value.lifecycle_machines
          |> List.filter (fun (item : lifecycle_machine) ->
                 item.component_id = component.comp_name)
          |> List.map (fun (item : lifecycle_machine) ->
                 (item.instance_id, item.stable_id))
        in
        { component with machines = machine_instances })
      fpp_components
  in
  { model_name = value.formal_policy.model_contract.fpp_model_name;
    type_defs = [];
    port_defs = [ { port_name = "OperationsFlow"; params = []; return_type = None } ];
    constants = []; components = fpp_components;
    machines = List.map fpp_machine value.lifecycle_machines;
    instances = fpp_instances; topologies = [ topology ] }

let model = to_fpp_model authority

let nonempty value = String.trim value <> ""
let unique values = List.length values = List.length (List.sort_uniq String.compare values)

let known_capability_ids =
  Ops_capability.all
  |> List.filter_map (fun (item : Ops_capability.declaration) ->
         match item.kind with
         | Ops_capability.Capability -> Some item.id
         | Ops_capability.Rule | Ops_capability.Skill
         | Ops_capability.Superpower | Ops_capability.Agent
         | Ops_capability.Sop | Ops_capability.Activity -> None)

let action_graph_gaps_for ?(expected = expected_actions) (value : authority)
    (activity : declarative_activity) =
  let gaps = ref [] in
  let add text = gaps := text :: !gaps in
  let actions = activity.actions in
  let action_ids =
    List.map (fun (item : declarative_action) -> item.stable_id) actions in
  let command_ids =
    List.map (fun (item : declarative_action) -> item.command_id) actions in
  let preparation_ids =
    List.map (fun (item : declarative_action) -> item.preparation_id) actions in
  if actions <> expected then
    add "activity ordered action denominator differs";
  if actions = [] then add "activity action denominator is empty";
  if not (unique action_ids) then add "activity action ids are duplicated";
  if not (unique command_ids) then add "activity action commands are duplicated";
  if not (unique preparation_ids) then
    add "activity action preparation ids are duplicated";
  if command_ids <> activity.command_ids then
    add "activity action commands do not cover the command denominator in order";
  let rec cycle_from visiting visited id =
    if List.mem id visiting then true
    else if List.mem id visited then false
    else
      match List.find_opt
          (fun (item : declarative_action) -> item.stable_id = id) actions with
      | None -> false
      | Some item ->
          List.exists
            (cycle_from (id :: visiting) (id :: visited))
            item.dependency_ids
  in
  if List.exists (cycle_from [] []) action_ids then
    add "activity action dependencies contain a cycle";
  let seen = ref [] in
  List.iter
    (fun (item : declarative_action) ->
      if not (nonempty item.stable_id) then add "activity action id is empty";
      if not (nonempty item.command_id) then add "activity action command is empty";
      if not (nonempty item.assigned_agent_id) then
        add "activity action agent is empty";
      if not (nonempty item.selector_id) then add "activity action selector is empty";
      if not (nonempty item.required_capability_id) then
        add "activity action capability is empty";
      if not (nonempty item.target_component_id) then
        add "activity action target is empty";
      if not (nonempty item.preparation_id) then
        add "activity action preparation is empty";
      List.iter
        (fun gap -> add (gap ^ ": " ^ item.stable_id))
        (action_work_gaps item.work);
      if not (List.mem item.command_id activity.command_ids) then
        add ("activity action names unknown command " ^ item.command_id);
      if not (List.mem item.assigned_agent_id
                (List.map (fun (component : component) -> component.stable_id)
                   value.components))
      then add ("activity action names unknown agent " ^ item.assigned_agent_id);
      if not (List.exists
          (fun (route : miq_route) ->
            route.selector_id = item.selector_id
            && route.required_capability_id = item.required_capability_id
            && route.assigned_agent_id = item.assigned_agent_id)
          activity.miq_routes)
      then add ("activity action MIQ route differs: " ^ item.stable_id);
      if not (List.mem item.required_capability_id
                activity.required_capability_ids)
      then add ("activity action capability is unavailable: " ^ item.stable_id);
      if item.context_requirement_ids <> activity.context_requirement_ids then
        add ("activity action context coverage differs: " ^ item.stable_id);
      if not (unique item.context_requirement_ids) then
        add ("activity action context coverage is duplicated: " ^ item.stable_id);
      if item.target_component_id <> activity.target_component_id then
        add ("activity action target differs: " ^ item.stable_id);
      if not (List.mem item.effect_kind activity.effect_kinds) then
        add ("activity action effect is unavailable: " ^ item.stable_id);
      if List.mem item.stable_id item.dependency_ids then
        add ("activity action depends on itself: " ^ item.stable_id);
      if not (unique item.dependency_ids) then
        add ("activity action dependencies are duplicated: " ^ item.stable_id);
      List.iter
        (fun dependency_id ->
          if not (List.mem dependency_id action_ids) then
            add ("activity action names unknown dependency " ^ dependency_id)
          else if not (List.mem dependency_id !seen) then
            add ("activity action dependency is not earlier in order: "
                 ^ dependency_id))
        item.dependency_ids;
      seen := item.stable_id :: !seen)
    actions;
  let observed_effects =
    List.map (fun (item : declarative_action) -> item.effect_kind) actions
    |> List.sort_uniq compare in
  if observed_effects <> List.sort_uniq compare activity.effect_kinds then
    add "activity actions do not cover the effect denominator";
  List.rev !gaps

let activity_envelope_gaps_for (value : authority)
    (activity : declarative_activity) =
  let gaps = ref [] in
  let add text = gaps := text :: !gaps in
  let exact label expected observed =
    if observed <> expected then add (label ^ " denominator differs")
  in
  let expected =
    match activity.stable_id with
    | "activity.verify-sqlite-dependability" -> Some sqlite_activity
    | "activity.verify-repository" -> Some repository_activity
    | _ -> None
  in
  begin match expected with
  | None -> add "activity stable id differs from the closed registry"
  | Some expected ->
      exact "activity bridge id" expected.bridge_component_id
        activity.bridge_component_id;
      exact "activity target id" expected.target_component_id
        activity.target_component_id;
      exact "activity target state" expected.target_state activity.target_state;
      exact "activity intent" expected.intent activity.intent;
      exact "activity constraint" expected.constraints activity.constraints;
      exact "activity success criterion" expected.success_criteria
        activity.success_criteria;
      exact "activity capability" expected.required_capability_ids
        activity.required_capability_ids;
      exact "activity context requirement" expected.context_requirement_ids
        activity.context_requirement_ids;
      exact "activity MIQ route" expected.miq_routes activity.miq_routes;
      exact "activity effect kind" expected.effect_kinds activity.effect_kinds;
      exact "activity command" expected.command_ids activity.command_ids;
      List.iter add
        (action_graph_gaps_for ~expected:expected.actions value activity)
  end;
  if not (nonempty activity.intent) then add "activity intent is empty";
  if activity.constraints = [] then add "activity constraints are empty";
  if activity.success_criteria = [] then
    add "activity success criteria are empty";
  if activity.required_capability_ids = []
     || not (unique activity.required_capability_ids)
  then add "activity capability ids are empty or duplicated";
  List.iter
    (fun capability_id ->
      if not (List.mem capability_id known_capability_ids) then
        add ("activity names unknown capability " ^ capability_id))
    activity.required_capability_ids;
  if activity.context_requirement_ids = []
     || not (unique activity.context_requirement_ids)
  then add "activity context requirement ids are empty or duplicated";
  List.iter
    (fun context_id ->
      if not (List.mem context_id context_requirement_ids) then
        add ("activity names unknown context requirement " ^ context_id))
    activity.context_requirement_ids;
  let selectors =
    List.map (fun (route : miq_route) -> route.selector_id)
      activity.miq_routes in
  if activity.miq_routes = [] || not (unique selectors) then
    add "activity MIQ selectors are empty or duplicated";
  let known_selectors =
    List.map (fun (route : miq_route) -> route.selector_id) miq_routes in
  List.iter
    (fun (route : miq_route) ->
      if not (nonempty route.selector_id
              && nonempty route.required_capability_id
              && nonempty route.assigned_agent_id)
      then add "activity MIQ route contains an empty field";
      if not (List.mem route.selector_id known_selectors) then
        add ("activity names unknown MIQ selector " ^ route.selector_id);
      if not (List.mem route.required_capability_id
                activity.required_capability_ids)
      then add ("activity MIQ route names unavailable capability "
                ^ route.required_capability_id);
      if not (List.mem route.assigned_agent_id
                (List.map (fun (item : component) -> item.stable_id)
                   value.components))
      then add ("activity MIQ route names unknown agent "
                ^ route.assigned_agent_id))
    activity.miq_routes;
  if activity.effect_kinds = []
     || List.length activity.effect_kinds
        <> List.length (List.sort_uniq compare activity.effect_kinds)
  then add "activity effect kinds are empty or duplicated";
  if activity.command_ids = [] || not (unique activity.command_ids) then
    add "activity command ids are empty or duplicated";
  List.rev !gaps

let metric_channel_gaps_for (value : authority) =
  let gaps = ref [] in
  List.iter
    (fun (metric : Run_metrics.declaration) ->
      let matches = List.filter
          (fun (channel : channel) -> channel.metric_id = Some metric.id)
          value.channels
      in
      if List.length matches <> 1
         || not (List.for_all
              (fun (channel : channel) ->
                String.equal channel.fpp_name metric.fpp_channel)
              matches)
      then
        gaps := Printf.sprintf "metric %s resolves to %d FPP channels"
            metric.id (List.length matches) :: !gaps)
    Run_metrics.all;
  List.iter
    (fun (channel : channel) ->
      match channel.metric_id with
      | None -> ()
      | Some id when Option.is_none (Run_metrics.find id) ->
          gaps := ("channel maps unknown metric " ^ id) :: !gaps
      | Some _ -> ())
    value.channels;
  List.rev !gaps

let metric_channel_gaps () = metric_channel_gaps_for authority

let all_element_ids (value : authority) =
  List.map (fun (item : component) -> item.stable_id) value.components
  @ List.map (fun (item : port) -> item.stable_id) value.ports
  @ List.map (fun (item : channel) -> item.stable_id) value.channels
  @ List.map (fun (item : edge) -> item.stable_id) value.edges
  @ List.map (fun (item : lifecycle_machine) -> item.stable_id)
      value.lifecycle_machines
  @ List.map (fun (item : fault_event) -> item.stable_id) value.fault_events
  @ List.map (fun (item : gate_command) -> item.stable_id) value.gate_commands
  @ List.map (fun (item : declarative_activity) -> item.stable_id) value.activities
  @ List.concat_map
      (fun (activity : declarative_activity) ->
        List.map (fun (item : declarative_action) -> item.stable_id)
          activity.actions)
      value.activities

let requirement_gaps_for (value : authority) =
  let known = all_element_ids value in
  let gaps = ref [] in
  List.iter
    (fun (requirement : requirement) ->
      let verifier_count =
        List.length
          (List.filter
             (fun (verifier : verifier) ->
               String.equal verifier.stable_id requirement.verifier_id)
             value.verifiers)
      in
      if verifier_count <> 1 then
        gaps := Printf.sprintf "requirement %s resolves to %d verifiers"
            requirement.stable_id verifier_count :: !gaps;
      if not (nonempty requirement.statement && nonempty requirement.source) then
        gaps := ("requirement " ^ requirement.stable_id ^ " has empty authority") :: !gaps;
      if requirement.covered_elements = [] then
        gaps := ("requirement " ^ requirement.stable_id ^ " covers nothing") :: !gaps;
      List.iter
        (fun id ->
          if not (List.mem id known) then
            gaps := Printf.sprintf "requirement %s covers unknown element %s"
                requirement.stable_id id :: !gaps)
        requirement.covered_elements)
    value.requirements;
  List.rev !gaps

let requirement_gaps () = requirement_gaps_for authority

let sqlite_dependability_gaps_for (value : authority) =
  let gaps = ref [] in
  let add text = gaps := text :: !gaps in
  let find_machine stable_id =
    List.find_opt
      (fun (item : lifecycle_machine) -> item.stable_id = stable_id)
      value.lifecycle_machines
  in
  let exact_states stable_id expected =
    match find_machine stable_id with
    | None -> add ("missing lifecycle machine " ^ stable_id)
    | Some machine ->
        let observed = List.map (fun (state : lifecycle_state) -> state.stable_id)
            machine.states in
        if observed <> expected then add ("lifecycle state denominator differs: " ^ stable_id)
  in
  List.iter (fun (machine_id, state_ids) -> exact_states machine_id state_ids)
    value.formal_policy.sqlite.machine_state_ids;
  let require_transition machine_id state_id signal target required_actions =
    let present =
      match find_machine machine_id with
      | None -> false
      | Some machine ->
          begin match List.find_opt
              (fun (state : lifecycle_state) -> state.stable_id = state_id)
              machine.states with
          | None -> false
          | Some state ->
              List.exists
                (fun (transition : lifecycle_transition) ->
                  transition.signal = signal
                  && transition.target_state = target
                  && List.for_all
                       (fun action -> List.mem action transition.actions)
                       required_actions)
                state.transitions
          end
    in
    if not present then
      add (Printf.sprintf "lifecycle transition differs: %s.%s/%s"
        machine_id state_id signal)
  in
  List.iter
    (fun (item : sqlite_transition_policy) ->
      require_transition item.machine_id item.source_state_id item.signal_id
        item.target_state_id item.required_action_ids)
    value.formal_policy.sqlite.required_transitions;
  List.iter
    (fun (machine : lifecycle_machine) ->
      let states = List.map (fun (state : lifecycle_state) -> state.stable_id)
          machine.states in
      if machine.component_id <> "runEventStore" || machine.states = []
         || not (List.mem machine.initial_state states)
      then add ("invalid RunEventStore lifecycle machine " ^ machine.stable_id);
      List.iter
        (fun (state : lifecycle_state) ->
          List.iter
            (fun (transition : lifecycle_transition) ->
              if not (nonempty transition.signal)
                 || transition.actions = []
                 || not (List.mem transition.target_state states)
              then add ("invalid lifecycle transition from " ^ state.stable_id))
            state.transitions)
        machine.states)
    value.lifecycle_machines;
  let exact label expected observed =
    if List.sort String.compare observed <> List.sort String.compare expected then
      add (label ^ " denominator differs")
  in
  exact "SQLite fault event" value.formal_policy.sqlite.fault_event_ids
    (value.fault_events
     |> List.filter (fun (item : fault_event) ->
            List.mem item.stable_id value.formal_policy.sqlite.fault_event_ids)
     |> List.map (fun (item : fault_event) -> item.stable_id));
  List.iter
    (fun (item : fault_event) ->
      if item.component_id <> "runEventStore" || not (nonempty item.format) then
        add ("invalid SQLite fault event " ^ item.stable_id))
    (List.filter
       (fun (item : fault_event) ->
         List.mem item.stable_id value.formal_policy.sqlite.fault_event_ids)
       value.fault_events);
  exact "SQLite gate command" value.formal_policy.sqlite.gate_command_ids
    (value.gate_commands
     |> List.filter (fun (item : gate_command) ->
            List.mem item.stable_id value.formal_policy.sqlite.gate_command_ids)
     |> List.map (fun (item : gate_command) -> item.stable_id));
  List.iter
    (fun (item : gate_command) ->
      if item.component_id <> "runEventStore" || not (nonempty item.intent_id) then
        add ("invalid SQLite gate command " ^ item.stable_id))
    (List.filter
       (fun (item : gate_command) ->
         List.mem item.stable_id value.formal_policy.sqlite.gate_command_ids)
       value.gate_commands);
  begin match List.filter
      (fun (activity : declarative_activity) ->
        activity.stable_id = value.formal_policy.sqlite.activity_id)
      value.activities with
  | [ activity ] ->
      if activity.stable_id <> value.formal_policy.sqlite.activity_id
         || activity.bridge_component_id
            <> value.formal_policy.execution.bridge_component_id
         || activity.target_component_id <> "runEventStore"
         || not (nonempty activity.intent)
         || activity.constraints = [] || activity.success_criteria = []
      then add "SQLite declarative Swarm activity differs";
      exact "SQLite activity command"
        value.formal_policy.sqlite.gate_command_ids
        activity.command_ids;
      List.iter add (activity_envelope_gaps_for value activity)
  | _ -> add "expected exactly one SQLite declarative Swarm activity"
  end;
  if not (List.exists
      (fun (item : requirement) ->
        item.stable_id = value.formal_policy.sqlite.hazard_requirement_id)
      value.requirements)
  then add (value.formal_policy.sqlite.hazard_requirement_id
            ^ " requirement is missing");
  List.rev !gaps

let sqlite_dependability_gaps () = sqlite_dependability_gaps_for authority

let reachable ?(without = []) (value : authority) source target =
  let rec visit seen node =
    if String.equal node target then true
    else if List.mem node seen || List.mem node without then false
    else
      value.edges
      |> List.filter (fun (item : edge) -> String.equal item.from_component node)
      |> List.exists (fun (item : edge) -> visit (node :: seen) item.to_component)
  in
  visit [] source

let execution_bypass_gaps (value : authority) =
  let gaps = ref [] in
  let policy = value.formal_policy.execution in
  let bridge_edges =
    List.filter
      (fun (item : edge) -> item.kind = Execution
        && String.equal item.from_component policy.bridge_component_id
        && String.equal item.to_component policy.worker_component_id
        && String.equal item.stable_id policy.required_execution_edge_id)
      value.edges
  in
  if List.length bridge_edges <> 1 then
    gaps := Printf.sprintf "expected one bridge-to-worker execution edge, found %d"
        (List.length bridge_edges) :: !gaps;
  List.iter
    (fun (item : edge) ->
      if item.kind = Execution
         && (not (String.equal item.from_component policy.bridge_component_id)
             || not (String.equal item.to_component policy.worker_component_id)
             || not (String.equal item.stable_id policy.required_execution_edge_id))
      then gaps := ("execution bypass edge " ^ item.stable_id) :: !gaps)
    value.edges;
  if reachable ~without:[ policy.bridge_component_id ] value
       policy.supervisor_component_id policy.worker_component_id
  then gaps := "suiteWorker is reachable while the bridge is removed" :: !gaps;
  List.rev !gaps

let ui_admission_gaps (value : authority) =
  List.concat_map
    (fun source ->
      List.filter_map
        (fun target ->
          if reachable value source target then
            Some (Printf.sprintf "UI component %s reaches admission component %s" source target)
          else None)
        value.formal_policy.ui_isolation.admission_component_ids)
    value.formal_policy.ui_isolation.ui_component_ids

let validate_authority (value : authority) =
  let gaps = ref [] in
  let add text = gaps := text :: !gaps in
  let component_ids =
    List.map (fun (item : component) -> item.stable_id) value.components in
  if component_ids <> component_names then add "component denominator or order differs";
  let categories =
    [ ("component", component_ids);
      ("port", List.map (fun (item : port) -> item.stable_id) value.ports);
      ("channel", List.map (fun (item : channel) -> item.stable_id) value.channels);
      ("edge", List.map (fun (item : edge) -> item.stable_id) value.edges);
      ("verifier", List.map (fun (item : verifier) -> item.stable_id) value.verifiers);
      ("requirement", List.map (fun (item : requirement) -> item.stable_id)
         value.requirements);
      ("lifecycle-machine", List.map
         (fun (item : lifecycle_machine) -> item.stable_id)
         value.lifecycle_machines);
      ("fault-event", List.map (fun (item : fault_event) -> item.stable_id)
         value.fault_events);
      ("gate-command", List.map (fun (item : gate_command) -> item.stable_id)
         value.gate_commands);
      ("activity", List.map (fun (item : declarative_activity) -> item.stable_id)
         value.activities);
      ("action", List.concat_map
         (fun (activity : declarative_activity) ->
           List.map (fun (item : declarative_action) -> item.stable_id)
             activity.actions)
         value.activities) ]
  in
  List.iter (fun (label, ids) ->
    if ids = [] then add (label ^ " denominator is empty");
    if not (unique ids) then add (label ^ " stable ids are not unique");
    if List.exists (fun id -> not (nonempty id)) ids then
      add (label ^ " stable id is empty")) categories;
  let all_ids = List.concat_map snd categories in
  if not (unique all_ids) then add "stable ids collide across authority categories";
  let execution_policy = value.formal_policy.execution in
  List.iter
    (fun component_id ->
      if not (List.mem component_id component_ids) then
        add ("formal execution policy names unknown component " ^ component_id))
    [ execution_policy.supervisor_component_id;
      execution_policy.bridge_component_id; execution_policy.worker_component_id ];
  if not (List.exists
      (fun (item : edge) ->
        item.stable_id = execution_policy.required_execution_edge_id)
      value.edges)
  then add "formal execution policy names unknown required edge";
  let ui_policy = value.formal_policy.ui_isolation in
  if ui_policy.ui_component_ids = [] || ui_policy.admission_component_ids = []
     || not (unique ui_policy.ui_component_ids)
     || not (unique ui_policy.admission_component_ids)
  then add "formal UI isolation policy denominator is invalid";
  List.iter
    (fun component_id ->
      if not (List.mem component_id component_ids) then
        add ("formal UI isolation policy names unknown component " ^ component_id))
    (ui_policy.ui_component_ids @ ui_policy.admission_component_ids);
  if List.exists
      (fun component_id -> List.mem component_id ui_policy.admission_component_ids)
      ui_policy.ui_component_ids
  then add "formal UI and admission component sets overlap";
  let model_contract = value.formal_policy.model_contract in
  if not (nonempty model_contract.fpp_model_name
          && nonempty model_contract.fpp_topology_name)
     || model_contract.fpp_base_id < 0
     || model_contract.projection_surface_ids
        <> [ "sysml-v2"; "oml-owl"; "openmbee-mms"; "fpp" ]
  then add "formal model policy differs";
  if value.formal_policy.sqlite.machine_state_ids = []
     || value.formal_policy.sqlite.required_transitions = []
     || value.formal_policy.sqlite.fault_event_ids = []
     || value.formal_policy.sqlite.gate_command_ids = []
     || not (nonempty value.formal_policy.sqlite.activity_id)
     || not (nonempty value.formal_policy.sqlite.hazard_requirement_id)
  then add "formal SQLite policy denominator is invalid";
  List.iter
    (fun (item : port) ->
      if not (List.mem item.component_id component_ids) then add ("port owner unknown: " ^ item.stable_id);
      if not (nonempty item.name) || item.count <= 0 then add ("invalid port: " ^ item.stable_id))
    value.ports;
  let port_keys =
    List.map (fun (item : port) -> item.component_id ^ "." ^ item.name) value.ports in
  if not (unique port_keys) then add "component port names are not unique";
  let fpp_names = List.map (fun (item : channel) -> item.fpp_name) value.channels in
  if not (unique fpp_names) then add "FPP channel names are not unique";
  List.iter (fun component_id ->
    if not (List.exists (fun (item : port) -> item.component_id = component_id) value.ports)
    then add (component_id ^ " has no typed port");
    if not (List.exists (fun (item : channel) -> item.component_id = component_id) value.channels)
    then add (component_id ^ " has no FPP channel")) component_ids;
  List.iter
    (fun (item : channel) ->
      if not (List.mem item.component_id component_ids) then add ("channel owner unknown: " ^ item.stable_id);
      if not (nonempty item.fpp_name) then add ("empty FPP channel: " ^ item.stable_id))
    value.channels;
  let resolve_port component name =
    List.find_opt
      (fun (item : port) -> item.component_id = component && item.name = name)
      value.ports
  in
  List.iter
    (fun (item : edge) ->
      match resolve_port item.from_component item.from_port,
            resolve_port item.to_component item.to_port with
      | Some from_port, Some to_port ->
          if from_port.direction <> Output || to_port.direction <> Input then
            add ("edge direction invalid: " ^ item.stable_id);
          if from_port.kind <> to_port.kind then add ("edge payload kind differs: " ^ item.stable_id)
      | _ -> add ("edge endpoint unresolved: " ^ item.stable_id))
    value.edges;
  let edge_outputs =
    List.map (fun (item : edge) -> item.from_component ^ "." ^ item.from_port)
      value.edges in
  if not (unique edge_outputs) then add "an output port drives multiple typed edges";
  let verifier_kinds =
    List.map (fun (item : verifier) -> string_of_verifier_kind item.kind)
      value.verifiers in
  if List.sort String.compare verifier_kinds
     <> List.sort String.compare
          [ "fpp-validation"; "metric-channel-mapping"; "window-disjointness";
            "execution-mediation"; "ui-admission-isolation";
            "projection-correspondence"; "formal-nonvacuity" ]
  then add "executable verifier kind denominator differs";
  List.iter add (metric_channel_gaps_for value);
  List.iter add (requirement_gaps_for value);
  if List.map (fun (item : declarative_activity) -> item.stable_id)
       value.activities
     <> [ sqlite_activity.stable_id; repository_activity.stable_id ]
  then add "activity registry denominator or order differs";
  List.iter
    (fun activity -> List.iter add (activity_envelope_gaps_for value activity))
    value.activities;
  List.iter add (sqlite_dependability_gaps_for value);
  List.iter add (execution_bypass_gaps value);
  List.iter add (ui_admission_gaps value);
  let fpp = to_fpp_model value in
  if fpp.components = [] || fpp.instances = [] || fpp.topologies = []
  then add "FPP topology is vacuous";
  let fpp_gaps = Fpp_model.validate fpp in
  if fpp_gaps <> [] then
    add (Printf.sprintf "FPP topology has %d validation gaps" (List.length fpp_gaps));
  List.rev !gaps

let validate () = validate_authority authority

let admit_activity ~stable_id =
  if not (nonempty stable_id) then Error [ "activity stable id is empty" ]
  else
    let authority_gaps = validate_authority authority in
    if authority_gaps <> [] then Error authority_gaps
    else
      match List.filter
          (fun (item : declarative_activity) -> item.stable_id = stable_id)
          authority.activities with
      | [ declaration ] ->
          Ok
            { declaration; activity_digest = activity_digest_of declaration;
              authority_digest = source_digest }
      | [] -> Error [ "unknown activity stable id " ^ stable_id ]
      | matches ->
          Error
            [ Printf.sprintf "activity stable id %s resolves to %d rows"
                stable_id (List.length matches) ]

module For_test = struct
  let declarative_action ~stable_id ~command_id ~assigned_agent_id
      ~dependency_ids ~selector_id ~required_capability_id
      ~context_requirement_ids ~target_component_id ~effect_kind
      ~preparation_id =
    { stable_id; command_id; assigned_agent_id; dependency_ids; selector_id;
      required_capability_id; context_requirement_ids; target_component_id;
      effect_kind; preparation_id; work = Topology_gate }

  let declarative_action_work ~stable_id ~command_id ~assigned_agent_id
      ~dependency_ids ~selector_id ~required_capability_id
      ~context_requirement_ids ~target_component_id ~effect_kind ~work
      ~preparation_id =
    { stable_id; command_id; assigned_agent_id; dependency_ids; selector_id;
      required_capability_id; context_requirement_ids; target_component_id;
      effect_kind; preparation_id; work }

  let action_graph_gaps_for ~expected_actions activity =
    action_graph_gaps_for ~expected:expected_actions authority activity

  type task7a_mutation =
    | Drop_declaration_activity
    | Duplicate_declaration_action
    | Claim_live_bridge
    | Drop_static_template
    | Reorder_work_class
    | Flatten_conditional_controls
    | Swap_completion_receipt_order

  let task7a_declaration_digest_with_mutation mutation =
    let declarations =
      match mutation, task7a_declaration_activities with
      | Drop_declaration_activity, [] -> []
      | Drop_declaration_activity, _ :: rest -> rest
      | Duplicate_declaration_action, [] -> []
      | Duplicate_declaration_action, first :: rest ->
          begin
            match first.actions with
            | [] -> first :: rest
            | action :: _ -> { first with actions = action :: first.actions } :: rest
          end
      | Claim_live_bridge, [] -> []
      | Claim_live_bridge, first :: rest ->
          { first with bridge_component_id = "swarmExecutionBridge" } :: rest
      | (Drop_static_template | Reorder_work_class
        | Flatten_conditional_controls | Swap_completion_receipt_order),
        declarations -> declarations
    in
    match mutation with
    | Drop_static_template ->
        task7a_declaration_digest_of
          ~templates:(match task7a_static_templates with
            | [] -> [] | _ :: rest -> rest)
          declarations
    | Reorder_work_class ->
        task7a_declaration_digest_of
          ~work_class_ids:(List.rev task7a_action_work_class_ids) declarations
    | Flatten_conditional_controls ->
        task7a_declaration_digest_of
          ~conditional_control_schema:"flattened-unconditional-actions"
          declarations
    | Swap_completion_receipt_order ->
        task7a_declaration_digest_of
          ~completion_work_ids:(List.rev task7a_completion_receipt_work_ids)
          declarations
    | Drop_declaration_activity | Duplicate_declaration_action
    | Claim_live_bridge -> task7a_declaration_digest_of declarations
end

type interval = { owner : string; instance : string; first : int; last : int }

let intervals_of_model owner (model : Fpp_model.model) =
  let gaps = ref [] in
  let intervals =
    List.filter_map
      (fun (instance : Fpp_model.instance) ->
        match List.find_opt
            (fun (component : Fpp_model.component) ->
              String.equal component.comp_name instance.of_component)
            model.components with
        | None ->
            gaps := Printf.sprintf "%s.%s names unknown component %s" owner
                instance.inst_name instance.of_component :: !gaps;
            None
        | Some component ->
            let span = Fpp_model.id_span component in
            if instance.base_id < 0 || span <= 0 || instance.base_id > max_int - span then begin
              gaps := Printf.sprintf "%s.%s has invalid or overflowing interval" owner
                  instance.inst_name :: !gaps;
              None
            end else
              Some { owner; instance = instance.inst_name; first = instance.base_id;
                last = instance.base_id + span })
      model.instances
  in
  (List.rev !gaps, intervals)

let interval_gaps others =
  let overlap left right = left.first < right.last && right.first < left.last in
  let render left right =
    Printf.sprintf "%s.%s [%d,%d) overlaps %s.%s [%d,%d)"
      left.owner left.instance left.first left.last right.owner right.instance
      right.first right.last
  in
  let rec internal = function
    | [] -> []
    | left :: rest ->
        List.filter_map
          (fun right -> if overlap left right then Some (render left right) else None)
          rest
        @ internal rest
  in
  let operations_structural, operations = intervals_of_model "operations" model in
  let external_gaps =
    List.concat_map
      (fun (owner, external_model) ->
        let structural, outside_intervals = intervals_of_model owner external_model in
        let cross =
          List.concat_map
            (fun outside ->
              List.filter_map
                (fun operation ->
                  if overlap outside operation then Some (render outside operation)
                  else None)
                operations)
            outside_intervals
        in
        structural @ internal outside_intervals @ cross)
      others
  in
  operations_structural @ internal operations @ external_gaps
