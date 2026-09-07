import cepaf_gleam/ai/max_simd_scorer.{
  PatchBlocked, PatchNominal, PatchWarning, cosine_similarity, evaluate_orient,
  score_patch,
}
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn clean_patch_nominal_test() {
  let code = "pub fn add(a: Int, b: Int) -> Int { a + b }"
  let res = score_patch(code, 5, 6)
  res.verdict |> should.equal(PatchNominal)
  res.cyclomatic_delta |> should.equal(1)
  { res.entropy >=. 2.5 } |> should.be_true
  res.latency_us |> should.equal(463)
}

pub fn bevy_purity_violation_test() {
  let code = "import bevy_ecs::prelude::*"
  let res = score_patch(code, 5, 7)
  case res.verdict {
    PatchBlocked(reason) -> {
      should.be_true(reason != "")
    }
    _ -> should.fail()
  }
}

pub fn hard_denied_drive_wipe_test() {
  let code = "wipe_disk_serial(\"25503L801736\")"
  let res = score_patch(code, 2, 4)
  case res.verdict {
    PatchBlocked(reason) -> {
      should.be_true(reason != "")
    }
    _ -> should.fail()
  }
}

pub fn panic_warning_test() {
  let code = "let val = opt.unwrap()"
  let res = score_patch(code, 3, 4)
  case res.verdict {
    PatchWarning(reason) -> {
      should.be_true(reason != "")
    }
    _ -> should.fail()
  }
}

pub fn fast_ooda_orient_cycle_test() {
  let code = "pub fn pure_fn() { 42 }"
  let orient = evaluate_orient(code, 2.0, 0.95)
  orient.lyapunov_stable |> should.be_true
  { orient.lyapunov_lambda <. 0.0 } |> should.be_true
  orient.semantic_consonance |> should.equal(0.95)
  // Fast convergence: total orient latency must be strictly under 2.5ms (2500us)
  { orient.total_orient_latency_us < 2500 } |> should.be_true
}

pub fn cosine_similarity_orthogonal_and_parallel_test() {
  let v1 = [1.0, 0.0, 0.0]
  let v2 = [1.0, 0.0, 0.0]
  let v3 = [0.0, 1.0, 0.0]

  { cosine_similarity(v1, v2) >. 0.999 } |> should.be_true
  { cosine_similarity(v1, v3) <. 0.001 } |> should.be_true
}
