import cepaf_gleam/harness/telegram_read_adapters as adapters
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should

const wave_one = [
  "/immune", "/inference", "/rack-cv", "/acoustic", "/acoustic-hud", "/radar",
  "/mesh", "/adr", "/pacing", "/postmortem", "/retro", "/whatif", "/simulate",
  "/babel", "/canvas", "/whiteboard",
]

fn status_of(reply: String) -> String {
  let assert Ok(s) =
    json.parse(reply, {
      use s <- decode.field("status", decode.string)
      decode.success(s)
    })
  s
}

pub fn every_wave_one_literal_is_routed_test() {
  list.sort(adapters.literals(), string.compare)
  |> should.equal(list.sort(wave_one, string.compare))
  list.each(wave_one, fn(name) {
    let assert Some(reply) = adapters.route(name, [])
    // Truthful shapes only: a real observation or a typed refusal.
    list.contains(["ok", "backend_unavailable", "denied"], status_of(reply))
    |> should.be_true
    { string.byte_size(reply) <= 3500 } |> should.be_true
  })
}

pub fn no_wave_one_literal_claims_ok_without_a_named_backend_test() {
  list.each(wave_one, fn(name) {
    let assert Some(reply) = adapters.route(name, [])
    let assert Ok(backend) =
      json.parse(reply, {
        use b <- decode.optional_field("backend", "", decode.string)
        decode.success(b)
      })
    case status_of(reply) {
      "denied" -> Nil
      _ ->
        { backend != "" && backend != "none" || status_of(reply) != "ok" }
        |> should.be_true
    }
  })
}

pub fn foreign_literals_fall_through_test() {
  adapters.route("/task", ["X"]) |> should.equal(None)
  adapters.route("/verify", []) |> should.equal(None)
  adapters.route("conversational", ["hello"]) |> should.equal(None)
}

pub fn args_are_joined_not_dropped_test() {
  // /adr takes a number; two tokens must reach the adapter as one text.
  let assert Some(with_args) = adapters.route("/adr", ["1", "extra"])
  let assert Some(without) = adapters.route("/adr", [])
  { with_args != without } |> should.be_true
}
