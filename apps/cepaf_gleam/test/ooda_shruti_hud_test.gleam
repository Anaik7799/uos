import cepaf_gleam/agents/ooda_shruti_copilot.{
  AstAnomaly, advance_ooda_phase, init_copilot, record_ast_anomaly,
}
import cepaf_gleam/ui/lustre/ooda_shruti_hud
import gleam/string
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn init_ooda_shruti_hud_test() {
  let hud = ooda_shruti_hud.init_ooda_shruti_hud()
  hud.cycle_id |> should.equal("EV-104")
  hud.current_phase_name |> should.equal("OBSERVE")
  hud.active_swara |> should.equal("Sa")
  hud.os_nvme_locked |> should.equal(True)
  hud.os_nvme_serial |> should.equal("25503L801736")
  hud.sovereigns.quorum_fraction |> should.equal("3/3")
  should.be_true(hud.consonance_pct >. 50.0)
}

pub fn update_from_copilot_test() {
  let hud = ooda_shruti_hud.init_ooda_shruti_hud()
  let copilot = init_copilot()
  let copilot = advance_ooda_phase(copilot, 1000)
  let copilot =
    record_ast_anomaly(
      copilot,
      AstAnomaly("a1", "TypeMismatch", 0.9, "mod.gleam", "+ fix", False),
    )

  let updated = ooda_shruti_hud.update_from_copilot(hud, copilot)
  updated.current_phase_name |> should.equal("ORIENT")
  updated.active_swara |> should.equal("Re2")
  updated.anomaly_count |> should.equal(1)
  updated.andon_active |> should.equal(True)
}

pub fn render_svg_and_html_test() {
  let hud = ooda_shruti_hud.init_ooda_shruti_hud()
  let svg = ooda_shruti_hud.render_hud_svg(hud)
  should.be_true(string.contains(svg, "<svg"))
  should.be_true(string.contains(svg, "EV-104"))
  should.be_true(string.contains(svg, "OODA PHASE"))
  should.be_true(string.contains(svg, "SHRUTI RESONANCE"))
  should.be_true(string.contains(svg, "25503L801736"))

  let html = ooda_shruti_hud.render_html_page(hud)
  should.be_true(string.contains(html, "<!DOCTYPE html>"))
  should.be_true(string.contains(html, "http://nas-1.tail55d152.ts.net:4100"))
  should.be_true(string.contains(html, "Comprehensive Verification Checklist"))

  let ansi = ooda_shruti_hud.render_ansi(hud)
  should.be_true(string.contains(ansi, "EV-104"))
  should.be_true(string.contains(ansi, "25503L801736"))
}
