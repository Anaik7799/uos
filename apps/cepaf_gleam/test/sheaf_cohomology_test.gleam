//// apps/cepaf_gleam/test/sheaf_cohomology_test.gleam
//// STAMP: SC-INTENT-ATLAS-001

import gleeunit/should
import cepaf_gleam/semantics/sheaf_cohomology.{
  transition_morphism, cech_coboundary, verify_h1_vanishing, glue_global_section
}

pub fn transition_morphism_identity_test() {
  let x = 42.0
  let res = transition_morphism(0, 0, x)
  should.be_true(res == x)
}

pub fn transition_morphism_inversion_test() {
  let x = 100.0
  let forward = transition_morphism(0, 5, x)
  let reverse = transition_morphism(5, 0, forward)
  let diff = reverse -. x
  let abs_diff = case diff <. 0.0 {
    True -> 0.0 -. diff
    False -> diff
  }
  should.be_true(abs_diff <. 0.0001)
}

pub fn cech_coboundary_vanishing_test() {
  let defect = cech_coboundary(0, 3, 7, 50.0)
  should.be_true(defect <. 0.0001)
}

pub fn sheaf_cohomology_h1_zero_test() {
  case verify_h1_vanishing(10, 88.8) {
    Ok(max_defect) -> {
      should.be_true(max_defect <. 0.0001)
    }
    Error(_err) -> {
      should.fail()
    }
  }
}

pub fn sheaf_global_section_gluing_test() {
  let local_sections = [
    #(0, 10.0),
    #(1, transition_morphism(0, 1, 10.0)),
    #(2, transition_morphism(0, 2, 10.0)),
    #(3, transition_morphism(0, 3, 10.0)),
    #(4, transition_morphism(0, 4, 10.0)),
  ]

  case glue_global_section(local_sections) {
    Ok(global_val) -> {
      let diff = global_val -. 10.0
      let abs_diff = case diff <. 0.0 {
        True -> 0.0 -. diff
        False -> diff
      }
      should.be_true(abs_diff <. 0.0001)
    }
    Error(_) -> should.fail()
  }
}
