type outcome = Succeeded | Refused | Failed | Timed_out | Indeterminate

type declaration = {
  trace_id : string;
  span_id : string;
  parent_span_id : string option;
  run_id : string;
  request_id : string;
  intent_id : string;
  attempt_id : string option;
  path_id : string;
  metric_id : string;
  observed_at_ns : int64;
  duration_ns : int64;
  value : float;
  outcome : outcome;
  rca_origin : Ops_capability.rca_origin;
  hazard_id : string;
  event_code : string;
  source_digest : string;
  prediction_verdict : External_access_runtime.prediction_verdict;
}

type observation
val observe : declaration -> (observation, string list) result
val is_child : parent:observation -> child:observation -> bool
val attributes : observation -> (string * string) list

type log_record = {
  trace_id : string;
  span_id : string;
  parent_span_id : string option;
  path_id : string;
  level : Ops_capability.level;
  phase : External_access_runtime.ooda_phase;
  plane : External_access_runtime.plane;
  rca_origin : Ops_capability.rca_origin;
  hazard_id : string;
  event_code : string;
  outcome : outcome;
  observed_at_ns : int64;
  duration_ns : int64;
}
val log_record : observation -> log_record

type logging_contract = {
  path_id : string;
  metric_ids : string list;
  required_dimensions : string list;
  max_attributes : int;
  redaction_policy : string;
}
val logging_contracts : logging_contract list
val logging_coverage_gaps : unit -> string list

type tuning_action = No_change | Apply_backpressure | Scale_workers
  | Reduce_concurrency | Investigate_readback
type execution = Recommendation_only
type tuning_recommendation = {
  action : tuning_action;
  execution : execution;
  evidence_ids : string list;
  confidence : float;
  rationale : string;
  next_measurement : string;
}
val tune : observation list -> tuning_recommendation
val validate : unit -> string list
