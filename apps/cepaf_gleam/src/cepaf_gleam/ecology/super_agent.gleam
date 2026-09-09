//// =============================================================================
//// [C3I-BOUNDED-ECOLOGY] UOS AGENTIC PARTICIPANT & CAPABILITY SELECTION
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ecology/super_agent</module>
////     <authority>UOS-CANONICAL-AGENT-POLICY</authority>
////   </identity>
////   <fractal-topology>
////     <layer>L5_COGNITIVE</layer>
////     <mesh-domain>Holon Ecology, Super-Agent Architecture & Capabilities</mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>REVERSIBLE LOCAL STATE; NOT SYSTEM ADMISSION</criticality>
////     <stamp-controls>
////       SC-HOLON-001, SC-BIO-EVO-001, SC-MATH-001, SC-ZERO-MUDA-001
////     </stamp-controls>
////   </compliance>
//// </c3i-module>
//// =============================================================================
////
//// Every participant model can discover the common eleven capability ports.
//// Availability and actual execution remain separate observed outcomes:
////   1. F Prime (FPP) Component-Port State Machine Architecture
////   2. Bayesian Inference, Beta Beliefs & Pareto Optimization
////   3. Hermes Rete-UL Token Forward-Chaining Deduction
////   4. ETS Lockless Microsecond BEAM Term Storage
////   5. Two-Lattice Software Transactional Memory (STM)
////   6. Modular MAX / Mojo SIMD Hardware Tensor Acceleration
////   7. OpenRouter Free-Tier LLM Multi-Model Dialectic ($0.00 ceiling)
////   8. Ruliad & Multiway Computational Branchial Space Exploration
////   9. Formal Modeling & Digital Twinning (Lean 4, Quint, TLA+)
////  10. Denotational Design & 17-Aspect Verification Matrix
////  11. Algebraic Structure & Sheaf Atlas Chart Gluing
////
//// Selective Activation: Holons possess all 11 capabilities by construction,
//// but dynamically activate only the subset demanded by their current
//// operational mode (Reflex, Deliberative, Autonomous, SovereignEvolution).
////
//// STAMP: SC-HOLON-001, SC-BIO-EVO-001, SC-MATH-001, SC-ZERO-MUDA-001.

import gleam/json.{type Json}
import gleam/list

// =============================================================================
// 1. Core Types & Holon Lifecycle FSM
// =============================================================================

pub type Lifecycle {
  Dormant
  Awakening
  Active
  Stressed
  Healing
  Apoptotic
}

pub fn lifecycle_to_string(l: Lifecycle) -> String {
  case l {
    Dormant -> "dormant"
    Awakening -> "awakening"
    Active -> "active"
    Stressed -> "stressed"
    Healing -> "healing"
    Apoptotic -> "apoptotic"
  }
}

pub type OperationalMode {
  /// Minimal autonomic selection: ETS + FPrime.
  Reflex
  /// Analytical problem solving: + Bayesian + Rete-UL + STM
  Deliberative
  /// Distributed autonomic execution: + Mojo ML + OpenRouter Free
  Autonomous
  /// Full creative, formal and topological self-evolution: All 11 capabilities active
  SovereignEvolution
}

pub fn mode_to_string(m: OperationalMode) -> String {
  case m {
    Reflex -> "reflex"
    Deliberative -> "deliberative"
    Autonomous -> "autonomous"
    SovereignEvolution -> "sovereign_evolution"
  }
}

// =============================================================================
// 2. The 11 Systemic Capabilities Mask
// =============================================================================

pub type CapabilityMask {
  CapabilityMask(
    /// 1. F Prime (FPP) Component-Port State Machine Architecture
    fprime: Bool,
    /// 2. Bayesian Inference & Beta Distribution Tracking
    bayesian: Bool,
    /// 3. Hermes Rete-UL Token Forward-Chaining Pattern Matcher
    rete_ul: Bool,
    /// 4. ETS Ultra-Low Latency In-Memory Term Storage
    ets: Bool,
    /// 5. Two-Lattice Software Transactional Memory (STM)
    stm: Bool,
    /// 6. Modular MAX / Mojo SIMD Tensor Operations
    modular_max: Bool,
    /// 7. OpenRouter Free-Tier LLM Multi-Model Dialectic
    openrouter_free: Bool,
    /// 8. Ruliad & Multiway Computational Branchial Space
    ruliad: Bool,
    /// 9. Formal Digital Twin & Mathematical Verification (Lean 4 / Quint)
    formal_twin: Bool,
    /// 10. Denotational Design & 17-Aspect Verification Matrix
    denotational: Bool,
    /// 11. Algebraic Structure & Sheaf Atlas Chart Gluing
    algebraic_atlas: Bool,
  )
}

/// All 11 capabilities disabled (passive baseline)
pub const all_disabled = CapabilityMask(
  fprime: False,
  bayesian: False,
  rete_ul: False,
  ets: False,
  stm: False,
  modular_max: False,
  openrouter_free: False,
  ruliad: False,
  formal_twin: False,
  denotational: False,
  algebraic_atlas: False,
)

/// All 11 capabilities enabled (full super-agent power)
pub const all_enabled = CapabilityMask(
  fprime: True,
  bayesian: True,
  rete_ul: True,
  ets: True,
  stm: True,
  modular_max: True,
  openrouter_free: True,
  ruliad: True,
  formal_twin: True,
  denotational: True,
  algebraic_atlas: True,
)

/// Discoverable services are shared by every agentic holon. A selected mask is
/// an activation preference; neither selection nor discovery proves a backend ran.
pub const all_capability_names: List(String) = [
  "fprime", "bayesian", "rete_ul", "ets", "stm", "modular_max",
  "openrouter_free", "ruliad", "formal_twin", "denotational", "algebraic_atlas",
]

/// Generate capability mask corresponding to an operational mode
pub fn mask_for_mode(mode: OperationalMode) -> CapabilityMask {
  case mode {
    Reflex -> CapabilityMask(..all_disabled, fprime: True, ets: True)
    Deliberative ->
      CapabilityMask(
        ..all_disabled,
        fprime: True,
        ets: True,
        bayesian: True,
        rete_ul: True,
        stm: True,
      )
    Autonomous ->
      CapabilityMask(
        ..all_disabled,
        fprime: True,
        ets: True,
        bayesian: True,
        rete_ul: True,
        stm: True,
        modular_max: True,
        openrouter_free: True,
      )
    SovereignEvolution -> all_enabled
  }
}

/// Count how many capabilities are currently active
pub fn active_capability_count(mask: CapabilityMask) -> Int {
  let flags = [
    mask.fprime,
    mask.bayesian,
    mask.rete_ul,
    mask.ets,
    mask.stm,
    mask.modular_max,
    mask.openrouter_free,
    mask.ruliad,
    mask.formal_twin,
    mask.denotational,
    mask.algebraic_atlas,
  ]
  list.fold(flags, 0, fn(acc, active) {
    case active {
      True -> acc + 1
      False -> acc
    }
  })
}

// =============================================================================
// 3. Substrate States & Structures for the 11 Capabilities
// =============================================================================

/// 1. F Prime state: Port counts and active rate group
pub type FPrimeState {
  FPrimeState(
    component_name: String,
    rate_group_hz: Float,
    input_ports: List(String),
    output_ports: List(String),
    telemetry_channels: List(String),
  )
}

/// 2. Bayesian belief state: Gaussian mean/variance and Beta health belief
pub type BayesianState {
  BayesianState(
    prior_mean: Float,
    prior_variance: Float,
    alpha_health: Float,
    beta_health: Float,
    expected_divergence_pct: Float,
  )
}

/// 3. Rete-UL state: Token count and active discrimination nodes
pub type ReteULState {
  ReteULState(
    tokens_evaluated: Int,
    alpha_nodes_count: Int,
    beta_nodes_count: Int,
    rules_fired: Int,
  )
}

/// 4. ETS state: In-memory table identifier and entry count
pub type EtsState {
  EtsState(table_name: String, is_protected: Bool, cached_entries: Int)
}

/// 5. Two-Lattice STM state: Leased single-writer epoch and reader snapshot version
pub type StmState {
  StmState(
    telemetry_snapshot_version: Int,
    intent_lease_epoch: Int,
    lease_fencing_token: String,
    has_writer_lease: Bool,
  )
}

/// 6. Modular Mojo / MAX ML state: SIMD width, embeddings count, and tensor latency
pub type MojoMaxState {
  MojoMaxState(
    simd_width: Int,
    embedding_dimensions: Int,
    cached_vectors: Int,
    last_inference_us: Int,
  )
}

/// 7. OpenRouter Free state: Allowed free model allowlist and cost ledger ($0.00 ceiling)
pub type OpenRouterFreeState {
  OpenRouterFreeState(
    selected_model: String,
    cost_ceiling_usd: Float,
    cumulative_cost_usd: Float,
    advisory_tokens_spent: Int,
  )
}

/// 8. Ruliad state: Multiway branch count and branchial distance
pub type RuliadState {
  RuliadState(
    multiway_step: Int,
    branch_count: Int,
    causal_invariance_holds: Bool,
    branchial_entropy: Float,
  )
}

/// 9. Formal Digital Twin state: Lean 4 proof status and Quint parity checks
pub type FormalTwinState {
  FormalTwinState(
    lean4_theorems_proved: Int,
    quint_invariants_checked: Int,
    sorry_count: Int,
    digital_twin_parity_pct: Float,
  )
}

/// 10. Denotational Design state: 17-aspect verification score
pub type DenotationalState {
  DenotationalState(
    aspects_satisfied: Int,
    aspects_total: Int,
    fail_closed_passed: Bool,
  )
}

/// 11. Algebraic Atlas state: Sheaf charts glued and 13D coordinate divergence
pub type AlgebraicAtlasState {
  AlgebraicAtlasState(
    charts_glued: Int,
    sheaf_consistency: Bool,
    delta_t13_norm: Float,
  )
}

// =============================================================================
// 4. The Super-Agent Holon Record
// =============================================================================

pub type SuperAgentHolon {
  SuperAgentHolon(
    id: String,
    name: String,
    plane: String,
    level: Int,
    lifecycle: Lifecycle,
    mode: OperationalMode,
    mask: CapabilityMask,
    // Autonomic Homeostasis State
    homeostatic_error: Float,
    lyapunov_energy: Float,
    freshness_ticks: Int,
    successful_invocations: Int,
    unavailable_invocations: Int,
    masked_invocations: Int,
    last_capability: String,
    last_outcome: String,
    // Substrate states
    fprime: FPrimeState,
    bayesian: BayesianState,
    rete_ul: ReteULState,
    ets: EtsState,
    stm: StmState,
    mojo_max: MojoMaxState,
    openrouter_free: OpenRouterFreeState,
    ruliad: RuliadState,
    formal_twin: FormalTwinState,
    denotational: DenotationalState,
    algebraic_atlas: AlgebraicAtlasState,
  )
}

/// Create a new Super-Agent holon with default safe initializations
pub fn create_super_agent(
  id: String,
  name: String,
  plane: String,
  level: Int,
) -> SuperAgentHolon {
  SuperAgentHolon(
    id: id,
    name: name,
    plane: plane,
    level: level,
    lifecycle: Dormant,
    mode: Reflex,
    mask: mask_for_mode(Reflex),
    homeostatic_error: 0.0,
    lyapunov_energy: 0.0,
    freshness_ticks: 0,
    successful_invocations: 0,
    unavailable_invocations: 0,
    masked_invocations: 0,
    last_capability: "",
    last_outcome: "unrun",
    fprime: FPrimeState(
      component_name: id,
      rate_group_hz: 1.0,
      input_ports: ["cmd_in", "telemetry_in"],
      output_ports: ["event_out", "telemetry_out"],
      telemetry_channels: ["health", "latency", "entropy"],
    ),
    bayesian: BayesianState(
      prior_mean: 1.0,
      prior_variance: 0.01,
      alpha_health: 1.0,
      beta_health: 1.0,
      expected_divergence_pct: 0.0,
    ),
    rete_ul: ReteULState(
      tokens_evaluated: 0,
      alpha_nodes_count: 0,
      beta_nodes_count: 0,
      rules_fired: 0,
    ),
    ets: EtsState(
      table_name: "uos_holon_" <> id,
      is_protected: True,
      cached_entries: 0,
    ),
    stm: StmState(
      telemetry_snapshot_version: 0,
      intent_lease_epoch: 0,
      lease_fencing_token: "fence_" <> id <> "_0",
      has_writer_lease: False,
    ),
    mojo_max: MojoMaxState(
      simd_width: 0,
      embedding_dimensions: 0,
      cached_vectors: 0,
      last_inference_us: 0,
    ),
    openrouter_free: OpenRouterFreeState(
      selected_model: "",
      cost_ceiling_usd: 0.0,
      cumulative_cost_usd: 0.0,
      advisory_tokens_spent: 0,
    ),
    ruliad: RuliadState(
      multiway_step: 0,
      branch_count: 1,
      causal_invariance_holds: False,
      branchial_entropy: 0.0,
    ),
    formal_twin: FormalTwinState(
      lean4_theorems_proved: 0,
      quint_invariants_checked: 0,
      sorry_count: 0,
      digital_twin_parity_pct: 0.0,
    ),
    denotational: DenotationalState(
      aspects_satisfied: 0,
      aspects_total: 17,
      fail_closed_passed: False,
    ),
    algebraic_atlas: AlgebraicAtlasState(
      charts_glued: 0,
      sheaf_consistency: False,
      delta_t13_norm: 0.0,
    ),
  )
}

// =============================================================================
// 5. Autonomic Transitions & Selective Capability Activation
// =============================================================================

/// Awaken a dormant holon into active biological participation
pub fn awaken(holon: SuperAgentHolon) -> Result(SuperAgentHolon, String) {
  case holon.lifecycle {
    Dormant ->
      Ok(SuperAgentHolon(..holon, lifecycle: Awakening, freshness_ticks: 1))
    Awakening ->
      Ok(SuperAgentHolon(..holon, lifecycle: Active, freshness_ticks: 1))
    Active -> Ok(holon)
    Stressed -> Ok(SuperAgentHolon(..holon, lifecycle: Healing))
    Healing -> Ok(SuperAgentHolon(..holon, lifecycle: Active))
    Apoptotic -> Error("Cannot awaken an apoptotic (terminated) holon")
  }
}

/// Dynamically switch operational mode and update active capability mask
pub fn set_mode(
  holon: SuperAgentHolon,
  mode: OperationalMode,
) -> SuperAgentHolon {
  SuperAgentHolon(..holon, mode: mode, mask: mask_for_mode(mode))
}

/// Custom selective activation: Enable or disable a specific capability
pub fn toggle_capability(
  holon: SuperAgentHolon,
  capability: String,
  enabled: Bool,
) -> Result(SuperAgentHolon, String) {
  let m = holon.mask
  case capability {
    "fprime" ->
      Ok(SuperAgentHolon(..holon, mask: CapabilityMask(..m, fprime: enabled)))
    "bayesian" ->
      Ok(SuperAgentHolon(..holon, mask: CapabilityMask(..m, bayesian: enabled)))
    "rete_ul" ->
      Ok(SuperAgentHolon(..holon, mask: CapabilityMask(..m, rete_ul: enabled)))
    "ets" ->
      Ok(SuperAgentHolon(..holon, mask: CapabilityMask(..m, ets: enabled)))
    "stm" ->
      Ok(SuperAgentHolon(..holon, mask: CapabilityMask(..m, stm: enabled)))
    "modular_max" ->
      Ok(
        SuperAgentHolon(
          ..holon,
          mask: CapabilityMask(..m, modular_max: enabled),
        ),
      )
    "openrouter_free" ->
      Ok(
        SuperAgentHolon(
          ..holon,
          mask: CapabilityMask(..m, openrouter_free: enabled),
        ),
      )
    "ruliad" ->
      Ok(SuperAgentHolon(..holon, mask: CapabilityMask(..m, ruliad: enabled)))
    "formal_twin" ->
      Ok(
        SuperAgentHolon(
          ..holon,
          mask: CapabilityMask(..m, formal_twin: enabled),
        ),
      )
    "denotational" ->
      Ok(
        SuperAgentHolon(
          ..holon,
          mask: CapabilityMask(..m, denotational: enabled),
        ),
      )
    "algebraic_atlas" ->
      Ok(
        SuperAgentHolon(
          ..holon,
          mask: CapabilityMask(..m, algebraic_atlas: enabled),
        ),
      )
    _ -> Error("Unknown capability name: " <> capability)
  }
}

// =============================================================================
// 6. Continuous Homeostatic Autonomic Pulse (OODA Loop)
// =============================================================================

pub type AutonomicPulseReport {
  AutonomicPulseReport(
    holon_id: String,
    lifecycle: Lifecycle,
    mode: OperationalMode,
    active_capabilities: Int,
    homeostatic_error: Float,
    lyapunov_energy: Float,
    is_stable: Bool,
    action_taken: String,
  )
}

/// Perform one continuous autonomic cycle (Observe, Orient, Decide, Act, Reflect)
pub fn execute_autonomic_pulse(
  holon: SuperAgentHolon,
  observed_latency_ms: Float,
  target_latency_ms: Float,
) -> #(SuperAgentHolon, AutonomicPulseReport) {
  // 1. OBSERVE & ORIENT: Compute homeostatic error and Lyapunov energy V(e) = 0.5 * e^2
  let observation_valid =
    target_latency_ms >. 0.0 && observed_latency_ms >=. 0.0
  let raw_error = case observation_valid {
    True -> { observed_latency_ms -. target_latency_ms } /. target_latency_ms
    False -> 1.0
  }
  let energy = 0.5 *. raw_error *. raw_error
  let is_stable = energy <=. 0.05

  // 2. DECIDE: Update Bayesian beliefs if active
  let updated_bayesian = case holon.mask.bayesian && observation_valid {
    True -> {
      let b = holon.bayesian
      let alpha = case is_stable {
        True -> b.alpha_health +. 1.0
        False -> b.alpha_health
      }
      let beta = case is_stable {
        True -> b.beta_health
        False -> b.beta_health +. 1.0
      }
      BayesianState(..b, alpha_health: alpha, beta_health: beta)
    }
    False -> holon.bayesian
  }

  // Backend work is dispatched separately and credited only from its Outcome.
  // A heartbeat observation is not a Rete firing, rewrite, proof or inference.

  // 5. REFLECT: Determine next lifecycle state based on stability
  let next_lifecycle = case holon.lifecycle, is_stable {
    Active, False -> Stressed
    Stressed, True -> Healing
    Healing, True -> Active
    l, _ -> l
  }

  let action = case observation_valid, is_stable {
    False, _ -> "invalid_latency_observation"
    True, True -> "equilibrium_maintained"
    True, False -> "latency_stress_observed"
  }

  let updated_holon =
    SuperAgentHolon(
      ..holon,
      lifecycle: next_lifecycle,
      homeostatic_error: raw_error,
      lyapunov_energy: energy,
      freshness_ticks: holon.freshness_ticks + 1,
      bayesian: updated_bayesian,
    )

  let report =
    AutonomicPulseReport(
      holon_id: holon.id,
      lifecycle: next_lifecycle,
      mode: holon.mode,
      active_capabilities: active_capability_count(holon.mask),
      homeostatic_error: raw_error,
      lyapunov_energy: energy,
      is_stable: is_stable,
      action_taken: action,
    )

  #(updated_holon, report)
}

// =============================================================================
// 7. JSON Serialization for ZMOF Telemetry & Board Publishing
// =============================================================================

pub fn to_json(holon: SuperAgentHolon) -> Json {
  json.object([
    #("id", json.string(holon.id)),
    #("participant_kind", json.string("local_agentic_model")),
    #("external_system_binding", json.bool(False)),
    #("name", json.string(holon.name)),
    #("plane", json.string(holon.plane)),
    #("level", json.int(holon.level)),
    #("lifecycle", json.string(lifecycle_to_string(holon.lifecycle))),
    #("mode", json.string(mode_to_string(holon.mode))),
    #("active_capabilities", json.int(active_capability_count(holon.mask))),
    #("capability_catalog", json.array(all_capability_names, json.string)),
    #("successful_invocations", json.int(holon.successful_invocations)),
    #("unavailable_invocations", json.int(holon.unavailable_invocations)),
    #("masked_invocations", json.int(holon.masked_invocations)),
    #("last_capability", json.string(holon.last_capability)),
    #("last_outcome", json.string(holon.last_outcome)),
    #(
      "capabilities",
      json.object([
        #("fprime", json.bool(holon.mask.fprime)),
        #("bayesian", json.bool(holon.mask.bayesian)),
        #("rete_ul", json.bool(holon.mask.rete_ul)),
        #("ets", json.bool(holon.mask.ets)),
        #("stm", json.bool(holon.mask.stm)),
        #("modular_max", json.bool(holon.mask.modular_max)),
        #("openrouter_free", json.bool(holon.mask.openrouter_free)),
        #("ruliad", json.bool(holon.mask.ruliad)),
        #("formal_twin", json.bool(holon.mask.formal_twin)),
        #("denotational", json.bool(holon.mask.denotational)),
        #("algebraic_atlas", json.bool(holon.mask.algebraic_atlas)),
      ]),
    ),
    #("homeostatic_error", json.float(holon.homeostatic_error)),
    #("lyapunov_energy", json.float(holon.lyapunov_energy)),
    #("freshness_ticks", json.int(holon.freshness_ticks)),
  ])
}

pub fn pulse_report_to_json(report: AutonomicPulseReport) -> Json {
  json.object([
    #("holon_id", json.string(report.holon_id)),
    #("lifecycle", json.string(lifecycle_to_string(report.lifecycle))),
    #("mode", json.string(mode_to_string(report.mode))),
    #("active_capabilities", json.int(report.active_capabilities)),
    #("homeostatic_error", json.float(report.homeostatic_error)),
    #("lyapunov_energy", json.float(report.lyapunov_energy)),
    #("is_stable", json.bool(report.is_stable)),
    #("action_taken", json.string(report.action_taken)),
  ])
}
