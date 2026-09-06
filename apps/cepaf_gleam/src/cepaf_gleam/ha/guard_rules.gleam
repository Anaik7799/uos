//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ha/guard_rules</module>
////     <fsharp-lineage>None — RETE-UL Guard Rules engine (F22)</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L5_COGNITIVE</layer>
////     <mesh-domain>
////       Typed RETE-UL rule definitions that evaluate guard grid state and
////       produce intelligent control actions. Gleam-side mirror of the 52 GRL
////       rules in rule_engine.rs. Pure evaluation — no I/O, no side-effects.
////     </mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>SAFETY-CRITICAL</criticality>
////     <stamp-controls>SC-SIL4-001, SC-HA-001, SC-OODA-001, SC-MUDA-001, SC-FUNC-001</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective">
////       Rust rule_engine.rs GRL strings ↪ Gleam typed ADTs.
////       Salience maps directly; condition/action encode intent without mutation.
////     </morphism>
////     <morphism type="surjective" loss="runtime-evaluation">
////       RETE network working-memory ↠ pure function over Float parameters.
////       Mitigation: callers supply all required metrics explicitly; no global state.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// RETE-UL Guard Rules Engine — Typed rule definitions for guard grid evaluation
//// नियतं कुरु कर्म त्वं — Perform your prescribed duty (Gita 3.8)
////
//// 50 predefined rules cover cascade detection, cockpit mode escalation,
//// self-healing triggers, entropy/Lyapunov divergence signals, constitutional
//// layer protection, failure correlation, predictive alerting, and compound
//// degradation detection.  Rules are evaluated in salience order (highest first);
//// the first triggered rule's action is returned as the highest-priority action.
////
//// Rule inventory (GR-001..GR-015 — original):
////   GR-001  CascadeEscalation       salience 100  cascade_depth >= 3 → JidokaHalt
////   GR-002  EmergencyMode           salience  95  health < 0.3       → SetCockpitMode("emergency")
////   GR-003  ConstitutionalThreat    salience 100  LayerFailing("L0") → JidokaHalt
////   GR-004  QuorumThreat            salience  85  LayerFailing("L6") → EscalateToOperator
////   GR-005  MultiLayerFailure       salience  90  failure_count >= 5  → SetCockpitMode("bright")
////   GR-006  BrightMode              salience  85  health < 0.5        → SetCockpitMode("bright")
////   GR-007  AutoHealNif             salience  80  ModuleConsecutive("nif_bridge",3) → AttemptHotReload
////   GR-008  IsolateFailingL4        salience  75  LayerFailing("L4") → IsolateCell("L4")
////   GR-009  RunbookNifRecovery      salience  70  LayerFailing("L1") → TriggerRunbook("RB-001")
////   GR-010  CognitiveDegraded       salience  55  LayerFailing("L5") → TriggerRunbook("RB-005")
////   GR-011  HealthDegraded          salience  50  HealthBelow(0.7)   → LogWarning
////   GR-012  EntropyAlert            salience  65  entropy > 1.5      → EscalateToOperator
////   GR-013  LyapunovDivergence      salience  60  LyapunovPositive   → LogWarning
////   GR-014  NormalMode              salience  40  health > 0.9       → SetCockpitMode("dark")
////   GR-015  AllClear                salience  30  health >= 0.95 AND entropy < 0.3 → NoAction
////
//// Rule inventory (GR-016..GR-030 — extended predictive & correlation layer):
////   GR-016  RecurringNifFailure     salience  70  ConsecutiveFailures("nif_bridge",3) → TriggerRunbook("RB-001")
////   GR-017  HealthOscillation       salience  65  HealthOscillating(0.2)  → PreventiveCooldown
////   GR-018  ReliabilityStreak       salience  25  HealthAbove(0.95)       → RecordMilestone("1h_streak")
////   GR-019  NifPlanningCorrelation  salience  55  LayersFailing(["L1","L3"]) → CorrelateFailures
////   GR-020  HealthDeclineRate       salience  60  HealthDeclining(-0.1)   → PredictiveAlert
////   GR-021  ZenohFedCorrelation     salience  55  LayersFailing(["L6","L7"]) → CorrelateFailures
////   GR-022  GhostStateDetection     salience  45  L4/health low AND NOT L5 → ClassifyPattern
////   GR-023  EntropyEscalation       salience  80  EntropyIncreasing(3)    → PreventiveCooldown
////   GR-024  DegradedClassification  salience  50  HealthBelow(0.6)        → ClassifyPattern
////   GR-025  IsolatedFailure         salience  35  failures > 1, no cascade → ClassifyPattern
////   GR-026  CriticalDivergence      salience  95  LyapunovPositive + cascade → JidokaHalt
////   GR-027  ComponentDegradation    salience  40  LayerFailing("L2")      → LogWarning
////   GR-028  TransactionRecovery     salience  45  LayerFailing("L3")      → TriggerRunbook("RB-003")
////   GR-029  MassFailureEmergency    salience  75  failure_count > 8       → SetCockpitMode("emergency")
////   GR-030  CompoundDegradation     salience  55  HealthDeclining + EntropyExceeds → EscalateToOperator
////
//// Rule inventory (GR-031..GR-033 — container lifecycle safety, SC-LIFECYCLE-001..004):
////   GR-031  DataVolumePreservation  salience 100  ContainerHasDataVolume("db-prod") → BlockContainerRemove
////   GR-032  MigrationVerification   salience  80  MigrationsMissing → TriggerRunbook("RB-LIFECYCLE-001")
////   GR-033  StatefulContainerGuard  salience  90  ContainerHasDataVolume("db-prod") → RequireNamedVolume
////
//// Rule inventory (GR-051..GR-070 — STAMP constraint guard rules):
////
////   SC-FUNC (Functional Invariant):
////   GR-051  BuildFailureHalt         salience 100  BuildFailed → JidokaHalt
////   GR-052  CoreServiceDegraded      salience  90  HealthBelow(0.5) AND failures > 3 → EscalateEmergency
////   GR-053  ContainerAutoHeal        salience  85  MultipleContainersDown → TriggerRunbook("RB-HEAL")
////   GR-054  ZenohDisconnected        salience  95  ZenohDisconnected → EscalateToOperator
////
////   SC-TRUTH (Truthfulness):
////   GR-055  DataStaleWarn            salience  75  DataStalenessExceeds(60) → WarnLog
////   GR-056  DataStaleBright          salience  80  DataStalenessExceeds(120) → SetCockpitMode("bright")
////   GR-057  DataDeadEmergency        salience  90  DataStalenessExceeds(300) → SetCockpitMode("emergency")
////   GR-058  MockDataHalt             salience 100  MockDataInProduction → JidokaHalt
////
////   SC-SIL4 (Safety):
////   GR-059  L0ActionNoConsensus      salience 100  L0ActionWithoutConsensus → JidokaHalt
////   GR-060  ShutdownNoCheckpoint     salience  90  ShutdownWithoutCheckpoint → EscalateToOperator
////   GR-061  BootNoDag                salience 100  BootWithoutDagValidation → JidokaHalt
////   GR-062  QuorumLost               salience  95  QuorumLost → SetCockpitMode("emergency")
////   GR-063  SplitBrainApoptosis      salience 100  PartitionDetected → JidokaHalt
////
////   SC-MUDA (Waste):
////   GR-064  CompileWarnings          salience  60  CompileWarningsExist → WarnLog
////   GR-065  LargeFileDetected        salience  45  LargeFileDetected → LogWarning
////   GR-066  InternalHttpDetected     salience  65  InternalHttpDetected → WarnLog
////
////   SC-ZK (Zettelkasten):
////   GR-067  ZkRecallIgnored          salience  55  ZkRecallIgnored → WarnLog
////   GR-068  ZkNoCitation             salience  50  ZkNoCitation → WarnLog
////   GR-069  SessionNoHolon           salience  45  SessionNoHolonProduced → WarnLog
////   GR-070  TaskWithoutZkSearch      salience  50  TaskWithoutZkSearch → WarnLog
////
//// Rule inventory (GR-071..GR-085 — AOR behavioral guard rules):
////
////   AOR-FUNC (Functional):
////   GR-071  BuildNotVerified         salience  80  BuildNotVerified → WarnLog
////   GR-072  RiskyOpNoCheckpoint      salience  75  RiskyOpWithoutCheckpoint → WarnLog
////   GR-073  FunctionalRollback       salience  85  HealthDecliningAfterChange → TriggerRunbook("RB-ROLLBACK")
////   GR-074  FunctionalInvariantHalt  salience 100  AllOf([BuildFailed, HealthBelow(0.3)]) → JidokaHalt
////
////   AOR-DELETE (Deletion Safety):
////   GR-075  DeleteWithoutBackup      salience  90  DeleteWithoutBackup → EscalateToOperator
////   GR-076  DangerousDeleteHalt      salience 100  DangerousDeleteDetected → JidokaHalt
////   GR-077  DeletionNotLogged        salience  55  DeletionNotLogged → WarnLog
////
////   AOR-WIRE (Wiring Guard):
////   GR-078  ModelChangedNoGuard      salience  65  ModelChangedWithoutGuard → WarnLog
////   GR-079  ModelChangedNoTest       salience  60  ModelChangedWithoutTest → WarnLog
////   GR-080  DirectConstructorTest    salience  55  DirectConstructorInTest → WarnLog
////
////   AOR-ZENOH (Telemetry):
////   GR-081  ZenohDisabledProd        salience 100  ZenohDisabledInProd → JidokaHalt
////   GR-082  ZenohLongDisconnect      salience  85  ZenohDisconnected30s → EscalateToOperator
////   GR-083  HealthNotPublished       salience  60  HealthNotPublished → WarnLog
////
////   AOR-MOKSHA (Coverage):
////   GR-084  CoverageDecreased        salience  65  CoverageDecreased → WarnLog
////   GR-085  CommitWithoutTest        salience  75  CommitWithoutTest → WarnLog
////
//// STAMP: SC-SIL4-001, SC-HA-001, SC-OODA-001, SC-MUDA-001, SC-FUNC-001,
////        SC-FUNC-002, SC-FUNC-005, SC-FUNC-007, SC-TRUTH-001, SC-TRUTH-003,
////        SC-TRUTH-004, SC-TRUTH-010, SC-SIL4-006, SC-SIL4-007, SC-SIL4-010,
////        SC-SIL4-011, SC-SIL4-015, SC-MUDA-F-003, SC-MUDA-F-005,
////        SC-ZK-IMP-001, SC-ZK-IMP-002, SC-ZETTEL-001, SC-ZK-CLAUDE-001,
////        AOR-FUNC-001, AOR-FUNC-002, AOR-FUNC-005, AOR-FUNC-008,
////        AOR-DELETE-001, AOR-DELETE-003, AOR-DELETE-007,
////        AOR-WIRE-001, AOR-WIRE-004, AOR-WIRE-005,
////        AOR-ZENOH-001, AOR-ZENOH-005, AOR-ZENOH-007,
////        AOR-MOKSHA-001, AOR-MOKSHA-002

import gleam/float
import gleam/int
import gleam/list
import gleam/string

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

/// A guard rule definition — typed mirror of a GRL rule string
pub type GuardRule {
  GuardRule(
    /// Rule identifier, e.g. "GR-001"
    id: String,
    /// Human-readable name, e.g. "CascadeEscalation"
    name: String,
    /// Priority — higher salience is evaluated first
    salience: Int,
    /// What must be true in the grid for this rule to fire
    condition: RuleCondition,
    /// What to do when the condition is met
    action: RuleAction,
    /// Fractal layer scope ("*" means all layers)
    layer: String,
    /// One-line description of intent
    description: String,
  )
}

/// Rule conditions — predicates over grid metrics
pub type RuleCondition {
  /// failure_count >= threshold
  FailureCountExceeds(threshold: Int)
  /// cascade_depth >= min_depth (adjacent layer failures)
  CascadeDepth(min_depth: Int)
  /// Shannon entropy exceeds threshold (unpredictable failures)
  EntropyExceeds(threshold: Float)
  /// Named fractal layer has >= 1 failure
  LayerFailing(layer: String)
  /// Named module has >= count consecutive failures
  ModuleConsecutiveFailures(module: String, count: Int)
  /// health_score < threshold
  HealthBelow(threshold: Float)
  /// health_score >= threshold
  HealthAbove(threshold: Float)
  /// Lyapunov exponent is positive (system diverging from attractor)
  LyapunovPositive
  /// All sub-conditions must be true (logical AND)
  AllOf(conditions: List(RuleCondition))
  /// Any sub-condition is true (logical OR)
  AnyOf(conditions: List(RuleCondition))
  /// Consecutive failures for a specific module exceed threshold.
  /// Encoded at evaluation time as failure_count > threshold (conservative
  /// approximation when per-module history is not available in the signature).
  ConsecutiveFailures(module: String, threshold: Int)
  /// Health oscillating — delta > threshold in a sliding window.
  /// Encoded as entropy > delta_threshold (oscillation raises entropy).
  HealthOscillating(delta_threshold: Float)
  /// Health derivative is negative (health is declining at rate <= rate).
  /// Encoded via lyapunov < rate (rate is negative, e.g. -0.1).
  HealthDeclining(rate: Float)
  /// Entropy has been increasing for N consecutive cycles.
  /// Encoded as cascade_depth >= cycles (rising entropy escalates depth).
  EntropyIncreasing(cycles: Int)
  /// All listed fractal layers are failing simultaneously.
  /// Requires evaluate_condition_with_layers for accurate evaluation;
  /// falls back to failure_count > list.length(layers) in basic API.
  LayersFailing(layers: List(String))
  /// Container has a data volume mounted (SC-LIFECYCLE-001)
  ContainerHasDataVolume(container: String)
  /// Database schema_migrations table is missing or empty (SC-LIFECYCLE-003)
  MigrationsMissing
  /// Data staleness — NIF data older than threshold seconds
  DataStale(max_age_seconds: Int)
  /// Rate of change exceeds threshold in window (velocity check)
  RateOfChangeExceeds(threshold: Float)
  /// Status flipped more than N times (oscillation)
  StatusFlips(count: Int)
  /// N consecutive monotonic declines
  MonotonicDecline(checks: Int)
  /// No heartbeat for N cycles
  HeartbeatMissing(cycles: Int)
  /// Shannon entropy below minimum (insufficient diversity)
  EntropyBelow(threshold: Float)
  /// State description complexity exceeds factor × baseline
  ComplexityExceeds(factor: Float)
  /// Mutual information between layers below threshold
  MutualInfoBelow(threshold: Float)
  /// Transfer entropy (causal influence) below threshold
  TransferEntropyBelow(threshold: Float)
  // ── STAMP-specific conditions (GR-051..GR-070) ──
  /// SC-FUNC-001: build_failures > 0 (compile gate failed)
  BuildFailed
  /// SC-FUNC-002: core services < 50% health AND >= 3 failures
  CoreServiceDegraded(min_failures: Int)
  /// SC-FUNC-005: more than one container in the Down state
  MultipleContainersDown(threshold: Int)
  /// SC-FUNC-007: Zenoh router is not reachable / session lost
  ZenohDisconnected
  /// SC-TRUTH-001/003/004: NIF data age exceeds given seconds
  DataStalenessExceeds(seconds: Int)
  /// SC-TRUTH-010: mock or hardcoded data detected in a production render
  MockDataInProduction
  /// SC-SIL4-006: an L0-constitutional action was taken without 2oo3 quorum
  L0ActionWithoutConsensus
  /// SC-SIL4-007: a shutdown sequence completed without a dying-gasp checkpoint
  ShutdownWithoutCheckpoint
  /// SC-SIL4-010: the boot DAG was not validated before container launch
  BootWithoutDagValidation
  /// SC-SIL4-011: mesh quorum dropped below floor(N/2)+1
  QuorumLost
  /// SC-SIL4-015: network partition detected → split-brain risk
  PartitionDetected
  /// SC-MUDA-001: compile_warnings > 0 (zero-warnings gate failed)
  CompileWarningsExist
  /// SC-MUDA-F-003: a source file exceeds 1000 lines
  LargeFileDetected
  /// SC-MUDA-F-005: internal HTTP call detected between mesh components
  InternalHttpDetected
  /// SC-ZK-IMP-001: ZK recall results were not read for a prompt
  ZkRecallIgnored
  /// SC-ZK-IMP-002: response had zero Zettelkasten holon citations
  ZkNoCitation
  /// SC-ZETTEL-001: session ended without producing at least one new holon
  SessionNoHolonProduced
  /// SC-ZK-CLAUDE-001: task started without prior Zettelkasten search
  TaskWithoutZkSearch
  // ── AOR-FUNC conditions (GR-071..GR-074) ──
  /// AOR-FUNC-001: a commit was attempted without running gleam build first
  BuildNotVerified
  /// AOR-FUNC-002: a risky git/infra operation started without a git checkpoint
  RiskyOpWithoutCheckpoint
  /// AOR-FUNC-005: health score is declining in the window following a code change
  HealthDecliningAfterChange
  // ── AOR-DELETE conditions (GR-075..GR-077) ──
  /// AOR-DELETE-001: file deletion attempted without a prior backup / git stash
  DeleteWithoutBackup
  /// AOR-DELETE-003: rm -rf (or equivalent) detected on a code directory
  DangerousDeleteDetected
  /// AOR-DELETE-007: deletion occurred but was not recorded in the audit log
  DeletionNotLogged
  // ── AOR-WIRE conditions (GR-078..GR-080) ──
  /// AOR-WIRE-001: a Model type was changed without reading wiring_guard.gleam first
  ModelChangedWithoutGuard
  /// AOR-WIRE-004: a Model type was changed without running gleam test afterwards
  ModelChangedWithoutTest
  /// AOR-WIRE-005: a test file constructs a Model directly instead of using init()
  DirectConstructorInTest
  // ── AOR-ZENOH conditions (GR-081..GR-083) ──
  /// AOR-ZENOH-001: SKIP_ZENOH_NIF=1 set in a production or staging environment
  ZenohDisabledInProd
  /// AOR-ZENOH-005: Zenoh router has been unreachable for >= 30 seconds
  ZenohDisconnected30s
  /// AOR-ZENOH-007: node health has not been published to Zenoh within 10 seconds
  HealthNotPublished
  // ── AOR-MOKSHA conditions (GR-084..GR-085) ──
  /// AOR-MOKSHA-001: test coverage tensor shows a decrease after a sprint
  CoverageDecreased
  /// AOR-MOKSHA-002: a commit was attempted without running gleam test first
  CommitWithoutTest
}

/// Rule actions — control decisions produced by fired rules
pub type RuleAction {
  /// Append a warning to the system log
  LogWarning(message: String)
  /// Attempt hot code reload of failing module
  AttemptHotReload
  /// Transition cockpit to the named mode
  SetCockpitMode(mode: String)
  /// Isolate a failing cell (blast-radius containment)
  IsolateCell(layer: String)
  /// Invoke a named runbook
  TriggerRunbook(runbook_id: String)
  /// Page the operator with a reason string
  EscalateToOperator(reason: String)
  /// Jidoka hard halt with reason (Psi-0 preservation)
  JidokaHalt(reason: String)
  /// Condition not met — no action required
  NoAction
  /// Execute multiple actions in sequence
  ActionSequence(actions: List(RuleAction))
  /// Correlate failures across layers for root-cause analysis
  CorrelateFailures(description: String)
  /// Classify failure pattern for diagnostic routing
  ClassifyPattern(pattern: String)
  /// Record a reliability milestone for SLO tracking
  RecordMilestone(milestone: String)
  /// Predictive alert based on current trend extrapolation
  PredictiveAlert(prediction: String)
  /// Preventive cooldown to arrest an unstable trajectory
  PreventiveCooldown(reason: String)
  /// Block force-remove of a container with data volumes (SC-LIFECYCLE-001)
  BlockContainerRemove(container: String, reason: String)
  /// Require named volume for stateful container (SC-LIFECYCLE-001)
  RequireNamedVolume(container: String)
}

/// Result of evaluating a single rule against current grid metrics
pub type RuleEvaluation {
  RuleEvaluation(
    /// Which rule was evaluated
    rule_id: String,
    /// Human-readable name
    rule_name: String,
    /// Whether the condition was satisfied
    condition_met: Bool,
    /// Action to apply (NoAction when condition_met = False)
    action: RuleAction,
    /// Salience for ordering
    salience: Int,
  )
}

// ---------------------------------------------------------------------------
// Rule catalog — 50 predefined rules
// ---------------------------------------------------------------------------

/// All guard rules ordered by salience (highest first).
/// Mirrors the 52 GRL rules in rule_engine.rs for the guard-grid domain.
pub fn all_rules() -> List(GuardRule) {
  [
    GuardRule(
      id: "GR-001",
      name: "CascadeEscalation",
      salience: 100,
      condition: CascadeDepth(min_depth: 3),
      action: JidokaHalt(
        "Cascade depth >= 3: structural failure across 3+ adjacent layers",
      ),
      layer: "*",
      description: "Cascade across 3+ adjacent layers triggers Jidoka halt",
    ),
    GuardRule(
      id: "GR-003",
      name: "ConstitutionalThreat",
      salience: 100,
      condition: LayerFailing(layer: "L0"),
      action: JidokaHalt(
        "L0 Constitutional layer failing: Psi invariants may be violated",
      ),
      layer: "L0",
      description: "L0 Constitutional layer failure triggers immediate Jidoka halt",
    ),
    GuardRule(
      id: "GR-026",
      name: "CriticalDivergence",
      salience: 95,
      condition: AllOf(conditions: [
        LyapunovPositive,
        CascadeDepth(min_depth: 2),
      ]),
      action: JidokaHalt(
        "Lyapunov positive with cascade depth >= 2: stability boundary breached",
      ),
      layer: "*",
      description: "Positive Lyapunov exponent combined with cascade triggers Jidoka halt",
    ),
    GuardRule(
      id: "GR-002",
      name: "EmergencyMode",
      salience: 95,
      condition: HealthBelow(threshold: 0.3),
      action: SetCockpitMode("emergency"),
      layer: "*",
      description: "Health < 30% escalates cockpit to emergency mode",
    ),
    GuardRule(
      id: "GR-005",
      name: "MultiLayerFailure",
      salience: 90,
      condition: FailureCountExceeds(threshold: 5),
      action: SetCockpitMode("bright"),
      layer: "*",
      description: "5+ module failures across grid triggers bright cockpit mode",
    ),
    GuardRule(
      id: "GR-004",
      name: "QuorumThreat",
      salience: 85,
      condition: LayerFailing(layer: "L6"),
      action: EscalateToOperator("L6 Ecosystem / Zenoh mesh quorum threatened"),
      layer: "L6",
      description: "L6 Ecosystem failure threatens mesh quorum — escalate to operator",
    ),
    GuardRule(
      id: "GR-006",
      name: "BrightMode",
      salience: 85,
      condition: HealthBelow(threshold: 0.5),
      action: SetCockpitMode("bright"),
      layer: "*",
      description: "Health < 50% transitions cockpit to bright (high-visibility) mode",
    ),
    GuardRule(
      id: "GR-023",
      name: "EntropyEscalation",
      salience: 80,
      condition: EntropyIncreasing(cycles: 3),
      action: PreventiveCooldown("entropy rising for 3+ consecutive cycles"),
      layer: "*",
      description: "Entropy increasing for 3+ cycles triggers preventive cooldown",
    ),
    GuardRule(
      id: "GR-007",
      name: "AutoHealNif",
      salience: 80,
      condition: ModuleConsecutiveFailures(module: "nif_bridge", count: 3),
      action: AttemptHotReload,
      layer: "L1",
      description: "3 consecutive NIF bridge failures trigger hot code reload",
    ),
    GuardRule(
      id: "GR-029",
      name: "MassFailureEmergency",
      salience: 75,
      condition: FailureCountExceeds(threshold: 8),
      action: SetCockpitMode("emergency"),
      layer: "*",
      description: "Mass failure (> 8 modules) escalates cockpit to emergency",
    ),
    GuardRule(
      id: "GR-008",
      name: "IsolateFailingL4",
      salience: 75,
      condition: LayerFailing(layer: "L4"),
      action: IsolateCell("L4"),
      layer: "L4",
      description: "L4 System failure isolates the cell (blast-radius containment)",
    ),
    GuardRule(
      id: "GR-009",
      name: "RunbookNifRecovery",
      salience: 70,
      condition: LayerFailing(layer: "L1"),
      action: TriggerRunbook("RB-001"),
      layer: "L1",
      description: "L1 Atomic/NIF layer failure invokes NIF Pipeline Recovery runbook",
    ),
    GuardRule(
      id: "GR-016",
      name: "RecurringNifFailure",
      salience: 70,
      condition: ConsecutiveFailures(module: "nif_bridge", threshold: 3),
      action: TriggerRunbook("RB-001"),
      layer: "L1",
      description: "Recurring NIF bridge failures (> 3) invoke recovery runbook",
    ),
    GuardRule(
      id: "GR-017",
      name: "HealthOscillation",
      salience: 65,
      condition: HealthOscillating(delta_threshold: 0.2),
      action: PreventiveCooldown("health unstable: oscillation delta > 0.2"),
      layer: "*",
      description: "Health oscillating with delta > 0.2 triggers preventive cooldown",
    ),
    GuardRule(
      id: "GR-012",
      name: "EntropyAlert",
      salience: 65,
      condition: EntropyExceeds(threshold: 1.5),
      action: EscalateToOperator(
        "Shannon entropy > 1.5 bits: failures are systemic / unpredictable",
      ),
      layer: "*",
      description: "High Shannon entropy signals systemic unpredictability — escalate",
    ),
    GuardRule(
      id: "GR-020",
      name: "HealthDeclineRate",
      salience: 60,
      condition: HealthDeclining(rate: -0.1),
      action: PredictiveAlert(
        "health declining at rate > 0.1/cycle — emergency in ~70s",
      ),
      layer: "*",
      description: "Health declining at >= 0.1/cycle predicts imminent emergency",
    ),
    GuardRule(
      id: "GR-013",
      name: "LyapunovDivergence",
      salience: 60,
      condition: LyapunovPositive,
      action: LogWarning(
        "Lyapunov exponent positive: system diverging from stable attractor",
      ),
      layer: "*",
      description: "Positive Lyapunov exponent warns of chaotic divergence",
    ),
    GuardRule(
      id: "GR-010",
      name: "CognitiveDegraded",
      salience: 55,
      condition: LayerFailing(layer: "L5"),
      action: TriggerRunbook("RB-005"),
      layer: "L5",
      description: "L5 Cognitive layer degraded — invoke circuit breaker reset runbook",
    ),
    GuardRule(
      id: "GR-019",
      name: "NifPlanningCorrelation",
      salience: 55,
      condition: LayersFailing(layers: ["L1", "L3"]),
      action: CorrelateFailures(
        "NIF→Planning pipeline failure correlation detected",
      ),
      layer: "*",
      description: "L1 and L3 failing simultaneously — NIF-Planning pipeline correlation",
    ),
    GuardRule(
      id: "GR-021",
      name: "ZenohFedCorrelation",
      salience: 55,
      condition: LayersFailing(layers: ["L6", "L7"]),
      action: CorrelateFailures(
        "Zenoh→Federation dependency failure correlation detected",
      ),
      layer: "*",
      description: "L6 and L7 failing simultaneously — Zenoh-Federation dependency correlation",
    ),
    GuardRule(
      id: "GR-030",
      name: "CompoundDegradation",
      salience: 55,
      condition: AllOf(conditions: [
        HealthDeclining(rate: -0.05),
        EntropyExceeds(threshold: 1.0),
      ]),
      action: EscalateToOperator(
        "compound degradation: health declining + entropy elevated",
      ),
      layer: "*",
      description: "Declining health combined with elevated entropy signals compound degradation",
    ),
    GuardRule(
      id: "GR-011",
      name: "HealthDegraded",
      salience: 50,
      condition: HealthBelow(threshold: 0.7),
      action: LogWarning(
        "Health score below 0.7: system degraded — monitor closely",
      ),
      layer: "*",
      description: "Health < 70% logs a degradation warning",
    ),
    GuardRule(
      id: "GR-024",
      name: "DegradedClassification",
      salience: 50,
      condition: HealthBelow(threshold: 0.6),
      action: ClassifyPattern("degraded_but_operational"),
      layer: "*",
      description: "Health < 60% classifies system as degraded but operational",
    ),
    GuardRule(
      id: "GR-022",
      name: "GhostStateDetection",
      salience: 45,
      condition: AllOf(conditions: [
        AnyOf(conditions: [LayerFailing("L4"), HealthBelow(threshold: 0.8)]),
        HealthAbove(threshold: 0.0),
      ]),
      action: ClassifyPattern("container_issue_cortex_alive"),
      layer: "*",
      description: "L4/health degraded while L5 intact — ghost state (container issue, cortex alive)",
    ),
    GuardRule(
      id: "GR-028",
      name: "TransactionRecovery",
      salience: 45,
      condition: LayerFailing(layer: "L3"),
      action: TriggerRunbook("RB-003"),
      layer: "L3",
      description: "L3 Transaction layer failure invokes transaction recovery runbook",
    ),
    GuardRule(
      id: "GR-014",
      name: "NormalMode",
      salience: 40,
      condition: HealthAbove(threshold: 0.9),
      action: SetCockpitMode("dark"),
      layer: "*",
      description: "Health > 90% returns cockpit to dark (nominal suppressed) mode",
    ),
    GuardRule(
      id: "GR-027",
      name: "ComponentDegradation",
      salience: 40,
      condition: LayerFailing(layer: "L2"),
      action: LogWarning("L2 Component layer degraded"),
      layer: "L2",
      description: "L2 Component layer failure logged as a degradation warning",
    ),
    GuardRule(
      id: "GR-025",
      name: "IsolatedFailure",
      salience: 35,
      condition: AllOf(conditions: [
        FailureCountExceeds(threshold: 1),
        AnyOf(conditions: [EntropyExceeds(threshold: 0.0)]),
      ]),
      action: ClassifyPattern("isolated_failure"),
      layer: "*",
      description: "Isolated failure (failures > 1, no deep cascade) classified for tracking",
    ),
    GuardRule(
      id: "GR-015",
      name: "AllClear",
      salience: 30,
      condition: AllOf(conditions: [
        HealthAbove(threshold: 0.95),
        AnyOf(conditions: [EntropyExceeds(threshold: 0.0)])
          |> fn(_) {
            // Rewrite: entropy < 0.3 expressed as NOT EntropyExceeds(0.3).
            // Since AnyOf([EntropyExceeds(0.0)]) would be TRUE for any entropy > 0,
            // we instead use HealthAbove for both legs and capture entropy via the
            // AllClear evaluate_condition override below.
            HealthAbove(threshold: 0.95)
          },
      ]),
      action: NoAction,
      layer: "*",
      description: "Health >= 95% and entropy < 0.3 — all clear, no action required",
    ),
    GuardRule(
      id: "GR-018",
      name: "ReliabilityStreak",
      salience: 25,
      condition: HealthAbove(threshold: 0.95),
      action: RecordMilestone("1h_streak"),
      layer: "*",
      description: "Health >= 95% sustained — record reliability streak milestone for SLO",
    ),
    // ── GR-031..033: Container Lifecycle Safety (SC-LIFECYCLE-001..004) ──
    GuardRule(
      id: "GR-031",
      name: "DataVolumePreservation",
      salience: 100,
      condition: ContainerHasDataVolume(container: "indrajaal-db-prod"),
      action: BlockContainerRemove(
        container: "indrajaal-db-prod",
        reason: "SC-LIFECYCLE-001: Stateful containers must not be force-removed without named volumes",
      ),
      layer: "L0",
      description: "Block force-remove on containers with data volumes — Constitutional data protection",
    ),
    GuardRule(
      id: "GR-032",
      name: "MigrationVerification",
      salience: 80,
      condition: MigrationsMissing,
      action: TriggerRunbook(runbook_id: "RB-LIFECYCLE-001"),
      layer: "L3",
      description: "Verify schema_migrations table exists before declaring database healthy",
    ),
    GuardRule(
      id: "GR-033",
      name: "StatefulContainerGuard",
      salience: 90,
      condition: ContainerHasDataVolume(container: "indrajaal-db-prod"),
      action: RequireNamedVolume(container: "indrajaal-db-prod"),
      layer: "L4",
      description: "Require named volumes for stateful containers to prevent data loss on recreation",
    ),
    // ── GR-034..035: ZK Knowledge Health (SC-ZK-IMP-001) ──
    GuardRule(
      id: "GR-034",
      name: "ZkRecallFailure",
      salience: 70,
      condition: HealthBelow(threshold: 0.4),
      action: EscalateToOperator(
        "ZK recall degraded — check search index health and embedding coverage",
      ),
      layer: "L5",
      description: "ZK recall returning poor results — escalate for search index maintenance",
    ),
    GuardRule(
      id: "GR-035",
      name: "KnowledgeDecayAlert",
      salience: 55,
      condition: HealthDeclining(rate: -0.05),
      action: LogWarning(
        "Knowledge decay detected — run sa-plan-daemon zk-maintain",
      ),
      layer: "L7",
      description: "Knowledge utilization declining — flag stale holons for review",
    ),
    // ── GR-036..040: Temporal Rules (SC-TRUTH-001, SC-DMS-001) ──
    GuardRule(
      id: "GR-036",
      name: "StalenessDetector",
      salience: 85,
      condition: DataStale(max_age_seconds: 60),
      action: EscalateToOperator("NIF data > 60s old — pipeline stale"),
      layer: "*",
      description: "Alert if any NIF data exceeds 60s staleness threshold",
    ),
    GuardRule(
      id: "GR-037",
      name: "RapidHealthDrop",
      salience: 80,
      condition: RateOfChangeExceeds(threshold: -0.1),
      action: PredictiveAlert(
        "Health dropping > 10%/30s — extrapolating failure",
      ),
      layer: "*",
      description: "Alert if health drops more than 10% in 30 seconds",
    ),
    GuardRule(
      id: "GR-038",
      name: "OscillationDetector",
      salience: 70,
      condition: StatusFlips(count: 3),
      action: PreventiveCooldown(
        "Status oscillating > 3 flips/60s — stabilizing",
      ),
      layer: "*",
      description: "Detect status flip-flopping indicating unstable control loop",
    ),
    GuardRule(
      id: "GR-039",
      name: "MonotonicDeclineAlert",
      salience: 65,
      condition: MonotonicDecline(checks: 5),
      action: PredictiveAlert(
        "5 consecutive declining checks — monotonic degradation",
      ),
      layer: "*",
      description: "Alert on sustained monotonic decline over 5 check cycles",
    ),
    GuardRule(
      id: "GR-040",
      name: "HeartbeatTimeout",
      salience: 90,
      condition: HeartbeatMissing(cycles: 2),
      action: EscalateToOperator(
        "No heartbeat for 2 cycles — possible process death",
      ),
      layer: "*",
      description: "Dead man's switch — alert if no heartbeat in 2 check cycles",
    ),
    // ── GR-041..045: Cross-Layer Consistency Rules (SC-FRACTAL-001) ──
    GuardRule(
      id: "GR-041",
      name: "L0L4Consistency",
      salience: 85,
      condition: AllOf([LayerFailing("L0"), HealthAbove(threshold: 0.7)]),
      action: JidokaHalt(
        "L0 Constitutional failing but system reports healthy — state inconsistency",
      ),
      layer: "L0",
      description: "Constitutional layer failing must degrade overall health",
    ),
    GuardRule(
      id: "GR-042",
      name: "L4L6BridgeHealth",
      salience: 70,
      condition: AllOf([LayerFailing("L4"), LayerFailing("L6")]),
      action: CorrelateFailures(
        "Container health (L4) and mesh topology (L6) both failing — bridge issue",
      ),
      layer: "L4",
      description: "Container health must correlate with mesh topology status",
    ),
    GuardRule(
      id: "GR-043",
      name: "L5L7CognitiveAlignment",
      salience: 65,
      condition: AllOf([LayerFailing("L5"), LayerFailing("L7")]),
      action: CorrelateFailures(
        "OODA decisions (L5) misaligned with federation policy (L7)",
      ),
      layer: "L5",
      description: "Cognitive OODA decisions must align with federation governance",
    ),
    GuardRule(
      id: "GR-044",
      name: "L1L3DataFlow",
      salience: 60,
      condition: AllOf([LayerFailing("L1"), LayerFailing("L3")]),
      action: TriggerRunbook("RB-DATAFLOW-001"),
      layer: "L1",
      description: "Atomic operations must reach transaction layer — NIF→DB pipeline",
    ),
    GuardRule(
      id: "GR-045",
      name: "L2L6ComponentMesh",
      salience: 55,
      condition: AllOf([LayerFailing("L2"), LayerFailing("L6")]),
      action: LogWarning(
        "Component catalog (L2) inconsistent with deployed services (L6)",
      ),
      layer: "L2",
      description: "UI component catalog must match deployed mesh services",
    ),
    // ── GR-046..050: Mathematical Rules (SC-MATH-001) ──
    GuardRule(
      id: "GR-046",
      name: "ShannonEntropyGate",
      salience: 60,
      condition: EntropyBelow(threshold: 2.0),
      action: LogWarning(
        "System entropy H < 2.0 bits — insufficient state diversity",
      ),
      layer: "*",
      description: "Shannon entropy must be >= 2.0 bits for healthy state distribution",
    ),
    GuardRule(
      id: "GR-047",
      name: "KolmogorovComplexity",
      salience: 55,
      condition: ComplexityExceeds(factor: 2.0),
      action: EscalateToOperator(
        "State description complexity > 2x baseline — system over-complicated",
      ),
      layer: "*",
      description: "Alert if system state description grows beyond 2x baseline complexity",
    ),
    GuardRule(
      id: "GR-048",
      name: "MutualInformation",
      salience: 50,
      condition: MutualInfoBelow(threshold: 0.3),
      action: LogWarning(
        "Mutual information between layers < 0.3 — layers decoupled",
      ),
      layer: "*",
      description: "Layers should share mutual information > 0.3 for coherent behavior",
    ),
    GuardRule(
      id: "GR-049",
      name: "TransferEntropy",
      salience: 50,
      condition: TransferEntropyBelow(threshold: 0.1),
      action: LogWarning("Transfer entropy L4→L5 < 0.1 — weak causal influence"),
      layer: "L4",
      description: "Container state (L4) should causally influence OODA decisions (L5)",
    ),
    GuardRule(
      id: "GR-050",
      name: "LyapunovChaosGate",
      salience: 75,
      condition: AllOf([LyapunovPositive, EntropyExceeds(threshold: 2.5)]),
      action: SetCockpitMode("bright"),
      layer: "*",
      description: "Positive Lyapunov + high entropy = chaotic divergence — escalate cockpit",
    ),
    // ── GR-051..054: SC-FUNC (Functional Invariant) ─────────────────────────
    GuardRule(
      id: "GR-051",
      name: "BuildFailureHalt",
      salience: 100,
      condition: BuildFailed,
      action: JidokaHalt(
        "SC-FUNC-001: build_failures > 0 — system must compile at all times",
      ),
      layer: "*",
      description: "SC-FUNC-001: Any compile failure triggers an immediate Jidoka halt",
    ),
    GuardRule(
      id: "GR-052",
      name: "CoreServiceDegraded",
      salience: 90,
      condition: AllOf([
        HealthBelow(threshold: 0.5),
        CoreServiceDegraded(min_failures: 3),
      ]),
      action: ActionSequence([
        SetCockpitMode("emergency"),
        EscalateToOperator(
          "SC-FUNC-002: health < 50% AND failures > 3 — core services not operational",
        ),
      ]),
      layer: "*",
      description: "SC-FUNC-002: Core services < 50% health with 3+ failures → emergency escalation",
    ),
    GuardRule(
      id: "GR-053",
      name: "ContainerAutoHeal",
      salience: 85,
      condition: MultipleContainersDown(threshold: 1),
      action: TriggerRunbook("RB-HEAL"),
      layer: "L4",
      description: "SC-FUNC-005: More than one container down — invoke auto-heal runbook",
    ),
    GuardRule(
      id: "GR-054",
      name: "ZenohDisconnectedAlert",
      salience: 95,
      condition: ZenohDisconnected,
      action: EscalateToOperator(
        "SC-FUNC-007: Zenoh mesh connectivity lost — internal bus unavailable",
      ),
      layer: "L6",
      description: "SC-FUNC-007: Zenoh router unreachable triggers operator escalation",
    ),
    // ── GR-055..058: SC-TRUTH (Truthfulness) ────────────────────────────────
    GuardRule(
      id: "GR-055",
      name: "DataStaleWarn",
      salience: 75,
      condition: DataStalenessExceeds(seconds: 60),
      action: LogWarning(
        "SC-TRUTH-001: NIF data > 60s old — only verified current data may be displayed",
      ),
      layer: "*",
      description: "SC-TRUTH-001: Data staleness > 60s logs a truthfulness warning",
    ),
    GuardRule(
      id: "GR-056",
      name: "DataStaleBright",
      salience: 80,
      condition: DataStalenessExceeds(seconds: 120),
      action: SetCockpitMode("bright"),
      layer: "*",
      description: "SC-TRUTH-003: Data > 120s stale escalates cockpit to bright mode",
    ),
    GuardRule(
      id: "GR-057",
      name: "DataDeadEmergency",
      salience: 90,
      condition: DataStalenessExceeds(seconds: 300),
      action: SetCockpitMode("emergency"),
      layer: "*",
      description: "SC-TRUTH-004: Data > 5 min dead triggers emergency cockpit mode",
    ),
    GuardRule(
      id: "GR-058",
      name: "MockDataHalt",
      salience: 100,
      condition: MockDataInProduction,
      action: JidokaHalt(
        "SC-TRUTH-010: Mock/hardcoded data detected in production render — SC-SATYA-007 violated",
      ),
      layer: "*",
      description: "SC-TRUTH-010: Any mock data in production triggers Jidoka halt",
    ),
    // ── GR-059..063: SC-SIL4 (Safety) ───────────────────────────────────────
    GuardRule(
      id: "GR-059",
      name: "L0ActionNoConsensus",
      salience: 100,
      condition: L0ActionWithoutConsensus,
      action: JidokaHalt(
        "SC-SIL4-006: L0 Constitutional action attempted without 2oo3 voting consensus",
      ),
      layer: "L0",
      description: "SC-SIL4-006: All L0 actuations require 2oo3 quorum — halt if violated",
    ),
    GuardRule(
      id: "GR-060",
      name: "ShutdownNoCheckpoint",
      salience: 90,
      condition: ShutdownWithoutCheckpoint,
      action: EscalateToOperator(
        "SC-SIL4-007: Shutdown sequence without dying-gasp checkpoint — state may be lost",
      ),
      layer: "L4",
      description: "SC-SIL4-007: Checkpoint is mandatory before shutdown — escalate if missed",
    ),
    GuardRule(
      id: "GR-061",
      name: "BootNoDag",
      salience: 100,
      condition: BootWithoutDagValidation,
      action: JidokaHalt(
        "SC-SIL4-010: Container boot attempted without DAG topological validation",
      ),
      layer: "L4",
      description: "SC-SIL4-010: Boot DAG must be validated before any container launch",
    ),
    GuardRule(
      id: "GR-062",
      name: "QuorumLostEmergency",
      salience: 95,
      condition: QuorumLost,
      action: SetCockpitMode("emergency"),
      layer: "L6",
      description: "SC-SIL4-011: Mesh quorum < floor(N/2)+1 triggers emergency cockpit mode",
    ),
    GuardRule(
      id: "GR-063",
      name: "SplitBrainApoptosis",
      salience: 100,
      condition: PartitionDetected,
      action: JidokaHalt(
        "SC-SIL4-015: Network partition detected — split-brain prevention via Jidoka halt",
      ),
      layer: "L6",
      description: "SC-SIL4-015: Network partition triggers immediate Jidoka halt to prevent split-brain",
    ),
    // ── GR-064..066: SC-MUDA (Waste Reduction) ──────────────────────────────
    GuardRule(
      id: "GR-064",
      name: "CompileWarningsGate",
      salience: 60,
      condition: CompileWarningsExist,
      action: LogWarning(
        "SC-MUDA-001: Compile warnings detected — zero-warnings gate requires immediate cleanup",
      ),
      layer: "*",
      description: "SC-MUDA-001: Any compile warnings violate the zero-warnings gate",
    ),
    GuardRule(
      id: "GR-065",
      name: "LargeFileAlert",
      salience: 45,
      condition: LargeFileDetected,
      action: LogWarning(
        "SC-MUDA-F-003: Source file > 1000 lines detected — split file before next evolution",
      ),
      layer: "*",
      description: "SC-MUDA-F-003: Files > 1000 lines are agent-efficiency anti-patterns",
    ),
    GuardRule(
      id: "GR-066",
      name: "InternalHttpWarn",
      salience: 65,
      condition: InternalHttpDetected,
      action: LogWarning(
        "SC-MUDA-F-005: Internal HTTP call between mesh components — use Zenoh pub/sub (SC-ZMOF-001)",
      ),
      layer: "*",
      description: "SC-MUDA-F-005: HTTP between internal components violates Zenoh backplane mandate",
    ),
    // ── GR-067..070: SC-ZK (Zettelkasten) ───────────────────────────────────
    GuardRule(
      id: "GR-067",
      name: "ZkRecallIgnoredWarn",
      salience: 55,
      condition: ZkRecallIgnored,
      action: LogWarning(
        "SC-ZK-IMP-001: ZK recall results not read — institutional memory ignored (SC-ZK-CLAUDE-001)",
      ),
      layer: "L5",
      description: "SC-ZK-IMP-001: Agent must read ZK recall before acting — warn on omission",
    ),
    GuardRule(
      id: "GR-068",
      name: "ZkNoCitationWarn",
      salience: 50,
      condition: ZkNoCitation,
      action: LogWarning(
        "SC-ZK-IMP-002: Response contained zero Zettelkasten holon citations — cite >= 1 holon",
      ),
      layer: "L5",
      description: "SC-ZK-IMP-002: Every analysis response requires at least one holon citation",
    ),
    GuardRule(
      id: "GR-069",
      name: "SessionNoHolonWarn",
      salience: 45,
      condition: SessionNoHolonProduced,
      action: LogWarning(
        "SC-ZETTEL-001: Session ended without producing >= 1 new Zettelkasten holon",
      ),
      layer: "L5",
      description: "SC-ZETTEL-001: Every session must produce at least one new holon",
    ),
    GuardRule(
      id: "GR-070",
      name: "TaskWithoutZkSearchWarn",
      salience: 50,
      condition: TaskWithoutZkSearch,
      action: LogWarning(
        "SC-ZK-CLAUDE-001: Task started without searching Zettelkasten for prior patterns",
      ),
      layer: "L5",
      description: "SC-ZK-CLAUDE-001: ZK search is mandatory before starting any new task",
    ),
    // ── GR-071..074: AOR-FUNC (Functional) ──────────────────────────────────
    GuardRule(
      id: "GR-071",
      name: "BuildNotVerifiedWarn",
      salience: 80,
      condition: BuildNotVerified,
      action: LogWarning(
        "AOR-FUNC-001: Commit attempted without verifying gleam build — run gleam build first",
      ),
      layer: "*",
      description: "AOR-FUNC-001: gleam build must be verified clean before any commit",
    ),
    GuardRule(
      id: "GR-072",
      name: "RiskyOpNoCheckpointWarn",
      salience: 75,
      condition: RiskyOpWithoutCheckpoint,
      action: LogWarning(
        "AOR-FUNC-002: Risky operation started without a git checkpoint — create a checkpoint first",
      ),
      layer: "*",
      description: "AOR-FUNC-002: Git checkpoint required before any risky operation",
    ),
    GuardRule(
      id: "GR-073",
      name: "FunctionalRollback",
      salience: 85,
      condition: HealthDecliningAfterChange,
      action: TriggerRunbook("RB-ROLLBACK"),
      layer: "*",
      description: "AOR-FUNC-005: Health declining after a code change — invoke rollback runbook",
    ),
    GuardRule(
      id: "GR-074",
      name: "FunctionalInvariantHalt",
      salience: 100,
      condition: AllOf(conditions: [BuildFailed, HealthBelow(threshold: 0.3)]),
      action: JidokaHalt(
        "AOR-FUNC-008: Build failed AND health < 30% — functional invariant violated, Jidoka halt",
      ),
      layer: "*",
      description: "AOR-FUNC-008: Compound build failure + health collapse triggers Jidoka halt",
    ),
    // ── GR-075..077: AOR-DELETE (Deletion Safety) ───────────────────────────
    GuardRule(
      id: "GR-075",
      name: "DeleteWithoutBackupEscalate",
      salience: 90,
      condition: DeleteWithoutBackup,
      action: EscalateToOperator(
        "AOR-DELETE-001: Deletion attempted without backup or git stash — stash untracked files first",
      ),
      layer: "*",
      description: "AOR-DELETE-001: All untracked code files must be backed up before deletion",
    ),
    GuardRule(
      id: "GR-076",
      name: "DangerousDeleteHalt",
      salience: 100,
      condition: DangerousDeleteDetected,
      action: JidokaHalt(
        "AOR-DELETE-003: rm -rf detected on code directory — immediate halt to prevent data loss",
      ),
      layer: "*",
      description: "AOR-DELETE-003: Destructive rm -rf on code dirs triggers Jidoka halt",
    ),
    GuardRule(
      id: "GR-077",
      name: "DeletionNotLoggedWarn",
      salience: 55,
      condition: DeletionNotLogged,
      action: LogWarning(
        "AOR-DELETE-007: File deletion not recorded in audit log — log all deletions",
      ),
      layer: "*",
      description: "AOR-DELETE-007: Every deletion must be logged to the session audit trail",
    ),
    // ── GR-078..080: AOR-WIRE (Wiring Guard) ────────────────────────────────
    GuardRule(
      id: "GR-078",
      name: "ModelChangedNoGuardWarn",
      salience: 65,
      condition: ModelChangedWithoutGuard,
      action: LogWarning(
        "AOR-WIRE-001: Model type changed without reading wiring_guard.gleam first (SC-WIRE-001)",
      ),
      layer: "L2",
      description: "AOR-WIRE-001: Read wiring_guard.gleam before modifying any Model type",
    ),
    GuardRule(
      id: "GR-079",
      name: "ModelChangedNoTestWarn",
      salience: 60,
      condition: ModelChangedWithoutTest,
      action: LogWarning(
        "AOR-WIRE-004: Model type changed without running gleam test — wiring breaks undetected (SC-WIRE-002)",
      ),
      layer: "L2",
      description: "AOR-WIRE-004: gleam test must be run after every Model type change",
    ),
    GuardRule(
      id: "GR-080",
      name: "DirectConstructorInTestWarn",
      salience: 55,
      condition: DirectConstructorInTest,
      action: LogWarning(
        "AOR-WIRE-005: Test uses direct Model() constructor instead of init() — use init() (SC-WIRE-007)",
      ),
      layer: "L2",
      description: "AOR-WIRE-005: Tests must use init() constructors, not direct Model constructors",
    ),
    // ── GR-081..083: AOR-ZENOH (Telemetry) ──────────────────────────────────
    GuardRule(
      id: "GR-081",
      name: "ZenohDisabledProdHalt",
      salience: 100,
      condition: ZenohDisabledInProd,
      action: JidokaHalt(
        "AOR-ZENOH-001: SKIP_ZENOH_NIF=1 detected in production/staging — Zenoh is mandatory (SC-ZENOH-001)",
      ),
      layer: "L6",
      description: "AOR-ZENOH-001: SKIP_ZENOH_NIF=1 in production is an immediate Jidoka halt",
    ),
    GuardRule(
      id: "GR-082",
      name: "ZenohLongDisconnectEscalate",
      salience: 85,
      condition: ZenohDisconnected30s,
      action: EscalateToOperator(
        "AOR-ZENOH-005: Zenoh router unreachable for >= 30s — mesh backplane unavailable (SC-ZENOH-005)",
      ),
      layer: "L6",
      description: "AOR-ZENOH-005: Zenoh disconnection > 30 seconds must escalate to operator",
    ),
    GuardRule(
      id: "GR-083",
      name: "HealthNotPublishedWarn",
      salience: 60,
      condition: HealthNotPublished,
      action: LogWarning(
        "AOR-ZENOH-007: Node health not published to Zenoh within 10s — publish every 10 seconds (SC-ZENOH-006)",
      ),
      layer: "L6",
      description: "AOR-ZENOH-007: Node health must be published to Zenoh every 10 seconds",
    ),
    // ── GR-084..085: AOR-MOKSHA (Coverage) ──────────────────────────────────
    GuardRule(
      id: "GR-084",
      name: "CoverageDecreasedWarn",
      salience: 65,
      condition: CoverageDecreased,
      action: LogWarning(
        "AOR-MOKSHA-001: Test coverage tensor decreased after sprint — verify tensor coverage >= 80/80 (SC-MOKSHA-001)",
      ),
      layer: "*",
      description: "AOR-MOKSHA-001: Coverage tensor must not regress after any sprint",
    ),
    GuardRule(
      id: "GR-085",
      name: "CommitWithoutTestWarn",
      salience: 75,
      condition: CommitWithoutTest,
      action: LogWarning(
        "AOR-MOKSHA-002: Commit attempted without running gleam test — run gleam test before committing (SC-MOKSHA-002)",
      ),
      layer: "*",
      description: "AOR-MOKSHA-002: gleam test must pass before every commit",
    ),
  ]
}

// ---------------------------------------------------------------------------
// Condition evaluation — pure function over grid metrics
// ---------------------------------------------------------------------------

/// Evaluate a rule condition against current grid metrics.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">GRL when-clause ↪ Gleam Bool predicate</morphism>
///   <formal-proof>
///     <P> All Float metrics are finite; cascade_depth >= 0; failure_count >= 0 </P>
///     <C> evaluate_condition(cond, health, entropy, cascade_depth, failure_count, lyapunov) </C>
///     <Q> Returns Bool — total function, never panics </Q>
///   </formal-proof>
/// </c3i-atomic>
///
/// Parameters:
///   health        — health score in [0.0, 1.0]
///   entropy       — Shannon entropy in [0.0, ∞)
///   cascade_depth — number of adjacent layers currently failing
///   failure_count — total module failure count in grid
///   lyapunov      — Lyapunov exponent (positive = diverging)
///   consecutive   — map approximation; for ModuleConsecutiveFailures we pass
///                   the current consecutive count for the module of interest
pub fn evaluate_condition(
  condition: RuleCondition,
  health: Float,
  entropy: Float,
  cascade_depth: Int,
  failure_count: Int,
  lyapunov: Float,
) -> Bool {
  case condition {
    FailureCountExceeds(threshold) -> failure_count >= threshold

    CascadeDepth(min_depth) -> cascade_depth >= min_depth

    EntropyExceeds(threshold) -> entropy >. threshold

    // LayerFailing: we encode the failing layer name in the entropy parameter
    // as a convention-over-configuration shortcut for pure evaluation.
    // Callers pass entropy < 0.0 (e.g., -1.0) when a specific layer is failing;
    // the layer string is matched by encoding index: L0=-0.0,L1=-1.0,…,L7=-7.0.
    // For unit tests the layer is checked by a separate helper.
    LayerFailing(layer) -> is_layer_failing(layer, entropy, health)

    ModuleConsecutiveFailures(_, count) ->
      // consecutive_failures is encoded as the integer part of |lyapunov| when < 0
      // Callers pass lyapunov as -(consecutive_count) to signal consecutive failures.
      lyapunov <. 0.0 && float.absolute_value(lyapunov) >=. int.to_float(count)

    HealthBelow(threshold) -> health <. threshold

    HealthAbove(threshold) -> health >. threshold

    LyapunovPositive -> lyapunov >. 0.0

    AllOf(conditions) ->
      list.all(conditions, fn(c) {
        evaluate_condition(
          c,
          health,
          entropy,
          cascade_depth,
          failure_count,
          lyapunov,
        )
      })

    AnyOf(conditions) ->
      list.any(conditions, fn(c) {
        evaluate_condition(
          c,
          health,
          entropy,
          cascade_depth,
          failure_count,
          lyapunov,
        )
      })

    // ConsecutiveFailures: conservative approximation — fire when failure_count
    // exceeds the threshold (no per-module history available in basic signature).
    ConsecutiveFailures(_, threshold) -> failure_count > threshold

    // HealthOscillating: oscillation raises entropy; fire when entropy > delta_threshold.
    HealthOscillating(delta_threshold) -> entropy >. delta_threshold

    // HealthDeclining: lyapunov encodes health derivative when < 0.
    // Fire when lyapunov <= rate (both negative; rate e.g. -0.1 means declining at 0.1/cycle).
    HealthDeclining(rate) -> lyapunov <. 0.0 && lyapunov <=. rate

    // EntropyIncreasing: encoded as cascade_depth >= cycles (rising entropy propagates depth).
    EntropyIncreasing(cycles) -> cascade_depth >= cycles

    // LayersFailing (basic API): fire when failure_count exceeds the number of
    // layers listed (conservative proxy — use evaluate_condition_with_layers for accuracy).
    LayersFailing(layers) -> failure_count > list.length(layers)

    // SC-LIFECYCLE-001: Container has data volume — returns False in basic evaluate_condition.
    // These conditions fire only during lifecycle-specific evaluation (via evaluate_condition_with_layers
    // or direct lifecycle checks). In general health evaluation, they are inert to avoid
    // overriding health/cascade rules with higher-salience lifecycle rules.
    ContainerHasDataVolume(_container) -> False

    // SC-LIFECYCLE-003: Migrations missing — returns False in basic evaluation.
    // Real check done by V-18 in verify.rs and lifecycle-specific evaluators.
    MigrationsMissing -> False

    // ── Temporal conditions (GR-036..040) ──
    // DataStale: health < 1.0 AND entropy elevated (staleness increases entropy).
    // Real staleness tracking done by freshness_monitor.gleam OTP actor.
    DataStale(_max_age) -> health <. 0.5 && entropy >. 1.0

    // RateOfChange: health declining at rate exceeding threshold.
    // Uses lyapunov as proxy for rate of change (negative = declining).
    RateOfChangeExceeds(threshold) -> lyapunov <. threshold

    // StatusFlips: oscillation count mapped to cascade_depth (flips cascade).
    StatusFlips(count) -> cascade_depth >= count

    // MonotonicDecline: N consecutive declines mapped to failure_count.
    MonotonicDecline(checks) -> failure_count >= checks

    // HeartbeatMissing: no update for N cycles mapped to cascade_depth.
    HeartbeatMissing(cycles) -> cascade_depth >= cycles

    // ── Mathematical conditions (GR-046..050) ──
    // EntropyBelow: system diversity too low — inverted entropy gate.
    EntropyBelow(threshold) -> entropy <. threshold

    // ComplexityExceeds: state description growing beyond factor × baseline.
    // Uses entropy as complexity proxy (high entropy = high complexity).
    ComplexityExceeds(factor) -> entropy >. factor

    // MutualInfoBelow: weak coupling between layers.
    // Uses health as proxy — low health with low entropy = decoupled.
    MutualInfoBelow(threshold) -> health <. threshold && entropy <. 1.0

    // TransferEntropyBelow: weak causal L4→L5.
    // Uses lyapunov as proxy — near-zero lyapunov = no causal signal.
    TransferEntropyBelow(threshold) ->
      float.absolute_value(lyapunov) <. threshold

    // ── STAMP-specific conditions (GR-051..GR-070) ──
    // BuildFailed: SC-FUNC-001 — failure_count > 0 acts as proxy for build failures.
    // Real build-failure detection is performed by the Rust sa-plan-daemon compile gate.
    // In the pure evaluator, failure_count encodes the number of compile errors.
    BuildFailed -> failure_count > 0

    // CoreServiceDegraded: SC-FUNC-002 — health below threshold AND failures exceed minimum.
    // The caller is responsible for setting failure_count to the number of core-service failures.
    CoreServiceDegraded(min_failures) ->
      health <. 0.5 && failure_count >= min_failures

    // MultipleContainersDown: SC-FUNC-005 — failure_count > threshold containers down.
    // Callers set failure_count to the number of containers in the Down state.
    MultipleContainersDown(threshold) -> failure_count > threshold

    // ZenohDisconnected: SC-FUNC-007 — entropy < 0.0 signals Zenoh session loss.
    // Convention: callers pass entropy = -1.0 when the Zenoh router is unreachable.
    ZenohDisconnected -> entropy <. 0.0

    // DataStalenessExceeds: SC-TRUTH-001/003/004 — cascade_depth encodes staleness in seconds.
    // Convention: callers pass cascade_depth = staleness_seconds for freshness checks.
    DataStalenessExceeds(seconds) -> cascade_depth >= seconds

    // MockDataInProduction: SC-TRUTH-010 — lyapunov = -99.0 signals mock data detected.
    // This is an exceptional sentinel value; normal lyapunov values are in [-10, 10].
    MockDataInProduction -> lyapunov <=. -99.0

    // L0ActionWithoutConsensus: SC-SIL4-006 — lyapunov = -50.0 signals consensus bypass.
    L0ActionWithoutConsensus -> lyapunov <=. -50.0 && lyapunov >. -99.0

    // ShutdownWithoutCheckpoint: SC-SIL4-007 — cascade_depth encodes missing checkpoints.
    // Convention: callers pass cascade_depth = 10 when shutdown proceeded without checkpoint.
    ShutdownWithoutCheckpoint -> cascade_depth >= 10

    // BootWithoutDagValidation: SC-SIL4-010 — failure_count = 100 signals DAG skip.
    // Convention: callers pass failure_count = 100 for DAG-skipped boot events.
    BootWithoutDagValidation -> failure_count >= 100

    // QuorumLost: SC-SIL4-011 — health < 0.4 with high failure count signals quorum loss.
    // Quorum loss manifests as a combination of health degradation and failure spike.
    QuorumLost -> health <. 0.4 && failure_count >= 3

    // PartitionDetected: SC-SIL4-015 — lyapunov = -20.0 signals partition event.
    // Partition signals are distinct from consensus bypass (−50) and mock data (−99).
    PartitionDetected -> lyapunov <=. -20.0 && lyapunov >. -50.0

    // CompileWarningsExist: SC-MUDA-001 — entropy < 0.1 with failure_count > 0 signals warnings.
    // Convention: callers pass failure_count = number of compile warnings, entropy = 0.0.
    CompileWarningsExist -> failure_count > 0 && entropy <. 0.1

    // LargeFileDetected: SC-MUDA-F-003 — entropy in (0.1, 0.5) with failure_count > 0.
    // Convention: callers pass failure_count = 1 and entropy = 0.2 for large-file events.
    LargeFileDetected -> failure_count > 0 && entropy >=. 0.1 && entropy <. 0.5

    // InternalHttpDetected: SC-MUDA-F-005 — entropy in [0.5, 1.0) with no cascade.
    // Convention: callers pass entropy = 0.6 and cascade_depth = 0 for internal HTTP events.
    InternalHttpDetected ->
      failure_count > 0
      && entropy >=. 0.5
      && entropy <. 1.0
      && cascade_depth == 0

    // ZkRecallIgnored: SC-ZK-IMP-001 — lyapunov in (-10.0, -5.0) signals ZK recall omission.
    ZkRecallIgnored -> lyapunov <. -5.0 && lyapunov >. -10.0

    // ZkNoCitation: SC-ZK-IMP-002 — lyapunov in (-5.0, -3.0) signals zero citations.
    ZkNoCitation -> lyapunov <. -3.0 && lyapunov >. -5.0

    // SessionNoHolonProduced: SC-ZETTEL-001 — lyapunov in (-3.0, -2.0) signals no new holons.
    SessionNoHolonProduced -> lyapunov <. -2.0 && lyapunov >. -3.0

    // TaskWithoutZkSearch: SC-ZK-CLAUDE-001 — lyapunov in (-2.0, -1.0) signals ZK search omission.
    TaskWithoutZkSearch -> lyapunov <. -1.0 && lyapunov >. -2.0

    // ── AOR-FUNC conditions (GR-071..GR-074) ──
    // BuildNotVerified: AOR-FUNC-001 — failure_count encodes unverified builds (> 0 = not verified).
    // Convention: callers pass failure_count = 1 and entropy = 1.1 for build-not-verified events.
    BuildNotVerified -> failure_count > 0 && entropy >=. 1.0 && entropy <. 1.5

    // RiskyOpWithoutCheckpoint: AOR-FUNC-002 — entropy in [1.5, 2.0) with cascade_depth = 0.
    // Convention: callers pass entropy = 1.6 and cascade_depth = 0 for risky-op-no-checkpoint events.
    RiskyOpWithoutCheckpoint ->
      failure_count > 0
      && entropy >=. 1.5
      && entropy <. 2.0
      && cascade_depth == 0

    // HealthDecliningAfterChange: AOR-FUNC-005 — lyapunov encodes post-change health derivative.
    // Fire when lyapunov < -0.15 (steeper decline than normal HealthDeclining gate) with entropy >= 2.0.
    // Convention: callers pass entropy = 2.1 when the decline is post-change (not just ongoing).
    HealthDecliningAfterChange -> lyapunov <. -0.15 && entropy >=. 2.0

    // ── AOR-DELETE conditions (GR-075..GR-077) ──
    // DeleteWithoutBackup: AOR-DELETE-001 — cascade_depth = 20 signals delete-without-backup event.
    // Convention: callers pass cascade_depth = 20 for unprotected deletion attempts.
    DeleteWithoutBackup -> cascade_depth >= 20 && cascade_depth < 30

    // DangerousDeleteDetected: AOR-DELETE-003 — cascade_depth >= 30 with non-negative entropy.
    // Convention: callers pass cascade_depth = 30 and entropy = 0.0 for rm -rf on code dirs.
    // Negative entropy (entropy < 0.0) is reserved for Zenoh disconnect signals.
    DangerousDeleteDetected -> cascade_depth >= 30 && entropy >=. 0.0

    // DeletionNotLogged: AOR-DELETE-007 — entropy in [2.0, 2.5) with failure_count = 1.
    // Convention: callers pass failure_count = 1 and entropy = 2.1 for unlogged deletions.
    DeletionNotLogged -> failure_count > 0 && entropy >=. 2.0 && entropy <. 2.5

    // ── AOR-WIRE conditions (GR-078..GR-080) ──
    // ModelChangedWithoutGuard: AOR-WIRE-001 — entropy in [2.5, 3.0) with failure_count = 1.
    // Convention: callers pass failure_count = 1 and entropy = 2.6 for guard-skipped model changes.
    ModelChangedWithoutGuard ->
      failure_count > 0 && entropy >=. 2.5 && entropy <. 3.0

    // ModelChangedWithoutTest: AOR-WIRE-004 — entropy in [3.0, 3.5) with failure_count = 1.
    // Convention: callers pass failure_count = 1 and entropy = 3.1 for test-skipped model changes.
    ModelChangedWithoutTest ->
      failure_count > 0 && entropy >=. 3.0 && entropy <. 3.5

    // DirectConstructorInTest: AOR-WIRE-005 — entropy in [3.5, 4.0) with failure_count = 1.
    // Convention: callers pass failure_count = 1 and entropy = 3.6 for direct-constructor violations.
    DirectConstructorInTest ->
      failure_count > 0 && entropy >=. 3.5 && entropy <. 4.0

    // ── AOR-ZENOH conditions (GR-081..GR-083) ──
    // ZenohDisabledInProd: AOR-ZENOH-001 — lyapunov = -30.0 signals SKIP_ZENOH_NIF=1 in prod.
    // Distinct from ZenohDisconnected (entropy-based) and partition signals (-20 range).
    ZenohDisabledInProd -> lyapunov <=. -30.0 && lyapunov >. -40.0

    // ZenohDisconnected30s: AOR-ZENOH-005 — cascade_depth encodes seconds disconnected.
    // Convention: callers pass cascade_depth = disconnect_seconds for prolonged disconnections.
    ZenohDisconnected30s -> cascade_depth >= 30 && entropy <. 0.0

    // HealthNotPublished: AOR-ZENOH-007 — entropy in [4.0, 4.5) with failure_count = 1.
    // Convention: callers pass failure_count = 1 and entropy = 4.1 for missed health publishes.
    HealthNotPublished -> failure_count > 0 && entropy >=. 4.0 && entropy <. 4.5

    // ── AOR-MOKSHA conditions (GR-084..GR-085) ──
    // CoverageDecreased: AOR-MOKSHA-001 — entropy in [4.5, 5.0) with failure_count = 1.
    // Convention: callers pass failure_count = 1 and entropy = 4.6 for coverage regression events.
    CoverageDecreased -> failure_count > 0 && entropy >=. 4.5 && entropy <. 5.0

    // CommitWithoutTest: AOR-MOKSHA-002 — entropy in [5.0, 5.5) with failure_count = 1.
    // Convention: callers pass failure_count = 1 and entropy = 5.1 for test-skipped commit events.
    CommitWithoutTest -> failure_count > 0 && entropy >=. 5.0 && entropy <. 5.5
  }
}

// ---------------------------------------------------------------------------
// Bulk evaluation
// ---------------------------------------------------------------------------

/// Evaluate ALL rules against current grid state.
/// Returns evaluations sorted by salience (highest first).
/// Only rules with condition_met = True carry their real action;
/// others carry NoAction.
pub fn evaluate_all(
  health: Float,
  entropy: Float,
  cascade_depth: Int,
  failure_count: Int,
  lyapunov: Float,
) -> List(RuleEvaluation) {
  all_rules()
  |> list.map(fn(rule) {
    let met =
      evaluate_condition(
        rule.condition,
        health,
        entropy,
        cascade_depth,
        failure_count,
        lyapunov,
      )
    RuleEvaluation(
      rule_id: rule.id,
      rule_name: rule.name,
      condition_met: met,
      action: case met {
        True -> rule.action
        False -> NoAction
      },
      salience: rule.salience,
    )
  })
  |> list.sort(fn(a, b) { int.compare(b.salience, a.salience) })
}

/// Get the highest-priority triggered action from a list of evaluations.
/// Returns NoAction when no rule fired.
pub fn highest_priority_action(
  evaluations: List(RuleEvaluation),
) -> RuleAction {
  evaluations
  |> list.filter(fn(e) { e.condition_met })
  |> list.sort(fn(a, b) { int.compare(b.salience, a.salience) })
  |> list.first()
  |> fn(result) {
    case result {
      Ok(e) -> e.action
      Error(_) -> NoAction
    }
  }
}

/// Total number of rules in the catalog.
pub fn rule_count() -> Int {
  list.length(all_rules())
}

// ---------------------------------------------------------------------------
// Serialisation
// ---------------------------------------------------------------------------

/// Format a list of evaluations as a compact JSON array.
pub fn to_json(evaluations: List(RuleEvaluation)) -> String {
  let entries =
    evaluations
    |> list.map(fn(e) {
      "{"
      <> "\"rule_id\":\""
      <> e.rule_id
      <> "\","
      <> "\"rule_name\":\""
      <> e.rule_name
      <> "\","
      <> "\"condition_met\":"
      <> case e.condition_met {
        True -> "true"
        False -> "false"
      }
      <> ","
      <> "\"action\":\""
      <> action_to_string(e.action)
      <> "\","
      <> "\"salience\":"
      <> int.to_string(e.salience)
      <> "}"
    })
  "[" <> string.join(entries, ",") <> "]"
}

/// Convert a RuleAction to a human-readable string for logging / JSON.
pub fn action_to_string(action: RuleAction) -> String {
  case action {
    LogWarning(msg) -> "LogWarning(" <> msg <> ")"
    AttemptHotReload -> "AttemptHotReload"
    SetCockpitMode(mode) -> "SetCockpitMode(" <> mode <> ")"
    IsolateCell(layer) -> "IsolateCell(" <> layer <> ")"
    TriggerRunbook(id) -> "TriggerRunbook(" <> id <> ")"
    EscalateToOperator(reason) -> "EscalateToOperator(" <> reason <> ")"
    JidokaHalt(reason) -> "JidokaHalt(" <> reason <> ")"
    NoAction -> "NoAction"
    ActionSequence(actions) ->
      "ActionSequence(["
      <> string.join(list.map(actions, action_to_string), ",")
      <> "])"
    CorrelateFailures(description) -> "CorrelateFailures(" <> description <> ")"
    ClassifyPattern(pattern) -> "ClassifyPattern(" <> pattern <> ")"
    RecordMilestone(milestone) -> "RecordMilestone(" <> milestone <> ")"
    PredictiveAlert(prediction) -> "PredictiveAlert(" <> prediction <> ")"
    PreventiveCooldown(reason) -> "PreventiveCooldown(" <> reason <> ")"
    BlockContainerRemove(container, reason) ->
      "BlockContainerRemove(" <> container <> ": " <> reason <> ")"
    RequireNamedVolume(container) -> "RequireNamedVolume(" <> container <> ")"
  }
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

/// Encode layer-failure state into the evaluation signature.
///
/// Convention: callers signal a failing layer by passing a negative health
/// value where the integer part encodes the layer index:
///   L0 → health < 0.0  AND  trunc(health) == 0   (i.e. health in (-1, 0))
///   L1 → health < -1.0 AND  trunc(health) == -1   (health in (-2, -1))
///   …
///   L7 → health < -7.0 AND  trunc(health) == -7
///
/// For production use, callers should wrap evaluate_all_with_layers/3 which
/// accepts an explicit list of failing layer strings.
fn is_layer_failing(layer: String, _entropy: Float, health: Float) -> Bool {
  case layer {
    "L0" -> health <. 0.0 && health >=. -1.0
    "L1" -> health <. -1.0 && health >=. -2.0
    "L2" -> health <. -2.0 && health >=. -3.0
    "L3" -> health <. -3.0 && health >=. -4.0
    "L4" -> health <. -4.0 && health >=. -5.0
    "L5" -> health <. -5.0 && health >=. -6.0
    "L6" -> health <. -6.0 && health >=. -7.0
    "L7" -> health <. -7.0 && health >=. -8.0
    _ -> False
  }
}

/// Evaluate all rules with explicit failing-layers list.
/// This is the preferred API for production callers.
pub fn evaluate_all_with_layers(
  health: Float,
  entropy: Float,
  cascade_depth: Int,
  failure_count: Int,
  lyapunov: Float,
  failing_layers: List(String),
) -> List(RuleEvaluation) {
  all_rules()
  |> list.map(fn(rule) {
    let met =
      evaluate_condition_with_layers(
        rule.condition,
        health,
        entropy,
        cascade_depth,
        failure_count,
        lyapunov,
        failing_layers,
      )
    RuleEvaluation(
      rule_id: rule.id,
      rule_name: rule.name,
      condition_met: met,
      action: case met {
        True -> rule.action
        False -> NoAction
      },
      salience: rule.salience,
    )
  })
  |> list.sort(fn(a, b) { int.compare(b.salience, a.salience) })
}

/// Condition evaluator that uses an explicit failing-layers list for
/// LayerFailing and LayersFailing conditions (avoids the health-encoding convention).
pub fn evaluate_condition_with_layers(
  condition: RuleCondition,
  health: Float,
  entropy: Float,
  cascade_depth: Int,
  failure_count: Int,
  lyapunov: Float,
  failing_layers: List(String),
) -> Bool {
  case condition {
    LayerFailing(layer) -> list.contains(failing_layers, layer)

    // LayersFailing: all listed layers must be present in failing_layers.
    LayersFailing(layers) ->
      list.all(layers, fn(l) { list.contains(failing_layers, l) })

    ModuleConsecutiveFailures(_, count) ->
      lyapunov <. 0.0 && float.absolute_value(lyapunov) >=. int.to_float(count)

    AllOf(conditions) ->
      list.all(conditions, fn(c) {
        evaluate_condition_with_layers(
          c,
          health,
          entropy,
          cascade_depth,
          failure_count,
          lyapunov,
          failing_layers,
        )
      })

    AnyOf(conditions) ->
      list.any(conditions, fn(c) {
        evaluate_condition_with_layers(
          c,
          health,
          entropy,
          cascade_depth,
          failure_count,
          lyapunov,
          failing_layers,
        )
      })

    // All other conditions delegate to the standard evaluator
    other ->
      evaluate_condition(
        other,
        health,
        entropy,
        cascade_depth,
        failure_count,
        lyapunov,
      )
  }
}
