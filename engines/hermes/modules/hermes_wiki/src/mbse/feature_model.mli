(* THE MODEL OF RECORD for the feature register — the MBSE spine.

   The instruction this module answers is "the model comes first": a
   feature is a MODEL ELEMENT before it is code, and the three MBSE
   surfaces the programme names — SysML (structure), OML (ontology),
   OpenMBEE (the repository the model is pushed to) — are PROJECTIONS of
   one source, never three hand-maintained documents that drift.

   That single-source discipline is the whole point. A SysML block
   diagram, an OWL vocabulary and an MMS payload maintained separately
   agree on the day they are written and never again; the register is
   already the tracked truth about 285 features, so the model is DERIVED
   from it and every surface is a total function of that derivation.

   Reuse, not reinvention (R14): the OML/OWL emitters already exist in
   modules/hermes_sysml (Oml_projection over Sysml_types.block). This
   module supplies the blocks and adds only what was missing — the SysML
   v2 textual form, the MMS projection, and the gate.

   ---------------------------------------------------------------------
   THE MODEL-FIRST GATE

   A model that merely describes what was built is documentation. A model
   that CONSTRAINS what may be built is engineering, and the difference
   is enforceable: [model_gaps] names every row claiming Built whose
   model element carries no VERIFICATION METHOD. A requirement with no
   verification is the oldest gap in systems engineering — it states an
   intent nothing can ever contradict.

   The gate's verdict is deliberately bounded (R5). A missing model
   element BLOCKS credit and never DENIES it, and its origin is Control —
   the harness's own bookkeeping — never Implementation. A candidate
   cannot be wrong because we failed to model it, and a model gap must
   never be recordable as a defect in the thing being measured. *)

type verification =
  | Probe          (* a live predicate runs and can fail — the strong form *)
  | Declared       (* asserted in the register, nothing executes — a GAP *)

type element = {
  mid : string;              (* stable model id, a function of the feature id *)
  feature_id : string;       (* HW.a.b.c, the key shared with the register *)
  package : string;          (* the owning area, the SysML package / OML concept *)
  name : string;
  requirement : string;      (* the law, read as a requirement statement *)
  satisfied_after : string list;  (* gate edges — model dependencies *)
  verification : verification;
  status : string;           (* the register's derived readiness, not its claim *)
}

(* The feature id -> model id map, exposed because every surface's
   dependency edges name model ids while the register names feature ids,
   and a caller resolving between them must use the SAME function the
   surfaces do or the edges point nowhere. TOTAL. *)
val mid_of : string -> string

(* One element per register row, ordered by feature id so every surface
   below is byte-stable. TOTAL: a row with no gates, no law, or an
   unknown area still yields an element — the model never silently
   loses a feature, because a feature absent from the model is exactly
   what the gate exists to catch. *)
val elements : unit -> element list

(* ------------------------------------------------------- the surfaces *)

(* SysML v2 textual notation: one `package` per area, one `part def` per
   feature, `requirement` bodies carrying the law, and a `dependency`
   for each gate edge. Deterministic — sorted, no clock, no hash order. *)
val sysml_v2 : unit -> string

(* The OML vocabulary as the shared types already express it, so
   Oml_projection emits the TTL and OWL without knowing about wikis. *)
val oml_vocabulary : unit -> Hermes_sysml.Sysml_types.oml_vocabulary

(* SysML blocks for the existing OWL/TTL emitters. One block per area
   (the classifier) plus one per feature (the specialisation), so the
   ontology has real subsumption rather than a flat list of individuals. *)
val blocks : unit -> Hermes_sysml.Sysml_types.block list

(* The OML ontology in Turtle, via the existing projection. *)
val oml_ttl : unit -> string

(* ONE element rendered to each surface. Exposed for two reasons: a
   caller pushing a single element to MMS needs it, and a test needs to
   feed the emitters input the register does not happen to contain. The
   whole-model surfaces below are these applied over [elements ()], so a
   law proved here holds there — which is the point: an escaping bug that
   only fires on an authored quote is invisible until someone writes one. *)
val mms_element : element -> string
val sysml_part : element -> string

(* OpenMBEE MMS element payload: a JSON array of elements with stable
   ids and ownership, the shape an MMS commit expects. Emitted rather
   than posted — this module is pure, and pushing is the caller's IO. *)
val mms_json : unit -> string

(* --------------------------------------------------------- the gate *)

(* Rows claiming Built whose element has no verification method: the
   model-first gate's counted debt. One sorted line each. *)
val model_gaps : unit -> string list

(* Gate edges naming a feature with no model element — a dependency on
   something the model does not contain. Sorted, deduped. *)
val dangling_dependencies : unit -> string list

(* Coverage of the model over the register, for the dashboard: how many
   elements exist, how many carry an executable verification, and how
   many are gaps. Derived, never stored. *)
type coverage = { total : int; verified : int; declared_only : int; built : int }

val coverage : unit -> coverage
