// Guardian Policy Configuration Tests
// Tests the 5-mode configurable Guardian gate system
// SC-PI-002, SC-SAFETY-001, SC-SIL4-006

import cepaf_gleam/bridge/pi_tools.{
  type FederatedTool, Allowed, AllowedWithAudit, AuditOnly, Blocked, C3iTool,
  ConsensusRequired, EnforceAll, EnforceNonL0, FederatedTool, GuardianPolicy,
  GuardianRequired, Lockdown, NoGate, Permissive, PiTool, check_gate,
  default_guardian_policy, gate_decision_to_string, guardian_mode_to_string,
  is_allowed, operator_guardian_policy, production_guardian_policy,
  staging_guardian_policy,
}
import gleeunit/should

// === Helper: Create test tools ===

fn ungated_l3_tool() -> FederatedTool {
  FederatedTool(
    name: "plan_status",
    source: C3iTool,
    description: "Check planning status",
    fractal_layer: 3,
    gate: NoGate,
  )
}

fn guardian_l4_tool() -> FederatedTool {
  FederatedTool(
    name: "system_health",
    source: C3iTool,
    description: "System health check",
    fractal_layer: 4,
    gate: GuardianRequired,
  )
}

fn guardian_l0_tool() -> FederatedTool {
  FederatedTool(
    name: "system_verification",
    source: C3iTool,
    description: "L0 constitutional verification",
    fractal_layer: 0,
    gate: GuardianRequired,
  )
}

fn consensus_l0_tool() -> FederatedTool {
  FederatedTool(
    name: "emergency_stop",
    source: C3iTool,
    description: "Emergency halt",
    fractal_layer: 0,
    gate: ConsensusRequired,
  )
}

fn pi_bash_tool() -> FederatedTool {
  FederatedTool(
    name: "bash",
    source: PiTool,
    description: "Shell execution",
    fractal_layer: 4,
    gate: NoGate,
  )
}

// === Preset Policies ===

pub fn default_policy_is_permissive_test() {
  let p = default_guardian_policy()
  p.mode |> should.equal(Permissive)
  p.emergency_override |> should.be_false()
  p.audit_all |> should.be_false()
}

pub fn production_policy_is_enforce_all_test() {
  let p = production_guardian_policy()
  p.mode |> should.equal(EnforceAll)
  p.audit_all |> should.be_true()
}

pub fn staging_policy_is_audit_only_test() {
  let p = staging_guardian_policy()
  p.mode |> should.equal(AuditOnly)
  p.audit_all |> should.be_true()
}

pub fn operator_policy_is_enforce_non_l0_test() {
  let p = operator_guardian_policy()
  p.mode |> should.equal(EnforceNonL0)
  p.auto_allow_layers |> should.equal([0])
}

// === Permissive Mode (ALL allowed) ===

pub fn permissive_allows_ungated_tool_test() {
  let d = check_gate(default_guardian_policy(), ungated_l3_tool())
  is_allowed(d) |> should.be_true()
}

pub fn permissive_allows_guardian_tool_test() {
  let d = check_gate(default_guardian_policy(), guardian_l4_tool())
  is_allowed(d) |> should.be_true()
}

pub fn permissive_allows_consensus_tool_test() {
  let d = check_gate(default_guardian_policy(), consensus_l0_tool())
  is_allowed(d) |> should.be_true()
}

pub fn permissive_allows_l0_constitutional_test() {
  let d = check_gate(default_guardian_policy(), guardian_l0_tool())
  is_allowed(d) |> should.be_true()
}

pub fn permissive_reason_is_permissive_mode_test() {
  let d = check_gate(default_guardian_policy(), guardian_l4_tool())
  case d {
    Allowed(reason:) -> reason |> should.equal("permissive_mode")
    _ -> should.fail()
  }
}

// === AuditOnly Mode (ALL allowed, gated ones logged) ===

pub fn audit_allows_ungated_test() {
  let p = staging_guardian_policy()
  let d = check_gate(p, ungated_l3_tool())
  case d {
    Allowed(_) -> True |> should.be_true()
    _ -> should.fail()
  }
}

pub fn audit_allows_with_audit_guardian_test() {
  let p = staging_guardian_policy()
  let d = check_gate(p, guardian_l4_tool())
  case d {
    AllowedWithAudit(_) -> True |> should.be_true()
    _ -> should.fail()
  }
}

pub fn audit_allows_with_audit_consensus_test() {
  let p = staging_guardian_policy()
  let d = check_gate(p, consensus_l0_tool())
  case d {
    AllowedWithAudit(_) -> True |> should.be_true()
    _ -> should.fail()
  }
}

pub fn audit_is_allowed_returns_true_test() {
  let p = staging_guardian_policy()
  let d = check_gate(p, guardian_l4_tool())
  is_allowed(d) |> should.be_true()
}

// === EnforceAll Mode (gated tools BLOCKED) ===

pub fn enforce_all_allows_ungated_test() {
  let p = production_guardian_policy()
  let d = check_gate(p, ungated_l3_tool())
  is_allowed(d) |> should.be_true()
}

pub fn enforce_all_blocks_guardian_test() {
  let p = production_guardian_policy()
  let d = check_gate(p, guardian_l4_tool())
  is_allowed(d) |> should.be_false()
}

pub fn enforce_all_blocks_consensus_test() {
  let p = production_guardian_policy()
  let d = check_gate(p, consensus_l0_tool())
  is_allowed(d) |> should.be_false()
}

pub fn enforce_all_blocked_reason_test() {
  let p = production_guardian_policy()
  let d = check_gate(p, guardian_l4_tool())
  case d {
    Blocked(reason:) -> reason |> should.equal("guardian_required_enforced")
    _ -> should.fail()
  }
}

// === EnforceNonL0 Mode (L0 auto-allowed, L1-L7 enforced) ===

pub fn enforce_non_l0_allows_l0_guardian_test() {
  let p =
    GuardianPolicy(
      mode: EnforceNonL0,
      auto_allow_layers: [],
      audit_all: True,
      emergency_override: False,
    )
  let d = check_gate(p, guardian_l0_tool())
  is_allowed(d) |> should.be_true()
}

pub fn enforce_non_l0_blocks_l4_guardian_test() {
  let p =
    GuardianPolicy(
      mode: EnforceNonL0,
      auto_allow_layers: [],
      audit_all: True,
      emergency_override: False,
    )
  let d = check_gate(p, guardian_l4_tool())
  is_allowed(d) |> should.be_false()
}

pub fn enforce_non_l0_allows_ungated_test() {
  let p =
    GuardianPolicy(
      mode: EnforceNonL0,
      auto_allow_layers: [],
      audit_all: True,
      emergency_override: False,
    )
  let d = check_gate(p, ungated_l3_tool())
  is_allowed(d) |> should.be_true()
}

// === Lockdown Mode (only read-only L<=3 with NoGate) ===

pub fn lockdown_allows_readonly_l3_test() {
  let p =
    GuardianPolicy(
      mode: Lockdown,
      auto_allow_layers: [],
      audit_all: True,
      emergency_override: False,
    )
  let d = check_gate(p, ungated_l3_tool())
  is_allowed(d) |> should.be_true()
}

pub fn lockdown_blocks_l4_ungated_test() {
  let p =
    GuardianPolicy(
      mode: Lockdown,
      auto_allow_layers: [],
      audit_all: True,
      emergency_override: False,
    )
  let d = check_gate(p, pi_bash_tool())
  is_allowed(d) |> should.be_false()
}

pub fn lockdown_blocks_all_gated_test() {
  let p =
    GuardianPolicy(
      mode: Lockdown,
      auto_allow_layers: [],
      audit_all: True,
      emergency_override: False,
    )
  let d = check_gate(p, guardian_l0_tool())
  is_allowed(d) |> should.be_false()
}

// === Emergency Override ===

pub fn emergency_override_allows_everything_test() {
  let p =
    GuardianPolicy(
      mode: EnforceAll,
      auto_allow_layers: [],
      audit_all: True,
      emergency_override: True,
    )
  let d = check_gate(p, consensus_l0_tool())
  is_allowed(d) |> should.be_true()
}

pub fn emergency_override_reason_test() {
  let p =
    GuardianPolicy(
      mode: Lockdown,
      auto_allow_layers: [],
      audit_all: True,
      emergency_override: True,
    )
  let d = check_gate(p, guardian_l4_tool())
  case d {
    Allowed(reason:) -> reason |> should.equal("emergency_override_active")
    _ -> should.fail()
  }
}

// === Per-Layer Auto-Allow ===

pub fn layer_override_allows_in_enforce_all_test() {
  let p =
    GuardianPolicy(
      mode: EnforceAll,
      auto_allow_layers: [4],
      audit_all: True,
      emergency_override: False,
    )
  let d = check_gate(p, guardian_l4_tool())
  is_allowed(d) |> should.be_true()
}

pub fn layer_override_does_not_affect_other_layers_test() {
  let p =
    GuardianPolicy(
      mode: EnforceAll,
      auto_allow_layers: [3],
      audit_all: True,
      emergency_override: False,
    )
  let d = check_gate(p, guardian_l4_tool())
  is_allowed(d) |> should.be_false()
}

// === String Conversions ===

pub fn guardian_mode_to_string_permissive_test() {
  guardian_mode_to_string(Permissive) |> should.equal("permissive")
}

pub fn guardian_mode_to_string_enforce_all_test() {
  guardian_mode_to_string(EnforceAll) |> should.equal("enforce_all")
}

pub fn guardian_mode_to_string_lockdown_test() {
  guardian_mode_to_string(Lockdown) |> should.equal("lockdown")
}

pub fn gate_decision_to_string_allowed_test() {
  gate_decision_to_string(Allowed(reason: "test"))
  |> should.equal("ALLOWED: test")
}

pub fn gate_decision_to_string_blocked_test() {
  gate_decision_to_string(Blocked(reason: "denied"))
  |> should.equal("BLOCKED: denied")
}

pub fn gate_decision_to_string_audit_test() {
  gate_decision_to_string(AllowedWithAudit(reason: "logged"))
  |> should.equal("ALLOWED_AUDIT: logged")
}
