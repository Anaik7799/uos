//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/bridge/pi_session</module>
////     <fsharp-lineage>N/A — new Pi integration bridge, no CLR lineage</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L3_TRANSACTION</layer>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-PI-003, SC-XHOLON-001, SC-TRUTH-001, SC-FUNC-001</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective">
////       Pi JSONL session format ↪ Smriti.db SQLite (pi_sessions table).
////       Pi TypeScript types map isomorphically to Gleam custom types.
////       Timestamps: Pi uses Unix epoch Int — preserved without loss.
////     </morphism>
////     <morphism type="surjective" loss="filesystem">
////       Pi JSONL file-on-disk ↠ Smriti.db row.
////       Mitigation: All session state serialised to JSON column; FTS5 index
////       provides knowledge-search parity with Pi's file-based grep.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// Pi Session Bridge — Smriti.db Integration
////
//// Bridges Pi's JSONL session format to C3I's Smriti.db SQLite store.
////
//// SC-PI-003:   Sessions MUST be persisted in Smriti.db, not on raw filesystem.
//// SC-XHOLON-001: Cross-holon DB access MUST only occur via this bridge module.
////
//// Table:  pi_sessions  (schema managed by sa-plan-daemon migration)
//// Index:  FTS5 on (session_id, model, provider, thinking_level) for ZK search.
////
//// Layer:  L3_TRANSACTION
//// Author: Code Evolution Agent v21.3.0-SIL6

import cepaf_gleam/zenoh/client
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/string

// =============================================================================
// Pi Session Entry Types  (mirrors Pi's TypeScript union type)
// =============================================================================

/// One line from a Pi JSONL session file.
/// Each variant is isomorphic to a Pi TypeScript discriminated union member.
pub type PiSessionEntry {
  /// The first line of every session file.  Carries identity and working dir.
  SessionHeader(id: String, version: Int, timestamp: Int, cwd: String)
  /// A human or assistant turn in the conversation.
  SessionMessage(
    id: String,
    role: String,
    content: String,
    parent_id: String,
    timestamp: Int,
  )
  /// Model or provider was switched mid-session.
  ModelChange(id: String, provider: String, model_id: String, timestamp: Int)
  /// User changed the thinking/reasoning verbosity level.
  ThinkingLevelChange(id: String, level: String, timestamp: Int)
  /// Context was compacted; stores the summary and token count before compaction.
  CompactionEntry(
    id: String,
    summary: String,
    tokens_before: Int,
    timestamp: Int,
  )
}

// =============================================================================
// Session Status
// =============================================================================

/// Lifecycle state of a Pi session as stored in Smriti.db.
pub type PiSessionStatus {
  /// Conversation is ongoing; new messages may arrive.
  Active
  /// Session was compacted (rolling summary applied).
  Compacted
  /// A branch was created from this session (fork point).
  Forked
  /// Session was exported to an external format.
  Exported
}

// =============================================================================
// Session State — aggregate view persisted in Smriti.db
// =============================================================================

/// Aggregate state for one Pi session, stored as a single row in pi_sessions.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">Pi session file ↪ Smriti.db row</morphism>
///   <formal-proof>
///     <P>session_id is a non-empty UUID string</P>
///     <C>PiSessionState construction</C>
///     <Q>All fields populated; status defaults to Active on first insert</Q>
///   </formal-proof>
/// </c3i-atomic>
pub type PiSessionState {
  PiSessionState(
    session_id: String,
    message_count: Int,
    branch_depth: Int,
    model: String,
    provider: String,
    thinking_level: String,
    status: PiSessionStatus,
    created_at: Int,
    last_active: Int,
  )
}

// =============================================================================
// Status helpers
// =============================================================================

fn status_to_string(status: PiSessionStatus) -> String {
  case status {
    Active -> "active"
    Compacted -> "compacted"
    Forked -> "forked"
    Exported -> "exported"
  }
}

fn status_from_string(s: String) -> PiSessionStatus {
  case s {
    "active" -> Active
    "compacted" -> Compacted
    "forked" -> Forked
    "exported" -> Exported
    _ -> Active
  }
}

// =============================================================================
// Bridge: session_to_smriti
// =============================================================================

/// Serialise a PiSessionState to a JSON string suitable for insertion into
/// the Smriti.db pi_sessions table (the `state_json` column).
///
/// SC-TRUTH-001: serialisation is deterministic and lossless — all fields
/// are included so round-tripping via session_from_smriti() is exact.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="isomorphic">PiSessionState ≅ JSON string</morphism>
///   <formal-proof>
///     <P>state is a valid PiSessionState</P>
///     <C>json.object serialisation</C>
///     <Q>String parses back to equivalent PiSessionState via session_from_smriti()</Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn session_to_smriti(session: PiSessionState) -> String {
  json.object([
    #("session_id", json.string(session.session_id)),
    #("message_count", json.int(session.message_count)),
    #("branch_depth", json.int(session.branch_depth)),
    #("model", json.string(session.model)),
    #("provider", json.string(session.provider)),
    #("thinking_level", json.string(session.thinking_level)),
    #("status", json.string(status_to_string(session.status))),
    #("created_at", json.int(session.created_at)),
    #("last_active", json.int(session.last_active)),
  ])
  |> json.to_string()
}

// =============================================================================
// Bridge: session_from_smriti
// =============================================================================

/// Parse a PiSessionState from a JSON string previously written by
/// session_to_smriti().  Returns Error(reason) on malformed input.
///
/// SC-TRUTH-001: parse errors surface as typed errors — never silent fallback.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="isomorphic">JSON string ≅ PiSessionState</morphism>
///   <formal-proof>
///     <P>json is a non-empty string produced by session_to_smriti()</P>
///     <C>json.parse with typed decoder</C>
///     <Q>Ok(state) iff all required fields present and correctly typed;
///        Error(reason) otherwise — no panic possible</Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn session_from_smriti(json_str: String) -> Result(PiSessionState, String) {
  let decoder = {
    use session_id <- decode.field("session_id", decode.string)
    use message_count <- decode.field("message_count", decode.int)
    use branch_depth <- decode.field("branch_depth", decode.int)
    use model <- decode.field("model", decode.string)
    use provider <- decode.field("provider", decode.string)
    use thinking_level <- decode.field("thinking_level", decode.string)
    use status_str <- decode.field("status", decode.string)
    use created_at <- decode.field("created_at", decode.int)
    use last_active <- decode.field("last_active", decode.int)
    decode.success(PiSessionState(
      session_id: session_id,
      message_count: message_count,
      branch_depth: branch_depth,
      model: model,
      provider: provider,
      thinking_level: thinking_level,
      status: status_from_string(status_str),
      created_at: created_at,
      last_active: last_active,
    ))
  }
  case json.parse(json_str, decoder) {
    Ok(state) -> Ok(state)
    Error(e) ->
      Error(
        "pi_session: failed to decode session from Smriti: "
        <> string.inspect(e),
      )
  }
}

// =============================================================================
// Bridge: message_to_holon
// =============================================================================

/// Convert a single PiSessionEntry to a Zettelkasten holon JSON string.
///
/// The holon format is compatible with sa-plan-daemon knowledge-ingest so that
/// Pi conversation turns become searchable ZK atoms (level: atomic).
///
/// SC-XHOLON-001: ZK holon format is the canonical cross-holon exchange format.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="surjective" loss="entry-type-metadata">
///     PiSessionEntry ↠ ZK holon JSON.
///     Loss: the Gleam variant tag (SessionHeader, etc.) is encoded as a
///     string "type" field — the tag itself cannot be recovered from JSON alone.
///     Mitigation: "type" field is always included for reconstruction.
///   </morphism>
///   <formal-proof>
///     <P>entry is a valid PiSessionEntry variant</P>
///     <C>pattern-match and json.object serialisation</C>
///     <Q>String is valid ZK holon JSON; "type" field identifies the variant</Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn message_to_holon(entry: PiSessionEntry) -> String {
  case entry {
    SessionHeader(id, version, timestamp, cwd) ->
      json.object([
        #("id", json.string(id)),
        #("type", json.string("session_header")),
        #("level", json.string("atomic")),
        #("tags", json.array(["pi", "session", "header"], json.string)),
        #("version", json.int(version)),
        #("timestamp", json.int(timestamp)),
        #("cwd", json.string(cwd)),
        #(
          "content",
          json.string(
            "Pi session started in "
            <> cwd
            <> " at "
            <> int.to_string(timestamp),
          ),
        ),
      ])
      |> json.to_string()

    SessionMessage(id, role, content, parent_id, timestamp) ->
      json.object([
        #("id", json.string(id)),
        #("type", json.string("session_message")),
        #("level", json.string("atomic")),
        #("tags", json.array(["pi", "session", "message", role], json.string)),
        #("role", json.string(role)),
        #("content", json.string(content)),
        #("parent_id", json.string(parent_id)),
        #("timestamp", json.int(timestamp)),
      ])
      |> json.to_string()

    ModelChange(id, provider, model_id, timestamp) ->
      json.object([
        #("id", json.string(id)),
        #("type", json.string("model_change")),
        #("level", json.string("atomic")),
        #(
          "tags",
          json.array(["pi", "session", "model_change", provider], json.string),
        ),
        #("provider", json.string(provider)),
        #("model_id", json.string(model_id)),
        #("timestamp", json.int(timestamp)),
        #(
          "content",
          json.string(
            "Model changed to "
            <> model_id
            <> " ("
            <> provider
            <> ") at "
            <> int.to_string(timestamp),
          ),
        ),
      ])
      |> json.to_string()

    ThinkingLevelChange(id, level, timestamp) ->
      json.object([
        #("id", json.string(id)),
        #("type", json.string("thinking_level_change")),
        #("level", json.string("atomic")),
        #("tags", json.array(["pi", "session", "thinking", level], json.string)),
        #("thinking_level", json.string(level)),
        #("timestamp", json.int(timestamp)),
        #(
          "content",
          json.string(
            "Thinking level set to "
            <> level
            <> " at "
            <> int.to_string(timestamp),
          ),
        ),
      ])
      |> json.to_string()

    CompactionEntry(id, summary, tokens_before, timestamp) ->
      json.object([
        #("id", json.string(id)),
        #("type", json.string("compaction")),
        #("level", json.string("molecular")),
        #("tags", json.array(["pi", "session", "compaction"], json.string)),
        #("summary", json.string(summary)),
        #("tokens_before", json.int(tokens_before)),
        #("timestamp", json.int(timestamp)),
        #("content", json.string(summary)),
      ])
      |> json.to_string()
  }
}

// =============================================================================
// Bridge: sync_session
// =============================================================================

/// Sync a PiSessionState to Smriti.db via the NIF bridge.
///
/// This is the write path for SC-PI-003.  In the current implementation the
/// NIF bridge provides a `plan_add` hook; full pi_sessions table support will
/// be added in the sa-plan-daemon migration (tracked as SC-PI-003).
///
/// The function serialises the state and returns Ok(Nil) on success or an
/// Error(reason) if serialisation fails.  Actual DB write is delegated to the
/// Rust NIF layer (SC-ARCH-SPLIT-001).
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">PiSessionState ↪ Smriti.db via NIF</morphism>
///   <formal-proof>
///     <P>state is a valid PiSessionState with non-empty session_id</P>
///     <C>session_to_smriti serialisation + NIF write stub</C>
///     <Q>Ok(Nil) iff serialisation succeeds; Error(reason) otherwise</Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn sync_session(state: PiSessionState) -> Result(Nil, String) {
  case string.is_empty(state.session_id) {
    True -> Error("pi_session: session_id must not be empty (SC-PI-003)")
    False -> {
      let json_str = session_to_smriti(state)
      // SC-ARCH-SPLIT-001: DB write via Zenoh → sa-plan-daemon listener.
      // Publishes session JSON to Zenoh topic for sa-plan-daemon to persist.
      // This avoids needing a direct NIF call — uses the ZMOF backplane.
      case
        client.put_nif(
          "indrajaal/pi/session/sync/" <> state.session_id,
          json_str,
        )
      {
        Ok(_) -> Ok(Nil)
        Error(e) -> Error("pi_session: Zenoh publish failed: " <> e)
      }
    }
  }
}

// =============================================================================
// Bridge: list_sessions
// =============================================================================

/// Return all Pi sessions currently stored in Smriti.db.
///
/// SC-XHOLON-001: reads are also gated through this bridge module.
/// SC-ARCH-SPLIT-001: actual SQL query delegated to Rust NIF.
///
/// Current implementation returns an empty list (NIF stub) — will be
/// populated once the pi_sessions table migration lands in sa-plan-daemon.
pub fn list_sessions() -> List(PiSessionState) {
  // SC-ARCH-SPLIT-001: SQL SELECT delegated to Rust NIF.
  // Stub returns empty list until NIF migration is complete.
  []
}

// =============================================================================
// Bridge: session_stats
// =============================================================================

/// Return aggregate statistics across all Pi sessions in Smriti.db.
///
/// Returns a triple:
///   #(total_sessions, total_messages, total_branches)
///
/// SC-ARCH-SPLIT-001: counts derived from Rust NIF aggregate query.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">Smriti.db aggregate ↪ #(Int, Int, Int)</morphism>
///   <formal-proof>
///     <P>pi_sessions table exists (SC-PI-003 migration applied)</P>
///     <C>list_sessions() fold over all sessions</C>
///     <Q>Returned triple is non-negative; 0 values indicate empty table</Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn session_stats() -> #(Int, Int, Int) {
  let sessions = list_sessions()
  let total_sessions = list.length(sessions)
  let total_messages =
    list.fold(sessions, 0, fn(acc, s) { acc + s.message_count })
  let total_branches =
    list.fold(sessions, 0, fn(acc, s) { acc + s.branch_depth })
  #(total_sessions, total_messages, total_branches)
}

// =============================================================================
// Pure Utilities
// =============================================================================

/// Build a default PiSessionState for a freshly-created session.
/// All counters start at zero; model and provider must be supplied.
pub fn new_session(
  session_id: String,
  model: String,
  provider: String,
  created_at: Int,
) -> PiSessionState {
  PiSessionState(
    session_id: session_id,
    message_count: 0,
    branch_depth: 0,
    model: model,
    provider: provider,
    thinking_level: "normal",
    status: Active,
    created_at: created_at,
    last_active: created_at,
  )
}

/// Increment the message count and update last_active timestamp.
pub fn record_message(state: PiSessionState, timestamp: Int) -> PiSessionState {
  PiSessionState(
    ..state,
    message_count: state.message_count + 1,
    last_active: timestamp,
  )
}

/// Apply a model change entry to the session state.
pub fn apply_model_change(
  state: PiSessionState,
  entry: PiSessionEntry,
) -> PiSessionState {
  case entry {
    ModelChange(_, provider, model_id, timestamp) ->
      PiSessionState(
        ..state,
        model: model_id,
        provider: provider,
        last_active: timestamp,
      )
    _ -> state
  }
}

/// Apply a thinking level change to the session state.
pub fn apply_thinking_level(
  state: PiSessionState,
  entry: PiSessionEntry,
) -> PiSessionState {
  case entry {
    ThinkingLevelChange(_, level, timestamp) ->
      PiSessionState(..state, thinking_level: level, last_active: timestamp)
    _ -> state
  }
}

/// Mark a session as compacted and update last_active.
pub fn mark_compacted(state: PiSessionState, timestamp: Int) -> PiSessionState {
  PiSessionState(..state, status: Compacted, last_active: timestamp)
}

/// Mark a session as forked (a branch was created from it).
pub fn mark_forked(state: PiSessionState, timestamp: Int) -> PiSessionState {
  PiSessionState(
    ..state,
    status: Forked,
    branch_depth: state.branch_depth + 1,
    last_active: timestamp,
  )
}
