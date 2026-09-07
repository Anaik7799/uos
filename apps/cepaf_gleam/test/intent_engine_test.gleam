// =============================================================================
// [C3I-SIL6-MSTS] INTENT ENGINE TEST SUITE (SC-INTENT-001)
// =============================================================================

import cepaf_gleam/c3i/trace13.{
  Admitted, Development, GleamControlPlane, L5ActorSupervision, Lean4Theorem,
  RootSupervisor, SynchronousNif, TraceCoordinate,
}
import cepaf_gleam/intent/engine.{
  type CapabilityToken, CapabilityToken, Condition,
  Intent, IntentAuthorized, IntentVetoed, PlanMutation, ReadOnlyTelemetry,
  StorageMutation,
}
import gleam/option.{Some}
import gleeunit/should

fn create_sample_coord() -> trace13.TraceCoordinate {
  TraceCoordinate(
    layer: L5ActorSupervision,
    component: "intent_supervisor",
    feature: "typed_authorization",
    surface: Development,
    modal: SynchronousNif,
    plane: GleamControlPlane,
    carrier: "gleam:intent_engine",
    profile: Lean4Theorem,
    semantics: "Denotational state transition and capability verification",
    operations: ["authorize", "evaluate", "veto"],
    telemetry: ["intents_authorized_total", "intents_vetoed_total"],
    invariants: ["INV_CAPABILITY_CHECKED", "INV_STORAGE_SERIAL_LOCK"],
    authority: RootSupervisor,
    status: Admitted,
  )
}

fn create_token(domain: engine.EffectDomain, max_crit: Int) -> CapabilityToken {
  CapabilityToken(
    token_id: "tok-001",
    actor_id: "actor-planner",
    granted_domain: domain,
    max_criticality: max_crit,
    expires_at_epoch_us: 2_000_000_000_000_000,
    signature_sha256: "sig-valid",
  )
}

pub fn authorize_valid_intent_test() {
  let token = create_token(PlanMutation, 3)
  let intent =
    Intent(
      intent_id: "int-100",
      actor_id: "actor-planner",
      target_domain: PlanMutation,
      action: "enqueue_oban_job",
      payload_json: "{\"job\":\"sync_clock\"}",
      preconditions: [
        Condition("sa_plan_ready", "status == ready", True),
        Condition("worker_available", "count > 0", True),
      ],
      postconditions: [
        Condition("job_enqueued", "state == queued", True),
      ],
      criticality: 2,
      coordinate: create_sample_coord(),
    )

  let res = engine.evaluate_intent(intent, token, 1_700_000_000_000_000)
  case res {
    IntentAuthorized(receipt_id, intent_id, actor, dom, act, _, pre, post, _) -> {
      receipt_id |> should.equal("rcpt-int-100")
      intent_id |> should.equal("int-100")
      actor |> should.equal("actor-planner")
      dom |> should.equal(PlanMutation)
      act |> should.equal("enqueue_oban_job")
      pre |> should.equal(2)
      post |> should.equal(1)
    }
    IntentVetoed(_, reason, _) -> panic as reason
  }
}

pub fn veto_insufficient_capability_test() {
  // Token has ReadOnlyTelemetry domain, intent requests PlanMutation -> Vetoed
  let token = create_token(ReadOnlyTelemetry, 3)
  let intent =
    Intent(
      intent_id: "int-101",
      actor_id: "actor-planner",
      target_domain: PlanMutation,
      action: "mutate_plan",
      payload_json: "{}",
      preconditions: [],
      postconditions: [],
      criticality: 1,
      coordinate: create_sample_coord(),
    )

  let res = engine.evaluate_intent(intent, token, 1_700_000_000_000_000)
  case res {
    IntentVetoed(intent_id, reason, _) -> {
      intent_id |> should.equal("int-101")
      reason |> should.equal("Invalid, expired, or insufficient capability token for target domain")
    }
    IntentAuthorized(_, _, _, _, _, _, _, _, _) -> panic as "Should have been vetoed"
  }
}

pub fn veto_storage_serial_lock_test() {
  // Intent payload targeting locked root OS NVMe serial 25503L801736 -> Vetoed
  let token = create_token(StorageMutation, 5)
  let intent =
    Intent(
      intent_id: "int-102",
      actor_id: "actor-storage",
      target_domain: StorageMutation,
      action: "wipe_target",
      payload_json: "{\"disk\":\"/dev/nvme0n1\",\"serial\":\"25503L801736\"}",
      preconditions: [],
      postconditions: [],
      criticality: 5,
      coordinate: create_sample_coord(),
    )

  let res = engine.evaluate_intent(intent, token, 1_700_000_000_000_000)
  case res {
    IntentVetoed(intent_id, _, failing) -> {
      intent_id |> should.equal("int-102")
      failing |> should.equal(Some("INV_STORAGE_SERIAL_LOCK"))
    }
    IntentAuthorized(_, _, _, _, _, _, _, _, _) -> panic as "Should have been vetoed"
  }
}

pub fn veto_unsatisfied_precondition_test() {
  let token = create_token(PlanMutation, 3)
  let intent =
    Intent(
      intent_id: "int-103",
      actor_id: "actor-planner",
      target_domain: PlanMutation,
      action: "claim_task",
      payload_json: "{}",
      preconditions: [
        Condition("sa_plan_healthy", "status == ok", True),
        Condition("lease_acquired", "lease != null", False),
      ],
      postconditions: [],
      criticality: 2,
      coordinate: create_sample_coord(),
    )

  let res = engine.evaluate_intent(intent, token, 1_700_000_000_000_000)
  case res {
    IntentVetoed(intent_id, _, failing) -> {
      intent_id |> should.equal("int-103")
      failing |> should.equal(Some("lease_acquired"))
    }
    IntentAuthorized(_, _, _, _, _, _, _, _, _) -> panic as "Should have been vetoed"
  }
}
