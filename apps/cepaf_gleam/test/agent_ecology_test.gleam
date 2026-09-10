//// =============================================================================
//// [C3I-SIL6-MSTS] UOS Agent Ecology & 17 Aspects Unit Tests
//// =============================================================================

import cepaf_gleam/harness/agent_ecology.{
  A01SubstrateHardwareSafety, A02VersionControlDiscipline, A03ZeroMudaPurity,
  A04SupervisionActorHierarchy, A05DeterministicRuntimeEngine,
  A06FormalEvidenceAnalysis, A07MathematicalAuthority,
  A08FeedbackSemioticsHomeostasis, A09QuarantinedAIInference,
  A10MeshTelemetryObservability, A11AgentEventBusProtocol,
  A12DeclarativeUIComponentCatalog, A13MultiInterfaceAccessibility,
  A14UniversalTailscaleWebNavigation, A15ComprehensiveVerificationChecklist,
  A16KnowledgeManagementTriad, A17DurableExecutionWorkflow,
  all_agent_profiles, all_system_aspects, andon_halt_quorum_missing_code,
  andon_halt_unauthorized_code, aspect_from_code, aspect_to_code,
  can_execute_capability, can_invoke_tool, evaluate_agent_intent,
  format_aspect_detail, format_aspects_summary, format_ecology_summary,
  format_profile_detail, get_agent_profile, validate_aspect_completeness,
}
import gleam/list
import gleam/string
import gleeunit/should

pub fn seventeen_aspects_count_and_completeness_test() {
  let aspects = all_system_aspects()
  should.equal(17, list.length(aspects))
  let is_complete = validate_aspect_completeness(aspects)
  should.be_true(is_complete)
}

pub fn aspect_codes_roundtrip_test() {
  should.equal("A01", aspect_to_code(A01SubstrateHardwareSafety))
  should.equal("A02", aspect_to_code(A02VersionControlDiscipline))
  should.equal("A03", aspect_to_code(A03ZeroMudaPurity))
  should.equal("A04", aspect_to_code(A04SupervisionActorHierarchy))
  should.equal("A05", aspect_to_code(A05DeterministicRuntimeEngine))
  should.equal("A06", aspect_to_code(A06FormalEvidenceAnalysis))
  should.equal("A07", aspect_to_code(A07MathematicalAuthority))
  should.equal("A08", aspect_to_code(A08FeedbackSemioticsHomeostasis))
  should.equal("A09", aspect_to_code(A09QuarantinedAIInference))
  should.equal("A10", aspect_to_code(A10MeshTelemetryObservability))
  should.equal("A11", aspect_to_code(A11AgentEventBusProtocol))
  should.equal("A12", aspect_to_code(A12DeclarativeUIComponentCatalog))
  should.equal("A13", aspect_to_code(A13MultiInterfaceAccessibility))
  should.equal("A14", aspect_to_code(A14UniversalTailscaleWebNavigation))
  should.equal("A15", aspect_to_code(A15ComprehensiveVerificationChecklist))
  should.equal("A16", aspect_to_code(A16KnowledgeManagementTriad))
  should.equal("A17", aspect_to_code(A17DurableExecutionWorkflow))

  should.be_ok(aspect_from_code("A01"))
  should.be_ok(aspect_from_code("A17"))
  should.be_error(aspect_from_code("A99"))
}

pub fn rich_agent_profiles_enumeration_test() {
  let profiles = all_agent_profiles()
  should.be_true(profiles != [])

  should.be_ok(get_agent_profile("agy_sovereign_coordinator"))
  should.be_ok(get_agent_profile("sre_homeostasis_overseer"))
  should.be_ok(get_agent_profile("security_hardware_guardian"))
  should.be_ok(get_agent_profile("multimodal_edge_ingestor"))
  should.be_ok(get_agent_profile("formal_verifier_oracle"))
  should.be_ok(get_agent_profile("knowledge_sheaf_curator"))
  should.be_ok(get_agent_profile("quarantined_inference_worker"))
  should.be_error(get_agent_profile("nonexistent_agent"))
}

pub fn capability_and_tool_allowlist_test() {
  let assert Ok(sec_profile) = get_agent_profile("security_hardware_guardian")
  should.be_true(can_execute_capability(sec_profile, "drive_serial_enclave_lock"))
  should.be_false(can_execute_capability(sec_profile, "lean4_theorem_validation"))

  should.be_true(can_invoke_tool(sec_profile, "storage_status"))
  should.be_false(can_invoke_tool(sec_profile, "drop_table_users"))
}

pub fn evaluate_agent_intent_gating_test() {
  let assert Ok(agy) = get_agent_profile("agy_sovereign_coordinator")
  let assert Ok(sec) = get_agent_profile("security_hardware_guardian")

  // Case 1: Permitted call with valid lease and no quorum needed
  let res1 = evaluate_agent_intent(agy, "plan_status", True, 0)
  should.equal(Ok("PERMITTED"), res1)

  // Case 2: Unlisted tool halts with -32002 (Andon Halt)
  let res2 = evaluate_agent_intent(agy, "unauthorized_tool", True, 0)
  should.equal(Error(andon_halt_unauthorized_code), res2)

  // Case 3: Missing lease halts with -32002
  let res3 = evaluate_agent_intent(agy, "plan_status", False, 0)
  should.equal(Error(andon_halt_unauthorized_code), res3)

  // Case 4: Security guardian requires 2oo3 quorum; quorum count 1 fails with -32003
  let res4 = evaluate_agent_intent(sec, "storage_status", True, 1)
  should.equal(Error(andon_halt_quorum_missing_code), res4)

  // Case 5: Security guardian with quorum count 2 succeeds
  let res5 = evaluate_agent_intent(sec, "storage_status", True, 2)
  should.equal(Ok("PERMITTED"), res5)
}

pub fn aspects_markdown_formatters_test() {
  let summary = format_aspects_summary()
  string.contains(summary, "A01") |> should.be_true
  string.contains(summary, "A17") |> should.be_true
  string.contains(summary, "Substrate & Hardware Safety") |> should.be_true

  let detail_a01 = format_aspect_detail("A01")
  string.contains(detail_a01, "Aspect A01: Substrate & Hardware Safety Enclave") |> should.be_true
  string.contains(detail_a01, "[REDACTED_SYSTEM_OS_SERIAL]") |> should.be_true

  let detail_a17 = format_aspect_detail("17")
  string.contains(detail_a17, "Aspect A17: Durable Execution & Workflow (Sa-Plan)") |> should.be_true
  string.contains(detail_a17, "SC-JIDOKA-001") |> should.be_true

  let detail_unknown = format_aspect_detail("invalid_code")
  string.contains(detail_unknown, "Unknown System Aspect code") |> should.be_true
}

pub fn ecology_markdown_formatters_test() {
  let summary = format_ecology_summary()
  string.contains(summary, "7 Canonical Holon Profiles") |> should.be_true
  string.contains(summary, "agy_sovereign_coordinator") |> should.be_true
  string.contains(summary, "sre_homeostasis_overseer") |> should.be_true

  let detail_agy = format_profile_detail("agy_sovereign_coordinator")
  string.contains(detail_agy, "AGY Sovereign Coordinator") |> should.be_true
  string.contains(detail_agy, "Single-Agent Safe Dispatch") |> should.be_true
  string.contains(detail_agy, "plan_status") |> should.be_true

  let detail_sec = format_profile_detail("security_hardware_guardian")
  string.contains(detail_sec, "2oo3 Constitutional Quorum Required") |> should.be_true

  let detail_unknown = format_profile_detail("unknown_agent")
  string.contains(detail_unknown, "Unknown agent profile ID") |> should.be_true
}
