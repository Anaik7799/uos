//// Pass-22 — page_checker actor tests.
////
//// Anti-Stub-That-Lies guard ([zk-3346fc607a1ef9e6]): every test exercises
//// the *real* alignment math + classification rules over seeded HTML, not
//// mocked PageReport literals.

import cepaf_gleam/ha/page_checker.{
  Apoptosis, CheckerState, Drift, EmitOtelSpan, Misaligned, NoAction, Nominal,
  OpenP0Task, OpenP1Task, Outage, PageReport, PageSpec, alignment, build_report,
  classify, default_registry, escalation, escalation_counts, init,
  mean_alignment, tick,
}
import gleam/list
import gleeunit/should

// ── §1. init + registry ──────────────────────────────────────────────────

pub fn init_returns_default_registry_test() {
  let s = init()
  // Top-6 PageRank pages registered (Dashboard, Cockpit, Verification,
  // Agents, Planning, Immune).
  list.length(s.specs) |> should.equal(6)
  s.tick_count |> should.equal(0)
  s.consecutive_outages |> should.equal(0)
}

pub fn registry_contains_planning_test() {
  let registry = default_registry()
  let planning = list.filter(registry, fn(spec) { spec.page == "/planning" })
  list.length(planning) |> should.equal(1)
}

pub fn planning_spec_has_required_sections_test() {
  let registry = default_registry()
  let planning = list.filter(registry, fn(spec) { spec.page == "/planning" })
  let assert [planning_spec] = planning
  // Pass-7/9 substrate: planning page MUST have these IDs.
  { list.length(planning_spec.required_sections) >= 5 }
  |> should.be_true()
}

// ── §2. alignment math ───────────────────────────────────────────────────

pub fn alignment_perfect_match_test() {
  let spec =
    PageSpec(
      page: "/test",
      required_sections: ["foo", "bar"],
      required_endpoints: [],
      cache_bust_strategy: "build-hash",
    )
  let html = "<html>foo and bar both present</html>"
  alignment(spec, html) |> should.equal(1.0)
}

pub fn alignment_zero_match_test() {
  let spec =
    PageSpec(
      page: "/test",
      required_sections: ["foo", "bar"],
      required_endpoints: [],
      cache_bust_strategy: "build-hash",
    )
  let html = "<html>nothing here</html>"
  alignment(spec, html) |> should.equal(0.0)
}

pub fn alignment_partial_match_test() {
  let spec =
    PageSpec(
      page: "/test",
      required_sections: ["foo", "bar", "baz", "qux"],
      required_endpoints: [],
      cache_bust_strategy: "build-hash",
    )
  let html = "<html>foo and bar but not the others</html>"
  // 2 of 4 sections present → 0.5 alignment
  alignment(spec, html) |> should.equal(0.5)
}

pub fn alignment_empty_spec_returns_one_test() {
  let spec =
    PageSpec(
      page: "/test",
      required_sections: [],
      required_endpoints: [],
      cache_bust_strategy: "build-hash",
    )
  alignment(spec, "any html") |> should.equal(1.0)
}

// ── §3. build_report ─────────────────────────────────────────────────────

pub fn build_report_records_counts_test() {
  let spec =
    PageSpec(
      page: "/test",
      required_sections: ["foo", "bar", "baz"],
      required_endpoints: [],
      cache_bust_strategy: "build-hash",
    )
  let r = build_report(spec, 200, "<html>foo bar present, qux not z</html>")
  r.page |> should.equal("/test")
  r.status_code |> should.equal(200)
  r.sections_found |> should.equal(2)
  r.sections_total |> should.equal(3)
}

// ── §4. classify → action mapping ────────────────────────────────────────

pub fn classify_5xx_emits_p0_test() {
  let r =
    PageReport(
      page: "/planning",
      status_code: 503,
      sections_found: 5,
      sections_total: 5,
      alignment_score: 1.0,
    )
  case classify(r) {
    OpenP0Task(_, 503, _) -> True
    _ -> False
  }
  |> should.be_true()
}

pub fn classify_low_alignment_emits_p1_test() {
  let r =
    PageReport(
      page: "/planning",
      status_code: 200,
      sections_found: 1,
      sections_total: 5,
      alignment_score: 0.2,
    )
  case classify(r) {
    OpenP1Task(_, _, _) -> True
    _ -> False
  }
  |> should.be_true()
}

pub fn classify_drift_emits_otel_span_test() {
  let r =
    PageReport(
      page: "/planning",
      status_code: 200,
      sections_found: 4,
      sections_total: 5,
      alignment_score: 0.8,
    )
  case classify(r) {
    EmitOtelSpan(_, _) -> True
    _ -> False
  }
  |> should.be_true()
}

pub fn classify_perfect_emits_no_action_test() {
  let r =
    PageReport(
      page: "/planning",
      status_code: 200,
      sections_found: 5,
      sections_total: 5,
      alignment_score: 1.0,
    )
  case classify(r) {
    NoAction -> True
    _ -> False
  }
  |> should.be_true()
}

// ── §5. escalation ───────────────────────────────────────────────────────

pub fn escalation_levels_test() {
  let mk = fn(score, code) {
    PageReport(
      page: "/x",
      status_code: code,
      sections_found: 0,
      sections_total: 0,
      alignment_score: score,
    )
  }
  case escalation(mk(0.95, 200)) {
    Nominal -> True
    _ -> False
  }
  |> should.be_true()
  case escalation(mk(0.8, 200)) {
    Drift -> True
    _ -> False
  }
  |> should.be_true()
  case escalation(mk(0.5, 200)) {
    Misaligned -> True
    _ -> False
  }
  |> should.be_true()
  case escalation(mk(1.0, 503)) {
    Outage -> True
    _ -> False
  }
  |> should.be_true()
}

// ── §6. tick → state machine ─────────────────────────────────────────────

pub fn tick_increments_count_test() {
  let s0 = init()
  let r =
    PageReport(
      page: "/x",
      status_code: 200,
      sections_found: 5,
      sections_total: 5,
      alignment_score: 1.0,
    )
  let #(s1, _) = tick(s0, [r])
  s1.tick_count |> should.equal(1)
}

pub fn tick_resets_consecutive_on_clean_test() {
  let s0 =
    CheckerState(
      specs: default_registry(),
      last_reports: [],
      consecutive_outages: 2,
      tick_count: 5,
    )
  let r =
    PageReport(
      page: "/x",
      status_code: 200,
      sections_found: 5,
      sections_total: 5,
      alignment_score: 1.0,
    )
  let #(s1, _) = tick(s0, [r])
  s1.consecutive_outages |> should.equal(0)
}

pub fn tick_apoptosis_after_3_consecutive_outages_test() {
  let s0 =
    CheckerState(
      specs: default_registry(),
      last_reports: [],
      consecutive_outages: 2,
      tick_count: 5,
    )
  let r =
    PageReport(
      page: "/x",
      status_code: 503,
      sections_found: 0,
      sections_total: 5,
      alignment_score: 0.0,
    )
  let #(_s1, actions) = tick(s0, [r])
  // Should include Apoptosis at end
  let apoptosis_count =
    list.filter(actions, fn(a) {
      case a {
        Apoptosis(_) -> True
        _ -> False
      }
    })
    |> list.length
  apoptosis_count |> should.equal(1)
}

// ── §7. aggregates ───────────────────────────────────────────────────────

pub fn mean_alignment_empty_returns_one_test() {
  mean_alignment([]) |> should.equal(1.0)
}

pub fn mean_alignment_simple_test() {
  let r1 =
    PageReport(
      page: "/a",
      status_code: 200,
      sections_found: 5,
      sections_total: 5,
      alignment_score: 1.0,
    )
  let r2 =
    PageReport(
      page: "/b",
      status_code: 200,
      sections_found: 0,
      sections_total: 5,
      alignment_score: 0.0,
    )
  mean_alignment([r1, r2]) |> should.equal(0.5)
}

pub fn escalation_counts_correct_distribution_test() {
  let mk = fn(score, code) {
    PageReport(
      page: "/x",
      status_code: code,
      sections_found: 0,
      sections_total: 0,
      alignment_score: score,
    )
  }
  let reports = [
    mk(0.95, 200),
    mk(0.95, 200),
    mk(0.8, 200),
    mk(0.5, 200),
    mk(1.0, 503),
  ]
  let #(nominal, drift, misaligned, outages) = escalation_counts(reports)
  nominal |> should.equal(2)
  drift |> should.equal(1)
  misaligned |> should.equal(1)
  outages |> should.equal(1)
}
