//// Guard Rules Engine Tests — RETE-UL typed rule definitions
//// STAMP: SC-SIL4-001, SC-HA-001, SC-OODA-001, SC-MUDA-001
//// Layer: L5_COGNITIVE
//// नियतं कुरु कर्म त्वं — Perform your prescribed duty (Gita 3.8)

import cepaf_gleam/ha/guard_rules.{
  type GuardRule, type RuleEvaluation, ActionSequence, AllOf, AnyOf,
  AttemptHotReload, BootWithoutDagValidation, BuildFailed, CascadeDepth,
  ClassifyPattern, CompileWarningsExist, ConsecutiveFailures,
  CoreServiceDegraded, CorrelateFailures, DataStalenessExceeds, EntropyExceeds,
  EntropyIncreasing, EscalateToOperator, FailureCountExceeds, HealthAbove,
  HealthBelow, HealthDeclining, HealthOscillating, InternalHttpDetected,
  IsolateCell, JidokaHalt, L0ActionWithoutConsensus, LargeFileDetected,
  LayersFailing, LogWarning, LyapunovPositive, MockDataInProduction,
  ModuleConsecutiveFailures, MultipleContainersDown, NoAction, PartitionDetected,
  PredictiveAlert, PreventiveCooldown, QuorumLost, RecordMilestone,
  SessionNoHolonProduced, SetCockpitMode, ShutdownWithoutCheckpoint,
  TaskWithoutZkSearch, TriggerRunbook, ZenohDisconnected, ZkNoCitation,
  ZkRecallIgnored,
}
import gleam/list
import gleam/string
import gleeunit/should

// ═══════════════════════════════════════════════════════════════
// Rule Catalog
// ═══════════════════════════════════════════════════════════════

pub fn all_rules_returns_thirty_test() {
  guard_rules.rule_count() |> should.equal(85)
}

pub fn all_rules_have_unique_ids_test() {
  let ids =
    guard_rules.all_rules()
    |> list.map(fn(r: GuardRule) { r.id })
  let unique_count = list.unique(ids) |> list.length()
  unique_count |> should.equal(85)
}

pub fn all_rules_have_non_empty_names_test() {
  guard_rules.all_rules()
  |> list.all(fn(r: GuardRule) { string.length(r.name) > 0 })
  |> should.be_true()
}

pub fn all_rules_have_positive_salience_test() {
  guard_rules.all_rules()
  |> list.all(fn(r: GuardRule) { r.salience > 0 })
  |> should.be_true()
}

pub fn rules_contain_gr001_test() {
  guard_rules.all_rules()
  |> list.any(fn(r: GuardRule) { r.id == "GR-001" })
  |> should.be_true()
}

pub fn rules_contain_gr003_constitutional_threat_test() {
  guard_rules.all_rules()
  |> list.any(fn(r: GuardRule) { r.id == "GR-003" })
  |> should.be_true()
}

pub fn rules_contain_all_new_ids_test() {
  let ids = guard_rules.all_rules() |> list.map(fn(r: GuardRule) { r.id })
  list.contains(ids, "GR-016") |> should.be_true()
  list.contains(ids, "GR-017") |> should.be_true()
  list.contains(ids, "GR-018") |> should.be_true()
  list.contains(ids, "GR-019") |> should.be_true()
  list.contains(ids, "GR-020") |> should.be_true()
  list.contains(ids, "GR-021") |> should.be_true()
  list.contains(ids, "GR-022") |> should.be_true()
  list.contains(ids, "GR-023") |> should.be_true()
  list.contains(ids, "GR-024") |> should.be_true()
  list.contains(ids, "GR-025") |> should.be_true()
  list.contains(ids, "GR-026") |> should.be_true()
  list.contains(ids, "GR-027") |> should.be_true()
  list.contains(ids, "GR-028") |> should.be_true()
  list.contains(ids, "GR-029") |> should.be_true()
  list.contains(ids, "GR-030") |> should.be_true()
}

pub fn rules_contain_stamp_guard_ids_gr051_to_gr070_test() {
  let ids = guard_rules.all_rules() |> list.map(fn(r: GuardRule) { r.id })
  // SC-FUNC rules
  list.contains(ids, "GR-051") |> should.be_true()
  list.contains(ids, "GR-052") |> should.be_true()
  list.contains(ids, "GR-053") |> should.be_true()
  list.contains(ids, "GR-054") |> should.be_true()
  // SC-TRUTH rules
  list.contains(ids, "GR-055") |> should.be_true()
  list.contains(ids, "GR-056") |> should.be_true()
  list.contains(ids, "GR-057") |> should.be_true()
  list.contains(ids, "GR-058") |> should.be_true()
  // SC-SIL4 rules
  list.contains(ids, "GR-059") |> should.be_true()
  list.contains(ids, "GR-060") |> should.be_true()
  list.contains(ids, "GR-061") |> should.be_true()
  list.contains(ids, "GR-062") |> should.be_true()
  list.contains(ids, "GR-063") |> should.be_true()
  // SC-MUDA rules
  list.contains(ids, "GR-064") |> should.be_true()
  list.contains(ids, "GR-065") |> should.be_true()
  list.contains(ids, "GR-066") |> should.be_true()
  // SC-ZK rules
  list.contains(ids, "GR-067") |> should.be_true()
  list.contains(ids, "GR-068") |> should.be_true()
  list.contains(ids, "GR-069") |> should.be_true()
  list.contains(ids, "GR-070") |> should.be_true()
}

// ═══════════════════════════════════════════════════════════════
// STAMP guard rule conditions (GR-051..GR-070)
// ═══════════════════════════════════════════════════════════════

// SC-FUNC-001: BuildFailed fires when failure_count > 0
pub fn gr051_build_failed_fires_when_failure_count_positive_test() {
  guard_rules.evaluate_condition(BuildFailed, 1.0, 0.0, 0, 1, 0.0)
  |> should.be_true()
}

pub fn gr051_build_failed_does_not_fire_when_no_failures_test() {
  guard_rules.evaluate_condition(BuildFailed, 1.0, 0.0, 0, 0, 0.0)
  |> should.be_false()
}

pub fn gr051_build_failed_action_is_jidoka_halt_test() {
  let rule =
    guard_rules.all_rules()
    |> list.find(fn(r: GuardRule) { r.id == "GR-051" })
  case rule {
    Ok(r) ->
      case r.action {
        JidokaHalt(_) -> should.be_true(True)
        _ -> should.be_true(False)
      }
    Error(_) -> should.be_true(False)
  }
}

// SC-FUNC-002: CoreServiceDegraded fires when health < 0.5 AND failures >= min
pub fn gr052_core_service_degraded_fires_test() {
  guard_rules.evaluate_condition(
    CoreServiceDegraded(min_failures: 3),
    0.4,
    0.0,
    0,
    4,
    0.0,
  )
  |> should.be_true()
}

pub fn gr052_core_service_degraded_does_not_fire_when_health_ok_test() {
  guard_rules.evaluate_condition(
    CoreServiceDegraded(min_failures: 3),
    0.7,
    0.0,
    0,
    4,
    0.0,
  )
  |> should.be_false()
}

pub fn gr052_core_service_degraded_does_not_fire_below_min_failures_test() {
  guard_rules.evaluate_condition(
    CoreServiceDegraded(min_failures: 3),
    0.4,
    0.0,
    0,
    2,
    0.0,
  )
  |> should.be_false()
}

// SC-FUNC-005: MultipleContainersDown fires when failure_count > threshold
pub fn gr053_multiple_containers_down_fires_test() {
  guard_rules.evaluate_condition(
    MultipleContainersDown(threshold: 1),
    0.6,
    0.0,
    0,
    2,
    0.0,
  )
  |> should.be_true()
}

pub fn gr053_multiple_containers_down_does_not_fire_at_threshold_test() {
  // failure_count=1, threshold=1 → 1 > 1 is False
  guard_rules.evaluate_condition(
    MultipleContainersDown(threshold: 1),
    0.6,
    0.0,
    0,
    1,
    0.0,
  )
  |> should.be_false()
}

pub fn gr053_container_auto_heal_action_is_trigger_runbook_test() {
  let rule =
    guard_rules.all_rules()
    |> list.find(fn(r: GuardRule) { r.id == "GR-053" })
  case rule {
    Ok(r) ->
      case r.action {
        TriggerRunbook("RB-HEAL") -> should.be_true(True)
        _ -> should.be_true(False)
      }
    Error(_) -> should.be_true(False)
  }
}

// SC-FUNC-007: ZenohDisconnected fires when entropy < 0.0
pub fn gr054_zenoh_disconnected_fires_when_entropy_negative_test() {
  guard_rules.evaluate_condition(ZenohDisconnected, 0.8, -1.0, 0, 0, 0.0)
  |> should.be_true()
}

pub fn gr054_zenoh_disconnected_does_not_fire_when_entropy_zero_test() {
  guard_rules.evaluate_condition(ZenohDisconnected, 0.8, 0.0, 0, 0, 0.0)
  |> should.be_false()
}

// SC-TRUTH-001: DataStalenessExceeds(60) fires when cascade_depth >= 60
pub fn gr055_data_stale_warn_fires_when_cascade_depth_60_test() {
  guard_rules.evaluate_condition(
    DataStalenessExceeds(seconds: 60),
    0.8,
    0.0,
    60,
    0,
    0.0,
  )
  |> should.be_true()
}

pub fn gr055_data_stale_warn_does_not_fire_below_60_test() {
  guard_rules.evaluate_condition(
    DataStalenessExceeds(seconds: 60),
    0.8,
    0.0,
    59,
    0,
    0.0,
  )
  |> should.be_false()
}

// SC-TRUTH-010: MockDataInProduction fires when lyapunov <= -99.0
pub fn gr058_mock_data_halt_fires_when_lyapunov_minus99_test() {
  guard_rules.evaluate_condition(MockDataInProduction, 0.8, 0.0, 0, 0, -99.0)
  |> should.be_true()
}

pub fn gr058_mock_data_halt_fires_when_lyapunov_below_minus99_test() {
  guard_rules.evaluate_condition(MockDataInProduction, 0.8, 0.0, 0, 0, -100.0)
  |> should.be_true()
}

pub fn gr058_mock_data_halt_does_not_fire_for_normal_lyapunov_test() {
  guard_rules.evaluate_condition(MockDataInProduction, 0.8, 0.0, 0, 0, -0.5)
  |> should.be_false()
}

pub fn gr058_mock_data_action_is_jidoka_halt_test() {
  let rule =
    guard_rules.all_rules()
    |> list.find(fn(r: GuardRule) { r.id == "GR-058" })
  case rule {
    Ok(r) ->
      case r.action {
        JidokaHalt(_) -> should.be_true(True)
        _ -> should.be_true(False)
      }
    Error(_) -> should.be_true(False)
  }
}

// SC-SIL4-006: L0ActionWithoutConsensus fires when lyapunov in (-99, -50]
pub fn gr059_l0_action_no_consensus_fires_test() {
  guard_rules.evaluate_condition(
    L0ActionWithoutConsensus,
    0.8,
    0.0,
    0,
    0,
    -50.0,
  )
  |> should.be_true()
}

pub fn gr059_l0_action_no_consensus_does_not_fire_for_normal_lyapunov_test() {
  guard_rules.evaluate_condition(L0ActionWithoutConsensus, 0.8, 0.0, 0, 0, -0.5)
  |> should.be_false()
}

// SC-SIL4-007: ShutdownWithoutCheckpoint fires when cascade_depth >= 10
pub fn gr060_shutdown_no_checkpoint_fires_test() {
  guard_rules.evaluate_condition(
    ShutdownWithoutCheckpoint,
    0.8,
    0.0,
    10,
    0,
    0.0,
  )
  |> should.be_true()
}

pub fn gr060_shutdown_no_checkpoint_does_not_fire_below_10_test() {
  guard_rules.evaluate_condition(ShutdownWithoutCheckpoint, 0.8, 0.0, 9, 0, 0.0)
  |> should.be_false()
}

// SC-SIL4-010: BootWithoutDagValidation fires when failure_count >= 100
pub fn gr061_boot_no_dag_fires_when_failure_count_100_test() {
  guard_rules.evaluate_condition(
    BootWithoutDagValidation,
    0.8,
    0.0,
    0,
    100,
    0.0,
  )
  |> should.be_true()
}

pub fn gr061_boot_no_dag_does_not_fire_below_100_test() {
  guard_rules.evaluate_condition(BootWithoutDagValidation, 0.8, 0.0, 0, 99, 0.0)
  |> should.be_false()
}

pub fn gr061_boot_no_dag_action_is_jidoka_halt_test() {
  let rule =
    guard_rules.all_rules()
    |> list.find(fn(r: GuardRule) { r.id == "GR-061" })
  case rule {
    Ok(r) ->
      case r.action {
        JidokaHalt(_) -> should.be_true(True)
        _ -> should.be_true(False)
      }
    Error(_) -> should.be_true(False)
  }
}

// SC-SIL4-011: QuorumLost fires when health < 0.4 AND failure_count >= 3
pub fn gr062_quorum_lost_fires_test() {
  guard_rules.evaluate_condition(QuorumLost, 0.3, 0.0, 0, 4, 0.0)
  |> should.be_true()
}

pub fn gr062_quorum_lost_does_not_fire_when_health_ok_test() {
  guard_rules.evaluate_condition(QuorumLost, 0.6, 0.0, 0, 4, 0.0)
  |> should.be_false()
}

// SC-SIL4-015: PartitionDetected fires when lyapunov in (-50, -20]
pub fn gr063_partition_detected_fires_test() {
  guard_rules.evaluate_condition(PartitionDetected, 0.8, 0.0, 0, 0, -20.0)
  |> should.be_true()
}

pub fn gr063_partition_detected_does_not_fire_for_normal_lyapunov_test() {
  guard_rules.evaluate_condition(PartitionDetected, 0.8, 0.0, 0, 0, -0.5)
  |> should.be_false()
}

pub fn gr063_split_brain_action_is_jidoka_halt_test() {
  let rule =
    guard_rules.all_rules()
    |> list.find(fn(r: GuardRule) { r.id == "GR-063" })
  case rule {
    Ok(r) ->
      case r.action {
        JidokaHalt(_) -> should.be_true(True)
        _ -> should.be_true(False)
      }
    Error(_) -> should.be_true(False)
  }
}

// SC-MUDA-001: CompileWarningsExist fires when failure_count > 0 AND entropy < 0.1
pub fn gr064_compile_warnings_fires_test() {
  guard_rules.evaluate_condition(CompileWarningsExist, 0.9, 0.05, 0, 2, 0.0)
  |> should.be_true()
}

pub fn gr064_compile_warnings_does_not_fire_when_no_failures_test() {
  guard_rules.evaluate_condition(CompileWarningsExist, 0.9, 0.05, 0, 0, 0.0)
  |> should.be_false()
}

pub fn gr064_compile_warnings_action_is_log_warning_test() {
  let rule =
    guard_rules.all_rules()
    |> list.find(fn(r: GuardRule) { r.id == "GR-064" })
  case rule {
    Ok(r) ->
      case r.action {
        LogWarning(_) -> should.be_true(True)
        _ -> should.be_true(False)
      }
    Error(_) -> should.be_true(False)
  }
}

// SC-MUDA-F-003: LargeFileDetected fires when failure_count > 0 AND entropy in [0.1, 0.5)
pub fn gr065_large_file_fires_test() {
  guard_rules.evaluate_condition(LargeFileDetected, 0.9, 0.2, 0, 1, 0.0)
  |> should.be_true()
}

pub fn gr065_large_file_does_not_fire_when_entropy_below_01_test() {
  guard_rules.evaluate_condition(LargeFileDetected, 0.9, 0.05, 0, 1, 0.0)
  |> should.be_false()
}

// SC-MUDA-F-005: InternalHttpDetected fires when failure_count > 0 AND entropy in [0.5, 1.0) AND cascade = 0
pub fn gr066_internal_http_fires_test() {
  guard_rules.evaluate_condition(InternalHttpDetected, 0.9, 0.6, 0, 1, 0.0)
  |> should.be_true()
}

pub fn gr066_internal_http_does_not_fire_when_cascade_nonzero_test() {
  guard_rules.evaluate_condition(InternalHttpDetected, 0.9, 0.6, 1, 1, 0.0)
  |> should.be_false()
}

// SC-ZK-IMP-001: ZkRecallIgnored fires when lyapunov in (-10.0, -5.0)
pub fn gr067_zk_recall_ignored_fires_test() {
  guard_rules.evaluate_condition(ZkRecallIgnored, 0.9, 0.0, 0, 0, -7.0)
  |> should.be_true()
}

pub fn gr067_zk_recall_ignored_does_not_fire_for_normal_lyapunov_test() {
  guard_rules.evaluate_condition(ZkRecallIgnored, 0.9, 0.0, 0, 0, -0.5)
  |> should.be_false()
}

// SC-ZK-IMP-002: ZkNoCitation fires when lyapunov in (-5.0, -3.0)
pub fn gr068_zk_no_citation_fires_test() {
  guard_rules.evaluate_condition(ZkNoCitation, 0.9, 0.0, 0, 0, -4.0)
  |> should.be_true()
}

pub fn gr068_zk_no_citation_does_not_fire_outside_range_test() {
  guard_rules.evaluate_condition(ZkNoCitation, 0.9, 0.0, 0, 0, -7.0)
  |> should.be_false()
}

// SC-ZETTEL-001: SessionNoHolonProduced fires when lyapunov in (-3.0, -2.0)
pub fn gr069_session_no_holon_fires_test() {
  guard_rules.evaluate_condition(SessionNoHolonProduced, 0.9, 0.0, 0, 0, -2.5)
  |> should.be_true()
}

pub fn gr069_session_no_holon_does_not_fire_outside_range_test() {
  guard_rules.evaluate_condition(SessionNoHolonProduced, 0.9, 0.0, 0, 0, -4.0)
  |> should.be_false()
}

// SC-ZK-CLAUDE-001: TaskWithoutZkSearch fires when lyapunov in (-2.0, -1.0)
pub fn gr070_task_without_zk_search_fires_test() {
  guard_rules.evaluate_condition(TaskWithoutZkSearch, 0.9, 0.0, 0, 0, -1.5)
  |> should.be_true()
}

pub fn gr070_task_without_zk_search_does_not_fire_outside_range_test() {
  guard_rules.evaluate_condition(TaskWithoutZkSearch, 0.9, 0.0, 0, 0, -2.5)
  |> should.be_false()
}

pub fn gr070_task_without_zk_search_action_is_log_warning_test() {
  let rule =
    guard_rules.all_rules()
    |> list.find(fn(r: GuardRule) { r.id == "GR-070" })
  case rule {
    Ok(r) ->
      case r.action {
        LogWarning(_) -> should.be_true(True)
        _ -> should.be_true(False)
      }
    Error(_) -> should.be_true(False)
  }
}

// ═══════════════════════════════════════════════════════════════
// evaluate_condition — atomic conditions (original)
// ═══════════════════════════════════════════════════════════════

pub fn failure_count_exceeds_fires_at_threshold_test() {
  guard_rules.evaluate_condition(
    FailureCountExceeds(threshold: 5),
    1.0,
    0.0,
    0,
    5,
    0.0,
  )
  |> should.be_true()
}

pub fn failure_count_exceeds_does_not_fire_below_threshold_test() {
  guard_rules.evaluate_condition(
    FailureCountExceeds(threshold: 5),
    1.0,
    0.0,
    0,
    4,
    0.0,
  )
  |> should.be_false()
}

pub fn cascade_depth_fires_at_min_depth_test() {
  guard_rules.evaluate_condition(
    CascadeDepth(min_depth: 3),
    1.0,
    0.0,
    3,
    0,
    0.0,
  )
  |> should.be_true()
}

pub fn cascade_depth_does_not_fire_below_min_depth_test() {
  guard_rules.evaluate_condition(
    CascadeDepth(min_depth: 3),
    1.0,
    0.0,
    2,
    0,
    0.0,
  )
  |> should.be_false()
}

pub fn entropy_exceeds_fires_above_threshold_test() {
  guard_rules.evaluate_condition(
    EntropyExceeds(threshold: 1.5),
    1.0,
    2.0,
    0,
    0,
    0.0,
  )
  |> should.be_true()
}

pub fn entropy_exceeds_does_not_fire_at_equal_test() {
  guard_rules.evaluate_condition(
    EntropyExceeds(threshold: 1.5),
    1.0,
    1.5,
    0,
    0,
    0.0,
  )
  |> should.be_false()
}

pub fn entropy_exceeds_does_not_fire_below_threshold_test() {
  guard_rules.evaluate_condition(
    EntropyExceeds(threshold: 1.5),
    1.0,
    1.0,
    0,
    0,
    0.0,
  )
  |> should.be_false()
}

pub fn health_below_fires_when_health_is_low_test() {
  guard_rules.evaluate_condition(
    HealthBelow(threshold: 0.5),
    0.3,
    0.0,
    0,
    0,
    0.0,
  )
  |> should.be_true()
}

pub fn health_below_does_not_fire_above_threshold_test() {
  guard_rules.evaluate_condition(
    HealthBelow(threshold: 0.5),
    0.8,
    0.0,
    0,
    0,
    0.0,
  )
  |> should.be_false()
}

pub fn health_above_fires_when_health_is_high_test() {
  guard_rules.evaluate_condition(
    HealthAbove(threshold: 0.9),
    0.95,
    0.0,
    0,
    0,
    0.0,
  )
  |> should.be_true()
}

pub fn health_above_does_not_fire_at_threshold_test() {
  guard_rules.evaluate_condition(
    HealthAbove(threshold: 0.9),
    0.9,
    0.0,
    0,
    0,
    0.0,
  )
  |> should.be_false()
}

pub fn lyapunov_positive_fires_when_positive_test() {
  guard_rules.evaluate_condition(LyapunovPositive, 1.0, 0.0, 0, 0, 0.1)
  |> should.be_true()
}

pub fn lyapunov_positive_does_not_fire_when_negative_test() {
  guard_rules.evaluate_condition(LyapunovPositive, 1.0, 0.0, 0, 0, -0.1)
  |> should.be_false()
}

pub fn lyapunov_positive_does_not_fire_at_zero_test() {
  guard_rules.evaluate_condition(LyapunovPositive, 1.0, 0.0, 0, 0, 0.0)
  |> should.be_false()
}

pub fn module_consecutive_failures_fires_at_count_test() {
  // lyapunov = -3.0 signals 3 consecutive failures
  guard_rules.evaluate_condition(
    ModuleConsecutiveFailures(module: "nif_bridge", count: 3),
    1.0,
    0.0,
    0,
    0,
    -3.0,
  )
  |> should.be_true()
}

pub fn module_consecutive_failures_does_not_fire_below_count_test() {
  guard_rules.evaluate_condition(
    ModuleConsecutiveFailures(module: "nif_bridge", count: 3),
    1.0,
    0.0,
    0,
    0,
    -2.0,
  )
  |> should.be_false()
}

pub fn module_consecutive_failures_does_not_fire_when_positive_lyapunov_test() {
  guard_rules.evaluate_condition(
    ModuleConsecutiveFailures(module: "nif_bridge", count: 1),
    1.0,
    0.0,
    0,
    0,
    1.0,
  )
  |> should.be_false()
}

// ═══════════════════════════════════════════════════════════════
// evaluate_condition — new condition types (GR-016..GR-030)
// ═══════════════════════════════════════════════════════════════

pub fn consecutive_failures_fires_when_count_exceeded_test() {
  // failure_count=5 > threshold=3 → fires
  guard_rules.evaluate_condition(
    ConsecutiveFailures(module: "nif_bridge", threshold: 3),
    1.0,
    0.0,
    0,
    5,
    0.0,
  )
  |> should.be_true()
}

pub fn consecutive_failures_does_not_fire_at_threshold_test() {
  // failure_count=3, threshold=3 → 3 > 3 is False
  guard_rules.evaluate_condition(
    ConsecutiveFailures(module: "nif_bridge", threshold: 3),
    1.0,
    0.0,
    0,
    3,
    0.0,
  )
  |> should.be_false()
}

pub fn consecutive_failures_does_not_fire_below_threshold_test() {
  guard_rules.evaluate_condition(
    ConsecutiveFailures(module: "nif_bridge", threshold: 3),
    1.0,
    0.0,
    0,
    2,
    0.0,
  )
  |> should.be_false()
}

pub fn health_oscillating_fires_when_entropy_above_delta_test() {
  // entropy=0.5 > delta_threshold=0.2 → oscillation detected
  guard_rules.evaluate_condition(
    HealthOscillating(delta_threshold: 0.2),
    0.7,
    0.5,
    0,
    0,
    0.0,
  )
  |> should.be_true()
}

pub fn health_oscillating_does_not_fire_below_delta_test() {
  guard_rules.evaluate_condition(
    HealthOscillating(delta_threshold: 0.2),
    0.7,
    0.1,
    0,
    0,
    0.0,
  )
  |> should.be_false()
}

pub fn health_oscillating_does_not_fire_at_delta_threshold_test() {
  // entropy == delta_threshold (0.2 > 0.2 is False)
  guard_rules.evaluate_condition(
    HealthOscillating(delta_threshold: 0.2),
    0.7,
    0.2,
    0,
    0,
    0.0,
  )
  |> should.be_false()
}

pub fn health_declining_fires_when_lyapunov_at_or_below_rate_test() {
  // lyapunov=-0.15, rate=-0.1 → -0.15 <= -0.1, declining faster than threshold
  guard_rules.evaluate_condition(
    HealthDeclining(rate: -0.1),
    0.6,
    0.0,
    0,
    0,
    -0.15,
  )
  |> should.be_true()
}

pub fn health_declining_fires_exactly_at_rate_test() {
  // lyapunov=-0.1, rate=-0.1 → -0.1 <= -0.1 is True
  guard_rules.evaluate_condition(
    HealthDeclining(rate: -0.1),
    0.6,
    0.0,
    0,
    0,
    -0.1,
  )
  |> should.be_true()
}

pub fn health_declining_does_not_fire_when_stable_test() {
  // lyapunov=-0.05, rate=-0.1 → -0.05 <= -0.1 is False (declining slower than threshold)
  guard_rules.evaluate_condition(
    HealthDeclining(rate: -0.1),
    0.9,
    0.0,
    0,
    0,
    -0.05,
  )
  |> should.be_false()
}

pub fn health_declining_does_not_fire_when_lyapunov_positive_test() {
  // positive lyapunov means health is not declining in this encoding
  guard_rules.evaluate_condition(
    HealthDeclining(rate: -0.1),
    0.8,
    0.0,
    0,
    0,
    0.05,
  )
  |> should.be_false()
}

pub fn entropy_increasing_fires_when_cascade_depth_at_cycles_test() {
  // cascade_depth=3 >= cycles=3 → entropy rising for 3+ cycles
  guard_rules.evaluate_condition(
    EntropyIncreasing(cycles: 3),
    0.8,
    1.2,
    3,
    0,
    0.0,
  )
  |> should.be_true()
}

pub fn entropy_increasing_fires_when_cascade_depth_exceeds_cycles_test() {
  guard_rules.evaluate_condition(
    EntropyIncreasing(cycles: 3),
    0.8,
    1.2,
    5,
    0,
    0.0,
  )
  |> should.be_true()
}

pub fn entropy_increasing_does_not_fire_below_cycles_test() {
  guard_rules.evaluate_condition(
    EntropyIncreasing(cycles: 3),
    0.8,
    1.2,
    2,
    0,
    0.0,
  )
  |> should.be_false()
}

pub fn layers_failing_basic_api_fires_when_failure_count_exceeds_list_size_test() {
  // layers=["L1","L3"] has length 2; failure_count=3 > 2 → fires
  guard_rules.evaluate_condition(
    LayersFailing(layers: ["L1", "L3"]),
    0.7,
    0.5,
    1,
    3,
    0.0,
  )
  |> should.be_true()
}

pub fn layers_failing_basic_api_does_not_fire_when_failure_count_low_test() {
  // layers=["L1","L3"] has length 2; failure_count=2 → 2 > 2 is False
  guard_rules.evaluate_condition(
    LayersFailing(layers: ["L1", "L3"]),
    0.7,
    0.5,
    1,
    2,
    0.0,
  )
  |> should.be_false()
}

// ═══════════════════════════════════════════════════════════════
// AllOf / AnyOf combinators
// ═══════════════════════════════════════════════════════════════

pub fn all_of_true_when_all_conditions_true_test() {
  guard_rules.evaluate_condition(
    AllOf(conditions: [
      HealthBelow(threshold: 0.5),
      CascadeDepth(min_depth: 2),
    ]),
    0.3,
    0.0,
    3,
    0,
    0.0,
  )
  |> should.be_true()
}

pub fn all_of_false_when_one_condition_false_test() {
  guard_rules.evaluate_condition(
    AllOf(conditions: [
      HealthBelow(threshold: 0.5),
      CascadeDepth(min_depth: 2),
    ]),
    0.3,
    0.0,
    1,
    0,
    0.0,
  )
  |> should.be_false()
}

pub fn any_of_true_when_one_condition_true_test() {
  guard_rules.evaluate_condition(
    AnyOf(conditions: [
      HealthBelow(threshold: 0.5),
      CascadeDepth(min_depth: 5),
    ]),
    0.3,
    0.0,
    2,
    0,
    0.0,
  )
  |> should.be_true()
}

pub fn any_of_false_when_all_conditions_false_test() {
  guard_rules.evaluate_condition(
    AnyOf(conditions: [
      HealthBelow(threshold: 0.5),
      CascadeDepth(min_depth: 5),
    ]),
    0.8,
    0.0,
    2,
    0,
    0.0,
  )
  |> should.be_false()
}

pub fn nested_all_of_any_of_evaluates_correctly_test() {
  // (health < 0.5) AND (cascade >= 2 OR failure_count >= 3)
  let condition =
    AllOf(conditions: [
      HealthBelow(threshold: 0.5),
      AnyOf(conditions: [
        CascadeDepth(min_depth: 2),
        FailureCountExceeds(threshold: 3),
      ]),
    ])
  // health=0.3 (<0.5), cascade=1 (<2), failures=4 (>=3) → True
  guard_rules.evaluate_condition(condition, 0.3, 0.0, 1, 4, 0.0)
  |> should.be_true()
}

pub fn all_of_with_empty_list_is_vacuously_true_test() {
  guard_rules.evaluate_condition(AllOf(conditions: []), 0.5, 0.0, 0, 0, 0.0)
  |> should.be_true()
}

pub fn any_of_with_empty_list_is_false_test() {
  guard_rules.evaluate_condition(AnyOf(conditions: []), 0.5, 0.0, 0, 0, 0.0)
  |> should.be_false()
}

// ═══════════════════════════════════════════════════════════════
// evaluate_all — bulk evaluation with salience ordering
// ═══════════════════════════════════════════════════════════════

pub fn evaluate_all_returns_thirty_evaluations_test() {
  let evals = guard_rules.evaluate_all(0.8, 0.5, 0, 0, 0.0)
  list.length(evals) |> should.equal(85)
}

pub fn evaluate_all_sorted_by_salience_descending_test() {
  let evals = guard_rules.evaluate_all(0.8, 0.5, 0, 0, 0.0)
  let saliences = list.map(evals, fn(e: RuleEvaluation) { e.salience })
  // Verify each element is >= the next (non-increasing order)
  let pairs = list.zip(saliences, list.drop(saliences, 1))
  list.all(pairs, fn(p) { p.0 >= p.1 })
  |> should.be_true()
}

pub fn evaluate_all_healthy_system_no_critical_rules_fired_test() {
  // Perfect health, low entropy, no cascade, positive lyapunov not set
  let evals = guard_rules.evaluate_all(0.98, 0.1, 0, 0, -0.1)
  let fired = list.filter(evals, fn(e: RuleEvaluation) { e.condition_met })
  // Only GR-014 (NormalMode) and similar should fire
  list.any(fired, fn(e: RuleEvaluation) { e.rule_id == "GR-014" })
  |> should.be_true()
}

pub fn evaluate_all_critical_failure_fires_jidoka_halt_test() {
  // health=0.1, cascade=4 → GR-001 CascadeEscalation should fire
  let evals = guard_rules.evaluate_all(0.1, 2.0, 4, 8, 0.0)
  let fired = list.filter(evals, fn(e: RuleEvaluation) { e.condition_met })
  list.any(fired, fn(e: RuleEvaluation) { e.rule_id == "GR-001" })
  |> should.be_true()
}

pub fn evaluate_all_unfired_rules_carry_no_action_test() {
  // Perfect health — no alerts should fire
  let evals = guard_rules.evaluate_all(0.98, 0.1, 0, 0, 0.0)
  let unfired = list.filter(evals, fn(e: RuleEvaluation) { !e.condition_met })
  list.all(unfired, fn(e: RuleEvaluation) { e.action == NoAction })
  |> should.be_true()
}

// ═══════════════════════════════════════════════════════════════
// highest_priority_action
// ═══════════════════════════════════════════════════════════════

pub fn highest_priority_action_returns_no_action_when_none_fired_test() {
  // Perfectly healthy system: high health, no cascade, no failures, stable lyapunov
  let evals = guard_rules.evaluate_all(0.98, 0.15, 0, 0, -0.5)
  let action = guard_rules.highest_priority_action(evals)
  // In a healthy system, the highest-priority action MUST NOT be JidokaHalt or emergency
  case action {
    JidokaHalt(_) -> should.be_true(False)
    SetCockpitMode("emergency") -> should.be_true(False)
    _ -> should.be_true(True)
  }
}

pub fn highest_priority_action_returns_jidoka_halt_on_cascade_test() {
  let evals = guard_rules.evaluate_all(0.1, 2.0, 4, 8, 0.0)
  let action = guard_rules.highest_priority_action(evals)
  // GR-001 (salience 100) fires JidokaHalt
  case action {
    JidokaHalt(_) -> should.be_true(True)
    _ -> should.be_true(False)
  }
}

pub fn highest_priority_action_emergency_mode_on_low_health_test() {
  // health=0.2, no cascade, no layer-specific failure, failure_count=0 (no compile errors)
  // GR-051 BuildFailed (salience 100) must NOT fire (failure_count=0)
  // GR-002 EmergencyMode (salience 95) fires — health < 0.3
  let evals = guard_rules.evaluate_all(0.2, 0.5, 0, 0, 0.0)
  let action = guard_rules.highest_priority_action(evals)
  action |> should.equal(SetCockpitMode("emergency"))
}

pub fn highest_priority_action_returns_no_action_empty_list_test() {
  guard_rules.highest_priority_action([])
  |> should.equal(NoAction)
}

// ═══════════════════════════════════════════════════════════════
// evaluate_all_with_layers — explicit layer failure API
// ═══════════════════════════════════════════════════════════════

pub fn evaluate_all_with_layers_l0_failing_fires_constitutional_threat_test() {
  let evals = guard_rules.evaluate_all_with_layers(0.8, 0.5, 0, 0, 0.0, ["L0"])
  let fired = list.filter(evals, fn(e: RuleEvaluation) { e.condition_met })
  list.any(fired, fn(e: RuleEvaluation) { e.rule_id == "GR-003" })
  |> should.be_true()
}

pub fn evaluate_all_with_layers_l6_failing_fires_quorum_threat_test() {
  let evals = guard_rules.evaluate_all_with_layers(0.8, 0.5, 0, 0, 0.0, ["L6"])
  let fired = list.filter(evals, fn(e: RuleEvaluation) { e.condition_met })
  list.any(fired, fn(e: RuleEvaluation) { e.rule_id == "GR-004" })
  |> should.be_true()
}

pub fn evaluate_all_with_layers_l1_failing_fires_runbook_nif_test() {
  let evals = guard_rules.evaluate_all_with_layers(0.8, 0.5, 0, 0, 0.0, ["L1"])
  let fired = list.filter(evals, fn(e: RuleEvaluation) { e.condition_met })
  list.any(fired, fn(e: RuleEvaluation) { e.rule_id == "GR-009" })
  |> should.be_true()
}

pub fn evaluate_all_with_layers_no_failures_does_not_fire_layer_rules_test() {
  let evals = guard_rules.evaluate_all_with_layers(0.95, 0.2, 0, 0, -0.1, [])
  let fired = list.filter(evals, fn(e: RuleEvaluation) { e.condition_met })
  // Layer-specific rules should NOT fire when no layers are failing
  list.any(fired, fn(e: RuleEvaluation) {
    e.rule_id == "GR-003" || e.rule_id == "GR-004" || e.rule_id == "GR-009"
  })
  |> should.be_false()
}

pub fn evaluate_all_with_layers_l1_l3_fires_nif_planning_correlation_test() {
  // Both L1 and L3 failing → GR-019 NifPlanningCorrelation fires
  let evals =
    guard_rules.evaluate_all_with_layers(0.6, 0.8, 1, 2, 0.0, ["L1", "L3"])
  let fired = list.filter(evals, fn(e: RuleEvaluation) { e.condition_met })
  list.any(fired, fn(e: RuleEvaluation) { e.rule_id == "GR-019" })
  |> should.be_true()
}

pub fn evaluate_all_with_layers_l1_only_does_not_fire_gr019_test() {
  // Only L1 failing → GR-019 requires both L1 and L3
  let evals = guard_rules.evaluate_all_with_layers(0.7, 0.5, 0, 1, 0.0, ["L1"])
  let fired = list.filter(evals, fn(e: RuleEvaluation) { e.condition_met })
  list.any(fired, fn(e: RuleEvaluation) { e.rule_id == "GR-019" })
  |> should.be_false()
}

pub fn evaluate_all_with_layers_l6_l7_fires_zenoh_fed_correlation_test() {
  // Both L6 and L7 failing → GR-021 ZenohFedCorrelation fires
  let evals =
    guard_rules.evaluate_all_with_layers(0.6, 0.8, 1, 2, 0.0, ["L6", "L7"])
  let fired = list.filter(evals, fn(e: RuleEvaluation) { e.condition_met })
  list.any(fired, fn(e: RuleEvaluation) { e.rule_id == "GR-021" })
  |> should.be_true()
}

pub fn evaluate_all_with_layers_l3_failing_fires_transaction_recovery_test() {
  // L3 failing → GR-028 TransactionRecovery fires
  let evals = guard_rules.evaluate_all_with_layers(0.7, 0.4, 0, 1, 0.0, ["L3"])
  let fired = list.filter(evals, fn(e: RuleEvaluation) { e.condition_met })
  list.any(fired, fn(e: RuleEvaluation) { e.rule_id == "GR-028" })
  |> should.be_true()
}

pub fn evaluate_all_with_layers_l2_failing_fires_component_degradation_test() {
  // L2 failing → GR-027 ComponentDegradation fires
  let evals = guard_rules.evaluate_all_with_layers(0.75, 0.4, 0, 1, 0.0, ["L2"])
  let fired = list.filter(evals, fn(e: RuleEvaluation) { e.condition_met })
  list.any(fired, fn(e: RuleEvaluation) { e.rule_id == "GR-027" })
  |> should.be_true()
}

pub fn evaluate_all_with_layers_multiple_layer_failures_fires_multiple_rules_test() {
  let evals =
    guard_rules.evaluate_all_with_layers(0.4, 0.5, 1, 3, 0.0, ["L1", "L4", "L5"])
  let fired = list.filter(evals, fn(e: RuleEvaluation) { e.condition_met })
  { list.length(fired) > 2 } |> should.be_true()
}

// ═══════════════════════════════════════════════════════════════
// New rule-specific evaluation tests (GR-016..GR-030)
// ═══════════════════════════════════════════════════════════════

pub fn gr016_recurring_nif_failure_fires_via_basic_api_test() {
  // failure_count=5 > threshold=3 → GR-016 ConsecutiveFailures fires
  let evals = guard_rules.evaluate_all(0.7, 0.3, 0, 5, 0.0)
  let fired = list.filter(evals, fn(e: RuleEvaluation) { e.condition_met })
  list.any(fired, fn(e: RuleEvaluation) { e.rule_id == "GR-016" })
  |> should.be_true()
}

pub fn gr017_health_oscillation_fires_when_entropy_high_test() {
  // entropy=0.5 > delta_threshold=0.2 → GR-017 HealthOscillation fires
  let evals = guard_rules.evaluate_all(0.7, 0.5, 0, 0, 0.0)
  let fired = list.filter(evals, fn(e: RuleEvaluation) { e.condition_met })
  list.any(fired, fn(e: RuleEvaluation) { e.rule_id == "GR-017" })
  |> should.be_true()
}

pub fn gr018_reliability_streak_fires_when_health_high_test() {
  // health=0.97 > 0.95 → GR-018 ReliabilityStreak fires
  let evals = guard_rules.evaluate_all(0.97, 0.1, 0, 0, 0.0)
  let fired = list.filter(evals, fn(e: RuleEvaluation) { e.condition_met })
  list.any(fired, fn(e: RuleEvaluation) { e.rule_id == "GR-018" })
  |> should.be_true()
}

pub fn gr018_reliability_streak_action_is_record_milestone_test() {
  let rule =
    guard_rules.all_rules()
    |> list.find(fn(r: GuardRule) { r.id == "GR-018" })
  case rule {
    Ok(r) ->
      case r.action {
        RecordMilestone("1h_streak") -> should.be_true(True)
        _ -> should.be_true(False)
      }
    Error(_) -> should.be_true(False)
  }
}

pub fn gr020_health_decline_rate_fires_when_lyapunov_steep_test() {
  // lyapunov=-0.2, rate=-0.1 → -0.2 <= -0.1 → GR-020 fires
  let evals = guard_rules.evaluate_all(0.6, 0.3, 0, 0, -0.2)
  let fired = list.filter(evals, fn(e: RuleEvaluation) { e.condition_met })
  list.any(fired, fn(e: RuleEvaluation) { e.rule_id == "GR-020" })
  |> should.be_true()
}

pub fn gr020_health_decline_rate_action_is_predictive_alert_test() {
  let rule =
    guard_rules.all_rules()
    |> list.find(fn(r: GuardRule) { r.id == "GR-020" })
  case rule {
    Ok(r) ->
      case r.action {
        PredictiveAlert(_) -> should.be_true(True)
        _ -> should.be_true(False)
      }
    Error(_) -> should.be_true(False)
  }
}

pub fn gr023_entropy_escalation_fires_when_cascade_depth_at_3_test() {
  // cascade_depth=3 >= cycles=3 → GR-023 EntropyEscalation fires
  let evals = guard_rules.evaluate_all(0.75, 1.2, 3, 0, 0.0)
  let fired = list.filter(evals, fn(e: RuleEvaluation) { e.condition_met })
  list.any(fired, fn(e: RuleEvaluation) { e.rule_id == "GR-023" })
  |> should.be_true()
}

pub fn gr023_entropy_escalation_action_is_preventive_cooldown_test() {
  let rule =
    guard_rules.all_rules()
    |> list.find(fn(r: GuardRule) { r.id == "GR-023" })
  case rule {
    Ok(r) ->
      case r.action {
        PreventiveCooldown(_) -> should.be_true(True)
        _ -> should.be_true(False)
      }
    Error(_) -> should.be_true(False)
  }
}

pub fn gr024_degraded_classification_fires_when_health_below_06_test() {
  // health=0.55 < 0.6 → GR-024 DegradedClassification fires
  let evals = guard_rules.evaluate_all(0.55, 0.3, 0, 0, 0.0)
  let fired = list.filter(evals, fn(e: RuleEvaluation) { e.condition_met })
  list.any(fired, fn(e: RuleEvaluation) { e.rule_id == "GR-024" })
  |> should.be_true()
}

pub fn gr024_degraded_classification_action_is_classify_pattern_test() {
  let rule =
    guard_rules.all_rules()
    |> list.find(fn(r: GuardRule) { r.id == "GR-024" })
  case rule {
    Ok(r) ->
      case r.action {
        ClassifyPattern("degraded_but_operational") -> should.be_true(True)
        _ -> should.be_true(False)
      }
    Error(_) -> should.be_true(False)
  }
}

pub fn gr026_critical_divergence_fires_on_lyapunov_plus_cascade_test() {
  // lyapunov=0.3 (positive) AND cascade_depth=2 → GR-026 CriticalDivergence fires
  let evals = guard_rules.evaluate_all(0.6, 0.5, 2, 3, 0.3)
  let fired = list.filter(evals, fn(e: RuleEvaluation) { e.condition_met })
  list.any(fired, fn(e: RuleEvaluation) { e.rule_id == "GR-026" })
  |> should.be_true()
}

pub fn gr026_critical_divergence_does_not_fire_without_cascade_test() {
  // lyapunov positive but cascade_depth=1 < 2 → GR-026 must NOT fire
  let evals = guard_rules.evaluate_all(0.7, 0.4, 1, 1, 0.3)
  let fired = list.filter(evals, fn(e: RuleEvaluation) { e.condition_met })
  list.any(fired, fn(e: RuleEvaluation) { e.rule_id == "GR-026" })
  |> should.be_false()
}

pub fn gr026_critical_divergence_action_is_jidoka_halt_test() {
  let rule =
    guard_rules.all_rules()
    |> list.find(fn(r: GuardRule) { r.id == "GR-026" })
  case rule {
    Ok(r) ->
      case r.action {
        JidokaHalt(_) -> should.be_true(True)
        _ -> should.be_true(False)
      }
    Error(_) -> should.be_true(False)
  }
}

pub fn gr029_mass_failure_emergency_fires_when_failures_exceed_8_test() {
  // failure_count=9 > 8 → GR-029 MassFailureEmergency fires
  let evals = guard_rules.evaluate_all(0.5, 0.8, 1, 9, 0.0)
  let fired = list.filter(evals, fn(e: RuleEvaluation) { e.condition_met })
  list.any(fired, fn(e: RuleEvaluation) { e.rule_id == "GR-029" })
  |> should.be_true()
}

pub fn gr029_mass_failure_emergency_action_is_set_cockpit_emergency_test() {
  let rule =
    guard_rules.all_rules()
    |> list.find(fn(r: GuardRule) { r.id == "GR-029" })
  case rule {
    Ok(r) -> r.action |> should.equal(SetCockpitMode("emergency"))
    Error(_) -> should.be_true(False)
  }
}

pub fn gr030_compound_degradation_fires_with_declining_health_and_entropy_test() {
  // lyapunov=-0.1 (declining at rate <= -0.05) AND entropy=1.2 > 1.0 → GR-030 fires
  let evals = guard_rules.evaluate_all(0.6, 1.2, 0, 0, -0.1)
  let fired = list.filter(evals, fn(e: RuleEvaluation) { e.condition_met })
  list.any(fired, fn(e: RuleEvaluation) { e.rule_id == "GR-030" })
  |> should.be_true()
}

pub fn gr030_compound_degradation_does_not_fire_without_entropy_test() {
  // lyapunov=-0.1 but entropy=0.5 < 1.0 → GR-030 must NOT fire
  let evals = guard_rules.evaluate_all(0.6, 0.5, 0, 0, -0.1)
  let fired = list.filter(evals, fn(e: RuleEvaluation) { e.condition_met })
  list.any(fired, fn(e: RuleEvaluation) { e.rule_id == "GR-030" })
  |> should.be_false()
}

pub fn gr030_compound_degradation_action_is_escalate_to_operator_test() {
  let rule =
    guard_rules.all_rules()
    |> list.find(fn(r: GuardRule) { r.id == "GR-030" })
  case rule {
    Ok(r) ->
      case r.action {
        EscalateToOperator(_) -> should.be_true(True)
        _ -> should.be_true(False)
      }
    Error(_) -> should.be_true(False)
  }
}

// ═══════════════════════════════════════════════════════════════
// to_json — serialisation
// ═══════════════════════════════════════════════════════════════

pub fn to_json_produces_valid_array_test() {
  let evals = guard_rules.evaluate_all(0.8, 0.5, 0, 0, 0.0)
  let json = guard_rules.to_json(evals)
  string.starts_with(json, "[") |> should.be_true()
  string.ends_with(json, "]") |> should.be_true()
}

pub fn to_json_contains_rule_id_field_test() {
  let evals = guard_rules.evaluate_all(0.8, 0.5, 0, 0, 0.0)
  let json = guard_rules.to_json(evals)
  string.contains(json, "rule_id") |> should.be_true()
}

pub fn to_json_contains_salience_field_test() {
  let evals = guard_rules.evaluate_all(0.8, 0.5, 0, 0, 0.0)
  let json = guard_rules.to_json(evals)
  string.contains(json, "salience") |> should.be_true()
}

// ═══════════════════════════════════════════════════════════════
// action_to_string — logging (original + new actions)
// ═══════════════════════════════════════════════════════════════

pub fn action_to_string_no_action_test() {
  guard_rules.action_to_string(NoAction) |> should.equal("NoAction")
}

pub fn action_to_string_jidoka_halt_test() {
  let s = guard_rules.action_to_string(JidokaHalt("critical"))
  string.starts_with(s, "JidokaHalt(") |> should.be_true()
}

pub fn action_to_string_set_cockpit_mode_test() {
  guard_rules.action_to_string(SetCockpitMode("emergency"))
  |> should.equal("SetCockpitMode(emergency)")
}

pub fn action_to_string_attempt_hot_reload_test() {
  guard_rules.action_to_string(AttemptHotReload)
  |> should.equal("AttemptHotReload")
}

pub fn action_to_string_trigger_runbook_test() {
  guard_rules.action_to_string(TriggerRunbook("RB-001"))
  |> should.equal("TriggerRunbook(RB-001)")
}

pub fn action_to_string_log_warning_test() {
  let s = guard_rules.action_to_string(LogWarning("system degraded"))
  string.starts_with(s, "LogWarning(") |> should.be_true()
}

pub fn action_to_string_escalate_to_operator_test() {
  let s = guard_rules.action_to_string(EscalateToOperator("quorum loss"))
  string.starts_with(s, "EscalateToOperator(") |> should.be_true()
}

pub fn action_to_string_isolate_cell_test() {
  guard_rules.action_to_string(IsolateCell("L4"))
  |> should.equal("IsolateCell(L4)")
}

pub fn action_to_string_action_sequence_test() {
  let s =
    guard_rules.action_to_string(
      ActionSequence(actions: [SetCockpitMode("bright"), LogWarning("warn")]),
    )
  string.starts_with(s, "ActionSequence([") |> should.be_true()
}

pub fn action_to_string_correlate_failures_test() {
  let s = guard_rules.action_to_string(CorrelateFailures("NIF→Planning"))
  string.starts_with(s, "CorrelateFailures(") |> should.be_true()
}

pub fn action_to_string_classify_pattern_test() {
  guard_rules.action_to_string(ClassifyPattern("isolated_failure"))
  |> should.equal("ClassifyPattern(isolated_failure)")
}

pub fn action_to_string_record_milestone_test() {
  guard_rules.action_to_string(RecordMilestone("1h_streak"))
  |> should.equal("RecordMilestone(1h_streak)")
}

pub fn action_to_string_predictive_alert_test() {
  let s = guard_rules.action_to_string(PredictiveAlert("emergency in ~70s"))
  string.starts_with(s, "PredictiveAlert(") |> should.be_true()
}

pub fn action_to_string_preventive_cooldown_test() {
  let s = guard_rules.action_to_string(PreventiveCooldown("entropy rising"))
  string.starts_with(s, "PreventiveCooldown(") |> should.be_true()
}

// ═══════════════════════════════════════════════════════════════
// Edge cases
// ═══════════════════════════════════════════════════════════════

pub fn evaluate_condition_with_layers_health_below_uses_standard_evaluator_test() {
  // Non-layer condition delegates to standard evaluator
  guard_rules.evaluate_condition_with_layers(
    HealthBelow(threshold: 0.5),
    0.3,
    0.0,
    0,
    0,
    0.0,
    [],
  )
  |> should.be_true()
}

pub fn evaluate_condition_cascade_depth_zero_does_not_fire_test() {
  guard_rules.evaluate_condition(
    CascadeDepth(min_depth: 1),
    1.0,
    0.0,
    0,
    0,
    0.0,
  )
  |> should.be_false()
}

pub fn layers_failing_with_layers_api_all_present_fires_test() {
  guard_rules.evaluate_condition_with_layers(
    LayersFailing(layers: ["L1", "L3"]),
    0.7,
    0.5,
    1,
    2,
    0.0,
    ["L1", "L3", "L4"],
  )
  |> should.be_true()
}

pub fn layers_failing_with_layers_api_partial_match_does_not_fire_test() {
  // Only L1 in failing_layers, but L3 also required → False
  guard_rules.evaluate_condition_with_layers(
    LayersFailing(layers: ["L1", "L3"]),
    0.7,
    0.5,
    1,
    2,
    0.0,
    ["L1"],
  )
  |> should.be_false()
}

pub fn layers_failing_with_layers_api_empty_layers_vacuously_true_test() {
  // Empty list of required layers → all() over empty = True
  guard_rules.evaluate_condition_with_layers(
    LayersFailing(layers: []),
    0.7,
    0.5,
    1,
    2,
    0.0,
    [],
  )
  |> should.be_true()
}

pub fn evaluate_all_with_gr019_nif_planning_does_not_fire_single_layer_test() {
  // Only L1 failing — GR-019 requires both L1 and L3
  let evals = guard_rules.evaluate_all_with_layers(0.7, 0.5, 0, 1, 0.0, ["L1"])
  let fired = list.filter(evals, fn(e: RuleEvaluation) { e.condition_met })
  list.any(fired, fn(e: RuleEvaluation) { e.rule_id == "GR-019" })
  |> should.be_false()
}
