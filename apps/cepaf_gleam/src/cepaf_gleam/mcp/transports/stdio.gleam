//// T16 Supervised stdio transport: bounded, split-safe UTF-8 JSON-RPC framing
//// for MCP. Frames are newline-delimited, byte/depth bounded, and deadline
//// enforced. Only valid JSON-RPC response frames reach stdout; every diagnostic
//// is confined to stderr so hostile input can never forge protocol bytes.

import cepaf_gleam/harness/value
import cepaf_gleam/mcp/json_guard
import cepaf_gleam/mcp/principal.{type Principal}
import cepaf_gleam/mcp/types.{
  type Outcome, type ProtocolProfile, type ToolError, ClientProfile, Complete,
  NonRetryable, Refused, ToolError, Uncertain,
}
import cepaf_gleam/mcp/wire
import gleam/bit_array
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

/// Hard upper bound on a single JSON-RPC frame, in bytes.
pub const max_frame_bytes = 1_048_576

/// Maximum permitted JSON nesting depth for a complete frame.
pub const max_json_depth = 32

/// Default absolute deadline for an in-progress frame, in milliseconds.
pub const default_frame_deadline_ms = 5000

pub type StdioSession {
  StdioSession(
    principal: Principal,
    profile: ProtocolProfile,
    buffer: String,
    frame_started_at_ms: Option(Int),
    deadline_ms: Int,
    stdout_frames: List(String),
    stderr_logs: List(String),
    closed: Bool,
  )
}

/// Build a session bound to an admitted launcher environment. An empty actor or
/// workspace root is refused: transport policy never guesses a principal.
pub fn new_session(
  actor_id actor_id: String,
  client_name client_name: String,
  workspace_root workspace_root: String,
  session_id session_id: String,
  profile profile: ProtocolProfile,
  deadline_ms deadline_ms: Int,
) -> Result(StdioSession, ToolError) {
  case string.trim(actor_id), string.trim(workspace_root) {
    "", _ ->
      Error(ToolError(
        "STDIO_LAUNCHER_BINDING_REQUIRED",
        "actor_id must not be empty",
        NonRetryable,
      ))
    _, "" ->
      Error(ToolError(
        "STDIO_LAUNCHER_BINDING_REQUIRED",
        "workspace_root must not be empty",
        NonRetryable,
      ))
    _, _ ->
      Ok(StdioSession(
        principal: principal.from_launcher_env(
          actor: actor_id,
          client: ClientProfile(client_name),
          workspace_root: workspace_root,
          session_id: session_id,
        ),
        profile: profile,
        buffer: "",
        frame_started_at_ms: None,
        deadline_ms: deadline_ms,
        stdout_frames: [],
        stderr_logs: [],
        closed: False,
      ))
  }
}

/// Ingest one chunk of stdin. Returns the updated session and the response
/// frames newly produced by this chunk (the delta), in emission order.
pub fn ingest_chunk(
  session session: StdioSession,
  chunk chunk: String,
  now_ms now_ms: Int,
  handler handler: fn(Principal, wire.NormalizedMessage) -> Outcome,
) -> Result(#(StdioSession, List(String)), ToolError) {
  use _ <- result.try(check_open(session))
  use _ <- result.try(check_nul(chunk))
  use _ <- result.try(check_chunk_bounds(session, chunk))
  use _ <- result.try(check_deadline(session, now_ms))

  let started = case session.buffer, session.frame_started_at_ms {
    "", _ -> None
    _, Some(started_at) -> Some(started_at)
    _, None -> Some(now_ms)
  }
  let combined = session.buffer <> chunk
  let parts = string.split(combined, "\n")
  let drained = StdioSession(..session, buffer: "", frame_started_at_ms: None)
  process_parts(drained, parts, started, now_ms, handler, [])
}

/// Close a session at EOF. A non-empty trailing buffer means the peer emitted a
/// truncated frame and the session is refused rather than silently discarded.
pub fn handle_eof(
  session session: StdioSession,
) -> Result(StdioSession, ToolError) {
  case session.closed {
    True -> Ok(session)
    False ->
      case session.buffer {
        "" ->
          Ok(StdioSession(..session, frame_started_at_ms: None, closed: True))
        _ ->
          Error(ToolError(
            "STDIO_TRUNCATED_FRAME_AT_EOF",
            "Incomplete frame remained buffered at EOF",
            NonRetryable,
          ))
      }
  }
}

fn check_open(session: StdioSession) -> Result(Nil, ToolError) {
  case session.closed {
    True ->
      Error(ToolError(
        "STDIO_SESSION_CLOSED",
        "Session is closed and cannot accept further chunks",
        NonRetryable,
      ))
    False -> Ok(Nil)
  }
}

fn check_nul(chunk: String) -> Result(Nil, ToolError) {
  case
    string.contains(chunk, "\u{0000}")
    || string.contains(string.lowercase(chunk), "\\u0000")
  {
    True ->
      Error(ToolError(
        "STDIO_NUL_BYTE_FORBIDDEN",
        "NUL bytes, including JSON-escaped \\u0000, are forbidden in stdio frames",
        NonRetryable,
      ))
    False -> Ok(Nil)
  }
}

fn check_chunk_bounds(
  session: StdioSession,
  chunk: String,
) -> Result(Nil, ToolError) {
  let chunk_size = string.byte_size(chunk)
  case chunk_size > max_frame_bytes {
    True -> Error(frame_too_large_error())
    False ->
      case string.contains(chunk, "\n") {
        True -> Ok(Nil)
        False ->
          case string.byte_size(session.buffer) + chunk_size > max_frame_bytes {
            True -> Error(frame_too_large_error())
            False -> Ok(Nil)
          }
      }
  }
}

fn check_deadline(
  session: StdioSession,
  now_ms: Int,
) -> Result(Nil, ToolError) {
  case session.buffer, session.frame_started_at_ms {
    "", _ -> Ok(Nil)
    _, Some(started_at) ->
      case now_ms - started_at > session.deadline_ms {
        True ->
          Error(ToolError(
            "STDIO_FRAME_DEADLINE_EXCEEDED",
            "In-progress frame exceeded its absolute deadline",
            NonRetryable,
          ))
        False -> Ok(Nil)
      }
    _, None -> Ok(Nil)
  }
}

fn check_frame_size(frame: String) -> Result(Nil, ToolError) {
  case string.byte_size(frame) > max_frame_bytes {
    True -> Error(frame_too_large_error())
    False -> Ok(Nil)
  }
}

fn frame_too_large_error() -> ToolError {
  ToolError(
    "STDIO_FRAME_TOO_LARGE",
    "Frame exceeds the 1048576-byte limit",
    NonRetryable,
  )
}

fn check_depth(line: String) -> Result(Nil, ToolError) {
  case json_depth(line) > max_json_depth {
    True ->
      Error(ToolError(
        "STDIO_JSON_DEPTH_EXCEEDED",
        "Frame exceeds the maximum JSON nesting depth 32",
        NonRetryable,
      ))
    False -> Ok(Nil)
  }
}

fn process_parts(
  session: StdioSession,
  parts: List(String),
  started: Option(Int),
  now_ms: Int,
  handler: fn(Principal, wire.NormalizedMessage) -> Outcome,
  emitted_rev: List(String),
) -> Result(#(StdioSession, List(String)), ToolError) {
  case parts {
    [] -> Ok(#(session, list.reverse(emitted_rev)))
    [partial] -> {
      use _ <- result.try(check_frame_size(partial))
      let next_started = case partial, started {
        "", _ -> None
        _, Some(started_at) -> Some(started_at)
        _, None -> Some(now_ms)
      }
      Ok(#(
        StdioSession(
          ..session,
          buffer: partial,
          frame_started_at_ms: next_started,
        ),
        list.reverse(emitted_rev),
      ))
    }
    [line, ..rest] -> {
      use _ <- result.try(check_frame_size(line))
      use _ <- result.try(check_depth(line))
      // Preserve the legacy transport's diagnostic-only malformed-JSON path;
      // standard RPC ingress emits parse errors separately. Security refusal
      // must precede wire decoding at every object nesting depth.
      use _ <- result.try(case json_guard.inspect(line, "STDIO") {
        Ok(_) -> Ok(Nil)
        Error(error) ->
          case error.code {
            "INVALID_JSON_SYNTAX" -> Ok(Nil)
            _ -> Error(error)
          }
      })
      let #(next, emitted_rev) =
        handle_line(session, line, handler, emitted_rev)
      // Any remaining parts belong to a frame that started within this chunk.
      process_parts(next, rest, Some(now_ms), now_ms, handler, emitted_rev)
    }
  }
}

fn handle_line(
  session: StdioSession,
  line: String,
  handler: fn(Principal, wire.NormalizedMessage) -> Outcome,
  emitted_rev: List(String),
) -> #(StdioSession, List(String)) {
  case wire.decode_request(session.profile, line) {
    Error(error) -> {
      let next =
        log_diagnostic(
          session,
          "wire_reject:" <> error.code <> ":" <> error.reason,
        )
      #(next, emitted_rev)
    }
    Ok(message) -> {
      let outcome = handler(session.principal, message)
      let next = log_outcome(session, outcome)
      case wire.encode_outcome(session.profile, message.id, outcome) {
        None -> #(next, emitted_rev)
        Some(frame) ->
          case is_valid_jsonrpc_frame(frame) {
            True -> {
              let emitted =
                StdioSession(
                  ..next,
                  stdout_frames: list.append(next.stdout_frames, [frame]),
                )
              #(emitted, [frame, ..emitted_rev])
            }
            False -> #(
              log_diagnostic(next, "wire_reject:NON_JSONRPC_FRAME"),
              emitted_rev,
            )
          }
      }
    }
  }
}

fn log_outcome(session: StdioSession, outcome: Outcome) -> StdioSession {
  case outcome {
    Complete(_, _) -> session
    Refused(error) -> log_diagnostic(session, "outcome_refused:" <> error.code)
    Uncertain(receipt) ->
      log_diagnostic(session, "outcome_uncertain:" <> receipt.reason)
  }
}

fn log_diagnostic(session: StdioSession, message: String) -> StdioSession {
  StdioSession(
    ..session,
    stderr_logs: list.append(session.stderr_logs, [message]),
  )
}

/// Structural gate: a frame is only emitted after it parses as a JSON object
/// carrying `"jsonrpc":"2.0"`. Never trust an encoder blindly.
fn is_valid_jsonrpc_frame(frame: String) -> Bool {
  case json.parse(frame, value.decoder()) {
    Ok(value.Object(fields)) ->
      list.any(fields, fn(field) {
        field.0 == "jsonrpc" && field.1 == value.Text("2.0")
      })
    _ -> False
  }
}

/// Maximum bracket nesting depth of a JSON document, ignoring brackets inside
/// string literals and honoring backslash escapes. Malformed input yields the
/// observed depth and is rejected later by the wire decoder.
fn json_depth(text: String) -> Int {
  scan_depth(bit_array.from_string(text), False, False, 0, 0)
}

fn scan_depth(
  bytes: BitArray,
  in_string: Bool,
  escaped: Bool,
  depth: Int,
  maximum: Int,
) -> Int {
  case bytes, in_string, escaped {
    <<>>, _, _ -> maximum
    <<_, rest:bytes>>, True, True ->
      scan_depth(rest, True, False, depth, maximum)
    <<0x5c, rest:bytes>>, True, False ->
      scan_depth(rest, True, True, depth, maximum)
    <<0x22, rest:bytes>>, _, _ ->
      scan_depth(rest, !in_string, False, depth, maximum)
    <<0x7b, rest:bytes>>, False, _ | <<0x5b, rest:bytes>>, False, _ -> {
      let opened = depth + 1
      scan_depth(rest, False, False, opened, int_max(opened, maximum))
    }
    <<0x7d, rest:bytes>>, False, _ | <<0x5d, rest:bytes>>, False, _ ->
      scan_depth(rest, False, False, int_max(depth - 1, 0), maximum)
    <<_, rest:bytes>>, _, _ ->
      scan_depth(rest, in_string, False, depth, maximum)
    _, _, _ -> maximum
  }
}

fn int_max(a: Int, b: Int) -> Int {
  case a > b {
    True -> a
    False -> b
  }
}
