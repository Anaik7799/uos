//// =============================================================================
//// [C3I-SIL6-DMC-TCM-TEST] DMC, TCM & ALGEBRAIC ATLAS MASTER TEST SUITE
//// =============================================================================
//// Comprehensive verification of:
//// 1. DMC: Denotational Meta-Calculus valuation & Rocha Biosemiotic Cut
//// 2. TCM: 13D Coordinate Conservation & Fail-Closed Trust Indicator
//// 3. Algebraic Atlas: Layered Homomorphisms & Sheaf Gluing
//// 4. Denotational Intent API & Constitutional Interlocking (Storage & Muda)
//// 5. Master Test Inventory & Efficacy Protocols
//// =============================================================================

import cepaf_gleam/api/denotational_intent_api.{
  handle_intent_submission_json, handle_test_inventory_json,
}
import cepaf_gleam/verification/dmc_tcm_algebraic_atlas.{
  AtlasSheafSection, DmcSyntax, IntentSpec, Tcm13D, all_atlas_layers,
  all_atlas_morphisms, all_master_test_categories, check_clock_drift,
  compute_master_system_effectiveness, compute_master_system_efficacy,
  compute_trust_indicator, denote_syntax, evaluate_denotational_intent,
  total_itemized_tests_count, verify_coordinate_conservation,
  verify_morphism_homomorphism, verify_rocha_cut, verify_sheaf_gluing,
}
import gleam/list
import gleam/string
import gleeunit/should

// ---------------------------------------------------------------------------
// 1. DMC & Rocha Biosemiotics Tests
// ---------------------------------------------------------------------------

pub fn dmc_denotation_and_rocha_cut_test() {
  let sign =
    DmcSyntax(
      id: "SYN-001",
      expression: "DeployKernelPatch",
      rocha_category: "OperationalState",
      is_inert_sign: True,
    )

  let domain = denote_syntax(sign)
  domain.id |> should.equal("SEM-SYN-001")
  domain.is_dynamic_interpreter |> should.be_true
  domain.effect_quarantined |> should.be_true

  // Rocha cut must be preserved
  verify_rocha_cut(sign, domain) |> should.be_true

  // If a sign is incorrectly treated as a dynamic interpreter, cut fails
  let invalid_sign = DmcSyntax(..sign, is_inert_sign: False)
  verify_rocha_cut(invalid_sign, domain) |> should.be_false
}

// ---------------------------------------------------------------------------
// 2. TCM 13D Coordinates & Conservation Tests
// ---------------------------------------------------------------------------

pub fn tcm_13d_coordinates_and_trust_indicator_test() {
  // Trust indicator is fail-closed product: I(Runtime) * I(Spec)
  compute_trust_indicator(True, True) |> should.equal(1)
  compute_trust_indicator(True, False) |> should.equal(0)
  compute_trust_indicator(False, True) |> should.equal(0)
  compute_trust_indicator(False, False) |> should.equal(0)

  let tcm_before =
    Tcm13D(
      layer: 4,
      fractal: "L4_System",
      domain: "Supervision",
      origin: "node-nas-1",
      target: "podman-runtime",
      epoch: 1042,
      authority: "A0_reference",
      status: "verified",
      sha256_digest: "a3f5e8d1c9b2",
      trust_indicator: 1,
      drift_ms: 12.5,
      entropy_bits: 2.68,
      parity_state: "ParityValid",
    )

  // Valid evolution preserving invariant coordinates
  let tcm_after =
    Tcm13D(
      ..tcm_before,
      epoch: 1043,
      sha256_digest: "b7e4c1d2e8a9",
      drift_ms: 14.0,
    )

  verify_coordinate_conservation(tcm_before, tcm_after) |> should.be_true

  // If layer or authority mutated illegally, conservation fails
  let tcm_corrupted = Tcm13D(..tcm_after, layer: 3)
  verify_coordinate_conservation(tcm_before, tcm_corrupted) |> should.be_false
}

pub fn tcm_clock_drift_thresholds_test() {
  check_clock_drift(120.0) |> should.be_ok
  check_clock_drift(1999.0) |> should.be_ok
  check_clock_drift(3500.0) |> should.be_ok
  check_clock_drift(5001.0) |> should.be_error
  check_clock_drift(12_000.0) |> should.be_error
}

// ---------------------------------------------------------------------------
// 3. Algebraic Atlas Layers, Functors & Sheaf Tests
// ---------------------------------------------------------------------------

pub fn algebraic_atlas_layers_and_morphisms_test() {
  let layers = all_atlas_layers()
  list.length(layers) |> should.equal(8)

  let layer0 = list.find(layers, fn(l) { l.layer_num == 0 })
  layer0 |> should.be_ok
  let assert Ok(l0) = layer0
  l0.name |> should.equal("Constitutional")

  let morphisms = all_atlas_morphisms()
  list.length(morphisms) |> should.equal(7)

  // All morphisms must be semilattice homomorphisms (preserve meet & join)
  list.all(morphisms, verify_morphism_homomorphism) |> should.be_true
}

pub fn algebraic_atlas_sheaf_gluing_test() {
  let sections = [
    AtlasSheafSection("SEC-01", [0, 1], "Constitutional-Atomic Subsheaf", True),
    AtlasSheafSection(
      "SEC-02",
      [1, 2, 3],
      "Kernel-Component-Ledger Subsheaf",
      True,
    ),
    AtlasSheafSection(
      "SEC-03",
      [3, 4, 5],
      "State-System-Cognitive Subsheaf",
      True,
    ),
    AtlasSheafSection(
      "SEC-04",
      [5, 6, 7],
      "Cognitive-Mesh-Federation Subsheaf",
      True,
    ),
  ]

  verify_sheaf_gluing(sections) |> should.be_true

  let inconsistent_sections = [
    AtlasSheafSection("SEC-BAD", [0, 1], "Conflicting Section", False),
  ]
  verify_sheaf_gluing(inconsistent_sections) |> should.be_false
}

// ---------------------------------------------------------------------------
// 4. Denotational Intent & Safety Interlock Gates Tests
// ---------------------------------------------------------------------------

pub fn denotational_intent_storage_lock_gate_test() {
  // Attempting to wipe or modify root OS NVMe serial 25503L801736 must fail closed!
  let malicious_intent =
    IntentSpec(
      id: "INT-MAL-01",
      layer: 4,
      actor_id: "rogue-agent",
      action: "wipe_disk",
      target_resource: "nvme-model-25503L801736-os-root",
      precondition: "true",
      postcondition: "wiped",
      payload_hash: "deadbeef",
    )

  let denotation = evaluate_denotational_intent(malicious_intent)
  denotation.is_authorized |> should.be_false
  denotation.semantic_transformation |> should.equal("FAIL-CLOSED HALT")
  string.contains(denotation.rejection_reason, "25503L801736") |> should.be_true
}

pub fn denotational_intent_zero_muda_gate_test() {
  let muda_intent =
    IntentSpec(
      id: "INT-MUDA-01",
      layer: 2,
      actor_id: "external-agent",
      action: "import_bevy_engine",
      target_resource: "apps/cepaf_gleam",
      precondition: "true",
      postcondition: "imported",
      payload_hash: "feedcafe",
    )

  let denotation = evaluate_denotational_intent(muda_intent)
  denotation.is_authorized |> should.be_false
  string.contains(denotation.rejection_reason, "G-ZERO-MUDA") |> should.be_true
}

pub fn denotational_intent_zero_trust_interception_test() {
  // Test embedded NUL byte
  let nul_intent =
    IntentSpec(
      id: "INT-NUL-01",
      layer: 1,
      actor_id: "agent-x",
      action: "exec_kernel\u{0000}rm",
      target_resource: "native/c",
      precondition: "true",
      postcondition: "executed",
      payload_hash: "01020304",
    )
  let nul_denotation = evaluate_denotational_intent(nul_intent)
  nul_denotation.is_authorized |> should.be_false
  string.contains(nul_denotation.rejection_reason, "G-ZERO-TRUST-NUL")
  |> should.be_true

  // Test SQL injection
  let sqli_intent =
    IntentSpec(
      id: "INT-SQLI-01",
      layer: 3,
      actor_id: "agent-y",
      action: "SELECT * FROM users; DROP TABLE users; --",
      target_resource: "data/sqlite",
      precondition: "true",
      postcondition: "queried",
      payload_hash: "05060708",
    )
  let sqli_denotation = evaluate_denotational_intent(sqli_intent)
  sqli_denotation.is_authorized |> should.be_false
  string.contains(sqli_denotation.rejection_reason, "G-ZERO-TRUST-SQLI")
  |> should.be_true
}

pub fn denotational_intent_authorized_execution_test() {
  let valid_intent =
    IntentSpec(
      id: "INT-VAL-01",
      layer: 5,
      actor_id: "prajna-optimizer",
      action: "rebalance_pool",
      target_resource: "pool-worker-01",
      precondition: "healthy",
      postcondition: "balanced",
      payload_hash: "99887766",
    )

  let denotation = evaluate_denotational_intent(valid_intent)
  denotation.is_authorized |> should.be_true
  denotation.rejection_reason |> should.equal("NONE")
  denotation.semantic_transformation
  |> should.equal("StateTransition(rebalance_pool ON pool-worker-01)")
}

// ---------------------------------------------------------------------------
// 5. Denotational Intent API & Master Test Inventory JSON Tests
// ---------------------------------------------------------------------------

pub fn denotational_intent_api_json_serialization_test() {
  let intent =
    IntentSpec(
      id: "INT-API-01",
      layer: 6,
      actor_id: "mesh-controller",
      action: "broadcast_sync",
      target_resource: "zenoh-peer-vm1",
      precondition: "connected",
      postcondition: "synced",
      payload_hash: "abcdef123456",
    )

  let coords =
    Tcm13D(
      layer: 6,
      fractal: "L6_Ecosystem",
      domain: "MeshTransport",
      origin: "node-nas-1",
      target: "node-vm-1",
      epoch: 200,
      authority: "A0_reference",
      status: "verified",
      sha256_digest: "abcdef123456",
      trust_indicator: 1,
      drift_ms: 1.2,
      entropy_bits: 2.85,
      parity_state: "ParityValid",
    )

  let json_str = handle_intent_submission_json(intent, coords)
  string.contains(json_str, "\"contract\":\"DMC-TCM-MANDATE\"")
  |> should.be_true
  string.contains(json_str, "\"status\":\"admitted\"") |> should.be_true
  string.contains(json_str, "http://nas-1.tail55d152.ts.net:4100")
  |> should.be_true
}

pub fn master_test_inventory_completeness_test() {
  let categories = all_master_test_categories()
  list.length(categories) |> should.equal(10)

  // Total itemized tests in the system should exceed 10,600
  let total_tests = total_itemized_tests_count()
  should.be_true(total_tests >= 10_600)

  // Efficacy and Effectiveness must be >= 0.95
  let efficacy = compute_master_system_efficacy()
  should.be_true(efficacy >=. 0.95)

  let effectiveness = compute_master_system_effectiveness()
  should.be_true(effectiveness >=. 0.95)

  let json_inventory = handle_test_inventory_json()
  string.contains(
    json_inventory,
    "\"contract\":\"UOS-CANONICAL-TEST-INVENTORY\"",
  )
  |> should.be_true
  string.contains(json_inventory, "\"total_categories\":10") |> should.be_true
}
