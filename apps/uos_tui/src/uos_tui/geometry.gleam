//// Geometry primitives (Textual `textual.geometry` reference: Size, Offset, Region).
//// Pure, total functions. Regions are half-open cell rectangles.
//// STAMP: SC-TUI-GEOM-001 (intersection idempotent, union commutative/associative).

import gleam/int

pub type Size {
  Size(width: Int, height: Int)
}

pub type Offset {
  Offset(x: Int, y: Int)
}

pub type Region {
  Region(x: Int, y: Int, width: Int, height: Int)
}

pub const empty_region = Region(0, 0, 0, 0)

/// Region covering a whole size at the origin.
pub fn size_to_region(size: Size) -> Region {
  Region(0, 0, int.max(size.width, 0), int.max(size.height, 0))
}

pub fn region_size(region: Region) -> Size {
  Size(int.max(region.width, 0), int.max(region.height, 0))
}

pub fn area(region: Region) -> Int {
  int.max(region.width, 0) * int.max(region.height, 0)
}

pub fn is_empty(region: Region) -> Bool {
  region.width <= 0 || region.height <= 0
}

pub fn right(region: Region) -> Int {
  region.x + region.width
}

pub fn bottom(region: Region) -> Int {
  region.y + region.height
}

pub fn contains(region: Region, offset: Offset) -> Bool {
  offset.x >= region.x
  && offset.x < right(region)
  && offset.y >= region.y
  && offset.y < bottom(region)
}

pub fn translate(region: Region, by offset: Offset) -> Region {
  Region(..region, x: region.x + offset.x, y: region.y + offset.y)
}

/// Largest region contained in both. Empty (0-area) when disjoint.
pub fn intersection(a: Region, b: Region) -> Region {
  let x1 = int.max(a.x, b.x)
  let y1 = int.max(a.y, b.y)
  let x2 = int.min(right(a), right(b))
  let y2 = int.min(bottom(a), bottom(b))
  case x2 > x1 && y2 > y1 {
    True -> Region(x1, y1, x2 - x1, y2 - y1)
    False -> Region(x1, y1, 0, 0)
  }
}

/// Smallest region containing both. Empty regions are identities.
pub fn union(a: Region, b: Region) -> Region {
  case is_empty(a), is_empty(b) {
    True, True -> empty_region
    True, False -> b
    False, True -> a
    False, False -> {
      let x1 = int.min(a.x, b.x)
      let y1 = int.min(a.y, b.y)
      let x2 = int.max(right(a), right(b))
      let y2 = int.max(bottom(a), bottom(b))
      Region(x1, y1, x2 - x1, y2 - y1)
    }
  }
}

/// Shrink a region by a uniform margin, never below zero size.
pub fn shrink(region: Region, by margin: Int) -> Region {
  Region(
    region.x + margin,
    region.y + margin,
    int.max(region.width - 2 * margin, 0),
    int.max(region.height - 2 * margin, 0),
  )
}

/// Split off `n` rows from the top; returns #(top, rest).
pub fn split_top(region: Region, rows n: Int) -> #(Region, Region) {
  let n = int.clamp(n, 0, int.max(region.height, 0))
  #(
    Region(..region, height: n),
    Region(..region, y: region.y + n, height: region.height - n),
  )
}

/// Split off `n` rows from the bottom; returns #(rest, bottom).
pub fn split_bottom(region: Region, rows n: Int) -> #(Region, Region) {
  let n = int.clamp(n, 0, int.max(region.height, 0))
  #(
    Region(..region, height: region.height - n),
    Region(..region, y: bottom(region) - n, height: n),
  )
}

/// Split off `n` columns from the left; returns #(left, rest).
pub fn split_left(region: Region, columns n: Int) -> #(Region, Region) {
  let n = int.clamp(n, 0, int.max(region.width, 0))
  #(
    Region(..region, width: n),
    Region(..region, x: region.x + n, width: region.width - n),
  )
}

/// Split off `n` columns from the right; returns #(rest, right).
pub fn split_right(region: Region, columns n: Int) -> #(Region, Region) {
  let n = int.clamp(n, 0, int.max(region.width, 0))
  #(
    Region(..region, width: region.width - n),
    Region(..region, x: right(region) - n, width: n),
  )
}
