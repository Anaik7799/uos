import gleam/list
import gleeunit/should
import prng
import uos_tui/event.{
  BackTab, Backspace, Char, Ctrl, Delete, Down, End, Enter, Escape, F, Home,
  Left, PageDown, PageUp, Right, Tab, Unknown, Up,
}

pub fn printable_test() {
  event.parse_keys("ab") |> should.equal([Char("a"), Char("b")])
}

pub fn arrows_csi_and_ss3_test() {
  event.parse_keys("\u{001b}[A\u{001b}[B\u{001b}OC\u{001b}[D")
  |> should.equal([Up, Down, Right, Left])
}

pub fn tilde_sequences_test() {
  event.parse_keys(
    "\u{001b}[3~\u{001b}[5~\u{001b}[6~\u{001b}[1~\u{001b}[4~\u{001b}[15~",
  )
  |> should.equal([Delete, PageUp, PageDown, Home, End, F(5)])
}

pub fn control_keys_test() {
  event.parse_keys("\r\t\u{007f}\u{0003}")
  |> should.equal([Enter, Tab, Backspace, Ctrl("c")])
}

pub fn shift_tab_and_lone_escape_test() {
  event.parse_keys("\u{001b}[Z") |> should.equal([BackTab])
  event.parse_keys("\u{001b}") |> should.equal([Escape])
}

pub fn unknown_sequence_is_preserved_test() {
  event.parse_keys("\u{001b}[99z") |> should.equal([Unknown("\u{001b}[99z")])
}

pub fn unicode_char_test() {
  event.parse_keys("日") |> should.equal([Char("日")])
}

pub fn key_labels_test() {
  event.key_label(BackTab) |> should.equal("shift+tab")
  event.key_label(Ctrl("p")) |> should.equal("^p")
  event.key_label(Char(" ")) |> should.equal("space")
}

// Fuzz: any input parses without crashing and never yields more keys than graphemes.
pub fn fuzz_parse_never_crashes_test() {
  list.each(prng.seeds(500), fn(seed) {
    let #(txt, _) = prng.text(seed, 40)
    let keys = event.parse_keys(txt)
    { list.length(keys) <= 40 } |> should.be_true
    list.each(keys, fn(k) { event.key_label(k) |> fn(_) { Nil } })
  })
}
