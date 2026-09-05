import cepaf_gleam/testing/fractal_matrix
import gleam/list
import gleeunit/should

// =============================================================================
// Fractal Matrix Regression Tests (10 tests)
// =============================================================================

pub fn all_pages_returns_15_test() {
  fractal_matrix.all_pages() |> list.length |> should.equal(15)
}

pub fn page_count_returns_15_test() {
  fractal_matrix.page_count() |> should.equal(15)
}

pub fn rust_tab_count_returns_12_test() {
  fractal_matrix.rust_tab_count() |> should.equal(12)
}

pub fn bdd_level_count_returns_7_test() {
  fractal_matrix.bdd_level_count() |> should.equal(7)
}

pub fn enumerate_all_tab_elements_returns_15_inventories_test() {
  fractal_matrix.enumerate_all_tab_elements()
  |> list.length
  |> should.equal(15)
}

pub fn total_element_count_positive_test() {
  let count = fractal_matrix.total_element_count()
  { count > 0 } |> should.equal(True)
}

pub fn total_bdd_cells_positive_test() {
  let cells = fractal_matrix.total_bdd_cells()
  { cells > 0 } |> should.equal(True)
}

pub fn bdd_level_matrix_non_empty_test() {
  let matrix = fractal_matrix.bdd_level_matrix()
  { matrix != [] } |> should.equal(True)
}

pub fn matrix_coverage_positive_test() {
  let coverage = fractal_matrix.matrix_coverage()
  { coverage >. 0.0 } |> should.equal(True)
}

pub fn monitoring_plan_has_15_entries_test() {
  fractal_matrix.monitoring_plan() |> list.length |> should.equal(15)
}
