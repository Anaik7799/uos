import cepaf_gleam/ui/lustre/gospel_z3_parity_explorer
import gleeunit/should

pub fn gospel_explorer_contract_count_test() {
  let explorer = gospel_z3_parity_explorer.build_canonical_explorer()
  should.be_true(gospel_z3_parity_explorer.contract_count(explorer) >= 5)
  should.equal(explorer.all_contracts_verified, True)
}

pub fn gospel_explorer_z3_solver_bounded_test() {
  let explorer = gospel_z3_parity_explorer.build_canonical_explorer()
  should.be_true(explorer.mean_z3_solve_time_ms <=. 150.0)
  should.equal(explorer.z3_timeouts_count, 0)
}

pub fn gospel_explorer_parsoid_roundtrip_test() {
  let explorer = gospel_z3_parity_explorer.build_canonical_explorer()
  should.equal(explorer.parsoid_roundtrip_fidelity, 1.0)
}
