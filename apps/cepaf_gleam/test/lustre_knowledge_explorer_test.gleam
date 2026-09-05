//// =============================================================================
//// Test Module: test/lustre_knowledge_explorer_test.gleam
//// Subject: Lustre MVU Knowledge & Wiki Explorer Component Tests
//// =============================================================================

import gleeunit/should
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import cepaf_gleam/ui/lustre/knowledge_explorer.{
  init, update, view, default_items,
  SetSearch, SelectTab, SelectItem, FilterByTag, ClearSelection,
  TabWikiCorpus, TabZkInvariants,
}

pub fn init_model_test() {
  let model = init()
  model.search_query |> should.equal("")
  model.active_tab |> should.equal(TabWikiCorpus)
  model.selected_id |> should.equal(None)
  model.active_tag_filter |> should.equal(None)
  { list.length(model.items) >= 5 } |> should.equal(True)
}

pub fn default_items_test() {
  let items = default_items()
  let has_wiki = list.any(items, fn(i) { i.id == "WIKI-001" })
  let has_adr = list.any(items, fn(i) { i.id == "ADR-001" })
  let has_bio = list.any(items, fn(i) { i.id == "BIO-001" })
  has_wiki |> should.equal(True)
  has_adr |> should.equal(True)
  has_bio |> should.equal(True)
}

pub fn update_search_and_tab_test() {
  let m0 = init()
  let m1 = update(m0, SetSearch("rete"))
  m1.search_query |> should.equal("rete")

  let m2 = update(m1, SelectTab(TabZkInvariants))
  m2.active_tab |> should.equal(TabZkInvariants)
  m2.selected_id |> should.equal(None)

  let m3 = update(m2, SelectItem("ADR-001"))
  m3.selected_id |> should.equal(Some("ADR-001"))

  let m4 = update(m3, FilterByTag(Some("#rocha-semiotics")))
  m4.active_tag_filter |> should.equal(Some("#rocha-semiotics"))

  let m5 = update(m4, ClearSelection)
  m5.selected_id |> should.equal(None)
}

pub fn view_render_test() {
  let model = init()
  let elem = view(model)
  let elem_str = string.inspect(elem)
  string.contains(elem_str, "knowledge-explorer") |> should.equal(True)
  string.contains(elem_str, "Wiki Corpus Index") |> should.equal(True)
}
