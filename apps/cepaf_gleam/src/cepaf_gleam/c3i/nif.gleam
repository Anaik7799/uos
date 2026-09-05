//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/c3i/nif</module>
////     <fsharp-lineage>Cepaf.Planning.CLI (Rust replacement)</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L3_TRANSACTION</layer>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-MCP-001, SC-TODO-001, SC-NIF-001, SC-ZMOF-005, SC-ARCH-SPLIT-003</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="isomorphic">
////       Rust c3i_nif NIFs = Gleam FFI bridge. Zero information loss.
////       All functions return JSON strings parsed by Gleam callers.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// Unified C3I NIF bridge — 14 external functions exposing:
//// - Planning (7): task CRUD on Smriti.db
//// - System (5): live mesh health, dashboard, immune, zenoh, verification
//// - Knowledge (1): search Smriti.db knowledge tables
//// - Verification (1): run gleam check
////
//// All functions return JSON strings. Callers parse with gleam/json.
////
//// STAMP: SC-MCP-001, SC-TODO-001, SC-NIF-001, SC-ZMOF-005, SC-ARCH-SPLIT-003

// ---------------------------------------------------------------------------
// Planning NIFs (7) — task CRUD on Smriti.db
// ---------------------------------------------------------------------------

/// Task count summary: {"active":N,"pending":N,"completed":N,"blocked":N,"total":N}
@external(erlang, "c3i_nif", "plan_status")
pub fn plan_status() -> String

/// All non-completed tasks as JSON array.
@external(erlang, "c3i_nif", "plan_list_pending")
pub fn plan_list_pending() -> String

/// Filter tasks by status: pending|in_progress|completed|blocked|all.
@external(erlang, "c3i_nif", "plan_list_by_status")
pub fn plan_list_by_status(status: String) -> String

/// Get single task by ID. Returns task JSON or {"error":"..."}.
@external(erlang, "c3i_nif", "plan_get_task")
pub fn plan_get_task(id: String) -> String

/// Add new task: {"ok":true,"id":"..."} or {"ok":false,"error":"..."}.
@external(erlang, "c3i_nif", "plan_add_task")
pub fn plan_add_task(title: String, priority: String) -> String

/// Update task status: {"ok":true,"id":"...","status":"..."}.
@external(erlang, "c3i_nif", "plan_update_task")
pub fn plan_update_task(id: String, status: String) -> String

/// Search tasks by title (LIKE match, max 100 results).
@external(erlang, "c3i_nif", "plan_search")
pub fn plan_search(query: String) -> String

// ---------------------------------------------------------------------------
// System NIFs (5) — live mesh state
// ---------------------------------------------------------------------------

/// Live mesh health: container counts, threat level, OODA phase, cockpit mode.
@external(erlang, "c3i_nif", "system_health")
pub fn system_health() -> String

/// Dashboard data: health %, zenoh status, quorum, timestamps.
@external(erlang, "c3i_nif", "system_dashboard")
pub fn system_dashboard() -> String

/// Immune system: threat level, antibodies, chaos attacks.
@external(erlang, "c3i_nif", "system_immune")
pub fn system_immune() -> String

/// Zenoh mesh: connected, router count, endpoints.
@external(erlang, "c3i_nif", "system_zenoh")
pub fn system_zenoh() -> String

/// Verification: SIL level, test counts, compliance %.
@external(erlang, "c3i_nif", "system_verification")
pub fn system_verification() -> String

// ---------------------------------------------------------------------------
// Knowledge NIF (1)
// ---------------------------------------------------------------------------

/// Search knowledge base by query string.
@external(erlang, "c3i_nif", "knowledge_search")
pub fn knowledge_search(query: String) -> String

// ---------------------------------------------------------------------------
// Verification NIF (1)
// ---------------------------------------------------------------------------

/// Run gleam check and return result.
@external(erlang, "c3i_nif", "verification_run")
pub fn verification_run() -> String

// ---------------------------------------------------------------------------
// Cortex & Operations NIFs (11) — Real operational data
// ---------------------------------------------------------------------------

/// Inference tier status: active model, latency, circuit breakers.
@external(erlang, "c3i_nif", "inference_status")
pub fn inference_status() -> String

/// Last N pipeline traces from TransactionSummary.
@external(erlang, "c3i_nif", "trace_recent")
pub fn trace_recent(limit: Int) -> String

/// Last N conversation messages with role.
@external(erlang, "c3i_nif", "conversation_history")
pub fn conversation_history(limit: Int) -> String

/// Semantic cache hit rate and entry count.
@external(erlang, "c3i_nif", "cache_stats")
pub fn cache_stats() -> String

/// FMEA failure modes derived from TransactionSummary.
@external(erlang, "c3i_nif", "fmea_report")
pub fn fmea_report() -> String

/// HA election role, missed heartbeats, lease TTL.
@external(erlang, "c3i_nif", "ha_status")
pub fn ha_status() -> String

/// Voice pipeline: WS connected, active tier, transcription.
@external(erlang, "c3i_nif", "voice_status")
pub fn voice_status() -> String

/// Ruliology: cellular automaton by name.
@external(erlang, "c3i_nif", "ruliology_automaton")
pub fn ruliology_automaton(name: String) -> String

/// Ruliology: multiway system (inference cascade).
@external(erlang, "c3i_nif", "ruliology_multiway")
pub fn ruliology_multiway() -> String

/// Ruliology: causal graph (pipeline DAG).
@external(erlang, "c3i_nif", "ruliology_causal")
pub fn ruliology_causal() -> String

/// Current OODA cycle phase and count.
@external(erlang, "c3i_nif", "ooda_phase")
pub fn ooda_phase() -> String

// =============================================================================
// Zenoh Native NIF (SC-ZENOH-001) — Direct BEAM → Rust → Zenoh
// =============================================================================

/// Open a Zenoh session. Config JSON: "{}" for default localhost:7447.
@external(erlang, "c3i_nif", "zenoh_open")
pub fn zenoh_open(config_json: String) -> String

/// Publish data to a Zenoh key expression.
@external(erlang, "c3i_nif", "zenoh_put")
pub fn zenoh_put(key: String, payload: String) -> String

/// Get data from a Zenoh key expression.
@external(erlang, "c3i_nif", "zenoh_get")
pub fn zenoh_get(key: String) -> String

/// Check Zenoh session connection status.
@external(erlang, "c3i_nif", "zenoh_status")
pub fn zenoh_status() -> String

/// Close the Zenoh session.
@external(erlang, "c3i_nif", "zenoh_close")
pub fn zenoh_close() -> String
