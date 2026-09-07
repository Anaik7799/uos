//// Layout resolution (Textual `Scalar` units and vertical/horizontal/grid layouts reference).
//// `resolve` distributes `total` cells over a list of scalars: fixed Cells first, then
//// Percent of total, Auto takes its content size, and Fraction shares the remainder.
//// Invariant: sum(resolve(..)) == total whenever at least one Fraction is present.
//// STAMP: SC-TUI-LAYOUT-001.

import gleam/int
import gleam/list
import uos_tui/geometry.{type Region, Region}

pub type Scalar {
  Cells(Int)
  Fraction(Int)
  Percent(Int)
  Auto
}

pub type Direction {
  Vertical
  Horizontal
}

/// Resolve scalars to concrete sizes. `auto_sizes` supplies the content size for each
/// `Auto` entry (positionally; missing entries count as 1).
pub fn resolve(
  scalars: List(Scalar),
  total: Int,
  auto_sizes: List(Int),
) -> List(Int) {
  let total = int.max(total, 0)
  let fixed =
    list.index_map(scalars, fn(s, i) {
      case s {
        Cells(n) -> int.max(n, 0)
        Percent(p) -> int.clamp(p, 0, 100) * total / 100
        Auto ->
          auto_sizes |> list.drop(i) |> list.first |> unwrap_or(1) |> int.max(0)
        Fraction(_) -> 0
      }
    })
  let fixed_sum = list.fold(fixed, 0, int.add)
  let fr_total =
    list.fold(scalars, 0, fn(acc, s) {
      case s {
        Fraction(f) -> acc + int.max(f, 0)
        _ -> acc
      }
    })
  let remaining = int.max(total - fixed_sum, 0)
  // Distribute remaining over fractions, giving the rounding remainder to the last fraction.
  let #(sizes, _, _) =
    list.fold(
      list.zip(scalars, fixed),
      #([], remaining, fr_total),
      fn(acc, pair) {
        let #(out, left, fr_left) = acc
        let #(scalar, size) = pair
        case scalar {
          Fraction(f) -> {
            let f = int.max(f, 0)
            let share = case fr_left == f {
              True -> left
              False ->
                case fr_total > 0 {
                  True -> remaining * f / fr_total
                  False -> 0
                }
            }
            let share = int.min(share, left)
            #([share, ..out], left - share, fr_left - f)
          }
          _ -> #([size, ..out], left, fr_left)
        }
      },
    )
  list.reverse(sizes)
}

fn unwrap_or(r: Result(a, b), default: a) -> a {
  case r {
    Ok(v) -> v
    Error(_) -> default
  }
}

/// Arrange child regions inside `region` along `direction`.
pub fn arrange(
  direction: Direction,
  region: Region,
  scalars: List(Scalar),
  auto_sizes: List(Int),
) -> List(Region) {
  let total = case direction {
    Vertical -> region.height
    Horizontal -> region.width
  }
  let sizes = resolve(scalars, total, auto_sizes)
  let #(regions, _) =
    list.fold(sizes, #([], 0), fn(acc, size) {
      let #(out, cursor) = acc
      let r = case direction {
        Vertical -> Region(region.x, region.y + cursor, region.width, size)
        Horizontal -> Region(region.x + cursor, region.y, size, region.height)
      }
      #([r, ..out], cursor + size)
    })
  regions |> list.reverse |> list.map(geometry.intersection(region, _))
}

/// Grid of regions, row-major, from column and row scalars.
pub fn grid(
  region: Region,
  columns: List(Scalar),
  rows: List(Scalar),
) -> List(List(Region)) {
  let row_regions = arrange(Vertical, region, rows, [])
  list.map(row_regions, fn(row) { arrange(Horizontal, row, columns, []) })
}
