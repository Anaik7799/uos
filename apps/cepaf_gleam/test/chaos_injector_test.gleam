/// F10 — Chaos Injection Testing: 35 tests covering all public API functions.
/// STAMP: SC-CHAOS-001, SC-SIL4-001, SC-HA-001
/// Layer: L6_ECOSYSTEM
/// परित्राणाय साधूनां — For protection of the good (Gita 4.8)
import cepaf_gleam/testing/chaos_injector.{
  ChaosCritical, ChaosHigh, ChaosLow, ChaosMedium, ChaosScenario, CpuSaturation,
  KillProcess, LatencySpike, MemoryPressure, NetworkPartition, NifFailure,
  QuorumLoss, StaleData, ZenohDisconnect,
}
import gleam/list
import gleam/string
import gleeunit/should

// =============================================================================
// T01 — Catalogue completeness
// =============================================================================

pub fn all_scenarios_returns_at_least_20_test() {
  chaos_injector.all_scenarios()
  |> list.length
  |> fn(n) { n >= 20 }
  |> should.be_true()
}

pub fn scenario_count_matches_all_scenarios_test() {
  let direct = chaos_injector.all_scenarios() |> list.length
  chaos_injector.scenario_count() |> should.equal(direct)
}

pub fn scenario_count_is_21_test() {
  chaos_injector.scenario_count() |> should.equal(21)
}

// =============================================================================
// T02 — Layer coverage: every L0-L7 layer has at least one scenario
// =============================================================================

pub fn every_fractal_layer_has_at_least_one_scenario_test() {
  let layers = [
    "L0_CONSTITUTIONAL",
    "L1_ATOMIC_DEBUG",
    "L2_COMPONENT",
    "L3_TRANSACTION",
    "L4_SYSTEM",
    "L5_COGNITIVE",
    "L6_ECOSYSTEM",
    "L7_FEDERATION",
  ]
  list.all(layers, fn(layer) {
    chaos_injector.scenarios_for_layer(layer) |> list.length |> fn(n) { n > 0 }
  })
  |> should.be_true()
}

// =============================================================================
// T03 — Layer filter correctness
// =============================================================================

pub fn scenarios_for_layer_returns_only_matching_layer_test() {
  let target = "L6_ECOSYSTEM"
  let results = chaos_injector.scenarios_for_layer(target)
  list.all(results, fn(s) { s.layer == target })
  |> should.be_true()
}

pub fn scenarios_for_layer_unknown_returns_empty_test() {
  chaos_injector.scenarios_for_layer("L99_UNKNOWN")
  |> should.equal([])
}

pub fn l6_ecosystem_has_at_least_three_scenarios_test() {
  let n = chaos_injector.scenarios_for_layer("L6_ECOSYSTEM") |> list.length
  { n >= 3 } |> should.be_true()
}

// =============================================================================
// T04 — Severity filter
// =============================================================================

pub fn scenarios_for_severity_critical_not_empty_test() {
  chaos_injector.scenarios_for_severity(ChaosCritical)
  |> list.length
  |> fn(n) { n > 0 }
  |> should.be_true()
}

pub fn scenarios_for_severity_returns_only_matching_severity_test() {
  let results = chaos_injector.scenarios_for_severity(ChaosHigh)
  list.all(results, fn(s) { s.severity == ChaosHigh })
  |> should.be_true()
}

pub fn scenarios_for_severity_low_all_match_test() {
  let results = chaos_injector.scenarios_for_severity(ChaosLow)
  list.all(results, fn(s) { s.severity == ChaosLow })
  |> should.be_true()
}

// =============================================================================
// T05 — describe() format
// =============================================================================

pub fn describe_contains_medium_label_test() {
  let scenario =
    ChaosScenario(
      name: "med",
      description: "Medium scenario",
      layer: "L5_COGNITIVE",
      severity: ChaosMedium,
      injection: ZenohDisconnect,
    )
  let desc = chaos_injector.describe(scenario)
  string.contains(desc, "[MEDIUM]") |> should.be_true()
}

pub fn describe_contains_severity_label_test() {
  let scenario =
    ChaosScenario(
      name: "test-scenario",
      description: "A test chaos scenario",
      layer: "L4_SYSTEM",
      severity: ChaosCritical,
      injection: KillProcess(target: "app-1"),
    )
  let desc = chaos_injector.describe(scenario)
  string.contains(desc, "[CRITICAL]") |> should.be_true()
}

pub fn describe_contains_name_test() {
  let scenario =
    ChaosScenario(
      name: "zenoh-kill",
      description: "Kill Zenoh router",
      layer: "L6_ECOSYSTEM",
      severity: ChaosHigh,
      injection: ZenohDisconnect,
    )
  let desc = chaos_injector.describe(scenario)
  string.contains(desc, "zenoh-kill") |> should.be_true()
}

pub fn describe_contains_layer_test() {
  let scenario =
    ChaosScenario(
      name: "partition",
      description: "Network partition test",
      layer: "L7_FEDERATION",
      severity: ChaosMedium,
      injection: NetworkPartition(node: "node-1"),
    )
  let desc = chaos_injector.describe(scenario)
  string.contains(desc, "L7_FEDERATION") |> should.be_true()
}

// =============================================================================
// T06 — to_json() valid output
// =============================================================================

pub fn to_json_produces_non_empty_string_test() {
  let json_str = chaos_injector.to_json(chaos_injector.all_scenarios())
  { string.length(json_str) > 0 } |> should.be_true()
}

pub fn to_json_contains_name_field_test() {
  let json_str = chaos_injector.to_json(chaos_injector.all_scenarios())
  string.contains(json_str, "\"name\"") |> should.be_true()
}

pub fn to_json_contains_severity_field_test() {
  let json_str = chaos_injector.to_json(chaos_injector.all_scenarios())
  string.contains(json_str, "\"severity\"") |> should.be_true()
}

pub fn to_json_empty_list_produces_valid_json_test() {
  let json_str = chaos_injector.to_json([])
  json_str |> should.equal("[]")
}

// =============================================================================
// T07 — Analytics
// =============================================================================

pub fn severity_distribution_covers_all_tiers_test() {
  let dist = chaos_injector.severity_distribution()
  list.length(dist) |> should.equal(4)
}

pub fn layer_distribution_covers_all_eight_layers_test() {
  let dist = chaos_injector.layer_distribution()
  list.length(dist) |> should.equal(8)
}

pub fn max_severity_int_is_four_for_critical_test() {
  // ChaosCritical maps to 4 — the catalogue includes Critical scenarios
  chaos_injector.max_severity_int() |> should.equal(4)
}

pub fn guardian_required_scenarios_not_empty_test() {
  chaos_injector.guardian_required_scenarios()
  |> list.length
  |> fn(n) { n > 0 }
  |> should.be_true()
}

pub fn guardian_required_scenarios_all_high_or_critical_test() {
  let results = chaos_injector.guardian_required_scenarios()
  list.all(results, fn(s) {
    s.severity == ChaosCritical || s.severity == ChaosHigh
  })
  |> should.be_true()
}

pub fn injection_types_contains_all_ten_types_test() {
  let types = chaos_injector.injection_types()
  list.length(types) |> should.equal(10)
}

// =============================================================================
// T08 — Injection variant constructor sanity
// =============================================================================

pub fn kill_process_stores_target_test() {
  let KillProcess(t) = KillProcess(target: "my-container")
  t |> should.equal("my-container")
}

pub fn latency_spike_stores_ms_test() {
  let LatencySpike(ms) = LatencySpike(ms: 1234)
  ms |> should.equal(1234)
}

pub fn memory_pressure_stores_mb_test() {
  let MemoryPressure(mb) = MemoryPressure(mb: 512)
  mb |> should.equal(512)
}

pub fn stale_data_stores_age_seconds_test() {
  let StaleData(age_seconds) = StaleData(age_seconds: 3600)
  age_seconds |> should.equal(3600)
}

pub fn cpu_saturation_stores_percent_test() {
  let CpuSaturation(percent) = CpuSaturation(percent: 88)
  percent |> should.equal(88)
}

pub fn nif_failure_stores_nif_name_test() {
  let NifFailure(nif_name) = NifFailure(nif_name: "rule_engine_nif")
  nif_name |> should.equal("rule_engine_nif")
}

pub fn network_partition_stores_node_test() {
  let NetworkPartition(node) = NetworkPartition(node: "zenoh-router-2")
  node |> should.equal("zenoh-router-2")
}

// =============================================================================
// T09 — Determinism: all_scenarios() is pure and stable
// =============================================================================

pub fn all_scenarios_is_deterministic_test() {
  let first = chaos_injector.all_scenarios() |> list.length
  let second = chaos_injector.all_scenarios() |> list.length
  first |> should.equal(second)
}

// =============================================================================
// T10 — Every scenario has a non-empty name and description
// =============================================================================

pub fn all_scenarios_have_non_empty_names_test() {
  chaos_injector.all_scenarios()
  |> list.all(fn(s) { string.length(s.name) > 0 })
  |> should.be_true()
}

pub fn all_scenarios_have_non_empty_descriptions_test() {
  chaos_injector.all_scenarios()
  |> list.all(fn(s) { string.length(s.description) > 0 })
  |> should.be_true()
}

// =============================================================================
// T11 — L6 scenarios include Zenoh-critical failures
// =============================================================================

pub fn l6_includes_zenoh_disconnect_scenario_test() {
  let l6 = chaos_injector.scenarios_for_layer("L6_ECOSYSTEM")
  let has_zenoh_disconnect =
    list.any(l6, fn(s) {
      case s.injection {
        ZenohDisconnect -> True
        _ -> False
      }
    })
  has_zenoh_disconnect |> should.be_true()
}

pub fn l6_includes_quorum_loss_scenario_test() {
  let l6 = chaos_injector.scenarios_for_layer("L6_ECOSYSTEM")
  let has_quorum_loss =
    list.any(l6, fn(s) {
      case s.injection {
        QuorumLoss -> True
        _ -> False
      }
    })
  has_quorum_loss |> should.be_true()
}

// =============================================================================
// T12 — L0 scenarios include NIF failures (SC-NIF-001)
// =============================================================================

pub fn l0_includes_nif_failure_scenario_test() {
  let l0 = chaos_injector.scenarios_for_layer("L0_CONSTITUTIONAL")
  let has_nif =
    list.any(l0, fn(s) {
      case s.injection {
        NifFailure(_) -> True
        _ -> False
      }
    })
  has_nif |> should.be_true()
}

pub fn l0_scenarios_all_critical_test() {
  let l0 = chaos_injector.scenarios_for_layer("L0_CONSTITUTIONAL")
  list.all(l0, fn(s) { s.severity == ChaosCritical })
  |> should.be_true()
}

// =============================================================================
// T13 — severity_distribution totals match scenario_count
// =============================================================================

pub fn severity_distribution_total_matches_scenario_count_test() {
  let dist = chaos_injector.severity_distribution()
  let total = list.fold(dist, 0, fn(acc, pair) { acc + pair.1 })
  total |> should.equal(chaos_injector.scenario_count())
}

// =============================================================================
// T14 — layer_distribution totals match scenario_count
// =============================================================================

pub fn layer_distribution_total_matches_scenario_count_test() {
  let dist = chaos_injector.layer_distribution()
  let total = list.fold(dist, 0, fn(acc, pair) { acc + pair.1 })
  total |> should.equal(chaos_injector.scenario_count())
}

// =============================================================================
// T15 — injection_types() sorted unique list with no duplicates
// =============================================================================

pub fn injection_types_has_no_duplicates_test() {
  let types = chaos_injector.injection_types()
  let unique_count = types |> list.unique |> list.length
  unique_count |> should.equal(list.length(types))
}

// =============================================================================
// T16 — QuorumLoss unit variant roundtrip
// =============================================================================

pub fn quorum_loss_unit_variant_test() {
  let injection = QuorumLoss
  injection |> should.equal(QuorumLoss)
}
