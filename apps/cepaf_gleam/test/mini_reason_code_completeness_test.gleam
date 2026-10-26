//// Review A-01 follow-up (wave 6l, section 6): the closed reason list in
//// `mini_api` is honest only while every `Unavailable("…")` literal written in
//// the Mini App modules is a member of it. A literal outside the list renders
//// as `unavailable_unspecified`, which leaks nothing but loses the typed
//// absence this surface exists to report. This suite reads the module sources
//// at test time and refuses a literal the list does not know, so the next
//// observer reason cannot be added without being named.

import cepaf_gleam/telegram/mini_api as api
import gleam/list
import gleam/string
import gleeunit/should
import simplifile

const telegram_src = "src/cepaf_gleam/telegram"

/// Every string literal passed to `Unavailable(…)`; a variable argument is not
/// a literal and is skipped.
pub fn literals_in(source: String) -> List(String) {
  case string.split(source, "Unavailable(\"") {
    [] -> []
    [_, ..tails] ->
      list.filter_map(tails, fn(tail) {
        case string.split_once(tail, "\"") {
          Ok(#(literal, _)) -> Ok(literal)
          Error(_) -> Error(Nil)
        }
      })
  }
}

pub fn extraction_reads_only_string_literals_test() {
  literals_in(
    "x Unavailable(\"a_b\") y Unavailable(reason) z Unavailable(\"c\") tail",
  )
  |> should.equal(["a_b", "c"])
  literals_in("nothing here") |> should.equal([])
}

pub fn every_unavailable_literal_is_a_closed_reason_code_test() {
  let assert Ok(files) = simplifile.read_directory(telegram_src)
  let literals =
    files
    |> list.filter(fn(f) { string.ends_with(f, ".gleam") })
    |> list.sort(string.compare)
    |> list.flat_map(fn(f) {
      let assert Ok(source) = simplifile.read(telegram_src <> "/" <> f)
      literals_in(source) |> list.map(fn(l) { #(f, l) })
    })
  // The scan saw the modules; a wrong working directory must not pass
  // vacuously.
  { list.length(literals) >= 10 } |> should.be_true
  literals
  |> list.filter(fn(pair) { !list.contains(api.unavailability_reasons, pair.1) })
  |> should.equal([])
}

pub fn every_closed_reason_renders_itself_test() {
  api.unavailability_reasons
  |> list.each(fn(r) { api.reason_code(r) |> should.equal(r) })
  // The reason the span wrapper uses for a crashed backend is a member.
  api.reason_code("backend_exception") |> should.equal("backend_exception")
  api.reason_code("not_a_reason") |> should.equal("unavailable_unspecified")
}

pub fn closed_list_has_no_duplicates_test() {
  list.length(list.unique(api.unavailability_reasons))
  |> should.equal(list.length(api.unavailability_reasons))
}
