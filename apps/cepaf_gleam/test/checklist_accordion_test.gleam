//// apps/cepaf_gleam/test/checklist_accordion_test.gleam
//// Universal 18-Point Verification Checklist Accordion Test Suite (All 15 Tabs)
//// STAMP: SC-CHECKLIST-001, SC-TAILSCALE-WEB-001

import gleeunit/should
import cepaf_gleam/testing/webui_test_engine.{
  all_web_tabs, evaluate_checklist_accordion
}
import gleam/list

pub fn all_15_tabs_checklist_accordion_test() {
  let tabs = all_web_tabs()
  list.length(tabs) |> should.equal(15)

  let all_18_checks_pass =
    list.all(tabs, fn(tab) {
      case evaluate_checklist_accordion(tab) {
        Ok(count) -> count == 18
        Error(_) -> False
      }
    })

  should.be_true(all_18_checks_pass)
}
