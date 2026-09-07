//// Versioned, deterministic KPI projection for shared hive evidence.
//// It observes validated public samples only. It cannot grant authority, infer
//// private model state, or turn absent evidence into a zero.

import gleam/dict
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub const schema = "uos-hive-kpi/v1"

pub const maximum_samples = 4096

pub type MetricReading {
  Measured(value: Int, sample_count: Int, scale: Int, unit: String)
  MissingMetric(source: String, required_sample_type: String, reason: String)
}

pub type MetricDefinition {
  MetricDefinition(
    id: String,
    version: Int,
    unit: String,
    required_sample_type: String,
  )
}

pub type ForecastDimension {
  Duration
  Cost
}

pub type AwarenessEvidenceKind {
  SharedStateObserved
  SelfMonitoringObserved
  PredictiveCalibrationObserved
  VerifiedAdaptationObserved
}

pub type ClockDomain {
  ClockDomain(host_id: String, boot_id: String)
}

pub type KpiSample {
  VerifiedTaskOutcome(sample_uid: String, succeeded: Bool)
  CapabilityRequirement(
    sample_uid: String,
    capability_id: String,
    admitted: Bool,
  )
  DecisionRecordCompleteness(
    sample_uid: String,
    present_fields: Int,
    required_fields: Int,
  )
  BinaryForecastResolution(
    sample_uid: String,
    probability_basis_points: Int,
    observed: Bool,
    precommitted: Bool,
  )
  ForecastAbsoluteError(
    sample_uid: String,
    dimension: ForecastDimension,
    absolute_error: Int,
    unit: String,
  )
  AcceptedResultCost(sample_uid: String, cost_micro_usd: Option(Int))
  CoordinationAttempt(
    sample_uid: String,
    delivered: Bool,
    ack_latency_us: Option(Int),
  )
  SharedStateObservation(
    sample_uid: String,
    source_clock: ClockDomain,
    observer_clock: ClockDomain,
    observed_at_us: Int,
    now_us: Int,
    freshness_limit_us: Int,
    present_fields: Int,
    required_fields: Int,
  )
  ConflictObservation(sample_uid: String, conflict: Bool)
  MissingDataObservation(sample_uid: String, missing: Bool)
  AwarenessEvidence(sample_uid: String, kind: AwarenessEvidenceKind)
}

pub type FunctionalAwareness {
  FunctionalAwareness(level: Int, observed_evidence: List(String))
}

pub type ResearchStatus {
  Unestablished
}

pub type ConsciousnessAssessment {
  ConsciousnessAssessment(
    research_status: ResearchStatus,
    level: Option(Int),
    statement: String,
  )
}

pub type ProjectionAuthority {
  ReadOnlyObservational
}

pub type HiveKpis {
  HiveKpis(
    schema: String,
    unique_samples: Int,
    duplicate_deliveries: Int,
    verified_task_success: MetricReading,
    verified_task_samples: MetricReading,
    admitted_capability_coverage: MetricReading,
    decision_record_completeness: MetricReading,
    binary_forecast_brier: MetricReading,
    duration_absolute_error: MetricReading,
    cost_absolute_error: MetricReading,
    cost_per_accepted_result: MetricReading,
    coordination_delivery: MetricReading,
    acknowledgement_latency: MetricReading,
    shared_state_freshness: MetricReading,
    shared_state_coverage: MetricReading,
    conflict_rate: MetricReading,
    missing_data_rate: MetricReading,
    functional_awareness: FunctionalAwareness,
    consciousness: ConsciousnessAssessment,
    authority: ProjectionAuthority,
  )
}

pub type KpiError {
  InvalidBound(max_samples: Int)
  TooManySamples(count: Int, maximum: Int)
  InvalidSample(sample_uid: String, reason: String)
  ConflictingReplay(sample_uid: String)
}

pub fn definitions() -> List(MetricDefinition) {
  [
    MetricDefinition(
      "verified_task_success",
      1,
      "basis-points",
      "VerifiedTaskOutcome",
    ),
    MetricDefinition("verified_task_samples", 1, "count", "VerifiedTaskOutcome"),
    MetricDefinition(
      "admitted_capability_coverage",
      1,
      "basis-points",
      "CapabilityRequirement",
    ),
    MetricDefinition(
      "decision_record_completeness",
      1,
      "basis-points",
      "DecisionRecordCompleteness",
    ),
    MetricDefinition(
      "binary_forecast_brier",
      1,
      "basis-points-squared",
      "BinaryForecastResolution(precommitted=true)",
    ),
    MetricDefinition(
      "duration_absolute_error",
      1,
      "sample-unit",
      "ForecastAbsoluteError(Duration)",
    ),
    MetricDefinition(
      "cost_absolute_error",
      1,
      "sample-unit",
      "ForecastAbsoluteError(Cost)",
    ),
    MetricDefinition(
      "cost_per_accepted_result",
      1,
      "micro-usd",
      "AcceptedResultCost(cost=known)",
    ),
    MetricDefinition(
      "coordination_delivery",
      1,
      "basis-points",
      "CoordinationAttempt",
    ),
    MetricDefinition(
      "acknowledgement_latency",
      1,
      "microseconds",
      "CoordinationAttempt(ack_latency_us=known)",
    ),
    MetricDefinition(
      "shared_state_freshness",
      1,
      "basis-points",
      "SharedStateObservation",
    ),
    MetricDefinition(
      "shared_state_coverage",
      1,
      "basis-points",
      "SharedStateObservation",
    ),
    MetricDefinition("conflict_rate", 1, "basis-points", "ConflictObservation"),
    MetricDefinition(
      "missing_data_rate",
      1,
      "basis-points",
      "MissingDataObservation",
    ),
  ]
}

fn sample_uid(sample: KpiSample) -> String {
  case sample {
    VerifiedTaskOutcome(uid, _)
    | CapabilityRequirement(uid, _, _)
    | DecisionRecordCompleteness(uid, _, _)
    | BinaryForecastResolution(uid, _, _, _)
    | ForecastAbsoluteError(uid, _, _, _)
    | AcceptedResultCost(uid, _)
    | CoordinationAttempt(uid, _, _)
    | SharedStateObservation(uid, _, _, _, _, _, _, _)
    | ConflictObservation(uid, _)
    | MissingDataObservation(uid, _)
    | AwarenessEvidence(uid, _) -> uid
  }
}

fn uid_valid(uid: String) -> Bool {
  !string.is_empty(uid) && string.length(uid) <= 256
}

fn valid_sample(sample: KpiSample) -> Result(Nil, KpiError) {
  let uid = sample_uid(sample)
  use _ <- result.try(case uid_valid(uid) {
    True -> Ok(Nil)
    False -> Error(InvalidSample(uid, "sample_uid must be 1..256 characters"))
  })
  case sample {
    CapabilityRequirement(_, capability, _) ->
      case string.is_empty(capability) {
        True -> Error(InvalidSample(uid, "capability_id must not be empty"))
        False -> Ok(Nil)
      }
    DecisionRecordCompleteness(_, present, required)
      if required <= 0 || present < 0 || present > required
    ->
      Error(InvalidSample(
        uid,
        "field counts must satisfy 0 <= present <= required",
      ))
    SharedStateObservation(
      _,
      source,
      observer,
      observed,
      now,
      limit,
      present,
      required,
    ) -> {
      let ClockDomain(source_host, source_boot) = source
      let ClockDomain(observer_host, observer_boot) = observer
      case
        string.is_empty(source_host)
        || string.is_empty(source_boot)
        || string.is_empty(observer_host)
        || string.is_empty(observer_boot)
        || observed < 0
        || now < 0
        || limit < 0
        || required <= 0
        || present < 0
        || present > required
      {
        True ->
          Error(InvalidSample(
            uid,
            "clock domains, freshness bounds, and field counts must be valid",
          ))
        False ->
          case source == observer && observed > now {
            True ->
              Error(InvalidSample(
                uid,
                "future timestamp in a comparable host+boot clock domain",
              ))
            False -> Ok(Nil)
          }
      }
    }
    BinaryForecastResolution(_, probability, _, _)
      if probability < 0 || probability > 10_000
    -> Error(InvalidSample(uid, "probability must be 0..10000 basis points"))
    ForecastAbsoluteError(_, _, error, unit) ->
      case error < 0 || string.is_empty(unit) {
        True ->
          Error(InvalidSample(
            uid,
            "forecast error must be non-negative with a unit",
          ))
        False -> Ok(Nil)
      }
    AcceptedResultCost(_, Some(cost)) if cost < 0 ->
      Error(InvalidSample(uid, "accepted result cost must be non-negative"))
    CoordinationAttempt(_, _, Some(latency)) if latency < 0 ->
      Error(InvalidSample(uid, "ACK latency must be non-negative"))
    _ -> Ok(Nil)
  }
}

fn deduplicate(
  samples: List(KpiSample),
) -> Result(#(List(KpiSample), Int), KpiError) {
  use state <- result.try(
    list.try_fold(samples, #(dict.new(), 0), fn(state, sample) {
      use _ <- result.try(valid_sample(sample))
      let #(seen, duplicates) = state
      let uid = sample_uid(sample)
      case dict.get(seen, uid) {
        Error(_) -> Ok(#(dict.insert(seen, uid, sample), duplicates))
        Ok(existing) if existing == sample -> Ok(#(seen, duplicates + 1))
        Ok(_) -> Error(ConflictingReplay(uid))
      }
    }),
  )
  let #(seen, duplicates) = state
  Ok(#(
    seen
      |> dict.to_list
      |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
      |> list.map(fn(pair) { pair.1 }),
    duplicates,
  ))
}

fn unavailable(required: String, reason: String) -> MetricReading {
  MissingMetric(schema, required, reason)
}

fn ratio(numerator: Int, denominator: Int, required: String) -> MetricReading {
  case denominator {
    0 -> unavailable(required, "zero denominator")
    _ ->
      Measured(numerator * 10_000 / denominator, denominator, 10_000, "ratio")
  }
}

fn count_metric(value: Int, required: String) -> MetricReading {
  case value {
    0 -> unavailable(required, "zero denominator")
    _ -> Measured(value, value, 1, "count")
  }
}

fn mean(
  total: Int,
  count: Int,
  unit: String,
  required: String,
) -> MetricReading {
  case count {
    0 -> unavailable(required, "zero denominator")
    _ -> Measured(total / count, count, 1, unit)
  }
}

fn matching(samples: List(KpiSample), predicate: fn(KpiSample) -> Bool) -> Int {
  list.count(samples, predicate)
}

fn forecast_error_metric(
  samples: List(KpiSample),
  dimension: ForecastDimension,
) -> MetricReading {
  let selected =
    list.filter_map(samples, fn(sample) {
      case sample {
        ForecastAbsoluteError(_, selected, error, unit)
          if selected == dimension
        -> Ok(#(error, unit))
        _ -> Error(Nil)
      }
    })
  case selected {
    [] -> unavailable("ForecastAbsoluteError", "zero denominator")
    [first, ..rest] ->
      case list.all(rest, fn(item) { item.1 == first.1 }) {
        False ->
          unavailable(
            "ForecastAbsoluteError",
            "mixed units cannot be aggregated",
          )
        True ->
          mean(
            list.fold(selected, 0, fn(total, item) { total + item.0 }),
            list.length(selected),
            first.1,
            "ForecastAbsoluteError",
          )
      }
  }
}

fn cost_per_result(samples: List(KpiSample)) -> MetricReading {
  let costs =
    list.filter_map(samples, fn(sample) {
      case sample {
        AcceptedResultCost(_, cost) -> Ok(cost)
        _ -> Error(Nil)
      }
    })
  case costs {
    [] -> unavailable("AcceptedResultCost", "zero denominator")
    _ ->
      case list.all(costs, fn(cost) { cost != None }) {
        False ->
          unavailable(
            "AcceptedResultCost(cost=known)",
            "at least one accepted result has unknown cost",
          )
        True -> {
          let total =
            list.fold(costs, 0, fn(total, cost) {
              case cost {
                Some(value) -> total + value
                None -> total
              }
            })
          mean(total, list.length(costs), "micro-usd", "AcceptedResultCost")
        }
      }
  }
}

fn awareness(samples: List(KpiSample)) -> FunctionalAwareness {
  let observed =
    list.filter_map(samples, fn(sample) {
      case sample {
        AwarenessEvidence(_, kind) -> Ok(kind)
        _ -> Error(Nil)
      }
    })
  let shared = list.contains(observed, SharedStateObserved)
  let monitoring = list.contains(observed, SelfMonitoringObserved)
  let calibration = list.contains(observed, PredictiveCalibrationObserved)
  let adaptation = list.contains(observed, VerifiedAdaptationObserved)
  let level = case shared, monitoring, calibration, adaptation {
    False, _, _, _ -> 0
    True, False, _, _ -> 1
    True, True, False, _ -> 2
    True, True, True, False -> 3
    True, True, True, True -> 4
  }
  let labels =
    [
      #(shared, "shared-state-observed"),
      #(monitoring, "self-monitoring-observed"),
      #(calibration, "predictive-calibration-observed"),
      #(adaptation, "verified-adaptation-observed"),
    ]
    |> list.filter_map(fn(item) {
      case item.0 {
        True -> Ok(item.1)
        False -> Error(Nil)
      }
    })
  FunctionalAwareness(level, labels)
}

fn freshness_metric(samples: List(KpiSample)) -> MetricReading {
  let state =
    list.fold(samples, #(0, 0, 0), fn(total, sample) {
      case sample {
        SharedStateObservation(
          _,
          source_clock,
          observer_clock,
          observed,
          now,
          limit,
          _,
          _,
        ) ->
          case source_clock == observer_clock && now >= observed {
            False -> #(total.0, total.1, total.2 + 1)
            True -> #(
              total.0
                + case now - observed <= limit {
                True -> 1
                False -> 0
              },
              total.1 + 1,
              total.2,
            )
          }
        _ -> total
      }
    })
  case state.2 {
    0 ->
      ratio(state.0, state.1, "SharedStateObservation(comparable-clock-domain)")
    _ ->
      unavailable(
        "SharedStateObservation(comparable-clock-domain)",
        "at least one host+boot clock domain is mismatched or uncomparable",
      )
  }
}

pub fn observe(
  samples: List(KpiSample),
  max_samples: Int,
) -> Result(HiveKpis, KpiError) {
  use _ <- result.try(case max_samples > 0 && max_samples <= maximum_samples {
    True -> Ok(Nil)
    False -> Error(InvalidBound(max_samples))
  })
  use _ <- result.try(case list.length(samples) <= max_samples {
    True -> Ok(Nil)
    False -> Error(TooManySamples(list.length(samples), max_samples))
  })
  use unique <- result.try(deduplicate(samples))
  let #(samples, duplicates) = unique
  let tasks =
    matching(samples, fn(sample) {
      case sample {
        VerifiedTaskOutcome(_, _) -> True
        _ -> False
      }
    })
  let successes =
    matching(samples, fn(sample) {
      case sample {
        VerifiedTaskOutcome(_, True) -> True
        _ -> False
      }
    })
  let capabilities =
    matching(samples, fn(sample) {
      case sample {
        CapabilityRequirement(_, _, _) -> True
        _ -> False
      }
    })
  let admitted =
    matching(samples, fn(sample) {
      case sample {
        CapabilityRequirement(_, _, True) -> True
        _ -> False
      }
    })
  let completeness =
    list.fold(samples, #(0, 0), fn(total, sample) {
      case sample {
        DecisionRecordCompleteness(_, present, required) -> #(
          total.0 + present,
          total.1 + required,
        )
        _ -> total
      }
    })
  let brier =
    list.fold(samples, #(0, 0), fn(total, sample) {
      case sample {
        BinaryForecastResolution(_, probability, observed, True) -> {
          let target = case observed {
            True -> 10_000
            False -> 0
          }
          let error = probability - target
          #(total.0 + error * error, total.1 + 1)
        }
        _ -> total
      }
    })
  let coordination =
    matching(samples, fn(sample) {
      case sample {
        CoordinationAttempt(_, _, _) -> True
        _ -> False
      }
    })
  let delivered =
    matching(samples, fn(sample) {
      case sample {
        CoordinationAttempt(_, True, _) -> True
        _ -> False
      }
    })
  let ack =
    list.fold(samples, #(0, 0), fn(total, sample) {
      case sample {
        CoordinationAttempt(_, _, Some(latency)) -> #(
          total.0 + latency,
          total.1 + 1,
        )
        _ -> total
      }
    })
  let coverage =
    list.fold(samples, #(0, 0), fn(total, sample) {
      case sample {
        SharedStateObservation(_, _, _, _, _, _, present, required) -> #(
          total.0 + present,
          total.1 + required,
        )
        _ -> total
      }
    })
  let conflicts =
    matching(samples, fn(sample) {
      case sample {
        ConflictObservation(_, True) -> True
        _ -> False
      }
    })
  let conflict_samples =
    matching(samples, fn(sample) {
      case sample {
        ConflictObservation(_, _) -> True
        _ -> False
      }
    })
  let missing =
    matching(samples, fn(sample) {
      case sample {
        MissingDataObservation(_, True) -> True
        _ -> False
      }
    })
  let missing_samples =
    matching(samples, fn(sample) {
      case sample {
        MissingDataObservation(_, _) -> True
        _ -> False
      }
    })
  Ok(HiveKpis(
    schema,
    list.length(samples),
    duplicates,
    ratio(successes, tasks, "VerifiedTaskOutcome"),
    count_metric(tasks, "VerifiedTaskOutcome"),
    ratio(admitted, capabilities, "CapabilityRequirement"),
    ratio(completeness.0, completeness.1, "DecisionRecordCompleteness"),
    mean(
      brier.0,
      brier.1,
      "basis-points-squared",
      "BinaryForecastResolution(precommitted=true)",
    ),
    forecast_error_metric(samples, Duration),
    forecast_error_metric(samples, Cost),
    cost_per_result(samples),
    ratio(delivered, coordination, "CoordinationAttempt"),
    mean(
      ack.0,
      ack.1,
      "microseconds",
      "CoordinationAttempt(ack_latency_us=known)",
    ),
    freshness_metric(samples),
    ratio(coverage.0, coverage.1, "SharedStateObservation"),
    ratio(conflicts, conflict_samples, "ConflictObservation"),
    ratio(missing, missing_samples, "MissingDataObservation"),
    awareness(samples),
    ConsciousnessAssessment(
      Unestablished,
      None,
      "Functional proxies do not establish subjective experience or consciousness.",
    ),
    ReadOnlyObservational,
  ))
}
