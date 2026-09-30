// Tests for Predictive Autoscaler Cockpit HUD (EV-106)
// STAMP: SC-TAILSCALE-WEB-001, SC-CHECKLIST-001, SC-GLM-UI-001

import cepaf_gleam/ha/predictive_autoscaler.{evaluate_scaling, init_autoscaler}
import cepaf_gleam/ui/lustre/predictive_autoscaler_hud
import gleam/string
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn init_autoscaler_hud_test() {
  let hud = predictive_autoscaler_hud.init_autoscaler_hud()
  hud.cycle_id |> should.equal("EV-106")
  hud.os_nvme_locked |> should.equal(True)
  hud.os_nvme_serial |> should.equal("25503L801736")
  hud.sovereigns.quorum_fraction |> should.equal("3/3")
  should.be_true(hud.available_tokens > 0)
}

pub fn update_from_autoscaler_test() {
  let hud = predictive_autoscaler_hud.init_autoscaler_hud()
  let assert Ok(engine0) = init_autoscaler(2, 10, 50.0, 1000, 100, 1000)
  let engine1 = evaluate_scaling(engine0, 25, 120.0, 1000 + 10_000_001)

  let updated_hud =
    predictive_autoscaler_hud.update_from_autoscaler(hud, engine1)
  updated_hud.current_workers |> should.equal(4)
  updated_hud.queue_depth |> should.equal(25)
  should.be_true(string.contains(updated_hud.last_action_desc, "SCALE UP"))
}

pub fn render_svg_and_html_test() {
  let hud = predictive_autoscaler_hud.init_autoscaler_hud()

  let svg = predictive_autoscaler_hud.render_hud_svg(hud)
  should.be_true(string.contains(svg, "<svg"))
  should.be_true(string.contains(svg, "EV-106"))
  should.be_true(string.contains(svg, "25503L801736"))
  should.be_true(string.contains(svg, "WORKER POOL DYNAMICS"))
  should.be_true(string.contains(svg, "TOKEN FLOW RATE"))

  let html = predictive_autoscaler_hud.render_html_page(hud)
  should.be_true(string.contains(html, "<!DOCTYPE html>"))
  should.be_true(string.contains(html, "http://nas-1.tail55d152.ts.net:4100"))
  should.be_true(string.contains(html, "Comprehensive Verification Checklist"))

  let ansi = predictive_autoscaler_hud.render_ansi(hud)
  should.be_true(string.contains(ansi, "EV-106"))
  should.be_true(string.contains(ansi, "25503L801736"))
}
