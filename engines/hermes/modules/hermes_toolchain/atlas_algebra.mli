(* Denotational core for algebraic-atlas conformance.

   Formal spec section 3 declares nine algebraic structures and, for each, a
   required law. The atlas JSON is supposed to encode that table per capability
   row. It did not: measured over the 30 rows, 46 of 64 leaf fields carried an
   IDENTICAL value on every row, including `algebra.laws[1]`, `algebra.oracle`
   and `traceability.aspects`. A schema that admits a constant is an observable
   coarser than the property it claims to record, which is the defect class this
   whole review has been chasing.

   This module is the MEANING of conformance. It is pure -- no unix, no IO, no
   clock -- so every law in the test suite is about semantics, and the effectful
   shell (atlas_check.ml) only supplies observations. Same split as
   `preflight_algebra`, and for the same reason: the law suite must link the
   shipped semantics rather than a copy that can drift. *)

(* The nine structures of formal spec section 3, closed. There is deliberately
   no `Other` constructor: a row cannot invent a tenth structure to look
   complete, and the compiler enforces that every match handles all nine. *)
type structure =
  | Intent_composition
  | Independent_operations
  | Capability_refinement
  | Authority_constraints
  | Evidence_refinement
  | State_projection
  | Replication
  | Release_migration
  | Resource_accounting

val all_structures : structure list
val structure_name : structure -> string
val required_law : structure -> string

(* Status of one obligation.

   There is no `Assumed` and no `Probably`. `Unknown` is a real state and it is
   NOT a passing one -- spec section 3's own evidence-refinement law says UNKNOWN
   never becomes PASS without new applicable evidence, so this type applies that
   law to the checker itself. *)
type obligation_status =
  | Holds
  | Not_applicable
  | Unknown
  | Violated

val status_name : obligation_status -> string

(* One structure's obligation on one capability row.

   `predicate` is what is claimed for THIS row. `falsifier` is the observation
   that would disprove it. A `Holds` with an empty falsifier is decoration, not
   evidence, and `check_obligation` rejects it. *)
type obligation = {
  structure : structure;
  status : obligation_status;
  (* A checkable predicate with bound variables, not prose. AGY's advisory
     (2026-09-09) named the failure this guards: adding nine prose fields per
     row makes `grep associativity` return 30 matches and leaves 0% of them
     falsifiable. The keyword passes; the property is untouched. *)
  predicate : string;
  falsifier : string;
  (* Where the claim is actually executed. A HOLDS without a named oracle is a
     assertion about the world with nothing in the repository that would
     notice if it stopped being true. *)
  oracle : string;
  (* Whether a human or tool actually established this, versus it being derived
     mechanically from the row's other declared fields. Template derivation is
     honest provenance, not a verdict, and may not accompany `Holds`. *)
  independently_reviewed : bool;
}

type finding = {
  row_id : string;
  detail : string;
}

type verdict =
  | Conforms
  | Nonconforming of finding list

(* Meet of the verdict semilattice. `Conforms` is the identity (top);
   `Nonconforming` absorbs and accumulates findings in order. *)
val meet : verdict -> verdict -> verdict
val meet_all : verdict list -> verdict
val findings : verdict -> finding list
val is_conforming : verdict -> bool

(* --- the laws, as checkable functions ----------------------------------- *)

(* An obligation is well formed when:
     - a `Holds` carries a non-empty predicate, falsifier AND oracle
     - a `Holds` is `independently_reviewed` (a template cannot assert a pass)
     - a `Violated` carries a non-empty predicate (say what was violated)
     - `Not_applicable` carries a non-empty predicate saying WHY it cannot apply
     - `Unknown` is always well formed; not knowing is permitted, claiming is not *)
val check_obligation : row_id:string -> obligation -> verdict

(* A row conforms when all nine structures appear exactly once and each
   obligation is well formed. Missing or duplicated structures are findings:
   a row cannot be complete by omission. *)
val check_row : row_id:string -> obligation list -> verdict

(* Degeneracy. `repeats` maps a field path to how many rows share its single
   most common value. A field whose most common value covers more than
   `max_repeat` rows is a finding, because at that point the field is a constant
   wearing a schema. `total_rows` is carried so the message can state the ratio
   rather than a bare count. *)
val check_degeneracy :
  total_rows:int -> max_repeat:int -> (string * int) list -> verdict

(* Monotonicity of degeneracy, exposed so the law suite can state it: adding a
   row that shares an existing value never lowers that field's repeat count.
   Returns the repeat count after the addition. *)
val repeat_after_adding_same : int -> int
