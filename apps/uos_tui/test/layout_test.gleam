import gleam/int
import gleam/list
import gleeunit/should
import prng
import uos_tui/geometry.{Region}
import uos_tui/layout.{Auto, Cells, Fraction, Horizontal, Percent, Vertical}

pub fn fractions_share_remainder_test() {
  layout.resolve([Cells(2), Fraction(1), Fraction(1)], 12, [])
  |> should.equal([2, 5, 5])
}

pub fn last_fraction_takes_rounding_test() {
  layout.resolve([Fraction(1), Fraction(1), Fraction(1)], 10, [])
  |> should.equal([3, 3, 4])
}

pub fn percent_and_auto_test() {
  layout.resolve([Percent(50), Auto, Fraction(1)], 20, [0, 3, 0])
  |> should.equal([10, 3, 7])
}

pub fn overflow_fixed_yields_zero_fraction_test() {
  layout.resolve([Cells(30), Fraction(1)], 10, []) |> should.equal([30, 0])
}

pub fn arrange_vertical_test() {
  layout.arrange(Vertical, Region(0, 0, 10, 6), [Cells(2), Fraction(1)], [])
  |> should.equal([Region(0, 0, 10, 2), Region(0, 2, 10, 4)])
}

pub fn arrange_horizontal_clips_test() {
  let rs =
    layout.arrange(Horizontal, Region(0, 0, 10, 2), [Cells(8), Cells(8)], [])
  list.map(rs, fn(r) { r.width }) |> should.equal([8, 2])
}

pub fn grid_shape_test() {
  let g =
    layout.grid(Region(0, 0, 10, 4), [Fraction(1), Fraction(1)], [
      Cells(2),
      Cells(2),
    ])
  list.length(g) |> should.equal(2)
  list.map(g, list.length) |> should.equal([2, 2])
}

// Property: with at least one Fraction and no overflow, sizes sum to total; sizes never negative.
pub fn property_resolve_sums_to_total_test() {
  list.each(prng.seeds(300), fn(seed) {
    let #(total, seed) = prng.int_between(seed, 0, 200)
    let #(kinds, seed) = prng.ints(seed, 5, 0, 3)
    let #(amounts, _) = prng.ints(seed, 5, 0, 20)
    let scalars =
      list.zip(kinds, amounts)
      |> list.map(fn(p) {
        case p.0 {
          0 -> Cells(p.1)
          1 -> Fraction(int.max(p.1 % 4, 1))
          2 -> Percent(p.1 * 2)
          _ -> Auto
        }
      })
    let scalars = [Fraction(1), ..scalars]
    let sizes = layout.resolve(scalars, total, [])
    list.length(sizes) |> should.equal(list.length(scalars))
    list.all(sizes, fn(s) { s >= 0 }) |> should.be_true
    let fixed =
      list.fold(scalars, 0, fn(acc, s) {
        case s {
          Cells(n) -> acc + n
          Percent(p) -> acc + int.clamp(p, 0, 100) * total / 100
          Auto -> acc + 1
          Fraction(_) -> acc
        }
      })
    case fixed <= total {
      True -> list.fold(sizes, 0, int.add) |> should.equal(total)
      False -> Nil
    }
  })
}
