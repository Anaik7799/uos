// 20260909-0157; #fractal-l3 #fractal-l8 #zero-muda
// Finite execution scenarios for the pure ecology transaction capability.
// A bounded simulation is not exhaustive checking or live effect authority.
module ecology_capability_twin {
  type Snapshot = { version: int, value: int, owner: int, epoch: int,
    expires: int, telemetry: int }
  type Transaction = { actor: int, token: int, snapshot: int, now: int, write: int }
  var s: Snapshot
  var previous: Snapshot
  var lastTx: Transaction
  var operation: str

  pure def gate(st: Snapshot, tx: Transaction): bool = and {
    st.version >= 1, st.epoch >= 1, st.owner >= 0, st.expires >= 0,
    st.telemetry >= 0, tx.snapshot >= 1, tx.token >= 1, tx.now >= 0,
    tx.actor > 0, st.owner == tx.actor, st.epoch == tx.token,
    tx.now < st.expires, tx.snapshot == st.version
  }
  pure def commit(st: Snapshot, tx: Transaction): Snapshot =
    if (gate(st, tx)) st.with("version", st.version + 1).with("value", tx.write).with("owner", 0)
    else st
  pure val initial = { version: 1, value: 0, owner: 1, epoch: 1, expires: 3, telemetry: 0 }
  pure val validTx = { actor: 1, token: 1, snapshot: 1, now: 0, write: 1 }
  action init = all { s' = initial, previous' = initial, lastTx' = validTx, operation' = "init" }
  action attempt(tx: Transaction): bool = all {
    previous' = s, s' = commit(s, tx), lastTx' = tx, operation' = "commit"
  }
  action observe = all {
    previous' = s, s' = if (s.telemetry < 5) s.with("telemetry", s.telemetry + 1) else s,
    lastTx' = lastTx, operation' = "observe"
  }
  action step = any {
    observe,
    nondet a = oneOf(0.to(2)); nondet e = oneOf(0.to(2));
    nondet v = oneOf(0.to(2)); nondet n = oneOf(0.to(4));
    attempt({ actor: a, token: e, snapshot: v, now: n, write: 1 })
  }
  val inv_fenced_effect = s.version != previous.version implies and {
    operation == "commit", gate(previous, lastTx), s.version == previous.version + 1,
    s.value == lastTx.write, s.owner == 0, s.epoch == previous.epoch,
    s.telemetry == previous.telemetry
  }
  val inv_rejection = operation == "commit" and not(gate(previous, lastTx)) implies s == previous
  val inv_observation = operation == "observe" implies and {
    s.version == previous.version, s.value == previous.value,
    s.owner == previous.owner, s.epoch == previous.epoch, s.expires == previous.expires
  }
  val inv_all = and { inv_fenced_effect, inv_rejection, inv_observation,
    s.version >= 1, s.version <= 2, s.telemetry >= 0, s.telemetry <= 5 }
  val witness_commit = s.version == 2
  val false_control_no_commit = s.version == 1

  run validCommitTest = init.then(attempt(validTx)).expect(s.version == 2 and s.owner == 0 and inv_all)
  run expiryBoundaryTest = init.then(attempt(validTx.with("now", 3))).expect(s == initial and inv_all)
  run staleFenceTest = init.then(attempt(validTx.with("token", 2))).expect(s == initial and inv_all)
  run staleSnapshotTest = init.then(attempt(validTx.with("snapshot", 2))).expect(s == initial and inv_all)
  run wrongOwnerTest = init.then(attempt(validTx.with("actor", 2))).expect(s == initial and inv_all)
  run anonymousTest = init.then(attempt(validTx.with("actor", 0))).expect(s == initial and inv_all)
  run replayTest = init.then(attempt(validTx)).then(attempt(validTx)).expect(s.version == 2 and inv_all)
  run observationTest = init.then(observe).then(observe).expect(s.version == 1 and s.owner == 1 and s.telemetry == 2 and inv_all)
}
