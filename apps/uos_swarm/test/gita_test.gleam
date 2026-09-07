import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/string
import gleeunit/should
import uos_swarm/gita

pub fn register_validates_test() {
  gita.validate_register() |> should.equal(Ok(Nil))
}

pub fn register_has_at_least_24_entries_test() {
  { list.length(gita.register()) >= 24 } |> should.be_true
}

pub fn verse_2_47_is_present_with_exact_first_words_test() {
  case gita.find(2, 47) {
    Ok(v) ->
      string.starts_with(v.iast, "karmaṇy evādhikāras te") |> should.be_true
    Error(_) -> should.fail()
  }
}

pub fn find_unknown_verse_is_error_test() {
  gita.find(99, 99) |> should.equal(Error(Nil))
}

pub fn for_module_aspects_admissible_is_nonempty_test() {
  { gita.for_module("aspects.admissible") != [] } |> should.be_true
}

/// Jujutsu applies_to entries (operator directive: "create jujutsu ontology"): BG 18.63
/// (operator authority) now names `jj.move_main`, BG 2.40 (append-only log) names
/// `jj.op_restore`, and BG 3.35 (svadharma / disjoint ownership) names `jj.workspace`.
pub fn for_module_jj_move_main_is_nonempty_test() {
  { gita.for_module("jj.move_main") != [] } |> should.be_true
  let assert Ok(v) = gita.find(18, 63)
  list.contains(v.applies_to, "jj.move_main") |> should.be_true
}

pub fn jujutsu_applies_to_reach_op_restore_and_workspace_test() {
  { gita.for_module("jj.op_restore") != [] } |> should.be_true
  { gita.for_module("jj.workspace") != [] } |> should.be_true
  let assert Ok(v240) = gita.find(2, 40)
  list.contains(v240.applies_to, "jj.op_restore") |> should.be_true
  let assert Ok(v335) = gita.find(3, 35)
  list.contains(v335.applies_to, "jj.workspace") |> should.be_true
}

pub fn cite_formats_bg_reference_test() {
  let text = gita.cite(2, 47)
  string.starts_with(text, "BG 2.47 · karmaṇy evādhikāras te")
  |> should.be_true
  string.contains(text, "; en:") |> should.be_true
}

type VerseStub {
  VerseStub(chapter: Int, verse: Int)
}

fn verse_stub_decoder() -> decode.Decoder(VerseStub) {
  use chapter <- decode.field("chapter", decode.int)
  use verse <- decode.field("verse", decode.int)
  decode.success(VerseStub(chapter, verse))
}

pub fn json_round_trips_and_sizes_match_test() {
  let text = json.to_string(gita.to_json())
  case json.parse(text, decode.list(verse_stub_decoder())) {
    Ok(stubs) -> {
      list.length(stubs) |> should.equal(list.length(gita.register()))
      list.each(stubs, fn(v) {
        { v.chapter >= 1 && v.chapter <= 18 } |> should.be_true
      })
    }
    Error(_) -> should.fail()
  }
}

pub fn markdown_contains_devanagari_test() {
  let md = gita.to_markdown()
  case gita.find(2, 47) {
    Ok(v) -> string.contains(md, v.devanagari) |> should.be_true
    Error(_) -> should.fail()
  }
}
