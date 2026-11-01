import cepaf_gleam/ecology/core_effect_fence as fence
import gleam/list
import gleam/string
import gleeunit/should

fn valid_ctx() -> fence.EffectContext {
  fence.EffectContext(
    plan_id: "uos/mcp-canonical-completion/20261031-1807",
    task_id: "oi07-effect-time-authority",
    worker: "worker-w1b-oi07",
    attempt: 1,
    lease_until_ns: 2_000_000_000,
    now_ns: 1_000_000_000,
    expected_candidate_sha256: "sha256:aaaa1111bbbb2222cccc3333dddd4444",
    actual_candidate_sha256: "sha256:aaaa1111bbbb2222cccc3333dddd4444",
    assessment_age_s: 30,
    max_age_s: 300,
    writer_identity: "uos-gleam-ecology-authority:4100",
    superseded_plans: ["uos/mcp-canonical-completion/20261031-0327"],
    oi07_verified: True,
  )
}

pub fn valid_grant_test() {
  let ctx = valid_ctx()
  let res = fence.evaluate_effect_fence(ctx)
  should.be_ok(res)
  let assert Ok(grant) = res
  grant.plan_id |> should.equal(ctx.plan_id)
  grant.task_id |> should.equal(ctx.task_id)
  grant.worker |> should.equal("worker-w1b-oi07")
  grant.attempt |> should.equal(1)
  grant.candidate_sha256 |> should.equal(ctx.actual_candidate_sha256)
  grant.oi07_verified |> should.be_true
}

pub fn expired_lease_hold_test() {
  let ctx =
    fence.EffectContext(
      ..valid_ctx(),
      now_ns: 2_000_000_000,
      lease_until_ns: 2_000_000_000,
    )
  let res = fence.evaluate_effect_fence(ctx)
  should.be_error(res)
  let assert Error(reasons) = res
  list.any(reasons, fn(r) { string.contains(r, "lease_expired") })
  |> should.be_true
}

pub fn superseded_0327_v1_hold_test() {
  let ctx =
    fence.EffectContext(
      ..valid_ctx(),
      plan_id: "uos/mcp-canonical-completion/20261031-0327",
    )
  let res = fence.evaluate_effect_fence(ctx)
  should.be_error(res)
  let assert Error(reasons) = res
  list.any(reasons, fn(r) { string.contains(r, "plan_superseded") })
  |> should.be_true
}

pub fn rogue_4200_c3i_writer_hold_test() {
  let ctx1 =
    fence.EffectContext(
      ..valid_ctx(),
      writer_identity: "http://127.0.0.1:4200/mcp",
    )
  let res1 = fence.evaluate_effect_fence(ctx1)
  should.be_error(res1)

  let ctx2 =
    fence.EffectContext(..valid_ctx(), writer_identity: "c3i-legacy-daemon")
  let res2 = fence.evaluate_effect_fence(ctx2)
  should.be_error(res2)
}

pub fn oi02_before_oi07_i29_hold_test() {
  let ctx_blocked =
    fence.EffectContext(
      ..valid_ctx(),
      task_id: "oi02-live-cutover",
      oi07_verified: False,
    )
  let res_blocked = fence.evaluate_effect_fence(ctx_blocked)
  should.be_error(res_blocked)
  let assert Error(reasons) = res_blocked
  list.any(reasons, fn(r) { string.contains(r, "I29_oi02_blocked") })
  |> should.be_true

  let ctx_oi02e_allowed =
    fence.EffectContext(
      ..valid_ctx(),
      task_id: "oi02e-rehearsal",
      oi07_verified: False,
    )
  fence.evaluate_effect_fence(ctx_oi02e_allowed) |> should.be_ok

  let ctx_spoofed_oi02e_blocked =
    fence.EffectContext(
      ..valid_ctx(),
      task_id: "oi02-live-cutover-oi02e",
      oi07_verified: False,
    )
  let res_spoofed = fence.evaluate_effect_fence(ctx_spoofed_oi02e_blocked)
  should.be_error(res_spoofed)
  let assert Error(spoofed_reasons) = res_spoofed
  list.any(spoofed_reasons, fn(r) { string.contains(r, "I29_oi02_blocked") })
  |> should.be_true

  let ctx_w2_canonical_blocked =
    fence.EffectContext(
      ..valid_ctx(),
      task_id: "w2-recoverable-14target-cutover",
      oi07_verified: False,
    )
  let res_w2_canonical_blocked =
    fence.evaluate_effect_fence(ctx_w2_canonical_blocked)
  should.be_error(res_w2_canonical_blocked)
  let assert Error(w2_canonical_reasons) = res_w2_canonical_blocked
  list.any(w2_canonical_reasons, fn(r) {
    string.contains(r, "I29_oi02_blocked")
  })
  |> should.be_true

  let ctx_w2_blocked =
    fence.EffectContext(
      ..valid_ctx(),
      task_id: "w2-capsule-activation-and-14-target-cutover",
      oi07_verified: False,
    )
  let res_w2_blocked = fence.evaluate_effect_fence(ctx_w2_blocked)
  should.be_error(res_w2_blocked)
  let assert Error(w2_reasons) = res_w2_blocked
  list.any(w2_reasons, fn(r) { string.contains(r, "I29_oi02_blocked") })
  |> should.be_true

  let ctx_w2_after_oi07 =
    fence.EffectContext(
      ..valid_ctx(),
      task_id: "w2-capsule-activation-and-14-target-cutover",
      oi07_verified: True,
    )
  fence.evaluate_effect_fence(ctx_w2_after_oi07) |> should.be_ok

  let ctx_oi02_after_oi07 =
    fence.EffectContext(
      ..valid_ctx(),
      task_id: "oi02-live-cutover",
      oi07_verified: True,
    )
  fence.evaluate_effect_fence(ctx_oi02_after_oi07) |> should.be_ok
}

pub fn candidate_drift_hold_test() {
  let ctx =
    fence.EffectContext(
      ..valid_ctx(),
      expected_candidate_sha256: "sha256:1111",
      actual_candidate_sha256: "sha256:2222",
    )
  let res = fence.evaluate_effect_fence(ctx)
  should.be_error(res)
  let assert Error(reasons) = res
  list.any(reasons, fn(r) { string.contains(r, "candidate_sha256_drift") })
  |> should.be_true
}

pub fn crash_steps_1_to_13_rollback_and_step_0_commit_test() {
  let old_sha = "sha256:old_capsule_0001"
  let new_sha = "sha256:new_capsule_0002"

  [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13]
  |> list.each(fn(step) {
    let receipt = fence.simulate_14target_crash_recovery(old_sha, new_sha, step)
    receipt.commit_point_step |> should.equal(14)
    receipt.reader_drain_barrier_ok |> should.be_true
    receipt.committed |> should.be_false
    receipt.rolled_back |> should.be_true
    receipt.mixed_reader_count |> should.equal(0)
    receipt.active_capsule_sha |> should.equal(old_sha)
    list.length(receipt.target_states) |> should.equal(14)
    list.all(receipt.target_states, fn(t) {
      t.active_capsule_sha == old_sha && t.rolled_back
    })
    |> should.be_true
  })

  let commit_receipt =
    fence.simulate_14target_crash_recovery(old_sha, new_sha, 0)
  commit_receipt.commit_point_step |> should.equal(14)
  commit_receipt.reader_drain_barrier_ok |> should.be_true
  commit_receipt.committed |> should.be_true
  commit_receipt.rolled_back |> should.be_false
  commit_receipt.mixed_reader_count |> should.equal(0)
  commit_receipt.active_capsule_sha |> should.equal(new_sha)
  list.length(commit_receipt.target_states) |> should.equal(14)
  list.all(commit_receipt.target_states, fn(t) {
    t.active_capsule_sha == new_sha && !t.rolled_back
  })
  |> should.be_true
}
