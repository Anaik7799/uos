// 20261031: CODEX relay, M03_METHOD_COVERAGE; REPORT_ONLY, EV ceiling 93.
// Independent finite interleaving abstraction, not a translation/refinement of Lean.
// Fixed identities: two writer workers and one reviewer; five effect/receipt IDs.
// All non-free phases hold capacity. Dispatch collapses starting into running.
// One frozen day, fixed 250000 microUSD per reservation, hard 40-request limit.
// Five fresh IDs cannot exhaust 40; this bounds interleavings, not full budget traffic.
// Authentication/readback truth are assumed inputs, not cryptographic guarantees.
// No liveness, fairness, exhaustive-state or native implementation claim.
module agent_scale_control {
  type Message = { worker: int, effect: int, receipt: int,
    expectedGen: int, expectedEpoch: int, deadline: int, lease: int, grant: bool }
  type State = { phase: int -> str, active: int -> int,
    owner: int -> int, receipt: int -> int, runs: int -> int,
    seen: Set[int], consumed: Set[int], usedReceipts: Set[int],
    uncertain: Set[int], paid: int, target: int, draining: bool,
    generation: int, epoch: int, clock: int }
  var s: State
  var previous: State
  var message: Message
  var operation: str

  pure val workers = Set(0, 1, 2)
  pure val writerIds = Set(0, 1)
  pure val reviewerIds = Set(2)
  pure val effects = Set(0, 1, 2, 3, 4)
  pure val phases = Set("free", "reserved", "running", "uncertain", "draining")
  pure val initial: State = {
    phase: workers.mapBy(w => "free"), active: workers.mapBy(w => -1),
    owner: effects.mapBy(e => -1), receipt: effects.mapBy(e => -1),
    runs: effects.mapBy(e => 0), seen: Set(), consumed: Set(),
    usedReceipts: Set(), uncertain: Set(), paid: 0, target: 3, draining: false,
    generation: 0, epoch: 1, clock: 0
  }
  pure val placeholder: Message = { worker: 0, effect: 0, receipt: 0,
    expectedGen: 0, expectedEpoch: 1, deadline: 1, lease: 1, grant: true }
  pure def held(st: State): Set[int] = workers.filter(w => st.phase.get(w) != "free")
  pure def activeEffects(st: State): Set[int] = held(st).map(w => st.active.get(w))
  pure def fresh(st: State, m: Message): bool = and {
    m.grant, m.expectedGen == st.generation, m.expectedEpoch == st.epoch,
    st.clock < m.deadline, st.clock < m.lease
  }
  pure def canAdmit(st: State, m: Message): bool = and {
    fresh(st, m), not(st.draining), held(st).size() < st.target,
    st.phase.get(m.worker) == "free", not(st.seen.contains(m.effect)),
    not(st.usedReceipts.contains(m.receipt)), st.paid + 1 <= 40
  }
  pure def admit(st: State, m: Message): State =
    if (canAdmit(st, m))
      st.with("phase", st.phase.set(m.worker, "reserved"))
        .with("active", st.active.set(m.worker, m.effect))
        .with("owner", st.owner.set(m.effect, m.worker))
        .with("receipt", st.receipt.set(m.effect, m.receipt))
        .with("seen", st.seen.union(Set(m.effect)))
        .with("usedReceipts", st.usedReceipts.union(Set(m.receipt)))
        .with("paid", st.paid + 1)
    else st
  pure def canDispatch(st: State, m: Message): bool = and {
    fresh(st, m), not(st.draining), st.seen.contains(m.effect),
    st.owner.get(m.effect) == m.worker, st.receipt.get(m.effect) == m.receipt,
    st.phase.get(m.worker) == "reserved", st.active.get(m.worker) == m.effect,
    not(st.consumed.contains(m.effect))
  }
  pure def dispatch(st: State, m: Message): State =
    if (canDispatch(st, m))
      st.with("phase", st.phase.set(m.worker, "running"))
        .with("consumed", st.consumed.union(Set(m.effect)))
        .with("runs", st.runs.set(m.effect, st.runs.get(m.effect) + 1))
    else st
  pure def uncertain(st: State, w: int): State =
    if (st.phase.get(w) != "free")
      st.with("phase", st.phase.set(w, "uncertain"))
        .with("uncertain", st.uncertain.union(Set(st.active.get(w))))
    else st
  // This action's authoritative stopped readback is assumed current/effect-bound.
  pure def stopped(st: State, w: int, authoritative: bool): State =
    if (authoritative and st.phase.get(w) != "free")
      st.with("phase", st.phase.set(w, "free"))
        .with("active", st.active.set(w, -1))
        .with("uncertain", st.uncertain.exclude(Set(st.active.get(w))))
    else st
  pure def drain(st: State): State =
    if (st.generation < 3) st.with("draining", true).with("target", 0)
      .with("phase", workers.mapBy(w =>
        if (st.phase.get(w) == "free") "free" else "draining"))
      .with("generation", st.generation + 1)
    else st
  pure def setTarget(st: State, target: int): State =
    if (st.generation < 3) st.with("target", target).with("draining", target == 0)
      .with("generation", st.generation + 1)
    else st

  action init = all { s' = initial, previous' = initial,
    message' = placeholder, operation' = "init" }
  action admitMessage(m: Message): bool = all {
    previous' = s, s' = admit(s, m), message' = m, operation' = "admit"
  }
  action dispatchMessage(m: Message): bool = all {
    previous' = s, s' = dispatch(s, m), message' = m, operation' = "dispatch"
  }
  action becomeUncertain(w: int): bool = all {
    previous' = s, s' = uncertain(s, w), message' = message, operation' = "uncertain"
  }
  action readStopped(w: int, known: bool): bool = all {
    previous' = s, s' = stopped(s, w, known), message' = message,
    operation' = if (known) "stopped" else "unknown_readback"
  }
  action drainPool = all {
    previous' = s, s' = drain(s), message' = message, operation' = "drain"
  }
  action target(t: int): bool = all {
    previous' = s, s' = setTarget(s, t), message' = message, operation' = "target"
  }
  action advanceClock = all {
    previous' = s, s' = s.with("clock", if (s.clock < 4) s.clock + 1 else 4),
    message' = message, operation' = "tick"
  }
  action advanceEpoch = all {
    previous' = s, s' = s.with("epoch", if (s.epoch < 3) s.epoch + 1 else 3),
    message' = message, operation' = "epoch"
  }
  action idle = all { previous' = s, s' = s, message' = message, operation' = "idle" }
  action requests = {
    nondet w = oneOf(workers)
    nondet e = oneOf(effects)
    nondet r = oneOf(effects)
    nondet g = oneOf(Set(s.generation, s.generation - 1))
    nondet ep = oneOf(Set(s.epoch, s.epoch - 1))
    nondet d = oneOf(Set(s.clock, s.clock + 1))
    nondet l = oneOf(Set(s.clock, s.clock + 1))
    nondet auth = oneOf(Set(true, false))
    val m = {worker: w, effect: e, receipt: r, expectedGen: g,
      expectedEpoch: ep, deadline: d, lease: l, grant: auth}
    any { admitMessage(m), dispatchMessage(m) }
  }
  action step = any {
    requests, advanceClock, advanceEpoch, drainPool, idle,
    nondet t = oneOf(0.to(3)); target(t),
    nondet w = oneOf(workers); becomeUncertain(w),
    nondet w = oneOf(workers); nondet known = oneOf(Set(true, false)); readStopped(w, known)
  }

  val inv_capacity = and {
    held(s).size() <= 3, held(s).intersect(writerIds).size() <= 2,
    held(s).intersect(reviewerIds).size() <= 1,
    held(s).forall(w => phases.contains(s.phase.get(w))),
    activeEffects(s).size() == held(s).size()
  }
  val inv_subsets = and {
    s.seen.subseteq(effects), s.consumed.subseteq(s.seen),
    activeEffects(s).subseteq(s.seen), s.uncertain.subseteq(activeEffects(s)),
    s.usedReceipts == s.seen.map(e => s.receipt.get(e)),
    s.usedReceipts.size() == s.seen.size()
  }
  val inv_budget_no_repeat = and {
    s.paid == s.seen.size(), s.paid >= previous.paid, s.paid <= 40,
    effects.forall(e => s.runs.get(e) >= 0 and s.runs.get(e) <= 1),
    s.consumed == effects.filter(e => s.runs.get(e) == 1),
    previous.seen.subseteq(s.seen), previous.consumed.subseteq(s.consumed)
  }
  val inv_immutable_binding = previous.seen.forall(e => and {
    s.owner.get(e) == previous.owner.get(e), s.receipt.get(e) == previous.receipt.get(e)
  })
  val inv_effect_fences = and {
    operation == "dispatch" and s.runs != previous.runs implies canDispatch(previous, message),
    operation == "admit" and s.paid != previous.paid implies canAdmit(previous, message),
    operation == "admit" and previous.seen.contains(message.effect) implies s == previous,
    operation == "dispatch" and previous.draining implies s == previous,
    operation == "unknown_readback" implies s == previous
  }
  val inv_monotone_clock = and {
    s.clock >= previous.clock, s.generation >= previous.generation,
    s.epoch >= previous.epoch, s.target >= 0, s.target <= 3,
    operation == "target" and s != previous implies s.generation == previous.generation + 1,
    operation == "drain" and s != previous implies s.generation == previous.generation + 1
  }
  val inv_all = and { inv_capacity, inv_subsets, inv_budget_no_repeat,
    inv_immutable_binding, inv_effect_fences, inv_monotone_clock }
  // False control: an admitted effect must be reachable, otherwise positive
  // safety runs might have explored only stuttering/refusal states.
  val never_admitted = s.seen.size() == 0
  val witness_admitted = s.seen.size() > 0

  // A deliberately unsafe UNKNOWN-release transition is excluded from step.
  // It loses capacity while uncertain evidence remains. The checker must refute it.
  action badUnknownRelease(w: int): bool = all {
    s.phase.get(w) == "uncertain", previous' = s,
    s' = s.with("phase", s.phase.set(w, "free")).with("active", s.active.set(w, -1)),
    message' = message, operation' = "bad_unknown_release"
  }
  action step_bad_unknown_release = any {
    step, nondet w = oneOf(workers); badUnknownRelease(w)
  }

  // Deterministic acceptance/negative witnesses supplement low-probability
  // random message matches. They do not turn simulation into exhaustive checking.
  pure val writer1 = placeholder.with("worker", 1).with("effect", 1).with("receipt", 1)
  pure val reviewer = placeholder.with("worker", 2).with("effect", 2).with("receipt", 2)
  run threeWorkersTest = init.then(admitMessage(placeholder)).then(admitMessage(writer1))
    .then(admitMessage(reviewer)).expect(held(s).size() == 3 and s.paid == 3 and inv_all)
  run consumedOnceTest = init.then(admitMessage(placeholder)).then(dispatchMessage(placeholder))
    .then(dispatchMessage(placeholder)).expect(s.runs.get(0) == 1 and s.consumed == Set(0) and inv_all)
  run uncertainUnknownTest = init.then(admitMessage(placeholder)).then(dispatchMessage(placeholder))
    .then(becomeUncertain(0)).then(readStopped(0, false))
    .expect(held(s).size() == 1 and s.uncertain == Set(0) and inv_all)
  run tombstoneNoRefundTest = init.then(admitMessage(placeholder)).then(dispatchMessage(placeholder))
    .then(becomeUncertain(0)).then(readStopped(0, true)).then(admitMessage(placeholder))
    .then(admitMessage(writer1.with("receipt", 0)))
    .expect(held(s).size() == 0 and s.paid == 1 and s.seen == Set(0) and s.consumed == Set(0) and inv_all)
  run strictDeadlineTest = init.then(admitMessage(placeholder.with("deadline", 0)))
    .expect(s == initial and inv_all)
  run strictLeaseTest = init.then(admitMessage(placeholder.with("lease", 0)))
    .expect(s == initial and inv_all)
  run staleGenerationTest = init.then(target(2)).then(admitMessage(placeholder))
    .expect(s.paid == 0 and held(s).size() == 0 and inv_all)
  run staleEpochTest = init.then(advanceEpoch).then(admitMessage(placeholder))
    .expect(s.paid == 0 and held(s).size() == 0 and inv_all)
  run drainNoDispatchTest = init.then(admitMessage(placeholder)).then(drainPool)
    .then(dispatchMessage(placeholder.with("expectedGen", 1)))
    .expect(s.runs.get(0) == 0 and held(s).size() == 1 and s.draining and inv_all)
}
