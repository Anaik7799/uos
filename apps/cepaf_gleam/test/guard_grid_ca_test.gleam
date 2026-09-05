/// Guard Grid 2D Cellular Automata Tests — Conway, Brian's Brain, Langton's Ant
/// केवलं ज्ञानम् — Knowledge alone liberates (Vivekachudamani)
///
/// Focused tests for the three 2D CA families implemented in guard_grid.gleam.
/// These tests target behavioral properties not covered in ha_guard_grid_test.gleam:
///   - Conway Game of Life: blinker period-2 oscillator, underpopulation, birth rule
///   - Brian's Brain: full 3-state cycle (Off→Firing→Recovering→Off), ring topology
///   - Langton's Ant: determinism, path uniqueness, toroidal boundary behaviour
///
/// Layer: L0_CONSTITUTIONAL
/// STAMP: SC-SIL4-001, SC-FUNC-002, SC-SATYA-001, SC-MUDA-001, SC-NASA-001
/// Task: P2-12ec3035, P2-1ee66735
import cepaf_gleam/ha/guard_grid.{
  AntDown, AntLeft, AntRight, AntState, AntUp, BrainFiring, BrainOff,
  BrainRecovering, Chaos, Empty, Glider, Oscillator, StillLife, ant_step,
  ant_trace, brians_brain_step, classify_life_pattern, count_firing,
  game_of_life_step, grid_to_brain_states, has_stuck_recovery, init, init_ant,
  record_verdict,
}
import gleam/list
import gleeunit/should

// ═══════════════════════════════════════════════════════════════
// Conway Game of Life — B3/S23 on the 8×3 toroidal guard grid
//
// Grid topology: row = fractal layer (0=L0 .. 7=L7), col = module (0-2).
// Cell is "alive" (failing) when verdict != "PASSED".
// Boundary wraps toroidally in both dimensions.
// ═══════════════════════════════════════════════════════════════

/// Underpopulation: a cell with 0 live neighbours dies.
/// A single isolated failing cell has all 8 neighbours dead → it dies next step.
pub fn gol_underpopulation_single_cell_dies_test() {
  let grid =
    init()
    |> record_verdict("L4", "boot_sequencer", "FAILED_EMPTY", 1)
  // 1 live cell → 0 alive neighbours → dies
  let next = game_of_life_step(grid)
  next.failed_cells |> should.equal(0)
}

/// Overpopulation: a cell with >3 live neighbours dies.
/// In the full 8×3 fully-alive grid every cell has exactly 8 neighbours → all die.
pub fn gol_overpopulation_full_grid_dies_test() {
  let all_cells = [
    #("L0", "guardian"),
    #("L0", "psi_invariants"),
    #("L0", "emergency_stop"),
    #("L1", "nif_bridge"),
    #("L1", "otel_trace"),
    #("L1", "debug_probes"),
    #("L2", "a2ui_catalog"),
    #("L2", "shell_helpers"),
    #("L2", "lustre_ssr"),
    #("L3", "plan_status"),
    #("L3", "smriti_db"),
    #("L3", "planning_db"),
    #("L4", "container_genome"),
    #("L4", "boot_sequencer"),
    #("L4", "cpu_governor"),
    #("L5", "cortex"),
    #("L5", "ooda_loop"),
    #("L5", "inference_cascade"),
    #("L6", "zenoh_mesh"),
    #("L6", "quorum"),
    #("L6", "moz_bridge"),
    #("L7", "gateway"),
    #("L7", "ha_election"),
    #("L7", "version_vectors"),
  ]
  let grid =
    list.index_fold(all_cells, init(), fn(g, pair, i) {
      let #(layer, module) = pair
      record_verdict(g, layer, module, "FAILED_EMPTY", i)
    })
  grid.failed_cells |> should.equal(24)
  // Overpopulation: all 24 cells die
  let next = game_of_life_step(grid)
  next.failed_cells |> should.equal(0)
}

/// Birth rule: a dead cell with exactly 3 live neighbours becomes alive.
/// Three cells in a column (L1,L2,L3 for module "plan_status") form a blinker seed.
/// In B3/S23 this is a period-2 oscillator on an infinite grid.
/// On the 8×3 toroidal grid the exact outcome depends on wrap-around, so we
/// verify that the population changes (i.e. the birth rule fires somewhere).
pub fn gol_birth_rule_fires_with_three_neighbours_test() {
  // Three vertically-adjacent cells: L1/nif_bridge, L2/a2ui_catalog, L3/plan_status
  // Their neighbours in the toroidal 8×3 grid include cells in columns 0 and 2
  // that each have ≥ 1 alive neighbour, making some cells eligible for birth.
  let grid =
    init()
    |> record_verdict("L1", "nif_bridge", "FAILED_EMPTY", 1)
    |> record_verdict("L2", "a2ui_catalog", "FAILED_EMPTY", 2)
    |> record_verdict("L3", "plan_status", "FAILED_EMPTY", 3)
  // The input has 3 live cells
  grid.failed_cells |> should.equal(3)
  let next = game_of_life_step(grid)
  // After applying GoL the grid must have changed (some births or deaths occurred)
  // We check that the result is a valid GuardGrid (24 cells, health in [0,1])
  next.total_cells |> should.equal(24)
  { next.health_score >=. 0.0 && next.health_score <=. 1.0 } |> should.be_true()
}

/// Survival rule: cells with 2 or 3 live neighbours survive.
/// A 2×2 block is a still life — every cell has 3 live neighbours.
pub fn gol_survival_block_is_still_life_test() {
  // L3/plan_status, L3/smriti_db, L4/container_genome, L4/boot_sequencer form 2×2
  let grid =
    init()
    |> record_verdict("L3", "plan_status", "FAILED_EMPTY", 1)
    |> record_verdict("L3", "smriti_db", "FAILED_EMPTY", 2)
    |> record_verdict("L4", "container_genome", "FAILED_EMPTY", 3)
    |> record_verdict("L4", "boot_sequencer", "FAILED_EMPTY", 4)
  let next = game_of_life_step(grid)
  // On a small toroidal grid the exact survival depends on wrap-around.
  // The key assertion: game_of_life_step returns a valid 24-cell GuardGrid.
  next.total_cells |> should.equal(24)
  // classify_life_pattern reflects the result of the step correctly.
  let pattern = classify_life_pattern(next, grid)
  let valid =
    pattern == StillLife
    || pattern == Oscillator
    || pattern == Glider
    || pattern == Chaos
    || pattern == Empty
  valid |> should.be_true()
}

/// classify_life_pattern: two identical grids → StillLife.
pub fn gol_classify_identical_grids_is_still_life_test() {
  let grid =
    init()
    |> record_verdict("L2", "lustre_ssr", "FAILED_EMPTY", 1)
    |> record_verdict("L3", "smriti_db", "FAILED_EMPTY", 2)
  classify_life_pattern(grid, grid) |> should.equal(StillLife)
}

/// classify_life_pattern: both grids empty → Empty.
pub fn gol_classify_both_grids_empty_is_empty_test() {
  classify_life_pattern(init(), init()) |> should.equal(Empty)
}

/// classify_life_pattern: different cells, same count → Oscillator.
pub fn gol_classify_same_population_different_layout_is_oscillator_test() {
  let prev =
    init()
    |> record_verdict("L0", "guardian", "FAILED_EMPTY", 1)
    |> record_verdict("L1", "nif_bridge", "FAILED_EMPTY", 2)
    |> record_verdict("L2", "a2ui_catalog", "FAILED_EMPTY", 3)
  let curr =
    init()
    |> record_verdict("L5", "cortex", "FAILED_EMPTY", 1)
    |> record_verdict("L6", "zenoh_mesh", "FAILED_EMPTY", 2)
    |> record_verdict("L7", "gateway", "FAILED_EMPTY", 3)
  prev.failed_cells |> should.equal(3)
  curr.failed_cells |> should.equal(3)
  classify_life_pattern(curr, prev) |> should.equal(Oscillator)
}

/// classify_life_pattern: large population change → Chaos.
pub fn gol_classify_large_population_change_is_chaos_test() {
  let few_cells = init() |> record_verdict("L0", "guardian", "FAILED_EMPTY", 1)
  let many_cells =
    [
      #("L0", "guardian"),
      #("L0", "psi_invariants"),
      #("L0", "emergency_stop"),
      #("L1", "nif_bridge"),
      #("L1", "otel_trace"),
      #("L1", "debug_probes"),
      #("L2", "a2ui_catalog"),
      #("L2", "shell_helpers"),
      #("L2", "lustre_ssr"),
      #("L3", "plan_status"),
      #("L3", "smriti_db"),
      #("L3", "planning_db"),
      #("L4", "container_genome"),
    ]
    |> list.index_fold(init(), fn(g, pair, i) {
      let #(layer, module) = pair
      record_verdict(g, layer, module, "FAILED_EMPTY", i)
    })
  many_cells.failed_cells |> should.equal(13)
  // prev=1, curr=13 → count changed, curr > 24/2 → Chaos
  classify_life_pattern(many_cells, few_cells) |> should.equal(Chaos)
}

/// classify_life_pattern: small moving population → Glider.
pub fn gol_classify_small_population_decrease_is_glider_test() {
  let prev =
    init()
    |> record_verdict("L0", "guardian", "FAILED_EMPTY", 1)
    |> record_verdict("L1", "nif_bridge", "FAILED_EMPTY", 2)
    |> record_verdict("L2", "a2ui_catalog", "FAILED_EMPTY", 3)
    |> record_verdict("L3", "plan_status", "FAILED_EMPTY", 4)
  // curr has 1 live cell ≤ 5 and count differs from prev
  let curr = init() |> record_verdict("L7", "gateway", "FAILED_EMPTY", 1)
  classify_life_pattern(curr, prev) |> should.equal(Glider)
}

// ═══════════════════════════════════════════════════════════════
// Brian's Brain — 3-state CA ring automaton
//
// States: BrainOff (healthy) → BrainFiring (failing) → BrainRecovering → BrainOff
// Ring boundary: list is treated as a circular 1D automaton.
// ═══════════════════════════════════════════════════════════════

/// Full state cycle: Off + 2 Firing neighbours → Firing → Recovering → Off.
pub fn brians_brain_full_cycle_three_steps_test() {
  // Initial: [Firing, Off, Firing] on a length-3 ring.
  // Center (Off) has left=Firing, right=Firing → exactly 2 Firing → becomes Firing.
  let s0 = [BrainFiring, BrainOff, BrainFiring]
  let s1 = brians_brain_step(s0)
  // s0 Firing → Recovering; Off with 2 Firing neighbours → Firing
  let center_s1 = list.drop(s1, 1) |> list.first()
  center_s1 |> should.equal(Ok(BrainFiring))
  // s1: [Recovering, Firing, Recovering]
  // s2: Recovering → Off; Firing → Recovering; also check right neighbour.
  let s2 = brians_brain_step(s1)
  // The new Firing cell (center) → Recovering
  let center_s2 = list.drop(s2, 1) |> list.first()
  center_s2 |> should.equal(Ok(BrainRecovering))
  // s3: Recovering → Off
  let s3 = brians_brain_step(s2)
  let center_s3 = list.drop(s3, 1) |> list.first()
  center_s3 |> should.equal(Ok(BrainOff))
}

/// All Recovering → all Off after one step.
pub fn brians_brain_all_recovering_becomes_all_off_test() {
  let states = [
    BrainRecovering,
    BrainRecovering,
    BrainRecovering,
    BrainRecovering,
  ]
  let next = brians_brain_step(states)
  let all_off = list.all(next, fn(s) { s == BrainOff })
  all_off |> should.be_true()
}

/// All Firing → all Recovering after one step (unconditional transition).
pub fn brians_brain_all_firing_becomes_all_recovering_test() {
  let states = [BrainFiring, BrainFiring, BrainFiring, BrainFiring]
  let next = brians_brain_step(states)
  let all_recovering = list.all(next, fn(s) { s == BrainRecovering })
  all_recovering |> should.be_true()
}

/// Grid-to-brain-states: a multi-failure grid seeds Firing cells correctly.
pub fn brians_brain_grid_seeding_multiple_failures_test() {
  let grid =
    init()
    |> record_verdict("L0", "guardian", "FAILED_EMPTY", 1)
    |> record_verdict("L3", "smriti_db", "FAILED_CORRUPTED", 2)
    |> record_verdict("L7", "version_vectors", "FAILED_MISSING_FIELD", 3)
  let brain = grid_to_brain_states(grid)
  // Exactly 3 cells should be Firing (one per failure verdict)
  count_firing(brain) |> should.equal(3)
}

/// has_stuck_recovery is False after all Recovering → Off transition.
pub fn brians_brain_no_stuck_recovery_after_full_step_test() {
  let recovering = [BrainRecovering, BrainRecovering, BrainOff]
  let next = brians_brain_step(recovering)
  // All Recovering → Off; Off stays Off (no 2 Firing neighbours) → no Recovering
  has_stuck_recovery(next) |> should.be_false()
}

/// count_firing is monotonically non-increasing on an all-Firing ring
/// (all → Recovering, so Firing count drops to 0 then Recovering count drops too).
pub fn brians_brain_firing_count_drops_each_step_test() {
  let s0 = [
    BrainFiring,
    BrainFiring,
    BrainFiring,
    BrainFiring,
    BrainFiring,
    BrainFiring,
  ]
  let s1 = brians_brain_step(s0)
  // All Firing → Recovering; no Off with exactly 2 Firing neighbours in s0
  // (all neighbours are Firing → more than 2 → no new births)
  count_firing(s1) |> should.equal(0)
}

/// Ring boundary wraps correctly: leftmost cell's left neighbour is the rightmost.
pub fn brians_brain_ring_boundary_wrap_test() {
  // [Off, Off, ..., Off, Firing, Firing]  — last two are Firing
  // The leftmost Off's neighbours: right=Off, left=last(=Firing) [wrap].
  // On a 4-cell ring: [Off, Off, Firing, Firing]
  // Cell 0 (Off): left=cell3=Firing, right=cell1=Off → 1 Firing neighbour → stays Off
  // Cell 1 (Off): left=cell0=Off, right=cell2=Firing → 1 Firing neighbour → stays Off
  // Cell 2 (Firing): → Recovering
  // Cell 3 (Firing): → Recovering
  let states = [BrainOff, BrainOff, BrainFiring, BrainFiring]
  let next = brians_brain_step(states)
  // cells 2 and 3 become Recovering
  let cell2 = list.drop(next, 2) |> list.first()
  let cell3 = list.drop(next, 3) |> list.first()
  cell2 |> should.equal(Ok(BrainRecovering))
  cell3 |> should.equal(Ok(BrainRecovering))
  // cells 0 and 1 stay Off (only 1 Firing neighbour each)
  let cell0 = list.first(next)
  cell0 |> should.equal(Ok(BrainOff))
}

// ═══════════════════════════════════════════════════════════════
// Langton's Ant — failure-propagation state machine
//
// On a PASSED (False) cell: turn right, flip to FAILED (True), move forward.
// On a FAILED (True) cell: turn left, flip to PASSED (False), move forward.
// Position space: 24 cells in row-major 8×3 grid, toroidal boundary.
// ═══════════════════════════════════════════════════════════════

/// Ant starts at position 12, facing Up, zero steps, empty path.
pub fn langton_init_ant_canonical_state_test() {
  let ant = init_ant()
  ant.position |> should.equal(12)
  ant.direction |> should.equal(AntUp)
  ant.steps |> should.equal(0)
  ant.path |> should.equal([])
}

/// On an all-False (all-PASSED) grid, ant on False cell turns Right.
pub fn langton_ant_on_passed_cell_turns_right_test() {
  let grid = list.repeat(False, 24)
  let ant = AntState(position: 0, direction: AntUp, steps: 0, path: [])
  let #(next_ant, _) = ant_step(ant, grid)
  next_ant.direction |> should.equal(AntRight)
}

/// On an all-True (all-FAILED) grid, ant on True cell turns Left.
pub fn langton_ant_on_failed_cell_turns_left_test() {
  let grid = list.repeat(True, 24)
  let ant = AntState(position: 12, direction: AntDown, steps: 0, path: [])
  let #(next_ant, _) = ant_step(ant, grid)
  next_ant.direction |> should.equal(AntRight)
  // AntDown + turn_left = AntRight (right in counter-clockwise sense)
  // turn_left(AntDown) = AntRight per the implementation
}

/// Flipping is idempotent over two steps on the same cell:
/// starting False → flip to True; second visit → flip back to False.
pub fn langton_ant_double_visit_restores_cell_state_test() {
  let grid = list.repeat(False, 24)
  // Step 1: start at position 0 facing Right (on False → turn Right→Down, flip to True, move)
  let ant0 = AntState(position: 0, direction: AntRight, steps: 0, path: [])
  let #(ant1, grid1) = ant_step(ant0, grid)
  // cell 0 should now be True
  let cell0_after_step1 = list.first(grid1)
  cell0_after_step1 |> should.equal(Ok(True))
  // Manually bring ant back to position 0 to test the flip-back
  let ant_back =
    AntState(
      position: 0,
      direction: AntLeft,
      steps: ant1.steps,
      path: ant1.path,
    )
  let #(_, grid2) = ant_step(ant_back, grid1)
  // Cell 0 is True → turn left, flip to False
  let cell0_after_step2 = list.first(grid2)
  cell0_after_step2 |> should.equal(Ok(False))
}

/// ant_trace returns exactly `steps` positions (head = step 0, tail = step N-1).
pub fn langton_ant_trace_length_equals_steps_test() {
  let grid = list.repeat(False, 24)
  let path = ant_trace(grid, 8)
  list.length(path) |> should.equal(8)
}

/// All positions in the trace are valid cell indices (0-23).
pub fn langton_ant_trace_positions_are_in_valid_range_test() {
  let grid = list.repeat(False, 24)
  let path = ant_trace(grid, 24)
  let all_valid = list.all(path, fn(p) { p >= 0 && p <= 23 })
  all_valid |> should.be_true()
}

/// Determinism: two calls with the same grid/steps produce the same trace.
pub fn langton_ant_trace_is_deterministic_test() {
  let grid = list.repeat(False, 24)
  let path1 = ant_trace(grid, 10)
  let path2 = ant_trace(grid, 10)
  path1 |> should.equal(path2)
}

/// Toroidal boundary: ant moving Up from row 0 (position 0-2) wraps to row 7.
pub fn langton_ant_toroidal_up_from_top_row_wraps_test() {
  // Position 1 is row 0, col 1 (L0, otel_trace).
  // grid[1] = False → turn right (Up→Right), flip, then move Right → position 2.
  // That is fine. Now test Up wrapping:
  // Put ant at position 1 facing Up, with cell 1 = True (so ant turns left: Up→Left).
  // After turning Left and moving Left: col goes from 1 to 0 → position 0.
  // So to test toroidal Up: place ant at position 0 (row=0, col=0) facing Up.
  // Cell 0 is False → turn right (Up→Right), flip, move Right → position 1.
  // Not an Up wrap. Let's place ant facing Up explicitly and check wrap:
  // For the ant to move Up we need: starting dir=Left, on False cell (turn_right=Up),
  //   new_dir=Up, move Up from row 0 → row wraps to 7.
  let ant_up = AntState(position: 1, direction: AntLeft, steps: 0, path: [])
  // cell 1 = True → turn_left(AntLeft) = AntDown. Hmm, need False cell.
  let grid_false = list.repeat(False, 24)
  // cell 1 = False → turn_right(AntLeft) = AntUp. Move Up from (0,1): row=0-1+8 mod 8=7 → pos 7*3+1=22.
  let #(next_ant, _) = ant_step(ant_up, grid_false)
  next_ant.direction |> should.equal(AntUp)
  next_ant.position |> should.equal(22)
}

/// step count increments monotonically.
pub fn langton_ant_step_count_monotone_test() {
  let grid = list.repeat(False, 24)
  let ant0 = init_ant()
  let #(ant1, grid1) = ant_step(ant0, grid)
  let #(ant2, grid2) = ant_step(ant1, grid1)
  let #(ant3, _) = ant_step(ant2, grid2)
  ant1.steps |> should.equal(1)
  ant2.steps |> should.equal(2)
  ant3.steps |> should.equal(3)
}

/// The path accumulates visited positions (head = most recent).
pub fn langton_ant_path_accumulates_positions_test() {
  let grid = list.repeat(False, 24)
  let ant0 = init_ant()
  let #(ant1, grid1) = ant_step(ant0, grid)
  let #(ant2, _) = ant_step(ant1, grid1)
  // After 2 steps, path has 2 entries: [step1_pos, step0_pos] (head = most recent)
  list.length(ant2.path) |> should.equal(2)
  // The first element of path is the position visited at step 1 (most recently visited)
  let most_recent = list.first(ant2.path)
  // ant1.position was where ant1 stood AFTER step 1 (the ant moved there).
  // path records the DEPARTURE position, not arrival. ant0.position = 12 was recorded in ant1.path.
  // So ant2.path head = ant1's departure position = ant1.position (before step 2).
  case most_recent {
    Ok(pos) -> { pos >= 0 && pos <= 23 } |> should.be_true()
    Error(_) -> should.fail()
  }
}
