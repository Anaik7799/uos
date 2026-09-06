//// Deterministic LCG for property/fuzz/chaos tests (no external dependency).

import gleam/int
import gleam/list
import gleam/string

/// Inclusive integer range (stdlib 1.x removed list.range).
pub fn range(from: Int, to: Int) -> List(Int) {
  case from > to {
    True -> []
    False -> [from, ..range(from + 1, to)]
  }
}

pub type Seed {
  Seed(Int)
}

pub fn next(seed: Seed) -> #(Int, Seed) {
  let Seed(s) = seed
  let n =
    { s * 6_364_136_223_846_793_005 + 1_442_695_040_888_963_407 }
    % 9_223_372_036_854_775_807
  let n = int.absolute_value(n)
  #(n, Seed(n))
}

pub fn int_between(seed: Seed, lo: Int, hi: Int) -> #(Int, Seed) {
  let #(n, seed) = next(seed)
  #(lo + n % int.max(hi - lo + 1, 1), seed)
}

pub fn ints(seed: Seed, count: Int, lo: Int, hi: Int) -> #(List(Int), Seed) {
  list.fold(range(1, int.max(count, 1)), #([], seed), fn(acc, _) {
    let #(xs, s) = acc
    let #(n, s) = int_between(s, lo, hi)
    #([n, ..xs], s)
  })
}

const alphabet = [
  "a",
  "b",
  "z",
  " ",
  "─",
  "█",
  "日",
  "本",
  "é",
  "\u{001b}",
  "[",
  "A",
  "~",
  "1",
  "5",
  ";",
  "\r",
  "\t",
  "\u{007f}",
  "O",
  "🙂",
  "\u{200b}",
]

pub fn text(seed: Seed, len: Int) -> #(String, Seed) {
  let #(idx, seed) = ints(seed, len, 0, list.length(alphabet) - 1)
  let s =
    idx
    |> list.filter_map(fn(i) { alphabet |> list.drop(i) |> list.first })
    |> string.concat
  #(s, seed)
}

pub fn seeds(count: Int) -> List(Seed) {
  range(1, count) |> list.map(fn(i) { Seed(i * 7919) })
}
