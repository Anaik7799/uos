import cepaf_gleam/ui/lustre/sovereign_tensor_cockpit
import gleeunit/should

pub fn tensor_dimension_count_test() {
  let cockpit = sovereign_tensor_cockpit.build_canonical_cockpit()
  sovereign_tensor_cockpit.dimension_count(cockpit)
  |> should.equal(10)
}

pub fn tensor_overall_health_test() {
  let cockpit = sovereign_tensor_cockpit.build_canonical_cockpit()
  should.equal(cockpit.overall_health, 1.0)
  should.be_true(cockpit.all_dimensions_green)
}
