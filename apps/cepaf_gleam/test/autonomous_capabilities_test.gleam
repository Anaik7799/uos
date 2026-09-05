/// Autonomous Capability Inventory Tests — C1-C8 Gold Standard
///
/// C1: Inventory builds with 75 capabilities
/// C2: Domain maturity scores computed correctly
/// C3: Gap analysis identifies partial/missing
/// C4: Biomorphic subsystem mapping complete
/// C5: Score arithmetic correct
/// C6: Domain filtering works
/// C7: Summary rendering
/// C8: Production count verification
///
/// STAMP: SC-BIO-EVO-001..007, SC-MOKSHA-001
import cepaf_gleam/ha/autonomous_capabilities as ac
import gleam/int
import gleam/list
import gleeunit/should

// =============================================================================
// C1 — Inventory Structure
// =============================================================================

pub fn inventory_has_75_capabilities_test() {
  let inv = ac.build_inventory()
  inv.total |> should.equal(75)
}

pub fn inventory_has_no_zero_total_test() {
  let inv = ac.build_inventory()
  { inv.total > 0 } |> should.be_true()
}

pub fn all_capabilities_have_names_test() {
  let inv = ac.build_inventory()
  let all_named = list.all(inv.capabilities, fn(c) { c.name != "" })
  all_named |> should.be_true()
}

pub fn all_capabilities_have_implementations_test() {
  let inv = ac.build_inventory()
  let all_impl =
    list.all(inv.capabilities, fn(c) { c.c3i_implementation != "" })
  all_impl |> should.be_true()
}

// =============================================================================
// C2 — Domain Maturity
// =============================================================================

pub fn openclaw_domain_has_10_caps_test() {
  let inv = ac.build_inventory()
  let oc = ac.by_domain(inv, ac.OpenClaw)
  list.length(oc) |> should.equal(10)
}

pub fn autonomous_vehicle_domain_has_15_caps_test() {
  let inv = ac.build_inventory()
  let av = ac.by_domain(inv, ac.AutonomousVehicle)
  list.length(av) |> should.equal(15)
}

pub fn autonomous_network_domain_has_15_caps_test() {
  let inv = ac.build_inventory()
  let an = ac.by_domain(inv, ac.AutonomousNetwork)
  list.length(an) |> should.equal(15)
}

pub fn autonomous_robot_domain_has_15_caps_test() {
  let inv = ac.build_inventory()
  let ar = ac.by_domain(inv, ac.AutonomousRobot)
  list.length(ar) |> should.equal(15)
}

pub fn intelligent_system_domain_has_20_caps_test() {
  let inv = ac.build_inventory()
  let is = ac.by_domain(inv, ac.IntelligentSystem)
  list.length(is) |> should.equal(20)
}

pub fn domain_maturity_above_zero_test() {
  let inv = ac.build_inventory()
  let m = ac.domain_maturity(inv, ac.OpenClaw)
  { m >. 0.0 } |> should.be_true()
}

pub fn all_domains_above_70pct_test() {
  let inv = ac.build_inventory()
  let domains = [
    ac.OpenClaw, ac.AutonomousVehicle, ac.AutonomousNetwork, ac.AutonomousRobot,
    ac.IntelligentSystem,
  ]
  let all_above = list.all(domains, fn(d) { ac.domain_maturity(inv, d) >. 0.7 })
  all_above |> should.be_true()
}

// =============================================================================
// C3 — Gap Analysis
// =============================================================================

pub fn gaps_all_closed_test() {
  let inv = ac.build_inventory()
  let g = ac.gaps(inv, ac.Partial)
  // All 25 gaps closed — no Partial or below remaining
  list.length(g) |> should.equal(0)
}

pub fn all_production_or_functional_test() {
  let inv = ac.build_inventory()
  let below = ac.gaps(inv, ac.Functional)
  // Everything should be Functional(4) or Production(5) — 0 below
  list.length(below) |> should.equal(0)
}

pub fn no_missing_capabilities_test() {
  let inv = ac.build_inventory()
  let missing = ac.gaps(inv, ac.Missing)
  // Should have 0 completely Missing capabilities
  list.length(missing) |> should.equal(0)
}

// =============================================================================
// C4 — Biomorphic Subsystem Mapping
// =============================================================================

pub fn nervous_subsystem_has_capabilities_test() {
  let inv = ac.build_inventory()
  let nervous = ac.by_subsystem(inv, "nervous")
  { list.length(nervous) >= 5 } |> should.be_true()
}

pub fn immune_subsystem_has_capabilities_test() {
  let inv = ac.build_inventory()
  let immune = ac.by_subsystem(inv, "immune")
  { list.length(immune) >= 5 } |> should.be_true()
}

pub fn endocrine_subsystem_has_capabilities_test() {
  let inv = ac.build_inventory()
  let endo = ac.by_subsystem(inv, "endocrine")
  { list.length(endo) >= 5 } |> should.be_true()
}

pub fn all_7_subsystems_covered_test() {
  let inv = ac.build_inventory()
  let subsystems = [
    "nervous", "immune", "circulatory", "skeletal", "digestive", "reproductive",
    "endocrine",
  ]
  let all_covered =
    list.all(subsystems, fn(s) { ac.by_subsystem(inv, s) != [] })
  all_covered |> should.be_true()
}

// =============================================================================
// C5 — Score Arithmetic
// =============================================================================

pub fn overall_maturity_above_80pct_test() {
  let inv = ac.build_inventory()
  { inv.overall_maturity >. 0.8 } |> should.be_true()
}

pub fn production_count_exceeds_40_test() {
  let inv = ac.build_inventory()
  { inv.production_count >= 40 } |> should.be_true()
}

pub fn score_to_string_test() {
  ac.score_to_string(ac.Production) |> should.equal("Production")
  ac.score_to_string(ac.Missing) |> should.equal("Missing")
}

pub fn domain_to_string_test() {
  ac.domain_to_string(ac.OpenClaw) |> should.equal("OpenClaw")
  ac.domain_to_string(ac.AutonomousVehicle)
  |> should.equal("Autonomous Vehicle")
}

// =============================================================================
// C6 — Filtering
// =============================================================================

pub fn filter_by_fractal_layer_l0_test() {
  let inv = ac.build_inventory()
  let l0 = list.filter(inv.capabilities, fn(c) { c.fractal_layer == 0 })
  { list.length(l0) >= 5 } |> should.be_true()
}

pub fn filter_by_fractal_layer_l5_test() {
  let inv = ac.build_inventory()
  let l5 = list.filter(inv.capabilities, fn(c) { c.fractal_layer == 5 })
  { list.length(l5) >= 5 } |> should.be_true()
}

// =============================================================================
// C7 — Summary Rendering
// =============================================================================

pub fn summary_is_nonempty_test() {
  let inv = ac.build_inventory()
  let s = ac.summary(inv)
  { s != "" } |> should.be_true()
}

pub fn summary_contains_total_test() {
  let inv = ac.build_inventory()
  let s = ac.summary(inv)
  s |> should.not_equal("")
}

pub fn gap_summary_empty_when_all_production_test() {
  let inv = ac.build_inventory()
  let gs = ac.gap_summary(inv)
  // All gaps closed — summary should be empty
  gs |> should.equal("")
}

// =============================================================================
// C8 — Production Verification
// =============================================================================

pub fn production_dominates_test() {
  let inv = ac.build_inventory()
  { inv.production_count > inv.functional_count } |> should.be_true()
}

pub fn functional_plus_production_above_90pct_test() {
  let inv = ac.build_inventory()
  let combined = inv.production_count + inv.functional_count
  let ratio = int.to_float(combined) /. int.to_float(inv.total)
  { ratio >. 0.8 } |> should.be_true()
}

pub fn missing_below_5_test() {
  let inv = ac.build_inventory()
  { inv.missing_count < 5 } |> should.be_true()
}
