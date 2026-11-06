import cepaf_gleam/ecology/core_biomorphic_fractal.{
  AnabolicParallel, AntigenForeignC3iFrame, AntigenProvenanceAboveEv93,
  BreakerClosed, BreakerHalfOpen, BreakerOpen, CatabolicCriticalPathOnly,
  HomeostaticZeroOrShift, ImmuneIsolateAndHeal,
  ImmuneQuarantineAndTripBreaker, ImmuneTolerateSelf, L0Constitutional,
  L9MetaEvolution, LayerAndonHold, LayerDegraded, LayerHealthy, LayerObservation,
  SelfCanonicalEnvelope, TorporMargin40Hold,
}
import cepaf_gleam/ecology/core_evolution.{
  BatchConductorWakeups, CodexCli, ConductorRole, ExecuteAttempt, FmeaFormalRole,
  FreshAttemptWorkspace, ImplRole, InitialDispatch, JidokaAndonHold,
  NormalDispatch, PiArgonGoogle, PiDeepSeekFlash, PiDeepSeekPro,
  QuarantineRollbackAchRcaAndPokaYoke,
  QuarantineRollbackStpaTpsArchitecturalPivot, QuotaAdmitted,
  QuotaHoldMargin40Pct, QuotaSnapshot, RcaTpsRole, SafetyBoundaryViolation,
  SovereignGateRole, TransientOrTestFailure, WorkspaceCorruption,
  WrongArchitecturalPath, ZeroOpenRouterAndBatchedWakeups, ZeroOpenRouterShift,
}
import cepaf_gleam/ecology/core_hive.{
  ArchitectSynthesizer, ForagerBuilder, HiveCellTask, NurseDiagnostician,
  PheromoneSignal, QueenConductor, QuorumAdmitted2oo3, QuorumAdmittedUnanimous,
  QuorumFailClosedHold, SovereignSentinel, TrailCorruptionQuarantine,
  TrailReadyPull,
}
import cepaf_gleam/ecology/core_bionic_token_twin.{
  CtFormalSpec, CtHighEntropy, CtJsonStruct, CtLogStream, CtProseMd,
  CtSourceAst, CtTabularCsv, CtUnifiedDiff, TokenHealthOptimal,
  TokenHealthRedflag, TokenTurnTelemetry,
}
import cepaf_gleam/ecology/core_fractal_holonic_simulator
import cepaf_gleam/ecology/core_fpp_actor_twin_mesh.{
  ActorIntentAccepted, ActorIntentRequest, ActorIntentVetoed, AdvisoryFreeTier,
  DeepAchRcaProTier, DispatchIntent, ImplementationFlashTier, InspectActor,
  OpenRouterBlockedEgressSafety, OpenRouterBlockedMargin40, OpenRouterDispatched,
  Otp29Verified, ReflexAutonomousSelfHeal, ShutdownActor,
}
import cepaf_gleam/uos_sup.{
  AppsDomain, EnginesDomain, IntelligenceDomain, ServicesDomain,
}
import cepaf_gleam/ecology/core_systems_engineering.{
  ErrModeFormalProofOrReteVeto, ErrModeHardwareOrProvenanceBreach,
  ErrModeLeaseOrHeartbeatExpired, ErrModeQuotaMargin40Breached,
  ErrModeSplitBrainForeignC3iFrame, ErrModeTransientTestOrBuild,
  ErrModeWorkspaceOrArtifactCorruption, ErrModeWrongArchitecturalPath,
  RiskBlockedPrecondition, RiskPrioritized, StanCalibrated, StanDiagnostics,
  StanTriggerFired, StpaUcaAnalysis, Trace13Vector,
}
import cepaf_gleam/ui/lustre/core_evo_cockpit
import cepaf_gleam/ui/tui/core_evo_view
import cepaf_gleam/ui/wisp/core_evo_api
import cepaf_gleam/zenoh/core_bus.{
  AuthCoreError, ErrDigestMismatch, ErrLegacySplitBrainTopic, ErrNonMonotonicSeq,
  ErrPayloadTooLarge, ErrProvenanceCeilingExceeded, SignedCoreEnvelope,
}
import gleam/erlang/process
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should

const sample_candidate_sha = "8fa6d05c909b8fa6d05c909b8fa6d05c909b8fa6d05c909b8fa6d05c909b0001"

@external(erlang, "core_bus_crypto_ffi", "concurrent_cold_start_unique_pubkeys_for_test")
fn ffi_concurrent_cold_start_unique_pubkeys(n: Int) -> Int

@external(erlang, "core_bus_crypto_ffi", "concurrent_replay_winners_for_test")
fn ffi_concurrent_replay_winners(
  wire_json: String,
  expected_pubkey_hex: String,
  n: Int,
) -> #(Int, Int)

@external(erlang, "core_bus_crypto_ffi", "reset_replay_table_for_test")
fn ffi_reset_replay_table() -> Nil

pub fn quota_margin_40pct_admits_exact_60pct_boundary_test() {
  let q =
    QuotaSnapshot(
      agy_5h_bps: 4000,
      agy_7d_bps: 6000,
      agy_30d_bps: 5999,
      openrouter_24h_nanodollars: 6_000_000_000,
    )
  case core_evolution.evaluate_quota_margin(q) {
    QuotaAdmitted(
      mode,
      min_remaining_margin_bps,
      openrouter_remaining_nanodollars,
    ) -> {
      should.equal(mode, ZeroOpenRouterAndBatchedWakeups)
      should.equal(min_remaining_margin_bps, 4000)
      should.equal(openrouter_remaining_nanodollars, 0)
    }
    QuotaHoldMargin40Pct(_) -> should.fail()
  }
}

pub fn quota_margin_40pct_holds_across_all_four_windows_above_60pct_test() {
  let q =
    QuotaSnapshot(
      agy_5h_bps: 6001,
      agy_7d_bps: 6100,
      agy_30d_bps: 6005,
      openrouter_24h_nanodollars: 6_000_000_001,
    )
  case core_evolution.evaluate_quota_margin(q) {
    QuotaHoldMargin40Pct(windows) -> should.equal(list.length(windows), 4)
    QuotaAdmitted(_, _, _) -> should.fail()
  }
}

pub fn quota_soft_shift_at_4_50_usd_switches_to_zero_openrouter_engines_test() {
  let q =
    QuotaSnapshot(
      agy_5h_bps: 1200,
      agy_7d_bps: 1800,
      agy_30d_bps: 2000,
      openrouter_24h_nanodollars: 4_500_000_000,
    )
  case core_evolution.evaluate_quota_margin(q) {
    QuotaAdmitted(mode, _, _) -> should.equal(mode, ZeroOpenRouterShift)
    _ -> should.fail()
  }

  case
    core_evolution.plan_attempt_step(
      task_id: "w1-oi07-fence",
      role: ImplRole,
      attempt: 1,
      failure: InitialDispatch,
      quota: q,
    )
  {
    ExecuteAttempt(
      attempt: 1,
      primary_engine: primary,
      reviewer_engine: reviewer,
      timeout_ms: timeout_ms,
      lease_ttl_ms: lease_ms,
      tool_timeout_ms: tool_ms,
      ..,
    ) -> {
      should.equal(primary, PiArgonGoogle)
      should.equal(reviewer, CodexCli)
      should.equal(timeout_ms, 3_600_000)
      should.equal(lease_ms, 14_400_000)
      should.equal(tool_ms, 1_800_000)
    }
    _ -> should.fail()
  }
}

pub fn three_attempt_corruption_rca_tps_escalation_and_andon_hold_test() {
  let nominal_q =
    QuotaSnapshot(
      agy_5h_bps: 800,
      agy_7d_bps: 1100,
      agy_30d_bps: 1500,
      openrouter_24h_nanodollars: 900_000_000,
    )
  case core_evolution.evaluate_quota_margin(nominal_q) {
    QuotaAdmitted(mode, _, _) -> should.equal(mode, NormalDispatch)
    _ -> should.fail()
  }

  case
    core_evolution.plan_attempt_step(
      task_id: "w1-oi02e",
      role: ImplRole,
      attempt: 1,
      failure: InitialDispatch,
      quota: nominal_q,
    )
  {
    ExecuteAttempt(
      attempt: 1,
      primary_engine: primary,
      timeout_ms: t1,
      strategy: strat1,
      workspace_suffix: ws1,
      ..,
    ) -> {
      should.equal(primary, PiDeepSeekFlash)
      should.equal(t1, 3_600_000)
      should.equal(strat1, FreshAttemptWorkspace)
      should.equal(ws1, "w1-oi02e-a1")
    }
    _ -> should.fail()
  }

  case
    core_evolution.plan_attempt_step(
      task_id: "w1-oi02e",
      role: ImplRole,
      attempt: 2,
      failure: WorkspaceCorruption("partial_beam_write"),
      quota: nominal_q,
    )
  {
    ExecuteAttempt(
      attempt: 2,
      primary_engine: primary2,
      reviewer_engine: rev2,
      timeout_ms: t2,
      strategy: strat2,
      workspace_suffix: ws2,
      ..,
    ) -> {
      should.equal(primary2, PiDeepSeekPro)
      should.equal(rev2, CodexCli)
      should.equal(t2, 5_400_000)
      should.equal(strat2, QuarantineRollbackAchRcaAndPokaYoke)
      should.equal(ws2, "w1-oi02e-a2")
    }
    _ -> should.fail()
  }

  case
    core_evolution.plan_attempt_step(
      task_id: "w1-oi02e",
      role: ImplRole,
      attempt: 3,
      failure: WrongArchitecturalPath("inverted_oi07_oi02_edge"),
      quota: nominal_q,
    )
  {
    ExecuteAttempt(
      attempt: 3,
      primary_engine: primary3,
      reviewer_engine: rev3,
      timeout_ms: t3,
      strategy: strat3,
      workspace_suffix: ws3,
      ..,
    ) -> {
      should.equal(primary3, PiArgonGoogle)
      should.equal(rev3, CodexCli)
      should.equal(t3, 7_200_000)
      should.equal(strat3, QuarantineRollbackStpaTpsArchitecturalPivot)
      should.equal(ws3, "w1-oi02e-a3")
    }
    _ -> should.fail()
  }

  case
    core_evolution.plan_attempt_step(
      task_id: "w1-oi02e",
      role: ImplRole,
      attempt: 4,
      failure: TransientOrTestFailure("still_failing"),
      quota: nominal_q,
    )
  {
    JidokaAndonHold(attempt: 4, reason: r, zenoh_alert_topic: topic) -> {
      should.be_true(string.contains(r, "JIDOKA_ANDON"))
      should.equal(topic, "uos/v1/rca/w1-oi02e/andon_hold")
    }
    _ -> should.fail()
  }
}

pub fn safety_boundary_violation_triggers_immediate_andon_hold_test() {
  let q = QuotaSnapshot(500, 500, 500, 100_000_000)
  case
    core_evolution.plan_attempt_step(
      task_id: "w2-cutover",
      role: SovereignGateRole,
      attempt: 1,
      failure: SafetyBoundaryViolation("default_at_codex_digest_drift"),
      quota: q,
    )
  {
    JidokaAndonHold(attempt: 1, reason: r, ..) ->
      should.be_true(string.contains(r, "HOLD_SAFETY_BOUNDARY"))
    _ -> should.fail()
  }
}

pub fn lease_4h_and_20m_heartbeat_freshness_test() {
  let t = core_evolution.maximized_timeouts()
  should.equal(t.lease_ttl_ms, 14_400_000)
  should.equal(t.heartbeat_interval_ms, 1_200_000)
  should.equal(t.stale_after_ms, 3_600_000)
  should.equal(t.soak_envelope_timeout_ms, 28_800_000)

  let now = 10_000_000
  should.be_true(core_evolution.is_lease_healthy(
    now_ms: now,
    lease_expires_ms: now + 10_800_000,
    last_heartbeat_ms: now - 1_200_000,
  ))
  should.be_false(core_evolution.is_lease_healthy(
    now_ms: now,
    lease_expires_ms: now + 10_800_000,
    last_heartbeat_ms: now - 3_600_001,
  ))
}

pub fn zero_muda_mcp_whitelist_and_512b_conductor_digest_bound_test() {
  let roles = [
    ImplRole,
    RcaTpsRole,
    SovereignGateRole,
    FmeaFormalRole,
    ConductorRole,
  ]
  list.each(roles, fn(r) {
    let tools = core_evolution.minimal_mcp_tools(r)
    should.be_true(list.length(tools) >= 5 && list.length(tools) <= 12)
    should.be_false(
      list.any(tools, fn(t) {
        string.contains(t, "stitch")
        || string.contains(t, "gdrive")
        || string.contains(t, "datacloud")
        || string.contains(t, "notebooks")
      }),
    )
  })

  let q =
    QuotaSnapshot(
      agy_5h_bps: 4600,
      agy_7d_bps: 2000,
      agy_30d_bps: 1500,
      openrouter_24h_nanodollars: 1_250_000_000,
    )
  case core_evolution.evaluate_quota_margin(q) {
    QuotaAdmitted(mode, _, _) -> should.equal(mode, BatchConductorWakeups)
    _ -> should.fail()
  }

  let long_note = string.repeat("wave-green-verified-", 20)
  let digest =
    core_evolution.encode_conductor_digest(
      wave: "w1-parallel-dev",
      status: "PASS",
      commit_id: "8fa6d05c909b",
      tests_passed: 425,
      quota: q,
      note: long_note,
    )
  should.be_true(
    string.byte_size(digest) <= core_evolution.max_conductor_digest_bytes,
  )
}

pub fn hive_heijunka_pheromone_decay_and_2oo3_sovereign_quorum_test() {
  let q = QuotaSnapshot(900, 1100, 1400, 800_000_000)

  // Pheromone half-life decay: 8000 bps decays to 2000 bps after 2 half-lives
  let sig =
    PheromoneSignal(
      cell_id: "w1a",
      kind: TrailReadyPull,
      intensity_bps: 8000,
      emitted_at_s: 1000,
      half_life_s: 300,
    )
  should.equal(core_hive.decayed_intensity_bps(sig, 1600), 2000)

  // Heijunka scheduler: caps ForagerBuilder at WIP=4, blocks quarantined L-B & unready W2
  let tasks = [
    HiveCellTask("w1a", ForagerBuilder, 900, True, True),
    HiveCellTask("w1b", NurseDiagnostician, 980, True, True),
    HiveCellTask("w1c", ForagerBuilder, 850, True, True),
    HiveCellTask("w1d", ForagerBuilder, 840, True, True),
    HiveCellTask("w1e", ForagerBuilder, 830, True, True),
    HiveCellTask("w1f-overflow", ForagerBuilder, 700, True, True),
    HiveCellTask("lb-quarantined", ForagerBuilder, 999, True, True),
    HiveCellTask("w2-unready", SovereignSentinel, 950, True, False),
  ]
  let pheromones = [
    sig,
    PheromoneSignal(
      cell_id: "lb-quarantined",
      kind: TrailCorruptionQuarantine,
      intensity_bps: 9000,
      emitted_at_s: 1500,
      half_life_s: 3600,
    ),
  ]
  let assert Ok(sched) =
    core_hive.schedule_heijunka_wave(tasks, pheromones, [], q, 1600)
  // 4 ForagerBuilders + 1 NurseDiagnostician = 5 admitted; w1f-overflow deferred by WIP=4; lb & w2 blocked
  should.equal(list.length(sched.admitted_tasks), 5)
  should.equal(sched.deferred_wip_tasks, ["w1f-overflow"])
  should.be_true(list.contains(sched.blocked_tasks, "lb-quarantined"))
  should.be_true(list.contains(sched.blocked_tasks, "w2-unready"))

  // 2oo3 Tri-Sovereign Quorum: Unanimous, 2oo3 Majority, and Sovereign HOLD veto
  case core_hive.evaluate_sovereign_quorum("rev:8fa6d", "rev:8fa6d", "rev:8fa6d") {
    QuorumAdmittedUnanimous("rev:8fa6d") -> Nil
    _ -> should.fail()
  }
  case core_hive.evaluate_sovereign_quorum("rev:8fa6d", "rev:8fa6d", "rev:other") {
    QuorumAdmitted2oo3("rev:8fa6d", _) -> Nil
    _ -> should.fail()
  }
  case core_hive.evaluate_sovereign_quorum("rev:8fa6d", "HOLD", "rev:8fa6d") {
    QuorumFailClosedHold(_) -> Nil
    _ -> should.fail()
  }
  // Generalized 2-of-4 Model Families + Operator Quorum (any 2 of Codex, AGY, Claude, Pi+Argon)
  case
    core_hive.evaluate_two_of_four_model_quorum(
      "",
      "",
      "rev:8fa6d",
      "rev:8fa6d",
      True,
    )
  {
    core_hive.QuorumAdmitted2oo4("rev:8fa6d", 2) -> Nil
    _ -> should.fail()
  }
  case
    core_hive.evaluate_two_of_four_model_quorum(
      "rev:8fa6d",
      "rev:8fa6d",
      "",
      "",
      False,
    )
  {
    QuorumFailClosedHold("operator_ratification_missing") -> Nil
    _ -> should.fail()
  }
  should.equal(
    core_hive.caste_engine(QueenConductor, q),
    Ok(core_evolution.AgyThinConductor),
  )
  should.equal(
    core_hive.caste_engine(ArchitectSynthesizer, q),
    Ok(PiArgonGoogle),
  )
  should.equal(core_hive.caste_engine(NurseDiagnostician, q), Ok(PiDeepSeekPro))
}

pub fn biomorphic_homeostasis_immune_breaker_lyapunov_and_10layer_fractal_poodavr_test() {
  // 1. Metabolic ATP regimes track remaining margin toward the 40% floor
  should.equal(
    core_biomorphic_fractal.classify_metabolic_regime(QuotaSnapshot(
      1000,
      1200,
      1500,
      500_000_000,
    )),
    AnabolicParallel,
  )
  should.equal(
    core_biomorphic_fractal.classify_metabolic_regime(QuotaSnapshot(
      5000,
      2000,
      2000,
      500_000_000,
    )),
    HomeostaticZeroOrShift,
  )
  should.equal(
    core_biomorphic_fractal.classify_metabolic_regime(QuotaSnapshot(
      5800,
      2000,
      2000,
      500_000_000,
    )),
    CatabolicCriticalPathOnly,
  )
  should.equal(
    core_biomorphic_fractal.classify_metabolic_regime(QuotaSnapshot(
      6001,
      2000,
      2000,
      500_000_000,
    )),
    TorporMargin40Hold,
  )

  // 2. Autonomic Immune Reflex + Prajna Circuit Breaker
  case
    core_biomorphic_fractal.evaluate_immune_reflex(SelfCanonicalEnvelope, 0)
  {
    ImmuneTolerateSelf(BreakerClosed) -> Nil
    _ -> should.fail()
  }
  case
    core_biomorphic_fractal.evaluate_immune_reflex(
      AntigenForeignC3iFrame("pid_9040_port_4200"),
      0,
    )
  {
    ImmuneIsolateAndHeal(_, BreakerHalfOpen(1)) -> Nil
    _ -> should.fail()
  }
  case
    core_biomorphic_fractal.evaluate_immune_reflex(
      AntigenProvenanceAboveEv93(108),
      0,
    )
  {
    ImmuneQuarantineAndTripBreaker(_, BreakerOpen("sc_provenance_001_violation")) ->
      Nil
    _ -> should.fail()
  }

  // 3. Discrete Lyapunov Stability Proof (dV/dt <= 0)
  let stable =
    core_biomorphic_fractal.evaluate_lyapunov_stability(
      v_prev: 520,
      failing_tasks: 0,
      stale_leases: 2,
      open_issues: 14,
      drift_events: 0,
    )
  should.be_true(stable.is_monotone_stable)
  should.be_true(stable.delta_v < 0)

  let diverging =
    core_biomorphic_fractal.evaluate_lyapunov_stability(
      v_prev: 100,
      failing_tasks: 2,
      stale_leases: 3,
      open_issues: 20,
      drift_events: 1,
    )
  should.be_false(diverging.is_monotone_stable)
  should.be_true(diverging.delta_v > 0)

  // 4. Full 10-Layer (L0..L9) Fractal x 7-Stage POODAVR Closure
  let layers = core_biomorphic_fractal.all_10_fractal_layers()
  should.equal(list.length(layers), 10)

  let all_green_obs =
    list.map(layers, fn(layer) {
      let verdict =
        core_biomorphic_fractal.run_layer_poodavr(
          layer,
          horizon_s: 14_400,
          topics_observed: 9,
          truth_level: 0.96,
          utility_score: 0.92,
          port_name: "uos_zlp_v3_port",
          formal_verified: True,
          brier_delta: -0.04,
        )
      LayerObservation(
        layer: layer,
        health: LayerHealthy,
        open_issues: 0,
        poodavr_verdict: verdict,
      )
    })
  should.equal(
    core_biomorphic_fractal.rollup_fractal_health(all_green_obs),
    LayerHealthy,
  )

  // Missing L9 -> LayerDegraded (zero green-washing)
  let missing_l9 =
    list.filter(all_green_obs, fn(o) { o.layer != L9MetaEvolution })
  case core_biomorphic_fractal.rollup_fractal_health(missing_l9) {
    LayerDegraded(_) -> Nil
    _ -> should.fail()
  }

  // Failed formal verification at L0 -> POODAVR Andon Halt -> whole-system LayerAndonHold
  let l0_fail_verdict =
    core_biomorphic_fractal.run_layer_poodavr(
      L0Constitutional,
      horizon_s: 14_400,
      topics_observed: 9,
      truth_level: 0.95,
      utility_score: 0.9,
      port_name: "uos_zlp_v3_port",
      formal_verified: False,
      brier_delta: 0.0,
    )
  let with_l0_fail = [
    LayerObservation(
      layer: L0Constitutional,
      health: LayerHealthy,
      open_issues: 1,
      poodavr_verdict: l0_fail_verdict,
    ),
    ..list.filter(all_green_obs, fn(o) { o.layer != L0Constitutional })
  ]
  case core_biomorphic_fractal.rollup_fractal_health(with_l0_fail) {
    LayerAndonHold(_) -> Nil
    _ -> should.fail()
  }
}

pub fn core_bus_rejects_legacy_c3i_split_brain_ev94_tamper_and_replay_test() {
  case
    core_bus.build_envelope(
      topic: "c3i/a2a/ets/poison",
      candidate_sha256: sample_candidate_sha,
      plan_id: "p1",
      task_id: "t1",
      worker_id: "w1",
      attempt: 1,
      seq_id: 1,
      ev_ceiling: 93,
      payload_json: "{\"ok\":true}",
    )
  {
    Error(ErrLegacySplitBrainTopic(_)) -> Nil
    _ -> should.fail()
  }

  case
    core_bus.build_envelope(
      topic: "uos/v1/saplan/p1/t1/a1/heartbeat",
      candidate_sha256: sample_candidate_sha,
      plan_id: "p1",
      task_id: "t1",
      worker_id: "w1",
      attempt: 1,
      seq_id: 1,
      ev_ceiling: 94,
      payload_json: "{\"ok\":true}",
    )
  {
    Error(ErrProvenanceCeilingExceeded(94)) -> Nil
    _ -> should.fail()
  }

  let bloated = "{\"blob\":\"" <> string.repeat("x", 600) <> "\"}"
  case
    core_bus.build_envelope(
      topic: "uos/v1/wave/w1/summary",
      candidate_sha256: sample_candidate_sha,
      plan_id: "p1",
      task_id: "w1",
      worker_id: "conductor",
      attempt: 1,
      seq_id: 1,
      ev_ceiling: 93,
      payload_json: bloated,
    )
  {
    Error(ErrPayloadTooLarge(_, 512)) -> Nil
    _ -> should.fail()
  }

  let assert Ok(valid_env) =
    core_bus.build_envelope(
      topic: "uos/v1/hive/pheromone/w1a",
      candidate_sha256: sample_candidate_sha,
      plan_id: "uos/master",
      task_id: "w1a",
      worker_id: "forager-flash",
      attempt: 1,
      seq_id: 10,
      ev_ceiling: 93,
      payload_json: "{\"intensity_bps\":8000}",
    )

  case core_bus.validate_envelope(valid_env, 10) {
    Error(ErrNonMonotonicSeq(10, 10)) -> Nil
    _ -> should.fail()
  }

  let tampered =
    SignedCoreEnvelope(..valid_env, payload_json: "{\"intensity_bps\":9999}")
  case core_bus.validate_envelope(tampered, 9) {
    Error(ErrDigestMismatch(_, _)) -> Nil
    _ -> should.fail()
  }
}

pub fn core_bus_publish_and_fetch_roundtrip_over_zlp_and_ets_test() {
  let q = QuotaSnapshot(900, 1200, 1400, 750_000_000)
  let digest =
    core_evolution.encode_conductor_digest(
      wave: "w0-core-evo",
      status: "PASS",
      commit_id: "8fa6d05c909b",
      tests_passed: 423,
      quota: q,
      note: "zlp-zenoh-ets-hive-fractal-verified",
    )
  let assert Ok(env) =
    core_bus.build_envelope(
      topic: "uos/v1/wave/w0_core_evo_test/summary",
      candidate_sha256: sample_candidate_sha,
      plan_id: "uos/agy-fractal-issue-resolution-master/20261101-1454",
      task_id: "w0-fenced-hygiene-reclaim",
      worker_id: "uos-core-evo",
      attempt: 1,
      seq_id: 77,
      ev_ceiling: 93,
      payload_json: digest,
    )

  let assert Ok(receipt) = core_bus.publish_verified(env)
  should.be_true(receipt.ets_buffered)
  should.equal(receipt.seq_id, 77)

  let assert Ok(fetched) =
    core_bus.fetch_verified("uos/v1/wave/w0_core_evo_test/summary", 76)
  should.equal(fetched.payload_sha256, env.payload_sha256)
  should.equal(fetched.payload_json, digest)
  should.equal(fetched.ev_ceiling, 93)
}

// =============================================================================
// UOS-CORE-EVO v2: Total Systems Engineering, Math, Control, Rete-UL, Stan,
// Fractal FMEA/STPA, FPP/SysML v2 & 8 Bionic Services Tests
// =============================================================================

pub fn systems_engineering_sheaf_h1_and_trace13_conservation_test() {
  should.be_true(core_systems_engineering.verify_sheaf_global_gluing(6, 1.0))

  let t0 = Trace13Vector([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 93], True)
  let t_drifted =
    Trace13Vector([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 94], True)
  let t_untrusted =
    Trace13Vector([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 93], False)

  should.be_true(core_systems_engineering.verify_trace13_conservation(t0, t0))
  should.be_false(
    core_systems_engineering.verify_trace13_conservation(t0, t_drifted),
  )
  should.be_false(
    core_systems_engineering.verify_trace13_conservation(t0, t_untrusted),
  )
}

pub fn stan_hmc_bayesian_pareto_and_11_domain_rete_ul_fusion_test() {
  // 1. Calibrated Stan HMC/NUTS gate + Gaussian/Beta conjugate update
  case
    core_systems_engineering.evaluate_stan_bayesian_gate(
      StanDiagnostics(
        r_hat: 1.003,
        effective_sample_size: 920,
        divergent_transitions: 0,
        brier_score: 0.09,
      ),
      0.92,
      0.04,
      0.96,
      0.02,
      19.0,
      1.0,
      True,
    )
  {
    StanCalibrated(mean, beta_rel, conf) -> {
      should.be_true(mean >. 0.92)
      should.be_true(beta_rel >. 0.94)
      should.be_true(conf >. 0.5)
    }
    StanTriggerFired(_) -> should.fail()
  }

  // 2. Divergent transitions or R_hat > 1.01 fires StanTriggerFired
  case
    core_systems_engineering.evaluate_stan_bayesian_gate(
      StanDiagnostics(1.04, 250, 2, 0.31),
      0.9,
      0.04,
      0.9,
      0.02,
      10.0,
      1.0,
      True,
    )
  {
    StanTriggerFired(_) -> Nil
    StanCalibrated(_, _, _) -> should.fail()
  }

  // 3. Pareto front rejects dominated bloated-MCP solution (4 optimal of 5)
  should.equal(core_systems_engineering.compute_engine_pareto_front(), 4)

  // 4. 11-Domain Rete-UL forward-chaining salience overrides
  let #(res_nominal, dom_cnt) =
    core_systems_engineering.evaluate_11_domain_rete_ul(
      ev_claimed: 93,
      max_quota_bps: 1800,
      openrouter_nd: 900_000_000,
      foreign_c3i_frame: False,
      default_at_conserved: True,
      mcp_zenoh_healthy: True,
    )
  should.equal(dom_cnt, 11)
  should.be_true(res_nominal.salience > 0)

  let #(res_ev94, _) =
    core_systems_engineering.evaluate_11_domain_rete_ul(
      ev_claimed: 94,
      max_quota_bps: 1800,
      openrouter_nd: 900_000_000,
      foreign_c3i_frame: False,
      default_at_conserved: True,
      mcp_zenoh_healthy: True,
    )
  should.equal(res_ev94.decision, "ANDON_HOLD_PROVENANCE_CEILING_93")

  let #(res_c3i, _) =
    core_systems_engineering.evaluate_11_domain_rete_ul(
      ev_claimed: 93,
      max_quota_bps: 1800,
      openrouter_nd: 900_000_000,
      foreign_c3i_frame: True,
      default_at_conserved: True,
      mcp_zenoh_healthy: True,
    )
  should.equal(res_c3i.decision, "DROP_AND_FENCE_SPLIT_BRAIN")

  let #(res_margin, _) =
    core_systems_engineering.evaluate_11_domain_rete_ul(
      ev_claimed: 93,
      max_quota_bps: 6001,
      openrouter_nd: 900_000_000,
      foreign_c3i_frame: False,
      default_at_conserved: True,
      mcp_zenoh_healthy: True,
    )
  should.equal(res_margin.decision, "HOLD_MARGIN_40PCT")
}

pub fn closed_loop_kalman_pid_shield_and_nasa_fprime_poodavr_fsm_test() {
  // Nominal closed-loop tick: Kalman nominal, F' traverses all 7 states back to Predicting
  let ok_rep =
    core_systems_engineering.run_closed_loop_control_tick(
      health_measurement: 0.98,
      action_risk: 0.05,
      intent_safe: True,
      breakers_closed: True,
      trace13_conserved: True,
    )
  should.be_true(ok_rep.kalman_nominal)
  should.be_false(ok_rep.fprime_halted)
  should.equal(ok_rep.fprime_final_state, "Predicting")
  should.be_true(ok_rep.shield_safe_rate >=. 0.99)

  // Unsafe intent or broken trace13 trips F' ConstitutionalHalt fail-closed
  let halt_rep =
    core_systems_engineering.run_closed_loop_control_tick(
      health_measurement: 0.55,
      action_risk: 0.75,
      intent_safe: False,
      breakers_closed: True,
      trace13_conserved: False,
    )
  should.be_true(halt_rep.fprime_halted)
  should.equal(halt_rep.fprime_final_state, "ConstitutionalHalt")
}

pub fn fractal_fmea_4uca_stpa_stamp_contagion_and_8class_error_handler_test() {
  let full_uca =
    StpaUcaAnalysis(
      not_provided_hazard: "UCA-1: Zenoh fence not applied during cutover",
      provided_unsafe_hazard: "UCA-2: Unverified artifact promoted to main",
      wrong_timing_or_order_hazard: "UCA-3: OI-07 executed after OI-02 split-brain",
      wrong_duration_hazard: "UCA-4: Lease expires mid-build (< 4h TTL)",
    )
  let incomplete_uca = StpaUcaAnalysis("UCA-1", "", "UCA-3", "UCA-4")

  // SC-RISK-PRIORITY-001 precondition gates
  case
    core_systems_engineering.evaluate_fractal_fmea_stpa_risk(
      authority_valid: False,
      deps_ready: True,
      uca: full_uca,
      severity: 9,
      occurrence: 4,
      detection: 3,
      criticality: 9,
      stpa_weight: 8,
      dependency_weight: 7,
      impact_weight: 9,
      violated_constraints: [],
    )
  {
    RiskBlockedPrecondition(r) ->
      should.equal(r, "authority_or_lease_fence_invalid")
    _ -> should.fail()
  }

  case
    core_systems_engineering.evaluate_fractal_fmea_stpa_risk(
      authority_valid: True,
      deps_ready: True,
      uca: incomplete_uca,
      severity: 9,
      occurrence: 4,
      detection: 3,
      criticality: 9,
      stpa_weight: 8,
      dependency_weight: 7,
      impact_weight: 9,
      violated_constraints: [],
    )
  {
    RiskBlockedPrecondition(r) -> should.equal(r, "incomplete_4_uca_stpa_record")
    _ -> should.fail()
  }

  // Valid preconditions + 1 STAMP constraint violation propagates contagion to neighbours (3 cells degraded)
  case
    core_systems_engineering.evaluate_fractal_fmea_stpa_risk(
      authority_valid: True,
      deps_ready: True,
      uca: full_uca,
      severity: 9,
      occurrence: 4,
      detection: 5,
      criticality: 8,
      stpa_weight: 7,
      dependency_weight: 6,
      impact_weight: 9,
      violated_constraints: ["SC-RISK-PRIORITY-001"],
    )
  {
    RiskPrioritized(rpn, _, product, stamp_degraded) -> {
      should.equal(rpn, 180)
      should.equal(product, 8 * 7 * 180 * 6 * 9)
      should.equal(stamp_degraded, 3)
    }
    _ -> should.fail()
  }

  // Verify all 8 error classes map deterministically to clean recovery or Jidoka Andon HOLD
  let q = QuotaSnapshot(900, 1100, 1300, 800_000_000)
  let recoverable_modes = [
    ErrModeTransientTestOrBuild("flaky_io"),
    ErrModeWorkspaceOrArtifactCorruption("corrupt_ebin"),
    ErrModeWrongArchitecturalPath("bad_dag_edge"),
    ErrModeLeaseOrHeartbeatExpired("missed_hb"),
    ErrModeSplitBrainForeignC3iFrame("c3i_4200"),
    ErrModeFormalProofOrReteVeto("gospel_postcond"),
  ]
  list.each(recoverable_modes, fn(m) {
    case
      core_systems_engineering.handle_system_error(
        task_id: "w1-task",
        role: ImplRole,
        next_attempt: 2,
        err: m,
        quota: q,
      )
    {
      ExecuteAttempt(attempt: 2, ..) -> Nil
      _ -> should.fail()
    }
  })

  list.each(
    [
      ErrModeQuotaMargin40Breached("6005_bps"),
      ErrModeHardwareOrProvenanceBreach("ev_108_forged"),
    ],
    fn(m) {
      case
        core_systems_engineering.handle_system_error(
          task_id: "w1-task",
          role: ImplRole,
          next_attempt: 2,
          err: m,
          quota: q,
        )
      {
        JidokaAndonHold(..) -> Nil
        _ -> should.fail()
      }
    },
  )
}

pub fn full_fpp_6_machines_sysml_v2_packages_and_8_bionic_services_test() {
  let #(canon_rep, core_rep, fpp_cnt) =
    core_systems_engineering.validate_all_fpp_sysml_models()
  should.be_true(canon_rep.valid)
  should.be_true(core_rep.valid)
  should.equal(core_rep.satisfaction_ratio, 1.0)
  should.equal(core_rep.errors, [])
  should.equal(core_rep.total_parts, 7)
  should.equal(fpp_cnt, 6)

  let q = QuotaSnapshot(900, 1200, 1500, 750_000_000)
  let bionic =
    core_systems_engineering.evaluate_bionic_services_suite(
      quota: q,
      cpu_load: 0.28,
      error_rate: 0.01,
      mem_pressure: 0.31,
      stress_event: True,
    )
  should.be_true(bionic.holon_active)
  should.be_true(bionic.membrane_allows_uos_gleam)
  should.be_true(bionic.membrane_blocks_legacy_c3i)
  should.be_true(bionic.neuro_spine_delivered)
  should.be_true(bionic.prajna_breaker_allowed)
  should.equal(bionic.metabolic_regime, AnabolicParallel)
  should.equal(bionic.fractal_l0_l9_health, LayerHealthy)
  should.equal(bionic.bionic_services_online, 8)
  should.be_true(bionic.bionic_token_twin_verified)

  let unified =
    core_systems_engineering.evaluate_unified_systems_engineering(
      q,
      1_793_550_000_000,
    )
  should.be_true(unified.sheaf_h1_vanished)
  should.be_true(unified.trace13_conserved)
  should.equal(unified.pareto_optimal_engines, 4)
  should.be_true(unified.stan_calibrated)
  should.be_true(unified.control_nominal)
  should.be_true(unified.fprime_6_machines_ready)
  should.be_true(unified.sysml_core_valid)
  should.be_true(unified.system_fmea_entries > 0)
  should.be_true(unified.bionic_8_services_healthy)

  let encoded = core_systems_engineering.encode_unified_systems_json(unified)
  should.be_true(
    string.contains(encoded, "uos.core_evo.systems_engineering.v2"),
  )
}

pub fn fractal_holonic_10x17_simulation_and_12_invariant_formal_certificate_test() {
  let sim = core_fractal_holonic_simulator.simulate_fractal_holarchy()
  should.equal(sim.total_ticks, 24)
  should.equal(sim.atomic_holons_per_tick, 170)
  should.equal(sim.layer_macro_holons_per_tick, 10)
  should.equal(sim.faults_injected, 2)
  should.equal(sim.faults_self_healed_within_3_attempts, 2)
  should.equal(sim.attacks_quarantined, 3)
  should.equal(sim.torpor_holds_enforced, 2)
  // AGY Thin Conductor share strictly < 2.0% (< 200 bps)
  should.be_true(sim.agy_token_share_bps > 0 && sim.agy_token_share_bps < 200)
  should.equal(sim.final_root_holon.lyapunov_v, 0)
  should.be_true(sim.final_root_holon.trust_indicator)

  let cert = core_fractal_holonic_simulator.verify_simulation_correctness(sim)
  should.be_true(cert.all_12_invariants_proved)
  should.equal(cert.proved_count, 12)
  should.equal(cert.total_invariants, 12)
  should.equal(cert.total_holon_epoch_states_verified, 4080)

  let cert_json =
    core_fractal_holonic_simulator.encode_holonic_certificate_json(sim, cert)
  should.be_true(
    string.contains(cert_json, "uos.core_evo.fractal_holonic_simulation.v3"),
  )
}

// =============================================================================
// UOS-CORE-EVO v4: System Erlang/OTP 29 + Universal FPP Actor Mesh (MCP +
// Zenoh + Fractal Logging/OTel + Mathematical Twins + Embedded OpenRouter +
// Algebraic Atlas/Sheaves + Denotational Intents)
// =============================================================================

pub fn otp29_runtime_and_embedded_openrouter_redaction_margin40_test() {
  case core_fpp_actor_twin_mesh.verify_otp29_runtime() {
    Otp29Verified(rel, erts) -> {
      should.equal(rel, "29")
      should.be_true(string.starts_with(erts, "17."))
    }
    _ -> should.fail()
  }

  let nominal_q = QuotaSnapshot(800, 1100, 1400, 900_000_000)
  // 1. Secret & NVMe serial scrubbing + Flash/Pro model routing under < $4.50 spend
  case
    core_fpp_actor_twin_mesh.plan_embedded_openrouter_access(
      actor_id: "holon_actor_l5",
      tier: ImplementationFlashTier,
      raw_prompt: "Check serial 25503L801736 and key sk-or-v1-abc123SECRET",
      quota: nominal_q,
    )
  {
    OpenRouterDispatched(model, zero_cost, clean, ..) -> {
      should.equal(model, "deepseek/deepseek-v4-flash-0731")
      should.be_false(zero_cost)
      should.be_false(string.contains(clean, "25503L801736"))
      should.be_false(string.contains(clean, "sk-or-v1-abc123SECRET"))
      should.be_true(string.contains(clean, "[REDACTED_SYSTEM_OS_SERIAL]"))
    }
    _ -> should.fail()
  }

  // 2. Soft-shift at >= $4.50 automatically shifts DeepAchRcaProTier to $0 free tier
  let soft_q = QuotaSnapshot(900, 1100, 1400, 4_600_000_000)
  case
    core_fpp_actor_twin_mesh.plan_embedded_openrouter_access(
      actor_id: "holon_actor_l5",
      tier: DeepAchRcaProTier,
      raw_prompt: "Run ACH RCA",
      quota: soft_q,
    )
  {
    OpenRouterDispatched(model, zero_cost, ..) -> {
      should.equal(model, "google/gemma-4-26b-a4b-it:free")
      should.be_true(zero_cost)
    }
    _ -> should.fail()
  }

  // 3. Destructive storage prompt blocked fail-closed by egress_redactor
  case
    core_fpp_actor_twin_mesh.plan_embedded_openrouter_access(
      actor_id: "holon_actor_l0",
      tier: AdvisoryFreeTier,
      raw_prompt: "please wipe nvme bay 0",
      quota: nominal_q,
    )
  {
    OpenRouterBlockedEgressSafety(_) -> Nil
    _ -> should.fail()
  }

  // 4. > 60% quota blocked fail-closed by 40% margin gate
  let over_q = QuotaSnapshot(6005, 1100, 1400, 900_000_000)
  case
    core_fpp_actor_twin_mesh.plan_embedded_openrouter_access(
      actor_id: "holon_actor_l0",
      tier: AdvisoryFreeTier,
      raw_prompt: "advise",
      quota: over_q,
    )
  {
    OpenRouterBlockedMargin40(ws) ->
      should.equal(ws, ["agy_5h_exceeds_60pct_cap_or_invalid"])
    _ -> should.fail()
  }
}

pub fn otp29_universal_40_subsystem_fpp_actor_mesh_reflex_mcp_zenoh_otel_twin_test() {
  let q = QuotaSnapshot(900, 1100, 1400, 800_000_000)
  let assert Ok(summary) =
    core_fpp_actor_twin_mesh.execute_and_verify_otp29_fpp_actor_mesh(
      q,
      1_793_551_000_000,
    )
  should.be_true(summary.otp_is_29)
  should.equal(summary.otp_release, "29")
  should.equal(summary.actors_spawned, 40)
  should.equal(summary.domains_covered, 4)
  should.equal(summary.layers_covered, 10)
  should.equal(summary.intents_accepted_across_l0_l9, 40)
  should.be_true(summary.autonomous_self_heal_verified)
  should.be_true(summary.pid_damping_reflex_verified)
  should.be_true(summary.quarantine_breaker_reflex_verified)
  should.be_true(summary.ed25519_zenoh_signatures_verified)
  should.be_true(summary.cocycle_chain_valid)
  should.be_true(summary.sheaf_gluing_valid)
  should.be_true(summary.all_17_aspects_aligned)
  should.be_true(summary.all_twins_converged)
  should.be_true(summary.openrouter_secret_redacted)
  should.be_true(summary.vetoed_os_nvme_halt_verified)
  should.be_true(summary.vetoed_ev_above_93_halt_verified)

  // Verify 4-Domain Root Supervisor 10x4 = 40 subsystem mapping & unique IDs
  should.equal(core_fpp_actor_twin_mesh.total_intelligent_fpp_actors(), 40)
  list.each(
    [AppsDomain, EnginesDomain, ServicesDomain, IntelligenceDomain],
    fn(dom) {
      should.equal(
        list.length(core_fpp_actor_twin_mesh.fpp_actors_for_root_domain(dom)),
        10,
      )
    },
  )

  // Verify named subsystem actor startup, degraded-health autonomous self-heal, and unknown rejection
  case
    core_fpp_actor_twin_mesh.start_named_subsystem_fpp_actor(
      "nonexistent_actor_xyz",
      1_793_551_000_000,
    )
  {
    Error(msg) ->
      should.be_true(string.starts_with(msg, "UNKNOWN_SUBSYSTEM_FPP_ACTOR:"))
    Ok(_) -> should.fail()
  }

  let assert Ok(zlp_actor) =
    core_fpp_actor_twin_mesh.start_named_subsystem_fpp_actor(
      "l1_intel_zlp_v3_lean_zig_hyperplane",
      1_793_551_000_000,
    )
  let heal_probe =
    ActorIntentRequest(
      intent_id: "zlp_self_heal_probe",
      authority: "sa-plan",
      target_drive_serial: "NVME-DATA-POOL-01",
      criticality: "DAL-B",
      guardian_approved: True,
      ev_cycle: 93,
      target_chart: core_fpp_actor_twin_mesh.chart_for_layer_index(2),
      action: "verify_zlp_two_lane_port",
      mcp_route: "system_verification",
      role: ImplRole,
      openrouter_tier: AdvisoryFreeTier,
      embedded_prompt: "advise zlp port pool",
      parent_trace: None,
      observed_health: 0.72,
      quota: q,
      now_ms: 1_793_551_000_050,
    )
  case
    process.call(zlp_actor.data, 5000, fn(r) { DispatchIntent(heal_probe, r) })
  {
    ActorIntentAccepted(
      actor_id: "l1_intel_zlp_v3_lean_zig_hyperplane",
      fprime_lifecycle_state: "Predicting",
      twin_health: 1.0,
      ..,
    ) -> Nil
    _ -> should.fail()
  }
  let zlp_st = process.call(zlp_actor.data, 5000, InspectActor)
  case zlp_st.last_reflex_action {
    ReflexAutonomousSelfHeal(_, _) -> should.equal(zlp_st.autonomous_heals, 1)
    _ -> should.fail()
  }
  process.send(zlp_actor.data, ShutdownActor)

  // Verify non-Zero-Muda bloated MCP route (e.g. "stitch_generate") is vetoed into F' ConstitutionalHalt
  let assert Ok(started) =
    core_fpp_actor_twin_mesh.start_fpp_holon_actor(5, 1_793_551_000_000)
  let bad_mcp_req =
    ActorIntentRequest(
      intent_id: "veto_stitch_mcp",
      authority: "sa-plan",
      target_drive_serial: "NVME-DATA-POOL-01",
      criticality: "DAL-B",
      guardian_approved: True,
      ev_cycle: 93,
      target_chart: core_fpp_actor_twin_mesh.chart_for_layer_index(5),
      action: "bloated_ui_call",
      mcp_route: "stitch_generate_screen",
      role: ImplRole,
      openrouter_tier: AdvisoryFreeTier,
      embedded_prompt: "check",
      parent_trace: None,
      observed_health: 0.99,
      quota: q,
      now_ms: 1_793_551_000_100,
    )
  case
    process.call(started.data, 5000, fn(r) { DispatchIntent(bad_mcp_req, r) })
  {
    ActorIntentVetoed(
      fprime_lifecycle_state: "ConstitutionalHalt",
      veto_stage: "mcp_whitelist_gate",
      ..,
    ) -> Nil
    _ -> should.fail()
  }
  process.send(started.data, ShutdownActor)
}

pub fn ed25519_authenticated_core_envelope_roundtrip_and_publish_test() {
  let #(pub_hex, priv_hex) = core_bus.generate_ed25519_keypair_hex()
  should.equal(string.byte_size(pub_hex), 64)
  should.equal(string.byte_size(priv_hex), 64)

  let assert Ok(auth_env) =
    core_bus.build_and_sign_ed25519(
      topic: "uos/v1/wave/w2/summary",
      candidate_sha256: sample_candidate_sha,
      plan_id: "uos/agy-fractal-issue-resolution-master/20261101-1454",
      task_id: "w2-recoverable-14target-cutover",
      worker_id: "agy-core-evo-conductor-20261101",
      attempt: 1,
      seq_id: 77,
      ev_ceiling: 93,
      payload_json: "{\"wave\":\"W2\",\"auth\":\"ed25519\",\"ev_ceiling\":93}",
      pubkey_hex: pub_hex,
      privkey_hex: priv_hex,
    )
  should.equal(auth_env.auth_alg, "ed25519")
  should.equal(auth_env.signer_pubkey_hex, pub_hex)
  should.equal(string.byte_size(auth_env.signature_hex), 128)

  let wire = core_bus.encode_authenticated_envelope(auth_env)
  let assert Ok(decoded) =
    core_bus.decode_and_verify_authenticated_envelope(wire, pub_hex, 76)
  should.equal(decoded, auth_env)

  let assert Ok(rcpt) = core_bus.publish_authenticated(auth_env, pub_hex)
  should.be_true(rcpt.ets_buffered)
  let assert Ok(fetched) =
    core_bus.fetch_authenticated("uos/v1/wave/w2/summary", pub_hex, 76)
  should.equal(fetched.signature_hex, auth_env.signature_hex)
}

pub fn ed25519_authenticated_envelope_rejects_tamper_and_wrong_signer_fail_closed_test() {
  let #(pub_a, priv_a) = core_bus.generate_ed25519_keypair_hex()
  let #(pub_b, _priv_b) = core_bus.generate_ed25519_keypair_hex()

  let assert Ok(auth_env) =
    core_bus.build_and_sign_ed25519(
      topic: "uos/v1/hive/conductor/w2_auth_probe",
      candidate_sha256: sample_candidate_sha,
      plan_id: "uos/agy-fractal-issue-resolution-master/20261101-1454",
      task_id: "w2-recoverable-14target-cutover",
      worker_id: "agy-core-evo-conductor-20261101",
      attempt: 1,
      seq_id: 101,
      ev_ceiling: 93,
      payload_json: "{\"status\":\"authentic\"}",
      pubkey_hex: pub_a,
      privkey_hex: priv_a,
    )

  // 1. Wrong expected signer public key rejected fail-closed
  case core_bus.verify_authenticated_envelope(auth_env, pub_b, 100) {
    Error(core_bus.ErrSignerMismatch(expected, actual)) -> {
      should.equal(expected, pub_b)
      should.equal(actual, pub_a)
    }
    _ -> should.fail()
  }

  // 2. Forged seq_id (keeping valid payload_sha256) rejected by Ed25519 verify
  let forged_seq_env =
    core_bus.AuthenticatedCoreEnvelope(
      ..auth_env,
      envelope: SignedCoreEnvelope(..auth_env.envelope, seq_id: 102),
    )
  case core_bus.verify_authenticated_envelope(forged_seq_env, pub_a, 100) {
    Error(core_bus.ErrInvalidSignature(_)) -> Nil
    _ -> should.fail()
  }

  // 3. Pipe delimiter injection in worker_id rejected fail-closed
  case
    core_bus.build_and_sign_ed25519(
      topic: "uos/v1/hive/conductor/w2_auth_probe",
      candidate_sha256: sample_candidate_sha,
      plan_id: "plan-ok",
      task_id: "task-ok",
      worker_id: "bad|worker",
      attempt: 1,
      seq_id: 103,
      ev_ceiling: 93,
      payload_json: "{}",
      pubkey_hex: pub_a,
      privkey_hex: priv_a,
    )
  {
    Error(core_bus.ErrDelimiterInIdentifier("worker_id")) -> Nil
    _ -> should.fail()
  }
}

pub fn ed25519_session_key_signing_keeps_private_key_in_ram_test() {
  let session_pub = core_bus.session_ed25519_pubkey_hex()
  should.equal(string.byte_size(session_pub), 64)
  let assert Ok(auth_env) =
    core_bus.build_and_sign_session_ed25519(
      topic: "uos/v1/saplan/w2_cutover/session_key_test",
      candidate_sha256: sample_candidate_sha,
      plan_id: "uos/agy-fractal-issue-resolution-master/20261101-1454",
      task_id: "w2-recoverable-14target-cutover",
      worker_id: "agy-core-evo-conductor-20261101",
      attempt: 1,
      seq_id: 205,
      ev_ceiling: 93,
      payload_json: "{\"ram_only_ed25519\":true}",
    )
  should.equal(auth_env.signer_pubkey_hex, session_pub)
  let wire = core_bus.encode_authenticated_envelope(auth_env)
  let assert Ok(verified) =
    core_bus.decode_and_verify_authenticated_envelope(wire, session_pub, 204)
  should.equal(verified.envelope.seq_id, 205)
}

pub fn core_bus_session_keypair_64_process_concurrency_test() {
  core_bus.reset_session_ed25519_for_test()
  should.equal(string.byte_size(core_bus.session_ed25519_pubkey_hex()), 64)

  // 64 concurrent cold-start signers must converge on exactly 1 identical pubkey.
  should.equal(ffi_concurrent_cold_start_unique_pubkeys(64), 1)

  // Warm reads stay lock-free O(1) and idempotent.
  let pub_a = core_bus.session_ed25519_pubkey_hex()
  let pub_b = core_bus.session_ed25519_pubkey_hex()
  should.equal(pub_a, pub_b)
  should.equal(string.byte_size(pub_a), 64)
}

pub fn core_bus_stateful_ets_replay_rejection_test() {
  let session_pub = core_bus.session_ed25519_pubkey_hex()
  // Session-keyed topic keeps the durable ETS high-water mark isolated per VM run.
  let topic = "uos/v1/hive/w2_replay_probe_" <> session_pub
  let payload = "{\"replay_probe\":true}"
  let build = fn(seq_id) {
    core_bus.build_and_sign_session_ed25519(
      topic: topic,
      candidate_sha256: sample_candidate_sha,
      plan_id: "uos/agy-fractal-issue-resolution-master/20261101-1454",
      task_id: "w2-recoverable-14target-cutover",
      worker_id: "agy-core-evo-conductor-20261101",
      attempt: 1,
      seq_id: seq_id,
      ev_ceiling: 93,
      payload_json: payload,
    )
  }
  let assert Ok(env_501) = build(501)
  let wire_501 = core_bus.encode_authenticated_envelope(env_501)

  // 1. First delivery of seq_id=501 is accepted and advances the high water mark.
  let assert Ok(accepted) =
    core_bus.consume_authenticated_envelope_once(wire_501, session_pub)
  should.equal(accepted.envelope.seq_id, 501)

  // 2. Exact duplicate delivery of the identical signed wire is refused as replay.
  case core_bus.consume_authenticated_envelope_once(wire_501, session_pub) {
    Error(AuthCoreError(ErrNonMonotonicSeq(501, 501))) -> Nil
    _ -> should.fail()
  }

  // 3. An older authentically signed frame (seq_id=500) is refused as replay.
  let assert Ok(env_500) = build(500)
  case
    core_bus.consume_authenticated_envelope_once(
      core_bus.encode_authenticated_envelope(env_500),
      session_pub,
    )
  {
    Error(AuthCoreError(ErrNonMonotonicSeq(500, 501))) -> Nil
    _ -> should.fail()
  }

  // 4. A strictly monotonic successor (seq_id=502) is accepted.
  let assert Ok(env_502) = build(502)
  let assert Ok(next) =
    core_bus.consume_authenticated_envelope_once(
      core_bus.encode_authenticated_envelope(env_502),
      session_pub,
    )
  should.equal(next.envelope.seq_id, 502)

  // 5. Cold-start 64-process short-lived worker race: tear down the replay ETS
  //    table first so the very first caller is a short-lived spawned worker that
  //    immediately exits; immortal `core_bus_replay_ets` must survive (`#(1, 63)`).
  ffi_reset_replay_table()
  let assert Ok(env_503) = build(503)
  let wire_503 = core_bus.encode_authenticated_envelope(env_503)
  should.equal(ffi_concurrent_replay_winners(wire_503, session_pub, 64), #(1, 63))
  // And subsequent replay after all 64 short-lived workers exited still fails closed!
  case core_bus.consume_authenticated_envelope_once(wire_503, session_pub) {
    Error(AuthCoreError(ErrNonMonotonicSeq(503, 503))) -> Nil
    _ -> should.fail()
  }
}

pub fn supervised_live_40_fpp_actor_mesh_and_one_for_one_self_healing_test() {
  let assert Ok(started_cnt) =
    core_fpp_actor_twin_mesh.ensure_live_40_fpp_actor_mesh_started()
  should.equal(started_cnt, 40)

  let #(sup_running, alive_cnt) =
    core_fpp_actor_twin_mesh.live_40_fpp_supervisor_status()
  should.be_true(sup_running)
  should.equal(alive_cnt, 40)

  let inspected = core_fpp_actor_twin_mesh.inspect_live_40_fpp_actors()
  should.equal(list.length(inspected), 40)
  should.be_true(
    list.all(inspected, fn(entry) {
      let #(_spec, st_opt, is_alive) = entry
      case is_alive, st_opt {
        True, Some(st) ->
          st.intents_accepted >= 1
          && st.last_ed25519_verified
          && st.math_twin.twin_health == 1.0
        _, _ -> False
      }
    }),
  )

  // Verify OTP OneForOne self-healing: stop actor #17 and confirm static_supervisor
  // automatically restarts & re-registers a live Ed25519-verified actor #17!
  let assert Ok(subj_before) =
    core_fpp_actor_twin_mesh.lookup_live_subsystem_fpp_actor(17)
  process.send(subj_before, ShutdownActor)
  process.sleep(120)
  let #(sup_after, alive_after) =
    core_fpp_actor_twin_mesh.live_40_fpp_supervisor_status()
  should.be_true(sup_after)
  should.equal(alive_after, 40)
  let assert Ok(subj_after) =
    core_fpp_actor_twin_mesh.lookup_live_subsystem_fpp_actor(17)
  let st_after = process.call(subj_after, 2000, InspectActor)
  should.equal(st_after.spec.actor_index, 17)
  should.be_true(st_after.intents_accepted >= 1)
  should.be_true(st_after.last_ed25519_verified)

  // Verify immortal guardian auto-restart when the static_supervisor itself terminates:
  // kill SupPid directly and confirm guardian restarts a fresh SupPid + all 40 actors!
  let assert Ok(sup_pid_before) = ffi_live_fpp_supervisor_pid()
  should.be_true(ffi_kill_live_fpp_supervisor_for_test())
  let assert Ok(40) =
    core_fpp_actor_twin_mesh.ensure_live_40_fpp_actor_mesh_started()
  let #(sup_recovered, alive_recovered) =
    core_fpp_actor_twin_mesh.live_40_fpp_supervisor_status()
  should.be_true(sup_recovered)
  should.equal(alive_recovered, 40)
  let assert Ok(sup_pid_after) = ffi_live_fpp_supervisor_pid()
  should.not_equal(sup_pid_before, sup_pid_after)
}

@external(erlang, "core_fpp_candidate_ffi", "live_fpp_supervisor_pid")
fn ffi_live_fpp_supervisor_pid() -> Result(process.Pid, Nil)

@external(erlang, "core_fpp_candidate_ffi", "kill_live_fpp_supervisor_for_test")
fn ffi_kill_live_fpp_supervisor_for_test() -> Bool

pub fn capsule_manifest_binding_sibling_prefix_and_payload_anchor_test() {
  should.be_true(ffi_is_canonical_capsule_location(
    "/home/an/NAS-setup/uos/var/releases/ecology/20261102-1625-251aed109760094edb053439ef539550a3519b85acc5a99bb1201cd77c1acb56",
    "/home/an/NAS-setup/uos",
    "251aed109760094edb053439ef539550a3519b85acc5a99bb1201cd77c1acb56",
  ))

  should.be_false(ffi_is_canonical_capsule_location(
    "/home/an/NAS-setup/uos/var/releases/ecology/20261102-1625-251aed109760094edb053439ef539550a3519b85acc5a99bb1201cd77c1acb56",
    "/tmp/evil",
    "251aed109760094edb053439ef539550a3519b85acc5a99bb1201cd77c1acb56",
  ))

  should.be_false(ffi_is_canonical_capsule_location(
    "/home/an/NAS-setup/uos/var/releases/ecology/20261102-1625-251aed109760094edb053439ef539550a3519b85acc5a99bb1201cd77c1acb56",
    "/home/an/NAS-setup/uos/.uos-workspaces/..",
    "251aed109760094edb053439ef539550a3519b85acc5a99bb1201cd77c1acb56",
  ))

  should.be_false(ffi_is_canonical_capsule_location(
    "/home/an/NAS-setup/uos/var/releases/ecology/20261102-1625-251aed109760094edb053439ef539550a3519b85acc5a99bb1201cd77c1acb56",
    "/home/an/NAS-setup/uos/.uos-workspaces/a/b",
    "251aed109760094edb053439ef539550a3519b85acc5a99bb1201cd77c1acb56",
  ))

  ffi_set_expected_payload_env_for_test("")
  should.be_false(ffi_expected_payload_env_matches(
    "fdb9ed6e8c17a15983a5a36b136057e575c614dec87d7e61e0d9dfec675560a1",
  ))

  ffi_set_expected_payload_env_for_test(
    "0000000000000000000000000000000000000000000000000000000000000000",
  )
  should.be_false(ffi_expected_payload_env_matches(
    "fdb9ed6e8c17a15983a5a36b136057e575c614dec87d7e61e0d9dfec675560a1",
  ))

  ffi_set_expected_payload_env_for_test(
    "fdb9ed6e8c17a15983a5a36b136057e575c614dec87d7e61e0d9dfec675560a1",
  )
  should.be_true(ffi_expected_payload_env_matches(
    "fdb9ed6e8c17a15983a5a36b136057e575c614dec87d7e61e0d9dfec675560a1",
  ))
}

@external(erlang, "core_fpp_candidate_ffi", "is_canonical_capsule_location")
fn ffi_is_canonical_capsule_location(
  cap_dir: String,
  src_root: String,
  cand_sha: String,
) -> Bool

@external(erlang, "core_fpp_candidate_ffi", "expected_payload_env_matches")
fn ffi_expected_payload_env_matches(payload_sha: String) -> Bool

@external(erlang, "core_fpp_candidate_ffi", "set_expected_payload_env_for_test")
fn ffi_set_expected_payload_env_for_test(val: String) -> Nil

pub fn bionic_token_twin_shannon_fastpath_and_8_fpp_watchdogs_test() {
  let profiles = core_bionic_token_twin.all_content_fastpath_profiles()
  should.equal(list.length(profiles), 8)

  let json_prof =
    core_bionic_token_twin.classify_shannon_fastpath(4621, 778, 1200, 80)
  should.equal(json_prof.content_class, CtJsonStruct)
  should.equal(json_prof.target_compression_ratio_x10, 145)

  let entropy_prof =
    core_bionic_token_twin.classify_shannon_fastpath(5800, 100, 7200, 20)
  should.equal(entropy_prof.content_class, CtHighEntropy)
  should.equal(entropy_prof.target_compression_ratio_x10, 920)

  let log_prof =
    core_bionic_token_twin.classify_shannon_fastpath(4400, 200, 2200, 180)
  should.equal(log_prof.content_class, CtLogStream)

  let watchdogs = core_bionic_token_twin.canonical_8_fpp_token_watchdogs()
  should.equal(list.length(watchdogs), 8)

  let nominal_sample =
    TokenTurnTelemetry(
      raw_tokens: 34_400,
      wire_tokens: 5606,
      cache_hit_bps: 9450,
      kl_drift_milli: 12,
      lyapunov_v_prev_micro: 214_000,
      lyapunov_v_curr_micro: 11_482,
      remaining_margin_bps: 10_000,
      active_context_controllers: 1,
      capsule_sha_matched: True,
      nif_latency_us: 19,
    )
  case core_bionic_token_twin.evaluate_token_watchdog_mesh(nominal_sample) {
    TokenHealthOptimal(red_bps, dv_micro, active_count) -> {
      should.be_true(red_bps > 8000)
      should.be_true(dv_micro < 0)
      should.equal(active_count, 8)
    }
    _ -> should.fail()
  }

  let misconfig_sample =
    TokenTurnTelemetry(
      raw_tokens: 34_400,
      wire_tokens: 25_099,
      cache_hit_bps: 7000,
      kl_drift_milli: 50,
      lyapunov_v_prev_micro: 100_000,
      lyapunov_v_curr_micro: 140_000,
      remaining_margin_bps: 3500,
      active_context_controllers: 2,
      capsule_sha_matched: False,
      nif_latency_us: 2000,
    )
  case core_bionic_token_twin.evaluate_token_watchdog_mesh(misconfig_sample) {
    TokenHealthRedflag(flags, dv_micro, reflex) -> {
      should.equal(list.length(flags), 7)
      should.be_true(dv_micro > 0)
      should.equal(reflex, "ReflexJidokaConstitutionalHalt")
    }
    _ -> should.fail()
  }
}

pub fn bionic_token_twin_bdd_8_archetypes_and_rate_distortion_fold_test() {
  // BDD Scenario 1: Given all 8 content archetypes, when classified by Shannon entropy
  // and structural/hex/newline densities, then each maps to its exact FastpathProfile.
  let p_high = core_bionic_token_twin.classify_shannon_fastpath(6200, 120, 7500, 40)
  should.equal(p_high.content_class, CtHighEntropy)

  let p_json = core_bionic_token_twin.classify_shannon_fastpath(4500, 820, 900, 90)
  should.equal(p_json.content_class, CtJsonStruct)

  let p_csv = core_bionic_token_twin.classify_shannon_fastpath(4100, 90, 1900, 280)
  should.equal(p_csv.content_class, CtTabularCsv)

  let p_log = core_bionic_token_twin.classify_shannon_fastpath(4300, 220, 2100, 160)
  should.equal(p_log.content_class, CtLogStream)

  let p_diff = core_bionic_token_twin.classify_shannon_fastpath(4400, 260, 1100, 210)
  should.equal(p_diff.content_class, CtUnifiedDiff)

  let p_formal = core_bionic_token_twin.classify_shannon_fastpath(5100, 540, 800, 110)
  should.equal(p_formal.content_class, CtFormalSpec)

  let p_ast = core_bionic_token_twin.classify_shannon_fastpath(4400, 460, 700, 110)
  should.equal(p_ast.content_class, CtSourceAst)

  let p_prose = core_bionic_token_twin.classify_shannon_fastpath(4200, 120, 400, 90)
  should.equal(p_prose.content_class, CtProseMd)

  // BDD Scenario 2: Rate-distortion fold respects D_KL <= 35 milli-nats and rejects unsafe distortion
  let assert Ok(#(folded_json, kl_json)) =
    core_bionic_token_twin.compute_rate_distortion_fold(14_500, p_json, 120)
  should.be_true(folded_json < 1000)
  should.be_true(kl_json <= 35)

  // Low lambda weight causes KL divergence > 35 -> fail-closed Error
  let assert Error(reason) =
    core_bionic_token_twin.compute_rate_distortion_fold(14_500, p_prose, 50)
  should.equal(reason, "KL_DIVERGENCE_CEILING_EXCEEDED")
}

pub fn bionic_token_twin_data_driven_10_fractal_surfaces_and_property_chaos_test() {
  // 1. Data-Driven 10-Layer (L0..L9) Fractal Surface Table Verification
  let surfaces = core_bionic_token_twin.canonical_10_layer_fractal_token_surfaces()
  should.equal(list.length(surfaces), 10)
  list.each(surfaces, fn(s) {
    should.be_true(s.slo_latency_us > 0 && s.slo_latency_us <= 1200)
    should.be_true(s.min_compression_ratio_x10 >= 24)
    should.be_true(string.starts_with(s.watchdog_agent_id, "FPP-"))
    should.be_true(string.starts_with(s.governing_contract, "SC-"))
  })

  // 2. Property-Based, Fuzz & Chaos Suite (1,000 deterministic trials: 500 nominal + 500 chaos fault injections)
  let #(passed, redflags, optimals) =
    core_bionic_token_twin.run_property_and_chaos_suite(1000, 42_093)
  should.equal(passed, 1000)
  should.equal(redflags, 500)
  should.equal(optimals, 500)
}

pub fn bionic_token_twin_full_12_domain_mathematical_coverage_test() {
  let theorems =
    core_bionic_token_twin.verify_full_12_domain_mathematical_coverage()
  should.equal(list.length(theorems), 13)
  list.each(theorems, fn(t) {
    should.be_true(string.starts_with(t.theorem_id, "MATH-"))
    should.be_true(t.verified_holds)
  })
}

pub fn bionic_token_twin_mcip_v1_and_digital_twin_mirroring_test() {
  // 1. Public Model Architecture Catalog (5 canonical models across Caste-02..Caste-04)
  let models = core_bionic_token_twin.canonical_public_model_catalog()
  should.equal(list.length(models), 5)
  list.each(models, fn(m) {
    should.be_true(m.context_window_tokens >= 163_840)
    should.be_true(m.prefix_cache_affinity_bps >= 8800)
  })

  // 2. MCIP-v1 Envelope Encoding (RoPE Attention-Sink Aligned Header + Forecast + Anchors + Footer)
  let anchors = [
    "apps/cepaf_gleam/src/cepaf_gleam/mcp/runtime_gateway.gleam:412",
    "sha256:e8f218a5772fd4248086dc95f854d0c7e134b041c249f6bbdf5db136a468b44c",
    "admitted_ev_ceiling=93",
    "fencing_token=91044",
  ]
  let env =
    core_bionic_token_twin.encode_mcip_v1_envelope(
      "W01_CODE_EXEC_BASH_GLEAM_DUNE",
      "L3",
      "VERIFY",
      3758,
      64,
      190,
      320,
      anchors,
    )
  should.equal(env.protocol_version, "MCIP/1.0")
  should.equal(env.critical_anchors_preserved, 4)
  should.be_false(env.re_read_required)
  should.equal(env.ev_ceiling, 93)
  should.be_true(string.starts_with(env.wire_packet, "@MCIP/1.0{id=W01_"))
  should.be_true(string.contains(
    env.wire_packet,
    "@MCIP_DECISION{re_read_required=false|ev_ceiling=EV-93",
  ))

  // 3. Mojo 1.0 Digital Twin Mirroring Summary (>= 95.0% fidelity gate)
  let twin = core_bionic_token_twin.verified_digital_twin_mirroring_summary()
  should.equal(twin.recorded_transactions, 4357)
  should.equal(twin.replayed_valid_transactions, 4337)
  should.be_true(twin.token_mirroring_bps >= 9500)
  should.be_true(twin.cost_mirroring_bps >= 9500)
  should.be_true(twin.behavior_decision_mirroring_bps >= 9500)
  should.be_true(twin.composite_mirroring_bps >= 9500)
  should.be_true(twin.meets_95pct_gate)
  should.equal(twin.mcip_anchor_recall_bps, 10_000)

  // 4. 2x2 Live SQLite WAL Transaction Capture (`billion-context` vs `uos-harness`)
  let tx2x2 =
    core_bionic_token_twin.verified_live_2x2_sqlite_transaction_summary()
  should.equal(tx2x2.supervisor_model, "pi+openrouter(gemini-4-argon)")
  should.equal(tx2x2.bili_transactions, 2)
  should.equal(tx2x2.uos_transactions, 2)
  should.equal(tx2x2.anchor_audit_rows, 20)
  should.equal(tx2x2.uos_anchor_recall_bps, 10_000)
  should.equal(tx2x2.uos_reread_turns, 0)
  should.be_true(tx2x2.uos_total_cost_nanodollars < tx2x2.bili_total_cost_nanodollars)
  should.be_true(tx2x2.append_only_triggers_verified)

  // 5. 15 Fractal Data-Driven Optimizations (`FDO-01..FDO-15`) across 4 Domains
  let fdos =
    core_bionic_token_twin.canonical_15_fractal_data_driven_optimizations()
  should.equal(list.length(fdos), 15)
  should.be_true(list.all(fdos, fn(f) { f.verified_pass }))

  // 6. Wisp API, Lustre Cockpit HTML, and TUI Plain View Triple-Surface Verification
  let api_str = json.to_string(core_evo_api.bionic_token_twin_json())
  should.be_true(string.contains(api_str, "\"mcip_digital_twin\":{"))
  should.be_true(string.contains(api_str, "\"live_2x2_sqlite_ledger\":{"))
  should.be_true(string.contains(
    api_str,
    "\"fractal_data_driven_optimizations_count\":15",
  ))
  should.be_true(string.contains(api_str, "\"fdo_id\":\"FDO-15\""))
  should.be_true(string.contains(
    api_str,
    "\"supervisor_model\":\"pi+openrouter(gemini-4-argon)\"",
  ))

  let html = core_evo_cockpit.view()
  should.be_true(string.contains(
    html,
    "MCIP/1.0 Protocol &amp; 5-Model Mojo Digital Twin (99.69% Mirroring over 4,337 Turns, 100.0% Anchor Recall, 2x2 SQLite WAL Live Ledger Verified, 15/15 Fractal Optimizations FDO-01..FDO-15)",
  ))

  let tui_plain = core_evo_view.render_plain()
  should.be_true(string.contains(
    tui_plain,
    "MCIP/1.0 (99.69% Twin, 2x2 SQLite WAL, 15/15 FDO)",
  ))
}

