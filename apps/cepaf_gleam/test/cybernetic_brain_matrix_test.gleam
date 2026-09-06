import cepaf_gleam/ui/lustre/cybernetic_brain_matrix
import gleeunit/should

pub fn brain_matrix_tensor_dimensions_test() {
  let matrix = cybernetic_brain_matrix.build_canonical_brain()
  should.equal(cybernetic_brain_matrix.dimension_count(matrix), 10)
  should.be_true(matrix.composite_tensor_score >=. 0.99)
}

pub fn brain_matrix_sovereign_ratification_test() {
  let matrix = cybernetic_brain_matrix.build_canonical_brain()
  should.equal(matrix.tri_sovereign_consensus, True)
  should.equal(matrix.all_18_checks_green, True)
}

pub fn brain_matrix_subsystem_saturation_test() {
  let matrix = cybernetic_brain_matrix.build_canonical_brain()
  should.be_true(matrix.total_features_cataloged >= 186)
  should.be_true(matrix.total_gleam_tests >= 9966)
}
