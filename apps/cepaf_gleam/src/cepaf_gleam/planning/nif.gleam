//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>planning/nif</module>
////     <fsharp-lineage>Cepaf.Planning.CLI (sa-plan-daemon db.rs)</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L3_TRANSACTION</layer>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-TODO-001, SC-ARCH-SPLIT-003, SC-NIF-001</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="isomorphic">
////       Rust db.rs SQLite queries = Gleam NIF bridge. Zero information loss.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================

// ---------------------------------------------------------------------------
// Planning NIF — Gleam FFI bridge to Rust planning_nif
// ---------------------------------------------------------------------------
// All functions return JSON strings. The NIF handles SQLite WAL mode,
// busy timeout, and exponential backoff internally.
// ---------------------------------------------------------------------------

/// Returns JSON: {"active":N,"pending":N,"completed":N,"blocked":N,"total":N}
@external(erlang, "planning_nif", "plan_status")
pub fn status() -> String

/// Returns JSON array of all non-completed tasks
@external(erlang, "planning_nif", "plan_list_pending")
pub fn list_pending() -> String

/// Returns JSON array filtered by status ("pending"|"in_progress"|"completed"|"blocked"|"all")
@external(erlang, "planning_nif", "plan_list_by_status")
pub fn list_by_status(status: String) -> String

/// Returns JSON for a single task by ID, or {"error":"..."} if not found
@external(erlang, "planning_nif", "plan_get_task")
pub fn get_task(id: String) -> String

/// Adds a task, returns {"ok":true,"id":"..."} or {"ok":false,"error":"..."}
@external(erlang, "planning_nif", "plan_add_task")
pub fn add_task(title: String, priority: String) -> String

/// Updates task status, returns {"ok":true,"id":"...","status":"..."} or error
@external(erlang, "planning_nif", "plan_update_task")
pub fn update_task(id: String, status: String) -> String

/// LIKE search on task title, returns JSON array (max 100 results)
@external(erlang, "planning_nif", "plan_search")
pub fn search(query: String) -> String
