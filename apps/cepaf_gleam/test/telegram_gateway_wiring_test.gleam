//// Wave 6q (review G-13): the gateway drain has a start site. A deployment
//// takes `gateway_drain_child` from a service configuration, adds it to a
//// supervisor, and ticks it with `gateway_tick`, whose Send goes through the
//// configuration's own HTTP client and is dropped after the tick. The
//// fixture plays Telegram: a Critical enqueued on the drain arrives as one
//// `sendMessage` and the report counts one delivery.

import cepaf_gleam/gateway/telegram_gateway_drain as drain
import cepaf_gleam/gateway/telegram_gateway_outbox as outbox
import cepaf_gleam/harness/telegram_delivery_ledger as ledger
import cepaf_gleam/harness/telegram_http_client as http_client
import cepaf_gleam/harness/telegram_service as service
import cepaf_gleam/harness/telegram_store_transport as transport
import gleam/dynamic.{type Dynamic}
import gleam/erlang/process.{type Pid}
import gleam/list
import gleam/option.{None}
import gleam/otp/static_supervisor as sup
import gleam/otp/system
import gleam/string
import gleeunit/should

@external(erlang, "telegram_http_test_fixture", "start")
fn fixture_start() -> Result(#(Pid, Int, String), Dynamic)

@external(erlang, "telegram_http_test_fixture", "stop")
fn fixture_stop(pid: Pid) -> Dynamic

@external(erlang, "telegram_http_test_fixture", "get_requests")
fn fixture_get_requests(pid: Pid) -> List(Dynamic)

const token = "test-bot-token-gateway-wiring"

fn config(base_url: String) -> service.ServiceConfiguration {
  service.development_service_configuration(
    transport.reviewed_local_configuration(
      "/tmp/uos-gateway-wiring-unused/guardian",
      "0",
      "/tmp/uos-gateway-wiring-unused/worker",
      "0",
      "/tmp/uos-gateway-wiring-unused/store.sqlite3",
    ),
    http_client.TelegramHttpConfiguration(
      base_url: base_url,
      bot_token: token,
      timeout_ms: 2000,
      max_response_bytes: 65_536,
    ),
    777,
    [#(100, 200)],
    "worker-gateway-wiring",
    1,
  )
}

fn request(kind: outbox.Kind, text: String) -> outbox.Request {
  outbox.Request(
    kind: kind,
    chat_id: 100,
    text: text,
    source_topic: "indrajaal/otel/span/critical",
    observed_at_ms: 1_700_000_000_000,
    digest: "digest-" <> text,
  )
}

pub fn drain_under_a_supervisor_delivers_a_critical_through_the_fixture_test() {
  let assert Ok(#(fixture_pid, _port, base_url)) = fixture_start()
  let cfg = config(base_url)
  let #(name, spec) = service.gateway_drain_child(cfg, 8)
  let assert Ok(_supervisor) =
    sup.new(sup.OneForOne)
    |> sup.add(spec)
    |> sup.start
  let d = process.named_subject(name)
  drain.enqueue(d, request(outbox.Critical, "disk full on nas-1"), 500)
  |> should.equal(Ok(Nil))
  drain.enqueue(d, request(outbox.Notice, "routine"), 500)
  |> should.equal(Ok(Nil))
  let report = service.gateway_tick(cfg, d, 1, 3000)
  report.selected |> should.equal(1)
  report.delivered |> should.equal(1)
  report.failed |> should.equal(0)
  let sends =
    list.filter(fixture_get_requests(fixture_pid), fn(r) {
      string.contains(string.inspect(r), "/sendMessage")
    })
  list.length(sends) |> should.equal(1)
  let rendered = string.inspect(sends)
  string.contains(rendered, "disk full on nas-1") |> should.be_true
  string.contains(rendered, "routine") |> should.be_false
  // The drain's state holds no closure and no token after the tick.
  let assert Ok(pid) = process.named(name)
  let state = string.inspect(system.get_state(pid))
  string.contains(state, token) |> should.be_false
  string.contains(string.lowercase(state), "token") |> should.be_false
  let counters = drain.counters(d, 500)
  counters.delivered |> should.equal(1)
  counters.pending |> should.equal(1)
  fixture_stop(fixture_pid)
}

pub fn send_maps_outcomes_without_leaking_text_test() {
  // An unreachable base_url yields an uncertain or failed status, never a
  // crash and never the token in the reason.
  let cfg = config("http://127.0.0.1:9")
  let send = service.gateway_send(cfg)
  let status = send(request(outbox.Critical, "x"))
  let rendered = string.inspect(status)
  string.contains(rendered, token) |> should.be_false
  case status {
    ledger.OutboxDelivered(_) -> should.fail()
    _ -> Nil
  }
}
