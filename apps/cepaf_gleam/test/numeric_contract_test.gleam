import cepaf_gleam/ha/lyapunov_proof as stability
import cepaf_gleam/semantics/sheaf_cohomology as atlas
import gleam/list
import gleeunit/should

pub fn actual_finite_cocycle_is_not_exact_test() {
  should.be_true(atlas.cech_coboundary(0, 2, 4, 0.1) >. 0.0)
  let assert Ok(obs) = atlas.observe_cocycle(10, 0.1)
  atlas.observation_charts(obs) |> should.equal(10)
  atlas.observation_comparisons(obs) |> should.equal(1000)
  atlas.observation_sample(obs) |> should.equal(0.1)
  should.be_true(atlas.observation_residual(obs) >. 0.0)
  should.be_true(atlas.observation_residual(obs) <. atlas.residual_tolerance)
}

pub fn exact_positive_controls_test() {
  atlas.checked_transition(0, 1, 10.0) |> should.equal(Ok(20.0))
  atlas.checked_transition(1, 0, 20.0) |> should.equal(Ok(10.0))
  let assert Ok(obs) = atlas.observe_cocycle(1, -100.0)
  atlas.observation_comparisons(obs) |> should.equal(1)
  atlas.observation_residual(obs) |> should.equal(0.0)
}

pub fn every_domain_boundary_refused_test() {
  list.each([-100, -1, 10, 100], fn(i) {
    atlas.checked_transition(i, 0, 1.0) |> should.be_error
    atlas.checked_transition(0, i, 1.0) |> should.be_error
  })
  atlas.checked_transition(0, 1, 1.0e100) |> should.be_error
  atlas.checked_transition(0, 1, -1.0e100) |> should.be_error
  atlas.glue_global_section([]) |> should.be_error
  atlas.glue_global_section([#(0, 1.0), #(1, 3.0)]) |> should.be_error
}

pub fn compatible_section_observation_test() {
  atlas.glue_global_section([#(0, 10.0), #(1, 20.0), #(2, 30.0)])
  |> should.equal(Ok(10.0))
  atlas.glue_global_section([#(2, 30.0), #(1, 20.0), #(0, 10.0)])
  |> should.equal(Ok(10.0))
}

pub fn section_count_bound_test() {
  atlas.glue_global_section(list.repeat(#(0, 1.0), 10)) |> should.equal(Ok(1.0))
  atlas.glue_global_section(list.repeat(#(0, 1.0), 11)) |> should.be_error
}

pub fn measured_large_residual_is_refused_test() {
  atlas.verify_h1_vanishing(10, 1.0e12) |> should.be_error
}

pub fn finite_energy_equilibrium_controls_test() {
  list.each([0.0, 0.1, 0.5, 1.0], fn(x) {
    stability.checked_energy(x, x) |> should.equal(Ok(0.0))
  })
  stability.checked_energy(0.0, 1.0) |> should.equal(Ok(1.0))
  stability.checked_energy(-0.1, 1.0) |> should.be_error
  stability.checked_energy(1.1, 1.0) |> should.be_error
  stability.checked_energy(1.0e300, 1.0) |> should.be_error
}

pub fn finite_trajectory_and_refusal_test() {
  let assert Ok(s) = stability.checked_update(stability.init(), 0.8, 0.5, 1.0)
  s.samples |> should.equal(1)
  should.be_true(s.energy >=. 0.0 && s.energy <=. 1.0)
  stability.is_stable(s) |> should.be_true
  stability.checked_update(s, 0.8, 0.5, 0.0) |> should.be_error
  stability.checked_update(s, 0.8, 0.5, -1.0) |> should.be_error
  stability.checked_update(s, 0.8, 0.5, 1.0e100) |> should.be_error
  stability.checked_update(s, -1.0, 0.5, 1.0) |> should.be_error
}
