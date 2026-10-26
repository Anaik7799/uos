import cepaf_gleam/harness/telegram_action_lockbox as action
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
  let assert Ok(r) = action.parse("seal operator_requested")
  r
}

fn fresh_dir(name: String) -> String {
  let dir = "/tmp/uos_w1_lockbox_test_" <> name
  let _ = simplifile.delete(dir)
  let assert Ok(_) = simplifile.create_directory_all(dir)
  dir
}

pub fn literal_test() {
  action.literal() |> should.equal("/lockbox")
}

pub fn parse_positive_test() {
  let assert Ok(a) = action.parse("seal operator_requested")
  let assert Ok(b) = action.parse("  seal    operator_requested ")
  let assert Ok(c) = action.parse("seal other_reason")
  action.effect_id(a) |> should.equal(action.effect_id(b))
  action.effect_id(a) |> should.not_equal(action.effect_id(c))
  string.starts_with(action.effect_id(a), "lockbox-") |> should.equal(True)
  string.byte_size(action.effect_id(a)) |> should.equal(72)
}

pub fn parse_negative_test() {
  list.each(
    [
      "",
      "seal",
      "unseal reason",
      "seal Bad",
      "seal bad-reason",
      "seal a b",
      "reason seal",
      "seal \u{0}x",
      string.repeat("a", 257),
      "seal " <> string.repeat("a", 65),
    ],
    fn(input) { action.parse(input) |> is_error |> should.equal(True) },
  )
  let assert Error(message) = action.parse(string.repeat("a", 257))
  string.starts_with(message, "args_bound") |> should.equal(True)
}

pub fn preview_shape_and_declared_confidence_test() {
  let text = action.preview(req())
  status_of(text) |> should.equal("preview")
  keys(text)
  |> should.equal([
    "approval_required", "authority", "confidence", "derived_key_bytes",
    "effect_id", "execute", "kdf", "kdf_iterations", "kdf_memory_mb",
    "kdf_parallelism", "kek_chain_order", "literal", "operation", "reason",
    "salt_min_bytes", "secret_material_read", "state_source", "status",
    "unavailable_reason",
  ])
  string.contains(text, "\"confidence\":\"declared\"") |> should.equal(True)
  string.contains(text, "[\"tpm\",\"passphrase\",\"kms\"]")
  |> should.equal(True)
  string.contains(text, "\"secret_material_read\":false") |> should.equal(True)
  string.contains(text, "\"execute\":\"unavailable:vault_kek\"")
  |> should.equal(True)
  { string.byte_size(text) <= 3500 } |> should.equal(True)
}

pub fn preview_creates_nothing_test() {
  let dir = fresh_dir("preview")
  let _ = action.preview(req())
  simplifile.read_directory(dir) |> should.equal(Ok([]))
}

pub fn execute_is_exactly_backend_unavailable_and_writes_nothing_test() {
  let dir = fresh_dir("exec")
  action.execute(req(), dir)
  |> should.equal(Error("backend_unavailable:vault_kek"))
  action.execute(req(), dir)
  |> should.equal(Error("backend_unavailable:vault_kek"))
  simplifile.read_directory(dir) |> should.equal(Ok([]))
}

pub fn execute_refuses_missing_dir_test() {
  let missing = "/tmp/uos_w1_lockbox_test_absent_xyz"
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
  string.contains(text, "\"backend\":\"vault_kek\"") |> should.equal(True)
}
