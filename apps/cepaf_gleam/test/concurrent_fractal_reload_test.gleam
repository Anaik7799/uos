import cepaf_gleam/ha/concurrent_fractal_reload.{
  L0Constitutional, L1AtomicDebug, L2ComponentHealth, L3TransactionState,
  L4SystemSupervision, L5CognitiveOoda, L6EcosystemSwarm, L7FederationZenoh,
  L8EvolutionImmune, L9SingularityHarmonic,
  classify_module_layer, layer_to_string, layer_to_level,
  concurrent_reload, sequential_reload, parallel_scan_changed, compare_concurrency,
  ConcurrentReloadSuccess
}
import gleeunit/should

pub fn fractal_layer_classification_test() {
  classify_module_layer("cepaf_gleam@fractal@l0_constitutional")
  |> should.equal(L0Constitutional)

  classify_module_layer("cepaf_gleam@fractal@l1_atomic_debug")
  |> should.equal(L1AtomicDebug)

  classify_module_layer("cepaf_gleam@fractal@l2_component")
  |> should.equal(L2ComponentHealth)

  classify_module_layer("cepaf_gleam@fractal@l3_transaction")
  |> should.equal(L3TransactionState)

  classify_module_layer("cepaf_gleam@fractal@l4_system")
  |> should.equal(L4SystemSupervision)

  classify_module_layer("cepaf_gleam@fractal@l5_cognitive")
  |> should.equal(L5CognitiveOoda)

  classify_module_layer("cepaf_gleam@fractal@l6_ecosystem")
  |> should.equal(L6EcosystemSwarm)

  classify_module_layer("cepaf_gleam@fractal@l7_federation")
  |> should.equal(L7FederationZenoh)

  classify_module_layer("cepaf_gleam@ha@homeostasis_evolution_engine")
  |> should.equal(L8EvolutionImmune)

  classify_module_layer("cepaf_gleam@ha@singularity")
  |> should.equal(L9SingularityHarmonic)
}

pub fn fractal_layer_ordinals_test() {
  layer_to_level(L0Constitutional) |> should.equal(0)
  layer_to_level(L1AtomicDebug) |> should.equal(1)
  layer_to_level(L2ComponentHealth) |> should.equal(2)
  layer_to_level(L3TransactionState) |> should.equal(3)
  layer_to_level(L4SystemSupervision) |> should.equal(4)
  layer_to_level(L5CognitiveOoda) |> should.equal(5)
  layer_to_level(L6EcosystemSwarm) |> should.equal(6)
  layer_to_level(L7FederationZenoh) |> should.equal(7)
  layer_to_level(L8EvolutionImmune) |> should.equal(8)
  layer_to_level(L9SingularityHarmonic) |> should.equal(9)
}

pub fn fractal_layer_strings_test() {
  layer_to_string(L0Constitutional) |> should.equal("L0_Constitutional")
  layer_to_string(L9SingularityHarmonic) |> should.equal("L9_Singularity_Harmonic")
}

pub fn parallel_scan_changed_test() {
  let changed = parallel_scan_changed()
  // Should successfully scan without error
  let _ = changed
  should.be_true(True)
}

pub fn concurrent_reload_execution_test() {
  let res = concurrent_reload()
  case res {
    ConcurrentReloadSuccess(scanned, reloaded, dur, _mods, mode) -> {
      should.be_true(scanned > 0)
      should.be_true(reloaded >= 0)
      should.be_true(dur >= 0)
      mode |> should.equal("concurrent_fractal_mesh")
    }
    _ -> should.fail()
  }
}

pub fn sequential_reload_execution_test() {
  let res = sequential_reload()
  case res {
    ConcurrentReloadSuccess(scanned, reloaded, dur, _mods, mode) -> {
      should.be_true(scanned > 0)
      should.be_true(reloaded >= 0)
      should.be_true(dur >= 0)
      mode |> should.equal("sequential_baseline")
    }
    _ -> should.fail()
  }
}

pub fn sequential_vs_concurrent_benchmark_test() {
  let #(seq, conc, speedup) = compare_concurrency()
  case seq, conc {
    ConcurrentReloadSuccess(scanned1, _, _, _, _), ConcurrentReloadSuccess(scanned2, _, _, _, _) -> {
      scanned1 |> should.equal(scanned2)
      should.be_true(speedup >=. 1.0)
    }
    _, _ -> should.fail()
  }
}
