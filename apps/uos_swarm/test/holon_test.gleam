import gleam/dynamic/decode
import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/option
import gleam/string
import gleeunit/should
import prng
import uos_swarm/board
import uos_swarm/holon
import uos_swarm/raga

pub fn holarchy_validates_test() {
  holon.validate(holon.holarchy()) |> should.equal(Ok(Nil))
  holon.roots(holon.holarchy())
  |> list.map(fn(h) { h.id })
  |> should.equal(["uos"])
  // Census-derived Process holons reach as deep as L7 (federation/peer/tailnet rows, e.g. the
  // Matrix chat federation server) -- deeper than the 34 original architectural holons (L0..L3).
  holon.depth(holon.holarchy()) |> should.equal(7)
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
  // Census-derived Process holons may carry a blank sanskrit (design doc 3.2); every other
  // kind still must not.
  list.each(hs, fn(h) {
    case h.kind {
      holon.Process -> Nil
      _ -> { h.sanskrit != "" } |> should.be_true
    }
  })
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
    holon.holon("uos", "dup", "x", 0, holon.Control, option.None, [], "m"),
    ..hs
  ]
  holon.validate(dup) |> should.equal(Error("duplicate holon id"))
}

pub fn tree_and_mermaid_render_test() {
  let t = holon.to_tree(holon.holarchy())
  string.contains(t, "L0 uos") |> should.be_true
  // HOLON-LIFECYCLE fix: "planes" is back at its natural L1 (not pulled down to L0 by the
  // level-monotonic cascade any more) now that the 9 L0 census rows (IAM/vault/clock-guard/
  // constitutional) nest under the new `constitution` holon instead of under
  // `cepaf-gleam`/`uos-swarm`/`native-nifs` several hops below `control-plane`/`messaging-plane`.
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
// Base-layer rules B1..B9: all pass on the shipped 34 holons.
// ---------------------------------------------------------------------------

/// The Jujutsu holon adds one more holon to the structure plane (33 -> 34), reciprocally
/// listed in `structure-plane.parts` (B2).
pub fn holon_count_is_34_including_jujutsu_test() {
  let hs = holon.holarchy()
  // HOLON-LIFECYCLE adds one more Subsystem-kind holon ("constitution") on top of the
  // HOLARCHY-CENSUS total (34 + 10 + 113 = 157), for 158 total.
  list.length(hs) |> should.equal(34 + 11 + 113)
  let assert Ok(jj) = holon.find(hs, "jujutsu")
  jj.level |> should.equal(2)
  jj.plane |> should.equal(holon.Structure)
  jj.whole |> should.equal(option.Some("structure-plane"))
  jj.parts |> should.equal([])
  let assert Ok(structure_plane) = holon.find(hs, "structure-plane")
  list.contains(structure_plane.parts, "jujutsu") |> should.be_true
}

// ---------------------------------------------------------------------------
// HOLARCHY-CENSUS + HOLON-LIFECYCLE: 11 Subsystem holons (the original 10 plus the new
// `constitution` L0-constitutional whole) + 113 census-derived Process holons.
// ---------------------------------------------------------------------------

pub fn holarchy_carries_11_subsystems_and_113_process_holons_test() {
  let hs = holon.holarchy()
  list.length(list.filter(hs, fn(h) { h.kind == holon.Subsystem }))
  |> should.equal(11)
  list.length(list.filter(hs, fn(h) { h.kind == holon.Process }))
  |> should.equal(113)
  // Every Process holon carries a 13-hex uid and a non-empty process_class.
  list.each(hs, fn(h) {
    case h.kind {
      holon.Process -> {
        string.length(h.uid) |> should.equal(13)
        { h.process_class != "" } |> should.be_true
      }
      _ -> Nil
    }
  })
}

pub fn address_carries_plane_slug_test() {
  let assert Ok(uos) = holon.find(holon.holarchy(), "uos")
  holon.address(uos) |> should.equal("uos/holon/L0/control/uos")
}

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

// ---------------------------------------------------------------------------
// B10: census parity. Loads the daemon-census fixture (a copy of
// generated/20260907-1320-uos-daemon-process-census-c3i-indrajaal-vs-uos.json), extracts every
// row's `name`, and asserts every one matches a Process holon in `holarchy()`.
// ---------------------------------------------------------------------------

fn census_name_decoder() -> decode.Decoder(String) {
  use name <- decode.field("name", decode.string)
  decode.success(name)
}

pub fn b10_census_parity_test() {
  let assert Ok(content) =
    board.file_read("test/fixtures/20260907-1320-daemon-census.json")
  let assert Ok(names) = json.parse(content, decode.list(census_name_decoder()))
  list.length(names) |> should.equal(113)
  let missing = holon.b10_missing(holon.holarchy(), names)
  missing |> should.equal([])
  let #(rule_id, ok, detail) = holon.rule_b10(holon.holarchy(), names)
  rule_id |> should.equal("B10")
  ok |> should.be_true
  string.contains(detail, "113") |> should.be_true
}

// B13 is a documented placeholder: always passes, never claims implementation.
pub fn b13_is_a_placeholder_that_passes_test() {
  let #(id, ok, detail) = holon.rule_b13()
  id |> should.equal("B13")
  ok |> should.be_true
  string.contains(detail, "placeholder") |> should.be_true
}

// ---------------------------------------------------------------------------
// HOLON-LIFECYCLE: `LifecycleEvent`/`transition` state machine.
// ---------------------------------------------------------------------------

/// (1) Every legal transition edge: the five forward edges plus the five "Die from a
/// non-terminal state" edges.
pub fn transition_legal_edges_test() {
  holon.transition(holon.Dormant, holon.Wake)
  |> should.equal(Ok(holon.Awakening))
  holon.transition(holon.Awakening, holon.Ready)
  |> should.equal(Ok(holon.Active))
  holon.transition(holon.Active, holon.Stress)
  |> should.equal(Ok(holon.Stressed))
  holon.transition(holon.Stressed, holon.Heal)
  |> should.equal(Ok(holon.Healing))
  holon.transition(holon.Healing, holon.Recover)
  |> should.equal(Ok(holon.Active))
  holon.transition(holon.Dormant, holon.Die)
  |> should.equal(Ok(holon.Apoptotic))
  holon.transition(holon.Awakening, holon.Die)
  |> should.equal(Ok(holon.Apoptotic))
  holon.transition(holon.Active, holon.Die) |> should.equal(Ok(holon.Apoptotic))
  holon.transition(holon.Stressed, holon.Die)
  |> should.equal(Ok(holon.Apoptotic))
  holon.transition(holon.Healing, holon.Die)
  |> should.equal(Ok(holon.Apoptotic))
}

/// (2) At least four illegal edges return `Error`.
pub fn transition_illegal_edges_are_errors_test() {
  case holon.transition(holon.Dormant, holon.Ready) {
    Error(_) -> Nil
    Ok(_) -> should.fail()
  }
  case holon.transition(holon.Dormant, holon.Stress) {
    Error(_) -> Nil
    Ok(_) -> should.fail()
  }
  case holon.transition(holon.Active, holon.Wake) {
    Error(_) -> Nil
    Ok(_) -> should.fail()
  }
  case holon.transition(holon.Healing, holon.Stress) {
    Error(_) -> Nil
    Ok(_) -> should.fail()
  }
  case holon.transition(holon.Stressed, holon.Recover) {
    Error(_) -> Nil
    Ok(_) -> should.fail()
  }
}

/// (3) `Apoptotic` is terminal: every one of the 6 events from it is an `Error`.
pub fn transition_apoptotic_is_terminal_for_every_event_test() {
  list.each(
    [
      holon.Wake,
      holon.Ready,
      holon.Stress,
      holon.Heal,
      holon.Recover,
      holon.Die,
    ],
    fn(event) {
      case holon.transition(holon.Apoptotic, event) {
        Error(_) -> Nil
        Ok(_) -> should.fail()
      }
    },
  )
}

// ---------------------------------------------------------------------------
// HOLON-LIFECYCLE: `lifecycle_from_status` and `with_process`-derived lifecycle.
// ---------------------------------------------------------------------------

/// (4) `lifecycle_from_status` for all five named census statuses and one unknown status.
pub fn lifecycle_from_status_maps_all_named_statuses_test() {
  holon.lifecycle_from_status("running") |> should.equal(holon.Active)
  holon.lifecycle_from_status("stopped") |> should.equal(holon.Dormant)
  holon.lifecycle_from_status("absent") |> should.equal(holon.Dormant)
  holon.lifecycle_from_status("failed") |> should.equal(holon.Stressed)
  holon.lifecycle_from_status("superseded") |> should.equal(holon.Apoptotic)
  // Unknown/blank statuses (the census itself never uses "running"/"stopped"/"failed" -- see
  // (5) below -- and instead uses "integrated"/"imported-not-wired"/"barred"/"") default safely
  // to Dormant, same as an unrecognized status would.
  holon.lifecycle_from_status("not-a-real-status")
  |> should.equal(holon.Dormant)
  holon.lifecycle_from_status("") |> should.equal(holon.Dormant)
}

/// (5) A holon built with `with_process(_, _, "running")` is Active (the daemon census fixture
/// itself never uses the literal string "running" -- its vocabulary is
/// integrated/imported-not-wired/absent/superseded/barred -- so this exercises the mapping
/// directly via `with_process` rather than searching for a census row that cannot exist); and a
/// real census-derived holon whose status is "superseded" is Apoptotic.
pub fn census_holon_lifecycle_running_is_active_and_superseded_is_apoptotic_test() {
  let running =
    holon.holon("x", "x", "x", 4, holon.Runtime, option.None, [], "m")
    |> holon.with_process("systemd", "running")
  running.lifecycle |> should.equal(holon.Active)

  let assert Ok(superseded) =
    holon.find(holon.holarchy(), "c3i-sa-plan-cortex-service")
  superseded.status |> should.equal("superseded")
  superseded.lifecycle |> should.equal(holon.Apoptotic)
}

// ---------------------------------------------------------------------------
// HOLON-LIFECYCLE: the level-cascade fix (`constitution`, restored subsystem/plane levels).
// ---------------------------------------------------------------------------

/// (6) `constitution` exists at L0 with whole "uos", and every L0 `Process` holon names
/// `constitution` as its whole.
pub fn constitution_holds_every_l0_process_holon_test() {
  let hs = holon.holarchy()
  let assert Ok(constitution) = holon.find(hs, "constitution")
  constitution.level |> should.equal(0)
  constitution.whole |> should.equal(option.Some("uos"))
  constitution.kind |> should.equal(holon.Subsystem)
  list.each(hs, fn(h) {
    case h.kind == holon.Process && h.level == 0 {
      True -> h.whole |> should.equal(option.Some("constitution"))
      False -> Nil
    }
  })
}

/// (7) All seven plane holons and `planes` itself are at L1 (the level-monotonic cascade no
/// longer pulls them down to L0 now that the L0 census rows sit under `constitution`).
pub fn all_planes_and_planes_grouping_are_at_l1_test() {
  let hs = holon.holarchy()
  list.each(
    [
      "control-plane", "structure-plane", "runtime-plane", "data-plane",
      "messaging-plane", "intelligence-plane", "language-plane", "planes",
    ],
    fn(id) {
      let assert Ok(h) = holon.find(hs, id)
      h.level |> should.equal(1)
    },
  )
}

/// (8) No `Subsystem`-kind holon sits at L0 any more (all 11, including `constitution` itself
/// once it is excluded as the new L0-constitutional whole -- `constitution` is intentionally L0,
/// every OTHER Subsystem is not).
pub fn no_non_constitution_subsystem_holon_is_at_l0_test() {
  let hs = holon.holarchy()
  list.each(hs, fn(h) {
    case h.kind == holon.Subsystem && h.id != "constitution" {
      True -> { h.level != 0 } |> should.be_true
      False -> Nil
    }
  })
}

/// (9) Total holon count is 158, and the level distribution matches the design's post-fix
/// count exactly: L0 12, L1 24, L2 24, L3 7, L4 58, L5 26, L6 6, L7 1.
pub fn total_count_and_level_distribution_test() {
  let hs = holon.holarchy()
  list.length(hs) |> should.equal(158)
  let count_at = fn(level: Int) {
    list.length(list.filter(hs, fn(h) { h.level == level }))
  }
  let dist = [
    #(0, count_at(0)),
    #(1, count_at(1)),
    #(2, count_at(2)),
    #(3, count_at(3)),
    #(4, count_at(4)),
    #(5, count_at(5)),
    #(6, count_at(6)),
    #(7, count_at(7)),
  ]
  io.println(
    "level distribution: "
    <> string.join(
      list.map(dist, fn(d) {
        "L" <> int.to_string(d.0) <> "=" <> int.to_string(d.1)
      }),
      " ",
    ),
  )
  dist
  |> should.equal([
    #(0, 12),
    #(1, 24),
    #(2, 24),
    #(3, 7),
    #(4, 58),
    #(5, 26),
    #(6, 6),
    #(7, 1),
  ])
}
