import cepaf_gleam/harness/telegram_system_read_command as cmd
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/string
import gleeunit/should

fn status_of(reply: String) -> String {
  let assert Ok(s) = json.parse(reply, decode.at(["status"], decode.string))
  s
}

fn keys_of(reply: String) -> List(String) {
  let assert Ok(keys) =
    json.parse(reply, decode.dict(decode.string, decode.dynamic))
  keys |> dict_keys |> list.sort(string.compare)
}

@external(erlang, "maps", "keys")
fn dict_keys(d: a) -> List(String)

fn field(reply: String, name: String) -> String {
  let assert Ok(v) = json.parse(reply, decode.at([name], decode.string))
  v
}

fn assert_closed_shape(reply: String) {
  { string.byte_size(reply) <= 3500 } |> should.equal(True)
  case status_of(reply) {
    "ok" ->
      keys_of(reply)
      |> should.equal(["backend", "command", "observation", "status"])
    "backend_unavailable" ->
      keys_of(reply) |> should.equal(["backend", "command", "reason", "status"])
    "denied" -> keys_of(reply) |> should.equal(["command", "reason", "status"])
    _ -> should.fail()
  }
}

pub fn catalog_lists_exactly_six_literals_test() {
  cmd.literals()
  |> should.equal([
    "/immune", "/inference", "/rack-cv", "/acoustic", "/acoustic-hud", "/radar",
  ])
}

// ---- /immune ----
pub fn immune_reports_actor_backend_unavailable_test() {
  let r = cmd.handle("/immune", "")
  status_of(r) |> should.equal("backend_unavailable")
  field(r, "backend") |> should.equal("cepaf_gleam/immune/system")
  field(r, "command") |> should.equal("/immune")
}

pub fn immune_rejects_arguments_test() {
  let r = cmd.handle("/immune", "halt")
  status_of(r) |> should.equal("denied")
  string.contains(field(r, "reason"), "Usage: /immune") |> should.equal(True)
}

// ---- /inference ----
pub fn inference_observes_configured_cascade_test() {
  let r = cmd.handle("/inference", "")
  status_of(r) |> should.equal("ok")
  field(r, "backend") |> should.equal("cepaf_gleam/ui/lustre/inference_tier")
  string.contains(r, "\"live_status\":\"not_observed\"") |> should.equal(True)
  string.contains(r, "Modular MAX / Mojo") |> should.equal(True)
  string.contains(r, "\"tier_count\":7") |> should.equal(True)
  string.contains(r, "infer_text") |> should.equal(True)
  // Defaults are not live: no circuit or latency is claimed.
  string.contains(r, "circuit") |> should.equal(False)
  string.contains(r, "latency") |> should.equal(False)
}

pub fn inference_rejects_arguments_test() {
  let r = cmd.handle("/inference", "prompt=hello")
  status_of(r) |> should.equal("denied")
  string.contains(r, "hello") |> should.equal(False)
}

// ---- /rack-cv ----
pub fn rack_cv_reports_no_vision_backend_test() {
  let r = cmd.handle("/rack-cv", "  \t")
  status_of(r) |> should.equal("backend_unavailable")
  field(r, "backend") |> should.equal("cepaf_gleam/harness/multimodal_features")
  string.contains(r, "nvme") |> should.equal(False)
}

pub fn rack_cv_rejects_photo_reference_test() {
  status_of(cmd.handle("/rack-cv", "photo-chassis-01"))
  |> should.equal("denied")
}

// ---- /acoustic ----
pub fn acoustic_reports_no_sample_backend_test() {
  let r = cmd.handle("/acoustic", "")
  status_of(r) |> should.equal("backend_unavailable")
  field(r, "backend")
  |> should.equal("cepaf_gleam/services/max_inference_daemon")
  string.contains(r, "1240") |> should.equal(False)
}

pub fn acoustic_rejects_sample_argument_test() {
  status_of(cmd.handle("/acoustic", "audio-exhaust-sample"))
  |> should.equal("denied")
}

// ---- /acoustic-hud ----
pub fn acoustic_hud_reads_real_shruti_audit_test() {
  let r = cmd.handle("/acoustic-hud", "")
  status_of(r) |> should.equal("ok")
  field(r, "backend")
  |> should.equal("cepaf_gleam/knowledge/raga_cybernetic_synthesis")
  string.contains(r, "\"total_shrutis\":22") |> should.equal(True)
  string.contains(r, "\"teentaal_beats\":16") |> should.equal(True)
  string.contains(r, "\"durga_swaras\":6") |> should.equal(True)
  string.contains(r, "\"just_intonation_verified\":true") |> should.equal(True)
  string.contains(r, "\"live_sensor\":\"not_observed\"") |> should.equal(True)
}

pub fn acoustic_hud_rejects_engage_argument_test() {
  let r = cmd.handle("/acoustic-hud", "engage")
  status_of(r) |> should.equal("denied")
  string.contains(field(r, "reason"), "no arguments") |> should.equal(True)
}

// ---- /radar ----
pub fn radar_reports_no_live_feed_test() {
  let r = cmd.handle("/radar", "")
  status_of(r) |> should.equal("backend_unavailable")
  field(r, "backend")
  |> should.equal("cepaf_gleam/ui/lustre/biosemiotics_radar")
  // Hardware serial must never be echoed.
  string.contains(r, "25503L801736") |> should.equal(False)
}

pub fn radar_rejects_oversized_arguments_test() {
  status_of(cmd.handle("/radar", string.repeat("a", 257)))
  |> should.equal("denied")
}

// ---- shared ----
pub fn unknown_literals_are_denied_test() {
  list.each(["/status", "", "/IMMUNE", "immune", "/immune ", "/radar\n"], fn(l) {
    let r = cmd.handle(l, "")
    status_of(r) |> should.equal("denied")
    field(r, "reason")
    |> should.equal("not handled by telegram_system_read_command")
  })
}

pub fn overlong_unknown_literal_is_not_echoed_in_full_test() {
  let r = cmd.handle(string.repeat("x", 5000), "")
  status_of(r) |> should.equal("denied")
  { string.byte_size(r) < 300 } |> should.equal(True)
}

pub fn every_reply_is_closed_shape_json_within_bound_test() {
  list.each(cmd.literals(), fn(l) {
    assert_closed_shape(cmd.handle(l, ""))
    assert_closed_shape(cmd.handle(l, "x"))
  })
  assert_closed_shape(cmd.handle("/nope", ""))
}

pub fn ok_replies_only_from_the_two_observable_backends_test() {
  let oks =
    list.filter(cmd.literals(), fn(l) { status_of(cmd.handle(l, "")) == "ok" })
  oks |> should.equal(["/inference", "/acoustic-hud"])
}
