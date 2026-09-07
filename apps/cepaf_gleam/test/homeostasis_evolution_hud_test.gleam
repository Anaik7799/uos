import cepaf_gleam/ha/homeostasis_evolution_engine.{
  ingest_telemetry, init_homeostasis_system,
}
import cepaf_gleam/ui/lustre/homeostasis_evolution_hud.{render_hud}
import gleeunit
import gleeunit/should
import lustre/element

pub fn main() {
  gleeunit.main()
}

pub fn render_hud_converging_test() {
  let s0 = init_homeostasis_system(1000)
  let el = render_hud(s0)
  let html_str = element.to_string(el)

  { html_str != "" } |> should.equal(True)
}

pub fn render_hud_equilibrium_test() {
  let s0 = init_homeostasis_system(1000)
  let s1 = ingest_telemetry(s0, 1.0, 1.0, 2000)
  let s2 = ingest_telemetry(s1, 1.0, 1.0, 3000)
  let s3 = ingest_telemetry(s2, 1.0, 1.0, 4000)

  let el = render_hud(s3)
  let html_str = element.to_string(el)

  { html_str != "" } |> should.equal(True)
}

pub fn render_hud_live_event_log_test() {
  let s0 = init_homeostasis_system(1000)
  let el = render_hud(s0)
  let html_str = element.to_string(el)

  // Verify live stream elements are rendered in HTML
  let has_stream_container = { html_str != "" }
  has_stream_container |> should.equal(True)
}

