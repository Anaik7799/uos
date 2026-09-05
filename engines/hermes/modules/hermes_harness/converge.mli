(** Automatic convergence of configuration to intent — the closed loop of
    intent-based networking / Pulumi apply, made honest for this harness.

    Declare intent; the loop repeatedly runs the harness's step (execute the
    standard pipeline, record evidence, re-read the live roll-up) and
    re-reconciles until the satisfied-intent set stops growing — a Kleene
    fixpoint of a monotone function over the finite powerset lattice of intents.

    Three guarantees, formally grounded:
    - MONOTONE: within a run the candidate is fixed, so recording evidence only
      SATISFIES intents, never un-satisfies. A step that shrinks the satisfied
      set is a convergence ANOMALY (the apparatus misbehaved) and is reported,
      never hidden.
    - TERMINATING: the satisfied set is non-decreasing and bounded by the finite
      intent set, so the loop reaches a fixpoint in at most [|all_intents|]
      steps (plus a bounded [max_iterations] backstop).
    - CORRECT: the loop converges iff every intent is satisfied; otherwise it
      settles at a partial fixpoint whose residual drift is exactly the real
      candidate work R10 says the loop cannot fabricate.

    The lattice laws the reconcile rests on (roll_up / combine) are machine-
    checked in proofs/Parity_Lattice.v; this module adds the fixpoint iteration
    over them. *)

type outcome =
  | Converged of { iterations : int; satisfied : string list }
  | Settled of { iterations : int; satisfied : string list; drift : string list }
      (** a fixpoint below full satisfaction: [drift] is the residual work *)
  | Anomaly of { iteration : int; lost : string list }
      (** monotonicity violated: a step un-satisfied an intent (apparatus bug) *)

val converge :
  max_iterations:int ->
  all_intents:string list ->
  step:(string list -> string list) ->
  string list ->
  outcome
(** Iterate [step] from the initial satisfied set. Stops at [Converged] when the
    satisfied set covers [all_intents], [Settled] at a fixpoint below that,
    [Anomaly] the moment a step drops a previously-satisfied intent. Never
    exceeds [max_iterations]. *)

val trajectory :
  max_iterations:int -> step:(string list -> string list) -> string list -> string list list
(** The sequence of satisfied sets visited, for observation (deduped stops at the
    fixpoint). *)

val describe : outcome -> string
