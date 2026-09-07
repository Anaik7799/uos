import gleam/list
import gleam/option.{None, Some}
import gleeunit/should
import uos_swarm/hive_kpi as kpi

fn clock() -> kpi.ClockDomain {
  kpi.ClockDomain("nas-1", "boot-a")
}

fn sample_set() -> List(kpi.KpiSample) {
  [
    kpi.VerifiedTaskOutcome("task:1", True),
    kpi.VerifiedTaskOutcome("task:2", False),
    kpi.CapabilityRequirement("cap:1", "observe", True),
    kpi.CapabilityRequirement("cap:2", "act", False),
    kpi.DecisionRecordCompleteness("decision:1", 9, 10),
    kpi.BinaryForecastResolution("forecast:1", 8000, True, True),
    kpi.BinaryForecastResolution("forecast:2", 2000, False, True),
    kpi.BinaryForecastResolution("forecast:uncommitted", 10_000, False, False),
    kpi.ForecastAbsoluteError("duration:1", kpi.Duration, 10, "microseconds"),
    kpi.ForecastAbsoluteError("duration:2", kpi.Duration, 30, "microseconds"),
    kpi.ForecastAbsoluteError("cost-error:1", kpi.Cost, 5, "micro-usd"),
    kpi.AcceptedResultCost("accepted:1", Some(100)),
    kpi.AcceptedResultCost("accepted:2", Some(300)),
    kpi.CoordinationAttempt("coord:1", True, Some(100)),
    kpi.CoordinationAttempt("coord:2", False, None),
    kpi.SharedStateObservation(
      "state:1",
      clock(),
      clock(),
      900,
      1000,
      200,
      4,
      4,
    ),
    kpi.SharedStateObservation(
      "state:2",
      clock(),
      clock(),
      100,
      1000,
      200,
      2,
      4,
    ),
    kpi.ConflictObservation("conflict:1", True),
    kpi.ConflictObservation("conflict:2", False),
    kpi.MissingDataObservation("missing:1", True),
    kpi.MissingDataObservation("missing:2", False),
    kpi.AwarenessEvidence("awareness:1", kpi.SharedStateObserved),
    kpi.AwarenessEvidence("awareness:2", kpi.SelfMonitoringObserved),
    kpi.AwarenessEvidence("awareness:3", kpi.PredictiveCalibrationObserved),
    kpi.AwarenessEvidence("awareness:4", kpi.VerifiedAdaptationObserved),
  ]
}

pub fn zero_denominators_are_unavailable_and_consciousness_unestablished_test() {
  let assert Ok(observation) = kpi.observe([], 32)
  let assert kpi.MissingMetric(_, "VerifiedTaskOutcome", "zero denominator") =
    observation.verified_task_success
  let assert kpi.MissingMetric(_, "AcceptedResultCost", "zero denominator") =
    observation.cost_per_accepted_result
  let assert kpi.ConsciousnessAssessment(kpi.Unestablished, None, _) =
    observation.consciousness
  observation.authority |> should.equal(kpi.ReadOnlyObservational)
}

pub fn versioned_kpis_use_only_observed_denominators_test() {
  let assert Ok(observation) = kpi.observe(sample_set(), 64)
  observation.schema |> should.equal("uos-hive-kpi/v1")
  observation.verified_task_success
  |> should.equal(kpi.Measured(5000, 2, 10_000, "ratio"))
  observation.verified_task_samples
  |> should.equal(kpi.Measured(2, 2, 1, "count"))
  observation.admitted_capability_coverage
  |> should.equal(kpi.Measured(5000, 2, 10_000, "ratio"))
  observation.decision_record_completeness
  |> should.equal(kpi.Measured(9000, 10, 10_000, "ratio"))
  observation.binary_forecast_brier
  |> should.equal(kpi.Measured(4_000_000, 2, 1, "basis-points-squared"))
  observation.duration_absolute_error
  |> should.equal(kpi.Measured(20, 2, 1, "microseconds"))
  observation.cost_absolute_error
  |> should.equal(kpi.Measured(5, 1, 1, "micro-usd"))
  observation.cost_per_accepted_result
  |> should.equal(kpi.Measured(200, 2, 1, "micro-usd"))
  observation.coordination_delivery
  |> should.equal(kpi.Measured(5000, 2, 10_000, "ratio"))
  observation.acknowledgement_latency
  |> should.equal(kpi.Measured(100, 1, 1, "microseconds"))
  observation.shared_state_freshness
  |> should.equal(kpi.Measured(5000, 2, 10_000, "ratio"))
  observation.shared_state_coverage
  |> should.equal(kpi.Measured(7500, 8, 10_000, "ratio"))
  observation.conflict_rate
  |> should.equal(kpi.Measured(5000, 2, 10_000, "ratio"))
  observation.missing_data_rate
  |> should.equal(kpi.Measured(5000, 2, 10_000, "ratio"))
  observation.functional_awareness
  |> should.equal(
    kpi.FunctionalAwareness(4, [
      "shared-state-observed",
      "self-monitoring-observed",
      "predictive-calibration-observed",
      "verified-adaptation-observed",
    ]),
  )
}

pub fn replay_uid_is_idempotent_and_conflicting_uid_fails_closed_test() {
  let sample = kpi.VerifiedTaskOutcome("task:one", True)
  let assert Ok(observation) = kpi.observe([sample, sample], 8)
  observation.unique_samples |> should.equal(1)
  observation.duplicate_deliveries |> should.equal(1)
  observation.verified_task_success
  |> should.equal(kpi.Measured(10_000, 1, 10_000, "ratio"))
  kpi.observe([sample, kpi.VerifiedTaskOutcome("task:one", False)], 8)
  |> should.equal(Error(kpi.ConflictingReplay("task:one")))
}

pub fn missing_accepted_cost_is_not_zero_test() {
  let assert Ok(observation) =
    kpi.observe(
      [
        kpi.AcceptedResultCost("accepted:known", Some(100)),
        kpi.AcceptedResultCost("accepted:unknown", None),
      ],
      8,
    )
  let assert kpi.MissingMetric(
    _,
    "AcceptedResultCost(cost=known)",
    "at least one accepted result has unknown cost",
  ) = observation.cost_per_accepted_result
}

pub fn input_order_does_not_change_projection_test() {
  let samples = sample_set()
  kpi.observe(samples, 64)
  |> should.equal(kpi.observe(list.reverse(samples), 64))
}

pub fn maturity_requires_prefix_evidence_and_never_scores_experience_test() {
  let assert Ok(observation) =
    kpi.observe(
      [
        kpi.AwarenessEvidence("adaptation-only", kpi.VerifiedAdaptationObserved),
      ],
      8,
    )
  observation.functional_awareness
  |> should.equal(kpi.FunctionalAwareness(0, ["verified-adaptation-observed"]))
  let assert kpi.ConsciousnessAssessment(kpi.Unestablished, None, _) =
    observation.consciousness
}

pub fn clock_domain_mismatch_makes_freshness_unavailable_test() {
  let assert Ok(observation) =
    kpi.observe(
      [
        kpi.SharedStateObservation(
          "state:mismatched-clock",
          kpi.ClockDomain("nas-1", "boot-a"),
          kpi.ClockDomain("nas-1", "boot-b"),
          900,
          1000,
          200,
          4,
          4,
        ),
      ],
      8,
    )
  let assert kpi.MissingMetric(
    _,
    "SharedStateObservation(comparable-clock-domain)",
    "at least one host+boot clock domain is mismatched or uncomparable",
  ) = observation.shared_state_freshness
}

pub fn future_timestamp_in_comparable_clock_domain_is_rejected_test() {
  kpi.observe(
    [
      kpi.SharedStateObservation(
        "state:future",
        clock(),
        clock(),
        1001,
        1000,
        200,
        4,
        4,
      ),
    ],
    8,
  )
  |> should.equal(
    Error(kpi.InvalidSample(
      "state:future",
      "future timestamp in a comparable host+boot clock domain",
    )),
  )
}

pub fn sample_bounds_are_enforced_test() {
  kpi.observe([], 0) |> should.equal(Error(kpi.InvalidBound(0)))
  kpi.observe(
    [
      kpi.VerifiedTaskOutcome("task:1", True),
      kpi.VerifiedTaskOutcome("task:2", True),
    ],
    1,
  )
  |> should.equal(Error(kpi.TooManySamples(2, 1)))
}
