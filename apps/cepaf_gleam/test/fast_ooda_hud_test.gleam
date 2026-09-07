import cepaf_gleam/ui/lustre/fast_ooda_hud.{
  default_metrics, render_fast_ooda_hud,
}
import gleam/string
import gleeunit
import gleeunit/should
import lustre/element

pub fn main() {
  gleeunit.main()
}

pub fn default_metrics_test() {
  let m = default_metrics()
  { m.total_loop_ms <. 50.0 } |> should.be_true
  m.lyapunov_stable |> should.be_true
  m.solo5_vms_running |> should.equal(3)
}

pub fn render_fast_ooda_hud_html_test() {
  let m = default_metrics()
  let rendered = render_fast_ooda_hud(m)
  let html_str = element.to_string(rendered)

  // Verify key components exist in rendered HTML
  should.be_true(html_str != "")
  should.be_true(string.contains(html_str, "Fast OODA Cybernetic Convergence Cockpit"))
  should.be_true(string.contains(html_str, "25503L801736"))
  should.be_true(string.contains(html_str, "Comprehensive Verification Checklist"))
}
