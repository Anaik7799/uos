import cepaf_gleam/ha/homeostasis_evolution_engine as engine
import cepaf_gleam/ui/lustre/homeostasis_evolution_hud as hud
import cepaf_gleam/ui/tui/homeostasis_evolution_view as terminal
import cepaf_gleam/ui/wisp/agui_sse_api as sse
import cepaf_gleam/ui/wisp/router
import cepaf_gleam/fpp/homeostasis_fprime as fprime
import cepaf_gleam/ui/lustre/widgets/homeostasis_control as controls
import gleam/list
import gleam/string
import gleeunit/should
import lustre/element

pub fn initial_model_is_explicitly_simulated_in_hud_test() {
  let rendered = hud.render_hud(engine.init_homeostasis_system(0)) |> element.to_string
  string.contains(rendered, "SIMULATED") |> should.be_true()
  string.contains(rendered, "Status: ONLINE") |> should.be_false()
  string.contains(rendered, "18/18 Checks Validated") |> should.be_false()
}

pub fn initial_model_has_no_claimed_live_peers_in_tui_test() {
  let rendered = terminal.render(engine.init_homeostasis_system(0))
  string.contains(rendered, "SIMULATED") |> should.be_true()
  string.contains(rendered, "ONLINE") |> should.be_false()
}

pub fn unavailable_homeostasis_api_has_no_healthy_fallback_test() {
  let body = router.route("/api/v1/homeostasis?mode=test&scenario=unavailable")
  string.contains(body, "\"status\":\"unavailable\"") |> should.be_true()
  string.contains(body, "\"stable\":true") |> should.be_false()
}

pub fn status_stream_does_not_fabricate_observations_test() {
  let body = sse.homeostasis_telemetry_sse_stream()
  string.contains(body, "event: homeostasis_status\n") |> should.be_true()
  string.contains(body, "RATIFIED") |> should.be_false()
  string.contains(body, "\"status\":\"unavailable\"") |> should.be_true()
}

pub fn browser_event_handler_is_safe_and_handles_disconnect_test() {
  let rendered = hud.render_hud(engine.init_homeostasis_system(0)) |> element.to_string
  string.contains(rendered, "innerHTML") |> should.be_false()
  string.contains(rendered, "homeostasis_status") |> should.be_true()
  string.contains(rendered, "onerror") |> should.be_true()
}

fn context() {
  fprime.WiredContext(
    cpu_pct: 45.0, memory_pct: 55.0, latency_ms: 12.5, error_rate_pct: 0.01,
    heartbeat_age_ms: 650, fault_count: 0, lyapunov_v: 0.005,
    lyapunov_lambda: -0.15, quorum_votes: 4,
  )
}

pub fn invalid_negative_heartbeat_cannot_revalidate_handshake_test() {
  let ctx = fprime.WiredContext(..context(), heartbeat_age_ms: -1)
  fprime.evaluate_wired_guards(ctx)
  |> list.key_find("handshake_revalidated")
  |> should.equal(Ok(False))
  fprime.wired_watchdog_signal(ctx) |> should.equal("dead_timeout")
}

pub fn impossible_quorum_cannot_arm_evolution_test() {
  let ctx = fprime.WiredContext(..context(), quorum_votes: 5)
  fprime.evaluate_wired_guards(ctx)
  |> list.key_find("lyapunov_dissipative_and_quorum")
  |> should.equal(Ok(False))
}

pub fn threshold_widget_has_associated_labels_and_request_semantics_test() {
  let rendered = controls.view(fn(msg) { msg }) |> element.to_string
  string.contains(rendered, "for=\"homeostasis-cpu\"") |> should.be_true()
  string.contains(rendered, "id=\"homeostasis-cpu\"") |> should.be_true()
  string.contains(rendered, "Request equilibrium review") |> should.be_true()
}
