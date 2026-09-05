//// [C3I-SIL6-MSTS] MODULE CONTRACT
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/testing/test_dashboard</module>
////     <fsharp-lineage>Cepaf.Testing.TestDashboard</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L1_ATOMIC_DEBUG</layer>
////     <mesh-domain>Real-time Test Execution Dashboard Model</mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>HIGH</criticality>
////     <stamp-controls>SC-GLM-UI-001, SC-GLM-UI-009, SC-MATH-COV-001, SC-MATH-COV-005</stamp-controls>
////   </compliance>
//// </c3i-module>
////
//// Test Dashboard Data Model — tracks test execution in real-time.
//// Per-tab summaries, per-element KPIs (entropy, CCM, D_EA, ITQS),
//// corrective action tracking, duration tracking.
//// STAMP: SC-GLM-CORE-002, SC-GLM-CORE-003, SC-MATH-COV-001..008

import cepaf_gleam/testing/coverage_math.{
  type Grade, GradeA, GradeB, GradeC, GradeD,
}
import cepaf_gleam/ui/domain.{
  type FractalLayer, L0Constitutional, L1AtomicDebug, L2Component, L3Transaction,
  L4System, L5Cognitive, L6Ecosystem, L7Federation, layer_to_string,
}
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}

// =============================================================================
// Test Status Types
// =============================================================================

pub type TestStatus {
  TestPending
  TestRunning
  TestPassed
  TestFailed(reason: String)
  TestSkipped
}

pub type TestPhase {
  PhaseSynthetic
  PhaseRealtime
  PhaseSystemOps
  PhaseZenohOtel
}

// =============================================================================
// Per-Element KPIs (math gate metrics)
// =============================================================================

pub type ElementKpi {
  ElementKpi(
    element_name: String,
    entropy: Float,
    ccm: Float,
    d_ea: Float,
    itqs: Float,
    fsi: Float,
    grade: Grade,
  )
}

pub type CorrectiveAction {
  CorrectiveAction(
    id: String,
    element: String,
    description: String,
    severity: ActionSeverity,
    status: ActionStatus,
    triggered_at: Int,
  )
}

pub type ActionSeverity {
  ActionCritical
  ActionHigh
  ActionMedium
  ActionLow
}

pub type ActionStatus {
  ActionOpen
  ActionInProgress
  ActionResolved
  ActionDismissed
}

// =============================================================================
// Per-Tab Test Summary
// =============================================================================

pub type TabSummary {
  TabSummary(
    tab_name: String,
    fractal_layer: FractalLayer,
    tests_total: Int,
    tests_passed: Int,
    tests_failed: Int,
    tests_pending: Int,
    tests_running: Int,
    tests_skipped: Int,
    duration_ms: Int,
    avg_duration_ms: Float,
    kpis: List(ElementKpi),
    corrective_actions: List(CorrectiveAction),
  )
}

// =============================================================================
// Test Execution Record
// =============================================================================

pub type TestRecord {
  TestRecord(
    id: String,
    name: String,
    tab: String,
    status: TestStatus,
    duration_ms: Int,
    started_at: Int,
    finished_at: Option(Int),
  )
}

// =============================================================================
// Test Dashboard Model
// =============================================================================

pub type TestDashboardModel {
  TestDashboardModel(
    phase: TestPhase,
    phase_start_ms: Int,
    phase_elapsed_ms: Int,
    total_duration_ms: Int,
    tabs: List(TabSummary),
    test_records: List(TestRecord),
    total_tests: Int,
    total_passed: Int,
    total_failed: Int,
    total_pending: Int,
    total_running: Int,
    total_skipped: Int,
    overall_kpi: ElementKpi,
    corrective_actions: List(CorrectiveAction),
    cycle_count: Int,
    is_complete: Bool,
    last_update_ms: Int,
  )
}

// =============================================================================
// Init — empty dashboard, synthetic phase
// =============================================================================

pub fn init() -> TestDashboardModel {
  let default_kpi =
    ElementKpi(
      element_name: "overall",
      entropy: 0.0,
      ccm: 0.0,
      d_ea: 1.0,
      itqs: 0.0,
      fsi: 0.0,
      grade: GradeD,
    )

  TestDashboardModel(
    phase: PhaseSynthetic,
    phase_start_ms: 0,
    phase_elapsed_ms: 0,
    total_duration_ms: 0,
    tabs: [],
    test_records: [],
    total_tests: 0,
    total_passed: 0,
    total_failed: 0,
    total_pending: 0,
    total_running: 0,
    total_skipped: 0,
    overall_kpi: default_kpi,
    corrective_actions: [],
    cycle_count: 0,
    is_complete: False,
    last_update_ms: 0,
  )
}

// =============================================================================
// Initialize tabs for all 8 fractal layers
// =============================================================================

pub fn init_all_tabs() -> List(TabSummary) {
  let layers = [
    L0Constitutional,
    L1AtomicDebug,
    L2Component,
    L3Transaction,
    L4System,
    L5Cognitive,
    L6Ecosystem,
    L7Federation,
  ]

  list.map(layers, fn(layer: FractalLayer) {
    TabSummary(
      tab_name: layer_to_string(layer),
      fractal_layer: layer,
      tests_total: 0,
      tests_passed: 0,
      tests_failed: 0,
      tests_pending: 0,
      tests_running: 0,
      tests_skipped: 0,
      duration_ms: 0,
      avg_duration_ms: 0.0,
      kpis: [],
      corrective_actions: [],
    )
  })
}

pub fn init_with_tabs() -> TestDashboardModel {
  let model = init()
  TestDashboardModel(..model, tabs: init_all_tabs())
}

// =============================================================================
// Update functions — event-driven state transitions
// =============================================================================

pub fn start_test(
  model: TestDashboardModel,
  record: TestRecord,
  now_ms: Int,
) -> TestDashboardModel {
  let updated_records = [record, ..model.test_records]
  let updated_tabs = update_tab_for_test(model.tabs, record, True)

  TestDashboardModel(
    ..model,
    test_records: updated_records,
    tabs: updated_tabs,
    total_running: model.total_running + 1,
    total_pending: model.total_pending - 1,
    last_update_ms: now_ms,
  )
}

pub fn finish_test(
  model: TestDashboardModel,
  test_id: String,
  passed: Bool,
  reason: String,
  duration_ms: Int,
  now_ms: Int,
) -> TestDashboardModel {
  let updated_records =
    list.map(model.test_records, fn(r: TestRecord) {
      case r.id == test_id {
        True ->
          TestRecord(
            ..r,
            status: case passed {
              True -> TestPassed
              False -> TestFailed(reason)
            },
            duration_ms: duration_ms,
            finished_at: Some(now_ms),
          )
        False -> r
      }
    })

  let finished_record =
    list.find(model.test_records, fn(r: TestRecord) { r.id == test_id })

  let tab_name = case finished_record {
    Ok(r) -> r.tab
    Error(_) -> ""
  }

  let updated_tabs =
    update_tab_on_finish(model.tabs, tab_name, passed, duration_ms)

  let new_passed = case passed {
    True -> model.total_passed + 1
    False -> model.total_passed
  }
  let new_failed = case passed {
    False -> model.total_failed + 1
    True -> model.total_failed
  }

  let overall_kpi = recompute_overall_kpi(updated_tabs)

  TestDashboardModel(
    ..model,
    test_records: updated_records,
    tabs: updated_tabs,
    total_passed: new_passed,
    total_failed: new_failed,
    total_running: model.total_running - 1,
    overall_kpi: overall_kpi,
    last_update_ms: now_ms,
  )
}

pub fn advance_phase(
  model: TestDashboardModel,
  new_phase: TestPhase,
  now_ms: Int,
) -> TestDashboardModel {
  TestDashboardModel(
    ..model,
    phase: new_phase,
    phase_start_ms: now_ms,
    phase_elapsed_ms: 0,
    cycle_count: model.cycle_count + 1,
    last_update_ms: now_ms,
  )
}

pub fn complete_cycle(
  model: TestDashboardModel,
  now_ms: Int,
) -> TestDashboardModel {
  let total =
    model.total_passed
    + model.total_failed
    + model.total_pending
    + model.total_running
    + model.total_skipped

  let is_done = model.total_running == 0 && model.total_pending == 0

  let corrective = generate_corrective_actions(model.tabs)

  TestDashboardModel(
    ..model,
    total_duration_ms: now_ms - model.phase_start_ms,
    total_tests: total,
    corrective_actions: corrective,
    is_complete: is_done,
    last_update_ms: now_ms,
  )
}

// =============================================================================
// Tab update helpers
// =============================================================================

fn update_tab_for_test(
  tabs: List(TabSummary),
  record: TestRecord,
  is_start: Bool,
) -> List(TabSummary) {
  list.map(tabs, fn(tab: TabSummary) {
    case tab.tab_name == record.tab {
      True ->
        TabSummary(
          ..tab,
          tests_total: tab.tests_total + 1,
          tests_running: case is_start {
            True -> tab.tests_running + 1
            False -> tab.tests_running
          },
          tests_pending: case is_start {
            True -> tab.tests_pending - 1
            False -> tab.tests_pending
          },
        )
      False -> tab
    }
  })
}

fn update_tab_on_finish(
  tabs: List(TabSummary),
  tab_name: String,
  passed: Bool,
  duration_ms: Int,
) -> List(TabSummary) {
  list.map(tabs, fn(tab: TabSummary) {
    case tab.tab_name == tab_name {
      True -> {
        let new_passed = case passed {
          True -> tab.tests_passed + 1
          False -> tab.tests_passed
        }
        let new_failed = case passed {
          False -> tab.tests_failed + 1
          True -> tab.tests_failed
        }
        let new_total_duration = tab.duration_ms + duration_ms
        let completed_tests = new_passed + new_failed
        let new_avg = case completed_tests > 0 {
          True ->
            int.to_float(new_total_duration) /. int.to_float(completed_tests)
          False -> 0.0
        }

        TabSummary(
          ..tab,
          tests_passed: new_passed,
          tests_failed: new_failed,
          tests_running: tab.tests_running - 1,
          duration_ms: new_total_duration,
          avg_duration_ms: new_avg,
        )
      }
      False -> tab
    }
  })
}

// =============================================================================
// KPI computation
// =============================================================================

pub fn make_kpi(
  name: String,
  entropy: Float,
  ccm: Float,
  d_ea: Float,
  fsi: Float,
) -> ElementKpi {
  let itqs = compute_itqs(entropy, ccm, d_ea, fsi)
  let grade = grade_from_itqs(itqs)

  ElementKpi(
    element_name: name,
    entropy: entropy,
    ccm: ccm,
    d_ea: d_ea,
    itqs: itqs,
    fsi: fsi,
    grade: grade,
  )
}

fn compute_itqs(entropy: Float, ccm: Float, d_ea: Float, fsi: Float) -> Float {
  let h_norm = case entropy >=. 2.5 {
    True -> 1.0
    False -> entropy /. 2.5
  }
  let d_norm = case d_ea <=. 0.1 {
    True -> 1.0
    False -> 1.0 -. d_ea
  }

  0.25 *. h_norm +. 0.35 *. ccm +. 0.25 *. d_norm +. 0.15 *. fsi
}

fn grade_from_itqs(itqs: Float) -> Grade {
  case itqs {
    s if s >=. 0.95 -> GradeA
    s if s >=. 0.85 -> GradeB
    s if s >=. 0.7 -> GradeC
    _ -> GradeD
  }
}

fn recompute_overall_kpi(tabs: List(TabSummary)) -> ElementKpi {
  let all_kpis = list.flat_map(tabs, fn(tab: TabSummary) { tab.kpis })

  case all_kpis {
    [] ->
      ElementKpi(
        element_name: "overall",
        entropy: 0.0,
        ccm: 0.0,
        d_ea: 1.0,
        itqs: 0.0,
        fsi: 0.0,
        grade: GradeD,
      )
    _ -> {
      let count = int.to_float(list.length(all_kpis))
      let avg_entropy =
        list.fold(all_kpis, 0.0, fn(acc: Float, k: ElementKpi) {
          acc +. k.entropy
        })
        /. count
      let avg_ccm =
        list.fold(all_kpis, 0.0, fn(acc: Float, k: ElementKpi) { acc +. k.ccm })
        /. count
      let avg_d_ea =
        list.fold(all_kpis, 0.0, fn(acc: Float, k: ElementKpi) { acc +. k.d_ea })
        /. count
      let avg_fsi =
        list.fold(all_kpis, 0.0, fn(acc: Float, k: ElementKpi) { acc +. k.fsi })
        /. count

      make_kpi("overall", avg_entropy, avg_ccm, avg_d_ea, avg_fsi)
    }
  }
}

// =============================================================================
// Corrective action generation
// =============================================================================

fn generate_corrective_actions(tabs: List(TabSummary)) -> List(CorrectiveAction) {
  list.flat_map(tabs, fn(tab: TabSummary) {
    let actions = case tab.tests_failed > 0 {
      True -> [
        CorrectiveAction(
          id: "CA-" <> tab.tab_name <> "-FAIL",
          element: tab.tab_name,
          description: tab.tab_name
            <> " has "
            <> int.to_string(tab.tests_failed)
            <> " failed test(s)",
          severity: case tab.tests_failed {
            n if n >= 5 -> ActionCritical
            n if n >= 3 -> ActionHigh
            n if n >= 1 -> ActionMedium
            _ -> ActionLow
          },
          status: ActionOpen,
          triggered_at: 0,
        ),
      ]
      False -> []
    }

    let kpi_actions =
      list.flat_map(tab.kpis, fn(kpi: ElementKpi) {
        case kpi.itqs <. 0.85 {
          True -> [
            CorrectiveAction(
              id: "CA-" <> kpi.element_name <> "-ITQS",
              element: kpi.element_name,
              description: kpi.element_name
                <> " ITQS below threshold: "
                <> float.to_string(kpi.itqs),
              severity: case kpi.itqs {
                s if s <. 0.5 -> ActionCritical
                s if s <. 0.7 -> ActionHigh
                s if s <. 0.85 -> ActionMedium
                _ -> ActionLow
              },
              status: ActionOpen,
              triggered_at: 0,
            ),
          ]
          False -> []
        }
      })

    list.append(actions, kpi_actions)
  })
}

// =============================================================================
// Query functions
// =============================================================================

pub fn tab_pass_rate(tab: TabSummary) -> Float {
  let completed = tab.tests_passed + tab.tests_failed
  case completed > 0 {
    True -> int.to_float(tab.tests_passed) /. int.to_float(completed)
    False -> 1.0
  }
}

pub fn overall_pass_rate(model: TestDashboardModel) -> Float {
  let completed = model.total_passed + model.total_failed
  case completed > 0 {
    True -> int.to_float(model.total_passed) /. int.to_float(completed)
    False -> 1.0
  }
}

pub fn phase_duration_label(phase: TestPhase) -> String {
  case phase {
    PhaseSynthetic -> "Synthetic Data Tests (3 min)"
    PhaseRealtime -> "Real-time System Data (3 min)"
    PhaseSystemOps -> "System Operation Tests (2 min)"
    PhaseZenohOtel -> "Zenoh/OTel Verification (2 min)"
  }
}

pub fn phase_target_ms(phase: TestPhase) -> Int {
  case phase {
    PhaseSynthetic -> 180_000
    PhaseRealtime -> 180_000
    PhaseSystemOps -> 120_000
    PhaseZenohOtel -> 120_000
  }
}

pub fn test_status_label(status: TestStatus) -> String {
  case status {
    TestPending -> "PENDING"
    TestRunning -> "RUNNING"
    TestPassed -> "PASS"
    TestFailed(_) -> "FAIL"
    TestSkipped -> "SKIP"
  }
}

pub fn test_status_color(status: TestStatus) -> String {
  case status {
    TestPending -> "dim"
    TestRunning -> "blue"
    TestPassed -> "green"
    TestFailed(_) -> "red"
    TestSkipped -> "yellow"
  }
}

pub fn action_severity_label(severity: ActionSeverity) -> String {
  case severity {
    ActionCritical -> "CRITICAL"
    ActionHigh -> "HIGH"
    ActionMedium -> "MEDIUM"
    ActionLow -> "LOW"
  }
}

pub fn action_severity_color(severity: ActionSeverity) -> String {
  case severity {
    ActionCritical -> "red"
    ActionHigh -> "red"
    ActionMedium -> "yellow"
    ActionLow -> "cyan"
  }
}

pub fn action_status_label(status: ActionStatus) -> String {
  case status {
    ActionOpen -> "OPEN"
    ActionInProgress -> "IN_PROGRESS"
    ActionResolved -> "RESOLVED"
    ActionDismissed -> "DISMISSED"
  }
}

pub fn grade_label(grade: Grade) -> String {
  case grade {
    GradeA -> "A"
    GradeB -> "B"
    GradeC -> "C"
    GradeD -> "D"
  }
}

pub fn grade_color(grade: Grade) -> String {
  case grade {
    GradeA -> "green"
    GradeB -> "cyan"
    GradeC -> "yellow"
    GradeD -> "red"
  }
}

// =============================================================================
// Build a test record
// =============================================================================

pub fn make_test_record(
  id: String,
  name: String,
  tab: String,
  now_ms: Int,
) -> TestRecord {
  TestRecord(
    id: id,
    name: name,
    tab: tab,
    status: TestPending,
    duration_ms: 0,
    started_at: now_ms,
    finished_at: None,
  )
}

// =============================================================================
// Summary report string
// =============================================================================

pub fn summary_report(model: TestDashboardModel) -> String {
  let pass_rate = overall_pass_rate(model)
  let pass_pct = float.round(pass_rate *. 100.0) |> int.to_string

  "=== TEST DASHBOARD SUMMARY ===\n"
  <> "Phase: "
  <> phase_duration_label(model.phase)
  <> "\n"
  <> "Cycle: "
  <> int.to_string(model.cycle_count)
  <> "\n"
  <> "Total: "
  <> int.to_string(model.total_tests)
  <> " | Pass: "
  <> int.to_string(model.total_passed)
  <> " | Fail: "
  <> int.to_string(model.total_failed)
  <> " | Pending: "
  <> int.to_string(model.total_pending)
  <> " | Running: "
  <> int.to_string(model.total_running)
  <> " | Skip: "
  <> int.to_string(model.total_skipped)
  <> "\n"
  <> "Pass Rate: "
  <> pass_pct
  <> "%\n"
  <> "Overall ITQS: "
  <> float.to_string(model.overall_kpi.itqs)
  <> " ["
  <> grade_label(model.overall_kpi.grade)
  <> "]\n"
  <> "Corrective Actions: "
  <> int.to_string(list.length(model.corrective_actions))
  <> "\n"
  <> "Complete: "
  <> case model.is_complete {
    True -> "YES"
    False -> "NO"
  }
  <> "\n"
}

// =============================================================================
// Coverage-Driven KPI Update (Batch 5)
// =============================================================================

/// Update the overall KPI from file coverage data.
pub fn update_kpis_from_coverages(
  model: TestDashboardModel,
  overall_ccm: Float,
  overall_entropy: Float,
  overall_d_ea: Float,
  overall_fsi: Float,
) -> TestDashboardModel {
  let h_norm = case overall_entropy >=. 2.5 {
    True -> 1.0
    False -> overall_entropy /. 2.5
  }
  let d_norm = case overall_d_ea <=. 0.1 {
    True -> 1.0
    False -> 1.0 -. overall_d_ea
  }
  let itqs_val =
    0.25
    *. h_norm
    +. 0.35
    *. overall_ccm
    +. 0.25
    *. d_norm
    +. 0.15
    *. overall_fsi
  let grade = case itqs_val >=. 0.95 {
    True -> GradeA
    False ->
      case itqs_val >=. 0.85 {
        True -> GradeB
        False ->
          case itqs_val >=. 0.7 {
            True -> GradeC
            False -> GradeD
          }
      }
  }
  let updated_kpi =
    ElementKpi(
      element_name: "overall_suite",
      entropy: overall_entropy,
      ccm: overall_ccm,
      d_ea: overall_d_ea,
      itqs: itqs_val,
      fsi: overall_fsi,
      grade: grade,
    )
  TestDashboardModel(..model, overall_kpi: updated_kpi)
}
