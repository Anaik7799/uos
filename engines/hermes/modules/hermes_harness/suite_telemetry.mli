(** The adapter every suite calls. R30 in one line of code.

    {1 The algebra}

    Let [t] be the carrier: a suite's observation of itself. Define

    {v
      ε  = empty                      the identity
      ⊕  = combine : t -> t -> t      composition of two observations
    v}

    Then [(t, ⊕, ε)] is a {b commutative monoid}:

    - {b associativity} [(a ⊕ b) ⊕ c = a ⊕ (b ⊕ c)]
    - {b identity} [ε ⊕ a = a = a ⊕ ε]
    - {b commutativity} [a ⊕ b = b ⊕ a]

    Commutativity is the load-bearing one: it makes a battery's total
    independent of the order suites happen to run in, which is what lets the
    engine schedule them across domains without changing the verdict. It holds
    because the counts are the free commutative monoid [(ℕ³, +)] and [⊕] is
    [+] componentwise; the suite name is the only non-numeric field and it
    degrades to a set union under composition.

    [total] is a monoid homomorphism into [(ℕ, +)]:
    [total (a ⊕ b) = total a + total b].

    {b Completeness is an antitone predicate.} [complete] is closed downward
    under [⊕]: if [complete (a ⊕ b)] then [complete a] and [complete b]. A
    skip anywhere poisons the whole, which is R22 — a skip is disclosed and
    never counted green — expressed as an order property rather than a habit.
    There is no way to compose your way out of an incomplete denominator.

    {1 The emission}

    Every suite emits both halves (R30). AS-IS is what it measured, with the
    denominator visible. PREDICTIVE is bounded by its reverse dependency cone,
    which is the honest limit of what a suite can foresee. *)

type t

val empty : t
(** [ε]. The observation of a suite that has not run: zero of everything. *)

val observe : suite:string -> passed:int -> failed:int -> skipped:int -> t
(** Clamps negatives to zero rather than propagating them: a negative count is
    a broken sensor, and a broken sensor must not be able to make a total look
    healthier by cancellation. *)

val combine : t -> t -> t
(** [⊕]. Associative, commutative, with [empty] as identity. *)

val concat : t list -> t
(** [List.fold_left combine empty]. Well-defined without a stated order
    precisely because [⊕] is commutative. *)

val total : t -> int
(** The homomorphism into [(ℕ, +)]. *)

val clean : t -> bool
(** [failed = 0 ∧ skipped = 0]. {b Antitone} under [⊕]: if [clean (a ⊕ b)]
    then [clean a] and [clean b], because each component is a sum of
    non-negatives and a zero sum forces zero parts. This is the R22 half — a
    skip anywhere poisons the whole, and there is no composing out of it. *)

val complete : t -> bool
(** [clean t ∧ passed t > 0].

    {b Not antitone}, and the distinction is not pedantry: [passed > 0] is
    MONOTONE, so [ε ⊕ a] can be complete while [ε] is not. An earlier draft of
    this interface claimed [complete] was antitone and a law test refuted it
    with exactly that counterexample. The antitone content lives in {!clean};
    [complete] adds a non-vacuity condition on top, and the two must not be
    conflated. *)

val exit_code : t -> int
(** [0] iff no failures. The battery judges by exit code alone (R19 cl. 4), so
    this is the only honest reduction of an observation to a verdict. *)

(** {1 Emission} *)

val as_is : t -> string
(** The measured half, denominator visible. The tag names the CAUSE:
    [FAILURES PRESENT] when failed > 0, [INCOMPLETE DENOMINATOR] when a skip
    makes the denominator unusable, [NO CHECKS RAN] when nothing was
    observed. A label that misattributes its cause is a small vacuity of its
    own — the first draft printed [INCOMPLETE DENOMINATOR] for a plain
    failure. Old text below.

    The measured half, denominator visible, marked [INCOMPLETE] when a skip
    makes the denominator unusable. *)

val predictive : t -> targets:Stanza.t list -> string
(** The implied half, bounded by the reverse dependency cone. States
    containment explicitly when the cone is empty: an unstated bound is one the
    reader assumes away. *)

val emit : t -> targets:Stanza.t list -> string
(** Both halves plus the one-line verdict, token-optimised: fixed width,
    no per-check output, and no growth in the number of checks. A suite with
    ten thousand assertions emits the same number of lines as one with three,
    which is the property that makes this affordable across ~192 suites. *)

val render_line : t -> string
(** The single-line form for a battery roll-up. *)
