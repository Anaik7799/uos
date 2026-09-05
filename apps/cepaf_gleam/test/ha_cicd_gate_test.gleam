/// CI/CD Quality Gate tests
/// Layer: L7_FEDERATION
/// STAMP: SC-HA-001, SC-CI-001, SC-FUNC-006, SC-MUDA-001
///
/// Covers:
///   GatePolicy construction (default)
///   PipelineRun construction and stage recording
///   evaluate_pipeline: pass / fail / missing stages
///   missing_stages computation
///   pipeline_duration aggregate
///   stage_to_string conversion
///   Summary string
import cepaf_gleam/ha/cicd_gate.{
  type StageResult, Build, Deploy, FitnessGate, Lint, SecurityScan, StageResult,
  Test, evaluate_pipeline, missing_stages, pipeline_duration, pipeline_new,
  policy_default, record_stage, stage_to_string, summary,
}
import gleam/list
import gleeunit/should

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn pass(stage) -> StageResult {
  StageResult(stage: stage, passed: True, duration_ms: 100, blocking: True)
}

fn fail_stage(stage) -> StageResult {
  StageResult(stage: stage, passed: False, duration_ms: 50, blocking: True)
}

fn all_required_pass() -> List(StageResult) {
  [
    pass(Build),
    pass(Test),
    pass(Lint),
    pass(SecurityScan),
    pass(FitnessGate),
  ]
}

fn pipeline_with_all_passing() {
  list.fold(all_required_pass(), pipeline_new("abc123", "main", 0), fn(p, r) {
    record_stage(p, r)
  })
}

// ---------------------------------------------------------------------------
// Policy default
// ---------------------------------------------------------------------------

pub fn policy_default_requires_build_test() {
  let policy = policy_default()
  list.contains(policy.required_stages, Build) |> should.be_true()
}

pub fn policy_default_requires_test_stage_test() {
  let policy = policy_default()
  list.contains(policy.required_stages, Test) |> should.be_true()
}

pub fn policy_default_requires_security_scan_test() {
  let policy = policy_default()
  list.contains(policy.required_stages, SecurityScan) |> should.be_true()
}

pub fn policy_default_does_not_require_deploy_test() {
  let policy = policy_default()
  list.contains(policy.required_stages, Deploy) |> should.be_false()
}

pub fn policy_default_min_test_count_is_100_test() {
  policy_default().min_test_count |> should.equal(100)
}

pub fn policy_default_block_on_security_is_true_test() {
  policy_default().block_on_security |> should.be_true()
}

// ---------------------------------------------------------------------------
// Pipeline construction
// ---------------------------------------------------------------------------

pub fn pipeline_new_has_no_stages_test() {
  let p = pipeline_new("sha1", "main", 12_345)
  list.length(p.stages) |> should.equal(0)
}

pub fn pipeline_new_stores_commit_sha_test() {
  pipeline_new("deadbeef", "main", 0).commit_sha |> should.equal("deadbeef")
}

pub fn pipeline_new_stores_branch_test() {
  pipeline_new("sha", "feature/x", 0).branch |> should.equal("feature/x")
}

// ---------------------------------------------------------------------------
// record_stage
// ---------------------------------------------------------------------------

pub fn record_stage_appends_result_test() {
  let p =
    pipeline_new("sha", "main", 0)
    |> record_stage(pass(Build))
  list.length(p.stages) |> should.equal(1)
}

pub fn record_stage_replaces_existing_test() {
  let p =
    pipeline_new("sha", "main", 0)
    |> record_stage(pass(Build))
    |> record_stage(fail_stage(Build))
  list.length(p.stages) |> should.equal(1)
  case p.stages {
    [s, ..] -> s.passed |> should.be_false()
    [] -> should.fail()
  }
}

// ---------------------------------------------------------------------------
// evaluate_pipeline
// ---------------------------------------------------------------------------

pub fn evaluate_pipeline_all_pass_test() {
  let p = pipeline_with_all_passing()
  let #(passed, reasons) = evaluate_pipeline(p, policy_default())
  passed |> should.be_true()
  list.length(reasons) |> should.equal(0)
}

pub fn evaluate_pipeline_missing_stage_fails_test() {
  let p = pipeline_new("sha", "main", 0)
  let #(passed, _) = evaluate_pipeline(p, policy_default())
  passed |> should.be_false()
}

pub fn evaluate_pipeline_blocking_failure_fails_test() {
  let p =
    pipeline_new("sha", "main", 0)
    |> record_stage(fail_stage(Build))
    |> record_stage(pass(Test))
    |> record_stage(pass(Lint))
    |> record_stage(pass(SecurityScan))
    |> record_stage(pass(FitnessGate))
  let #(passed, _) = evaluate_pipeline(p, policy_default())
  passed |> should.be_false()
}

pub fn evaluate_pipeline_returns_reasons_on_failure_test() {
  let p = pipeline_new("sha", "main", 0)
  let #(_, reasons) = evaluate_pipeline(p, policy_default())
  // reasons should be non-empty since all stages are missing
  { reasons != [] } |> should.be_true()
}

// ---------------------------------------------------------------------------
// missing_stages
// ---------------------------------------------------------------------------

pub fn missing_stages_all_required_test() {
  let p = pipeline_new("sha", "main", 0)
  let missing = missing_stages(p, policy_default())
  list.length(missing) |> should.equal(5)
}

pub fn missing_stages_none_when_all_recorded_test() {
  let p = pipeline_with_all_passing()
  let missing = missing_stages(p, policy_default())
  list.length(missing) |> should.equal(0)
}

// ---------------------------------------------------------------------------
// pipeline_duration
// ---------------------------------------------------------------------------

pub fn pipeline_duration_zero_for_empty_test() {
  pipeline_new("sha", "main", 0) |> pipeline_duration() |> should.equal(0)
}

pub fn pipeline_duration_sums_stages_test() {
  let p =
    pipeline_new("sha", "main", 0)
    |> record_stage(StageResult(
      stage: Build,
      passed: True,
      duration_ms: 300,
      blocking: True,
    ))
    |> record_stage(StageResult(
      stage: Test,
      passed: True,
      duration_ms: 700,
      blocking: True,
    ))
  pipeline_duration(p) |> should.equal(1000)
}

// ---------------------------------------------------------------------------
// stage_to_string
// ---------------------------------------------------------------------------

pub fn stage_to_string_build_test() {
  stage_to_string(Build) |> should.equal("Build")
}

pub fn stage_to_string_security_scan_test() {
  stage_to_string(SecurityScan) |> should.equal("SecurityScan")
}

pub fn stage_to_string_deploy_test() {
  stage_to_string(Deploy) |> should.equal("Deploy")
}

// ---------------------------------------------------------------------------
// Summary
// ---------------------------------------------------------------------------

pub fn summary_is_not_empty_test() {
  let p = pipeline_new("sha123", "main", 0)
  summary(p) |> should.not_equal("")
}
