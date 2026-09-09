//// Finite feature registration and progress projection over canonical Sa-plan.
//// No task/job is claimed and no workflow is completed by this module.
//// Catalog stages are declarations; SQLite registration is not acceptance.

import cepaf_gleam/harness/clock
import cepaf_gleam/harness/development as dev
import cepaf_gleam/harness/files
import cepaf_gleam/harness/value
import cepaf_gleam/planning/sa_plan_bridge
import gleam/bit_array
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub const plan_id = "uos/harness-features/20260909"

pub const plan_name = "harness/features/20260909"

pub const plan_title = "Gleam harness feature tracking and local workflow service"

pub const catalog_path = "governance/capability-inventory/20260909-0412-harness-feature-catalog.json"

pub const review_queue = "harness-feature-review"

pub const record_worker = "harness-feature-metadata-only"

pub const canonical_db = "/home/an/NAS-setup/uos/var/sa-plan/uos.sqlite3"

@external(erlang, "ecology_capability_ffi", "run_bounded")
fn native_run(
  path: String,
  args: List(String),
  timeout_ms: Int,
) -> Result(#(Int, BitArray), String)

pub fn canonical_argv(args: List(String)) -> List(String) {
  [
    "UOS_SA_PLAN_DB=" <> canonical_db,
    sa_plan_bridge.resolve_sa_plan_binary(),
    ..args
  ]
}

fn cli_run(
  args: List(String),
  timeout_ms: Int,
) -> Result(#(Int, String), String) {
  use _ <- result.try(
    case
      list.length(args) <= 16
      && list.all(args, fn(arg) {
        string.byte_size(arg) <= 65_536 && !string.contains(arg, "\u{0}")
      })
    {
      True -> Ok(Nil)
      False -> Error("tracking_cli_argument_bound")
    },
  )
  use #(code, bytes) <- result.try(native_run(
    "/home/an/NAS-setup/uos/toolchains/nix-profile/bin/env",
    canonical_argv(args),
    timeout_ms,
  ))
  use output <- result.try(
    bit_array.to_string(bytes)
    |> result.map_error(fn(_) { "tracking_cli_utf8" }),
  )
  Ok(#(code, output))
}

pub type Feature {
  Feature(
    id: String,
    title: String,
    stage: String,
    dependencies: List(String),
    content: value.Value,
  )
}

pub type Catalog {
  Catalog(source_sha256: String, features: List(Feature))
}

pub fn names() -> List(String) {
  [
    "harness_feature_initialize",
    "harness_feature_sync",
    "harness_feature_status",
  ]
}

fn text(object: value.Value, key: String) -> Result(String, String) {
  use found <- result.try(value.get(object, key))
  case found {
    value.Text(s) -> Ok(s)
    _ -> Error("tracking_text:" <> key)
  }
}

fn strings(object: value.Value, key: String) -> Result(List(String), String) {
  use found <- result.try(value.get(object, key))
  case found {
    value.Array(items) ->
      case list.length(items) <= 128 {
        False -> Error("tracking_string_array:" <> key)
        True ->
          list.try_map(items, fn(item) {
            case item {
              value.Text(s) ->
                case string.byte_size(s) <= 2048 {
                  True -> Ok(s)
                  False -> Error("tracking_string_array:" <> key)
                }
              _ -> Error("tracking_string_array:" <> key)
            }
          })
      }
    _ -> Error("tracking_string_array:" <> key)
  }
}

pub fn valid_feature_id(id: String) -> Bool {
  let characters = string.to_graphemes(id)
  let first = list.first(characters) |> result.unwrap("")
  let last = characters |> list.reverse |> list.first |> result.unwrap("")
  string.byte_size(id) > 0
  && string.byte_size(id) <= 80
  && string.contains("abcdefghijklmnopqrstuvwxyz0123456789", first)
  && string.contains("abcdefghijklmnopqrstuvwxyz0123456789", last)
  && list.all(string.to_graphemes(id), fn(c) {
    string.contains("abcdefghijklmnopqrstuvwxyz0123456789_.-", c)
  })
}

fn canonical(object: value.Value) -> value.Value {
  case object {
    value.Object(fields) ->
      value.Object(
        fields
        |> list.map(fn(p) { #(p.0, canonical(p.1)) })
        |> list.sort(fn(a, b) { string.compare(a.0, b.0) }),
      )
    value.Array(items) -> value.Array(list.map(items, canonical))
    _ -> object
  }
}

fn serialize(object: value.Value) -> String {
  object |> canonical |> value.encode |> json.to_string
}

fn parse_feature(object: value.Value) -> Result(Feature, String) {
  use id <- result.try(text(object, "feature_id"))
  use title <- result.try(text(object, "title"))
  use stage <- result.try(text(object, "implementation_stage"))
  use dependencies <- result.try(strings(object, "dependencies"))
  use _ <- result.try(
    list.try_map(["requirements", "decisions", "acceptance"], fn(key) {
      strings(object, key)
    }),
  )
  use _ <- result.try(
    list.try_map(["dashboard", "blocker", "next_action"], fn(key) {
      text(object, key)
    }),
  )
  use evidence <- result.try(value.get(object, "evidence"))
  use _ <- result.try(case evidence {
    value.Array(items) ->
      case list.length(items) <= 64 {
        False -> Error("tracking_evidence_array")
        True ->
          list.try_map(items, fn(item) {
            list.try_map(["kind", "path", "state", "note"], fn(key) {
              text(item, key)
            })
          })
          |> result.map(fn(_) { Nil })
      }
    _ -> Error("tracking_evidence_array")
  })
  case
    valid_feature_id(id)
    && string.byte_size(title) > 0
    && string.byte_size(title) <= 512
    && string.byte_size(stage) > 0
    && string.byte_size(stage) <= 80
    && list.all(dependencies, valid_feature_id)
    && !list.contains(dependencies, id)
    && list.length(list.unique(dependencies)) == list.length(dependencies)
    && string.byte_size(serialize(object)) <= 16_384
  {
    True -> Ok(Feature(id, title, stage, dependencies, canonical(object)))
    False -> Error("tracking_feature_bound_or_dependency")
  }
}

pub fn parse_catalog(body: String) -> Result(Catalog, String) {
  use parsed <- result.try(
    json.parse(body, value.decoder())
    |> result.map_error(fn(_) { "tracking_catalog_json" }),
  )
  use entries <- result.try(case parsed {
    value.Array(items) -> Ok(items)
    value.Object(_) ->
      case value.get(parsed, "features"), text(parsed, "plan_id") {
        Ok(value.Array(items)), Ok(plan) if plan == plan_id -> Ok(items)
        _, _ -> Error("tracking_catalog_features")
      }
    _ -> Error("tracking_catalog_features")
  })
  use _ <- result.try(
    case
      string.byte_size(body) <= files.max_bytes
      && entries != []
      && list.length(entries) <= 128
    {
      True -> Ok(Nil)
      False -> Error("tracking_catalog_bound")
    },
  )
  use features <- result.try(list.try_map(entries, parse_feature))
  let ids = list.map(features, fn(f) { f.id })
  case
    list.length(list.unique(ids)) == list.length(ids)
    && list.all(features, fn(f) {
      list.all(f.dependencies, fn(d) { list.contains(ids, d) })
    })
  {
    True ->
      case acyclic(features, []) {
        True -> Ok(Catalog(files.digest(body), features))
        False -> Error("tracking_catalog_dependency_cycle")
      }
    False -> Error("tracking_catalog_duplicate_or_unknown_dependency")
  }
}

fn acyclic(remaining: List(Feature), ready: List(String)) -> Bool {
  case remaining {
    [] -> True
    _ -> {
      let eligible =
        list.filter(remaining, fn(f) {
          list.all(f.dependencies, fn(d) { list.contains(ready, d) })
        })
      case eligible {
        [] -> False
        _ -> {
          let selected = list.map(eligible, fn(f) { f.id })
          acyclic(
            list.filter(remaining, fn(f) { !list.contains(selected, f.id) }),
            list.append(ready, selected),
          )
        }
      }
    }
  }
}

fn load_catalog() -> Result(Catalog, String) {
  use body <- result.try(files.read(dev.root, catalog_path))
  parse_catalog(body)
}

pub fn task_name(f: Feature) -> String {
  "harness/features/" <> f.id
}

pub fn job_id(f: Feature) -> String {
  plan_id <> "/job/" <> f.id
}

pub fn workflow_id(f: Feature) -> String {
  plan_id <> "/workflow/" <> f.id
}

fn task_title(f: Feature) -> String {
  "Feature tracking: " <> f.id
}

pub fn identity(f: Feature) -> String {
  json.object([
    #("schema", json.string("uos.harness.feature-identity.v1")),
    #("feature_id", json.string(f.id)),
    #("plan_id", json.string(plan_id)),
    #("task_id", json.string(f.id)),
    #("job_id", json.string(job_id(f))),
    #("workflow_id", json.string(workflow_id(f))),
    #("mode", json.string("metadata_only_no_automatic_dispatch")),
  ])
  |> json.to_string
}

pub fn progress(catalog: Catalog, f: Feature) -> String {
  json.object([
    #("schema", json.string("uos.harness.feature-progress.v1")),
    #("feature_id", json.string(f.id)),
    #("catalog_sha256", json.string(catalog.source_sha256)),
    #("declaration", value.encode(f.content)),
    #("verified_acceptance", json.bool(False)),
    #("task_completion_granted", json.bool(False)),
    #("workflow_service", json.string("sa_plan_local_durable_history")),
    #("external_temporal_runtime", json.string("NOT_VERIFIED")),
  ])
  |> json.to_string
}

pub fn task_arguments(f: Feature) -> List(String) {
  [
    "task",
    "create",
    plan_id,
    f.id,
    task_name(f),
    task_title(f),
    "-",
    case f.dependencies {
      [] -> "-"
      _ -> string.join(f.dependencies, ",")
    },
    "0",
    "--format",
    "json",
  ]
}

pub fn job_arguments(f: Feature) -> List(String) {
  [
    "job",
    "enqueue",
    job_id(f),
    task_name(f) <> "/job",
    review_queue,
    record_worker,
    identity(f),
    "1",
    "--format",
    "json",
  ]
}

pub fn workflow_arguments(f: Feature) -> List(String) {
  [
    "workflow",
    "start",
    workflow_id(f),
    task_name(f) <> "/workflow",
    "harness-feature-tracking",
    identity(f),
    "--format",
    "json",
  ]
}

pub fn progress_arguments(catalog: Catalog, f: Feature) -> List(String) {
  let payload = progress(catalog, f)
  let digest = files.digest(payload)
  [
    "workflow",
    "activity",
    workflow_id(f),
    "progress-" <> digest,
    task_name(f) <> "/progress/" <> digest,
    "progress-" <> digest,
    payload,
    "--format",
    "json",
  ]
}

pub fn parse_rows(raw: String) -> Result(List(value.Value), String) {
  let lines =
    raw
    |> string.split("\n")
    |> list.filter(fn(s) { !string.is_empty(string.trim(s)) })
  case string.byte_size(raw) <= 262_144 && list.length(lines) <= 512 {
    False -> Error("tracking_rows_bound")
    True ->
      list.try_fold(lines, [], fn(rows, line) {
        case string.starts_with(line, "sa-plan-pipeline ") {
          True -> {
            use telemetry <- result.try(
              json.parse(string.drop_start(line, 17), value.decoder())
              |> result.map_error(fn(_) { "tracking_cli_telemetry_json" }),
            )
            case text(telemetry, "authority") == Ok("report_only") {
              True -> Ok(rows)
              False -> Error("tracking_cli_telemetry_shape")
            }
          }
          False -> {
            use row <- result.try(
              json.parse(line, value.decoder())
              |> result.map_error(fn(_) { "tracking_cli_json" }),
            )
            case row {
              value.Object(_) -> Ok([row, ..rows])
              _ -> Error("tracking_cli_object_required")
            }
          }
        }
      })
      |> result.map(list.reverse)
  }
}

pub fn decode_cli(
  code: Int,
  output: String,
  missing_message: String,
) -> Result(List(value.Value), String) {
  case code {
    0 -> parse_rows(output)
    1 -> {
      let other =
        output
        |> string.split("\n")
        |> list.filter(fn(line) {
          !string.is_empty(string.trim(line))
          && !string.starts_with(line, "sa-plan-pipeline ")
        })
      case missing_message != "" && other == ["sa-plan: " <> missing_message] {
        True -> Error("tracking_entity_missing")
        False -> Error("tracking_cli_failed_not_absence")
      }
    }
    _ -> Error("tracking_cli_exit:" <> int.to_string(code))
  }
}

fn query(args: List(String)) -> Result(List(value.Value), String) {
  use #(code, output) <- result.try(cli_run(args, 5000))
  decode_cli(code, output, "")
}

fn query_entity(
  args: List(String),
  missing: String,
) -> Result(List(value.Value), String) {
  use #(code, output) <- result.try(cli_run(args, 5000))
  decode_cli(code, output, missing)
}

pub fn exact_fields(
  row: value.Value,
  expected: List(#(String, String)),
) -> Bool {
  list.all(expected, fn(p) { text(row, p.0) == Ok(p.1) })
}

pub fn select_row(
  rows: List(value.Value),
  id: String,
) -> Result(Option(value.Value), String) {
  let found = list.filter(rows, fn(row) { text(row, "id") == Ok(id) })
  case found {
    [] -> Ok(None)
    [row] -> Ok(Some(row))
    _ -> Error("tracking_duplicate_identity")
  }
}

fn read_plan() -> Result(Nil, String) {
  use rows <- result.try(query_entity(
    ["plan", "show", plan_id, "--format", "json"],
    "Unknown Sa-plan plan: " <> plan_id,
  ))
  case rows {
    [row] ->
      case
        exact_fields(row, [
          #("id", plan_id),
          #("name", plan_name),
          #("title", plan_title),
        ])
      {
        True -> Ok(Nil)
        False -> Error("tracking_plan_identity_conflict")
      }
    _ -> Error("tracking_plan_readback")
  }
}

fn task_rows() {
  query(["task", "list", plan_id, "--format", "json"])
}

fn job_rows() {
  query(["job", "list", review_queue, "--format", "json"])
}

fn history(f: Feature) {
  query_entity(
    ["workflow", "history", workflow_id(f), "--format", "json"],
    "Unknown Sa-plan workflow: " <> workflow_id(f),
  )
}

pub fn task_matches(f: Feature, row: value.Value) -> Bool {
  exact_fields(row, [
    #("plan_id", plan_id),
    #("id", f.id),
    #("name", task_name(f)),
    #("title", task_title(f)),
    #("parent_id", "-"),
    #("priority", "0"),
  ])
}

pub fn job_matches(f: Feature, row: value.Value) -> Bool {
  exact_fields(row, [
    #("id", job_id(f)),
    #("name", task_name(f) <> "/job"),
    #("queue", review_queue),
    #("worker", record_worker),
    #("max_attempts", "1"),
  ])
}

pub fn workflow_matches(f: Feature, rows: List(value.Value)) -> Bool {
  let starts =
    list.filter(rows, fn(row) { text(row, "kind") == Ok("workflow_started") })
  case starts {
    [row] -> text(row, "payload") == Ok(identity(f))
    _ -> False
  }
}

pub fn progress_matches(
  catalog: Catalog,
  f: Feature,
  rows: List(value.Value),
) -> Bool {
  let payload = progress(catalog, f)
  let expected = "progress-" <> files.digest(payload) <> ":" <> payload
  list.any(rows, fn(row) {
    exact_fields(row, [#("kind", "activity_completed"), #("payload", expected)])
  })
}

fn verify_task(f: Feature) -> Result(Nil, String) {
  use rows <- result.try(task_rows())
  use found <- result.try(select_row(rows, f.id))
  case found {
    Some(row) ->
      case task_matches(f, row) {
        True -> Ok(Nil)
        False -> Error("tracking_task_readback_conflict")
      }
    None -> Error("tracking_task_readback_conflict")
  }
}

fn verify_job(f: Feature) -> Result(Nil, String) {
  use rows <- result.try(job_rows())
  use found <- result.try(select_row(rows, job_id(f)))
  case found {
    Some(row) ->
      case job_matches(f, row) {
        True -> Ok(Nil)
        False -> Error("tracking_job_readback_conflict")
      }
    None -> Error("tracking_job_readback_conflict")
  }
}

fn verify_workflow(f: Feature) -> Result(Nil, String) {
  use rows <- result.try(history(f))
  case workflow_matches(f, rows) {
    True -> Ok(Nil)
    False -> Error("tracking_workflow_readback_conflict")
  }
}

fn command_hash(args: List(String)) -> String {
  json.array(args, json.string) |> json.to_string |> files.digest
}

fn artifact(args: List(String), suffix: String) -> String {
  dev.effects
  <> "20260909-0412-feature-"
  <> command_hash(args)
  <> "-"
  <> suffix
  <> ".json"
}

fn creation_receipt(args: List(String)) -> Result(value.Value, String) {
  use raw <- result.try(files.read(dev.root, artifact(args, "result")))
  json.parse(raw, value.decoder())
  |> result.map_error(fn(_) { "tracking_creation_receipt_json" })
}

fn receipt_matches(args: List(String)) -> Bool {
  case creation_receipt(args) {
    Ok(row) ->
      exact_fields(row, [
        #("status", "applied_readback"),
        #("request_sha256", command_hash(args)),
      ])
    Error(_) -> False
  }
}

/// Sa-plan task list omits dependency edges. A matching visible row is
/// insufficient: the durable creation receipt must bind the exact edge argv.
pub fn task_registration_matches(
  f: Feature,
  row: value.Value,
  receipt: Result(value.Value, String),
) -> Bool {
  case receipt {
    Ok(saved) ->
      task_matches(f, row)
      && exact_fields(saved, [
        #("status", "applied_readback"),
        #("request_sha256", command_hash(task_arguments(f))),
      ])
    Error(_) -> False
  }
}

/// Execute one literal metadata command after an exclusive durable intent.
/// An existing intent without a matching receipt requires reconciliation;
/// an error after dispatch is never retried automatically.
fn perform(
  binding: dev.Binding,
  catalog_hash: String,
  args: List(String),
  verify: fn() -> Result(Nil, String),
) -> Result(Nil, String) {
  use proof <- result.try(dev.begin_tracking(binding))
  use observed <- result.try(clock.observe())
  use _ <- result.try(case catalog_hash {
    "" -> Ok(Nil)
    _ -> {
      use current <- result.try(files.read(dev.root, catalog_path))
      case files.digest(current) == catalog_hash {
        True -> Ok(Nil)
        False -> Error("tracking_catalog_changed_before_effect")
      }
    }
  })
  let intent =
    json.object([
      #("schema", json.string("uos.harness.tracking-intent.v1")),
      #("request_sha256", json.string(command_hash(args))),
      #("argv", json.array(args, json.string)),
      #("catalog_sha256", json.string(catalog_hash)),
      #("generated_at", json.string(clock.utc(observed))),
      #("authority_plan", json.string(binding.plan)),
      #("authority_task", json.string(binding.task)),
      #("worker", json.string(binding.worker)),
      #("attempt", json.int(binding.attempt)),
      #("effect_mode", json.string("metadata_registration_only")),
    ])
    |> json.to_string
  use _ <- result.try(
    files.create(dev.root, artifact(args, "intent"), intent)
    |> result.map_error(fn(_) {
      "tracking_intent_exists_or_unavailable_reconcile_no_retry"
    }),
  )
  use budget <- result.try(dev.tracking_budget_ms(proof))
  let timeout = case budget < 5000 {
    True -> budget
    False -> 5000
  }
  use #(code, output) <- result.try(
    cli_run(args, timeout)
    |> result.map_error(fn(e) { "tracking_dispatch_unknown_no_retry:" <> e }),
  )
  use _ <- result.try(case code == 0 {
    True -> Ok(Nil)
    False ->
      Error(
        "tracking_dispatch_nonzero_reconcile_no_retry:" <> int.to_string(code),
      )
  })
  use _ <- result.try(verify())
  use _ <- result.try(dev.end_tracking(binding, proof))
  let receipt =
    json.object([
      #("schema", json.string("uos.harness.tracking-receipt.v1")),
      #("status", json.string("applied_readback")),
      #("request_sha256", json.string(command_hash(args))),
      #("output_sha256", json.string(files.digest(output))),
      #("catalog_sha256", json.string(catalog_hash)),
      #("generated_at", json.string(clock.utc(observed))),
      #("mode", json.string("metadata_only_no_automatic_dispatch")),
    ])
    |> json.to_string
  files.create(dev.root, artifact(args, "result"), receipt)
}

fn initialize(binding: dev.Binding) -> Result(json.Json, String) {
  let args = [
    "plan",
    "create",
    plan_id,
    plan_name,
    plan_title,
    "--format",
    "json",
  ]
  use _ <- result.try(case read_plan() {
    Ok(_) -> Ok(Nil)
    Error("tracking_plan_identity_conflict") ->
      Error("tracking_plan_identity_conflict")
    Error("tracking_entity_missing") -> perform(binding, "", args, read_plan)
    Error(reason) -> Error(reason)
  })
  Ok(
    json.object([
      #("status", json.string("tracking_plan_ready")),
      #("plan_id", json.string(plan_id)),
      #("effect_authority", json.bool(False)),
    ]),
  )
}

fn sync_feature(
  binding: dev.Binding,
  catalog: Catalog,
  f: Feature,
) -> Result(json.Json, String) {
  use _ <- result.try(read_plan())
  use tasks <- result.try(task_rows())
  use _ <- result.try(
    list.try_map(f.dependencies, fn(dependency) {
      let expected =
        list.find(catalog.features, fn(entry) { entry.id == dependency })
      case select_row(tasks, dependency), expected {
        Ok(Some(row)), Ok(parent) ->
          case
            task_registration_matches(
              parent,
              row,
              creation_receipt(task_arguments(parent)),
            )
          {
            True -> Ok(Nil)
            False ->
              Error(
                "tracking_dependency_identity_or_edges_conflict:" <> dependency,
              )
          }
        _, _ -> Error("tracking_dependency_registration_missing:" <> dependency)
      }
    }),
  )
  use task <- result.try(select_row(tasks, f.id))
  use _ <- result.try(case task {
    Some(row) ->
      case
        task_registration_matches(f, row, creation_receipt(task_arguments(f)))
      {
        True -> Ok(Nil)
        False -> Error("tracking_task_identity_conflict")
      }
    None ->
      perform(binding, catalog.source_sha256, task_arguments(f), fn() {
        verify_task(f)
      })
  })
  use jobs <- result.try(job_rows())
  use job <- result.try(select_row(jobs, job_id(f)))
  use _ <- result.try(case job {
    Some(row) ->
      case job_matches(f, row) && receipt_matches(job_arguments(f)) {
        True -> Ok(Nil)
        False -> Error("tracking_job_identity_or_unobservable_args_conflict")
      }
    None ->
      perform(binding, catalog.source_sha256, job_arguments(f), fn() {
        verify_job(f)
      })
  })
  use _ <- result.try(case history(f) {
    Ok([]) ->
      perform(binding, catalog.source_sha256, workflow_arguments(f), fn() {
        verify_workflow(f)
      })
    Ok(rows) ->
      case workflow_matches(f, rows) {
        True -> Ok(Nil)
        False -> Error("tracking_workflow_identity_conflict")
      }
    Error("tracking_entity_missing") ->
      perform(binding, catalog.source_sha256, workflow_arguments(f), fn() {
        verify_workflow(f)
      })
    Error(reason) -> Error(reason)
  })
  use events <- result.try(history(f))
  use _ <- result.try(case progress_matches(catalog, f, events) {
    True -> Ok(Nil)
    False ->
      perform(
        binding,
        catalog.source_sha256,
        progress_arguments(catalog, f),
        fn() {
          use rows <- result.try(history(f))
          case progress_matches(catalog, f, rows) {
            True -> Ok(Nil)
            False -> Error("tracking_progress_readback_conflict")
          }
        },
      )
  })
  Ok(
    json.object([
      #("status", json.string("feature_tracking_synchronized")),
      #("feature_id", json.string(f.id)),
      #("plan_id", json.string(plan_id)),
      #("task_id", json.string(f.id)),
      #("job_id", json.string(job_id(f))),
      #("workflow_id", json.string(workflow_id(f))),
      #("declared_implementation_stage", json.string(f.stage)),
      #("verified_acceptance", json.bool(False)),
      #("workflow_service", json.string("sa_plan_local_durable_history")),
      #("external_temporal_runtime", json.string("NOT_VERIFIED")),
      #(
        "job_args_readback",
        json.string("CLI_OMITS_ARGS_BOUND_TO_FENCED_CREATION_RECEIPT"),
      ),
      #("worker_started_by_tracking", json.bool(False)),
      #("task_completed_by_tracking", json.bool(False)),
    ]),
  )
}

fn status(catalog: Catalog) -> Result(json.Json, String) {
  use _ <- result.try(read_plan())
  use tasks <- result.try(task_rows())
  use jobs <- result.try(job_rows())
  let rows =
    list.map(catalog.features, fn(f) {
      let task = select_row(tasks, f.id)
      let job = select_row(jobs, job_id(f))
      let task_ok = case task {
        Ok(Some(row)) ->
          task_registration_matches(f, row, creation_receipt(task_arguments(f)))
        _ -> False
      }
      let job_ok = case job {
        Ok(Some(row)) ->
          job_matches(f, row) && receipt_matches(job_arguments(f))
        _ -> False
      }
      let #(workflow_ok, progress_ok) = case history(f) {
        Ok(events) -> #(
          workflow_matches(f, events),
          progress_matches(catalog, f, events),
        )
        Error(_) -> #(False, False)
      }
      json.object([
        #("feature_id", json.string(f.id)),
        #("plan_id", json.string(plan_id)),
        #("task_id", json.string(f.id)),
        #("job_id", json.string(job_id(f))),
        #("workflow_id", json.string(workflow_id(f))),
        #("title", json.string(f.title)),
        #("declared_implementation_stage", json.string(f.stage)),
        #(
          "task_edges_readback",
          json.string("CLI_OMITS_EDGES_BOUND_TO_CREATION_RECEIPT"),
        ),
        #(
          "task_worker",
          json.string(case task {
            Ok(Some(row)) -> text(row, "worker") |> result.unwrap("UNKNOWN")
            _ -> "MISSING_OR_UNKNOWN"
          }),
        ),
        #(
          "task_attempt",
          json.string(case task {
            Ok(Some(row)) -> text(row, "attempt") |> result.unwrap("UNKNOWN")
            _ -> "MISSING_OR_UNKNOWN"
          }),
        ),
        #(
          "tracking_complete",
          json.bool(task_ok && job_ok && workflow_ok && progress_ok),
        ),
        #("task_registered", json.bool(task_ok)),
        #("job_registered", json.bool(job_ok)),
        #("workflow_registered", json.bool(workflow_ok)),
        #("progress_current", json.bool(progress_ok)),
        #(
          "task_state",
          json.string(case task {
            Ok(Some(row)) -> text(row, "state") |> result.unwrap("UNKNOWN")
            _ -> "MISSING_OR_UNKNOWN"
          }),
        ),
        #(
          "job_state",
          json.string(case job {
            Ok(Some(row)) -> text(row, "state") |> result.unwrap("UNKNOWN")
            _ -> "MISSING_OR_UNKNOWN"
          }),
        ),
        #("verified_acceptance", json.bool(False)),
        #("catalog", value.encode(f.content)),
      ])
    })
  Ok(
    json.object([
      #("status", json.string("feature_tracking_observed")),
      #("plan_id", json.string(plan_id)),
      #("catalog_sha256", json.string(catalog.source_sha256)),
      #("declared_features", json.int(list.length(catalog.features))),
      #("features", json.array(rows, fn(row) { row })),
      #("workflow_service", json.string("sa_plan_local_durable_history")),
      #("external_temporal_runtime", json.string("NOT_VERIFIED")),
      #(
        "worker_dispatch_enforcement",
        json.string("NOT_ESTABLISHED_BY_QUEUE_NAME"),
      ),
      #("snapshot", json.string("bounded_sequential_observations_not_atomic")),
      #("effect_authority", json.bool(False)),
    ]),
  )
}

pub fn call(
  binding: dev.Binding,
  name: String,
  args: value.Value,
) -> Result(json.Json, String) {
  use _ <- result.try(dev.fence(binding))
  case name, args {
    "harness_feature_initialize", value.Object([]) -> initialize(binding)
    "harness_feature_status", value.Object([]) -> {
      use catalog <- result.try(load_catalog())
      status(catalog)
    }
    "harness_feature_sync", value.Object([#("feature_id", value.Text(id))]) -> {
      use catalog <- result.try(load_catalog())
      use feature <- result.try(
        list.find(catalog.features, fn(f) { f.id == id })
        |> result.map_error(fn(_) { "unknown_feature_id" }),
      )
      sync_feature(binding, catalog, feature)
    }
    _, _ -> Error("tracking_tool_or_arguments_not_admitted")
  }
}
