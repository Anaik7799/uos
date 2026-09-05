//// =============================================================================
//// Test Module: test/lustre_feature_tracker_view_test.gleam
//// Subject: Lustre MVU 145-Feature Living Tracker Component Tests
//// =============================================================================

import gleeunit/should
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import cepaf_gleam/knowledge/zigvm_feature_tracker.{PermanentAdrRecord, WikiCoreEngine}
import cepaf_gleam/ui/lustre/feature_tracker_view.{
  init, update, view,
  SetSearch, SetCategoryFilter, SelectFeature, ClearFilter,
}

pub fn init_model_test() {
  let model = init()
  model.search_query |> should.equal("")
  model.category_filter |> should.equal(None)
  model.selected_feature_id |> should.equal(Some("WIKI-001"))
  list.length(model.features) |> should.equal(145)
  model.summary.total_features |> should.equal(145)
}

pub fn update_search_and_category_test() {
  let m0 = init()
  let m1 = update(m0, SetSearch("Gospel"))
  m1.search_query |> should.equal("Gospel")

  let m2 = update(m1, SetCategoryFilter(Some(WikiCoreEngine)))
  m2.category_filter |> should.equal(Some(WikiCoreEngine))

  let m3 = update(m2, SetCategoryFilter(Some(PermanentAdrRecord)))
  m3.category_filter |> should.equal(Some(PermanentAdrRecord))

  let m4 = update(m3, SelectFeature("ADR-001"))
  m4.selected_feature_id |> should.equal(Some("ADR-001"))

  let m5 = update(m4, ClearFilter)
  m5.search_query |> should.equal("")
  m5.category_filter |> should.equal(None)
}

pub fn view_render_test() {
  let model = init()
  let elem = view(model)
  let elem_str = string.inspect(elem)
  string.contains(elem_str, "feature-tracker-view") |> should.equal(True)
  string.contains(elem_str, "145 FEATURES 100% OPERATIONAL") |> should.equal(True)
}
