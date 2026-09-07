//// Dirty-row frame diffing so the live driver repaints only changed rows.
//// Reference: Textual compositor dirty-region tracking (only touched lines are
//// re-blitted to the terminal). Zero-Muda: pure Gleam, no NIFs, no @external.
//// STAMP: SC-TUI-W05-001.

import gleam/int
import gleam/list
import gleam/string
import uos_tui/frame.{type Frame, Frame}
import uos_tui/segment.{type Strip}

/// One row that must be repainted, carrying its replacement strip.
pub type Change {
  Change(row: Int, strip: Strip)
}

/// Rows that differ between `prev` and `next`. A size change forces a full
/// repaint of every row in `next`; otherwise only rows whose simplified
/// strip differs are reported.
pub fn diff(prev: Frame, next: Frame) -> List(Change) {
  case prev.size == next.size {
    False -> full_repaint(next)
    True ->
      list.index_map(next.lines, fn(next_line, row) { #(row, next_line) })
      |> list.zip(prev.lines)
      |> list.filter_map(fn(pair) {
        let #(#(row, next_line), prev_line) = pair
        case segment.simplify(prev_line) == segment.simplify(next_line) {
          True -> Error(Nil)
          False -> Ok(Change(row, next_line))
        }
      })
  }
}

/// Every row of `next` as a Change (used when there is nothing to compare
/// against, e.g. after a size change or on first paint).
pub fn full_repaint(next: Frame) -> List(Change) {
  list.index_map(next.lines, fn(line, row) { Change(row, line) })
}

/// Apply `changes` to `prev`, replacing the addressed rows. Rows outside the
/// bounds of `prev` are ignored and the size of `prev` is always preserved.
pub fn patch(prev: Frame, changes: List(Change)) -> Frame {
  let lines =
    list.index_map(prev.lines, fn(line, row) {
      case find_change(changes, row) {
        Ok(change) -> change.strip
        Error(Nil) -> line
      }
    })
  Frame(prev.size, lines)
}

fn find_change(changes: List(Change), row: Int) -> Result(Change, Nil) {
  case changes {
    [] -> Error(Nil)
    [change, ..rest] ->
      case change.row == row {
        True -> Ok(change)
        False -> find_change(rest, row)
      }
  }
}

/// ANSI encoding of `changes`: for each, move the cursor to the row (1-based,
/// column 1), emit the simplified strip, then clear to end of line.
pub fn to_ansi(changes: List(Change)) -> String {
  changes
  |> list.map(fn(change) {
    "\u{001b}["
    <> int.to_string(change.row + 1)
    <> ";1H"
    <> segment.to_ansi(segment.simplify(change.strip))
    <> "\u{001b}[K"
  })
  |> string.concat
}

/// #(rows_changed, rows_total, bytes_saved_estimate). `bytes_saved_estimate`
/// sums the plain-text byte size of every unchanged row of `next` when the
/// frames share a size (0 when sizes differ, since nothing is reused then).
pub fn stats(prev: Frame, next: Frame) -> #(Int, Int, Int) {
  let changes = diff(prev, next)
  let changed_rows = list.map(changes, fn(change) { change.row })
  let rows_total = list.length(next.lines)
  let bytes_saved = case prev.size == next.size {
    False -> 0
    True ->
      next.lines
      |> list.index_map(fn(line, row) { #(row, line) })
      |> list.fold(0, fn(acc, pair) {
        let #(row, line) = pair
        case list.contains(changed_rows, row) {
          True -> acc
          False -> acc + string.byte_size(segment.plain_text(line))
        }
      })
  }
  #(list.length(changes), rows_total, bytes_saved)
}
