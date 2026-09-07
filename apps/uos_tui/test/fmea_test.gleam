import gleam/list
import gleam/string
import gleeunit/should
import prng
import uos_tui/fmea.{FailureMode}

pub fn model_validates_test() {
  fmea.validate(fmea.model())
  |> should.equal(Ok(Nil))
}

pub fn model_has_at_least_twelve_rows_test() {
  { list.length(fmea.model()) >= 12 }
  |> should.be_true
}

pub fn rpn_arithmetic_test() {
  list.each(fmea.model(), fn(f) {
    fmea.rpn(f) |> should.equal(f.severity * f.occurrence * f.detection)
  })
}

pub fn duplicate_id_detected_test() {
  let rows = fmea.model()
  let assert Ok(first) = list.first(rows)
  let dup = FailureMode(..first, id: first.id)
  fmea.validate([dup, ..rows])
  |> should.not_equal(Ok(Nil))
}

pub fn out_of_range_score_detected_test() {
  let rows = fmea.model()
  let bad =
    FailureMode(
      "FM-BAD",
      "item",
      "mode",
      "effect",
      "cause",
      11,
      1,
      1,
      "mitigation",
      "open",
    )
  fmea.validate([bad, ..rows])
  |> should.not_equal(Ok(Nil))
}

pub fn top_ordering_test() {
  let rows = fmea.model()
  let top3 = fmea.top(rows, 3)
  { list.length(top3) == 3 }
  |> should.be_true
  case top3 {
    [a, b, c] -> {
      { fmea.rpn(a) >= fmea.rpn(b) }
      |> should.be_true
      { fmea.rpn(b) >= fmea.rpn(c) }
      |> should.be_true
    }
    _ -> should.fail()
  }
}

pub fn markdown_contains_every_id_test() {
  let rows = fmea.model()
  let md = fmea.to_markdown(rows)
  list.each(rows, fn(f) { string.contains(md, f.id) |> should.be_true })
}

pub fn property_rpn_in_range_for_random_scores_test() {
  list.each(prng.seeds(12), fn(seed) {
    let #(s, seed1) = prng.int_between(seed, 1, 10)
    let #(o, seed2) = prng.int_between(seed1, 1, 10)
    let #(d, _seed3) = prng.int_between(seed2, 1, 10)
    let f =
      FailureMode(
        "FM-PROP",
        "item",
        "mode",
        "effect",
        "cause",
        s,
        o,
        d,
        "m",
        "open",
      )
    let r = fmea.rpn(f)
    { r >= 1 && r <= 1000 }
    |> should.be_true
    fmea.validate([f])
    |> should.equal(Ok(Nil))
  })
}

pub fn fuzz_random_text_ids_never_crash_validate_test() {
  list.each(prng.seeds(8), fn(seed) {
    let #(txt, _) = prng.text(seed, 6)
    let rows = [
      FailureMode("FM-FUZZ-" <> txt, txt, txt, txt, txt, 5, 5, 5, txt, "open"),
      ..fmea.model()
    ]
    case fmea.validate(rows) {
      Ok(Nil) -> Nil
      Error(_) -> Nil
    }
  })
}

pub fn chaos_shuffled_rows_keep_validate_result_test() {
  let rows = fmea.model()
  let reversed = list.reverse(rows)
  fmea.validate(rows)
  |> should.equal(fmea.validate(reversed))
}
