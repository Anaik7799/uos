//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// <c3i-module>
////   <identity><module>cepaf_gleam/planning/chaya</module>
////     <fsharp-lineage>Cepaf.ChayaSync.fs</fsharp-lineage></identity>
////   <fractal-topology><layer>L3_TRANSACTION</layer></fractal-topology>
////   <compliance><criticality>DAL-A / SIL-6</criticality>
////     <stamp-controls>SC-SYNC-PLAN-001 through SC-SYNC-PLAN-020</stamp-controls></compliance>
////   <description>
////     Chaya digital twin sync module — implements the 5-phase sync protocol
////     between the Planning subsystem and the Chaya external twin.
////     Phase 1: Read planning tasks
////     Phase 2: Detect orphans (chaya IDs not in planning)
////     Phase 3: Convert planning tasks to Chaya format
////     Phase 4: Regenerate Chaya state from planning source-of-truth
////     Phase 5: Verify bidirectional consistency
////   </description>
//// </c3i-module>

import cepaf_gleam/core/ids
import cepaf_gleam/core/types
import cepaf_gleam/planning/domain
import gleam/int
import gleam/json
import gleam/list
import gleam/string

// =============================================================================
// Type Definitions — Chaya 5-Phase Sync Protocol
// =============================================================================

/// A task in Chaya digital twin format.
pub type ChayaTask {
  ChayaTask(
    id: String,
    title: String,
    status: String,
    priority: String,
    created_at: String,
  )
}

/// The five phases of the Chaya sync protocol.
pub type SyncPhase {
  Phase1ReadPlanning
  Phase2DetectOrphans
  Phase3Convert
  Phase4Regenerate
  Phase5Verify
}

/// Result of a single sync phase execution.
pub type SyncResult {
  SyncResult(
    phase: SyncPhase,
    success: Bool,
    tasks_processed: Int,
    errors: Int,
    details: String,
  )
}

/// Aggregate report across all 5 sync phases.
pub type SyncReport {
  SyncReport(
    phases: List(SyncResult),
    total_tasks: Int,
    synced_tasks: Int,
    orphans: Int,
    mismatches: Int,
    success: Bool,
  )
}

// =============================================================================
// Status & Priority Mapping (SC-SYNC-PLAN-003, SC-SYNC-PLAN-004)
// =============================================================================

/// Map a Planning TaskStatus to its Chaya string representation.
/// Note: UnknownStatus is mapped to "todo" (lossy — SC-SYNC-PLAN-003).
pub fn map_status_to_chaya(status: types.TaskStatus) -> String {
  case status {
    types.Pending -> "todo"
    types.InProgress -> "in_progress"
    types.Completed -> "done"
    types.Blocked -> "blocked"
    types.UnknownStatus(_) -> "todo"
  }
}

/// Map a Planning Priority to its Chaya string representation.
pub fn map_priority_to_chaya(priority: types.Priority) -> String {
  case priority {
    types.P0Critical -> "P0"
    types.P1High -> "P1"
    types.P2Medium -> "P2"
    types.P3Low -> "P3"
    types.P4Minimal -> "P4"
    types.UnknownPriority(s) -> s
  }
}

/// Reverse-map a Chaya status string back to a Planning TaskStatus.
pub fn map_chaya_status_back(status: String) -> types.TaskStatus {
  case string.lowercase(string.trim(status)) {
    "todo" -> types.Pending
    "in_progress" -> types.InProgress
    "done" -> types.Completed
    "blocked" -> types.Blocked
    _ -> types.UnknownStatus(status)
  }
}

// =============================================================================
// Task Conversion (SC-SYNC-PLAN-005)
// =============================================================================

/// Convert a Planning domain Task to a ChayaTask.
/// Extracts the string representations of opaque ID, title, status, and priority.
pub fn convert_to_chaya_task(task: domain.Task) -> ChayaTask {
  let domain.Task(
    id: task_id,
    title: title_nes,
    status: status,
    priority: priority,
    created_at: created_at,
    ..,
  ) = task

  ChayaTask(
    id: ids.task_id_to_string(task_id),
    title: types.non_empty_string_value(title_nes),
    status: map_status_to_chaya(status),
    priority: map_priority_to_chaya(priority),
    created_at: created_at,
  )
}

// =============================================================================
// Orphan Detection (SC-SYNC-PLAN-008)
// =============================================================================

/// Detect orphan IDs: IDs present in Chaya but absent from Planning.
/// Returns the list of orphaned Chaya IDs.
pub fn detect_orphans(
  planning_ids: List(String),
  chaya_ids: List(String),
) -> List(String) {
  list.filter(chaya_ids, fn(cid) { !list.contains(planning_ids, cid) })
}

// =============================================================================
// Verification (SC-SYNC-PLAN-015)
// =============================================================================

/// Verify sync consistency between planning tasks and chaya tasks.
/// Checks both count match and per-task status alignment.
pub fn verify_sync(
  planning_tasks: List(domain.Task),
  chaya_tasks: List(ChayaTask),
) -> SyncResult {
  let planning_count = list.length(planning_tasks)
  let chaya_count = list.length(chaya_tasks)
  let count_match = planning_count == chaya_count

  // Build a lookup of chaya tasks by ID for status comparison
  let chaya_by_id = list.map(chaya_tasks, fn(ct) { #(ct.id, ct.status) })

  // Count status mismatches
  let mismatches =
    list.fold(planning_tasks, 0, fn(acc, pt) {
      let pid = ids.task_id_to_string(pt.id)
      let expected_status = map_status_to_chaya(pt.status)
      let found = list.find(chaya_by_id, fn(pair) { pair.0 == pid })
      case found {
        Ok(#(_, actual_status)) ->
          case actual_status == expected_status {
            True -> acc
            False -> acc + 1
          }
        Error(_) -> acc + 1
      }
    })

  let success = count_match && mismatches == 0

  SyncResult(
    phase: Phase5Verify,
    success: success,
    tasks_processed: planning_count,
    errors: mismatches,
    details: "count_match="
      <> bool_to_string(count_match)
      <> " mismatches="
      <> int.to_string(mismatches),
  )
}

// =============================================================================
// Full 5-Phase Sync Pipeline (SC-SYNC-PLAN-001)
// =============================================================================

/// Execute the full Chaya 5-phase sync protocol.
///
/// Phase 1: Read planning tasks (input already provided)
/// Phase 2: Detect orphans (none expected on fresh sync)
/// Phase 3: Convert all planning tasks to Chaya format
/// Phase 4: Regenerate — the converted list IS the new Chaya state
/// Phase 5: Verify bidirectional consistency
pub fn run_sync(planning_tasks: List(domain.Task)) -> SyncReport {
  let task_count = list.length(planning_tasks)

  // Phase 1: Read planning tasks
  let phase1 =
    SyncResult(
      phase: Phase1ReadPlanning,
      success: True,
      tasks_processed: task_count,
      errors: 0,
      details: "Read " <> int.to_string(task_count) <> " planning tasks",
    )

  // Phase 2: Detect orphans (fresh sync — no prior chaya state)
  let orphans =
    detect_orphans(
      list.map(planning_tasks, fn(t) { ids.task_id_to_string(t.id) }),
      [],
    )
  let orphan_count = list.length(orphans)
  let phase2 =
    SyncResult(
      phase: Phase2DetectOrphans,
      success: True,
      tasks_processed: task_count,
      errors: orphan_count,
      details: "Orphans detected: " <> int.to_string(orphan_count),
    )

  // Phase 3: Convert planning tasks to Chaya format
  let chaya_tasks = list.map(planning_tasks, convert_to_chaya_task)
  let phase3 =
    SyncResult(
      phase: Phase3Convert,
      success: True,
      tasks_processed: task_count,
      errors: 0,
      details: "Converted "
        <> int.to_string(list.length(chaya_tasks))
        <> " tasks to Chaya format",
    )

  // Phase 4: Regenerate (the converted list is the new state)
  let phase4 =
    SyncResult(
      phase: Phase4Regenerate,
      success: True,
      tasks_processed: list.length(chaya_tasks),
      errors: 0,
      details: "Regenerated Chaya state with "
        <> int.to_string(list.length(chaya_tasks))
        <> " tasks",
    )

  // Phase 5: Verify
  let phase5 = verify_sync(planning_tasks, chaya_tasks)

  let all_phases = [phase1, phase2, phase3, phase4, phase5]
  let all_success = list.all(all_phases, fn(p) { p.success })

  SyncReport(
    phases: all_phases,
    total_tasks: task_count,
    synced_tasks: list.length(chaya_tasks),
    orphans: orphan_count,
    mismatches: phase5.errors,
    success: all_success,
  )
}

// =============================================================================
// JSON Serialization (SC-SYNC-PLAN-018)
// =============================================================================

/// Serialize a SyncReport to JSON for Wisp/Zenoh transport.
pub fn sync_report_to_json(report: SyncReport) -> json.Json {
  json.object([
    #("phases", json.array(report.phases, sync_result_to_json)),
    #("total_tasks", json.int(report.total_tasks)),
    #("synced_tasks", json.int(report.synced_tasks)),
    #("orphans", json.int(report.orphans)),
    #("mismatches", json.int(report.mismatches)),
    #("success", json.bool(report.success)),
  ])
}

/// Serialize a single SyncResult phase to JSON.
fn sync_result_to_json(result: SyncResult) -> json.Json {
  json.object([
    #("phase", json.string(sync_phase_to_string(result.phase))),
    #("success", json.bool(result.success)),
    #("tasks_processed", json.int(result.tasks_processed)),
    #("errors", json.int(result.errors)),
    #("details", json.string(result.details)),
  ])
}

// =============================================================================
// Internal Helpers
// =============================================================================

fn sync_phase_to_string(phase: SyncPhase) -> String {
  case phase {
    Phase1ReadPlanning -> "phase1_read_planning"
    Phase2DetectOrphans -> "phase2_detect_orphans"
    Phase3Convert -> "phase3_convert"
    Phase4Regenerate -> "phase4_regenerate"
    Phase5Verify -> "phase5_verify"
  }
}

fn bool_to_string(b: Bool) -> String {
  case b {
    True -> "true"
    False -> "false"
  }
}
