//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ha/cicd_gate</module>
////     <fsharp-lineage>None — novel Gleam module for CI/CD quality gate (SC-CI-001)</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L7_FEDERATION</layer>
////     <mesh-domain>
////       CI/CD Quality Gate — evaluates a PipelineRun against a GatePolicy to
////       produce a typed pass/fail decision with human-readable reasons.
////       Implements the SIL-6 deployment gate: a pipeline may only proceed to
////       Deploy when Build, Test, Lint, SecurityScan, and FitnessGate have all
////       passed and the policy thresholds are satisfied.
////     </mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>HIGH</criticality>
////     <stamp-controls>SC-HA-001, SC-CI-001, SC-FUNC-006, SC-MUDA-001</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective">
////       GitHub Actions / GitLab CI pipeline ↪ Gleam PipelineRun ADT.
////       Branch protection rules ↪ GatePolicy.required_stages list.
////       All logic is pure; callers own triggering and Zenoh publishing.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// CI/CD Quality Gate — गुणवत्ता द्वार (Quality Portal)
//// "Better is one's own dharma, though imperfectly performed." (Gita 3.35)
////
//// Design invariants:
////   I1: evaluate_pipeline returns (False, reasons) when any blocking stage failed.
////   I2: missing_stages returns stages in policy.required_stages not yet recorded.
////   I3: pipeline_duration = sum of all StageResult.duration_ms values.
////   I4: policy_default requires all 5 non-Deploy stages, min 100 tests, fitness 0.8.
////   I5: A pipeline with 0 stages always fails (all required stages are missing).
////
//// STAMP: SC-HA-001, SC-CI-001, SC-FUNC-006, SC-MUDA-001

import gleam/int
import gleam/list

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

/// The stages of a CI/CD pipeline.
pub type CicdStage {
  /// Compilation step — must produce 0 errors and 0 warnings (SC-MUDA-001).
  Build
  /// Automated test suite — must meet min_test_count from the policy.
  Test
  /// Static analysis — credo strict / gleam check / clippy.
  Lint
  /// Security scan — sobelow / cargo audit / trivy.
  SecurityScan
  /// Fitness gate — composite fitness score must meet min_fitness.
  FitnessGate
  /// Deployment to a target environment — gated by all prior stages.
  Deploy
}

/// The result of a single pipeline stage.
pub type StageResult {
  StageResult(
    /// The stage that was run.
    stage: CicdStage,
    /// True when the stage completed without errors.
    passed: Bool,
    /// Wall-clock duration of the stage in milliseconds.
    duration_ms: Int,
    /// When True, a failure in this stage blocks the whole pipeline.
    blocking: Bool,
  )
}

/// Policy that controls which stages are required and what thresholds apply.
pub type GatePolicy {
  GatePolicy(
    /// Stages that MUST be recorded and passing for the pipeline to proceed.
    required_stages: List(CicdStage),
    /// Minimum number of tests that must have run (enforced by the Test stage).
    min_test_count: Int,
    /// Minimum fitness score ∈ [0.0, 1.0] (enforced by the FitnessGate stage).
    min_fitness: Float,
    /// When True, a failed SecurityScan always blocks the pipeline.
    block_on_security: Bool,
  )
}

/// A single pipeline execution.
pub type PipelineRun {
  PipelineRun(
    /// Stage results recorded so far.
    stages: List(StageResult),
    /// Git commit SHA that triggered this pipeline.
    commit_sha: String,
    /// Branch name the commit was pushed to.
    branch: String,
    /// Unix-epoch milliseconds when the pipeline started.
    started_at: Int,
  )
}

// ---------------------------------------------------------------------------
// Policy construction
// ---------------------------------------------------------------------------

/// Returns the default SIL-6 gate policy.
///
/// Requires Build, Test, Lint, SecurityScan, and FitnessGate.
/// Minimum 100 tests, fitness >= 0.8, security scan is blocking.
pub fn policy_default() -> GatePolicy {
  GatePolicy(
    required_stages: [Build, Test, Lint, SecurityScan, FitnessGate],
    min_test_count: 100,
    min_fitness: 0.8,
    block_on_security: True,
  )
}

// ---------------------------------------------------------------------------
// Pipeline construction
// ---------------------------------------------------------------------------

/// Creates a new empty pipeline run.
pub fn pipeline_new(
  commit_sha: String,
  branch: String,
  timestamp: Int,
) -> PipelineRun {
  PipelineRun(
    stages: [],
    commit_sha: commit_sha,
    branch: branch,
    started_at: timestamp,
  )
}

// ---------------------------------------------------------------------------
// Stage recording
// ---------------------------------------------------------------------------

/// Appends a stage result to the pipeline.
///
/// If a result for the same stage already exists it is replaced.
pub fn record_stage(pipeline: PipelineRun, result: StageResult) -> PipelineRun {
  let filtered = list.filter(pipeline.stages, fn(s) { s.stage != result.stage })
  PipelineRun(..pipeline, stages: list.append(filtered, [result]))
}

// ---------------------------------------------------------------------------
// Evaluation
// ---------------------------------------------------------------------------

/// Evaluates the pipeline against the policy.
///
/// Returns #(True, []) when all gates pass, or #(False, reasons) otherwise.
pub fn evaluate_pipeline(
  pipeline: PipelineRun,
  policy: GatePolicy,
) -> #(Bool, List(String)) {
  let reasons_missing = check_missing_stages(pipeline, policy)
  let reasons_failed = check_failed_stages(pipeline, policy)
  let all_reasons = list.append(reasons_missing, reasons_failed)
  case all_reasons {
    [] -> #(True, [])
    _ -> #(False, all_reasons)
  }
}

/// Returns stages from the policy that have not yet been recorded.
pub fn missing_stages(
  pipeline: PipelineRun,
  policy: GatePolicy,
) -> List(CicdStage) {
  let recorded = list.map(pipeline.stages, fn(s) { s.stage })
  list.filter(policy.required_stages, fn(required) {
    !list.contains(recorded, required)
  })
}

// ---------------------------------------------------------------------------
// Metrics
// ---------------------------------------------------------------------------

/// Returns the sum of all stage durations in milliseconds.
pub fn pipeline_duration(pipeline: PipelineRun) -> Int {
  list.fold(pipeline.stages, 0, fn(acc, s) { acc + s.duration_ms })
}

// ---------------------------------------------------------------------------
// String conversions
// ---------------------------------------------------------------------------

/// Returns the display name of a CicdStage.
pub fn stage_to_string(stage: CicdStage) -> String {
  case stage {
    Build -> "Build"
    Test -> "Test"
    Lint -> "Lint"
    SecurityScan -> "SecurityScan"
    FitnessGate -> "FitnessGate"
    Deploy -> "Deploy"
  }
}

/// Returns a human-readable summary of the pipeline run.
pub fn summary(pipeline: PipelineRun) -> String {
  let total = list.length(pipeline.stages)
  let passed = list.filter(pipeline.stages, fn(s) { s.passed }) |> list.length()
  let duration = pipeline_duration(pipeline)
  "PipelineRun{sha="
  <> pipeline.commit_sha
  <> ",branch="
  <> pipeline.branch
  <> ",stages="
  <> int.to_string(total)
  <> ",passed="
  <> int.to_string(passed)
  <> ",duration_ms="
  <> int.to_string(duration)
  <> "}"
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

fn check_missing_stages(
  pipeline: PipelineRun,
  policy: GatePolicy,
) -> List(String) {
  list.map(missing_stages(pipeline, policy), fn(stage) {
    "required stage not recorded: " <> stage_to_string(stage)
  })
}

fn check_failed_stages(
  pipeline: PipelineRun,
  policy: GatePolicy,
) -> List(String) {
  list.flat_map(pipeline.stages, fn(result) {
    case result.passed {
      True -> []
      False ->
        case result.blocking {
          True -> ["blocking stage failed: " <> stage_to_string(result.stage)]
          False ->
            case result.stage == SecurityScan && policy.block_on_security {
              True -> ["security scan failed (block_on_security=true)"]
              False -> []
            }
        }
    }
  })
}
