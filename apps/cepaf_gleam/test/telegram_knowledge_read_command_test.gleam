import cepaf_gleam/config/mesh_source
import cepaf_gleam/harness/telegram_knowledge_read_command as cmd
import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should

// cwd for eunit is apps/cepaf_gleam, two levels below the repository root.
const root = "../.."

fn call(literal: String, args: String) -> String {
  cmd.handle_at(root, literal, args)
}

fn keys(reply: String) -> List(String) {
  let assert Ok(d) = gleam_json_parse(reply)
  d |> dict.keys |> list.sort(string.compare)
}

fn gleam_json_parse(reply: String) {
  json.parse(reply, decode.dict(decode.string, decode.dynamic))
}

fn field(reply: String, name: String) -> String {
  let assert Ok(d) = gleam_json_parse(reply)
  let assert Ok(v) = dict.get(d, name)
  let assert Ok(s) = decode.run(v, decode.string)
  s
}

fn status(reply: String) -> String {
  field(reply, "status")
}

fn observation_field(reply: String, name: String) -> decode.Dynamic {
  let assert Ok(d) = gleam_json_parse(reply)
  let assert Ok(o) = dict.get(d, "observation")
  let assert Ok(od) = decode.run(o, decode.dict(decode.string, decode.dynamic))
  let assert Ok(v) = dict.get(od, name)
  v
}

pub fn literal_catalog_test() {
  cmd.literals()
  |> should.equal(["/mesh", "/adr", "/pacing", "/postmortem", "/retro"])
}

pub fn unknown_literal_denied_test() {
  let r = call("/nope", "")
  status(r) |> should.equal("denied")
  field(r, "command") |> should.equal("/nope")
  field(r, "reason")
  |> should.equal("not handled by telegram_knowledge_read_command")
  keys(r) |> should.equal(["command", "reason", "status"])
}

pub fn mesh_positive_test() {
  let r = call("/mesh", "")
  status(r) |> should.equal("ok")
  field(r, "backend") |> should.equal("cepaf_gleam/config/mesh_source")
  decode.run(observation_field(r, "deployment_confirmed"), decode.bool)
  |> should.equal(Ok(False))
  decode.run(observation_field(r, "containers"), decode.int)
  |> should.equal(Ok(7))
  keys(r) |> should.equal(["backend", "command", "observation", "status"])
}

pub fn mesh_negative_test() {
  status(call("/mesh", "extra")) |> should.equal("denied")
  let bad = cmd.mesh_reply(mesh_source.from_environment(Some("not json")))
  status(bad) |> should.equal("backend_unavailable")
  keys(bad) |> should.equal(["backend", "command", "reason", "status"])
  let good = cmd.mesh_reply(mesh_source.from_environment(None))
  status(good) |> should.equal("ok")
}

pub fn adr_positive_test() {
  let listing = call("/adr", "")
  status(listing) |> should.equal("ok")
  decode.run(observation_field(listing, "highest_number"), decode.int)
  |> should.equal(Ok(137))
  let one = call("/adr", "1")
  status(one) |> should.equal("ok")
  decode.run(observation_field(one, "found"), decode.bool)
  |> should.equal(Ok(True))
  decode.run(observation_field(one, "file"), decode.string)
  |> should.equal(Ok(
    "20260904-150139-adr-001-closed-rete-fact-schema-and-strict-typing-invariant.md",
  ))
  { string.byte_size(one) <= 3500 } |> should.be_true
}

pub fn adr_negative_test() {
  status(call("/adr", "abc")) |> should.equal("denied")
  status(call("/adr", "0")) |> should.equal("denied")
  status(call("/adr", "1000")) |> should.equal("denied")
  status(call("/adr", "../etc")) |> should.equal("denied")
  let missing = call("/adr", "999")
  status(missing) |> should.equal("ok")
  decode.run(observation_field(missing, "found"), decode.bool)
  |> should.equal(Ok(False))
  let gone = cmd.handle_at("../../no-such-root", "/adr", "")
  status(gone) |> should.equal("backend_unavailable")
}

pub fn pacing_positive_and_negative_test() {
  let r = call("/pacing", "")
  status(r) |> should.equal("backend_unavailable")
  field(r, "backend") |> should.equal("cepaf_gleam/harness/telegram_creative")
  status(call("/pacing", "nap")) |> should.equal("backend_unavailable")
  status(call("/pacing", "now")) |> should.equal("denied")
  status(call("/pacing", string.repeat("a", 129))) |> should.equal("denied")
}

pub fn postmortem_positive_test() {
  let r = call("/postmortem", "3")
  status(r) |> should.equal("ok")
  field(r, "backend")
  |> should.equal("cepaf_gleam/harness/files (docs/journal)")
  let assert Ok(names) =
    decode.run(observation_field(r, "newest"), decode.list(decode.string))
  list.length(names) |> should.equal(3)
  names |> list.sort(string.compare) |> list.reverse |> should.equal(names)
}

pub fn postmortem_negative_test() {
  status(call("/postmortem", "0")) |> should.equal("denied")
  status(call("/postmortem", "21")) |> should.equal("denied")
  status(call("/postmortem", "x")) |> should.equal("denied")
  status(cmd.handle_at("../../no-such-root", "/postmortem", ""))
  |> should.equal("backend_unavailable")
}

pub fn retro_positive_test() {
  let r = call("/retro", "")
  status(r) |> should.equal("ok")
  let assert Ok(names) =
    decode.run(observation_field(r, "newest"), decode.list(decode.string))
  list.length(names) |> should.equal(10)
  decode.run(observation_field(r, "keyword"), decode.string)
  |> should.equal(Ok("retro"))
}

pub fn retro_negative_test() {
  status(call("/retro", "5; rm")) |> should.equal("denied")
  status(call("/retro", "-1")) |> should.equal("denied")
  status(cmd.handle_at("../../no-such-root", "/retro", ""))
  |> should.equal("backend_unavailable")
}

pub fn every_reply_is_bounded_and_closed_test() {
  let replies =
    list.flat_map(cmd.literals(), fn(l) {
      [
        call(l, ""),
        call(l, "1"),
        call(l, "zzz"),
        call(l, string.repeat("9", 300)),
      ]
    })
  list.each(replies, fn(r) {
    { string.byte_size(r) <= 3500 } |> should.be_true
    let allowed = [
      ["backend", "command", "observation", "status"],
      ["backend", "command", "reason", "status"],
      ["command", "reason", "status"],
    ]
    list.contains(allowed, keys(r)) |> should.be_true
  })
}
