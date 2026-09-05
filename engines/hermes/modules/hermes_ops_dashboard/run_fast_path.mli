(** Data-driven fast-path choice. Every non-reference strategy is admitted only
    by semantic equivalence with the immutable reference oracle. *)

type strategy = Reference | Incremental | Snapshot_then_suffix | Aggregated_graph

type semantic_oracle = { id : string; digest : string }
type resource_budget = {
  max_age_ns : int64;
  future_tolerance_ns : int64;
  max_cost : float;
}

type cost_evidence =
  | Measured_cost of {
      value : float;
      sampled_at_ns : int64;
      receipt_digest : string;
    }
  | Estimated_cost of {
      value : float;
      estimated_at_ns : int64;
      model_digest : string;
    }
  | Cost_unavailable of { reason : string }

type admission =
  | Gate_admitted of { gate_id : string; receipt_digest : string }
  | Gate_not_admitted of { gate_id : string; reason : string }

type fallback_kind =
  | Missing_or_unavailable
  | Stale
  | Malformed
  | Out_of_domain
  | Non_equivalent
  | Not_admitted
  | Cost_exceeded

type diagnostic = {
  kind : fallback_kind;
  message : string;
  coordinate : Ops_capability.coordinate;
  rca_origin : Ops_capability.rca_origin;
}

type reason = Below_low | Above_high | Hysteresis_hold | Reference_fallback

type policy = {
  version : string;
  metric_id : string;
  low_threshold : float;
  high_threshold : float;
  oracle : semantic_oracle;
  equivalent_strategies : (strategy * string) list;
  budget : resource_budget;
  admission : admission;
}

type decision = {
  strategy : strategy;
  reason : reason;
  observation_digest : string option;
  cost_digest : string option;
  policy_digest : string;
  threshold_version : string;
  oracle : semantic_oracle;
  budget : resource_budget;
  decided_at_ns : int64;
  diagnostic : diagnostic option;
}

type selection

val choose_v2 :
  context:Run_safety.gate_context ->
  activity:Run_topology.admitted_activity ->
  policy:policy -> previous:selection option -> now_ns:int64 ->
  cost:cost_evidence -> Run_metrics.observation ->
  (selection, diagnostic list) result

val validate_selection :
  context:Run_safety.gate_context ->
  activity:Run_topology.admitted_activity -> selection ->
  (unit, diagnostic list) result

val selected_strategy : selection -> strategy
val selection_digest : selection -> string

val policy_digest : policy -> string
val choose :
  policy -> previous:decision option -> now_ns:int64 ->
  cost:cost_evidence -> Run_metrics.observation -> decision
