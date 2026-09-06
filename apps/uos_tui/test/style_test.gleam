import gleam/list
import gleam/string
import gleeunit/should
import prng
import uos_tui/style.{type Style, Ansi256, Cyan, Default, Red, Rgb, Style}

pub fn none_has_no_sgr_test() {
  style.to_sgr(style.none) |> should.equal("")
}

pub fn fg_red_bold_test() {
  style.none
  |> style.fg(Red)
  |> style.bold
  |> style.to_sgr
  |> should.equal("\u{001b}[1;31m")
}

pub fn bg_bright_test() {
  style.none
  |> style.bg(style.BrightCyan)
  |> style.to_sgr
  |> should.equal("\u{001b}[106m")
}

pub fn ansi256_and_rgb_test() {
  style.none
  |> style.fg(Ansi256(300))
  |> style.to_sgr
  |> should.equal("\u{001b}[38;5;255m")
  style.none
  |> style.bg(Rgb(-1, 128, 999))
  |> style.to_sgr
  |> should.equal("\u{001b}[48;2;0;128;255m")
}

pub fn combine_right_wins_for_colors_test() {
  let base = style.none |> style.fg(Red)
  let over = style.none |> style.fg(Cyan)
  style.combine(base, over).fg |> should.equal(Cyan)
  style.combine(over, style.none).fg |> should.equal(Cyan)
}

pub fn combine_identity_and_flags_or_test() {
  let s = Style(Red, Default, True, False, True, False, False)
  style.combine(style.none, s) |> should.equal(s)
  style.combine(s, style.none) |> should.equal(s)
  style.combine(s, style.underline(style.none)).underline |> should.be_true
}

fn rand_style(seed: prng.Seed) -> #(Style, prng.Seed) {
  let #(bits, seed) = prng.ints(seed, 7, 0, 3)
  let color = fn(n) {
    case n {
      0 -> Default
      1 -> Red
      2 -> Ansi256(n * 40)
      _ -> Rgb(n, n, n)
    }
  }
  case bits {
    [a, b, c, d, e, f, g] -> #(
      Style(color(a), color(b), c == 1, d == 1, e == 1, f == 1, g == 1),
      seed,
    )
    _ -> #(style.none, seed)
  }
}

// Property: combine is associative and every SGR string is well-formed.
pub fn property_combine_associative_test() {
  list.each(prng.seeds(200), fn(seed) {
    let #(a, seed) = rand_style(seed)
    let #(b, seed) = rand_style(seed)
    let #(c, _) = rand_style(seed)
    style.combine(style.combine(a, b), c)
    |> should.equal(style.combine(a, style.combine(b, c)))
    let sgr = style.to_sgr(a)
    {
      sgr == ""
      || { string.starts_with(sgr, "\u{001b}[") && string.ends_with(sgr, "m") }
    }
    |> should.be_true
  })
}
