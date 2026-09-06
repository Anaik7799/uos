import cepaf_gleam/ui/lustre/recursive_patrol_hud
import gleeunit/should

pub fn patrol_hud_cycle_execution_test() {
  let hud = recursive_patrol_hud.init_hud()
  let completed = recursive_patrol_hud.run_all_four_cycles(hud)
  completed.cycle1_passed |> should.be_true()
  completed.cycle2_passed |> should.be_true()
  completed.cycle3_passed |> should.be_true()
  completed.cycle4_passed |> should.be_true()
  completed.all_cycles_green |> should.be_true()
}

pub fn patrol_hud_checklist_verification_test() {
  let hud = recursive_patrol_hud.init_hud()
  let completed = recursive_patrol_hud.run_all_four_cycles(hud)
  should.equal(completed.checklist_points_passed, 18)
}

pub fn patrol_hud_otel_telemetry_test() {
  let hud = recursive_patrol_hud.init_hud()
  let span = recursive_patrol_hud.emit_hud_otel_span(hud)
  should.equal(span.layer, "L5_COGNITIVE")
  should.equal(span.status, "OK")
}
