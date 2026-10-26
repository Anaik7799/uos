import cepaf_gleam/gateway/telegram
import cepaf_gleam/gateway/telegram_gateway_outbox as outbox
import gleam/json
import gleam/list
import gleam/string
import gleeunit/should

pub fn start_never_panics_and_reports_observed_state_test() {
  case telegram.start(42) {
    telegram.Unavailable(reason) -> string.length(reason) |> should.not_equal(0)
    telegram.Observed(subscribed: _, topic: topic) ->
      topic |> should.equal("indrajaal/otel/span/critical")
  }
}

pub fn start_is_not_fabricated_ignition_test() {
  let rendered = string.inspect(telegram.start(42))
  string.contains(rendered, "nominal") |> should.be_false()
  string.contains(rendered, "Ignition") |> should.be_false()
}

pub fn now_ms_is_a_real_clock_test() {
  { telegram.now_ms() > 1_700_000_000_000 } |> should.be_true()
}

pub fn enqueue_notification_stamps_host_clock_when_given_zero_test() {
  let q = outbox.new(4)
  let assert Ok(q) = telegram.enqueue_notification(q, 7, "hello", "topic/a", 0)
  let #(taken, _) = outbox.select(q, 1)
  let assert [r] = taken
  { r.observed_at_ms > 0 } |> should.be_true()
  r.kind |> should.equal(outbox.Notice)
  r.chat_id |> should.equal(7)
  r.source_topic |> should.equal("topic/a")
}

pub fn enqueue_notification_keeps_caller_time_test() {
  let assert Ok(q) =
    telegram.enqueue_notification(outbox.new(4), 7, "hello", "t", 1_234_567)
  let #(taken, _) = outbox.select(q, 1)
  let assert [r] = taken
  r.observed_at_ms |> should.equal(1_234_567)
}

pub fn enqueue_critical_is_selected_first_test() {
  let assert Ok(q) =
    telegram.enqueue_notification(outbox.new(4), 7, "n", "t", 1)
  let assert Ok(q) = telegram.enqueue_critical(q, 7, "c", "t", 2)
  let #(taken, _) = outbox.select(q, 1)
  let assert [r] = taken
  r.kind |> should.equal(outbox.Critical)
}

pub fn request_digest_is_stable_and_identity_bound_test() {
  let a = telegram.request_digest(outbox.Notice, 7, "t", "x")
  telegram.request_digest(outbox.Notice, 7, "t", "x") |> should.equal(a)
  telegram.request_digest(outbox.Notice, 8, "t", "x") |> should.not_equal(a)
  telegram.request_digest(outbox.Notice, 7, "u", "x") |> should.not_equal(a)
  telegram.request_digest(outbox.Notice, 7, "t", "y") |> should.not_equal(a)
  // Review G-03: the kind is part of the identity.
  telegram.request_digest(outbox.Critical, 7, "t", "x") |> should.not_equal(a)
  string.length(a) |> should.equal(64)
}

/// Review G-03: a Notice cannot pre-empt a Critical with the same text.
pub fn notice_then_identical_critical_ends_with_the_critical_queued_test() {
  let assert Ok(q) =
    telegram.enqueue_notification(outbox.new(4), 7, "disk full", "t", 1)
  let assert Ok(q) = telegram.enqueue_critical(q, 7, "disk full", "t", 2)
  let #(taken, _) = outbox.select(q, 1)
  let assert [r] = taken
  r.kind |> should.equal(outbox.Critical)
  r.text |> should.equal("disk full")
  // The reverse order is refused only for the second Critical, as a duplicate.
  telegram.enqueue_critical(q, 7, "disk full", "t", 3) |> should.be_error()
}

/// Review G-08: the Telegram refusal is case- and whitespace-insensitive.
pub fn telegram_channel_variants_are_refused_test() {
  let state = telegram.GatewayState(moz: telegram.new_moz_state(), chat_id: "c")
  ["telegram", "Telegram", "TELEGRAM", " telegram ", "\tTelegram\n"]
  |> list.each(fn(channel) {
    telegram.is_telegram_channel(channel) |> should.be_true()
    telegram.route_peer_notification(state, channel, "m") |> should.be_error()
  })
  telegram.is_telegram_channel("gchat") |> should.be_false()
  telegram.is_telegram_channel("telegram2") |> should.be_false()
}

pub fn duplicate_notification_is_refused_test() {
  let assert Ok(q) =
    telegram.enqueue_notification(outbox.new(4), 7, "x", "t", 1)
  telegram.enqueue_notification(q, 7, "x", "t", 2)
  |> should.be_error()
}

pub fn no_payload_or_request_mentions_a_credential_test() {
  let assert Ok(q) =
    telegram.enqueue_critical(outbox.new(4), 7, "alert", "t", 5)
  let #(taken, _) = outbox.select(q, 1)
  let request_text = string.lowercase(string.inspect(taken))
  string.contains(request_text, "token") |> should.be_false()
  string.contains(request_text, "bot_token") |> should.be_false()
  string.contains(request_text, "chat_secret") |> should.be_false()

  let state = telegram.GatewayState(moz: telegram.new_moz_state(), chat_id: "c")
  let payload =
    telegram.peer_params(state, "gchat", "m")
    |> json.to_string
    |> string.lowercase
  string.contains(payload, "token") |> should.be_false()
  string.contains(payload, "chat_secret") |> should.be_false()
}

pub fn telegram_channel_is_refused_on_moz_test() {
  let state = telegram.GatewayState(moz: telegram.new_moz_state(), chat_id: "c")
  telegram.route_peer_notification(state, "telegram", "m") |> should.be_error()
}
