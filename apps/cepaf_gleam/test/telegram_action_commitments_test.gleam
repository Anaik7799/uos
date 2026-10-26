import cepaf_gleam/harness/telegram_action_commitments as commitments
import gleam/int
import gleam/string
import gleeunit/should
import simplifile

pub fn literal_test() {
  commitments.literal() |> should.equal("/commitments")
}

pub fn parse_test() {
  let assert Ok(r) = commitments.parse("")
  let assert Ok(_) = commitments.parse("   ")
  commitments.effect_id(r) |> string.length |> should.equal(64)
  commitments.parse("all") |> should.be_error
  commitments.parse("plan-1") |> should.be_error
  commitments.parse(string.repeat(" ", 300)) |> should.be_error
}

pub fn preview_declared_test() {
  let assert Ok(r) = commitments.parse("")
  let text = commitments.preview(r)
  string.contains(text, "\"status\":\"preview\"") |> should.be_true
  string.contains(text, "\"confidence\":\"declared\"") |> should.be_true
  string.contains(text, "\"tasks_observed\":0") |> should.be_true
  string.contains(text, "uos/telegram-runtime/20261001-1150") |> should.be_true
  string.contains(
    text,
    "backend_unavailable:cepaf_gleam/harness/telegram_task_command",
  )
  |> should.be_true
  { string.byte_size(text) <= 3500 } |> should.be_true
}

pub fn execute_unavailable_and_writes_nothing_test() {
  let dir = "/tmp/uos-commitments-" <> int.to_string(int.random(1_000_000_000))
  let assert Ok(_) = simplifile.create_directory_all(dir)
  let assert Ok(r) = commitments.parse("")
  commitments.execute(r, dir)
  |> should.equal(Error(
    "backend_unavailable:cepaf_gleam/harness/telegram_task_command",
  ))
  simplifile.read_directory(dir) |> should.equal(Ok([]))
  commitments.execute(r, dir <> "-missing")
  |> should.equal(Error(
    "backend_unavailable:cepaf_gleam/harness/telegram_task_command",
  ))
  let assert Ok(_) = simplifile.delete(dir)
}
