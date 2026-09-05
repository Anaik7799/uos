(** Fail-closed typed boundary from admitted operations intent to Swarm
    execution.  Admission, immutable planning, apply-once execution, durable
    attempt evidence, projection checking, and full readback are one boundary. *)

type diagnostic_code =
  | Invalid_event_source
  | Invalid_current_authority
  | Invalid_intent
  | Invalid_admission
  | Invalid_action_registry
  | Invalid_plan

type diagnostic = private {
  code : diagnostic_code;
  message : string;
  coordinate : Ops_capability.coordinate;
  rca_origin : Ops_capability.rca_origin;
  hazard_id : string;
}

type error_code =
  | Event_authority_unavailable
  | Execution_refused
  | Event_append_failure
  | Effect_failure
  | Projection_invalid
  | Readback_invalid

type error = private {
  code : error_code;
  message : string;
  coordinate : Ops_capability.coordinate;
  rca_origin : Ops_capability.rca_origin;
  hazard_id : string;
}

type event_sources
type event_authority
type current_authority
type typed_intent
type admission
type action_registry
type admitted_plan

type action_status = Action_succeeded | Action_failed

type action_receipt = private {
  action_id : string;
  action_digest : string;
  request_digest : string;
  effect_receipt_digest : string;
  output_digest : string;
  attempt_count : int;
  status : action_status;
}

type result = private {
  run_id : string;
  authority_digest : string;
  admission_digest : string;
  plan_digest : string;
  ordered_action_receipts : action_receipt list;
  engine_projection_digest : string;
  initial_head_sequence : int64;
  initial_head_digest : string;
  final_head_sequence : int64;
  final_head_digest : string;
  attempt_event_count : int;
  complete_stream_digest : string;
  result_digest : string;
}

val production_event_sources : event_sources

val create_event_authority :
  store:Run_event_store.t -> context:Run_safety.gate_context ->
  sources:event_sources -> (event_authority, error) Stdlib.result

val current_authority :
  event_authority -> (current_authority, error) Stdlib.result

val resolve_intent :
  context:Run_safety.gate_context ->
  current_authority:current_authority ->
  activity:Run_topology.admitted_activity ->
  (typed_intent, diagnostic list) Stdlib.result

val intent_authority_digests : typed_intent -> string * string
val intent_debug_authority_digest : typed_intent -> string
val intent_external_access_authority_digest : typed_intent -> string
(** Returns the module-intent, five-owner FPP portfolio, debugging, and
    controlled-external-access authority digests bound into this closed intent.
    These are admission evidence, never effect authority. *)

val admit :
  context:Run_safety.gate_context -> intent:typed_intent ->
  current_authority:current_authority ->
  assurance:Run_assurance.admitted_bundle ->
  fast_path:Run_fast_path.selection ->
  (admission, diagnostic list) Stdlib.result

val action_registry :
  activity:Run_topology.admitted_activity ->
  (action_registry, diagnostic list) Stdlib.result

val admit_plan :
  admission:admission -> action_registry:action_registry ->
  (admitted_plan, diagnostic list) Stdlib.result

val admitted_plan_digest : admitted_plan -> string

val execution_identity :
  run_id:string -> activity:Run_topology.admitted_activity -> string
(** Freshness-independent logical execution identity.  It binds the run and
    canonical activity/topology authority, never a current head, admission,
    or plan digest. *)

val execute :
  admission:admission -> authority:event_authority ->
  interpreter:Run_effect_authority.interpreter -> plan:admitted_plan ->
  (result, error) Stdlib.result

val validate_result :
  admission:admission -> authority:event_authority ->
  interpreter:Run_effect_authority.interpreter -> plan:admitted_plan -> result ->
  (unit, error) Stdlib.result

module For_test : sig
  type intent_mutation =
    | Debug_authority_digest
    | External_access_authority_digest
  val mutate_intent : intent_mutation -> typed_intent -> typed_intent
  val intent_authorities_current : typed_intent -> bool

  val event_sources :
    wall_now_ns:(unit -> int64) -> monotonic_now_ns:(unit -> int64) ->
    event_id:(run_id:string -> sequence:int64 -> string) ->
    readback_agrees:bool -> event_sources

  val action_registry_from_declaration :
    Run_topology.declarative_activity ->
    (action_registry, diagnostic list) Stdlib.result

  val validate_admission_identities :
    context:Run_safety.gate_context -> intent_context_digest:string ->
    current_context_digest:string -> assurance_context_digest:string ->
    selection_context_digest:string ->
    (unit, diagnostic list) Stdlib.result

  type registry_mutation =
    | Registry_activity_identity
    | Registry_action_order
    | Registry_digest

  val mutate_action_registry :
    registry_mutation -> action_registry -> action_registry

  type plan_mutation =
    | Duplicate_admission_id
    | Duplicate_plan_id
    | Plan_action_order
    | Plan_graph_digest
    | Plan_digest

  val mutate_plan : plan_mutation -> admitted_plan -> admitted_plan

  val validate_plan :
    admission:admission -> action_registry:action_registry -> admitted_plan ->
    (unit, diagnostic list) Stdlib.result

  type result_mutation =
    | Result_authority_identity
    | Result_admission_identity
    | Result_plan_identity
    | Result_action_order
    | Result_action_digest
    | Result_request_digest
    | Result_effect_digest
    | Result_output_digest
    | Result_attempt_count
    | Result_action_status
    | Result_engine_projection
    | Result_initial_head
    | Result_final_head
    | Result_attempt_event_count
    | Result_complete_stream
    | Result_digest

  val mutate_result : result_mutation -> result -> result

  val reset_engine_call_count : unit -> unit
  val engine_call_count : unit -> int
  val reset_preparation_call_count : unit -> unit
  val preparation_call_count : unit -> int

  val arm_preparation_failures :
    event_authority -> action_id:string -> count:int ->
    (unit, string) Stdlib.result

  val fail_next_terminal_append :
    event_authority -> action_id:string -> (unit, string) Stdlib.result

end
