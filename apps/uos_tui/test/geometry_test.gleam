import gleam/list
import gleeunit/should
import prng
import uos_tui/geometry.{Offset, Region, Size}

fn rand_region(seed: prng.Seed) -> #(geometry.Region, prng.Seed) {
  let #(x, y, w, h, seed) = case prng.ints(seed, 4, 0, 40) {
    #([a, b, c, d], s) -> #(a, b, c, d, s)
    #(_, s) -> #(0, 0, 1, 1, s)
  }
  #(Region(x, y, w, h), seed)
}

pub fn intersection_of_disjoint_is_empty_test() {
  geometry.intersection(Region(0, 0, 5, 5), Region(10, 10, 5, 5))
  |> geometry.is_empty
  |> should.be_true
}

pub fn intersection_overlap_test() {
  geometry.intersection(Region(0, 0, 10, 10), Region(5, 5, 10, 10))
  |> should.equal(Region(5, 5, 5, 5))
}

pub fn union_contains_both_test() {
  let u = geometry.union(Region(0, 0, 2, 2), Region(8, 8, 2, 2))
  u |> should.equal(Region(0, 0, 10, 10))
}

pub fn union_identity_test() {
  geometry.union(geometry.empty_region, Region(3, 3, 2, 2))
  |> should.equal(Region(3, 3, 2, 2))
}

pub fn contains_test() {
  geometry.contains(Region(2, 2, 3, 3), Offset(4, 4)) |> should.be_true
  geometry.contains(Region(2, 2, 3, 3), Offset(5, 4)) |> should.be_false
}

pub fn split_top_test() {
  let #(top, rest) = geometry.split_top(Region(0, 0, 10, 10), 3)
  top |> should.equal(Region(0, 0, 10, 3))
  rest |> should.equal(Region(0, 3, 10, 7))
}

pub fn split_bottom_clamps_test() {
  let #(rest, bottom) = geometry.split_bottom(Region(0, 0, 10, 4), 99)
  rest.height |> should.equal(0)
  bottom.height |> should.equal(4)
}

pub fn shrink_never_negative_test() {
  geometry.shrink(Region(0, 0, 1, 1), 5) |> geometry.area |> should.equal(0)
}

pub fn size_to_region_clamps_negative_test() {
  geometry.size_to_region(Size(-3, 4)) |> should.equal(Region(0, 0, 0, 4))
}

// Property: intersection is idempotent and commutative; union is commutative and absorbs.
pub fn property_intersection_laws_test() {
  list.each(prng.seeds(200), fn(seed) {
    let #(a, seed) = rand_region(seed)
    let #(b, _) = rand_region(seed)
    let i = geometry.intersection(a, b)
    geometry.area(geometry.intersection(i, i)) |> should.equal(geometry.area(i))
    geometry.area(geometry.intersection(b, a)) |> should.equal(geometry.area(i))
    // intersection never larger than either operand
    {
      geometry.area(i) <= geometry.area(a)
      && geometry.area(i) <= geometry.area(b)
    }
    |> should.be_true
  })
}

pub fn property_union_laws_test() {
  list.each(prng.seeds(200), fn(seed) {
    let #(a, seed) = rand_region(seed)
    let #(b, _) = rand_region(seed)
    let u = geometry.union(a, b)
    geometry.union(b, a) |> should.equal(u)
    geometry.union(u, a) |> should.equal(u)
    { geometry.area(u) >= geometry.area(a) } |> should.be_true
  })
}
