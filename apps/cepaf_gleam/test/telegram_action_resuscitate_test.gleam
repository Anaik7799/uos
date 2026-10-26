import cepaf_gleam/harness/telegram_action_resuscitate as action
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
  let assert Ok(r) = action.parse("modular_max")
  r
}

pub fn literal_test() {
  action.literal() |> should.equal("/resuscitate")
}

pub fn parse_positive_test() {
  let assert Ok(a) = action.parse("modular_max")
  let assert Ok(a2) = action.parse("  modular_max  ")
  let assert Ok(b) = action.parse("openrouter_free")
  action.effect_id(a) |> should.equal(action.effect_id(a2))
  action.effect_id(a) |> should.not_equal(action.effect_id(b))
  string.starts_with(action.effect_id(a), "resuscitate-") |> should.equal(True)
  string.byte_size(action.effect_id(a)) |> should.equal(76)
}

pub fn parse_negative_test() {
  list.each(
    [
      "",
      "modular_max extra",
      "unknown_cap",
      "Modular_Max",
      "modular-max",
      "modular_max\u{0}",
      string.repeat("a", 257),
    ],
    fn(input) { action.parse(input) |> is_error |> should.equal(True) },
  )
  let assert Error(message) = action.parse(string.repeat("a", 257))
  string.starts_with(message, "args_bound") |> should.equal(True)
}

pub fn preview_shape_and_simulated_confidence_test() {
  let text = action.preview(req())
  status_of(text) |> should.equal("preview")
  keys(text)
  |> should.equal([
    "approval_required", "authority", "capability", "completion_requires",
    "confidence", "declared_before_phase", "effect", "effect_id", "literal",
    "predicted_after_phase", "predicted_recovery_attempts", "process_restarted",
    "state_source", "status",
  ])
  string.contains(text, "\"confidence\":\"simulated\"") |> should.equal(True)
  string.contains(text, "\"declared_before_phase\":\"stopped\"")
  |> should.equal(True)
  string.contains(text, "\"predicted_after_phase\":\"recovering\"")
  |> should.equal(True)
  string.contains(text, "\"predicted_recovery_attempts\":1")
  |> should.equal(True)
  string.contains(text, "\"process_restarted\":false") |> should.equal(True)
  { string.byte_size(text) <= 3500 } |> should.equal(True)
}

pub fn receipt_records_plan_and_restarts_nothing_test() {
  let dir = fresh_dir("receipt")
  let assert Ok(r) = action.parse("openrouter_free")
  let assert Ok(reply) = action.execute(r, dir)
  string.contains(reply, "\"capability\":\"openrouter_free\"")
  |> should.equal(True)
  string.contains(reply, "\"before_phase\":\"stopped\"") |> should.equal(True)
  string.contains(reply, "\"after_phase\":\"recovering\"") |> should.equal(True)
  string.contains(reply, "\"recovery_attempts\":1") |> should.equal(True)
  string.contains(reply, "\"recovery_count\":0") |> should.equal(True)
  string.contains(reply, "\"process_restarted\":false") |> should.equal(True)
  string.contains(reply, "engaged_backend_probe_receipt") |> should.equal(True)
}

pub fn distinct_requests_get_distinct_receipts_test() {
  let dir = fresh_dir("distinct")
  let assert Ok(a) = action.parse("modular_max")
  let assert Ok(b) = action.parse("openrouter_free")
  let assert Ok(ra) = action.execute(a, dir)
  let assert Ok(rb) = action.execute(b, dir)
  status_of(ra) |> should.equal("executed")
  status_of(rb) |> should.equal("executed")
  let assert Ok(files) = simplifile.read_directory(dir)
  list.length(files) |> should.equal(2)
}

fn fresh_dir(name: String) -> String {
  let dir = "/tmp/uos_w1_resuscitate_test_" <> name
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
  let missing = "/tmp/uos_w1_resuscitate_test_absent_dir_xyz"
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
      "{\"status\":\"executed\",\"literal\":\"/resuscitate\",\"effect_id\":\"resuscitate-forged\"}",
    )
  action.execute(r, dir) |> should.equal(Error("stored_receipt_invalid"))
  let assert Ok(_) = simplifile.write(path, "not json")
  action.execute(r, dir) |> should.equal(Error("stored_receipt_invalid"))
  let assert Ok(_) =
    simplifile.write(
      path,
      "{\"status\":\"preview\",\"literal\":\"/resuscitate\",\"effect_id\":\""
        <> action.effect_id(r)
        <> "\"}",
    )
  action.execute(r, dir) |> should.equal(Error("stored_receipt_invalid"))
}
