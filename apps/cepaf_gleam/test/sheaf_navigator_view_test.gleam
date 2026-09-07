//// =============================================================================
//// [C3I-SIL6-MSTS] SHEAF NAVIGATOR VIEW TEST CONTRACT
//// =============================================================================

import cepaf_gleam/ui/lustre/sheaf_navigator_view.{
  init_sheaf_navigator, render_ansi, render_checklist_section, render_html,
  render_sheaf_svg,
}
import gleam/string
import gleeunit/should

pub fn sheaf_navigator_init_test() {
  let model = init_sheaf_navigator()
  model.selected_node_id |> should.equal("ADR-077")
  model.active_search_query |> should.equal("")
}

pub fn sheaf_navigator_render_svg_test() {
  let model = init_sheaf_navigator()
  let svg = render_sheaf_svg(model)
  string.contains(svg, "<svg") |> should.equal(True)
  string.contains(svg, "HOLOGRAPHIC SHEAF HYPERGRAPH") |> should.equal(True)
  string.contains(svg, "ADR-077") |> should.equal(True)
  string.contains(svg, "WIKI-MOC") |> should.equal(True)
  string.contains(svg, "SIL-6") |> should.equal(True)
}

pub fn sheaf_navigator_checklist_test() {
  let checklist = render_checklist_section()
  string.contains(checklist, "18/18 CHECKS 100% GREEN") |> should.equal(True)
  string.contains(checklist, "Domain 1: Metadata & Navigation")
  |> should.equal(True)
  string.contains(checklist, "Domain 2: Zero-Muda & Storage Safety")
  |> should.equal(True)
  string.contains(checklist, "CHK-01-TIME") |> should.equal(True)
  string.contains(checklist, "CHK-18-JJ") |> should.equal(True)
}

pub fn sheaf_navigator_render_html_test() {
  let model = init_sheaf_navigator()
  let html = render_html(model)
  string.contains(html, "http://nas-1.tail55d152.ts.net:4100")
  |> should.equal(True)
  string.contains(html, "http://vm-1.tail55d152.ts.net:8088")
  |> should.equal(True)
  string.contains(html, "Autonomous Semantic Knowledge Sheaf Navigator")
  |> should.equal(True)
  string.contains(html, "SHEAF HYPERGRAPH NODES") |> should.equal(True)
}

pub fn sheaf_navigator_render_ansi_test() {
  let model = init_sheaf_navigator()
  let ansi = render_ansi(model)
  string.contains(ansi, "EV-101 // Holographic Sheaf Knowledge Navigator")
  |> should.equal(True)
  string.contains(ansi, "Selected Node: ADR-077") |> should.equal(True)
}
