//// Versioned public decision and forecast record for the UOS hive.
////
//// Records contain bounded review summaries and evidence references only. They
//// do not request private reasoning, raw prompts, hidden memory, secrets, or
//// claims about consciousness. Forecasts and completed reports are advisory
//// evidence and never authorize an action.

import gleam/dynamic/decode
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub const schema = "uos-decision-record/v1"

pub type ReviewValue {
  Stated(value: String)
  Unknown(reason: String)
  NotApplicable(reason: String)
}

pub type ActorKind {
  ModelActor
  DeterministicActor
}

pub type Actor {
  Actor(
    identity: String,
    kind: ActorKind,
    session: String,
    provider: ReviewValue,
    model: ReviewValue,
  )
}

pub type Estimate {
  Estimated(value: Int, unit: String, basis_ref: String)
  UnknownEstimate(reason: String)
  NotApplicableEstimate(reason: String)
}

pub type Budget {
  Budget(max_cost: Estimate, max_tokens: Estimate, max_wall_time: Estimate)
}

/// Host and boot identity for boot-relative monotonic timestamps.
pub type ClockDomain {
  ClockDomain(host_id: String, boot_id: String)
}

pub type StateSource {
  ModelSelfReport
  MeasuredRuntime
  Inference
  DeterministicRuleState
}

pub type SnapshotStatus {
  SnapshotCurrent
  SnapshotStale(reason: String)
  SnapshotSuperseded(by_snapshot_id: String)
}

pub type EpistemicStatus {
  EvidenceBound
  Hypothesis
  Uncertain
}

pub type Belief {
  Belief(
    statement: String,
    evidence_refs: List(String),
    status: EpistemicStatus,
    source: StateSource,
  )
}

pub type StateSnapshot {
  StateSnapshot(
    snapshot_id: String,
    clock: ClockDomain,
    as_of_boot_us: Int,
    status: SnapshotStatus,
    source: StateSource,
    current_goals: List(ReviewValue),
    subgoals: List(ReviewValue),
    beliefs: List(Belief),
    uncertainties: List(ReviewValue),
    open_questions: List(ReviewValue),
    constraints: List(ReviewValue),
    resources: List(ReviewValue),
    budget: Budget,
    attention: ReviewValue,
    active_task: ReviewValue,
    intended_next_actions: List(ReviewValue),
  )
}

pub type ConfidenceBasis {
  MeasuredConfidence(basis_ref: String)
  EstimatedConfidence(basis_ref: String)
  UnknownConfidence(reason: String)
}

pub type Probability {
  PointProbability(basis_points: Int, basis_ref: String)
  ProbabilityRange(
    low_basis_points: Int,
    high_basis_points: Int,
    basis_ref: String,
  )
  UnknownProbability(reason: String)
  NotApplicableProbability(reason: String)
}

pub type Forecast {
  Forecast(
    clock: ClockDomain,
    horizon: String,
    as_of_boot_us: Int,
    expires_boot_us: Int,
    predicted_outcome: ReviewValue,
    alternatives: List(ReviewValue),
    assumptions: List(ReviewValue),
    confidence: ConfidenceBasis,
    probability: Probability,
    expected_duration: Estimate,
    expected_cost: Estimate,
    expected_resources: List(ReviewValue),
    failure_signals: List(ReviewValue),
    update_triggers: List(ReviewValue),
    observed_outcome: ReviewValue,
    calibration_ref: ReviewValue,
  )
}

pub type Alternative {
  Alternative(option: String, tradeoff: String)
}

pub type ProcessStep {
  ProcessStep(order: Int, summary: String, evidence: ReviewValue)
}

pub type PreparedDecision {
  PreparedDecision(
    decision_id: String,
    hive_id: String,
    tenant_id: String,
    actor: Actor,
    task_id: String,
    goal: String,
    candidate_revision: String,
    resource: String,
    epoch: Int,
    evidence_refs: List(String),
    constraints: List(ReviewValue),
    policy: ReviewValue,
    budget: Budget,
    alternatives: List(Alternative),
    selected_action: String,
    rationale: String,
    uncertainties: List(ReviewValue),
    risks: List(ReviewValue),
    process: List(ProcessStep),
    authorization_refs: List(String),
    verification_plan: ReviewValue,
    rollback_plan: ReviewValue,
    state: StateSnapshot,
    forecast: Forecast,
  )
}

pub type DecisionOutcome {
  Succeeded(summary: String)
  Failed(reason: String)
  OutcomeUnknown(reason: String)
  OutcomeNotApplicable(reason: String)
}

pub type CompletedDecision {
  CompletedDecision(
    decision_id: String,
    prepared_decision_id: String,
    hive_id: String,
    tenant_id: String,
    actor: Actor,
    task_id: String,
    candidate_revision: String,
    resource: String,
    epoch: Int,
    selected_action: String,
    outcome: DecisionOutcome,
    observed_evidence_refs: List(String),
    observed_cost: Estimate,
    process: List(ProcessStep),
    verification_result: ReviewValue,
    rollback_result: ReviewValue,
    observed_outcome: ReviewValue,
    calibration_ref: ReviewValue,
  )
}

pub type Record {
  PreparedRecord(PreparedDecision)
  CompletedRecord(CompletedDecision)
}

pub type RecordPhase {
  PreparedPhase
  CompletedPhase
}

/// Read-only public projection of a structurally validated shared record.
/// Possession of this view cannot authorize an action.
pub type ValidatedRecordView {
  PreparedView(PreparedDecision)
  CompletedView(CompletedDecision)
}

pub type RecordFreshness {
  RecordCurrent
  RecordExpired
  RecordDeclaredStale(reason: String)
  RecordSuperseded(by_snapshot_id: String)
  RecordFreshnessUnknown(reason: String)
  CompletionFreshnessNotApplicable
}

pub type ExpectedDecision {
  ExpectedDecision(
    hive_id: String,
    tenant_id: String,
    clock: ClockDomain,
    actor_identity: String,
    actor_kind: ActorKind,
    session: String,
    task_id: String,
    candidate_revision: String,
    resource: String,
    epoch: Int,
    selected_action: String,
  )
}

pub opaque type ValidatedDecision {
  ValidatedDecision(prepared: PreparedDecision)
}

pub opaque type ValidatedCompletion {
  ValidatedCompletion(completed: CompletedDecision)
}

pub opaque type ValidatedRecord {
  ValidatedPreparedRecord(
    prepared: PreparedDecision,
    freshness: RecordFreshness,
  )
  ValidatedCompletedRecord(
    completed: CompletedDecision,
    freshness: RecordFreshness,
  )
}

fn require(condition: Bool, reason: String) -> Result(Nil, String) {
  case condition {
    True -> Ok(Nil)
    False -> Error(reason)
  }
}

fn bounded(value: String, maximum: Int) -> Bool {
  value != ""
  && string.length(value) <= maximum
  && !string.contains(value, "\u{0000}")
}

fn identifier(value: String) -> Bool {
  bounded(value, 128)
  && value
  |> string.to_graphemes
  |> list.all(fn(character) {
    string.contains(
      "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.:/@",
      character,
    )
  })
}

fn refs_valid(refs: List(String)) -> Bool {
  !list.is_empty(refs)
  && list.length(refs) <= 32
  && list.all(refs, fn(reference) { bounded(reference, 1024) })
}

fn review_valid(value: ReviewValue) -> Bool {
  case value {
    Stated(text) -> bounded(text, 4096)
    Unknown(reason) | NotApplicable(reason) -> bounded(reason, 1024)
  }
}

fn reviews_valid(values: List(ReviewValue)) -> Bool {
  !list.is_empty(values)
  && list.length(values) <= 32
  && list.all(values, review_valid)
}

fn estimate_valid(estimate: Estimate) -> Bool {
  case estimate {
    Estimated(value, unit, basis) ->
      value >= 0 && bounded(unit, 64) && bounded(basis, 1024)
    UnknownEstimate(reason) | NotApplicableEstimate(reason) ->
      bounded(reason, 1024)
  }
}

fn budget_valid(budget: Budget) -> Bool {
  estimate_valid(budget.max_cost)
  && estimate_valid(budget.max_tokens)
  && estimate_valid(budget.max_wall_time)
}

fn clock_valid(clock: ClockDomain) -> Bool {
  identifier(clock.host_id) && identifier(clock.boot_id)
}

fn actor_valid(actor: Actor) -> Bool {
  let model_kind_valid = case actor.kind, actor.model {
    DeterministicActor, NotApplicable(_) -> True
    DeterministicActor, _ -> False
    ModelActor, NotApplicable(_) -> False
    ModelActor, _ -> True
  }
  identifier(actor.identity)
  && identifier(actor.session)
  && review_valid(actor.provider)
  && review_valid(actor.model)
  && model_kind_valid
}

fn source_valid(actor_kind: ActorKind, source: StateSource) -> Bool {
  case actor_kind, source {
    ModelActor, DeterministicRuleState -> False
    DeterministicActor, ModelSelfReport -> False
    _, _ -> True
  }
}

fn belief_valid(belief: Belief, actor_kind: ActorKind) -> Bool {
  bounded(belief.statement, 4096)
  && refs_valid(belief.evidence_refs)
  && source_valid(actor_kind, belief.source)
}

fn snapshot_valid(snapshot: StateSnapshot, actor_kind: ActorKind) -> Bool {
  let status_valid = case snapshot.status {
    SnapshotCurrent -> True
    SnapshotStale(reason) -> bounded(reason, 1024)
    SnapshotSuperseded(id) -> identifier(id)
  }
  identifier(snapshot.snapshot_id)
  && clock_valid(snapshot.clock)
  && snapshot.as_of_boot_us >= 0
  && status_valid
  && source_valid(actor_kind, snapshot.source)
  && reviews_valid(snapshot.current_goals)
  && reviews_valid(snapshot.subgoals)
  && !list.is_empty(snapshot.beliefs)
  && list.length(snapshot.beliefs) <= 32
  && list.all(snapshot.beliefs, fn(belief) { belief_valid(belief, actor_kind) })
  && reviews_valid(snapshot.uncertainties)
  && reviews_valid(snapshot.open_questions)
  && reviews_valid(snapshot.constraints)
  && reviews_valid(snapshot.resources)
  && budget_valid(snapshot.budget)
  && review_valid(snapshot.attention)
  && review_valid(snapshot.active_task)
  && reviews_valid(snapshot.intended_next_actions)
}

fn confidence_valid(confidence: ConfidenceBasis) -> Bool {
  case confidence {
    MeasuredConfidence(reference) | EstimatedConfidence(reference) ->
      bounded(reference, 1024)
    UnknownConfidence(reason) -> bounded(reason, 1024)
  }
}

fn probability_valid(
  confidence: ConfidenceBasis,
  probability: Probability,
) -> Bool {
  let numeric_justified = case confidence {
    MeasuredConfidence(_) | EstimatedConfidence(_) -> True
    UnknownConfidence(_) -> False
  }
  case probability {
    PointProbability(value, basis) ->
      numeric_justified && value >= 0 && value <= 10_000 && bounded(basis, 1024)
    ProbabilityRange(low, high, basis) ->
      numeric_justified
      && low >= 0
      && low <= high
      && high <= 10_000
      && bounded(basis, 1024)
    UnknownProbability(reason) | NotApplicableProbability(reason) ->
      bounded(reason, 1024)
  }
}

fn forecast_valid(forecast: Forecast, snapshot: StateSnapshot) -> Bool {
  clock_valid(forecast.clock)
  && forecast.clock == snapshot.clock
  && bounded(forecast.horizon, 512)
  && forecast.as_of_boot_us >= snapshot.as_of_boot_us
  && forecast.as_of_boot_us < forecast.expires_boot_us
  && review_valid(forecast.predicted_outcome)
  && reviews_valid(forecast.alternatives)
  && reviews_valid(forecast.assumptions)
  && confidence_valid(forecast.confidence)
  && probability_valid(forecast.confidence, forecast.probability)
  && estimate_valid(forecast.expected_duration)
  && estimate_valid(forecast.expected_cost)
  && reviews_valid(forecast.expected_resources)
  && reviews_valid(forecast.failure_signals)
  && reviews_valid(forecast.update_triggers)
  && review_valid(forecast.observed_outcome)
  && review_valid(forecast.calibration_ref)
}

fn alternatives_valid(alternatives: List(Alternative)) -> Bool {
  !list.is_empty(alternatives)
  && list.length(alternatives) <= 16
  && list.all(alternatives, fn(alternative) {
    bounded(alternative.option, 1024) && bounded(alternative.tradeoff, 2048)
  })
}

fn process_valid(steps: List(ProcessStep)) -> Bool {
  !list.is_empty(steps)
  && list.length(steps) <= 64
  && process_ordered(steps, 1)
  && list.all(steps, fn(step) {
    bounded(step.summary, 2048) && review_valid(step.evidence)
  })
}

fn process_ordered(steps: List(ProcessStep), expected: Int) -> Bool {
  case steps {
    [] -> True
    [step, ..rest] ->
      step.order == expected && process_ordered(rest, expected + 1)
  }
}

fn prepared_structural(prepared: PreparedDecision) -> Bool {
  identifier(prepared.decision_id)
  && identifier(prepared.hive_id)
  && identifier(prepared.tenant_id)
  && actor_valid(prepared.actor)
  && identifier(prepared.task_id)
  && bounded(prepared.goal, 4096)
  && bounded(prepared.candidate_revision, 512)
  && bounded(prepared.resource, 512)
  && prepared.epoch > 0
  && refs_valid(prepared.evidence_refs)
  && reviews_valid(prepared.constraints)
  && review_valid(prepared.policy)
  && budget_valid(prepared.budget)
  && alternatives_valid(prepared.alternatives)
  && bounded(prepared.selected_action, 512)
  && bounded(prepared.rationale, 2048)
  && reviews_valid(prepared.uncertainties)
  && reviews_valid(prepared.risks)
  && process_valid(prepared.process)
  && refs_valid(prepared.authorization_refs)
  && review_valid(prepared.verification_plan)
  && review_valid(prepared.rollback_plan)
  && snapshot_valid(prepared.state, prepared.actor.kind)
  && forecast_valid(prepared.forecast, prepared.state)
}

fn prepared_valid(prepared: PreparedDecision, now_boot_us: Int) -> Bool {
  let current = case prepared.state.status {
    SnapshotCurrent -> True
    SnapshotStale(_) | SnapshotSuperseded(_) -> False
  }
  prepared_structural(prepared)
  && current
  && prepared.state.as_of_boot_us <= now_boot_us
  && prepared.forecast.as_of_boot_us <= now_boot_us
  && now_boot_us < prepared.forecast.expires_boot_us
}

fn binds(prepared: PreparedDecision, expected: ExpectedDecision) -> Bool {
  prepared.hive_id == expected.hive_id
  && prepared.tenant_id == expected.tenant_id
  && prepared.state.clock == expected.clock
  && prepared.actor.identity == expected.actor_identity
  && prepared.actor.kind == expected.actor_kind
  && prepared.actor.session == expected.session
  && prepared.task_id == expected.task_id
  && prepared.candidate_revision == expected.candidate_revision
  && prepared.resource == expected.resource
  && prepared.epoch == expected.epoch
  && prepared.selected_action == expected.selected_action
}

pub fn validate_prepared(
  prepared: PreparedDecision,
  expected: ExpectedDecision,
  now_boot_us: Int,
) -> Result(ValidatedDecision, String) {
  use _ <- result.try(require(
    now_boot_us >= 0 && prepared_valid(prepared, now_boot_us),
    "prepared decision record is incomplete, stale, or invalid",
  ))
  use _ <- result.try(require(
    binds(prepared, expected),
    "prepared decision does not match the expected hive action",
  ))
  Ok(ValidatedDecision(prepared))
}

pub fn matches(
  validated: ValidatedDecision,
  expected: ExpectedDecision,
  now_boot_us: Int,
) -> Bool {
  prepared_valid(validated.prepared, now_boot_us)
  && binds(validated.prepared, expected)
}

pub fn decision_id(validated: ValidatedDecision) -> String {
  validated.prepared.decision_id
}

fn outcome_valid(outcome: DecisionOutcome) -> Bool {
  case outcome {
    Succeeded(summary)
    | Failed(summary)
    | OutcomeUnknown(summary)
    | OutcomeNotApplicable(summary) -> bounded(summary, 2048)
  }
}

fn completion_valid(completed: CompletedDecision) -> Bool {
  identifier(completed.decision_id)
  && identifier(completed.prepared_decision_id)
  && completed.decision_id != completed.prepared_decision_id
  && identifier(completed.hive_id)
  && identifier(completed.tenant_id)
  && actor_valid(completed.actor)
  && identifier(completed.task_id)
  && bounded(completed.candidate_revision, 512)
  && bounded(completed.resource, 512)
  && completed.epoch > 0
  && bounded(completed.selected_action, 512)
  && outcome_valid(completed.outcome)
  && refs_valid(completed.observed_evidence_refs)
  && estimate_valid(completed.observed_cost)
  && process_valid(completed.process)
  && review_valid(completed.verification_result)
  && review_valid(completed.rollback_result)
  && review_valid(completed.observed_outcome)
  && review_valid(completed.calibration_ref)
}

pub fn validate_completion(
  prepared: PreparedDecision,
  completed: CompletedDecision,
) -> Result(ValidatedCompletion, String) {
  use _ <- result.try(require(
    prepared_structural(prepared),
    "prepared decision link is incomplete or invalid",
  ))
  use _ <- result.try(require(
    completion_valid(completed),
    "completed decision record is incomplete or invalid",
  ))
  use _ <- result.try(require(
    completed.prepared_decision_id == prepared.decision_id
      && completed.hive_id == prepared.hive_id
      && completed.tenant_id == prepared.tenant_id
      && completed.actor == prepared.actor
      && completed.task_id == prepared.task_id
      && completed.candidate_revision == prepared.candidate_revision
      && completed.resource == prepared.resource
      && completed.epoch == prepared.epoch
      && completed.selected_action == prepared.selected_action,
    "completion does not match its prepared decision",
  ))
  Ok(ValidatedCompletion(completed))
}

/// Structural/freshness boundary for hive projection. This does not bind an
/// action expectation and therefore cannot produce `ValidatedDecision`.
pub fn validate_record(
  record: Record,
  observer_clock: ClockDomain,
  now_boot_us: Int,
) -> Result(ValidatedRecord, String) {
  use _ <- result.try(require(
    clock_valid(observer_clock) && now_boot_us >= 0,
    "observer clock domain is invalid",
  ))
  case record {
    PreparedRecord(prepared) -> {
      use _ <- result.try(require(
        prepared_structural(prepared),
        "prepared shared record is incomplete or invalid",
      ))
      let freshness = case prepared.state.clock == observer_clock {
        False ->
          RecordFreshnessUnknown(
            "record and observer use different host or boot domains",
          )
        True
          if prepared.state.as_of_boot_us > now_boot_us
          || prepared.forecast.as_of_boot_us > now_boot_us
        -> RecordFreshnessUnknown("record timestamp is ahead of observer time")
        True ->
          case prepared.state.status {
            SnapshotStale(reason) -> RecordDeclaredStale(reason)
            SnapshotSuperseded(id) -> RecordSuperseded(id)
            SnapshotCurrent
              if now_boot_us >= prepared.forecast.expires_boot_us
            -> RecordExpired
            SnapshotCurrent -> RecordCurrent
          }
      }
      Ok(ValidatedPreparedRecord(prepared, freshness))
    }
    CompletedRecord(completed) -> {
      use _ <- result.try(require(
        completion_valid(completed),
        "completed shared record is incomplete or invalid",
      ))
      Ok(ValidatedCompletedRecord(completed, CompletionFreshnessNotApplicable))
    }
  }
}

pub fn validated_record_view(record: ValidatedRecord) -> ValidatedRecordView {
  case record {
    ValidatedPreparedRecord(prepared, _) -> PreparedView(prepared)
    ValidatedCompletedRecord(completed, _) -> CompletedView(completed)
  }
}

pub fn validated_hive_id(record: ValidatedRecord) -> String {
  case record {
    ValidatedPreparedRecord(prepared, _) -> prepared.hive_id
    ValidatedCompletedRecord(completed, _) -> completed.hive_id
  }
}

pub fn validated_tenant_id(record: ValidatedRecord) -> String {
  case record {
    ValidatedPreparedRecord(prepared, _) -> prepared.tenant_id
    ValidatedCompletedRecord(completed, _) -> completed.tenant_id
  }
}

pub fn validated_decision_id(record: ValidatedRecord) -> String {
  case record {
    ValidatedPreparedRecord(prepared, _) -> prepared.decision_id
    ValidatedCompletedRecord(completed, _) -> completed.decision_id
  }
}

pub fn validated_phase(record: ValidatedRecord) -> RecordPhase {
  case record {
    ValidatedPreparedRecord(_, _) -> PreparedPhase
    ValidatedCompletedRecord(_, _) -> CompletedPhase
  }
}

pub fn validated_snapshot_status(
  record: ValidatedRecord,
) -> Option(SnapshotStatus) {
  case record {
    ValidatedPreparedRecord(prepared, _) -> Some(prepared.state.status)
    ValidatedCompletedRecord(_, _) -> None
  }
}

pub fn validated_freshness(record: ValidatedRecord) -> RecordFreshness {
  case record {
    ValidatedPreparedRecord(_, freshness) -> freshness
    ValidatedCompletedRecord(_, freshness) -> freshness
  }
}

fn review_json(value: ReviewValue) -> Json {
  let #(status, text) = case value {
    Stated(text) -> #("stated", text)
    Unknown(reason) -> #("unknown", reason)
    NotApplicable(reason) -> #("not_applicable", reason)
  }
  json.object([#("status", json.string(status)), #("text", json.string(text))])
}

fn actor_kind_label(kind: ActorKind) -> String {
  case kind {
    ModelActor -> "model"
    DeterministicActor -> "deterministic"
  }
}

fn source_label(source: StateSource) -> String {
  case source {
    ModelSelfReport -> "model_self_report"
    MeasuredRuntime -> "measured_runtime"
    Inference -> "inference"
    DeterministicRuleState -> "deterministic_rule_state"
  }
}

fn epistemic_label(status: EpistemicStatus) -> String {
  case status {
    EvidenceBound -> "evidence_bound"
    Hypothesis -> "hypothesis"
    Uncertain -> "uncertain"
  }
}

fn estimate_json(estimate: Estimate) -> Json {
  case estimate {
    Estimated(value, unit, basis) ->
      json.object([
        #("status", json.string("estimated")),
        #("value", json.int(value)),
        #("unit", json.string(unit)),
        #("basis_ref", json.string(basis)),
      ])
    UnknownEstimate(reason) ->
      json.object([
        #("status", json.string("unknown")),
        #("reason", json.string(reason)),
      ])
    NotApplicableEstimate(reason) ->
      json.object([
        #("status", json.string("not_applicable")),
        #("reason", json.string(reason)),
      ])
  }
}

fn budget_json(budget: Budget) -> Json {
  json.object([
    #("max_cost", estimate_json(budget.max_cost)),
    #("max_tokens", estimate_json(budget.max_tokens)),
    #("max_wall_time", estimate_json(budget.max_wall_time)),
  ])
}

fn actor_json(actor: Actor) -> Json {
  json.object([
    #("identity", json.string(actor.identity)),
    #("kind", json.string(actor_kind_label(actor.kind))),
    #("session", json.string(actor.session)),
    #("provider", review_json(actor.provider)),
    #("model", review_json(actor.model)),
  ])
}

fn reviews_json(values: List(ReviewValue)) -> Json {
  json.array(values, review_json)
}

fn refs_json(refs: List(String)) -> Json {
  json.array(refs, json.string)
}

fn belief_json(belief: Belief) -> Json {
  json.object([
    #("statement", json.string(belief.statement)),
    #("evidence_refs", refs_json(belief.evidence_refs)),
    #("epistemic_status", json.string(epistemic_label(belief.status))),
    #("source", json.string(source_label(belief.source))),
  ])
}

fn snapshot_status_json(status: SnapshotStatus) -> Json {
  case status {
    SnapshotCurrent -> json.object([#("status", json.string("current"))])
    SnapshotStale(reason) ->
      json.object([
        #("status", json.string("stale")),
        #("reason", json.string(reason)),
      ])
    SnapshotSuperseded(id) ->
      json.object([
        #("status", json.string("superseded")),
        #("by_snapshot_id", json.string(id)),
      ])
  }
}

fn snapshot_json(snapshot: StateSnapshot) -> Json {
  json.object([
    #("snapshot_id", json.string(snapshot.snapshot_id)),
    #("clock_host", json.string(snapshot.clock.host_id)),
    #("clock_boot", json.string(snapshot.clock.boot_id)),
    #("as_of_boot_us", json.int(snapshot.as_of_boot_us)),
    #("snapshot_status", snapshot_status_json(snapshot.status)),
    #("source", json.string(source_label(snapshot.source))),
    #("current_goals", reviews_json(snapshot.current_goals)),
    #("subgoals", reviews_json(snapshot.subgoals)),
    #("beliefs", json.array(snapshot.beliefs, belief_json)),
    #("uncertainties", reviews_json(snapshot.uncertainties)),
    #("open_questions", reviews_json(snapshot.open_questions)),
    #("constraints", reviews_json(snapshot.constraints)),
    #("resources", reviews_json(snapshot.resources)),
    #("budget", budget_json(snapshot.budget)),
    #("attention", review_json(snapshot.attention)),
    #("active_task", review_json(snapshot.active_task)),
    #("intended_next_actions", reviews_json(snapshot.intended_next_actions)),
  ])
}

fn confidence_json(confidence: ConfidenceBasis) -> Json {
  let #(status, text) = case confidence {
    MeasuredConfidence(reference) -> #("measured", reference)
    EstimatedConfidence(reference) -> #("estimated", reference)
    UnknownConfidence(reason) -> #("unknown", reason)
  }
  json.object([#("status", json.string(status)), #("basis", json.string(text))])
}

fn probability_json(probability: Probability) -> Json {
  case probability {
    PointProbability(value, basis) ->
      json.object([
        #("status", json.string("point")),
        #("low_basis_points", json.int(value)),
        #("high_basis_points", json.int(value)),
        #("basis_ref", json.string(basis)),
      ])
    ProbabilityRange(low, high, basis) ->
      json.object([
        #("status", json.string("range")),
        #("low_basis_points", json.int(low)),
        #("high_basis_points", json.int(high)),
        #("basis_ref", json.string(basis)),
      ])
    UnknownProbability(reason) ->
      json.object([
        #("status", json.string("unknown")),
        #("reason", json.string(reason)),
      ])
    NotApplicableProbability(reason) ->
      json.object([
        #("status", json.string("not_applicable")),
        #("reason", json.string(reason)),
      ])
  }
}

fn forecast_json(forecast: Forecast) -> Json {
  json.object([
    #("clock_host", json.string(forecast.clock.host_id)),
    #("clock_boot", json.string(forecast.clock.boot_id)),
    #("horizon", json.string(forecast.horizon)),
    #("as_of_boot_us", json.int(forecast.as_of_boot_us)),
    #("expires_boot_us", json.int(forecast.expires_boot_us)),
    #("predicted_outcome", review_json(forecast.predicted_outcome)),
    #("alternatives", reviews_json(forecast.alternatives)),
    #("assumptions", reviews_json(forecast.assumptions)),
    #("confidence", confidence_json(forecast.confidence)),
    #("probability", probability_json(forecast.probability)),
    #("expected_duration", estimate_json(forecast.expected_duration)),
    #("expected_cost", estimate_json(forecast.expected_cost)),
    #("expected_resources", reviews_json(forecast.expected_resources)),
    #("failure_signals", reviews_json(forecast.failure_signals)),
    #("update_triggers", reviews_json(forecast.update_triggers)),
    #("observed_outcome", review_json(forecast.observed_outcome)),
    #("calibration_ref", review_json(forecast.calibration_ref)),
  ])
}

fn alternative_json(alternative: Alternative) -> Json {
  json.object([
    #("option", json.string(alternative.option)),
    #("tradeoff", json.string(alternative.tradeoff)),
  ])
}

fn step_json(step: ProcessStep) -> Json {
  json.object([
    #("order", json.int(step.order)),
    #("summary", json.string(step.summary)),
    #("evidence", review_json(step.evidence)),
  ])
}

fn prepared_json(prepared: PreparedDecision) -> Json {
  json.object([
    #("schema", json.string(schema)),
    #("phase", json.string("prepared")),
    #("decision_id", json.string(prepared.decision_id)),
    #("hive_id", json.string(prepared.hive_id)),
    #("tenant_id", json.string(prepared.tenant_id)),
    #("shared_scope", json.string("hive_operating_state")),
    #("actor", actor_json(prepared.actor)),
    #("task_id", json.string(prepared.task_id)),
    #("goal", json.string(prepared.goal)),
    #("candidate_revision", json.string(prepared.candidate_revision)),
    #("resource", json.string(prepared.resource)),
    #("epoch", json.int(prepared.epoch)),
    #("evidence_refs", refs_json(prepared.evidence_refs)),
    #("constraints", reviews_json(prepared.constraints)),
    #("policy", review_json(prepared.policy)),
    #("budget", budget_json(prepared.budget)),
    #("alternatives", json.array(prepared.alternatives, alternative_json)),
    #("selected_action", json.string(prepared.selected_action)),
    #("rationale", json.string(prepared.rationale)),
    #("uncertainties", reviews_json(prepared.uncertainties)),
    #("risks", reviews_json(prepared.risks)),
    #("process", json.array(prepared.process, step_json)),
    #("authorization_refs", refs_json(prepared.authorization_refs)),
    #("verification_plan", review_json(prepared.verification_plan)),
    #("rollback_plan", review_json(prepared.rollback_plan)),
    #("state_snapshot", snapshot_json(prepared.state)),
    #("forecast", forecast_json(prepared.forecast)),
  ])
}

fn outcome_json(outcome: DecisionOutcome) -> Json {
  let #(status, summary) = case outcome {
    Succeeded(summary) -> #("succeeded", summary)
    Failed(reason) -> #("failed", reason)
    OutcomeUnknown(reason) -> #("unknown", reason)
    OutcomeNotApplicable(reason) -> #("not_applicable", reason)
  }
  json.object([
    #("status", json.string(status)),
    #("summary", json.string(summary)),
  ])
}

fn completed_json(completed: CompletedDecision) -> Json {
  json.object([
    #("schema", json.string(schema)),
    #("phase", json.string("completed")),
    #("decision_id", json.string(completed.decision_id)),
    #("prepared_decision_id", json.string(completed.prepared_decision_id)),
    #("hive_id", json.string(completed.hive_id)),
    #("tenant_id", json.string(completed.tenant_id)),
    #("shared_scope", json.string("hive_operating_state")),
    #("actor", actor_json(completed.actor)),
    #("task_id", json.string(completed.task_id)),
    #("candidate_revision", json.string(completed.candidate_revision)),
    #("resource", json.string(completed.resource)),
    #("epoch", json.int(completed.epoch)),
    #("selected_action", json.string(completed.selected_action)),
    #("outcome", outcome_json(completed.outcome)),
    #("observed_evidence_refs", refs_json(completed.observed_evidence_refs)),
    #("observed_cost", estimate_json(completed.observed_cost)),
    #("process", json.array(completed.process, step_json)),
    #("verification_result", review_json(completed.verification_result)),
    #("rollback_result", review_json(completed.rollback_result)),
    #("observed_outcome", review_json(completed.observed_outcome)),
    #("calibration_ref", review_json(completed.calibration_ref)),
  ])
}

pub fn encode(record: Record) -> String {
  case record {
    PreparedRecord(prepared) -> json.to_string(prepared_json(prepared))
    CompletedRecord(completed) -> json.to_string(completed_json(completed))
  }
}

fn review_decoder() -> decode.Decoder(ReviewValue) {
  use status <- decode.field("status", decode.string)
  use text <- decode.field("text", decode.string)
  case status {
    "stated" -> decode.success(Stated(text))
    "unknown" -> decode.success(Unknown(text))
    "not_applicable" -> decode.success(NotApplicable(text))
    _ -> decode.failure(Stated(text), "review status")
  }
}

fn actor_kind_decoder() -> decode.Decoder(ActorKind) {
  use label <- decode.then(decode.string)
  case label {
    "model" -> decode.success(ModelActor)
    "deterministic" -> decode.success(DeterministicActor)
    _ -> decode.failure(ModelActor, "actor kind")
  }
}

fn actor_decoder() -> decode.Decoder(Actor) {
  use identity <- decode.field("identity", decode.string)
  use kind <- decode.field("kind", actor_kind_decoder())
  use session <- decode.field("session", decode.string)
  use provider <- decode.field("provider", review_decoder())
  use model <- decode.field("model", review_decoder())
  decode.success(Actor(identity, kind, session, provider, model))
}

fn estimate_decoder() -> decode.Decoder(Estimate) {
  use status <- decode.field("status", decode.string)
  case status {
    "estimated" -> {
      use value <- decode.field("value", decode.int)
      use unit <- decode.field("unit", decode.string)
      use basis <- decode.field("basis_ref", decode.string)
      decode.success(Estimated(value, unit, basis))
    }
    "unknown" -> {
      use reason <- decode.field("reason", decode.string)
      decode.success(UnknownEstimate(reason))
    }
    "not_applicable" -> {
      use reason <- decode.field("reason", decode.string)
      decode.success(NotApplicableEstimate(reason))
    }
    _ -> decode.failure(UnknownEstimate(status), "estimate status")
  }
}

fn budget_decoder() -> decode.Decoder(Budget) {
  use cost <- decode.field("max_cost", estimate_decoder())
  use tokens <- decode.field("max_tokens", estimate_decoder())
  use wall <- decode.field("max_wall_time", estimate_decoder())
  decode.success(Budget(cost, tokens, wall))
}

fn source_decoder() -> decode.Decoder(StateSource) {
  use label <- decode.then(decode.string)
  case label {
    "model_self_report" -> decode.success(ModelSelfReport)
    "measured_runtime" -> decode.success(MeasuredRuntime)
    "inference" -> decode.success(Inference)
    "deterministic_rule_state" -> decode.success(DeterministicRuleState)
    _ -> decode.failure(Inference, "state source")
  }
}

fn epistemic_decoder() -> decode.Decoder(EpistemicStatus) {
  use label <- decode.then(decode.string)
  case label {
    "evidence_bound" -> decode.success(EvidenceBound)
    "hypothesis" -> decode.success(Hypothesis)
    "uncertain" -> decode.success(Uncertain)
    _ -> decode.failure(Uncertain, "epistemic status")
  }
}

fn belief_decoder() -> decode.Decoder(Belief) {
  use statement <- decode.field("statement", decode.string)
  use evidence <- decode.field("evidence_refs", decode.list(decode.string))
  use status <- decode.field("epistemic_status", epistemic_decoder())
  use source <- decode.field("source", source_decoder())
  decode.success(Belief(statement, evidence, status, source))
}

fn snapshot_status_decoder() -> decode.Decoder(SnapshotStatus) {
  use status <- decode.field("status", decode.string)
  case status {
    "current" -> decode.success(SnapshotCurrent)
    "stale" -> {
      use reason <- decode.field("reason", decode.string)
      decode.success(SnapshotStale(reason))
    }
    "superseded" -> {
      use id <- decode.field("by_snapshot_id", decode.string)
      decode.success(SnapshotSuperseded(id))
    }
    _ -> decode.failure(SnapshotStale(status), "snapshot status")
  }
}

fn snapshot_decoder() -> decode.Decoder(StateSnapshot) {
  use id <- decode.field("snapshot_id", decode.string)
  use clock_host <- decode.field("clock_host", decode.string)
  use clock_boot <- decode.field("clock_boot", decode.string)
  use as_of <- decode.field("as_of_boot_us", decode.int)
  use status <- decode.field("snapshot_status", snapshot_status_decoder())
  use source <- decode.field("source", source_decoder())
  use goals <- decode.field("current_goals", decode.list(review_decoder()))
  use subgoals <- decode.field("subgoals", decode.list(review_decoder()))
  use beliefs <- decode.field("beliefs", decode.list(belief_decoder()))
  use uncertainties <- decode.field(
    "uncertainties",
    decode.list(review_decoder()),
  )
  use questions <- decode.field("open_questions", decode.list(review_decoder()))
  use constraints <- decode.field("constraints", decode.list(review_decoder()))
  use resources <- decode.field("resources", decode.list(review_decoder()))
  use budget <- decode.field("budget", budget_decoder())
  use attention <- decode.field("attention", review_decoder())
  use active_task <- decode.field("active_task", review_decoder())
  use next <- decode.field(
    "intended_next_actions",
    decode.list(review_decoder()),
  )
  decode.success(StateSnapshot(
    id,
    ClockDomain(clock_host, clock_boot),
    as_of,
    status,
    source,
    goals,
    subgoals,
    beliefs,
    uncertainties,
    questions,
    constraints,
    resources,
    budget,
    attention,
    active_task,
    next,
  ))
}

fn confidence_decoder() -> decode.Decoder(ConfidenceBasis) {
  use status <- decode.field("status", decode.string)
  use basis <- decode.field("basis", decode.string)
  case status {
    "measured" -> decode.success(MeasuredConfidence(basis))
    "estimated" -> decode.success(EstimatedConfidence(basis))
    "unknown" -> decode.success(UnknownConfidence(basis))
    _ -> decode.failure(UnknownConfidence(basis), "confidence status")
  }
}

fn probability_decoder() -> decode.Decoder(Probability) {
  use status <- decode.field("status", decode.string)
  case status {
    "point" -> {
      use value <- decode.field("low_basis_points", decode.int)
      use basis <- decode.field("basis_ref", decode.string)
      decode.success(PointProbability(value, basis))
    }
    "range" -> {
      use low <- decode.field("low_basis_points", decode.int)
      use high <- decode.field("high_basis_points", decode.int)
      use basis <- decode.field("basis_ref", decode.string)
      decode.success(ProbabilityRange(low, high, basis))
    }
    "unknown" -> {
      use reason <- decode.field("reason", decode.string)
      decode.success(UnknownProbability(reason))
    }
    "not_applicable" -> {
      use reason <- decode.field("reason", decode.string)
      decode.success(NotApplicableProbability(reason))
    }
    _ -> decode.failure(UnknownProbability(status), "probability status")
  }
}

fn forecast_decoder() -> decode.Decoder(Forecast) {
  use clock_host <- decode.field("clock_host", decode.string)
  use clock_boot <- decode.field("clock_boot", decode.string)
  use horizon <- decode.field("horizon", decode.string)
  use as_of <- decode.field("as_of_boot_us", decode.int)
  use expires <- decode.field("expires_boot_us", decode.int)
  use predicted <- decode.field("predicted_outcome", review_decoder())
  use alternatives <- decode.field(
    "alternatives",
    decode.list(review_decoder()),
  )
  use assumptions <- decode.field("assumptions", decode.list(review_decoder()))
  use confidence <- decode.field("confidence", confidence_decoder())
  use probability <- decode.field("probability", probability_decoder())
  use duration <- decode.field("expected_duration", estimate_decoder())
  use cost <- decode.field("expected_cost", estimate_decoder())
  use resources <- decode.field(
    "expected_resources",
    decode.list(review_decoder()),
  )
  use failures <- decode.field("failure_signals", decode.list(review_decoder()))
  use triggers <- decode.field("update_triggers", decode.list(review_decoder()))
  use observed <- decode.field("observed_outcome", review_decoder())
  use calibration <- decode.field("calibration_ref", review_decoder())
  decode.success(Forecast(
    ClockDomain(clock_host, clock_boot),
    horizon,
    as_of,
    expires,
    predicted,
    alternatives,
    assumptions,
    confidence,
    probability,
    duration,
    cost,
    resources,
    failures,
    triggers,
    observed,
    calibration,
  ))
}

fn alternative_decoder() -> decode.Decoder(Alternative) {
  use option <- decode.field("option", decode.string)
  use tradeoff <- decode.field("tradeoff", decode.string)
  decode.success(Alternative(option, tradeoff))
}

fn step_decoder() -> decode.Decoder(ProcessStep) {
  use order <- decode.field("order", decode.int)
  use summary <- decode.field("summary", decode.string)
  use evidence <- decode.field("evidence", review_decoder())
  decode.success(ProcessStep(order, summary, evidence))
}

fn prepared_decoder() -> decode.Decoder(PreparedDecision) {
  use id <- decode.field("decision_id", decode.string)
  use hive <- decode.field("hive_id", decode.string)
  use tenant <- decode.field("tenant_id", decode.string)
  use actor <- decode.field("actor", actor_decoder())
  use task <- decode.field("task_id", decode.string)
  use goal <- decode.field("goal", decode.string)
  use candidate <- decode.field("candidate_revision", decode.string)
  use resource <- decode.field("resource", decode.string)
  use epoch <- decode.field("epoch", decode.int)
  use evidence <- decode.field("evidence_refs", decode.list(decode.string))
  use constraints <- decode.field("constraints", decode.list(review_decoder()))
  use policy <- decode.field("policy", review_decoder())
  use budget <- decode.field("budget", budget_decoder())
  use alternatives <- decode.field(
    "alternatives",
    decode.list(alternative_decoder()),
  )
  use selected <- decode.field("selected_action", decode.string)
  use rationale <- decode.field("rationale", decode.string)
  use uncertainties <- decode.field(
    "uncertainties",
    decode.list(review_decoder()),
  )
  use risks <- decode.field("risks", decode.list(review_decoder()))
  use process <- decode.field("process", decode.list(step_decoder()))
  use authorization <- decode.field(
    "authorization_refs",
    decode.list(decode.string),
  )
  use verification <- decode.field("verification_plan", review_decoder())
  use rollback <- decode.field("rollback_plan", review_decoder())
  use state <- decode.field("state_snapshot", snapshot_decoder())
  use forecast <- decode.field("forecast", forecast_decoder())
  decode.success(PreparedDecision(
    id,
    hive,
    tenant,
    actor,
    task,
    goal,
    candidate,
    resource,
    epoch,
    evidence,
    constraints,
    policy,
    budget,
    alternatives,
    selected,
    rationale,
    uncertainties,
    risks,
    process,
    authorization,
    verification,
    rollback,
    state,
    forecast,
  ))
}

fn outcome_decoder() -> decode.Decoder(DecisionOutcome) {
  use status <- decode.field("status", decode.string)
  use summary <- decode.field("summary", decode.string)
  case status {
    "succeeded" -> decode.success(Succeeded(summary))
    "failed" -> decode.success(Failed(summary))
    "unknown" -> decode.success(OutcomeUnknown(summary))
    "not_applicable" -> decode.success(OutcomeNotApplicable(summary))
    _ -> decode.failure(OutcomeUnknown(summary), "completion outcome")
  }
}

fn completed_decoder() -> decode.Decoder(CompletedDecision) {
  use id <- decode.field("decision_id", decode.string)
  use prepared_id <- decode.field("prepared_decision_id", decode.string)
  use hive <- decode.field("hive_id", decode.string)
  use tenant <- decode.field("tenant_id", decode.string)
  use actor <- decode.field("actor", actor_decoder())
  use task <- decode.field("task_id", decode.string)
  use candidate <- decode.field("candidate_revision", decode.string)
  use resource <- decode.field("resource", decode.string)
  use epoch <- decode.field("epoch", decode.int)
  use selected <- decode.field("selected_action", decode.string)
  use outcome <- decode.field("outcome", outcome_decoder())
  use evidence <- decode.field(
    "observed_evidence_refs",
    decode.list(decode.string),
  )
  use cost <- decode.field("observed_cost", estimate_decoder())
  use process <- decode.field("process", decode.list(step_decoder()))
  use verification <- decode.field("verification_result", review_decoder())
  use rollback <- decode.field("rollback_result", review_decoder())
  use observed <- decode.field("observed_outcome", review_decoder())
  use calibration <- decode.field("calibration_ref", review_decoder())
  decode.success(CompletedDecision(
    id,
    prepared_id,
    hive,
    tenant,
    actor,
    task,
    candidate,
    resource,
    epoch,
    selected,
    outcome,
    evidence,
    cost,
    process,
    verification,
    rollback,
    observed,
    calibration,
  ))
}

fn record_decoder() -> decode.Decoder(Record) {
  use schema_value <- decode.field("schema", decode.string)
  use phase <- decode.field("phase", decode.string)
  use shared_scope <- decode.field("shared_scope", decode.string)
  case schema_value == schema && shared_scope == "hive_operating_state", phase {
    True, "prepared" -> {
      use prepared <- decode.then(prepared_decoder())
      decode.success(PreparedRecord(prepared))
    }
    True, "completed" -> {
      use completed <- decode.then(completed_decoder())
      decode.success(CompletedRecord(completed))
    }
    _, _ ->
      decode.failure(
        PreparedRecord(PreparedDecision(
          "invalid",
          "invalid",
          "invalid",
          Actor(
            "invalid",
            DeterministicActor,
            "invalid",
            Unknown("invalid"),
            NotApplicable("invalid"),
          ),
          "invalid",
          "invalid",
          "invalid",
          "invalid",
          0,
          [],
          [],
          Unknown("invalid"),
          Budget(
            UnknownEstimate("invalid"),
            UnknownEstimate("invalid"),
            UnknownEstimate("invalid"),
          ),
          [],
          "invalid",
          "invalid",
          [],
          [],
          [],
          [],
          Unknown("invalid"),
          Unknown("invalid"),
          StateSnapshot(
            "invalid",
            ClockDomain("invalid", "invalid"),
            0,
            SnapshotStale("invalid"),
            Inference,
            [],
            [],
            [],
            [],
            [],
            [],
            [],
            Budget(
              UnknownEstimate("invalid"),
              UnknownEstimate("invalid"),
              UnknownEstimate("invalid"),
            ),
            Unknown("invalid"),
            Unknown("invalid"),
            [],
          ),
          Forecast(
            ClockDomain("invalid", "invalid"),
            "invalid",
            0,
            0,
            Unknown("invalid"),
            [],
            [],
            UnknownConfidence("invalid"),
            UnknownProbability("invalid"),
            UnknownEstimate("invalid"),
            UnknownEstimate("invalid"),
            [],
            [],
            [],
            Unknown("invalid"),
            Unknown("invalid"),
          ),
        )),
        "decision record schema, scope, and phase",
      )
  }
}

pub fn decode(payload: String) -> Result(Record, String) {
  use _ <- result.try(require(
    string.length(payload) <= 65_536,
    "decision record exceeds 64 KiB",
  ))
  json.parse(payload, record_decoder())
  |> result.replace_error("malformed decision record")
}
