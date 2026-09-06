//// Vault audit reconcile — Smriti.db I/O scaffold (Slice F).
////
//// Bridges the pure-function reconciler in `vault_audit_reconcile.gleam` to
//// the Smriti.db `secret_policy` table. This module deliberately ships
//// **scaffolding only**: SQL constants, pure parse functions, and an FFI
//// signature into a not-yet-wired Erlang shim (`vault_smriti_ffi`).
////
//// Stub-That-Lies guard ([zk-3346fc607a1ef9e6], RPN 729): we do NOT execute
//// SQL here. The Erlang shim returns `{error, <<"not_yet_wired">>}` so any
//// caller that invokes `fetch_actual_policies/0` gets a truthful error
//// instead of an empty list pretending to be a successful query.
////
//// The pure parse functions (`parse_row`, `parse_rows`) are the real,
//// exhaustively-tested public surface.
////
//// Schema (from `sub-projects/c3i/native/planning_daemon/src/db.rs` Pass-6):
////   CREATE TABLE secret_policy (
////     Name TEXT PRIMARY KEY,
////     Category TEXT NOT NULL CHECK (Category IN (...)),
////     TtlSeconds INTEGER NOT NULL CHECK (TtlSeconds > 0),
////     MaxTtlSec INTEGER NOT NULL CHECK (MaxTtlSec > 0 AND MaxTtlSec >= TtlSeconds),
////     RotationDays INTEGER NOT NULL DEFAULT 365,
////     Sensitivity TEXT NOT NULL CHECK (Sensitivity IN ('L0','L3','L7')),
////     CreatedAt TEXT NOT NULL,
////     UpdatedAt TEXT NOT NULL
////   );
////
//// SC-VAULT-013, SC-VAULT-016.

import cepaf_gleam/vault_audit_reconcile.{
  type ActualPolicy, type Discrepancy, type ExpectedPolicy, ActualPolicy,
}
import gleam/list

// =====================================================================
// SQL constants
// =====================================================================

/// Canonical SELECT for reconciliation. Returns the 4 columns needed to
/// construct an `ActualPolicy`: Name, TtlSeconds, MaxTtlSec, Sensitivity.
/// Other columns (Category, RotationDays, CreatedAt, UpdatedAt) are not
/// used by the reconciler.
pub const select_all_policies_sql: String = "SELECT Name, TtlSeconds, MaxTtlSec, Sensitivity FROM secret_policy"

// =====================================================================
// Pure parsers (the real, tested surface)
// =====================================================================

/// Convert a single Smriti row tuple into an `ActualPolicy`. Pure: same
/// input always yields same output. No validation — the SQL CHECK
/// constraints in db.rs guarantee well-formed values, so the reconciler
/// itself classifies any anomaly as a `Drift`.
pub fn parse_row(row: #(String, Int, Int, String)) -> ActualPolicy {
  let #(name, ttl, max_ttl, sensitivity) = row
  ActualPolicy(name: name, ttl: ttl, max_ttl: max_ttl, sensitivity: sensitivity)
}

/// Map `parse_row` over a list of rows.
pub fn parse_rows(
  rows: List(#(String, Int, Int, String)),
) -> List(ActualPolicy) {
  list.map(rows, parse_row)
}

// =====================================================================
// FFI bridge (signature-only; shim returns Error("not_yet_wired"))
// =====================================================================

/// Fetch all `secret_policy` rows from Smriti.db and parse them into
/// `ActualPolicy` values. Used by the daily `vault_policy_audit` Oban job.
///
/// Slice F status: the FFI shim in `vault_smriti_ffi.erl` returns
/// `{error, <<"not_yet_wired">>}`. A future slice will replace the shim
/// with a real sqlite query (likely via the existing `sa-plan-daemon`
/// Smriti binding rather than rusqlite-in-NIF, per SC-VAULT-CRYPTO-001
/// and the existing architecture split).
pub fn fetch_actual_policies() -> Result(List(ActualPolicy), String) {
  case ffi_select() {
    Ok(rows) -> Ok(parse_rows(rows))
    Error(reason) -> Error(reason)
  }
}

@external(erlang, "vault_smriti_ffi", "select_actual_policies")
fn ffi_select() -> Result(List(#(String, Int, Int, String)), String)

// =====================================================================
// Pass-34 Track F — pure compare_actual_vs_expected wrapper
// =====================================================================

/// Pure-function thin wrapper over `vault_audit_reconcile.reconcile/2`
/// that exposes ONLY the discrepancies list. Used by the daily Oban
/// audit job which only cares about what differs (the totals are
/// available via the upstream `reconcile` if needed).
///
/// Same input always yields same output. No FFI, no I/O.
pub fn compare_actual_vs_expected(
  actual: List(ActualPolicy),
  expected: List(ExpectedPolicy),
) -> List(Discrepancy) {
  vault_audit_reconcile.reconcile(expected, actual).discrepancies
}
