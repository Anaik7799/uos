//// Epistemic documentation, dashboard, dev-acceptance and release gates.
////
//// This module keeps declaration, implementation, observed execution, formal
//// verification, independent review and admission strictly separated. Refusal,
//// unavailability, unknown and stale capability verdicts are never rendered as
//// operational or admitted; completed task counts alone can never turn the
//// dashboard green; and raw review verdicts can never be overridden by a
//// summary wrapper claim. Sovereign system admission additionally requires the
//// two-key verification: formal verification AND fresh runtime observation at
//// the active candidate, on top of at least one raw-passing independent review.

import cepaf_gleam/mcp/types.{type ToolError, NonRetryable, ToolError}
import gleam/list
import gleam/result
import gleam/string

// ---------------------------------------------------------------------------
// Capability documentation status
// ---------------------------------------------------------------------------

/// Four-state separated capability verdict. Only a genuinely observed
/// operational capability may be rendered as operational development evidence.
pub type CapabilityVerdict {
  Operational(detail: String)
  Refused(code: String, detail: String)
  Unavailable(reason: String)
  Unknown(reason: String)
  Stale(candidate: String)
}

/// Render the documentation status string for a capability verdict. Refusal,
/// unavailability, unknown and stale verdicts are explicitly non-operational
/// and never collapse to `"operational"` or `"admitted"`.
pub fn render_capability_doc_status(verdict: CapabilityVerdict) -> String {
  case verdict {
    Operational(_) -> "operational_verified_dev"
    Refused(code, _) -> "refused_non_operational:" <> code
    Unavailable(reason) -> "unavailable_non_operational:" <> reason
    Unknown(reason) -> "unknown_non_operational:" <> reason
    Stale(candidate) -> "stale_non_operational:" <> candidate
  }
}

// ---------------------------------------------------------------------------
// Independent review reconciliation
// ---------------------------------------------------------------------------

pub type ReviewRecord {
  ReviewRecord(
    reviewer: String,
    candidate_id: String,
    raw_verdict: String,
    critical_findings: Int,
  )
}

fn review_blocking_error(reason: String) -> ToolError {
  ToolError("RAW_REVIEW_BLOCKING", reason, NonRetryable)
}

fn wrapper_conflict_error() -> ToolError {
  ToolError(
    "WRAPPER_RAW_REVIEW_CONFLICT",
    "Summary wrapper cannot override a non-passing raw review verdict",
    NonRetryable,
  )
}

/// Reconcile an independent review against the active candidate.
///
/// The wrapper claim (`"PASS"`, `"GREEN"`, `"OVERRIDE"`, ...) is never used to
/// elevate a review. Elevation requires the review to be bound to the active
/// candidate, carry zero critical findings and carry a raw `"PASS"` verdict.
/// A claiming wrapper on a non-passing raw review is a fail-closed conflict.
pub fn reconcile_review_verdict(
  review: ReviewRecord,
  active_candidate: String,
  wrapper_claim: String,
) -> Result(String, ToolError) {
  let raw_pass = string.uppercase(string.trim(review.raw_verdict)) == "PASS"
  let wrapper_pass = string.uppercase(string.trim(wrapper_claim)) == "PASS"
  case review.candidate_id != active_candidate {
    True ->
      Error(review_blocking_error(
        "Review candidate does not match active candidate",
      ))
    False ->
      case review.critical_findings > 0 {
        True ->
          Error(review_blocking_error(
            "Review carries unresolved critical findings",
          ))
        False ->
          case raw_pass {
            False ->
              case wrapper_pass {
                True -> Error(wrapper_conflict_error())
                False ->
                  Error(review_blocking_error("Raw review verdict is not PASS"))
              }
            True -> Ok("RAW_REVIEW_PASS")
          }
      }
  }
}

fn reviews_pass(reviews: List(ReviewRecord), active_candidate: String) -> Bool {
  reviews != []
  && list.all(reviews, fn(review) {
    result.is_ok(reconcile_review_verdict(
      review,
      active_candidate,
      review.raw_verdict,
    ))
  })
}

// ---------------------------------------------------------------------------
// Dashboard readiness
// ---------------------------------------------------------------------------

pub const hold_status = "INCOMPLETE_EVIDENCE_HOLD"

pub const dev_verified_status = "DEV_CANDIDATE_VERIFIED_NOT_SYSTEM_ADMITTED"

/// Compute dashboard readiness. Completing every task is never sufficient:
/// positive cell coverage, at least one independent review and an all-pass
/// review reconciliation are mandatory. A fully passing dashboard is still only
/// a verified development candidate, never a sovereign system admission.
pub fn compute_dashboard_readiness(
  total_tasks: Int,
  completed_tasks: Int,
  verified_positive_cells: Int,
  required_positive_cells: Int,
  active_candidate: String,
  reviews: List(ReviewRecord),
) -> String {
  let tasks_complete = total_tasks > 0 && completed_tasks == total_tasks
  let cells_covered =
    required_positive_cells > 0
    && verified_positive_cells >= required_positive_cells
  let reviews_ok = reviews_pass(reviews, active_candidate)
  case tasks_complete && cells_covered && reviews_ok {
    True -> dev_verified_status
    False -> hold_status
  }
}

// ---------------------------------------------------------------------------
// Dev acceptance decision
// ---------------------------------------------------------------------------

pub type MatrixCell {
  MatrixCell(
    cell_id: String,
    category: String,
    candidate_id: String,
    positive_observed: Bool,
    refusal_only: Bool,
  )
}

pub type DevAcceptanceDecision {
  DevAcceptanceDecision(
    core_dev_ready: Bool,
    mcp_full_dev_ready: Bool,
    system_admission: String,
    blocking_reasons: List(String),
  )
}

/// The four full acceptance categories. Each must have at least one positive,
/// candidate-bound, non-refusal-only cell before full MCP development readiness.
pub const full_cell_categories = [
  "clients",
  "facilities",
  "transports",
  "assurance",
]

pub const not_admitted = "NOT_ADMITTED"

pub const admitted = "ADMITTED"

fn cell_positive_at_candidate(
  cell: MatrixCell,
  active_candidate: String,
) -> Bool {
  cell.candidate_id == active_candidate
  && cell.positive_observed
  && !cell.refusal_only
}

fn core_cells_ok(cells: List(MatrixCell), active_candidate: String) -> Bool {
  let core_cells = list.filter(cells, fn(cell) { cell.category == "core" })
  core_cells != []
  && list.all(core_cells, fn(cell) {
    cell_positive_at_candidate(cell, active_candidate)
  })
}

fn full_cells_ok(cells: List(MatrixCell), active_candidate: String) -> Bool {
  let required_categories_ok =
    list.all(full_cell_categories, fn(category) {
      let cat_cells = list.filter(cells, fn(cell) { cell.category == category })
      cat_cells != []
      && list.all(cat_cells, fn(cell) {
        cell_positive_at_candidate(cell, active_candidate)
      })
    })
  let no_unknown_or_failing_extra =
    list.all(cells, fn(cell) {
      case cell.category {
        "core" -> True
        category ->
          list.contains(full_cell_categories, category)
          && cell_positive_at_candidate(cell, active_candidate)
      }
    })
  required_categories_ok && no_unknown_or_failing_extra
}

/// Evaluate development acceptance and sovereign system admission.
///
/// Core cell gaps block both development readiness flags. Full category gaps
/// block only full MCP readiness. Missing/failing independent reviews, absent
/// formal verification or absent fresh runtime observation block development
/// readiness and force `"NOT_ADMITTED"` even when a sovereign grant was
/// presented (two-key verification).
pub fn evaluate_dev_acceptance(
  active_candidate: String,
  cells: List(MatrixCell),
  formal_verified: Bool,
  runtime_observed: Bool,
  independent_reviews: List(ReviewRecord),
  sovereign_admission_granted: Bool,
) -> DevAcceptanceDecision {
  let core_ok = core_cells_ok(cells, active_candidate)
  let full_ok = full_cells_ok(cells, active_candidate)
  let reviews_ok = reviews_pass(independent_reviews, active_candidate)
  let two_key_ok = reviews_ok && formal_verified && runtime_observed

  let blocking_reasons =
    list.flatten([
      case core_ok {
        True -> []
        False -> ["CORE_CELLS_NOT_POSITIVE_AT_ACTIVE_CANDIDATE"]
      },
      case full_ok {
        True -> []
        False -> ["FULL_CELL_CATEGORIES_INCOMPLETE"]
      },
      case reviews_ok {
        True -> []
        False -> ["INDEPENDENT_REVIEWS_MISSING_OR_FAILING"]
      },
      case formal_verified {
        True -> []
        False -> ["FORMAL_VERIFICATION_ABSENT"]
      },
      case runtime_observed {
        True -> []
        False -> ["RUNTIME_OBSERVATION_ABSENT"]
      },
    ])

  let system_admission = case
    sovereign_admission_granted && core_ok && full_ok && two_key_ok
  {
    True -> admitted
    False -> not_admitted
  }

  DevAcceptanceDecision(
    core_dev_ready: core_ok && two_key_ok,
    mcp_full_dev_ready: core_ok && full_ok && two_key_ok,
    system_admission: system_admission,
    blocking_reasons: blocking_reasons,
  )
}
