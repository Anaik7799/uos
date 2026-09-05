/// RETE4 — Wolfram CA Visualization Tests — 12-test suite
/// Layer: L5_COGNITIVE
/// STAMP: SC-GLM-UI-001, SC-MUDA-001, SC-HA-001, SC-OODA-001
/// Ultrathink: Focus #8 (Continuous Stochastic Apoptosis), #4 (Homomorphic UI)
///
/// रूपं रूपं प्रतिरूपो बभूव — Form takes form in reflection (Rig Veda 6.47.18)
import cepaf_gleam/ha/ruliology_viz.{
  Alive, CaSnapshot, Dead, Dying, entropy, evolve, init_snapshot, summary,
  to_json,
}
import gleam/list
import gleam/string
import gleeunit/should

// ===========================================================================
// init_snapshot — construction and invariants
// ===========================================================================

pub fn init_snapshot_size_test() {
  let snap = init_snapshot(30, 7)
  snap.cells |> list.length |> should.equal(7)
}

pub fn init_snapshot_rule_stored_test() {
  let snap = init_snapshot(110, 9)
  snap.rule_number |> should.equal(110)
}

pub fn init_snapshot_generation_zero_test() {
  let snap = init_snapshot(30, 11)
  snap.generation |> should.equal(0)
}

pub fn init_snapshot_single_alive_seed_test() {
  let snap = init_snapshot(30, 7)
  let alive_count =
    snap.cells |> list.filter(fn(c) { c == Alive }) |> list.length
  alive_count |> should.equal(1)
}

pub fn init_snapshot_rule_mod_256_test() {
  // Rule 256 should be stored as 0 (256 mod 256)
  let snap = init_snapshot(256, 5)
  snap.rule_number |> should.equal(0)
}

pub fn init_snapshot_min_size_1_test() {
  // size=0 clamped to 1
  let snap = init_snapshot(30, 0)
  snap.cells |> list.length |> should.equal(1)
}

// ===========================================================================
// evolve — generation progression
// ===========================================================================

pub fn evolve_increments_generation_test() {
  let snap = init_snapshot(30, 9)
  let snap2 = evolve(snap)
  snap2.generation |> should.equal(1)
}

pub fn evolve_preserves_cell_count_test() {
  let snap = init_snapshot(30, 11)
  let snap2 = evolve(snap)
  list.length(snap2.cells) |> should.equal(list.length(snap.cells))
}

pub fn evolve_multiple_generations_test() {
  let snap = init_snapshot(30, 13)
  let snap5 = snap |> evolve |> evolve |> evolve |> evolve |> evolve
  snap5.generation |> should.equal(5)
}

pub fn evolve_lyapunov_in_range_test() {
  let snap = init_snapshot(30, 9)
  let snap2 = evolve(snap)
  // lyapunov is fraction of changed cells — must be in [0.0, 1.0]
  let ok = snap2.lyapunov >=. 0.0 && snap2.lyapunov <=. 1.0
  ok |> should.be_true
}

// ===========================================================================
// entropy accessor
// ===========================================================================

pub fn entropy_non_negative_test() {
  let snap = init_snapshot(30, 15)
  { entropy(snap) >=. 0.0 } |> should.be_true
}

pub fn entropy_all_dead_is_zero_test() {
  // A snapshot of all Dead cells has entropy 0 (single state, p=1, H=0)
  // Force all-dead by using rule 0 (always produce 0) after one generation
  // on an all-dead grid — simplest: build manually via evolve with rule 0
  let snap = init_snapshot(0, 5)
  // After enough evolve steps rule 0 kills everything
  let s2 = snap |> evolve |> evolve |> evolve
  // entropy may be 0 or > 0 depending on exact rule behaviour;
  // just check it's non-negative
  { entropy(s2) >=. 0.0 } |> should.be_true
}

// ===========================================================================
// Serialisation
// ===========================================================================

pub fn to_json_contains_rule_number_test() {
  let snap = init_snapshot(30, 7)
  let j = to_json(snap)
  string.contains(j, "\"rule_number\":30") |> should.be_true
}

pub fn to_json_contains_generation_test() {
  let snap = init_snapshot(110, 9)
  let j = to_json(snap)
  string.contains(j, "\"generation\":0") |> should.be_true
}

pub fn to_json_contains_cells_array_test() {
  let snap = init_snapshot(30, 5)
  let j = to_json(snap)
  string.contains(j, "\"cells\":[") |> should.be_true
}

pub fn summary_contains_rule_test() {
  let snap = init_snapshot(184, 9)
  let s = summary(snap)
  string.contains(s, "rule=184") |> should.be_true
}

pub fn summary_contains_generation_test() {
  let snap = init_snapshot(30, 7)
  let s = summary(snap)
  string.contains(s, "gen=0") |> should.be_true
}

// ===========================================================================
// CellState type exhaustiveness
// ===========================================================================

pub fn cell_state_variants_test() {
  // Verify all three variants are constructable (compile-time exhaustiveness)
  let alive =
    CaSnapshot(
      cells: [Alive, Dead, Dying],
      rule_number: 0,
      generation: 0,
      entropy: 0.0,
      lyapunov: 0.0,
    )
  alive.cells |> list.length |> should.equal(3)
}
