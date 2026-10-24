import cepaf_gleam/harness/telegram_bridge as bridge
import cepaf_gleam/harness/telegram_store_transport as transport
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import gleeunit/should

fn request() {
  let assert Ok(r) =
    bridge.new(
      "mapping-1",
      "fence",
      "controller",
      "owner",
      1,
      "runtime-bridge",
      1000,
    )
  r
}

fn body(historical, found, lease) {
  json.object([
    #("schema", json.string("uos.telegram.cancel-transport-response.v1")),
    #("status", json.string("ok")),
    #("error", json.null()),
    #(
      "result",
      json.object([
        #("schema", json.string("uos.sa-plan.bridge-bind-response.v1")),
        #("found", json.bool(found)),
        #("historical", json.bool(historical)),
        #("observed_at_ns", json.int(100)),
        #("lease", lease),
      ]),
    ),
  ])
  |> json.to_string
}

fn lease() {
  json.object([
    #("mapping_id", json.string("mapping-1")),
    #("plan_id", json.string("fence")),
    #("task_id", json.string("controller")),
    #("owner", json.string("owner")),
    #("task_attempt", json.int(1)),
    #("lease_id", json.string("runtime-bridge")),
    #("fencing_token", json.int(7)),
    #("expires_at_ns", json.int(1000)),
  ])
}

pub fn request_bounds_test() {
  list.each(
    ["", " ", "../bad", "a..b", "x\\n", "é", string.repeat("a", 241)],
    fn(value) {
      bridge.new(
        value,
        "fence",
        "controller",
        "owner",
        1,
        "runtime-bridge",
        1000,
      )
      |> result.is_error
      |> should.be_true
    },
  )
  list.each([0, -1, 2_147_483_648], fn(attempt) {
    bridge.new(
      "mapping-1",
      "fence",
      "controller",
      "owner",
      attempt,
      "lease",
      1000,
    )
    |> result.is_error
    |> should.be_true
  })
  list.each([0, -1, 9_223_372_036_854_775_808], fn(expiry) {
    bridge.new("mapping-1", "fence", "controller", "owner", 1, "lease", expiry)
    |> result.is_error
    |> should.be_true
  })
}

pub fn request_envelope_test() {
  bridge.envelope(request(), bridge.Bind)
  |> string.contains(bridge.request_json(request()))
  |> should.be_true
  bridge.envelope(request(), bridge.Lookup)
  |> string.contains("controller-bridge-result")
  |> should.be_true
}

pub fn found_bind_and_expired_history_test() {
  bridge.decode_response(
    request(),
    bridge.Bind,
    body(False, True, lease()),
    101,
  )
  |> should.equal(Ok(bridge.Found(7, 1000, 100, False)))
  bridge.decode_response(
    request(),
    bridge.Lookup,
    body(True, True, lease()),
    2000,
  )
  |> should.equal(Ok(bridge.Found(7, 1000, 100, True)))
}

pub fn exact_binding_test() {
  list.each(
    [
      #("mapping-1", "mapping-2"),
      #("fence", "other-plan"),
      #("controller", "other-task"),
      #("\"owner\":\"owner\"", "\"owner\":\"other\""),
      #("\"task_attempt\":1", "\"task_attempt\":2"),
      #("runtime-bridge", "other-lease"),
      #("\"expires_at_ns\":1000", "\"expires_at_ns\":1001"),
      #("\"fencing_token\":7", "\"fencing_token\":0"),
      #("\"fencing_token\":7", "\"fencing_token\":9223372036854775808"),
    ],
    fn(change) {
      body(False, True, lease())
      |> string.replace(change.0, change.1)
      |> bridge.decode_response(request(), bridge.Bind, _, 101)
      |> result.is_error
      |> should.be_true
    },
  )
}

pub fn strict_closed_response_test() {
  let good = body(False, True, lease())
  list.each(
    [
      "",
      "{}",
      "[]",
      string.repeat("x", 16_385),
      good |> string.replace("\"found\":true", "\"found\":true,\"found\":true"),
      good |> string.replace("\"found\":true", "\"found\":true,\"extra\":false"),
      good |> string.replace("\"task_attempt\":1", "\"task_attempt\":1.0"),
      good |> string.replace("\"fencing_token\":7", "\"fencing_token\":\"7\""),
      good |> string.replace("\"observed_at_ns\":100", "\"observed_at_ns\":-1"),
      good |> string.replace("\"observed_at_ns\":100", "\"observed_at_ns\":102"),
    ],
    fn(raw) {
      bridge.decode_response(request(), bridge.Bind, raw, 101)
      |> result.is_error
      |> should.be_true
    },
  )
}

pub fn operation_expiry_and_absence_test() {
  bridge.decode_response(request(), bridge.Bind, body(True, True, lease()), 101)
  |> result.is_error
  |> should.be_true
  bridge.decode_response(
    request(),
    bridge.Lookup,
    body(False, True, lease()),
    101,
  )
  |> result.is_error
  |> should.be_true
  bridge.decode_response(
    request(),
    bridge.Bind,
    body(False, True, lease()),
    1000,
  )
  |> result.is_error
  |> should.be_true
  bridge.decode_response(
    request(),
    bridge.Lookup,
    body(True, False, json.null()),
    101,
  )
  |> should.equal(Ok(bridge.Absent))
  bridge.decode_response(
    request(),
    bridge.Bind,
    body(False, False, json.null()),
    101,
  )
  |> result.is_error
  |> should.be_true
  let assert Ok(long) =
    bridge.new(
      "mapping-1",
      "fence",
      "controller",
      "owner",
      1,
      "runtime-bridge",
      300_000_000_101,
    )
  let raw =
    body(False, True, lease())
    |> string.replace(
      "\"expires_at_ns\":1000",
      "\"expires_at_ns\":300000000101",
    )
  bridge.decode_response(long, bridge.Bind, raw, 101)
  |> result.is_error
  |> should.be_true
}

pub fn rejection_is_not_success_test() {
  let raw =
    "{\"schema\":\"uos.telegram.cancel-transport-response.v1\",\"status\":\"rejected\",\"result\":null,\"error\":\"cancel_request_rejected\"}"
  bridge.decode_response(request(), bridge.Bind, raw, 101)
  |> should.equal(Ok(bridge.Rejected))
  raw
  |> string.replace("cancel_request_rejected", "private-details")
  |> bridge.decode_response(request(), bridge.Bind, _, 101)
  |> result.is_error
  |> should.be_true
}

type TimeUnit {
  Nanosecond
}

@external(erlang, "erlang", "system_time")
fn time(unit: TimeUnit) -> Int

/// Actual isolated native transport fixture; never a live service entrypoint.
pub fn run_native(
  config: transport.LocalConfiguration,
  mapping: String,
  expiry: Int,
) {
  let assert Ok(r) =
    bridge.new(
      mapping,
      "fence",
      "controller",
      "owner",
      1,
      "runtime-bridge",
      expiry,
    )
  let assert Ok(raw) =
    transport.exchange(config, bridge.envelope(r, bridge.Lookup))
  bridge.decode_response(r, bridge.Lookup, raw, time(Nanosecond))
  |> should.equal(Ok(bridge.Absent))
  let assert Ok(raw) =
    transport.exchange(config, bridge.envelope(r, bridge.Bind))
  let assert Ok(bridge.Found(1, saved_expiry, _, False)) =
    bridge.decode_response(r, bridge.Bind, raw, time(Nanosecond))
  saved_expiry |> should.equal(expiry)
  let assert Ok(raw) =
    transport.exchange(config, bridge.envelope(r, bridge.Bind))
  bridge.decode_response(r, bridge.Bind, raw, time(Nanosecond))
  |> should.equal(Ok(bridge.Rejected))
  let assert Ok(raw) =
    transport.exchange(config, bridge.envelope(r, bridge.Lookup))
  let assert Ok(bridge.Found(1, recovered_expiry, _, True)) =
    bridge.decode_response(r, bridge.Lookup, raw, time(Nanosecond))
  recovered_expiry |> should.equal(expiry)
  "bridge_bound_and_reconciled"
}
