import cepaf_gleam/harness/telegram_action_dark as action
import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/string
import gleeunit/should
import simplifile

const modes = ["dark", "dim", "normal", "bright", "emergency"]

fn fresh_dir(name: String) -> String {
  let dir = "/tmp/uos_w1_dark_test_" <> name
  let _ = simplifile.delete(dir)
  let assert Ok(_) = simplifile.create_directory_all(dir)
  dir
}

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

fn req(mode: String) {
  let assert Ok(r) = action.parse(mode)
  r
}

fn is_error(r: Result(a, String)) -> Bool {
  case r {
    Ok(_) -> False
    Error(_) -> True
  }
}

pub fn literal_is_dark_test() {
  action.literal() |> should.equal("/dark")
}

pub fn parse_accepts_each_mode_and_trims_test() {
  list.each(modes, fn(mode) {
    let assert Ok(_) = action.parse(mode)
    let assert Ok(_) = action.parse("  " <> mode <> "\n")
  })
}

pub fn parse_refusals_test() {
  list.each(
    [
      "",
      " ",
      "Dark",
      "DARK",
      "toggle",
      "dark dim",
      "dark;",
      "dim\u{0}",
      "brightest",
      string.repeat("a", 257),
    ],
    fn(input) { action.parse(input) |> is_error |> should.equal(True) },
  )
  let assert Error(message) = action.parse(string.repeat("a", 257))
  string.starts_with(message, "args_bound") |> should.equal(True)
}

pub fn effect_ids_are_stable_and_distinct_per_mode_test() {
  let ids = list.map(modes, fn(mode) { action.effect_id(req(mode)) })
  list.unique(ids) |> list.length |> should.equal(5)
  action.effect_id(req("dim")) |> should.equal(action.effect_id(req(" dim ")))
  list.each(ids, fn(id) {
    string.starts_with(id, "dark-") |> should.equal(True)
    string.byte_size(id) |> should.equal(69)
  })
}

pub fn preview_is_closed_shape_and_labelled_declared_test() {
  let text = action.preview(req("emergency"))
  status_of(text) |> should.equal("preview")
  keys(text)
  |> should.equal([
    "approval_required", "authority", "before_mode", "confidence", "effect",
    "effect_id", "global_state_mutated", "literal", "predicted_after_mode",
    "reversible_by", "state_source", "status", "synthetic_alerts", "target_mode",
  ])
  string.contains(text, "\"confidence\":\"declared\"") |> should.equal(True)
  string.contains(text, "\"before_mode\":\"dark\"") |> should.equal(True)
  string.contains(text, "\"predicted_after_mode\":\"emergency\"")
  |> should.equal(True)
  string.contains(text, "\"global_state_mutated\":false") |> should.equal(True)
  string.contains(text, "\"authority\":\"NONE\"") |> should.equal(True)
  { string.byte_size(text) <= 3500 } |> should.equal(True)
}

pub fn preview_predicts_the_requested_mode_for_every_target_test() {
  list.each(modes, fn(mode) {
    string.contains(
      action.preview(req(mode)),
      "\"predicted_after_mode\":\"" <> mode <> "\"",
    )
    |> should.equal(True)
  })
}

pub fn preview_creates_nothing_test() {
  let dir = fresh_dir("preview")
  let _ = action.preview(req("dim"))
  simplifile.read_directory(dir) |> should.equal(Ok([]))
}

pub fn synthetic_alert_counts_follow_the_backend_rule_test() {
  let count = fn(mode, expected) {
    let dir = fresh_dir("count_" <> mode)
    let assert Ok(reply) = action.execute(req(mode), dir)
    string.contains(reply, "\"alert_count\":" <> expected) |> should.equal(True)
    string.contains(reply, "\"after_mode\":\"" <> mode <> "\"")
    |> should.equal(True)
  }
  count("dark", "0")
  count("dim", "1")
  count("normal", "1")
  count("bright", "3")
  count("emergency", "1")
}

pub fn execute_writes_receipt_exclusively_test() {
  let dir = fresh_dir("write")
  let r = req("bright")
  let assert Ok(reply) = action.execute(r, dir)
  status_of(reply) |> should.equal("executed")
  string.contains(reply, "\"global_state_mutated\":false") |> should.equal(True)
  string.contains(reply, "\"clock\":\"not_sampled\"") |> should.equal(True)
  simplifile.read(dir <> "/" <> action.effect_id(r) <> ".json")
  |> should.equal(Ok(reply))
  simplifile.read_directory(dir)
  |> should.equal(Ok([action.effect_id(r) <> ".json"]))
}

pub fn execute_repeat_is_duplicate_with_stored_receipt_test() {
  let dir = fresh_dir("dup")
  let r = req("dim")
  let assert Ok(first) = action.execute(r, dir)
  let assert Ok(second) = action.execute(r, dir)
  status_of(second) |> should.equal("duplicate")
  string.contains(second, first) |> should.equal(True)
  { string.byte_size(second) <= 3500 } |> should.equal(True)
  simplifile.read(dir <> "/" <> action.effect_id(r) <> ".json")
  |> should.equal(Ok(first))
  let assert Ok(files) = simplifile.read_directory(dir)
  list.length(files) |> should.equal(1)
}

pub fn reversal_is_a_separate_effect_test() {
  let dir = fresh_dir("reverse")
  let assert Ok(up) = action.execute(req("emergency"), dir)
  let assert Ok(down) = action.execute(req("dark"), dir)
  status_of(up) |> should.equal("executed")
  status_of(down) |> should.equal("executed")
  let assert Ok(files) = simplifile.read_directory(dir)
  list.length(files) |> should.equal(2)
}

pub fn execute_refuses_missing_or_empty_evidence_dir_test() {
  let missing = "/tmp/uos_w1_dark_test_absent_dir_xyz"
  let _ = simplifile.delete(missing)
  action.execute(req("dim"), missing)
  |> should.equal(Error("evidence_dir_missing"))
  action.execute(req("dim"), "") |> should.equal(Error("evidence_dir_missing"))
  action.execute(req("dim"), "  ")
  |> should.equal(Error("evidence_dir_missing"))
  simplifile.is_directory(missing) |> should.equal(Ok(False))
}

pub fn execute_refuses_a_file_as_evidence_dir_test() {
  let dir = fresh_dir("filedir")
  let file = dir <> "/not_a_dir"
  let assert Ok(_) = simplifile.write(file, "x")
  action.execute(req("dim"), file)
  |> should.equal(Error("evidence_dir_missing"))
}

pub fn tampered_stored_receipt_fails_closed_test() {
  let dir = fresh_dir("tamper")
  let r = req("dim")
  let path = dir <> "/" <> action.effect_id(r) <> ".json"
  let assert Ok(_) =
    simplifile.write(
      path,
      "{\"status\":\"executed\",\"literal\":\"/dark\",\"effect_id\":\"dark-forged\"}",
    )
  action.execute(r, dir) |> should.equal(Error("stored_receipt_invalid"))
  let assert Ok(_) = simplifile.write(path, "garbage")
  action.execute(r, dir) |> should.equal(Error("stored_receipt_invalid"))
  let assert Ok(_) =
    simplifile.write(
      path,
      "{\"status\":\"executed\",\"literal\":\"/andon\",\"effect_id\":\""
        <> action.effect_id(r)
        <> "\"}",
    )
  action.execute(r, dir) |> should.equal(Error("stored_receipt_invalid"))
}
