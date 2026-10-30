//// T23: Independent final development acceptance.
////
//// Verifies that completed tasks alone can never qualify a candidate:
//// CORE_DEV_READY requires every `"core"` cell to carry a real positive
//// observation at the active candidate, and MCP_FULL_DEV_READY additionally
//// requires clients, facilities, transports and assurance. Sovereign system
//// admission remains a separate two-key decision (formal verification AND
//// fresh runtime observation on top of passing independent reviews) and can
//// never be reached by a grant alone or by a summary wrapper.

import cepaf_gleam/mcp/epistemic_gates.{
  type DevAcceptanceDecision, type MatrixCell, type ReviewRecord, MatrixCell,
  ReviewRecord, evaluate_dev_acceptance, full_cell_categories, not_admitted,
}
import cepaf_gleam/mcp/registry
import gleam/list
import gleeunit/should

const active_candidate = "cand-final-active"

const stale_candidate = "cand-final-stale"

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

fn review(reviewer: String, candidate: String) -> ReviewRecord {
  ReviewRecord(
    reviewer: reviewer,
    candidate_id: candidate,
    raw_verdict: "PASS",
    critical_findings: 0,
  )
}

fn passing_reviews() -> List(ReviewRecord) {
  [review("Claude", active_candidate), review("Codex", active_candidate)]
}

fn core_cell(id: String) -> MatrixCell {
  MatrixCell(
    cell_id: id,
    category: "core",
    candidate_id: active_candidate,
    positive_observed: True,
    refusal_only: False,
  )
}

fn all_core_cells() -> List(MatrixCell) {
  [
    core_cell("core-admission"),
    core_cell("core-route"),
    core_cell("core-schema"),
  ]
}

fn full_cell(category: String) -> MatrixCell {
  MatrixCell(
    cell_id: "cell-" <> category,
    category: category,
    candidate_id: active_candidate,
    positive_observed: True,
    refusal_only: False,
  )
}

fn all_full_cells() -> List(MatrixCell) {
  list.map(full_cell_categories, full_cell)
}

fn complete_cells() -> List(MatrixCell) {
  list.append(all_core_cells(), all_full_cells())
}

fn evaluate(
  cells: List(MatrixCell),
  formal_verified: Bool,
  runtime_observed: Bool,
  reviews: List(ReviewRecord),
  sovereign_admission_granted: Bool,
) -> DevAcceptanceDecision {
  evaluate_dev_acceptance(
    active_candidate,
    cells,
    formal_verified,
    runtime_observed,
    reviews,
    sovereign_admission_granted,
  )
}

fn assert_both_blocked(decision: DevAcceptanceDecision, label: String) -> Nil {
  case decision.core_dev_ready {
    True -> panic as { label <> ": CORE_DEV_READY must be blocked" }
    False -> Nil
  }
  case decision.mcp_full_dev_ready {
    True -> panic as { label <> ": MCP_FULL_DEV_READY must be blocked" }
    False -> Nil
  }
}

// ---------------------------------------------------------------------------
// Registry census
// ---------------------------------------------------------------------------

fn assert_registry_census() -> Nil {
  let specs = registry.all_specs()
  list.length(specs) |> should.equal(101)
  list.length(list.filter(specs, fn(spec) { spec.route == "public" }))
  |> should.equal(65)
  list.length(list.filter(specs, fn(spec) { spec.route == "development" }))
  |> should.equal(21)
  list.length(list.filter(specs, fn(spec) { spec.route == "successor" }))
  |> should.equal(15)
}

// ---------------------------------------------------------------------------
// Test 1
// ---------------------------------------------------------------------------

pub fn missing_positive_cell_blocks_development_acceptance_test() {
  assert_registry_census()

  let reviews = passing_reviews()

  // A core cell that is missing, stale, non-positive or refusal-only blocks
  // BOTH development readiness flags, even with a sovereign grant presented.
  let missing_core_cells = all_full_cells()

  let stale_core_cells =
    [
      core_cell("core-admission"),
      MatrixCell(
        cell_id: "core-route",
        category: "core",
        candidate_id: stale_candidate,
        positive_observed: True,
        refusal_only: False,
      ),
    ]
    |> list.append(all_full_cells())

  let non_positive_core_cells =
    [
      core_cell("core-admission"),
      MatrixCell(
        cell_id: "core-route",
        category: "core",
        candidate_id: active_candidate,
        positive_observed: False,
        refusal_only: False,
      ),
    ]
    |> list.append(all_full_cells())

  let refusal_only_core_cells =
    [
      core_cell("core-admission"),
      MatrixCell(
        cell_id: "core-route",
        category: "core",
        candidate_id: active_candidate,
        positive_observed: True,
        refusal_only: True,
      ),
    ]
    |> list.append(all_full_cells())

  [
    #("missing core", missing_core_cells),
    #("stale core", stale_core_cells),
    #("non-positive core", non_positive_core_cells),
    #("refusal-only core", refusal_only_core_cells),
  ]
  |> list.each(fn(entry) {
    let #(label, cells) = entry
    let decision = evaluate(cells, True, True, reviews, True)
    assert_both_blocked(decision, label)
  })

  // With all core cells genuinely positive, CORE_DEV_READY is reached, but a
  // missing or refusal-only full-category cell keeps MCP_FULL_DEV_READY False.
  list.each(full_cell_categories, fn(missing_category) {
    let cells_without_category =
      all_core_cells()
      |> list.append(
        list.filter(all_full_cells(), fn(cell) {
          cell.category != missing_category
        }),
      )
    let missing_decision =
      evaluate(cells_without_category, True, True, reviews, True)
    missing_decision.core_dev_ready |> should.equal(True)
    missing_decision.mcp_full_dev_ready |> should.equal(False)

    let refusal_cells =
      all_core_cells()
      |> list.append(
        list.map(all_full_cells(), fn(cell) {
          case cell.category == missing_category {
            True -> MatrixCell(..cell, refusal_only: True)
            False -> cell
          }
        }),
      )
    let refusal_decision = evaluate(refusal_cells, True, True, reviews, True)
    refusal_decision.core_dev_ready |> should.equal(True)
    refusal_decision.mcp_full_dev_ready |> should.equal(False)
  })

  // Only a complete positive matrix on the active candidate, with passing
  // independent reviews and both verification keys, reaches both dev flags.
  let fully_ready = evaluate(complete_cells(), True, True, reviews, False)
  fully_ready.core_dev_ready |> should.equal(True)
  fully_ready.mcp_full_dev_ready |> should.equal(True)
  // Absent a sovereign grant, system admission is still withheld.
  fully_ready.system_admission |> should.equal(not_admitted)
}

// ---------------------------------------------------------------------------
// Test 2
// ---------------------------------------------------------------------------

fn assert_admission_fail_closed(
  cells: List(MatrixCell),
  formal_verified: Bool,
  runtime_observed: Bool,
  reviews: List(ReviewRecord),
  label: String,
) -> Nil {
  let decision =
    evaluate(cells, formal_verified, runtime_observed, reviews, True)
  decision.system_admission |> should.equal(not_admitted)
  assert_both_blocked(decision, label)
}

pub fn formal_or_runtime_missing_cannot_be_admitted_test() {
  let cells = complete_cells()
  let good_reviews = passing_reviews()

  // Two-key enforcement: a sovereign grant plus a full matrix is still not
  // enough when either verification key is absent.
  assert_admission_fail_closed(
    cells,
    False,
    True,
    good_reviews,
    "formal absent",
  )
  assert_admission_fail_closed(
    cells,
    True,
    False,
    good_reviews,
    "runtime absent",
  )
  assert_admission_fail_closed(
    cells,
    False,
    False,
    good_reviews,
    "both keys absent",
  )

  // A critical finding survives even a raw PASS verdict.
  let critical_reviews = [
    review("Claude", active_candidate),
    ReviewRecord(
      reviewer: "Codex",
      candidate_id: active_candidate,
      raw_verdict: "PASS",
      critical_findings: 1,
    ),
  ]
  assert_admission_fail_closed(
    cells,
    True,
    True,
    critical_reviews,
    "critical findings",
  )

  // A review bound to a stale candidate is never accepted, even if it claims
  // PASS and carries no findings.
  let stale_reviews = [
    review("Claude", active_candidate),
    review("Codex", stale_candidate),
  ]
  assert_admission_fail_closed(
    cells,
    True,
    True,
    stale_reviews,
    "stale review candidate",
  )

  // Missing independent reviews also block admission.
  assert_admission_fail_closed(cells, True, True, [], "no reviews")
}

// ---------------------------------------------------------------------------
// Test 3: Popperian hardening of category masking and grant-only admission
// ---------------------------------------------------------------------------

pub fn failing_second_cell_in_category_blocks_full_dev_ready_test() {
  let reviews = passing_reviews()

  // One passing `"transports"` cell must never mask a failing second cell in
  // the same category: every cell in every required category must be positive
  // at the active candidate.
  let extra_failing_transports =
    MatrixCell(
      cell_id: "cell-transports-regression",
      category: "transports",
      candidate_id: active_candidate,
      positive_observed: False,
      refusal_only: False,
    )
  let masked =
    complete_cells()
    |> list.append([extra_failing_transports])
  let masked_decision = evaluate(masked, True, True, reviews, True)
  masked_decision.core_dev_ready |> should.equal(True)
  masked_decision.mcp_full_dev_ready |> should.equal(False)
  masked_decision.system_admission |> should.equal(not_admitted)

  // A refusal-only extra cell in a satisfied category also blocks.
  let extra_refusal_transports =
    MatrixCell(
      cell_id: "cell-transports-refusal",
      category: "transports",
      candidate_id: active_candidate,
      positive_observed: True,
      refusal_only: True,
    )
  let refusal_masked =
    complete_cells()
    |> list.append([extra_refusal_transports])
  let refusal_decision = evaluate(refusal_masked, True, True, reviews, True)
  refusal_decision.mcp_full_dev_ready |> should.equal(False)

  // A cell hiding under an unknown category name is rejected outright.
  let unknown_category =
    MatrixCell(
      cell_id: "cell-unlisted",
      category: "unlisted",
      candidate_id: active_candidate,
      positive_observed: True,
      refusal_only: False,
    )
  let unknown_masked =
    complete_cells()
    |> list.append([unknown_category])
  let unknown_decision = evaluate(unknown_masked, True, True, reviews, True)
  unknown_decision.mcp_full_dev_ready |> should.equal(False)
  unknown_decision.system_admission |> should.equal(not_admitted)
}

pub fn grant_cannot_admit_failing_matrix_cell_test() {
  let reviews = passing_reviews()

  // A sovereign grant with a failing full-category cell must still force
  // `"NOT_ADMITTED"`, even when both verification keys and reviews pass.
  let failing_transports =
    all_core_cells()
    |> list.append(
      list.map(all_full_cells(), fn(cell) {
        case cell.category == "transports" {
          True -> MatrixCell(..cell, positive_observed: False)
          False -> cell
        }
      }),
    )
  let full_decision = evaluate(failing_transports, True, True, reviews, True)
  full_decision.mcp_full_dev_ready |> should.equal(False)
  full_decision.system_admission |> should.equal(not_admitted)

  // A sovereign grant with a failing core cell must also force `"NOT_ADMITTED"`.
  let failing_core =
    all_full_cells()
    |> list.append([
      core_cell("core-admission"),
      MatrixCell(
        cell_id: "core-route",
        category: "core",
        candidate_id: active_candidate,
        positive_observed: False,
        refusal_only: False,
      ),
    ])
  let core_decision = evaluate(failing_core, True, True, reviews, True)
  core_decision.core_dev_ready |> should.equal(False)
  core_decision.system_admission |> should.equal(not_admitted)
}
