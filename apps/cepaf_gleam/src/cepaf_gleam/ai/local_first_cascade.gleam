//// Local-First Cascade Router & Fail-Closed Remote Effect Gate (task `mt/mt3`)
//// #fractal-l2 #fractal-l4 #fractal-l5 #zero-muda
////
//// STAMP: `SC-ROUTING-001`, `SC-HARNESS-MCP-001`, `SC-PROVENANCE-001`, `SC-MUDA-001`
////
//// PURPOSE — the token/cost objective is only meaningful if the accounting cannot
//// lie. This module is the single place where a request becomes "resolved", so it
//// is the single place where that claim can be falsified. Two design decisions
//// make the claim structural rather than asserted:
////
//// 1. A `KindLocal` decision carries NO remote-token field. A local resolution
////    cannot express remote usage, so "local implies zero remote tokens" is not a
////    runtime check that some later path might skip — it is a property of the
////    data shape.
//// 2. `record_remote_usage` OVERRIDES a local or held label with the observed
////    remote usage. The ledger therefore cannot be made to claim a locality it
////    did not have, even if some future code path leaks a call out to a provider.
////    That override is the narrow falsifier for the headline claim; it is tested
////    by `remote_usage_overrides_local_label_test`.
////
//// CASCADE — Tier 0 (Mojo SIMD NIF) -> Tier 1 (bounded compressor / Raven) ->
//// Tier 2 (supervised MAX worker). Local-to-local promotion is free. Promotion to
//// Tier 3/4 is a REMOTE EFFECT and requires ALL of: an explicit grant for this
//// tenant, an unexpired grant, an in-budget request, an explicitly permitted paid
//// tier, and a prefix-pinned MCIP/1.0 envelope bound to this logical request and
//// fractal layer. Local timeout, error, unavailability or low confidence yields
//// `KindHeld` — never an implicit remote call. `SovereignOnly` forbids remote
//// outright.
////
//// WHAT THIS DOES NOT DO — it does not dispatch. The probes are injected by the
//// supervised adapter, which is what keeps this module pure and testable. A
//// passing test here is an observation about the router, not evidence that the
//// NIF or the MAX worker behaved correctly; those carry their own evidence.

import cepaf_gleam/ecology/core_bionic_token_twin.{type McipV1Envelope}
import gleam/dict.{type Dict}
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/string

// ---------------------------------------------------------------------------
// Allocation constants. Every threshold is named and appears in the report so a
// reader can disagree with the number rather than guess at it.
// ---------------------------------------------------------------------------

/// A local probe must reach this confidence to count as a resolution.
/// Micro-precision is deliberate: an integer floor avoids float comparisons in
/// the decision path, where the rounding would be a silent source of drift.
pub const local_confidence_floor_milli: Int = 700

/// Provenance ceiling. An MCIP envelope that advertises a higher EV cycle is
/// refused, so compression receipts cannot smuggle a non-admitted claim.
pub const admission_ev_ceiling: Int = 93

/// Operator objective: >= 80% of logical requests resolved locally.
pub const local_resolution_target_bps: Int = 8000

/// Documented pricing for the paid tier, in thousandths of a USD per 1k tokens.
pub const paid_usd_milli_per_kprompt: Int = 3
pub const paid_usd_milli_per_kcompletion: Int = 15

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

pub type Tier {
  Tier0Simd
  Tier1Compress
  Tier2Max
  Tier3FreeRemote
  Tier4PaidRemote
}

pub fn tier_label(tier: Tier) -> String {
  case tier {
    Tier0Simd -> "tier0_simd"
    Tier1Compress -> "tier1_compress"
    Tier2Max -> "tier2_max"
    Tier3FreeRemote -> "tier3_free_remote"
    Tier4PaidRemote -> "tier4_paid_remote"
  }
}

/// True only for tiers that spend provider tokens. This is the guard the effect
/// gate and the ledger both consult, so the two can never disagree.
pub fn is_remote(tier: Tier) -> Bool {
  case tier {
    Tier3FreeRemote -> True
    Tier4PaidRemote -> True
    Tier0Simd | Tier1Compress | Tier2Max -> False
  }
}

pub type Strategy {
  ZeroCostPreferFree
  LowLatencyLocalFirst
  SovereignOnly
}

pub fn strategy_label(strategy: Strategy) -> String {
  case strategy {
    ZeroCostPreferFree -> "zero_cost_prefer_free"
    LowLatencyLocalFirst -> "low_latency_local_first"
    SovereignOnly -> "sovereign_only"
  }
}

/// Where a request came from. A child inherits its parent's tenant; a retry
/// carries the parent request id so the ledger can group attempts.
pub type Origin {
  Ingress
  Child(parent_request_id: String, tenant: String)
  Retry(parent_request_id: String)
}

pub fn origin_label(origin: Origin) -> String {
  case origin {
    Ingress -> "ingress"
    Child(parent, tenant) -> "child:" <> parent <> ":" <> tenant
    Retry(parent) -> "retry:" <> parent
  }
}

pub type RouteRequest {
  RouteRequest(
    request_id: String,
    /// Stable across retries of the same logical request. Equals `request_id`
    /// for a first attempt.
    logical_id: String,
    tenant: String,
    origin: Origin,
    strategy: Strategy,
    layer_code: String,
    prompt_bytes: Int,
    max_completion_tokens: Int,
    allow_paid: Bool,
  )
}

/// What a local tier reported. These are observations handed in by the
/// supervised adapter — this module performs no I/O.
pub type ProbeOutcome {
  ProbeOk(confidence_milli: Int, latency_us: Int)
  ProbeLowConfidence(confidence_milli: Int, latency_us: Int)
  ProbeTimeout(latency_us: Int)
  ProbeError(code: String)
  ProbeUnavailable
  /// The probe was called with inadmissible arguments. A client-side defect:
  /// never retried on another tier, because that would mask the defect.
  ProbeContractViolation(field: String)
  ProbeNotAttempted
}

pub fn probe_label(outcome: ProbeOutcome) -> String {
  case outcome {
    ProbeOk(confidence_milli, latency_us) ->
      "ok:" <> int.to_string(confidence_milli) <> ":" <> int.to_string(latency_us)
    ProbeLowConfidence(confidence_milli, latency_us) ->
      "low:" <> int.to_string(confidence_milli) <> ":" <> int.to_string(latency_us)
    ProbeTimeout(latency_us) -> "timeout:" <> int.to_string(latency_us)
    ProbeError(code) -> "error:" <> code
    ProbeUnavailable -> "unavailable"
    ProbeContractViolation(field) -> "contract_violation:" <> field
    ProbeNotAttempted -> "not_attempted"
  }
}

pub type Attempt {
  Attempt(tier: Tier, outcome: ProbeOutcome)
}

pub fn attempt_label(attempt: Attempt) -> String {
  tier_label(attempt.tier) <> "=" <> probe_label(attempt.outcome)
}

pub type LocalProbe {
  LocalProbe(
    simd: ProbeOutcome,
    compress: ProbeOutcome,
    max: ProbeOutcome,
  )
}

/// An explicit authorization for one remote effect. `mcip` must be present and
/// valid before dispatch; a grant without a compression receipt is not enough.
pub type RemoteGrant {
  RemoteGrant(
    grant_id: String,
    tenant: String,
    tier: Tier,
    max_usd_milli: Int,
    expires_utc_ms: Int,
    mcip: Option(McipV1Envelope),
  )
}

pub type DecisionKind {
  KindLocal
  KindHeld
  KindRemote
  KindRejected
}

pub fn kind_label(kind: DecisionKind) -> String {
  case kind {
    KindLocal -> "local"
    KindHeld -> "held"
    KindRemote -> "remote"
    KindRejected -> "rejected"
  }
}

/// Note the absent field: there is no `remote_tokens` here. A local decision
/// cannot carry remote usage, by construction.
pub type Decision {
  Decision(
    request_id: String,
    logical_id: String,
    tenant: String,
    kind: DecisionKind,
    tier: Tier,
    confidence_milli: Int,
    reason: String,
    attempts: List(Attempt),
    grant: Option(RemoteGrant),
  )
}

// ---------------------------------------------------------------------------
// Token and cost estimation
// ---------------------------------------------------------------------------

/// Documented heuristic: ~4 UTF-8 bytes per token. A zero-byte prompt is zero
/// tokens, not one — the old `max(1, ...)` floor silently billed empty input.
pub fn estimate_tokens_from_bytes(bytes: Int) -> Int {
  case bytes <= 0 {
    True -> 0
    False -> { bytes + 3 } / 4
  }
}

pub fn estimate_remote_cost_milli(
  prompt_bytes: Int,
  max_completion_tokens: Int,
  tier: Tier,
) -> Int {
  case tier {
    Tier3FreeRemote -> 0
    _ -> {
      let prompt_tokens = estimate_tokens_from_bytes(prompt_bytes)
      let completion_tokens = int.max(0, max_completion_tokens)
      { prompt_tokens * paid_usd_milli_per_kprompt }
      / 1000
      + { completion_tokens * paid_usd_milli_per_kcompletion }
      / 1000
    }
  }
}

// ---------------------------------------------------------------------------
// MCIP/1.0 prefix-pinned envelope validation
// ---------------------------------------------------------------------------

/// Validate a compression receipt against the prefix pin, the provenance
/// ceiling, and the "it must actually have compacted" requirement. Each failure
/// is a distinct reason string so the held decision explains itself.
pub fn validate_mcip_pin(env: McipV1Envelope) -> Result(Nil, String) {
  let checks = [
    #(
      "protocol_version",
      env.protocol_version == "MCIP/1.0",
      "mcip_bad_protocol_version:" <> env.protocol_version,
    ),
    #("workload_id", env.workload_id != "", "mcip_missing_workload_id"),
    #(
      "fractal_layer_code",
      env.fractal_layer_code != "",
      "mcip_missing_layer_code",
    ),
    #(
      "ev_ceiling",
      env.ev_ceiling <= admission_ev_ceiling,
      "mcip_ev_ceiling_exceeds_admission:"
      <> int.to_string(env.ev_ceiling)
      <> ">"
      <> int.to_string(admission_ev_ceiling),
    ),
    #(
      "re_read_required",
      env.re_read_required == False,
      "mcip_requires_re_read",
    ),
    #(
      "critical_anchors_preserved",
      env.critical_anchors_preserved >= 1,
      "mcip_no_anchors_preserved",
    ),
    #(
      "compacted_bytes",
      env.compacted_bytes < env.raw_bytes,
      "mcip_did_not_compact:"
      <> int.to_string(env.compacted_bytes)
      <> ">="
      <> int.to_string(env.raw_bytes),
    ),
    #(
      "prefix_header",
      string.starts_with(env.wire_packet, "@MCIP/1.0{"),
      "mcip_prefix_header_missing",
    ),
    #(
      "prefix_pi_ready",
      string.contains(env.wire_packet, "|Pi_ready=1}"),
      "mcip_prefix_pi_ready_missing",
    ),
    #(
      "prefix_decision",
      string.contains(env.wire_packet, "@MCIP_DECISION{"),
      "mcip_prefix_decision_missing",
    ),
  ]
  let failures =
    list.filter(checks, fn(check) { check.1 == False })
    |> list.map(fn(check) { check.2 })
  case failures {
    [] -> Ok(Nil)
    _ -> Error(string.join(failures, ";"))
  }
}

// ---------------------------------------------------------------------------
// Routing
// ---------------------------------------------------------------------------

type LocalRun {
  LocalRun(
    attempts: List(Attempt),
    resolved: Option(#(Tier, Int)),
    violation: Option(String),
    failure: String,
  )
}

fn base(request: RouteRequest) -> Decision {
  Decision(
    request_id: request.request_id,
    logical_id: request.logical_id,
    tenant: request.tenant,
    kind: KindHeld,
    tier: Tier0Simd,
    confidence_milli: 0,
    reason: "",
    attempts: [],
    grant: None,
  )
}

fn step_local(state: LocalRun, tier: Tier, outcome: ProbeOutcome) -> LocalRun {
  case state.resolved {
    Some(_) -> state
    None ->
      case state.violation {
        Some(_) -> state
        None -> {
          let attempts = list.append(state.attempts, [Attempt(tier, outcome)])
          let failed = fn(
            inner: LocalRun,
            detail: String,
          ) { LocalRun(..inner, attempts: attempts, failure: detail) }
          case outcome {
            ProbeContractViolation(field) ->
              LocalRun(
                ..state,
                attempts: attempts,
                violation: Some(field),
              )
            ProbeOk(confidence_milli, _latency) ->
              case confidence_milli >= local_confidence_floor_milli {
                True ->
                  LocalRun(
                    ..state,
                    attempts: attempts,
                    resolved: Some(#(tier, confidence_milli)),
                  )
                False ->
                  failed(
                    state,
                    "low_confidence:"
                    <> int.to_string(confidence_milli)
                    <> "@"
                    <> tier_label(tier),
                  )
              }
            ProbeLowConfidence(confidence_milli, _latency) ->
              failed(
                state,
                "low_confidence:"
                <> int.to_string(confidence_milli)
                <> "@"
                <> tier_label(tier),
              )
            ProbeTimeout(_latency) -> failed(state, "timeout@" <> tier_label(tier))
            ProbeError(code) ->
              failed(state, "error:" <> code <> "@" <> tier_label(tier))
            ProbeUnavailable -> failed(state, "unavailable@" <> tier_label(tier))
            ProbeNotAttempted ->
              failed(state, "not_attempted@" <> tier_label(tier))
          }
        }
      }
  }
}

fn run_local(probe: LocalProbe) -> LocalRun {
  list.fold(
    [
      #(Tier0Simd, probe.simd),
      #(Tier1Compress, probe.compress),
      #(Tier2Max, probe.max),
    ],
    LocalRun(attempts: [], resolved: None, violation: None, failure: ""),
    fn(acc, entry) { step_local(acc, entry.0, entry.1) },
  )
}

fn hold(request: RouteRequest, attempts: List(Attempt), reason: String) -> Decision {
  Decision(
    ..base(request),
    kind: KindHeld,
    tier: Tier2Max,
    reason: reason,
    attempts: attempts,
    grant: None,
  )
}

fn try_remote(
  request: RouteRequest,
  attempts: List(Attempt),
  grant: RemoteGrant,
  now_utc_ms: Int,
) -> Decision {
  let held = fn(reason: String) { hold(request, attempts, reason) }
  case is_remote(grant.tier) {
    False -> held("grant_tier_is_local:" <> tier_label(grant.tier))
    True ->
      case grant.tenant == request.tenant {
        False -> held("grant_tenant_mismatch:" <> grant.tenant)
        True ->
          case grant.expires_utc_ms > now_utc_ms {
            False -> held("grant_expired:" <> grant.grant_id)
            True -> {
              let cost =
                estimate_remote_cost_milli(
                  request.prompt_bytes,
                  request.max_completion_tokens,
                  grant.tier,
                )
              case grant.max_usd_milli >= cost {
                False ->
                  held(
                    "grant_budget_exceeded:"
                    <> int.to_string(cost)
                    <> ">"
                    <> int.to_string(grant.max_usd_milli),
                  )
                True ->
                  case request.allow_paid, grant.tier {
                    False, Tier4PaidRemote -> held("paid_tier_not_permitted")
                    _, _ ->
                      case request.prompt_bytes <= 0 {
                        True -> held("empty_prompt")
                        False ->
                          case grant.mcip {
                            None -> held("mcip_receipt_missing")
                            Some(env) ->
                              case validate_mcip_pin(env) {
                                Error(reason) -> held(reason)
                                Ok(_) ->
                                  case env.workload_id == request.logical_id {
                                    False ->
                                      held(
                                        "mcip_workload_mismatch:"
                                        <> env.workload_id
                                        <> "!="
                                        <> request.logical_id,
                                      )
                                    True ->
                                      case env.fractal_layer_code
                                        == request.layer_code
                                      {
                                        False ->
                                          held(
                                            "mcip_layer_mismatch:"
                                            <> env.fractal_layer_code
                                            <> "!="
                                            <> request.layer_code,
                                          )
                                        True ->
                                          Decision(
                                            ..base(request),
                                            kind: KindRemote,
                                            tier: grant.tier,
                                            reason: "remote_authorized:"
                                            <> grant.grant_id,
                                            attempts: attempts,
                                            grant: Some(grant),
                                          )
                                      }
                                  }
                              }
                          }
                      }
                  }
              }
            }
          }
      }
  }
}

fn escalate(
  request: RouteRequest,
  run: LocalRun,
  grant: Option(RemoteGrant),
  now_utc_ms: Int,
) -> Decision {
  case request.strategy {
    SovereignOnly -> hold(request, run.attempts, "sovereign_only_forbids_remote")
    ZeroCostPreferFree | LowLatencyLocalFirst ->
      case grant {
        None -> hold(request, run.attempts, "no_remote_grant:" <> run.failure)
        Some(g) -> try_remote(request, run.attempts, g, now_utc_ms)
      }
  }
}

/// The single routing entry point. Deterministic: the clock is injected.
pub fn route(
  request: RouteRequest,
  probe: LocalProbe,
  grant: Option(RemoteGrant),
  now_utc_ms: Int,
) -> Decision {
  let run = run_local(probe)
  case run.violation {
    Some(field) ->
      Decision(
        ..base(request),
        kind: KindRejected,
        tier: Tier0Simd,
        reason: "local_contract_violation:" <> field,
        attempts: run.attempts,
        grant: None,
      )
    None ->
      case request.origin {
        Child(_parent, child_tenant) ->
          case child_tenant == request.tenant {
            False ->
              Decision(
                ..base(request),
                kind: KindRejected,
                reason: "child_tenant_mismatch:" <> child_tenant,
                attempts: run.attempts,
                grant: None,
              )
            True -> decide(request, run, grant, now_utc_ms)
          }
        Ingress | Retry(_) -> decide(request, run, grant, now_utc_ms)
      }
  }
}

fn decide(
  request: RouteRequest,
  run: LocalRun,
  grant: Option(RemoteGrant),
  now_utc_ms: Int,
) -> Decision {
  case run.resolved {
    Some(#(tier, confidence_milli)) ->
      Decision(
        ..base(request),
        kind: KindLocal,
        tier: tier,
        confidence_milli: confidence_milli,
        reason: "local_resolved@" <> tier_label(tier),
        attempts: run.attempts,
        grant: None,
      )
    None -> escalate(request, run, grant, now_utc_ms)
  }
}

// ---------------------------------------------------------------------------
// Ledger — the authority that turns decisions into the 80% / $0 claim
// ---------------------------------------------------------------------------

pub type Account {
  Account(
    request_id: String,
    logical_id: String,
    tenant: String,
    kind: DecisionKind,
    tier: Tier,
    remote_prompt_tokens: Int,
    remote_completion_tokens: Int,
  )
}

pub type Ledger {
  Ledger(accounts: List(Account))
}

pub fn empty_ledger() -> Ledger {
  Ledger(accounts: [])
}

pub fn find_account(ledger: Ledger, request_id: String) -> Option(Account) {
  case list.find(ledger.accounts, fn(a) { a.request_id == request_id }) {
    Ok(account) -> Some(account)
    Error(Nil) -> None
  }
}

pub fn record(ledger: Ledger, decision: Decision) -> Result(Ledger, String) {
  case find_account(ledger, decision.request_id) {
    Some(_) -> Error("duplicate_request_id:" <> decision.request_id)
    None ->
      Ok(
        Ledger(
          accounts: list.append(ledger.accounts, [
            Account(
              request_id: decision.request_id,
              logical_id: decision.logical_id,
              tenant: decision.tenant,
              kind: decision.kind,
              tier: decision.tier,
              remote_prompt_tokens: 0,
              remote_completion_tokens: 0,
            ),
          ]),
        ),
      )
  }
}

fn replace_account(
  accounts: List(Account),
  request_id: String,
  replacement: Account,
) -> List(Account) {
  list.map(accounts, fn(a) {
    case a.request_id == request_id {
      True -> replacement
      False -> a
    }
  })
}

/// Record OBSERVED provider usage for a request.
///
/// This deliberately overrides the recorded kind with `KindRemote`. If any code
/// path sends remote tokens for a request that the router had labelled local or
/// held, the ledger flips to remote and the locality claim fails. Usage for an
/// unknown request id is refused rather than dropped — an unattributable token
/// charge is exactly the gap that would let the 80% denominator lie.
pub fn record_remote_usage(
  ledger: Ledger,
  request_id: String,
  prompt_tokens: Int,
  completion_tokens: Int,
) -> Result(Ledger, String) {
  case prompt_tokens < 0 || completion_tokens < 0 {
    True -> Error("negative_usage:" <> request_id)
    False ->
      case find_account(ledger, request_id) {
        None -> Error("unknown_request_id:" <> request_id)
        Some(existing) ->
          Ok(
            Ledger(
              accounts: replace_account(ledger.accounts, request_id, Account(
                ..existing,
                kind: KindRemote,
                remote_prompt_tokens: existing.remote_prompt_tokens
                + prompt_tokens,
                remote_completion_tokens: existing.remote_completion_tokens
                + completion_tokens,
              )),
            ),
          )
      }
  }
}

pub type LogicalOutcome {
  LogicalOutcome(
    logical_id: String,
    kind: DecisionKind,
    attempts: Int,
    remote_prompt_tokens: Int,
    remote_completion_tokens: Int,
  )
}

/// Collapse attempts onto their logical request.
///
/// A logical request counts as local ONLY if at least one attempt resolved
/// locally and NO attempt of that logical request spent remote tokens. This is
/// the rule that stops a "local" request with a remote retry from inflating the
/// headline number.
fn combine_logical(logical_id: String, accounts: List(Account)) -> LogicalOutcome {
  let prompt_tokens =
    list.fold(accounts, 0, fn(acc, a) { acc + a.remote_prompt_tokens })
  let completion_tokens =
    list.fold(accounts, 0, fn(acc, a) { acc + a.remote_completion_tokens })
  let any_remote = list.any(accounts, fn(a) { a.kind == KindRemote })
  let any_rejected = list.any(accounts, fn(a) { a.kind == KindRejected })
  let any_local = list.any(accounts, fn(a) { a.kind == KindLocal })
  let spent = prompt_tokens > 0 || completion_tokens > 0
  let kind = case any_remote || spent {
    True -> KindRemote
    False ->
      case any_rejected {
        True -> KindRejected
        False ->
          case any_local {
            True -> KindLocal
            False -> KindHeld
          }
      }
  }
  LogicalOutcome(
    logical_id: logical_id,
    kind: kind,
    attempts: list.length(accounts),
    remote_prompt_tokens: prompt_tokens,
    remote_completion_tokens: completion_tokens,
  )
}

pub fn logical_outcomes(ledger: Ledger) -> List(LogicalOutcome) {
  list.group(ledger.accounts, by: fn(a) { a.logical_id })
  |> dict.to_list
  |> list.map(fn(entry) { combine_logical(entry.0, entry.1) })
  |> list.sort(fn(a, b) { string.compare(a.logical_id, b.logical_id) })
}

pub type Summary {
  Summary(
    total_logical_requests: Int,
    local_resolved: Int,
    held: Int,
    remote: Int,
    rejected: Int,
    remote_prompt_tokens: Int,
    remote_completion_tokens: Int,
    local_resolution_bps: Int,
  )
}

pub fn summarize(ledger: Ledger) -> Summary {
  let outcomes = logical_outcomes(ledger)
  let count = fn(kind: DecisionKind) {
    list.length(list.filter(outcomes, fn(o) { o.kind == kind }))
  }
  let local = count(KindLocal)
  let total = list.length(outcomes)
  let prompt_tokens =
    list.fold(outcomes, 0, fn(acc, o) { acc + o.remote_prompt_tokens })
  let completion_tokens =
    list.fold(outcomes, 0, fn(acc, o) { acc + o.remote_completion_tokens })
  let bps = case total {
    0 -> 0
    _ -> { local * 10000 } / total
  }
  Summary(
    total_logical_requests: total,
    local_resolved: local,
    held: count(KindHeld),
    remote: count(KindRemote),
    rejected: count(KindRejected),
    remote_prompt_tokens: prompt_tokens,
    remote_completion_tokens: completion_tokens,
    local_resolution_bps: bps,
  )
}

/// Falsifiers for the headline claim. An empty list is the only passing value.
pub fn locality_falsifiers(ledger: Ledger) -> List(String) {
  list.filter(ledger.accounts, fn(a) {
    a.kind == KindLocal
    && a.remote_prompt_tokens + a.remote_completion_tokens > 0
  })
  |> list.map(fn(a) { "local_account_with_remote_tokens:" <> a.request_id })
}

/// Acceptance gate for the token objective. Fails closed on an empty ledger: a
/// denominator of zero is not a 100% local-resolution rate.
pub fn check_local_resolution_gate(
  summary: Summary,
  target_bps: Int,
) -> Result(Nil, String) {
  case summary.total_logical_requests {
    0 -> Error("no_requests_accounted")
    _ ->
      case summary.local_resolution_bps >= target_bps {
        False ->
          Error(
            "local_resolution_below_target:"
            <> int.to_string(summary.local_resolution_bps)
            <> "<"
            <> int.to_string(target_bps),
          )
        True -> Ok(Nil)
      }
  }
}

// ---------------------------------------------------------------------------
// Operator surfaces
// ---------------------------------------------------------------------------

pub fn decision_to_json(decision: Decision) -> json.Json {
  json.object([
    #("request_id", json.string(decision.request_id)),
    #("logical_id", json.string(decision.logical_id)),
    #("tenant", json.string(decision.tenant)),
    #("kind", json.string(kind_label(decision.kind))),
    #("tier", json.string(tier_label(decision.tier))),
    #("confidence_milli", json.int(decision.confidence_milli)),
    #("reason", json.string(decision.reason)),
    #(
      "attempts",
      json.array(decision.attempts, fn(a) { json.string(attempt_label(a)) }),
    ),
    #(
      "remote_authorized",
      json.bool(is_remote(decision.tier) && decision.kind == KindRemote),
    ),
  ])
}

pub fn summary_to_json(summary: Summary) -> json.Json {
  json.object([
    #(
      "total_logical_requests",
      json.int(summary.total_logical_requests),
    ),
    #("local_resolved", json.int(summary.local_resolved)),
    #("held", json.int(summary.held)),
    #("remote", json.int(summary.remote)),
    #("rejected", json.int(summary.rejected)),
    #("remote_prompt_tokens", json.int(summary.remote_prompt_tokens)),
    #(
      "remote_completion_tokens",
      json.int(summary.remote_completion_tokens),
    ),
    #("local_resolution_bps", json.int(summary.local_resolution_bps)),
    #("target_bps", json.int(local_resolution_target_bps)),
    #("ev_ceiling", json.int(admission_ev_ceiling)),
  ])
}

pub fn render_summary(summary: Summary) -> String {
  "local_first_cascade{total="
  <> int.to_string(summary.total_logical_requests)
  <> " local="
  <> int.to_string(summary.local_resolved)
  <> " held="
  <> int.to_string(summary.held)
  <> " remote="
  <> int.to_string(summary.remote)
  <> " rejected="
  <> int.to_string(summary.rejected)
  <> " local_bps="
  <> int.to_string(summary.local_resolution_bps)
  <> " target_bps="
  <> int.to_string(local_resolution_target_bps)
  <> " remote_tokens="
  <> int.to_string(
    summary.remote_prompt_tokens + summary.remote_completion_tokens,
  )
  <> "}"
}

/// Deterministic ordering helper used by dashboards that list outcomes.
pub fn sort_outcomes(outcomes: List(LogicalOutcome)) -> List(LogicalOutcome) {
  list.sort(outcomes, fn(a, b) { string.compare(a.logical_id, b.logical_id) })
}

/// Explicitly unused-import guard for `order`; `list.sort` relies on the
/// `Order` type returned by `string.compare`.
pub fn order_is_lower(a: String, b: String) -> Bool {
  case string.compare(a, b) {
    order.Lt -> True
    order.Eq | order.Gt -> False
  }
}

/// Convenience map from logical id to outcome for O(1) dashboard lookup.
pub fn outcomes_by_id(
  ledger: Ledger,
) -> Dict(String, LogicalOutcome) {
  dict.from_list(
    list.map(logical_outcomes(ledger), fn(o) { #(o.logical_id, o) }),
  )
}
