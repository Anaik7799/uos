(** Executable laws connecting event fold, transport recovery, projections,
    RCA effects, and causal Fast OODA closure. *)

type transport_state = Fresh | Stale | Unavailable
type projection = Table | Tyxml | Webgl_neutral | Otel | Fpp | Mbse
type completion = Unmapped | Blocked | Verified
type failure_effect = Blocks_credit | Denies_credit

type semantic_projection = {
  summary : Run_snapshot.summary;
  receipt_digest : string;
}

type table_surface = { semantic : semantic_projection; columns : string list }
type tyxml_surface = { semantic : semantic_projection; root_role : string }
type webgl_surface = { semantic : semantic_projection; scene_schema : string }
type otel_surface = { semantic : semantic_projection; scope_name : string }
type fpp_surface = { semantic : semantic_projection; channel : string }
type mbse_surface = { semantic : semantic_projection; element_kind : string }

type surface_projection =
  | Table_surface of table_surface
  | Tyxml_surface of tyxml_surface
  | Webgl_surface of webgl_surface
  | Otel_surface of otel_surface
  | Fpp_surface of fpp_surface
  | Mbse_surface of mbse_surface

type ooda_step = {
  run_id : string;
  coordinate : Ops_capability.coordinate;
  occurred_at_ns : int64;
  consumes_receipt_digest : string option;
  produces_receipt_digest : string;
}

val snapshot_suffix_equivalent : split_at:int -> Run_model.event list -> bool
val duplicate_identity : Run_snapshot.t -> Run_model.event -> bool
val gap_requires_resync : Run_snapshot.t -> Run_model.event -> bool
val transport_state :
  now_ns:int64 -> max_age_ns:int64 -> future_tolerance_ns:int64 ->
  last_seen_ns:int64 option -> transport_state
val project : projection -> Run_snapshot.summary -> surface_projection
val normalize_projection : surface_projection -> (semantic_projection, string) result
val projections_equivalent : surface_projection list -> bool
val projection_homomorphism : Run_snapshot.summary -> bool
val complete_required : bool list -> completion
val failure_effect : Ops_capability.rca_origin -> failure_effect
val closes_fast_ooda : max_latency_ns:int64 -> ooda_step list -> bool
