//// Vault audit reconcile — pure-function diff between expected secret_policy
//// rows and actual rows in Smriti.db.
////
//// Slice F partial (Pass-24): the daily Oban schedule `vault_policy_audit`
//// fetches actual rows from Smriti.db, calls into this pure module to compute
//// the discrepancy, and emits the result as a Zenoh OTel span on
//// `indrajaal/l5/vault/policy_audit/<run_id>`.
////
//// Per .claude/rules/secrets-vault.md SC-VAULT-016 (daily reconciliation cron)
//// and SC-VAULT-013 (every secret MUST have a policy row).
////
//// Pure function, no side effects → exhaustively unit-testable in-process.

import gleam/list

// =====================================================================
// Types
// =====================================================================

/// Expected canonical policy entry — comes from `vault.gleam` defaults
/// (policy_l0_hot_key, policy_l3_oauth_refresh, etc.) keyed by secret name.
pub type ExpectedPolicy {
  ExpectedPolicy(name: String, ttl: Int, max_ttl: Int, sensitivity: String)
}

/// Actual row from Smriti.db secret_policy table.
pub type ActualPolicy {
  ActualPolicy(name: String, ttl: Int, max_ttl: Int, sensitivity: String)
}

/// Discrepancy classification.
pub type Discrepancy {
  /// Expected secret has no row in Smriti.db.
  Missing(name: String)
  /// Smriti.db has a row that no longer exists in the expected catalog
  /// (orphan; potentially a renamed/rotated secret).
  Orphan(name: String)
  /// Both sides have the row but ttl/max_ttl/sensitivity differ.
  Drift(name: String, field: String, expected: String, actual: String)
}

/// Result of a full reconciliation pass.
pub type ReconcileResult {
  ReconcileResult(
    discrepancies: List(Discrepancy),
    expected_count: Int,
    actual_count: Int,
    matched_count: Int,
  )
}

// =====================================================================
// Public API
// =====================================================================

/// Compute the full diff between expected and actual policy lists.
///
/// Algorithm:
/// 1. For each expected: find matching actual (by name).
///    - No match → Missing
///    - Match with field drift → Drift entries
///    - Exact match → matched_count++
/// 2. For each actual: if no expected with same name → Orphan
///
/// Pure function — same input always produces same output.
pub fn reconcile(
  expected: List(ExpectedPolicy),
  actual: List(ActualPolicy),
) -> ReconcileResult {
  let #(expected_results, matched_count) =
    list.fold(expected, #([], 0), fn(acc, exp) {
      let #(discs, matches) = acc
      case find_actual(actual, exp.name) {
        Error(Nil) -> #([Missing(name: exp.name), ..discs], matches)
        Ok(act) -> {
          let drifts = compare_fields(exp, act)
          case drifts {
            [] -> #(discs, matches + 1)
            ds -> #(list.append(ds, discs), matches)
          }
        }
      }
    })

  let orphans =
    list.fold(actual, [], fn(acc, act) {
      case find_expected(expected, act.name) {
        Error(Nil) -> [Orphan(name: act.name), ..acc]
        Ok(_) -> acc
      }
    })

  ReconcileResult(
    discrepancies: list.append(expected_results, orphans),
    expected_count: list.length(expected),
    actual_count: list.length(actual),
    matched_count: matched_count,
  )
}

/// Convenience: returns True iff the reconcile result has zero discrepancies.
pub fn is_clean(result: ReconcileResult) -> Bool {
  case result.discrepancies {
    [] -> True
    _ -> False
  }
}

/// Severity classification: any Missing or Orphan = HIGH (secret unprotected
/// or stale row); only Drift = MEDIUM (config out of sync). For SC-VAULT-016
/// daily cron alerting.
pub fn highest_severity(result: ReconcileResult) -> String {
  let has_critical =
    list.any(result.discrepancies, fn(d) {
      case d {
        Missing(_) -> True
        Orphan(_) -> True
        Drift(_, _, _, _) -> False
      }
    })
  case has_critical, result.discrepancies {
    True, _ -> "HIGH"
    _, [] -> "NONE"
    _, _ -> "MEDIUM"
  }
}

// =====================================================================
// Internal helpers
// =====================================================================

fn find_actual(
  actual: List(ActualPolicy),
  name: String,
) -> Result(ActualPolicy, Nil) {
  list.find(actual, fn(a) { a.name == name })
}

fn find_expected(
  expected: List(ExpectedPolicy),
  name: String,
) -> Result(ExpectedPolicy, Nil) {
  list.find(expected, fn(e) { e.name == name })
}

fn compare_fields(exp: ExpectedPolicy, act: ActualPolicy) -> List(Discrepancy) {
  let drifts = []
  let drifts = case exp.ttl == act.ttl {
    True -> drifts
    False -> [
      Drift(
        name: exp.name,
        field: "ttl",
        expected: int_to_s(exp.ttl),
        actual: int_to_s(act.ttl),
      ),
      ..drifts
    ]
  }
  let drifts = case exp.max_ttl == act.max_ttl {
    True -> drifts
    False -> [
      Drift(
        name: exp.name,
        field: "max_ttl",
        expected: int_to_s(exp.max_ttl),
        actual: int_to_s(act.max_ttl),
      ),
      ..drifts
    ]
  }
  let drifts = case exp.sensitivity == act.sensitivity {
    True -> drifts
    False -> [
      Drift(
        name: exp.name,
        field: "sensitivity",
        expected: exp.sensitivity,
        actual: act.sensitivity,
      ),
      ..drifts
    ]
  }
  drifts
}

@external(erlang, "erlang", "integer_to_binary")
fn int_to_s(n: Int) -> String
