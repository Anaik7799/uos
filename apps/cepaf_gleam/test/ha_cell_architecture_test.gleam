/// Cell Architecture tests — F39 (Cell-Based Blast Radius Isolation)
/// Layer: L6_ECOSYSTEM
/// SC-ULTRA-001 Focus 8: Continuous Stochastic Apoptosis
/// STAMP: SC-HA-001, SC-SIL4-015, SC-FUNC-003, SC-MUDA-001
///
/// बहूनि मे व्यतीतानि जन्मानि — Many births have passed (Gita 4.5)
import cepaf_gleam/ha/cell_architecture.{Contained, Spreading}
import gleam/list
import gleam/string
import gleeunit/should

// ---------------------------------------------------------------------------
// C1: init_grid — 8 cells, all healthy, none isolated
// ---------------------------------------------------------------------------

pub fn init_grid_has_8_cells_test() {
  let grid = cell_architecture.init_grid()
  grid.total_cells |> should.equal(8)
}

pub fn init_grid_all_healthy_test() {
  let grid = cell_architecture.init_grid()
  grid.healthy_cells |> should.equal(8)
}

pub fn init_grid_none_isolated_test() {
  let grid = cell_architecture.init_grid()
  grid.isolated_cells |> should.equal(0)
}

pub fn init_grid_blast_radius_contained_test() {
  let grid = cell_architecture.init_grid()
  grid.system_blast_radius |> should.equal(Contained)
}

pub fn init_grid_fully_healthy_test() {
  let grid = cell_architecture.init_grid()
  cell_architecture.is_fully_healthy(grid) |> should.be_true()
}

// ---------------------------------------------------------------------------
// C2: cell identifiers and layer names
// ---------------------------------------------------------------------------

pub fn init_grid_has_cell_l0_test() {
  let grid = cell_architecture.init_grid()
  let found = list.any(grid.cells, fn(c) { c.id == "cell-L0" })
  found |> should.be_true()
}

pub fn init_grid_has_cell_l7_test() {
  let grid = cell_architecture.init_grid()
  let found = list.any(grid.cells, fn(c) { c.id == "cell-L7" })
  found |> should.be_true()
}

pub fn cell_l0_has_no_dependencies_test() {
  let grid = cell_architecture.init_grid()
  let assert Ok(l0) = cell_architecture.find_cell(grid, "cell-L0")
  l0.dependencies |> should.equal([])
}

pub fn cell_l7_depends_on_l0_l5_l6_test() {
  let grid = cell_architecture.init_grid()
  let assert Ok(l7) = cell_architecture.find_cell(grid, "cell-L7")
  list.length(l7.dependencies) |> should.equal(3)
}

pub fn cell_l4_depends_on_l0_l3_test() {
  let grid = cell_architecture.init_grid()
  let assert Ok(l4) = cell_architecture.find_cell(grid, "cell-L4")
  list.contains(l4.dependencies, "cell-L0") |> should.be_true()
  list.contains(l4.dependencies, "cell-L3") |> should.be_true()
}

// ---------------------------------------------------------------------------
// C3: isolate_cell
// ---------------------------------------------------------------------------

pub fn isolate_cell_increments_isolated_count_test() {
  let grid =
    cell_architecture.init_grid()
    |> cell_architecture.isolate_cell("cell-L4")
  grid.isolated_cells |> should.equal(1)
}

pub fn isolate_cell_sets_isolated_flag_test() {
  let grid =
    cell_architecture.init_grid()
    |> cell_architecture.isolate_cell("cell-L4")
  let assert Ok(l4) = cell_architecture.find_cell(grid, "cell-L4")
  l4.isolated |> should.be_true()
}

pub fn isolate_cell_does_not_affect_others_test() {
  let grid =
    cell_architecture.init_grid()
    |> cell_architecture.isolate_cell("cell-L4")
  let assert Ok(l0) = cell_architecture.find_cell(grid, "cell-L0")
  l0.isolated |> should.be_false()
}

pub fn isolate_cell_blast_radius_stays_contained_test() {
  let grid =
    cell_architecture.init_grid()
    |> cell_architecture.isolate_cell("cell-L4")
  cell_architecture.blast_radius(grid) |> should.equal(Contained)
}

// ---------------------------------------------------------------------------
// C4: restore_cell
// ---------------------------------------------------------------------------

pub fn restore_cell_clears_isolated_flag_test() {
  let grid =
    cell_architecture.init_grid()
    |> cell_architecture.isolate_cell("cell-L3")
    |> cell_architecture.restore_cell("cell-L3")
  let assert Ok(l3) = cell_architecture.find_cell(grid, "cell-L3")
  l3.isolated |> should.be_false()
}

pub fn restore_cell_decrements_isolated_count_test() {
  let grid =
    cell_architecture.init_grid()
    |> cell_architecture.isolate_cell("cell-L3")
    |> cell_architecture.restore_cell("cell-L3")
  grid.isolated_cells |> should.equal(0)
}

// ---------------------------------------------------------------------------
// C5: mark_unhealthy / blast radius propagation
// ---------------------------------------------------------------------------

pub fn mark_unhealthy_reduces_healthy_count_test() {
  let grid =
    cell_architecture.init_grid()
    |> cell_architecture.mark_unhealthy("cell-L4")
  grid.healthy_cells |> should.equal(7)
}

pub fn mark_unhealthy_sets_spreading_test() {
  let grid =
    cell_architecture.init_grid()
    |> cell_architecture.mark_unhealthy("cell-L4")
  let assert Ok(l4) = cell_architecture.find_cell(grid, "cell-L4")
  l4.blast_radius |> should.equal(Spreading)
}

pub fn mark_unhealthy_propagates_to_dependent_test() {
  // L5 depends on L4; unhealthy L4 should mark L5 as Spreading
  let grid =
    cell_architecture.init_grid()
    |> cell_architecture.mark_unhealthy("cell-L4")
  let assert Ok(l5) = cell_architecture.find_cell(grid, "cell-L5")
  l5.blast_radius |> should.equal(Spreading)
}

pub fn system_blast_radius_spreading_when_unhealthy_test() {
  let grid =
    cell_architecture.init_grid()
    |> cell_architecture.mark_unhealthy("cell-L4")
  cell_architecture.blast_radius(grid) |> should.equal(Spreading)
}

pub fn mark_healthy_restores_count_test() {
  let grid =
    cell_architecture.init_grid()
    |> cell_architecture.mark_unhealthy("cell-L4")
    |> cell_architecture.mark_healthy("cell-L4")
  grid.healthy_cells |> should.equal(8)
}

// ---------------------------------------------------------------------------
// C6: active_failure_count
// ---------------------------------------------------------------------------

pub fn active_failure_count_zero_on_clean_grid_test() {
  let grid = cell_architecture.init_grid()
  cell_architecture.active_failure_count(grid) |> should.equal(0)
}

pub fn active_failure_count_increments_on_failure_test() {
  let grid =
    cell_architecture.init_grid()
    |> cell_architecture.mark_unhealthy("cell-L4")
  { cell_architecture.active_failure_count(grid) >= 1 } |> should.be_true()
}

// ---------------------------------------------------------------------------
// C7: to_json
// ---------------------------------------------------------------------------

pub fn to_json_contains_total_cells_test() {
  let j = cell_architecture.init_grid() |> cell_architecture.to_json()
  string.contains(j, "total_cells") |> should.be_true()
}

pub fn to_json_contains_cell_l0_test() {
  let j = cell_architecture.init_grid() |> cell_architecture.to_json()
  string.contains(j, "cell-L0") |> should.be_true()
}

pub fn to_json_contains_blast_radius_test() {
  let j = cell_architecture.init_grid() |> cell_architecture.to_json()
  string.contains(j, "blast_radius") |> should.be_true()
}

pub fn to_json_contained_when_healthy_test() {
  let j = cell_architecture.init_grid() |> cell_architecture.to_json()
  string.contains(j, "contained") |> should.be_true()
}

// ---------------------------------------------------------------------------
// C8: summary helper
// ---------------------------------------------------------------------------

pub fn summary_contains_healthy_count_test() {
  let s = cell_architecture.init_grid() |> cell_architecture.summary()
  string.contains(s, "8/8") |> should.be_true()
}

pub fn summary_contains_blast_radius_test() {
  let s = cell_architecture.init_grid() |> cell_architecture.summary()
  string.contains(s, "blast_radius") |> should.be_true()
}
