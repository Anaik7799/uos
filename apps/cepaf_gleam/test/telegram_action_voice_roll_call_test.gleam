import cepaf_gleam/harness/files
import cepaf_gleam/harness/telegram_action_voice_roll_call as roll
import gleam/list
import gleam/string
import gleeunit/should
import simplifile

const base = "/tmp/claude-1000/-home-an-NAS-setup-uos/35600f5c-f8c9-4312-b1e0-07fde55d77cc/scratchpad/w3/roll-"

fn fresh(name: String) -> String {
  let dir = base <> name
  let _ = simplifile.delete(dir)
  let assert Ok(_) = simplifile.create_directory_all(dir)
  dir
}

fn req(args: String) {
  let assert Ok(r) = roll.parse(args)
  r
}

pub fn literal_and_parse_positive_test() {
  roll.literal() |> should.equal("/voice-roll-call")
  let all = roll.effect_id(req(""))
  string.length(all) |> should.equal(64)
  let ids =
    list.map(["always_on", "push_to_talk", "wake_word", "disabled"], fn(m) {
      roll.effect_id(req("mode=" <> m))
    })
  list.length(list.unique([all, ..ids])) |> should.equal(5)
}

pub fn parse_negative_test() {
  list.each(
    [
      "mode=",
      "mode=loud",
      "mode=always_on mode=disabled",
      "verify prop-drain",
      "always_on",
      "mode=always_on extra",
      string.repeat("a", 257),
    ],
    fn(input) {
      case roll.parse(input) {
        Error(message) ->
          string.starts_with(message, "usage: /voice-roll-call")
          |> should.equal(True)
        Ok(_) -> should.fail()
      }
    },
  )
}

pub fn preview_shape_and_confidence_test() {
  let text = roll.preview(req(""))
  string.contains(text, "\"status\":\"preview\"") |> should.equal(True)
  string.contains(text, "\"confidence\":\"declared\"") |> should.equal(True)
  string.contains(text, "\"literal\":\"/voice-roll-call\"")
  |> should.equal(True)
  string.contains(text, "\"mode\":\"always_on\"") |> should.equal(True)
  string.contains(text, "\"mode\":\"disabled\"") |> should.equal(True)
  string.contains(text, "\"votes_counted\":0") |> should.equal(True)
  string.contains(text, "\"ws_connected\":false") |> should.equal(True)
  string.contains(text, "\"authority\":\"NONE\"") |> should.equal(True)
  { string.byte_size(text) <= 3500 } |> should.equal(True)
  let one = roll.preview(req("mode=wake_word"))
  string.contains(one, "\"mode\":\"wake_word\"") |> should.equal(True)
  string.contains(one, "\"mode\":\"always_on\"") |> should.equal(False)
  string.contains(one, "\"health\":0.5") |> should.equal(True)
}

pub fn disabled_mode_has_zero_health_test() {
  let text = roll.preview(req("mode=disabled"))
  string.contains(text, "\"health\":0.0") |> should.equal(True)
  string.contains(text, "\"active\":false") |> should.equal(True)
}

pub fn execute_writes_receipt_then_duplicates_test() {
  let dir = fresh("exec")
  let r = req("mode=push_to_talk")
  let assert Ok(first) = roll.execute(r, dir)
  string.contains(first, "\"status\":\"executed\"") |> should.equal(True)
  string.contains(first, "\"mode\":\"push_to_talk\"") |> should.equal(True)
  let id = roll.effect_id(r)
  simplifile.read(dir <> "/" <> id <> ".json") |> should.equal(Ok(first))
  let assert Ok(second) = roll.execute(r, dir)
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
  roll.execute(req(""), dir) |> should.equal(Error("evidence_dir_unavailable"))
  simplifile.is_directory(dir) |> should.equal(Ok(False))
}
