//// Strict, bounded projection loader for the feature receipt ledger.
////
//// The ledger is untrusted input. Symlinks (including parent directories),
//// oversize files, duplicate JSON members, NUL bytes, non-object roots,
//// malformed fields, duplicate task ids, a missing `admitted_ev_ceiling`, and
//// per-receipt `observed_tools` naming unknown registry tools all quarantine
//// the store behind a negative sentinel ceiling so every feature tool fails
//// closed before reporting any evidence. An absent ledger is the only case
//// that yields the honest empty projection. No `T00..T24` tasks are
//// fabricated: absent means zero completed tasks and zero receipts.

import cepaf_gleam/harness/files
import cepaf_gleam/harness/value
import cepaf_gleam/mcp/adapters/features
import cepaf_gleam/mcp/json_guard
import cepaf_gleam/mcp/registry
import cepaf_gleam/mcp/tools
import envoy
import gleam/bit_array
import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/set
import gleam/string
import simplifile

pub const max_ledger_bytes = 1_048_576

type ReadMode {
  Read
  Binary
  Raw
}

@external(erlang, "file", "open")
fn open_read(path: String, modes: List(ReadMode)) -> Result(Dynamic, Dynamic)

@external(erlang, "file", "pread")
fn pread(fd: Dynamic, offset: Int, count: Int) -> Dynamic

@external(erlang, "file", "close")
fn close_read(fd: Dynamic) -> Dynamic

/// The allocation is capped even if the file grows after its size precheck.
pub fn read_bounded(path: String, limit: Int) -> Result(String, Nil) {
  use fd <- result.try(
    open_read(path, [Read, Binary, Raw]) |> result.map_error(fn(_) { Nil }),
  )
  let bytes =
    decode.run(pread(fd, 0, limit + 1), decode.at([1], decode.bit_array))
  let _ = close_read(fd)
  case bytes {
    Ok(raw) ->
      case bit_array.byte_size(raw) <= limit {
        True -> bit_array.to_string(raw)
        False -> Error(Nil)
      }
    _ -> Error(Nil)
  }
}

pub fn valid_sha256(pin: String) -> Bool {
  string.byte_size(pin) == 64
  && list.all(string.to_graphemes(pin), fn(c) {
    string.contains("0123456789abcdef", c)
  })
}

pub fn normalized_absolute_path(path: String) -> Bool {
  string.starts_with(path, "/")
  && string.byte_size(path) <= 4096
  && !string.contains(path, "\u{0}")
  && case path {
    "/" -> True
    _ ->
      string.split(string.drop_start(path, 1), "/")
      |> list.all(fn(segment) {
        segment != "" && segment != "." && segment != ".."
      })
  }
}

const allowed_top_level_keys = [
  "schema",
  "admitted_ev_ceiling",
  "completed_task_ids",
  "receipts",
  "intents",
]

type ParsedReceipt {
  ParsedReceipt(
    receipt: features.ExecutionReceipt,
    observed_tools: List(String),
  )
}

pub fn default_ledger_path(root: String) -> String {
  root <> "/var/harness/mcp_feature_receipt_ledger.json"
}

/// Declared-unavailable tools are not implemented: they have no runtime
/// binding, so their `implementation_state` is `declared_only` and they are
/// never counted as `implemented` in the capability inventory.
pub fn default_capabilities() -> List(features.CapabilityRecord) {
  registry.all_specs()
  |> list.map(fn(spec) {
    let implementation_state = case
      list.contains(tools.unavailable_tools, spec.name)
    {
      True -> "declared_only"
      False -> "implemented"
    }
    features.CapabilityRecord(
      id: spec.name,
      route: spec.route,
      declaration_state: "declared",
      implementation_state: implementation_state,
      execution_state: "unrun",
      formal_state: "unrun",
      admission_state: "not_admitted",
    )
  })
}

pub fn empty_verified_store(
  active_candidate: String,
) -> features.FeatureEvidenceStore {
  features.FeatureEvidenceStore(
    active_candidate: active_candidate,
    admitted_ev_ceiling: features.ev_ceiling,
    capabilities: default_capabilities(),
    completed_task_ids: [],
    receipts: dict.new(),
    intents: dict.new(),
  )
}

fn quarantine_store(
  active_candidate: String,
  sentinel: Int,
) -> features.FeatureEvidenceStore {
  features.FeatureEvidenceStore(
    active_candidate: active_candidate,
    admitted_ev_ceiling: sentinel,
    capabilities: default_capabilities(),
    completed_task_ids: [],
    receipts: dict.new(),
    intents: dict.new(),
  )
}

fn env_override(name: String) -> Option(String) {
  case envoy.get(name) {
    Ok(value) if value != "" -> Some(value)
    _ -> None
  }
}

pub fn load_verified_projection(
  root: String,
  active_candidate: String,
) -> features.FeatureEvidenceStore {
  let ledger_path = case env_override("UOS_FEATURE_RECEIPT_LEDGER_PATH") {
    Some(path) -> path
    None -> default_ledger_path(root)
  }
  case normalized_absolute_path(ledger_path) {
    False ->
      quarantine_store(active_candidate, features.corrupt_ledger_sentinel)
    True -> load_verified_projection_from(root, active_candidate, ledger_path)
  }
}

pub fn load_verified_projection_from(
  root: String,
  active_candidate: String,
  ledger_path: String,
) -> features.FeatureEvidenceStore {
  case has_symlink_ancestor(root, ledger_path) {
    True -> quarantine_store(active_candidate, features.symlink_ledger_sentinel)
    False ->
      case simplifile.is_file(ledger_path) {
        Ok(False) ->
          case env_override("UOS_FEATURE_RECEIPT_LEDGER_SHA256") {
            None -> empty_verified_store(active_candidate)
            Some(_) ->
              quarantine_store(
                active_candidate,
                features.corrupt_ledger_sentinel,
              )
          }
        Error(_) ->
          quarantine_store(active_candidate, features.corrupt_ledger_sentinel)
        Ok(True) ->
          case simplifile.file_info(ledger_path) {
            Error(_) ->
              quarantine_store(
                active_candidate,
                features.corrupt_ledger_sentinel,
              )
            Ok(info) ->
              case info.size > 0 && info.size <= max_ledger_bytes {
                False ->
                  quarantine_store(
                    active_candidate,
                    features.corrupt_ledger_sentinel,
                  )
                True ->
                  case read_bounded(ledger_path, max_ledger_bytes) {
                    Error(_) ->
                      quarantine_store(
                        active_candidate,
                        features.corrupt_ledger_sentinel,
                      )
                    Ok(raw) ->
                      case string.byte_size(raw) > max_ledger_bytes {
                        True ->
                          quarantine_store(
                            active_candidate,
                            features.corrupt_ledger_sentinel,
                          )
                        False ->
                          case ledger_pin_matches(raw) {
                            False ->
                              quarantine_store(
                                active_candidate,
                                features.corrupt_ledger_sentinel,
                              )
                            True ->
                              case json_guard.native_inspect(raw, 24) {
                                Error(_) ->
                                  quarantine_store(
                                    active_candidate,
                                    features.corrupt_ledger_sentinel,
                                  )
                                Ok(value.Object(fields)) ->
                                  case parse_ledger(fields, active_candidate) {
                                    Ok(store) ->
                                      case
                                        env_override(
                                          "UOS_FEATURE_RECEIPT_LEDGER_SHA256",
                                        )
                                      {
                                        Some(_) -> features.pinned_store(store)
                                        None -> store
                                      }
                                    Error(_) ->
                                      quarantine_store(
                                        active_candidate,
                                        features.corrupt_ledger_sentinel,
                                      )
                                  }
                                Ok(_) ->
                                  quarantine_store(
                                    active_candidate,
                                    features.corrupt_ledger_sentinel,
                                  )
                              }
                          }
                      }
                  }
              }
          }
      }
  }
}

fn ledger_pin_matches(raw: String) -> Bool {
  case env_override("UOS_FEATURE_RECEIPT_LEDGER_SHA256") {
    None -> True
    Some(pin) -> valid_sha256(pin) && pin == files.digest(raw)
  }
}

// ---------------------------------------------------------------------------
// Symlink ancestor guard
// ---------------------------------------------------------------------------

fn strip_trailing_slash(path: String) -> String {
  case string.ends_with(path, "/") && path != "/" {
    True -> strip_trailing_slash(string.drop_end(path, 1))
    False -> path
  }
}

fn parent_path(path: String) -> String {
  let parts =
    string.split(strip_trailing_slash(path), "/")
    |> list.filter(fn(part) { part != "" })
  case list.reverse(parts) {
    [_, ..rest] -> "/" <> string.join(list.reverse(rest), "/")
    [] -> "/"
  }
}

fn has_symlink_ancestor(_root: String, path: String) -> Bool {
  has_unsafe_ancestor(path)
}

pub fn has_unsafe_ancestor(path: String) -> Bool {
  !normalized_absolute_path(path) || unsafe_ancestor_loop(path)
}

fn unsafe_ancestor_loop(path: String) -> Bool {
  case simplifile.is_symlink(path) {
    Ok(True) -> True
    Error(_) -> True
    Ok(False) ->
      case path == "/" {
        True -> False
        False -> unsafe_ancestor_loop(parent_path(path))
      }
  }
}

// ---------------------------------------------------------------------------
// Strict projection parsing
// ---------------------------------------------------------------------------

fn get_field(
  fields: List(#(String, value.Value)),
  key: String,
) -> Result(value.Value, Nil) {
  case list.find(fields, fn(pair) { pair.0 == key }) {
    Ok(pair) -> Ok(pair.1)
    Error(_) -> Error(Nil)
  }
}

fn parse_ledger(
  fields: List(#(String, value.Value)),
  active_candidate: String,
) -> Result(features.FeatureEvidenceStore, Nil) {
  case
    list.any(fields, fn(field) {
      !list.contains(allowed_top_level_keys, field.0)
    })
  {
    True -> Error(Nil)
    False -> {
      use _ <- result.try(validate_schema(fields))
      use ceiling <- result.try(parse_ceiling(fields))
      use completed <- result.try(parse_completed_task_ids(fields))
      use parsed <- result.try(parse_receipts(fields))
      use intents <- result.try(parse_intents(fields))
      let keyed =
        dict.from_list(
          list.map(parsed, fn(parsed_receipt) {
            #(parsed_receipt.receipt.feature_or_task_id, parsed_receipt.receipt)
          }),
        )
      case dict.size(keyed) == list.length(parsed) {
        False -> Error(Nil)
        True -> {
          let store =
            features.FeatureEvidenceStore(
              active_candidate: active_candidate,
              admitted_ev_ceiling: ceiling,
              capabilities: default_capabilities(),
              completed_task_ids: completed,
              receipts: keyed,
              intents: intents,
            )
          Ok(apply_observed_tools(store, parsed))
        }
      }
    }
  }
}

fn validate_schema(fields: List(#(String, value.Value))) -> Result(Nil, Nil) {
  case get_field(fields, "schema") {
    Error(_) -> Ok(Nil)
    Ok(value.Text(_)) -> Ok(Nil)
    Ok(_) -> Error(Nil)
  }
}

/// A ledger JSON file must state its admitted evidence ceiling explicitly.
/// The absent-file case never reaches this parser.
fn parse_ceiling(fields: List(#(String, value.Value))) -> Result(Int, Nil) {
  case get_field(fields, "admitted_ev_ceiling") {
    Error(_) -> Error(Nil)
    Ok(value.Integer(93)) -> Ok(93)
    Ok(_) -> Error(Nil)
  }
}

/// Duplicate completed task ids inflate progress and are quarantined.
fn parse_completed_task_ids(
  fields: List(#(String, value.Value)),
) -> Result(List(String), Nil) {
  case get_field(fields, "completed_task_ids") {
    Error(_) -> Ok([])
    Ok(value.Array(items)) -> {
      use _ <- result.try(within_cap(items, 4096))
      use ids <- result.try(parse_nonempty_texts(items))
      case unique_ids(ids, set.new()) {
        True -> Ok(ids)
        False -> Error(Nil)
      }
    }
    Ok(_) -> Error(Nil)
  }
}

fn within_cap(items: List(a), cap: Int) -> Result(Nil, Nil) {
  case list.length(items) <= cap {
    True -> Ok(Nil)
    False -> Error(Nil)
  }
}

fn unique_ids(ids: List(String), seen: set.Set(String)) -> Bool {
  case ids {
    [] -> True
    [id, ..rest] ->
      !set.contains(seen, id) && unique_ids(rest, set.insert(seen, id))
  }
}

fn parse_receipts(
  fields: List(#(String, value.Value)),
) -> Result(List(ParsedReceipt), Nil) {
  case get_field(fields, "receipts") {
    Error(_) -> Ok([])
    Ok(value.Array(items)) -> {
      use _ <- result.try(within_cap(items, 1024))
      let valid_names = registry.all_specs() |> list.map(fn(spec) { spec.name })
      list.try_map(items, fn(item) { parse_receipt(item, valid_names) })
    }
    Ok(_) -> Error(Nil)
  }
}

fn parse_receipt(
  item: value.Value,
  valid_names: List(String),
) -> Result(ParsedReceipt, Nil) {
  case item {
    value.Object(fields) -> {
      use task_id <- result.try(required_text(fields, "task_id"))
      use candidate_commit <- result.try(required_text(
        fields,
        "candidate_commit",
      ))
      use output_sha256 <- result.try(required_text(fields, "output_sha256"))
      use exit_code <- result.try(required_int(fields, "exit_code"))
      use raw_review_verdict <- result.try(optional_text(
        fields,
        "raw_review_verdict",
      ))
      use wrapper_verdict <- result.try(optional_text(fields, "wrapper_verdict"))
      use observed_tools <- result.try(parse_receipt_observed_tools(
        fields,
        valid_names,
      ))
      Ok(ParsedReceipt(
        receipt: features.ExecutionReceipt(
          feature_or_task_id: task_id,
          candidate_commit: candidate_commit,
          exit_code: exit_code,
          raw_review_verdict: raw_review_verdict,
          wrapper_verdict: wrapper_verdict,
          output_sha256: output_sha256,
        ),
        observed_tools: observed_tools,
      ))
    }
    _ -> Error(Nil)
  }
}

/// Per-receipt `observed_tools` binds a named tool to the receipt that observed
/// it. Every name must resolve to a known registry spec or the whole ledger is
/// quarantined.
fn parse_receipt_observed_tools(
  fields: List(#(String, value.Value)),
  valid_names: List(String),
) -> Result(List(String), Nil) {
  case get_field(fields, "observed_tools") {
    Error(_) -> Ok([])
    Ok(value.Array(items)) -> {
      use _ <- result.try(within_cap(items, 128))
      use names <- result.try(parse_nonempty_texts(items))
      case
        list.any(names, fn(name) {
          !list.contains(valid_names, name)
          || list.contains(tools.unavailable_tools, name)
        })
      {
        True -> Error(Nil)
        False -> Ok(names)
      }
    }
    Ok(_) -> Error(Nil)
  }
}

fn parse_intents(
  fields: List(#(String, value.Value)),
) -> Result(Dict(String, String), Nil) {
  case get_field(fields, "intents") {
    Error(_) -> Ok(dict.new())
    Ok(value.Object(pairs)) -> {
      use _ <- result.try(within_cap(pairs, 4096))
      pairs
      |> list.try_map(fn(pair) {
        case pair.1 {
          value.Text(text) -> Ok(#(pair.0, text))
          _ -> Error(Nil)
        }
      })
      |> result.map(dict.from_list)
    }
    Ok(_) -> Error(Nil)
  }
}

fn parse_nonempty_texts(items: List(value.Value)) -> Result(List(String), Nil) {
  list.try_map(items, fn(item) {
    case item {
      value.Text(text) if text != "" -> Ok(text)
      _ -> Error(Nil)
    }
  })
}

fn required_text(
  fields: List(#(String, value.Value)),
  key: String,
) -> Result(String, Nil) {
  case get_field(fields, key) {
    Ok(value.Text(text)) if text != "" -> Ok(text)
    _ -> Error(Nil)
  }
}

fn required_int(
  fields: List(#(String, value.Value)),
  key: String,
) -> Result(Int, Nil) {
  case get_field(fields, key) {
    Ok(value.Integer(number)) -> Ok(number)
    _ -> Error(Nil)
  }
}

fn optional_text(
  fields: List(#(String, value.Value)),
  key: String,
) -> Result(Option(String), Nil) {
  case get_field(fields, key) {
    Error(_) -> Ok(None)
    Ok(value.Null) -> Ok(None)
    Ok(value.Text(text)) -> Ok(Some(text))
    Ok(_) -> Error(Nil)
  }
}

/// A capability is only marked `observed` when a receipt that names it is a
/// clean, non-conflicting, active-candidate receipt. The tool-to-receipt
/// binding is per receipt, never a ledger-wide trust list, so one clean
/// receipt cannot elevate unrelated tools.
fn apply_observed_tools(
  store: features.FeatureEvidenceStore,
  parsed: List(ParsedReceipt),
) -> features.FeatureEvidenceStore {
  let observed_tools =
    parsed
    |> list.filter(fn(parsed_receipt) {
      features.valid_active_receipt(store, parsed_receipt.receipt)
      && !features.wrapper_raw_conflict(parsed_receipt.receipt)
    })
    |> list.flat_map(fn(parsed_receipt) { parsed_receipt.observed_tools })
  features.FeatureEvidenceStore(
    ..store,
    capabilities: list.map(store.capabilities, fn(capability) {
      case
        capability.implementation_state == "implemented"
        && list.contains(observed_tools, capability.id)
      {
        True ->
          features.CapabilityRecord(
            capability.id,
            capability.route,
            capability.declaration_state,
            capability.implementation_state,
            "observed",
            capability.formal_state,
            capability.admission_state,
          )
        False -> capability
      }
    }),
  )
}
