import gleam/list
import gleam/string
import gleeunit/should
import prng
import uos_tui/segment
import uos_tui/style

pub fn ascii_width_test() {
  segment.cell_width("hello") |> should.equal(5)
}

pub fn cjk_is_double_width_test() {
  segment.cell_width("日本") |> should.equal(4)
}

pub fn combining_and_zero_width_test() {
  segment.cell_width("e\u{0301}") |> should.equal(1)
  segment.cell_width("a\u{200b}b") |> should.equal(2)
}

pub fn emoji_width_test() {
  segment.cell_width("🙂") |> should.equal(2)
}

pub fn crop_ascii_test() {
  segment.plain("abcdef")
  |> segment.crop(3)
  |> segment.plain_text
  |> should.equal("abc")
}

pub fn crop_does_not_split_wide_glyph_test() {
  let s = segment.plain("a日b") |> segment.crop(2)
  segment.plain_text(s) |> should.equal("a")
  s.cell_length |> should.equal(1)
}

pub fn extend_pads_to_width_test() {
  let s = segment.plain("ab") |> segment.extend(5, style.none)
  s.cell_length |> should.equal(5)
  segment.plain_text(s) |> should.equal("ab   ")
}

pub fn fit_is_exact_test() {
  segment.plain("abcdefgh")
  |> segment.fit(4, style.none)
  |> fn(s) { s.cell_length }
  |> should.equal(4)
  segment.plain("ab")
  |> segment.fit(4, style.none)
  |> fn(s) { s.cell_length }
  |> should.equal(4)
}

pub fn simplify_merges_same_style_test() {
  let s =
    segment.from_segments([
      segment.Segment("a", style.none),
      segment.Segment("b", style.none),
      segment.Segment("c", style.bold(style.none)),
    ])
  segment.simplify(s).segments |> list.length |> should.equal(2)
}

pub fn to_ansi_wraps_styled_segments_test() {
  segment.text("x", style.bold(style.none))
  |> segment.to_ansi
  |> should.equal("\u{001b}[1mx\u{001b}[0m")
  segment.plain("x") |> segment.to_ansi |> should.equal("x")
}

// Property: crop never exceeds width; fit is exactly width; plain_text of crop is a prefix.
pub fn property_crop_and_fit_test() {
  list.each(prng.seeds(300), fn(seed) {
    let #(txt, seed) = prng.text(seed, 24)
    let #(w, _) = prng.int_between(seed, 0, 30)
    let s = segment.plain(txt)
    let c = segment.crop(s, w)
    { c.cell_length <= w } |> should.be_true
    string.starts_with(segment.plain_text(s), segment.plain_text(c))
    |> should.be_true
    segment.fit(s, w, style.none).cell_length |> should.equal(w)
    // cell_length always agrees with recomputation
    c.cell_length |> should.equal(segment.cell_width(segment.plain_text(c)))
  })
}
