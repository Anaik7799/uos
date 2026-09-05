(* Standard Operating Procedure (SOP) Execution Engine for 5-Agent Swarms
   with OCaml System Services (Planning, Job Manager, Temporal),
   Resource Dashboard Token Tracking, and Phase 3 Advanced Swarm Capabilities
   (Decentralized Gossip, Branchable Irmin CRDT Memory, Immune Resilience, Effects I/O). *)

type agent_id = string

type agent_config = {
  id : agent_id;
  name : string;
  role : string;
  estimated_input_tokens : int;
  estimated_output_tokens : int;
}

type agent_token_stat = {
  agent_id : agent_id;
  role : string;
  estimated_tokens : int;
  actual_input_tokens : int;
  actual_output_tokens : int;
  actual_total_tokens : int;
  variance : int;
  percentage_variance : float;
}

type resource_dashboard = {
  stats : agent_token_stat list;
  total_estimated : int;
  total_actual : int;
  total_variance : int;
  total_percentage_variance : float;
  execution_status : string;
}

type step_status =
  | Pending
  | Ready
  | Executing
  | Completed
  | Failed of string

type step = {
  step_id : string;
  name : string;
  assigned_agent : agent_id;
  dependencies : string list;
  action : agent_id -> string -> string * (int * int);
  (* action returns (output_payload, (actual_input_tokens, actual_output_tokens)) *)
}

type step_result = {
  step_id : string;
  agent_id : agent_id;
  status : step_status;
  input_payload : string;
  output_payload : string;
  tokens_used : int * int; (* input_tokens, output_tokens *)
  duration_ms : float;
}

type job_state =
  | Queued
  | Executing
  | Completed
  | Retried of int
  | Failed of string

type job = {
  job_id : string;
  step_id : string;
  target_agent : agent_id;
  state : job_state;
  attempts : int;
  max_retries : int;
}

type event =
  | StepScheduled of string * agent_id
  | JobStateChanged of string * job_state
  | StepCompletedEvent of string * agent_id * string
  | CheckpointCreated of string * string (* step_id * state_hash *)

type checkpoint = {
  step_id : string;
  timestamp : float;
  state_hash : string;
  completed_steps : string list;
  agent_results : (agent_id * string) list;
}

type temporal_history = {
  events : event list;
  checkpoints : checkpoint list;
}

(* Phase 3.1: Decentralized Gossip (hermes_zenoh integration) *)
module Gossip : sig
  type message = {
    topic : string;
    sender : agent_id;
    payload : string;
    timestamp : float;
  }
  type mesh
  val create : unit -> mesh
  val publish : mesh -> topic:string -> sender:agent_id -> payload:string -> unit
  val subscribe : mesh -> topic:string -> (message -> unit) -> unit
  val broadcast_state_transition : mesh -> agent_id:agent_id -> step_id:string -> state:string -> unit
  val get_messages : mesh -> message list
end

(* Phase 3.2: Branchable Memory & CRDTs (irmin integration) *)
module IrminMemory : sig
  type tree = (string * string) list
  type commit = {
    commit_id : string;
    parent_id : string option;
    tree : tree;
    author : agent_id;
    timestamp : float;
  }
  type store
  val create : unit -> store
  val commit : store -> branch:string -> author:agent_id -> tree:tree -> commit
  val create_branch : store -> from_branch:string -> new_branch:string -> unit
  val merge_crdt : store -> source_branch:string -> target_branch:string -> author:agent_id -> commit
  val get_branch_head : store -> branch:string -> commit option
  val get_tree : store -> branch:string -> tree
end

(* Phase 3.3: Immune Resilience (homeostasis integration) *)
module Immune : sig
  type health_status = Healthy | Degraded of string | ApoptosisTriggered of string
  type anomaly = {
    agent_id : agent_id;
    step_id : string;
    anomaly_type : string;
    severity : int; (* 0..3 *)
  }
  type engine
  val create : unit -> engine
  val check_health : engine -> agent_id -> health_status
  val detect_anomaly : engine -> agent_id:agent_id -> step_id:string -> duration_ms:float -> error:string option -> anomaly option
  val record_anomaly : engine -> anomaly -> unit
  val should_apoptosis : engine -> agent_id -> bool
  val self_heal_retry : engine -> string -> (unit -> 'a) -> ('a, string) result
end

(* Phase 3.4: Effects-based Concurrent I/O (eio integration) *)
module EffectsIO : sig
  type 'a fiber
  type effect_event =
    | ReadPayload of string
    | WriteTelemetry of string * string
    | FiberYield
  val spawn_fiber : (unit -> 'a) -> 'a fiber
  val await_fiber : 'a fiber -> 'a
  val run_with_handler : (unit -> 'a) -> 'a * effect_event list
  val execute_concurrent : (unit -> 'a) list -> 'a list
end

(* Phase 5: Observability & Telemetry (Structured Fractal Logging Engine) *)
module FractalTelemetry : sig
  type telemetry_event = {
    timestamp : float;
    level : Fractal_ontology.level;
    component_id : string;
    aspect : Fractal_ontology.aspect;
    decision : string;
    system_service_constraint : string;
    payload : string;
  }

  type engine

  val create : unit -> engine
  val record_event :
    engine ->
    level:Fractal_ontology.level ->
    component_id:string ->
    aspect:Fractal_ontology.aspect ->
    decision:string ->
    system_service_constraint:string ->
    payload:string ->
    telemetry_event

  val get_log : engine -> telemetry_event list
  val clear : engine -> unit
  val render_summary : engine -> string

  val record_global :
    level:Fractal_ontology.level ->
    component_id:string ->
    aspect:Fractal_ontology.aspect ->
    decision:string ->
    system_service_constraint:string ->
    payload:string ->
    telemetry_event

  val get_global_log : unit -> telemetry_event list
  val clear_global : unit -> unit
  val render_global_summary : unit -> string
end

type workflow_execution_result = {
  step_results : step_result list;
  job_history : job list;
  history : temporal_history;
  dashboard : resource_dashboard;
  gossip_messages : Gossip.message list;
  irmin_store : IrminMemory.store;
  immune_engine : Immune.engine;
  effects_telemetry : EffectsIO.effect_event list;
  telemetry_log : FractalTelemetry.telemetry_event list;
  replay_verified : bool;
}

(* Top-level Fractal Telemetry Accessors *)
val get_fractal_telemetry_log : unit -> FractalTelemetry.telemetry_event list
val render_fractal_telemetry_summary : unit -> string

(* OCaml System Service: Planning Scheduler *)
module Planning : sig
  type dag
  val create_dag : step list -> dag
  val get_step : dag -> string -> step option
  val all_steps : dag -> step list
  val get_ready_steps : dag -> (string * step_status) list -> step list
  val is_complete : dag -> (string * step_status) list -> bool
  val topological_sort : dag -> string list
end

(* OCaml System Service: Job Manager (Oban Equivalent) *)
module JobManager : sig
  type queue
  type nonrec job = job
  val create : unit -> queue
  val enqueue : queue -> job -> unit
  val dequeue : queue -> job option
  val update_state : queue -> string -> job_state -> unit
  val get_job : queue -> string -> job option
  val all_jobs : queue -> job list
end

(* OCaml System Service: Temporal Engine *)
module Temporal : sig
  type engine
  val create : unit -> engine
  val record_event : engine -> event -> unit
  val create_checkpoint : engine -> string -> string list -> (agent_id * string) list -> checkpoint
  val get_history : engine -> temporal_history
  val verify_replay : temporal_history -> bool
end

(* Resource Dashboard Renderer *)
module Dashboard : sig
  val create : agent_config list -> step_result list -> resource_dashboard
  val render_ascii : resource_dashboard -> string
  val print : resource_dashboard -> unit
end

(* Pre-configured 5-agent swarm and SOP workflow *)
val default_5_agents : agent_config list
val default_5_step_sop : step list

module For_test : sig
  type spawn_receipt = {
    attempted_step_ids : string list;
    spawned_step_ids : string list;
    joined_step_ids : string list;
    failed_step_id : string option;
  }

  val with_pre_spawn_failure :
    before_attempt:int ->
    (unit -> 'a) ->
    'a * spawn_receipt

  type result_fault =
    | Missing_action_result
    | Duplicate_action_result
    | Unknown_action_result
    | Out_of_order_results
    | Replay_not_verified
    | Engine_exception

  val with_result_fault : result_fault -> (unit -> 'a) -> 'a

  val dependency_payload : string list -> string
end

(* Workflow Execution Engine with bounded Domain parallelism.  The optional
   positive bound is clamped to at least one.  The default keeps at least 32
   slots so a container's conservative CPU recommendation cannot effectively
   serialize the whole verification graph; a larger runtime recommendation is
   honored. Ready work beyond the bound remains pending for the next
   engine-owned wave. *)
val default_max_parallelism : unit -> int
val execute_sop_workflow :
  ?agents:agent_config list ->
  ?max_parallelism:int ->
  ?steps:step list ->
  unit ->
  workflow_execution_result

(* Phase 6: Declarative Intent Configuration & Autonomous Synthesis *)
module DeclarativeIntent : sig
  type declarative_intent = {
    goal : string;
    constraints : string list;
    target_state : string;
    required_capabilities : string list;
  }

  val synthesize_execution_plan : declarative_intent -> step list * job list
  val execute_declarative_intent : declarative_intent -> workflow_execution_result
end

type declarative_intent = DeclarativeIntent.declarative_intent = {
  goal : string;
  constraints : string list;
  target_state : string;
  required_capabilities : string list;
}

val synthesize_execution_plan : declarative_intent -> step list * job list
val execute_declarative_intent : declarative_intent -> workflow_execution_result
