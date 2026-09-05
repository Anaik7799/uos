(** Multiway-system exploration — the ruliad lens on the harness, made concrete.

    A slice of the ruliad here is a MOVE SYSTEM: an initial state, the moves
    applicable in a state, and their application. [explore] builds the full
    multiway graph to a fixpoint -- every state reachable under every ordering --
    mirroring the zigvm [sm_reachable] BFS-and-signature discipline (R14), with
    the HashLife lesson applied: states are MEMOIZED by canonical key, so the
    factorial space of paths collapses onto the (usually exponential-or-smaller)
    lattice of distinct states.

    What the concepts mean HERE, attached to real structures:
    - CAUSAL INVARIANCE is confluence: every maximal path reaches the same
      terminal state. For the configuration algebra this is a theorem (the
      z3-discharged join laws); [explore] verifies it exhaustively for concrete
      systems, and the chaos tests prove the detector can FAIL (a non-commutative
      move system is reported non-confluent, never papered over).
    - MULTIWAY BRANCHING is the decision space: the parity frontier's valid
      build orders under the blueprint's [requires] DAG. Path counts are the
      number of distinct plans; the first moves are today's real options.
    - COMPUTATIONAL IRREDUCIBILITY is R10: exploration enumerates the ORDER of
      work, but each edge's cost is running the differential evidence, which no
      formula shortcuts. Exploration is bounded and says so ([Error] when the
      state cap is hit) -- bounded exploration, honestly, not omniscience.

    NO AUTHORITY: exploration annotates decisions; verdicts and evidence remain
    the sole authority. *)

type ('state, 'move) system = {
  initial : 'state;
  moves : 'state -> 'move list;      (** applicable moves; [] = terminal *)
  apply : 'state -> 'move -> 'state;
  canonical : 'state -> string;      (** the memoization key (the HashLife lesson) *)
}

type 'state graph = {
  state_count : int;        (** distinct canonical states reached *)
  edge_count : int;         (** distinct (state, move-result) transitions *)
  terminals : 'state list;  (** canonically-distinct terminal states *)
  reachable : 'state list;  (** every distinct reachable state -- the signature
                                the quint differential compares against *)
  confluent : bool;         (** exactly one terminal -- causal invariance holds *)
  path_count : int;         (** distinct maximal move sequences (exact, via DP) *)
  max_depth : int;
}

val explore : ?max_states:int -> ('state, 'move) system -> ('state graph, string) result
(** BFS to fixpoint over memoized states (default cap 100_000). [Error] on a cap
    hit or on a cyclic system (a state reachable from itself would make the path
    DP diverge; the move systems this harness explores are monotone). *)
