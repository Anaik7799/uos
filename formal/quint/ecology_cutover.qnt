// Independent finite policy abstraction. Not extracted native/Gleam code.
// 14/15 physical files; cooperative readers stay fenced across a writer crash.
// Grant, health, epoch and backup observations are assumed authentic inputs.
// Native directory durability, authentication, timing and liveness are outside
// this model. Seeded traces are not exhaustive exploration or system admission.
module ecology_cutover {
  type State = { count: int, pins: int -> str, phase: str, index: int,
    fenced: bool, alive: bool, prepared: bool, epoch: int, grant: bool,
    visible: str, verified: str, ceiling: int }
  var s: State
  pure val AllFiles = 0.to(14)
  pure def uniform(st: State, version: str): bool =
    0.to(st.count - 1).forall(i => st.pins.get(i) == version)
  pure def fresh(st: State, epoch: int): bool =
    st.alive and st.grant and st.epoch == epoch
  action initFor(count: int): bool = s' = {
    count: count, pins: AllFiles.mapBy(i => "old"), phase: "preparing",
    index: 0, fenced: false, alive: true, prepared: false, epoch: 1,
    grant: true, visible: "old", verified: "old", ceiling: 93 }
  action init = initFor(15)
  action init14 = initFor(14)
  action prepare(valid: bool, epoch: int): bool = s' =
    if (fresh(s, epoch) and s.phase == "preparing")
      s.with("phase", if (valid) "quiescing" else "held")
        .with("prepared", valid) else s
  action fence(epoch: int): bool = s' =
    if (fresh(s, epoch) and Set("quiescing", "recoveryFence").contains(s.phase))
      s.with("fenced", true)
        .with("index", if (s.phase == "recoveryFence") s.count - 1 else 0)
        .with("phase", if (s.phase == "recoveryFence") "restoring" else "replacing")
    else s
  action replace(i: int, epoch: int): bool = s' =
    if (fresh(s, epoch) and s.fenced and s.phase == "replacing" and i == s.index)
      if (s.pins.get(i) == "old")
        s.with("pins", s.pins.set(i, "new")).with("index", i + 1).with("verified", "")
          .with("phase", if (i + 1 == s.count) "checkingCandidate" else "replacing")
      else s.with("phase", "held")
    else s
  action checkCandidate(healthy: bool, epoch: int): bool = s' =
    if (fresh(s, epoch) and s.fenced and s.phase == "checkingCandidate")
      s.with("phase", if (healthy and uniform(s, "new")) "candidateReady" else "restoring")
        .with("verified", if (healthy and uniform(s, "new")) "new" else "")
        .with("index", s.count - 1)
    else s
  action beginRollback = s' =
    if (s.alive and s.fenced and Set("replacing", "checkingCandidate").contains(s.phase))
      s.with("phase", "restoring").with("index", s.count - 1) else s
  action restore(i: int, epoch: int): bool = s' =
    if (fresh(s, epoch) and s.fenced and s.prepared and s.phase == "restoring" and i == s.index)
      if (Set("old", "new").contains(s.pins.get(i)))
        s.with("pins", s.pins.set(i, "old")).with("index", i - 1).with("verified", "")
          .with("phase", if (i == 0) "checkingPrevious" else "restoring")
      else s.with("phase", "held")
    else s
  action checkPrevious(healthy: bool, epoch: int): bool = s' =
    if (fresh(s, epoch) and s.fenced and s.phase == "checkingPrevious")
      s.with("phase", if (healthy and uniform(s, "old")) "previousReady" else "held")
        .with("verified", if (healthy and uniform(s, "old")) "old" else "") else s
  action resume(epoch: int): bool = s' =
    if (fresh(s, epoch) and s.fenced and s.phase == "candidateReady" and s.verified == "new" and uniform(s, "new"))
      s.with("fenced", false).with("visible", "new").with("phase", "committed")
    else if (fresh(s, epoch) and s.fenced and s.phase == "previousReady" and s.verified == "old" and uniform(s, "old"))
      s.with("fenced", false).with("visible", "old").with("phase", "rolledBack")
    else s
  action crash = s' = if (Set("committed", "rolledBack").contains(s.phase)) s
    else s.with("alive", false)
  // A lost/failed resume acknowledgement can leave readers already running.
  // Reconciliation must fence them again before the first restoration.
  action failedResume = s' =
    if (s.alive and Set("candidateReady", "previousReady").contains(s.phase))
      s.with("fenced", false).with("phase", "held")
        .with("visible", if (s.phase == "candidateReady") "new" else "old") else s
  action recover(epoch: int): bool = s' =
    if (s.prepared and epoch > s.epoch and epoch <= 4 and
        not(Set("committed", "rolledBack").contains(s.phase)))
      s.with("alive", true).with("epoch", epoch).with("phase", "recoveryFence") else s
  action editUnexpected(i: int): bool = s' =
    if (s.fenced and not(Set("committed", "rolledBack").contains(s.phase)))
      s.with("pins", s.pins.set(i, "unknown")).with("phase", "held").with("verified", "") else s
  action grant(known: bool): bool = s' = s.with("grant", known)
  action step = {
    nondet i = oneOf(AllFiles)
    nondet epoch = oneOf(1.to(4))
    nondet good = oneOf(Set(true, false))
    any { prepare(good, epoch), fence(epoch), replace(i, epoch),
      checkCandidate(good, epoch), beginRollback, restore(i, epoch), checkPrevious(good, epoch),
      resume(epoch), failedResume, crash, recover(epoch), editUnexpected(i), grant(good) }
  }
  val invReaderVersionCoherence = s.fenced or uniform(s, s.visible)
  val invVisibleVersionHasHealthEvidence = s.fenced or s.verified == s.visible
  val invCeiling = s.ceiling == 93
  val invTerminalCoherent =
    (s.phase != "committed" or (not(s.fenced) and uniform(s, "new"))) and
    (s.phase != "rolledBack" or (not(s.fenced) and uniform(s, "old")))
  val invRecoveryHasBackups =
    not(Set("recoveryFence", "restoring", "checkingPrevious", "previousReady").contains(s.phase)) or s.prepared
  val invAll = invReaderVersionCoherence and invVisibleVersionHasHealthEvidence and invCeiling and invTerminalCoherent and invRecoveryHasBackups
  // This mutant is deliberately absent from step. It demonstrates that the
  // reader barrier is non-vacuous even with individually atomic replacements.
  action mutantResumeWithoutVerification = s' = s.with("fenced", false)
  action mutantUniformUnverifiedResume = s' = s.with("fenced", false).with("visible", "new")
  run partialCrashKeepsReadersFencedTest = init.then(prepare(true,1)).then(fence(1))
    .then(replace(0,1)).then(crash).expect(s.fenced and not(s.alive) and invAll)
  run staleEpochCannotReplaceTest = init.then(prepare(true,1)).then(fence(1))
    .then(replace(0,2)).expect(uniform(s,"old") and s.index == 0)
  run badPayloadDoesNotPublishTest = init.then(prepare(false,1))
    .then(fence(1)).then(replace(0,1)).expect(uniform(s,"old") and not(s.prepared))
  run unknownEditHoldsRecoveryTest = init.then(prepare(true,1)).then(fence(1))
    .then(editUnexpected(14)).then(recover(2)).then(fence(2)).then(restore(14,2))
    .expect(s.phase == "held" and s.fenced and s.pins.get(14) == "unknown")
  run crashRecoveryRequiresFreshFenceTest = init.then(prepare(true,1)).then(fence(1))
    .then(replace(0,1)).then(crash).then(recover(2)).then(restore(14,2))
    .expect(s.phase == "recoveryFence" and s.pins.get(0) == "new")
  run barrierMutantHasCounterexampleTest = init.then(prepare(true,1)).then(fence(1))
    .then(replace(0,1)).then(mutantResumeWithoutVerification)
    .expect(not(invReaderVersionCoherence))
  run allFourteenReachVerifiedCommitTest = initFor(14).then(prepare(true,1)).then(fence(1))
    .then(replace(0,1)).then(replace(1,1)).then(replace(2,1)).then(replace(3,1))
    .then(replace(4,1)).then(replace(5,1)).then(replace(6,1)).then(replace(7,1))
    .then(replace(8,1)).then(replace(9,1)).then(replace(10,1)).then(replace(11,1))
    .then(replace(12,1)).then(replace(13,1)).then(checkCandidate(true,1)).then(resume(1))
    .expect(s.phase == "committed" and invAll)
  run failedHealthRestoresAllFifteenTest = init.then(prepare(true,1)).then(fence(1))
    .then(replace(0,1)).then(replace(1,1)).then(replace(2,1)).then(replace(3,1))
    .then(replace(4,1)).then(replace(5,1)).then(replace(6,1)).then(replace(7,1))
    .then(replace(8,1)).then(replace(9,1)).then(replace(10,1)).then(replace(11,1))
    .then(replace(12,1)).then(replace(13,1)).then(replace(14,1)).then(checkCandidate(false,1))
    .then(restore(14,1)).then(restore(13,1)).then(restore(12,1)).then(restore(11,1))
    .then(restore(10,1)).then(restore(9,1)).then(restore(8,1)).then(restore(7,1))
    .then(restore(6,1)).then(restore(5,1)).then(restore(4,1)).then(restore(3,1))
    .then(restore(2,1)).then(restore(1,1)).then(restore(0,1))
    .then(checkPrevious(true,1)).then(resume(1)).expect(s.phase == "rolledBack" and invAll)
  run failedResumeRequiresNewFenceTest = initFor(14).then(prepare(true,1)).then(fence(1))
    .then(replace(0,1)).then(replace(1,1)).then(replace(2,1)).then(replace(3,1))
    .then(replace(4,1)).then(replace(5,1)).then(replace(6,1)).then(replace(7,1))
    .then(replace(8,1)).then(replace(9,1)).then(replace(10,1)).then(replace(11,1))
    .then(replace(12,1)).then(replace(13,1)).then(checkCandidate(true,1)).then(failedResume)
    .then(recover(2)).then(restore(13,2)).expect(s.phase == "recoveryFence" and uniform(s,"new") and invAll)
  run uniformUnverifiedMutantHasCounterexampleTest = init14.then(prepare(true,1)).then(fence(1))
    .then(replace(0,1)).then(replace(1,1)).then(replace(2,1)).then(replace(3,1))
    .then(replace(4,1)).then(replace(5,1)).then(replace(6,1)).then(replace(7,1))
    .then(replace(8,1)).then(replace(9,1)).then(replace(10,1)).then(replace(11,1))
    .then(replace(12,1)).then(replace(13,1)).then(mutantUniformUnverifiedResume)
    .expect(invReaderVersionCoherence and not(invVisibleVersionHasHealthEvidence))
}
