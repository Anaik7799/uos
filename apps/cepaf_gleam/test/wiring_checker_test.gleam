/// WIRING CHECKER REGRESSION TEST
/// Runs on EVERY gleam test invocation.
/// Fails if coverage drops below 85% or any CRITICAL gap exists.
///
/// SC-WIRE-001: Automated regression gate.
/// This test catches wiring degradation from code generation.
import cepaf_gleam/testing/wiring_checker
import gleeunit/should

/// Master regression: full check must pass
pub fn full_wiring_check_passes_test() {
  let report = wiring_checker.run_full_check()
  report.pass |> should.be_true()
}

/// Coverage must be >= 85%
pub fn coverage_above_85_pct_test() {
  let report = wiring_checker.run_full_check()
  let above = report.coverage_pct >=. 85.0
  above |> should.be_true()
}

/// No CRITICAL gaps allowed
pub fn no_critical_gaps_test() {
  let report = wiring_checker.run_full_check()
  // Filter for CRITICAL severity
  let critical_count = count_severity(report.categories, "CRITICAL")
  critical_count |> should.equal(0)
}

/// NIF bridges must be 100%
pub fn nif_bridges_100_pct_test() {
  let check = wiring_checker.check_nif_coverage()
  check.wired |> should.equal(25)
  check.missing |> should.equal(0)
}

/// Model update exhaustiveness must be 100%
pub fn model_update_100_pct_test() {
  let check = wiring_checker.check_model_update()
  check.missing |> should.equal(0)
}

/// A2UI renderer must cover all 233 components
pub fn a2ui_renderer_233_test() {
  let check = wiring_checker.check_a2ui_renderer()
  check.wired |> should.equal(233)
}

/// Wiring guard must verify 95 connections
pub fn wiring_guard_95_connections_test() {
  let check = wiring_checker.check_wiring_guard()
  check.wired |> should.equal(104)
}

/// Page count must match registry
pub fn page_count_matches_registry_test() {
  let pages = wiring_checker.all_lustre_pages()
  let count = list_len(pages)
  // Must have at least 33 pages (can grow, never shrink)
  let above = count >= 33
  above |> should.be_true()
}

/// Rule engine: Gleam evaluators cover Rust domains
pub fn rule_engine_coverage_test() {
  let check = wiring_checker.check_rule_engine()
  let above = check.wired >= 9
  above |> should.be_true()
}

/// Ruliology: at least 2 structures in Gleam
pub fn ruliology_structures_test() {
  let check = wiring_checker.check_ruliology()
  let above = check.wired >= 2
  above |> should.be_true()
}

/// All 5 agents emit AG-UI events
pub fn all_agents_emit_events_test() {
  let check = wiring_checker.check_agent_event_parity()
  check.wired |> should.equal(5)
}

/// Print report (for CI output)
pub fn print_wiring_report_test() {
  let report = wiring_checker.run_full_check()
  let output = wiring_checker.format_report(report)
  let non_empty = output != ""
  non_empty |> should.be_true()
}

fn count_severity(
  categories: List(wiring_checker.WiringCategory),
  sev: String,
) -> Int {
  do_count_sev(categories, sev, 0)
}

fn do_count_sev(
  cats: List(wiring_checker.WiringCategory),
  sev: String,
  acc: Int,
) -> Int {
  case cats {
    [] -> acc
    [c, ..rest] ->
      case c.severity == sev {
        True -> do_count_sev(rest, sev, acc + 1)
        False -> do_count_sev(rest, sev, acc)
      }
  }
}

fn list_len(l: List(a)) -> Int {
  do_len(l, 0)
}

fn do_len(l: List(a), acc: Int) -> Int {
  case l {
    [] -> acc
    [_, ..rest] -> do_len(rest, acc + 1)
  }
}
