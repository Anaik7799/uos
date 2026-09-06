import gleam/list
import gleam/string
import gleeunit/should
import prng
import uos_tui/frame
import uos_tui/geometry.{Region, Size}
import uos_tui/segment
import uos_tui/style

pub fn blank_is_well_formed_test() {
  frame.blank(Size(10, 3), style.none) |> frame.is_well_formed |> should.be_true
}

pub fn blit_places_text_test() {
  let f =
    frame.blank(Size(10, 2), style.none)
    |> frame.blit(Region(2, 1, 5, 1), [segment.plain("hello")], style.none)
  frame.to_text(f) |> should.equal("          \n  hello   ")
}

pub fn blit_clips_to_region_and_frame_test() {
  let f =
    frame.blank(Size(6, 1), style.none)
    |> frame.blit(Region(4, 0, 10, 1), [segment.plain("abcdef")], style.none)
  frame.to_text(f) |> should.equal("    ab")
  frame.is_well_formed(f) |> should.be_true
}

pub fn blit_negative_origin_test() {
  let f =
    frame.blank(Size(4, 1), style.none)
    |> frame.blit(Region(-2, 0, 5, 1), [segment.plain("abcde")], style.none)
  frame.to_text(f) |> should.equal("cde ")
}

pub fn to_ansi_has_one_line_per_row_test() {
  let f = frame.blank(Size(3, 4), style.none)
  frame.to_ansi(f) |> string.split("\r\n") |> list.length |> should.equal(4)
}

pub fn zero_size_frame_test() {
  let f = frame.blank(Size(0, 0), style.none)
  frame.is_well_formed(f) |> should.be_true
  frame.to_text(f) |> should.equal("")
}

// Chaos: random blits at random regions into random frames always preserve the invariant.
pub fn chaos_blit_preserves_invariant_test() {
  list.each(prng.seeds(300), fn(seed) {
    let #(w, h, x, y, rw, rh, seed) = case prng.ints(seed, 6, -5, 30) {
      #([a, b, c, d, e, f], s) -> #(a, b, c, d, e, f, s)
      #(_, s) -> #(1, 1, 0, 0, 1, 1, s)
    }
    let #(txt, _) = prng.text(seed, 12)
    let f = frame.blank(Size(w, h), style.none)
    let out =
      frame.blit(
        f,
        Region(x, y, rw, rh),
        [segment.plain(txt), segment.plain(txt)],
        style.none,
      )
    frame.is_well_formed(out) |> should.be_true
  })
}
