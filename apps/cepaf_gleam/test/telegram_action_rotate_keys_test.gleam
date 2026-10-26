import cepaf_gleam/harness/telegram_action_rotate_keys as action
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
  let assert Ok(r) = action.parse("90 100")
  r
}

fn fresh_dir(name: String) -> String {
  let dir = "/tmp/uos_w1_rotate_keys_test_" <> name
  let _ = simplifile.delete(dir)
  let assert Ok(_) = simplifile.create_directory_all(dir)
  dir
}

pub fn literal_test() {
  action.literal() |> should.equal("/rotate-keys")
}

pub fn parse_positive_test() {
  let assert Ok(a) = action.parse("90 10")
  let assert Ok(b) = action.parse("  90    10 ")
  let assert Ok(c) = action.parse("90 11")
  let assert Ok(_) = action.parse("1 0")
  let assert Ok(_) = action.parse("3650 36500")
  action.effect_id(a) |> should.equal(action.effect_id(b))
  action.effect_id(a) |> should.not_equal(action.effect_id(c))
  string.starts_with(action.effect_id(a), "rotate-keys-") |> should.equal(True)
  string.byte_size(action.effect_id(a)) |> should.equal(76)
}

pub fn parse_negative_test() {
  list.each(
    [
      "",
      "90",
      "90 10 5",
      "0 10",
      "3651 10",
      "90 36501",
      "-1 5",
      "9x 5",
      "a b",
      "90 1.5",
      "090000 1",
      "90 \u{0}",
      string.repeat("1", 257),
    ],
    fn(input) { action.parse(input) |> is_error |> should.equal(True) },
  )
  let assert Error(message) = action.parse(string.repeat("1", 257))
  string.starts_with(message, "args_bound") |> should.equal(True)
}

pub fn preview_shape_and_declared_confidence_test() {
  let text = action.preview(req())
  status_of(text) |> should.equal("preview")
  keys(text)
  |> should.equal([
    "approval_required", "authority", "blocking", "confidence", "effect_id",
    "execute", "key_age_days", "key_material_read", "literal", "plan",
    "policy_decision", "rotation_days", "severity_tier", "should_propose_reseal",
    "state_source", "status", "unavailable_reason", "urgency_color",
  ])
  string.contains(text, "\"confidence\":\"declared\"") |> should.equal(True)
  string.contains(text, "\"key_material_read\":false") |> should.equal(True)
  string.contains(text, "\"execute\":\"unavailable:vault_kek_rotation\"")
  |> should.equal(True)
  string.contains(text, "opened vault and production authority")
  |> should.equal(True)
  { string.byte_size(text) <= 3500 } |> should.equal(True)
}

pub fn preview_policy_boundaries_test() {
  let label = fn(args: String) {
    let assert Ok(r) = action.parse(args)
    action.preview(r)
  }
  string.contains(label("90 10"), "\"policy_decision\":\"not_due\"")
  |> should.equal(True)
  string.contains(label("90 72"), "\"policy_decision\":\"due_soon\"")
  |> should.equal(True)
  string.contains(label("90 90"), "\"policy_decision\":\"overdue\"")
  |> should.equal(True)
  string.contains(label("90 180"), "\"policy_decision\":\"expired\"")
  |> should.equal(True)
  string.contains(label("90 180"), "\"blocking\":true") |> should.equal(True)
  string.contains(label("90 10"), "\"should_propose_reseal\":false")
  |> should.equal(True)
  string.contains(label("90 90"), "\"should_propose_reseal\":true")
  |> should.equal(True)
}

pub fn preview_creates_nothing_test() {
  let dir = fresh_dir("preview")
  let _ = action.preview(req())
  simplifile.read_directory(dir) |> should.equal(Ok([]))
}

pub fn execute_is_exactly_backend_unavailable_and_writes_nothing_test() {
  let dir = fresh_dir("exec")
  action.execute(req(), dir)
  |> should.equal(Error("backend_unavailable:vault_kek_rotation"))
  action.execute(req(), dir)
  |> should.equal(Error("backend_unavailable:vault_kek_rotation"))
  simplifile.read_directory(dir) |> should.equal(Ok([]))
}

pub fn execute_refuses_missing_dir_test() {
  let missing = "/tmp/uos_w1_rotate_keys_test_absent_xyz"
  let _ = simplifile.delete(missing)
  action.execute(req(), missing) |> should.equal(Error("evidence_dir_missing"))
  action.execute(req(), "") |> should.equal(Error("evidence_dir_missing"))
  simplifile.is_directory(missing) |> should.equal(Ok(False))
}

pub fn unavailable_reply_is_typed_test() {
  let text = action.unavailable_reply(req())
  status_of(text) |> should.equal("backend_unavailable")
  keys(text)
  |> should.equal([
    "authority", "backend", "effect_id", "literal", "reason", "status",
  ])
  string.contains(text, "\"backend\":\"vault_kek_rotation\"")
  |> should.equal(True)
}
