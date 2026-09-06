//// Typed style sheet (Textual TCSS reference, expressed as Gleam records instead of a CSS parser).
//// `combine` is a monoid with `none` as identity: the right operand's explicit settings win.
//// STAMP: SC-TUI-STYLE-001.

import gleam/int
import gleam/list
import gleam/string

pub type Color {
  Default
  Black
  Red
  Green
  Yellow
  Blue
  Magenta
  Cyan
  White
  BrightBlack
  BrightRed
  BrightGreen
  BrightYellow
  BrightBlue
  BrightMagenta
  BrightCyan
  BrightWhite
  Ansi256(Int)
  Rgb(Int, Int, Int)
}

pub type Style {
  Style(
    fg: Color,
    bg: Color,
    bold: Bool,
    dim: Bool,
    italic: Bool,
    underline: Bool,
    reverse: Bool,
  )
}

pub const none = Style(Default, Default, False, False, False, False, False)

pub fn fg(style: Style, color: Color) -> Style {
  Style(..style, fg: color)
}

pub fn bg(style: Style, color: Color) -> Style {
  Style(..style, bg: color)
}

pub fn bold(style: Style) -> Style {
  Style(..style, bold: True)
}

pub fn dim(style: Style) -> Style {
  Style(..style, dim: True)
}

pub fn italic(style: Style) -> Style {
  Style(..style, italic: True)
}

pub fn underline(style: Style) -> Style {
  Style(..style, underline: True)
}

pub fn reverse(style: Style) -> Style {
  Style(..style, reverse: True)
}

/// Overlay `over` on `base`. Colors: `Default` in `over` keeps base. Flags OR.
pub fn combine(base: Style, over: Style) -> Style {
  Style(
    fg: case over.fg {
      Default -> base.fg
      c -> c
    },
    bg: case over.bg {
      Default -> base.bg
      c -> c
    },
    bold: base.bold || over.bold,
    dim: base.dim || over.dim,
    italic: base.italic || over.italic,
    underline: base.underline || over.underline,
    reverse: base.reverse || over.reverse,
  )
}

fn fg_code(color: Color) -> List(String) {
  case color {
    Default -> []
    Black -> ["30"]
    Red -> ["31"]
    Green -> ["32"]
    Yellow -> ["33"]
    Blue -> ["34"]
    Magenta -> ["35"]
    Cyan -> ["36"]
    White -> ["37"]
    BrightBlack -> ["90"]
    BrightRed -> ["91"]
    BrightGreen -> ["92"]
    BrightYellow -> ["93"]
    BrightBlue -> ["94"]
    BrightMagenta -> ["95"]
    BrightCyan -> ["96"]
    BrightWhite -> ["97"]
    Ansi256(n) -> ["38", "5", int.to_string(int.clamp(n, 0, 255))]
    Rgb(r, g, b) -> [
      "38",
      "2",
      int.to_string(int.clamp(r, 0, 255)),
      int.to_string(int.clamp(g, 0, 255)),
      int.to_string(int.clamp(b, 0, 255)),
    ]
  }
}

fn bg_code(color: Color) -> List(String) {
  case fg_code(color) {
    [] -> []
    ["38", ..rest] -> ["48", ..rest]
    [single] -> {
      // 30..37 -> 40..47, 90..97 -> 100..107
      case int.parse(single) {
        Ok(n) -> [int.to_string(n + 10)]
        Error(_) -> []
      }
    }
    other -> other
  }
}

/// SGR escape for a style; empty string for `none`.
pub fn to_sgr(style: Style) -> String {
  let flags =
    [
      #(style.bold, "1"),
      #(style.dim, "2"),
      #(style.italic, "3"),
      #(style.underline, "4"),
      #(style.reverse, "7"),
    ]
    |> list.filter_map(fn(pair) {
      case pair.0 {
        True -> Ok(pair.1)
        False -> Error(Nil)
      }
    })
  let codes =
    list.append(flags, list.append(fg_code(style.fg), bg_code(style.bg)))
  case codes {
    [] -> ""
    _ -> "\u{001b}[" <> string.join(codes, ";") <> "m"
  }
}

pub const reset = "\u{001b}[0m"

pub fn is_none(style: Style) -> Bool {
  style == none
}
