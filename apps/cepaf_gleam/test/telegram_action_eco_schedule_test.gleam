import cepaf_gleam/harness/files
import cepaf_gleam/harness/telegram_action_eco_schedule as eco
import gleam/list
import gleam/string
import gleeunit/should
import simplifile

const base = "/tmp/claude-1000/-home-an-NAS-setup-uos/35600f5c-f8c9-4312-b1e0-07fde55d77cc/scratchpad/w3/eco-"

fn fresh(name: String) -> String {
  let dir = base <> name
  let _ = simplifile.delete(dir)
  let assert Ok(_) = simplifile.create_directory_all(dir)
  dir
}

fn req(args: String) {
  let assert Ok(r) = eco.parse(args)
  r
}

pub fn literal_and_parse_positive_test() {
  eco.literal() |> should.equal("/eco-schedule")
  let id = eco.effect_id(req(""))
  string.length(id) |> should.equal(64)
  id |> should.equal(eco.effect_id(req("jobs=24 max_tokens=512")))
  { id == eco.effect_id(req("jobs=25")) } |> should.equal(False)
  { id == eco.effect_id(req("max_tokens=513")) } |> should.equal(False)
  { id == eco.effect_id(req("input_bytes=2049")) } |> should.equal(False)
  { id == eco.effect_id(req("model=z-ai/glm-5.3")) } |> should.equal(False)
  eco.effect_id(req("jobs=7 max_tokens=9"))
  |> should.equal(eco.effect_id(req("max_tokens=9 jobs=7")))
  let _ = req("jobs=1000")
  let _ = req("max_tokens=4096 input_bytes=16384")
  Nil
}

pub fn parse_negative_test() {
  list.each(
    [
      "jobs=0",
      "jobs=1001",
      "jobs=abc",
      "jobs=",
      "jobs=-1",
      "jobs=1 jobs=2",
      "max_tokens=4097",
      "input_bytes=16385",
      "model=nope/none",
      "model=",
      "bogus",
      "run",
      "secret=1",
      string.repeat("a", 257),
    ],
    fn(input) {
      case eco.parse(input) {
        Error(message) ->
          string.starts_with(message, "usage:") |> should.equal(True)
        Ok(_) -> should.fail()
      }
    },
  )
}

pub fn preview_shape_and_confidence_test() {
  let text = eco.preview(req("jobs=48"))
  string.contains(text, "\"status\":\"preview\"") |> should.equal(True)
  string.contains(text, "\"confidence\":\"simulated\"") |> should.equal(True)
  string.contains(text, "\"literal\":\"/eco-schedule\"") |> should.equal(True)
  string.contains(text, "\"jobs_scheduled\":48") |> should.equal(True)
  string.contains(text, "\"jobs_deferred\":0") |> should.equal(True)
  string.contains(
    text,
    "\"hourly_slots\":[2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2]",
  )
  |> should.equal(True)
  string.contains(text, "\"authority\":\"NONE\"") |> should.equal(True)
  { string.byte_size(text) <= 3500 } |> should.equal(True)
}

pub fn preview_levels_uneven_and_defers_over_budget_test() {
  let even = eco.preview(req("jobs=25"))
  string.contains(
    even,
    "\"hourly_slots\":[2,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1]",
  )
  |> should.equal(True)
  // kimi-k3 at the largest bounds costs 116_736_000 nanodollars per job, so the
  // 10_000_000_000 daily limit admits 85 of 100 requested jobs.
  let over =
    eco.preview(req(
      "model=moonshotai/kimi-k3 jobs=100 max_tokens=4096 input_bytes=16384",
    ))
  string.contains(over, "\"max_jobs_per_day\":85") |> should.equal(True)
  string.contains(over, "\"jobs_scheduled\":85") |> should.equal(True)
  string.contains(over, "\"jobs_deferred\":15") |> should.equal(True)
  string.contains(over, "\"worst_case_nanodollars_per_job\":116736000")
  |> should.equal(True)
}

pub fn parse_and_preview_write_nothing_test() {
  let dir = fresh("pure")
  let r = req("jobs=3")
  let _ = eco.preview(r)
  simplifile.read_directory(dir) |> should.equal(Ok([]))
}

pub fn execute_writes_receipt_then_duplicates_test() {
  let dir = fresh("exec")
  let r = req("jobs=30")
  let assert Ok(first) = eco.execute(r, dir)
  string.contains(first, "\"status\":\"executed\"") |> should.equal(True)
  string.contains(first, "\"jobs_scheduled\":30") |> should.equal(True)
  let id = eco.effect_id(r)
  simplifile.read(dir <> "/" <> id <> ".json") |> should.equal(Ok(first))
  let assert Ok(second) = eco.execute(r, dir)
  string.contains(second, "\"status\":\"duplicate\"") |> should.equal(True)
  string.contains(second, "\"effect_id\":\"" <> id <> "\"")
  |> should.equal(True)
  string.contains(
    second,
    "\"receipt_sha256\":\"" <> files.digest(first) <> "\"",
  )
  |> should.equal(True)
  simplifile.read(dir <> "/" <> id <> ".json") |> should.equal(Ok(first))
  simplifile.read_directory(dir) |> should.equal(Ok([id <> ".json"]))
}

pub fn execute_refuses_missing_evidence_dir_test() {
  let dir = base <> "does-not-exist"
  let _ = simplifile.delete(dir)
  eco.execute(req(""), dir) |> should.equal(Error("evidence_dir_unavailable"))
  simplifile.is_directory(dir) |> should.equal(Ok(False))
}
