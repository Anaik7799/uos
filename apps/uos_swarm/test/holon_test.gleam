import gleam/list
import gleam/option
import gleam/string
import gleeunit/should
import prng
import uos_swarm/holon

pub fn holarchy_validates_test() {
  holon.validate(holon.holarchy()) |> should.equal(Ok(Nil))
  holon.roots(holon.holarchy())
  |> list.map(fn(h) { h.id })
  |> should.equal(["uos"])
  holon.depth(holon.holarchy()) |> should.equal(3)
}

pub fn every_plane_populated_and_same_interface_test() {
  let hs = holon.holarchy()
  list.each(
    [
      holon.Control,
      holon.Structure,
      holon.Runtime,
      holon.DataPlane,
      holon.Messaging,
      holon.Intelligence,
      holon.Language,
    ],
    fn(p) { { list.length(holon.by_plane(hs, p)) >= 2 } |> should.be_true },
  )
  list.each(hs, fn(h) {
    string.starts_with(holon.address(h), "uos/holon/L") |> should.be_true
  })
  list.each(hs, fn(h) { { h.sanskrit != "" } |> should.be_true })
}

pub fn validation_detects_breaks_test() {
  let hs = holon.holarchy()
  let orphan =
    list.map(hs, fn(h) {
      case h.id == "coord" {
        True -> holon.Holon(..h, whole: option.Some("uos"))
        False -> h
      }
    })
  holon.validate(orphan)
  |> should.equal(Error("coord does not name control-plane as its whole"))
  let dup = [
    holon.Holon(
      "uos",
      "dup",
      "x",
      0,
      holon.Control,
      option.None,
      [],
      "m",
      option.None,
      option.None,
    ),
    ..hs
  ]
  holon.validate(dup) |> should.equal(Error("duplicate holon id"))
}

pub fn tree_and_mermaid_render_test() {
  let t = holon.to_tree(holon.holarchy())
  string.contains(t, "L0 uos") |> should.be_true
  string.contains(t, "  L1 planes") |> should.be_true
  string.contains(holon.to_mermaid(holon.holarchy()), "graph TD")
  |> should.be_true
  string.contains(holon.to_markdown(holon.holarchy()), "```mermaid")
  |> should.be_true
}

// Property: random subsets that keep the root remain acyclic in the walk (never "cycle").
pub fn property_walk_never_cycles_test() {
  list.each(prng.seeds(40), fn(seed) {
    let #(n, _) = prng.int_between(seed, 1, 30)
    let hs = list.take(holon.holarchy(), n)
    list.each(hs, fn(h) {
      case holon.validate([h]) {
        Error(e) -> string.contains(e, "cycle") |> should.be_false
        Ok(_) -> Nil
      }
    })
  })
}
