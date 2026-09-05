//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ha/beam_metrics</module>
////     <fsharp-lineage>None — novel BEAM VM observability layer</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L1_ATOMIC_DEBUG</layer>
////     <mesh-domain>BEAM VM scheduler utilization monitoring (F17)</mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>HIGH</criticality>
////     <stamp-controls>SC-GLM-UI-001, SC-GLM-UI-003, SC-GLM-ZEN-001, SC-MUDA-001</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective">
////       Erlang runtime introspection (erlang:memory/0, erlang:statistics/1,
////       erlang:system_info/1) ↪ Gleam typed BeamMetrics record.
////       All values normalised to Int (MB or raw counts) for JSON serialisation.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// BEAM SCHEDULER UTILIZATION MONITORING — F17
//// प्रकृतिं स्वामवष्टभ्य — Resting on My own nature (Gita 9.8)
////
//// Exposes BEAM VM runtime metrics via Erlang FFI.  Metrics are consumed by:
////   • GET /api/v1/system/beam   — Wisp REST endpoint
////   • TUI ha_view               — terminal sparkline display
////   • Zenoh OTel span           — SC-GLM-ZEN-001
////
//// Threshold defaults (conservative, tunable):
////   run_queue_length > 50  → WARNING
////   process_count    > 50_000 → WARNING
////   memory_total_mb  > 4096   → WARNING
////
//// STAMP: SC-GLM-UI-001, SC-GLM-UI-003, SC-GLM-ZEN-001, SC-MUDA-001

import gleam/int
import gleam/json
import gleam/list

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

/// BEAM VM metrics snapshot — all counters captured atomically by the FFI.
pub type BeamMetrics {
  BeamMetrics(
    /// Number of online schedulers (hardware concurrency)
    scheduler_count: Int,
    /// Number of living BEAM processes
    process_count: Int,
    /// Total VM memory in MB
    memory_total_mb: Int,
    /// Memory allocated to processes in MB
    memory_processes_mb: Int,
    /// Memory allocated to ETS tables in MB
    memory_ets_mb: Int,
    /// Memory allocated to binary heap in MB
    memory_binary_mb: Int,
    /// Aggregate run-queue length (work items awaiting schedulers)
    run_queue_length: Int,
    /// Wall-clock uptime in seconds since VM start
    uptime_seconds: Int,
    /// Cumulative I/O input in MB
    io_input_mb: Int,
    /// Cumulative I/O output in MB
    io_output_mb: Int,
    /// Number of atoms in the atom table
    atom_count: Int,
    /// Number of open ports
    port_count: Int,
  )
}

// ---------------------------------------------------------------------------
// FFI declaration
// ---------------------------------------------------------------------------

@external(erlang, "beam_metrics_ffi", "snapshot")
fn ffi_snapshot() -> BeamMetrics

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Capture a point-in-time BEAM VM metrics snapshot via Erlang FFI.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">Erlang runtime stats ↪ BeamMetrics</morphism>
///   <formal-proof>
///     <P> Pre: Erlang runtime is running (always true in BEAM context) </P>
///     <C> snapshot() </C>
///     <Q> Post: Returns BeamMetrics with all fields >= 0. Never raises. </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn snapshot() -> BeamMetrics {
  ffi_snapshot()
}

/// Serialise a BeamMetrics snapshot to a JSON string.
/// Uses gleam/json — no raw string concatenation (SC-GLM-UI-003).
pub fn to_json(m: BeamMetrics) -> String {
  json.object([
    #("page", json.string("BEAM Scheduler Metrics")),
    #("scheduler_count", json.int(m.scheduler_count)),
    #("process_count", json.int(m.process_count)),
    #("memory_total_mb", json.int(m.memory_total_mb)),
    #("memory_processes_mb", json.int(m.memory_processes_mb)),
    #("memory_ets_mb", json.int(m.memory_ets_mb)),
    #("memory_binary_mb", json.int(m.memory_binary_mb)),
    #("run_queue_length", json.int(m.run_queue_length)),
    #("uptime_seconds", json.int(m.uptime_seconds)),
    #("io_input_mb", json.int(m.io_input_mb)),
    #("io_output_mb", json.int(m.io_output_mb)),
    #("atom_count", json.int(m.atom_count)),
    #("port_count", json.int(m.port_count)),
    #("warnings", json.array(check_thresholds(m), json.string)),
  ])
  |> json.to_string()
}

/// Evaluate conservative safety thresholds and return a list of warning strings.
/// Returns an empty list when all metrics are within normal operating bounds.
pub fn check_thresholds(m: BeamMetrics) -> List(String) {
  let warnings = []

  let warnings =
    add_if(
      warnings,
      m.run_queue_length > 50,
      "run_queue_length="
        <> int.to_string(m.run_queue_length)
        <> " exceeds threshold 50",
    )

  let warnings =
    add_if(
      warnings,
      m.process_count > 50_000,
      "process_count="
        <> int.to_string(m.process_count)
        <> " exceeds threshold 50000",
    )

  let warnings =
    add_if(
      warnings,
      m.memory_total_mb > 4096,
      "memory_total_mb="
        <> int.to_string(m.memory_total_mb)
        <> " exceeds threshold 4096 MB",
    )

  let warnings =
    add_if(
      warnings,
      m.atom_count > 1_000_000,
      "atom_count="
        <> int.to_string(m.atom_count)
        <> " exceeds threshold 1000000",
    )

  list.reverse(warnings)
}

/// Human-readable single-line summary for TUI sparkline label.
pub fn summary_line(m: BeamMetrics) -> String {
  "BEAM sched="
  <> int.to_string(m.scheduler_count)
  <> " procs="
  <> int.to_string(m.process_count)
  <> " mem="
  <> int.to_string(m.memory_total_mb)
  <> "MB rq="
  <> int.to_string(m.run_queue_length)
  <> " up="
  <> uptime_human(m.uptime_seconds)
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

fn add_if(acc: List(String), cond: Bool, msg: String) -> List(String) {
  case cond {
    True -> [msg, ..acc]
    False -> acc
  }
}

fn uptime_human(seconds: Int) -> String {
  let h = seconds / 3600
  let m = seconds % 3600 / 60
  let s = seconds % 60
  case h > 0 {
    True -> int.to_string(h) <> "h" <> int.to_string(m) <> "m"
    False ->
      case m > 0 {
        True -> int.to_string(m) <> "m" <> int.to_string(s) <> "s"
        False -> int.to_string(s) <> "s"
      }
  }
}

// Expose for tests — allow constructing a metrics value without FFI.
pub fn new_metrics(
  scheduler_count sc: Int,
  process_count pc: Int,
  memory_total_mb mt: Int,
  memory_processes_mb mp: Int,
  memory_ets_mb me: Int,
  memory_binary_mb mb: Int,
  run_queue_length rq: Int,
  uptime_seconds up: Int,
  io_input_mb ii: Int,
  io_output_mb io: Int,
  atom_count ac: Int,
  port_count poc: Int,
) -> BeamMetrics {
  BeamMetrics(
    scheduler_count: sc,
    process_count: pc,
    memory_total_mb: mt,
    memory_processes_mb: mp,
    memory_ets_mb: me,
    memory_binary_mb: mb,
    run_queue_length: rq,
    uptime_seconds: up,
    io_input_mb: ii,
    io_output_mb: io,
    atom_count: ac,
    port_count: poc,
  )
}
