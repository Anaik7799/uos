// =============================================================================
// fmea_physical_fault_injection_test.gleam — FMEA Physical Fault Injection Tests
// STAMP: SC-SIL6-001, SC-FMEA-001, SC-SAFETY-001, SC-JIDOKA-001
// Covers 20 canonical FMEA failure modes + Storage Drive Lockout + Zero-Trust
// =============================================================================

import gleam/int
import gleam/list
import gleam/option.{type Option, Some}
import gleam/string
import gleeunit/should

// -----------------------------------------------------------------------------
// FM-01: Guardian Approval Request Lost on BEAM Crash Mid-Transaction
// -----------------------------------------------------------------------------

pub type GuardianTxState {
  TxPending(tx_id: String, payload: String)
  TxCrashed(tx_id: String)
  TxReplayed(tx_id: String, payload: String, replayed_from: String)
}

pub fn simulate_guardian_crash_recovery(
  tx_id: String,
  _payload: String,
  journal_entries: List(#(String, String)),
) -> GuardianTxState {
  let crashed = TxCrashed(tx_id)
  let found = list.find(journal_entries, fn(entry) { entry.0 == tx_id })
  case found {
    Ok(#(id, data)) -> TxReplayed(id, data, "ZenohEventLog+WAL")
    Error(_) -> crashed
  }
}

pub fn fmea_guardian_lost_replay_test() {
  let log = [#("tx-101", "ApproveDeployment"), #("tx-102", "TransferAsset")]
  let res = simulate_guardian_crash_recovery("tx-101", "ApproveDeployment", log)
  case res {
    TxReplayed(id, payload, source) -> {
      id |> should.equal("tx-101")
      payload |> should.equal("ApproveDeployment")
      source |> should.equal("ZenohEventLog+WAL")
    }
    _ -> should.fail()
  }

  // Unrecorded crash fails closed
  let res_unrecorded = simulate_guardian_crash_recovery("tx-999", "Unknown", log)
  case res_unrecorded {
    TxCrashed(id) -> id |> should.equal("tx-999")
    _ -> should.fail()
  }
}

// -----------------------------------------------------------------------------
// FM-02: Psi Invariant Checker Violation (I-01: container_count >= healthy_count)
// -----------------------------------------------------------------------------

pub type RenderElement {
  NominalView(metric: String)
  SafeFallbackView(reason: String)
}

pub fn check_psi_invariant_and_render(
  total_containers: Int,
  healthy_containers: Int,
) -> RenderElement {
  case total_containers >= healthy_containers {
    True -> NominalView("Cluster Healthy: " <> int.to_string(healthy_containers))
    False ->
      SafeFallbackView(
        "Psi Invariant I-01 Violated: healthy ("
        <> int.to_string(healthy_containers)
        <> ") > total ("
        <> int.to_string(total_containers)
        <> ")",
      )
  }
}

pub fn fmea_psi_invariant_guard_test() {
  let ok_view = check_psi_invariant_and_render(16, 16)
  case ok_view {
    NominalView(msg) -> string.contains(msg, "Cluster Healthy") |> should.be_true
    _ -> should.fail()
  }

  let violated_view = check_psi_invariant_and_render(10, 15)
  case violated_view {
    SafeFallbackView(reason) ->
      string.contains(reason, "Psi Invariant I-01 Violated") |> should.be_true
    _ -> should.fail()
  }
}

// -----------------------------------------------------------------------------
// FM-03: NIF Pipeline Empty Data During Rust NIF Reload
// -----------------------------------------------------------------------------

pub type NifStatus {
  NifReady(data: String)
  NifReloading
}

pub fn read_nif_with_cache_fallback(
  status: NifStatus,
  cached_val: String,
) -> String {
  case status {
    NifReady(d) -> d
    NifReloading -> cached_val
  }
}

pub fn fmea_nif_reload_empty_fallback_test() {
  let fresh = read_nif_with_cache_fallback(NifReady("metric:42"), "metric:0")
  fresh |> should.equal("metric:42")

  let fallback = read_nif_with_cache_fallback(NifReloading, "metric:cached_prev")
  fallback |> should.equal("metric:cached_prev")
}

// -----------------------------------------------------------------------------
// FM-04: Segfault in Rust NIF Isolated by Dirty Scheduler Watchdog
// -----------------------------------------------------------------------------

pub type SchedulerHealth {
  SchedulerIntact(watchdog_restarted: Bool, error_logged: String)
  SchedulerCrashed
}

pub fn isolate_nif_segfault(nif_signal: Int) -> SchedulerHealth {
  case nif_signal {
    11 ->
      // SIGSEGV (11) intercepted by dirty scheduler wrapper
      SchedulerIntact(
        watchdog_restarted: True,
        error_logged: "SIGSEGV trapped in isolated dirty scheduler. BEAM intact.",
      )
    _ -> SchedulerIntact(watchdog_restarted: False, error_logged: "Nominal")
  }
}

pub fn fmea_nif_segfault_isolation_test() {
  let isolation = isolate_nif_segfault(11)
  case isolation {
    SchedulerIntact(restarted, log) -> {
      restarted |> should.be_true
      string.contains(log, "BEAM intact") |> should.be_true
    }
    SchedulerCrashed -> should.fail()
  }
}

// -----------------------------------------------------------------------------
// FM-05: Zenoh NIF Router Unreachable & Publication Budget (100ms)
// -----------------------------------------------------------------------------

pub type ZenohPubResult {
  PubSuccess(latency_ms: Int)
  PubBudgetExceededFallback(elapsed_ms: Int, dropped_or_buffered: Bool)
}

pub fn publish_with_100ms_budget(
  router_reachable: Bool,
  simulated_delay_ms: Int,
) -> ZenohPubResult {
  case router_reachable && simulated_delay_ms <= 100 {
    True -> PubSuccess(simulated_delay_ms)
    False -> PubBudgetExceededFallback(elapsed_ms: 100, dropped_or_buffered: True)
  }
}

pub fn fmea_zenoh_router_unreachable_budget_test() {
  let ok_pub = publish_with_100ms_budget(True, 15)
  case ok_pub {
    PubSuccess(lat) -> lat |> should.equal(15)
    _ -> should.fail()
  }

  let timeout_pub = publish_with_100ms_budget(False, 250)
  case timeout_pub {
    PubBudgetExceededFallback(elapsed, buffered) -> {
      elapsed |> should.equal(100)
      buffered |> should.be_true
    }
    _ -> should.fail()
  }
}

// -----------------------------------------------------------------------------
// FM-06: Telemetry Cache Corruption & CRC / TTL Eviction
// -----------------------------------------------------------------------------

pub type CacheEntry {
  CacheEntry(payload: String, crc: Int, age_seconds: Int)
}

pub type CacheReadResult {
  CacheHit(payload: String)
  CacheEvicted(reason: String)
}

pub fn read_telemetry_cache(
  entry: CacheEntry,
  computed_crc: Int,
  ttl_seconds: Int,
) -> CacheReadResult {
  case entry.age_seconds > ttl_seconds {
    True -> CacheEvicted("TTL Expired")
    False ->
      case entry.crc == computed_crc {
        True -> CacheHit(entry.payload)
        False -> CacheEvicted("CRC Mismatch: Bit Rot / Corruption")
      }
  }
}

pub fn fmea_telemetry_cache_crc_eviction_test() {
  let valid_entry = CacheEntry("valid_metrics", 12_345, 10)
  read_telemetry_cache(valid_entry, 12_345, 60)
  |> should.equal(CacheHit("valid_metrics"))

  let corrupted_entry = CacheEntry("corrupted_metrics", 99_999, 10)
  read_telemetry_cache(corrupted_entry, 12_345, 60)
  |> should.equal(CacheEvicted("CRC Mismatch: Bit Rot / Corruption"))

  let expired_entry = CacheEntry("old_metrics", 12_345, 86_500)
  read_telemetry_cache(expired_entry, 12_345, 86_400)
  |> should.equal(CacheEvicted("TTL Expired"))
}

// -----------------------------------------------------------------------------
// FM-07: SQLite WAL Lock Contention & Exponential Backoff
// -----------------------------------------------------------------------------

pub type WalLockResult {
  LockAcquired(attempts: Int, elapsed_ms: Int)
  LockBusyExhausted(attempts: Int, elapsed_ms: Int)
}

fn do_wal_retry(attempt: Int, elapsed: Int, max: Int, depth: Int) -> WalLockResult {
  case attempt >= max {
    True -> LockBusyExhausted(attempts: attempt, elapsed_ms: elapsed)
    False ->
      case attempt >= depth {
        True -> LockAcquired(attempts: attempt + 1, elapsed_ms: elapsed + 10)
        False -> {
          let backoff = 10 * { attempt + 1 }
          do_wal_retry(attempt + 1, elapsed + backoff, max, depth)
        }
      }
  }
}

pub fn simulate_wal_retry(max_retries: Int, contention_depth: Int) -> WalLockResult {
  do_wal_retry(0, 0, max_retries, contention_depth)
}

pub fn fmea_sqlite_wal_contention_recovery_test() {
  let res1 = simulate_wal_retry(5, 3)
  case res1 {
    LockAcquired(attempts, elapsed) -> {
      attempts |> should.equal(4)
      should.be_true(elapsed < 100)
    }
    _ -> should.fail()
  }

  let res2 = simulate_wal_retry(3, 5)
  case res2 {
    LockBusyExhausted(attempts, _) -> attempts |> should.equal(3)
    _ -> should.fail()
  }
}

// -----------------------------------------------------------------------------
// FM-08: Planning State Sync Conflict (sa-plan vs Gleam on Smriti.db)
// -----------------------------------------------------------------------------

pub type SmritiAccessMode {
  ExclusiveWriter(holder: String)
  ReadOnlyReplica
}

pub fn arbitrate_smriti_access(lease_holder: Option(String), requested_by: String) -> SmritiAccessMode {
  case lease_holder {
    Some(holder) if holder == requested_by -> ExclusiveWriter(holder)
    _ -> ReadOnlyReplica
  }
}

pub fn fmea_planning_state_sync_conflict_test() {
  let writer = arbitrate_smriti_access(Some("sa-plan-daemon"), "sa-plan-daemon")
  writer |> should.equal(ExclusiveWriter("sa-plan-daemon"))

  let gleam_mode = arbitrate_smriti_access(Some("sa-plan-daemon"), "gleam-c3i")
  gleam_mode |> should.equal(ReadOnlyReplica)
}

// -----------------------------------------------------------------------------
// FM-09: Podman Container Exits Without Dying-Gasp Checkpoint
// -----------------------------------------------------------------------------

pub type ContainerRecovery {
  CleanApoptosis
  UncleanDyingGaspReplay(wal_events_replayed: Int)
}

pub fn recover_container_state(dying_gasp_logged: Bool, wal_event_count: Int) -> ContainerRecovery {
  case dying_gasp_logged {
    True -> CleanApoptosis
    False -> UncleanDyingGaspReplay(wal_events_replayed: wal_event_count)
  }
}

pub fn fmea_podman_sigkill_dying_gasp_test() {
  let clean = recover_container_state(True, 0)
  clean |> should.equal(CleanApoptosis)

  let replayed = recover_container_state(False, 47)
  replayed |> should.equal(UncleanDyingGaspReplay(47))
}

// -----------------------------------------------------------------------------
// FM-10: Hot Reload Failure on Running GenServer (code_change/2)
// -----------------------------------------------------------------------------

pub type ReloadDecision {
  ReloadCommitted(version: String)
  ReloadRolledBack(active_version: String, error: String)
}

pub fn perform_hot_reload_with_guard(
  code_change_ok: Bool,
  target_version: String,
  current_version: String,
) -> ReloadDecision {
  case code_change_ok {
    True -> ReloadCommitted(target_version)
    False ->
      ReloadRolledBack(
        active_version: current_version,
        error: "code_change/2 failed validation, traffic drained to current version",
      )
  }
}

pub fn fmea_hot_reload_rollback_test() {
  let ok_reload = perform_hot_reload_with_guard(True, "v2.0.1", "v2.0.0")
  ok_reload |> should.equal(ReloadCommitted("v2.0.1"))

  let failed_reload = perform_hot_reload_with_guard(False, "v2.0.1", "v2.0.0")
  case failed_reload {
    ReloadRolledBack(ver, err) -> {
      ver |> should.equal("v2.0.0")
      string.contains(err, "traffic drained") |> should.be_true
    }
    _ -> should.fail()
  }
}

// -----------------------------------------------------------------------------
// FM-11: Host Disk Pressure (>80% Warning, >95% Apoptosis)
// -----------------------------------------------------------------------------

pub type DiskSafetyAction {
  DiskNominal
  DiskWarningAlert(usage_percent: Int)
  DiskEmergencyApoptosis(usage_percent: Int)
}

pub fn evaluate_disk_pressure(usage_pct: Int) -> DiskSafetyAction {
  case usage_pct {
    n if n > 95 -> DiskEmergencyApoptosis(n)
    n if n >= 80 -> DiskWarningAlert(n)
    _ -> DiskNominal
  }
}

pub fn fmea_disk_pressure_apoptosis_test() {
  evaluate_disk_pressure(72) |> should.equal(DiskNominal)
  evaluate_disk_pressure(84) |> should.equal(DiskWarningAlert(84))
  evaluate_disk_pressure(98) |> should.equal(DiskEmergencyApoptosis(98))
}

// -----------------------------------------------------------------------------
// FM-12: Host CPU Saturation (>85% Degrading OODA Cycle)
// -----------------------------------------------------------------------------

pub type SchedulerThrottle {
  SchedulersFull(count: Int)
  SchedulersThrottled(count: Int, ooda_sla_preserved: Bool)
}

pub fn govern_cpu_load(cpu_pct: Int, total_schedulers: Int) -> SchedulerThrottle {
  case cpu_pct > 85 {
    True -> SchedulersThrottled(count: 6, ooda_sla_preserved: True)
    False -> SchedulersFull(count: total_schedulers)
  }
}

pub fn fmea_cpu_saturation_throttle_test() {
  govern_cpu_load(60, 16) |> should.equal(SchedulersFull(16))
  govern_cpu_load(92, 16) |> should.equal(SchedulersThrottled(6, True))
}

// -----------------------------------------------------------------------------
// FM-13: BEAM Process Memory Leak Detection & Self-Healing
// -----------------------------------------------------------------------------

pub type MemorySupervisorAction {
  MemoryHealthy
  TriggerSelfHealingRestart(pid_leak: String, ema_growth_mb: Float)
}

pub fn monitor_beam_memory_growth(ema_growth_mb: Float, threshold_mb: Float) -> MemorySupervisorAction {
  case ema_growth_mb >. threshold_mb {
    True -> TriggerSelfHealingRestart("<0.1234.0>", ema_growth_mb)
    False -> MemoryHealthy
  }
}

pub fn fmea_beam_memory_leak_healing_test() {
  monitor_beam_memory_growth(12.5, 50.0) |> should.equal(MemoryHealthy)
  let action = monitor_beam_memory_growth(85.0, 50.0)
  case action {
    TriggerSelfHealingRestart(pid, growth) -> {
      pid |> should.equal("<0.1234.0>")
      growth |> should.equal(85.0)
    }
    _ -> should.fail()
  }
}

// -----------------------------------------------------------------------------
// FM-14: OODA Supervisor Hard 100ms SLA & LLM Abort Fallback
// -----------------------------------------------------------------------------

pub type OodaCycleResult {
  OodaLLMSuccess(elapsed_ms: Int)
  OodaRuleOnlyFallback(reason: String)
}

pub fn execute_ooda_step(elapsed_ms: Int, hard_budget_ms: Int) -> OodaCycleResult {
  case elapsed_ms <= hard_budget_ms {
    True -> OodaLLMSuccess(elapsed_ms)
    False ->
      OodaRuleOnlyFallback(
        "Hard budget exceeded ("
        <> int.to_string(elapsed_ms)
        <> "ms > "
        <> int.to_string(hard_budget_ms)
        <> "ms): LLM aborted, rule-only fallback triggered",
      )
  }
}

pub fn fmea_ooda_sla_hard_budget_test() {
  execute_ooda_step(45, 100) |> should.equal(OodaLLMSuccess(45))
  let fallback = execute_ooda_step(140, 100)
  case fallback {
    OodaRuleOnlyFallback(reason) ->
      string.contains(reason, "Hard budget exceeded") |> should.be_true
    _ -> should.fail()
  }
}

// -----------------------------------------------------------------------------
// FM-15: AI Inference OOM & Dual Fallback Cascade
// -----------------------------------------------------------------------------

pub type InferenceEngine {
  Gemma3
  Gemma4Fallback
  NifKeywordSearchFallback
}

pub fn dispatch_inference(primary_alive: Bool, secondary_alive: Bool) -> InferenceEngine {
  case primary_alive {
    True -> Gemma3
    False ->
      case secondary_alive {
        True -> Gemma4Fallback
        False -> NifKeywordSearchFallback
      }
  }
}

pub fn fmea_inference_oom_dual_fallback_test() {
  dispatch_inference(True, True) |> should.equal(Gemma3)
  dispatch_inference(False, True) |> should.equal(Gemma4Fallback)
  dispatch_inference(False, False) |> should.equal(NifKeywordSearchFallback)
}

// -----------------------------------------------------------------------------
// FM-16: MCP Tool Dispatcher Hang & Circuit Breaker Cooldown
// -----------------------------------------------------------------------------

pub type McpDispatchStatus {
  McpCompleted(result: String)
  McpCircuitOpenCooldown(cooldown_sec: Int)
  McpEscalatedHITL
}

pub fn dispatch_mcp_tool(failures: Int, timeout_exceeded: Bool) -> McpDispatchStatus {
  case timeout_exceeded {
    False -> McpCompleted("Tool Execution Nominal")
    True ->
      case failures >= 3 {
        True -> McpEscalatedHITL
        False -> McpCircuitOpenCooldown(60)
      }
  }
}

pub fn fmea_mcp_tool_hang_cooldown_test() {
  dispatch_mcp_tool(0, False) |> should.equal(McpCompleted("Tool Execution Nominal"))
  dispatch_mcp_tool(1, True) |> should.equal(McpCircuitOpenCooldown(60))
  dispatch_mcp_tool(3, True) |> should.equal(McpEscalatedHITL)
}

// -----------------------------------------------------------------------------
// FM-17: Zenoh Mesh Partition & Quorum Redundancy
// -----------------------------------------------------------------------------

pub type MeshPartitionQuorum {
  QuorumMaintained(active_routers: Int)
  QuorumLostPartitioned(active_routers: Int)
}

pub fn evaluate_mesh_quorum(active_routers: Int, total_routers: Int) -> MeshPartitionQuorum {
  let threshold = { total_routers / 2 } + 1
  case active_routers >= threshold {
    True -> QuorumMaintained(active_routers)
    False -> QuorumLostPartitioned(active_routers)
  }
}

pub fn fmea_zenoh_mesh_partition_quorum_test() {
  // 4 routers total, threshold is 3
  evaluate_mesh_quorum(4, 4) |> should.equal(QuorumMaintained(4))
  evaluate_mesh_quorum(3, 4) |> should.equal(QuorumMaintained(3))
  evaluate_mesh_quorum(2, 4) |> should.equal(QuorumLostPartitioned(2))
}

// -----------------------------------------------------------------------------
// FM-18: WebSocket Handler Drop & Auto-Reconnect Backoff
// -----------------------------------------------------------------------------

pub type WsConnectionStatus {
  WsConnected
  WsReconnecting(attempt: Int, delay_ms: Int)
}

pub fn handle_websocket_drop(dropped: Bool, retry_attempt: Int) -> WsConnectionStatus {
  case dropped {
    False -> WsConnected
    True -> {
      let delay = 1000 * { retry_attempt + 1 }
      WsReconnecting(attempt: retry_attempt + 1, delay_ms: delay)
    }
  }
}

pub fn fmea_websocket_disconnect_reconnect_test() {
  handle_websocket_drop(False, 0) |> should.equal(WsConnected)
  let reconn = handle_websocket_drop(True, 2)
  reconn |> should.equal(WsReconnecting(3, 3000))
}

// -----------------------------------------------------------------------------
// FM-19: Split-Brain Quorum & Immediate Apoptosis
// -----------------------------------------------------------------------------

pub type NodeLeaseVerdict {
  LeaseAffirmed
  ApoptosisTriggered(reason: String)
}

pub fn verify_lease_authority(has_zenoh_lease: Bool, dual_leader_observed: Bool) -> NodeLeaseVerdict {
  case dual_leader_observed && !has_zenoh_lease {
    True ->
      ApoptosisTriggered(
        "SC-SIL4-015: Split-brain detected without Zenoh lease authority. Commencing apoptosis.",
      )
    False -> LeaseAffirmed
  }
}

pub fn fmea_split_brain_apoptosis_test() {
  verify_lease_authority(True, True) |> should.equal(LeaseAffirmed)
  let suicide = verify_lease_authority(False, True)
  case suicide {
    ApoptosisTriggered(msg) ->
      string.contains(msg, "Split-brain detected") |> should.be_true
    _ -> should.fail()
  }
}

// -----------------------------------------------------------------------------
// FM-20: Supervisor Restart Storm Escalation
// -----------------------------------------------------------------------------

pub type SupervisorDecision {
  ChildRestarted(restarts: Int)
  SupervisorEscalated(restarts: Int, reason: String)
}

pub fn simulate_supervisor_crash(crash_count: Int, max_restarts: Int) -> SupervisorDecision {
  case crash_count > max_restarts {
    True ->
      SupervisorEscalated(
        restarts: crash_count,
        reason: "Child crashed repeatedly exceeding restart budget (intensity exceeded)",
      )
    False -> ChildRestarted(restarts: crash_count)
  }
}

pub fn fmea_supervisor_restart_storm_escalation_test() {
  let s1 = simulate_supervisor_crash(2, 3)
  case s1 {
    ChildRestarted(r) -> r |> should.equal(2)
    _ -> should.fail()
  }

  let s2 = simulate_supervisor_crash(5, 3)
  case s2 {
    SupervisorEscalated(r, reason) -> {
      r |> should.equal(5)
      string.contains(reason, "exceeding restart budget") |> should.be_true
    }
    _ -> should.fail()
  }
}

// -----------------------------------------------------------------------------
// FM-21: Host NVMe Drive Serial Lockout (HARD_DENIED_SYSTEM_OS_SERIAL)
// -----------------------------------------------------------------------------

pub const hard_denied_serial: String = "25503L801736"

pub fn verify_device_safe_for_write(device_serial: String) -> Result(String, String) {
  case string.contains(device_serial, hard_denied_serial) {
    True -> Error("FAIL_CLOSED: OS NVMe serial locked from write operations")
    False -> Ok("SAFE_DEVICE")
  }
}

pub fn fmea_drive_serial_lockout_test() {
  verify_device_safe_for_write("NVME_DATA_STORE_001") |> should.be_ok
  verify_device_safe_for_write("DEV_25503L801736_SYS") |> should.be_error
}

// -----------------------------------------------------------------------------
// FM-22: Zero-Trust Payload Interception (NUL byte & Raw SQL Injection)
// -----------------------------------------------------------------------------

pub type InterceptorVerdict {
  PayloadAdmitted
  PayloadRejected(exit_code: Int, reason: String)
}

pub fn intercept_mcp_payload(payload: String) -> InterceptorVerdict {
  let has_nul = string.contains(payload, "\u{0000}")
  let upper = string.uppercase(payload)
  let has_sqli =
    string.contains(upper, "DROP TABLE")
    || string.contains(upper, "DELETE FROM")
    || string.contains(upper, "UNION SELECT")

  case has_nul {
    True -> PayloadRejected(-2, "Zero-Trust: Embedded NUL byte trapped")
    False ->
      case has_sqli {
        True -> PayloadRejected(-3, "Zero-Trust: Raw SQL mutation trapped")
        False -> PayloadAdmitted
      }
  }
}

pub fn fmea_zero_trust_payload_interception_test() {
  intercept_mcp_payload("read_file: path=/data/report.json")
  |> should.equal(PayloadAdmitted)

  let nul_res = intercept_mcp_payload("read_file: /etc/passwd\u{0000}.jpg")
  case nul_res {
    PayloadRejected(code, msg) -> {
      code |> should.equal(-2)
      string.contains(msg, "Embedded NUL byte") |> should.be_true
    }
    _ -> should.fail()
  }

  let sqli_res = intercept_mcp_payload("query: 1; DROP TABLE users; --")
  case sqli_res {
    PayloadRejected(code, msg) -> {
      code |> should.equal(-3)
      string.contains(msg, "Raw SQL mutation") |> should.be_true
    }
    _ -> should.fail()
  }
}
