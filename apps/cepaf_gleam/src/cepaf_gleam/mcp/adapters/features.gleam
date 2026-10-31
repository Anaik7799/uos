//// Feature Evidence Family Adapter (5 tools): mcp_capability_inventory,
//// harness_system_feature_catalog, harness_system_feature_observations,
//// harness_system_feature_intent, harness_execution_progress.
////
//// Enforces strict epistemic separation between declaration, implementation,
//// observed execution, formal verification, and admission. Refuses any store
//// that claims admitted evidence above the immutable EV93 ceiling, fails closed
//// on wrapper/raw review verdict conflicts, stale candidate receipts, and
//// completed tasks that lack a candidate-bound execution receipt.

import cepaf_gleam/harness/files
import cepaf_gleam/mcp/registry
import cepaf_gleam/mcp/types.{
  type Outcome, type ToolError, type ToolSpec, Complete, EvidenceRecord,
  NonRetryable, Refused, ToolError,
}
import gleam/dict.{type Dict}
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub fn execute(
  store: FeatureEvidenceStore,
  tool_name: String,
  args: Dict(String, String),
) -> Outcome {
  // The quarantine/ceiling guard runs ahead of every argument check so a
  // corrupt or symlinked ledger always yields the quarantine refusal code
  // across all five tools, including missing-argument requests.
  case check_ceiling(store) {
    Error(error) -> Refused(error)
    Ok(_) ->
      case tool_name {
        "mcp_capability_inventory" -> mcp_capability_inventory(store)
        "harness_system_feature_catalog" -> catalog_page(store, args)
        "harness_system_feature_observations" -> {
          let task_id = result.unwrap(dict.get(args, "task_id"), "")
          let feature_id = result.unwrap(dict.get(args, "feature_id"), "")
          let target = case task_id {
            "" -> feature_id
            _ -> task_id
          }
          case target {
            "" ->
              case dict.has_key(args, "offset") {
                True -> observations_page(store, args)
                False ->
                  Refused(ToolError(
                    "MISSING_ARGUMENT",
                    "Missing required task_id or feature_id",
                    NonRetryable,
                  ))
              }
            _ -> harness_system_feature_observations(store, target)
          }
        }
        "harness_system_feature_intent" -> {
          let intent_id =
            result.unwrap(dict.get(args, "intent_id"), "") |> string.trim
          let intent_id = case intent_id {
            "" -> result.unwrap(dict.get(args, "intent"), "") |> string.trim
            id -> id
          }
          case intent_id {
            "" ->
              Refused(ToolError(
                "MISSING_ARGUMENT",
                "Missing required intent_id",
                NonRetryable,
              ))
            _ -> harness_system_feature_intent(store, intent_id)
          }
        }
        "harness_execution_progress" -> harness_execution_progress(store)
        _ ->
          Refused(ToolError(
            "UNSUPPORTED_FEATURE_TOOL",
            "Unsupported tool in features adapter: " <> tool_name,
            NonRetryable,
          ))
      }
  }
}

pub const ev_ceiling = 93

/// Sentinel ceilings used by the strict receipt-ledger loader. A negative
/// ceiling can never be mistaken for legitimate admitted evidence and is
/// refused ahead of every other check so quarantined stores fail closed.
pub const corrupt_ledger_sentinel = -1

pub const symlink_ledger_sentinel = -2

pub const feature_tools = [
  "mcp_capability_inventory",
  "harness_system_feature_catalog",
  "harness_system_feature_observations",
  "harness_system_feature_intent",
  "harness_execution_progress",
]

pub type ExecutionReceipt {
  ExecutionReceipt(
    feature_or_task_id: String,
    candidate_commit: String,
    exit_code: Int,
    raw_review_verdict: Option(String),
    wrapper_verdict: Option(String),
    output_sha256: String,
  )
}

pub type CapabilityRecord {
  CapabilityRecord(
    id: String,
    route: String,
    declaration_state: String,
    implementation_state: String,
    execution_state: String,
    formal_state: String,
    admission_state: String,
  )
  /// Same capability evidence with a verified disk SHA-256 source pin.
  Sha256PinnedCapabilityRecord(
    id: String,
    route: String,
    declaration_state: String,
    implementation_state: String,
    execution_state: String,
    formal_state: String,
    admission_state: String,
  )
}

pub type FeatureEvidenceStore {
  FeatureEvidenceStore(
    active_candidate: String,
    admitted_ev_ceiling: Int,
    capabilities: List(CapabilityRecord),
    completed_task_ids: List(String),
    receipts: Dict(String, ExecutionReceipt),
    intents: Dict(String, String),
  )
}

pub fn pinned_store(store: FeatureEvidenceStore) -> FeatureEvidenceStore {
  FeatureEvidenceStore(
    ..store,
    capabilities: list.map(store.capabilities, fn(c) {
      Sha256PinnedCapabilityRecord(
        c.id,
        c.route,
        c.declaration_state,
        c.implementation_state,
        c.execution_state,
        c.formal_state,
        c.admission_state,
      )
    }),
  )
}

pub fn merge_actor_intents(
  store: FeatureEvidenceStore,
  memory: Dict(String, String),
) -> FeatureEvidenceStore {
  FeatureEvidenceStore(..store, intents: dict.merge(store.intents, memory))
}

fn ledger_authenticity(store: FeatureEvidenceStore) -> String {
  case store.capabilities {
    [Sha256PinnedCapabilityRecord(..), ..] -> "sha256_pinned"
    _ -> "workspace_self_attested_unpinned"
  }
}

pub type CapabilityInventory {
  CapabilityInventory(
    total_routes: Int,
    public_routes: Int,
    development_routes: Int,
    successor_routes: Int,
    declared_count: Int,
    implemented_count: Int,
    observed_count: Int,
    formal_count: Int,
    admitted_count: Int,
  )
}

pub type ProgressReport {
  ProgressReport(
    active_candidate: String,
    completed_total: Int,
    verified_complete_count: Int,
    unverified_missing_receipt_count: Int,
    stale_receipt_count: Int,
  )
}

// ---------------------------------------------------------------------------
// Fail-closed guards
// ---------------------------------------------------------------------------

fn ceiling_error() -> ToolError {
  ToolError(
    "PROVENANCE_CEILING_VIOLATION",
    "Store admits evidence above the immutable EV93 ceiling",
    NonRetryable,
  )
}

fn conflict_error() -> ToolError {
  ToolError(
    "WRAPPER_RAW_VERDICT_CONFLICT",
    "Summary wrapper cannot override raw review verdict",
    NonRetryable,
  )
}

fn stale_error() -> ToolError {
  ToolError(
    "STALE_CANDIDATE_RECEIPT",
    "Receipt candidate does not match active candidate",
    NonRetryable,
  )
}

fn missing_receipt_error() -> ToolError {
  ToolError(
    "MISSING_EXECUTION_RECEIPT",
    "Completed task lacks candidate-bound execution receipt",
    NonRetryable,
  )
}

fn failed_receipt_error() -> ToolError {
  ToolError(
    "FAILED_EXECUTION_RECEIPT",
    "Completed task receipt recorded non-zero exit code",
    NonRetryable,
  )
}

/// The admitted evidence ceiling is immutable at 93. Any store claiming a
/// higher ceiling is refused before any evidence is reported. A negative
/// sentinel ceiling means the receipt ledger was symlinked or failed the
/// strict loader guard, in which case every feature tool must fail closed.
pub fn check_ceiling(store: FeatureEvidenceStore) -> Result(Nil, ToolError) {
  let ceiling = store.admitted_ev_ceiling
  case ceiling == symlink_ledger_sentinel {
    True ->
      Error(ToolError(
        "FEATURE_LEDGER_SYMLINK_FORBIDDEN",
        "Feature receipt ledger symlink is forbidden",
        NonRetryable,
      ))
    False ->
      case ceiling < 0 {
        True ->
          Error(ToolError(
            "FEATURE_LEDGER_CORRUPT",
            "Feature receipt ledger corrupt or failed strict OTP29 JSON guard",
            NonRetryable,
          ))
        False ->
          case ceiling > ev_ceiling {
            True -> Error(ceiling_error())
            False -> Ok(Nil)
          }
      }
  }
}

/// A summary wrapper may never upgrade a raw review verdict. Any receipt whose
/// wrapper claims approval while the raw review holds, rejects, or is absent is
/// a fail-closed conflict.
pub fn wrapper_raw_conflict(receipt: ExecutionReceipt) -> Bool {
  let raw_approved = case receipt.raw_review_verdict {
    None -> False
    Some(verdict) -> {
      let normalized = string.uppercase(string.trim(verdict))
      normalized == "APPROVED" || normalized == "APPROVED_FOR_MAIN"
    }
  }
  let wrapper_non_claiming = case receipt.wrapper_verdict {
    None -> True
    Some(verdict) -> {
      let normalized = string.uppercase(string.trim(verdict))
      list.contains(
        [
          "",
          "NONE",
          "PENDING",
          "UNRUN",
          "REJECTED",
          "HOLD",
          "REMEDIATE",
          "FAIL",
          "FAILED",
          "NOT_ADMITTED",
          "UNVERIFIED",
        ],
        normalized,
      )
    }
  }
  !raw_approved && !wrapper_non_claiming
}

fn store_has_conflict(store: FeatureEvidenceStore) -> Bool {
  store.receipts
  |> dict.values
  |> list.any(wrapper_raw_conflict)
}

/// A receipt only counts for the active candidate when it is bound to that
/// candidate and observed a clean exit.
pub fn is_active_candidate_receipt(
  store: FeatureEvidenceStore,
  receipt: ExecutionReceipt,
) -> Bool {
  receipt.candidate_commit == store.active_candidate
}

pub fn valid_active_receipt(
  store: FeatureEvidenceStore,
  receipt: ExecutionReceipt,
) -> Bool {
  is_active_candidate_receipt(store, receipt) && receipt.exit_code == 0
}

// ---------------------------------------------------------------------------
// Aggregate progress
// ---------------------------------------------------------------------------

pub fn compute_progress(store: FeatureEvidenceStore) -> ProgressReport {
  let completed_total = list.length(store.completed_task_ids)
  let verified_complete_count =
    list.count(store.completed_task_ids, fn(task_id) {
      case dict.get(store.receipts, task_id) {
        Ok(receipt) -> valid_active_receipt(store, receipt)
        Error(_) -> False
      }
    })
  let stale_receipt_count =
    store.receipts
    |> dict.values
    |> list.count(fn(receipt) { !is_active_candidate_receipt(store, receipt) })
  ProgressReport(
    active_candidate: store.active_candidate,
    completed_total: completed_total,
    verified_complete_count: verified_complete_count,
    unverified_missing_receipt_count: completed_total - verified_complete_count,
    stale_receipt_count: stale_receipt_count,
  )
}

fn progress_payload(
  store: FeatureEvidenceStore,
  report: ProgressReport,
) -> String {
  json.object([
    #("active_candidate", json.string(report.active_candidate)),
    #("admitted_ev_ceiling", json.int(store.admitted_ev_ceiling)),
    #("completed_total", json.int(report.completed_total)),
    #("verified_complete_count", json.int(report.verified_complete_count)),
    #(
      "unverified_missing_receipt_count",
      json.int(report.unverified_missing_receipt_count),
    ),
    #("stale_receipt_count", json.int(report.stale_receipt_count)),
    #("stale_never_counts_as_complete", json.bool(True)),
  ])
  |> json.to_string
}

pub fn harness_execution_progress(store: FeatureEvidenceStore) -> Outcome {
  case check_ceiling(store) {
    Error(error) -> Refused(error)
    Ok(_) ->
      case store_has_conflict(store) {
        True -> Refused(conflict_error())
        False -> {
          let report = compute_progress(store)
          complete(
            "harness_execution_progress",
            progress_payload(store, report),
            store,
          )
        }
      }
  }
}

// ---------------------------------------------------------------------------
// Capability inventory
// ---------------------------------------------------------------------------

fn route_count(specs: List(ToolSpec), route: String) -> Int {
  list.count(specs, fn(spec) { spec.route == route })
}

pub fn capability_inventory(
  store: FeatureEvidenceStore,
) -> Result(CapabilityInventory, ToolError) {
  case check_ceiling(store) {
    Error(error) -> Error(error)
    Ok(_) ->
      case store_has_conflict(store) {
        True -> Error(conflict_error())
        False -> {
          let specs = registry.all_specs()
          Ok(CapabilityInventory(
            total_routes: list.length(specs),
            public_routes: route_count(specs, "public"),
            development_routes: route_count(specs, "development"),
            successor_routes: route_count(specs, "successor"),
            declared_count: list.count(store.capabilities, fn(capability) {
              capability.declaration_state == "declared"
            }),
            implemented_count: list.count(store.capabilities, fn(capability) {
              capability.implementation_state == "implemented"
            }),
            observed_count: list.count(store.capabilities, fn(capability) {
              capability.execution_state == "observed"
            }),
            formal_count: list.count(store.capabilities, fn(capability) {
              capability.formal_state == "verified"
            }),
            admitted_count: list.count(store.capabilities, fn(capability) {
              capability.admission_state == "admitted"
            }),
          ))
        }
      }
  }
}

pub fn mcp_capability_inventory(store: FeatureEvidenceStore) -> Outcome {
  case capability_inventory(store) {
    Error(error) -> Refused(error)
    Ok(inventory) -> {
      let payload =
        json.object([
          #("total_mcp_routes", json.int(inventory.total_routes)),
          #("public_routes", json.int(inventory.public_routes)),
          #(
            "development_private_routes",
            json.int(inventory.development_routes),
          ),
          #("successor_private_routes", json.int(inventory.successor_routes)),
          #("admitted_ev_ceiling", json.int(store.admitted_ev_ceiling)),
          #("declared_count", json.int(inventory.declared_count)),
          #("implemented_count", json.int(inventory.implemented_count)),
          #("observed_count", json.int(inventory.observed_count)),
          #("formal_count", json.int(inventory.formal_count)),
          #("admitted_count", json.int(inventory.admitted_count)),
          #("declared_is_not_admitted", json.bool(True)),
        ])
        |> json.to_string
      complete("mcp_capability_inventory", payload, store)
    }
  }
}

// ---------------------------------------------------------------------------
// Feature catalog
// ---------------------------------------------------------------------------

fn catalog_payload(store: FeatureEvidenceStore) -> String {
  json.object([
    #("active_candidate", json.string(store.active_candidate)),
    #("admitted_ev_ceiling", json.int(store.admitted_ev_ceiling)),
    #(
      "capabilities",
      json.array(store.capabilities, fn(capability) {
        json.object([
          #("id", json.string(capability.id)),
          #("route", json.string(capability.route)),
          #("declaration_state", json.string(capability.declaration_state)),
          #(
            "implementation_state",
            json.string(capability.implementation_state),
          ),
          #("execution_state", json.string(capability.execution_state)),
          #("formal_state", json.string(capability.formal_state)),
          #("admission_state", json.string(capability.admission_state)),
        ])
      }),
    ),
  ])
  |> json.to_string
}

/// Digest of the complete canonical catalog, independent of pagination.
pub fn catalog_digest(store: FeatureEvidenceStore) -> String {
  files.digest(catalog_payload(store))
}

fn validate_catalog_digest(
  store: FeatureEvidenceStore,
  args: Dict(String, String),
) -> Result(Nil, ToolError) {
  let expected =
    result.unwrap(dict.get(args, "catalog_sha256"), "") |> string.trim
  case
    expected == "" || expected == "any" || expected == catalog_digest(store)
  {
    True -> Ok(Nil)
    False ->
      Error(ToolError(
        "CATALOG_DIGEST_MISMATCH",
        "Requested catalog_sha256 differs from the canonical catalog",
        NonRetryable,
      ))
  }
}

pub fn ledger_digest(store: FeatureEvidenceStore) -> String {
  store.receipts
  |> dict.to_list
  |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
  |> json.array(fn(pair) {
    json.object([
      #("id", json.string(pair.0)),
      #("candidate", json.string(pair.1.candidate_commit)),
      #("exit_code", json.int(pair.1.exit_code)),
      #(
        "raw_review_verdict",
        json.nullable(pair.1.raw_review_verdict, json.string),
      ),
      #("wrapper_verdict", json.nullable(pair.1.wrapper_verdict, json.string)),
      #("output_sha256", json.string(pair.1.output_sha256)),
    ])
  })
  |> json.to_string
  |> files.digest
}

fn validate_ledger_digest(
  store: FeatureEvidenceStore,
  args: Dict(String, String),
) -> Result(Nil, ToolError) {
  let expected =
    result.unwrap(dict.get(args, "ledger_sha256"), "") |> string.trim
  case expected == "" || expected == "any" || expected == ledger_digest(store) {
    True -> Ok(Nil)
    False ->
      Error(ToolError(
        "LEDGER_DIGEST_MISMATCH",
        "Requested ledger_sha256 differs from the canonical ledger",
        NonRetryable,
      ))
  }
}

fn page_offset(args: Dict(String, String)) -> Result(Int, ToolError) {
  case dict.get(args, "offset") {
    Error(_) -> Ok(0)
    Ok(raw) ->
      case int.parse(string.trim(raw)) {
        Ok(offset) if offset >= 0 -> Ok(offset)
        _ ->
          Error(ToolError(
            "INVALID_OFFSET",
            "offset must be a nonnegative integer",
            NonRetryable,
          ))
      }
  }
}

fn catalog_page(
  store: FeatureEvidenceStore,
  args: Dict(String, String),
) -> Outcome {
  // The quarantined-ledger check runs before any digest work so a corrupt or
  // symlinked ledger fails closed without touching the catalog projection.
  case check_ceiling(store) {
    Error(error) -> Refused(error)
    Ok(_) ->
      case validate_catalog_digest(store, args), page_offset(args) {
        Error(error), _ | _, Error(error) -> Refused(error)
        Ok(_), Ok(offset) ->
          case dict.has_key(args, "offset") {
            False -> harness_system_feature_catalog(store)
            True ->
              complete(
                "harness_system_feature_catalog",
                catalog_payload(page_store(store, offset)),
                store,
              )
          }
      }
  }
}

fn page_store(
  store: FeatureEvidenceStore,
  offset: Int,
) -> FeatureEvidenceStore {
  FeatureEvidenceStore(
    ..store,
    capabilities: list.drop(store.capabilities, offset) |> list.take(100),
  )
}

fn observations_page(
  store: FeatureEvidenceStore,
  args: Dict(String, String),
) -> Outcome {
  case
    check_ceiling(store),
    validate_observation_digests(store, args),
    page_offset(args)
  {
    Error(error), _, _ | _, Error(error), _ | _, _, Error(error) ->
      Refused(error)
    Ok(_), Ok(_), Ok(offset) ->
      case store_has_conflict(store) {
        True -> Refused(conflict_error())
        False -> {
          let observations =
            dict.to_list(store.receipts)
            |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
            |> list.drop(offset)
            |> list.take(100)
          let payload =
            json.object([
              #("active_candidate", json.string(store.active_candidate)),
              #("catalog_sha256", json.string(catalog_digest(store))),
              #("ledger_sha256", json.string(ledger_digest(store))),
              #("offset", json.int(offset)),
              #("total_observations", json.int(dict.size(store.receipts))),
              #(
                "observations",
                json.array(observations, fn(pair) {
                  json.object([
                    #("task_id", json.string(pair.0)),
                    #("candidate_commit", json.string(pair.1.candidate_commit)),
                    #("exit_code", json.int(pair.1.exit_code)),
                    #("output_sha256", json.string(pair.1.output_sha256)),
                    #(
                      "verified_for_active_candidate",
                      json.bool(valid_active_receipt(store, pair.1)),
                    ),
                    #("formal_state", json.string("unrun")),
                    #("admission_state", json.string("not_admitted")),
                  ])
                }),
              ),
            ])
            |> json.to_string
          complete("harness_system_feature_observations", payload, store)
        }
      }
  }
}

fn validate_observation_digests(
  store: FeatureEvidenceStore,
  args: Dict(String, String),
) -> Result(Nil, ToolError) {
  use _ <- result.try(validate_catalog_digest(store, args))
  validate_ledger_digest(store, args)
}

pub fn harness_system_feature_catalog(store: FeatureEvidenceStore) -> Outcome {
  case check_ceiling(store) {
    Error(error) -> Refused(error)
    Ok(_) ->
      case store_has_conflict(store) {
        True -> Refused(conflict_error())
        False ->
          complete(
            "harness_system_feature_catalog",
            catalog_payload(store),
            store,
          )
      }
  }
}

// ---------------------------------------------------------------------------
// Feature observations
// ---------------------------------------------------------------------------

fn observation_payload(
  store: FeatureEvidenceStore,
  task_id: String,
  receipt: ExecutionReceipt,
) -> String {
  json.object([
    #("task_id", json.string(task_id)),
    #("active_candidate", json.string(store.active_candidate)),
    #("candidate_commit", json.string(receipt.candidate_commit)),
    #("exit_code", json.int(receipt.exit_code)),
    #("output_sha256", json.string(receipt.output_sha256)),
    #(
      "execution_state",
      json.string(case receipt.exit_code == 0 {
        True -> "observed"
        False -> "failed_observation"
      }),
    ),
    #("formal_state", json.string("unrun")),
    #("admission_state", json.string("not_admitted")),
    #(
      "verified_for_active_candidate",
      json.bool(valid_active_receipt(store, receipt)),
    ),
    #("declared_is_not_admitted", json.bool(True)),
  ])
  |> json.to_string
}

pub fn harness_system_feature_observations(
  store: FeatureEvidenceStore,
  task_id: String,
) -> Outcome {
  case check_ceiling(store) {
    Error(error) -> Refused(error)
    Ok(_) ->
      case store_has_conflict(store) {
        True -> Refused(conflict_error())
        False -> observations_for_task(store, task_id)
      }
  }
}

fn observations_for_task(
  store: FeatureEvidenceStore,
  task_id: String,
) -> Outcome {
  case dict.get(store.receipts, task_id) {
    Ok(receipt) ->
      case wrapper_raw_conflict(receipt) {
        True -> Refused(conflict_error())
        False ->
          case is_active_candidate_receipt(store, receipt) {
            False -> Refused(stale_error())
            True ->
              case list.contains(store.completed_task_ids, task_id) {
                True ->
                  case receipt.exit_code == 0 {
                    True ->
                      complete(
                        "harness_system_feature_observations",
                        observation_payload(store, task_id, receipt),
                        store,
                      )
                    False -> Refused(failed_receipt_error())
                  }
                False ->
                  complete(
                    "harness_system_feature_observations",
                    observation_payload(store, task_id, receipt),
                    store,
                  )
              }
          }
      }
    Error(_) ->
      case list.contains(store.completed_task_ids, task_id) {
        True -> Refused(missing_receipt_error())
        False ->
          Refused(ToolError(
            "UNKNOWN_FEATURE_OR_TASK",
            "No receipt or completed task for id " <> task_id,
            NonRetryable,
          ))
      }
  }
}

// ---------------------------------------------------------------------------
// Feature intent
// ---------------------------------------------------------------------------

pub fn harness_system_feature_intent(
  store: FeatureEvidenceStore,
  intent_id: String,
) -> Outcome {
  case check_ceiling(store) {
    Error(error) -> Refused(error)
    Ok(_) ->
      case store_has_conflict(store) {
        True -> Refused(conflict_error())
        False ->
          case dict.get(store.intents, intent_id) {
            Ok(intent) -> {
              let payload =
                json.object([
                  #("intent_id", json.string(intent_id)),
                  #("intent", json.string(intent)),
                  #("active_candidate", json.string(store.active_candidate)),
                  #("execution_state", json.string("planned")),
                  #("formal_state", json.string("unrun")),
                  #("admission_state", json.string("not_admitted")),
                ])
                |> json.to_string
              complete("harness_system_feature_intent", payload, store)
            }
            Error(_) ->
              Refused(ToolError(
                "UNKNOWN_FEATURE_INTENT",
                "No recorded intent for id " <> intent_id,
                NonRetryable,
              ))
          }
      }
  }
}

// ---------------------------------------------------------------------------
// Evidence helper
// ---------------------------------------------------------------------------

fn complete(
  tool: String,
  payload: String,
  store: FeatureEvidenceStore,
) -> Outcome {
  // All feature payloads are generated JSON objects; bind the authenticity to
  // this loaded projection, never to a later environment observation.
  let payload =
    "{\"ledger_authenticity\":\""
    <> ledger_authenticity(store)
    <> "\","
    <> string.drop_start(payload, 1)
  Complete(
    payload,
    EvidenceRecord(
      candidate: store.active_candidate,
      route: "public",
      tool: tool,
      declaration_state: "declared",
      implementation_state: "implemented",
      execution_state: "observed",
      formal_state: "unrun",
      admission_state: "not_admitted",
      output_sha256: files.digest(payload),
    ),
  )
}
