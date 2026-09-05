(** Fail-closed algebras for dependability composition and projection. *)

type availability = Available | Unavailable_observed | Blocked | Indeterminate

type evidence_credit = Dependability_atlas.evidence_credit =
  | No_credit
  | Discovery_credit
  | Structural_credit
  | Differential_credit

type verdict =
  | Satisfied
  | Refuted
  | Evidence_unavailable
  | Not_executed
  | Verdict_indeterminate

type taint = Clean | Tainted
type criticality = private int

type lifecycle =
  | Declared
  | Admitted
  | Running
  | Terminal
  | Current
  | Stale

type coordinate = private { level : string; path : string list }

type ooda_phase =
  | Observe of string
  | Orient of string
  | Decide of string
  | Act of string

type observation = private {
  attempt_id : int;
  verdict : verdict;
  observation_digest : string;
}

type atlas_rollup = private {
  row_ids : string list;
  maximum_source_credit : evidence_credit;
  maximum_projected_credit : evidence_credit;
}

type projected_topology = {
  topology_components : string list;
  topology_edges : (string * string * string * string) list;
}

val meet_availability : availability -> availability -> availability
(*@ result = meet_availability left right
    pure *)

val project_availability : availability -> availability
(*@ result = project_availability source
    pure *)

val credit_rank : evidence_credit -> int
val join_credit : evidence_credit -> evidence_credit -> evidence_credit
val meet_verdict : verdict -> verdict -> verdict
val combine_taint : taint -> taint -> taint

val make_criticality : int -> (criticality, string) result
val criticality_value : criticality -> int
val max_criticality : criticality -> criticality -> criticality

val make_coordinate :
  level:string -> path:string list -> (coordinate, string) result

val refines : parent:coordinate -> child:coordinate -> bool
val advance_lifecycle : lifecycle -> lifecycle -> (lifecycle, string) result

val compose_graph :
  Dependability_graph.node list ->
  Dependability_graph.node list ->
  (Dependability_graph.node list, string) result

val make_observation :
  attempt_id:int ->
  verdict:verdict ->
  observation_digest:string ->
  (observation, string) result

val normalize_observations :
  expected_attempt_ids:int list ->
  observation list ->
  (observation list, string) result

val observations_equivalent :
  expected_attempt_ids:int list ->
  sequential:observation list ->
  parallel:observation list ->
  bool

val projection_preserves_credit : Dependability_atlas.row list -> bool
val rollup_atlas : Dependability_atlas.row list -> atlas_rollup
val drill_down_atlas :
  atlas_rollup -> Dependability_atlas.row list -> Dependability_atlas.row list
val rollup_roundtrip : Dependability_atlas.row list -> bool
val graph_fpp_topology_agreement :
  graph:Dependability_graph.node list ->
  atlas:Dependability_atlas.row list ->
  authority:projected_topology ->
  projection:projected_topology ->
  bool

val taint_closure : edges:(string * string) list -> string list -> string list
(*@ closed = taint_closure ~edges seeds
    pure *)

val closes_ooda : ooda_phase list -> bool
(*@ closed = closes_ooda trace
    pure *)

val atlas_homomorphism :
  ontology:Dependability_ontology.node list ->
  atlas:Dependability_atlas.row list ->
  bool
(*@ preserved = atlas_homomorphism ~ontology ~atlas
    pure *)
