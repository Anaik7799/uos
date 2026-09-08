//// Laws for the Gleam control layer over the Mojo KM kernel (SC-PROVENANCE-001).
////
//// These tests assert the CONTROL contract, not the arithmetic. The arithmetic
//// has its own independent oracle in C (native/nifs/mojo/test_uos_km_kernel.c),
//// which computes every expected value from first principles rather than by
//// calling the kernel a second time.

import cepaf_gleam/km/provenance_metrics as pm
import gleeunit/should

/// Uniform counts over k bins carry exactly log2(k) bits.
pub fn entropy_uniform_eight_is_three_bits_test() {
  pm.entropy_bits([5.0, 5.0, 5.0, 5.0, 5.0, 5.0, 5.0, 5.0])
  |> should.equal(Ok(3.0))
}

pub fn entropy_uniform_four_is_two_bits_test() {
  pm.entropy_bits([1.0, 1.0, 1.0, 1.0])
  |> should.equal(Ok(2.0))
}

/// An all-zero histogram has no distribution, so it is rejected rather than
/// reported as zero bits: a metric that cannot be computed must not pass.
pub fn entropy_rejects_all_zero_test() {
  pm.entropy_bits([0.0, 0.0, 0.0])
  |> should.equal(Error(pm.KernelRejected("rejected_by_kernel")))
}

pub fn entropy_rejects_empty_test() {
  pm.entropy_bits([])
  |> should.equal(Error(pm.KernelRejected("bad_counts")))
}

pub fn conformance_all_marked_is_one_test() {
  pm.conformance([1.0, 1.0, 1.0, 1.0], [2.0, 2.0, 2.0, 2.0])
  |> should.equal(Ok(1.0))
}

pub fn conformance_none_marked_is_zero_test() {
  pm.conformance([0.0, 0.0, 0.0, 0.0], [2.0, 2.0, 2.0, 2.0])
  |> should.equal(Ok(0.0))
}

/// Length mismatch is caught in Gleam before the kernel is reached.
pub fn conformance_rejects_length_mismatch_test() {
  pm.conformance([1.0, 1.0], [1.0])
  |> should.equal(Error(pm.InvalidInput("features and weights differ in length")))
}

/// Identical vectors are at distance zero: no surface has drifted.
pub fn drift_zero_when_every_surface_marked_test() {
  pm.drift([
    pm.Surface("wiki", 1.0, 1.0),
    pm.Surface("zk", 1.0, 1.0),
    pm.Surface("km", 1.0, 1.0),
  ])
  |> should.equal(Ok(0.0))
}

/// One fully unmarked surface out of three gives distance 1.0.
pub fn drift_one_unmarked_surface_test() {
  pm.drift([
    pm.Surface("wiki", 1.0, 1.0),
    pm.Surface("zk", 0.0, 1.0),
    pm.Surface("km", 1.0, 1.0),
  ])
  |> should.equal(Ok(1.0))
}

pub fn drift_rejects_empty_test() {
  pm.drift([])
  |> should.equal(Error(pm.InvalidInput("no surfaces supplied")))
}

/// Bands follow the risk-priority policy maxima [5, 15, 35, 70, 125].
pub fn fmea_band_boundaries_test() {
  pm.fmea_band(1, 1, 5) |> should.equal(Ok(1))
  pm.fmea_band(2, 2, 3) |> should.equal(Ok(2))
  pm.fmea_band(3, 3, 3) |> should.equal(Ok(3))
  pm.fmea_band(4, 3, 3) |> should.equal(Ok(4))
  pm.fmea_band(5, 5, 5) |> should.equal(Ok(5))
}

pub fn fmea_band_rejects_out_of_range_test() {
  pm.fmea_band(0, 1, 1) |> should.equal(Error(pm.KernelRejected("rejected_by_kernel")))
  pm.fmea_band(1, 1, 6) |> should.equal(Error(pm.KernelRejected("rejected_by_kernel")))
}

/// A corpus that is complete, diverse and fully marked passes.
pub fn evaluate_passes_when_all_thresholds_met_test() {
  pm.evaluate(
    [1.0, 1.0, 1.0, 1.0],
    [1.0, 1.0, 1.0, 1.0],
    [5.0, 5.0, 5.0, 5.0, 5.0, 5.0, 5.0, 5.0],
    [pm.Surface("wiki", 1.0, 1.0), pm.Surface("zk", 1.0, 1.0)],
  )
  |> should.equal(Ok(pm.Pass(1.0, 3.0, 0.0)))
}

/// The observed corpus: 68 of 86 records collapsed onto one fractal layer.
/// Entropy is 1.31 bits, below the 2.50 floor, so the verdict must hold.
pub fn evaluate_holds_on_degenerate_layer_distribution_test() {
  let result =
    pm.evaluate(
      [1.0, 1.0],
      [1.0, 1.0],
      [68.0, 5.0, 4.0, 3.0, 2.0, 1.0, 1.0, 1.0, 1.0],
      [pm.Surface("wiki", 1.0, 1.0), pm.Surface("zk", 1.0, 1.0)],
    )
  case result {
    Ok(pm.Hold(_, _, _, reasons)) ->
      reasons |> should.equal(["layer entropy below CHK-09-MATH floor"])
    _ -> should.fail()
  }
}

/// Drift alone is enough to hold the verdict.
pub fn evaluate_holds_on_surface_drift_test() {
  let result =
    pm.evaluate(
      [1.0, 1.0],
      [1.0, 1.0],
      [5.0, 5.0, 5.0, 5.0, 5.0, 5.0, 5.0, 5.0],
      [pm.Surface("wiki", 1.0, 1.0), pm.Surface("zk", 0.0, 1.0)],
    )
  case result {
    Ok(pm.Hold(_, _, drift, reasons)) -> {
      drift |> should.equal(1.0)
      reasons |> should.equal(["surface drift above ceiling"])
    }
    _ -> should.fail()
  }
}
