import gleam/list
import gleeunit/should
import uos_swarm/decision_record as decision
import uos_swarm/hive_projection as hive

const observer_host = "nas-1"

const observer_boot = "boot-a"

fn clock() -> decision.ClockDomain {
  decision.ClockDomain(observer_host, observer_boot)
}

fn budget(cost: decision.Estimate) -> decision.Budget {
  decision.Budget(
    cost,
    decision.NotApplicableEstimate("no model tokens"),
    decision.UnknownEstimate("wall time is not independently measured"),
  )
}

fn snapshot(
  id: String,
  status: decision.SnapshotStatus,
  goal: String,
  record_clock: decision.ClockDomain,
) -> decision.StateSnapshot {
  decision.StateSnapshot(
    id,
    record_clock,
    100,
    status,
    decision.DeterministicRuleState,
    [decision.Stated(goal)],
    [decision.Stated("bounded subgoal")],
    [
      decision.Belief(
        "measured shared evidence",
        ["evidence:measured"],
        decision.EvidenceBound,
        decision.MeasuredRuntime,
      ),
      decision.Belief(
        "candidate hypothesis",
        ["evidence:hypothesis"],
        decision.Hypothesis,
        decision.Inference,
      ),
      decision.Belief(
        "unresolved belief",
        ["evidence:uncertain"],
        decision.Uncertain,
        decision.Inference,
      ),
    ],
    [decision.Stated("external state remains uncertain")],
    [decision.Stated("is the destination current?")],
    [decision.Stated("read only")],
    [decision.Stated("one executor")],
    budget(decision.UnknownEstimate("snapshot budget has no measured cost")),
    decision.Stated("candidate review"),
    decision.Stated("task"),
    [decision.Stated("inspect the candidate")],
  )
}

fn forecast(
  confidence: decision.ConfidenceBasis,
  predicted: String,
  cost: decision.Estimate,
  record_clock: decision.ClockDomain,
  expires: Int,
) -> decision.Forecast {
  decision.Forecast(
    record_clock,
    "next bounded action",
    100,
    expires,
    decision.Stated(predicted),
    [decision.Stated("defer")],
    [decision.Stated("shared record remains valid")],
    confidence,
    decision.UnknownProbability("probability not independently calibrated"),
    decision.UnknownEstimate("dependencies are absent"),
    cost,
    [decision.Stated("one executor")],
    [decision.Stated("fence changes")],
    [decision.Stated("new evidence")],
    decision.Unknown("outcome not observed"),
    decision.NotApplicable("prepared forecast"),
  )
}

fn prepared(
  id: String,
  hive_id: String,
  tenant_id: String,
  actor: String,
  session: String,
  resource: String,
  epoch: Int,
  action: String,
  goal: String,
  status: decision.SnapshotStatus,
  confidence: decision.ConfidenceBasis,
  predicted: String,
  cost: decision.Estimate,
  record_clock: decision.ClockDomain,
  expires: Int,
) -> decision.PreparedDecision {
  decision.PreparedDecision(
    id,
    hive_id,
    tenant_id,
    decision.Actor(
      actor,
      decision.DeterministicActor,
      session,
      decision.Stated("uos_swarm"),
      decision.NotApplicable("deterministic actor"),
    ),
    "task:" <> id,
    goal,
    "candidate:" <> id,
    resource,
    epoch,
    ["evidence:" <> id],
    [decision.Stated("read only")],
    decision.Stated("policy:projection"),
    budget(cost),
    [decision.Alternative("defer", "retain current state")],
    action,
    "projection input",
    [decision.Stated("result remains uncertain")],
    [decision.Stated("stale fence")],
    [decision.ProcessStep(1, "publish shared state", decision.Stated("record"))],
    ["authority:review-only"],
    decision.Stated("compare projection"),
    decision.NotApplicable("no mutation"),
    snapshot("snapshot:" <> id, status, goal, record_clock),
    forecast(confidence, predicted, cost, record_clock, expires),
  )
}

fn current(
  id: String,
  tenant: String,
  actor: String,
  action: String,
  goal: String,
  predicted: String,
  confidence: decision.ConfidenceBasis,
  cost: decision.Estimate,
) -> decision.PreparedDecision {
  prepared(
    id,
    "hive-uos",
    tenant,
    actor,
    "session:" <> actor,
    "integration/main",
    2,
    action,
    goal,
    decision.SnapshotCurrent,
    confidence,
    predicted,
    cost,
    clock(),
    1000,
  )
}

fn validated(prepared: decision.PreparedDecision) -> decision.ValidatedRecord {
  decision.PreparedRecord(prepared)
  |> decision.validate_record(clock(), 200)
  |> should.be_ok
}

fn completion(
  id: String,
  prepared_id: String,
  cost: decision.Estimate,
) -> decision.CompletedDecision {
  decision.CompletedDecision(
    id,
    prepared_id,
    "hive-uos",
    "tenant-a",
    decision.Actor(
      "codex",
      decision.DeterministicActor,
      "session:codex",
      decision.Stated("uos_swarm"),
      decision.NotApplicable("deterministic actor"),
    ),
    "task:" <> prepared_id,
    "candidate:" <> prepared_id,
    "integration/main",
    2,
    "inspect",
    decision.Succeeded("accepted result"),
    ["evidence:completion"],
    cost,
    [decision.ProcessStep(1, "completed", decision.Stated("receipt"))],
    decision.Stated("verified"),
    decision.NotApplicable("no rollback"),
    decision.Stated("accepted"),
    decision.Stated("calibration:one"),
  )
}

fn validated_completion(
  completed: decision.CompletedDecision,
) -> decision.ValidatedRecord {
  decision.CompletedRecord(completed)
  |> decision.validate_record(clock(), 200)
  |> should.be_ok
}

fn epochs() -> List(hive.CurrentResourceEpoch) {
  [hive.CurrentResourceEpoch("integration/main", 2)]
}

pub fn exact_hive_and_tenant_partition_prevents_leakage_test() {
  let own =
    validated(current(
      "own",
      "tenant-a",
      "codex",
      "inspect",
      "own goal",
      "own forecast",
      decision.MeasuredConfidence("basis:own"),
      decision.Estimated(10, "micro-usd", "basis:own"),
    ))
  let other =
    validated(current(
      "other",
      "tenant-b",
      "claude",
      "delete-secret",
      "private other-tenant goal",
      "private other-tenant forecast",
      decision.UnknownConfidence("other tenant unknown"),
      decision.UnknownEstimate("other tenant cost"),
    ))
  let assert Ok(view) =
    hive.project([other, own], "hive-uos", "tenant-a", epochs(), 16)
  let assert [state] = view.active
  state.goal |> should.equal("own goal")
  view.conflicts |> should.equal([])
}

pub fn stale_superseded_expired_epoch_and_clock_unknown_are_not_active_test() {
  let stale =
    prepared(
      "stale",
      "hive-uos",
      "tenant-a",
      "a",
      "session:a",
      "integration/main",
      2,
      "inspect",
      "stale",
      decision.SnapshotStale("declared stale"),
      decision.MeasuredConfidence("basis"),
      "stale",
      decision.Estimated(1, "micro-usd", "basis"),
      clock(),
      1000,
    )
    |> validated
  let superseded =
    prepared(
      "superseded",
      "hive-uos",
      "tenant-a",
      "b",
      "session:b",
      "integration/main",
      2,
      "inspect",
      "superseded",
      decision.SnapshotSuperseded("snapshot:new"),
      decision.MeasuredConfidence("basis"),
      "superseded",
      decision.Estimated(1, "micro-usd", "basis"),
      clock(),
      1000,
    )
    |> validated
  let expired =
    prepared(
      "expired",
      "hive-uos",
      "tenant-a",
      "c",
      "session:c",
      "integration/main",
      2,
      "inspect",
      "expired",
      decision.SnapshotCurrent,
      decision.MeasuredConfidence("basis"),
      "expired",
      decision.Estimated(1, "micro-usd", "basis"),
      clock(),
      150,
    )
    |> validated
  let stale_epoch =
    prepared(
      "old-epoch",
      "hive-uos",
      "tenant-a",
      "d",
      "session:d",
      "integration/main",
      1,
      "inspect",
      "old epoch",
      decision.SnapshotCurrent,
      decision.MeasuredConfidence("basis"),
      "old",
      decision.Estimated(1, "micro-usd", "basis"),
      clock(),
      1000,
    )
    |> validated
  let foreign_clock = decision.ClockDomain("nas-1", "boot-other")
  let unknown =
    prepared(
      "unknown-clock",
      "hive-uos",
      "tenant-a",
      "e",
      "session:e",
      "integration/main",
      2,
      "inspect",
      "unknown clock",
      decision.SnapshotCurrent,
      decision.MeasuredConfidence("basis"),
      "unknown",
      decision.Estimated(1, "micro-usd", "basis"),
      foreign_clock,
      1000,
    )
    |> validated
  let assert Ok(view) =
    hive.project(
      [stale, superseded, expired, stale_epoch, unknown],
      "hive-uos",
      "tenant-a",
      epochs(),
      16,
    )
  view.active |> should.equal([])
  view.history.stale_snapshots |> should.equal(1)
  view.history.superseded_snapshots |> should.equal(1)
  view.history.expired_records |> should.equal(1)
  view.history.stale_epochs |> should.equal(1)
  view.history.unknown_freshness |> should.equal(1)
  let assert hive.FreshnessUnknown([_]) = view.state_freshness
}

pub fn duplicates_conflicts_and_order_are_deterministic_test() {
  let first =
    validated(current(
      "first",
      "tenant-a",
      "codex",
      "inspect",
      "goal a",
      "forecast a",
      decision.MeasuredConfidence("measured:a"),
      decision.Estimated(100, "micro-usd", "basis:a"),
    ))
  let second =
    validated(current(
      "second",
      "tenant-a",
      "claude",
      "apply",
      "goal b",
      "forecast b",
      decision.EstimatedConfidence("estimated:b"),
      decision.Estimated(200, "micro-usd", "basis:b"),
    ))
  let records = [second, first, first]
  let assert Ok(view) =
    hive.project(records, "hive-uos", "tenant-a", epochs(), 16)
  view.history.duplicate_deliveries |> should.equal(1)
  list.length(view.conflicts) |> should.equal(3)
  view.active_expected_cost
  |> should.equal(hive.AdditiveCost(
    300,
    "micro-usd",
    2,
    "one active PreparedDecision decision_id per planned attempt",
  ))
  view.forecast_confidence
  |> should.equal(hive.EstimatedAggregate(["estimated:b", "measured:a"]))
  hive.project(records, "hive-uos", "tenant-a", epochs(), 16)
  |> should.equal(hive.project(
    list.reverse(records),
    "hive-uos",
    "tenant-a",
    epochs(),
    16,
  ))
}

pub fn unknown_confidence_and_cost_propagate_without_averaging_test() {
  let measured =
    validated(current(
      "measured",
      "tenant-a",
      "codex",
      "inspect",
      "goal",
      "forecast",
      decision.MeasuredConfidence("measured"),
      decision.Estimated(100, "micro-usd", "measured"),
    ))
  let unknown =
    validated(current(
      "unknown",
      "tenant-a",
      "claude",
      "inspect",
      "goal",
      "forecast",
      decision.UnknownConfidence(
        "correlated self-report has no independent basis",
      ),
      decision.UnknownEstimate("cost missing"),
    ))
  let assert Ok(view) =
    hive.project([measured, unknown], "hive-uos", "tenant-a", epochs(), 16)
  view.forecast_confidence
  |> should.equal(
    hive.UnknownAggregate([
      "correlated self-report has no independent basis",
    ]),
  )
  let assert hive.CostUnknown(_) = view.active_expected_cost
}

pub fn completion_cost_is_once_per_planned_attempt_and_conflict_is_visible_test() {
  let first =
    validated_completion(completion(
      "completion:1",
      "attempt:1",
      decision.Estimated(10, "micro-usd", "receipt:1"),
    ))
  let second =
    validated_completion(completion(
      "completion:2",
      "attempt:2",
      decision.Estimated(20, "micro-usd", "receipt:2"),
    ))
  let conflicting =
    validated_completion(completion(
      "completion:3",
      "attempt:1",
      decision.Estimated(30, "micro-usd", "receipt:3"),
    ))
  let assert Ok(clean) =
    hive.project([first, first, second], "hive-uos", "tenant-a", epochs(), 16)
  clean.observed_completed_cost
  |> should.equal(hive.AdditiveCost(
    30,
    "micro-usd",
    2,
    "deduplicated by prepared_decision_id",
  ))
  clean.history.duplicate_deliveries |> should.equal(1)
  let assert Ok(conflicted) =
    hive.project([first, conflicting], "hive-uos", "tenant-a", epochs(), 16)
  let assert hive.CostUnknown(_) = conflicted.observed_completed_cost
  let assert [hive.Conflict(hive.MultipleCompletionConflict, ..)] =
    conflicted.conflicts
}

pub fn projection_has_no_authority_and_parallel_wall_time_stays_unknown_test() {
  let assert Ok(view) = hive.project([], "hive-uos", "tenant-a", epochs(), 8)
  view.authority |> should.equal(hive.ReadOnlyObservational)
  view.parallel_wall_time
  |> should.equal(hive.ParallelWallTimeUnknown(
    "DecisionRecord v1 has no dependency graph; parallel wall time is not additive",
  ))
}

pub fn future_record_and_missing_epoch_fail_closed_test() {
  let future =
    prepared(
      "future",
      "hive-uos",
      "tenant-a",
      "codex",
      "session:codex",
      "integration/main",
      2,
      "inspect",
      "future goal",
      decision.SnapshotCurrent,
      decision.MeasuredConfidence("basis"),
      "future forecast",
      decision.Estimated(1, "micro-usd", "basis"),
      clock(),
      1000,
    )
  let future =
    decision.PreparedDecision(
      ..future,
      state: decision.StateSnapshot(..future.state, as_of_boot_us: 300),
      forecast: decision.Forecast(..future.forecast, as_of_boot_us: 300),
    )
  let future = validated(future)
  let current_without_epoch =
    validated(current(
      "missing-epoch",
      "tenant-a",
      "claude",
      "inspect",
      "goal",
      "forecast",
      decision.MeasuredConfidence("basis"),
      decision.Estimated(1, "micro-usd", "basis"),
    ))
  let assert Ok(view) =
    hive.project([future, current_without_epoch], "hive-uos", "tenant-a", [], 8)
  view.active |> should.equal([])
  view.history.unknown_freshness |> should.equal(1)
  view.history.missing_current_epochs |> should.equal(1)
  let assert hive.FreshnessUnknown([_]) = view.state_freshness
}

pub fn bounds_and_conflicting_resource_epochs_are_rejected_test() {
  hive.project([], "hive-uos", "tenant-a", [], 0)
  |> should.equal(Error(hive.InvalidBound(0)))
  hive.project(
    [],
    "hive-uos",
    "tenant-a",
    [
      hive.CurrentResourceEpoch("integration/main", 1),
      hive.CurrentResourceEpoch("integration/main", 2),
    ],
    8,
  )
  |> should.equal(Error(hive.ConflictingCurrentEpoch("integration/main")))
}

pub fn shared_goal_and_next_action_disagreements_are_preserved_test() {
  let base =
    current(
      "shared-a",
      "tenant-a",
      "codex",
      "inspect",
      "common goal",
      "common forecast",
      decision.MeasuredConfidence("basis"),
      decision.Estimated(1, "micro-usd", "basis"),
    )
  let different_snapshot =
    decision.StateSnapshot(
      ..base.state,
      snapshot_id: "snapshot:shared-b",
      current_goals: [decision.Stated("different current goal")],
      intended_next_actions: [decision.Stated("apply the candidate")],
    )
  let second =
    decision.PreparedDecision(
      ..base,
      decision_id: "shared-b",
      task_id: "task:shared-b",
      candidate_revision: "candidate:shared-b",
      evidence_refs: ["evidence:shared-b"],
      state: different_snapshot,
    )
  let assert Ok(view) =
    hive.project(
      [validated(base), validated(second)],
      "hive-uos",
      "tenant-a",
      epochs(),
      8,
    )
  list.length(view.conflicts) |> should.equal(2)
  let assert [
    hive.Conflict(hive.IntendedActionConflict, ..),
    hive.Conflict(hive.DeclaredGoalConflict, ..),
  ] = view.conflicts
}

pub fn same_record_validated_at_different_times_is_not_order_dependent_test() {
  let source =
    current(
      "time-context",
      "tenant-a",
      "codex",
      "inspect",
      "goal",
      "forecast",
      decision.MeasuredConfidence("basis"),
      decision.Estimated(1, "micro-usd", "basis"),
    )
  let current_record =
    decision.PreparedRecord(source)
    |> decision.validate_record(clock(), 200)
    |> should.be_ok
  let expired_record =
    decision.PreparedRecord(source)
    |> decision.validate_record(clock(), 1200)
    |> should.be_ok
  let expected = Error(hive.ConflictingRecordReplay("time-context"))
  hive.project(
    [current_record, expired_record],
    "hive-uos",
    "tenant-a",
    epochs(),
    8,
  )
  |> should.equal(expected)
  hive.project(
    [expired_record, current_record],
    "hive-uos",
    "tenant-a",
    epochs(),
    8,
  )
  |> should.equal(expected)
}
