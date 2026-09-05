(** A declarative, intent-based mechanism for configuring the harness and
    instructing it when it is reused to build new software.

    The model is desired-state reconciliation -- Pulumi and intent-based
    networking, mapped onto the fractal evidence model. A blueprint DECLARES the
    intended state (which fractal targets should reach which parity verdict, and
    WHY); the harness RECONCILES that intent against the actual state (the
    evidence roll-up), reporting each satisfied intent and each drift as a fractal
    diagnostic. It is closed-loop: as the candidate is built the drift shrinks,
    and re-reconciling converges. The declaration says WHAT and WHY, never HOW to
    execute -- the harness interprets it.

    Alignment (the user's requirement):
    - textual part = the OCaml comment above each directive (its rationale);
    - executable part = this typed OCaml data (the seed pattern, R14 -- mirrored
      from zigvm safety_seed/sdlc_seed and the harness's capability_catalog);
    - the fractal ALGEBRA is Parity_algebra: [desired]/[actual] are verdicts and
      drift is computed in that lattice;
    - the fractal ONTOLOGY/ATLAS is the [target] space: a target is an ontology
      component or capability node, so a blueprint composes over the same fractal
      the ontology describes;
    - a drift is a fractal DIAGNOSTIC (level + RCA origin), like every other
      harness finding.

    Checked like the ontology: an intent that says nothing, a duplicate id, a
    requirement that resolves to nothing, or a dependency cycle is a failing
    validation, not a silent gap. *)

type directive = {
  id : string;
  target : string;  (** a fractal target -- an ontology component or capability node *)
  desired : Parity_algebra.verdict;  (** the intended state, usually Verified *)
  intent : string;  (** the human "why", mirrored in the comment above it *)
  requires : string list;  (** directive ids that must be satisfied first *)
}

type t = directive list

type error =
  | Vacuous_intent of string
  | Duplicate_id of string
  | Unresolved_requirement of { directive : string; missing : string }
  | Unknown_target of { directive : string; target : string }
  | Cycle of string list

val describe_error : error -> string

val validate : ?resolve:(string -> bool) -> t -> (unit, error list) result
(** Every directive has substantive intent (> 20 chars) and a unique id, every
    [requires] resolves to a declared directive, and the [requires] graph is
    acyclic. When [resolve] is given (the ontology/catalog alignment check),
    every [target] must satisfy it or the directive fails with [Unknown_target]
    -- an intent about a node the fractal does not contain is a typo, not a
    plan. Returns every problem, not just the first. *)

val order : t -> (string list, error) result
(** Directive ids in dependency order -- each after all it [requires]. *)

(* -------------------------------------------------------- reconciliation *)

type outcome =
  | Satisfied
  | Drift of { desired : Parity_algebra.verdict; actual : Parity_algebra.verdict }

type reconciled = {
  directive : directive;
  outcome : outcome;
  diagnostic : Fractal_diagnostic.t option;  (** None when satisfied *)
}

val reconcile : t -> actual:(string -> Parity_algebra.verdict) -> reconciled list
(** Diff intent against reality: for each directive, [Satisfied] when the target's
    [actual] verdict equals the [desired] one, else [Drift] with a fractal
    diagnostic naming the shortfall (Implementation/Denies for a Divergent actual,
    Environment/Blocks for Blocked, Control/Blocks for an Unmapped intent with no
    evidence yet). Never grants credit -- it only reports the gap. *)

val converged : reconciled list -> bool
(** True when every directive is [Satisfied] -- the closed loop has settled. *)

val summary : reconciled list -> string
(** [n/m intents satisfied]. *)

val render : t -> string
