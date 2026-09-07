//// CLI wire adapter for `uos-decision-record/v1` files under `generated/`.
////
//// `uos_swarm/decision_record.gleam` owns a richer, strictly bounded schema for
//// action-boundary review (see `coord`, `hive_kpi`, `action_boundary`); its shape
//// (`schema`, `hive_id`, `state_snapshot`, ...) does not match the hive integration
//// decision records already on disk under `generated/*-uos-decision-record-*.json`
//// (`carrier`, `identity_scope`, `task_authority`, `evidence_choice`, `process`,
//// `forecast`, and — once completed — `completed`). This module is the thin
//// adapter that reads/writes exactly that on-disk shape for the
//// `decision-record prepare|complete` CLI arms; it reuses
//// `decision_record.schema` as the carrier constant (both name the same wire
//// value, `"uos-decision-record/v1"`) rather than duplicating the literal.
////
//// Rule: once a record is written by `prepare`, its `forecast` object is never
//// rewritten. `complete` decodes the stored record, adds a `completed` object,
//// flips `phase` to `"completed"`, and re-encodes the same decoded `forecast`
//// value unchanged.

import gleam/dynamic/decode
import gleam/int
import gleam/json.{type Json}
import gleam/result
import gleam/string
import uos_swarm/board
import uos_swarm/decision_record
import uos_tui/telemetry

/// Wire carrier value; reuses the peer action-boundary schema's constant since
/// both name the same string, `"uos-decision-record/v1"`.
pub const carrier = decision_record.schema

/// Fixed clock domain label used across every hive decision record on this host.
const clock_domain = "UTC host nas-1"

pub type Observation {
  Observation(source: String, value: String, grade: String)
}

pub type Alternative {
  Alternative(option: String, tradeoff: String)
}

pub type ForecastSpec {
  ForecastSpec(
    horizon_minutes: Int,
    predicted_outcome: String,
    probability: Float,
    basis: String,
    unknowns: List(String),
  )
}

pub type PrepareSpec {
  PrepareSpec(
    task: String,
    resource: String,
    proposed_action: String,
    policy_refs: List(String),
    authorization: String,
    observations: List(Observation),
    alternatives: List(Alternative),
    selected: String,
    rationale: String,
    risks: List(String),
    unresolved: List(String),
    steps: List(String),
    rollback: String,
    escalation: String,
    forecast: ForecastSpec,
    lease_epoch: String,
  )
}

pub type CompletionSpec {
  CompletionSpec(
    observed_actions: List(String),
    outcome: String,
    forecast_resolution: String,
    consumed_tokens: String,
    consumed_usd: Float,
  )
}

pub type ForecastBlock {
  ForecastBlock(
    horizon: String,
    clock_domain: String,
    observed_at: String,
    expires_at: String,
    predicted_outcome: String,
    probability: Float,
    basis: String,
    unknowns: List(String),
  )
}

pub type IdentityScope {
  IdentityScope(
    hive: String,
    tenant: String,
    actor_kind: String,
    actor_id: String,
    session: String,
    provider: String,
    model: String,
  )
}

pub type TaskAuthority {
  TaskAuthority(
    task: String,
    resource: String,
    lease_epoch: String,
    proposed_action: String,
    policy_refs: List(String),
    authorization: String,
  )
}

pub type EvidenceChoice {
  EvidenceChoice(
    observations: List(Observation),
    alternatives: List(Alternative),
    selected: String,
    rationale: String,
    risks: List(String),
    unresolved: List(String),
  )
}

pub type ProcessBlock {
  ProcessBlock(steps: List(String), rollback: String, escalation: String)
}

pub type CompletedBlock {
  CompletedBlock(
    observed_at: String,
    observed_actions: List(String),
    outcome: String,
    forecast_resolution: String,
    consumed_tokens: String,
    consumed_usd: Float,
  )
}

/// A record as decoded off disk (the `completed` object, when present, is
/// handled separately by `complete_record` rather than round-tripped here).
pub type StoredRecord {
  StoredRecord(
    carrier: String,
    phase: String,
    decision_id: String,
    identity_scope: IdentityScope,
    task_authority: TaskAuthority,
    evidence_choice: EvidenceChoice,
    process: ProcessBlock,
    forecast: ForecastBlock,
  )
}

@external(erlang, "uos_swarm_ffi", "getenv")
pub fn getenv(name: String, default: String) -> String

fn number_decoder() -> decode.Decoder(Float) {
  decode.one_of(decode.float, [decode.int |> decode.map(int.to_float)])
}

/// `"YYYYMMDD-HHMM"` from a `telemetry.iso8601_us` string
/// (`"YYYY-MM-DDTHH:MM:SS.ffffffZ"`), by fixed-width slicing.
pub fn stamp_from_iso(iso: String) -> String {
  let date =
    string.slice(iso, 0, 4)
    <> string.slice(iso, 5, 2)
    <> string.slice(iso, 8, 2)
  let time = string.slice(iso, 11, 2) <> string.slice(iso, 14, 2)
  date <> "-" <> time
}

pub fn stamp_from_epoch_us(epoch_us: Int) -> String {
  stamp_from_iso(telemetry.iso8601_us(epoch_us))
}

pub fn expires_at_iso(observed_epoch_us: Int, horizon_minutes: Int) -> String {
  telemetry.iso8601_us(observed_epoch_us + horizon_minutes * 60_000_000)
}

pub fn horizon_label(minutes: Int) -> String {
  int.to_string(minutes) <> " min"
}

/// `<actor upper-cased, hyphens stripped>`, e.g. `"L0-fable"` -> `"L0FABLE"`.
fn actor_token(actor_id: String) -> String {
  actor_id |> string.uppercase |> string.replace("-", "")
}

/// `"DR-<YYYYMMDD-HHMM>-<ACTOR>-<SLUG-UPPER>"`.
pub fn decision_id(actor_id: String, slug: String, stamp: String) -> String {
  "DR-"
  <> stamp
  <> "-"
  <> actor_token(actor_id)
  <> "-"
  <> string.uppercase(slug)
}

/// `"<YYYYMMDD-HHMM>-uos-decision-record-<slug>.json"`.
pub fn file_name(slug: String, stamp: String) -> String {
  stamp <> "-uos-decision-record-" <> slug <> ".json"
}

fn join_path(dir: String, name: String) -> String {
  case string.ends_with(dir, "/") {
    True -> dir <> name
    False -> dir <> "/" <> name
  }
}

// ---- encoders (also used to re-encode a decoded record on `complete`) ----

fn observation_json(o: Observation) -> Json {
  json.object([
    #("source", json.string(o.source)),
    #("value", json.string(o.value)),
    #("grade", json.string(o.grade)),
  ])
}

fn alternative_json(a: Alternative) -> Json {
  json.object([
    #("option", json.string(a.option)),
    #("tradeoff", json.string(a.tradeoff)),
  ])
}

fn identity_scope_json(i: IdentityScope) -> Json {
  json.object([
    #("hive", json.string(i.hive)),
    #("tenant", json.string(i.tenant)),
    #("actor_kind", json.string(i.actor_kind)),
    #("actor_id", json.string(i.actor_id)),
    #("session", json.string(i.session)),
    #(
      "provider_model",
      json.object([
        #("provider", json.string(i.provider)),
        #("model", json.string(i.model)),
        #("self_report", json.bool(True)),
      ]),
    ),
  ])
}

fn task_authority_json(t: TaskAuthority) -> Json {
  json.object([
    #("task", json.string(t.task)),
    #("resource", json.string(t.resource)),
    #("lease_epoch", json.string(t.lease_epoch)),
    #("proposed_action", json.string(t.proposed_action)),
    #("policy_refs", json.array(t.policy_refs, json.string)),
    #("authorization", json.string(t.authorization)),
  ])
}

fn evidence_choice_json(e: EvidenceChoice) -> Json {
  json.object([
    #("observations", json.array(e.observations, observation_json)),
    #("alternatives", json.array(e.alternatives, alternative_json)),
    #("selected", json.string(e.selected)),
    #("rationale", json.string(e.rationale)),
    #("risks", json.array(e.risks, json.string)),
    #("unresolved", json.array(e.unresolved, json.string)),
  ])
}

fn process_json(p: ProcessBlock) -> Json {
  json.object([
    #("steps", json.array(p.steps, json.string)),
    #("rollback", json.string(p.rollback)),
    #("escalation", json.string(p.escalation)),
  ])
}

fn forecast_json(f: ForecastBlock) -> Json {
  json.object([
    #("horizon", json.string(f.horizon)),
    #("clock_domain", json.string(f.clock_domain)),
    #("observed_at", json.string(f.observed_at)),
    #("expires_at", json.string(f.expires_at)),
    #("predicted_outcome", json.string(f.predicted_outcome)),
    #("probability", json.float(f.probability)),
    #("basis", json.string(f.basis)),
    #("unknowns", json.array(f.unknowns, json.string)),
  ])
}

fn completed_json(
  observed_at: String,
  observed_actions: List(String),
  outcome: String,
  forecast_resolution: String,
  consumed_tokens: String,
  consumed_usd: Float,
) -> Json {
  json.object([
    #("observed_at", json.string(observed_at)),
    #("observed_actions", json.array(observed_actions, json.string)),
    #("outcome", json.string(outcome)),
    #("forecast_resolution", json.string(forecast_resolution)),
    #(
      "consumed",
      json.object([
        #("tokens", json.string(consumed_tokens)),
        #("usd", json.float(consumed_usd)),
      ]),
    ),
  ])
}

/// A freshly prepared record: `phase = "prepared"`, no `completed` object.
fn prepared_json(record: StoredRecord) -> Json {
  json.object([
    #("carrier", json.string(record.carrier)),
    #("phase", json.string("prepared")),
    #("decision_id", json.string(record.decision_id)),
    #("identity_scope", identity_scope_json(record.identity_scope)),
    #("task_authority", task_authority_json(record.task_authority)),
    #("evidence_choice", evidence_choice_json(record.evidence_choice)),
    #("process", process_json(record.process)),
    #("forecast", forecast_json(record.forecast)),
  ])
}

/// The same record with `phase = "completed"` and a `completed` object added;
/// `record.forecast` is the value `complete_record` decoded from disk,
/// re-encoded unchanged.
fn completed_record_json(record: StoredRecord, completed: Json) -> Json {
  json.object([
    #("carrier", json.string(record.carrier)),
    #("phase", json.string("completed")),
    #("decision_id", json.string(record.decision_id)),
    #("identity_scope", identity_scope_json(record.identity_scope)),
    #("task_authority", task_authority_json(record.task_authority)),
    #("evidence_choice", evidence_choice_json(record.evidence_choice)),
    #("process", process_json(record.process)),
    #("completed", completed),
    #("forecast", forecast_json(record.forecast)),
  ])
}

// ---- decoders ----

fn observation_decoder() -> decode.Decoder(Observation) {
  use source <- decode.field("source", decode.string)
  use value <- decode.field("value", decode.string)
  use grade <- decode.field("grade", decode.string)
  decode.success(Observation(source, value, grade))
}

fn alternative_decoder() -> decode.Decoder(Alternative) {
  use option <- decode.field("option", decode.string)
  use tradeoff <- decode.field("tradeoff", decode.string)
  decode.success(Alternative(option, tradeoff))
}

fn forecast_spec_decoder() -> decode.Decoder(ForecastSpec) {
  use horizon_minutes <- decode.field("horizon_minutes", decode.int)
  use predicted_outcome <- decode.field("predicted_outcome", decode.string)
  use probability <- decode.field("probability", number_decoder())
  use basis <- decode.field("basis", decode.string)
  use unknowns <- decode.field("unknowns", decode.list(decode.string))
  decode.success(ForecastSpec(
    horizon_minutes,
    predicted_outcome,
    probability,
    basis,
    unknowns,
  ))
}

/// Decoder for the small input spec `decision-record prepare` reads. Unknown
/// extra keys in the spec are ignored (field decoders only look up the names
/// they ask for); a missing required key fails the whole decode.
pub fn prepare_spec_decoder() -> decode.Decoder(PrepareSpec) {
  use task <- decode.field("task", decode.string)
  use resource <- decode.field("resource", decode.string)
  use proposed_action <- decode.field("proposed_action", decode.string)
  use policy_refs <- decode.field("policy_refs", decode.list(decode.string))
  use authorization <- decode.field("authorization", decode.string)
  use observations <- decode.field(
    "observations",
    decode.list(observation_decoder()),
  )
  use alternatives <- decode.field(
    "alternatives",
    decode.list(alternative_decoder()),
  )
  use selected <- decode.field("selected", decode.string)
  use rationale <- decode.field("rationale", decode.string)
  use risks <- decode.field("risks", decode.list(decode.string))
  use unresolved <- decode.field("unresolved", decode.list(decode.string))
  use steps <- decode.field("steps", decode.list(decode.string))
  use rollback <- decode.field("rollback", decode.string)
  use escalation <- decode.field("escalation", decode.string)
  use forecast <- decode.field("forecast", forecast_spec_decoder())
  use lease_epoch <- decode.optional_field(
    "lease_epoch",
    "not claimed",
    decode.string,
  )
  decode.success(PrepareSpec(
    task,
    resource,
    proposed_action,
    policy_refs,
    authorization,
    observations,
    alternatives,
    selected,
    rationale,
    risks,
    unresolved,
    steps,
    rollback,
    escalation,
    forecast,
    lease_epoch,
  ))
}

/// Decoder for the small input spec `decision-record complete` reads.
pub fn completion_spec_decoder() -> decode.Decoder(CompletionSpec) {
  use observed_actions <- decode.field(
    "observed_actions",
    decode.list(decode.string),
  )
  use outcome <- decode.field("outcome", decode.string)
  use forecast_resolution <- decode.field("forecast_resolution", decode.string)
  use #(tokens, usd) <- decode.field("consumed", {
    use tokens <- decode.field("tokens", decode.string)
    use usd <- decode.field("usd", number_decoder())
    decode.success(#(tokens, usd))
  })
  decode.success(CompletionSpec(
    observed_actions,
    outcome,
    forecast_resolution,
    tokens,
    usd,
  ))
}

fn identity_scope_decoder() -> decode.Decoder(IdentityScope) {
  use hive <- decode.field("hive", decode.string)
  use tenant <- decode.field("tenant", decode.string)
  use actor_kind <- decode.field("actor_kind", decode.string)
  use actor_id <- decode.field("actor_id", decode.string)
  use session <- decode.field("session", decode.string)
  use #(provider, model) <- decode.field("provider_model", {
    use provider <- decode.field("provider", decode.string)
    use model <- decode.field("model", decode.string)
    decode.success(#(provider, model))
  })
  decode.success(IdentityScope(
    hive,
    tenant,
    actor_kind,
    actor_id,
    session,
    provider,
    model,
  ))
}

fn task_authority_decoder() -> decode.Decoder(TaskAuthority) {
  use task <- decode.field("task", decode.string)
  use resource <- decode.field("resource", decode.string)
  use lease_epoch <- decode.field("lease_epoch", decode.string)
  use proposed_action <- decode.field("proposed_action", decode.string)
  use policy_refs <- decode.field("policy_refs", decode.list(decode.string))
  use authorization <- decode.field("authorization", decode.string)
  decode.success(TaskAuthority(
    task,
    resource,
    lease_epoch,
    proposed_action,
    policy_refs,
    authorization,
  ))
}

fn evidence_choice_decoder() -> decode.Decoder(EvidenceChoice) {
  use observations <- decode.field(
    "observations",
    decode.list(observation_decoder()),
  )
  use alternatives <- decode.field(
    "alternatives",
    decode.list(alternative_decoder()),
  )
  use selected <- decode.field("selected", decode.string)
  use rationale <- decode.field("rationale", decode.string)
  use risks <- decode.field("risks", decode.list(decode.string))
  use unresolved <- decode.field("unresolved", decode.list(decode.string))
  decode.success(EvidenceChoice(
    observations,
    alternatives,
    selected,
    rationale,
    risks,
    unresolved,
  ))
}

fn process_decoder() -> decode.Decoder(ProcessBlock) {
  use steps <- decode.field("steps", decode.list(decode.string))
  use rollback <- decode.field("rollback", decode.string)
  use escalation <- decode.field("escalation", decode.string)
  decode.success(ProcessBlock(steps, rollback, escalation))
}

fn forecast_block_decoder() -> decode.Decoder(ForecastBlock) {
  use horizon <- decode.field("horizon", decode.string)
  use clock_domain <- decode.field("clock_domain", decode.string)
  use observed_at <- decode.field("observed_at", decode.string)
  use expires_at <- decode.field("expires_at", decode.string)
  use predicted_outcome <- decode.field("predicted_outcome", decode.string)
  use probability <- decode.field("probability", number_decoder())
  use basis <- decode.field("basis", decode.string)
  use unknowns <- decode.field("unknowns", decode.list(decode.string))
  decode.success(ForecastBlock(
    horizon,
    clock_domain,
    observed_at,
    expires_at,
    predicted_outcome,
    probability,
    basis,
    unknowns,
  ))
}

/// Decoder for a stored record's `carrier` and `phase` only, used to decide
/// whether `complete_record` may proceed before doing a full decode.
fn header_decoder() -> decode.Decoder(#(String, String)) {
  use carrier_value <- decode.field("carrier", decode.string)
  use phase <- decode.field("phase", decode.string)
  decode.success(#(carrier_value, phase))
}

fn completed_block_decoder() -> decode.Decoder(CompletedBlock) {
  use observed_at <- decode.field("observed_at", decode.string)
  use observed_actions <- decode.field(
    "observed_actions",
    decode.list(decode.string),
  )
  use outcome <- decode.field("outcome", decode.string)
  use forecast_resolution <- decode.field("forecast_resolution", decode.string)
  use #(tokens, usd) <- decode.field("consumed", {
    use tokens <- decode.field("tokens", decode.string)
    use usd <- decode.field("usd", number_decoder())
    decode.success(#(tokens, usd))
  })
  decode.success(CompletedBlock(
    observed_at,
    observed_actions,
    outcome,
    forecast_resolution,
    tokens,
    usd,
  ))
}

pub fn stored_record_decoder() -> decode.Decoder(StoredRecord) {
  use carrier_value <- decode.field("carrier", decode.string)
  use phase <- decode.field("phase", decode.string)
  use decision_id <- decode.field("decision_id", decode.string)
  use identity_scope <- decode.field("identity_scope", identity_scope_decoder())
  use task_authority <- decode.field("task_authority", task_authority_decoder())
  use evidence_choice <- decode.field(
    "evidence_choice",
    evidence_choice_decoder(),
  )
  use process <- decode.field("process", process_decoder())
  use forecast <- decode.field("forecast", forecast_block_decoder())
  decode.success(StoredRecord(
    carrier_value,
    phase,
    decision_id,
    identity_scope,
    task_authority,
    evidence_choice,
    process,
    forecast,
  ))
}

// ---- CLI entry points ----

/// `decision-record prepare <out_dir> <slug> <spec.json>`.
///
/// `actor_id` comes from `UOS_ACTOR_ID` (default `"L0-fable"`), `session` from
/// `UOS_SESSION_ID` (default `"unknown"`), `model` from `UOS_MODEL` (default
/// `"claude-fable-5-1"`, provider fixed `"anthropic"`, `self_report: true`).
/// `observed_at`/`expires_at` are stamped from the host clock
/// (`board.system_time_us` + `telemetry.iso8601_us`), never from spec input.
/// Returns the written file path on success.
pub fn write_prepared(
  out_dir: String,
  slug: String,
  spec_path: String,
) -> Result(String, String) {
  use spec_text <- result.try(
    board.file_read(spec_path)
    |> result.map_error(fn(e) { "spec read error (" <> spec_path <> "): " <> e }),
  )
  use spec <- result.try(
    json.parse(spec_text, prepare_spec_decoder())
    |> result.replace_error(
      "spec error: "
      <> spec_path
      <> " is missing a required field or is malformed",
    ),
  )
  let now_us = board.system_time_us()
  let observed_iso = telemetry.iso8601_us(now_us)
  let stamp = stamp_from_iso(observed_iso)
  let actor_id = getenv("UOS_ACTOR_ID", "L0-fable")
  let session = getenv("UOS_SESSION_ID", "unknown")
  let model = getenv("UOS_MODEL", "claude-fable-5-1")
  let id = decision_id(actor_id, slug, stamp)
  let expires_iso = expires_at_iso(now_us, spec.forecast.horizon_minutes)
  let record =
    StoredRecord(
      carrier: carrier,
      phase: "prepared",
      decision_id: id,
      identity_scope: IdentityScope(
        hive: "uos-tui-swarm",
        tenant: "uos",
        actor_kind: "model-agent (uos_swarm decision-record CLI)",
        actor_id: actor_id,
        session: session,
        provider: "anthropic",
        model: model,
      ),
      task_authority: TaskAuthority(
        task: spec.task,
        resource: spec.resource,
        lease_epoch: spec.lease_epoch,
        proposed_action: spec.proposed_action,
        policy_refs: spec.policy_refs,
        authorization: spec.authorization,
      ),
      evidence_choice: EvidenceChoice(
        observations: spec.observations,
        alternatives: spec.alternatives,
        selected: spec.selected,
        rationale: spec.rationale,
        risks: spec.risks,
        unresolved: spec.unresolved,
      ),
      process: ProcessBlock(
        steps: spec.steps,
        rollback: spec.rollback,
        escalation: spec.escalation,
      ),
      forecast: ForecastBlock(
        horizon: horizon_label(spec.forecast.horizon_minutes),
        clock_domain: clock_domain,
        observed_at: observed_iso,
        expires_at: expires_iso,
        predicted_outcome: spec.forecast.predicted_outcome,
        probability: spec.forecast.probability,
        basis: spec.forecast.basis,
        unknowns: spec.forecast.unknowns,
      ),
    )
  let out_path = join_path(out_dir, file_name(slug, stamp))
  use _ <- result.try(
    board.file_write(out_path, json.to_string(prepared_json(record)))
    |> result.map_error(fn(e) { "write failed (" <> out_path <> "): " <> e }),
  )
  Ok(out_path)
}

/// `decision-record complete <record.json> <completion.json>`.
///
/// Refuses (without writing) when the record's `phase` is already
/// `"completed"` or its `carrier` is not `"uos-decision-record/v1"`. On
/// success, rewrites `record_path` with a `completed` object added,
/// `phase` set to `"completed"`, and the decoded `forecast` re-encoded
/// unchanged. Returns the record's `decision_id`.
pub fn complete_record(
  record_path: String,
  completion_path: String,
) -> Result(String, String) {
  use record_text <- result.try(
    board.file_read(record_path)
    |> result.map_error(fn(e) {
      "record read error (" <> record_path <> "): " <> e
    }),
  )
  use #(carrier_value, phase) <- result.try(
    json.parse(record_text, header_decoder())
    |> result.replace_error(
      "record error: " <> record_path <> " is not a readable JSON object",
    ),
  )
  use _ <- result.try(case carrier_value == carrier {
    True -> Ok(Nil)
    False ->
      Error("refused: " <> record_path <> " is not a " <> carrier <> " file")
  })
  use _ <- result.try(case phase == "completed" {
    False -> Ok(Nil)
    True -> Error("refused: " <> record_path <> " is already completed")
  })
  use record <- result.try(
    json.parse(record_text, stored_record_decoder())
    |> result.replace_error(
      "record error: "
      <> record_path
      <> " is missing a required field or is malformed",
    ),
  )
  use completion_text <- result.try(
    board.file_read(completion_path)
    |> result.map_error(fn(e) {
      "completion read error (" <> completion_path <> "): " <> e
    }),
  )
  use completion <- result.try(
    json.parse(completion_text, completion_spec_decoder())
    |> result.replace_error(
      "completion error: "
      <> completion_path
      <> " is missing a required field or is malformed",
    ),
  )
  let observed_iso = telemetry.iso8601_us(board.system_time_us())
  let completed =
    completed_json(
      observed_iso,
      completion.observed_actions,
      completion.outcome,
      completion.forecast_resolution,
      completion.consumed_tokens,
      completion.consumed_usd,
    )
  use _ <- result.try(
    board.file_write(
      record_path,
      json.to_string(completed_record_json(record, completed)),
    )
    |> result.map_error(fn(e) { "write failed (" <> record_path <> "): " <> e }),
  )
  Ok(record.decision_id)
}

/// Re-decodes a stored record's `forecast` object; used by tests to assert the
/// forecast is byte-identical (structurally equal) before and after `complete_record`.
pub fn read_forecast(record_path: String) -> Result(ForecastBlock, String) {
  use text <- result.try(
    board.file_read(record_path)
    |> result.map_error(fn(e) { "record read error: " <> e }),
  )
  use record <- result.try(
    json.parse(text, stored_record_decoder())
    |> result.replace_error("record error: missing or malformed forecast"),
  )
  Ok(record.forecast)
}

/// The `phase` of a stored record (`"prepared"` or `"completed"`), used by
/// tests and callers that only need to check completion status.
pub fn read_phase(record_path: String) -> Result(String, String) {
  use text <- result.try(
    board.file_read(record_path)
    |> result.map_error(fn(e) { "record read error: " <> e }),
  )
  use #(_, phase) <- result.try(
    json.parse(text, header_decoder())
    |> result.replace_error("record error: missing or malformed header"),
  )
  Ok(phase)
}

/// The `completed` object of a stored record, once `complete_record` has
/// added one; used by tests to assert its contents.
pub fn read_completed(record_path: String) -> Result(CompletedBlock, String) {
  use text <- result.try(
    board.file_read(record_path)
    |> result.map_error(fn(e) { "record read error: " <> e }),
  )
  json.parse(
    text,
    decode.field("completed", completed_block_decoder(), decode.success),
  )
  |> result.replace_error("record error: missing or malformed completed")
}
