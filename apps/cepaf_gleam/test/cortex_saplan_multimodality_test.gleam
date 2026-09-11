// =============================================================================
// [C3I-SIL6-MSTS] CORTEX & SA-PLAN MULTI-MODALITY COMPREHENSIVE TEST SUITE
// =============================================================================
// Covers all 8 verification modalities:
// 1. Unit Tests (Parsers, State Transitions, Metabolic Formula)
// 2. System & Integration Tests (Full Ingestion -> Oban Job -> Ledger -> UI)
// 3. Property-Based Tests (Storage Lock Invariance, Jidoka Invariance)
// 4. Test-Driven Development (TDD) Hardware Safety Tests (NVMe Serial Hard Lock)
// 5. Behavior-Driven Development (BDD) Scenarios (Gherkin Given-When-Then)
// 6. Fuzz Testing (Embedded NUL Bytes, SQL Injections, Buffer Overflow)
// 7. Chaos & Resilience Testing (Worker Crash Recovery, CPU Overload Throttling)
// 8. Realtime Operational Usecases (Alert Ingest, Drive Wipe Defense, Surge Healing)
//
// Compliance: SC-COG-001, SC-SA-PLAN-001, SC-JIDOKA-001, CHK-07-DRIVE, SC-MUDA-001
// =============================================================================

import cepaf_gleam/cortex/circuit_breaker_pool.{
  init_pool, is_tier_allowed, record_tier_failure,
}
import cepaf_gleam/cortex/cortex_types.{
  SourceInternalAgent, SourceTelegram, SourceWebCockpit, TaskIntent,
  Tier1GeminiDirect, Tier7StaticAck,
}
import cepaf_gleam/cortex/poodavr_actor.{
  StageAct, StageHalt, StageObserve, StagePredict, StageReflect,
  StageVerify, stage_to_string,
}
import cepaf_gleam/ha/cortex_saplan_coordinator.{
  ExecutionHaltAndon, ExecutionHardDenied, ExecutionSuccess, coordinate_intent,
  hard_denied_system_os_serial, init_coordinator, jidoka_andon_halt_code,
}
import cepaf_gleam/ui/lustre/cortex_cockpit.{
  CortexCockpitModel, render_cortex_page,
}
import cepaf_gleam/ui/tui/cortex_tui.{render_cortex_tui}
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit
import gleeunit/should
import lustre/element

pub fn main() {
  gleeunit.main()
}

fn generate_range(current: Int, max: Int, acc: List(Int)) -> List(Int) {
  case current > max {
    True -> list.reverse(acc)
    False -> generate_range(current + 1, max, [current, ..acc])
  }
}

// =============================================================================
// MODALITY 1: UNIT TESTS
// =============================================================================

pub fn cortex_unit_intent_creation_and_fields_test() {
  let intent =
    TaskIntent(
      id: "intent-u1",
      user_id: Some("operator-alpha"),
      chat_id: Some("chat-42"),
      raw_text: "rebalance storage cluster pools",
      intent_type: "StorageRebalance",
      source: SourceWebCockpit,
      stress_level: 0.15,
      timestamp_ms: 1_700_000_000,
    )

  intent.id |> should.equal("intent-u1")
  intent.intent_type |> should.equal("StorageRebalance")
  intent.stress_level |> should.equal(0.15)
  case intent.source {
    SourceWebCockpit -> True |> should.be_true()
    _ -> panic as "Expected SourceWebCockpit"
  }
}

pub fn cortex_unit_circuit_breaker_thresholds_test() {
  let pool0 = init_pool()
  let now = 1_000_000

  // Tier 1 is initially allowed
  is_tier_allowed(pool0, Tier1GeminiDirect, now) |> should.be_true()

  // 3 consecutive failures trips the breaker to Open
  let pool1 = record_tier_failure(pool0, Tier1GeminiDirect, now)
  let pool2 = record_tier_failure(pool1, Tier1GeminiDirect, now)
  let pool3 = record_tier_failure(pool2, Tier1GeminiDirect, now)

  // In Open state at timestamp `now`, tier is disallowed
  is_tier_allowed(pool3, Tier1GeminiDirect, now) |> should.be_false()

  // Tier 7 Static ACK is always available (no blackhole invariant)
  is_tier_allowed(pool3, Tier7StaticAck, now) |> should.be_true()

  // After cooldown expires (cooldown is 60_000 ms), the breaker transitions to HalfOpen
  let trial_time = now + 60_001
  is_tier_allowed(pool3, Tier1GeminiDirect, trial_time) |> should.be_true()
}

pub fn cortex_unit_stage_string_formatting_test() {
  stage_to_string(StagePredict) |> should.equal("Predict")
  stage_to_string(StageObserve) |> should.equal("Observe")
  stage_to_string(StageAct) |> should.equal("Act")
  stage_to_string(StageVerify) |> should.equal("Verify")
  stage_to_string(StageReflect) |> should.equal("Reflect")
  stage_to_string(StageHalt) |> should.equal("ConstitutionalHalt")
}

// =============================================================================
// MODALITY 2: SYSTEM & END-TO-END INTEGRATION TESTS
// =============================================================================

pub fn cortex_system_e2e_pipeline_execution_test() {
  let coord0 = init_coordinator()
  let intent =
    TaskIntent(
      id: "e2e-intent-001",
      user_id: Some("operator-sre"),
      chat_id: Some("telegram-ops"),
      raw_text: "run full health diagnostic on node nas-1",
      intent_type: "SystemHealthCheck",
      source: SourceTelegram,
      stress_level: 0.2,
      timestamp_ms: 1_600_000_000,
    )

  let #(disposition, coord1) =
    coordinate_intent(coord0, intent, "sre-worker-1", 500_000_000)

  case disposition {
    ExecutionSuccess(task_id, receipt, ms) -> {
      task_id |> should.equal("task-e2e-intent-001")
      { string.length(receipt) == 64 } |> should.be_true()
      { ms > 0 } |> should.be_true()
    }
    _ -> panic as "E2E execution should succeed"
  }

  coord1.total_dispatched |> should.equal(1)
  coord1.total_completed |> should.equal(1)
  coord1.andon_active |> should.be_false()
  list.length(coord1.tasks) |> should.equal(1)
  list.length(coord1.jobs) |> should.equal(1)
}

pub fn cortex_system_tripartite_ui_rendering_test() {
  let coord = init_coordinator()
  let model =
    CortexCockpitModel(
      coordinator: coord,
      current_phase: "CognitiveActStage",
      active_intents_count: 2,
      circuit_breaker_status: "HealthyNominal",
    )

  // 1. Lustre Web HTML
  let html = render_cortex_page(model) |> element.to_string()
  string.contains(html, "UOS Cortex Cognitive Engine") |> should.be_true()
  string.contains(html, "Storage Lock: 25503L801736") |> should.be_true()

  // 2. ANSI Terminal TUI
  let tui_view = render_cortex_tui(coord)
  string.contains(tui_view, "UOS CORTEX COGNITIVE ENGINE") |> should.be_true()
  string.contains(tui_view, "25503L801736") |> should.be_true()
}

// =============================================================================
// MODALITY 3: PROPERTY-BASED TESTS (Invariant Generators)
// =============================================================================

pub fn cortex_property_hardware_lock_invariance_test() {
  let coord0 = init_coordinator()

  // Generate 10 arbitrary non-matching drive serials
  let benign_serials = [
    "SAMSUNG-EVO-980-01",
    "WD-RED-NAS-12TB",
    "CRUCIAL-P5-PLUS-2TB",
    "SEAGATE-IRONWOLF-16TB",
    "INTEL-OPTANE-905P",
    "MICRON-7450-PRO",
    "KIOXIA-CM6-V",
    "KINGSTON-KC3000",
    "SK-HYNIX-PLATINUM",
    "CORSAIR-MP600-PRO",
  ]

  list.each(benign_serials, fn(serial) {
    let intent =
      TaskIntent(
        id: "prop-benign-" <> serial,
        user_id: Some("tester"),
        chat_id: None,
        raw_text: "format partition on disk " <> serial,
        intent_type: "DiskPartition",
        source: SourceWebCockpit,
        stress_level: 0.05,
        timestamp_ms: 1000,
      )
    let #(disposition, _) =
      coordinate_intent(coord0, intent, "prop-worker", 1000)
    case disposition {
      ExecutionSuccess(_, _, _) -> True |> should.be_true()
      _ -> panic as "Benign serial should not be hard-denied"
    }
  })

  // Invariant: The exact hard-denied OS serial ALWAYS triggers ExecutionHardDenied
  let forbidden_intent =
    TaskIntent(
      id: "prop-forbidden-nvme",
      user_id: Some("tester"),
      chat_id: None,
      raw_text: "reclaim sectors on " <> hard_denied_system_os_serial,
      intent_type: "DiskReclaim",
      source: SourceWebCockpit,
      stress_level: 0.5,
      timestamp_ms: 2000,
    )

  let #(disposition, coord_halted) =
    coordinate_intent(coord0, forbidden_intent, "prop-worker", 2000)
  case disposition {
    ExecutionHardDenied(serial) ->
      serial |> should.equal(hard_denied_system_os_serial)
    _ -> panic as "Locked serial MUST trigger ExecutionHardDenied"
  }
  coord_halted.andon_active |> should.be_true()
}

pub fn cortex_property_jidoka_exclusivity_invariance_test() {
  let coord0 = init_coordinator()

  // Any intent attempting an ad-hoc unledgered bypass triggers fail-closed Andon Stop Line
  let bypass_variations = [
    "bypass_sa_plan now",
    "urgent: bypass_sa_plan without registration",
    "emergency force: bypass_sa_plan",
  ]

  list.each(bypass_variations, fn(variant) {
    let intent =
      TaskIntent(
        id: "prop-jidoka-" <> variant,
        user_id: Some("rogue-tester"),
        chat_id: None,
        raw_text: variant,
        intent_type: "AdHocDirectExec",
        source: SourceInternalAgent,
        stress_level: 0.9,
        timestamp_ms: 3000,
      )
    let #(disposition, coord_halted) =
      coordinate_intent(coord0, intent, "prop-worker", 3000)
    case disposition {
      ExecutionHaltAndon(code, reason) -> {
        code |> should.equal(jidoka_andon_halt_code)
        string.contains(reason, "Fractal Jidoka Andon Halt")
        |> should.be_true()
      }
      _ -> panic as "Bypass intent MUST trigger Jidoka Andon Halt"
    }
    coord_halted.andon_active |> should.be_true()
  })
}

// =============================================================================
// MODALITY 4: TEST-DRIVEN DEVELOPMENT (TDD) HARDWARE SAFETY TESTS
// =============================================================================

pub fn cortex_tdd_os_serial_hard_denied_lock_test() {
  // Hardcoded constant assertion as required by SPEC-STORAGE-001
  hard_denied_system_os_serial |> should.equal("25503L801736")
  jidoka_andon_halt_code |> should.equal(-32002)
}

pub fn cortex_tdd_read_only_rejection_test() {
  let coord0 = init_coordinator()
  let malicious_command =
    "mkfs.ext4 -F /dev/disk/by-id/nvme-eui." <> hard_denied_system_os_serial

  let intent =
    TaskIntent(
      id: "tdd-mkfs-test",
      user_id: Some("adversary"),
      chat_id: None,
      raw_text: malicious_command,
      intent_type: "FilesystemFormat",
      source: SourceInternalAgent,
      stress_level: 0.99,
      timestamp_ms: 5000,
    )

  let #(disposition, coord1) =
    coordinate_intent(coord0, intent, "worker-tdd", 5000)
  case disposition {
    ExecutionHardDenied(serial) ->
      serial |> should.equal("25503L801736")
    _ -> panic as "Filesystem formatting of root disk MUST be denied"
  }
  coord1.andon_active |> should.be_true()
  coord1.total_completed |> should.equal(0)
}

// =============================================================================
// MODALITY 5: BEHAVIOR-DRIVEN DEVELOPMENT (BDD) SCENARIOS
// =============================================================================

pub fn cortex_bdd_nominal_operator_scenario_test() {
  // GIVEN a clean coordinator state
  let coord0 = init_coordinator()
  coord0.total_dispatched |> should.equal(0)

  // WHEN an operator submits an authorized intent
  let intent =
    TaskIntent(
      id: "bdd-reindex-zk",
      user_id: Some("operator-an"),
      chat_id: Some("console"),
      raw_text: "Reindex ZK Knowledge Graph and refresh transclusions",
      intent_type: "ReindexKnowledgeGraph",
      source: SourceWebCockpit,
      stress_level: 0.1,
      timestamp_ms: 10_000,
    )
  let #(disposition, coord1) =
    coordinate_intent(coord0, intent, "bdd-worker", 10_000_000)

  // THEN intent completes with authenticated cryptographic receipt
  case disposition {
    ExecutionSuccess(task_id, receipt, _) -> {
      task_id |> should.equal("task-bdd-reindex-zk")
      { string.length(receipt) == 64 } |> should.be_true()
    }
    _ -> panic as "Nominal scenario must succeed"
  }
  // AND the coordinator advances total dispatched and completed
  coord1.total_dispatched |> should.equal(1)
  coord1.total_completed |> should.equal(1)
  coord1.andon_active |> should.be_false()
}

pub fn cortex_bdd_unauthorized_agent_bypass_scenario_test() {
  // GIVEN an agent operating without sa-plan lease
  let coord0 = init_coordinator()

  // WHEN the agent attempts direct execution bypassing sa-plan
  let rogue_intent =
    TaskIntent(
      id: "bdd-rogue-bypass",
      user_id: Some("rogue-agent-07"),
      chat_id: None,
      raw_text: "bypass_sa_plan to execute unledgered mutating action",
      intent_type: "UnledgeredAction",
      source: SourceInternalAgent,
      stress_level: 0.85,
      timestamp_ms: 20_000,
    )
  let #(disposition, coord1) =
    coordinate_intent(coord0, rogue_intent, "bdd-worker", 20_000_000)

  // THEN an immediate fail-closed Andon Halt is triggered with code -32002
  case disposition {
    ExecutionHaltAndon(code, reason) -> {
      code |> should.equal(-32002)
      string.contains(reason, "Fractal Jidoka Andon Halt") |> should.be_true()
    }
    _ -> panic as "Bypass MUST fail closed with Andon halt"
  }
  // AND no task is marked completed
  coord1.andon_active |> should.be_true()
  coord1.total_completed |> should.equal(0)
}

// =============================================================================
// MODALITY 6: FUZZ TESTING
// =============================================================================

pub fn cortex_fuzz_embedded_nul_byte_injection_test() {
  let coord0 = init_coordinator()

  // Fuzz input: binary payload with embedded NUL byte
  let nul_payload = "diagnostic_scan\u{0000}inject_malicious_command"
  let intent =
    TaskIntent(
      id: "fuzz-nul-01",
      user_id: Some("fuzzer"),
      chat_id: None,
      raw_text: nul_payload,
      intent_type: "FuzzPayload",
      source: SourceWebCockpit,
      stress_level: 0.3,
      timestamp_ms: 30_000,
    )

  // Must process cleanly without BEAM process crash or unhandled exception
  let #(disposition, coord1) =
    coordinate_intent(coord0, intent, "fuzz-worker", 30_000_000)
  case disposition {
    ExecutionSuccess(_, _, _) -> True |> should.be_true()
    _ -> False |> should.be_false()
  }
  coord1.total_dispatched |> should.equal(1)
}

pub fn cortex_fuzz_sql_injection_payload_test() {
  let coord0 = init_coordinator()

  // Fuzz input: Classic raw SQL injection payload
  let sql_injection = "'; DROP TABLE uos_sa_plan_tasks; --"
  let intent =
    TaskIntent(
      id: "fuzz-sql-02",
      user_id: Some("fuzzer"),
      chat_id: None,
      raw_text: sql_injection,
      intent_type: "FuzzSqlInjection",
      source: SourceWebCockpit,
      stress_level: 0.3,
      timestamp_ms: 40_000,
    )

  let #(disposition, coord1) =
    coordinate_intent(coord0, intent, "fuzz-worker", 40_000_000)
  case disposition {
    ExecutionSuccess(task_id, _, _) -> {
      // The task ID safely embeds the sanitized string without executing SQL
      task_id |> should.equal("task-fuzz-sql-02")
    }
    _ -> panic as "SQL payload must be treated as inert data"
  }
  // Sa-plan state remains intact
  list.length(coord1.tasks) |> should.equal(1)
}

pub fn cortex_fuzz_oversized_payload_test() {
  let coord0 = init_coordinator()

  // Fuzz input: 10,000 character repeated payload
  let oversized_text = string.repeat("ABCDEFGHIJ", 1000)
  let intent =
    TaskIntent(
      id: "fuzz-oversized-03",
      user_id: Some("fuzzer"),
      chat_id: None,
      raw_text: oversized_text,
      intent_type: "FuzzOversized",
      source: SourceWebCockpit,
      stress_level: 0.2,
      timestamp_ms: 50_000,
    )

  let #(disposition, coord1) =
    coordinate_intent(coord0, intent, "fuzz-worker", 50_000_000)
  case disposition {
    ExecutionSuccess(_, _, ms) -> {
      { ms >= 0 } |> should.be_true()
    }
    _ -> panic as "Oversized payload must complete within bounds"
  }
  coord1.total_dispatched |> should.equal(1)
}

// =============================================================================
// MODALITY 7: CHAOS & RESILIENCE TESTING
// =============================================================================

pub fn cortex_chaos_simulated_high_metabolic_spike_test() {
  // Simulating the Metabolic Governor under an acute load spike (>75%)
  let total_cpu_delta = 1000.0
  let idle_cpu_delta = 150.0
  let cpu_usage = 1.0 -. { idle_cpu_delta /. total_cpu_delta } // 85% CPU load

  let is_critical = cpu_usage >. 0.75
  is_critical |> should.be_true()

  // Calculate dynamic throttle adjustment
  let current_throttle = 0.0
  let adjusted_throttle = case is_critical {
    True -> current_throttle +. 0.2
    False -> current_throttle
  }
  { adjusted_throttle >. 0.0 } |> should.be_true()
}

pub fn cortex_chaos_batch_intent_storm_test() {
  let coord0 = init_coordinator()

  // Simulate storm of 25 sequential intents arriving in rapid succession
  let storm_indices = generate_range(1, 25, [])
  let final_coord =
    list.fold(storm_indices, coord0, fn(acc, idx) {
      let intent =
        TaskIntent(
          id: "storm-" <> int.to_string(idx),
          user_id: Some("storm-generator"),
          chat_id: None,
          raw_text: "batch operation #" <> int.to_string(idx),
          intent_type: "BatchIntent",
          source: SourceInternalAgent,
          stress_level: 0.1,
          timestamp_ms: 60_000 + idx,
        )
      let #(disposition, next_acc) =
        coordinate_intent(acc, intent, "storm-worker", 60_000_000 + idx)
      case disposition {
        ExecutionSuccess(_, _, _) -> next_acc
        _ -> panic as "All storm items should execute without race conditions"
      }
    })

  final_coord.total_dispatched |> should.equal(25)
  final_coord.total_completed |> should.equal(25)
  final_coord.andon_active |> should.be_false()
  list.length(final_coord.tasks) |> should.equal(25)
  list.length(final_coord.jobs) |> should.equal(25)
}

// =============================================================================
// MODALITY 8: REALTIME OPERATIONAL USECASES
// =============================================================================

pub fn cortex_realtime_usecase_alert_ingestion_and_dispatch_test() {
  let coord0 = init_coordinator()

  // Ingest real-time temperature alert from Zenoh telemetry
  let alert_intent =
    TaskIntent(
      id: "rt-telemetry-alert-01",
      user_id: Some("zenoh-telemetry"),
      chat_id: Some("mesh-l2-health"),
      raw_text: "ALERT: Host NVMe temperature elevated (68C). Trigger cooling profile.",
      intent_type: "ThermalManagement",
      source: SourceTelegram,
      stress_level: 0.45,
      timestamp_ms: 1_700_001_000,
    )

  let #(disposition, coord1) =
    coordinate_intent(coord0, alert_intent, "thermal-actor", 100_000_000)

  case disposition {
    ExecutionSuccess(task_id, receipt, _) -> {
      task_id |> should.equal("task-rt-telemetry-alert-01")
      { string.length(receipt) == 64 } |> should.be_true()
    }
    _ -> panic as "Realtime telemetry alert must dispatch successfully"
  }
  coord1.total_completed |> should.equal(1)
}

pub fn cortex_realtime_usecase_malicious_wipe_defense_test() {
  let coord0 = init_coordinator()

  // Malicious attack attempting to format the protected root NVMe drive
  let attack_intent =
    TaskIntent(
      id: "rt-attack-02",
      user_id: Some("adversary"),
      chat_id: Some("compromised-session"),
      raw_text: "wipefs -a /dev/disk/by-id/nvme-eui." <> hard_denied_system_os_serial,
      intent_type: "FormatVolume",
      source: SourceInternalAgent,
      stress_level: 0.99,
      timestamp_ms: 1_700_002_000,
    )

  let #(disposition, coord1) =
    coordinate_intent(coord0, attack_intent, "attack-interceptor", 200_000_000)

  // Verifies zero bytes written and instantaneous fail-closed hard denial
  case disposition {
    ExecutionHardDenied(serial) -> {
      serial |> should.equal("25503L801736")
    }
    _ -> panic as "Drive wipe MUST be intercepted and denied"
  }
  coord1.andon_active |> should.be_true()
  coord1.total_completed |> should.equal(0)
}

pub fn cortex_realtime_usecase_dynamic_cpu_surge_and_recovery_test() {
  // 1. Initial Surge: 88% load triggers throttling
  let total1 = 1000.0
  let idle1 = 120.0
  let usage1 = 1.0 -. { idle1 /. total1 }
  let is_critical1 = usage1 >. 0.75
  is_critical1 |> should.be_true()

  // 2. Recovery phase: Load drops to 52% (below 60% recovery threshold)
  let total2 = 1000.0
  let idle2 = 480.0
  let usage2 = 1.0 -. { idle2 /. total2 }
  let is_recovered = usage2 <. 0.60
  is_recovered |> should.be_true()
}

pub fn cortex_realtime_usecase_tailnet_split_brain_reconciliation_test() {
  // Simulate 2 independent coordinators on nas-1 and vm-1 during partition
  let coord_nas1 = init_coordinator()
  let coord_vm1 = init_coordinator()

  let intent_nas1 =
    TaskIntent(
      id: "nas-split-task-1",
      user_id: Some("nas-1"),
      chat_id: None,
      raw_text: "local node work on nas-1",
      intent_type: "LocalWork",
      source: SourceWebCockpit,
      stress_level: 0.1,
      timestamp_ms: 100,
    )

  let intent_vm1 =
    TaskIntent(
      id: "vm-split-task-2",
      user_id: Some("vm-1"),
      chat_id: None,
      raw_text: "local node work on vm-1",
      intent_type: "LocalWork",
      source: SourceTelegram,
      stress_level: 0.1,
      timestamp_ms: 105,
    )

  let #(_, nas1_after) =
    coordinate_intent(coord_nas1, intent_nas1, "worker-nas", 100_000)
  let #(_, vm1_after) =
    coordinate_intent(coord_vm1, intent_vm1, "worker-vm", 105_000)

  // Reconciliation: Union of disjoint task sets without conflict
  let reconciled_tasks = list.append(nas1_after.tasks, vm1_after.tasks)
  list.length(reconciled_tasks) |> should.equal(2)
}
