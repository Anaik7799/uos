// UOS tri-agent coordination reference model, 2026-09-07.
// One protected resource per instance; evidence IDs abstract authenticated
// receipts. Atomic transitions assume a serialized authoritative journal.
// Bounded seeded simulation is not exhaustive verification, implementation
// refinement, cryptographic validation, a liveness proof, or system admission.
module agentic_coordination {
  const Budget: int
  const MaxEpoch: int
  const MaxClock: int
  const Resource: str

  type Packet = { aspect: int, source: int, runtime: int, formal: int,
                  runtimeKey: int, formalKey: int, runtimePass: bool, formalPass: bool }
  type State = { candidate: int, packets: int -> Packet, admitted: bool,
    clock: int, epoch: int, owner: int, expires: int, authority: Set[int],
    reserved: int, settled: int, effects: int, observations: int,
    lastActor: int, lastEpoch: int, lastRevision: int, lastResource: str }

  val Aspects = 1.to(17)
  val Agents = Set(1, 2, 3) // Claude, Codex, AGY, respectively.
  val Revisions = Set(1, 2, 3)
  var s: State
  var previous: State

  pure def packet(a: int, c: int): Packet = {
    aspect: a, source: c, runtime: c, formal: c,
    runtimeKey: 2 * a - 1, formalKey: 2 * a,
    runtimePass: true, formalPass: true
  }

  def ready(st: State): bool = and {
    Aspects.forall(a => {
      val p = st.packets.get(a)
      and { p.aspect == a, p.source == st.candidate,
        p.runtime == st.candidate, p.formal == st.candidate,
        p.runtimeKey > 0, p.formalKey > 0, p.runtimePass, p.formalPass }
    }),
    Aspects.forall(a => Aspects.forall(b => and {
      st.packets.get(a).runtimeKey == st.packets.get(b).runtimeKey implies a == b,
      st.packets.get(a).formalKey == st.packets.get(b).formalKey implies a == b,
      st.packets.get(a).runtimeKey != st.packets.get(b).formalKey
    }))
  }

  def canApply(st: State, r: str, a: int, e: int, c: int): bool = and {
    r == Resource, st.authority.contains(a), st.admitted,
    c == st.candidate, e == st.epoch, st.owner == a,
    st.clock < st.expires, st.effects < 4
  }

  def initial: State = {
    candidate: 1,
    packets: Aspects.mapBy(a => packet(a, 0).with("runtimePass", false).with("formalPass", false)),
    admitted: false, clock: 0, epoch: 0, owner: 0, expires: 0,
    authority: Set(1, 2), reserved: 0, settled: 0, effects: 0, observations: 0,
    lastActor: 0, lastEpoch: 0, lastRevision: 0, lastResource: "none"
  }

  action init = all { s' = initial, previous' = initial }
  action move(proposed: State): bool = all { previous' = s, s' = proposed }

  action freshEvidence = move(s.with("packets", Aspects.mapBy(a => packet(a, s.candidate))).with("admitted", false))
  action submit(a: int, p: Packet): bool =
    move(s.with("packets", s.packets.set(a, p)).with("admitted", false))
  action nominate(c: int): bool = move(s.with("candidate", c).with("admitted", false))
  action admit = move(if (ready(s)) s.with("admitted", true) else s)
  action claim(a: int): bool = move(
    if (s.epoch < MaxEpoch and (s.owner == 0 or s.expires <= s.clock))
      s.with("owner", a).with("epoch", s.epoch + 1).with("expires", s.clock + 2)
    else s)
  action release(a: int, e: int): bool =
    move(if (s.owner == a and s.epoch == e) s.with("owner", 0) else s)
  action clockTick = move(if (s.clock < MaxClock) s.with("clock", s.clock + 1) else s)
  action reserve(n: int): bool = move(
    if (n >= 0 and s.reserved + n + s.settled <= Budget)
      s.with("reserved", s.reserved + n) else s)
  action settle(n: int): bool = move(
    if (n >= 0 and n <= s.reserved)
      s.with("reserved", s.reserved - n).with("settled", s.settled + n) else s)
  // Applies to an adapter only after this gate. The concrete adapter is not modeled.
  action apply(r: str, a: int, e: int, c: int): bool = move(
    if (canApply(s, r, a, e, c))
      s.with("effects", s.effects + 1).with("lastActor", a)
       .with("lastEpoch", e).with("lastRevision", c).with("lastResource", r)
    else s)
  // Message ACK, advice, prompt, and model output share this non-authority path.
  action observation = move(s.with("observations", (s.observations + 1) % 5))

  action step = any {
    freshEvidence, admit, clockTick, observation,
    nondet a = oneOf(Aspects); nondet c = oneOf(Revisions); submit(a, packet(a, c)),
    nondet a = oneOf(Aspects); submit(a, packet(a, s.candidate).with("runtimeKey", 2)),
    nondet c = oneOf(Revisions); nominate(c),
    nondet a = oneOf(Agents); claim(a),
    nondet a = oneOf(Agents); nondet e = oneOf(0.to(MaxEpoch)); release(a, e),
    nondet n = oneOf(0.to(Budget + 1)); reserve(n),
    nondet n = oneOf(0.to(Budget + 1)); settle(n),
    nondet a = oneOf(Agents); nondet e = oneOf(0.to(MaxEpoch));
      nondet c = oneOf(Revisions); nondet r = oneOf(Set(Resource, "wrong-resource")); apply(r, a, e, c)
  }

  val inv_all17_candidate_keys = s.admitted implies ready(s)
  val inv_budget = s.reserved >= 0 and s.settled >= 0 and s.reserved + s.settled <= Budget
  val inv_epoch_monotone = previous.epoch <= s.epoch
  val inv_single_owner = Agents.union(Set(0)).contains(s.owner)
  val inv_authority = s.authority == Set(1, 2)
  val inv_effect_gate = s.effects > previous.effects implies
    (ready(previous) and canApply(previous, s.lastResource, s.lastActor, s.lastEpoch, s.lastRevision))
  val inv_observations_do_not_authorize = s.observations != previous.observations implies and {
    s.owner == previous.owner, s.epoch == previous.epoch,
    s.admitted == previous.admitted, s.effects == previous.effects,
    s.authority == previous.authority, s.packets == previous.packets
  }
  val inv_all = and { inv_all17_candidate_keys, inv_budget, inv_epoch_monotone,
    inv_single_owner, inv_authority, inv_effect_gate, inv_observations_do_not_authorize }

  // Witnesses prevent a vacuous green caused by disabled successful transitions.
  val witness_admitted = s.admitted
  val witness_effect = s.effects > 0
  val witness_reacquired = s.epoch > 1
  val witness_spent = s.settled > 0
  val prop_no_effect = s.effects == 0 // Deliberately false control.

  run validLifecycleTest = init.then(freshEvidence).then(admit).then(claim(2))
    .then(reserve(3)).then(apply(Resource, 2, 1, 1)).then(settle(3))
    .expect(s.effects == 1 and s.settled == 3 and inv_all)
  run staleFenceTest = init.then(freshEvidence).then(admit).then(claim(2))
    .then(release(2, 1)).then(claim(2)).then(apply(Resource, 2, 1, 1))
    .expect(s.effects == 0 and s.epoch == 2 and inv_all)
  run expiredFenceTest = init.then(freshEvidence).then(admit).then(claim(2))
    .then(clockTick).then(clockTick).then(apply(Resource, 2, 1, 1))
    .expect(s.effects == 0 and inv_all)
  run wrongResourceTest = init.then(freshEvidence).then(admit).then(claim(2))
    .then(apply("wrong-resource", 2, 1, 1)).expect(s.effects == 0 and inv_all)
  run staleRevisionTest = init.then(freshEvidence).then(admit).then(claim(2))
    .then(nominate(2)).then(admit).then(apply(Resource, 2, 1, 2))
    .expect(not(s.admitted) and s.effects == 0 and inv_all)
  run missingAspectTest = init.then(submit(1, packet(1, 1))).then(admit)
    .expect(not(s.admitted) and inv_all)
  run duplicateKeyTest = init.then(freshEvidence)
    .then(submit(17, packet(17, 1).with("runtimeKey", 2))).then(admit)
    .expect(not(s.admitted) and inv_all)
  run observationOnlyTest = init.then(observation).then(observation).then(claim(3))
    .then(apply(Resource, 3, 1, 1)).expect(s.effects == 0 and inv_all)
  run overspendTest = init.then(reserve(Budget)).then(reserve(1)).then(settle(Budget))
    .then(reserve(1)).expect(s.settled == Budget and s.reserved == 0 and inv_all)

  // Two controlled mutants, intentionally NOT reachable from normal step.
  action mutantUnfencedApply = move(s.with("effects", s.effects + 1)
    .with("lastActor", 2).with("lastEpoch", 0).with("lastRevision", 1).with("lastResource", Resource))
  action mutantOverspend = move(s.with("reserved", Budget + 1))
  action mutantFenceStep = mutantUnfencedApply
  action mutantBudgetStep = mutantOverspend
}

module agentic_coordination_test {
  import agentic_coordination(Budget = 6, MaxEpoch = 4, MaxClock = 8, Resource = "integration/main").*
}

module agentic_coordination_runtime_test {
  import agentic_coordination(Budget = 6, MaxEpoch = 4, MaxClock = 8, Resource = "runtime/service").*
}
