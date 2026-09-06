//// Segment and Strip (Textual `textual.strip.Strip` / Rich `Segment` reference).
//// A Strip is one terminal line: styled segments with a known cell length.
//// Widths are grapheme- and East-Asian-wide aware. All functions are total.
//// STAMP: SC-TUI-STRIP-001 (crop never exceeds width, extend always reaches width).

import gleam/int
import gleam/list
import gleam/string
import uos_tui/style.{type Style}

pub type Segment {
  Segment(text: String, style: Style)
}

pub type Strip {
  Strip(segments: List(Segment), cell_length: Int)
}

pub const empty = Strip([], 0)

/// Terminal cell width of one grapheme (0, 1, or 2).
pub fn grapheme_width(grapheme: String) -> Int {
  case string.to_utf_codepoints(grapheme) {
    [] -> 0
    [cp, ..] -> codepoint_width(string.utf_codepoint_to_int(cp))
  }
}

fn codepoint_width(cp: Int) -> Int {
  case cp {
    _ if cp == 0 -> 0
    _ if cp < 32 -> 0
    _ if cp >= 0x7f && cp < 0xa0 -> 0
    _ if cp >= 0x0300 && cp <= 0x036f -> 0
    _ if cp >= 0x200b && cp <= 0x200f -> 0
    _ if cp == 0xfe0f || cp == 0xfe0e -> 0
    _ if cp >= 0x1100 && cp <= 0x115f -> 2
    _ if cp >= 0x2e80 && cp <= 0xa4cf -> 2
    _ if cp >= 0xac00 && cp <= 0xd7a3 -> 2
    _ if cp >= 0xf900 && cp <= 0xfaff -> 2
    _ if cp >= 0xfe30 && cp <= 0xfe4f -> 2
    _ if cp >= 0xff00 && cp <= 0xff60 -> 2
    _ if cp >= 0xffe0 && cp <= 0xffe6 -> 2
    _ if cp >= 0x1f300 && cp <= 0x1f64f -> 2
    _ if cp >= 0x1f900 && cp <= 0x1f9ff -> 2
    _ if cp >= 0x20000 && cp <= 0x3fffd -> 2
    _ -> 1
  }
}

/// Cell width of a string.
pub fn cell_width(text: String) -> Int {
  text
  |> string.to_graphemes
  |> list.fold(0, fn(acc, g) { acc + grapheme_width(g) })
}

pub fn segment(text: String, style: Style) -> Segment {
  Segment(text, style)
}

pub fn from_segments(segments: List(Segment)) -> Strip {
  let width = list.fold(segments, 0, fn(acc, s) { acc + cell_width(s.text) })
  Strip(segments, width)
}

pub fn text(text: String, style: Style) -> Strip {
  from_segments([Segment(text, style)])
}

pub fn plain(text: String) -> Strip {
  from_segments([Segment(text, style.none)])
}

pub fn append(a: Strip, b: Strip) -> Strip {
  Strip(list.append(a.segments, b.segments), a.cell_length + b.cell_length)
}

pub fn concat(strips: List(Strip)) -> Strip {
  list.fold(strips, empty, append)
}

/// Text with all styling removed.
pub fn plain_text(strip: Strip) -> String {
  strip.segments |> list.map(fn(s) { s.text }) |> string.concat
}

/// Crop to at most `width` cells. Wide glyphs that would straddle the edge are dropped.
pub fn crop(strip: Strip, width: Int) -> Strip {
  let width = int.max(width, 0)
  case strip.cell_length <= width {
    True -> strip
    False -> {
      let #(segments, _) =
        list.fold(strip.segments, #([], 0), fn(acc, seg) {
          let #(kept, used) = acc
          case used >= width {
            True -> acc
            False -> {
              let #(taken, w) = take_graphemes(seg.text, width - used)
              #([Segment(taken, seg.style), ..kept], used + w)
            }
          }
        })
      from_segments(list.reverse(segments))
    }
  }
}

fn take_graphemes(text: String, budget: Int) -> #(String, Int) {
  let #(chars, used) =
    text
    |> string.to_graphemes
    |> list.fold(#([], 0), fn(acc, g) {
      let #(kept, used) = acc
      let w = grapheme_width(g)
      case used + w <= budget {
        True -> #([g, ..kept], used + w)
        False -> #(kept, budget + 1)
      }
    })
  #(chars |> list.reverse |> string.concat, int.min(used, budget))
}

/// Pad with spaces (in `pad_style`) up to `width`; no-op when already wider.
pub fn extend(strip: Strip, width: Int, pad_style: Style) -> Strip {
  case strip.cell_length >= width {
    True -> strip
    False -> {
      let padding = string.repeat(" ", width - strip.cell_length)
      Strip(list.append(strip.segments, [Segment(padding, pad_style)]), width)
    }
  }
}

/// Crop then extend: exactly `width` cells.
pub fn fit(strip: Strip, width: Int, pad_style: Style) -> Strip {
  strip |> crop(width) |> extend(width, pad_style)
}

/// Merge adjacent segments sharing a style.
pub fn simplify(strip: Strip) -> Strip {
  let merged =
    list.fold(strip.segments, [], fn(acc, seg) {
      case acc {
        [Segment(t, s), ..rest] if s == seg.style -> [
          Segment(t <> seg.text, s),
          ..rest
        ]
        _ -> [seg, ..acc]
      }
    })
  Strip(list.reverse(merged), strip.cell_length)
}

/// Apply a style over every segment.
pub fn apply_style(strip: Strip, over: Style) -> Strip {
  Strip(
    list.map(strip.segments, fn(s) {
      Segment(s.text, style.combine(s.style, over))
    }),
    strip.cell_length,
  )
}

/// ANSI encoding of one line, always ending with a reset.
pub fn to_ansi(strip: Strip) -> String {
  let body =
    strip.segments
    |> list.map(fn(s) {
      case style.is_none(s.style) {
        True -> s.text
        False -> style.to_sgr(s.style) <> s.text <> style.reset
      }
    })
    |> string.concat
  body
}
