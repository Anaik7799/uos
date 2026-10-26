import cepaf_gleam/harness/files
import cepaf_gleam/harness/telegram_action_verification as ver
import gleam/list
import gleam/string
import gleeunit/should
import simplifile

const base = "/tmp/claude-1000/-home-an-NAS-setup-uos/35600f5c-f8c9-4312-b1e0-07fde55d77cc/scratchpad/w3/ver-"

fn fresh(name: String) -> String {
  let dir = base <> name
  let _ = simplifile.delete(dir)
  let assert Ok(_) = simplifile.create_directory_all(dir)
  dir
}

fn req(args: String) {
  let assert Ok(r) = ver.parse(args)
  r
}

pub fn literal_and_parse_positive_test() {
  ver.literal() |> should.equal("/verification")
  let default_id = ver.effect_id(req(""))
  string.length(default_id) |> should.equal(64)
  default_id |> should.equal(ver.effect_id(req("checklist")))
  { default_id == ver.effect_id(req("aspects")) } |> should.equal(False)
  { ver.effect_id(req("aspects")) == ver.effect_id(req("A07")) }
  |> should.equal(False)
  let _ = req("A01")
  let _ = req("A17")
  Nil
}

pub fn parse_negative_test() {
  list.each(
    [
      "A00",
      "A18",
      "a01",
      "CHK-01-TIME",
      "checklist aspects",
      "aspects A01",
      "run",
      "../x",
      string.repeat("a", 257),
    ],
    fn(input) {
      case ver.parse(input) {
        Error(message) ->
          string.starts_with(message, "usage: /verification")
          |> should.equal(True)
        Ok(_) -> should.fail()
      }
    },
  )
}

pub fn preview_checklist_shape_and_confidence_test() {
  let text = ver.preview(req(""))
  string.contains(text, "\"status\":\"preview\"") |> should.equal(True)
  string.contains(text, "\"confidence\":\"declared\"") |> should.equal(True)
  string.contains(text, "\"view\":\"checklist\"") |> should.equal(True)
  string.contains(text, "\"selected_count\":18") |> should.equal(True)
  string.contains(text, "\"missing_count\":18") |> should.equal(True)
  string.contains(text, "\"record_source\":\"not_configured\"")
  |> should.equal(True)
  string.contains(text, "\"id\":\"CHK-18-JJ\"") |> should.equal(True)
  string.contains(text, "\"gates_executed\":false") |> should.equal(True)
  string.contains(text, "\"runtime_admission\":\"NOT_GRANTED\"")
  |> should.equal(True)
  string.contains(text, "\"state\":\"PASS\"") |> should.equal(False)
  { string.byte_size(text) <= 3500 } |> should.equal(True)
}

pub fn preview_aspects_scopes_test() {
  let all = ver.preview(req("aspects"))
  string.contains(all, "\"selected_count\":17") |> should.equal(True)
  string.contains(all, "\"id\":\"A17\"") |> should.equal(True)
  { string.byte_size(all) <= 3500 } |> should.equal(True)
  let one = ver.preview(req("A07"))
  string.contains(one, "\"selected_count\":1") |> should.equal(True)
  string.contains(one, "\"selector\":\"A07\"") |> should.equal(True)
  string.contains(one, "\"id\":\"A07\"") |> should.equal(True)
  string.contains(one, "\"id\":\"A08\"") |> should.equal(False)
}

pub fn execute_writes_receipt_then_duplicates_test() {
  let dir = fresh("exec")
  let r = req("A03")
  let assert Ok(first) = ver.execute(r, dir)
  string.contains(first, "\"status\":\"executed\"") |> should.equal(True)
  string.contains(first, "\"id\":\"A03\"") |> should.equal(True)
  let id = ver.effect_id(r)
  simplifile.read(dir <> "/" <> id <> ".json") |> should.equal(Ok(first))
  let assert Ok(second) = ver.execute(r, dir)
  string.contains(second, "\"status\":\"duplicate\"") |> should.equal(True)
  string.contains(
    second,
    "\"receipt_sha256\":\"" <> files.digest(first) <> "\"",
  )
  |> should.equal(True)
  simplifile.read_directory(dir) |> should.equal(Ok([id <> ".json"]))
}

pub fn execute_refuses_missing_evidence_dir_test() {
  let dir = base <> "does-not-exist"
  let _ = simplifile.delete(dir)
  ver.execute(req(""), dir) |> should.equal(Error("evidence_dir_unavailable"))
  simplifile.is_directory(dir) |> should.equal(Ok(False))
}
