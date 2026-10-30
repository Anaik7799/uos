//// T16 transport acceptance tests: supervised stdio framing bounds and
//// authenticated Zenoh ingress with pinned reply destinations.

import cepaf_gleam/harness/value
import cepaf_gleam/mcp/principal
import cepaf_gleam/mcp/transports/stdio
import cepaf_gleam/mcp/transports/zenoh
import cepaf_gleam/mcp/types.{
  type Outcome, type ToolError, Complete, EvidenceRecord, Legacy20241105,
  NonRetryable, Refused, ToolError,
}
import cepaf_gleam/mcp/wire
import gleam/json
import gleam/list
import gleam/option.{Some}
import gleam/string
import gleeunit/should

// ---------------------------------------------------------------------------
// stdio
// ---------------------------------------------------------------------------

pub fn split_frame_and_slow_frame_are_bounded_test() {
  let assert Ok(session) = default_session()

  // A single frame delivered across two chunks is reassembled, not truncated.
  let first = "{\"jsonrpc\":\"2.0\",\"id\":1,"
  let assert Ok(#(after_first, emitted_first)) =
    stdio.ingest_chunk(session, first, 0, complete_handler)
  emitted_first |> should.equal([])
  after_first.buffer |> should.equal(first)

  let assert Ok(#(after_second, emitted_second)) =
    stdio.ingest_chunk(
      after_first,
      "\"method\":\"ping\"}\n",
      100,
      complete_handler,
    )
  emitted_second |> list.length |> should.equal(1)
  after_second.buffer |> should.equal("")
  after_second.stdout_frames |> list.length |> should.equal(1)

  // A partial frame that outlives its absolute deadline is refused.
  let assert Ok(slow) = session_with_deadline(1000)
  let assert Ok(#(slow_partial, _)) =
    stdio.ingest_chunk(
      slow,
      "{\"jsonrpc\":\"2.0\",\"id\":2,",
      0,
      complete_handler,
    )
  let assert Error(deadline_error) =
    stdio.ingest_chunk(
      slow_partial,
      "\"method\":\"ping\"}",
      2000,
      complete_handler,
    )
  deadline_error.code |> should.equal("STDIO_FRAME_DEADLINE_EXCEEDED")

  // A buffered frame larger than the byte bound is refused before decode.
  let oversized = string.repeat("a", stdio.max_frame_bytes + 1)
  let assert Error(size_error) =
    stdio.ingest_chunk(session, oversized, 0, complete_handler)
  size_error.code |> should.equal("STDIO_FRAME_TOO_LARGE")

  // JSON nesting deeper than 32 is refused before decode.
  let deep =
    string.repeat("{\"a\":", stdio.max_json_depth + 1)
    <> "1"
    <> string.repeat("}", stdio.max_json_depth + 1)
    <> "\n"
  let assert Error(depth_error) =
    stdio.ingest_chunk(session, deep, 0, complete_handler)
  depth_error.code |> should.equal("STDIO_JSON_DEPTH_EXCEEDED")

  // NUL bytes never cross the boundary.
  let assert Error(nul_error) =
    stdio.ingest_chunk(session, "{\"a\":\"\u{0000}\"}\n", 0, complete_handler)
  nul_error.code |> should.equal("STDIO_NUL_BYTE_FORBIDDEN")

  // JSON-escaped NUL (\\u0000) is equally forbidden, not just the raw byte.
  let assert Error(escaped_nul_error) =
    stdio.ingest_chunk(session, "{\"a\":\"\\u0000\"}\n", 0, complete_handler)
  escaped_nul_error.code |> should.equal("STDIO_NUL_BYTE_FORBIDDEN")

  // A leftover partial frame at EOF is a truncation, not a silent close.
  let assert Ok(#(truncated, _)) =
    stdio.ingest_chunk(
      session,
      "{\"jsonrpc\":\"2.0\",\"id\":3",
      0,
      complete_handler,
    )
  let assert Error(eof_error) = stdio.handle_eof(truncated)
  eof_error.code |> should.equal("STDIO_TRUNCATED_FRAME_AT_EOF")

  // A clean EOF closes the session, and closed sessions refuse further chunks.
  let assert Ok(closed) = stdio.handle_eof(session)
  let assert Error(closed_error) =
    stdio.ingest_chunk(closed, "}\n", 0, complete_handler)
  closed_error.code |> should.equal("STDIO_SESSION_CLOSED")
}

// ---------------------------------------------------------------------------
// Zenoh topic grammar
// ---------------------------------------------------------------------------

pub fn malformed_zenoh_topic_has_no_unknown_fallback_test() {
  let malformed_topics = [
    "indrajaal/mcp/request",
    "indrajaal/mcp/request/client-1",
    "indrajaal/mcp/request/client-1/req-1/extra",
    "indrajaal/mcp/request//req-1",
    "indrajaal/mcp/request/client-1/",
    "indrajaal/mcp/request/cl*ent/req-1",
    "indrajaal/mcp/request/cl?ent/req-1",
    "indrajaal/mcp/request/../req-1",
    "indrajaal/mcp/request/client-1/req.1",
    "indrajaal/mcp/request/client 1/req-1",
  ]
  list.each(malformed_topics, fn(topic) {
    let envelope = envelope_with_topic(topic, "indrajaal/control/actuate")
    let assert Error(error) =
      zenoh.handle_envelope(
        "secret",
        True,
        Legacy20241105,
        "client-1",
        envelope,
        complete_handler,
      )
    error.code |> should.equal("MALFORMED_ZENOH_TOPIC")
    string.contains(error.reason, "unknown") |> should.be_false()
  })

  // REST-only Zenoh cannot host subscriptions.
  let assert Error(rest_error) = zenoh.verify_subscription_capability(False)
  rest_error.code |> should.equal("ZENOH_SUBSCRIPTIONS_UNSUPPORTED")

  let valid =
    envelope_with_topic(
      "indrajaal/mcp/request/client-1/req-1",
      "indrajaal/mcp/response/client-1/req-1",
    )
  let assert Error(rest_envelope_error) =
    zenoh.handle_envelope(
      "secret",
      False,
      Legacy20241105,
      "client-1",
      valid,
      complete_handler,
    )
  rest_envelope_error.code |> should.equal("ZENOH_SUBSCRIPTIONS_UNSUPPORTED")
}

// ---------------------------------------------------------------------------
// Zenoh reply pinning and signatures
// ---------------------------------------------------------------------------

pub fn zenoh_empty_secret_is_refused_test() {
  // An empty or whitespace-only shared secret can never authenticate an
  // envelope; it is refused before the signature comparison.
  let envelope =
    envelope_with_topic(
      "indrajaal/mcp/request/client-1/req-1",
      "indrajaal/mcp/response/client-1/req-1",
    )
  list.each(["", "   "], fn(secret) {
    let assert Error(error) =
      zenoh.handle_envelope(
        secret,
        True,
        Legacy20241105,
        "client-1",
        envelope,
        complete_handler,
      )
    error.code |> should.equal("ZENOH_SECRET_REQUIRED")
    error.retryability |> should.equal(NonRetryable)
  })
}

pub fn foreign_reply_destination_refused_test() {
  let secret = "shared-secret"
  let topic = "indrajaal/mcp/request/client-1/req-1"
  let reply_topic = "indrajaal/mcp/response/client-1/req-1"
  let payload = "{\"jsonrpc\":\"2.0\",\"id\":\"abc\",\"method\":\"ping\"}"
  let signature =
    zenoh.compute_signature(
      secret,
      topic,
      reply_topic,
      "actor-1",
      "test-client",
      "/workspace",
      "session-1",
      payload,
    )
  let valid =
    zenoh.SignedZenohEnvelope(
      topic: topic,
      reply_topic: reply_topic,
      sender_actor: "actor-1",
      client_name: "test-client",
      workspace_root: "/workspace",
      session_id: "session-1",
      payload: payload,
      signature: signature,
    )

  let assert Ok(Some(#(pinned_topic, body))) =
    zenoh.handle_envelope(
      secret,
      True,
      Legacy20241105,
      "client-1",
      valid,
      complete_handler,
    )
  pinned_topic |> should.equal(reply_topic)
  frame_is_jsonrpc(body) |> should.be_true()

  // A control topic or another client's key is never an acceptable reply target.
  list.each(
    ["indrajaal/control/actuate", "indrajaal/mcp/response/other-client/req-1"],
    fn(foreign) {
      let assert Error(error) =
        zenoh.handle_envelope(
          secret,
          True,
          Legacy20241105,
          "client-1",
          zenoh.SignedZenohEnvelope(..valid, reply_topic: foreign),
          complete_handler,
        )
      error.code |> should.equal("FOREIGN_REPLY_DESTINATION_FORBIDDEN")
    },
  )

  // A tampered signature over the pinned destination is refused.
  let assert Error(signature_error) =
    zenoh.handle_envelope(
      secret,
      True,
      Legacy20241105,
      "client-1",
      zenoh.SignedZenohEnvelope(..valid, signature: "deadbeef"),
      complete_handler,
    )
  signature_error.code |> should.equal("ZENOH_SIGNATURE_INVALID")

  // A tampered client_name is covered by the signature and refused.
  let assert Error(client_name_error) =
    zenoh.handle_envelope(
      secret,
      True,
      Legacy20241105,
      "client-1",
      zenoh.SignedZenohEnvelope(..valid, client_name: "other-profile"),
      complete_handler,
    )
  client_name_error.code |> should.equal("ZENOH_SIGNATURE_INVALID")
}

// ---------------------------------------------------------------------------
// stdout purity
// ---------------------------------------------------------------------------

pub fn stdout_contains_only_jsonrpc_test() {
  let assert Ok(session) = default_session()

  // Diagnostics (malformed JSON) must never leak to stdout.
  let assert Ok(#(after_diag, diag_stdout)) =
    stdio.ingest_chunk(session, "not-json\n", 0, complete_handler)
  diag_stdout |> should.equal([])
  { list.length(after_diag.stderr_logs) > 0 } |> should.be_true()

  // A notification produces no response frame.
  let assert Ok(#(after_notification, notification_stdout)) =
    stdio.ingest_chunk(
      after_diag,
      "{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}\n",
      10,
      complete_handler,
    )
  notification_stdout |> should.equal([])

  // A normal request produces exactly one response frame.
  let assert Ok(#(after_request, request_stdout)) =
    stdio.ingest_chunk(
      after_notification,
      "{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"ping\"}\n",
      20,
      complete_handler,
    )
  request_stdout |> list.length |> should.equal(1)

  // A refused request still emits a well-formed JSON-RPC error object.
  let assert Ok(#(after_refusal, refusal_stdout)) =
    stdio.ingest_chunk(
      after_request,
      "{\"jsonrpc\":\"2.0\",\"id\":8,\"method\":\"ping\"}\n",
      30,
      refused_handler,
    )
  refusal_stdout |> list.length |> should.equal(1)

  after_refusal.stdout_frames |> list.length |> should.equal(2)
  list.each(after_refusal.stdout_frames, fn(frame) {
    frame_is_jsonrpc(frame) |> should.be_true()
  })
  { list.length(after_refusal.stderr_logs) > 0 } |> should.be_true()
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn default_session() -> Result(stdio.StdioSession, ToolError) {
  session_with_deadline(stdio.default_frame_deadline_ms)
}

fn session_with_deadline(
  deadline_ms: Int,
) -> Result(stdio.StdioSession, ToolError) {
  stdio.new_session(
    actor_id: "actor-1",
    client_name: "test-client",
    workspace_root: "/workspace",
    session_id: "session-1",
    profile: Legacy20241105,
    deadline_ms: deadline_ms,
  )
}

fn complete_handler(
  _principal: principal.Principal,
  message: wire.NormalizedMessage,
) -> Outcome {
  Complete(
    message.canonical_json,
    EvidenceRecord(
      candidate: "test",
      route: "test/route",
      tool: "ping",
      declaration_state: "declared",
      implementation_state: "implemented",
      execution_state: "executed",
      formal_state: "verified",
      admission_state: "admitted",
      output_sha256: "0",
    ),
  )
}

fn refused_handler(
  _principal: principal.Principal,
  _message: wire.NormalizedMessage,
) -> Outcome {
  Refused(ToolError("TEST_REFUSED", "refused by test handler", NonRetryable))
}

fn envelope_with_topic(
  topic: String,
  reply_topic: String,
) -> zenoh.SignedZenohEnvelope {
  zenoh.SignedZenohEnvelope(
    topic: topic,
    reply_topic: reply_topic,
    sender_actor: "actor-1",
    client_name: "test-client",
    workspace_root: "/workspace",
    session_id: "session-1",
    payload: "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\"}",
    signature: "unused-for-topic-tests",
  )
}

fn frame_is_jsonrpc(frame: String) -> Bool {
  case json.parse(frame, value.decoder()) {
    Ok(value.Object(fields)) ->
      list.any(fields, fn(field) {
        field.0 == "jsonrpc" && field.1 == value.Text("2.0")
      })
    _ -> False
  }
}
