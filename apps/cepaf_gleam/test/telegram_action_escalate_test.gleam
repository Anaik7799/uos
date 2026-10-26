import cepaf_gleam/harness/telegram_action_escalate as action
import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/string
import gleeunit/should
import simplifile

fn keys(text: String) -> List(String) {
  let assert Ok(object) =
    json.parse(text, decode.dict(decode.string, decode.dynamic))
  dict.keys(object) |> list.sort(string.compare)
}

fn status_of(text: String) -> String {
  let decoder = {
    use status <- decode.field("status", decode.string)
    decode.success(status)
  }
  let assert Ok(status) = json.parse(text, decoder)
  status
}

fn is_error(r: Result(a, String)) -> Bool {
  case r {
    Ok(_) -> False
    Error(_) -> True
  }
}

fn req() {
  let assert Ok(r) = action.parse("400")
  r
}

fn at(age: String) {
  let assert Ok(r) = action.parse(age)
  r
}

pub fn literal_test() {
  action.literal() |> should.equal("/escalate")
}

pub fn parse_positive_test() {
  let assert Ok(a) = action.parse("90")
  let assert Ok(b) = action.parse("  90  ")
  let assert Ok(c) = action.parse("91")
  let assert Ok(_) = action.parse("0")
  let assert Ok(_) = action.parse("86400")
  action.effect_id(a) |> should.equal(action.effect_id(b))
  action.effect_id(a) |> should.not_equal(action.effect_id(c))
  string.starts_with(action.effect_id(a), "escalate-") |> should.equal(True)
  string.byte_size(action.effect_id(a)) |> should.equal(73)
}

pub fn parse_negative_test() {
  list.each(
    [
      "",
      "90 5",
      "-1",
      "86401",
      "9x",
      "abc",
      "1.5",
      "123456",
      "\u{0}",
      string.repeat("1", 257),
    ],
    fn(input) { action.parse(input) |> is_error |> should.equal(True) },
  )
  let assert Error(message) = action.parse(string.repeat("1", 257))
  string.starts_with(message, "args_bound") |> should.equal(True)
}

pub fn preview_shape_and_simulated_confidence_test() {
  let text = action.preview(req())
  status_of(text) |> should.equal("preview")
  keys(text)
  |> should.equal([
    "age_seconds", "approval_required", "authority", "cockpit_mode",
    "confidence", "effect", "effect_id", "jidoka_halt_in_plan", "literal",
    "notification_sent", "runbook_id", "runbook_severity", "runbook_steps",
    "staleness_level", "state_source", "status",
  ])
  string.contains(text, "\"confidence\":\"simulated\"") |> should.equal(True)
  string.contains(text, "\"notification_sent\":false") |> should.equal(True)
  { string.byte_size(text) <= 3500 } |> should.equal(True)
}

pub fn escalation_ladder_matches_the_backend_test() {
  let fresh = action.preview(at("30"))
  string.contains(fresh, "\"staleness_level\":\"fresh\"") |> should.equal(True)
  string.contains(fresh, "\"cockpit_mode\":\"normal\"") |> should.equal(True)
  string.contains(fresh, "\"runbook_id\":\"none\"") |> should.equal(True)
  let stale = action.preview(at("90"))
  string.contains(stale, "\"staleness_level\":\"stale\"") |> should.equal(True)
  string.contains(stale, "\"cockpit_mode\":\"dim\"") |> should.equal(True)
  string.contains(stale, "\"runbook_id\":\"RB-009\"") |> should.equal(True)
  let degraded = action.preview(at("200"))
  string.contains(degraded, "\"staleness_level\":\"degraded\"")
  |> should.equal(True)
  string.contains(degraded, "\"cockpit_mode\":\"bright\"") |> should.equal(True)
  let dead = action.preview(at("400"))
  string.contains(dead, "\"staleness_level\":\"dead\"") |> should.equal(True)
  string.contains(dead, "\"cockpit_mode\":\"emergency\"") |> should.equal(True)
  string.contains(dead, "\"runbook_id\":\"RB-010\"") |> should.equal(True)
  string.contains(dead, "\"jidoka_halt_in_plan\":true") |> should.equal(True)
  string.contains(stale, "\"jidoka_halt_in_plan\":false") |> should.equal(True)
}

pub fn ladder_boundaries_test() {
  string.contains(action.preview(at("59")), "\"staleness_level\":\"fresh\"")
  |> should.equal(True)
  string.contains(action.preview(at("60")), "\"staleness_level\":\"stale\"")
  |> should.equal(True)
  string.contains(action.preview(at("120")), "\"staleness_level\":\"degraded\"")
  |> should.equal(True)
  string.contains(action.preview(at("300")), "\"staleness_level\":\"dead\"")
  |> should.equal(True)
}

pub fn receipt_records_runbook_and_sends_nothing_test() {
  let dir = fresh_dir("receipt")
  let assert Ok(reply) = action.execute(at("400"), dir)
  string.contains(reply, "\"runbook_id\":\"RB-010\"") |> should.equal(True)
  string.contains(reply, "\"runbook_name\":\"Jidoka Emergency Halt\"")
  |> should.equal(True)
  string.contains(reply, "\"notification_sent\":false") |> should.equal(True)
  string.contains(reply, "\"effect\":\"escalation_record_only\"")
  |> should.equal(True)
}

fn fresh_dir(name: String) -> String {
  let dir = "/tmp/uos_w1_escalate_test_" <> name
  let _ = simplifile.delete(dir)
  let assert Ok(_) = simplifile.create_directory_all(dir)
  dir
}

pub fn preview_creates_nothing_test() {
  let dir = fresh_dir("preview")
  let _ = action.preview(req())
  simplifile.read_directory(dir) |> should.equal(Ok([]))
}

pub fn execute_writes_receipt_exclusively_test() {
  let dir = fresh_dir("write")
  let r = req()
  let assert Ok(reply) = action.execute(r, dir)
  status_of(reply) |> should.equal("executed")
  string.contains(reply, "\"confidence\":\"simulated\"") |> should.equal(True)
  string.contains(reply, "\"clock\":\"not_sampled\"") |> should.equal(True)
  string.contains(reply, "\"authority\":\"NONE\"") |> should.equal(True)
  let path = dir <> "/" <> action.effect_id(r) <> ".json"
  simplifile.read(path) |> should.equal(Ok(reply))
  simplifile.read_directory(dir)
  |> should.equal(Ok([action.effect_id(r) <> ".json"]))
}

pub fn execute_repeat_is_duplicate_with_stored_receipt_test() {
  let dir = fresh_dir("dup")
  let r = req()
  let assert Ok(first) = action.execute(r, dir)
  let assert Ok(second) = action.execute(r, dir)
  let assert Ok(third) = action.execute(r, dir)
  status_of(second) |> should.equal("duplicate")
  status_of(third) |> should.equal("duplicate")
  string.contains(second, first) |> should.equal(True)
  { string.byte_size(second) <= 3500 } |> should.equal(True)
  simplifile.read(dir <> "/" <> action.effect_id(r) <> ".json")
  |> should.equal(Ok(first))
  let assert Ok(files) = simplifile.read_directory(dir)
  list.length(files) |> should.equal(1)
}

pub fn execute_refuses_missing_or_empty_evidence_dir_test() {
  let missing = "/tmp/uos_w1_escalate_test_absent_dir_xyz"
  let _ = simplifile.delete(missing)
  action.execute(req(), missing) |> should.equal(Error("evidence_dir_missing"))
  action.execute(req(), "") |> should.equal(Error("evidence_dir_missing"))
  action.execute(req(), "   ") |> should.equal(Error("evidence_dir_missing"))
  simplifile.is_directory(missing) |> should.equal(Ok(False))
}

pub fn execute_refuses_a_file_as_evidence_dir_test() {
  let dir = fresh_dir("filedir")
  let file = dir <> "/not_a_dir"
  let assert Ok(_) = simplifile.write(file, "x")
  action.execute(req(), file) |> should.equal(Error("evidence_dir_missing"))
}

pub fn tampered_stored_receipt_fails_closed_test() {
  let dir = fresh_dir("tamper")
  let r = req()
  let path = dir <> "/" <> action.effect_id(r) <> ".json"
  let assert Ok(_) =
    simplifile.write(
      path,
      "{\"status\":\"executed\",\"literal\":\"/escalate\",\"effect_id\":\"escalate-forged\"}",
    )
  action.execute(r, dir) |> should.equal(Error("stored_receipt_invalid"))
  let assert Ok(_) = simplifile.write(path, "not json")
  action.execute(r, dir) |> should.equal(Error("stored_receipt_invalid"))
  let assert Ok(_) =
    simplifile.write(
      path,
      "{\"status\":\"preview\",\"literal\":\"/escalate\",\"effect_id\":\""
        <> action.effect_id(r)
        <> "\"}",
    )
  action.execute(r, dir) |> should.equal(Error("stored_receipt_invalid"))
}
