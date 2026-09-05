//// =============================================================================
//// Test Module: test/lustre_zk_decision_matrix_test.gleam
//// Subject: Lustre MVU ZK Decision Matrix & ADR Explorer Component Tests
//// =============================================================================

import gleeunit/should
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import cepaf_gleam/ui/lustre/zk_decision_matrix.{
  init, update, view, all_adrs,
  SetSearch, SetLayerFilter, SelectAdr, ClearFilter,
}

pub fn all_adrs_count_test() {
  let adrs = all_adrs()
  list.length(adrs) |> should.equal(16)
}

pub fn init_model_test() {
  let model = init()
  model.search_query |> should.equal("")
  model.layer_filter |> should.equal(None)
  model.selected_adr_id |> should.equal(Some("ADR-001"))
  list.length(model.adrs) |> should.equal(16)
}

pub fn update_search_and_filter_test() {
  let m0 = init()
  let m1 = update(m0, SetSearch("SMT"))
  m1.search_query |> should.equal("SMT")

  let m2 = update(m1, SetLayerFilter(Some("#fractal-l2")))
  m2.layer_filter |> should.equal(Some("#fractal-l2"))

  let m3 = update(m2, SelectAdr("ADR-003"))
  m3.selected_adr_id |> should.equal(Some("ADR-003"))

  let m4 = update(m3, ClearFilter)
  m4.search_query |> should.equal("")
  m4.layer_filter |> should.equal(None)
}

pub fn view_render_test() {
  let model = init()
  let elem = view(model)
  let elem_str = string.inspect(elem)
  string.contains(elem_str, "zk-decision-matrix") |> should.equal(True)
  string.contains(elem_str, "ADR-001") |> should.equal(True)
  string.contains(elem_str, "16/16 RATIFIED") |> should.equal(True)
}
