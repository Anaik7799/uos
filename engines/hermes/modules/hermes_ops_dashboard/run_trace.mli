(** Correlated, bounded W3C-shaped run traces with deterministic OTLP export. *)

type attribute_value =
  | String_value of string
  | Int_value of int64
  | Float_value of float
  | Bool_value of bool

type attribute = { key : string; value : attribute_value }
type link_kind = Span_link | Event_link | Metric_link | Evidence_link | Profile_link
type link_resolution =
  | Span_resolved of { trace_id : string; span_id : string }
  | Artifact_resolved
  | Unavailable_observed of string
type link = {
  kind : link_kind;
  id : string;
  digest : string option;
  resolution : link_resolution;
}

type span = {
  trace_id : string;
  span_id : string;
  parent_span_id : string option;
  name : string;
  run_id : string;
  provenance : Run_model.provenance;
  plane : Ops_capability.plane;
  surface : Ops_capability.surface option;
  coordinate : Ops_capability.coordinate;
  rca_origin : Ops_capability.rca_origin;
  started_at_ns : int64;
  ended_at_ns : int64;
  attributes : attribute list;
  links : link list;
}

val validate_graph : span list -> (unit, string) result
val to_otlp_json : span list -> (Yojson.Safe.t, string) result
