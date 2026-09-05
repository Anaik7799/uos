/// Symbiosis module tests — ecological relationship types + biomorphic tensor
///
/// C1: Structure — types construct correctly
/// C2: Classification — all 6 relationship types classified
/// C3: Tensor — 7×8 matrix built with correct coverage
/// C4: Scoring — global index, mutualism ratio computed
/// C5: Integration — biomorphic model includes symbiosis + tensor
///
/// STAMP: SC-ECO-001, SC-BIO-EVO-001..007, SC-MOKSHA-001
/// Layer: L5_COGNITIVE, L6_ECOSYSTEM
import cepaf_gleam/symbiosis/tensor
import cepaf_gleam/symbiosis/types as symbiosis
import cepaf_gleam/ui/lustre/biomorphic
import gleam/list
import gleeunit/should

// =============================================================================
// C1 — Structure: types construct and init correctly
// =============================================================================

pub fn symbiosis_new_empty_test() {
  let idx = symbiosis.new()
  idx.total_count |> should.equal(0)
  idx.global_index |> should.equal(0.0)
  idx.mutualism_count |> should.equal(0)
}

pub fn symbiosis_record_creates_relation_test() {
  let idx =
    symbiosis.new()
    |> symbiosis.record("a", "b", 0.5, 0.5)
  idx.total_count |> should.equal(1)
  idx.mutualism_count |> should.equal(1)
}

pub fn tensor_build_has_56_cells_test() {
  let t = tensor.build()
  list.length(t.cells) |> should.equal(56)
}

pub fn tensor_coverage_positive_test() {
  let t = tensor.build()
  { t.coverage >. 0.0 } |> should.be_true()
}

pub fn tensor_health_positive_test() {
  let t = tensor.build()
  { t.health >. 0.0 } |> should.be_true()
}

// Pass-17 — Symbiosis tensor pass-history accessor tests.
pub fn tensor_pass14_cells_present_test() {
  let t = tensor.build()
  let upgraded = tensor.cells_upgraded_in_pass(t, 14)
  // Pass-14 added ruliology DQ Rule30/110/Lyapunov + ruliology submodule mention
  { list.length(upgraded) >= 2 } |> should.be_true()
}

pub fn tensor_pass15_cells_present_test() {
  let t = tensor.build()
  let upgraded = tensor.cells_upgraded_in_pass(t, 15)
  // Pass-15 added dq_scan SQL scanner annotation
  { list.length(upgraded) >= 1 } |> should.be_true()
}

pub fn tensor_pass16_cells_present_test() {
  let t = tensor.build()
  let upgraded = tensor.cells_upgraded_in_pass(t, 16)
  // Pass-16 added proptest validators annotation
  { list.length(upgraded) >= 1 } |> should.be_true()
}

pub fn tensor_pass_history_includes_recent_test() {
  let t = tensor.build()
  let history = tensor.pass_history(t)
  // History MUST contain Pass-14, 15, 16 (all three latest passes)
  { list.contains(history, 14) } |> should.be_true()
  { list.contains(history, 15) } |> should.be_true()
  { list.contains(history, 16) } |> should.be_true()
}

pub fn tensor_health_increased_after_passes_14_15_16_test() {
  let t = tensor.build()
  // Pass-13 baseline reported health ~0.84. After 14/15/16 enrichment
  // (raising 11 cells from 0.85→0.92 average) the health MUST exceed 0.84.
  { t.health >. 0.84 } |> should.be_true()
}

// =============================================================================
// C2 — Classification: all 6 ecological relationship types
// =============================================================================

pub fn classify_mutualism_test() {
  let rt = symbiosis.classify(0.5, 0.5)
  symbiosis.relation_type_to_string(rt) |> should.equal("mutualism")
}

pub fn classify_commensalism_test() {
  let rt = symbiosis.classify(0.5, 0.0)
  symbiosis.relation_type_to_string(rt) |> should.equal("commensalism")
}

pub fn classify_parasitism_test() {
  let rt = symbiosis.classify(0.5, -0.5)
  symbiosis.relation_type_to_string(rt) |> should.equal("parasitism")
}

pub fn classify_amensalism_test() {
  let rt = symbiosis.classify(0.0, -0.5)
  symbiosis.relation_type_to_string(rt) |> should.equal("amensalism")
}

pub fn classify_competition_test() {
  let rt = symbiosis.classify(-0.5, -0.5)
  symbiosis.relation_type_to_string(rt) |> should.equal("competition")
}

pub fn classify_neutralism_test() {
  let rt = symbiosis.classify(0.0, 0.0)
  symbiosis.relation_type_to_string(rt) |> should.equal("neutralism")
}

// =============================================================================
// C3 — Tensor: 7 properties × 8 layers matrix
// =============================================================================

pub fn tensor_row_homeostasis_has_8_cells_test() {
  let t = tensor.build()
  let row = tensor.row(t, tensor.Homeostasis)
  list.length(row) |> should.equal(8)
}

pub fn tensor_row_reproduction_gap_closed_test() {
  let t = tensor.build()
  let row = tensor.row(t, tensor.Reproduction)
  let missing = list.filter(row, fn(c) { c.status == tensor.Missing })
  // Gap closed: L0/L1 = NotApplicable (safety), L2/L4/L6 = Active
  list.length(missing) |> should.equal(0)
  let na = list.filter(row, fn(c) { c.status == tensor.NotApplicable })
  // L0 + L1 = 2 NotApplicable (safety kernel must not self-generate)
  list.length(na) |> should.equal(2)
  let active = list.filter(row, fn(c) { c.status == tensor.Active })
  // L2, L3, L4, L5, L6, L7 = 6 Active
  list.length(active) |> should.equal(6)
}

pub fn tensor_column_l5_all_active_test() {
  let t = tensor.build()
  let col = tensor.column(t, 5)
  let active = list.filter(col, fn(c) { c.status == tensor.Active })
  // L5 Cognitive should have all 7 properties active
  list.length(active) |> should.equal(7)
}

pub fn tensor_active_count_test() {
  let t = tensor.build()
  let active = tensor.active_count(t)
  // Most cells are Active (at least 40 of 56)
  { active > 40 } |> should.be_true()
}

pub fn tensor_no_missing_cells_test() {
  let t = tensor.build()
  let missing = tensor.missing_count(t)
  // GAP CLOSED: 0 missing cells (L0/L1 Reproduction = NotApplicable, rest Active)
  missing |> should.equal(0)
}

pub fn tensor_not_applicable_count_test() {
  let t = tensor.build()
  let na =
    list.length(
      list.filter(t.cells, fn(c) { c.status == tensor.NotApplicable }),
    )
  // L0 + L1 Reproduction = 2 NotApplicable
  na |> should.equal(2)
}

pub fn tensor_coverage_above_95_pct_test() {
  let t = tensor.build()
  // With gap closed: 54 applicable, all Active → coverage ≈ 100%
  { t.coverage >. 0.95 } |> should.be_true()
}

pub fn tensor_health_above_80_pct_test() {
  let t = tensor.build()
  // All applicable cells have positive scores
  { t.health >. 0.8 } |> should.be_true()
}

pub fn tensor_property_to_string_test() {
  tensor.property_to_string(tensor.Homeostasis) |> should.equal("Homeostasis")
  tensor.property_to_string(tensor.Evolution) |> should.equal("Evolution")
}

pub fn tensor_property_to_sanskrit_test() {
  tensor.property_to_sanskrit(tensor.Homeostasis) |> should.equal("समस्थिति")
  tensor.property_to_sanskrit(tensor.Reproduction) |> should.equal("प्रजनन")
}

pub fn tensor_layer_label_test() {
  tensor.layer_label(0) |> should.equal("L0 Constitutional")
  tensor.layer_label(7) |> should.equal("L7 Federation")
}

// =============================================================================
// C4 — Scoring: global index, pair index, mutualism ratio
// =============================================================================

pub fn pair_index_mean_test() {
  let idx = symbiosis.pair_index(0.8, 0.6)
  { idx >. 0.69 && idx <. 0.71 } |> should.be_true()
}

pub fn global_index_positive_for_mutualistic_test() {
  let idx =
    symbiosis.new()
    |> symbiosis.record("a", "b", 0.8, 0.7)
    |> symbiosis.record("c", "d", 0.6, 0.5)
  { idx.global_index >. 0.0 } |> should.be_true()
}

pub fn mutualism_ratio_all_mutualistic_test() {
  let idx =
    symbiosis.new()
    |> symbiosis.record("a", "b", 0.8, 0.7)
    |> symbiosis.record("c", "d", 0.6, 0.5)
  let ratio = symbiosis.mutualism_ratio(idx)
  { ratio >. 0.99 } |> should.be_true()
}

pub fn is_healthy_positive_test() {
  let idx =
    symbiosis.new()
    |> symbiosis.record("a", "b", 0.8, 0.7)
  symbiosis.is_healthy(idx) |> should.be_true()
}

pub fn is_healthy_negative_for_parasitism_test() {
  let idx =
    symbiosis.new()
    |> symbiosis.record("a", "b", 0.8, -0.7)
    |> symbiosis.record("c", "d", 0.9, -0.3)
  // Parasitism count > mutualism count → not healthy
  symbiosis.is_healthy(idx) |> should.be_false()
}

pub fn by_type_filters_correctly_test() {
  let idx =
    symbiosis.new()
    |> symbiosis.record("a", "b", 0.8, 0.7)
    |> symbiosis.record("c", "d", 0.5, -0.5)
  let mutual = symbiosis.by_type(idx, symbiosis.Mutualism)
  list.length(mutual) |> should.equal(1)
  let parasitic = symbiosis.by_type(idx, symbiosis.Parasitism)
  list.length(parasitic) |> should.equal(1)
}

pub fn relation_type_sanskrit_test() {
  symbiosis.relation_type_to_sanskrit(symbiosis.Mutualism)
  |> should.equal("परस्पर लाभ")
  symbiosis.relation_type_to_sanskrit(symbiosis.Parasitism)
  |> should.equal("परजीविता")
}

// =============================================================================
// C5 — Integration: BiomorphicModel includes symbiosis + tensor
// =============================================================================

pub fn biomorphic_model_has_symbiosis_test() {
  let model = biomorphic.init()
  { model.symbiosis.total_count > 0 } |> should.be_true()
}

pub fn biomorphic_model_has_tensor_test() {
  let model = biomorphic.init()
  { list.length(model.tensor.cells) == 56 } |> should.be_true()
}

pub fn biomorphic_tensor_coverage_test() {
  let model = biomorphic.init()
  { biomorphic.tensor_coverage(model) >. 0.0 } |> should.be_true()
}

pub fn biomorphic_symbiosis_healthy_test() {
  let model = biomorphic.init()
  biomorphic.symbiosis_healthy(model) |> should.be_true()
}

pub fn biomorphic_update_symbiosis_test() {
  let model = biomorphic.init()
  let updated =
    biomorphic.update(model, biomorphic.SymbiosisRecorded("x", "y", 0.9, 0.8))
  { updated.symbiosis.total_count > model.symbiosis.total_count }
  |> should.be_true()
}

pub fn biomorphic_refresh_rebuilds_tensor_test() {
  let model = biomorphic.init()
  let refreshed = biomorphic.update(model, biomorphic.RefreshBiomorphic)
  refreshed.loading |> should.be_true()
  { list.length(refreshed.tensor.cells) == 56 } |> should.be_true()
}

pub fn biomorphic_all_healthy_nominal_test() {
  let model = biomorphic.init()
  biomorphic.all_healthy(model) |> should.be_true()
}
