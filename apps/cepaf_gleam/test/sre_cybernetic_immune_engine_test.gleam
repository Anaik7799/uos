import cepaf_gleam/ui/lustre/sre_cybernetic_immune_engine
import gleeunit/should

pub fn immune_engine_self_healing_rate_test() {
  let engine = sre_cybernetic_immune_engine.build_canonical_engine()
  should.be_true(engine.self_healing_rate >=. 0.95)
  should.be_true(engine.active_antibodies_count >= 4)
}

pub fn immune_engine_phase_space_stability_test() {
  let engine = sre_cybernetic_immune_engine.build_canonical_engine()
  should.be_true(engine.lyapunov_gradient <=. -0.05)
  should.equal(engine.phase_trajectory_converged, True)
}

pub fn immune_engine_antibody_synthesis_test() {
  let ab = sre_cybernetic_immune_engine.synthesize_antibody("ANOM_CLOCK_DRIFT_01")
  should.equal(ab.target_anomaly, "ANOM_CLOCK_DRIFT_01")
  should.be_true(ab.neutralization_potency >=. 0.99)
}
