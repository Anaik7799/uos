// Independent finite temporal reference for delayed three-tender observations.
// Candidate, boot, run and clock are finite abstract identities; Lean carries
// detailed per-receipt profile predicates. No cryptography or OS behavior is
// modeled. Normal actions are serialized observation-store transitions.
module mirage_receipt_admission {
  type Stamp = { candidate: int, boot: int, invocation: int, at: int, active: bool, good: bool }
  type State = { candidate: int, boot: int, invocation: int, clock: int,
                 pending: int -> Stamp, receipts: int -> Stamp, admitted: bool }
  val Targets = Set(0, 1, 2) // HVT, SPT, virtio: every target is required.
  var s: State

  pure val blank = { candidate: 0, boot: 0, invocation: 0, at: 0, active: false, good: false }
  pure def captured(c: int, b: int, r: int, at: int): Stamp =
    { candidate: c, boot: b, invocation: r, at: at, active: true, good: true }
  val initial = { candidate: 1, boot: 1, invocation: 1, clock: 0,
    pending: Targets.mapBy(_ => blank), receipts: Targets.mapBy(_ => blank), admitted: false }

  pure def usable(st: State, receipt: Stamp): bool = and {
    receipt.active, receipt.good, receipt.candidate == st.candidate,
    receipt.boot == st.boot, receipt.invocation == st.invocation,
    receipt.at <= st.clock, st.clock - receipt.at <= 1
  }
  pure def ready(st: State): bool = Targets.forall(t => usable(st, st.receipts.get(t)))

  action init = s' = initial
  action launch(t: int): bool = s' = s
    .with("pending", s.pending.set(t, captured(s.candidate, s.boot, s.invocation, s.clock)))
    .with("admitted", false)
  action complete(t: int, good: bool): bool = s' =
    if (s.pending.get(t).active)
      s.with("receipts", s.receipts.set(t, s.pending.get(t).with("good", good)))
       .with("pending", s.pending.set(t, blank)).with("admitted", false)
    else s
  action nominate(candidate: int): bool = s' = s.with("candidate", candidate).with("admitted", false)
  action reboot(boot: int): bool = s' = s.with("boot", boot).with("admitted", false)
  action newRun(invocation: int): bool = s' = s.with("invocation", invocation).with("admitted", false)
  action tick = s' = if (s.clock < 4) s.with("clock", s.clock + 1).with("admitted", false) else s
  action admit = s' = s.with("admitted", ready(s))

  action step = any {
    admit, tick,
    nondet t = oneOf(Targets); launch(t),
    nondet t = oneOf(Targets); nondet good = oneOf(Set(false, true)); complete(t, good),
    nondet c = oneOf(Set(1, 2)); nominate(c),
    nondet b = oneOf(Set(1, 2)); reboot(b),
    nondet r = oneOf(Set(1, 2)); newRun(r)
  }

  val inv_current_complete_fresh = s.admitted implies ready(s)
  val witness_verified = s.admitted
  val false_control_never_verified = not(s.admitted)

  run goodLifecycleTest = init.then(launch(0)).then(launch(1)).then(launch(2))
    .then(complete(2, true)).then(complete(0, true)).then(complete(1, true)).then(admit)
    .expect(s.admitted and inv_current_complete_fresh)
  run delayedCandidateTest = init.then(launch(0)).then(launch(1)).then(launch(2))
    .then(nominate(2)).then(complete(0, true)).then(complete(2, true))
    .then(complete(1, true)).then(admit).expect(not(s.admitted) and inv_current_complete_fresh)
  run delayedRebootTest = init.then(launch(0)).then(launch(1)).then(launch(2))
    .then(reboot(2)).then(complete(0, true)).then(complete(1, true))
    .then(complete(2, true)).then(admit).expect(not(s.admitted) and inv_current_complete_fresh)
  run delayedRunTest = init.then(launch(0)).then(launch(1)).then(launch(2))
    .then(newRun(2)).then(complete(0, true)).then(complete(1, true))
    .then(complete(2, true)).then(admit).expect(not(s.admitted) and inv_current_complete_fresh)
  run staleObservationTest = init.then(launch(0)).then(launch(1)).then(launch(2))
    .then(tick).then(tick).then(complete(0, true)).then(complete(1, true))
    .then(complete(2, true)).then(admit).expect(not(s.admitted) and inv_current_complete_fresh)
  run missingVirtioTest = init.then(launch(0)).then(launch(1))
    .then(complete(0, true)).then(complete(1, true)).then(admit)
    .expect(not(s.admitted) and inv_current_complete_fresh)
  run failedTargetTest = init.then(launch(0)).then(launch(1)).then(launch(2))
    .then(complete(0, true)).then(complete(1, true)).then(complete(2, false)).then(admit)
    .expect(not(s.admitted) and inv_current_complete_fresh)

  // Fixed successful initializer and two unsafe transitions are controls only;
  // neither mutant is reachable through the normal step relation above.
  action validInit = s' = initial.with("receipts",
    Targets.mapBy(_ => captured(1, 1, 1, 0))).with("admitted", true)
  action stickyTickMutant = s' = s.with("clock", 2)
  action omittedTargetMutant = s' = s.with("receipts", s.receipts.set(2, blank))
}
