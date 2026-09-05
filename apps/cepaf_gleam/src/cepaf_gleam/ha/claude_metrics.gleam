//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ha/claude_metrics</module>
////     <fsharp-lineage>None — novel self-observation layer (SC-SATYA-002)</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L5_COGNITIVE</layer>
////     <mesh-domain>
////       Claude Session Metrics Tracker — self-observation of Claude's own
////       interaction with the C3I system.  Tracks ZK citations, tool calls,
////       build outcomes, agent spawns, and MCP calls so that the system can
////       observe its own cognitive performance (SC-SATYA-002).
////     </mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>HIGH</criticality>
////     <stamp-controls>
////       SC-SATYA-002, SC-OODA-CLAUDE-001, SC-EVO-KPI-001,
////       SC-GLM-UI-003, SC-MUDA-001
////     </stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective">
////       Raw interaction counters ↪ typed SessionMetrics ADT.
////       All arithmetic is pure; no panics; effectiveness score clamped
////       to [0.0, 1.0].  publish_to_ets is a side-effect boundary that
////       callers may replace with a real ETS write via Erlang FFI.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// CLAUDE SESSION METRICS TRACKER — आत्म-अवलोकन (Self-Observation)
////
//// "ज्ञानेन तु तदज्ञानं येषां नाशितमात्मनः" — By knowledge, ignorance is
//// destroyed.  For them, knowledge shines like the sun. (Gita 5.16)
////
//// The system must observe itself — not just the world.
////   • How many times did Claude search the Zettelkasten?
////   • Did Claude cite holon IDs in responses? (SC-ZK-IMP-002)
////   • How many builds were clean vs failed? (SC-FUNC-001)
////   • How many agents were spawned and did they succeed?
////   • How many MCP tool calls were made?
////
//// This module is PURE (all functions side-effect free except publish_to_ets).
//// Callers are responsible for persisting the SessionMetrics value.
////
//// STAMP: SC-SATYA-002, SC-OODA-CLAUDE-001, SC-EVO-KPI-001

import cepaf_gleam/substrate/beam_cache
import gleam/float
import gleam/int
import gleam/string

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

/// Accumulated counters for one Claude agent session.
///
/// All counters start at zero; use the `record_*` helpers to increment them.
/// The record is pure data — ownership stays with the caller.
pub type SessionMetrics {
  SessionMetrics(
    /// Unique identifier for this session (e.g. ISO-8601 timestamp string).
    session_id: String,
    /// Unix-epoch millisecond at which the session started.
    started_at_ms: Int,
    // -----------------------------------------------------------------------
    // Zettelkasten recall (SC-ZK-IMP-001..006)
    // -----------------------------------------------------------------------
    /// Number of ZK `knowledge-search` queries executed.
    zk_recalls: Int,
    /// Number of holon IDs explicitly cited in a response.
    zk_citations: Int,
    /// Number of anti-patterns detected from ZK recall and explicitly avoided.
    zk_anti_patterns: Int,
    // -----------------------------------------------------------------------
    // Tool call counters
    // -----------------------------------------------------------------------
    /// Calls to the Read tool.
    tool_reads: Int,
    /// Calls to the Edit tool.
    tool_edits: Int,
    /// Calls to the Write tool.
    tool_writes: Int,
    /// Calls to the Bash tool.
    tool_bash: Int,
    /// Sub-agent spawns (Agent tool calls).
    tool_agents: Int,
    /// Sub-agents that completed without error.
    tool_agent_success: Int,
    /// Sub-agents that terminated with an error.
    tool_agent_failed: Int,
    // -----------------------------------------------------------------------
    // Build metrics (SC-FUNC-001 — system MUST compile at all times)
    // -----------------------------------------------------------------------
    /// Total `gleam build` invocations.
    builds_total: Int,
    /// Builds that produced 0 errors and 0 warnings.
    builds_clean: Int,
    /// Builds that produced at least one error.
    builds_failed: Int,
    // -----------------------------------------------------------------------
    // Test metrics
    // -----------------------------------------------------------------------
    /// Total test runs (`gleam test`).
    tests_run: Int,
    /// Tests that passed in the most recent run.
    tests_passed: Int,
    /// Tests that failed in the most recent run.
    tests_failed: Int,
    // -----------------------------------------------------------------------
    // Commit & MCP metrics
    // -----------------------------------------------------------------------
    /// Number of git commits created during the session.
    commits: Int,
    /// MCP tool invocations (plan_status, system_health, etc.).
    mcp_calls: Int,
  )
}

// ---------------------------------------------------------------------------
// Constructor
// ---------------------------------------------------------------------------

/// Create a zeroed SessionMetrics for a new session.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">
///     String × Int ↪ SessionMetrics (all counters = 0)
///   </morphism>
///   <formal-proof>
///     <P> Pre: session_id is non-empty, started_at_ms >= 0 </P>
///     <C> init(session_id, started_at_ms) </C>
///     <Q> Post: all counter fields == 0; id and timestamp set as given </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn init(session_id: String, started_at_ms: Int) -> SessionMetrics {
  SessionMetrics(
    session_id: session_id,
    started_at_ms: started_at_ms,
    zk_recalls: 0,
    zk_citations: 0,
    zk_anti_patterns: 0,
    tool_reads: 0,
    tool_edits: 0,
    tool_writes: 0,
    tool_bash: 0,
    tool_agents: 0,
    tool_agent_success: 0,
    tool_agent_failed: 0,
    builds_total: 0,
    builds_clean: 0,
    builds_failed: 0,
    tests_run: 0,
    tests_passed: 0,
    tests_failed: 0,
    commits: 0,
    mcp_calls: 0,
  )
}

// ---------------------------------------------------------------------------
// Increment helpers — each returns an updated SessionMetrics
// ---------------------------------------------------------------------------

/// Record one ZK recall (knowledge-search query executed).
pub fn record_zk_recall(m: SessionMetrics) -> SessionMetrics {
  SessionMetrics(..m, zk_recalls: m.zk_recalls + 1)
}

/// Record one ZK holon citation in a response.
pub fn record_zk_citation(m: SessionMetrics) -> SessionMetrics {
  SessionMetrics(..m, zk_citations: m.zk_citations + 1)
}

/// Record one anti-pattern detected via ZK recall and avoided.
pub fn record_zk_anti_pattern(m: SessionMetrics) -> SessionMetrics {
  SessionMetrics(..m, zk_anti_patterns: m.zk_anti_patterns + 1)
}

/// Record one Read tool call.
pub fn record_tool_read(m: SessionMetrics) -> SessionMetrics {
  SessionMetrics(..m, tool_reads: m.tool_reads + 1)
}

/// Record one Edit tool call.
pub fn record_tool_edit(m: SessionMetrics) -> SessionMetrics {
  SessionMetrics(..m, tool_edits: m.tool_edits + 1)
}

/// Record one Write tool call.
pub fn record_tool_write(m: SessionMetrics) -> SessionMetrics {
  SessionMetrics(..m, tool_writes: m.tool_writes + 1)
}

/// Record one Bash tool call.
pub fn record_tool_bash(m: SessionMetrics) -> SessionMetrics {
  SessionMetrics(..m, tool_bash: m.tool_bash + 1)
}

/// Record one sub-agent spawn.
pub fn record_agent_spawn(m: SessionMetrics) -> SessionMetrics {
  SessionMetrics(..m, tool_agents: m.tool_agents + 1)
}

/// Record a successful sub-agent completion.
pub fn record_agent_success(m: SessionMetrics) -> SessionMetrics {
  SessionMetrics(..m, tool_agent_success: m.tool_agent_success + 1)
}

/// Record a failed sub-agent termination.
pub fn record_agent_failed(m: SessionMetrics) -> SessionMetrics {
  SessionMetrics(..m, tool_agent_failed: m.tool_agent_failed + 1)
}

/// Record a clean build (0 errors, 0 warnings).
pub fn record_build_clean(m: SessionMetrics) -> SessionMetrics {
  SessionMetrics(
    ..m,
    builds_total: m.builds_total + 1,
    builds_clean: m.builds_clean + 1,
  )
}

/// Record a failed build (at least 1 error).
pub fn record_build_failed(m: SessionMetrics) -> SessionMetrics {
  SessionMetrics(
    ..m,
    builds_total: m.builds_total + 1,
    builds_failed: m.builds_failed + 1,
  )
}

/// Record a test run with the given pass and fail counts.
pub fn record_test_run(
  m: SessionMetrics,
  passed: Int,
  failed: Int,
) -> SessionMetrics {
  SessionMetrics(
    ..m,
    tests_run: m.tests_run + 1,
    tests_passed: m.tests_passed + passed,
    tests_failed: m.tests_failed + failed,
  )
}

/// Record one git commit.
pub fn record_commit(m: SessionMetrics) -> SessionMetrics {
  SessionMetrics(..m, commits: m.commits + 1)
}

/// Record one MCP tool call.
pub fn record_mcp_call(m: SessionMetrics) -> SessionMetrics {
  SessionMetrics(..m, mcp_calls: m.mcp_calls + 1)
}

// ---------------------------------------------------------------------------
// Derived metrics — pure computations over accumulated counters
// ---------------------------------------------------------------------------

/// Total file-mutation operations (edits + writes).
pub fn total_mutations(m: SessionMetrics) -> Int {
  m.tool_edits + m.tool_writes
}

/// Total tool calls (reads + edits + writes + bash + agent spawns + mcp).
pub fn total_tool_calls(m: SessionMetrics) -> Int {
  m.tool_reads
  + m.tool_edits
  + m.tool_writes
  + m.tool_bash
  + m.tool_agents
  + m.mcp_calls
}

/// ZK citation rate: citations / max(recalls, 1).
///
/// Returns a value in [0.0, 1.0].  A rate of 1.0 means every recall led
/// to a citation in the response (ideal per SC-ZK-IMP-002).
pub fn zk_citation_rate(m: SessionMetrics) -> Float {
  safe_div(int.to_float(m.zk_citations), int.to_float(safe_pos(m.zk_recalls)))
}

/// Build success rate: clean_builds / max(total_builds, 1).
///
/// Returns a value in [0.0, 1.0].  1.0 means all builds were clean.
pub fn build_success_rate(m: SessionMetrics) -> Float {
  safe_div(int.to_float(m.builds_clean), int.to_float(safe_pos(m.builds_total)))
}

/// Test pass rate: passed / max(passed + failed, 1) across all runs.
///
/// Returns a value in [0.0, 1.0].
pub fn test_pass_rate(m: SessionMetrics) -> Float {
  let total = m.tests_passed + m.tests_failed
  safe_div(int.to_float(m.tests_passed), int.to_float(safe_pos(total)))
}

/// Agent success rate: successes / max(spawned, 1).
///
/// Returns a value in [0.0, 1.0].
pub fn agent_success_rate(m: SessionMetrics) -> Float {
  safe_div(
    int.to_float(m.tool_agent_success),
    int.to_float(safe_pos(m.tool_agents)),
  )
}

/// Compute an effectiveness score in [0.0, 1.0].
///
/// Weighted combination of four signals:
///   ZK citation rate    — 0.30  (are we citing prior knowledge?)
///   Build success rate  — 0.35  (are builds staying clean?)
///   Test pass rate      — 0.25  (are tests passing?)
///   Agent success rate  — 0.10  (are spawned agents succeeding?)
///
/// When a denominator is zero (no builds, no tests, etc.) the component
/// defaults to 1.0 so that an empty session is not penalised.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">SessionMetrics ↪ Float in [0.0, 1.0]</morphism>
///   <formal-proof>
///     <P> Pre: all counter fields >= 0 </P>
///     <C> effectiveness_score(m) </C>
///     <Q> Post: result in [0.0, 1.0]; no panics, no division-by-zero </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn effectiveness_score(m: SessionMetrics) -> Float {
  let zk_rate = case m.zk_recalls == 0 {
    True -> 1.0
    False -> zk_citation_rate(m)
  }
  let build_rate = case m.builds_total == 0 {
    True -> 1.0
    False -> build_success_rate(m)
  }
  let test_rate = case m.tests_passed + m.tests_failed == 0 {
    True -> 1.0
    False -> test_pass_rate(m)
  }
  let agent_rate = case m.tool_agents == 0 {
    True -> 1.0
    False -> agent_success_rate(m)
  }

  // Round to 4 significant figures to eliminate IEEE-754 rounding artefacts
  // (e.g. 0.30+0.35+0.25+0.10 ≠ 1.0 exactly in binary floating-point).
  let raw =
    zk_rate
    *. 0.3
    +. build_rate
    *. 0.35
    +. test_rate
    *. 0.25
    +. agent_rate
    *. 0.1
  let rounded = int.to_float(float.round(raw *. 10_000.0)) /. 10_000.0
  clamp01(rounded)
}

// ---------------------------------------------------------------------------
// ETS publication stub (side-effect boundary)
// ---------------------------------------------------------------------------

/// Publish the current metrics to persistent_term via beam_cache (F08).
///
/// Uses beam_cache.set_config/2 which writes to Erlang's persistent_term store.
/// Reads are O(1) cost; writes are infrequent (per-session publish), so the
/// triggered GC scan is acceptable (SC-SATYA-002, SC-EVO-KPI-001).
pub fn publish_to_ets(m: SessionMetrics) -> Nil {
  let _ = beam_cache.set_config("claude:session_id", m.session_id)
  let _ =
    beam_cache.set_config("claude:zk_citations", int.to_string(m.zk_citations))
  let _ =
    beam_cache.set_config("claude:zk_recalls", int.to_string(m.zk_recalls))
  let _ =
    beam_cache.set_config("claude:tool_edits", int.to_string(m.tool_edits))
  let _ =
    beam_cache.set_config("claude:builds_clean", int.to_string(m.builds_clean))
  let _ = beam_cache.set_config("claude:commits", int.to_string(m.commits))
  let _ =
    beam_cache.set_config(
      "claude:effectiveness",
      float_4dp(effectiveness_score(m)),
    )
  let _ = beam_cache.set_config("claude:summary", summary(m))
  Nil
}

// ---------------------------------------------------------------------------
// Serialisation
// ---------------------------------------------------------------------------

/// Human-readable multi-line summary for journals and emails.
///
/// Format mirrors the pattern used in `beam_metrics.summary_line/1`.
pub fn summary(m: SessionMetrics) -> String {
  "Session: "
  <> m.session_id
  <> "\n"
  <> "ZK: recalls="
  <> int.to_string(m.zk_recalls)
  <> " citations="
  <> int.to_string(m.zk_citations)
  <> " anti-patterns="
  <> int.to_string(m.zk_anti_patterns)
  <> " citation_rate="
  <> format_pct(zk_citation_rate(m))
  <> "\n"
  <> "Tools: reads="
  <> int.to_string(m.tool_reads)
  <> " edits="
  <> int.to_string(m.tool_edits)
  <> " writes="
  <> int.to_string(m.tool_writes)
  <> " bash="
  <> int.to_string(m.tool_bash)
  <> " total="
  <> int.to_string(total_tool_calls(m))
  <> "\n"
  <> "Agents: spawned="
  <> int.to_string(m.tool_agents)
  <> " success="
  <> int.to_string(m.tool_agent_success)
  <> " failed="
  <> int.to_string(m.tool_agent_failed)
  <> " rate="
  <> format_pct(agent_success_rate(m))
  <> "\n"
  <> "Builds: total="
  <> int.to_string(m.builds_total)
  <> " clean="
  <> int.to_string(m.builds_clean)
  <> " failed="
  <> int.to_string(m.builds_failed)
  <> " rate="
  <> format_pct(build_success_rate(m))
  <> "\n"
  <> "Tests: runs="
  <> int.to_string(m.tests_run)
  <> " passed="
  <> int.to_string(m.tests_passed)
  <> " failed="
  <> int.to_string(m.tests_failed)
  <> " rate="
  <> format_pct(test_pass_rate(m))
  <> "\n"
  <> "Commits: "
  <> int.to_string(m.commits)
  <> " | MCP calls: "
  <> int.to_string(m.mcp_calls)
  <> "\n"
  <> "Effectiveness: "
  <> format_pct(effectiveness_score(m))
}

/// Serialise a SessionMetrics to a JSON string.
///
/// Uses gleam/string — no raw gleam/json dependency needed for this module.
/// The output is a flat JSON object suitable for Zenoh OTel publishing.
pub fn to_json(m: SessionMetrics) -> String {
  "{"
  <> json_str("session_id", m.session_id)
  <> ","
  <> json_int("started_at_ms", m.started_at_ms)
  <> ","
  <> json_int("zk_recalls", m.zk_recalls)
  <> ","
  <> json_int("zk_citations", m.zk_citations)
  <> ","
  <> json_int("zk_anti_patterns", m.zk_anti_patterns)
  <> ","
  <> json_int("tool_reads", m.tool_reads)
  <> ","
  <> json_int("tool_edits", m.tool_edits)
  <> ","
  <> json_int("tool_writes", m.tool_writes)
  <> ","
  <> json_int("tool_bash", m.tool_bash)
  <> ","
  <> json_int("tool_agents", m.tool_agents)
  <> ","
  <> json_int("tool_agent_success", m.tool_agent_success)
  <> ","
  <> json_int("tool_agent_failed", m.tool_agent_failed)
  <> ","
  <> json_int("builds_total", m.builds_total)
  <> ","
  <> json_int("builds_clean", m.builds_clean)
  <> ","
  <> json_int("builds_failed", m.builds_failed)
  <> ","
  <> json_int("tests_run", m.tests_run)
  <> ","
  <> json_int("tests_passed", m.tests_passed)
  <> ","
  <> json_int("tests_failed", m.tests_failed)
  <> ","
  <> json_int("commits", m.commits)
  <> ","
  <> json_int("mcp_calls", m.mcp_calls)
  <> ","
  <> json_float("effectiveness_score", effectiveness_score(m))
  <> "}"
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

/// Clamp a float to [0.0, 1.0].
fn clamp01(v: Float) -> Float {
  float.min(1.0, float.max(0.0, v))
}

/// Safe division — returns 0.0 when denominator is 0.0.
fn safe_div(num: Float, den: Float) -> Float {
  case den == 0.0 {
    True -> 0.0
    False -> clamp01(num /. den)
  }
}

/// Guard division-by-zero for integer denominators.
fn safe_pos(n: Int) -> Int {
  case n <= 0 {
    True -> 1
    False -> n
  }
}

/// Render a [0.0, 1.0] float as a percentage string e.g. "87.50%".
fn format_pct(v: Float) -> String {
  let millis = float.round(v *. 10_000.0)
  let whole = millis / 100
  let frac = millis % 100
  let frac_str = case frac < 10 {
    True -> "0" <> int.to_string(frac)
    False -> int.to_string(frac)
  }
  int.to_string(whole) <> "." <> frac_str <> "%"
}

/// Render a float with 4 decimal places for JSON.
fn float_4dp(v: Float) -> String {
  let millis = float.round(v *. 10_000.0)
  let whole = millis / 10_000
  let frac = millis % 10_000
  let frac_str = case frac < 10 {
    True -> "000" <> int.to_string(frac)
    False ->
      case frac < 100 {
        True -> "00" <> int.to_string(frac)
        False ->
          case frac < 1000 {
            True -> "0" <> int.to_string(frac)
            False -> int.to_string(frac)
          }
      }
  }
  int.to_string(whole) <> "." <> frac_str
}

/// Emit `"key":value` JSON integer pair.
fn json_int(key: String, value: Int) -> String {
  "\"" <> key <> "\":" <> int.to_string(value)
}

/// Emit `"key":value` JSON float pair (4 decimal places).
fn json_float(key: String, value: Float) -> String {
  "\"" <> key <> "\":" <> float_4dp(value)
}

/// Emit `"key":"escaped_value"` JSON string pair.
fn json_str(key: String, value: String) -> String {
  "\"" <> key <> "\":\"" <> string.replace(value, "\"", "\\\"") <> "\""
}
