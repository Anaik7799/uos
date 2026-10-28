//// Closed typed planning intents for the private development harness.
////
//// Identity comes from the serving Execution, never the payload. Persistence is
//// the canonical Sa-plan CLI through literal argv with explicit `--format json`.
//// Two CLI calls are not one transaction: Store.with_transaction is atomic only
//// inside one OCaml invocation, so no cross-command atomicity, hostile-writer
//// or production guarantee is asserted here.

import cepaf_gleam/harness/admission as a
import cepaf_gleam/harness/clock
import cepaf_gleam/harness/development as dev
import cepaf_gleam/harness/files
import cepaf_gleam/harness/value
import cepaf_gleam/planning/sa_plan_bridge as sa
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub type Intent {
  CreatePlan
  CreateTask
  PublishEvidence
}

pub type Outcome {
  Applied
  Replayed
  Refused(String)
  Uncertain(String)
}

/// A resolution is a new append-only fact about an immutable uncertain ledger.
/// It never changes the original intent or result record.
pub type Resolution {
  Resolution(
    disposition: String,
    key: String,
    logical_id: String,
    payload_sha256: String,
    evidence_path: String,
    observed_evidence_sha256: Option(String),
    postcondition_sha256: Option(String),
    reason: String,
  )
}

/// Effects the interpreter needs. A bounded in-memory instance lets tests drive
/// real interpreter decisions without touching the canonical store.
pub type Backend {
  Backend(
    dispatch: fn(List(String)) -> Result(String, String),
    readback: fn(List(String)) -> Result(String, String),
    write_evidence: fn(String, String) -> Result(Nil, String),
  )
}

pub fn canonical_backend() -> Backend {
  Backend(
    dispatch: sa.run_sa_plan_cli,
    readback: sa.run_sa_plan_cli,
    write_evidence: fn(path, body) { files.create(dev.root, path, body) },
  )
}

pub const allowed_keys = [
  "intent", "logical_id", "target_plan", "task_id", "title", "evidence_path",
  "evidence_body",
]

pub const max_payload_bytes = 65_536

pub fn outcome_label(outcome: Outcome) -> String {
  case outcome {
    Applied -> "Applied"
    Replayed -> "Replayed"
    Refused(_) -> "Refused"
    Uncertain(_) -> "Uncertain"
  }
}

pub fn parse_intent(name: String) -> Result(Intent, String) {
  case name {
    "CreatePlan" -> Ok(CreatePlan)
    "CreateTask" -> Ok(CreateTask)
    "PublishEvidence" -> Ok(PublishEvidence)
    _ -> Error("unknown_intent")
  }
}

pub fn kind_label(intent: Intent) -> String {
  case intent {
    CreatePlan -> "CreatePlan"
    CreateTask -> "CreateTask"
    PublishEvidence -> "PublishEvidence"
  }
}

/// Unambiguous canonical JSON tuple, never separator concatenation, and it
/// excludes grant and attempt so one logical operation has one key everywhere.
pub fn logical_key(plan: String, task: String, logical_id: String) -> String {
  json.to_string(
    json.object([
      #("parent_plan", json.string(plan)),
      #("parent_task", json.string(task)),
      #("logical_id", json.string(logical_id)),
    ]),
  )
  |> files.digest
}

pub fn ledger_path(key: String, suffix: String) -> String {
  "var/harness/effects/planning@" <> key <> "@" <> suffix <> ".json"
}

pub fn resolution_path(key: String) -> String {
  ledger_path(key, "resolution")
}

pub fn transport_receipt_id(binding: dev.Binding, key: String) -> String {
  key <> "-a" <> string.inspect(binding.attempt)
}

pub fn payload_within_bound(body: String) -> Result(Nil, String) {
  a.require(
    string.byte_size(body) <= max_payload_bytes,
    "payload_bound_exceeded",
  )
}

pub fn target_allowed(
  target: String,
  allowlist: List(String),
) -> Result(Nil, String) {
  a.require(
    target != "" && list.contains(allowlist, target),
    "planning_target_refused",
  )
}

pub fn evidence_path_allowed(path: String) -> Result(Nil, String) {
  let shaped = case files.relative_path(path) {
    Ok(_) -> True
    Error(_) -> False
  }
  let extension =
    string.ends_with(path, ".md") || string.ends_with(path, ".json")
  let area =
    string.starts_with(path, "docs/")
    || string.starts_with(path, "governance/planning/")
  a.require(shaped && extension && area, "evidence_path_refused")
}

pub fn authorized_targets(grant: a.Grant) -> Result(List(String), String) {
  use body <- result.try(files.read(dev.root, grant.path))
  use _ <- result.try(a.require(
    files.digest(body) == grant.digest,
    "grant_digest_drift",
  ))
  json.parse(
    body,
    decode.field("planning_targets", decode.list(decode.string), decode.success),
  )
  |> result.map_error(fn(_) { "planning_targets_absent" })
}

/// Any failure after the key is reserved is Uncertain, never a refusal: the
/// canonical effect may already have landed.
pub fn classify_backend(outcome: Result(String, String)) -> Outcome {
  case outcome {
    Ok(_) -> Applied
    Error(reason) -> Uncertain(reason)
  }
}

pub fn dispatch_argv(
  intent: Intent,
  target: String,
  task_id: String,
  name: String,
  title: String,
) -> List(String) {
  case intent {
    CreatePlan -> ["plan", "create", target, name, title]
    CreateTask -> ["task", "create", target, task_id, name, title]
    PublishEvidence -> ["plan", "show", target, "--format", "json"]
  }
}

pub fn readback_argv(
  intent: Intent,
  target: String,
  task_id: String,
) -> #(List(String), String) {
  case intent {
    CreatePlan -> #(["plan", "show", target, "--format", "json"], target)
    CreateTask -> #(
      ["task", "show", target, task_id, "--format", "json"],
      task_id,
    )
    PublishEvidence -> #(["plan", "show", target, "--format", "json"], target)
  }
}

/// Observed stdout under `--format json` is exactly one JSON record line plus
/// one `sa-plan-pipeline` diagnostic line, so stdout as a whole is not JSON.
pub fn record_line(raw: String) -> Result(String, String) {
  let lines =
    string.split(raw, "\n")
    |> list.map(string.trim)
    |> list.filter(fn(line) { line != "" })
  let diagnostics =
    list.filter(lines, fn(line) { string.starts_with(line, "sa-plan-pipeline") })
  let records =
    list.filter(lines, fn(line) {
      !string.starts_with(line, "sa-plan-pipeline")
      && string.starts_with(line, "{")
    })
  let unexpected =
    list.length(lines) - list.length(diagnostics) - list.length(records)
  use _ <- result.try(a.require(unexpected == 0, "readback_unexpected_output"))
  use _ <- result.try(a.require(
    list.length(diagnostics) <= 1,
    "readback_unexpected_output",
  ))
  case records {
    [line] -> Ok(line)
    [] -> Error("readback_absent")
    _ -> Error("readback_ambiguous")
  }
}

fn record_text(parsed: value.Value, key: String) -> Result(String, String) {
  case value.get(parsed, key) {
    Ok(value.Text(text)) -> Ok(text)
    _ -> Error("readback_field_absent:" <> key)
  }
}

fn text_field(parsed: value.Value, key: String) -> Result(String, String) {
  case value.get(parsed, key) {
    Ok(value.Text(text)) -> Ok(text)
    _ -> Error("planning_payload_field:" <> key)
  }
}

fn parsed_record(body: String, error: String) -> Result(value.Value, String) {
  json.parse(body, value.decoder()) |> result.map_error(fn(_) { error })
}

fn record_matches(
  parsed: value.Value,
  key: String,
  expected: String,
  refusal: String,
) -> Result(Nil, String) {
  use actual <- result.try(record_text(parsed, key))
  a.require(actual == expected, refusal)
}

fn scope_digest(scope: a.Scope) -> String {
  json.object([
    #("plan", json.string(scope.plan)),
    #("task", json.string(scope.task)),
    #("reads", json.array(scope.reads, json.string)),
    #("writes", json.array(scope.writes, json.string)),
    #("sources", json.array(scope.sources, json.string)),
    #("tests", json.array(scope.tests, json.string)),
    #("portfolio", json.string(scope.portfolio)),
    #("allowed_clients", json.array(scope.allowed_clients, json.string)),
    #(
      "allowed_client_actions",
      json.array(scope.allowed_client_actions, json.string),
    ),
  ])
  |> json.to_string
  |> files.digest
}

/// Classify only an immutable uncertain result with an exact parent, logical
/// key, payload digest and current Andon pointer. A read-only PublishEvidence
/// plan-show failure is known not to have reached its evidence writer. Other
/// evidence writes require an exact content hash; CreatePlan/CreateTask require
/// canonical readback. Absence after a mutation is never treated as proof of
/// non-application.
pub fn classify_resolution(
  execution: a.Execution,
  logical_id: String,
  pointer: String,
  intent_body: String,
  result_body: String,
  observed_evidence: Option(String),
  postcondition: Result(String, String),
  targets: List(String),
) -> Result(Resolution, String) {
  let binding = execution.binding
  let key = logical_key(binding.plan, binding.task, logical_id)
  use current_key <- result.try(pointer_key(pointer))
  use _ <- result.try(a.require(
    current_key == key,
    "planning_resolution_not_current",
  ))
  use intent <- result.try(parsed_record(intent_body, "planning_intent_json"))
  use saved <- result.try(parsed_record(result_body, "planning_result_json"))
  use _ <- result.try(record_matches(
    intent,
    "schema",
    "uos.harness-planning-intent.v1",
    "planning_intent_schema",
  ))
  use _ <- result.try(record_matches(
    saved,
    "schema",
    "uos.harness-planning-intent.v1",
    "planning_result_schema",
  ))
  use _ <- result.try(record_matches(intent, "key", key, "planning_intent_key"))
  use _ <- result.try(record_matches(saved, "key", key, "planning_result_key"))
  use _ <- result.try(record_matches(
    intent,
    "parent_plan",
    binding.plan,
    "planning_intent_parent",
  ))
  use _ <- result.try(record_matches(
    intent,
    "parent_task",
    binding.task,
    "planning_intent_parent",
  ))
  use _ <- result.try(record_matches(
    saved,
    "parent_plan",
    binding.plan,
    "planning_result_parent",
  ))
  use _ <- result.try(record_matches(
    saved,
    "parent_task",
    binding.task,
    "planning_result_parent",
  ))
  use payload <- result.try(record_text(intent, "canonical_payload"))
  use payload_sha <- result.try(record_text(intent, "payload_sha256"))
  use _ <- result.try(a.require(
    files.digest(payload) == payload_sha,
    "planning_intent_payload_digest",
  ))
  use result_payload <- result.try(record_text(saved, "canonical_payload"))
  use result_payload_sha <- result.try(record_text(saved, "payload_sha256"))
  use _ <- result.try(a.require(
    result_payload == payload
      && result_payload_sha == payload_sha
      && files.digest(result_payload) == result_payload_sha,
    "planning_resolution_payload_conflict",
  ))
  use _ <- result.try(record_matches(
    saved,
    "outcome",
    "Uncertain",
    "planning_resolution_requires_uncertain_result",
  ))
  use parsed_payload <- result.try(parsed_record(
    payload,
    "planning_payload_json",
  ))
  use payload_intent <- result.try(text_field(parsed_payload, "intent"))
  use payload_id <- result.try(text_field(parsed_payload, "logical_id"))
  use target <- result.try(text_field(parsed_payload, "target_plan"))
  use task_id <- result.try(text_field(parsed_payload, "task_id"))
  use title <- result.try(text_field(parsed_payload, "title"))
  use evidence_path <- result.try(text_field(parsed_payload, "evidence_path"))
  use _ <- result.try(a.require(
    payload_id == logical_id,
    "planning_resolution_logical_id",
  ))
  use _ <- result.try(target_allowed(target, targets))
  use action <- result.try(parse_intent(payload_intent))
  use detail <- result.try(record_text(saved, "detail"))
  let expected_evidence_sha = case
    value.get(parsed_payload, "evidence_body_sha256")
  {
    Ok(value.Text(sha)) -> Some(sha)
    _ -> None
  }
  case action {
    PublishEvidence -> {
      use _ <- result.try(a.require(
        list.contains(execution.scope.writes, evidence_path),
        "planning_resolution_evidence_scope",
      ))
      use expected_sha <- result.try(case expected_evidence_sha {
        Some(sha) ->
          case a.digest_valid(sha) {
            True -> Ok(sha)
            False -> Error("planning_resolution_evidence_digest")
          }
        _ -> Error("planning_resolution_evidence_digest")
      })
      case observed_evidence {
        Some(body) ->
          case files.digest(body) == expected_sha {
            True ->
              Ok(Resolution(
                "RESOLVED_APPLIED",
                key,
                logical_id,
                payload_sha,
                evidence_path,
                Some(files.digest(body)),
                None,
                "exact evidence bytes observed at the scoped publish path",
              ))
            False -> Error("planning_resolution_evidence_mismatch")
          }
        None if detail == "sa-plan exited 1" ->
          Ok(Resolution(
            "RESOLVED_NOT_APPLIED",
            key,
            logical_id,
            payload_sha,
            evidence_path,
            None,
            None,
            "read-only plan-show failed before the evidence writer",
          ))
        None -> Error("planning_resolution_inconclusive:" <> key)
      }
    }
    CreatePlan -> {
      let expected_name = plan_name(target)
      use name <- result.try(expected_name)
      use raw <- result.try(
        postcondition
        |> result.map_error(fn(_) { "planning_resolution_inconclusive:" <> key }),
      )
      use _ <- result.try(
        readback_matches(target, "", name, title, raw)
        |> result.map_error(fn(_) { "planning_resolution_inconclusive:" <> key }),
      )
      Ok(Resolution(
        "RESOLVED_APPLIED",
        key,
        logical_id,
        payload_sha,
        "",
        None,
        Some(files.digest(raw)),
        "exact canonical plan readback observed; no redispatch",
      ))
    }
    CreateTask -> {
      let expected_name = task_name(task_id)
      use name <- result.try(expected_name)
      use raw <- result.try(
        postcondition
        |> result.map_error(fn(_) { "planning_resolution_inconclusive:" <> key }),
      )
      use _ <- result.try(
        readback_matches(task_id, target, name, title, raw)
        |> result.map_error(fn(_) { "planning_resolution_inconclusive:" <> key }),
      )
      Ok(Resolution(
        "RESOLVED_APPLIED",
        key,
        logical_id,
        payload_sha,
        "",
        None,
        Some(files.digest(raw)),
        "exact canonical task readback observed; no redispatch",
      ))
    }
  }
}

pub fn resolution_record(
  execution: a.Execution,
  resolution: Resolution,
  intent_body: String,
  result_body: String,
  observed_at: json.Json,
) -> String {
  let Resolution(
    disposition,
    key,
    logical_id,
    payload_sha,
    evidence_path,
    evidence_sha,
    postcondition_sha,
    reason,
  ) = resolution
  json.object([
    #("schema", json.string("uos.harness-planning-resolution.v1")),
    #("kind", json.string("planning_resolution")),
    #("disposition", json.string(disposition)),
    #("key", json.string(key)),
    #("logical_id", json.string(logical_id)),
    #("parent_plan", json.string(execution.binding.plan)),
    #("parent_task", json.string(execution.binding.task)),
    #("grant_sha256", json.string(execution.grant.digest)),
    #("worker", json.string(execution.binding.worker)),
    #("session", json.string(execution.binding.session)),
    #("attempt", json.int(execution.binding.attempt)),
    #("coordinator_epoch", json.int(execution.binding.epoch)),
    #("scope_sha256", json.string(scope_digest(execution.scope))),
    #("payload_sha256", json.string(payload_sha)),
    #("intent_sha256", json.string(files.digest(intent_body))),
    #("result_sha256", json.string(files.digest(result_body))),
    #("evidence_path", json.string(evidence_path)),
    #("observed_evidence_sha256", option_json(evidence_sha)),
    #("postcondition_sha256", option_json(postcondition_sha)),
    #("reason", json.string(reason)),
    #("observed_at", observed_at),
    #("execution", a.observe_execution(execution)),
    #("system_admission", json.bool(False)),
  ])
  |> json.to_string
}

fn option_json(option: Option(String)) -> json.Json {
  case option {
    Some(value) -> json.string(value)
    None -> json.null()
  }
}

pub fn validate_resolution(
  body: String,
  execution: a.Execution,
  resolution: Resolution,
  intent_body: String,
  result_body: String,
) -> Result(Nil, String) {
  use parsed <- result.try(parsed_record(body, "planning_resolution_json"))
  let Resolution(
    disposition,
    key,
    logical_id,
    payload_sha,
    evidence_path,
    evidence_sha,
    postcondition_sha,
    reason,
  ) = resolution
  use _ <- result.try(record_matches(
    parsed,
    "schema",
    "uos.harness-planning-resolution.v1",
    "planning_resolution_schema",
  ))
  use _ <- result.try(record_matches(
    parsed,
    "kind",
    "planning_resolution",
    "planning_resolution_kind",
  ))
  use _ <- result.try(record_matches(
    parsed,
    "disposition",
    disposition,
    "planning_resolution_disposition",
  ))
  use _ <- result.try(record_matches(
    parsed,
    "key",
    key,
    "planning_resolution_key",
  ))
  use _ <- result.try(record_matches(
    parsed,
    "logical_id",
    logical_id,
    "planning_resolution_logical_id",
  ))
  use _ <- result.try(record_matches(
    parsed,
    "parent_plan",
    execution.binding.plan,
    "planning_resolution_parent",
  ))
  use _ <- result.try(record_matches(
    parsed,
    "parent_task",
    execution.binding.task,
    "planning_resolution_parent",
  ))
  use _ <- result.try(record_matches(
    parsed,
    "grant_sha256",
    execution.grant.digest,
    "planning_resolution_grant",
  ))
  use _ <- result.try(record_matches(
    parsed,
    "worker",
    execution.binding.worker,
    "planning_resolution_worker",
  ))
  use _ <- result.try(record_matches(
    parsed,
    "session",
    execution.binding.session,
    "planning_resolution_session",
  ))
  use _ <- result.try(record_matches(
    parsed,
    "scope_sha256",
    scope_digest(execution.scope),
    "planning_resolution_scope",
  ))
  use _ <- result.try(record_matches(
    parsed,
    "payload_sha256",
    payload_sha,
    "planning_resolution_payload",
  ))
  use _ <- result.try(record_matches(
    parsed,
    "intent_sha256",
    files.digest(intent_body),
    "planning_resolution_intent",
  ))
  use _ <- result.try(record_matches(
    parsed,
    "result_sha256",
    files.digest(result_body),
    "planning_resolution_result",
  ))
  use _ <- result.try(record_matches(
    parsed,
    "evidence_path",
    evidence_path,
    "planning_resolution_evidence_path",
  ))
  use _ <- result.try(record_matches(
    parsed,
    "reason",
    reason,
    "planning_resolution_reason",
  ))
  use _ <- result.try(a.require(
    value.get(parsed, "attempt") == Ok(value.Integer(execution.binding.attempt))
      && value.get(parsed, "coordinator_epoch")
      == Ok(value.Integer(execution.binding.epoch)),
    "planning_resolution_fence",
  ))
  use observed_evidence <- result.try(optional_digest(
    parsed,
    "observed_evidence_sha256",
  ))
  use observed_postcondition <- result.try(optional_digest(
    parsed,
    "postcondition_sha256",
  ))
  use _ <- result.try(a.require(
    observed_evidence == evidence_sha
      && observed_postcondition == postcondition_sha,
    "planning_resolution_observation",
  ))
  use _ <- result.try(case value.get(parsed, "observed_at") {
    Ok(value.Object(fields)) -> resolution_clock_valid(value.Object(fields))
    _ -> Error("planning_resolution_clock")
  })
  case disposition {
    "RESOLVED_APPLIED" | "RESOLVED_NOT_APPLIED" -> Ok(Nil)
    _ -> Error("planning_resolution_disposition")
  }
}

fn resolution_clock_valid(witness: value.Value) -> Result(Nil, String) {
  use utc <- result.try(record_text(witness, "utc_us"))
  use boot <- result.try(record_text(witness, "boot_us"))
  use host <- result.try(record_text(witness, "host_id"))
  use boot_id <- result.try(record_text(witness, "boot_id"))
  use _ <- result.try(case int.parse(utc), int.parse(boot) {
    Ok(_), Ok(_) -> Ok(Nil)
    _, _ -> Error("planning_resolution_clock")
  })
  a.require(host != "" && boot_id != "", "planning_resolution_clock")
}

fn optional_digest(
  parsed: value.Value,
  key: String,
) -> Result(Option(String), String) {
  case value.get(parsed, key) {
    Ok(value.Null) -> Ok(None)
    Ok(value.Text(sha)) ->
      case a.digest_valid(sha) {
        True -> Ok(Some(sha))
        False -> Error("planning_resolution_digest_field:" <> key)
      }
    _ -> Error("planning_resolution_digest_field:" <> key)
  }
}

fn resolution_from_record(body: String) -> Result(Resolution, String) {
  use parsed <- result.try(parsed_record(body, "planning_resolution_json"))
  use disposition <- result.try(record_text(parsed, "disposition"))
  use key <- result.try(record_text(parsed, "key"))
  use logical_id <- result.try(record_text(parsed, "logical_id"))
  use payload_sha <- result.try(record_text(parsed, "payload_sha256"))
  use evidence_path <- result.try(record_text(parsed, "evidence_path"))
  use evidence_sha <- result.try(optional_digest(
    parsed,
    "observed_evidence_sha256",
  ))
  use postcondition_sha <- result.try(optional_digest(
    parsed,
    "postcondition_sha256",
  ))
  use reason <- result.try(record_text(parsed, "reason"))
  Ok(Resolution(
    disposition,
    key,
    logical_id,
    payload_sha,
    evidence_path,
    evidence_sha,
    postcondition_sha,
    reason,
  ))
}

/// Reconcile only planning ledgers. This function never dispatches a mutation
/// or invokes the evidence writer. A sidecar is exclusive-create and binds the
/// old immutable records, payload, parent scope, worker fence, and fresh clock.
pub fn reconcile(
  execution: a.Execution,
  logical_id: String,
) -> Result(Option(json.Json), String) {
  use _ <- result.try(a.require(
    dev.valid_identifier(logical_id),
    "logical_id_required",
  ))
  use proof <- result.try(a.fence(execution, 15_000))
  let key =
    logical_key(execution.binding.plan, execution.binding.task, logical_id)
  let intent_path = ledger_path(key, "intent")
  let result_path = ledger_path(key, "result")
  let sidecar_path = resolution_path(key)
  use intent <- result.try(a.read_optional(intent_path))
  use saved <- result.try(a.read_optional(result_path))
  case intent, saved {
    None, None -> Ok(None)
    Some(intent_body), Some(result_body) -> {
      use pointer <- result.try(
        a.read_optional(andon_path(
          execution.binding.plan,
          execution.binding.task,
        )),
      )
      use pointer_body <- result.try(case pointer {
        Some(body) -> Ok(body)
        None -> Error("planning_resolution_pointer_missing")
      })
      use current_key <- result.try(pointer_key(pointer_body))
      use _ <- result.try(a.require(
        current_key == key,
        "planning_resolution_not_current",
      ))
      use existing <- result.try(a.read_optional(sidecar_path))
      case existing {
        Some(sidecar) -> {
          use resolution <- result.try(resolution_from_record(sidecar))
          use _ <- result.try(validate_resolution(
            sidecar,
            execution,
            resolution,
            intent_body,
            result_body,
          ))
          json.parse(sidecar, value.decoder())
          |> result.map(value.encode)
          |> result.map(Some)
          |> result.map_error(fn(_) { "planning_resolution_json" })
        }
        None -> {
          use targets <- result.try(authorized_targets(execution.grant))
          use payload <- result.try(recorded_field(
            intent_body,
            "canonical_payload",
          ))
          use parsed_payload <- result.try(parsed_record(
            payload,
            "planning_payload_json",
          ))
          use action <- result.try(text_field(parsed_payload, "intent"))
          let observed_evidence = case action {
            "PublishEvidence" -> {
              use path <- result.try(text_field(parsed_payload, "evidence_path"))
              a.require(
                list.contains(execution.scope.writes, path),
                "planning_resolution_evidence_scope",
              )
              |> result.try(fn(_) { a.read_optional(path) })
            }
            _ -> Ok(None)
          }
          use observed_evidence <- result.try(observed_evidence)
          let postcondition = case action {
            "PublishEvidence" -> Error("read_phase_not_applicable")
            "CreatePlan" | "CreateTask" -> {
              use target <- result.try(text_field(parsed_payload, "target_plan"))
              use task_id <- result.try(text_field(parsed_payload, "task_id"))
              let #(arguments, _) =
                readback_argv(
                  case action {
                    "CreatePlan" -> CreatePlan
                    _ -> CreateTask
                  },
                  target,
                  task_id,
                )
              sa.run_sa_plan_cli(arguments)
            }
            _ -> Error("planning_resolution_unknown_intent")
          }
          use resolution <- result.try(classify_resolution(
            execution,
            logical_id,
            pointer_body,
            intent_body,
            result_body,
            observed_evidence,
            postcondition,
            targets,
          ))
          let sidecar =
            resolution_record(
              execution,
              resolution,
              intent_body,
              result_body,
              clock.to_json(proof.clock),
            )
          use _ <- result.try(a.fence(execution, 0))
          let write_outcome = files.create(dev.root, sidecar_path, sidecar)
          let stored = case write_outcome {
            Ok(_) -> Ok(sidecar)
            Error(_) -> {
              use concurrent <- result.try(a.read_optional(sidecar_path))
              case concurrent {
                Some(existing_body) -> Ok(existing_body)
                None -> Error("planning_resolution_append_failed")
              }
            }
          }
          use stored <- result.try(stored)
          use stored_resolution <- result.try(resolution_from_record(stored))
          use _ <- result.try(a.require(
            stored_resolution == resolution,
            "planning_resolution_conflict",
          ))
          use _ <- result.try(validate_resolution(
            stored,
            execution,
            stored_resolution,
            intent_body,
            result_body,
          ))
          use final <- result.try(a.fence(execution, 0))
          use _ <- result.try(clock.continuity(proof.clock, final.clock))
          json.parse(stored, value.decoder())
          |> result.map(value.encode)
          |> result.map(Some)
          |> result.map_error(fn(_) { "planning_resolution_json" })
        }
      }
    }
    _, _ -> Error("planning_resolution_records_incomplete")
  }
}

pub fn readback_matches(
  expected_id: String,
  expected_parent: String,
  expected_name: String,
  expected_title: String,
  raw: String,
) -> Result(Nil, String) {
  use line <- result.try(record_line(raw))
  use parsed <- result.try(
    json.parse(line, value.decoder())
    |> result.map_error(fn(_) { "readback_unparsable" }),
  )
  use id <- result.try(record_text(parsed, "id"))
  use _ <- result.try(a.require(id == expected_id, "readback_identity_mismatch"))
  use _ <- result.try(case expected_parent {
    "" -> Ok(Nil)
    parent -> {
      use observed <- result.try(record_text(parsed, "plan_id"))
      a.require(observed == parent, "readback_parent_mismatch")
    }
  })
  use _ <- result.try(case expected_name {
    "" -> Ok(Nil)
    name -> {
      use observed <- result.try(record_text(parsed, "name"))
      a.require(observed == name, "readback_name_mismatch")
    }
  })
  case expected_title {
    "" -> Ok(Nil)
    title -> {
      use observed <- result.try(record_text(parsed, "title"))
      a.require(observed == title, "readback_title_mismatch")
    }
  }
}

/// PublishEvidence is only valid for an existing canonical plan. This bounded
/// read is deliberately performed before reserving the Andon pointer or the
/// logical intent ledger, so a known read-only failure cannot latch an unknown
/// effect outcome.
pub fn preflight_target(
  backend: Backend,
  prepared: Prepared,
) -> Result(Nil, String) {
  case prepared.intent {
    PublishEvidence -> {
      let #(arguments, expected_id) =
        readback_argv(PublishEvidence, prepared.target, prepared.task_id)
      case backend.readback(arguments) {
        Ok(raw) ->
          readback_matches(expected_id, "", "", "", raw)
          |> result.map_error(fn(_) { "refused:planning_target_precondition" })
        Error(_) -> Error("refused:planning_target_precondition")
      }
    }
    CreatePlan | CreateTask -> Ok(Nil)
  }
}

pub fn canonical_payload(
  kind: String,
  logical_id: String,
  target: String,
  task_id: String,
  title: String,
  evidence_path: String,
  evidence_body: String,
) -> String {
  json.to_string(
    json.object([
      #("intent", json.string(kind)),
      #("logical_id", json.string(logical_id)),
      #("target_plan", json.string(target)),
      #("task_id", json.string(task_id)),
      #("title", json.string(title)),
      #("evidence_path", json.string(evidence_path)),
      #("evidence_body_sha256", json.string(files.digest(evidence_body))),
    ]),
  )
}

/// Ledger records keep the exact canonical payload and the parent strings, not
/// only the hash, so a later reader can verify rather than trust.
pub fn ledger_record(
  key: String,
  binding: dev.Binding,
  kind: String,
  payload: String,
  outcome: Outcome,
  detail: String,
) -> json.Json {
  json.object([
    #("schema", json.string("uos.harness-planning-intent.v1")),
    #("key", json.string(key)),
    #("parent_plan", json.string(binding.plan)),
    #("parent_task", json.string(binding.task)),
    #("intent", json.string(kind)),
    #("canonical_payload", json.string(payload)),
    #("payload_sha256", json.string(files.digest(payload))),
    #("outcome", json.string(outcome_label(outcome))),
    #("detail", json.string(detail)),
  ])
}

pub fn recorded_field(body: String, key: String) -> Result(String, String) {
  use parsed <- result.try(
    json.parse(body, value.decoder())
    |> result.map_error(fn(_) { "ledger_unparsable" }),
  )
  record_text(parsed, key)
}

fn optional_text(args: value.Value, key: String) -> String {
  case value.get(args, key) {
    Ok(value.Text(text)) -> text
    _ -> ""
  }
}

pub fn submit(
  execution: a.Execution,
  args: value.Value,
) -> Result(json.Json, String) {
  submit_with(execution, args, canonical_backend())
}

pub fn submit_with(
  execution: a.Execution,
  args: value.Value,
  backend: Backend,
) -> Result(json.Json, String) {
  let binding = execution.binding
  use _ <- result.try(precheck(args))
  // Replay is read-only but still needs current reviewed authority, as
  // harness_read_file does, so fence BEFORE the grant and ledger reads.
  // Without this a ReplaySaved return bypassed expiry, current-owner and
  // control checks entirely. The post-risk 25s window below remains for
  // Dispatch only, and its clock is still carried into clock.continuity.
  use _ <- result.try(a.fence(execution, 0))
  use targets <- result.try(authorized_targets(execution.grant))
  // Single prevalidation path, shared with the tests.
  use prepared <- result.try(prepare(args, targets, execution.scope.writes))
  let key = logical_key(binding.plan, binding.task, prepared.logical_id)
  let intent_path = ledger_path(key, "intent")
  let result_path = ledger_path(key, "result")
  use saved <- result.try(a.read_optional(result_path))
  use pending <- result.try(a.read_optional(intent_path))
  // Single ledger decision path, shared with the tests.
  use decision <- result.try(decide_ledger(
    saved,
    pending,
    key,
    binding,
    prepared.payload,
    result_path,
    intent_path,
  ))
  case decision {
    // A replay reports the typed Replayed outcome while preserving the
    // immutable original record it replays.
    ReplaySaved(original) ->
      Ok(
        json.object([
          #("outcome", json.string(outcome_label(Replayed))),
          #("key", json.string(key)),
          #("replayed_from", json.string(result_path)),
          #("original_record", json.string(original)),
          #("original_sha256", json.string(files.digest(original))),
        ]),
      )
    Dispatch -> {
      use _ <- result.try(andon_guard(binding.plan, binding.task))
      submit_unsettled(
        execution,
        backend,
        prepared,
        key,
        intent_path,
        result_path,
      )
    }
  }
}

fn submit_unsettled(
  execution: a.Execution,
  backend: Backend,
  prepared: Prepared,
  key: String,
  intent_path: String,
  result_path: String,
) -> Result(json.Json, String) {
  let binding = execution.binding
  let intent = prepared.intent
  let kind = prepared.kind
  let payload = prepared.payload
  let target = prepared.target
  let task_id = prepared.task_id
  let title = prepared.title
  let native_name = prepared.native_name
  let evidence_path = prepared.evidence_path
  let evidence_body = prepared.evidence_body
  // Fence 0 before the bounded 15s risk phase, then re-observe a 25s
  // window AFTER it, immediately before reservation and the two 10s
  // backend calls, so the risk phase cannot consume the dispatch window.
  use _ <- result.try(a.fence(execution, 0))
  use _ <- result.try(a.risk_check(
    execution.risk_path,
    execution.scope,
    binding.worker,
    binding.attempt,
    True,
  ))
  use _ <- result.try(preflight_target(backend, prepared))
  use proof <- result.try(a.fence(execution, 25_000))
  use _ <- result.try(reserve_pointer(binding.plan, binding.task, key))
  use _ <- result.try(
    files.create(
      dev.root,
      intent_path,
      json.to_string(ledger_record(
        key,
        binding,
        kind,
        payload,
        Uncertain("reserved"),
        "intent reserved before dispatch",
      )),
    )
    |> result.map_error(fn(e) { "uncertain:reserve:" <> e }),
  )
  let dispatched =
    backend.dispatch(dispatch_argv(intent, target, task_id, native_name, title))
  let after_write = case classify_backend(dispatched), intent {
    Uncertain(reason), _ -> Uncertain(reason)
    _, PublishEvidence ->
      case backend.write_evidence(evidence_path, evidence_body) {
        Ok(_) -> Applied
        Error(reason) -> Uncertain("evidence_write:" <> reason)
      }
    _, _ -> Applied
  }
  let outcome = case after_write {
    Uncertain(reason) -> Uncertain(reason)
    _ ->
      case intent {
        // Evidence readback reads the WRITTEN FILE back and compares its bytes,
        // not the metadata of the target plan.
        PublishEvidence ->
          case files.read(dev.root, evidence_path) {
            Error(reason) -> Uncertain("evidence_readback_failed:" <> reason)
            Ok(observed) ->
              case files.digest(observed) == files.digest(evidence_body) {
                True -> Applied
                False -> Uncertain("evidence_readback_mismatch")
              }
          }
        _ -> {
          let #(argv, identity) = readback_argv(intent, target, task_id)
          case backend.readback(argv) {
            Error(reason) -> Uncertain("readback_failed:" <> reason)
            Ok(raw) ->
              case
                readback_matches(
                  identity,
                  case intent {
                    CreateTask -> target
                    _ -> ""
                  },
                  native_name,
                  title,
                  raw,
                )
              {
                Ok(_) -> Applied
                Error(reason) -> Uncertain(reason)
              }
          }
        }
      }
  }
  let detail = case outcome {
    Applied -> "canonical readback matched the requested identity"
    Replayed -> "recorded outcome returned without dispatch"
    Refused(reason) -> reason
    Uncertain(reason) -> reason
  }
  let settled_record =
    ledger_record(key, binding, kind, payload, outcome, detail)
  use _ <- result.try(
    a.fence(execution, 0)
    |> result.try(fn(final) {
      clock.continuity(proof.clock, final.clock)
      |> result.map(fn(_) { final })
    })
    |> result.map_error(fn(e) { "uncertain:post_fence:" <> e }),
  )
  use _ <- result.try(
    files.create(dev.root, result_path, json.to_string(settled_record))
    |> result.map_error(fn(e) { "uncertain:result_save:" <> e }),
  )
  case outcome {
    Applied | Replayed -> {
      Ok(settled_record)
    }
    Refused(reason) -> Error("refused:" <> reason)
    Uncertain(reason) ->
      Error("uncertain:" <> reason <> ";ledger:" <> result_path)
  }
}

/// Native name contract, observed at sa_plan_name.ml:7 and :18 — at least two
/// slash segments, lowercased, each segment ASCII alnum at both ends and
/// [a-z0-9._-] throughout. Names are normalized by the store, so an expected
/// name must be compared in normalized form on readback.
pub fn normalize_name(name: String) -> Result(String, String) {
  let segments = string.split(string.lowercase(name), "/")
  let ok_segment = fn(segment: String) {
    let graphemes = string.to_graphemes(segment)
    let inner =
      list.all(graphemes, fn(c) {
        string.contains("abcdefghijklmnopqrstuvwxyz0123456789._-", c)
      })
    let edge = fn(c) {
      string.contains("abcdefghijklmnopqrstuvwxyz0123456789", c)
    }
    case graphemes {
      [] -> False
      [only] -> edge(only)
      _ ->
        inner
        && segment != "."
        && segment != ".."
        && case list.first(graphemes), list.last(graphemes) {
          Ok(head), Ok(tail) -> edge(head) && edge(tail)
          _, _ -> False
        }
    }
  }
  case list.length(segments) >= 2 && list.all(segments, ok_segment) {
    True -> Ok(string.join(segments, "/"))
    False -> Error("native_name_invalid")
  }
}

/// A plan's name is derived from its allowlisted target, never from a caller
/// identifier, so it is hierarchical and already normalized.
pub fn plan_name(target: String) -> Result(String, String) {
  normalize_name(target)
}

/// A task name is namespaced, so a plain `T01` cannot be used as a name.
pub fn task_name(task_id: String) -> Result(String, String) {
  normalize_name("planning/" <> task_id)
}

pub fn title_valid(title: String) -> Result(Nil, String) {
  a.require(
    title != ""
      && string.byte_size(title) <= 4096
      && !string.contains(title, "\u{0}"),
    "title_required",
  )
}

/// One CURRENT pointer per parent task. It is replaced by CAS, never deleted,
/// so history stays in the immutable per-key intent and result records.
pub fn andon_path(plan: String, task: String) -> String {
  "var/harness/effects/planning-current@"
  <> files.digest(
    json.to_string(
      json.object([
        #("parent_plan", json.string(plan)),
        #("parent_task", json.string(task)),
      ]),
    ),
  )
  <> ".json"
}

fn pointer_body(plan: String, task: String, key: String) -> String {
  json.to_string(
    json.object([
      #("schema", json.string("uos.harness-planning-current.v1")),
      #("parent_plan", json.string(plan)),
      #("parent_task", json.string(task)),
      #("current_key", json.string(key)),
    ]),
  )
}

/// The hold is derived from the CURRENT pointer: the pointed-at key must have a
/// settled result whose schema, key, parent and digest check out and whose
/// outcome is Applied. Missing, corrupt or Uncertain holds the line.
pub fn andon_guard(plan: String, task: String) -> Result(Nil, String) {
  use pointer <- result.try(a.read_optional(andon_path(plan, task)))
  use pointed <- result.try(case pointer {
    None -> Ok(None)
    Some(body) -> {
      use key <- result.try(pointer_key(body))
      a.read_optional(ledger_path(key, "result"))
    }
  })
  use resolution <- result.try(case pointer {
    None -> Ok(None)
    Some(body) -> {
      use key <- result.try(pointer_key(body))
      a.read_optional(resolution_path(key))
    }
  })
  decide_andon_with_resolution(pointer, pointed, resolution, plan, task)
}

/// Point CURRENT at the new key. Creation when absent, CAS replacement
/// otherwise, and only after the guard has already passed.
fn reserve_pointer(
  plan: String,
  task: String,
  key: String,
) -> Result(Nil, String) {
  let path = andon_path(plan, task)
  case a.read_optional(path) {
    Error(reason) -> Error("uncertain:pointer_stat:" <> reason)
    Ok(None) ->
      files.create(dev.root, path, pointer_body(plan, task, key))
      |> result.map_error(fn(e) { "uncertain:pointer_create:" <> e })
    Ok(Some(current)) ->
      files.replace(
        dev.root,
        path,
        files.digest(current),
        pointer_body(plan, task, key),
      )
      |> result.map_error(fn(e) { "uncertain:pointer_cas:" <> e })
  }
}

// --- Pure typed decisions. The IO wrappers below call exactly these, so a
// --- test that drives them drives the real decision path.

pub type Prepared {
  Prepared(
    intent: Intent,
    kind: String,
    logical_id: String,
    target: String,
    task_id: String,
    native_name: String,
    title: String,
    evidence_path: String,
    evidence_body: String,
    payload: String,
  )
}

pub type Decision {
  ReplaySaved(String)
  Dispatch
}

/// Pure prevalidation over the payload, the reviewed targets and the write
/// scope. No file, grant or clock is read here.
pub fn prepare(
  args: value.Value,
  targets: List(String),
  writes: List(String),
) -> Result(Prepared, String) {
  use fields <- result.try(case args {
    value.Object(fields) -> Ok(fields)
    _ -> Error("object_required")
  })
  use _ <- result.try(
    list.try_each(fields, fn(pair) {
      case list.contains(allowed_keys, pair.0) {
        True -> Ok(Nil)
        False -> Error("unknown_payload_key:" <> pair.0)
      }
    }),
  )
  use _ <- result.try(
    list.try_each(fields, fn(pair) {
      case list.count(fields, fn(other) { other.0 == pair.0 }) {
        1 -> Ok(Nil)
        _ -> Error("duplicate_payload_key:" <> pair.0)
      }
    }),
  )
  use name <- result.try(case value.get(args, "intent") {
    Ok(value.Text(name)) -> Ok(name)
    _ -> Error("unknown_intent")
  })
  use intent <- result.try(parse_intent(name))
  use logical_id <- result.try(case value.get(args, "logical_id") {
    Ok(value.Text(id)) ->
      case dev.valid_identifier(id) {
        True -> Ok(id)
        False -> Error("logical_id_required")
      }
    _ -> Error("logical_id_required")
  })
  let target = optional_text(args, "target_plan")
  let task_id = optional_text(args, "task_id")
  let title = optional_text(args, "title")
  let evidence_path = optional_text(args, "evidence_path")
  let evidence_body = optional_text(args, "evidence_body")
  use _ <- result.try(target_allowed(target, targets))
  use _ <- result.try(title_valid(title))
  use _ <- result.try(case intent {
    PublishEvidence -> {
      use _ <- result.try(evidence_path_allowed(evidence_path))
      use _ <- result.try(a.require(
        evidence_body != "",
        "evidence_body_required",
      ))
      a.require(
        list.contains(writes, evidence_path),
        "evidence_write_scope_refused",
      )
    }
    _ -> a.require(dev.valid_identifier(task_id), "task_id_required")
  })
  use native_name <- result.try(case intent {
    CreatePlan -> plan_name(target)
    CreateTask -> task_name(task_id)
    PublishEvidence -> Ok("planning/evidence")
  })
  let kind = kind_label(intent)
  let payload =
    canonical_payload(
      kind,
      logical_id,
      target,
      task_id,
      title,
      evidence_path,
      evidence_body,
    )
  use _ <- result.try(payload_within_bound(payload))
  use _ <- result.try(payload_within_bound(evidence_body))
  Ok(Prepared(
    intent,
    kind,
    logical_id,
    target,
    task_id,
    native_name,
    title,
    evidence_path,
    evidence_body,
    payload,
  ))
}

/// Pure ledger decision from the already-read records.
pub fn decide_ledger(
  saved: Option(String),
  pending: Option(String),
  key: String,
  binding: dev.Binding,
  payload: String,
  result_path: String,
  intent_path: String,
) -> Result(Decision, String) {
  case saved {
    Some(body) -> {
      use _ <- result.try(validate_saved(body, key, binding, payload))
      use outcome <- result.try(recorded_field(body, "outcome"))
      case outcome {
        "Applied" | "Replayed" -> Ok(ReplaySaved(body))
        other ->
          Error("uncertain:recorded_" <> other <> ";ledger:" <> result_path)
      }
    }
    None ->
      case pending {
        None -> Ok(Dispatch)
        Some(body) -> {
          use recorded <- result.try(recorded_field(body, "payload_sha256"))
          case recorded == files.digest(payload) {
            True ->
              Error("uncertain:pending_not_redispatched;ledger:" <> intent_path)
            False -> Error("payload_conflict")
          }
        }
      }
  }
}

/// Pure Andon decision from the CURRENT pointer and the result it points at.
pub fn decide_andon(
  pointer: Option(String),
  pointed_result: Option(String),
  plan: String,
  task: String,
) -> Result(Nil, String) {
  decide_andon_with_resolution(pointer, pointed_result, None, plan, task)
}

fn resolution_binds_to_result(
  resolution_body: String,
  result_body: String,
  key: String,
  plan: String,
  task: String,
) -> Bool {
  case parsed_record(resolution_body, "planning_resolution_json") {
    Error(_) -> False
    Ok(parsed) -> {
      let allowed_disposition = case record_text(parsed, "disposition") {
        Ok("RESOLVED_APPLIED") | Ok("RESOLVED_NOT_APPLIED") -> True
        _ -> False
      }
      let saved_payload = recorded_field(result_body, "canonical_payload")
      let payload_sha = recorded_field(result_body, "payload_sha256")
      let logical_id = record_text(parsed, "logical_id")
      let result_payload_sha = recorded_field(result_body, "payload_sha256")
      let parsed_payload = case saved_payload {
        Ok(payload) -> parsed_record(payload, "planning_payload_json")
        Error(_) -> Error("payload")
      }
      let logical_matches_key = case logical_id, parsed_payload {
        Ok(id), Ok(payload) ->
          case text_field(payload, "logical_id") {
            Ok(payload_id) ->
              payload_id == id && logical_key(plan, task, id) == key
            Error(_) -> False
          }
        _, _ -> False
      }
      let payload_integrity = case saved_payload, payload_sha {
        Ok(payload), Ok(sha) -> files.digest(payload) == sha
        _, _ -> False
      }
      allowed_disposition
      && logical_matches_key
      && payload_integrity
      && result_payload_sha == record_text(parsed, "payload_sha256")
      && record_text(parsed, "schema")
      == Ok("uos.harness-planning-resolution.v1")
      && record_text(parsed, "kind") == Ok("planning_resolution")
      && record_text(parsed, "key") == Ok(key)
      && record_text(parsed, "parent_plan") == Ok(plan)
      && record_text(parsed, "parent_task") == Ok(task)
      && record_text(parsed, "result_sha256") == Ok(files.digest(result_body))
      && record_text(parsed, "payload_sha256") == payload_sha
      && record_text(parsed, "scope_sha256")
      |> result.map(fn(sha) { a.digest_valid(sha) })
      |> result.unwrap(False)
    }
  }
}

pub fn decide_andon_with_resolution(
  pointer: Option(String),
  pointed_result: Option(String),
  resolution: Option(String),
  plan: String,
  task: String,
) -> Result(Nil, String) {
  case pointer {
    None -> Ok(Nil)
    Some(body) -> {
      use schema <- result.try(recorded_field(body, "schema"))
      use _ <- result.try(a.require(
        schema == "uos.harness-planning-current.v1",
        "planning_andon_held;pointer_corrupt",
      ))
      use key <- result.try(recorded_field(body, "current_key"))
      case pointed_result {
        None -> Error("planning_andon_held;unsettled:" <> key)
        Some(record) -> {
          use saved_schema <- result.try(recorded_field(record, "schema"))
          use saved_key <- result.try(recorded_field(record, "key"))
          use saved_plan <- result.try(recorded_field(record, "parent_plan"))
          use saved_task <- result.try(recorded_field(record, "parent_task"))
          use saved_payload <- result.try(recorded_field(
            record,
            "canonical_payload",
          ))
          use saved_hash <- result.try(recorded_field(record, "payload_sha256"))
          use outcome <- result.try(recorded_field(record, "outcome"))
          let intact =
            saved_schema == "uos.harness-planning-intent.v1"
            && saved_key == key
            && saved_plan == plan
            && saved_task == task
            && files.digest(saved_payload) == saved_hash
          case intact, outcome {
            False, _ -> Error("planning_andon_held;result_corrupt:" <> key)
            True, "Applied" -> Ok(Nil)
            True, "Replayed" -> Ok(Nil)
            True, "Uncertain" ->
              case resolution {
                Some(sidecar) ->
                  case
                    resolution_binds_to_result(sidecar, record, key, plan, task)
                  {
                    True -> Ok(Nil)
                    False ->
                      Error("planning_andon_held;" <> outcome <> ":" <> key)
                  }
                _ -> Error("planning_andon_held;" <> outcome <> ":" <> key)
              }
            True, other -> Error("planning_andon_held;" <> other <> ":" <> key)
          }
        }
      }
    }
  }
}

/// Pointer key, so a test can name the result record the guard will consult.
pub fn pointer_key(body: String) -> Result(String, String) {
  recorded_field(body, "current_key")
}

pub fn pointer_record(plan: String, task: String, key: String) -> String {
  pointer_body(plan, task, key)
}

pub fn validate_saved(
  body: String,
  key: String,
  binding: dev.Binding,
  payload: String,
) -> Result(Nil, String) {
  use schema <- result.try(recorded_field(body, "schema"))
  use _ <- result.try(a.require(
    schema == "uos.harness-planning-intent.v1",
    "ledger_schema_mismatch",
  ))
  use saved_key <- result.try(recorded_field(body, "key"))
  use _ <- result.try(a.require(saved_key == key, "ledger_key_mismatch"))
  use plan <- result.try(recorded_field(body, "parent_plan"))
  use _ <- result.try(a.require(plan == binding.plan, "ledger_parent_mismatch"))
  use task <- result.try(recorded_field(body, "parent_task"))
  use _ <- result.try(a.require(task == binding.task, "ledger_parent_mismatch"))
  use saved_payload <- result.try(recorded_field(body, "canonical_payload"))
  use hash <- result.try(recorded_field(body, "payload_sha256"))
  use _ <- result.try(a.require(
    files.digest(saved_payload) == hash,
    "ledger_payload_digest_mismatch",
  ))
  a.require(saved_payload == payload, "payload_conflict")
}

/// Structural prevalidation that needs no grant, file or clock. It runs before
/// authorized_targets so a malformed payload is refused without any IO, and
/// prepare re-checks the same conditions idempotently on the full path.
pub fn precheck(args: value.Value) -> Result(Nil, String) {
  use fields <- result.try(case args {
    value.Object(fields) -> Ok(fields)
    _ -> Error("object_required")
  })
  use _ <- result.try(
    list.try_each(fields, fn(pair) {
      case list.contains(allowed_keys, pair.0) {
        True -> Ok(Nil)
        False -> Error("unknown_payload_key:" <> pair.0)
      }
    }),
  )
  use _ <- result.try(
    list.try_each(fields, fn(pair) {
      case list.count(fields, fn(other) { other.0 == pair.0 }) {
        1 -> Ok(Nil)
        _ -> Error("duplicate_payload_key:" <> pair.0)
      }
    }),
  )
  use name <- result.try(case value.get(args, "intent") {
    Ok(value.Text(name)) -> Ok(name)
    _ -> Error("unknown_intent")
  })
  use _ <- result.try(parse_intent(name))
  case value.get(args, "logical_id") {
    Ok(value.Text(id)) ->
      case dev.valid_identifier(id) {
        True -> Ok(Nil)
        False -> Error("logical_id_required")
      }
    _ -> Error("logical_id_required")
  }
}
