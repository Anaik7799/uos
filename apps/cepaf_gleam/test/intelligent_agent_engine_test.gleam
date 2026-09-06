//// =============================================================================
//// [UOS-TEST] 256-Agent Intelligent Cognitive OODA Engine Test Suite
//// =============================================================================

import cepaf_gleam/fpp/agent_taxonomy.{
  C3iIntelligence, C3iSdlc, C3iSre, C3iVerification, ConstitutionalGuardian,
  SdlcArchitectureSynthesizer, SreLyapunovTrendDetector, SwarmMesh,
}
import cepaf_gleam/fpp/intelligent_agent_engine.{
  ActPhase, DecidePhase, ObservePhase, OrientPhase, bind_skills_for_agent,
  bind_superpowers_for_agent, compress_agent_context,
  dispatch_subagent_delegation, encode_cognitive_context_json, execute_ooda_step,
  initialize_agent_intelligence, load_sdlc_sre_runbook,
}
import gleam/list
import gleam/string
import gleeunit/should

pub fn context_initialization_test() {
  let ctx =
    initialize_agent_intelligence(
      ConstitutionalGuardian,
      C3iVerification,
      "guardian-001",
    )

  ctx.agent_id |> should.equal("guardian-001")
  ctx.phase |> should.equal(ObservePhase)
  ctx.raw_tokens |> should.equal(4096)
  ctx.compressed_tokens |> should.equal(4096)
  ctx.compression_ratio |> should.equal(1.0)
  ctx.stpa_safe |> should.equal(True)

  list.contains(ctx.assigned_skills, "formal-verification-pipeline")
  |> should.equal(True)
  list.contains(ctx.assigned_skills, "safe-rust-x-safety")
  |> should.equal(True)
  list.contains(ctx.assigned_superpowers, "using-superpowers")
  |> should.equal(True)
}

pub fn skill_and_superpower_binding_test() {
  // SDLC
  let sdlc_skills = bind_skills_for_agent(SdlcArchitectureSynthesizer, C3iSdlc)
  list.contains(sdlc_skills, "algebra-driven-beam") |> should.equal(True)
  list.contains(sdlc_skills, "writing-gospel-specifications")
  |> should.equal(True)

  let sdlc_powers = bind_superpowers_for_agent(C3iSdlc)
  list.contains(sdlc_powers, "test-driven-development") |> should.equal(True)

  // SRE with Lyapunov specialization
  let sre_skills = bind_skills_for_agent(SreLyapunovTrendDetector, C3iSre)
  list.contains(sre_skills, "systematic-debugging") |> should.equal(True)
  list.contains(sre_skills, "predict") |> should.equal(True)
  list.contains(sre_skills, "stan-probabilistic-substrate")
  |> should.equal(True)

  // Intelligence
  let intel_skills = bind_skills_for_agent(SwarmMesh, C3iIntelligence)
  list.contains(intel_skills, "ruliad-frontier-search") |> should.equal(True)
  list.contains(intel_skills, "bayesian-inference") |> should.equal(True)
}

pub fn loss_bounded_context_compression_test() {
  let ctx =
    initialize_agent_intelligence(
      SdlcArchitectureSynthesizer,
      C3iSdlc,
      "arch-001",
    )

  // Target token budget 2048 (50% reduction)
  let compressed = compress_agent_context(ctx, 2048)
  compressed.compressed_tokens |> should.equal(2048)
  compressed.compression_ratio |> should.equal(0.5)

  // Target token budget within limits (no-op compression)
  let no_op = compress_agent_context(ctx, 8192)
  no_op.compressed_tokens |> should.equal(4096)
  no_op.compression_ratio |> should.equal(1.0)
}

pub fn ooda_four_phase_cycle_test() {
  let ctx0 =
    initialize_agent_intelligence(SreLyapunovTrendDetector, C3iSre, "lyap-001")

  // Phase 1: Observe -> Orient
  let #(ctx1, dec1) = execute_ooda_step(ctx0, 0.05)
  ctx1.phase |> should.equal(OrientPhase)
  dec1.authorized |> should.equal(True)
  dec1.selected_action |> should.equal("SampleTelemetryWindow")

  // Phase 2: Orient -> Decide
  let #(ctx2, dec2) = execute_ooda_step(ctx1, 0.05)
  ctx2.phase |> should.equal(DecidePhase)
  dec2.authorized |> should.equal(True)
  dec2.selected_action |> should.equal("EvaluateReteRulesAndHypotheses")

  // Phase 3: Decide -> Act
  let #(ctx3, dec3) = execute_ooda_step(ctx2, 0.05)
  ctx3.phase |> should.equal(ActPhase)
  dec3.authorized |> should.equal(True)
  dec3.smt_verified |> should.equal(True)
  dec3.selected_action |> should.equal("AuthorizeDenotationalIntent")

  // Phase 4: Act -> Observe (cycle complete)
  let #(ctx4, dec4) = execute_ooda_step(ctx3, 0.05)
  ctx4.phase |> should.equal(ObservePhase)
  dec4.authorized |> should.equal(True)
  dec4.selected_action |> should.equal("PublishOtelSpanAndRecycle")
}

pub fn bayesian_risk_safety_veto_test() {
  let ctx =
    initialize_agent_intelligence(
      ConstitutionalGuardian,
      C3iVerification,
      "guardian-002",
    )

  // Advance to Decide phase
  let #(ctx_orient, _) = execute_ooda_step(ctx, 0.0)
  let #(ctx_decide, _) = execute_ooda_step(ctx_orient, 0.0)

  // Inject massive telemetry drift (4.0) causing risk to spike above 0.35 threshold
  let #(vetoed_ctx, veto_decision) = execute_ooda_step(ctx_decide, 4.0)

  vetoed_ctx.stpa_safe |> should.equal(False)
  veto_decision.authorized |> should.equal(False)
  veto_decision.selected_action |> should.equal("TripFailClosedSafetyVeto")
  veto_decision.smt_verified |> should.equal(False)
  string.contains(veto_decision.rationale, "veto tripped")
  |> should.equal(True)
}

pub fn subagent_dynamic_delegation_test() {
  let ctx_sdlc =
    initialize_agent_intelligence(
      SdlcArchitectureSynthesizer,
      C3iSdlc,
      "arch-001",
    )
  let tasks_sdlc =
    dispatch_subagent_delegation(ctx_sdlc, "Decompose Layer 4 Architecture")
  list.length(tasks_sdlc) |> should.equal(2)

  let ctx_ver =
    initialize_agent_intelligence(
      ConstitutionalGuardian,
      C3iVerification,
      "guardian-001",
    )
  let tasks_ver = dispatch_subagent_delegation(ctx_ver, "Verify OS NVMe Lock")
  list.length(tasks_ver) |> should.equal(2)
}

pub fn runbook_loading_and_steps_test() {
  let rb_sdlc = load_sdlc_sre_runbook(C3iSdlc)
  rb_sdlc.runbook_id |> should.equal("RB-SDLC-001")
  list.length(rb_sdlc.steps) |> should.equal(4)

  let rb_sre = load_sdlc_sre_runbook(C3iSre)
  rb_sre.runbook_id |> should.equal("RB-SRE-001")
  list.length(rb_sre.steps) |> should.equal(4)

  let rb_ver = load_sdlc_sre_runbook(C3iVerification)
  rb_ver.runbook_id |> should.equal("RB-VER-001")
  list.length(rb_ver.steps) |> should.equal(4)

  let rb_intel = load_sdlc_sre_runbook(C3iIntelligence)
  rb_intel.runbook_id |> should.equal("RB-INTEL-001")
  list.length(rb_intel.steps) |> should.equal(4)
}

pub fn cognitive_context_json_serialization_test() {
  let ctx =
    initialize_agent_intelligence(
      ConstitutionalGuardian,
      C3iVerification,
      "guardian-json-001",
    )
  let json_str = encode_cognitive_context_json(ctx)

  string.contains(json_str, "\"agent_id\":\"guardian-json-001\"")
  |> should.equal(True)
  string.contains(json_str, "\"OBSERVE\"")
  |> should.equal(True)
  string.contains(json_str, "\"formal-verification-pipeline\"")
  |> should.equal(True)
  string.contains(json_str, "\"using-superpowers\"")
  |> should.equal(True)
}
