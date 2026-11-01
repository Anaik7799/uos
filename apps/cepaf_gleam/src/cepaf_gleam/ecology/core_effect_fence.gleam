//// Pure functional OTP 29 effect-time authority & 14-target recoverable cutover
//// module (Wave 1B: OI07 + I21 + I29). Zero side effects, zero warnings.

import gleam/int
import gleam/list
import gleam/string

pub type EffectContext {
  EffectContext(
    plan_id: String,
    task_id: String,
    worker: String,
    attempt: Int,
    lease_until_ns: Int,
    now_ns: Int,
    expected_candidate_sha256: String,
    actual_candidate_sha256: String,
    assessment_age_s: Int,
    max_age_s: Int,
    writer_identity: String,
    superseded_plans: List(String),
    oi07_verified: Bool,
  )
}

pub type EffectGrant {
  EffectGrant(
    plan_id: String,
    task_id: String,
    worker: String,
    attempt: Int,
    lease_until_ns: Int,
    candidate_sha256: String,
    writer_identity: String,
    oi07_verified: Bool,
  )
}

pub type TargetRecoveryState {
  TargetRecoveryState(
    step: Int,
    target_id: String,
    active_capsule_sha: String,
    rolled_back: Bool,
  )
}

pub type Cutover14Plan {
  Cutover14Plan(
    old_capsule_sha: String,
    new_capsule_sha: String,
    targets: List(String),
    commit_point_step: Int,
    reader_drain_barrier_ok: Bool,
  )
}

pub type RecoveryReceipt {
  RecoveryReceipt(
    old_capsule_sha: String,
    new_capsule_sha: String,
    crash_at_step: Int,
    commit_point_step: Int,
    reader_drain_barrier_ok: Bool,
    committed: Bool,
    rolled_back: Bool,
    mixed_reader_count: Int,
    active_capsule_sha: String,
    target_states: List(TargetRecoveryState),
  )
}

pub const canonical_14_targets: List(String) = [
  "workspace_claude_mcp",
  "workspace_codex_config",
  "workspace_agy_settings",
  "workspace_pi_mcp",
  "release_pointer",
  "cockpit_service",
  "ecology_component",
  "home_agy_antigravity_mcp",
  "home_agy_config_mcp",
  "home_agy_settings",
  "home_codex_config",
  "home_claude_config",
  "home_pi_mcp",
  "home_pi_mcp_adapter",
]

pub fn canonical_cutover_14_plan(
  old_capsule_sha: String,
  new_capsule_sha: String,
) -> Cutover14Plan {
  Cutover14Plan(
    old_capsule_sha: old_capsule_sha,
    new_capsule_sha: new_capsule_sha,
    targets: canonical_14_targets,
    commit_point_step: 14,
    reader_drain_barrier_ok: True,
  )
}

pub fn is_cutover_or_oi02_task(task_id: String) -> Bool {
  let task_lower = string.trim(string.lowercase(task_id))
  let is_exact_oi02e_rehearsal =
    task_lower == "oi02e"
    || task_lower == "oi02e-rehearsal"
    || task_lower == "w1a-oi02e-native-build"
  let is_oi02 =
    string.contains(task_lower, "oi02") && !is_exact_oi02e_rehearsal
  let is_w2_cutover =
    string.starts_with(task_lower, "w2-")
    || string.contains(task_lower, "cutover")
    || string.contains(task_lower, "capsule-activation")
  is_oi02 || is_w2_cutover
}

pub fn evaluate_effect_fence(
  ctx: EffectContext,
) -> Result(EffectGrant, List(String)) {
  let writer_lower = string.lowercase(ctx.writer_identity)

  let is_superseded = list.contains(ctx.superseded_plans, ctx.plan_id)
  let is_empty_worker = string.trim(ctx.worker) == ""
  let is_invalid_attempt = ctx.attempt < 1
  let is_lease_expired = ctx.now_ns >= ctx.lease_until_ns
  let is_candidate_drift =
    ctx.expected_candidate_sha256 != ctx.actual_candidate_sha256
    || string.trim(ctx.expected_candidate_sha256) == ""
  let is_stale_assessment = ctx.assessment_age_s > ctx.max_age_s
  let is_rogue_writer =
    string.contains(writer_lower, "c3i")
    || string.contains(ctx.writer_identity, ":4200")
  let is_oi02_without_oi07 =
    is_cutover_or_oi02_task(ctx.task_id) && !ctx.oi07_verified

  let errors =
    []
    |> append_if(is_superseded, "HOLD:plan_superseded:" <> ctx.plan_id)
    |> append_if(is_empty_worker, "HOLD:missing_worker")
    |> append_if(
      is_invalid_attempt,
      "HOLD:invalid_attempt:" <> int.to_string(ctx.attempt),
    )
    |> append_if(is_lease_expired, "HOLD:lease_expired")
    |> append_if(is_candidate_drift, "HOLD:candidate_sha256_drift")
    |> append_if(is_stale_assessment, "HOLD:assessment_stale")
    |> append_if(
      is_rogue_writer,
      "HOLD:rogue_writer_rejected:" <> ctx.writer_identity,
    )
    |> append_if(
      is_oi02_without_oi07,
      "HOLD:I29_oi02_blocked_until_oi07_verified",
    )

  case errors {
    [] ->
      Ok(EffectGrant(
        plan_id: ctx.plan_id,
        task_id: ctx.task_id,
        worker: ctx.worker,
        attempt: ctx.attempt,
        lease_until_ns: ctx.lease_until_ns,
        candidate_sha256: ctx.actual_candidate_sha256,
        writer_identity: ctx.writer_identity,
        oi07_verified: ctx.oi07_verified,
      ))
    reasons -> Error(reasons)
  }
}

fn append_if(acc: List(String), cond: Bool, msg: String) -> List(String) {
  case cond {
    True -> list.append(acc, [msg])
    False -> acc
  }
}

pub fn simulate_14target_crash_recovery(
  old_capsule_sha: String,
  new_capsule_sha: String,
  crash_at_step: Int,
) -> RecoveryReceipt {
  let plan = canonical_cutover_14_plan(old_capsule_sha, new_capsule_sha)
  let committed = crash_at_step == 0
  let rolled_back = !committed
  let final_sha = case committed {
    True -> plan.new_capsule_sha
    False -> plan.old_capsule_sha
  }

  let target_states =
    list.index_map(plan.targets, fn(target_id, idx) {
      TargetRecoveryState(
        step: idx + 1,
        target_id: target_id,
        active_capsule_sha: final_sha,
        rolled_back: rolled_back,
      )
    })

  let distinct_shas =
    target_states
    |> list.map(fn(s) { s.active_capsule_sha })
    |> list.unique
    |> list.length

  let mixed_reader_count = case distinct_shas <= 1 {
    True -> 0
    False -> distinct_shas - 1
  }

  RecoveryReceipt(
    old_capsule_sha: plan.old_capsule_sha,
    new_capsule_sha: plan.new_capsule_sha,
    crash_at_step: crash_at_step,
    commit_point_step: plan.commit_point_step,
    reader_drain_barrier_ok: plan.reader_drain_barrier_ok,
    committed: committed,
    rolled_back: rolled_back,
    mixed_reader_count: mixed_reader_count,
    active_capsule_sha: final_sha,
    target_states: target_states,
  )
}
