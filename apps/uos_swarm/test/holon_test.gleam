import gleam/list
import gleam/option
import gleam/string
import gleeunit/should
import prng
import uos_swarm/holon
import uos_swarm/raga

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

// ---------------------------------------------------------------------------
// swadharma / svara: every holon's duty and note, derived from its plane and level.
// ---------------------------------------------------------------------------

pub fn swara_of_plane_matches_holon_plane_order_test() {
  holon.swara_of_plane(holon.Control) |> should.equal(raga.Sa)
  holon.swara_of_plane(holon.Structure) |> should.equal(raga.Re)
  holon.swara_of_plane(holon.Runtime) |> should.equal(raga.Ga)
  holon.swara_of_plane(holon.DataPlane) |> should.equal(raga.Ma)
  holon.swara_of_plane(holon.Messaging) |> should.equal(raga.Pa)
  holon.swara_of_plane(holon.Intelligence) |> should.equal(raga.Dha)
  holon.swara_of_plane(holon.Language) |> should.equal(raga.Ni)
}

pub fn swara_of_matches_swara_of_plane_test() {
  list.each(holon.holarchy(), fn(h) {
    holon.swara_of(h) |> should.equal(holon.swara_of_plane(h.plane))
  })
}

pub fn dharma_of_mentions_id_plane_and_svara_test() {
  list.each(holon.holarchy(), fn(h) {
    let d = holon.dharma_of(h)
    string.contains(d, h.id) |> should.be_true
    string.contains(d, holon.plane_label(h.plane)) |> should.be_true
    string.contains(d, raga.swara_label(holon.swara_of(h))) |> should.be_true
  })
}

pub fn to_markdown_carries_a_svara_column_test() {
  let md = holon.to_markdown(holon.holarchy())
  string.contains(md, "svara") |> should.be_true
  string.contains(md, raga.swara_label(raga.Sa)) |> should.be_true
}

// ---------------------------------------------------------------------------
// Base-layer rules B1..B9: all pass on the shipped 33 holons.
// ---------------------------------------------------------------------------

pub fn base_rules_all_pass_on_shipped_holarchy_test() {
  let rules = holon.base_rules(holon.holarchy())
  list.length(rules) |> should.equal(9)
  list.each(rules, fn(r) {
    case r.1 {
      True -> Nil
      False -> should.fail()
    }
  })
  let ids = list.map(rules, fn(r) { r.0 })
  ids
  |> should.equal(["B1", "B2", "B3", "B4", "B5", "B6", "B7", "B8", "B9"])
}

pub fn base_rules_markdown_renders_all_nine_test() {
  let md = holon.base_rules_markdown()
  list.each(["B1", "B2", "B3", "B4", "B5", "B6", "B7", "B8", "B9"], fn(id) {
    string.contains(md, id) |> should.be_true
  })
  string.contains(md, "PASS") |> should.be_true
}

fn rule(rules: List(#(String, Bool, String)), id: String) -> #(Bool, String) {
  let assert Ok(r) = list.find(rules, fn(r) { r.0 == id })
  #(r.1, r.2)
}

// B2 (reciprocal membership) must catch a holon whose whole no longer lists it as a part —
// the direction plain `validate` did not check (Codex found this missing).
pub fn b2_catches_broken_reciprocal_membership_test() {
  // "control-plane" still names "planes" as its own whole, but we strip control-plane out of
  // "planes".parts — breaking the reciprocal link from the whole's side only.
  let broken =
    list.map(holon.holarchy(), fn(h) {
      case h.id == "planes" {
        True ->
          holon.Holon(
            ..h,
            parts: list.filter(h.parts, fn(p) { p != "control-plane" }),
          )
        False -> h
      }
    })
  let #(ok, detail) = rule(holon.base_rules(broken), "B2")
  ok |> should.be_false
  string.contains(detail, "control-plane") |> should.be_true
}

// B9 (unique, lower-kebab ids) must catch an uppercase / non-kebab id.
pub fn b9_catches_non_kebab_id_test() {
  let hs =
    list.map(holon.holarchy(), fn(h) {
      case h.id == "coord" {
        True -> holon.Holon(..h, id: "Coord_Bad")
        False -> h
      }
    })
  let #(ok, _) = rule(holon.base_rules(hs), "B9")
  ok |> should.be_false
}

// B5 (non-empty Sanskrit name) must catch a blanked-out name.
pub fn b5_catches_missing_sanskrit_name_test() {
  let hs =
    list.map(holon.holarchy(), fn(h) {
      case h.id == "acl" {
        True -> holon.Holon(..h, sanskrit: "")
        False -> h
      }
    })
  let #(ok, detail) = rule(holon.base_rules(hs), "B5")
  ok |> should.be_false
  string.contains(detail, "acl") |> should.be_true
}
