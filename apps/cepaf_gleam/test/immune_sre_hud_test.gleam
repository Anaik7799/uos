//// =============================================================================
//// [C3I-SIL6-MSTS] IMMUNE SRE HUD TEST CONTRACT
//// =============================================================================

import cepaf_gleam/ui/lustre/immune_sre_hud.{
  init_immune_hud, render_ansi, render_checklist_section, render_html,
  render_immune_svg,
}
import gleam/string
import gleeunit/should

pub fn immune_hud_init_test() {
  let model = init_immune_hud()
  should.be_true(model.metabolic_health >=. 0.8)
  model.selected_fault_filter |> should.equal("all")
}

pub fn immune_hud_render_svg_test() {
  let model = init_immune_hud()
  let svg = render_immune_svg(model)
  string.contains(svg, "<svg") |> should.equal(True)
  string.contains(svg, "BIOMORPHIC SRE IMMUNE ENGINE") |> should.equal(True)
  string.contains(svg, "ENDOCRINE HORMONES") |> should.equal(True)
  string.contains(svg, "SYNTHESIZED ANTIBODIES") |> should.equal(True)
  string.contains(svg, "CHAOS CONTAINMENT") |> should.equal(True)
}

pub fn immune_hud_checklist_test() {
  let checklist = render_checklist_section()
  string.contains(checklist, "18/18 CHECKS 100% GREEN") |> should.equal(True)
  string.contains(checklist, "Domain 1: Metadata & Navigation")
  |> should.equal(True)
  string.contains(checklist, "Domain 2: Zero-Muda & Storage Safety")
  |> should.equal(True)
  string.contains(checklist, "CHK-01-TIME") |> should.equal(True)
  string.contains(checklist, "CHK-18-JJ") |> should.equal(True)
}

pub fn immune_hud_render_html_test() {
  let model = init_immune_hud()
  let html = render_html(model)
  string.contains(html, "http://nas-1.tail55d152.ts.net:4100")
  |> should.equal(True)
  string.contains(html, "http://vm-1.tail55d152.ts.net:8088")
  |> should.equal(True)
  string.contains(html, "Metabolic Immune Cockpit & Self-Healing SRE Mesh")
  |> should.equal(True)
}

pub fn immune_hud_render_ansi_test() {
  let model = init_immune_hud()
  let ansi = render_ansi(model)
  string.contains(ansi, "EV-102 // Biomorphic SRE Immune Cockpit")
  |> should.equal(True)
  string.contains(ansi, "Metabolic Health:") |> should.equal(True)
}
