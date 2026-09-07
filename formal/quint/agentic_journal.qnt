// UOS C07 bounded durable-journal refinement, 2026-09-07.
// Structural source correspondence only (no differential interpreter proof):
// candidate 1c69804b45f13af549f0070a711ed089cee8a418
//   apps/uos_swarm/src/uos_swarm/session_sync.gleam
//   apps/uos_swarm/src/session_sync_ffi.erl
//
// Evidence values: 0 clean, 1 pending, 2 torn. Outcome values: 1 accepted,
// 2 replayed, -1 conflicting duplicate, -2 bad evidence, -3 busy.
// A bounded seeded run is not exhaustive and does not prove filesystem or
// power-loss durability, digest/IAM security, production action isolation,
// completeness of a decision summary/rationale, or concrete refinement.
module agentic_journal {
  const MaxSequence: int
  const MaxEpoch: int

  type State = {
    sequence: int,
    epochs: str -> int,
    owners: str -> int,
    seenBodies: int -> int,
    evidence: int,
    acknowledgements: int,
    effects: int,
    policyRevision: int,
    candidateRevision: int,
    authorizedActors: Set[int],
    reservedActor: int,
    reservedResource: str,
    reservedAttempt: int,
    decisionPresent: bool,
    decisionActor: int,
    decisionResource: str,
    decisionEpoch: int,
    decisionCandidate: int,
    decisionAttempt: int,
    decisionTask: int,
    decisionAction: int,
    lastKind: int,
    lastOutcome: int,
    lastOperation: int,
    lastBody: int,
    lastActor: int,
    lastResource: str,
    lastEpoch: int,
    lastAttempt: int,
    lastTask: int,
    lastAction: int
  }

  val Sessions = Set(1, 2, 3) // Claude, Codex, AGY.
  val Resources = Set("integration/main", "runtime:alpha", "runtime:beta")
  val Operations = 1.to(4)
  val Bodies = 1.to(3)

  var s: State
  var previous: State

  def initial: State = {
    sequence: 0,
    epochs: Resources.mapBy(_ => 0),
    owners: Resources.mapBy(_ => 0),
    seenBodies: Operations.mapBy(_ => 0),
    evidence: 0,
    acknowledgements: 0,
    effects: 0,
    policyRevision: 1,
    candidateRevision: 1,
    authorizedActors: Set(1, 2),
    reservedActor: 1,
    reservedResource: "integration/main",
    reservedAttempt: 1,
    decisionPresent: false,
    decisionActor: 0,
    decisionResource: "none",
    decisionEpoch: 0,
    decisionCandidate: 0,
    decisionAttempt: 0,
    decisionTask: 0,
    decisionAction: 0,
    lastKind: 0,
    lastOutcome: 0,
    lastOperation: 0,
    lastBody: 0,
    lastActor: 0,
    lastResource: "none",
    lastEpoch: 0,
    lastAttempt: 0,
    lastTask: 0,
    lastAction: 0
  }

  pure def validHolder(st: State, resource: str, actor: int, epoch: int): bool = and {
    st.evidence == 0,
    actor != 0,
    st.owners.get(resource) == actor,
    st.epochs.get(resource) == epoch
  }

  pure def canEffect(st: State, actor: int, resource: str, epoch: int,
      candidate: int, attempt: int, task: int, actionId: int): bool = and {
    validHolder(st, resource, actor, epoch),
    st.authorizedActors.contains(actor),
    st.policyRevision == 1,
    st.candidateRevision == candidate,
    st.reservedActor == actor,
    st.reservedResource == resource,
    st.reservedAttempt == attempt,
    attempt > 0,
    st.decisionPresent,
    st.decisionActor == actor,
    st.decisionResource == resource,
    st.decisionEpoch == epoch,
    st.decisionCandidate == candidate,
    st.decisionAttempt == attempt,
    st.decisionTask == task,
    st.decisionAction == actionId
  }

  action init = all { s' = initial, previous' = initial }
  action move(proposed: State): bool = all { previous' = s, s' = proposed }

  action claim(operation: int, body: int, actor: int, resource: str): bool = {
    val prior = s.seenBodies.get(operation)
    val nextEpoch = s.epochs.get(resource) + 1
    move(
      if (s.evidence != 0)
        s.with("lastKind", 1).with("lastOutcome", -2)
          .with("lastOperation", operation).with("lastBody", body)
      else if (prior != 0)
        s.with("lastKind", 1).with("lastOutcome", if (prior == body) 2 else -1)
          .with("lastOperation", operation).with("lastBody", body)
      else if (s.owners.get(resource) != 0 or s.sequence >= MaxSequence
          or nextEpoch > MaxEpoch)
        s.with("lastKind", 1).with("lastOutcome", -3)
          .with("lastOperation", operation).with("lastBody", body)
      else
        s.with("sequence", s.sequence + 1)
          .with("epochs", s.epochs.set(resource, nextEpoch))
          .with("owners", s.owners.set(resource, actor))
          .with("seenBodies", s.seenBodies.set(operation, body))
          .with("lastKind", 1).with("lastOutcome", 1)
          .with("lastOperation", operation).with("lastBody", body)
          .with("lastActor", actor).with("lastResource", resource)
          .with("lastEpoch", nextEpoch))
  }

  action release(actor: int, resource: str, epoch: int): bool =
    move(if (s.evidence == 0 and s.owners.get(resource) == actor
        and s.epochs.get(resource) == epoch)
      s.with("owners", s.owners.set(resource, 0)).with("lastKind", 8)
      else s.with("lastKind", 8))

  action ack(operation: int, body: int, actor: int): bool = {
    val prior = s.seenBodies.get(operation)
    move(
      if (s.evidence != 0)
        s.with("lastKind", 2).with("lastOutcome", -2)
          .with("lastOperation", operation).with("lastBody", body)
      else if (prior != 0)
        s.with("lastKind", 2).with("lastOutcome", if (prior == body) 2 else -1)
          .with("lastOperation", operation).with("lastBody", body)
      else if (s.sequence >= MaxSequence)
        s.with("lastKind", 2).with("lastOutcome", -3)
          .with("lastOperation", operation).with("lastBody", body)
      else
        s.with("sequence", s.sequence + 1)
          .with("seenBodies", s.seenBodies.set(operation, body))
          .with("acknowledgements", s.acknowledgements + 1)
          .with("lastKind", 2).with("lastOutcome", 1)
          .with("lastOperation", operation).with("lastBody", body)
          .with("lastActor", actor))
  }

  // Pre-commit leaves the committed head untouched and visible evidence pending.
  action crashBeforeCommit = move(s.with("evidence", 1).with("lastKind", 3))
  // Post-commit changes no committed field.
  action crashAfterCommit = move(s.with("lastKind", 4))
  action markTorn = move(s.with("evidence", 2).with("lastKind", 9))
  // Abstract explicit inspection/discard of pending bytes; torn evidence has no recovery action.
  action inspectPending = move(
    if (s.evidence == 1) s.with("evidence", 0).with("lastKind", 5)
    else s.with("lastKind", 5))

  action recordDecision(actor: int, resource: str, epoch: int, candidate: int,
      attempt: int, task: int, actionId: int): bool =
    move(s.with("decisionPresent", true)
      .with("decisionActor", actor).with("decisionResource", resource)
      .with("decisionEpoch", epoch).with("decisionCandidate", candidate)
      .with("decisionAttempt", attempt).with("decisionTask", task)
      .with("decisionAction", actionId).with("lastKind", 6))

  action apply(actor: int, resource: str, epoch: int, candidate: int,
      attempt: int, task: int, actionId: int): bool =
    move(if (canEffect(s, actor, resource, epoch, candidate, attempt, task, actionId))
      s.with("effects", s.effects + 1).with("lastOutcome", 1)
        .with("lastKind", 7).with("lastActor", actor)
        .with("lastResource", resource).with("lastEpoch", epoch)
        .with("lastAttempt", attempt).with("lastTask", task)
        .with("lastAction", actionId)
      else s.with("lastKind", 7).with("lastOutcome", -2)
        .with("lastActor", actor).with("lastResource", resource)
        .with("lastEpoch", epoch).with("lastAttempt", attempt)
        .with("lastTask", task).with("lastAction", actionId))

  action step = any {
    crashBeforeCommit, crashAfterCommit, markTorn, inspectPending,
    nondet operation = oneOf(Operations); nondet body = oneOf(Bodies);
      nondet actor = oneOf(Sessions); nondet resource = oneOf(Resources);
      claim(operation, body, actor, resource),
    nondet operation = oneOf(Operations); nondet body = oneOf(Bodies);
      nondet actor = oneOf(Sessions); ack(operation, body, actor),
    nondet actor = oneOf(Sessions); nondet resource = oneOf(Resources);
      nondet epoch = oneOf(1.to(MaxEpoch)); release(actor, resource, epoch),
    nondet actor = oneOf(Sessions); nondet resource = oneOf(Resources);
      nondet epoch = oneOf(1.to(MaxEpoch));
      recordDecision(actor, resource, epoch, 1, 1, 1, 1),
    nondet actor = oneOf(Sessions); nondet resource = oneOf(Resources);
      nondet epoch = oneOf(1.to(MaxEpoch));
      apply(actor, resource, epoch, 1, 1, 1, 1)
  }

  val inv_sequence_monotone = previous.sequence <= s.sequence
  val inv_epoch_monotone = Resources.forall(r => previous.epochs.get(r) <= s.epochs.get(r))
  val inv_no_two_valid_holders = Resources.forall(r =>
    Sessions.forall(a => Sessions.forall(b =>
      (validHolder(s, r, a, s.epochs.get(r)) and
       validHolder(s, r, b, s.epochs.get(r))) implies a == b)))
  val inv_crash_preserves_committed_head = (s.lastKind == 3 or s.lastKind == 4) implies and {
    s.sequence == previous.sequence,
    s.epochs == previous.epochs,
    s.owners == previous.owners,
    s.seenBodies == previous.seenBodies
  }
  val inv_conflicting_duplicate_rejected =
    if (Operations.contains(s.lastOperation))
      (previous.evidence == 0 and (s.lastKind == 1 or s.lastKind == 2) and
       previous.seenBodies.get(s.lastOperation) != 0 and
       previous.seenBodies.get(s.lastOperation) != s.lastBody) implies and {
        s.sequence == previous.sequence,
        s.seenBodies == previous.seenBodies,
        s.lastOutcome == -1
      }
    else true
  val inv_bad_evidence_failclosed = previous.evidence != 0 implies and {
    s.sequence == previous.sequence,
    s.epochs == previous.epochs,
    s.owners == previous.owners,
    s.effects == previous.effects
  }
  val inv_ack_non_authority = s.lastKind == 2 implies and {
    s.epochs == previous.epochs,
    s.owners == previous.owners,
    s.effects == previous.effects,
    s.authorizedActors == previous.authorizedActors,
    s.reservedActor == previous.reservedActor,
    s.reservedResource == previous.reservedResource,
    s.reservedAttempt == previous.reservedAttempt,
    s.decisionPresent == previous.decisionPresent
  }
  val inv_effect_requires_matching_decision = s.effects > previous.effects implies
    canEffect(previous, s.lastActor, s.lastResource, s.lastEpoch,
      previous.candidateRevision, s.lastAttempt, s.lastTask, s.lastAction)
  val inv_all = and {
    inv_sequence_monotone,
    inv_epoch_monotone,
    inv_no_two_valid_holders,
    inv_crash_preserves_committed_head,
    inv_conflicting_duplicate_rejected,
    inv_bad_evidence_failclosed,
    inv_ack_non_authority,
    inv_effect_requires_matching_decision
  }

  val witness_claim = s.sequence > 0
  val witness_multiple_resources =
    s.owners.get("integration/main") == 1 and s.owners.get("runtime:alpha") == 2
  val witness_recovered_replay = s.lastOutcome == 2
  val witness_decision_effect = s.effects > 0

  run positiveDecisionEffectTest = init
    .then(claim(1, 1, 1, "integration/main"))
    .then(recordDecision(1, "integration/main", 1, 1, 1, 7, 9))
    .then(apply(1, "integration/main", 1, 1, 1, 7, 9))
    .expect(s.effects == 1 and inv_all)
  run multipleSessionsResourcesTest = init
    .then(claim(1, 1, 1, "integration/main"))
    .then(claim(2, 2, 2, "runtime:alpha"))
    .expect(s.owners.get("integration/main") == 1 and
      s.owners.get("runtime:alpha") == 2 and inv_all)
  run secondHolderRejectedTest = init
    .then(claim(1, 1, 1, "integration/main"))
    .then(claim(2, 2, 2, "integration/main"))
    .expect(s.sequence == 1 and s.owners.get("integration/main") == 1 and
      s.lastOutcome == -3 and inv_all)
  run sameDuplicateReplayTest = init
    .then(claim(1, 1, 1, "integration/main"))
    .then(crashAfterCommit).then(claim(1, 1, 1, "integration/main"))
    .expect(s.sequence == 1 and s.lastOutcome == 2 and inv_all)
  run conflictingDuplicateTest = init
    .then(claim(1, 1, 1, "integration/main"))
    .then(claim(1, 2, 1, "integration/main"))
    .expect(s.sequence == 1 and s.lastOutcome == -1 and inv_all)
  run crashBeforeRecoveryTest = init.then(crashBeforeCommit)
    .then(claim(1, 1, 1, "integration/main")).then(inspectPending)
    .then(claim(1, 1, 1, "integration/main"))
    .expect(s.sequence == 1 and s.epochs.get("integration/main") == 1 and inv_all)
  run tornFailsClosedTest = init.then(markTorn)
    .then(claim(1, 1, 1, "integration/main"))
    .then(apply(1, "integration/main", 1, 1, 1, 1, 1))
    .expect(s.sequence == 0 and s.effects == 0 and inv_all)
  run ackDoesNotGrantTest = init.then(ack(1, 1, 2))
    .then(apply(1, "integration/main", 1, 1, 1, 1, 1))
    .expect(s.acknowledgements == 1 and s.effects == 0 and inv_all)
  run missingDecisionFailsClosedTest = init
    .then(claim(1, 1, 1, "integration/main"))
    .then(apply(1, "integration/main", 1, 1, 1, 7, 9))
    .expect(not(s.decisionPresent) and s.effects == 0 and inv_all)

  // Controlled mutants are unreachable from normal step.
  action mutantConflictInit = all {
    s' = initial.with("sequence", 1)
      .with("seenBodies", initial.seenBodies.set(1, 1)),
    previous' = initial.with("sequence", 1)
      .with("seenBodies", initial.seenBodies.set(1, 1))
  }
  action mutantAcceptConflictingDuplicate = move(
    s.with("sequence", s.sequence + 1)
      .with("seenBodies", s.seenBodies.set(1, 2))
      .with("lastOperation", 1).with("lastBody", 2)
      .with("lastOutcome", 1).with("lastKind", 1))

  action mutantAckGrantsEffect = move(
    s.with("effects", s.effects + 1).with("lastKind", 2)
      .with("lastOperation", 1).with("lastBody", 1))

  action mutantMissingDecisionInit = all {
    val ready = initial.with("sequence", 1)
      .with("epochs", initial.epochs.set("integration/main", 1))
      .with("owners", initial.owners.set("integration/main", 1))
    all { s' = ready, previous' = ready }
  }
  action mutantEffectWithoutDecision = move(
    s.with("effects", s.effects + 1).with("lastKind", 7)
      .with("lastActor", 1).with("lastResource", "integration/main")
      .with("lastEpoch", 1).with("lastAttempt", 1)
      .with("lastTask", 7).with("lastAction", 9))
}

module agentic_journal_test {
  import agentic_journal(MaxSequence = 8, MaxEpoch = 4).*
}
