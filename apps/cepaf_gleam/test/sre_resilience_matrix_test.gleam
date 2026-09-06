import cepaf_gleam/ui/lustre/sre_resilience_matrix
import gleeunit/should

pub fn circuit_breaker_state_test() {
  let sre = sre_resilience_matrix.build_canonical_sre()
  sre.circuit_breaker_state
  |> should.equal(sre_resilience_matrix.BreakerClosed)
}

pub fn freshness_monitor_test() {
  let sre = sre_resilience_matrix.build_canonical_sre()
  sre.freshness_level
  |> should.equal(sre_resilience_matrix.Fresh)
}

pub fn lyapunov_decay_rate_test() {
  let sre = sre_resilience_matrix.build_canonical_sre()
  should.be_true(sre.lyapunov_lambda <=. -0.05)
}
