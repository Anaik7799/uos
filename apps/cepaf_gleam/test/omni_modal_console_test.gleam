import cepaf_gleam/ui/lustre/omni_modal_console
import gleeunit/should

pub fn console_shortcuts_count_test() {
  let console = omni_modal_console.build_canonical_console()
  should.be_true(omni_modal_console.shortcuts_count(console) >= 6)
}

pub fn console_aria_live_status_test() {
  let console = omni_modal_console.build_canonical_console()
  should.equal(console.aria_live_mode, "polite")
  should.equal(console.screen_reader_ready, True)
}

pub fn console_telemetry_nodes_test() {
  let console = omni_modal_console.build_canonical_console()
  should.be_true(console.mean_tailnet_latency_ms <=. 20.0)
  should.be_true(omni_modal_console.nodes_count(console) >= 3)
}
