//// Falsifiers for the local-first cascade acceptance claim (task `mt/mt3`)
//// #fractal-l2 #fractal-l4
////
//// STAMP: `SC-ROUTING-001`, `SC-PROVENANCE-001`
////
//// Each test below is an attempt to make the headline claim ("locally resolved
//// work spends zero remote tokens") false. The gate is only worth something if
//// these attempts fail.

import cepaf_gleam/ai/local_first_cascade.{
  Attempt, Child, Ingress, KindHeld, KindLocal, KindRejected, KindRemote,
  LocalProbe, LowLatencyLocalFirst, ProbeContractViolation, ProbeError,
  ProbeLowConfidence, ProbeNotAttempted, ProbeOk, ProbeTimeout, ProbeUnavailable,
  RemoteGrant, Retry, RouteRequest, SovereignOnly, Tier0Simd, Tier1Compress,
  Tier2Max, Tier3FreeRemote, Tier4PaidRemote, ZeroCostPreferFree,
  check_local_resolution_gate, decision_to_json, empty_ledger,
  estimate_remote_cost_milli, estimate_tokens_from_bytes, locality_falsifiers,
  logical_outcomes, record, record_remote_usage, render_summary, route, summarize,
  type Decision, type Ledger, type LocalProbe as LocalProbeType,
  type ProbeOutcome, type RemoteGrant as RemoteGrantType, type RouteRequest,
  type Tier, validate_mcip_pin,
}
import cepaf_gleam/ecology/core_bionic_token_twin.{CtProseMd}
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{Some}
import gleam/string
import gleeunit/should

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const tenant = "tenant-alpha"
const layer = "L4"

fn req(id: String) -> RouteRequest {
  RouteRequest(
    request_id: id,
    logical_id: id,
    tenant: tenant,
    origin: Ingress,
    strategy: LowLatencyLocalFirst,
    layer_code: layer,
    prompt_bytes: 4000,
    max_completion_tokens: 1000,
    allow_paid: False,
  )
}

/// An envelope that is genuinely a compression receipt for `workload` at
/// `layer`: it compacted, preserved an anchor, and stays under the EV ceiling.
fn envelope(workload: String, layer_code: String) -> core_bionic_token_twin.McipV1Envelope {
  core_bionic_token_twin.McipV1Envelope(
    protocol_version: "MCIP/1.0",
    workload_id: workload,
    fractal_layer_code: layer_code,
    poodavr_stage: "O",
    content_class: CtProseMd,
    raw_bytes: 12_000,
    compacted_bytes: 400,
    critical_anchors_preserved: 3,
    re_read_required: False,
    kalman_horizon_turns: 1389,
    ev_ceiling: 93,
    wire_packet: "@MCIP/1.0{id="
      <> workload
      <> "|L="
      <> layer_code
      <> "|P=O|cls=CT_PROSE_MD|ratio_x10=24|kl_max_milli=31|Pi_ready=1}\n"
      <> "@MCIP_FORECAST{H_rem=1389_turns}\nanchor-1\nanchor-2\n"
      <> "@MCIP_DECISION{re_read_required=false|ev_ceiling=EV-93|action=PROCEED_BOUNDED}",
  )
}

fn live_grant(workload: String, tier: Tier) -> RemoteGrantType {
  RemoteGrant(
    grant_id: "grant-alpha-1",
    tenant: tenant,
    tier: tier,
    max_usd_milli: 100,
    expires_utc_ms: 10_000,
    mcip: Some(envelope(workload, layer)),
  )
}

fn local_ok(confidence: Int) -> ProbeOutcome {
  ProbeOk(confidence, 120)
}

fn all_fail() -> LocalProbeType {
  LocalProbe(
    simd: ProbeLowConfidence(310, 120),
    compress: ProbeTimeout(900),
    max: ProbeUnavailable,
  )
}

// ---------------------------------------------------------------------------
// Local resolution: the good path must never touch a provider
// ---------------------------------------------------------------------------

pub fn tier0_resolves_locally_test() {
  let decision =
    route(req("r1"), LocalProbe(
      simd: local_ok(950),
      compress: ProbeNotAttempted,
      max: ProbeNotAttempted,
    ), option.None, 0)
  decision.kind |> should.equal(KindLocal)
  decision.tier |> should.equal(Tier0Simd)
  decision.confidence_milli |> should.equal(950)
}

pub fn local_promotion_resolves_at_tier1_test() {
  let decision =
    route(req("r2"), LocalProbe(
      simd: ProbeLowConfidence(400, 90),
      compress: local_ok(820),
      max: ProbeNotAttempted,
    ), option.None, 0)
  decision.kind |> should.equal(KindLocal)
  decision.tier |> should.equal(Tier1Compress)
  // Both local attempts are recorded, so the promotion is visible in evidence.
  decision.attempts |> list.length
  |> should.equal(2)
}

pub fn confidence_below_floor_is_not_a_resolution_test() {
  // 699 is one milli-point under the documented floor of 700.
  let decision =
    route(req("r3"), LocalProbe(
      simd: local_ok(699),
      compress: ProbeNotAttempted,
      max: ProbeNotAttempted,
    ), option.None, 0)
  decision.kind |> should.equal(KindHeld)
}

// ---------------------------------------------------------------------------
// Held: no implicit escalation
// ---------------------------------------------------------------------------

pub fn local_failure_holds_without_grant_test() {
  let decision = route(req("r4"), all_fail(), option.None, 0)
  decision.kind |> should.equal(KindHeld)
  decision.grant |> should.equal(option.None)
  // The reason names the deepest failure: max was unavailable, after the simd
  // low-confidence and the compress timeout. All three are in `attempts`.
  decision.reason |> should.equal("no_remote_grant:unavailable@tier2_max")
}

pub fn retry_origin_still_holds_without_grant_test() {
  let retry =
    RouteRequest(
      ..req("r5"),
      logical_id: "logical-5",
      origin: Retry("logical-5"),
    )
  route(retry, all_fail(), option.None, 0).kind |> should.equal(KindHeld)
}

pub fn sovereign_only_forbids_remote_even_with_grant_test() {
  let sovereign = RouteRequest(..req("r6"), strategy: SovereignOnly)
  let decision =
    route(sovereign, all_fail(), option.Some(live_grant("r6", Tier3FreeRemote)), 0)
  decision.kind |> should.equal(KindHeld)
  decision.reason |> should.equal("sovereign_only_forbids_remote")
}

pub fn zero_cost_strategy_also_needs_a_grant_test() {
  let zero_cost = RouteRequest(..req("r7"), strategy: ZeroCostPreferFree)
  route(zero_cost, all_fail(), option.None, 0).kind
  |> should.equal(KindHeld)
}

// ---------------------------------------------------------------------------
// Remote: every precondition is individually load-bearing
// ---------------------------------------------------------------------------

pub fn authorized_remote_requires_pinned_mcip_test() {
  let decision =
    route(req("r8"), all_fail(), option.Some(live_grant("r8", Tier3FreeRemote)), 0)
  decision.kind |> should.equal(KindRemote)
  decision.tier |> should.equal(Tier3FreeRemote)
  decision.reason |> should.equal("remote_authorized:grant-alpha-1")
}

pub fn remote_refused_when_mcip_missing_test() {
  let bare =
    RemoteGrant(
      grant_id: "g",
      tenant: tenant,
      tier: Tier3FreeRemote,
      max_usd_milli: 100,
      expires_utc_ms: 10_000,
      mcip: option.None,
    )
  let decision = route(req("r9"), all_fail(), option.Some(bare), 0)
  decision.kind |> should.equal(KindHeld)
  decision.reason |> should.equal("mcip_receipt_missing")
}

pub fn remote_refused_on_workload_mismatch_test() {
  // Receipt for a DIFFERENT logical request must not authorize this one.
  let decision =
    route(req("r10"), all_fail(), option.Some(live_grant("other", Tier3FreeRemote)), 0)
  decision.kind |> should.equal(KindHeld)
  decision.reason |> should.equal("mcip_workload_mismatch:other!=r10")
}

pub fn remote_refused_on_layer_mismatch_test() {
  let wrong_layer =
    RemoteGrant(
      grant_id: "g",
      tenant: tenant,
      tier: Tier3FreeRemote,
      max_usd_milli: 100,
      expires_utc_ms: 10_000,
      mcip: option.Some(envelope("r11", "L7")),
    )
  let decision = route(req("r11"), all_fail(), option.Some(wrong_layer), 0)
  decision.kind |> should.equal(KindHeld)
  decision.reason |> should.equal("mcip_layer_mismatch:L7!=L4")
}

pub fn remote_refused_on_tenant_mismatch_test() {
  let foreign =
    RemoteGrant(
      ..live_grant("r12", Tier3FreeRemote),
      tenant: "tenant-beta",
    )
  route(req("r12"), all_fail(), option.Some(foreign), 0).reason
  |> should.equal("grant_tenant_mismatch:tenant-beta")
}

pub fn remote_refused_on_expired_grant_test() {
  let decision =
    route(req("r13"), all_fail(), option.Some(live_grant("r13", Tier3FreeRemote)), 10_000)
  decision.kind |> should.equal(KindHeld)
  decision.reason |> should.equal("grant_expired:grant-alpha-1")
}

pub fn remote_refused_on_budget_test() {
  // 4000 bytes -> 1000 prompt tokens; 1000 completion tokens. At 3/15 milli-USD
  // per 1k tokens the paid tier costs 3 + 15 = 18 milli-USD.
  estimate_remote_cost_milli(4000, 1000, Tier4PaidRemote)
  |> should.equal(18)
  let thin = RemoteGrant(
    ..live_grant("r14", Tier4PaidRemote),
    max_usd_milli: 17,
  )
  let paid = RouteRequest(..req("r14"), allow_paid: True)
  route(paid, all_fail(), option.Some(thin), 0).reason
  |> should.equal("grant_budget_exceeded:18>17")
}

pub fn paid_tier_requires_explicit_permission_test() {
  let decision =
    route(req("r15"), all_fail(), option.Some(live_grant("r15", Tier4PaidRemote)), 0)
  decision.kind |> should.equal(KindHeld)
  decision.reason |> should.equal("paid_tier_not_permitted")
}

pub fn local_tier_grant_is_not_a_remote_grant_test() {
  let mislabelled = live_grant("r16", Tier2Max)
  route(req("r16"), all_fail(), option.Some(mislabelled), 0).reason
  |> should.equal("grant_tier_is_local:tier2_max")
}

pub fn empty_prompt_cannot_go_remote_test() {
  let blank = RouteRequest(..req("r17"), prompt_bytes: 0)
  route(blank, all_fail(), option.Some(live_grant("r17", Tier3FreeRemote)), 0).reason
  |> should.equal("empty_prompt")
}

// ---------------------------------------------------------------------------
// Envelope validation
// ---------------------------------------------------------------------------

pub fn valid_envelope_passes_pin_test() {
  validate_mcip_pin(envelope("w1", layer)) |> should.equal(Ok(Nil))
}

pub fn ev_ceiling_above_admission_is_refused_test() {
  // An envelope claiming EV-108 is not admissible evidence (SC-PROVENANCE-001).
  let forged = core_bionic_token_twin.McipV1Envelope(..envelope("w2", layer), ev_ceiling: 108)
  case validate_mcip_pin(forged) {
    Ok(_) -> should.fail()
    Error(reason) ->
      reason |> should.equal("mcip_ev_ceiling_exceeds_admission:108>93")
  }
}

pub fn receipt_that_did_not_compact_is_refused_test() {
  let inert = core_bionic_token_twin.McipV1Envelope(..envelope("w3", layer), compacted_bytes: 12_000)
  case validate_mcip_pin(inert) {
    Ok(_) -> should.fail()
    Error(reason) -> reason |> should.equal("mcip_did_not_compact:12000>=12000")
  }
}

pub fn receipt_requiring_re_read_is_refused_test() {
  let unsafe = core_bionic_token_twin.McipV1Envelope(..envelope("w4", layer), re_read_required: True)
  case validate_mcip_pin(unsafe) {
    Ok(_) -> should.fail()
    Error(reason) ->
      string.contains(reason, "mcip_requires_re_read") |> should.be_true
  }
}

pub fn receipt_without_anchors_is_refused_test() {
  let lossy = core_bionic_token_twin.McipV1Envelope(..envelope("w5", layer), critical_anchors_preserved: 0)
  case validate_mcip_pin(lossy) {
    Ok(_) -> should.fail()
    Error(reason) -> reason |> should.equal("mcip_no_anchors_preserved")
  }
}

pub fn receipt_with_bad_prefix_is_refused_test() {
  let bad =
    core_bionic_token_twin.McipV1Envelope(
      ..envelope("w6", layer),
      wire_packet: "@MCIP/2.0{id=w6}",
    )
  case validate_mcip_pin(bad) {
    Ok(_) -> should.fail()
    Error(reason) -> {
      // Both prefix checks fail and both are reported, not just the first.
      should.be_true(string.contains(reason, "mcip_prefix_header_missing"))
      should.be_true(string.contains(reason, "mcip_prefix_pi_ready_missing"))
    }
  }
}

// ---------------------------------------------------------------------------
// Rejection: a client defect is not a routing failure
// ---------------------------------------------------------------------------

pub fn contract_violation_is_rejected_not_held_test() {
  let decision =
    route(req("r18"), LocalProbe(
      simd: ProbeContractViolation("prompt_bytes"),
      compress: ProbeNotAttempted,
      max: ProbeNotAttempted,
    ), option.Some(live_grant("r18", Tier3FreeRemote)), 0)
  decision.kind |> should.equal(KindRejected)
  decision.reason |> should.equal("local_contract_violation:prompt_bytes")
}

pub fn probe_error_does_not_leak_into_remote_test() {
  let decision =
    route(req("r19"), LocalProbe(
      simd: ProbeError("EXIT_11"),
      compress: ProbeNotAttempted,
      max: ProbeNotAttempted,
    ), option.None, 0)
  decision.kind |> should.equal(KindHeld)
  decision.reason |> should.equal("no_remote_grant:not_attempted@tier2_max")
  // The underlying error is preserved verbatim rather than flattened away.
  decision.attempts
  |> should.equal([
    Attempt(Tier0Simd, ProbeError("EXIT_11")),
    Attempt(Tier1Compress, ProbeNotAttempted),
    Attempt(Tier2Max, ProbeNotAttempted),
  ])
}

pub fn child_tenant_mismatch_is_rejected_test() {
  let child =
    RouteRequest(
      ..req("r20"),
      origin: Child("parent-20", "tenant-beta"),
    )
  route(child, LocalProbe(
    simd: local_ok(990),
    compress: ProbeNotAttempted,
    max: ProbeNotAttempted,
  ), option.None, 0).kind
  |> should.equal(KindRejected)
}

// ---------------------------------------------------------------------------
// Ledger: the accounting cannot lie
// ---------------------------------------------------------------------------

fn ledger_with(decisions: List(Decision)) -> Ledger {
  decisions
  |> list.fold(empty_ledger(), fn(l, d) {
    case record(l, d) {
      Ok(next) -> next
      Error(_) -> l
    }
  })
}

pub fn duplicate_request_id_is_refused_test() {
  let local =
    route(req("r21"), LocalProbe(
      simd: local_ok(990),
      compress: ProbeNotAttempted,
      max: ProbeNotAttempted,
    ), option.None, 0)
  let first = record(empty_ledger(), local)
  case first {
    Error(_) -> should.fail()
    Ok(l) ->
      case record(l, local) {
        Ok(_) -> should.fail()
        Error(reason) ->
          reason |> should.equal("duplicate_request_id:r21")
      }
  }
}

pub fn unknown_request_usage_is_refused_test() {
  case record_remote_usage(empty_ledger(), "r99", 10, 10) {
    Ok(_) -> should.fail()
    Error(reason) -> reason |> should.equal("unknown_request_id:r99")
  }
}

/// THE central falsifier. A request labelled local must flip to remote the
/// moment observed provider usage is recorded against it. If this passes with a
/// local label intact, the 80% figure is meaningless.
pub fn remote_usage_overrides_local_label_test() {
  let local =
    route(req("r22"), LocalProbe(
      simd: local_ok(990),
      compress: ProbeNotAttempted,
      max: ProbeNotAttempted,
    ), option.None, 0)
  let assert Ok(l1) = record(empty_ledger(), local)
  let assert Ok(l2) = record_remote_usage(l1, "r22", 700, 40)

  // Recording usage flips the label, so the invariant never had to fire.
  locality_falsifiers(l2) |> should.equal([])
  case list.first(l2.accounts) {
    Ok(a) -> a.kind |> should.equal(KindRemote)
    Error(Nil) -> should.fail()
  }

  // The falsifier is defence in depth: forge the defective state directly and
  // confirm it IS detected. Without this the empty list above proves nothing.
  let forged =
    local_first_cascade.Ledger(accounts: [
      local_first_cascade.Account(
        request_id: "r22",
        logical_id: "r22",
        tenant: tenant,
        kind: KindLocal,
        tier: Tier0Simd,
        remote_prompt_tokens: 700,
        remote_completion_tokens: 0,
      ),
    ])
  locality_falsifiers(forged)
  |> should.equal(["local_account_with_remote_tokens:r22"])

  let summary = summarize(l2)
  summary.local_resolved |> should.equal(0)
  summary.remote |> should.equal(1)
  summary.remote_prompt_tokens |> should.equal(700)
  summary.local_resolution_bps |> should.equal(0)
}

pub fn usage_accumulates_across_records_test() {
  let local =
    route(req("r23"), LocalProbe(
      simd: local_ok(990),
      compress: ProbeNotAttempted,
      max: ProbeNotAttempted,
    ), option.None, 0)
  let assert Ok(l1) = record(empty_ledger(), local)
  let assert Ok(l2) = record_remote_usage(l1, "r23", 500, 0)
  let assert Ok(l3) = record_remote_usage(l2, "r23", 0, 250)
  let summary = summarize(l3)
  summary.remote_prompt_tokens |> should.equal(500)
  summary.remote_completion_tokens |> should.equal(250)
}

/// A logical request with one local attempt and one remote retry is REMOTE.
/// Counting it as local would inflate the headline number.
pub fn retry_that_spent_remote_breaks_locality_test() {
  let first =
    route(req("r24"), LocalProbe(
      simd: local_ok(990),
      compress: ProbeNotAttempted,
      max: ProbeNotAttempted,
    ), option.None, 0)
  let retry =
    route(
      RouteRequest(..req("r24b"), logical_id: "r24", origin: Retry("r24")),
      all_fail(),
      // The receipt attests the LOGICAL request, not the retry's own id.
      option.Some(live_grant("r24", Tier3FreeRemote)),
      0,
    )
  retry.kind |> should.equal(KindRemote)
  let ledger = ledger_with([first, retry])
  let outcomes = logical_outcomes(ledger)
  outcomes |> list.length |> should.equal(1)
  case outcomes {
    [only] -> {
      only.kind |> should.equal(KindRemote)
      only.attempts |> should.equal(2)
    }
    _ -> should.fail()
  }
  summarize(ledger).local_resolved |> should.equal(0)
}

pub fn local_only_retries_count_as_local_test() {
  let first =
    route(req("r25"), LocalProbe(
      simd: ProbeTimeout(120),
      compress: ProbeNotAttempted,
      max: ProbeNotAttempted,
    ), option.None, 0)
  let second =
    route(
      RouteRequest(..req("r25b"), logical_id: "r25", origin: Retry("r25")),
      LocalProbe(
        simd: local_ok(880),
        compress: ProbeNotAttempted,
        max: ProbeNotAttempted,
      ),
      option.None,
      0,
    )
  let summary = summarize(ledger_with([first, second]))
  summary.local_resolved |> should.equal(1)
  summary.remote_prompt_tokens + summary.remote_completion_tokens
  |> should.equal(0)
}

// ---------------------------------------------------------------------------
// Acceptance gate
// ---------------------------------------------------------------------------

pub fn empty_ledger_does_not_pass_the_gate_test() {
  case check_local_resolution_gate(summarize(empty_ledger()), 8000) {
    Ok(_) -> should.fail()
    Error(reason) -> reason |> should.equal("no_requests_accounted")
  }
}

/// 8 of 10 local is exactly the 80% target; 7 of 10 is not.
pub fn eighty_percent_gate_test() {
  let local = fn(id: String) {
    route(req(id), LocalProbe(
      simd: local_ok(900),
      compress: ProbeNotAttempted,
      max: ProbeNotAttempted,
    ), option.None, 0)
  }
  let held = fn(id: String) { route(req(id), all_fail(), option.None, 0) }
  let passing =
    ledger_with([
      local("a1"), local("a2"), local("a3"), local("a4"), local("a5"), local("a6"),
      local("a7"), local("a8"), held("a9"), held("a10"),
    ])
  summarize(passing).local_resolution_bps |> should.equal(8000)
  check_local_resolution_gate(summarize(passing), 8000)
  |> should.equal(Ok(Nil))

  let failing =
    ledger_with([
      local("b1"), local("b2"), local("b3"), local("b4"), local("b5"), local("b6"),
      local("b7"), held("b8"), held("b9"), held("b10"),
    ])
  summarize(failing).local_resolution_bps |> should.equal(7000)
  case check_local_resolution_gate(summarize(failing), 8000) {
    Ok(_) -> should.fail()
    Error(reason) ->
      reason |> should.equal("local_resolution_below_target:7000<8000")
  }
}

// ---------------------------------------------------------------------------
// Estimation
// ---------------------------------------------------------------------------

pub fn token_estimate_has_no_phantom_floor_test() {
  // The previous heuristic floored to 1 token, which bills empty input.
  estimate_tokens_from_bytes(0) |> should.equal(0)
  estimate_tokens_from_bytes(-5) |> should.equal(0)
  estimate_tokens_from_bytes(1) |> should.equal(1)
  estimate_tokens_from_bytes(4) |> should.equal(1)
  estimate_tokens_from_bytes(5) |> should.equal(2)
  estimate_tokens_from_bytes(4000) |> should.equal(1000)
}

pub fn free_tier_costs_nothing_test() {
  estimate_remote_cost_milli(40_000, 4000, Tier3FreeRemote)
  |> should.equal(0)
}

// ---------------------------------------------------------------------------
// Operator surface
// ---------------------------------------------------------------------------

pub fn decision_json_reports_authorization_separately_test() {
  let decision =
    route(req("r26"), all_fail(), option.Some(live_grant("r26", Tier3FreeRemote)), 0)
  let rendered = decision_to_json(decision) |> json.to_string
  string.contains(rendered, "\"kind\":\"remote\"") |> should.be_true
  string.contains(rendered, "\"remote_authorized\":true") |> should.be_true

  let held = route(req("r27"), all_fail(), option.None, 0)
  decision_to_json(held) |> json.to_string
  |> string.contains("\"remote_authorized\":false")
  |> should.be_true
}

pub fn attempt_labels_are_machine_readable_test() {
  let decision =
    route(req("r28"), LocalProbe(
      simd: ProbeLowConfidence(400, 91),
      compress: ProbeOk(880, 210),
      max: ProbeNotAttempted,
    ), option.None, 0)
  decision.attempts
  |> should.equal([
    Attempt(Tier0Simd, ProbeLowConfidence(400, 91)),
    Attempt(Tier1Compress, ProbeOk(880, 210)),
  ])
}

pub fn summary_renders_key_values_test() {
  let summary = summarize(empty_ledger())
  render_summary(summary)
  |> should.equal(
    "local_first_cascade{total=0 local=0 held=0 remote=0 rejected=0 local_bps=0 target_bps=8000 remote_tokens=0}",
  )
}

pub fn int_module_is_used_for_reporting_test() {
  int.to_string(93) |> should.equal("93")
}
