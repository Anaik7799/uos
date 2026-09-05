(** Bayesian state classification over expect/parity evidence, with a
    Rete-shaped assessment pipeline.

    This emits a posterior IN ADDITION to the standard logs. It never replaces
    them: R22 requires a failing suite to print its bytes in full, first, and a
    compressed judgement about a failure is not the failure.

    {1 The boundary}

    No value produced here may move a parity verdict. R10 grants parity only on
    L4-L6 differential evidence and R5 lets only an Implementation origin deny
    it; a posterior is neither. These numbers rank triage, choose the next
    mutation batch, and compress a report. They are inadmissible as credit. *)

(** {1 Fractal ontology} *)

type state =
  | Stable            (** no change of consequence *)
  | Silent_divergence (** the execution path changed and the output did not *)
  | Structural_drift  (** path and output both moved; shape, not necessarily meaning *)
  | Regressed         (** the output changed *)

val states : state list
(** All four, in a fixed order. Exhaustive: the classifier's support. *)

val state_name : state -> string

(** {1 Evidence} *)

type evidence = {
  site : string;           (** the test site or scenario this concerns *)
  cause : string;          (** attribution fingerprint — the beta-join key *)
  path_changed : bool;
  output_changed : bool;
  churn : float;           (** historical volatility of the owning unit, 0.0-1.0 *)
  mutation_kill_rate : float;  (** discriminating power, 0.0-1.0, from [ops mutate] *)
}

val likelihood : state -> evidence -> float
(** [P(E | S)] over the four-point evidence space. For each state the four
    likelihoods sum to 1, which is what makes this a distribution rather than
    four unrelated weights; [test_expect_posterior] checks it exhaustively. *)

(** {1 Bayesian update} *)

type posterior = {
  distribution : (state * float) list;  (** sums to 1 *)
  argmax : state;
  confidence : float;      (** the winning mass *)
  marginal : float;        (** P(E) — the normalizing constant *)
  surprisal : float;       (** -log2 P(E); high means the evidence was unexpected *)
}

val update : prior:(state * float) list -> evidence -> (posterior, string) result
(** Bayes with the normalizing constant, so the result is a probability and the
    states are comparable. Refuses, rather than defaulting, when the prior is
    not a distribution over exactly {!states} or the marginal is zero — R19
    clause 2: a value the tool cannot determine is a refusal, never a default
    that reads as healthy.

    [argmax] is derived from the posterior. It is deliberately NOT a hardcoded
    rule over [path_changed]/[output_changed]: a classifier whose answer does
    not depend on its own arithmetic is decoration. *)

val uniform_prior : (state * float) list
(** The honest default when nothing is known. Seeding a prior from flake history
    is a caller's policy choice and a hazardous one — it discounts the failures
    of exactly the suites that most need fixing. *)

val severity : state -> float
(** The cost of being in a state undetected. Silent divergence is highest: the
    capture is blind to it, where a regression at least announces itself. *)

val priority : posterior -> float
(** [severity argmax * surprisal] — the specification's severity x rarity.

    Surprisal alone is the wrong queue and a failing test established it: under
    a uniform prior a path-only observation is BETTER explained (silent
    divergence assigns it 0.90) than a no-change one, so it carries LESS
    surprisal. Correct information theory, useless as a work order. *)

(** {1 Rete-shaped assessment} *)

type cluster = {
  cause_key : string;
  members : evidence list;
  representative : posterior;
}

val join : (evidence * posterior) list -> cluster list
(** Beta network. Correlates independent sites sharing a cause fingerprint into
    one semantic fact, so N redundant failures cost one line instead of N. The
    representative is the member with the highest surprisal. *)

type triage = {
  emitted : cluster list;      (** ranked by surprisal, descending *)
  withheld : cluster list;     (** filtered out — DISCLOSED, never dropped *)
  withheld_reason : string;
}

val alpha : ?min_kill_rate:float -> cluster list -> triage
(** Alpha network. Partitions by discriminating power rather than deleting:
    a cluster whose mutation kill rate is below the floor is withheld from the
    dense payload and reported as withheld.

    It is NOT discarded. A site that survives mutation is the most informative
    row in the report — [ops_mutate] already holds that a survivor is a finding,
    and that classifying one automatically would launder a weak test into an
    equivalent mutant. Silent deletion here would do exactly that. *)

type budget = {
  clusters_emitted : int;
  clusters_withheld : int;
  sites_covered : int;
  bytes_rendered : int;
}

val render : triage -> string * budget
(** The additional block, and the budget vector describing it. Deterministic:
    no clock, no ordering dependence, no identity — the same input renders the
    same bytes, which is what makes it safe to diff. *)

(** {1 Negative space — class 3}

    What did NOT happen. Usually outranks the evidence: a site that never ran
    tells you more than a hundred that passed. *)

type negative_space = {
  never_executed : string list;   (** sites present but not run *)
  uncovered_units : string list;  (** code units no site touches *)
  raised : string list;           (** sites that threw instead of comparing *)
  non_discriminating : string list; (** sites that survive every mutant *)
}

val negative_space_empty : negative_space

(** {1 Oracle state — class 7}

    An invariant that held for no reason reads as safety and provides none.
    This is the same disease as a vacuous snapshot, one level up. *)

type oracle = { invariant : string; margin : float; vacuous : bool }

(** {1 The report} *)

type report = {
  triage : triage;
  negative : negative_space;
  oracles : oracle list;
  budget_vector : budget;
  next_measurement : string;
}

val assess :
  ?min_kill_rate:float ->
  ?max_clusters:int ->
  negative:negative_space ->
  oracles:oracle list ->
  (evidence * posterior) list ->
  report
(** The three density rules, applied in the stated order: cluster by cause,
    rank by surprisal, truncate by budget. Truncation is disclosed in the
    budget vector, never silent. *)

val render_report : report -> string
(** The additional block. Ends with one recommended next measurement rather
    than a summary — a summary restates what was just printed, a measurement
    tells the next cycle what to do. *)

val recommend : triage -> negative_space -> oracle list -> string
(** Derived, never invented: silent divergence outranks a vacuous oracle, which
    outranks unexecuted negative space, which outranks a clean board. *)

(** {1 The gate — a posterior that only prints is a prettier log}

    Both external reviews landed on this, and one believed its own argument:
    "an agent can and frequently will hallucinate past high-surprisal warnings
    unless the Bayesian output strictly conditions a deterministic state machine
    or execution gate." So the posterior conditions a DETERMINISTIC decision.

    The input is probabilistic; the decision is not. And it can only ever
    BLOCK: the classifier is the harness's own bookkeeping, so under R5 it may
    withhold credit and may never deny it — a candidate is never wrong because
    we classified it. *)

type verdict =
  | Proceed
  | Blocked_pending_measurement of { reason : string; measurement : string }

val gate : ?confidence_floor:float -> report -> verdict
(** Blocks when a silent-divergence cluster clears the floor: the path moved,
    the output did not, and the capture is therefore blind to a real change.
    Deterministic in the report — same report, same verdict, always. *)

val verdict_name : verdict -> string

(** {1 Calibration — or stop claiming precision}

    Both reviews independently named the same limit: the likelihood constants
    are hand-authored point estimates, and exact surprisal computed on top of
    subjective numbers is false precision. Row-sum tests prove the table is a
    distribution; nothing proves it is the RIGHT one.

    This scores predictions against realized outcomes so the gap is measured
    rather than assumed. Until the score exists, the confidence figure is
    decoration and should be read as an ordinal rank. *)

type sample = { predicted : posterior; realized : state }

type calibration = {
  samples : int;
  brier : float;      (** 0 is perfect; a uniform guess over 4 states is 0.75 *)
  log_loss : float;   (** in bits; a uniform guess over 4 states is 2.0 *)
  accuracy : float;   (** argmax agreement, the crude comparison *)
  beats_uniform : bool;
}

val calibrate : sample list -> (calibration, string) result
(** Refuses an empty sample rather than reporting a perfect score over nothing —
    the same anti-vacuity rule [Parity_algebra.roll_up] applies one level down.

    [beats_uniform] is the claim that matters: if the classifier does not beat
    an uninformed guess, its arithmetic is ceremony and the honest move is to
    report ordinal ranks and stop printing confidences. *)

val render_calibration : calibration -> string
