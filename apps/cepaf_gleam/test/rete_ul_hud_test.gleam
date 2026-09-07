// Tests for Rete-UL Cockpit HUD (EV-107)
// STAMP: SC-TAILSCALE-WEB-001, SC-CHECKLIST-001, SC-GLM-UI-001

import cepaf_gleam/knowledge/rete_ul_verifier.{
  ConsequenceGateVerdict, OpEq, ReteCondition, ReteRule, add_rule,
  init_working_memory,
}
import cepaf_gleam/ui/lustre/rete_ul_hud
import gleam/string
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn init_rete_ul_hud_test() {
  let hud = rete_ul_hud.init_rete_ul_hud()
  hud.cycle_id |> should.equal("EV-107")
  hud.os_nvme_locked |> should.equal(True)
  hud.os_nvme_serial |> should.equal("25503L801736")
  hud.sovereigns.quorum_fraction |> should.equal("3/3")
  hud.is_consistent |> should.equal(True)
}

pub fn update_from_wm_test() {
  let hud = rete_ul_hud.init_rete_ul_hud()
  let wm0 = init_working_memory()
  let conds = [ReteCondition("policy", "level", OpEq, "strict")]

  let r1 = ReteRule("p_allow", conds, ConsequenceGateVerdict("ALLOW"))
  let r2 = ReteRule("p_deny", conds, ConsequenceGateVerdict("DENY"))

  let wm1 = add_rule(wm0, r1)
  let wm2 = add_rule(wm1, r2)

  let updated_hud = rete_ul_hud.update_from_wm(hud, wm2)
  updated_hud.is_consistent |> should.equal(False)
  updated_hud.anomaly_count |> should.equal(1)
  should.be_true(string.contains(updated_hud.status_badge, "VIOLATION"))
}

pub fn render_svg_and_html_test() {
  let hud = rete_ul_hud.init_rete_ul_hud()

  let svg = rete_ul_hud.render_hud_svg(hud)
  should.be_true(string.contains(svg, "<svg"))
  should.be_true(string.contains(svg, "EV-107"))
  should.be_true(string.contains(svg, "25503L801736"))
  should.be_true(string.contains(svg, "RETE-UL RULE BASE CONSISTENCY"))

  let html = rete_ul_hud.render_html_page(hud)
  should.be_true(string.contains(html, "<!DOCTYPE html>"))
  should.be_true(string.contains(html, "http://nas-1.tail55d152.ts.net:4100"))
  should.be_true(string.contains(html, "Comprehensive Verification Checklist"))

  let ansi = rete_ul_hud.render_ansi(hud)
  should.be_true(string.contains(ansi, "EV-107"))
  should.be_true(string.contains(ansi, "25503L801736"))
}
