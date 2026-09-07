import gleam/list
import gleam/option.{Some}
import gleam/string
import gleeunit/should
import uos_swarm/decision_record as decision

const candidate = "candidate-a"

const resource = "integration/main"

const action = "integration.inspect"

const clock_host = "host-a"

const clock_boot = "boot-a"

fn budget() -> decision.Budget {
  decision.Budget(
    decision.Estimated(0, "micro-usd", "policy:local-deterministic-no-charge"),
    decision.NotApplicableEstimate("no model tokens used"),
    decision.Estimated(
      2_000_000,
      "microseconds",
      "consumer callback timeout plan",
    ),
  )
}

fn state_snapshot() -> decision.StateSnapshot {
  decision.StateSnapshot(
    "snapshot-42",
    decision.ClockDomain(clock_host, clock_boot),
    900_000,
    decision.SnapshotCurrent,
    decision.DeterministicRuleState,
    [decision.Stated("inspect the exact candidate")],
    [decision.Stated("recheck the current lease fence")],
    [
      decision.Belief(
        "candidate evidence is available",
        ["evidence:runtime", "evidence:formal"],
        decision.EvidenceBound,
        decision.MeasuredRuntime,
      ),
    ],
    [decision.Stated("remote destination state may change")],
    [decision.Stated("will the destination remain current?")],
    [decision.Stated("no main mutation")],
    [decision.Stated("integration/main epoch 1")],
    budget(),
    decision.Stated("candidate and fence validation"),
    decision.Stated("task-42"),
    [decision.Stated("run the bounded inspection")],
  )
}

fn forecast(
  confidence: decision.ConfidenceBasis,
  probability: decision.Probability,
) -> decision.Forecast {
  decision.Forecast(
    decision.ClockDomain(clock_host, clock_boot),
    "next bounded inspection",
    900_000,
    2_000_000,
    decision.Stated("inspection returns a revision-bound receipt"),
    [decision.Stated("inspection refuses on a changed fence")],
    [decision.Stated("the local session journal remains readable")],
    confidence,
    probability,
    decision.Estimated(1_000_000, "microseconds", "bounded local test history"),
    decision.UnknownEstimate("destination cost is not measured yet"),
    [decision.Stated("one BEAM executor")],
    [decision.Stated("lease or candidate changes")],
    [decision.Stated("new heartbeat or policy revision")],
    decision.Unknown("outcome is not observed before execution"),
    decision.NotApplicable("calibration is recorded after completion"),
  )
}

fn prepared_with(forecast: decision.Forecast) -> decision.PreparedDecision {
  decision.PreparedDecision(
    "decision-prepared-42",
    "hive-uos",
    "tenant-operator",
    decision.Actor(
      "codex",
      decision.DeterministicActor,
      "codex-session",
      decision.Stated("uos_swarm"),
      decision.NotApplicable("deterministic actor has no model"),
    ),
    "task-42",
    "inspect candidate without mutating main",
    candidate,
    resource,
    1,
    ["evidence:runtime", "evidence:formal"],
    [decision.Stated("read-only adapter")],
    decision.Stated("policy-7"),
    budget(),
    [
      decision.Alternative(
        "defer inspection",
        "preserves state but yields no current evidence",
      ),
      decision.Alternative(
        "inspect now",
        "obtains evidence while the lease is current",
      ),
    ],
    action,
    "The current lease and candidate can be checked without a mutation.",
    [decision.Stated("destination result can be unknown")],
    [decision.Stated("lease expiry before callback")],
    [
      decision.ProcessStep(
        1,
        "validate the decision envelope",
        decision.NotApplicable("pure validation"),
      ),
      decision.ProcessStep(
        2,
        "observe the session fence",
        decision.Stated("session-journal"),
      ),
      decision.ProcessStep(
        3,
        "invoke one inspection",
        decision.Unknown("receipt not available before action"),
      ),
    ],
    ["authority:operator-task", "authorization:action-42"],
    decision.Stated("verify the receipt candidate and exit status"),
    decision.NotApplicable("read-only inspection has no rollback mutation"),
    state_snapshot(),
    forecast,
  )
}

fn prepared() -> decision.PreparedDecision {
  prepared_with(forecast(
    decision.EstimatedConfidence("basis:bounded-local-history"),
    decision.ProbabilityRange(7000, 9000, "basis:bounded-local-history"),
  ))
}

fn expected(
  actor: String,
  actor_kind: decision.ActorKind,
  session: String,
  task: String,
  candidate_revision: String,
  expected_resource: String,
  epoch: Int,
  selected_action: String,
) -> decision.ExpectedDecision {
  decision.ExpectedDecision(
    "hive-uos",
    "tenant-operator",
    decision.ClockDomain(clock_host, clock_boot),
    actor,
    actor_kind,
    session,
    task,
    candidate_revision,
    expected_resource,
    epoch,
    selected_action,
  )
}

fn exact_expected() -> decision.ExpectedDecision {
  expected(
    "codex",
    decision.DeterministicActor,
    "codex-session",
    "task-42",
    candidate,
    resource,
    1,
    action,
  )
}

pub fn prepared_validation_binds_every_action_identity_field_test() {
  decision.validate_prepared(prepared(), exact_expected(), 1_000_000)
  |> should.be_ok
  [
    expected(
      "claude",
      decision.DeterministicActor,
      "codex-session",
      "task-42",
      candidate,
      resource,
      1,
      action,
    ),
    expected(
      "codex",
      decision.ModelActor,
      "codex-session",
      "task-42",
      candidate,
      resource,
      1,
      action,
    ),
    expected(
      "codex",
      decision.DeterministicActor,
      "other-session",
      "task-42",
      candidate,
      resource,
      1,
      action,
    ),
    expected(
      "codex",
      decision.DeterministicActor,
      "codex-session",
      "other-task",
      candidate,
      resource,
      1,
      action,
    ),
    expected(
      "codex",
      decision.DeterministicActor,
      "codex-session",
      "task-42",
      "candidate-b",
      resource,
      1,
      action,
    ),
    expected(
      "codex",
      decision.DeterministicActor,
      "codex-session",
      "task-42",
      candidate,
      "runtime:wiki",
      1,
      action,
    ),
    expected(
      "codex",
      decision.DeterministicActor,
      "codex-session",
      "task-42",
      candidate,
      resource,
      2,
      action,
    ),
    expected(
      "codex",
      decision.DeterministicActor,
      "codex-session",
      "task-42",
      candidate,
      resource,
      1,
      "integration.apply",
    ),
  ]
  |> list.each(fn(wrong) {
    decision.validate_prepared(prepared(), wrong, 1_000_000) |> should.be_error
  })
  decision.validate_prepared(
    prepared(),
    decision.ExpectedDecision(
      "other-hive",
      "tenant-operator",
      decision.ClockDomain(clock_host, clock_boot),
      "codex",
      decision.DeterministicActor,
      "codex-session",
      "task-42",
      candidate,
      resource,
      1,
      action,
    ),
    1_000_000,
  )
  |> should.be_error
  decision.validate_prepared(
    prepared(),
    decision.ExpectedDecision(
      "hive-uos",
      "other-tenant",
      decision.ClockDomain(clock_host, clock_boot),
      "codex",
      decision.DeterministicActor,
      "codex-session",
      "task-42",
      candidate,
      resource,
      1,
      action,
    ),
    1_000_000,
  )
  |> should.be_error
}

pub fn unknown_forecast_values_are_explicit_but_numeric_claims_need_basis_test() {
  let unknown =
    prepared_with(forecast(
      decision.UnknownConfidence("no comparable history"),
      decision.UnknownProbability("confidence is unknown"),
    ))
  decision.validate_prepared(unknown, exact_expected(), 1_000_000)
  |> should.be_ok

  let unjustified =
    prepared_with(forecast(
      decision.UnknownConfidence("no comparable history"),
      decision.PointProbability(8500, "invented-number"),
    ))
  decision.validate_prepared(unjustified, exact_expected(), 1_000_000)
  |> should.be_error

  let future_forecast =
    decision.Forecast(
      ..forecast(
        decision.UnknownConfidence("no comparable history"),
        decision.UnknownProbability("confidence is unknown"),
      ),
      as_of_boot_us: 1_000_001,
    )
  decision.validate_prepared(
    prepared_with(future_forecast),
    exact_expected(),
    1_000_000,
  )
  |> should.be_error
}

pub fn prepared_json_codec_roundtrips_and_rejects_oversized_public_text_test() {
  let record = decision.PreparedRecord(prepared())
  decision.decode(decision.encode(record)) |> should.equal(Ok(record))
  let oversized =
    prepared_with(decision.Forecast(
      decision.ClockDomain(clock_host, clock_boot),
      "next bounded inspection",
      900_000,
      2_000_000,
      decision.Stated("x" <> string.repeat("y", 5000)),
      [decision.Stated("alternative")],
      [decision.Stated("assumption")],
      decision.UnknownConfidence("not measured"),
      decision.UnknownProbability("not measured"),
      decision.UnknownEstimate("not measured"),
      decision.UnknownEstimate("not measured"),
      [decision.Stated("resource unknown")],
      [decision.Stated("failure signal unknown")],
      [decision.Stated("update trigger unknown")],
      decision.Unknown("not observed"),
      decision.NotApplicable("not completed"),
    ))
  decision.validate_prepared(oversized, exact_expected(), 1_000_000)
  |> should.be_error
}

fn completed() -> decision.CompletedDecision {
  decision.CompletedDecision(
    "decision-completed-42",
    "decision-prepared-42",
    "hive-uos",
    "tenant-operator",
    decision.Actor(
      "codex",
      decision.DeterministicActor,
      "codex-session",
      decision.Stated("uos_swarm"),
      decision.NotApplicable("deterministic actor has no model"),
    ),
    "task-42",
    candidate,
    resource,
    1,
    action,
    decision.Succeeded("inspection produced a clean receipt"),
    ["receipt:inspection-42"],
    decision.Estimated(0, "micro-usd", "local deterministic execution"),
    [
      decision.ProcessStep(
        1,
        "inspection completed",
        decision.Stated("receipt:inspection-42"),
      ),
    ],
    decision.Stated("candidate and exit status matched"),
    decision.NotApplicable("no mutation required rollback"),
    decision.Stated("inspection produced a clean receipt"),
    decision.Stated("calibration:inspection-42"),
  )
}

pub fn completion_is_a_separate_linked_report_and_codec_roundtrips_test() {
  decision.validate_completion(prepared(), completed()) |> should.be_ok
  let record = decision.CompletedRecord(completed())
  decision.decode(decision.encode(record)) |> should.equal(Ok(record))

  let decision.CompletedDecision(
    id,
    _,
    hive,
    tenant,
    actor,
    task,
    candidate_revision,
    expected_resource,
    epoch,
    selected_action,
    outcome,
    evidence,
    cost,
    process,
    verification,
    rollback,
    observed,
    calibration,
  ) = completed()
  let wrong_link =
    decision.CompletedDecision(
      id,
      "another-prepared-record",
      hive,
      tenant,
      actor,
      task,
      candidate_revision,
      expected_resource,
      epoch,
      selected_action,
      outcome,
      evidence,
      cost,
      process,
      verification,
      rollback,
      observed,
      calibration,
    )
  decision.validate_completion(prepared(), wrong_link) |> should.be_error
}

pub fn projection_receives_only_structurally_validated_shared_records_test() {
  let assert Ok(validated) =
    decision.validate_record(
      decision.PreparedRecord(prepared()),
      decision.ClockDomain(clock_host, clock_boot),
      1_000_000,
    )
  decision.validated_hive_id(validated) |> should.equal("hive-uos")
  decision.validated_tenant_id(validated) |> should.equal("tenant-operator")
  decision.validated_phase(validated) |> should.equal(decision.PreparedPhase)
  decision.validated_snapshot_status(validated)
  |> should.equal(Some(decision.SnapshotCurrent))
  let assert Ok(other_clock) =
    decision.validate_record(
      decision.PreparedRecord(prepared()),
      decision.ClockDomain("host-b", "boot-b"),
      1_000_000,
    )
  let assert decision.RecordFreshnessUnknown(_) =
    decision.validated_freshness(other_clock)
}

pub fn projection_retains_stale_history_but_stale_record_cannot_authorize_test() {
  let stale_state =
    decision.StateSnapshot(
      ..state_snapshot(),
      status: decision.SnapshotStale("superseded by a current actor report"),
    )
  let stale = decision.PreparedDecision(..prepared(), state: stale_state)
  let assert Ok(validated) =
    decision.validate_record(
      decision.PreparedRecord(stale),
      decision.ClockDomain(clock_host, clock_boot),
      1_000_000,
    )
  decision.validated_snapshot_status(validated)
  |> should.equal(
    Some(decision.SnapshotStale("superseded by a current actor report")),
  )
  let assert decision.PreparedView(view) =
    decision.validated_record_view(validated)
  view.decision_id |> should.equal("decision-prepared-42")
  decision.validate_prepared(stale, exact_expected(), 1_000_000)
  |> should.be_error
}
