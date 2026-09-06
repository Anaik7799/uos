//// Keys and events (Textual `events.Key` / `Resize` / `Mount` reference).
//// `parse_keys` is total: any byte string yields a list of keys, unknown sequences become `Unknown`.
//// STAMP: SC-TUI-KEY-001 (fuzz: never crashes, never drops printable input).

import gleam/list
import gleam/string
import uos_tui/geometry.{type Size}

pub type Key {
  Char(String)
  Enter
  Escape
  Backspace
  Tab
  BackTab
  Up
  Down
  Left
  Right
  Home
  End
  PageUp
  PageDown
  Delete
  Insert
  F(Int)
  Ctrl(String)
  Unknown(String)
}

pub type Event {
  Mount
  KeyPress(Key)
  Resize(Size)
  Tick(elapsed_ms: Int)
  Paste(String)
}

/// Parse raw terminal input into keys.
pub fn parse_keys(input: String) -> List(Key) {
  parse_loop(string.to_graphemes(input), [])
  |> list.reverse
}

fn parse_loop(chars: List(String), acc: List(Key)) -> List(Key) {
  case chars {
    [] -> acc
    ["\u{001b}", "[", ..rest] -> {
      let #(key, remaining) = parse_csi(rest, "")
      parse_loop(remaining, [key, ..acc])
    }
    ["\u{001b}", "O", c, ..rest] -> parse_loop(rest, [ss3(c), ..acc])
    ["\u{001b}"] -> [Escape, ..acc]
    ["\u{001b}", "\u{001b}", ..rest] -> parse_loop(rest, [Escape, ..acc])
    ["\u{001b}", c, ..rest] ->
      parse_loop(rest, [Unknown("\u{001b}" <> c), ..acc])
    ["\r", ..rest] | ["\n", ..rest] -> parse_loop(rest, [Enter, ..acc])
    ["\t", ..rest] -> parse_loop(rest, [Tab, ..acc])
    ["\u{007f}", ..rest] | ["\u{0008}", ..rest] ->
      parse_loop(rest, [Backspace, ..acc])
    [c, ..rest] -> parse_loop(rest, [classify(c), ..acc])
  }
}

fn classify(c: String) -> Key {
  case string.to_utf_codepoints(c) {
    [cp] -> {
      let n = string.utf_codepoint_to_int(cp)
      case n >= 1 && n <= 26 {
        True -> Ctrl(letter(n))
        False ->
          case n < 32 {
            True -> Unknown(c)
            False -> Char(c)
          }
      }
    }
    _ -> Char(c)
  }
}

fn letter(n: Int) -> String {
  let letters = "abcdefghijklmnopqrstuvwxyz"
  string.slice(letters, n - 1, 1)
}

fn ss3(c: String) -> Key {
  case c {
    "A" -> Up
    "B" -> Down
    "C" -> Right
    "D" -> Left
    "H" -> Home
    "F" -> End
    "P" -> F(1)
    "Q" -> F(2)
    "R" -> F(3)
    "S" -> F(4)
    other -> Unknown("\u{001b}O" <> other)
  }
}

fn parse_csi(chars: List(String), params: String) -> #(Key, List(String)) {
  case chars {
    [] -> #(Unknown("\u{001b}[" <> params), [])
    [c, ..rest] ->
      case c {
        "A" -> #(Up, rest)
        "B" -> #(Down, rest)
        "C" -> #(Right, rest)
        "D" -> #(Left, rest)
        "H" -> #(Home, rest)
        "F" -> #(End, rest)
        "Z" -> #(BackTab, rest)
        "~" -> #(tilde(params), rest)
        _ ->
          case is_param_char(c) {
            True -> parse_csi(rest, params <> c)
            False -> #(Unknown("\u{001b}[" <> params <> c), rest)
          }
      }
  }
}

fn is_param_char(c: String) -> Bool {
  case c {
    "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" | ";" -> True
    _ -> False
  }
}

fn tilde(params: String) -> Key {
  case params {
    "1" | "7" -> Home
    "2" -> Insert
    "3" -> Delete
    "4" | "8" -> End
    "5" -> PageUp
    "6" -> PageDown
    "11" -> F(1)
    "12" -> F(2)
    "13" -> F(3)
    "14" -> F(4)
    "15" -> F(5)
    "17" -> F(6)
    "18" -> F(7)
    "19" -> F(8)
    "20" -> F(9)
    "21" -> F(10)
    "23" -> F(11)
    "24" -> F(12)
    other -> Unknown("\u{001b}[" <> other <> "~")
  }
}

/// Human label for footers (Textual Footer reference).
pub fn key_label(key: Key) -> String {
  case key {
    Char(" ") -> "space"
    Char(c) -> c
    Enter -> "enter"
    Escape -> "esc"
    Backspace -> "backspace"
    Tab -> "tab"
    BackTab -> "shift+tab"
    Up -> "↑"
    Down -> "↓"
    Left -> "←"
    Right -> "→"
    Home -> "home"
    End -> "end"
    PageUp -> "pgup"
    PageDown -> "pgdn"
    Delete -> "del"
    Insert -> "ins"
    F(n) -> "F" <> string.inspect(n)
    Ctrl(c) -> "^" <> c
    Unknown(_) -> "?"
  }
}
