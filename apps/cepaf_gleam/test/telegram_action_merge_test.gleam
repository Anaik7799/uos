import cepaf_gleam/harness/telegram_action_merge as merge
import gleam/int
import gleam/list
import gleam/string
import gleeunit/should
import simplifile

pub fn literal_test() {
  merge.literal() |> should.equal("/merge")
}

pub fn parse_positive_test() {
  let assert Ok(change) = merge.parse("mmztqvon")
  let assert Ok(commit) = merge.parse("52826c5a")
  merge.effect_id(change) |> string.length |> should.equal(64)
  merge.effect_id(change) |> should.not_equal(merge.effect_id(commit))
  string.contains(merge.preview(change), "\"shape\":\"change_id\"")
  |> should.be_true
  string.contains(merge.preview(commit), "\"shape\":\"commit_id\"")
  |> should.be_true
}

pub fn parse_negative_test() {
  list.each(
    [
      "",
      "abc",
      "MMZTQVON",
      "mmztqvo",
      string.repeat("k", 33),
      string.repeat("a", 41),
      "main",
      "mmztqvon; jj abandon",
      "52826c5a 52826c5b",
      "x\u{0}yzxyzxyz",
      string.repeat("k", 300),
    ],
    fn(args) { merge.parse(args) |> should.be_error },
  )
}

pub fn preview_declares_requirements_test() {
  let assert Ok(r) = merge.parse("mmztqvon")
  let text = merge.preview(r)
  string.contains(text, "\"confidence\":\"declared\"") |> should.be_true
  string.contains(text, "\"status\":\"backend_unavailable\"") |> should.be_true
  string.contains(text, "integration/main lease") |> should.be_true
  string.contains(text, "green build and test suite") |> should.be_true
  string.contains(text, "\"vcs_mutation\":false") |> should.be_true
  { string.byte_size(text) <= 3500 } |> should.be_true
}

pub fn execute_always_unavailable_and_writes_nothing_test() {
  let dir = "/tmp/uos-merge-" <> int.to_string(int.random(1_000_000_000))
  let assert Ok(_) = simplifile.create_directory_all(dir)
  let assert Ok(r) = merge.parse("mmztqvon")
  merge.execute(r, dir)
  |> should.equal(Error("backend_unavailable:integration_lease"))
  merge.execute(r, dir)
  |> should.equal(Error("backend_unavailable:integration_lease"))
  simplifile.read_directory(dir) |> should.equal(Ok([]))
  // a missing directory is still the same typed unavailability, never a write
  merge.execute(r, dir <> "-missing")
  |> should.equal(Error("backend_unavailable:integration_lease"))
  simplifile.is_directory(dir <> "-missing") |> should.equal(Ok(False))
  let assert Ok(_) = simplifile.delete(dir)
}
