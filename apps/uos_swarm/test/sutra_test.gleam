import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/string
import gleeunit/should
import uos_swarm/sutra

pub fn register_validates_test() {
  sutra.validate_register() |> should.equal(Ok(Nil))
}

pub fn register_has_at_least_42_entries_test() {
  { list.length(sutra.register()) >= 42 } |> should.be_true
}

pub fn every_pada_has_at_least_6_entries_test() {
  list.each([1, 2, 3, 4, 5, 6, 7], fn(p) {
    { list.length(sutra.by_pada(p)) >= 6 } |> should.be_true
  })
}

/// The Jujutsu discipline (S2.8..S2.14) extends pāda 2 to at least 14 sūtras, so the register
/// now carries at least 56 (operator directive: "create jujutsu ontology").
pub fn pada2_carries_the_jujutsu_sutras_test() {
  { list.length(sutra.by_pada(2)) >= 14 } |> should.be_true
  { list.length(sutra.register()) >= 56 } |> should.be_true
  list.each(
    ["S2.8", "S2.9", "S2.10", "S2.11", "S2.12", "S2.13", "S2.14"],
    fn(id) {
      case sutra.find(id) {
        Ok(s) -> {
          s.pada |> should.equal(2)
          list.contains(s.aspects, 2) |> should.be_true
        }
        Error(_) -> should.fail()
      }
    },
  )
  let assert Ok(s2_12) = sutra.find("S2.12")
  s2_12.kinds |> should.equal(["Integrate", "Plan"])
  let assert Ok(s2_13) = sutra.find("S2.13")
  s2_13.kinds |> should.equal(["Integrate"])
}

pub fn find_locates_a_known_sutra_test() {
  case sutra.find("S5.1") {
    Ok(s) -> {
      s.pada |> should.equal(5)
      { s.english != "" } |> should.be_true
    }
    Error(_) -> should.fail()
  }
  sutra.find("S99.99") |> should.equal(Error(Nil))
}

pub fn for_kind_ack_is_nonempty_test() {
  { sutra.for_kind("Ack") != [] } |> should.be_true
}

pub fn for_aspect_matches_registered_aspects_test() {
  case sutra.find("S1.5") {
    Ok(s) -> {
      list.each(s.aspects, fn(a) {
        { sutra.for_aspect(a) != [] } |> should.be_true
      })
    }
    Error(_) -> should.fail()
  }
}

pub fn markdown_contains_devanagari_test() {
  let md = sutra.to_markdown()
  case sutra.find("S1.5") {
    Ok(s) -> string.contains(md, s.devanagari) |> should.be_true
    Error(_) -> should.fail()
  }
  string.contains(md, "id") |> should.be_true
}

type SutraStub {
  SutraStub(id: String, pada: Int)
}

fn sutra_stub_decoder() -> decode.Decoder(SutraStub) {
  use id <- decode.field("id", decode.string)
  use pada <- decode.field("pada", decode.int)
  decode.success(SutraStub(id, pada))
}

pub fn json_round_trips_and_sizes_match_test() {
  let text = json.to_string(sutra.to_json())
  case json.parse(text, decode.list(sutra_stub_decoder())) {
    Ok(stubs) -> {
      list.length(stubs) |> should.equal(list.length(sutra.register()))
      list.each(stubs, fn(s) {
        { s.pada >= 1 && s.pada <= 7 } |> should.be_true
      })
    }
    Error(_) -> should.fail()
  }
}
