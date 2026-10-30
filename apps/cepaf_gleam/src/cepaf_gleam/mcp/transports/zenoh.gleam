//// T16 Authenticated Zenoh ingress for MCP. Requests arrive as signed envelopes
//// on a strict `indrajaal/mcp/request/{client}/{request}` topic grammar, and the
//// reply destination is pinned to the matching response key. REST-only Zenoh
//// (no subscriptions) is refused because it cannot host an MCP request stream.

import cepaf_gleam/harness/files
import cepaf_gleam/mcp/principal
import cepaf_gleam/mcp/types.{
  type Outcome, type ProtocolProfile, type ToolError, ClientProfile,
  NonRetryable, ToolError,
}
import cepaf_gleam/mcp/wire
import gleam/int
import gleam/list
import gleam/option.{type Option}
import gleam/result
import gleam/string

const request_prefix = "indrajaal/mcp/request/"

const response_prefix = "indrajaal/mcp/response/"

pub type SignedZenohEnvelope {
  SignedZenohEnvelope(
    topic: String,
    reply_topic: String,
    sender_actor: String,
    client_name: String,
    workspace_root: String,
    session_id: String,
    payload: String,
    signature: String,
  )
}

/// REST-only Zenoh deployments cannot host the MCP request stream. Fail closed
/// before any envelope is considered.
pub fn verify_subscription_capability(
  supports_subscriptions supports_subscriptions: Bool,
) -> Result(Nil, ToolError) {
  case supports_subscriptions {
    True -> Ok(Nil)
    False ->
      Error(ToolError(
        "ZENOH_SUBSCRIPTIONS_UNSUPPORTED",
        "REST-only Zenoh mode cannot host MCP subscriptions",
        NonRetryable,
      ))
  }
}

/// Deterministic signature over every authenticated envelope field, keyed by the
/// shared secret. Matching the digest is the only proof of sender authenticity.
pub fn compute_signature(
  shared_secret shared_secret: String,
  topic topic: String,
  reply_topic reply_topic: String,
  sender_actor sender_actor: String,
  client_name client_name: String,
  workspace_root workspace_root: String,
  session_id session_id: String,
  payload payload: String,
) -> String {
  [
    shared_secret,
    topic,
    reply_topic,
    sender_actor,
    client_name,
    workspace_root,
    session_id,
    payload,
  ]
  |> list.map(fn(field) {
    int.to_string(string.byte_size(field)) <> ":" <> field <> "|"
  })
  |> string.concat
  |> files.digest
}

/// Validate and dispatch one signed Zenoh envelope. Returns `Ok(Some(#(reply,
/// body)))` for a request that produced a wire frame, `Ok(None)` for a
/// notification, and a typed `ToolError` for any malformed or unauthenticated
/// input. The reply destination is never taken from untrusted input.
pub fn handle_envelope(
  shared_secret shared_secret: String,
  supports_subscriptions supports_subscriptions: Bool,
  profile profile: ProtocolProfile,
  expected_client_id expected_client_id: String,
  envelope envelope: SignedZenohEnvelope,
  handler handler: fn(principal.Principal, wire.NormalizedMessage) -> Outcome,
) -> Result(Option(#(String, String)), ToolError) {
  use _ <- result.try(verify_subscription_capability(supports_subscriptions))
  use #(client_id, request_id) <- result.try(parse_request_topic(envelope.topic))
  use _ <- result.try(check_client_id(client_id, expected_client_id))
  use _ <- result.try(check_reply_destination(
    client_id,
    request_id,
    envelope.reply_topic,
  ))
  use _ <- result.try(check_client_name(envelope.client_name))
  use _ <- result.try(check_signature(shared_secret, envelope))

  let principal =
    principal.from_signed_zenoh_envelope(
      actor: envelope.sender_actor,
      client: ClientProfile(envelope.client_name),
      workspace_root: envelope.workspace_root,
      session_id: envelope.session_id,
    )
  case wire.decode_request(profile, envelope.payload) {
    Error(error) -> Error(ToolError(error.code, error.reason, NonRetryable))
    Ok(message) -> {
      let outcome = handler(principal, message)
      Ok(
        option.map(wire.encode_outcome(profile, message.id, outcome), fn(body) {
          #(envelope.reply_topic, body)
        }),
      )
    }
  }
}

fn parse_request_topic(topic: String) -> Result(#(String, String), ToolError) {
  case string.split(topic, "/") {
    ["indrajaal", "mcp", "request", client_id, request_id] ->
      case valid_token(client_id) && valid_token(request_id) {
        True -> Ok(#(client_id, request_id))
        False -> Error(topic_error())
      }
    _ -> Error(topic_error())
  }
}

fn check_client_id(
  client_id: String,
  expected_client_id: String,
) -> Result(Nil, ToolError) {
  case client_id == expected_client_id {
    True -> Ok(Nil)
    False -> Error(topic_error())
  }
}

fn check_reply_destination(
  client_id: String,
  request_id: String,
  reply_topic: String,
) -> Result(Nil, ToolError) {
  let expected = response_prefix <> client_id <> "/" <> request_id
  case reply_topic == expected {
    True -> Ok(Nil)
    False ->
      Error(ToolError(
        "FOREIGN_REPLY_DESTINATION_FORBIDDEN",
        "Reply destination is not the pinned response key for this request",
        NonRetryable,
      ))
  }
}

fn check_client_name(client_name: String) -> Result(Nil, ToolError) {
  case client_name {
    "" ->
      Error(ToolError(
        "ZENOH_CLIENT_NAME_REQUIRED",
        "Envelope client_name must not be empty",
        NonRetryable,
      ))
    _ -> Ok(Nil)
  }
}

fn check_signature(
  shared_secret: String,
  envelope: SignedZenohEnvelope,
) -> Result(Nil, ToolError) {
  let expected =
    compute_signature(
      shared_secret,
      envelope.topic,
      envelope.reply_topic,
      envelope.sender_actor,
      envelope.client_name,
      envelope.workspace_root,
      envelope.session_id,
      envelope.payload,
    )
  case expected == envelope.signature {
    True -> Ok(Nil)
    False ->
      Error(ToolError(
        "ZENOH_SIGNATURE_INVALID",
        "Envelope signature does not match the shared secret",
        NonRetryable,
      ))
  }
}

/// A topic segment is ASCII alphanumeric plus `-` and `_`. Wildcards, empty
/// segments, `..`, non-ASCII bytes, and extra separators are all rejected.
fn valid_token(token: String) -> Bool {
  case token {
    "" -> False
    _ ->
      token
      |> string.to_utf_codepoints
      |> list.all(fn(codepoint) {
        let code = string.utf_codepoint_to_int(codepoint)
        code >= 48
        && code <= 57
        || code >= 65
        && code <= 90
        || code >= 97
        && code <= 122
        || code == 45
        || code == 95
      })
  }
}

fn topic_error() -> ToolError {
  ToolError(
    "MALFORMED_ZENOH_TOPIC",
    "Topic must be indrajaal/mcp/request/{ascii-token}/{ascii-token}",
    NonRetryable,
  )
}
