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
import cepaf_gleam/zenoh/core_bus.{
  ErrDigestMismatch, ErrLegacySplitBrainTopic, ErrNonMonotonicSeq,
  ErrPayloadTooLarge, ErrProvenanceCeilingExceeded, SignedCoreEnvelope,
}
import gleam/list
import gleam/string
import gleeunit/should

const sample_candidate_sha = "8fa6d05c909b8fa6d05c909b8fa6d05c909b8fa6d05c909b8fa6d05c909b0001"

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
