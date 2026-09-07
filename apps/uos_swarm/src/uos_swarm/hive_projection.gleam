//// Deterministic, read-only hive awareness over validated public decision records.
//// The projection preserves disagreements and missing data. It never grants a
//// lease, budget, approval, capability, or permission and invokes no action.

import gleam/dict
import gleam/int
import gleam/list
import gleam/result
import gleam/string
import uos_swarm/decision_record as decision

pub const schema = "uos-hive-awareness/v1"

pub const maximum_records = 4096

pub type CurrentResourceEpoch {
  CurrentResourceEpoch(resource: String, epoch: Int)
}

pub type Provenance {
  Provenance(
    decision_id: String,
    actor_identity: String,
    actor_kind: decision.ActorKind,
    session: String,
    provider: decision.ReviewValue,
    model: decision.ReviewValue,
    state_source: decision.StateSource,
    candidate_revision: String,
    evidence_refs: List(String),
  )
}

pub type SharedState {
  SharedState(
    provenance: Provenance,
    task_id: String,
    goal: String,
    resource: String,
    epoch: Int,
    current_goals: List(decision.ReviewValue),
    evidence: List(decision.Belief),
    hypotheses: List(decision.Belief),
    uncertain_beliefs: List(decision.Belief),
    uncertainties: List(decision.ReviewValue),
    intended_next_actions: List(decision.ReviewValue),
    selected_action: String,
    forecast: decision.Forecast,
  )
}

pub type ConflictKind {
  IntendedActionConflict
  DeclaredGoalConflict
  DeclaredForecastConflict
  CandidateAheadOfCurrentEpoch
  MultipleCompletionConflict
}

pub type Conflict {
  Conflict(
    kind: ConflictKind,
    resource: String,
    epoch: Int,
    decision_ids: List(String),
    declarations: List(String),
  )
}

pub type AggregateConfidence {
  MeasuredAggregate(basis_refs: List(String))
  EstimatedAggregate(basis_refs: List(String))
  UnknownAggregate(reasons: List(String))
}

pub type CostAggregate {
  AdditiveCost(value: Int, unit: String, unique_attempts: Int, basis: String)
  CostUnknown(reason: String)
}

pub type ParallelWallTime {
  ParallelWallTimeUnknown(reason: String)
}

pub type StateFreshness {
  FreshnessComparable(active_records: Int, clock_domains: List(String))
  FreshnessUnknown(reasons: List(String))
}

pub type HistoricalCounts {
  HistoricalCounts(
    stale_snapshots: Int,
    superseded_snapshots: Int,
    expired_records: Int,
    unknown_freshness: Int,
    stale_epochs: Int,
    missing_current_epochs: Int,
    completions: Int,
    duplicate_deliveries: Int,
  )
}

pub type ProjectionAuthority {
  ReadOnlyObservational
}

pub type HiveAwareness {
  HiveAwareness(
    schema: String,
    hive_id: String,
    tenant_id: String,
    active: List(SharedState),
    history: HistoricalCounts,
    conflicts: List(Conflict),
    forecast_confidence: AggregateConfidence,
    active_expected_cost: CostAggregate,
    observed_completed_cost: CostAggregate,
    state_freshness: StateFreshness,
    parallel_wall_time: ParallelWallTime,
    advisories: List(String),
    authority: ProjectionAuthority,
  )
}

pub type ProjectionError {
  InvalidBound(max_records: Int)
  TooManyRecords(count: Int, maximum: Int)
  InvalidPartition
  InvalidCurrentEpoch(resource: String, epoch: Int)
  ConflictingCurrentEpoch(resource: String)
  ConflictingRecordReplay(decision_id: String)
}

fn exact_partition(
  record: decision.ValidatedRecord,
  hive_id: String,
  tenant_id: String,
) -> Bool {
  decision.validated_hive_id(record) == hive_id
  && decision.validated_tenant_id(record) == tenant_id
}

fn deduplicate(
  records: List(decision.ValidatedRecord),
) -> Result(#(List(decision.ValidatedRecord), Int), ProjectionError) {
  use state <- result.try(
    list.try_fold(records, #(dict.new(), 0), fn(state, record) {
      let #(seen, duplicates) = state
      let id = decision.validated_decision_id(record)
      case dict.get(seen, id) {
        Error(_) -> Ok(#(dict.insert(seen, id, record), duplicates))
        Ok(existing) ->
          case
            decision.validated_record_view(existing)
            == decision.validated_record_view(record)
            && decision.validated_freshness(existing)
            == decision.validated_freshness(record)
          {
            True -> Ok(#(seen, duplicates + 1))
            False -> Error(ConflictingRecordReplay(id))
          }
      }
    }),
  )
  let #(seen, duplicates) = state
  Ok(#(
    seen
      |> dict.values
      |> list.sort(fn(a, b) {
        string.compare(
          decision.validated_decision_id(a),
          decision.validated_decision_id(b),
        )
      }),
    duplicates,
  ))
}

fn epoch_index(
  epochs: List(CurrentResourceEpoch),
) -> Result(dict.Dict(String, Int), ProjectionError) {
  list.try_fold(epochs, dict.new(), fn(index, item) {
    use _ <- result.try(case string.is_empty(item.resource) || item.epoch <= 0 {
      True -> Error(InvalidCurrentEpoch(item.resource, item.epoch))
      False -> Ok(Nil)
    })
    case dict.get(index, item.resource) {
      Error(_) -> Ok(dict.insert(index, item.resource, item.epoch))
      Ok(epoch) if epoch == item.epoch -> Ok(index)
      Ok(_) -> Error(ConflictingCurrentEpoch(item.resource))
    }
  })
}

fn provenance(prepared: decision.PreparedDecision) -> Provenance {
  Provenance(
    prepared.decision_id,
    prepared.actor.identity,
    prepared.actor.kind,
    prepared.actor.session,
    prepared.actor.provider,
    prepared.actor.model,
    prepared.state.source,
    prepared.candidate_revision,
    prepared.evidence_refs,
  )
}

fn shared_state(prepared: decision.PreparedDecision) -> SharedState {
  SharedState(
    provenance(prepared),
    prepared.task_id,
    prepared.goal,
    prepared.resource,
    prepared.epoch,
    prepared.state.current_goals,
    list.filter(prepared.state.beliefs, fn(belief) {
      belief.status == decision.EvidenceBound
    }),
    list.filter(prepared.state.beliefs, fn(belief) {
      belief.status == decision.Hypothesis
    }),
    list.filter(prepared.state.beliefs, fn(belief) {
      belief.status == decision.Uncertain
    }),
    prepared.state.uncertainties,
    prepared.state.intended_next_actions,
    prepared.selected_action,
    prepared.forecast,
  )
}

fn review_declaration(value: decision.ReviewValue) -> String {
  case value {
    decision.Stated(text) -> "stated:" <> text
    decision.Unknown(reason) -> "unknown:" <> reason
    decision.NotApplicable(reason) -> "not-applicable:" <> reason
  }
}

fn stated(value: decision.ReviewValue) -> Bool {
  case value {
    decision.Stated(_) -> True
    _ -> False
  }
}

fn stated_declarations(values: List(decision.ReviewValue)) -> List(String) {
  values
  |> list.filter_map(fn(value) {
    case value {
      decision.Stated(text) -> Ok(text)
      _ -> Error(Nil)
    }
  })
  |> list.unique
  |> list.sort(string.compare)
}

fn pair_conflicts(
  first: decision.PreparedDecision,
  next: decision.PreparedDecision,
) -> List(Conflict) {
  let ids = [first.decision_id, next.decision_id]
  let first_intended = stated_declarations(first.state.intended_next_actions)
  let next_intended = stated_declarations(next.state.intended_next_actions)
  let action = case
    first.selected_action == next.selected_action
    && case first_intended, next_intended {
      [], _ | _, [] -> True
      _, _ -> first_intended == next_intended
    }
  {
    True -> []
    False -> [
      Conflict(IntendedActionConflict, first.resource, first.epoch, ids, [
        first.selected_action,
        next.selected_action,
        ..list.append(first_intended, next_intended)
      ]),
    ]
  }
  let first_current_goals = stated_declarations(first.state.current_goals)
  let next_current_goals = stated_declarations(next.state.current_goals)
  let goals = case
    first.goal == next.goal
    && case first_current_goals, next_current_goals {
      [], _ | _, [] -> True
      _, _ -> first_current_goals == next_current_goals
    }
  {
    True -> []
    False -> [
      Conflict(DeclaredGoalConflict, first.resource, first.epoch, ids, [
        first.goal,
        next.goal,
        ..list.append(first_current_goals, next_current_goals)
      ]),
    ]
  }
  let first_forecast = first.forecast.predicted_outcome
  let next_forecast = next.forecast.predicted_outcome
  let forecasts = case
    stated(first_forecast)
    && stated(next_forecast)
    && first_forecast != next_forecast
  {
    True -> [
      Conflict(DeclaredForecastConflict, first.resource, first.epoch, ids, [
        review_declaration(first_forecast),
        review_declaration(next_forecast),
      ]),
    ]
    False -> []
  }
  list.append(action, list.append(goals, forecasts))
}

fn confidence_meet(active: List(SharedState)) -> AggregateConfidence {
  let observations = list.map(active, fn(item) { item.forecast.confidence })
  let unknown =
    list.filter_map(observations, fn(confidence) {
      case confidence {
        decision.UnknownConfidence(reason) -> Ok(reason)
        _ -> Error(Nil)
      }
    })
  let estimated =
    list.filter_map(observations, fn(confidence) {
      case confidence {
        decision.EstimatedConfidence(basis) -> Ok(basis)
        _ -> Error(Nil)
      }
    })
  let measured =
    list.filter_map(observations, fn(confidence) {
      case confidence {
        decision.MeasuredConfidence(basis) -> Ok(basis)
        _ -> Error(Nil)
      }
    })
  case unknown, estimated, measured {
    [_, ..], _, _ ->
      UnknownAggregate(unknown |> list.unique |> list.sort(string.compare))
    [], [_, ..], _ ->
      EstimatedAggregate(
        list.append(estimated, measured)
        |> list.unique
        |> list.sort(string.compare),
      )
    [], [], [] -> UnknownAggregate(["no active forecasts"])
    [], [], _ ->
      MeasuredAggregate(measured |> list.unique |> list.sort(string.compare))
  }
}

fn aggregate_cost(
  estimates: List(decision.Estimate),
  unique_attempts: Int,
  basis: String,
) -> CostAggregate {
  case estimates {
    [] -> CostUnknown("no matching cost observations")
    _ -> {
      let missing =
        list.filter_map(estimates, fn(estimate) {
          case estimate {
            decision.UnknownEstimate(reason) -> Ok("unknown:" <> reason)
            decision.NotApplicableEstimate(reason) ->
              Ok("not-applicable:" <> reason)
            decision.Estimated(_, _, _) -> Error(Nil)
          }
        })
      let measured =
        list.filter_map(estimates, fn(estimate) {
          case estimate {
            decision.Estimated(value, unit, _) -> Ok(#(value, unit))
            _ -> Error(Nil)
          }
        })
      case missing, measured {
        [_, ..], _ ->
          CostUnknown(
            missing
            |> list.unique
            |> list.sort(string.compare)
            |> string.join("; "),
          )
        [], [] -> CostUnknown("no numeric cost observations")
        [], [first, ..rest] ->
          case list.all(rest, fn(item) { item.1 == first.1 }) {
            False -> CostUnknown("mixed cost units cannot be aggregated")
            True ->
              AdditiveCost(
                list.fold(measured, 0, fn(total, item) { total + item.0 }),
                first.1,
                unique_attempts,
                basis,
              )
          }
      }
    }
  }
}

fn historical_cost(
  completions: List(decision.CompletedDecision),
) -> #(CostAggregate, List(Conflict)) {
  let state =
    list.fold(completions, #(dict.new(), []), fn(state, completed) {
      let #(attempts, conflicts) = state
      case dict.get(attempts, completed.prepared_decision_id) {
        Error(_) -> #(
          dict.insert(attempts, completed.prepared_decision_id, completed),
          conflicts,
        )
        Ok(first) -> #(attempts, [
          Conflict(
            MultipleCompletionConflict,
            completed.resource,
            completed.epoch,
            [first.decision_id, completed.decision_id],
            [first.prepared_decision_id],
          ),
          ..conflicts
        ])
      }
    })
  let #(attempts, conflicts) = state
  case conflicts {
    [_, ..] -> #(
      CostUnknown("multiple completion records exist for one planned attempt"),
      list.reverse(conflicts),
    )
    [] -> {
      let values = dict.values(attempts)
      #(
        aggregate_cost(
          list.map(values, fn(completed) { completed.observed_cost }),
          list.length(values),
          "deduplicated by prepared_decision_id",
        ),
        [],
      )
    }
  }
}

fn freshness_projection(
  records: List(decision.ValidatedRecord),
  active: List(SharedState),
) -> StateFreshness {
  let unknown =
    list.filter_map(records, fn(record) {
      case decision.validated_freshness(record) {
        decision.RecordFreshnessUnknown(reason) -> Ok(reason)
        _ -> Error(Nil)
      }
    })
  case unknown {
    [_, ..] ->
      FreshnessUnknown(unknown |> list.unique |> list.sort(string.compare))
    [] -> {
      let domains =
        list.map(active, fn(item) {
          let decision.ClockDomain(host, boot) = item.forecast.clock
          host <> "/" <> boot
        })
        |> list.unique
        |> list.sort(string.compare)
      FreshnessComparable(list.length(active), domains)
    }
  }
}

pub fn project(
  records: List(decision.ValidatedRecord),
  hive_id: String,
  tenant_id: String,
  current_epochs: List(CurrentResourceEpoch),
  max_records: Int,
) -> Result(HiveAwareness, ProjectionError) {
  use _ <- result.try(case max_records > 0 && max_records <= maximum_records {
    True -> Ok(Nil)
    False -> Error(InvalidBound(max_records))
  })
  use _ <- result.try(case list.length(records) <= max_records {
    True -> Ok(Nil)
    False -> Error(TooManyRecords(list.length(records), max_records))
  })
  use _ <- result.try(
    case string.is_empty(hive_id) || string.is_empty(tenant_id) {
      True -> Error(InvalidPartition)
      False -> Ok(Nil)
    },
  )
  use epochs <- result.try(epoch_index(current_epochs))
  let partition =
    list.filter(records, fn(record) {
      exact_partition(record, hive_id, tenant_id)
    })
  use unique <- result.try(deduplicate(partition))
  let #(records, duplicates) = unique
  let initial = #([], [], 0, 0, 0, 0, 0, 0, [], dict.new())
  let folded =
    list.fold(records, initial, fn(state, record) {
      let #(
        active,
        completions,
        stale,
        superseded,
        expired,
        unknown_freshness,
        stale_epochs,
        missing_epochs,
        conflicts,
        by_resource,
      ) = state
      case decision.validated_record_view(record) {
        decision.CompletedView(completed) -> #(
          active,
          [completed, ..completions],
          stale,
          superseded,
          expired,
          unknown_freshness,
          stale_epochs,
          missing_epochs,
          conflicts,
          by_resource,
        )
        decision.PreparedView(prepared) ->
          case decision.validated_freshness(record) {
            decision.RecordDeclaredStale(_) -> #(
              active,
              completions,
              stale + 1,
              superseded,
              expired,
              unknown_freshness,
              stale_epochs,
              missing_epochs,
              conflicts,
              by_resource,
            )
            decision.RecordSuperseded(_) -> #(
              active,
              completions,
              stale,
              superseded + 1,
              expired,
              unknown_freshness,
              stale_epochs,
              missing_epochs,
              conflicts,
              by_resource,
            )
            decision.RecordExpired -> #(
              active,
              completions,
              stale,
              superseded,
              expired + 1,
              unknown_freshness,
              stale_epochs,
              missing_epochs,
              conflicts,
              by_resource,
            )
            decision.RecordFreshnessUnknown(_) -> #(
              active,
              completions,
              stale,
              superseded,
              expired,
              unknown_freshness + 1,
              stale_epochs,
              missing_epochs,
              conflicts,
              by_resource,
            )
            decision.CompletionFreshnessNotApplicable -> #(
              active,
              completions,
              stale,
              superseded,
              expired,
              unknown_freshness + 1,
              stale_epochs,
              missing_epochs,
              conflicts,
              by_resource,
            )
            decision.RecordCurrent ->
              case dict.get(epochs, prepared.resource) {
                Error(_) -> #(
                  active,
                  completions,
                  stale,
                  superseded,
                  expired,
                  unknown_freshness,
                  stale_epochs,
                  missing_epochs + 1,
                  conflicts,
                  by_resource,
                )
                Ok(epoch) if prepared.epoch < epoch -> #(
                  active,
                  completions,
                  stale,
                  superseded,
                  expired,
                  unknown_freshness,
                  stale_epochs + 1,
                  missing_epochs,
                  conflicts,
                  by_resource,
                )
                Ok(epoch) if prepared.epoch > epoch -> #(
                  active,
                  completions,
                  stale,
                  superseded,
                  expired,
                  unknown_freshness,
                  stale_epochs,
                  missing_epochs,
                  [
                    Conflict(
                      CandidateAheadOfCurrentEpoch,
                      prepared.resource,
                      prepared.epoch,
                      [prepared.decision_id],
                      ["current_epoch=" <> int.to_string(epoch)],
                    ),
                    ..conflicts
                  ],
                  by_resource,
                )
                Ok(_) -> {
                  let key = #(prepared.resource, prepared.epoch)
                  let additional = case dict.get(by_resource, key) {
                    Error(_) -> []
                    Ok(first) -> pair_conflicts(first, prepared)
                  }
                  #(
                    [shared_state(prepared), ..active],
                    completions,
                    stale,
                    superseded,
                    expired,
                    unknown_freshness,
                    stale_epochs,
                    missing_epochs,
                    list.append(additional, conflicts),
                    case dict.get(by_resource, key) {
                      Error(_) -> dict.insert(by_resource, key, prepared)
                      Ok(_) -> by_resource
                    },
                  )
                }
              }
          }
      }
    })
  let #(
    active,
    completions,
    stale,
    superseded,
    expired,
    unknown_freshness,
    stale_epochs,
    missing_epochs,
    conflicts,
    _,
  ) = folded
  let active = list.reverse(active)
  let completions = list.reverse(completions)
  let #(observed_cost, completion_conflicts) = historical_cost(completions)
  let conflicts =
    list.append(conflicts, completion_conflicts)
    |> list.sort(fn(a, b) {
      string.compare(
        string.join(a.decision_ids, ":"),
        string.join(b.decision_ids, ":"),
      )
    })
  let expected_cost =
    aggregate_cost(
      list.map(active, fn(item) { item.forecast.expected_cost }),
      list.length(active),
      "one active PreparedDecision decision_id per planned attempt",
    )
  let advisories =
    [
      #(list.is_empty(conflicts), "escalate declared hive conflicts for review"),
      #(missing_epochs == 0, "supply current resource epochs before scheduling"),
      #(
        list.is_empty(active),
        "no active shared state is available for scheduling advice",
      ),
    ]
    |> list.filter_map(fn(item) {
      case item.0 {
        True -> Error(Nil)
        False -> Ok(item.1)
      }
    })
  Ok(HiveAwareness(
    schema,
    hive_id,
    tenant_id,
    active,
    HistoricalCounts(
      stale,
      superseded,
      expired,
      unknown_freshness,
      stale_epochs,
      missing_epochs,
      list.length(completions),
      duplicates,
    ),
    conflicts,
    confidence_meet(active),
    expected_cost,
    observed_cost,
    freshness_projection(records, active),
    ParallelWallTimeUnknown(
      "DecisionRecord v1 has no dependency graph; parallel wall time is not additive",
    ),
    advisories,
    ReadOnlyObservational,
  ))
}
