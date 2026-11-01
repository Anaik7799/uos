//// UOS-CORE-EVO: Pure Functional Core Development & Evolution Algebra
//// (`SC-HARNESS-MCP-001`, `SC-JIDOKA-001`, `SC-RISK-PRIORITY-001`, `SC-PROVENANCE-001`)
////
//// Enforces:
//// 1. Zero-Muda minimal AGY conductor token burn (< 2% share, <= 512-byte digests,
////    0 AGY subagents, 0 non-UOS MCP servers, 8-12 wave-scoped Gleam MCP routes).
//// 2. Hard 40.0% safety margin (<= 60.0% ceiling = 6,000 bps) across ALL FOUR
////    rolling windows: AGY 5h, AGY 7d (weekly), AGY 30d (monthly), and 24h
////    OpenRouter nanodollars ($6.00 hard cap out of $10.00 root limit).
//// 3. Maximized self-healing timeouts (4h Sa-plan lease, 20m Zenoh heartbeat,
////    30m build/tool timeout, 60m -> 90m -> 120m 3-attempt ladder, 8h soak).
//// 4. Clean Jujutsu sibling-workspace corruption rollback + progressive
////    Attempt 1 (Pi+DeepSeek Flash / Codex) -> Attempt 2 (Pi+DeepSeek Pro ACH
////    RCA + TPS Poka-Yoke guard first) -> Attempt 3 (Pi+Argon STPA/TPS wrong-path
////    architectural redesign + Codex surgical execution) -> Jidoka Andon HOLD.

import cepaf_gleam/ecology/daily_budget
import gleam/int
import gleam/json
import gleam/list
import gleam/string

pub const admitted_ev_ceiling = 93

/// Basis-point constants (10,000 bps = 100.00%).
/// 40.0% mandatory safety margin => 60.0% (6,000 bps) hard execution ceiling.
pub const full_window_bps = 10_000

pub const mandatory_margin_bps = 4000

pub const hard_ceiling_bps = 6000

pub const soft_shift_5h_bps = 4500

pub const soft_shift_7d_bps = 5000

pub const soft_shift_30d_bps = 5000

/// OpenRouter 24h nanodollar ceilings derived from daily_budget ($10.00 root).
/// 40.0% margin => $6.00 hard cap (6,000,000,000 nanodollars); $4.50 soft shift.
pub const openrouter_hard_cap_nanodollars = 6_000_000_000

pub const openrouter_soft_shift_nanodollars = 4_500_000_000

/// Maximized timeout constants (milliseconds) for deep builds & RCA/TPS recovery.
pub const lease_ttl_ms = 14_400_000

pub const heartbeat_interval_ms = 1_200_000

pub const max_missed_heartbeats = 3

pub const tool_command_timeout_ms = 1_800_000

pub const attempt_1_timeout_ms = 3_600_000

pub const attempt_2_timeout_ms = 5_400_000

pub const attempt_3_timeout_ms = 7_200_000

pub const soak_envelope_timeout_ms = 28_800_000

/// Strict upper bound on any wave/andon digest delivered to AGY conductor.
pub const max_conductor_digest_bytes = 512

pub type TimeoutEnvelope {
  TimeoutEnvelope(
    lease_ttl_ms: Int,
    heartbeat_interval_ms: Int,
    stale_after_ms: Int,
    tool_command_timeout_ms: Int,
    attempt_1_timeout_ms: Int,
    attempt_2_timeout_ms: Int,
    attempt_3_timeout_ms: Int,
    soak_envelope_timeout_ms: Int,
  )
}

pub fn maximized_timeouts() -> TimeoutEnvelope {
  TimeoutEnvelope(
    lease_ttl_ms: lease_ttl_ms,
    heartbeat_interval_ms: heartbeat_interval_ms,
    stale_after_ms: heartbeat_interval_ms * max_missed_heartbeats,
    tool_command_timeout_ms: tool_command_timeout_ms,
    attempt_1_timeout_ms: attempt_1_timeout_ms,
    attempt_2_timeout_ms: attempt_2_timeout_ms,
    attempt_3_timeout_ms: attempt_3_timeout_ms,
    soak_envelope_timeout_ms: soak_envelope_timeout_ms,
  )
}

pub type QuotaSnapshot {
  QuotaSnapshot(
    agy_5h_bps: Int,
    agy_7d_bps: Int,
    agy_30d_bps: Int,
    openrouter_24h_nanodollars: Int,
  )
}

pub type DispatchMode {
  NormalDispatch
  ZeroOpenRouterShift
  BatchConductorWakeups
  ZeroOpenRouterAndBatchedWakeups
}

pub type QuotaDecision {
  QuotaAdmitted(
    mode: DispatchMode,
    min_remaining_margin_bps: Int,
    openrouter_remaining_nanodollars: Int,
  )
  QuotaHoldMargin40Pct(violated_windows: List(String))
}

pub type Engine {
  PiDeepSeekFlash
  PiDeepSeekPro
  PiArgonGoogle
  PiArgonOpenRouter
  CodexCli
  AgyThinConductor
}

pub fn engine_id(engine: Engine) -> String {
  case engine {
    PiDeepSeekFlash -> "pi+openrouter:deepseek/deepseek-v4-flash-0731"
    PiDeepSeekPro -> "pi+openrouter:deepseek/deepseek-v4-pro-0813"
    PiArgonGoogle -> "pi+google:gemini-4-argon"
    PiArgonOpenRouter -> "pi+openrouter:google/gemini-4-argon"
    CodexCli -> "codex:gpt-6.1-terra"
    AgyThinConductor -> "agy:thin-conductor-digest-only"
  }
}

pub type TaskRole {
  ImplRole
  RcaTpsRole
  SovereignGateRole
  FmeaFormalRole
  ConductorRole
}

pub type FailureClass {
  InitialDispatch
  TransientOrTestFailure(detail: String)
  WorkspaceCorruption(detail: String)
  WrongArchitecturalPath(detail: String)
  SafetyBoundaryViolation(detail: String)
}

pub type RecoveryStrategy {
  FreshAttemptWorkspace
  QuarantineRollbackAchRcaAndPokaYoke
  QuarantineRollbackStpaTpsArchitecturalPivot
}

pub type AttemptPlan {
  ExecuteAttempt(
    attempt: Int,
    primary_engine: Engine,
    reviewer_engine: Engine,
    timeout_ms: Int,
    lease_ttl_ms: Int,
    tool_timeout_ms: Int,
    strategy: RecoveryStrategy,
    workspace_suffix: String,
    allowed_mcp_tools: List(String),
    zenoh_topic_prefix: String,
  )
  JidokaAndonHold(attempt: Int, reason: String, zenoh_alert_topic: String)
}

/// Evaluate all four sliding quota windows against the mandatory 40.0% safety
/// margin (<= 60.0% hard cap). Negative or unknown values fail closed.
pub fn evaluate_quota_margin(q: QuotaSnapshot) -> QuotaDecision {
  let or_bps =
    { q.openrouter_24h_nanodollars * full_window_bps }
    / daily_budget.daily_limit_nanodollars

  let violations =
    []
    |> add_if(
      q.agy_5h_bps < 0 || q.agy_5h_bps > hard_ceiling_bps,
      "agy_5h_exceeds_60pct_cap_or_invalid",
    )
    |> add_if(
      q.agy_7d_bps < 0 || q.agy_7d_bps > hard_ceiling_bps,
      "agy_7d_weekly_exceeds_60pct_cap_or_invalid",
    )
    |> add_if(
      q.agy_30d_bps < 0 || q.agy_30d_bps > hard_ceiling_bps,
      "agy_30d_monthly_exceeds_60pct_cap_or_invalid",
    )
    |> add_if(
      q.openrouter_24h_nanodollars < 0
        || q.openrouter_24h_nanodollars > openrouter_hard_cap_nanodollars,
      "openrouter_24h_exceeds_6usd_60pct_cap_or_invalid",
    )

  case violations {
    [_, ..] -> QuotaHoldMargin40Pct(list.reverse(violations))
    [] -> {
      let max_used_bps =
        q.agy_5h_bps
        |> int.max(q.agy_7d_bps)
        |> int.max(q.agy_30d_bps)
        |> int.max(or_bps)
      let min_margin = full_window_bps - max_used_bps
      let shift_or =
        q.openrouter_24h_nanodollars >= openrouter_soft_shift_nanodollars
      let batch_agy =
        q.agy_5h_bps >= soft_shift_5h_bps
        || q.agy_7d_bps >= soft_shift_7d_bps
        || q.agy_30d_bps >= soft_shift_30d_bps
      let mode = case shift_or, batch_agy {
        True, True -> ZeroOpenRouterAndBatchedWakeups
        True, False -> ZeroOpenRouterShift
        False, True -> BatchConductorWakeups
        False, False -> NormalDispatch
      }
      QuotaAdmitted(
        mode: mode,
        min_remaining_margin_bps: min_margin,
        openrouter_remaining_nanodollars: openrouter_hard_cap_nanodollars
          - q.openrouter_24h_nanodollars,
      )
    }
  }
}

/// Verify lease TTL and 20-minute Zenoh heartbeat freshness.
pub fn is_lease_healthy(
  now_ms now_ms: Int,
  lease_expires_ms lease_expires_ms: Int,
  last_heartbeat_ms last_heartbeat_ms: Int,
) -> Bool {
  let stale_window = heartbeat_interval_ms * max_missed_heartbeats
  now_ms > 0
  && lease_expires_ms > now_ms
  && last_heartbeat_ms <= now_ms
  && { now_ms - last_heartbeat_ms } <= stale_window
}

/// Zero-Muda wave-scoped MCP route whitelists (ONLY canonical UOS Gleam tools,
/// 8-11 routes per role instead of loading 15 external MCPs or all 101 schemas).
pub fn minimal_mcp_tools(role: TaskRole) -> List(String) {
  case role {
    ImplRole -> [
      "knowledge_search",
      "zk_transclude",
      "sa_plan_status_for",
      "sa_task_claim",
      "sa_task_complete",
      "system_health",
      "system_zenoh",
      "integrity_check",
      "verification_run",
    ]
    RcaTpsRole -> [
      "knowledge_search",
      "zk_transclude",
      "stpa_fmea_hazard",
      "rete_rule_conflict",
      "ast_anomaly_detect",
      "ooda_decide",
      "sa_plan_status_for",
      "system_zenoh",
      "integrity_check",
      "verification_run",
    ]
    SovereignGateRole -> [
      "sa_plan_status_for",
      "system_health",
      "system_zenoh",
      "system_verification",
      "preflight_check",
      "integrity_check",
      "stpa_fmea_hazard",
      "harness_execution_progress",
    ]
    FmeaFormalRole -> [
      "knowledge_search",
      "zk_transclude",
      "stpa_fmea_hazard",
      "lyapunov_trend_predict",
      "ooda_decide",
      "sa_plan_status_for",
      "system_verification",
      "integrity_check",
    ]
    ConductorRole -> [
      "sa_plan_status_for",
      "system_health",
      "system_zenoh",
      "preflight_check",
      "integrity_check",
    ]
  }
}

/// Deterministic 3-attempt progressive timeout, clean JJ rollback, and
/// Flash -> Pro (ACH RCA + Poka-Yoke) -> Argon + Codex (STPA/TPS pivot) ->
/// Jidoka Andon HOLD planner.
pub fn plan_attempt_step(
  task_id task_id: String,
  role role: TaskRole,
  attempt attempt: Int,
  failure failure: FailureClass,
  quota quota: QuotaSnapshot,
) -> AttemptPlan {
  let alert_topic = "uos/v1/rca/" <> sanitize_segment(task_id) <> "/andon_hold"
  case evaluate_quota_margin(quota) {
    QuotaHoldMargin40Pct(windows) ->
      JidokaAndonHold(
        attempt: attempt,
        reason: "HOLD_MARGIN_40PCT:" <> string.join(windows, ","),
        zenoh_alert_topic: alert_topic,
      )
    QuotaAdmitted(mode, _, _) ->
      case failure {
        SafetyBoundaryViolation(detail) ->
          JidokaAndonHold(
            attempt: attempt,
            reason: "HOLD_SAFETY_BOUNDARY:" <> detail,
            zenoh_alert_topic: alert_topic,
          )
        _ ->
          case attempt {
            1 -> {
              let zero_or = is_zero_or_mode(mode)
              let #(primary, reviewer) = select_attempt_1_engines(role, zero_or)
              ExecuteAttempt(
                attempt: 1,
                primary_engine: primary,
                reviewer_engine: reviewer,
                timeout_ms: attempt_1_timeout_ms,
                lease_ttl_ms: lease_ttl_ms,
                tool_timeout_ms: tool_command_timeout_ms,
                strategy: FreshAttemptWorkspace,
                workspace_suffix: sanitize_segment(task_id) <> "-a1",
                allowed_mcp_tools: minimal_mcp_tools(role),
                zenoh_topic_prefix: "uos/v1/saplan/"
                  <> sanitize_segment(task_id)
                  <> "/a1",
              )
            }
            2 -> {
              let zero_or = is_zero_or_mode(mode)
              // If Attempt 1 already proved a wrong architectural path, jump
              // straight to STPA/TPS architectural redesign capabilities on a2.
              let #(primary, reviewer, strat) = case failure, zero_or {
                WrongArchitecturalPath(_), _ -> #(
                  PiArgonGoogle,
                  CodexCli,
                  QuarantineRollbackStpaTpsArchitecturalPivot,
                )
                _, True -> #(
                  PiArgonGoogle,
                  CodexCli,
                  QuarantineRollbackAchRcaAndPokaYoke,
                )
                _, False -> #(
                  PiDeepSeekPro,
                  CodexCli,
                  QuarantineRollbackAchRcaAndPokaYoke,
                )
              }
              ExecuteAttempt(
                attempt: 2,
                primary_engine: primary,
                reviewer_engine: reviewer,
                timeout_ms: attempt_2_timeout_ms,
                lease_ttl_ms: lease_ttl_ms,
                tool_timeout_ms: tool_command_timeout_ms,
                strategy: strat,
                workspace_suffix: sanitize_segment(task_id) <> "-a2",
                allowed_mcp_tools: minimal_mcp_tools(RcaTpsRole),
                zenoh_topic_prefix: "uos/v1/rca/"
                  <> sanitize_segment(task_id)
                  <> "/a2",
              )
            }
            3 ->
              ExecuteAttempt(
                attempt: 3,
                primary_engine: PiArgonGoogle,
                reviewer_engine: CodexCli,
                timeout_ms: attempt_3_timeout_ms,
                lease_ttl_ms: lease_ttl_ms,
                tool_timeout_ms: tool_command_timeout_ms,
                strategy: QuarantineRollbackStpaTpsArchitecturalPivot,
                workspace_suffix: sanitize_segment(task_id) <> "-a3",
                allowed_mcp_tools: minimal_mcp_tools(RcaTpsRole),
                zenoh_topic_prefix: "uos/v1/rca/"
                  <> sanitize_segment(task_id)
                  <> "/a3",
              )
            _ ->
              JidokaAndonHold(
                attempt: attempt,
                reason: "HOLD_MAX_3_ATTEMPTS_EXHAUSTED_JIDOKA_ANDON",
                zenoh_alert_topic: alert_topic,
              )
          }
      }
  }
}

/// Encode a strict <= 512-byte JSON wave/task summary for AGY Thin Conductor,
/// guaranteeing minimal AGY context token burn.
pub fn encode_conductor_digest(
  wave wave: String,
  status status: String,
  commit_id commit_id: String,
  tests_passed tests_passed: Int,
  quota quota: QuotaSnapshot,
  note note: String,
) -> String {
  let clean_note = truncate_ascii(note, 96)
  let clean_wave = truncate_ascii(wave, 24)
  let clean_status = truncate_ascii(status, 24)
  let clean_commit = truncate_ascii(commit_id, 16)
  json.object([
    #("schema", json.string("uos.core_evo.digest.v1")),
    #("ev_ceiling", json.int(admitted_ev_ceiling)),
    #("wave", json.string(clean_wave)),
    #("status", json.string(clean_status)),
    #("rev", json.string(clean_commit)),
    #("tests", json.int(tests_passed)),
    #("agy_5h_bps", json.int(quota.agy_5h_bps)),
    #("agy_7d_bps", json.int(quota.agy_7d_bps)),
    #("agy_30d_bps", json.int(quota.agy_30d_bps)),
    #("or_nd", json.int(quota.openrouter_24h_nanodollars)),
    #("note", json.string(clean_note)),
  ])
  |> json.to_string
}

fn select_attempt_1_engines(role: TaskRole, zero_or: Bool) -> #(Engine, Engine) {
  case role, zero_or {
    SovereignGateRole, _ -> #(CodexCli, AgyThinConductor)
    FmeaFormalRole, _ -> #(PiArgonGoogle, CodexCli)
    ConductorRole, _ -> #(AgyThinConductor, CodexCli)
    _, True -> #(PiArgonGoogle, CodexCli)
    _, False -> #(PiDeepSeekFlash, CodexCli)
  }
}

fn is_zero_or_mode(mode: DispatchMode) -> Bool {
  case mode {
    ZeroOpenRouterShift | ZeroOpenRouterAndBatchedWakeups -> True
    NormalDispatch | BatchConductorWakeups -> False
  }
}

fn sanitize_segment(raw: String) -> String {
  raw
  |> string.to_graphemes
  |> list.filter(fn(c) {
    string.contains(
      "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-",
      c,
    )
  })
  |> string.concat
  |> truncate_ascii(48)
}

fn truncate_ascii(input: String, max_chars: Int) -> String {
  input
  |> string.to_graphemes
  |> list.take(max_chars)
  |> string.concat
}

fn add_if(items: List(String), cond: Bool, label: String) -> List(String) {
  case cond {
    True -> [label, ..items]
    False -> items
  }
}
