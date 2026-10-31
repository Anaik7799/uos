//// Wave 2 P01 acceptance tests: Vault metadata backend and the strict Feature
//// receipt ledger projection.
////
//// These tests exercise only metadata-only Vault files and the verified
//// receipt ledger. They assert that absent, symlinked, corrupted,
//// duplicate-key, NUL-byte, secret-bearing, stale, and wrong-tenant inputs
//// are refused without crashing; that the honest empty projection fabricates
//// no `T00..T24` completion; that per-receipt `observed_tools` are bound to
//// the receipt that observed them; and that a quarantined ledger
//// deterministically refuses all five feature tools.
////
//// Every test uses a unique per-run directory and removes it afterwards.

import cepaf_gleam/harness/files
import cepaf_gleam/mcp/adapters/feature_receipt_ledger as ledger
import cepaf_gleam/mcp/adapters/features
import cepaf_gleam/mcp/adapters/vault_backend
import cepaf_gleam/mcp/adapters/vault_metadata as vault
import cepaf_gleam/mcp/admission.{type ValidatedCall, ValidatedCall}
import cepaf_gleam/mcp/principal
import cepaf_gleam/mcp/registry
import cepaf_gleam/mcp/tools
import cepaf_gleam/mcp/types.{
  type Outcome, ClientProfile, Complete, NonRetryable, Refused, ToolError,
}
import gleam/dict
import gleam/erlang/charlist
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{None}
import gleam/string
import gleeunit/should
import simplifile

@external(erlang, "cepaf_gleam_ffi", "system_time_nanos")
fn system_time_nanos() -> Int

const now_ms = 1_800_000_000_000

const vault_tools = [
  "vault_status",
  "vault_health",
  "vault_list_secrets",
  "vault_audit_tail",
  "vault_policy_get",
]

// ---------------------------------------------------------------------------
// Unique directories and cleanup
// ---------------------------------------------------------------------------

fn temp_root(label: String) -> String {
  "/home/an/NAS-setup/uos/.uos-workspaces/codex-mcp-canonical-20261031/apps/cepaf_gleam/build/dev/p01_vault_ledger_"
  <> label
  <> "_"
  <> int.to_string(system_time_nanos())
}

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

fn write_nested(root: String, relative: String, contents: String) -> String {
  let path = root <> "/" <> relative
  let assert Ok(_) = simplifile.create_directory_all(parent_path(path))
  let assert Ok(Nil) = simplifile.write(path, contents)
  path
}

fn make_symlink(target: String, link: String) -> Nil {
  let assert Ok(_) = simplifile.create_directory_all(parent_path(link))
  let assert Ok(Nil) = simplifile.create_symlink(to: target, from: link)
  Nil
}

fn cleanup(root: String) -> Nil {
  let _ = simplifile.delete_all([root])
  Nil
}

fn call(tool: String, tenant: String) -> ValidatedCall {
  let assert Ok(spec) = registry.lookup("public", tool)
  ValidatedCall(
    spec,
    principal.from_launcher_env(
      actor: "owner",
      client: ClientProfile("test"),
      workspace_root: "tenant-a",
      session_id: "test",
    ),
    dict.from_list([#("tenant_id", tenant)]),
    None,
    None,
    None,
    None,
  )
}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

fn valid_vault_json_at(tenant: String, observed_at_ms: Int) -> String {
  "{\"tenant_id\":\""
  <> tenant
  <> "\",\"sealed\":false,\"healthy\":true,"
  <> "\"observed_at_ms\":"
  <> int.to_string(observed_at_ms)
  <> ","
  <> "\"secret_names\":[\"hvs.name\",\"Bearer token\",\"ghp_canary\",\"-----BEGIN PRIVATE KEY-----\"],"
  <> "\"policies\":{\"default\":\"hvs.policy\"},"
  <> "\"audit_lines\":[\"ghp_audit\",\"safe audit entry\"]}"
}

fn valid_vault_json(tenant: String) -> String {
  valid_vault_json_at(tenant, now_ms - 1000)
}

fn empty_ledger_json() -> String {
  "{\"admitted_ev_ceiling\":93,\"completed_task_ids\":[],\"receipts\":[],\"intents\":{}}"
}

fn valid_ledger_json() -> String {
  "{\"schema\":\"v1\",\"admitted_ev_ceiling\":93,"
  <> "\"completed_task_ids\":[\"T01\",\"T03\"],"
  <> "\"receipts\":["
  <> "{\"task_id\":\"T01\",\"candidate_commit\":\"cand-A\",\"exit_code\":0,"
  <> "\"raw_review_verdict\":\"APPROVED\",\"wrapper_verdict\":\"NONE\","
  <> "\"output_sha256\":\"sha-t01\","
  <> "\"observed_tools\":[\"mcp_capability_inventory\",\"harness_system_feature_catalog\"]},"
  <> "{\"task_id\":\"T02\",\"candidate_commit\":\"cand-B\",\"exit_code\":0,"
  <> "\"raw_review_verdict\":\"APPROVED\",\"wrapper_verdict\":\"NONE\","
  <> "\"output_sha256\":\"sha-t02\","
  <> "\"observed_tools\":[\"harness_execution_progress\"]}"
  <> "],"
  <> "\"intents\":{\"i1\":\"Implement truthful ledger\"}}"
}

fn conflict_ledger_json() -> String {
  "{\"admitted_ev_ceiling\":93,\"completed_task_ids\":[\"T01\"],"
  <> "\"receipts\":[{\"task_id\":\"T01\",\"candidate_commit\":\"cand-A\","
  <> "\"exit_code\":0,\"raw_review_verdict\":\"HOLD\","
  <> "\"wrapper_verdict\":\"APPROVED\",\"output_sha256\":\"sha-t01\"}],"
  <> "\"intents\":{}}"
}

fn conflict_elsewhere_ledger_json() -> String {
  "{\"admitted_ev_ceiling\":93,\"completed_task_ids\":[\"T01\",\"T09\"],"
  <> "\"receipts\":["
  <> "{\"task_id\":\"T01\",\"candidate_commit\":\"cand-A\",\"exit_code\":0,"
  <> "\"raw_review_verdict\":\"HOLD\",\"wrapper_verdict\":\"APPROVED\","
  <> "\"output_sha256\":\"sha-t01\"},"
  <> "{\"task_id\":\"T09\",\"candidate_commit\":\"cand-A\",\"exit_code\":0,"
  <> "\"raw_review_verdict\":\"APPROVED\",\"wrapper_verdict\":\"NONE\","
  <> "\"output_sha256\":\"sha-t09\"}"
  <> "],\"intents\":{}}"
}

fn load_store(path: String) -> features.FeatureEvidenceStore {
  ledger.load_verified_projection_from("tenant-a", "cand-A", path)
}

fn expect_refused(outcome: Outcome, code: String) -> Nil {
  case outcome {
    Refused(ToolError(actual, _, NonRetryable)) -> actual |> should.equal(code)
    _ -> should.fail()
  }
}

fn feature_outcomes(store: features.FeatureEvidenceStore) -> List(Outcome) {
  [
    features.execute(store, "mcp_capability_inventory", dict.new()),
    features.execute(store, "harness_system_feature_catalog", dict.new()),
    features.execute(
      store,
      "harness_system_feature_observations",
      dict.from_list([#("task_id", "T01")]),
    ),
    features.execute(
      store,
      "harness_system_feature_intent",
      dict.from_list([#("intent_id", "i1")]),
    ),
    features.execute(store, "harness_execution_progress", dict.new()),
  ]
}

fn expect_all_feature_refusals(
  store: features.FeatureEvidenceStore,
  code: String,
) -> Nil {
  feature_outcomes(store)
  |> list.each(fn(outcome) { expect_refused(outcome, code) })
}

fn find_capability(
  store: features.FeatureEvidenceStore,
  id: String,
) -> Result(features.CapabilityRecord, Nil) {
  list.find(store.capabilities, fn(capability) { capability.id == id })
}

fn expect_capability_state(
  store: features.FeatureEvidenceStore,
  id: String,
  state: String,
) -> Nil {
  let assert Ok(capability) = find_capability(store, id)
  capability.execution_state |> should.equal(state)
}

// ---------------------------------------------------------------------------
// Vault metadata: fail-closed loading
// ---------------------------------------------------------------------------

pub fn vault_absent_file_is_unwired_test() {
  let root = temp_root("vault_absent")
  let path = root <> "/var/vault/metadata.json"
  let handle = vault_backend.load_vault_handle_at("tenant-a", path, now_ms)
  let assert vault.UnwiredVault(_) = handle
  vault_tools
  |> list.each(fn(tool) {
    vault.execute(handle, call(tool, "tenant-a"))
    |> expect_refused("VAULT_BACKEND_UNWIRED")
  })
  cleanup(root)
}

pub fn vault_symlinked_file_is_unwired_test() {
  let root = temp_root("vault_symlink")
  let target = write_nested(root, "target.json", valid_vault_json("tenant-a"))
  let link = root <> "/link.json"
  make_symlink(target, link)
  let handle = vault_backend.load_vault_handle_at("tenant-a", link, now_ms)
  let assert vault.UnwiredVault(_) = handle
  vault_tools
  |> list.each(fn(tool) {
    vault.execute(handle, call(tool, "tenant-a"))
    |> expect_refused("VAULT_BACKEND_UNWIRED")
  })
  cleanup(root)
}

pub fn vault_corrupt_file_is_unwired_test() {
  let root = temp_root("vault_corrupt")
  let path = write_nested(root, "metadata.json", "{\"tenant_id\":")
  let handle = vault_backend.load_vault_handle_at("tenant-a", path, now_ms)
  let assert vault.UnwiredVault(_) = handle
  cleanup(root)
}

/// Strictly discriminating: identical to a 100%-valid `SupervisedVault`
/// snapshot except for the duplicate `tenant_id` member.
pub fn vault_duplicate_key_is_unwired_test() {
  let root = temp_root("vault_duplicate")
  let body =
    "{\"tenant_id\":\"tenant-a\",\"tenant_id\":\"tenant-a\",\"sealed\":false,\"healthy\":true,"
    <> "\"observed_at_ms\":"
    <> int.to_string(now_ms - 1000)
    <> ","
    <> "\"secret_names\":[\"hvs.name\"],"
    <> "\"policies\":{\"default\":\"read-only\"},"
    <> "\"audit_lines\":[\"safe audit entry\"]}"
  let path = write_nested(root, "metadata.json", body)
  let handle = vault_backend.load_vault_handle_at("tenant-a", path, now_ms)
  let assert vault.UnwiredVault(_) = handle
  cleanup(root)
}

/// Strictly discriminating: identical to a 100%-valid `SupervisedVault`
/// snapshot except for a single raw 0x00 byte inside an audit line.
pub fn vault_raw_nul_byte_is_unwired_test() {
  let root = temp_root("vault_nul")
  let body =
    "{\"tenant_id\":\"tenant-a\",\"sealed\":false,\"healthy\":true,"
    <> "\"observed_at_ms\":"
    <> int.to_string(now_ms - 1000)
    <> ","
    <> "\"secret_names\":[\"hvs.name\"],"
    <> "\"policies\":{\"default\":\"read-only\"},"
    <> "\"audit_lines\":[\"safe\u{0000}audit entry\"]}"
  let path = write_nested(root, "metadata.json", body)
  let handle = vault_backend.load_vault_handle_at("tenant-a", path, now_ms)
  let assert vault.UnwiredVault(_) = handle
  cleanup(root)
}

pub fn vault_wrong_tenant_is_unwired_test() {
  let root = temp_root("vault_wrong_tenant")
  let path = write_nested(root, "metadata.json", valid_vault_json("tenant-b"))
  let handle = vault_backend.load_vault_handle_at("tenant-a", path, now_ms)
  let assert vault.UnwiredVault(_) = handle
  cleanup(root)
}

pub fn vault_empty_root_is_unwired_test() {
  let root = temp_root("vault_empty_root")
  let path = write_nested(root, "metadata.json", valid_vault_json("tenant-a"))
  let handle = vault_backend.load_vault_handle_at("", path, now_ms)
  let assert vault.UnwiredVault(_) = handle
  cleanup(root)
}

pub fn vault_stale_snapshot_is_unwired_test() {
  let root = temp_root("vault_stale")
  let stale =
    write_nested(
      root,
      "stale.json",
      valid_vault_json_at("tenant-a", now_ms - 400_000),
    )
  let handle = vault_backend.load_vault_handle_at("tenant-a", stale, now_ms)
  let assert vault.UnwiredVault(_) = handle

  let future =
    write_nested(
      root,
      "future.json",
      valid_vault_json_at("tenant-a", now_ms + 100_000),
    )
  let skewed = vault_backend.load_vault_handle_at("tenant-a", future, now_ms)
  let assert vault.UnwiredVault(_) = skewed

  // A fresh snapshot with an explicit max_age_ms inside the bound is accepted.
  let fresh =
    "{\"tenant_id\":\"tenant-a\",\"sealed\":false,\"healthy\":true,"
    <> "\"observed_at_ms\":"
    <> int.to_string(now_ms - 1000)
    <> ",\"max_age_ms\":600000,"
    <> "\"secret_names\":[\"metadata/name\"],"
    <> "\"policies\":{\"default\":\"read-only\"},"
    <> "\"audit_lines\":[]}"
  let fresh_path = write_nested(root, "fresh.json", fresh)
  let assert vault.SupervisedVault(_, _, _, _, _, _) =
    vault_backend.load_vault_handle_at("tenant-a", fresh_path, now_ms)
  cleanup(root)
}

/// Unknown top-level keys and secret-material policy keys are refused.
pub fn vault_unknown_top_level_and_forbidden_policy_key_are_unwired_test() {
  let root = temp_root("vault_forbidden")
  let unknown =
    "{\"tenant_id\":\"tenant-a\",\"sealed\":false,\"healthy\":true,"
    <> "\"observed_at_ms\":"
    <> int.to_string(now_ms - 1000)
    <> ",\"secret_names\":[\"metadata/name\"],"
    <> "\"policies\":{\"default\":\"read-only\"},"
    <> "\"audit_lines\":[],\"Secrets\":[\"hvs.leak\"]}"
  let unknown_path = write_nested(root, "unknown.json", unknown)
  let handle =
    vault_backend.load_vault_handle_at("tenant-a", unknown_path, now_ms)
  let assert vault.UnwiredVault(_) = handle

  let forbidden_policy =
    "{\"tenant_id\":\"tenant-a\",\"sealed\":false,\"healthy\":true,"
    <> "\"observed_at_ms\":"
    <> int.to_string(now_ms - 1000)
    <> ",\"secret_names\":[\"metadata/name\"],"
    <> "\"policies\":{\"root_token\":\"s.leak\"},"
    <> "\"audit_lines\":[]}"
  let policy_path = write_nested(root, "policy.json", forbidden_policy)
  let policy_handle =
    vault_backend.load_vault_handle_at("tenant-a", policy_path, now_ms)
  let assert vault.UnwiredVault(_) = policy_handle

  // Non-text policy values and empty secret names fail closed.
  let bad_types =
    "{\"tenant_id\":\"tenant-a\",\"sealed\":false,\"healthy\":true,"
    <> "\"observed_at_ms\":"
    <> int.to_string(now_ms - 1000)
    <> ",\"secret_names\":[\"\"],"
    <> "\"policies\":{\"default\":42},"
    <> "\"audit_lines\":[42]}"
  let bad_types_path = write_nested(root, "bad_types.json", bad_types)
  let bad_types_handle =
    vault_backend.load_vault_handle_at("tenant-a", bad_types_path, now_ms)
  let assert vault.UnwiredVault(_) = bad_types_handle
  cleanup(root)
}

pub fn vault_parent_directory_symlink_is_unwired_test() {
  let root = temp_root("vault_parent_symlink")
  let _ =
    write_nested(root, "real/vault/metadata.json", valid_vault_json("tenant-a"))
  make_symlink(root <> "/real", root <> "/var")
  let handle =
    vault_backend.load_vault_handle_at(
      "tenant-a",
      root <> "/var/vault/metadata.json",
      now_ms,
    )
  let assert vault.UnwiredVault(_) = handle
  let _ = simplifile.delete(root <> "/var")
  cleanup(root)
}

// ---------------------------------------------------------------------------
// Vault metadata: redaction and tenant scope on the happy path
// ---------------------------------------------------------------------------

pub fn vault_redaction_spares_benign_and_catches_provider_prefixes_test() {
  vault.redact("task-123") |> should.equal("task-123")
  vault.redact("disk-1") |> should.equal("disk-1")
  vault.redact("sk-proj-abc") |> should.equal("[REDACTED]")
  vault.redact("sk-ant-abc") |> should.equal("[REDACTED]")
  vault.redact("AKIAIOSFODNN7EXAMPLE") |> should.equal("[REDACTED]")
  vault.redact("Bearer abc") |> should.equal("[REDACTED]")
  vault.redact("password=hunter2") |> should.equal("[REDACTED]")
  vault.redact("vault_token=abc") |> should.equal("[REDACTED]")
}

pub fn vault_valid_metadata_redacts_secret_patterns_across_all_tools_test() {
  let root = temp_root("vault_valid_redact")
  let path = write_nested(root, "metadata.json", valid_vault_json("tenant-a"))
  let handle = vault_backend.load_vault_handle_at("tenant-a", path, now_ms)
  let canaries = ["hvs.", "Bearer ", "ghp_", "canary", "PRIVATE KEY"]
  let carriers = ["vault_list_secrets", "vault_audit_tail", "vault_policy_get"]

  vault_tools
  |> list.each(fn(tool) {
    let assert Complete(payload, _) =
      vault.execute(handle, call(tool, "tenant-a"))
    list.each(canaries, fn(canary) {
      string.contains(payload, canary) |> should.be_false
    })
    case list.contains(carriers, tool) {
      True -> string.contains(payload, "[REDACTED]") |> should.be_true
      False -> Nil
    }
  })

  vault_tools
  |> list.each(fn(tool) {
    vault.execute(handle, call(tool, "tenant-b"))
    |> expect_refused("VAULT_CROSS_TENANT_FORBIDDEN")
  })
  cleanup(root)
}

// ---------------------------------------------------------------------------
// Feature receipt ledger: honest empty projection
// ---------------------------------------------------------------------------

pub fn absent_ledger_yields_honest_empty_projection_test() {
  let root = temp_root("feature_absent")
  let path = root <> "/var/harness/mcp_feature_receipt_ledger.json"
  let store = load_store(path)
  store.admitted_ev_ceiling |> should.equal(features.ev_ceiling)
  store.completed_task_ids |> should.equal([])
  store.receipts |> dict.size |> should.equal(0)
  store.intents |> dict.size |> should.equal(0)
  list.length(store.capabilities) |> should.equal(101)

  let report = features.compute_progress(store)
  report.completed_total |> should.equal(0)
  report.verified_complete_count |> should.equal(0)
  report.unverified_missing_receipt_count |> should.equal(0)
  report.stale_receipt_count |> should.equal(0)

  let assert Ok(inventory) = features.capability_inventory(store)
  inventory.total_routes |> should.equal(101)

  list.any(store.completed_task_ids, fn(id) {
    list.contains(fake_task_ids(), id)
  })
  |> should.be_false
  cleanup(root)
}

fn fake_task_ids() -> List(String) {
  [
    "T00", "T01", "T02", "T03", "T04", "T05", "T06", "T07", "T08", "T09", "T10",
    "T11", "T12", "T13", "T14", "T15", "T16", "T17", "T18", "T19", "T20", "T21",
    "T22", "T23", "T24",
  ]
}

pub fn empty_verified_store_matches_absent_projection_test() {
  let direct = ledger.empty_verified_store("cand-A")
  direct.admitted_ev_ceiling |> should.equal(features.ev_ceiling)
  direct.completed_task_ids |> should.equal([])
  direct.receipts |> dict.size |> should.equal(0)
  list.length(direct.capabilities) |> should.equal(101)
}

/// Declared-unavailable tools are never counted as implemented.
pub fn default_capabilities_does_not_fake_unavailable_implementations_test() {
  let store = ledger.empty_verified_store("cand-A")
  let assert Ok(control) = find_capability(store, "control_loop")
  control.implementation_state |> should.equal("declared_only")
  let assert Ok(vault_status) = find_capability(store, "vault_status")
  vault_status.implementation_state |> should.equal("declared_only")

  let assert Ok(inventory) = features.capability_inventory(store)
  let expected_implemented =
    registry.all_specs()
    |> list.count(fn(spec) {
      !list.contains(tools.unavailable_tools, spec.name)
    })
  should.equal(inventory.implemented_count, expected_implemented)
  should.be_true(inventory.implemented_count < inventory.total_routes)
}

// ---------------------------------------------------------------------------
// Feature receipt ledger: truthful progress and observations
// ---------------------------------------------------------------------------

pub fn valid_ledger_reports_truthful_progress_and_observations_test() {
  let root = temp_root("feature_valid")
  let path = write_nested(root, "ledger.json", valid_ledger_json())
  let store = load_store(path)
  store.admitted_ev_ceiling |> should.equal(93)

  let report = features.compute_progress(store)
  report.completed_total |> should.equal(2)
  report.verified_complete_count |> should.equal(1)
  report.unverified_missing_receipt_count |> should.equal(1)
  report.stale_receipt_count |> should.equal(1)

  // Active receipt T01 is observed.
  let assert Complete(payload, _) =
    features.execute(
      store,
      "harness_system_feature_observations",
      dict.from_list([#("task_id", "T01")]),
    )
  string.contains(payload, "\"execution_state\":\"observed\"")
  |> should.be_true
  string.contains(payload, "\"verified_for_active_candidate\":true")
  |> should.be_true

  // Stale receipt T02 is refused, never counted.
  features.execute(
    store,
    "harness_system_feature_observations",
    dict.from_list([#("task_id", "T02")]),
  )
  |> expect_refused("STALE_CANDIDATE_RECEIPT")

  // Unreceipted completed task T03 is refused, never counted.
  features.execute(
    store,
    "harness_system_feature_observations",
    dict.from_list([#("task_id", "T03")]),
  )
  |> expect_refused("MISSING_EXECUTION_RECEIPT")

  // Intents are reported as planned only.
  let assert Complete(intent_payload, _) =
    features.execute(
      store,
      "harness_system_feature_intent",
      dict.from_list([#("intent_id", "i1")]),
    )
  string.contains(intent_payload, "Implement truthful ledger") |> should.be_true
  string.contains(intent_payload, "\"admission_state\":\"not_admitted\"")
  |> should.be_true

  // Per-receipt binding: T01's tools are observed; the stale T02 tool is not.
  expect_capability_state(store, "mcp_capability_inventory", "observed")
  expect_capability_state(store, "harness_system_feature_catalog", "observed")
  expect_capability_state(store, "harness_execution_progress", "unrun")
  expect_capability_state(store, "vault_status", "unrun")

  let assert Ok(inventory) = features.capability_inventory(store)
  // The same tool name can appear on more than one route, so count capability
  // records rather than distinct names. Only T01's two named tools qualify.
  let observed_ids = [
    "mcp_capability_inventory",
    "harness_system_feature_catalog",
  ]
  let expected_observed =
    list.count(store.capabilities, fn(capability) {
      list.contains(observed_ids, capability.id)
    })
  should.equal(inventory.observed_count, expected_observed)
  should.be_true(inventory.observed_count >= 2)
  inventory.admitted_count |> should.equal(0)
  cleanup(root)
}

/// A clean receipt only elevates the tools it explicitly names. A ledger-wide
/// trust list no longer exists.
pub fn stale_receipt_tool_is_not_observed_test() {
  let root = temp_root("feature_stale_binding")
  let body =
    "{\"admitted_ev_ceiling\":93,\"completed_task_ids\":[\"T01\"],"
    <> "\"receipts\":[{\"task_id\":\"T01\",\"candidate_commit\":\"cand-B\","
    <> "\"exit_code\":0,\"raw_review_verdict\":\"APPROVED\","
    <> "\"wrapper_verdict\":\"NONE\",\"output_sha256\":\"sha-t01\","
    <> "\"observed_tools\":[\"harness_execution_progress\"]}],"
    <> "\"intents\":{}}"
  let path = write_nested(root, "ledger.json", body)
  let store = load_store(path)
  store.admitted_ev_ceiling |> should.equal(93)
  expect_capability_state(store, "harness_execution_progress", "unrun")
  cleanup(root)
}

/// The legacy ledger-wide `observed_tools` trust list is rejected outright.
pub fn top_level_observed_tools_refuses_all_feature_tools_test() {
  let root = temp_root("feature_top_level_observed")
  let body =
    "{\"admitted_ev_ceiling\":93,\"completed_task_ids\":[\"T01\"],"
    <> "\"receipts\":[{\"task_id\":\"T01\",\"candidate_commit\":\"cand-A\","
    <> "\"exit_code\":0,\"output_sha256\":\"sha-t01\"}],"
    <> "\"intents\":{},"
    <> "\"observed_tools\":[\"mcp_capability_inventory\"]}"
  let path = write_nested(root, "ledger.json", body)
  let store = load_store(path)
  store.admitted_ev_ceiling |> should.equal(features.corrupt_ledger_sentinel)
  expect_all_feature_refusals(store, "FEATURE_LEDGER_CORRUPT")
  cleanup(root)
}

pub fn unknown_observed_tool_refuses_all_feature_tools_test() {
  let root = temp_root("feature_unknown_tool")
  let body =
    "{\"admitted_ev_ceiling\":93,\"completed_task_ids\":[\"T01\"],"
    <> "\"receipts\":[{\"task_id\":\"T01\",\"candidate_commit\":\"cand-A\","
    <> "\"exit_code\":0,\"raw_review_verdict\":\"APPROVED\","
    <> "\"wrapper_verdict\":\"NONE\",\"output_sha256\":\"sha-t01\","
    <> "\"observed_tools\":[\"totally_unknown_tool\"]}],"
    <> "\"intents\":{}}"
  let path = write_nested(root, "ledger.json", body)
  let store = load_store(path)
  store.admitted_ev_ceiling |> should.equal(features.corrupt_ledger_sentinel)
  expect_all_feature_refusals(store, "FEATURE_LEDGER_CORRUPT")
  cleanup(root)
}

// ---------------------------------------------------------------------------
// Feature receipt ledger: quarantine fails all five tools closed
// ---------------------------------------------------------------------------

pub fn corrupt_ledger_refuses_all_feature_tools_test() {
  let root = temp_root("feature_corrupt")
  let path = write_nested(root, "ledger.json", "{\"receipts\":")
  let store = load_store(path)
  store.admitted_ev_ceiling |> should.equal(features.corrupt_ledger_sentinel)
  expect_all_feature_refusals(store, "FEATURE_LEDGER_CORRUPT")
  cleanup(root)
}

/// Strictly discriminating: identical to a valid ledger except for a duplicate
/// `schema` member.
pub fn duplicate_key_ledger_refuses_all_feature_tools_test() {
  let root = temp_root("feature_duplicate")
  let body =
    "{\"schema\":\"v1\",\"schema\":\"v1\",\"admitted_ev_ceiling\":93,"
    <> "\"completed_task_ids\":[],\"receipts\":[],\"intents\":{}}"
  let path = write_nested(root, "ledger.json", body)
  let store = load_store(path)
  store.admitted_ev_ceiling |> should.equal(features.corrupt_ledger_sentinel)
  expect_all_feature_refusals(store, "FEATURE_LEDGER_CORRUPT")
  cleanup(root)
}

/// Strictly discriminating: identical to a valid ledger except for a raw 0x00
/// byte inside an intent value.
pub fn nul_byte_ledger_refuses_all_feature_tools_test() {
  let root = temp_root("feature_nul")
  let body =
    "{\"schema\":\"v1\",\"admitted_ev_ceiling\":93,"
    <> "\"completed_task_ids\":[],\"receipts\":[],"
    <> "\"intents\":{\"i1\":\"truthful\u{0000}ledger\"}}"
  let path = write_nested(root, "ledger.json", body)
  let store = load_store(path)
  store.admitted_ev_ceiling |> should.equal(features.corrupt_ledger_sentinel)
  expect_all_feature_refusals(store, "FEATURE_LEDGER_CORRUPT")
  cleanup(root)
}

pub fn missing_ceiling_ledger_refuses_all_feature_tools_test() {
  let root = temp_root("feature_missing_ceiling")
  let path =
    write_nested(
      root,
      "ledger.json",
      "{\"schema\":\"v1\",\"completed_task_ids\":[],\"receipts\":[],\"intents\":{}}",
    )
  let store = load_store(path)
  store.admitted_ev_ceiling |> should.equal(features.corrupt_ledger_sentinel)
  expect_all_feature_refusals(store, "FEATURE_LEDGER_CORRUPT")
  cleanup(root)
}

pub fn duplicate_completed_task_ids_refuse_all_feature_tools_test() {
  let root = temp_root("feature_duplicate_ids")
  let path =
    write_nested(
      root,
      "ledger.json",
      "{\"schema\":\"v1\",\"admitted_ev_ceiling\":93,"
        <> "\"completed_task_ids\":[\"T01\",\"T01\"],\"receipts\":[],\"intents\":{}}",
    )
  let store = load_store(path)
  store.admitted_ev_ceiling |> should.equal(features.corrupt_ledger_sentinel)
  expect_all_feature_refusals(store, "FEATURE_LEDGER_CORRUPT")
  cleanup(root)
}

pub fn malformed_field_ledger_refuses_all_feature_tools_test() {
  let root = temp_root("feature_malformed")
  let path =
    write_nested(
      root,
      "ledger.json",
      "{\"admitted_ev_ceiling\":93,\"completed_task_ids\":[\"T01\",42],"
        <> "\"receipts\":[],\"intents\":{}}",
    )
  let store = load_store(path)
  store.admitted_ev_ceiling |> should.equal(features.corrupt_ledger_sentinel)
  expect_all_feature_refusals(store, "FEATURE_LEDGER_CORRUPT")
  cleanup(root)
}

pub fn empty_ledger_file_refuses_all_feature_tools_test() {
  let root = temp_root("feature_empty_file")
  let path = write_nested(root, "ledger.json", "")
  let store = load_store(path)
  store.admitted_ev_ceiling |> should.equal(features.corrupt_ledger_sentinel)
  expect_all_feature_refusals(store, "FEATURE_LEDGER_CORRUPT")
  cleanup(root)
}

pub fn symlink_ledger_refuses_all_feature_tools_test() {
  let root = temp_root("feature_symlink")
  let target = write_nested(root, "target.json", empty_ledger_json())
  let link = root <> "/ledger.json"
  make_symlink(target, link)
  let store = load_store(link)
  store.admitted_ev_ceiling |> should.equal(features.symlink_ledger_sentinel)
  expect_all_feature_refusals(store, "FEATURE_LEDGER_SYMLINK_FORBIDDEN")
  cleanup(root)
}

pub fn parent_symlink_ledger_refuses_all_feature_tools_test() {
  let root = temp_root("feature_parent_symlink")
  let _ = write_nested(root, "real/harness/ledger.json", empty_ledger_json())
  make_symlink(root <> "/real", root <> "/var")
  let store = load_store(root <> "/var/harness/ledger.json")
  store.admitted_ev_ceiling |> should.equal(features.symlink_ledger_sentinel)
  expect_all_feature_refusals(store, "FEATURE_LEDGER_SYMLINK_FORBIDDEN")
  let _ = simplifile.delete(root <> "/var")
  cleanup(root)
}

pub fn over_ceiling_ledger_refuses_all_feature_tools_test() {
  let root = temp_root("feature_ceiling")
  let path =
    write_nested(
      root,
      "ledger.json",
      "{\"admitted_ev_ceiling\":94,\"completed_task_ids\":[],"
        <> "\"receipts\":[],\"intents\":{}}",
    )
  let store = load_store(path)
  store.admitted_ev_ceiling |> should.equal(-1)
  expect_all_feature_refusals(store, "FEATURE_LEDGER_CORRUPT")
  cleanup(root)
}

pub fn wrapper_conflict_ledger_refuses_all_feature_tools_test() {
  let root = temp_root("feature_conflict")
  let path = write_nested(root, "ledger.json", conflict_ledger_json())
  let store = load_store(path)
  store.admitted_ev_ceiling |> should.equal(93)
  expect_all_feature_refusals(store, "WRAPPER_RAW_VERDICT_CONFLICT")
  cleanup(root)
}

/// The store-wide wrapper conflict guard fires even for an unrelated task id.
pub fn store_wide_conflict_is_caught_for_other_task_id_test() {
  let root = temp_root("feature_conflict_elsewhere")
  let path = write_nested(root, "ledger.json", conflict_elsewhere_ledger_json())
  let store = load_store(path)
  store.admitted_ev_ceiling |> should.equal(93)

  let assert Ok(clean_receipt) = dict.get(store.receipts, "T09")
  features.valid_active_receipt(store, clean_receipt) |> should.be_true
  features.wrapper_raw_conflict(clean_receipt) |> should.be_false

  features.execute(
    store,
    "harness_system_feature_observations",
    dict.from_list([#("task_id", "T09")]),
  )
  |> expect_refused("WRAPPER_RAW_VERDICT_CONFLICT")

  features.execute(
    store,
    "harness_system_feature_observations",
    dict.from_list([#("task_id", "T99")]),
  )
  |> expect_refused("WRAPPER_RAW_VERDICT_CONFLICT")
  cleanup(root)
}

/// A quarantined store refuses even missing-argument requests with the
/// quarantine code, because the ceiling guard runs before argument validation.
pub fn quarantined_store_refuses_missing_argument_with_quarantine_code_test() {
  let root = temp_root("feature_quarantine_priority")
  let path = write_nested(root, "ledger.json", "{\"receipts\":")
  let store = load_store(path)

  features.execute(store, "harness_system_feature_observations", dict.new())
  |> expect_refused("FEATURE_LEDGER_CORRUPT")

  features.execute(store, "harness_system_feature_intent", dict.new())
  |> expect_refused("FEATURE_LEDGER_CORRUPT")

  features.execute(store, "not_a_feature_tool", dict.new())
  |> expect_refused("FEATURE_LEDGER_CORRUPT")
  cleanup(root)
}

/// A failed receipt for a non-completed task is reported truthfully as a
/// failed observation, never elevated to `observed`.
pub fn failed_non_completed_observation_is_not_observed_test() {
  let root = temp_root("feature_failed_observation")
  let body =
    "{\"admitted_ev_ceiling\":93,\"completed_task_ids\":[],"
    <> "\"receipts\":[{\"task_id\":\"T-inflight\",\"candidate_commit\":\"cand-A\","
    <> "\"exit_code\":1,\"output_sha256\":\"sha-inflight\"}],"
    <> "\"intents\":{}}"
  let path = write_nested(root, "ledger.json", body)
  let store = load_store(path)
  let assert Complete(payload, _) =
    features.execute(
      store,
      "harness_system_feature_observations",
      dict.from_list([#("task_id", "T-inflight")]),
    )
  string.contains(payload, "\"execution_state\":\"failed_observation\"")
  |> should.be_true
  string.contains(payload, "\"execution_state\":\"observed\"")
  |> should.be_false
  cleanup(root)
}

@external(erlang, "os", "putenv")
fn put_env_native(name: charlist.Charlist, raw: charlist.Charlist) -> Bool

@external(erlang, "os", "unsetenv")
fn unset_env_native(name: charlist.Charlist) -> Bool

@external(erlang, "cepaf_gleam_ffi", "get_env")
fn get_env(name: String) -> Result(String, Nil)

fn with_env(name: String, raw: String, run: fn() -> a) -> a {
  let before = get_env(name)
  let _ = put_env_native(charlist.from_string(name), charlist.from_string(raw))
  let result = run()
  case before {
    Ok(old) -> {
      let _ =
        put_env_native(charlist.from_string(name), charlist.from_string(old))
      Nil
    }
    Error(_) -> {
      let _ = unset_env_native(charlist.from_string(name))
      Nil
    }
  }
  result
}

fn indices(count: Int) -> List(Int) {
  int.range(1, count + 1, [], fn(acc, n) { [n, ..acc] }) |> list.reverse
}

pub fn declared_only_observed_tool_quarantines_ledger_test() {
  let root = temp_root("declared_tool")
  let assert [unavailable, ..] = tools.unavailable_tools
  let raw =
    valid_ledger_json()
    |> string.replace("mcp_capability_inventory", unavailable)
  let path = write_nested(root, "ledger.json", raw)
  let store = load_store(path)
  cleanup(root)
  store.admitted_ev_ceiling |> should.equal(-1)
  expect_all_feature_refusals(store, "FEATURE_LEDGER_CORRUPT")
}

pub fn noncanonical_ceiling_quarantines_ledger_test() {
  let root = temp_root("exact_ceiling")
  let results =
    list.map([0, 92, 94, 109], fn(n) {
      let path =
        write_nested(
          root,
          "ledger.json",
          string.replace(empty_ledger_json(), ":93", ":" <> int.to_string(n)),
        )
      load_store(path).admitted_ev_ceiling
    })
  cleanup(root)
  results |> should.equal([-1, -1, -1, -1])
}

pub fn optional_ledger_sha_pin_and_authenticity_test() {
  let root = temp_root("ledger_pin")
  let raw = valid_ledger_json()
  let path = write_nested(root, "ledger.json", raw)
  let results =
    list.map(
      [files.digest(raw), string.repeat("0", 64), "INVALID", ""],
      fn(pin) {
        with_env("UOS_FEATURE_RECEIPT_LEDGER_SHA256", pin, fn() {
          let store = load_store(path)
          #(
            store.admitted_ev_ceiling,
            features.execute(store, "harness_execution_progress", dict.new()),
          )
        })
      },
    )
  cleanup(root)
  let assert [
    #(93, Complete(pinned, _)),
    #(-1, _),
    #(-1, _),
    #(93, Complete(unpinned, _)),
  ] = results
  pinned
  |> string.contains("\"ledger_authenticity\":\"sha256_pinned\"")
  |> should.be_true
  unpinned
  |> string.contains(
    "\"ledger_authenticity\":\"workspace_self_attested_unpinned\"",
  )
  |> should.be_true
}

pub fn relative_and_unnormalized_overrides_fail_closed_test() {
  let root = temp_root("relative_paths")
  list.each(
    [
      "ledger.json",
      "./ledger.json",
      root <> "/../ledger.json",
      root <> "//ledger.json",
      root <> "/./ledger.json",
    ],
    fn(path) {
      let ceiling =
        with_env("UOS_FEATURE_RECEIPT_LEDGER_PATH", path, fn() {
          ledger.load_verified_projection(root, "cand-A").admitted_ev_ceiling
        })
      ceiling |> should.equal(-1)
      let handle =
        with_env("UOS_VAULT_SNAPSHOT_PATH", path, fn() {
          vault_backend.load_vault_handle(root)
        })
      let assert vault.UnwiredVault(_) = handle
    },
  )
  cleanup(root)
}

pub fn ancestors_above_workspace_root_are_checked_test() {
  let root = temp_root("above_root")
  let _ = write_nested(root, "real/sub/ledger.json", empty_ledger_json())
  make_symlink(root <> "/real", root <> "/alias")
  let workspace = root <> "/alias/sub"
  let _ = write_nested(root, "real/sub/vault.json", valid_vault_json(workspace))
  let store =
    ledger.load_verified_projection_from(
      workspace,
      "cand-A",
      workspace <> "/ledger.json",
    )
  let handle =
    vault_backend.load_vault_handle_at(
      workspace,
      workspace <> "/vault.json",
      now_ms,
    )
  cleanup(root)
  store.admitted_ev_ceiling |> should.equal(-2)
  let assert vault.UnwiredVault(_) = handle
}

pub fn ledger_item_count_caps_test() {
  let root = temp_root("caps")
  let ids =
    indices(4097) |> list.map(fn(n) { json.string("T" <> int.to_string(n)) })
  let receipts =
    indices(1025)
    |> list.map(fn(n) {
      json.object([
        #("task_id", json.string(int.to_string(n))),
        #("candidate_commit", json.string("cand-A")),
        #("exit_code", json.int(0)),
        #("output_sha256", json.string("out")),
      ])
    })
  let intents =
    indices(4097)
    |> list.map(fn(n) { #(int.to_string(n), json.string("intent")) })
    |> json.object
  let observations =
    json.object([
      #("task_id", json.string("T1")),
      #("candidate_commit", json.string("cand-A")),
      #("exit_code", json.int(0)),
      #("output_sha256", json.string("out")),
      #(
        "observed_tools",
        json.array(list.repeat("mcp_capability_inventory", 129), json.string),
      ),
    ])
  let ceilings =
    list.map(
      [
        #("completed_task_ids", json.array(ids, fn(x) { x })),
        #("receipts", json.array(receipts, fn(x) { x })),
        #("intents", intents),
        #("receipts", json.array([observations], fn(x) { x })),
      ],
      fn(field) {
        let path =
          write_nested(
            root,
            "ledger.json",
            json.object([#("admitted_ev_ceiling", json.int(93)), field])
              |> json.to_string,
          )
        load_store(path).admitted_ev_ceiling
      },
    )
  cleanup(root)
  ceilings |> should.equal([-1, -1, -1, -1])
}

pub fn two_thousand_unique_ids_load_under_500ms_test() {
  let root = temp_root("2000_ids")
  let ids = indices(2000) |> list.map(fn(n) { "T" <> int.to_string(n) })
  let path =
    write_nested(
      root,
      "ledger.json",
      json.object([
        #("admitted_ev_ceiling", json.int(93)),
        #("completed_task_ids", json.array(ids, json.string)),
      ])
        |> json.to_string,
    )
  let start = system_time_nanos()
  let store = load_store(path)
  let elapsed = system_time_nanos() - start
  cleanup(root)
  store.completed_task_ids |> should.equal(ids)
  { elapsed < 500_000_000 } |> should.be_true
}

pub fn vault_secret_redaction_vectors_and_benign_policy_test() {
  let secrets = [
    "hvb.canary",
    "hvr.canary",
    "eyJhbGciOiJ",
    "token=canary",
    "secret=canary",
    "password=canary",
    "password: canary",
    "apikey=canary",
    "api_key=canary",
    "ya29.canary",
    "AIzaCanary",
    "glpat-canary",
    "ghp_canary",
    "ghs_canary",
    "xoxb-canary",
    "sk-proj-canary",
    "sk-ant-canary",
    "AKIA1234567890ABCDEF",
    "Authorization: Bearer canary",
    "https://user:pass@example.test/path",
  ]
  let redacted = list.map(secrets, vault.redact)
  let benign = [
    "akia",
    "brakia-report",
    "secret-readonly",
    "task-123",
    "disk-1",
    "AKIAshort",
  ]
  let safe = list.map(benign, vault.redact)
  let root = temp_root("benign_policy")
  let raw =
    valid_vault_json("tenant-a")
    |> string.replace(
      "\"default\":\"hvs.policy\"",
      "\"secret-readonly\":\"safe policy\"",
    )
  let path = write_nested(root, "vault.json", raw)
  let handle = vault_backend.load_vault_handle_at("tenant-a", path, now_ms)
  cleanup(root)
  redacted |> should.equal(list.repeat("[REDACTED]", list.length(secrets)))
  safe |> should.equal(benign)
  let assert vault.SupervisedVault(_, _, _, _, policies, _) = handle
  dict.get(policies, "secret-readonly") |> should.equal(Ok("safe policy"))
}

pub fn missing_pinned_ledger_is_quarantined_test() {
  let root = temp_root("missing_pin")
  let ceilings =
    list.map(["INVALID", string.repeat("0", 64)], fn(pin) {
      with_env("UOS_FEATURE_RECEIPT_LEDGER_SHA256", pin, fn() {
        ledger.load_verified_projection_from(
          root,
          "cand-A",
          root <> "/absent.json",
        ).admitted_ev_ceiling
      })
    })
  cleanup(root)
  ceilings |> should.equal([-1, -1])
}

pub fn pinned_authenticity_survives_environment_change_and_catalog_page_test() {
  let root = temp_root("pin_attribution")
  let raw = valid_ledger_json()
  let path = write_nested(root, "ledger.json", raw)
  let store =
    with_env("UOS_FEATURE_RECEIPT_LEDGER_SHA256", files.digest(raw), fn() {
      load_store(path)
    })
  cleanup(root)
  list.each(
    [
      #("mcp_capability_inventory", dict.new()),
      #("harness_execution_progress", dict.new()),
      #(
        "harness_system_feature_observations",
        dict.from_list([#("task_id", "T01")]),
      ),
      #(
        "harness_system_feature_catalog",
        dict.from_list([#("offset", "10000")]),
      ),
    ],
    fn(pair) {
      let assert Complete(raw, _) = features.execute(store, pair.0, pair.1)
      raw
      |> string.contains("\"ledger_authenticity\":\"sha256_pinned\"")
      |> should.be_true
    },
  )
}
