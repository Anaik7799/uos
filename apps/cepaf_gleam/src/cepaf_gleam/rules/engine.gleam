//// [C3I-SIL6-MSTS] MODULE CONTRACT
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/rules/engine</module>
////     <fsharp-lineage>Cepaf.Rules.Engine</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L5_COGNITIVE</layer>
////     <mesh-domain>RETE-UL Rule Engine NIF Bridge</mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-OODA-003, SC-ALLIUM-001</stamp-controls>
////   </compliance>
//// </c3i-module>
////
//// Gleam bindings to the rust-rule-engine RETE-UL NIF.
//// Evaluates GRL (Grule Rule Language) rules against facts in <1ms.
//// Falls back to pure-Gleam stub if NIF not loaded.
////
//// STAMP: SC-OODA-003 (decide phase), SC-ALLIUM-001

import gleam/int
import gleam/list
import gleam/string

// =============================================================================
// Types
// =============================================================================

/// Result of a rule evaluation: decision + reason (auditable).
pub type RuleResult {
  RuleResult(decision: String, reason: String)
}

/// A single fact: key-value pair passed to the rule engine.
pub type Fact {
  Fact(key: String, value: String)
}

// =============================================================================
// NIF FFI Bindings
// =============================================================================

/// Evaluate GRL rules against facts via RETE-UL NIF.
/// Returns {Decision, Reason} tuple.
@external(erlang, "rule_engine_nif", "evaluate")
fn nif_evaluate(
  domain: String,
  rules_grl: String,
  facts: List(#(String, String)),
) -> #(String, String)

/// Count parsed rules (for validation).
@external(erlang, "rule_engine_nif", "parse_rules_count")
fn nif_parse_rules_count(rules_grl: String) -> Int

/// Get engine version string.
@external(erlang, "rule_engine_nif", "engine_version")
fn nif_engine_version() -> String

// =============================================================================
// Public API
// =============================================================================

/// Evaluate rules in a domain against a list of facts.
/// Uses the RETE-UL NIF for <1ms evaluation.
pub fn evaluate(
  domain: String,
  rules_grl: String,
  facts: List(Fact),
) -> RuleResult {
  let fact_tuples = list.map(facts, fn(f) { #(f.key, f.value) })
  let #(decision, reason) = nif_evaluate(domain, rules_grl, fact_tuples)
  RuleResult(decision: decision, reason: reason)
}

/// Validate GRL rules by parsing them. Returns rule count or -1 on error.
pub fn validate_rules(rules_grl: String) -> Int {
  nif_parse_rules_count(rules_grl)
}

/// Get the rule engine version.
pub fn version() -> String {
  nif_engine_version()
}

// =============================================================================
// Pre-built GRL Rule Sets (matching Rust ignition rule_engine.rs)
// =============================================================================

/// OODA Decide rules (7 rules, salience 10-100).
pub fn ooda_rules() -> String {
  "
    rule \"Emergency Stop\" salience 100 {
      when System.MeshRunning == true && System.MissingCriticalNodes == true
      then System.Decision = \"EmergencyStop\"; System.Reason = \"Missing critical nodes while running\";
    }
    rule \"Cascade Apoptosis\" salience 100 {
      when System.MeshRunning == true && System.HighDriftCount == true
      then System.Decision = \"EmergencyStop\"; System.Reason = \"Cascade failure: >5 drifted\";
    }
    rule \"Boot Mesh\" salience 90 {
      when System.MeshRunning == false && System.MissingCriticalNodes == true
      then System.Decision = \"BootMesh\"; System.Reason = \"Initial boot required\";
    }
    rule \"Restart on Drift\" salience 80 {
      when System.DriftDetected == true && System.MissingCriticalNodes == false && System.HighDriftCount == false
      then System.Decision = \"RestartContainer\"; System.Reason = \"Single container drifted\";
    }
    rule \"Health Check\" salience 60 {
      when System.DriftDetected == true && System.MultiDrift == true && System.HighDriftCount == false
      then System.Decision = \"HealthCheck\"; System.Reason = \"Multiple containers degraded\";
    }
    rule \"LLM Escalation\" salience 40 {
      when System.DriftDetected == true && System.MultiDrift == false
      then System.Decision = \"DrainContainer\"; System.Reason = \"Ambiguous drift, escalating to LLM\";
    }
    rule \"No Action\" salience 10 {
      when System.DriftDetected == false && System.MissingCriticalNodes == false
      then System.Decision = \"NoAction\"; System.Reason = \"Mesh aligned with genotype\";
    }
  "
}

/// Preflight gate rules (4 rules).
pub fn preflight_rules() -> String {
  "
    rule \"Block on Infra\" salience 100 {
      when Preflight.InfraHealthy == false
      then Preflight.Decision = \"BlockBoot\"; Preflight.Reason = \"Infrastructure not running\";
    }
    rule \"Block on Quorum\" salience 95 {
      when Preflight.ZenohQuorum == false && Preflight.InfraHealthy == true
      then Preflight.Decision = \"BlockBoot\"; Preflight.Reason = \"Zenoh quorum not achieved\";
    }
    rule \"Warn Substrate\" salience 40 {
      when Preflight.SubstrateClean == false && Preflight.InfraHealthy == true && Preflight.ZenohQuorum == true
      then Preflight.Decision = \"WarnAndProceed\"; Preflight.Reason = \"Substrate contamination\";
    }
    rule \"Pass\" salience 10 {
      when Preflight.InfraHealthy == true && Preflight.ZenohQuorum == true && Preflight.SubstrateClean == true
      then Preflight.Decision = \"Pass\"; Preflight.Reason = \"All checks passed\";
    }
  "
}

/// Cascade containment rules (3 rules).
pub fn cascade_rules() -> String {
  "
    rule \"Apoptosis\" salience 100 {
      when Cascade.HighDepth == true
      then Cascade.Decision = \"Apoptosis\"; Cascade.Reason = \"Cascade depth >= 3\";
    }
    rule \"Isolate\" salience 70 {
      when Cascade.MediumDepth == true && Cascade.P0Affected == true
      then Cascade.Decision = \"IsolateTier\"; Cascade.Reason = \"P0 in cascade\";
    }
    rule \"Monitor\" salience 40 {
      when Cascade.HighDepth == false && Cascade.MediumDepth == false
      then Cascade.Decision = \"Monitor\"; Cascade.Reason = \"Shallow cascade\";
    }
  "
}

// =============================================================================
// Convenience Evaluators
// =============================================================================

/// Evaluate OODA decide phase.
pub fn evaluate_ooda(
  mesh_running: Bool,
  missing_critical: Bool,
  drift_detected: Bool,
  multi_drift: Bool,
  high_drift: Bool,
) -> RuleResult {
  evaluate("System", ooda_rules(), [
    Fact("System.MeshRunning", bool_str(mesh_running)),
    Fact("System.MissingCriticalNodes", bool_str(missing_critical)),
    Fact("System.DriftDetected", bool_str(drift_detected)),
    Fact("System.MultiDrift", bool_str(multi_drift)),
    Fact("System.HighDriftCount", bool_str(high_drift)),
  ])
}

/// Evaluate preflight gate.
pub fn evaluate_preflight(
  infra_healthy: Bool,
  zenoh_quorum: Bool,
  substrate_clean: Bool,
) -> RuleResult {
  evaluate("Preflight", preflight_rules(), [
    Fact("Preflight.InfraHealthy", bool_str(infra_healthy)),
    Fact("Preflight.ZenohQuorum", bool_str(zenoh_quorum)),
    Fact("Preflight.SubstrateClean", bool_str(substrate_clean)),
  ])
}

/// Evaluate cascade containment.
pub fn evaluate_cascade(depth: Int, p0_affected: Bool) -> RuleResult {
  evaluate("Cascade", cascade_rules(), [
    Fact("Cascade.HighDepth", bool_str(depth >= 3)),
    Fact("Cascade.MediumDepth", bool_str(depth >= 2)),
    Fact("Cascade.P0Affected", bool_str(p0_affected)),
  ])
}

// =============================================================================
// Additional Rule Domains (matching Rust ignition 13 domains)
// =============================================================================

pub fn recovery_rules() -> String {
  "
    rule \"NIF Recovery\" salience 252 {
      when Recovery.NifFailed == true
      then Recovery.Decision = \"NifCompilation\"; Recovery.Reason = \"RPN 252\";
    }
    rule \"Cascade Recovery\" salience 230 {
      when Recovery.CascadeDetected == true && Recovery.NifFailed == false
      then Recovery.Decision = \"CascadeContainment\"; Recovery.Reason = \"RPN 230\";
    }
    rule \"Glibc Recovery\" salience 225 {
      when Recovery.GlibcConflict == true && Recovery.NifFailed == false && Recovery.CascadeDetected == false
      then Recovery.Decision = \"GlibcMusl\"; Recovery.Reason = \"RPN 225\";
    }
    rule \"No Recovery\" salience 10 {
      when Recovery.NifFailed == false && Recovery.CascadeDetected == false && Recovery.GlibcConflict == false
      then Recovery.Decision = \"NoRecovery\"; Recovery.Reason = \"No failure mode\";
    }
  "
}

pub fn health_rules() -> String {
  "
    rule \"Critical 4/5\" salience 80 {
      when Health.IsCritical == true && Health.HighAgreement == true
      then Health.Decision = \"Reached\"; Health.Reason = \"P0: 4/5 agree\";
    }
    rule \"Standard 3/5\" salience 50 {
      when Health.IsCritical == false && Health.StandardAgreement == true
      then Health.Decision = \"Reached\"; Health.Reason = \"3/5 agree\";
    }
    rule \"Degraded\" salience 30 {
      when Health.StandardAgreement == false && Health.MinimalAgreement == true
      then Health.Decision = \"Degraded\"; Health.Reason = \"2/5 agree\";
    }
    rule \"None\" salience 10 {
      when Health.MinimalAgreement == false
      then Health.Decision = \"NotReached\"; Health.Reason = \"<2/5\";
    }
  "
}

pub fn governor_rules() -> String {
  "
    rule \"Emergency Pause\" salience 100 {
      when Governor.OverLimit == true
      then Governor.Decision = \"Wait\"; Governor.Reason = \"CPU > 85%\";
    }
    rule \"Throttle\" salience 70 {
      when Governor.HighLoad == true && Governor.OverLimit == false
      then Governor.Decision = \"HeavyThrottle\"; Governor.Reason = \"CPU 70-85%\";
    }
    rule \"Full Speed\" salience 10 {
      when Governor.HighLoad == false && Governor.OverLimit == false
      then Governor.Decision = \"FullSpeed\"; Governor.Reason = \"CPU < 70%\";
    }
  "
}

pub fn verify_rules() -> String {
  "
    rule \"NonCompliant\" salience 100 {
      when Verify.CriticalFailed == true
      then Verify.Decision = \"NonCompliant\"; Verify.Reason = \"Critical failed\";
    }
    rule \"Degraded\" salience 50 {
      when Verify.CriticalFailed == false && Verify.AllPassed == false
      then Verify.Decision = \"DegradedButOperational\"; Verify.Reason = \"Non-critical failed\";
    }
    rule \"Compliant\" salience 10 {
      when Verify.AllPassed == true
      then Verify.Decision = \"Compliant\"; Verify.Reason = \"All passed\";
    }
  "
}

pub fn launch_rules() -> String {
  "
    rule \"Halt\" salience 100 {
      when Launch.TierFailed == true && Launch.CriticalFailure == true
      then Launch.Decision = \"HaltPipeline\"; Launch.Reason = \"P0 failed\";
    }
    rule \"Continue\" salience 50 {
      when Launch.TierFailed == true && Launch.CriticalFailure == false
      then Launch.Decision = \"ContinueWithWarning\"; Launch.Reason = \"Non-critical\";
    }
    rule \"Proceed\" salience 10 {
      when Launch.TierFailed == false
      then Launch.Decision = \"Proceed\"; Launch.Reason = \"Tier healthy\";
    }
  "
}

pub fn rca_rules() -> String {
  "
    rule \"L1 NIF\" salience 80 {
      when RCA.NifPattern == true
      then RCA.Decision = \"L1\"; RCA.Reason = \"NIF/binary mismatch\";
    }
    rule \"L4 Container\" salience 80 {
      when RCA.ContainerPattern == true && RCA.NifPattern == false
      then RCA.Decision = \"L4\"; RCA.Reason = \"Container failure\";
    }
    rule \"L6 Quorum\" salience 80 {
      when RCA.QuorumPattern == true
      then RCA.Decision = \"L6\"; RCA.Reason = \"Quorum loss\";
    }
    rule \"L7 LLM\" salience 10 {
      when RCA.NifPattern == false && RCA.ContainerPattern == false && RCA.QuorumPattern == false
      then RCA.Decision = \"L7_LLM\"; RCA.Reason = \"Unknown, escalate\";
    }
  "
}

// =============================================================================
// Convenience Evaluators (continued)
// =============================================================================

pub fn evaluate_recovery(nif: Bool, cascade: Bool, glibc: Bool) -> RuleResult {
  evaluate("Recovery", recovery_rules(), [
    Fact("Recovery.NifFailed", bool_str(nif)),
    Fact("Recovery.CascadeDetected", bool_str(cascade)),
    Fact("Recovery.GlibcConflict", bool_str(glibc)),
  ])
}

pub fn evaluate_health(is_critical: Bool, agreed: Int) -> RuleResult {
  evaluate("Health", health_rules(), [
    Fact("Health.IsCritical", bool_str(is_critical)),
    Fact("Health.HighAgreement", bool_str(agreed >= 4)),
    Fact("Health.StandardAgreement", bool_str(agreed >= 3)),
    Fact("Health.MinimalAgreement", bool_str(agreed >= 2)),
  ])
}

pub fn evaluate_governor(cpu_pct: Int) -> RuleResult {
  evaluate("Governor", governor_rules(), [
    Fact("Governor.OverLimit", bool_str(cpu_pct > 85)),
    Fact("Governor.HighLoad", bool_str(cpu_pct >= 70)),
  ])
}

pub fn evaluate_verify(all_passed: Bool, critical_failed: Bool) -> RuleResult {
  evaluate("Verify", verify_rules(), [
    Fact("Verify.AllPassed", bool_str(all_passed)),
    Fact("Verify.CriticalFailed", bool_str(critical_failed)),
  ])
}

pub fn evaluate_launch(tier_failed: Bool, critical: Bool) -> RuleResult {
  evaluate("Launch", launch_rules(), [
    Fact("Launch.TierFailed", bool_str(tier_failed)),
    Fact("Launch.CriticalFailure", bool_str(critical)),
  ])
}

pub fn evaluate_rca(error: String) -> RuleResult {
  let nif = string.contains(error, "NIF") || string.contains(error, "glibc")
  let container =
    string.contains(error, "container") || string.contains(error, "podman")
  let quorum =
    string.contains(error, "quorum") || string.contains(error, "split brain")
  evaluate("RCA", rca_rules(), [
    Fact("RCA.NifPattern", bool_str(nif)),
    Fact("RCA.ContainerPattern", bool_str(container)),
    Fact("RCA.QuorumPattern", bool_str(quorum)),
  ])
}

// =============================================================================
// Missing Evaluators: build, apoptosis, hysteresis, partition (13/13 parity)
// =============================================================================

pub fn build_rules() -> String {
  "
    rule \"Rebuild P0\" salience 100 {
      when Build.AgeHours >= 72 && Build.IsCritical == true
      then Build.Decision = \"Rebuild\"; Build.Reason = \"P0 stale >72h\";
    }
    rule \"Rebuild Standard\" salience 50 {
      when Build.AgeHours >= 168 && Build.IsCritical == false
      then Build.Decision = \"Rebuild\"; Build.Reason = \"Standard stale >168h\";
    }
    rule \"Skip\" salience 10 {
      when Build.AgeHours < 72
      then Build.Decision = \"Skip\"; Build.Reason = \"Image fresh\";
    }
  "
}

pub fn apoptosis_rules() -> String {
  "
    rule \"Immediate\" salience 100 {
      when Apoptosis.Severity == true && Apoptosis.DataCorrupt == true
      then Apoptosis.Decision = \"Immediate\"; Apoptosis.Reason = \"Data corrupt\";
    }
    rule \"Fast 2s\" salience 80 {
      when Apoptosis.Severity == true && Apoptosis.DataCorrupt == false
      then Apoptosis.Decision = \"Fast2s\"; Apoptosis.Reason = \"Critical no corruption\";
    }
    rule \"Graceful 10s\" salience 50 {
      when Apoptosis.Severity == false && Apoptosis.ActiveConnections == true
      then Apoptosis.Decision = \"Graceful10s\"; Apoptosis.Reason = \"Drain connections\";
    }
    rule \"Default 5s\" salience 10 {
      when Apoptosis.Severity == false && Apoptosis.ActiveConnections == false
      then Apoptosis.Decision = \"Default5s\"; Apoptosis.Reason = \"Standard shutdown\";
    }
  "
}

pub fn hysteresis_rules() -> String {
  "
    rule \"Aggressive\" salience 80 {
      when Hysteresis.HighVolatility == true
      then Hysteresis.Decision = \"Aggressive\"; Hysteresis.Reason = \"High volatility\";
    }
    rule \"Conservative\" salience 50 {
      when Hysteresis.LowVolatility == true && Hysteresis.HighVolatility == false
      then Hysteresis.Decision = \"Conservative\"; Hysteresis.Reason = \"Low volatility\";
    }
    rule \"Default\" salience 10 {
      when Hysteresis.HighVolatility == false && Hysteresis.LowVolatility == false
      then Hysteresis.Decision = \"Default\"; Hysteresis.Reason = \"Normal volatility\";
    }
  "
}

pub fn partition_rules() -> String {
  "
    rule \"Fence Minority\" salience 100 {
      when Partition.Detected == true && Partition.DbInMinority == true
      then Partition.Decision = \"FenceMinority\"; Partition.Reason = \"DB in minority partition\";
    }
    rule \"Preserve Data\" salience 70 {
      when Partition.Detected == true && Partition.DbInMinority == false
      then Partition.Decision = \"PreserveData\"; Partition.Reason = \"DB in majority\";
    }
    rule \"No Action\" salience 10 {
      when Partition.Detected == false
      then Partition.Decision = \"NoAction\"; Partition.Reason = \"No partition\";
    }
  "
}

pub fn evaluate_build(age_hours: Int, is_critical: Bool) -> RuleResult {
  evaluate("Build", build_rules(), [
    Fact("Build.AgeHours", int_to_str(age_hours)),
    Fact("Build.IsCritical", bool_str(is_critical)),
  ])
}

pub fn evaluate_apoptosis(
  severity: Bool,
  data_corrupt: Bool,
  active_connections: Bool,
) -> RuleResult {
  evaluate("Apoptosis", apoptosis_rules(), [
    Fact("Apoptosis.Severity", bool_str(severity)),
    Fact("Apoptosis.DataCorrupt", bool_str(data_corrupt)),
    Fact("Apoptosis.ActiveConnections", bool_str(active_connections)),
  ])
}

pub fn evaluate_hysteresis(
  high_volatility: Bool,
  low_volatility: Bool,
) -> RuleResult {
  evaluate("Hysteresis", hysteresis_rules(), [
    Fact("Hysteresis.HighVolatility", bool_str(high_volatility)),
    Fact("Hysteresis.LowVolatility", bool_str(low_volatility)),
  ])
}

pub fn evaluate_partition(detected: Bool, db_in_minority: Bool) -> RuleResult {
  evaluate("Partition", partition_rules(), [
    Fact("Partition.Detected", bool_str(detected)),
    Fact("Partition.DbInMinority", bool_str(db_in_minority)),
  ])
}

// =============================================================================
// Domain 14: Container Lifecycle Safety (SC-LIFECYCLE-001..004)
// =============================================================================

/// Container lifecycle GRL rules — gates destructive container operations.
pub fn lifecycle_rules() -> String {
  "
    rule \"Block Stateful Remove\" salience 100 {
      when Lifecycle.HasDataVolume == true && Lifecycle.ForceRemove == true && Lifecycle.NamedVolume == false
      then Lifecycle.Decision = \"BlockStatefulRemove\"; Lifecycle.Reason = \"SC-LIFECYCLE-001: Stateful with anonymous volume\";
    }
    rule \"Warn Anonymous Volume\" salience 90 {
      when Lifecycle.HasDataVolume == true && Lifecycle.NamedVolume == false && Lifecycle.ForceRemove == false
      then Lifecycle.Decision = \"WarnAnonymousVolume\"; Lifecycle.Reason = \"Upgrade to named volume recommended\";
    }
    rule \"Allow Stateless Remove\" salience 50 {
      when Lifecycle.HasDataVolume == false
      then Lifecycle.Decision = \"AllowStatelessRemove\"; Lifecycle.Reason = \"Stateless container safe to remove\";
    }
    rule \"Allow Named Volume Remove\" salience 40 {
      when Lifecycle.HasDataVolume == true && Lifecycle.NamedVolume == true
      then Lifecycle.Decision = \"AllowNamedVolumeRemove\"; Lifecycle.Reason = \"Named volume persists\";
    }
  "
}

/// Evaluate container lifecycle safety.
pub fn evaluate_lifecycle(
  has_data_volume: Bool,
  has_named_volume: Bool,
  force_remove: Bool,
) -> RuleResult {
  evaluate("Lifecycle", lifecycle_rules(), [
    Fact("Lifecycle.HasDataVolume", bool_str(has_data_volume)),
    Fact("Lifecycle.NamedVolume", bool_str(has_named_volume)),
    Fact("Lifecycle.ForceRemove", bool_str(force_remove)),
  ])
}

// =============================================================================
// Domain 15: ZK Context — Knowledge-Aware Decision Rules (SC-ZK-IMP-001)
// =============================================================================

/// ZK Context rules — govern how Claude should use ZK recall results.
pub fn zk_context_rules() -> String {
  "
    rule \"Deep Read Anti-Pattern\" salience 100 {
      when ZK.AntiPatternDetected == true
      then ZK.Decision = \"DeepRead\"; ZK.Reason = \"Anti-pattern in recall — read full holon\";
    }
    rule \"Follow Proven Pattern\" salience 80 {
      when ZK.ProvenPatternMatch == true && ZK.PatternAgeDays < 30
      then ZK.Decision = \"FollowPattern\"; ZK.Reason = \"Recent proven pattern — reuse\";
    }
    rule \"Verify Stale Pattern\" salience 70 {
      when ZK.ProvenPatternMatch == true && ZK.PatternAgeDays >= 30
      then ZK.Decision = \"VerifyFirst\"; ZK.Reason = \"Pattern stale — verify first\";
    }
    rule \"First Principles\" salience 10 {
      when ZK.ProvenPatternMatch == false && ZK.AntiPatternDetected == false
      then ZK.Decision = \"FirstPrinciples\"; ZK.Reason = \"No prior art\";
    }
  "
}

/// Evaluate ZK context for knowledge-aware decision making.
pub fn evaluate_zk_context(
  anti_pattern: Bool,
  proven_match: Bool,
  age_days: Int,
) -> RuleResult {
  evaluate("ZK", zk_context_rules(), [
    Fact("ZK.AntiPatternDetected", bool_str(anti_pattern)),
    Fact("ZK.ProvenPatternMatch", bool_str(proven_match)),
    Fact("ZK.PatternAgeDays", int.to_string(age_days)),
  ])
}

// =============================================================================
// Per-Layer RETE-UL UI Rules (SC-WIRE-001: fractal display governance)
// =============================================================================

/// L0 Constitutional UI rules — emergency visibility
pub fn l0_ui_rules() -> String {
  "
    rule \"Emergency Mode\" salience 100 {
      when L0.EmergencyActive == true
      then L0.Display = \"FullIllumination\"; L0.Reason = \"Emergency active\";
    }
    rule \"Guardian Pending\" salience 80 {
      when L0.PendingApprovals > 0
      then L0.Display = \"ShowApprovalPanel\"; L0.Reason = \"HITL approvals pending\";
    }
    rule \"Constitutional OK\" salience 10 {
      when L0.EmergencyActive == false && L0.PendingApprovals == 0
      then L0.Display = \"DarkCockpit\"; L0.Reason = \"All clear\";
    }
  "
}

/// L1 Telemetry UI rules — display thresholds
pub fn l1_ui_rules() -> String {
  "
    rule \"High Latency\" salience 80 {
      when L1.AvgLatencyMs > 5000
      then L1.Display = \"RedAlert\"; L1.Reason = \"Latency > 5s\";
    }
    rule \"Elevated Latency\" salience 50 {
      when L1.AvgLatencyMs > 2000 && L1.AvgLatencyMs <= 5000
      then L1.Display = \"YellowWarning\"; L1.Reason = \"Latency 2-5s\";
    }
    rule \"Normal\" salience 10 {
      when L1.AvgLatencyMs <= 2000
      then L1.Display = \"Green\"; L1.Reason = \"Latency normal\";
    }
  "
}

/// L4 System UI rules — container health coloring
pub fn l4_ui_rules() -> String {
  "
    rule \"Critical Containers\" salience 80 {
      when L4.UnhealthyCount > 3
      then L4.Display = \"RedGrid\"; L4.Reason = \"Multiple unhealthy\";
    }
    rule \"Degraded\" salience 50 {
      when L4.UnhealthyCount > 0 && L4.UnhealthyCount <= 3
      then L4.Display = \"YellowGrid\"; L4.Reason = \"Some unhealthy\";
    }
    rule \"All Healthy\" salience 10 {
      when L4.UnhealthyCount == 0
      then L4.Display = \"GreenGrid\"; L4.Reason = \"All healthy\";
    }
  "
}

/// L5 Cognitive UI rules — reasoning display
pub fn l5_ui_rules() -> String {
  "
    rule \"Reasoning Active\" salience 80 {
      when L5.ReasoningActive == true
      then L5.Display = \"ShowStream\"; L5.Reason = \"Reasoning in progress\";
    }
    rule \"OODA Slow\" salience 60 {
      when L5.OodaLatencyMs > 100
      then L5.Display = \"OodaWarning\"; L5.Reason = \"OODA > 100ms target\";
    }
    rule \"Idle\" salience 10 {
      when L5.ReasoningActive == false
      then L5.Display = \"Compact\"; L5.Reason = \"No active reasoning\";
    }
  "
}

/// L6 Ecosystem UI rules — mesh topology visibility
pub fn l6_ui_rules() -> String {
  "
    rule \"Partition Detected\" salience 100 {
      when L6.PartitionDetected == true
      then L6.Display = \"FullTopology\"; L6.Reason = \"Network partition\";
    }
    rule \"Quorum Lost\" salience 90 {
      when L6.QuorumMet == false
      then L6.Display = \"QuorumAlert\"; L6.Reason = \"Quorum not met\";
    }
    rule \"Mesh Healthy\" salience 10 {
      when L6.PartitionDetected == false && L6.QuorumMet == true
      then L6.Display = \"MiniTopology\"; L6.Reason = \"Mesh healthy\";
    }
  "
}

/// L7 Federation UI rules — attestation
pub fn l7_ui_rules() -> String {
  "
    rule \"Attestation Expired\" salience 80 {
      when L7.AllAttested == false
      then L7.Display = \"ShowAttestationWarning\"; L7.Reason = \"Peer attestation expired\";
    }
    rule \"Version Mismatch\" salience 60 {
      when L7.VersionMismatch == true
      then L7.Display = \"ShowVersionDiff\"; L7.Reason = \"Peer version mismatch\";
    }
    rule \"Federation OK\" salience 10 {
      when L7.AllAttested == true && L7.VersionMismatch == false
      then L7.Display = \"Compact\"; L7.Reason = \"Federation aligned\";
    }
  "
}

/// Evaluate UI display rule for a fractal layer
pub fn evaluate_layer_ui(layer: String, facts: List(Fact)) -> RuleResult {
  let rules = case layer {
    "L0" -> l0_ui_rules()
    "L1" -> l1_ui_rules()
    "L4" -> l4_ui_rules()
    "L5" -> l5_ui_rules()
    "L6" -> l6_ui_rules()
    "L7" -> l7_ui_rules()
    _ ->
      "rule \"Default\" salience 1 { when true then Display = \"Normal\"; Reason = \"Default\"; }"
  }
  evaluate(layer, rules, facts)
}

// ─── Hook Subsystem Domain (SC-BOOTSTRAP-005) ────────────────────────────────
// 3 data-plane rules (D-1..D-3) + 10 control-plane rules (C-1..C-10)
// Allium spec: specs/allium/hook_subsystem.allium  §rete_ul

pub fn hook_snapshot_rules() -> String {
  "rule \"D1SnapshotFresh\" salience 100 {
    when Hook.AgeMs < 5000 then
      Hook.Decision = \"EmitCached\";
      Hook.Reason = \"snapshot fresh: age < 5 s\";
  }
  rule \"D2SnapshotStaleHealthy\" salience 90 {
    when Hook.AgeMs >= 5000 && Hook.DaemonProbHigh == true then
      Hook.Decision = \"EmitCachedStale\";
      Hook.Reason = \"snapshot stale but daemon healthy: emit with staleness tag\";
  }
  rule \"D3SnapshotStaleUnhealthy\" salience 80 {
    when Hook.AgeMs >= 5000 && Hook.DaemonProbHigh == false then
      Hook.Decision = \"EmbeddedFallback\";
      Hook.Reason = \"snapshot stale and daemon unhealthy: use embedded fallback\";
  }"
}

pub fn hook_control_rules() -> String {
  "rule \"C1BayesianHealthLow\" salience 100 {
    when Hook.DaemonPosteriorLow == true then
      Hook.Decision = \"WatchdogKill\";
      Hook.Reason = \"bayesian posterior < 0.05: trigger watchdog kill\";
  }
  rule \"C2EntropyAlarm\" salience 100 {
    when Hook.EntropyHigh == true && Hook.DaemonPosteriorLow == false then
      Hook.Decision = \"P0Alarm\";
      Hook.Reason = \"shannon entropy > 0.5 on outcome window: P0 alarm\";
  }
  rule \"C3PIDError\" salience 90 {
    when Hook.PIDError == true then
      Hook.Decision = \"PIDTuneCache\";
      Hook.Reason = \"pid error signal non-zero: retune cache TTL\";
  }
  rule \"C4LyapunovDrift\" salience 90 {
    when Hook.LyapunovDrift == true then
      Hook.Decision = \"LyapunovAlert\";
      Hook.Reason = \"lyapunov metric drifting: escalate to operator\";
  }
  rule \"C5GACycle\" salience 80 {
    when Hook.GACycleElapsed == true then
      Hook.Decision = \"GeneticEvolve\";
      Hook.Reason = \"ga cycle interval elapsed: evolve genome in shadow mode\";
  }
  rule \"C6MDPRefresh\" salience 80 {
    when Hook.MDPTransitionsReady == true then
      Hook.Decision = \"MDPRefresh\";
      Hook.Reason = \"mdp transition table ready: recompute bellman values\";
  }
  rule \"C7RuleInduction\" salience 75 {
    when Hook.MutualInfoHigh == true then
      Hook.Decision = \"RuleInduction\";
      Hook.Reason = \"mutual info rule-fires/outcome high: induce new RETE rule\";
  }
  rule \"C8ABShadowReady\" salience 70 {
    when Hook.ShadowReady == true then
      Hook.Decision = \"PromoteShadow\";
      Hook.Reason = \"a/b shadow candidate ready: promote after validation\";
  }
  rule \"C9SmritiWriteFail\" salience 95 {
    when Hook.SmritiWriteFailed == true then
      Hook.Decision = \"SmritiAlert\";
      Hook.Reason = \"smriti write failed: alert and halt hook ingest\";
  }
  rule \"C10PolicyRefuse\" salience 100 {
    when Hook.PolicyRefuse == true then
      Hook.Decision = \"RefuseHook\";
      Hook.Reason = \"s5 policy: disk/cpu/daemon threshold exceeded, refuse hook\";
  }"
}

/// Evaluate data-plane snapshot routing (D-1..D-3).
/// age_ms:          milliseconds since last snapshot write
/// daemon_prob_high: true when Bayesian posterior > 0.5
pub fn evaluate_hook_snapshot(age_ms: Int, daemon_prob_high: Bool) -> RuleResult {
  evaluate("Hook", hook_snapshot_rules(), [
    Fact("Hook.AgeMs", int_to_str(age_ms)),
    Fact("Hook.DaemonProbHigh", bool_str(daemon_prob_high)),
  ])
}

/// Evaluate control-plane hook governance (C-1..C-10).
pub fn evaluate_hook_control(
  daemon_posterior_low: Bool,
  entropy_high: Bool,
  pid_error: Bool,
  lyapunov_drift: Bool,
  ga_cycle_elapsed: Bool,
  mdp_transitions_ready: Bool,
  mutual_info_high: Bool,
  shadow_ready: Bool,
  smriti_write_failed: Bool,
  policy_refuse: Bool,
) -> RuleResult {
  evaluate("Hook", hook_control_rules(), [
    Fact("Hook.DaemonPosteriorLow", bool_str(daemon_posterior_low)),
    Fact("Hook.EntropyHigh", bool_str(entropy_high)),
    Fact("Hook.PIDError", bool_str(pid_error)),
    Fact("Hook.LyapunovDrift", bool_str(lyapunov_drift)),
    Fact("Hook.GACycleElapsed", bool_str(ga_cycle_elapsed)),
    Fact("Hook.MDPTransitionsReady", bool_str(mdp_transitions_ready)),
    Fact("Hook.MutualInfoHigh", bool_str(mutual_info_high)),
    Fact("Hook.ShadowReady", bool_str(shadow_ready)),
    Fact("Hook.SmritiWriteFailed", bool_str(smriti_write_failed)),
    Fact("Hook.PolicyRefuse", bool_str(policy_refuse)),
  ])
}

@external(erlang, "erlang", "integer_to_binary")
fn int_to_str(i: Int) -> String

fn bool_str(b: Bool) -> String {
  case b {
    True -> "true"
    False -> "false"
  }
}

// =============================================================================
// SC-VALUE-GUARD-001 / SC-TRUTH-001 — Data Quality rule domain (7 rules).
//
// Codifies prevention of the bug class that produced 83 corrupt rows in the
// /planning Tasks table:  status=`Completed` (capital), priority=`SUPREME`,
// `--priority`, `high`; plus 65 SimTest fixture leaks; plus popup-blocker
// fragility on rowClick; plus 600 KB JSON payload back-pressure; plus
// page-spec alignment drift (per Phase I PageChecker).
//
// Routed via `rules/dispatcher.gleam::decision_to_action` so daemon workers
// can act on each verdict without bespoke wiring.
//
// ZK lineage: [zk-907c636b4bbf0d73] silent-metric-drift · [zk-9ac52a4e020a0ff9]
// Slurm-style priority quotas · [zk-bb4de67d97f807ac] selector-guessing /
// runtime-truth-not-static-list family.
// =============================================================================

pub fn data_quality_rules() -> String {
  "
  rule \"EnforceEnumPriority\" salience 100 {
    when Dq.PriorityInvalid == true then
      Dq.Decision = \"Reject\";
      Dq.Reason = \"SC-TRUTH-001 priority enum violation\";
  }
  rule \"EnforceEnumStatus\" salience 100 {
    when Dq.StatusInvalid == true then
      Dq.Decision = \"Normalize\";
      Dq.Reason = \"SC-TRUTH-001 status enum violation\";
  }
  rule \"BlockSpamFixture\" salience 95 {
    when Dq.IsFixtureSpam == true then
      Dq.Decision = \"Reject\";
      Dq.Reason = \"SC-MUDA-001 test fixture leaked to prod\";
  }
  rule \"PageSpecAlignmentLow\" salience 95 {
    when Dq.PageAlignmentLow == true then
      Dq.Decision = \"BlockReleaseToProd\";
      Dq.Reason = \"SC-PAGE-SPEC-003 alignment below threshold\";
  }
  rule \"P0PriorityQuota\" salience 90 {
    when Dq.P0QuotaExceeded == true then
      Dq.Decision = \"Backpressure\";
      Dq.Reason = \"Slurm-style P0 active quota exceeded (>=50)\";
  }
  rule \"WindowOpenPopupBlocker\" salience 80 {
    when Dq.UntrustedRowClick == true then
      Dq.Decision = \"FallbackInPagePanel\";
      Dq.Reason = \"popup-blocker risk on synthetic rowClick\";
  }
  rule \"PaginationBackpressure\" salience 75 {
    when Dq.PayloadOversize == true then
      Dq.Decision = \"DemandRemotePagination\";
      Dq.Reason = \"client memory + bandwidth; payload > 500 KB\";
  }"
}

/// Evaluate data-quality + page-spec governance.
/// Facts are *positive violation flags* (true = violation present) per the
/// engine convention which only supports `== true` checks (mirrors hook rules).
///   priority_invalid    — value failed validate_priority (db.rs / planning.rs)
///   status_invalid      — value failed validate_status
///   is_fixture_spam     — title matches SimTest pattern
///   page_alignment_low  — page checker Jaccard score < 0.7
///   p0_quota_exceeded   — active P0 task count >= 50 (Slurm)
///   untrusted_rowclick  — JS rowClick fired without trusted user gesture
///   payload_oversize    — /api/v1/planning JSON > 500 KB
pub fn evaluate_data_quality(
  priority_invalid: Bool,
  status_invalid: Bool,
  is_fixture_spam: Bool,
  page_alignment_low: Bool,
  p0_quota_exceeded: Bool,
  untrusted_rowclick: Bool,
  payload_oversize: Bool,
) -> RuleResult {
  evaluate("Dq", data_quality_rules(), [
    Fact("Dq.PriorityInvalid", bool_str(priority_invalid)),
    Fact("Dq.StatusInvalid", bool_str(status_invalid)),
    Fact("Dq.IsFixtureSpam", bool_str(is_fixture_spam)),
    Fact("Dq.PageAlignmentLow", bool_str(page_alignment_low)),
    Fact("Dq.P0QuotaExceeded", bool_str(p0_quota_exceeded)),
    Fact("Dq.UntrustedRowClick", bool_str(untrusted_rowclick)),
    Fact("Dq.PayloadOversize", bool_str(payload_oversize)),
  ])
}

// ============================================================================
// SECRETS VAULT — secret_freshness + vault_integrity domains (12 rules)
// SC-VAULT-001..025 + SC-VAULT-CRYPTO-001 enforcement at runtime.
// Pass-3 of task 116494073339521648.
// ============================================================================

/// GRL rules for the secret_freshness domain (7 rules).
/// Pass-18 fix: changed `== "true"` (string) → `== true` (bool literal) to
/// match the GRL parser convention used by working OODA rules.
/// Per [zk-3346fc607a1ef9e6] Stub-That-Lies anti-pattern caught in Pass-17.
fn secret_freshness_rules() -> String {
  "
  rule \"SecretFresh\" salience 100 {
    when SecretFresh.AgeBelowTtl == true
    then SecretFresh.Decision = \"Allow\"; SecretFresh.Reason = \"hot path, fresh\";
  }

  rule \"SecretSoftStale\" salience 95 {
    when SecretFresh.AgeBelowTtl == false &&
         SecretFresh.AgeBelowMaxTtl == true &&
         SecretFresh.Online == true
    then SecretFresh.Decision = \"TriggerSync\"; SecretFresh.Reason = \"soft-stale online\";
  }

  rule \"SecretSoftStaleOffline\" salience 90 {
    when SecretFresh.AgeBelowTtl == false &&
         SecretFresh.AgeBelowMaxTtl == true &&
         SecretFresh.Online == false
    then SecretFresh.Decision = \"DegradedMode\"; SecretFresh.Reason = \"soft-stale offline\";
  }

  rule \"SecretHardStale\" salience 100 {
    when SecretFresh.AgeBelowMaxTtl == false
    then SecretFresh.Decision = \"FailClosed\"; SecretFresh.Reason = \"hard-stale, P0 alarm\";
  }

  rule \"SecretRotationDue\" salience 80 {
    when SecretFresh.RotationDue == true
    then SecretFresh.Decision = \"ProposeRotation\"; SecretFresh.Reason = \"rotation cadence reached\";
  }

  rule \"SecretLeaseExpiringSoon\" salience 75 {
    when SecretFresh.LeaseExpirySeconds == \"under60\"
    then SecretFresh.Decision = \"RenewLease\"; SecretFresh.Reason = \"lease near expiry\";
  }

  rule \"SecretBootUnsealFailed\" salience 100 {
    when SecretFresh.UnsealError == true
    then SecretFresh.Decision = \"HaltAgents\"; SecretFresh.Reason = \"unseal failed, P0\";
  }
  "
}

/// GRL rules for the vault_integrity domain (5 rules).
/// Pass-18 fix: same string→bool literal change as secret_freshness rules.
fn vault_integrity_rules() -> String {
  "
  rule \"VaultSealedAtBoot\" salience 100 {
    when Vault.UptimeOver30s == true && Vault.Sealed == true
    then Vault.Decision = \"P0Alarm\"; Vault.Reason = \"sealed > 30s after start\";
  }

  rule \"VaultUnsealAttemptFailed\" salience 100 {
    when Vault.AllKekPathsFailed == true
    then Vault.Decision = \"HaltAll\"; Vault.Reason = \"3 KEK paths exhausted, P0\";
  }

  rule \"VaultStorageCorrupt\" salience 100 {
    when Vault.IntegrityCheckFailed == true
    then Vault.Decision = \"ReadOnlyFallback\"; Vault.Reason = \"integrity_check failed, fallback to GCS\";
  }

  rule \"VaultAuditGap\" salience 90 {
    when Vault.AuditGapOver5s == true
    then Vault.Decision = \"P1Investigate\"; Vault.Reason = \"audit gap detected\";
  }

  rule \"VaultTongsuoLinked\" salience 100 {
    when Vault.TongsuoInDepTree == true
    then Vault.Decision = \"BlockRelease\"; Vault.Reason = \"SC-VAULT-CRYPTO-001 violation\";
  }
  "
}

/// Evaluate secret_freshness against per-secret facts.
pub fn evaluate_secret_freshness(
  age_below_ttl: Bool,
  age_below_max_ttl: Bool,
  online: Bool,
  rotation_due: Bool,
  lease_under_60s: Bool,
  unseal_error: Bool,
) -> RuleResult {
  let lease_str = case lease_under_60s {
    True -> "under60"
    False -> "over60"
  }
  evaluate("SecretFresh", secret_freshness_rules(), [
    Fact("SecretFresh.AgeBelowTtl", bool_str(age_below_ttl)),
    Fact("SecretFresh.AgeBelowMaxTtl", bool_str(age_below_max_ttl)),
    Fact("SecretFresh.Online", bool_str(online)),
    Fact("SecretFresh.RotationDue", bool_str(rotation_due)),
    Fact("SecretFresh.LeaseExpirySeconds", lease_str),
    Fact("SecretFresh.UnsealError", bool_str(unseal_error)),
  ])
}

/// Evaluate vault_integrity. Drives SC-VAULT-CRYPTO-001 build gate.
pub fn evaluate_vault_integrity(
  uptime_over_30s: Bool,
  sealed: Bool,
  all_kek_paths_failed: Bool,
  integrity_check_failed: Bool,
  audit_gap_over_5s: Bool,
  tongsuo_in_dep_tree: Bool,
) -> RuleResult {
  evaluate("Vault", vault_integrity_rules(), [
    Fact("Vault.UptimeOver30s", bool_str(uptime_over_30s)),
    Fact("Vault.Sealed", bool_str(sealed)),
    Fact("Vault.AllKekPathsFailed", bool_str(all_kek_paths_failed)),
    Fact("Vault.IntegrityCheckFailed", bool_str(integrity_check_failed)),
    Fact("Vault.AuditGapOver5s", bool_str(audit_gap_over_5s)),
    Fact("Vault.TongsuoInDepTree", bool_str(tongsuo_in_dep_tree)),
  ])
}
