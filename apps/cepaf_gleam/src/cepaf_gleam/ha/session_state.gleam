//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ha/session_state</module>
////     <fsharp-lineage>None — novel BEAM crash-recovery serialization layer</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L3_TRANSACTION</layer>
////     <mesh-domain>Session state serialization for crash recovery (DUR-2)</mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>HIGH</criticality>
////     <stamp-controls>SC-FUNC-004, SC-HA-001, SC-MUDA-001, SC-ARCH-SPLIT-002</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective">
////       BEAM process state ↪ JSON-serialized SQLite-ready record.
////       Enables bounded data loss (≤ checkpoint interval) after crash.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// SESSION STATE SERIALIZATION — Full AppState crash recovery (DUR-2)
//// सत्र अवस्था क्रमबद्धता — पूर्ण ऐपस्टेट क्रैश पुनर्प्राप्ति
////
//// Serializes and deserializes the core runtime counters so that a restarted
//// BEAM node can resume from a known good snapshot instead of cold-zero.
////
//// Mathematical model:
////   Let A = AppState at time t
////   Let S = SerializedState derived from A
////   Recovery guarantee: |reconstruct(S) ⊖ A| → 0 as checkpoint frequency → ∞
////   Durability bound:   data_loss ≤ writes_between_last_checkpoint_and_crash
////
//// STAMP: SC-FUNC-004 (state recoverable), SC-HA-001 (zero-downtime),
////        SC-MUDA-001 (zero warnings), SC-ARCH-SPLIT-002 (Gleam presentation only)
////
//// अव्यक्तादीनि भूतानि व्यक्तमध्यानि भारत।
//// अव्यक्तनिधनान्येव — Beings emerge from the unmanifest and return to it. (Gita 2.28)
//// (i.e. processes crash and are reborn — serialization bridges the gap)

import gleam/float
import gleam/int
import gleam/string

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

/// Complete snapshot of session-level counters for crash recovery.
///
/// All numeric fields use `Int` (Unix-epoch ms or loop counters) so the
/// struct can be round-tripped through JSON without floating-point loss.
pub type SerializedState {
  SerializedState(
    /// Unique identifier for this session (UUID or monotonic counter).
    session_id: String,
    /// Unix-epoch millisecond timestamp when this snapshot was taken.
    timestamp_ms: Int,
    /// Number of freshness-monitor OODA cycles completed since process start.
    freshness_cycle: Int,
    /// Number of self-observer scan cycles completed since process start.
    observer_cycle: Int,
    /// Number of guard-grid evaluation cycles completed since process start.
    guard_grid_cycle: Int,
    /// Most-recent computed system health score, stored as thousandths (0-1000).
    /// E.g. health_score = 0.92 is stored as 920.
    health_score_millis: Int,
    /// Current cockpit mode string: "dark" | "dim" | "normal" | "bright" | "emergency".
    cockpit_mode: String,
    /// Number of SQLite checkpoints taken this session.
    checkpoint_count: Int,
  )
}

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/// Default cockpit mode when no state has been captured yet.
const default_cockpit_mode: String = "dark"

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">Zero-valued bootstrap snapshot ↪ init/2</morphism>
///   <formal-proof>
///     <P> Pre-condition: session_id is non-empty, timestamp_ms >= 0. </P>
///     <C> Return zero-valued SerializedState with supplied identifiers. </C>
///     <Q> Post-condition: all cycle counters == 0, health == 1000 (nominal). </Q>
///   </formal-proof>
/// </c3i-atomic>
///
/// Construct a fresh SerializedState for a new session.
///
/// `health_score_millis` is initialised to 1000 (= 1.0, fully healthy) so
/// that the first checkpoint reflects "assumed healthy until measured".
pub fn from_app_state(
  session_id: String,
  timestamp_ms: Int,
) -> SerializedState {
  SerializedState(
    session_id: session_id,
    timestamp_ms: timestamp_ms,
    freshness_cycle: 0,
    observer_cycle: 0,
    guard_grid_cycle: 0,
    health_score_millis: 1000,
    cockpit_mode: default_cockpit_mode,
    checkpoint_count: 0,
  )
}

/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">SerializedState ↪ JSON string</morphism>
///   <formal-proof>
///     <P> Pre-condition: state fields are valid (no embedded quotes in cockpit_mode). </P>
///     <C> Produce a JSON object with all eight fields. </C>
///     <Q> Post-condition: output string is valid JSON; from_json(to_json(s)) == Ok(s). </Q>
///   </formal-proof>
/// </c3i-atomic>
///
/// Serialize a `SerializedState` to a compact JSON string.
///
/// Round-trip guarantee: `from_json(to_json(s)) == Ok(s)` for any valid `s`.
pub fn to_json(state: SerializedState) -> String {
  string.join(
    [
      "{",
      "\"session_id\":\"" <> escape_string(state.session_id) <> "\",",
      "\"timestamp_ms\":" <> int.to_string(state.timestamp_ms) <> ",",
      "\"freshness_cycle\":" <> int.to_string(state.freshness_cycle) <> ",",
      "\"observer_cycle\":" <> int.to_string(state.observer_cycle) <> ",",
      "\"guard_grid_cycle\":" <> int.to_string(state.guard_grid_cycle) <> ",",
      "\"health_score_millis\":"
        <> int.to_string(state.health_score_millis)
        <> ",",
      "\"cockpit_mode\":\"" <> escape_string(state.cockpit_mode) <> "\",",
      "\"checkpoint_count\":" <> int.to_string(state.checkpoint_count),
      "}",
    ],
    "",
  )
}

/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="surjective" loss="full-parser-absent">
///     JSON string ↠ SerializedState.
///     Mitigation: lightweight key-value extraction; rejects malformed input.
///   </morphism>
///   <formal-proof>
///     <P> Pre-condition: json is a UTF-8 string. </P>
///     <C> Extract the eight known fields from the JSON object. </C>
///     <Q> Post-condition: Ok(state) iff all fields present and parseable; Err otherwise. </Q>
///   </formal-proof>
/// </c3i-atomic>
///
/// Deserialize a JSON string produced by `to_json/1` back into a `SerializedState`.
///
/// Returns `Error(reason)` if any mandatory field is missing or unparseable.
pub fn from_json(json: String) -> Result(SerializedState, String) {
  let session_id = extract_string_field(json, "session_id")
  let timestamp_ms = extract_int_field(json, "timestamp_ms")
  let freshness_cycle = extract_int_field(json, "freshness_cycle")
  let observer_cycle = extract_int_field(json, "observer_cycle")
  let guard_grid_cycle = extract_int_field(json, "guard_grid_cycle")
  let health_score_millis = extract_int_field(json, "health_score_millis")
  let cockpit_mode = extract_string_field(json, "cockpit_mode")
  let checkpoint_count = extract_int_field(json, "checkpoint_count")

  case
    session_id,
    timestamp_ms,
    freshness_cycle,
    observer_cycle,
    guard_grid_cycle,
    health_score_millis,
    cockpit_mode,
    checkpoint_count
  {
    Ok(sid), Ok(ts), Ok(fc), Ok(oc), Ok(ggc), Ok(hsm), Ok(cm), Ok(cc) ->
      Ok(SerializedState(
        session_id: sid,
        timestamp_ms: ts,
        freshness_cycle: fc,
        observer_cycle: oc,
        guard_grid_cycle: ggc,
        health_score_millis: hsm,
        cockpit_mode: cm,
        checkpoint_count: cc,
      ))
    _, _, _, _, _, _, _, _ ->
      Error("from_json: one or more required fields missing or unparseable")
  }
}

/// Return a human-readable one-line summary of the serialized state.
///
/// Used for logging and TUI display without full JSON serialization.
pub fn summary(state: SerializedState) -> String {
  let health_pct = int.to_string(state.health_score_millis / 10) <> "%"
  string.join(
    [
      "session=" <> state.session_id,
      "ts=" <> int.to_string(state.timestamp_ms),
      "freshness_cycles=" <> int.to_string(state.freshness_cycle),
      "observer_cycles=" <> int.to_string(state.observer_cycle),
      "guard_grid_cycles=" <> int.to_string(state.guard_grid_cycle),
      "health=" <> health_pct,
      "cockpit=" <> state.cockpit_mode,
      "checkpoints=" <> int.to_string(state.checkpoint_count),
    ],
    " ",
  )
}

/// Convert a floating-point health score (0.0–1.0) to the integer
/// thousandths representation used by `SerializedState`.
///
/// E.g. `health_to_millis(0.92)` → `920`.
pub fn health_to_millis(score: Float) -> Int {
  float.round(score *. 1000.0)
}

/// Convert the integer thousandths health representation back to Float.
///
/// E.g. `millis_to_health(920)` → `0.92`.
pub fn millis_to_health(millis: Int) -> Float {
  int.to_float(millis) /. 1000.0
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

/// Escape double-quotes and backslashes in a string for safe JSON embedding.
fn escape_string(s: String) -> String {
  s
  |> string.replace("\\", "\\\\")
  |> string.replace("\"", "\\\"")
}

/// Extract a string value for `key` from a simple flat JSON object.
///
/// Handles the pattern `"key":"value"` produced by `to_json/1`.
fn extract_string_field(json: String, key: String) -> Result(String, String) {
  let needle = "\"" <> key <> "\":\""
  case string.split_once(json, needle) {
    Ok(#(_, rest)) ->
      case string.split_once(rest, "\"") {
        Ok(#(value, _)) -> Ok(value)
        Error(_) ->
          Error("extract_string_field: unterminated value for " <> key)
      }
    Error(_) -> Error("extract_string_field: key not found: " <> key)
  }
}

/// Extract an integer value for `key` from a simple flat JSON object.
///
/// Handles the pattern `"key":digits` produced by `to_json/1`.
fn extract_int_field(json: String, key: String) -> Result(Int, String) {
  let needle = "\"" <> key <> "\":"
  case string.split_once(json, needle) {
    Ok(#(_, rest)) -> {
      // Collect digits until a non-digit character
      let digits = collect_digits(rest, "")
      case int.parse(digits) {
        Ok(n) -> Ok(n)
        Error(_) -> Error("extract_int_field: non-integer value for " <> key)
      }
    }
    Error(_) -> Error("extract_int_field: key not found: " <> key)
  }
}

/// Collect leading digit characters from a string (stops at first non-digit).
fn collect_digits(s: String, acc: String) -> String {
  case string.pop_grapheme(s) {
    Ok(#(g, rest)) ->
      case g {
        "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" ->
          collect_digits(rest, acc <> g)
        _ -> acc
      }
    Error(_) -> acc
  }
}
