//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ha/fmea_generator</module>
////     <fsharp-lineage>Cepaf.Fmea.Generator (partial lineage — F28 novel extension)</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L4_SYSTEM</layer>
////     <mesh-domain>
////       FMEA Automation (F28). Generates Failure Mode and Effects Analysis entries
////       from known system component failure modes. RPN = Severity × Occurrence × Detection.
////       RPN >= 200 requires immediate P0 action. Covers 20 system components across
////       fractal layers L0-L7 of the 16-container SIL-6 Biomorphic Mesh.
////     </mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>HIGH</criticality>
////     <stamp-controls>SC-SIL4-001, SC-HA-001, SC-FUNC-002, SC-GLM-UI-003, SC-MUDA-001</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="surjective" loss="runtime-trace-data">
////       Rust fmea.rs (trace-based FMEA) ↠ Gleam static FMEA catalog.
////       Mitigation: Rust daemon generates trace-driven FMEA at runtime;
////       this module provides the static reference catalog for UI display
////       and threshold-based filtering available without the Rust daemon.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// FMEA AUTOMATION — FAILURE MODE AND EFFECTS ANALYSIS
//// कुरुक्षेत्रे — On the battlefield of action (Gita 1.1)
////
//// IEC 60812 FMEA methodology applied to the SIL-6 Biomorphic Mesh.
//// Risk Priority Number: RPN = Severity × Occurrence × Detection (1-10 each).
////
//// RPN thresholds (from Rust constraint-registry.md):
////   RPN >= 200 → IMMEDIATE P0 action required
////   RPN 100-199 → P1 — schedule within current sprint
////   RPN 50-99   → P2 — address in next sprint
////   RPN < 50    → P3 — monitor, no immediate action
////
//// Scale definitions (IEC 60812):
////   Severity  : 1=negligible effect, 10=catastrophic system failure
////   Occurrence: 1=extremely unlikely, 10=inevitable/known pattern
////   Detection : 1=certain detection, 10=undetectable (inverted — higher is worse)
////
//// STAMP: SC-SIL4-001, SC-HA-001, SC-FUNC-002, SC-GLM-UI-003, SC-MUDA-001

import gleam/int
import gleam/list
import gleam/string

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

/// A single FMEA entry describing one failure mode for one component.
/// RPN is pre-computed as severity × occurrence × detection.
pub type FmeaEntry {
  FmeaEntry(
    /// Component identifier — e.g., "NIF pipeline", "WebSocket handler"
    component: String,
    /// Specific failure mode — e.g., "returns empty data on NIF crash"
    failure_mode: String,
    /// Effect severity on system (1-10). 10 = catastrophic.
    severity: Int,
    /// Likelihood of occurrence (1-10). 10 = certain.
    occurrence: Int,
    /// Detectability (1-10). 1 = always detected; 10 = silent failure.
    detection: Int,
    /// Risk Priority Number = severity × occurrence × detection
    rpn: Int,
    /// Mitigation strategy currently in place
    mitigation: String,
    /// Fractal layer most affected (L0-L7)
    layer: String,
  )
}

/// Priority classification derived from RPN threshold.
pub type FmeaPriority {
  P0Critical
  P1High
  P2Medium
  P3Low
}

// ---------------------------------------------------------------------------
// Internal constructor
// ---------------------------------------------------------------------------

/// Build an FmeaEntry and compute RPN automatically.
fn entry(
  component: String,
  failure_mode: String,
  severity: Int,
  occurrence: Int,
  detection: Int,
  mitigation: String,
  layer: String,
) -> FmeaEntry {
  FmeaEntry(
    component: component,
    failure_mode: failure_mode,
    severity: severity,
    occurrence: occurrence,
    detection: detection,
    rpn: severity * occurrence * detection,
    mitigation: mitigation,
    layer: layer,
  )
}

// ---------------------------------------------------------------------------
// System FMEA catalog
// ---------------------------------------------------------------------------

/// Generate the full FMEA catalog for the SIL-6 Biomorphic Mesh.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <formal-proof>
///     <P> Pre: no inputs required — catalog is static</P>
///     <C> generate_system_fmea() </C>
///     <Q> Post: returns exactly 20 FmeaEntry values; all RPNs are pre-computed </Q>
///   </formal-proof>
/// </c3i-atomic>
///
/// 20 entries covering the 16-container SIL-6 mesh + core infrastructure components.
pub fn generate_system_fmea() -> List(FmeaEntry) {
  [
    // --- L0 Constitutional ---
    entry(
      "Guardian gate",
      "approval request lost on BEAM crash mid-transaction",
      9,
      2,
      3,
      "Immutable register + Zenoh event sourcing; re-replay on restart",
      "L0_CONSTITUTIONAL",
    ),
    entry(
      "Psi invariant checker",
      "invariant I-01 (container_count >= healthy_count) violated silently",
      8,
      2,
      4,
      "invariant_gate.gleam pre-render guard; safe fallback element on violation",
      "L0_CONSTITUTIONAL",
    ),
    // --- L1 Atomic / NIF ---
    entry(
      "NIF pipeline",
      "returns empty data when Rust NIF is reloading",
      7,
      4,
      3,
      "NIF bridge returns {:error, :nif_not_loaded}; Gleam callers return cached data",
      "L1_ATOMIC_DEBUG",
    ),
    entry(
      "NIF pipeline",
      "segfault in Rust NIF code crashes BEAM scheduler",
      10,
      1,
      2,
      "Dirty scheduler isolation; NIF watchdog restart; ELF integrity check at boot",
      "L1_ATOMIC_DEBUG",
    ),
    entry(
      "Zenoh NIF session",
      "Zenoh router unreachable — NIF blocks publication for > 100ms",
      7,
      3,
      2,
      "SC-ZENOH-004: 100ms publication budget; non-blocking pub; retry with backoff",
      "L1_ATOMIC_DEBUG",
    ),
    // --- L2 Component ---
    entry(
      "Telemetry cache",
      "cache corruption causes stale metrics to be served indefinitely",
      6,
      2,
      5,
      "TTL-based eviction (24h); CRC integrity check on cache read",
      "L2_COMPONENT",
    ),
    // --- L3 Transaction ---
    entry(
      "SQLite/DuckDB store",
      "WAL file lock prevents concurrent write — data loss on forced unlock",
      8,
      3,
      3,
      "SC-XHOLON-001: Zenoh-only cross-holon access; single writer per holon",
      "L3_TRANSACTION",
    ),
    entry(
      "Planning state sync",
      "sa-plan-daemon write conflicts with Gleam read on Smriti.db",
      7,
      3,
      4,
      "Rust leader election via Zenoh lease; Gleam read-only via NIF",
      "L3_TRANSACTION",
    ),
    // --- L4 System ---
    entry(
      "Podman container",
      "container exits without dying-gasp checkpoint — state unrecoverable",
      9,
      2,
      3,
      "SC-SIL4-007: dying gasp mandatory; 6-phase apoptosis; state replayed from WAL",
      "L4_SYSTEM",
    ),
    entry(
      "BEAM hot reload",
      "code_change/2 fails on running GenServer — module left in inconsistent state",
      8,
      2,
      4,
      "rolling_upgrade.gleam drains traffic before hot swap; health check post-reload",
      "L4_SYSTEM",
    ),
    entry(
      "Host disk",
      "disk full halts SQLite writes — silent data loss on non-WAL tables",
      9,
      2,
      4,
      "Disk usage alert at 80%; emergency data flush; apoptosis if > 95%",
      "L4_SYSTEM",
    ),
    entry(
      "Host CPU",
      "CPU saturation > 85% degrades OODA cycle beyond 100ms SLA",
      7,
      4,
      2,
      "SC-CPU-GOV: adaptive parallelism; throttle to 6 schedulers at 80-85%",
      "L4_SYSTEM",
    ),
    entry(
      "BEAM memory",
      "process memory leak causes OOM killer termination of entire node",
      9,
      2,
      3,
      "math_monitor.rs tracks memory; EMA-based alert; self-healing supervisor restart",
      "L4_SYSTEM",
    ),
    // --- L5 Cognitive ---
    entry(
      "OODA supervisor",
      "OODA cycle exceeds 100ms SLA — orientation phase blocks on LLM call",
      6,
      4,
      2,
      "SC-OODA-001: 100ms hard budget; LLM advisory timeout 15s; rule-only fallback",
      "L5_COGNITIVE",
    ),
    entry(
      "Gemma inference",
      "Gemma 3 model OOM — chat widget returns empty response silently",
      5,
      4,
      3,
      "Dual-model fallback (Gemma 3 -> Gemma 4 -> NIF search); 15s AbortController",
      "L5_COGNITIVE",
    ),
    entry(
      "MCP tool dispatcher",
      "tool call hangs indefinitely — blocks agent OODA loop permanently",
      7,
      3,
      3,
      "MoZ timeout 5s; circuit breaker 3 failures → 60s cooldown; HITL escalation",
      "L5_COGNITIVE",
    ),
    // --- L6 Ecosystem ---
    entry(
      "Zenoh router",
      "router crash partitions mesh — containers lose coordination bus",
      9,
      2,
      2,
      "4 redundant Zenoh routers; quorum floor(N/2)+1; SC-ZENOH-002 mandatory check",
      "L6_ECOSYSTEM",
    ),
    entry(
      "WebSocket handler",
      "WebSocket connection drop silently stops real-time UI updates",
      5,
      5,
      2,
      "SC-AGUI-UI-011: client 1s ping; dead at 10s; auto-reconnect with backoff",
      "L6_ECOSYSTEM",
    ),
    entry(
      "Quorum consensus",
      "split-brain: two nodes believe they are leader, both write to Smriti.db",
      10,
      1,
      2,
      "SC-SIL4-015: split-brain triggers apoptosis; Zenoh lease-based leader election",
      "L6_ECOSYSTEM",
    ),
    // --- L7 Federation ---
    entry(
      "Supervisor tree",
      "supervisor restart storm: child restarts > 3 in 5s triggers entire tree crash",
      8,
      2,
      3,
      "SC-REGEN-002: max_restarts 3 per 5s; escalation to L4 container restart",
      "L7_FEDERATION",
    ),
  ]
}

// ---------------------------------------------------------------------------
// Filtering and analysis
// ---------------------------------------------------------------------------

/// Filter entries to those with RPN >= threshold.
/// Use threshold 200 for P0-critical entries per constraint-registry.md.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <formal-proof>
///     <P> Pre: entries is List(FmeaEntry); threshold >= 0 </P>
///     <C> critical_entries(entries, threshold) </C>
///     <Q> Post: all returned entries have rpn >= threshold </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn critical_entries(
  entries: List(FmeaEntry),
  threshold: Int,
) -> List(FmeaEntry) {
  list.filter(entries, fn(e) { e.rpn >= threshold })
}

/// Filter entries by fractal layer.
pub fn entries_for_layer(
  entries: List(FmeaEntry),
  layer: String,
) -> List(FmeaEntry) {
  list.filter(entries, fn(e) { e.layer == layer })
}

/// Classify an RPN value into its priority tier.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <formal-proof>
///     <P> Pre: rpn is Int </P>
///     <C> classify_rpn(rpn) </C>
///     <Q> Post: exactly one of P0Critical|P1High|P2Medium|P3Low is returned </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn classify_rpn(rpn: Int) -> FmeaPriority {
  case rpn {
    n if n >= 200 -> P0Critical
    n if n >= 100 -> P1High
    n if n >= 50 -> P2Medium
    _ -> P3Low
  }
}

/// Sum of all RPN values — system-level risk indicator.
/// Higher total RPN = more aggregate risk in the system.
pub fn total_rpn(entries: List(FmeaEntry)) -> Int {
  list.fold(entries, 0, fn(acc, e) { acc + e.rpn })
}

/// Find the highest-RPN entry in the list.
/// Returns the entry needing the most urgent attention.
pub fn highest_risk(entries: List(FmeaEntry)) -> Result(FmeaEntry, Nil) {
  list.reduce(entries, fn(best, e) {
    case e.rpn > best.rpn {
      True -> e
      False -> best
    }
  })
}

/// Count entries per priority tier.
/// Returns #(p0_count, p1_count, p2_count, p3_count).
pub fn priority_distribution(
  entries: List(FmeaEntry),
) -> #(Int, Int, Int, Int) {
  let p0 = list.count(entries, fn(e) { e.rpn >= 200 })
  let p1 = list.count(entries, fn(e) { e.rpn >= 100 && e.rpn < 200 })
  let p2 = list.count(entries, fn(e) { e.rpn >= 50 && e.rpn < 100 })
  let p3 = list.count(entries, fn(e) { e.rpn < 50 })
  #(p0, p1, p2, p3)
}

// ---------------------------------------------------------------------------
// Serialisation
// ---------------------------------------------------------------------------

/// Escape a string for safe embedding in a JSON string literal.
fn json_escape(s: String) -> String {
  s
  |> string.replace("\\", "\\\\")
  |> string.replace("\"", "\\\"")
}

/// Serialize a single FmeaEntry to a JSON object string.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <formal-proof>
///     <P> Pre: entry is a well-formed FmeaEntry </P>
///     <C> entry_to_json(entry) </C>
///     <Q> Post: valid JSON object string; all string fields are escaped </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn entry_to_json(e: FmeaEntry) -> String {
  "{"
  <> "\"component\":\""
  <> json_escape(e.component)
  <> "\","
  <> "\"failure_mode\":\""
  <> json_escape(e.failure_mode)
  <> "\","
  <> "\"severity\":"
  <> int.to_string(e.severity)
  <> ","
  <> "\"occurrence\":"
  <> int.to_string(e.occurrence)
  <> ","
  <> "\"detection\":"
  <> int.to_string(e.detection)
  <> ","
  <> "\"rpn\":"
  <> int.to_string(e.rpn)
  <> ","
  <> "\"mitigation\":\""
  <> json_escape(e.mitigation)
  <> "\","
  <> "\"layer\":\""
  <> json_escape(e.layer)
  <> "\""
  <> "}"
}

/// Serialize the full FMEA list to a JSON array string.
/// Suitable for Wisp API responses and Zenoh OTel payloads.
pub fn to_json(entries: List(FmeaEntry)) -> String {
  let items = list.map(entries, entry_to_json)
  "[" <> string.join(items, ",") <> "]"
}

/// Produce a concise text summary of the FMEA report.
/// Includes total entries, total RPN, and count per priority tier.
pub fn summary(entries: List(FmeaEntry)) -> String {
  let total = list.length(entries)
  let trpn = total_rpn(entries)
  let #(p0, p1, p2, p3) = priority_distribution(entries)
  "FMEA summary: "
  <> int.to_string(total)
  <> " entries, total RPN="
  <> int.to_string(trpn)
  <> " | P0="
  <> int.to_string(p0)
  <> " P1="
  <> int.to_string(p1)
  <> " P2="
  <> int.to_string(p2)
  <> " P3="
  <> int.to_string(p3)
}
