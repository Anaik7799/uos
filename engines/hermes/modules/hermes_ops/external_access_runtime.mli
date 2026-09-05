(** Pure OTP-30-inspired supervision and predictive-control model for R31.
    It is a reference correspondence, not an OTP equivalence claim and not an
    effect scheduler. Actual work remains owned by Run_swarm_bridge. *)

type reference_claim = Reference_model_not_equivalence
type otp_reference = {
  release : string;
  pin_file : string;
  claim : reference_claim;
}
val otp_reference : otp_reference

type restart_strategy = One_for_one | One_for_all | Rest_for_one
type restart_type = Permanent | Transient | Temporary
type shutdown = Graceful of int | Brutal_kill
type child_role = Gateway | Policy | Adapter_worker | Evidence_store
  | Recovery_worker | Telemetry_worker
type child_spec = {
  child_id : string;
  role : child_role;
  restart : restart_type;
  shutdown : shutdown;
  mailbox_capacity : int;
  resource_budget_id : string;
  recovery_id : string;
}
type restart_intensity = { max_restarts : int; window_ms : int }
type supervisor_declaration = {
  supervisor_id : string;
  strategy : restart_strategy;
  intensity : restart_intensity;
  children : child_spec list;
}
type supervisor_spec
val make_supervisor : supervisor_declaration -> (supervisor_spec, string list) result

type exit_reason = Normal | Shutdown | Abnormal | Resource_exhausted | Indeterminate
val restart_set : supervisor_spec -> failed_child:string -> reason:exit_reason -> string list
type restart_decision = Restart_allowed | Escalate
val restart_decision : supervisor_spec -> now_ms:int -> failure_times_ms:int list -> restart_decision

type mailbox
type enqueue_result = Accepted | Rejected_full
val mailbox : capacity:int -> mailbox
val enqueue : mailbox -> enqueue_result
val dequeue : mailbox -> bool
val mailbox_depth : mailbox -> int

type resource_scope
val scope : string list -> resource_scope
val close_scope : resource_scope -> unit
val scope_open_resources : resource_scope -> int

type uca_type = Not_provided | Provided_incorrectly | Wrong_timing | Applied_too_long
type stpa_uca = {
  uca_id : string;
  uca_type : uca_type;
  controller : string;
  control_action : string;
  context : string;
  hazard_ids : string list;
  constraint_ids : string list;
}
val stpa_ucas : stpa_uca list

type failure_mode = {
  failure_id : string;
  component_id : string;
  effect_description : string;
  detection : string;
  recovery : string;
  severity : int;
  occurrence : int;
  detectability : int;
}
val fmea : failure_mode list
val validate_fmea : unit -> string list

type assurance_tool = Stpa | Fmea | Rete_ul | Stanc | Z3 | Rocq | Iris | Quint
type assurance_role = {
  tool : assurance_tool;
  obligation : string;
  credit_limit : string;
  required_control : string;
  current_adapter : string;
}
val assurance : assurance_role list
val validate_assurance : unit -> string list

type signal = Mailbox_saturation | Restart_storm | Latency_growth
  | Error_rate_growth | Resource_leak | Readback_mismatch
type prediction_input = {
  signal : signal;
  current_value : float;
  limit : float;
  derivative : float;
  confidence : float;
}
type prediction_verdict = Stable | Watch | Intervention_recommended | Insufficient_evidence
type prediction = {
  verdict : prediction_verdict;
  confidence : float;
  horizon_ms : int;
  hypotheses : string list;
  next_measurement : string;
  safe_action : string;
}
val predict : prediction_input -> prediction

type plane = Control_plane | Data_plane
type ooda_phase = Observe | Orient | Decide | Act
type communication = Request | Classification | Validation | Authorization
  | Preflight | Admission | Effect_request | Readback | Receipt | Telemetry
type metric_spec = {
  metric_id : string;
  unit_name : string;
  limit : float;
  retention_samples : int;
  freshness_ms : int;
}
type predictive_path = {
  path_id : string;
  resource : External_access.resource;
  level : Ops_capability.level;
  component_id : string;
  communication : communication;
  plane : plane;
  phase : ooda_phase;
  metrics : metric_spec list;
  prediction_target : string;
  safe_action_policy : string;
}
val predictive_paths : predictive_path list
val predictive_coverage_gaps : predictive_path list -> string list

type state_store
type sample = {
  path_id : string;
  metric_id : string;
  observed_at_ns : int64;
  value : float;
  source_digest : string;
  run_id : string;
}
type sample_refusal = Unknown_path | Unknown_metric | Invalid_value
  | Invalid_identity | Non_monotonic_time | Series_capacity_reached
  | Store_capacity_reached
val create_state_store : max_series:int -> max_samples_per_series:int -> state_store
val observe_sample : state_store -> sample -> (unit, sample_refusal) result
val samples : state_store -> path_id:string -> metric_id:string -> sample list
type quality = {
  sample_count : int;
  monotonic : bool;
  current : bool;
  source_consistent : bool;
  prediction_ready : bool;
}
val quality : state_store -> now_ns:int64 -> path_id:string -> metric_id:string -> quality
val predict_series : state_store -> now_ns:int64 -> path_id:string -> metric_id:string -> prediction

type complexity = Constant | Linear_in_children
type runtime_operation = {
  operation_id : string;
  time_complexity : complexity;
  space_complexity : complexity;
  bound : string;
}
val runtime_operations : runtime_operation list
val validate_runtime : unit -> string list
