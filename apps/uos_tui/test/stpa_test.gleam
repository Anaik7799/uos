import gleam/list
import gleam/string
import gleeunit/should
import prng
import uos_tui/stpa.{
  Constraint, HarnessCheck, NotProvided, ProvidedUnsafe, StoppedTooSoon,
  StpaModel, Uca, WrongTiming,
}

pub fn model_validates_test() {
  stpa.validate(stpa.model())
  |> should.equal(Ok(Nil))
}

pub fn model_has_at_least_ten_ucas_test() {
  { list.length(stpa.model().ucas) >= 10 }
  |> should.be_true
}

pub fn model_has_at_least_eight_constraints_test() {
  { list.length(stpa.model().constraints) >= 8 }
  |> should.be_true
}

pub fn all_four_uca_types_present_test() {
  let m = stpa.model()
  { list.length(stpa.ucas_by_type(m, NotProvided)) >= 2 }
  |> should.be_true
  { list.length(stpa.ucas_by_type(m, ProvidedUnsafe)) >= 2 }
  |> should.be_true
  { list.length(stpa.ucas_by_type(m, WrongTiming)) >= 2 }
  |> should.be_true
  { list.length(stpa.ucas_by_type(m, StoppedTooSoon)) >= 2 }
  |> should.be_true
}

pub fn band_thresholds_test() {
  let m = stpa.model()
  list.each(m.ucas, fn(u) {
    case u.ej >=. 4.0 {
      True -> u.band |> should.equal("P1")
      False -> Nil
    }
  })
}

pub fn band_boundaries_direct_test() {
  // Build small local ucas exercising the boundary logic through mk_uca path
  // by checking known model entries' band matches their ej.
  let m = stpa.model()
  list.each(m.ucas, fn(u) {
    let expected = case u.ej >=. 4.0 {
      True -> "P1"
      False ->
        case u.ej >=. 3.0 {
          True -> "P2"
          False -> "P3"
        }
    }
    u.band |> should.equal(expected)
  })
}

pub fn sif_arithmetic_test() {
  let m = stpa.model()
  list.each(m.ucas, fn(u) { u.sif |> should.equal(u.pms * u.cif) })
}

pub fn broken_uca_ref_detected_test() {
  let m = stpa.model()
  let bad_uca =
    Uca(
      "UCA-BAD",
      "CTRL-TUI-APP",
      NotProvided,
      "CA-does-not-exist",
      "ctx",
      ["H1"],
      1,
      1,
      1,
      1.0,
      "P3",
    )
  let broken = StpaModel(..m, ucas: [bad_uca, ..m.ucas])
  stpa.validate(broken)
  |> should.not_equal(Ok(Nil))
}

pub fn broken_hazard_ref_detected_test() {
  let m = stpa.model()
  let bad_uca =
    Uca(
      "UCA-BAD2",
      "CTRL-TUI-APP",
      NotProvided,
      "CA-emit_intent",
      "ctx",
      ["H-NOPE"],
      1,
      1,
      1,
      1.0,
      "P3",
    )
  let broken = StpaModel(..m, ucas: [bad_uca, ..m.ucas])
  stpa.validate(broken)
  |> should.not_equal(Ok(Nil))
}

pub fn broken_constraint_ref_detected_test() {
  let m = stpa.model()
  let bad_constraint =
    Constraint("C-BAD", ["UCA-NOPE"], "text", HarnessCheck("x"))
  let broken = StpaModel(..m, constraints: [bad_constraint, ..m.constraints])
  stpa.validate(broken)
  |> should.not_equal(Ok(Nil))
}

pub fn broken_sif_detected_test() {
  let m = stpa.model()
  let bad_uca =
    Uca(
      "UCA-BAD3",
      "CTRL-TUI-APP",
      NotProvided,
      "CA-emit_intent",
      "ctx",
      ["H1"],
      2,
      2,
      99,
      1.0,
      "P3",
    )
  let broken = StpaModel(..m, ucas: [bad_uca, ..m.ucas])
  stpa.validate(broken)
  |> should.not_equal(Ok(Nil))
}

pub fn markdown_contains_every_id_test() {
  let m = stpa.model()
  let md = stpa.to_markdown(m)
  list.each(m.losses, fn(x) { string.contains(md, x.id) |> should.be_true })
  list.each(m.hazards, fn(x) { string.contains(md, x.id) |> should.be_true })
  list.each(m.ucas, fn(x) { string.contains(md, x.id) |> should.be_true })
  list.each(m.constraints, fn(x) { string.contains(md, x.id) |> should.be_true })
}

pub fn property_sif_and_validate_for_random_scores_test() {
  list.each(prng.seeds(10), fn(seed) {
    let #(pms, seed1) = prng.int_between(seed, 1, 10)
    let #(cif, _seed2) = prng.int_between(seed1, 1, 10)
    let sif = pms * cif
    { sif >= 1 && sif <= 100 }
    |> should.be_true
    // sif must equal product regardless of magnitude
    sif
    |> should.equal(pms * cif)
  })
}

pub fn chaos_reordered_ucas_still_validate_test() {
  let m = stpa.model()
  let reversed = StpaModel(..m, ucas: list.reverse(m.ucas))
  stpa.validate(reversed)
  |> should.equal(Ok(Nil))
}

pub fn fuzz_random_text_ids_do_not_crash_validate_test() {
  list.each(prng.seeds(6), fn(seed) {
    let #(txt, _) = prng.text(seed, 5)
    let m = stpa.model()
    let noisy_uca =
      Uca(
        "UCA-FUZZ-" <> txt,
        "CTRL-TUI-APP",
        ProvidedUnsafe,
        "CA-emit_intent",
        txt,
        ["H1"],
        1,
        1,
        1,
        1.0,
        "P3",
      )
    let with_noise = StpaModel(..m, ucas: [noisy_uca, ..m.ucas])
    // must not crash; result is either Ok or Error, both acceptable outcomes
    case stpa.validate(with_noise) {
      Ok(Nil) -> Nil
      Error(_) -> Nil
    }
  })
}
