//// apps/cepaf_gleam/test/tui_cluster_c_test.gleam
//// System TUI Cluster C (Mesh, Distributed Data & Governance: Screens 17-24) Test Suite
//// STAMP: SC-GLM-UI-001, SC-GLM-UI-004

import gleeunit/should
import cepaf_gleam/testing/tui_test_engine.{
  AgentsScreen, HolonScreen, ConfigScreen, GitScreen,
  DatabaseScreen, BridgeScreen, SmritiScreen, PlanningDashScreen,
  render_screen_buffer, verify_frame_buffer
}

pub fn tui_cluster_c_agents_test() {
  let fb = render_screen_buffer(AgentsScreen)
  case verify_frame_buffer(fb) {
    Ok(len) -> should.be_true(len >= 50)
    Error(_) -> should.fail()
  }
}

pub fn tui_cluster_c_holon_test() {
  let fb = render_screen_buffer(HolonScreen)
  case verify_frame_buffer(fb) {
    Ok(len) -> should.be_true(len >= 50)
    Error(_) -> should.fail()
  }
}

pub fn tui_cluster_c_config_test() {
  let fb = render_screen_buffer(ConfigScreen)
  case verify_frame_buffer(fb) {
    Ok(len) -> should.be_true(len >= 50)
    Error(_) -> should.fail()
  }
}

pub fn tui_cluster_c_git_test() {
  let fb = render_screen_buffer(GitScreen)
  case verify_frame_buffer(fb) {
    Ok(len) -> should.be_true(len >= 50)
    Error(_) -> should.fail()
  }
}

pub fn tui_cluster_c_database_test() {
  let fb = render_screen_buffer(DatabaseScreen)
  case verify_frame_buffer(fb) {
    Ok(len) -> should.be_true(len >= 50)
    Error(_) -> should.fail()
  }
}

pub fn tui_cluster_c_bridge_test() {
  let fb = render_screen_buffer(BridgeScreen)
  case verify_frame_buffer(fb) {
    Ok(len) -> should.be_true(len >= 50)
    Error(_) -> should.fail()
  }
}

pub fn tui_cluster_c_smriti_test() {
  let fb = render_screen_buffer(SmritiScreen)
  case verify_frame_buffer(fb) {
    Ok(len) -> should.be_true(len >= 50)
    Error(_) -> should.fail()
  }
}

pub fn tui_cluster_c_planning_dash_test() {
  let fb = render_screen_buffer(PlanningDashScreen)
  case verify_frame_buffer(fb) {
    Ok(len) -> should.be_true(len >= 50)
    Error(_) -> should.fail()
  }
}
