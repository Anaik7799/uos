(** Total atomic capability atlas for the dependability component. *)

type evidence_credit =
  | No_credit
  | Discovery_credit
  | Structural_credit
  | Differential_credit

type surface = Ocaml_api | Cli | Mcp | Zenoh
type lifecycle = Declared | Implemented | Current | Unavailable_observed
type applicability = Applicable | Not_applicable of string
type availability = Available_structural | Unavailable_observed_status | Blocked_status

type row = {
  row_id : string;
  capability_id : string;
  ontology_id : string;
  coordinate : string;
  target : Dependability_intent.target;
  intent : Dependability_intent.operation option;
  surface : surface;
  applicability : applicability;
  availability : availability;
  graph_units : string list;
  fpp_elements : string list;
  formal_obligations : string list;
  native_tests : string list;
  metric_ids : string list;
  receipt_kinds : string list;
  currentness_dependencies : string list;
  residuals : string list;
  source_credit : evidence_credit;
  projected_credit : evidence_credit;
  plane : Dependability_intent.plane;
  owner : string;
  lifecycle : lifecycle;
}

val rows : row list
val find : string -> row option
val find_mapping :
  capability_id:string ->
  target:Dependability_intent.target ->
  surface:surface ->
  row option
val validate : unit -> string list
(*@ errors = validate ()
    pure *)

val meta_view : unit -> string
(*@ rendered = meta_view ()
    pure
    ensures rendered <> "" *)

val digest : string
val summary_total : int
