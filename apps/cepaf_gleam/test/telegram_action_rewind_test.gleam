import cepaf_gleam/harness/telegram_action_rewind as rewind
import gleam/int
import gleam/list
import gleam/string
import gleeunit/should
import simplifile

fn fresh() -> String {
  let dir = "/tmp/uos-rewind-" <> int.to_string(int.random(1_000_000_000))
  let assert Ok(_) = simplifile.create_directory_all(dir)
  dir
}

pub fn literal_test() {
  rewind.literal() |> should.equal("/rewind")
}

pub fn parse_positive_test() {
  let assert Ok(a) = rewind.parse("1")
  let assert Ok(b) = rewind.parse(" 64 ")
  rewind.effect_id(a) |> string.length |> should.equal(64)
  rewind.effect_id(a) |> should.not_equal(rewind.effect_id(b))
}

pub fn parse_negative_test() {
  list.each(
    [
      "",
      "0",
      "65",
      "-1",
      "01",
      "abc",
      "1 2",
      "100",
      "1.5",
      string.repeat("1", 300),
    ],
    fn(args) { rewind.parse(args) |> should.be_error },
  )
}

pub fn preview_window_test() {
  let assert Ok(r) = rewind.parse("3")
  let text = rewind.preview(r)
  string.contains(text, "\"confidence\":\"simulated\"") |> should.be_true
  string.contains(text, "\"status\":\"preview\"") |> should.be_true
  string.contains(text, "\"total_events\":129") |> should.be_true
  string.contains(text, "\"kept_events\":126") |> should.be_true
  string.contains(text, "\"dropped_events\":3") |> should.be_true
  string.contains(text, "\"first_dropped_index\":126") |> should.be_true
  string.contains(text, "\"store_mutations\":0") |> should.be_true
  string.contains(text, "simulate_temporal_replay") |> should.be_true
  { string.byte_size(text) <= 3500 } |> should.be_true
}

pub fn preview_replay_changes_with_window_test() {
  let assert Ok(one) = rewind.parse("1")
  let assert Ok(two) = rewind.parse("2")
  rewind.preview(one) |> should.not_equal(rewind.preview(two))
  rewind.preview(one) |> should.equal(rewind.preview(one))
}

pub fn execute_receipt_then_duplicate_test() {
  let dir = fresh()
  let assert Ok(r) = rewind.parse("5")
  let assert Ok(first) = rewind.execute(r, dir)
  string.contains(first, "\"status\":\"executed\"") |> should.be_true
  string.contains(first, "\"effect\":\"receipt_only\"") |> should.be_true
  simplifile.read_directory(dir)
  |> should.equal(Ok([rewind.effect_id(r) <> ".json"]))
  let assert Ok(second) = rewind.execute(r, dir)
  string.contains(second, "\"status\":\"duplicate\"") |> should.be_true
  let assert Ok(_) = simplifile.delete(dir)
}

pub fn execute_missing_dir_test() {
  let assert Ok(r) = rewind.parse("5")
  rewind.execute(
    r,
    "/tmp/uos-rewind-missing-" <> int.to_string(int.random(1_000_000_000)),
  )
  |> should.be_error
  rewind.execute(r, "relative") |> should.be_error
}
