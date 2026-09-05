import cepaf_gleam/verification/ocaml_differential_oracle.{
  GospelContractSpec, ParityMatch, ParityMismatch,
  evaluate_all_subsystem_mappings, evaluate_parity, verify_gospel_contract,
}
import gleeunit/should

pub fn parity_matching_test() {
  let verdict = evaluate_parity("expected_sha256_hash", "expected_sha256_hash")
  should.equal(verdict, ParityMatch)
}

pub fn parity_mismatching_test() {
  let verdict = evaluate_parity("expected_sha256_hash", "different_hash")
  should.equal(verdict, ParityMismatch)
}

pub fn gospel_contract_verification_test() {
  let contract =
    GospelContractSpec(
      module_name: "Hermes_wiki",
      precondition: fn() { True },
      postcondition: fn() { True },
    )
  should.equal(verify_gospel_contract(contract), True)
}

pub fn ocaml_subsystem_432_mapping_test() {
  let eval = evaluate_all_subsystem_mappings(432)
  should.equal(eval.total_files_mapped, 432)
  should.equal(eval.parity_pass, True)
}
