import cepaf_gleam/metabolic/service
import gleeunit/should

pub fn metabolic_scaling_base_test() {
  // Energy = 100, CPU = 50%
  // BaseRate = 100 * 0.8 = 80
  // CPU < 0.95 -> 80
  service.calculate_metabolic_set_point(100.0, 0.5)
  |> should.equal(80.0)
}

pub fn metabolic_scaling_redline_test() {
  // Energy = 100, CPU = 96%
  // BaseRate = 100 * 0.8 = 80
  // CPU > 0.95 -> 80 * 0.5 = 40
  service.calculate_metabolic_set_point(100.0, 0.96)
  |> should.equal(40.0)
}

pub fn metabolic_scaling_zero_energy_test() {
  service.calculate_metabolic_set_point(0.0, 0.5)
  |> should.equal(0.0)
}

pub fn metabolic_scaling_high_cpu_test() {
  // Energy = 50, CPU = 100%
  // BaseRate = 50 * 0.8 = 40
  // CPU > 0.95 -> 40 * 0.5 = 20
  service.calculate_metabolic_set_point(50.0, 1.0)
  |> should.equal(20.0)
}
