import cepaf_gleam/harness/development as dev
import cepaf_gleam/harness/files
import cepaf_gleam/harness/system_features as features
import cepaf_gleam/harness/tracking
import cepaf_gleam/harness/value
import gleam/bit_array
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub type Runtime {
  Runtime(
    fence: fn() -> Result(Nil, String),
    run: fn(List(String)) -> Result(#(Int, String), String),
  )
}

type TimeUnit {
  Millisecond
}

@external(erlang, "erlang", "monotonic_time")
fn monotonic_time(unit: TimeUnit) -> Int

fn budgeted(runtime: Runtime) -> Runtime {
  budgeted_with_clock(runtime, fn() { monotonic_time(Millisecond) })
}

pub fn budgeted_with_clock(runtime: Runtime, now: fn() -> Int) -> Runtime {
  let deadline = now() + 60_000
  let check = fn() {
    case now() + 3000 <= deadline {
      True -> Ok(Nil)
      False -> Error("feature_store_operation_deadline")
    }
  }
  Runtime(
    fn() {
      use _ <- result.try(check())
      use _ <- result.try(runtime.fence())
      check()
    },
    fn(args) {
      use _ <- result.try(check())
      let outcome = runtime.run(args)
      case now() <= deadline {
        True -> outcome
        False -> Error("feature_store_deadline_outcome_unknown")
      }
    },
  )
}

@external(erlang, "ecology_capability_ffi", "run_bounded")
fn native_run(
  path: String,
  args: List(String),
  timeout_ms: Int,
) -> Result(#(Int, BitArray), String)

pub fn canonical_runtime(binding: dev.Binding) -> Runtime {
  Runtime(
    fn() {
      use _ <- result.try(
        case
          binding.plan == "uos/system-mcp-features/20260919-1642"
          && binding.task == "t1-tracker"
        {
          True -> Ok(Nil)
          False -> Error("feature_store_task_scope")
        },
      )
      dev.fence(binding) |> result.map(fn(_) { Nil })
    },
    fn(args) {
      use #(code, bytes) <- result.try(native_run(
        "/home/an/NAS-setup/uos/toolchains/nix-profile/bin/env",
        tracking.canonical_argv(args),
        3000,
      ))
      use output <- result.try(
        bit_array.to_string(bytes) |> result.replace_error("feature_store_utf8"),
      )
      Ok(#(code, output))
    },
  )
}

pub fn record_id(kind: String, digest: String) -> Result(String, String) {
  case
    list.contains(["feature", "catalog", "observation", "ledger"], kind)
    && features.valid_digest(digest)
  {
    True -> Ok("uos/system-features/" <> kind <> "/" <> digest)
    False -> Error("feature_record_identity")
  }
}

fn execute(
  runtime: Runtime,
  args: List(String),
) -> Result(#(Int, String), String) {
  use _ <- result.try(
    case
      list.length(args) <= 10
      && list.all(args, fn(arg) {
        string.byte_size(arg) <= 65_536 && !string.contains(arg, "\u{0}")
      })
    {
      True -> Ok(Nil)
      False -> Error("feature_store_argument_bound")
    },
  )
  use _ <- result.try(runtime.fence())
  use #(code, output) <- result.try(
    runtime.run(list.append(args, ["--format", "json"])),
  )
  case string.byte_size(output) <= 262_144 {
    True -> Ok(#(code, output))
    False -> Error("feature_store_response_bound")
  }
}

fn text(row: value.Value, key: String) -> Result(String, String) {
  use found <- result.try(value.get(row, key))
  case found {
    value.Text(text) -> Ok(text)
    _ -> Error("feature_history_field:" <> key)
  }
}

fn completion() -> String {
  "{\"metadata_recorded\":true,\"system_admission\":false}"
}

fn history(
  runtime: Runtime,
  id: String,
) -> Result(Option(#(String, Bool)), String) {
  use #(code, output) <- result.try(
    execute(runtime, ["workflow", "history", id]),
  )
  case tracking.decode_cli(code, output, "Unknown Sa-plan workflow: " <> id) {
    Error("tracking_entity_missing") -> Ok(None)
    Error(reason) -> Error(reason)
    Ok(rows) -> {
      use _ <- result.try(
        case list.length(rows) >= 1 && list.length(rows) <= 2 {
          True -> Ok(Nil)
          False -> Error("feature_history_shape")
        },
      )
      use _ <- result.try(
        list.try_fold(rows, 0, fn(expected, row) {
          use sequence <- result.try(text(row, "sequence"))
          use kind <- result.try(text(row, "kind"))
          use payload <- result.try(text(row, "payload"))
          use occurred <- result.try(text(row, "occurred_at_ns"))
          use timestamp <- result.try(
            int.parse(occurred) |> result.replace_error("feature_history_time"),
          )
          case
            sequence == int.to_string(expected)
            && timestamp > 0
            && case expected {
              0 -> kind == "workflow_started"
              1 -> kind == "workflow_completed" && payload == completion()
              _ -> False
            }
          {
            True -> Ok(expected + 1)
            False -> Error("feature_history_conflict")
          }
        }),
      )
      let assert [started, ..] = rows
      use input <- result.try(text(started, "payload"))
      Ok(Some(#(input, list.length(rows) == 2)))
    }
  }
}

fn ensure_record(
  runtime: Runtime,
  id: String,
  payload: String,
) -> Result(Nil, String) {
  use current <- result.try(history(runtime, id))
  use terminal <- result.try(case current {
    Some(#(existing, done)) ->
      case existing == payload {
        True -> Ok(done)
        False -> Error("feature_record_payload_conflict")
      }
    None -> {
      use #(code, output) <- result.try(
        execute(runtime, [
          "workflow",
          "start",
          id,
          id,
          "feature-metadata",
          payload,
        ]),
      )
      use _ <- result.try(tracking.decode_cli(code, output, ""))
      use saved <- result.try(history(runtime, id))
      case saved {
        Some(#(existing, done)) if existing == payload -> Ok(done)
        _ -> Error("feature_record_readback_conflict")
      }
    }
  })
  case terminal {
    True -> Ok(Nil)
    False -> {
      use #(code, output) <- result.try(
        execute(runtime, ["workflow", "complete", id, completion()]),
      )
      use _ <- result.try(tracking.decode_cli(code, output, ""))
      use saved <- result.try(history(runtime, id))
      case saved {
        Some(#(existing, True)) if existing == payload -> Ok(Nil)
        _ -> Error("feature_record_completion_unverified")
      }
    }
  }
}

fn manifest(catalog: features.Catalog) -> String {
  json.object([
    #("schema", json.string("uos.system-feature-manifest.v1")),
    #("plan_id", json.string("uos/system-mcp-features/20260919-1642")),
    #("task_id", json.string("t1-tracker")),
    #("catalog_sha256", json.string(features.fingerprint(catalog))),
    #("candidate", json.string(features.candidate(catalog))),
    #(
      "features",
      json.array(features.declarations(catalog), fn(feature) {
        json.object([
          #("id", json.string(feature.id)),
          #(
            "sha256",
            json.string(features.encode_feature(feature) |> files.digest),
          ),
        ])
      }),
    ),
    #("system_admission", json.bool(False)),
  ])
  |> json.to_string
}

pub fn publish(
  runtime: Runtime,
  catalog: features.Catalog,
) -> Result(String, String) {
  let runtime = budgeted(runtime)
  use _ <- result.try(
    list.try_map(features.declarations(catalog), fn(feature) {
      let payload = features.encode_feature(feature)
      use id <- result.try(record_id("feature", files.digest(payload)))
      ensure_record(runtime, id, payload)
    }),
  )
  let digest = features.fingerprint(catalog)
  use id <- result.try(record_id("catalog", digest))
  use _ <- result.try(ensure_record(runtime, id, manifest(catalog)))
  use loaded <- result.try(load(runtime, digest))
  case loaded == catalog {
    True -> Ok(digest)
    False -> Error("feature_catalog_readback_conflict")
  }
}

fn load_record(runtime: Runtime, id: String) -> Result(String, String) {
  use current <- result.try(history(runtime, id))
  case current {
    Some(#(payload, True)) -> Ok(payload)
    Some(#(_, False)) -> Error("feature_record_incomplete")
    None -> Error("feature_record_missing")
  }
}

pub fn load(
  runtime: Runtime,
  digest: String,
) -> Result(features.Catalog, String) {
  let runtime = budgeted(runtime)
  use id <- result.try(record_id("catalog", digest))
  use raw <- result.try(load_record(runtime, id))
  use _ <- result.try(case string.byte_size(raw) <= 65_536 {
    True -> Ok(Nil)
    False -> Error("feature_manifest_bound")
  })
  let entry = {
    use id <- decode.field("id", decode.string)
    use digest <- decode.field("sha256", decode.string)
    decode.success(#(id, digest))
  }
  let decoder = {
    use schema <- decode.field("schema", decode.string)
    use plan <- decode.field("plan_id", decode.string)
    use task <- decode.field("task_id", decode.string)
    use claimed <- decode.field("catalog_sha256", decode.string)
    use candidate <- decode.field("candidate", decode.string)
    use declarations <- decode.field("features", decode.list(entry))
    use admission <- decode.field("system_admission", decode.bool)
    decode.success(#(
      schema,
      plan,
      task,
      claimed,
      candidate,
      declarations,
      admission,
    ))
  }
  use decoded <- result.try(
    json.parse(raw, decoder) |> result.replace_error("feature_manifest_json"),
  )
  let #(schema, plan, task, claimed, candidate, entries, admission) = decoded
  use _ <- result.try(
    case
      schema == "uos.system-feature-manifest.v1"
      && plan == "uos/system-mcp-features/20260919-1642"
      && task == "t1-tracker"
      && claimed == digest
      && features.valid_digest(candidate)
      && !admission
      && entries != []
      && list.length(entries) <= 128
      && list.length(list.unique(list.map(entries, fn(entry) { entry.0 })))
      == list.length(entries)
    {
      True -> Ok(Nil)
      False -> Error("feature_manifest_identity_or_bound")
    },
  )
  use declarations <- result.try(
    list.try_map(entries, fn(entry) {
      use record <- result.try(record_id("feature", entry.1))
      use raw <- result.try(load_record(runtime, record))
      use _ <- result.try(case files.digest(raw) == entry.1 {
        True -> Ok(Nil)
        False -> Error("feature_record_digest_conflict")
      })
      use feature <- result.try(features.parse_feature(raw))
      case feature.id == entry.0 {
        True -> Ok(feature)
        False -> Error("feature_manifest_foreign_feature")
      }
    }),
  )
  use catalog <- result.try(features.catalog(candidate, declarations))
  case features.fingerprint(catalog) == digest && manifest(catalog) == raw {
    True -> Ok(catalog)
    False -> Error("feature_manifest_digest_or_canonical_conflict")
  }
}

fn ledger_manifest(
  catalog: features.Catalog,
  ledger: features.Ledger,
) -> String {
  json.object([
    #("schema", json.string("uos.system-feature-observations.v1")),
    #("plan_id", json.string("uos/system-mcp-features/20260919-1642")),
    #("task_id", json.string("t1-tracker")),
    #("catalog_sha256", json.string(features.fingerprint(catalog))),
    #(
      "observations",
      json.array(features.observations(ledger), fn(observation) {
        json.object([
          #("id", json.string(observation.id)),
          #(
            "sha256",
            json.string(features.observation_fingerprint(observation)),
          ),
        ])
      }),
    ),
    #("system_admission", json.bool(False)),
  ])
  |> json.to_string
}

pub fn publish_ledger(
  runtime: Runtime,
  catalog: features.Catalog,
  ledger: features.Ledger,
) -> Result(String, String) {
  let runtime = budgeted(runtime)
  use _ <- result.try(features.validate_ledger(catalog, ledger))
  let manifest = ledger_manifest(catalog, ledger)
  use _ <- result.try(case string.byte_size(manifest) <= 65_536 {
    True -> Ok(Nil)
    False -> Error("ledger_manifest_bound")
  })
  use _ <- result.try(load(runtime, features.fingerprint(catalog)))
  use _ <- result.try(
    list.try_map(features.observations(ledger), fn(observation) {
      use id <- result.try(record_id(
        "observation",
        features.observation_fingerprint(observation),
      ))
      ensure_record(runtime, id, features.encode_observation(observation))
    }),
  )
  let digest = files.digest(manifest)
  use id <- result.try(record_id("ledger", digest))
  use _ <- result.try(ensure_record(runtime, id, manifest))
  use loaded <- result.try(load_ledger(runtime, catalog, digest))
  case loaded == ledger {
    True -> Ok(digest)
    False -> Error("ledger_readback_conflict")
  }
}

pub fn load_ledger(
  runtime: Runtime,
  catalog: features.Catalog,
  digest: String,
) -> Result(features.Ledger, String) {
  let runtime = budgeted(runtime)
  use id <- result.try(record_id("ledger", digest))
  use raw <- result.try(load_record(runtime, id))
  use _ <- result.try(
    case string.byte_size(raw) <= 65_536 && files.digest(raw) == digest {
      True -> Ok(Nil)
      False -> Error("ledger_manifest_bound_or_digest")
    },
  )
  let entry_decoder = {
    use id <- decode.field("id", decode.string)
    use digest <- decode.field("sha256", decode.string)
    decode.success(#(id, digest))
  }
  let decoder = {
    use entries <- decode.field("observations", decode.list(entry_decoder))
    decode.success(entries)
  }
  use entries <- result.try(
    json.parse(raw, decoder) |> result.replace_error("ledger_manifest_json"),
  )
  use _ <- result.try(
    case
      list.length(entries) <= 4096
      && list.length(list.unique(list.map(entries, fn(entry) { entry.0 })))
      == list.length(entries)
    {
      True -> Ok(Nil)
      False -> Error("ledger_manifest_count_or_duplicate")
    },
  )
  use ledger <- result.try(
    list.try_fold(entries, features.empty(), fn(ledger, entry) {
      use id <- result.try(record_id("observation", entry.1))
      use raw <- result.try(load_record(runtime, id))
      use _ <- result.try(case files.digest(raw) == entry.1 {
        True -> Ok(Nil)
        False -> Error("observation_digest_conflict")
      })
      use observation <- result.try(features.parse_observation(raw))
      use _ <- result.try(case observation.id == entry.0 {
        True -> Ok(Nil)
        False -> Error("observation_identity_conflict")
      })
      features.record(ledger, observation)
    }),
  )
  use _ <- result.try(features.validate_ledger(catalog, ledger))
  case ledger_manifest(catalog, ledger) == raw {
    True -> Ok(ledger)
    False -> Error("ledger_manifest_canonical_conflict")
  }
}
