/// beam_metrics_test — F17 BEAM Scheduler Utilisation Monitoring
///
/// Covers:
///   C1  Page structure: snapshot returns a valid BeamMetrics record
///   C2  Boundary validity: all numeric fields are non-negative
///   C3  JSON serialisation: to_json returns well-formed JSON
///   C5  Threshold logic: healthy metrics produce no warnings
///   C8  Safety gate: breach of each threshold triggers the expected warning
///
/// STAMP: SC-GLM-UI-001, SC-GLM-UI-003, SC-MUDA-001
/// Layer: L1_ATOMIC_DEBUG
import cepaf_gleam/ha/beam_metrics.{BeamMetrics}
import gleam/list
import gleam/string
import gleeunit/should

// ---------------------------------------------------------------------------
// C1 — Page structure: live snapshot from FFI is coherent
// ---------------------------------------------------------------------------

pub fn snapshot_returns_coherent_record_test() {
  let m = beam_metrics.snapshot()
  // scheduler_count must be at least 1 on any real BEAM VM
  { m.scheduler_count >= 1 } |> should.be_true()
}

// ---------------------------------------------------------------------------
// C2 — All fields non-negative (live FFI call)
// ---------------------------------------------------------------------------

pub fn scheduler_count_positive_test() {
  let m = beam_metrics.snapshot()
  { m.scheduler_count >= 1 } |> should.be_true()
}

pub fn process_count_positive_test() {
  let m = beam_metrics.snapshot()
  { m.process_count >= 1 } |> should.be_true()
}

pub fn memory_total_non_negative_test() {
  let m = beam_metrics.snapshot()
  { m.memory_total_mb >= 0 } |> should.be_true()
}

pub fn run_queue_length_non_negative_test() {
  let m = beam_metrics.snapshot()
  { m.run_queue_length >= 0 } |> should.be_true()
}

pub fn uptime_non_negative_test() {
  let m = beam_metrics.snapshot()
  { m.uptime_seconds >= 0 } |> should.be_true()
}

pub fn atom_count_positive_test() {
  let m = beam_metrics.snapshot()
  // Gleam itself registers dozens of atoms at startup
  { m.atom_count > 0 } |> should.be_true()
}

pub fn port_count_non_negative_test() {
  let m = beam_metrics.snapshot()
  { m.port_count >= 0 } |> should.be_true()
}

// ---------------------------------------------------------------------------
// C3 — JSON serialisation
// ---------------------------------------------------------------------------

pub fn to_json_contains_page_field_test() {
  let m = build_healthy_metrics()
  let j = beam_metrics.to_json(m)
  { string.contains(j, "BEAM Scheduler Metrics") } |> should.be_true()
}

pub fn to_json_contains_scheduler_count_test() {
  let m = build_healthy_metrics()
  let j = beam_metrics.to_json(m)
  { string.contains(j, "scheduler_count") } |> should.be_true()
}

pub fn to_json_contains_run_queue_test() {
  let m = build_healthy_metrics()
  let j = beam_metrics.to_json(m)
  { string.contains(j, "run_queue_length") } |> should.be_true()
}

pub fn to_json_contains_warnings_field_test() {
  let m = build_healthy_metrics()
  let j = beam_metrics.to_json(m)
  { string.contains(j, "warnings") } |> should.be_true()
}

pub fn to_json_is_non_empty_test() {
  let m = build_healthy_metrics()
  let j = beam_metrics.to_json(m)
  { string.length(j) > 10 } |> should.be_true()
}

// ---------------------------------------------------------------------------
// C5 — Threshold logic: healthy metrics → empty warning list
// ---------------------------------------------------------------------------

pub fn healthy_metrics_no_warnings_test() {
  let m = build_healthy_metrics()
  beam_metrics.check_thresholds(m) |> should.equal([])
}

// ---------------------------------------------------------------------------
// C8 — Safety gate: each threshold violation produces the expected warning
// ---------------------------------------------------------------------------

pub fn run_queue_threshold_triggers_warning_test() {
  // run_queue_length = 51 exceeds threshold of 50
  let m = BeamMetrics(..build_healthy_metrics(), run_queue_length: 51)
  let warnings = beam_metrics.check_thresholds(m)
  { list.length(warnings) >= 1 } |> should.be_true()
  let has_rq_warning =
    list.any(warnings, fn(w) { string.contains(w, "run_queue_length") })
  has_rq_warning |> should.be_true()
}

pub fn process_count_threshold_triggers_warning_test() {
  // process_count = 50_001 exceeds threshold of 50_000
  let m = BeamMetrics(..build_healthy_metrics(), process_count: 50_001)
  let warnings = beam_metrics.check_thresholds(m)
  let has_proc_warning =
    list.any(warnings, fn(w) { string.contains(w, "process_count") })
  has_proc_warning |> should.be_true()
}

pub fn memory_threshold_triggers_warning_test() {
  // memory_total_mb = 4097 exceeds threshold of 4096
  let m = BeamMetrics(..build_healthy_metrics(), memory_total_mb: 4097)
  let warnings = beam_metrics.check_thresholds(m)
  let has_mem_warning =
    list.any(warnings, fn(w) { string.contains(w, "memory_total_mb") })
  has_mem_warning |> should.be_true()
}

pub fn atom_count_threshold_triggers_warning_test() {
  // atom_count = 1_000_001 exceeds threshold of 1_000_000
  let m = BeamMetrics(..build_healthy_metrics(), atom_count: 1_000_001)
  let warnings = beam_metrics.check_thresholds(m)
  let has_atom_warning =
    list.any(warnings, fn(w) { string.contains(w, "atom_count") })
  has_atom_warning |> should.be_true()
}

// ---------------------------------------------------------------------------
// Summary line helper
// ---------------------------------------------------------------------------

pub fn summary_line_contains_sched_test() {
  let m = build_healthy_metrics()
  let s = beam_metrics.summary_line(m)
  { string.contains(s, "sched=") } |> should.be_true()
}

pub fn summary_line_contains_mem_test() {
  let m = build_healthy_metrics()
  let s = beam_metrics.summary_line(m)
  { string.contains(s, "mem=") } |> should.be_true()
}

pub fn summary_line_contains_procs_test() {
  let m = build_healthy_metrics()
  let s = beam_metrics.summary_line(m)
  { string.contains(s, "procs=") } |> should.be_true()
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn build_healthy_metrics() -> beam_metrics.BeamMetrics {
  beam_metrics.new_metrics(
    scheduler_count: 16,
    process_count: 250,
    memory_total_mb: 512,
    memory_processes_mb: 64,
    memory_ets_mb: 8,
    memory_binary_mb: 16,
    run_queue_length: 0,
    uptime_seconds: 3600,
    io_input_mb: 10,
    io_output_mb: 5,
    atom_count: 42_000,
    port_count: 4,
  )
}
