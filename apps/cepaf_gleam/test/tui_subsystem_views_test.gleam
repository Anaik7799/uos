//// apps/cepaf_gleam/test/tui_subsystem_views_test.gleam
//// System TUI 12 Specialized Subsystem Views Test Suite
//// STAMP: SC-GLM-UI-001, SC-GLM-UI-004

import gleeunit/should
import cepaf_gleam/testing/tui_test_engine.{
  all_subsystem_views, render_subsystem_view_buffer, verify_frame_buffer
}
import gleam/list

pub fn all_12_subsystem_views_render_test() {
  let views = all_subsystem_views()
  list.length(views) |> should.equal(12)

  let all_ok =
    list.all(views, fn(v) {
      let fb = render_subsystem_view_buffer(v)
      case verify_frame_buffer(fb) {
        Ok(len) -> len >= 30
        Error(_) -> False
      }
    })

  should.be_true(all_ok)
}
