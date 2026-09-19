//// =============================================================================
//// [C3I-SIL6-MSTS] CENTURY HUD TEST CONTRACT
//// =============================================================================

import cepaf_gleam/ui/lustre/century_hud.{
  init_century_hud, render_ansi, render_checklist_section, render_html,
  render_hud_svg, update_pid_telemetry,
}
import gleam/string
import gleeunit/should

pub fn century_hud_init_test() {
  let hud = init_century_hud()
  hud.milestone_id |> should.equal("EV-100")
  hud.cycle_name |> should.equal("Century Milestone Swarm Harmony")
  hud.total_eunit_tests |> should.equal(10475)
  hud.os_nvme_locked |> should.equal(True)
  hud.os_nvme_serial |> should.equal("25503L801736")
  hud.sovereigns.quorum_fraction |> should.equal("3/3")
  hud.math_gates.shannon_entropy |> should.equal(2.68)
}

pub fn century_hud_update_pid_test() {
  let hud = init_century_hud()
  let updated = update_pid_telemetry(hud, 2.5, 0.8, 0.25, 100.0, 0.0)
  updated.kp |> should.equal(2.5)
  updated.ki |> should.equal(0.8)
  updated.kd |> should.equal(0.25)
  updated.process_val |> should.equal(100.0)
  updated.control_output |> should.equal(0.0)
}

pub fn century_hud_render_svg_test() {
  let hud = init_century_hud()
  let svg = render_hud_svg(hud)
  string.contains(svg, "<svg") |> should.equal(True)
  string.contains(svg, "EV-100") |> should.equal(True)
  string.contains(svg, "PID TUNER") |> should.equal(True)
  string.contains(svg, "SWARM MESH") |> should.equal(True)
  string.contains(svg, "MATH GATES") |> should.equal(True)
  string.contains(svg, "25503L801736") |> should.equal(True)
}

pub fn century_hud_checklist_section_test() {
  let checklist = render_checklist_section()
  string.contains(checklist, "18/18 CHECKS 100% GREEN") |> should.equal(True)
  string.contains(checklist, "Domain 1: Metadata & Navigation")
  |> should.equal(True)
  string.contains(checklist, "Domain 2: Zero-Muda & Storage Safety")
  |> should.equal(True)
  string.contains(checklist, "Domain 3: Testing & Math Gates")
  |> should.equal(True)
  string.contains(checklist, "Domain 4: Cross-Language Control")
  |> should.equal(True)
  string.contains(checklist, "Domain 5: Tri-Sovereign Governance")
  |> should.equal(True)
  string.contains(checklist, "CHK-01-TIME") |> should.equal(True)
  string.contains(checklist, "CHK-18-JJ") |> should.equal(True)
}

pub fn century_hud_render_html_test() {
  let hud = init_century_hud()
  let html = render_html(hud)
  string.contains(html, "http://nas-1.tail55d152.ts.net:4100")
  |> should.equal(True)
  string.contains(html, "http://vm-1.tail55d152.ts.net:8088")
  |> should.equal(True)
  string.contains(html, "EV-100 CENTURY COCKPIT") |> should.equal(True)
  string.contains(html, "OTP 29 CLUSTER HEALTHY") |> should.equal(True)
}

pub fn century_hud_render_ansi_test() {
  let hud = init_century_hud()
  let ansi = render_ansi(hud)
  string.contains(ansi, "EV-100 // Century Milestone Swarm Harmony")
  |> should.equal(True)
  string.contains(ansi, "SECURE") |> should.equal(True)
  string.contains(ansi, "25503L801736") |> should.equal(True)
}
