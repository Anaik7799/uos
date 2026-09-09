import cepaf_gleam/ecology/external_capabilities as external
import gleam/option.{None, Some}
import gleam/list
import gleam/string
import gleeunit/should
import uos_swarm/openrouter_worker as worker

const input = "{\"model\":\"openrouter/free\",\"prompt\":\"Describe one bounded feedback-loop invariant.\",\"max_tokens\":128}"

fn io(key, price, response) {
  worker.Io(
    credential: fn() { key },
    fetch_prices: fn(_) { Ok(#(200, price)) },
    post: fn(_, body, _) {
      string.contains(body, "\"max_price\":{\"prompt\":0.0,\"completion\":0.0,\"request\":0.0}") |> should.be_true
      Ok(#(200, response))
    },
    now_ms: fn() { 0 },
  )
}

const prices = "{\"data\":[{\"id\":\"openrouter/free\",\"pricing\":{\"prompt\":\"0\",\"completion\":\"0\"}}]}"
const reply = "{\"id\":\"test\",\"model\":\"provider/free-model\",\"provider\":\"test\",\"choices\":[{\"message\":{\"content\":\"Require fresh feedback.\"},\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":10,\"completion_tokens\":5,\"total_tokens\":15,\"cost\":0.0}}"

pub fn missing_key_is_unavailable_test() {
  external.openrouter_with(input, io(None, "invalid", "invalid")) |> should.be_error
}

pub fn free_receipt_is_actual_reply_test() {
  let assert Ok(receipt) = external.openrouter_with(input, io(Some("unit-test"), prices, reply))
  string.contains(receipt, "Require fresh feedback") |> should.be_true
}

pub fn price_increase_is_refused_test() {
  external.openrouter_with(input, io(Some("unit-test"), string.replace(prices, "\"prompt\":\"0\"", "\"prompt\":\"0.1\""), reply))
  |> should.be_error
}

pub fn provider_charge_is_refused_test() {
  external.openrouter_with(input, io(Some("unit-test"), prices, string.replace(reply, "\"cost\":0.0", "\"cost\":0.01")))
  |> should.be_error
}

pub fn invalid_or_oversized_request_is_refused_test() {
  external.decode_request("{}") |> should.be_error
  external.decode_request(string.replace(input, "128", "513")) |> should.be_error
}

pub fn malformed_success_does_not_earn_capability_credit_test() {
  [
    "{\"choices\":[]}",
    string.replace(reply, "Require fresh feedback.", "  "),
    string.replace(reply, "\"model\":\"provider/free-model\"", "\"model\":\"\""),
    string.replace(reply, "\"prompt_tokens\":10", "\"prompt_tokens\":-10"),
    string.replace(reply, "\"completion_tokens\":5", "\"completion_tokens\":-5"),
    string.replace(reply, "\"total_tokens\":15", "\"total_tokens\":99"),
    string.replace(reply, ",\"cost\":0.0", ""),
    string.replace(reply, "\"cost\":0.0", "\"cost\":-0.01"),
  ] |> list.each(fn(body) {
    external.openrouter_with(input, io(Some("unit-test"), prices, body)) |> should.be_error
  })
}

pub fn unknown_completion_price_refuses_before_dispatch_test() {
  let no_post = worker.Io(..io(Some("unit-test"),
    string.replace(prices, "\"completion\":\"0\"", "\"completion\":\"unknown\""), reply),
    post: fn(_, _, _) { panic as "Unknown price must not dispatch" })
  external.openrouter_with(input, no_post) |> should.be_error
}
