import cepaf_gleam/harness/telegram_action_repro as repro
import gleam/int
import gleam/list
import gleam/string
import gleeunit/should
import simplifile

const known = "20260905-1755-codex-findings-resolution-and-km-triad-journal"

fn fresh() -> String {
  let dir = "/tmp/uos-repro-" <> int.to_string(int.random(1_000_000_000))
  let assert Ok(_) = simplifile.create_directory_all(dir)
  dir
}

pub fn literal_test() {
  repro.literal() |> should.equal("/repro")
}

pub fn parse_positive_test() {
  let assert Ok(task) = repro.parse("COMMAND_IMPL")
  repro.effect_id(task) |> string.length |> should.equal(64)
  let assert Ok(journal) = repro.parse(known <> ".md")
  repro.effect_id(journal) |> should.not_equal(repro.effect_id(task))
}

pub fn parse_negative_test() {
  list.each(
    [
      "",
      "   ",
      "../etc/passwd",
      "a b",
      "a/b",
      ".hidden",
      ".md",
      string.repeat("a", 129),
      string.repeat("a", 300),
      "x;rm",
      "x\u{0}y",
    ],
    fn(args) { repro.parse(args) |> should.be_error },
  )
}

pub fn preview_observed_journal_test() {
  let assert Ok(r) = repro.parse(known)
  let text = repro.preview(r)
  string.contains(text, "\"status\":\"preview\"") |> should.be_true
  string.contains(text, "\"confidence\":\"observed\"") |> should.be_true
  string.contains(text, "\"journal_exists\":true") |> should.be_true
  string.contains(text, "\"executes_commands\":false") |> should.be_true
  string.contains(text, "\"effect\":\"none\"") |> should.be_true
  { string.byte_size(text) <= 3500 } |> should.be_true
}

pub fn preview_missing_journal_test() {
  let assert Ok(r) = repro.parse("20990101-0000-no-such-journal")
  let text = repro.preview(r)
  string.contains(text, "\"confidence\":\"observed\"") |> should.be_true
  string.contains(text, "\"journal_exists\":false") |> should.be_true
}

pub fn preview_task_is_declared_test() {
  let assert Ok(r) = repro.parse("COMMAND_IMPL")
  let text = repro.preview(r)
  string.contains(text, "\"confidence\":\"declared\"") |> should.be_true
  string.contains(text, "\"task_state\":\"not_observed\"") |> should.be_true
}

pub fn execute_receipt_then_duplicate_test() {
  let dir = fresh()
  let assert Ok(r) = repro.parse(known)
  let assert Ok(first) = repro.execute(r, dir)
  string.contains(first, "\"status\":\"executed\"") |> should.be_true
  string.contains(first, "\"effect\":\"receipt_only\"") |> should.be_true
  let assert Ok(names) = simplifile.read_directory(dir)
  names |> should.equal([repro.effect_id(r) <> ".json"])
  let assert Ok(second) = repro.execute(r, dir)
  string.contains(second, "\"status\":\"duplicate\"") |> should.be_true
  let assert Ok(names2) = simplifile.read_directory(dir)
  list.length(names2) |> should.equal(1)
  let assert Ok(_) = simplifile.delete(dir)
}

pub fn execute_missing_dir_test() {
  let assert Ok(r) = repro.parse("COMMAND_IMPL")
  repro.execute(
    r,
    "/tmp/uos-repro-missing-" <> int.to_string(int.random(1_000_000_000)),
  )
  |> should.be_error
  repro.execute(r, "relative") |> should.be_error
}
