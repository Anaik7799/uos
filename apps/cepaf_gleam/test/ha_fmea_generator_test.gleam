/// FMEA Generator tests — automated Failure Mode and Effects Analysis
/// SC-SIL4-001, SC-HA-001, SC-FUNC-002
/// Layer: L4_SYSTEM
import cepaf_gleam/ha/fmea_generator.{
  FmeaEntry, P0Critical, P1High, P2Medium, P3Low, classify_rpn, critical_entries,
  entries_for_layer, entry_to_json, generate_system_fmea, highest_risk,
  priority_distribution, summary, to_json, total_rpn,
}
import gleam/list
import gleam/string
import gleeunit/should

// ---------------------------------------------------------------------------
// Catalog shape
// ---------------------------------------------------------------------------

pub fn generate_system_fmea_returns_20_entries_test() {
  generate_system_fmea()
  |> list.length()
  |> should.equal(20)
}

pub fn all_entries_have_positive_rpn_test() {
  generate_system_fmea()
  |> list.all(fn(e) { e.rpn > 0 })
  |> should.be_true()
}

pub fn rpn_equals_s_times_o_times_d_test() {
  generate_system_fmea()
  |> list.all(fn(e) { e.rpn == e.severity * e.occurrence * e.detection })
  |> should.be_true()
}

pub fn all_entries_have_non_empty_component_test() {
  generate_system_fmea()
  |> list.all(fn(e) { string.length(e.component) > 0 })
  |> should.be_true()
}

pub fn all_entries_have_non_empty_mitigation_test() {
  generate_system_fmea()
  |> list.all(fn(e) { string.length(e.mitigation) > 0 })
  |> should.be_true()
}

pub fn severity_is_in_range_1_to_10_test() {
  generate_system_fmea()
  |> list.all(fn(e) { e.severity >= 1 && e.severity <= 10 })
  |> should.be_true()
}

pub fn occurrence_is_in_range_1_to_10_test() {
  generate_system_fmea()
  |> list.all(fn(e) { e.occurrence >= 1 && e.occurrence <= 10 })
  |> should.be_true()
}

pub fn detection_is_in_range_1_to_10_test() {
  generate_system_fmea()
  |> list.all(fn(e) { e.detection >= 1 && e.detection <= 10 })
  |> should.be_true()
}

// ---------------------------------------------------------------------------
// Layer coverage — at least one entry per key fractal layer
// ---------------------------------------------------------------------------

pub fn has_l0_constitutional_entries_test() {
  generate_system_fmea()
  |> entries_for_layer("L0_CONSTITUTIONAL")
  |> list.length()
  |> fn(n) { n > 0 }
  |> should.be_true()
}

pub fn has_l4_system_entries_test() {
  generate_system_fmea()
  |> entries_for_layer("L4_SYSTEM")
  |> list.length()
  |> fn(n) { n > 0 }
  |> should.be_true()
}

pub fn has_l6_ecosystem_entries_test() {
  generate_system_fmea()
  |> entries_for_layer("L6_ECOSYSTEM")
  |> list.length()
  |> fn(n) { n > 0 }
  |> should.be_true()
}

// ---------------------------------------------------------------------------
// critical_entries filter
// ---------------------------------------------------------------------------

pub fn critical_entries_threshold_200_returns_subset_test() {
  let all = generate_system_fmea()
  let critical = critical_entries(all, 200)
  let is_subset = list.length(critical) <= list.length(all)
  is_subset |> should.be_true()
}

pub fn critical_entries_all_have_rpn_gte_threshold_test() {
  let critical = critical_entries(generate_system_fmea(), 100)
  critical
  |> list.all(fn(e) { e.rpn >= 100 })
  |> should.be_true()
}

pub fn critical_entries_threshold_0_returns_all_test() {
  let all = generate_system_fmea()
  critical_entries(all, 0)
  |> list.length()
  |> should.equal(list.length(all))
}

pub fn critical_entries_threshold_1000_returns_none_test() {
  // Max possible RPN = 10×10×10 = 1000, but our entries are < 1000
  generate_system_fmea()
  |> critical_entries(1000)
  |> list.length()
  |> should.equal(0)
}

// ---------------------------------------------------------------------------
// classify_rpn
// ---------------------------------------------------------------------------

pub fn classify_rpn_200_is_p0_test() {
  classify_rpn(200) |> should.equal(P0Critical)
}

pub fn classify_rpn_100_is_p1_test() {
  classify_rpn(100) |> should.equal(P1High)
}

pub fn classify_rpn_50_is_p2_test() {
  classify_rpn(50) |> should.equal(P2Medium)
}

pub fn classify_rpn_49_is_p3_test() {
  classify_rpn(49) |> should.equal(P3Low)
}

pub fn classify_rpn_0_is_p3_test() {
  classify_rpn(0) |> should.equal(P3Low)
}

// ---------------------------------------------------------------------------
// total_rpn
// ---------------------------------------------------------------------------

pub fn total_rpn_is_positive_test() {
  generate_system_fmea()
  |> total_rpn()
  |> fn(t) { t > 0 }
  |> should.be_true()
}

pub fn total_rpn_empty_list_is_zero_test() {
  total_rpn([]) |> should.equal(0)
}

// ---------------------------------------------------------------------------
// highest_risk
// ---------------------------------------------------------------------------

pub fn highest_risk_returns_ok_on_non_empty_test() {
  let result = generate_system_fmea() |> highest_risk()
  case result {
    Ok(_) -> True
    Error(_) -> False
  }
  |> should.be_true()
}

pub fn highest_risk_returns_error_on_empty_test() {
  highest_risk([]) |> should.equal(Error(Nil))
}

pub fn highest_risk_entry_has_max_rpn_test() {
  let entries = generate_system_fmea()
  let max_rpn =
    list.fold(entries, 0, fn(acc, e) {
      case e.rpn > acc {
        True -> e.rpn
        False -> acc
      }
    })
  case highest_risk(entries) {
    Ok(e) -> e.rpn |> should.equal(max_rpn)
    Error(_) -> should.fail()
  }
}

// ---------------------------------------------------------------------------
// priority_distribution
// ---------------------------------------------------------------------------

pub fn priority_distribution_sums_to_total_test() {
  let entries = generate_system_fmea()
  let total = list.length(entries)
  let #(p0, p1, p2, p3) = priority_distribution(entries)
  p0 + p1 + p2 + p3 |> should.equal(total)
}

// ---------------------------------------------------------------------------
// JSON serialisation
// ---------------------------------------------------------------------------

pub fn entry_to_json_contains_component_test() {
  let e =
    FmeaEntry(
      component: "test-comp",
      failure_mode: "crash",
      severity: 5,
      occurrence: 3,
      detection: 4,
      rpn: 60,
      mitigation: "restart",
      layer: "L4_SYSTEM",
    )
  entry_to_json(e)
  |> string.contains("test-comp")
  |> should.be_true()
}

pub fn entry_to_json_contains_rpn_test() {
  let e =
    FmeaEntry(
      component: "c",
      failure_mode: "f",
      severity: 5,
      occurrence: 3,
      detection: 4,
      rpn: 60,
      mitigation: "m",
      layer: "L4_SYSTEM",
    )
  entry_to_json(e)
  |> string.contains("60")
  |> should.be_true()
}

pub fn to_json_starts_with_bracket_test() {
  let json = generate_system_fmea() |> to_json()
  string.starts_with(json, "[") |> should.be_true()
}

pub fn to_json_ends_with_bracket_test() {
  let json = generate_system_fmea() |> to_json()
  string.ends_with(json, "]") |> should.be_true()
}

pub fn to_json_empty_list_is_empty_array_test() {
  to_json([]) |> should.equal("[]")
}

// ---------------------------------------------------------------------------
// summary
// ---------------------------------------------------------------------------

pub fn summary_contains_fmea_test() {
  let s = generate_system_fmea() |> summary()
  string.contains(s, "FMEA") |> should.be_true()
}

pub fn summary_contains_20_test() {
  let s = generate_system_fmea() |> summary()
  string.contains(s, "20") |> should.be_true()
}
