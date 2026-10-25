import cepaf_gleam/semantics/sheaf_cohomology as atlas
import gleeunit/should

pub fn empty_chart_count_refused_test() {
  atlas.verify_h1_vanishing(0, 1.0) |> should.be_error
}

pub fn negative_chart_count_refused_test() {
  atlas.verify_h1_vanishing(-1, 1.0) |> should.be_error
}

pub fn oversized_chart_count_refused_test() {
  atlas.verify_h1_vanishing(11, 1.0) |> should.be_error
}

pub fn invalid_section_chart_refused_test() {
  atlas.glue_global_section([#(-1, 1.0)]) |> should.be_error
}

pub fn consistent_duplicate_section_is_compatible_test() {
  atlas.glue_global_section([#(0, 1.0), #(0, 1.0)]) |> should.equal(Ok(1.0))
}

pub fn oversized_sample_refused_test() {
  atlas.verify_h1_vanishing(1, 1.0e100) |> should.be_error
}
