//// =============================================================================
//// [C3I-SIL6-MSTS] UOS POODAVR 7-STAGE CYBERNETIC LOOP ACTOR
//// =============================================================================
//// <uos-module>
////   <identity>
////     <module>cepaf_gleam/cortex/poodavr_actor</module>
////     <authority>UOS-CANONICAL-AGENT-POLICY</authority>
////   </identity>
////   <fractal-topology>
////     <layer>L5_COGNITIVE</layer>
////     <topology>Predict-Observe-Orient-Decide-Act-Verify-Reflect Cybernetic Loop</topology>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-POODAVR-001, SC-COG-001, SC-JIDOKA-001, SC-SA-PLAN-001, SC-CIRCUIT-001</stamp-controls>
////   </compliance>
//// </uos-module>
//// =============================================================================

import cepaf_gleam/cortex/circuit_breaker_pool.{
  type BreakerPool, init_pool, is_pool_tripped,
}
import cepaf_gleam/cortex/cortex_types.{type TaskIntent}
import cepaf_gleam/semantics/algebraic_atlas.{
  ChartState, DeclarativeIntent, DenotationalSuccess, DenotationalVetoed,
  L3Transactions, L5CognitiveOODA, TraceCoordinates,
  evaluate_denotational_intent,
}
import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/otp/supervision
import gleam/string

pub const hard_denied_system_os_serial: String = "25503L801736"

pub type PoodavrStage {
  StagePredict
  StageObserve
  StageOrient
  StageDecide
  StageAct
  StageVerify
  StageReflect
  StageHalt
}

pub fn stage_to_string(stage: PoodavrStage) -> String {
  case stage {
    StagePredict -> "Predict"
    StageObserve -> "Observe"
    StageOrient -> "Orient"
    StageDecide -> "Decide"
    StageAct -> "Act"
    StageVerify -> "Verify"
    StageReflect -> "Reflect"
    StageHalt -> "ConstitutionalHalt"
  }
}

pub type PoodavrDecision {
  PoodavrDecision(
    intent_id: String,
    stage: PoodavrStage,
    lyapunov_energy_prior: Float,
    lyapunov_energy_posterior: Float,
    reasoning: String,
    reply_markdown: String,
    actions_dispatched: List(String),
    receipt_sha256: String,
    denotational_status: String,
    confidence: Float,
    timestamp_ms: Int,
    is_halted: Bool,
    halt_code: Option(Int),
  )
}

pub type PoodavrState {
  PoodavrState(
    id: String,
    current_stage: PoodavrStage,
    breaker_pool: BreakerPool,
    causal_epoch: Int,
    kalman_state: Float,
    lyapunov_energy: Float,
    last_decision: Option(PoodavrDecision),
    total_cycles_completed: Int,
  )
}

pub type PoodavrMessage {
  ProcessIntent(
    intent: TaskIntent,
    reply_to: Subject(PoodavrDecision),
    now_ms: Int,
  )
  GetStage(reply_to: Subject(PoodavrStage))
  GetBreakers(reply_to: Subject(BreakerPool))
  GetState(reply_to: Subject(PoodavrState))
  ResetBreakers(reply_to: Subject(Nil))
  Stop
}

pub fn init_poodavr_state(id: String) -> PoodavrState {
  PoodavrState(
    id: id,
    current_stage: StagePredict,
    breaker_pool: init_pool(),
    causal_epoch: 1,
    kalman_state: 0.1,
    lyapunov_energy: 0.25,
    last_decision: None,
    total_cycles_completed: 0,
  )
}

/// Pure deterministic execution of the 7-stage POODAVR cybernetic cycle.
pub fn execute_pure_poodavr(
  intent: TaskIntent,
  st: PoodavrState,
  now_ms: Int,
) -> #(PoodavrDecision, PoodavrState) {
  // ── 1. PREDICT ──
  let v_prior = 0.5 *. st.lyapunov_energy +. 0.1 *. intent.stress_level
  let kalman_prior = 0.9 *. st.kalman_state +. 0.1 *. intent.stress_level

  // ── 2. OBSERVE ──
  let lower_text = string.lowercase(intent.raw_text)

  // ── 3. ORIENT ──
  // Check Storage Interlock: Host OS NVMe serial permanently locked
  let is_os_disk_targeted =
    string.contains(lower_text, hard_denied_system_os_serial)
    || string.contains(lower_text, "wipe")
    && string.contains(lower_text, "nvme")
    || string.contains(lower_text, "format /dev/nvme0n1")

  // Check Sa-Plan Jidoka Exclusivity (SC-JIDOKA-001)
  let is_unledgered =
    string.contains(lower_text, "unledgered")
    || string.contains(lower_text, "bypass sa-plan")
    || string.contains(lower_text, "shadow task")

  case is_os_disk_targeted, is_unledgered {
    True, _ -> {
      let decision =
        PoodavrDecision(
          intent_id: intent.id,
          stage: StageHalt,
          lyapunov_energy_prior: v_prior,
          lyapunov_energy_posterior: v_prior *. 2.0,
          reasoning: "Constitutional Storage Veto: Host NVMe HARD_DENIED_SYSTEM_OS_SERIAL = "
            <> hard_denied_system_os_serial
            <> " locked against destructive mutation.",
          reply_markdown: "⛔ **Constitutional Storage Veto**: Device "
            <> hard_denied_system_os_serial
            <> " is permanently locked by NixOS/Rust storage safety interlock. Mutation strictly rejected.",
          actions_dispatched: [],
          receipt_sha256: "veto-storage-lock-" <> intent.id,
          denotational_status: "VetoedByHardwareInterlock",
          confidence: 1.0,
          timestamp_ms: now_ms,
          is_halted: True,
          halt_code: Some(-32002),
        )
      let next_st =
        PoodavrState(
          ..st,
          current_stage: StageHalt,
          lyapunov_energy: v_prior *. 2.0,
          last_decision: Some(decision),
        )
      #(decision, next_st)
    }
    _, True -> {
      let decision =
        PoodavrDecision(
          intent_id: intent.id,
          stage: StageHalt,
          lyapunov_energy_prior: v_prior,
          lyapunov_energy_posterior: v_prior *. 1.5,
          reasoning: "Fractal Jidoka Andon Halt: Non-sa-plan task execution attempted. SC-JIDOKA-001 forbids ad-hoc un-ledgered plan execution.",
          reply_markdown: "⛔ **Fractal Jidoka Andon Halt (-32002)**: Non-sa-plan task execution attempted. All workflows must be durably scheduled via `sa-plan`.",
          actions_dispatched: [],
          receipt_sha256: "veto-jidoka-andon-" <> intent.id,
          denotational_status: "VetoedBySaPlanJidoka",
          confidence: 1.0,
          timestamp_ms: now_ms,
          is_halted: True,
          halt_code: Some(-32002),
        )
      let next_st =
        PoodavrState(
          ..st,
          current_stage: StageHalt,
          lyapunov_energy: v_prior *. 1.5,
          last_decision: Some(decision),
        )
      #(decision, next_st)
    }
    False, False -> {
      // ── 4. DECIDE ──
      let tripped = is_pool_tripped(st.breaker_pool)
      case tripped {
        True -> {
          let decision =
            PoodavrDecision(
              intent_id: intent.id,
              stage: StageHalt,
              lyapunov_energy_prior: v_prior,
              lyapunov_energy_posterior: v_prior,
              reasoning: "Circuit Breaker Trip: Prajna protection activated across inference tiers.",
              reply_markdown: "⚠️ **Circuit Breakers Open**: Prajna circuit breaker protection active. Degrading to safe fallback.",
              actions_dispatched: ["trip_circuit_breaker"],
              receipt_sha256: "breaker-trip-" <> intent.id,
              denotational_status: "DegradedCircuitBreaker",
              confidence: 0.5,
              timestamp_ms: now_ms,
              is_halted: True,
              halt_code: Some(-32001),
            )
          let next_st =
            PoodavrState(
              ..st,
              current_stage: StageHalt,
              last_decision: Some(decision),
            )
          #(decision, next_st)
        }
        False -> {
          // ── 5. ACT ──
          let dispatched_action =
            "sa_plan:task_execute:" <> intent.intent_type <> ":" <> intent.id

          // ── 6. VERIFY (Denotational Valuation [[ I ]] (sigma)) ──
          let coords =
            TraceCoordinates(
              timestamp_us: now_ms * 1000,
              layer_id: 5,
              holon_id: "cortex_poodavr",
              causal_epoch: st.causal_epoch,
              shannon_entropy_bits: 2.75,
              lyapunov_energy: v_prior,
              cyclomatic_complexity: 92,
              divergence_ppm: 120,
              itqs_quality: 0.95,
              quarantine_flags: 0,
              worker_hash: "poodavr_worker",
              plan_digest: "poodavr_plan",
              parent_digest: "uos_root",
            )

          let chart_st =
            ChartState(
              chart: L5CognitiveOODA,
              coordinates: coords,
              payload_json: "{\"intent_id\":\"" <> intent.id <> "\"}",
              constitutional_health: 0.98,
            )

          let decl_intent =
            DeclarativeIntent(
              intent_id: intent.id,
              proposer_holon: "poodavr_actor",
              source_chart: L5CognitiveOODA,
              target_chart: L3Transactions,
              action: dispatched_action,
              required_preconditions: ["intent_is_safe", "breakers_closed"],
              guaranteed_postconditions: ["durable_ledger_recorded"],
              preserves_constitutional_invariants: True,
            )

          let valuation = evaluate_denotational_intent(decl_intent, chart_st)

          case valuation {
            DenotationalVetoed(_, reason) -> {
              let decision =
                PoodavrDecision(
                  intent_id: intent.id,
                  stage: StageHalt,
                  lyapunov_energy_prior: v_prior,
                  lyapunov_energy_posterior: v_prior *. 1.2,
                  reasoning: "Denotational Valuation Veto: " <> reason,
                  reply_markdown: "⛔ **Denotational Valuation Failed**: "
                    <> reason,
                  actions_dispatched: [],
                  receipt_sha256: "denotational-veto-" <> intent.id,
                  denotational_status: "VetoedByDenotationalEvaluator",
                  confidence: 0.0,
                  timestamp_ms: now_ms,
                  is_halted: True,
                  halt_code: Some(-32003),
                )
              let next_st =
                PoodavrState(
                  ..st,
                  current_stage: StageHalt,
                  last_decision: Some(decision),
                )
              #(decision, next_st)
            }
            DenotationalSuccess(final_state, receipt_hash) -> {
              // ── 7. REFLECT ──
              // Stable convergence dampens Lyapunov energy
              let v_posterior = v_prior *. 0.6
              let kalman_posterior = kalman_prior *. 0.8
              let next_epoch = final_state.coordinates.causal_epoch

              let reply_md =
                "✅ **POODAVR Loop Completed**: Processed intent `"
                <> intent.id
                <> "` via durable dispatch `"
                <> dispatched_action
                <> "`. Causal Epoch: "
                <> int.to_string(next_epoch)
                <> ", Receipt SHA-256: `"
                <> string.slice(receipt_hash, 0, 16)
                <> "...`"

              let decision =
                PoodavrDecision(
                  intent_id: intent.id,
                  stage: StageReflect,
                  lyapunov_energy_prior: v_prior,
                  lyapunov_energy_posterior: v_posterior,
                  reasoning: "POODAVR convergence achieved with denotational receipt and Lyapunov energy damping.",
                  reply_markdown: reply_md,
                  actions_dispatched: [dispatched_action],
                  receipt_sha256: receipt_hash,
                  denotational_status: "DenotationalSuccess",
                  confidence: 0.98,
                  timestamp_ms: now_ms,
                  is_halted: False,
                  halt_code: None,
                )

              let next_st =
                PoodavrState(
                  ..st,
                  current_stage: StagePredict,
                  causal_epoch: next_epoch,
                  kalman_state: kalman_posterior,
                  lyapunov_energy: v_posterior,
                  last_decision: Some(decision),
                  total_cycles_completed: st.total_cycles_completed + 1,
                )

              #(decision, next_st)
            }
          }
        }
      }
    }
  }
}

// ── Actor Implementation ──

fn handle_message(
  state: PoodavrState,
  msg: PoodavrMessage,
) -> actor.Next(PoodavrState, PoodavrMessage) {
  case msg {
    ProcessIntent(intent, reply_to, now_ms) -> {
      let #(decision, next_state) =
        execute_pure_poodavr(intent, state, now_ms)
      process.send(reply_to, decision)
      actor.continue(next_state)
    }
    GetStage(reply_to) -> {
      process.send(reply_to, state.current_stage)
      actor.continue(state)
    }
    GetBreakers(reply_to) -> {
      process.send(reply_to, state.breaker_pool)
      actor.continue(state)
    }
    GetState(reply_to) -> {
      process.send(reply_to, state)
      actor.continue(state)
    }
    ResetBreakers(reply_to) -> {
      let next_state = PoodavrState(..state, breaker_pool: init_pool())
      process.send(reply_to, Nil)
      actor.continue(next_state)
    }
    Stop -> actor.stop()
  }
}

pub fn start(
  id: String,
) -> Result(actor.Started(Subject(PoodavrMessage)), actor.StartError) {
  actor.new(init_poodavr_state(id))
  |> actor.on_message(handle_message)
  |> actor.start()
}

pub fn supervised(
  id: String,
) -> supervision.ChildSpecification(Subject(PoodavrMessage)) {
  supervision.worker(fn() { start(id) })
}
