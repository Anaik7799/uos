// The parity frontier as a Quint state machine — the SAME machine
// ruliad_frontier explores in OCaml (Parity_intent.blueprint), specified
// independently so `quint run` is a second, independent checker of its
// invariants. Differential discipline mirrored from the zigvm quint-sm laws:
// identical verdicts + reachable-signature agreement, bounded and seeded —
// bounded-checker equivalence, honestly, not full LTL.
module parity_frontier {
  // An intent becomes satisfied only when everything it requires already is.
  var satisfied: Set[str]

  val intents = Set("product", "routing_family", "transports", "budget", "paths",
                    "retry", "route", "anthropic")

  def requires(i: str): Set[str] =
    if (i == "product") Set("routing_family")
    else if (i == "routing_family") Set("transports", "retry", "route", "anthropic")
    else if (i == "retry") Set("transports")
    else if (i == "route") Set("transports")
    else if (i == "anthropic") Set("transports")
    else Set()

  val buildable = intents.filter(i => not(satisfied.contains(i)) and requires(i).subseteq(satisfied))

  action init = satisfied' = Set()

  // Build one enabled intent; once converged, stutter (no deadlock).
  action move = all {
    satisfied != intents,
    nondet i = oneOf(buildable)
    satisfied' = satisfied.union(Set(i))
  }
  action stutter = all { satisfied == intents, satisfied' = satisfied }
  action step = any { move, stutter }

  // INVARIANT (expect Holds): requires-closure — no intent is ever satisfied
  // before everything it requires. The OCaml side checks the same predicate
  // over the full reachable set.
  val reqClosed = intents.forall(i => satisfied.contains(i) implies requires(i).subseteq(satisfied))

  // FALSE invariant (expect Violated): the machine can converge, so "never
  // converged" must be refuted — this proves the checker actually checks
  // (the proven-not-differential trap applied to quint itself).
  val notConverged = satisfied != intents
}
