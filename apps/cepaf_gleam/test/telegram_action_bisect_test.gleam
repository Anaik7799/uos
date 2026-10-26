import cepaf_gleam/harness/telegram_action_bisect as bisect
import gleam/int
import gleam/list
import gleam/string
import gleeunit/should
import simplifile

fn fresh() -> String {
  let dir = "/tmp/uos-bisect-" <> int.to_string(int.random(1_000_000_000))
  let assert Ok(_) = simplifile.create_directory_all(dir)
  dir
}

pub fn literal_test() {
  bisect.literal() |> should.equal("/bisect")
}

pub fn parse_positive_test() {
  let assert Ok(a) = bisect.parse("0000 0010")
  let assert Ok(b) = bisect.parse("0000 0010 5")
  bisect.effect_id(a) |> string.length |> should.equal(64)
  bisect.effect_id(a) |> should.not_equal(bisect.effect_id(b))
  let assert Ok(_) = bisect.parse("  abcd1234   abcd1299  64 ")
}

pub fn parse_negative_test() {
  list.each(
    [
      "",
      "0010",
      "0010 0000",
      "0010 0010",
      "zzzz 0010",
      "0000 0010 0",
      "0000 0010 65",
      "0000 0010 x",
      "0000 0010 5 6",
      "000 0010",
      "ABCD 0010",
      "0000 0010 05",
      string.repeat("0", 13) <> " ffff",
      string.repeat("a", 300),
    ],
    fn(args) { bisect.parse(args) |> should.be_error },
  )
}

pub fn preview_next_probe_deterministic_test() {
  let assert Ok(r) = bisect.parse("0000 0010")
  let text = bisect.preview(r)
  string.contains(text, "\"confidence\":\"simulated\"") |> should.be_true
  string.contains(text, "\"status\":\"preview\"") |> should.be_true
  string.contains(text, "\"candidates\":16") |> should.be_true
  string.contains(text, "\"probes_needed\":4") |> should.be_true
  string.contains(text, "\"next_probe\":\"0008\"") |> should.be_true
  string.contains(text, "\"plan\":[\"0008\",\"0004\",\"0002\",\"0001\"]")
  |> should.be_true
  string.contains(text, "\"vcs_calls\":0") |> should.be_true
  bisect.preview(r) |> should.equal(text)
}

pub fn preview_step_cap_and_adjacent_test() {
  let assert Ok(capped) = bisect.parse("0000 0010 2")
  string.contains(bisect.preview(capped), "\"plan\":[\"0008\",\"0004\"]")
  |> should.be_true
  let assert Ok(adjacent) = bisect.parse("00ff 0100")
  let text = bisect.preview(adjacent)
  string.contains(text, "\"candidates\":1") |> should.be_true
  string.contains(text, "\"plan\":[]") |> should.be_true
  string.contains(text, "\"next_probe\":\"0100\"") |> should.be_true
}

pub fn preview_bounded_at_max_steps_test() {
  let assert Ok(r) = bisect.parse("000000000000 ffffffffffff 64")
  { string.byte_size(bisect.preview(r)) <= 3500 } |> should.be_true
}

pub fn execute_receipt_then_duplicate_test() {
  let dir = fresh()
  let assert Ok(r) = bisect.parse("0000 0010")
  let assert Ok(first) = bisect.execute(r, dir)
  string.contains(first, "\"status\":\"executed\"") |> should.be_true
  string.contains(first, "\"effect\":\"receipt_only\"") |> should.be_true
  simplifile.read_directory(dir)
  |> should.equal(Ok([bisect.effect_id(r) <> ".json"]))
  let assert Ok(second) = bisect.execute(r, dir)
  string.contains(second, "\"status\":\"duplicate\"") |> should.be_true
  let assert Ok(_) = simplifile.delete(dir)
}

pub fn execute_missing_dir_test() {
  let assert Ok(r) = bisect.parse("0000 0010")
  bisect.execute(
    r,
    "/tmp/uos-bisect-missing-" <> int.to_string(int.random(1_000_000_000)),
  )
  |> should.be_error
  bisect.execute(r, "relative") |> should.be_error
}
