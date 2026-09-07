//// Tests for uos_tui/diff: dirty-row frame diffing.
//// STAMP: SC-TUI-W05-001.

import gleam/list
import gleam/string
import gleeunit/should
import prng
import uos_tui/diff
import uos_tui/frame
import uos_tui/geometry.{type Size, Region, Size}
import uos_tui/segment
import uos_tui/style

fn small_frame() -> frame.Frame {
  frame.blank(Size(6, 3), style.none)
}

pub fn identical_frames_have_no_changes_test() {
  let f = small_frame()
  diff.diff(f, f)
  |> should.equal([])
}

pub fn single_row_change_reports_that_row_test() {
  let prev = small_frame()
  let strip = segment.plain("hi    ")
  let next = frame.blit(prev, Region(0, 1, 6, 1), [strip], style.none)
  let changes = diff.diff(prev, next)
  case changes {
    [diff.Change(row, _)] -> row |> should.equal(1)
    _ -> should.fail()
  }
}

pub fn size_change_reports_every_row_test() {
  let prev = frame.blank(Size(4, 2), style.none)
  let next = frame.blank(Size(4, 3), style.none)
  let changes = diff.diff(prev, next)
  list.length(changes) |> should.equal(3)
}

pub fn full_repaint_covers_all_rows_test() {
  let next = frame.blank(Size(5, 4), style.none)
  let changes = diff.full_repaint(next)
  list.length(changes) |> should.equal(4)
  changes
  |> list.map(fn(c) { c.row })
  |> should.equal([0, 1, 2, 3])
}

pub fn patch_matches_next_for_same_size_frames_test() {
  let prev = small_frame()
  let strip = segment.plain("abcdef")
  let next = frame.blit(prev, Region(0, 2, 6, 1), [strip], style.none)
  let changes = diff.diff(prev, next)
  diff.patch(prev, changes)
  |> should.equal(next)
}

pub fn patch_out_of_range_rows_are_ignored_test() {
  let prev = small_frame()
  let bogus = diff.Change(row: 99, strip: segment.plain("xxxxxx"))
  diff.patch(prev, [bogus])
  |> should.equal(prev)
}

pub fn patch_preserves_frame_size_test() {
  let prev = small_frame()
  let patched = diff.patch(prev, [])
  patched.size |> should.equal(prev.size)
}

pub fn to_ansi_contains_cursor_sequence_for_row_test() {
  let change = diff.Change(row: 2, strip: segment.plain("hey"))
  let out = diff.to_ansi([change])
  out
  |> string.contains("\u{001b}[3;1H")
  |> should.be_true
}

pub fn stats_sums_changed_and_bytes_saved_test() {
  let prev = small_frame()
  let strip = segment.plain("zzzzzz")
  let next = frame.blit(prev, Region(0, 0, 6, 1), [strip], style.none)
  let #(changed, total, saved) = diff.stats(prev, next)
  changed |> should.equal(1)
  total |> should.equal(3)
  // two unchanged blank rows of width 6 -> 12 bytes
  saved |> should.equal(12)
}

pub fn stats_size_change_reports_zero_saved_test() {
  let prev = frame.blank(Size(4, 2), style.none)
  let next = frame.blank(Size(4, 3), style.none)
  let #(_, _, saved) = diff.stats(prev, next)
  saved |> should.equal(0)
}

fn random_frame(seed: prng.Seed, size: Size) -> #(frame.Frame, prng.Seed) {
  let base = frame.blank(size, style.none)
  case size.width > 0 && size.height > 0 {
    False -> #(base, seed)
    True -> {
      let #(row, seed1) = prng.int_between(seed, 0, size.height - 1)
      let #(len, seed2) = prng.int_between(seed1, 1, size.width)
      let #(text, seed3) = prng.text(seed2, len)
      let strip = segment.plain(text)
      let painted =
        frame.blit(base, Region(0, row, size.width, 1), [strip], style.none)
      #(painted, seed3)
    }
  }
}

pub fn property_patch_reconstructs_next_for_random_frames_test() {
  prng.seeds(200)
  |> list.each(fn(seed) {
    let size = Size(8, 5)
    let prev = frame.blank(size, style.none)
    let #(next, _) = random_frame(seed, size)
    let changes = diff.diff(prev, next)
    diff.patch(prev, changes)
    |> should.equal(next)
  })
}

pub fn chaos_diff_and_patch_never_crash_for_random_sizes_test() {
  prng.seeds(60)
  |> list.each(fn(seed) {
    let #(w, seed1) = prng.int_between(seed, 0, 6)
    let #(h, seed2) = prng.int_between(seed1, 0, 6)
    let size = Size(w, h)
    let prev = frame.blank(size, style.none)
    let #(next, _) = random_frame(seed2, size)
    let changes = diff.diff(prev, next)
    let patched = diff.patch(prev, changes)
    patched.size |> should.equal(prev.size)
    let _ = diff.to_ansi(changes)
    let _ = diff.stats(prev, next)
    Nil
  })
}
