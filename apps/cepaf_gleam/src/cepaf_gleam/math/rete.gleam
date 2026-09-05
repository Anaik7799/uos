//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/math/rete</module>
////     <fsharp-lineage>None — pure Gleam RETE-UL implementation</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L5_COGNITIVE</layer>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-OODA-003, SC-ALLIUM-001, SC-BIO-EVO-006</stamp-controls>
////   </compliance>
//// </c3i-module>
//// =============================================================================
////
//// शुद्ध RETE-UL — Pure Gleam RETE-UL Rule Engine (NIF-free fallback)
//// Pattern matching rule evaluation using salience-ordered firing.
//// No external dependencies. Falls back when NIF unavailable.
////
//// STAMP: SC-OODA-003, SC-ALLIUM-001

import gleam/dict.{type Dict}
import gleam/int
import gleam/list

// =============================================================================
// Types
// =============================================================================

/// A fact in the working memory: key-value pair.
pub type Fact {
  Fact(key: String, value: String)
}

/// A condition: tests a fact key against an expected value.
pub type Condition {
  Equals(key: String, value: String)
  NotEquals(key: String, value: String)
  GreaterThan(key: String, threshold: Int)
  LessThan(key: String, threshold: Int)
  IsTrue(key: String)
  IsFalse(key: String)
}

/// A production rule with salience (priority) and conditions.
pub type Rule {
  Rule(
    name: String,
    salience: Int,
    domain: String,
    conditions: List(Condition),
    decision: String,
    reason: String,
  )
}

/// Result of rule evaluation.
pub type RuleResult {
  RuleResult(
    decision: String,
    reason: String,
    rule_name: String,
    salience: Int,
    facts_matched: Int,
  )
}

/// A rule domain with pre-compiled rules.
pub type RuleDomain {
  RuleDomain(name: String, rules: List(Rule), evaluation_count: Int)
}

/// Working memory — fact store.
pub type WorkingMemory {
  WorkingMemory(facts: Dict(String, String))
}

// =============================================================================
// Working Memory
// =============================================================================

/// Create empty working memory.
pub fn memory_new() -> WorkingMemory {
  WorkingMemory(facts: dict.new())
}

/// Set a fact in working memory.
pub fn memory_set(
  wm: WorkingMemory,
  key: String,
  value: String,
) -> WorkingMemory {
  WorkingMemory(facts: dict.insert(wm.facts, key, value))
}

/// Set a boolean fact.
pub fn memory_set_bool(
  wm: WorkingMemory,
  key: String,
  value: Bool,
) -> WorkingMemory {
  memory_set(wm, key, case value {
    True -> "true"
    False -> "false"
  })
}

/// Set an integer fact.
pub fn memory_set_int(
  wm: WorkingMemory,
  key: String,
  value: Int,
) -> WorkingMemory {
  memory_set(wm, key, int.to_string(value))
}

/// Get a fact value.
pub fn memory_get(wm: WorkingMemory, key: String) -> Result(String, Nil) {
  dict.get(wm.facts, key)
}

// =============================================================================
// Condition Evaluation
// =============================================================================

/// Evaluate a single condition against working memory.
pub fn eval_condition(wm: WorkingMemory, cond: Condition) -> Bool {
  case cond {
    Equals(key, expected) -> dict.get(wm.facts, key) == Ok(expected)
    NotEquals(key, expected) -> dict.get(wm.facts, key) != Ok(expected)
    GreaterThan(key, threshold) ->
      case dict.get(wm.facts, key) {
        Ok(v) ->
          case int.parse(v) {
            Ok(n) -> n > threshold
            Error(_) -> False
          }
        Error(_) -> False
      }
    LessThan(key, threshold) ->
      case dict.get(wm.facts, key) {
        Ok(v) ->
          case int.parse(v) {
            Ok(n) -> n < threshold
            Error(_) -> False
          }
        Error(_) -> False
      }
    IsTrue(key) -> dict.get(wm.facts, key) == Ok("true")
    IsFalse(key) -> dict.get(wm.facts, key) == Ok("false")
  }
}

/// Evaluate all conditions (AND semantics).
pub fn eval_all_conditions(
  wm: WorkingMemory,
  conditions: List(Condition),
) -> Bool {
  list.all(conditions, fn(c) { eval_condition(wm, c) })
}

// =============================================================================
// Rule Evaluation (Salience-Ordered)
// =============================================================================

/// Evaluate rules against working memory.
/// Returns the highest-salience rule whose conditions all match.
pub fn evaluate(rules: List(Rule), wm: WorkingMemory) -> RuleResult {
  let sorted =
    list.sort(rules, fn(a, b) { int.compare(b.salience, a.salience) })
  let matched =
    list.find(sorted, fn(r) { eval_all_conditions(wm, r.conditions) })
  case matched {
    Ok(r) ->
      RuleResult(
        decision: r.decision,
        reason: r.reason,
        rule_name: r.name,
        salience: r.salience,
        facts_matched: list.length(r.conditions),
      )
    Error(_) ->
      RuleResult(
        decision: "NoAction",
        reason: "No matching rules",
        rule_name: "",
        salience: 0,
        facts_matched: 0,
      )
  }
}

/// Evaluate a domain's rules.
pub fn evaluate_domain(
  domain: RuleDomain,
  wm: WorkingMemory,
) -> #(RuleDomain, RuleResult) {
  let result = evaluate(domain.rules, wm)
  #(RuleDomain(..domain, evaluation_count: domain.evaluation_count + 1), result)
}

// =============================================================================
// Pre-built Domains (matching Rust 13 + Gleam 2 = 15 domains)
// =============================================================================

/// OODA Decide domain (7 rules).
pub fn ooda_domain() -> RuleDomain {
  RuleDomain(name: "ooda", evaluation_count: 0, rules: [
    Rule(
      "EmergencyStop",
      100,
      "ooda",
      [IsTrue("mesh_running"), IsTrue("missing_critical")],
      "EmergencyStop",
      "Missing critical nodes while running",
    ),
    Rule(
      "CascadeApoptosis",
      100,
      "ooda",
      [IsTrue("mesh_running"), IsTrue("high_drift")],
      "EmergencyStop",
      "Cascade failure: >5 drifted",
    ),
    Rule(
      "BootMesh",
      90,
      "ooda",
      [IsFalse("mesh_running"), IsTrue("missing_critical")],
      "BootMesh",
      "Initial boot required",
    ),
    Rule(
      "RestartDrift",
      80,
      "ooda",
      [
        IsTrue("drift_detected"),
        IsFalse("missing_critical"),
        IsFalse("high_drift"),
      ],
      "RestartContainer",
      "Single container drifted",
    ),
    Rule(
      "HealthCheck",
      60,
      "ooda",
      [IsTrue("drift_detected"), IsTrue("multi_drift"), IsFalse("high_drift")],
      "HealthCheck",
      "Multiple containers degraded",
    ),
    Rule(
      "DrainEscalate",
      40,
      "ooda",
      [IsTrue("drift_detected"), IsFalse("multi_drift")],
      "DrainContainer",
      "Ambiguous drift, escalating",
    ),
    Rule(
      "NoAction",
      10,
      "ooda",
      [IsFalse("drift_detected"), IsFalse("missing_critical")],
      "NoAction",
      "Mesh aligned",
    ),
  ])
}

/// Governor domain (3 rules).
pub fn governor_domain() -> RuleDomain {
  RuleDomain(name: "governor", evaluation_count: 0, rules: [
    Rule(
      "Wait",
      100,
      "governor",
      [GreaterThan("cpu_pct", 85)],
      "Wait",
      "CPU > 85%",
    ),
    Rule(
      "HeavyThrottle",
      70,
      "governor",
      [GreaterThan("cpu_pct", 69), LessThan("cpu_pct", 86)],
      "HeavyThrottle",
      "CPU 70-85%",
    ),
    Rule(
      "FullSpeed",
      10,
      "governor",
      [LessThan("cpu_pct", 70)],
      "FullSpeed",
      "CPU < 70%",
    ),
  ])
}

/// Symbiosis domain — NEW: ecological relationship governance.
pub fn symbiosis_domain() -> RuleDomain {
  RuleDomain(name: "symbiosis", evaluation_count: 0, rules: [
    Rule(
      "ParasiticQuarantine",
      100,
      "symbiosis",
      [IsTrue("parasitism_dominant"), IsTrue("global_negative")],
      "Quarantine",
      "Parasitic relationship dominates ecosystem",
    ),
    Rule(
      "RebalanceMesh",
      80,
      "symbiosis",
      [IsTrue("low_mutualism"), IsFalse("parasitism_dominant")],
      "Rebalance",
      "Mutualism ratio below 0.5",
    ),
    Rule(
      "BoostMutualism",
      60,
      "symbiosis",
      [IsTrue("mutualism_declining"), IsFalse("low_mutualism")],
      "BoostMutualism",
      "Mutualism ratio declining trend",
    ),
    Rule(
      "HealthyEcosystem",
      10,
      "symbiosis",
      [IsFalse("parasitism_dominant"), IsFalse("low_mutualism")],
      "Healthy",
      "Ecosystem mutualistic and stable",
    ),
  ])
}

/// Tensor coverage domain — NEW: biomorphic tensor governance.
pub fn tensor_domain() -> RuleDomain {
  RuleDomain(name: "tensor", evaluation_count: 0, rules: [
    Rule(
      "CriticalGap",
      100,
      "tensor",
      [IsTrue("has_missing"), GreaterThan("missing_count", 2)],
      "CriticalGap",
      "3+ tensor cells missing",
    ),
    Rule(
      "MinorGap",
      60,
      "tensor",
      [IsTrue("has_missing"), LessThan("missing_count", 3)],
      "MinorGap",
      "1-2 tensor cells missing",
    ),
    Rule(
      "LowHealth",
      50,
      "tensor",
      [IsFalse("has_missing"), LessThan("health_pct", 80)],
      "Improve",
      "Coverage 100% but health < 80%",
    ),
    Rule(
      "FullCoverage",
      10,
      "tensor",
      [IsFalse("has_missing"), GreaterThan("health_pct", 79)],
      "Optimal",
      "Full coverage, health > 80%",
    ),
  ])
}

// =============================================================================
// Domain Count
// =============================================================================

// Total number of RETE-UL domains (13 Rust + 2 Gleam-only = 15 + 2 new = 17).
// domain_count moved below all_domains()

// total_rule_count moved below all_domains()

// =============================================================================
// Decision Fusion (निर्णय संलयन)
// =============================================================================

/// Fuse multiple domain results by priority.
/// Returns the highest-salience non-NoAction result.
pub fn fuse_decisions(results: List(RuleResult)) -> RuleResult {
  let actionable = list.filter(results, fn(r) { r.decision != "NoAction" })
  let sorted =
    list.sort(actionable, fn(a, b) { int.compare(b.salience, a.salience) })
  case sorted {
    [first, ..] -> first
    [] ->
      RuleResult(
        decision: "NoAction",
        reason: "All domains nominal",
        rule_name: "fusion",
        salience: 0,
        facts_matched: 0,
      )
  }
}

/// Perception domain — autonomous sensor fusion governance.
pub fn perception_domain() -> RuleDomain {
  RuleDomain(name: "perception", evaluation_count: 0, rules: [
    Rule(
      "SensorFusion",
      100,
      "perception",
      [GreaterThan("sensor_count", 3), LessThan("latency_ms", 50)],
      "fuse_all_sensors",
      "All sensors available, latency nominal",
    ),
    Rule(
      "PerceptionTimeout",
      95,
      "perception",
      [GreaterThan("latency_ms", 200)],
      "emergency_safe_state",
      "Perception latency exceeds 200ms budget",
    ),
    Rule(
      "BlindSpot",
      90,
      "perception",
      [LessThan("coverage_pct", 80)],
      "activate_backup_sensors",
      "Coverage below 80% threshold",
    ),
    Rule(
      "DegradedPerception",
      80,
      "perception",
      [GreaterThan("sensor_count", 0), LessThan("sensor_count", 4)],
      "partial_fusion",
      "Reduced sensor count, partial fusion",
    ),
    Rule(
      "NominalPerception",
      10,
      "perception",
      [IsTrue("sensors_online")],
      "continue_nominal",
      "All perception systems nominal",
    ),
  ])
}

/// Self-healing domain — autonomous network recovery governance.
pub fn self_healing_domain() -> RuleDomain {
  RuleDomain(name: "self_healing", evaluation_count: 0, rules: [
    Rule(
      "CascadeContainment",
      100,
      "self_healing",
      [GreaterThan("cascade_depth", 3)],
      "isolate_and_contain",
      "Cascade depth exceeds isolation threshold",
    ),
    Rule(
      "AutoRecovery",
      80,
      "self_healing",
      [GreaterThan("failure_count", 0), LessThan("failure_count", 4)],
      "attempt_auto_recovery",
      "Recoverable failure count detected",
    ),
    Rule(
      "PredictiveRepair",
      70,
      "self_healing",
      [IsTrue("drift_detected"), GreaterThan("health_pct", 60)],
      "schedule_preventive",
      "Drift detected while still healthy",
    ),
    Rule(
      "DegradedOperation",
      60,
      "self_healing",
      [LessThan("health_pct", 61), GreaterThan("health_pct", 30)],
      "enter_degraded_mode",
      "Health below threshold, enter degraded",
    ),
    Rule(
      "HealthySystem",
      10,
      "self_healing",
      [IsFalse("drift_detected"), GreaterThan("health_pct", 80)],
      "dark_cockpit",
      "System healthy, suppress nominal noise",
    ),
  ])
}

/// Swarm coordination domain — multi-agent swarm governance.
pub fn swarm_coordination_domain() -> RuleDomain {
  RuleDomain(name: "swarm", evaluation_count: 0, rules: [
    Rule(
      "LeaderElection",
      100,
      "swarm",
      [IsFalse("leader_alive")],
      "elect_new_leader",
      "Leader node unresponsive, initiate election",
    ),
    Rule(
      "QuorumLost",
      90,
      "swarm",
      [LessThan("quorum_size", 3)],
      "emergency_consensus",
      "Quorum below minimum 3 nodes",
    ),
    Rule(
      "TaskRebalance",
      80,
      "swarm",
      [GreaterThan("load_imbalance_pct", 30)],
      "rebalance_tasks",
      "Load imbalance exceeds 30% threshold",
    ),
    Rule(
      "SwarmHealthy",
      10,
      "swarm",
      [IsTrue("leader_alive"), GreaterThan("quorum_size", 2)],
      "continue_operations",
      "Swarm quorum maintained, leader alive",
    ),
  ])
}

/// Safety domain — IEC 61508 safety kernel governance.
pub fn safety_domain() -> RuleDomain {
  RuleDomain(name: "safety", evaluation_count: 0, rules: [
    Rule(
      "EmergencyStop",
      100,
      "safety",
      [IsTrue("e_stop_pressed")],
      "immediate_halt",
      "Emergency stop activated by operator",
    ),
    Rule(
      "SafetyEnvelopeViolation",
      95,
      "safety",
      [IsFalse("within_envelope")],
      "return_to_safe_state",
      "Operating outside safety envelope",
    ),
    Rule(
      "RedundancyLoss",
      90,
      "safety",
      [LessThan("redundancy_level", 2)],
      "activate_backup",
      "Redundancy below SIL-6 minimum of 2",
    ),
    Rule(
      "WatchdogTimeout",
      85,
      "safety",
      [IsFalse("watchdog_alive")],
      "trigger_failsafe",
      "Watchdog heartbeat lost, trigger failsafe",
    ),
    Rule(
      "SafeNominal",
      10,
      "safety",
      [IsTrue("within_envelope"), IsTrue("watchdog_alive")],
      "continue_safe_operation",
      "All safety invariants satisfied",
    ),
  ])
}

/// Knowledge domain — Zettelkasten-driven decision governance.
pub fn knowledge_domain() -> RuleDomain {
  RuleDomain(name: "knowledge", evaluation_count: 0, rules: [
    Rule(
      "AntiPatternDetected",
      100,
      "knowledge",
      [IsTrue("anti_pattern")],
      "block_and_alert",
      "ZK anti-pattern matches current approach",
    ),
    Rule(
      "StaleKnowledge",
      80,
      "knowledge",
      [GreaterThan("knowledge_age_days", 30)],
      "verify_and_refresh",
      "Knowledge older than 30 days, verify",
    ),
    Rule(
      "ProvenPattern",
      70,
      "knowledge",
      [IsTrue("proven_match"), LessThan("knowledge_age_days", 31)],
      "apply_proven_pattern",
      "Recent proven pattern found in ZK",
    ),
    Rule(
      "FirstPrinciples",
      10,
      "knowledge",
      [IsFalse("anti_pattern"), IsFalse("proven_match")],
      "reason_from_scratch",
      "No ZK match, reason from first principles",
    ),
  ])
}

/// Matrix protocol domain — Matrix homeserver governance.
pub fn matrix_domain() -> RuleDomain {
  RuleDomain(name: "matrix", evaluation_count: 0, rules: [
    Rule(
      "MatrixFederationDown",
      100,
      "matrix",
      [IsTrue("matrix_running"), Equals("federation_peers", "0")],
      "AlertFederationDown",
      "No federation peers connected",
    ),
    Rule(
      "MatrixRoomFlood",
      90,
      "matrix",
      [GreaterThan("matrix_msg_per_min", 100)],
      "ThrottleRoom",
      "Message flood detected in Matrix room",
    ),
    Rule(
      "MatrixSyncStale",
      80,
      "matrix",
      [GreaterThan("matrix_sync_age_sec", 60)],
      "RestartSync",
      "Matrix sync loop stale > 60s",
    ),
    Rule(
      "MatrixE2EERotation",
      70,
      "matrix",
      [GreaterThan("key_age_hours", 24)],
      "RotateKeys",
      "E2EE keys older than 24 hours",
    ),
    Rule(
      "MatrixHealthy",
      10,
      "matrix",
      [IsTrue("matrix_running"), IsFalse("matrix_sync_stale")],
      "Continue",
      "Matrix homeserver healthy",
    ),
  ])
}

/// List all 10 domain names.
pub fn all_domains() -> List(String) {
  [
    "ooda", "governor", "symbiosis", "tensor", "perception", "self_healing",
    "swarm", "safety", "knowledge", "matrix",
  ]
}

/// Total domain count (4 original + 6 new + 13 Rust = 23).
pub fn domain_count() -> Int {
  23
}

/// Total rule count across all domains (Rust 52 + Gleam 46 = 98).
pub fn total_rule_count() -> Int {
  98
}

/// Format a rule result as audit string.
pub fn result_to_string(r: RuleResult) -> String {
  r.rule_name
  <> "("
  <> int.to_string(r.salience)
  <> "): "
  <> r.decision
  <> " — "
  <> r.reason
}
