import cepaf_gleam/harness/recovery_owner as c
import cepaf_gleam/harness/recovery_wire as w
import cepaf_gleam/harness/telegram_store_transport as t
import gleam/erlang/process
import gleam/json
import gleam/result
import gleam/string
import gleeunit/should

fn config() {
  let hex = string.repeat("0", 64)
  let factual =
    json.to_string(
      json.object([
        #("request_id", json.string("fixture")),
        #("plan", json.string("fixture")),
        #("snapshot_sha256", json.string("sha256:" <> hex)),
        #(
          "members",
          json.array(["a", "b", "c"], fn(id) {
            json.object([
              #("task_id", json.string(id)),
              #("worker", json.string("worker-" <> id)),
              #("old_attempt", json.int(1)),
              #("old_lease_ns", json.string("1")),
              #("lease_ms", json.int(1000)),
            ])
          }),
        ),
        #("deadline_utc_ms", json.int(1000)),
      ]),
    )
  let assert Ok(request) = w.decode(factual)
  let body = fn(op) {
    json.to_string(
      json.object([
        #("operation", json.string(op)),
        #("request", json.string(w.canonical_bytes(request))),
        #("capability", json.string("data-only")),
        #("reviewer_signature", json.string("fixture")),
        #("issuer_signature", json.string("fixture")),
      ]),
    )
  }
  let assert Ok(c) =
    c.configuration_data(
      "fixture",
      request,
      hex,
      body("commit"),
      body("inspect"),
      t.reviewed_local_configuration(
        "/unavailable",
        hex,
        "/unavailable",
        hex,
        "/unavailable",
      ),
      1000,
    )
  c
}

fn settled(owner, n) {
  let assert Ok(s) = c.get(owner, 1000)
  case s.in_flight && n > 0 {
    True -> {
      process.sleep(1)
      settled(owner, n - 1)
    }
    False -> s
  }
}

pub fn public_owner_has_no_production_activation_or_native_effect_test() {
  let assert Ok(owner) = c.start(config()) |> result.map(fn(s) { s.data })
  let s = settled(owner, 1000)
  s.phase |> should.equal(c.Unavailable)
  s.observed_effect_exchanges |> should.equal(0)
  c.commit(owner, c.Step(s.operation_id, s.revision), 1000) |> should.be_error()
  c.stop(owner, 1000) |> should.be_ok()
}

pub fn opaque_owner_checks_step_binding_and_wait_bounds_test() {
  let assert Ok(owner) = c.start(config()) |> result.map(fn(s) { s.data })
  let s = settled(owner, 1000)
  c.commit(owner, c.Step("different", s.revision), 1000) |> should.be_error()
  c.get(owner, 0) |> should.be_error()
  c.stop(owner, 1000) |> should.be_ok()
}
