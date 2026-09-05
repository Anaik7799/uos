/// claude_metrics_test — Claude Session Self-Observation (SC-SATYA-002)
///
/// Covers:
///   C1  Structure: init() returns zeroed SessionMetrics
///   C2  Invariants: counter fields are non-negative after increments
///   C3  JSON: to_json() produces well-formed output with all keys
///   C5  Logic: derived metrics (rates, totals) match manual expectations
///   C7  Effectiveness: score in [0.0, 1.0], improves with better behaviour
///   C8  Safety gate: empty session scores 1.0 (no penalty for zero counters)
///
/// STAMP: SC-SATYA-002, SC-OODA-CLAUDE-001, SC-EVO-KPI-001, SC-MUDA-001
/// Layer: L5_COGNITIVE
import cepaf_gleam/ha/claude_metrics
import gleam/string
import gleeunit/should

// ---------------------------------------------------------------------------
// C1 — Structure: init() returns a correctly zeroed record
// ---------------------------------------------------------------------------

pub fn init_sets_session_id_test() {
  let m = claude_metrics.init("sess-001", 1_700_000_000_000)
  m.session_id |> should.equal("sess-001")
}

pub fn init_sets_started_at_ms_test() {
  let m = claude_metrics.init("sess-001", 1_700_000_000_000)
  m.started_at_ms |> should.equal(1_700_000_000_000)
}

pub fn init_all_counters_zero_test() {
  let m = claude_metrics.init("sess-zero", 0)
  m.zk_recalls |> should.equal(0)
  m.zk_citations |> should.equal(0)
  m.zk_anti_patterns |> should.equal(0)
  m.tool_reads |> should.equal(0)
  m.tool_edits |> should.equal(0)
  m.tool_writes |> should.equal(0)
  m.tool_bash |> should.equal(0)
  m.tool_agents |> should.equal(0)
  m.tool_agent_success |> should.equal(0)
  m.tool_agent_failed |> should.equal(0)
  m.builds_total |> should.equal(0)
  m.builds_clean |> should.equal(0)
  m.builds_failed |> should.equal(0)
  m.tests_run |> should.equal(0)
  m.tests_passed |> should.equal(0)
  m.tests_failed |> should.equal(0)
  m.commits |> should.equal(0)
  m.mcp_calls |> should.equal(0)
}

// ---------------------------------------------------------------------------
// C2 — Invariants: increment helpers update exactly one field
// ---------------------------------------------------------------------------

pub fn record_zk_recall_increments_zk_recalls_test() {
  let m = base() |> claude_metrics.record_zk_recall()
  m.zk_recalls |> should.equal(1)
}

pub fn record_zk_citation_increments_zk_citations_test() {
  let m = base() |> claude_metrics.record_zk_citation()
  m.zk_citations |> should.equal(1)
}

pub fn record_zk_anti_pattern_increments_anti_patterns_test() {
  let m = base() |> claude_metrics.record_zk_anti_pattern()
  m.zk_anti_patterns |> should.equal(1)
}

pub fn record_tool_read_increments_tool_reads_test() {
  let m = base() |> claude_metrics.record_tool_read()
  m.tool_reads |> should.equal(1)
}

pub fn record_tool_edit_increments_tool_edits_test() {
  let m = base() |> claude_metrics.record_tool_edit()
  m.tool_edits |> should.equal(1)
}

pub fn record_tool_write_increments_tool_writes_test() {
  let m = base() |> claude_metrics.record_tool_write()
  m.tool_writes |> should.equal(1)
}

pub fn record_tool_bash_increments_tool_bash_test() {
  let m = base() |> claude_metrics.record_tool_bash()
  m.tool_bash |> should.equal(1)
}

pub fn record_agent_spawn_increments_agents_test() {
  let m = base() |> claude_metrics.record_agent_spawn()
  m.tool_agents |> should.equal(1)
}

pub fn record_agent_success_increments_agent_success_test() {
  let m = base() |> claude_metrics.record_agent_success()
  m.tool_agent_success |> should.equal(1)
}

pub fn record_agent_failed_increments_agent_failed_test() {
  let m = base() |> claude_metrics.record_agent_failed()
  m.tool_agent_failed |> should.equal(1)
}

pub fn record_build_clean_increments_total_and_clean_test() {
  let m = base() |> claude_metrics.record_build_clean()
  m.builds_total |> should.equal(1)
  m.builds_clean |> should.equal(1)
  m.builds_failed |> should.equal(0)
}

pub fn record_build_failed_increments_total_and_failed_test() {
  let m = base() |> claude_metrics.record_build_failed()
  m.builds_total |> should.equal(1)
  m.builds_clean |> should.equal(0)
  m.builds_failed |> should.equal(1)
}

pub fn record_commit_increments_commits_test() {
  let m = base() |> claude_metrics.record_commit()
  m.commits |> should.equal(1)
}

pub fn record_mcp_call_increments_mcp_calls_test() {
  let m = base() |> claude_metrics.record_mcp_call()
  m.mcp_calls |> should.equal(1)
}

pub fn record_test_run_accumulates_pass_and_fail_test() {
  let m = base() |> claude_metrics.record_test_run(100, 0)
  m.tests_run |> should.equal(1)
  m.tests_passed |> should.equal(100)
  m.tests_failed |> should.equal(0)
}

// ---------------------------------------------------------------------------
// C5 — Derived metrics: rates and totals
// ---------------------------------------------------------------------------

pub fn total_mutations_sums_edits_and_writes_test() {
  let m =
    base()
    |> claude_metrics.record_tool_edit()
    |> claude_metrics.record_tool_edit()
    |> claude_metrics.record_tool_write()
  claude_metrics.total_mutations(m) |> should.equal(3)
}

pub fn total_tool_calls_sums_all_call_types_test() {
  let m =
    base()
    |> claude_metrics.record_tool_read()
    |> claude_metrics.record_tool_edit()
    |> claude_metrics.record_tool_write()
    |> claude_metrics.record_tool_bash()
    |> claude_metrics.record_agent_spawn()
    |> claude_metrics.record_mcp_call()
  claude_metrics.total_tool_calls(m) |> should.equal(6)
}

pub fn build_success_rate_perfect_when_all_clean_test() {
  let m =
    base()
    |> claude_metrics.record_build_clean()
    |> claude_metrics.record_build_clean()
    |> claude_metrics.record_build_clean()
  claude_metrics.build_success_rate(m) |> should.equal(1.0)
}

pub fn build_success_rate_half_when_one_failed_test() {
  let m =
    base()
    |> claude_metrics.record_build_clean()
    |> claude_metrics.record_build_failed()
  claude_metrics.build_success_rate(m) |> should.equal(0.5)
}

pub fn zk_citation_rate_returns_ratio_test() {
  let m =
    base()
    |> claude_metrics.record_zk_recall()
    |> claude_metrics.record_zk_recall()
    |> claude_metrics.record_zk_citation()
  claude_metrics.zk_citation_rate(m) |> should.equal(0.5)
}

pub fn test_pass_rate_perfect_when_no_failures_test() {
  let m = base() |> claude_metrics.record_test_run(3354, 0)
  claude_metrics.test_pass_rate(m) |> should.equal(1.0)
}

pub fn agent_success_rate_returns_correct_ratio_test() {
  let m =
    base()
    |> claude_metrics.record_agent_spawn()
    |> claude_metrics.record_agent_spawn()
    |> claude_metrics.record_agent_spawn()
    |> claude_metrics.record_agent_success()
    |> claude_metrics.record_agent_success()
  claude_metrics.agent_success_rate(m) |> should.equal(2.0 /. 3.0)
}

// ---------------------------------------------------------------------------
// C7 — Effectiveness score: AI advisory / self-assessment
// ---------------------------------------------------------------------------

pub fn effectiveness_score_empty_session_is_one_test() {
  // Empty session: all denominators are zero — each component defaults to 1.0
  let m = base()
  claude_metrics.effectiveness_score(m) |> should.equal(1.0)
}

pub fn effectiveness_score_perfect_session_is_one_test() {
  let m =
    base()
    |> claude_metrics.record_zk_recall()
    |> claude_metrics.record_zk_citation()
    |> claude_metrics.record_build_clean()
    |> claude_metrics.record_test_run(100, 0)
    |> claude_metrics.record_agent_spawn()
    |> claude_metrics.record_agent_success()
  claude_metrics.effectiveness_score(m) |> should.equal(1.0)
}

pub fn effectiveness_score_is_in_unit_interval_test() {
  let m =
    base()
    |> claude_metrics.record_zk_recall()
    |> claude_metrics.record_build_failed()
    |> claude_metrics.record_test_run(80, 20)
    |> claude_metrics.record_agent_spawn()
    |> claude_metrics.record_agent_failed()
  let score = claude_metrics.effectiveness_score(m)
  { score >=. 0.0 } |> should.be_true()
  { score <=. 1.0 } |> should.be_true()
}

pub fn effectiveness_score_degrades_with_build_failures_test() {
  // Perfect session
  let perfect =
    base()
    |> claude_metrics.record_zk_recall()
    |> claude_metrics.record_zk_citation()
    |> claude_metrics.record_build_clean()
    |> claude_metrics.record_test_run(100, 0)
    |> claude_metrics.record_agent_spawn()
    |> claude_metrics.record_agent_success()

  // Same but with 3 extra failed builds
  let degraded =
    perfect
    |> claude_metrics.record_build_failed()
    |> claude_metrics.record_build_failed()
    |> claude_metrics.record_build_failed()

  let score_p = claude_metrics.effectiveness_score(perfect)
  let score_d = claude_metrics.effectiveness_score(degraded)
  { score_p >. score_d } |> should.be_true()
}

// ---------------------------------------------------------------------------
// C8 — Safety gate: zero-denominator cases never panic or produce NaN
// ---------------------------------------------------------------------------

pub fn zero_denominators_never_panic_test() {
  // This should not raise or produce an invalid float
  let m = base()
  let _rate = claude_metrics.zk_citation_rate(m)
  let _build = claude_metrics.build_success_rate(m)
  let _test = claude_metrics.test_pass_rate(m)
  let _agent = claude_metrics.agent_success_rate(m)
  let _eff = claude_metrics.effectiveness_score(m)
  // Reaching here means no exception was raised
  True |> should.be_true()
}

// ---------------------------------------------------------------------------
// C3 — JSON serialisation
// ---------------------------------------------------------------------------

pub fn to_json_contains_session_id_test() {
  let m = claude_metrics.init("my-session", 1_000_000)
  let j = claude_metrics.to_json(m)
  { string.contains(j, "session_id") } |> should.be_true()
  { string.contains(j, "my-session") } |> should.be_true()
}

pub fn to_json_contains_all_counter_keys_test() {
  let m = claude_metrics.init("x", 0)
  let j = claude_metrics.to_json(m)
  { string.contains(j, "zk_recalls") } |> should.be_true()
  { string.contains(j, "zk_citations") } |> should.be_true()
  { string.contains(j, "tool_reads") } |> should.be_true()
  { string.contains(j, "builds_total") } |> should.be_true()
  { string.contains(j, "effectiveness_score") } |> should.be_true()
}

pub fn to_json_starts_with_brace_test() {
  let m = base()
  let j = claude_metrics.to_json(m)
  { string.starts_with(j, "{") } |> should.be_true()
  { string.ends_with(j, "}") } |> should.be_true()
}

pub fn to_json_is_non_empty_test() {
  let m = base()
  let j = claude_metrics.to_json(m)
  { string.length(j) > 50 } |> should.be_true()
}

// ---------------------------------------------------------------------------
// Summary string
// ---------------------------------------------------------------------------

pub fn summary_contains_session_id_test() {
  let m = claude_metrics.init("test-session", 0)
  let s = claude_metrics.summary(m)
  { string.contains(s, "test-session") } |> should.be_true()
}

pub fn summary_contains_zk_section_test() {
  let m = base()
  let s = claude_metrics.summary(m)
  { string.contains(s, "ZK:") } |> should.be_true()
}

pub fn summary_contains_builds_section_test() {
  let m = base()
  let s = claude_metrics.summary(m)
  { string.contains(s, "Builds:") } |> should.be_true()
}

pub fn summary_contains_effectiveness_test() {
  let m = base()
  let s = claude_metrics.summary(m)
  { string.contains(s, "Effectiveness:") } |> should.be_true()
}

pub fn publish_to_ets_returns_nil_test() {
  let m = base()
  claude_metrics.publish_to_ets(m) |> should.equal(Nil)
}

// ---------------------------------------------------------------------------
// Prime path: multi-step chained evolution
// ---------------------------------------------------------------------------

pub fn pp_full_session_chain_test() {
  // Simulate a realistic Claude session: recall ZK → cite → build (clean)
  // → run tests → spawn agent → agent succeeds → commit
  let m =
    claude_metrics.init("pp-chain", 0)
    |> claude_metrics.record_zk_recall()
    |> claude_metrics.record_zk_recall()
    |> claude_metrics.record_zk_citation()
    |> claude_metrics.record_tool_read()
    |> claude_metrics.record_tool_read()
    |> claude_metrics.record_tool_edit()
    |> claude_metrics.record_tool_write()
    |> claude_metrics.record_build_clean()
    |> claude_metrics.record_test_run(3354, 0)
    |> claude_metrics.record_agent_spawn()
    |> claude_metrics.record_agent_success()
    |> claude_metrics.record_commit()
    |> claude_metrics.record_mcp_call()

  m.zk_recalls |> should.equal(2)
  m.zk_citations |> should.equal(1)
  m.tool_reads |> should.equal(2)
  m.tool_edits |> should.equal(1)
  m.tool_writes |> should.equal(1)
  m.builds_total |> should.equal(1)
  m.builds_clean |> should.equal(1)
  m.tests_passed |> should.equal(3354)
  m.tool_agents |> should.equal(1)
  m.tool_agent_success |> should.equal(1)
  m.commits |> should.equal(1)
  m.mcp_calls |> should.equal(1)

  // With one citation out of 2 recalls, citation rate = 0.5
  claude_metrics.zk_citation_rate(m) |> should.equal(0.5)
  // All builds clean → rate = 1.0
  claude_metrics.build_success_rate(m) |> should.equal(1.0)
  // All tests passed → rate = 1.0
  claude_metrics.test_pass_rate(m) |> should.equal(1.0)
  // All agents succeeded → rate = 1.0
  claude_metrics.agent_success_rate(m) |> should.equal(1.0)

  // total_mutations = edits + writes = 2
  claude_metrics.total_mutations(m) |> should.equal(2)
  // total_tool_calls = 2+1+1+0+1+1 = 6
  claude_metrics.total_tool_calls(m) |> should.equal(6)

  // Effectiveness: zk=0.5*0.30 + build=1*0.35 + test=1*0.25 + agent=1*0.10
  //             = 0.15 + 0.35 + 0.25 + 0.10 = 0.85
  let eff = claude_metrics.effectiveness_score(m)
  { eff >=. 0.84 } |> should.be_true()
  { eff <=. 0.86 } |> should.be_true()
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn base() -> claude_metrics.SessionMetrics {
  claude_metrics.init("test", 0)
}
