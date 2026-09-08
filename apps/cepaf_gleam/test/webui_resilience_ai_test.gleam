//// apps/cepaf_gleam/test/webui_resilience_ai_test.gleam
//// WebUI Resilience, Immune & AI Tabs (Immune, Metabolic, MCP, HealthGrid) Test Suite
//// STAMP: SC-GLM-UI-001, SC-CHECKLIST-001

import gleeunit/should
import cepaf_gleam/testing/webui_test_engine.{
  WebImmune, WebMetabolic, WebMcp, WebHealthGrid,
  evaluate_c1_c8, evaluate_checklist_accordion
}
import gleam/list

pub fn webui_resilience_ai_c1_c8_test() {
  let tabs = [WebImmune, WebMetabolic, WebMcp, WebHealthGrid]
  let all_ok =
    list.all(tabs, fn(t) {
      let score = evaluate_c1_c8(t)
      score.total_passed == 8
    })
  should.be_true(all_ok)
}

pub fn webui_resilience_ai_checklist_accordion_test() {
  let tabs = [WebImmune, WebMetabolic, WebMcp, WebHealthGrid]
  let all_ok =
    list.all(tabs, fn(t) {
      case evaluate_checklist_accordion(t) {
        Ok(count) -> count == 18
        Error(_) -> False
      }
    })
  should.be_true(all_ok)
}
