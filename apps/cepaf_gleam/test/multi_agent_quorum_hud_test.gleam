// Tests for Multi-Agent Quorum Cockpit HUD (EV-105)
// STAMP: SC-TAILSCALE-WEB-001, SC-CHECKLIST-001, SC-GLM-UI-001

import cepaf_gleam/ha/multi_agent_quorum.{
  AgySovereign, ClaudeSovereign, QuorumApprove, TwoOfThreeSovereign,
  cast_ballot_vote, create_ballot, init_quorum_engine, record_ballot,
}
import cepaf_gleam/ui/lustre/multi_agent_quorum_hud
import gleam/string
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn init_quorum_hud_test() {
  let hud = multi_agent_quorum_hud.init_quorum_hud()
  hud.cycle_id |> should.equal("EV-105")
  hud.os_nvme_locked |> should.equal(True)
  hud.os_nvme_serial |> should.equal("25503L801736")
  hud.sovereigns.quorum_fraction |> should.equal("3/3")
  should.be_true(hud.vote_entropy >. 0.0)
}

pub fn update_from_engine_test() {
  let hud = multi_agent_quorum_hud.init_quorum_hud()
  let engine0 = init_quorum_engine()

  let ballot0 = create_ballot("prop-test-01", "Admission", TwoOfThreeSovereign, 1000)
  let ballot1 = cast_ballot_vote(ballot0, AgySovereign, QuorumApprove, "Approved", "hash-1", 1010)
  let ballot2 = cast_ballot_vote(ballot1, ClaudeSovereign, QuorumApprove, "Approved", "hash-2", 1020)

  let engine1 = record_ballot(engine0, ballot2)
  let updated_hud = multi_agent_quorum_hud.update_from_engine(hud, engine1, ballot2)

  updated_hud.total_ballots |> should.equal(1)
  updated_hud.ratified_count |> should.equal(1)
  updated_hud.latest_proposal_id |> should.equal("prop-test-01")
  should.be_true(string.contains(updated_hud.latest_verdict, "RATIFIED"))
}

pub fn render_svg_and_html_test() {
  let hud = multi_agent_quorum_hud.init_quorum_hud()

  let svg = multi_agent_quorum_hud.render_hud_svg(hud)
  should.be_true(string.contains(svg, "<svg"))
  should.be_true(string.contains(svg, "EV-105"))
  should.be_true(string.contains(svg, "25503L801736"))
  should.be_true(string.contains(svg, "TRI-SOVEREIGN MESH"))

  let html = multi_agent_quorum_hud.render_html_page(hud)
  should.be_true(string.contains(html, "<!DOCTYPE html>"))
  should.be_true(string.contains(html, "http://nas-1.tail55d152.ts.net:4100"))
  should.be_true(string.contains(html, "Comprehensive Verification Checklist"))

  let ansi = multi_agent_quorum_hud.render_ansi(hud)
  should.be_true(string.contains(ansi, "EV-105"))
  should.be_true(string.contains(ansi, "25503L801736"))
}
