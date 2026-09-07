//// Frame: a fixed-size grid of Strips (Textual compositor output reference).
//// Invariant: every line is exactly `size.width` cells and there are exactly `size.height` lines.
//// STAMP: SC-TUI-FRAME-001.

import gleam/int
import gleam/list
import gleam/string
import uos_tui/geometry.{type Region, type Size, Region, Size}
import uos_tui/segment.{type Strip}
import uos_tui/style.{type Style}

pub type Frame {
  Frame(size: Size, lines: List(Strip))
}

/// Blank frame filled with spaces in `fill`.
pub fn blank(size: Size, fill: Style) -> Frame {
  let width = int.max(size.width, 0)
  let height = int.max(size.height, 0)
  let line = segment.extend(segment.empty, width, fill)
  Frame(Size(width, height), list.repeat(line, height))
}

/// Paint `strips` into `region` (clipped to the frame). Strips beyond the region height are dropped;
/// missing strips leave the existing content untouched.
pub fn blit(
  frame: Frame,
  region: Region,
  strips: List(Strip),
  fill: Style,
) -> Frame {
  let bounds = geometry.size_to_region(frame.size)
  let clip = geometry.intersection(bounds, region)
  case geometry.is_empty(clip) {
    True -> frame
    False -> {
      let lines =
        list.index_map(frame.lines, fn(line, y) {
          case y >= clip.y && y < geometry.bottom(clip) {
            True -> {
              let row = y - region.y
              case at(strips, row) {
                Ok(strip) -> {
                  // Cells of the strip that fall inside the clipped column window.
                  let skip = clip.x - region.x
                  let visible =
                    strip |> drop_cells(skip) |> segment.fit(clip.width, fill)
                  splice(line, clip.x, visible)
                }
                Error(_) -> line
              }
            }
            False -> line
          }
        })
      Frame(frame.size, lines)
    }
  }
}

fn at(items: List(a), index: Int) -> Result(a, Nil) {
  case index < 0 {
    True -> Error(Nil)
    False -> items |> list.drop(index) |> list.first
  }
}

/// Drop the first `n` cells of a strip.
fn drop_cells(strip: Strip, n: Int) -> Strip {
  case n <= 0 {
    True -> strip
    False -> {
      let #(kept, _) =
        list.fold(strip.segments, #([], n), fn(acc, seg) {
          let #(kept, remaining) = acc
          case remaining <= 0 {
            True -> #([seg, ..kept], 0)
            False -> {
              let w = segment.cell_width(seg.text)
              case w <= remaining {
                True -> #(kept, remaining - w)
                False -> {
                  let graphemes = string.to_graphemes(seg.text)
                  let #(_, tail) = drop_graphemes(graphemes, remaining)
                  #(
                    [segment.Segment(string.concat(tail), seg.style), ..kept],
                    0,
                  )
                }
              }
            }
          }
        })
      segment.from_segments(list.reverse(kept))
    }
  }
}

fn drop_graphemes(graphemes: List(String), cells: Int) -> #(Int, List(String)) {
  case graphemes {
    [] -> #(0, [])
    [g, ..rest] -> {
      let w = segment.grapheme_width(g)
      case cells <= 0 {
        True -> #(0, graphemes)
        False -> drop_graphemes(rest, cells - w)
      }
    }
  }
}

/// Replace cells [x, x+len) of `line` with `patch` (patch already exact width).
fn splice(line: Strip, x: Int, patch: Strip) -> Strip {
  let left = segment.crop(line, x)
  let right = drop_cells(line, x + patch.cell_length)
  segment.concat([left, patch, right])
}

/// Every line padded/cropped to the frame width (normalisation guard).
pub fn normalise(frame: Frame, fill: Style) -> Frame {
  let width = frame.size.width
  let lines =
    frame.lines
    |> list.map(segment.fit(_, width, fill))
    |> list.take(frame.size.height)
  let missing = frame.size.height - list.length(lines)
  let pad = segment.extend(segment.empty, width, fill)
  Frame(frame.size, list.append(lines, list.repeat(pad, int.max(missing, 0))))
}

/// True when the frame invariant holds.
pub fn is_well_formed(frame: Frame) -> Bool {
  list.length(frame.lines) == frame.size.height
  && list.all(frame.lines, fn(l) { l.cell_length == frame.size.width })
}

pub fn to_ansi(frame: Frame) -> String {
  frame.lines
  |> list.map(fn(l) { segment.to_ansi(segment.simplify(l)) <> "\u{001b}[K" })
  |> string.join("\r\n")
}

pub fn to_text(frame: Frame) -> String {
  frame.lines |> list.map(segment.plain_text) |> string.join("\n")
}

pub fn region(frame: Frame) -> Region {
  Region(0, 0, frame.size.width, frame.size.height)
}
