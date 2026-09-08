//// apps/cepaf_gleam/test/tui_cluster_a_test.gleam
//// System TUI Cluster A (Operations & Mission Control: Screens 1-8) Test Suite
//// STAMP: SC-GLM-UI-001, SC-GLM-UI-004

import gleeunit/should
import cepaf_gleam/testing/tui_test_engine.{
  DashboardScreen, PlanningScreen, ImmuneScreen, KnowledgeScreen,
  ZenohScreen, CockpitScreen, VerificationScreen, SubstrateScreen,
  render_screen_buffer, verify_frame_buffer
}

pub fn tui_cluster_a_dashboard_test() {
  let fb = render_screen_buffer(DashboardScreen)
  case verify_frame_buffer(fb) {
    Ok(len) -> should.be_true(len >= 50)
    Error(_) -> should.fail()
  }
}

pub fn tui_cluster_a_planning_test() {
  let fb = render_screen_buffer(PlanningScreen)
  case verify_frame_buffer(fb) {
    Ok(len) -> should.be_true(len >= 50)
    Error(_) -> should.fail()
  }
}

pub fn tui_cluster_a_immune_test() {
  let fb = render_screen_buffer(ImmuneScreen)
  case verify_frame_buffer(fb) {
    Ok(len) -> should.be_true(len >= 50)
    Error(_) -> should.fail()
  }
}

pub fn tui_cluster_a_knowledge_test() {
  let fb = render_screen_buffer(KnowledgeScreen)
  case verify_frame_buffer(fb) {
    Ok(len) -> should.be_true(len >= 50)
    Error(_) -> should.fail()
  }
}

pub fn tui_cluster_a_zenoh_test() {
  let fb = render_screen_buffer(ZenohScreen)
  case verify_frame_buffer(fb) {
    Ok(len) -> should.be_true(len >= 50)
    Error(_) -> should.fail()
  }
}

pub fn tui_cluster_a_cockpit_test() {
  let fb = render_screen_buffer(CockpitScreen)
  case verify_frame_buffer(fb) {
    Ok(len) -> should.be_true(len >= 50)
    Error(_) -> should.fail()
  }
}

pub fn tui_cluster_a_verification_test() {
  let fb = render_screen_buffer(VerificationScreen)
  case verify_frame_buffer(fb) {
    Ok(len) -> should.be_true(len >= 50)
    Error(_) -> should.fail()
  }
}

pub fn tui_cluster_a_substrate_test() {
  let fb = render_screen_buffer(SubstrateScreen)
  case verify_frame_buffer(fb) {
    Ok(len) -> should.be_true(len >= 50)
    Error(_) -> should.fail()
  }
}
