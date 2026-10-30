import cepaf_gleam/mcp/profiles/legacy
import cepaf_gleam/mcp/profiles/modern
import cepaf_gleam/mcp/types.{
  Legacy20241105, Modern20260728, NonRetryable, Refused, ToolError,
}
import cepaf_gleam/mcp/version
import cepaf_gleam/mcp/wire
import gleam/dict
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should

pub fn legacy_initialize_and_modern_discovery_do_not_mix_test() {
  let legacy_init =
    legacy.dispatch(
      "initialize",
      dict.from_list([
        #("protocolVersion", "2024-11-05"),
        #("clientName", "conformance-client"),
        #("clientVersion", "1.0.0"),
      ]),
    )
  let assert Ok(legacy_json) = legacy_init
  string.contains(legacy_json, "2024-11-05") |> should.be_true()

  let assert Error(legacy_discovery_error) =
    legacy.dispatch("discovery/list", dict.new())
  legacy_discovery_error.code |> should.equal("PROFILE_METHOD_MISMATCH")

  let modern_init =
    modern.dispatch(
      "initialize",
      dict.from_list([
        #("protocolVersion", "2026-07-28"),
        #("clientName", "conformance-client"),
        #("clientVersion", "1.0.0"),
      ]),
    )
  let assert Ok(modern_json) = modern_init
  string.contains(modern_json, "2026-07-28") |> should.be_true()

  let assert Ok(discovery_json) = modern.dispatch("discovery/list", dict.new())
  string.contains(discovery_json, "discovery") |> should.be_true()

  let assert Error(modern_mix_error) =
    modern.dispatch("initialize_legacy", dict.new())
  modern_mix_error.code |> should.equal("PROFILE_METHOD_MISMATCH")
}

pub fn notification_is_silent_test() {
  let raw = "{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}"
  let assert Ok(message) = wire.decode_request(Modern20260728, raw)
  message.id |> should.equal(wire.NoIdNotification)

  let outcome =
    Refused(ToolError(
      code: "PATH_SECURITY_VIOLATION",
      reason: "refused",
      retryability: NonRetryable,
    ))
  wire.encode_outcome(Modern20260728, wire.NoIdNotification, outcome)
  |> should.equal(None)
}

pub fn unsupported_version_refused_test() {
  let assert Error(error) = version.negotiate("2019-01-01")
  error.code |> should.equal("UNSUPPORTED_PROTOCOL_VERSION")
  error.retryability |> should.equal(NonRetryable)

  version.negotiate("2024-11-05") |> should.equal(Ok(Legacy20241105))
  version.negotiate("2026-07-28") |> should.equal(Ok(Modern20260728))
}

pub fn retry_id_change_keeps_logical_effect_test() {
  let args = [#("plan_id", "p1"), #("task_id", "T1")]
  let first =
    wire.logical_effect_id("public", "sa_task_complete", args, None)
  let retried =
    wire.logical_effect_id(
      "public",
      "sa_task_complete",
      [#("task_id", "T1"), #("plan_id", "p1")],
      None,
    )
  first |> should.equal(retried)

  let explicit =
    wire.logical_effect_id("public", "sa_task_complete", args, Some("idem-1"))
  explicit |> should.not_equal(first)

  // Different transport ids decode to the same logical effect id.
  let assert Ok(first_message) =
    wire.decode_request(
      Modern20260728,
      "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"arguments\":{\"plan_id\":\"p1\",\"task_id\":\"T1\"}}}",
    )
  let assert Ok(second_message) =
    wire.decode_request(
      Modern20260728,
      "{\"jsonrpc\":\"2.0\",\"id\":99,\"method\":\"tools/call\",\"params\":{\"arguments\":{\"task_id\":\"T1\",\"plan_id\":\"p1\"}}}",
    )
  let first_effect =
    wire.logical_effect_id(
      "public",
      first_message.method,
      first_message.args,
      None,
    )
  let second_effect =
    wire.logical_effect_id(
      "public",
      second_message.method,
      second_message.args,
      None,
    )
  first_effect |> should.equal(second_effect)
  first_message.id |> should.not_equal(second_message.id)
}
