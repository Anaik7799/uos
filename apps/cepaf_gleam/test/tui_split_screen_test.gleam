//// apps/cepaf_gleam/test/tui_split_screen_test.gleam
//// System TUI Split-Screen Dual-Pane Telemetry Test Suite
//// STAMP: SC-GLM-UI-001, SC-GLM-UI-004

import gleeunit/should
import cepaf_gleam/testing/tui_test_engine.{
  render_split_screen_buffer, verify_frame_buffer
}
import gleam/string

pub fn tui_split_screen_dual_pane_test() {
  let fb = render_split_screen_buffer()
  case verify_frame_buffer(fb) {
    Ok(len) -> {
      should.be_true(len >= 100)
      should.be_true(string.contains(fb.content, "LEFT PANE: SWARM TOPOLOGY"))
      should.be_true(string.contains(fb.content, "RIGHT PANE: OTEL 128-BIT SPAN"))
    }
    Error(_) -> should.fail()
  }
}
