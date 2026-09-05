/// IEC 61508 SIL-4 evidence package tests
/// SC-SIL4-001, SC-PRIME-001, SC-VER-001, SC-FUNC-002
/// Layer: L0_CONSTITUTIONAL
import cepaf_gleam/ha/iec61508.{
  type EvidenceItem, Complete, EvidenceItem, FormalVerification, Inspection,
  IntegrationTesting, Missing, NotApplicable, Partial, RequirementsSpec, SIL1,
  SIL2, SIL3, SIL4, add_evidence, c3i_evidence_package, count_by_status,
  coverage_percent, evidence_by_category, evidence_for_sil, init_safety_case,
  is_certifiable, item_summary, missing_evidence, partial_evidence, pfd_for_sil,
  sil_to_string, summary,
}
import gleam/list
import gleam/string
import gleeunit/should

// ---------------------------------------------------------------------------
// 1. init_safety_case — constructor and SIL defaults
// ---------------------------------------------------------------------------

pub fn init_creates_empty_evidence_list_test() {
  let c = init_safety_case("TestSys", SIL4)
  list.length(c.evidence) |> should.equal(0)
}

pub fn init_sets_system_name_test() {
  let c = init_safety_case("MySafetySystem", SIL3)
  c.system_name |> should.equal("MySafetySystem")
}

pub fn init_sets_target_sil_test() {
  let c = init_safety_case("Sys", SIL4)
  c.target_sil |> should.equal(SIL4)
}

pub fn init_sets_pfd_target_for_sil4_test() {
  let c = init_safety_case("Sys", SIL4)
  c.pfd_target |> should.equal(1.0e-4)
}

pub fn init_sets_hft_2_for_sil4_test() {
  let c = init_safety_case("Sys", SIL4)
  c.hft |> should.equal(2)
}

pub fn init_sets_sff_99_for_sil4_test() {
  let c = init_safety_case("Sys", SIL4)
  c.sff_percent |> should.equal(99.0)
}

// ---------------------------------------------------------------------------
// 2. pfd_for_sil — IEC 61508 PFD table
// ---------------------------------------------------------------------------

pub fn pfd_sil1_is_1e_minus_1_test() {
  pfd_for_sil(SIL1) |> should.equal(1.0e-1)
}

pub fn pfd_sil2_is_1e_minus_2_test() {
  pfd_for_sil(SIL2) |> should.equal(1.0e-2)
}

pub fn pfd_sil3_is_1e_minus_3_test() {
  pfd_for_sil(SIL3) |> should.equal(1.0e-3)
}

pub fn pfd_sil4_is_1e_minus_4_test() {
  pfd_for_sil(SIL4) |> should.equal(1.0e-4)
}

pub fn pfd_decreases_with_sil_level_test() {
  let sil1 = pfd_for_sil(SIL1)
  let sil2 = pfd_for_sil(SIL2)
  let sil3 = pfd_for_sil(SIL3)
  let sil4 = pfd_for_sil(SIL4)
  { sil1 >. sil2 && sil2 >. sil3 && sil3 >. sil4 }
  |> should.be_true()
}

// ---------------------------------------------------------------------------
// 3. sil_to_string
// ---------------------------------------------------------------------------

pub fn sil_to_string_sil4_test() {
  sil_to_string(SIL4) |> should.equal("SIL-4")
}

pub fn sil_to_string_sil1_test() {
  sil_to_string(SIL1) |> should.equal("SIL-1")
}

pub fn sil_to_string_sil2_test() {
  sil_to_string(SIL2) |> should.equal("SIL-2")
}

pub fn sil_to_string_sil3_test() {
  sil_to_string(SIL3) |> should.equal("SIL-3")
}

// ---------------------------------------------------------------------------
// 4. add_evidence
// ---------------------------------------------------------------------------

fn make_item(id: String, status: iec61508.EvidenceStatus) -> EvidenceItem {
  EvidenceItem(
    id: id,
    title: "Test item " <> id,
    category: RequirementsSpec,
    sil_level: SIL4,
    status: status,
    artifact_path: "path/" <> id,
    description: "Evidence for " <> id,
    verification_method: Inspection,
  )
}

pub fn add_evidence_appends_item_test() {
  let c =
    init_safety_case("Sys", SIL4)
    |> add_evidence(make_item("EV-001", Complete))
  list.length(c.evidence) |> should.equal(1)
}

pub fn add_evidence_preserves_order_test() {
  let c =
    init_safety_case("Sys", SIL4)
    |> add_evidence(make_item("EV-001", Complete))
    |> add_evidence(make_item("EV-002", Missing))
    |> add_evidence(make_item("EV-003", Partial))
  let ids = list.map(c.evidence, fn(e) { e.id })
  ids |> should.equal(["EV-001", "EV-002", "EV-003"])
}

// ---------------------------------------------------------------------------
// 5. coverage_percent
// ---------------------------------------------------------------------------

pub fn coverage_empty_evidence_returns_0_test() {
  init_safety_case("Sys", SIL4)
  |> coverage_percent()
  |> should.equal(0.0)
}

pub fn coverage_all_complete_returns_100_test() {
  init_safety_case("Sys", SIL4)
  |> add_evidence(make_item("EV-001", Complete))
  |> add_evidence(make_item("EV-002", Complete))
  |> coverage_percent()
  |> should.equal(100.0)
}

pub fn coverage_half_complete_returns_50_test() {
  init_safety_case("Sys", SIL4)
  |> add_evidence(make_item("EV-001", Complete))
  |> add_evidence(make_item("EV-002", Missing))
  |> coverage_percent()
  |> should.equal(50.0)
}

pub fn coverage_none_complete_returns_0_test() {
  init_safety_case("Sys", SIL4)
  |> add_evidence(make_item("EV-001", Missing))
  |> add_evidence(make_item("EV-002", Partial))
  |> coverage_percent()
  |> should.equal(0.0)
}

// ---------------------------------------------------------------------------
// 6. missing_evidence / partial_evidence
// ---------------------------------------------------------------------------

pub fn missing_evidence_returns_only_missing_test() {
  let c =
    init_safety_case("Sys", SIL4)
    |> add_evidence(make_item("EV-001", Missing))
    |> add_evidence(make_item("EV-002", Complete))
    |> add_evidence(make_item("EV-003", Missing))
  missing_evidence(c) |> list.length() |> should.equal(2)
}

pub fn partial_evidence_returns_only_partial_test() {
  let c =
    init_safety_case("Sys", SIL4)
    |> add_evidence(make_item("EV-001", Partial))
    |> add_evidence(make_item("EV-002", Complete))
  partial_evidence(c) |> list.length() |> should.equal(1)
}

// ---------------------------------------------------------------------------
// 7. is_certifiable
// ---------------------------------------------------------------------------

pub fn not_certifiable_when_empty_test() {
  init_safety_case("Sys", SIL4)
  |> is_certifiable()
  |> should.be_false()
}

pub fn not_certifiable_when_any_missing_test() {
  init_safety_case("Sys", SIL4)
  |> add_evidence(make_item("EV-001", Complete))
  |> add_evidence(make_item("EV-002", Missing))
  |> is_certifiable()
  |> should.be_false()
}

pub fn not_certifiable_when_any_partial_test() {
  init_safety_case("Sys", SIL4)
  |> add_evidence(make_item("EV-001", Complete))
  |> add_evidence(make_item("EV-002", Partial))
  |> is_certifiable()
  |> should.be_false()
}

pub fn certifiable_when_all_complete_test() {
  init_safety_case("Sys", SIL4)
  |> add_evidence(make_item("EV-001", Complete))
  |> add_evidence(make_item("EV-002", Complete))
  |> is_certifiable()
  |> should.be_true()
}

pub fn not_applicable_items_ignored_for_certifiability_test() {
  init_safety_case("Sys", SIL4)
  |> add_evidence(make_item("EV-001", Complete))
  |> add_evidence(
    EvidenceItem(..make_item("EV-002", NotApplicable), status: NotApplicable),
  )
  |> is_certifiable()
  |> should.be_true()
}

// ---------------------------------------------------------------------------
// 8. evidence_by_category
// ---------------------------------------------------------------------------

pub fn evidence_by_category_filters_correctly_test() {
  let fv_item =
    EvidenceItem(..make_item("EV-010", Complete), category: FormalVerification)
  let c =
    init_safety_case("Sys", SIL4)
    |> add_evidence(make_item("EV-001", Complete))
    |> add_evidence(fv_item)
  evidence_by_category(c, FormalVerification)
  |> list.length()
  |> should.equal(1)
}

// ---------------------------------------------------------------------------
// 9. count_by_status
// ---------------------------------------------------------------------------

pub fn count_by_status_complete_test() {
  let c =
    init_safety_case("Sys", SIL4)
    |> add_evidence(make_item("EV-001", Complete))
    |> add_evidence(make_item("EV-002", Complete))
    |> add_evidence(make_item("EV-003", Missing))
  count_by_status(c, Complete) |> should.equal(2)
  count_by_status(c, Missing) |> should.equal(1)
}

// ---------------------------------------------------------------------------
// 10. c3i_evidence_package — pre-populated package integrity
// ---------------------------------------------------------------------------

pub fn c3i_package_has_15_evidence_items_test() {
  let c = c3i_evidence_package()
  list.length(c.evidence) |> should.equal(15)
}

pub fn c3i_package_targets_sil4_test() {
  let c = c3i_evidence_package()
  c.target_sil |> should.equal(SIL4)
}

pub fn c3i_package_system_name_set_test() {
  let c = c3i_evidence_package()
  { string.length(c.system_name) > 0 } |> should.be_true()
}

pub fn c3i_package_all_items_have_non_empty_id_test() {
  let c = c3i_evidence_package()
  list.all(c.evidence, fn(e) { string.length(e.id) > 0 })
  |> should.be_true()
}

pub fn c3i_package_all_items_have_non_empty_title_test() {
  let c = c3i_evidence_package()
  list.all(c.evidence, fn(e) { string.length(e.title) > 0 })
  |> should.be_true()
}

pub fn c3i_package_all_items_have_non_empty_artifact_path_test() {
  let c = c3i_evidence_package()
  list.all(c.evidence, fn(e) { string.length(e.artifact_path) > 0 })
  |> should.be_true()
}

pub fn c3i_package_has_formal_verification_evidence_test() {
  let c = c3i_evidence_package()
  { list.length(evidence_by_category(c, FormalVerification)) >= 2 }
  |> should.be_true()
}

pub fn c3i_package_has_requirements_spec_evidence_test() {
  let c = c3i_evidence_package()
  { list.length(evidence_by_category(c, RequirementsSpec)) >= 1 }
  |> should.be_true()
}

pub fn c3i_package_coverage_above_75_percent_test() {
  { coverage_percent(c3i_evidence_package()) >. 75.0 }
  |> should.be_true()
}

pub fn c3i_package_has_no_missing_evidence_test() {
  c3i_evidence_package()
  |> missing_evidence()
  |> list.length()
  |> should.equal(0)
}

pub fn c3i_package_pfd_is_1e_minus_4_test() {
  let c = c3i_evidence_package()
  c.pfd_target |> should.equal(1.0e-4)
}

pub fn c3i_package_hft_is_2_test() {
  let c = c3i_evidence_package()
  c.hft |> should.equal(2)
}

// ---------------------------------------------------------------------------
// 11. summary
// ---------------------------------------------------------------------------

pub fn summary_contains_system_name_test() {
  let s = summary(c3i_evidence_package())
  string.contains(s, "C3I") |> should.be_true()
}

pub fn summary_contains_sil4_test() {
  let s = summary(c3i_evidence_package())
  string.contains(s, "SIL-4") |> should.be_true()
}

pub fn summary_contains_coverage_test() {
  let s = summary(c3i_evidence_package())
  string.contains(s, "Coverage") |> should.be_true()
}

pub fn summary_contains_certifiable_test() {
  let s = summary(c3i_evidence_package())
  string.contains(s, "Certifiable") |> should.be_true()
}

// ---------------------------------------------------------------------------
// 12. item_summary
// ---------------------------------------------------------------------------

pub fn item_summary_contains_id_test() {
  let item = make_item("EV-099", Complete)
  item_summary(item) |> string.contains("EV-099") |> should.be_true()
}

pub fn item_summary_contains_status_test() {
  let item = make_item("EV-099", Complete)
  item_summary(item) |> string.contains("Complete") |> should.be_true()
}

// ---------------------------------------------------------------------------
// 13. evidence_for_sil
// ---------------------------------------------------------------------------

pub fn evidence_for_sil_filters_by_level_test() {
  let sil2_item =
    EvidenceItem(..make_item("EV-SIL2", Complete), sil_level: SIL2)
  let c =
    init_safety_case("Sys", SIL4)
    |> add_evidence(make_item("EV-001", Complete))
    |> add_evidence(sil2_item)
  evidence_for_sil(c, SIL2) |> list.length() |> should.equal(1)
  evidence_for_sil(c, SIL4) |> list.length() |> should.equal(1)
}

// ---------------------------------------------------------------------------
// 14. Structural invariants
// ---------------------------------------------------------------------------

pub fn all_c3i_items_have_description_test() {
  let c = c3i_evidence_package()
  list.all(c.evidence, fn(e) { string.length(e.description) > 10 })
  |> should.be_true()
}

pub fn integration_testing_evidence_is_partial_test() {
  // EV-007 (Wallaby) is intentionally Partial — verify the package is honest
  let c = c3i_evidence_package()
  list.any(evidence_by_category(c, IntegrationTesting), fn(e) {
    e.status == Partial
  })
  |> should.be_true()
}
