import cepaf_gleam/harness/telegram_action_pair_voice as pair
import gleam/list
import gleam/string
import gleeunit/should
import simplifile

const base = "/tmp/claude-1000/-home-an-NAS-setup-uos/35600f5c-f8c9-4312-b1e0-07fde55d77cc/scratchpad/w3/pair-"

fn fresh(name: String) -> String {
  let dir = base <> name
  let _ = simplifile.delete(dir)
  let assert Ok(_) = simplifile.create_directory_all(dir)
  dir
}

fn req(args: String) {
  let assert Ok(r) = pair.parse(args)
  r
}

pub fn literal_and_parse_positive_test() {
  pair.literal() |> should.equal("/pair-voice")
  let id = pair.effect_id(req("agy"))
  string.length(id) |> should.equal(64)
  { id == pair.effect_id(req("codex")) } |> should.equal(False)
  id |> should.equal(pair.effect_id(req(" agy ")))
  let _ = req("vm-1")
  let _ = req(string.repeat("a", 32))
  Nil
}

pub fn parse_negative_test() {
  list.each(
    [
      "",
      "Agy",
      "-agy",
      "a_b",
      "a b",
      "a/b",
      "../x",
      "peer;ls",
      string.repeat("a", 33),
      string.repeat("a", 257),
    ],
    fn(input) {
      case pair.parse(input) {
        Error(message) ->
          string.starts_with(message, "usage: /pair-voice <peer>")
          |> should.equal(True)
        Ok(_) -> should.fail()
      }
    },
  )
}

pub fn preview_shape_and_confidence_test() {
  let text = pair.preview(req("agy"))
  string.contains(text, "\"status\":\"preview\"") |> should.equal(True)
  string.contains(text, "\"confidence\":\"declared\"") |> should.equal(True)
  string.contains(text, "\"literal\":\"/pair-voice\"") |> should.equal(True)
  string.contains(text, "\"peer\":\"agy\"") |> should.equal(True)
  string.contains(text, "\"mode\":\"push_to_talk\"") |> should.equal(True)
  string.contains(text, "\"pipeline_active\":false") |> should.equal(True)
  string.contains(text, "\"pipeline_health\":0.5") |> should.equal(True)
  string.contains(text, "unavailable:voice_pipeline_state")
  |> should.equal(True)
  string.contains(text, "\"authority\":\"NONE\"") |> should.equal(True)
  { string.byte_size(text) <= 3500 } |> should.equal(True)
}

pub fn execute_is_unavailable_and_writes_nothing_test() {
  let dir = fresh("unavail")
  pair.execute(req("agy"), dir)
  |> should.equal(Error("backend_unavailable:voice_pipeline_state"))
  simplifile.read_directory(dir) |> should.equal(Ok([]))
  let reply = pair.unavailable_reply(req("agy"))
  string.contains(reply, "\"status\":\"backend_unavailable\"")
  |> should.equal(True)
  string.contains(reply, "\"backend\":\"voice_pipeline_state\"")
  |> should.equal(True)
}

pub fn execute_refuses_missing_evidence_dir_test() {
  let dir = base <> "does-not-exist"
  let _ = simplifile.delete(dir)
  pair.execute(req("agy"), dir)
  |> should.equal(Error("evidence_dir_unavailable"))
  simplifile.is_directory(dir) |> should.equal(Ok(False))
}
