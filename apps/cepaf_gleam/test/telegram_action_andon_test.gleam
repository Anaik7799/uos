import cepaf_gleam/harness/telegram_action_andon as action
import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/string
import gleeunit/should
import simplifile

fn fresh_dir(name: String) -> String {
  let dir = "/tmp/uos_w1_andon_test_" <> name
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

fn req() {
  let assert Ok(r) = action.parse("modular_max invalid_max_response")
  r
}

pub fn literal_is_andon_test() {
  action.literal() |> should.equal("/andon")
}

pub fn parse_accepts_shared_capability_and_serious_reason_test() {
  let assert Ok(a) = action.parse("modular_max invalid_max_response")
  let assert Ok(b) = action.parse("  openrouter_free   backend_down  ")
  action.effect_id(a) |> should.not_equal(action.effect_id(b))
}

pub fn parse_refusals_test() {
  list.each(
    [
      "",
      "modular_max",
      "unknown_cap backend_down",
      "modular_max Bad",
      "modular_max bad-reason",
      "modular_max a b",
      "modular_max andon_x",
      "modular_max invalid_input",
      "modular_max recovery_x",
      "modular_max backend\u{0}down",
      string.repeat("a", 257),
      "modular_max " <> string.repeat("a", 65),
    ],
    fn(input) { action.parse(input) |> result_is_error |> should.equal(True) },
  )
}

fn result_is_error(r: Result(a, String)) -> Bool {
  case r {
    Ok(_) -> False
    Error(_) -> True
  }
}

pub fn oversize_args_name_the_bound_test() {
  let assert Error(message) = action.parse(string.repeat("a", 257))
  string.starts_with(message, "args_bound") |> should.equal(True)
}

pub fn non_serious_reason_is_refused_test() {
  let assert Error(message) = action.parse("modular_max andon_stopped")
  string.starts_with(message, "reason_not_a_serious_failure")
  |> should.equal(True)
}

pub fn effect_id_is_stable_and_depends_on_both_fields_test() {
  let assert Ok(a) = action.parse("modular_max backend_down")
  let assert Ok(a2) = action.parse("modular_max   backend_down")
  let assert Ok(b) = action.parse("modular_max backend_up_not")
  let assert Ok(c) = action.parse("openrouter_free backend_down")
  action.effect_id(a) |> should.equal(action.effect_id(a2))
  action.effect_id(a) |> should.not_equal(action.effect_id(b))
  action.effect_id(a) |> should.not_equal(action.effect_id(c))
  string.starts_with(action.effect_id(a), "andon-") |> should.equal(True)
  string.byte_size(action.effect_id(a)) |> should.equal(70)
}

pub fn preview_is_closed_shape_and_labelled_simulated_test() {
  let text = action.preview(req())
  status_of(text) |> should.equal("preview")
  keys(text)
  |> should.equal([
    "approval_required", "authority", "capability", "confidence",
    "declared_startup_phase", "effect", "effect_id", "hypothetical_before_phase",
    "literal", "predicted_after_phase", "predicted_failure_count",
    "process_signalled", "reason", "state_source", "status",
  ])
  string.contains(text, "\"confidence\":\"simulated\"") |> should.equal(True)
  string.contains(text, "\"predicted_after_phase\":\"stopped\"")
  |> should.equal(True)
  string.contains(text, "\"declared_startup_phase\":\"stopped\"")
  |> should.equal(True)
  string.contains(text, "\"process_signalled\":false") |> should.equal(True)
  string.contains(text, "\"authority\":\"NONE\"") |> should.equal(True)
  { string.byte_size(text) <= 3500 } |> should.equal(True)
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
  string.contains(reply, "\"after_phase\":\"stopped\"") |> should.equal(True)
  string.contains(reply, "\"before_phase\":\"ready\"") |> should.equal(True)
  string.contains(reply, "\"process_signalled\":false") |> should.equal(True)
  string.contains(reply, "\"clock\":\"not_sampled\"") |> should.equal(True)
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

pub fn distinct_requests_get_distinct_receipts_test() {
  let dir = fresh_dir("distinct")
  let assert Ok(a) = action.parse("modular_max backend_down")
  let assert Ok(b) = action.parse("openrouter_free backend_down")
  let assert Ok(ra) = action.execute(a, dir)
  let assert Ok(rb) = action.execute(b, dir)
  status_of(ra) |> should.equal("executed")
  status_of(rb) |> should.equal("executed")
  let assert Ok(files) = simplifile.read_directory(dir)
  list.length(files) |> should.equal(2)
}

pub fn execute_refuses_missing_or_empty_evidence_dir_test() {
  let missing = "/tmp/uos_w1_andon_test_absent_dir_xyz"
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
      "{\"status\":\"executed\",\"literal\":\"/andon\",\"effect_id\":\"andon-forged\"}",
    )
  action.execute(r, dir) |> should.equal(Error("stored_receipt_invalid"))
  let assert Ok(_) = simplifile.write(path, "not json")
  action.execute(r, dir) |> should.equal(Error("stored_receipt_invalid"))
  let assert Ok(_) =
    simplifile.write(
      path,
      "{\"status\":\"preview\",\"literal\":\"/andon\",\"effect_id\":\""
        <> action.effect_id(r)
        <> "\"}",
    )
  action.execute(r, dir) |> should.equal(Error("stored_receipt_invalid"))
}

pub fn receipt_records_trip_through_andon_backend_test() {
  let dir = fresh_dir("backend")
  let assert Ok(r) = action.parse("openrouter_free backend_down")
  let assert Ok(reply) = action.execute(r, dir)
  string.contains(reply, "\"capability\":\"openrouter_free\"")
  |> should.equal(True)
  string.contains(reply, "\"failure_count\":1") |> should.equal(True)
  string.contains(reply, "\"reason\":\"backend_down\"") |> should.equal(True)
  string.contains(reply, "telegram_action_andon") |> should.equal(True)
}
