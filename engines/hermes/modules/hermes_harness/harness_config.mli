(** The declarative configuration grammar and activity algebra of the harness.

    This is the comprehensive mechanism for configuring and instructing the
    harness when it is reused to build new software. It has three parts, each
    mapped onto the existing fractal architecture:

    {b 1. The configuration GRAMMAR} — a typed OCaml AST ([activity]) built by
    combinators. Textual intent lives in OCaml comments above each declaration
    (and in the [why] annotations); the executable part is this OCaml DSL. The
    grammar, in BNF over the constructors:

    {v
      activity ::= Capture   of corpus          (* produce L4 fixtures        *)
                 | Compare   of corpus          (* produce L5/L6 evidence     *)
                 | Check_contracts               (* gospel L3 receipts         *)
                 | Check_determinism             (* GATE-DETERMINACY           *)
                 | Preflight of resources        (* R13 resource envelope      *)
                 | Reconcile of blueprint        (* intent drift (Terraform plan) *)
                 | Report                        (* dashboards / KPIs          *)
                 | Seq       of activity list    (* ordered composition        *)
                 | Par       of activity list    (* order-independent intent   *)
                 | Gate      of activity * activity  (* fail-closed: run B only if A converged *)
                 | Annotate  of why * activity   (* attach intent to a subtree *)
      corpus   ::= All | Slices of target list
      why      ::= string                        (* the human rationale *)
    v}

    {b 2. The activity ALGEBRA} — how outcomes compose. An activity's outcome is
    a {!Parity_algebra.verdict}; composition folds with the SAME semilattice join
    ([combine]) the evidence roll-up uses, so configuration composes exactly like
    evidence:

    - [Seq]/[Par] outcomes are the join of their children's outcomes
      (commutative, associative, idempotent; Divergent absorbs; identity is
      [Verified] over a non-empty list — an EMPTY composite is [Unmapped], the
      vacuous-truth guard, never a silent pass).
    - [Gate (a, b)]: if [a]'s outcome grants no credit, [b] does not run and the
      gate's outcome is [a]'s — fail-closed sequencing (the preflight discipline
      as an algebraic operator).
    - [Annotate] is outcome-transparent: intent never changes semantics.

    {b 3. The harness BEHAVIOUR} — the interpreter. [plan] is total and pure: it
    linearizes an activity into the primitive steps WITH their intent, executing
    nothing (the Terraform plan). [execute] runs each primitive against the real
    subsystem via a {!driver} record (dependency injection, so behaviour is
    testable without subprocesses — and the driver wired to the real harness maps
    Capture -> reference_capture, Compare -> parity_compare, Check_contracts ->
    gospel_check, Check_determinism -> determinism_verifier, Preflight ->
    resource_envelope, Reconcile -> Blueprint.reconcile, Report -> dashboards).
    Execution is fail-closed at every Gate, produces one outcome per primitive,
    and folds them in the algebra. Nothing here grants parity credit: only the
    L4-L6 evidence a Compare produces can move [actual] (R10).

    Fractal alignment: targets are ontology/atlas node names; outcomes are the
    fractal algebra's verdicts; every failure surfaces as a fractal diagnostic
    from the underlying subsystem. R14: the typed-command-then-dispatch shape
    mirrors the zigvm harness's mode variant; the seed pattern carries the data. *)

type target = string  (** a fractal ontology/atlas node, e.g. "hermes.model_routing.provider_transports" *)

type corpus = All | Slices of target list

type activity =
  | Capture of corpus
  | Compare of corpus
  | Check_contracts
  | Check_determinism
  | Preflight of Resource_envelope.resource list
  | Reconcile of Blueprint.t
  | Report
  | Seq of activity list
  | Par of activity list
  | Gate of activity * activity
  | Annotate of string * activity

(* ------------------------------------------------------------- the plan *)

type step = { action : string; why : string option }
(** One primitive in linear order, with the innermost enclosing intent. *)

val plan : activity -> step list
(** Total and pure: linearize the activity into primitive steps with intent,
    executing nothing. [Gate (a, b)] plans both arms (the plan shows what WOULD
    run); [Par] plans children in declaration order (order-independence is a
    property of outcomes, not of the listing). *)

(* -------------------------------------------------------------- execution *)

type driver = {
  capture : corpus -> Parity_algebra.verdict;
  compare : corpus -> Parity_algebra.verdict;
  check_contracts : unit -> Parity_algebra.verdict;
  check_determinism : unit -> Parity_algebra.verdict;
  preflight : Resource_envelope.resource list -> Parity_algebra.verdict;
  reconcile : Blueprint.t -> Parity_algebra.verdict;
  report : unit -> Parity_algebra.verdict;
}
(** The binding from primitives to the real subsystems (or to test doubles). *)

type outcome = { activity_label : string; verdict : Parity_algebra.verdict }

val execute : driver -> activity -> Parity_algebra.verdict * outcome list
(** Run the activity: each primitive through the driver, composites folded with
    {!Parity_algebra.combine} over a non-empty list ([Unmapped] when empty — the
    vacuous-truth guard), and [Gate (a, b)] running [b] only when [a]'s outcome
    grants credit. Returns the folded verdict and the per-primitive trail in
    execution order (a gated-out [b] contributes no outcomes — it did not run). *)

(* ---------------------------------------------------------------- algebra *)

val outcome_of_list : Parity_algebra.verdict list -> Parity_algebra.verdict
(** The composite fold: [Unmapped] on empty, else the semilattice join. Exposed
    so the laws are testable directly: commutative, associative, idempotent,
    Divergent absorbs, and the empty case never reads as success. The join
    itself is {!Parity_algebra.combine}, whose laws are z3-discharged over the
    real emitted table in [formal_specs]. *)

val gate_verdict :
  Parity_algebra.verdict -> (unit -> Parity_algebra.verdict) -> Parity_algebra.verdict
(** The Gate combinator, exposed pure so [formal_specs] can emit its table from
    the code under test: runs the thunk only when the condition grants credit,
    folding both; otherwise the condition's verdict stands and the thunk never
    runs (fail-closed). *)

val render_plan : step list -> string

(* ---------------------------------------------------- fractal-layer coverage *)

val levels_of : activity -> Fractal_ontology.level list
(** The fractal levels an activity's work lives at (deduplicated; composites are
    the union of their children): Capture -> L4/L5 (pinned fixtures, normalized
    digests); Compare -> L4/L5/L6 (loads fixtures, normalized comparison,
    receipts); Check_contracts -> L3; Check_determinism and Preflight -> LX (the
    control plane); Reconcile -> L0/L1/L2 (intent is declared over product,
    family and capability nodes); Report -> L0 (the product-level view).
    This makes fractal coverage of a configuration DATA, so "does this
    configuration exercise every level" is a test, not a hope. *)

val standard_pipeline :
  preflight:Resource_envelope.resource list -> blueprint:Blueprint.t -> activity
(** The harness's canonical read-only configuration: the resource preflight
    GATES [Compare All], then contracts, determinism and intent-reconciliation
    run as order-independent checks, and the report closes the loop. Covers
    every fractal level (a completeness test enforces it) and writes no
    evidence -- Capture stays a deliberate, explicit activity outside it. *)

val sysml_behavior_model : Hermes_sysml.Sysml_grammar.System.t
(** The SysML v2 formalization of this configuration behavior. *)
