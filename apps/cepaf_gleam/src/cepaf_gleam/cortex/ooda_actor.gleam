//// =============================================================================
//// [C3I-SIL6-MSTS] UOS CORTEX OODA 4-PHASE STATE MACHINE ACTOR
//// =============================================================================
//// <uos-module>
////   <identity>
////     <module>cepaf_gleam/cortex/ooda_actor</module>
////     <authority>UOS-CANONICAL-AGENT-POLICY</authority>
////   </identity>
////   <fractal-topology>
////     <layer>L5_COGNITIVE</layer>
////     <topology>Observe-Orient-Decide-Act Cognitive Convergence Loop</topology>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-COG-001, SC-COG-MAX-001, SC-JIDOKA-001, SC-SA-PLAN-001, SC-CIRCUIT-001</stamp-controls>
////   </compliance>
//// </uos-module>
//// =============================================================================

import cepaf_gleam/cortex/circuit_breaker_pool.{
  type BreakerPool, init_pool,
}
import cepaf_gleam/cortex/cortex_types.{
  type CortexDecision, type OodaPhase, type TaskIntent, CortexDecision,
  PhaseCompleted, PhaseObserve, source_to_string,
}
import cepaf_gleam/cortex/hedged_cascade
import cepaf_gleam/cortex/pipeline_tracer
import cepaf_gleam/planning/sa_plan_bridge
import gleam/erlang/process.{type Subject}
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/otp/supervision
import gleam/string

pub const hard_denied_system_os_serial: String = "25503L801736"

pub type OodaState {
  OodaState(
    id: String,
    phase: OodaPhase,
    breaker_pool: BreakerPool,
    last_decision: Option(CortexDecision),
    total_processed: Int,
  )
}

pub type OodaMessage {
  ProcessIntent(intent: TaskIntent, reply_to: Subject(CortexDecision), now_ms: Int)
  GetPhase(reply_to: Subject(OodaPhase))
  GetBreakers(reply_to: Subject(BreakerPool))
  ResetBreakers(reply_to: Subject(Nil))
  Stop
}

/// Pure functional execution of the 4-phase OODA cycle.
/// Guaranteed zero side-effects, suitable for property tests, oracles, and deterministic verification.
pub fn execute_pure_ooda(
  intent: TaskIntent,
  pool: BreakerPool,
  now_ms: Int,
) -> #(CortexDecision, BreakerPool) {
  // ── Phase 1: OBSERVE ──
  let trace0 =
    pipeline_tracer.new_trace(intent.id, source_to_string(intent.source), now_ms)
  let trace1 =
    pipeline_tracer.add_stage(
      trace0,
      "observe",
      "ingested " <> string.inspect(string.length(intent.raw_text)) <> " chars",
      "ok",
      now_ms,
    )

  // ── Phase 2: ORIENT ──
  let lower_text = string.lowercase(intent.raw_text)
  let is_os_disk_targeted =
    string.contains(lower_text, hard_denied_system_os_serial)
    || string.contains(lower_text, "wipe")
    && string.contains(lower_text, "nvme")

  let is_destructive =
    string.contains(lower_text, "rm -rf /")
    || string.contains(lower_text, "drop database")
    || string.contains(lower_text, "format /dev")

  let is_unledgered_mutation =
    string.contains(lower_text, "unledgered")
    || string.contains(lower_text, "bypass sa-plan")
    || string.contains(lower_text, "shadow task")

  let is_tool_call =
    intent.intent_type == "tool_execution"
    || string.contains(lower_text, "execute_tool")
    || string.contains(lower_text, "run tool")

  let trace2 =
    pipeline_tracer.add_stage(
      trace1,
      "orient",
      "stress: " <> string.inspect(intent.stress_level),
      "ok",
      now_ms + 1,
    )

  // ── Phase 3: DECIDE ──
  case is_os_disk_targeted || is_destructive {
    True -> {
      // Immediate fail-closed hardware protection denial
      let trace3 =
        pipeline_tracer.add_stage(
          trace2,
          "decide",
          "HARD_DENIED: storage interlock triggered",
          "veto",
          now_ms + 2,
        )
      let trace4 =
        pipeline_tracer.add_stage(
          trace3,
          "act",
          "halted execution",
          "ok",
          now_ms + 3,
        )
      let footer = pipeline_tracer.format_footer(trace4)
      let decision =
        CortexDecision(
          intent_id: intent.id,
          phase: PhaseCompleted,
          reasoning: "HARD_DENIED: Attempt to access protected host NVMe serial "
            <> hard_denied_system_os_serial
            <> " or perform destructive storage purge. Interlock engaged.",
          reply_markdown: "⛔ **HARD_DENIED INTERLOCK TRIGGERED**\n\nAccess to root OS NVMe drive `"
            <> hard_denied_system_os_serial
            <> "` or destructive host mutation is strictly barred by UOS Canonical Policy (`contracts/rules/` CHK-07-DRIVE).\n\n"
            <> footer,
          actions_proposed: [],
          inference_result: None,
          confidence: 1.0,
          timestamp_ms: now_ms + 3,
          trace: Some(trace4),
          footer: footer,
          sa_plan_authorized: False,
        )
      #(decision, pool)
    }
    False -> {
      let is_authorized = !{ is_tool_call && is_unledgered_mutation }
      case sa_plan_bridge.enforce_fractal_jidoka(source_to_string(intent.source), intent.intent_type, is_authorized) {
        Error(err) -> {
          // Immediate fail-closed Fractal Jidoka Andon Stop Line (SC-JIDOKA-001)
          let trace3 =
            pipeline_tracer.add_stage(
              trace2,
              "decide",
              "ANDON_HALT: SC-JIDOKA-001 violation",
              "veto",
              now_ms + 2,
            )
          let trace4 =
            pipeline_tracer.add_stage(
              trace3,
              "act",
              "andon line pulled",
              "ok",
              now_ms + 3,
            )
          let footer = pipeline_tracer.format_footer(trace4)
          let decision =
            CortexDecision(
              intent_id: intent.id,
              phase: PhaseCompleted,
              reasoning: err,
              reply_markdown: "🚨 **ANDON STOP LINE HALT (-32002)**\n\n"
                <> err
                <> "\n\nAll mutations must be ledgered under `var/sa-plan/uos.sqlite3` with an active lease.\n\n"
                <> footer,
              actions_proposed: [],
              inference_result: None,
              confidence: 1.0,
              timestamp_ms: now_ms + 3,
              trace: Some(trace4),
              footer: footer,
              sa_plan_authorized: False,
            )
          #(decision, pool)
        }
        Ok(Nil) -> {
          // Hedged inference cascade through 7 tiers
          let #(inf_res, updated_pool) =
            hedged_cascade.execute_cascade(intent.raw_text, pool, now_ms + 2)

          let trace3 =
            pipeline_tracer.add_stage(
              trace2,
              "decide",
              "tier: " <> string.inspect(inf_res.tier),
              "ok",
              now_ms + 2 + inf_res.latency_ms,
            )

          // ── Phase 4: ACT ──
          let trace4 =
            pipeline_tracer.add_stage(
              trace3,
              "act",
              "delivered response",
              "ok",
              now_ms + 3 + inf_res.latency_ms,
            )
          let footer = pipeline_tracer.format_footer(trace4)

          let final_markdown =
            inf_res.response_text
            <> "\n\n---\n"
            <> footer
            <> "\n*Tier:* `"
            <> string.inspect(inf_res.tier)
            <> "` | *Model:* `"
            <> inf_res.model
            <> "`"

          let decision =
            CortexDecision(
              intent_id: intent.id,
              phase: PhaseCompleted,
              reasoning: "Cognitive convergence achieved via tier "
                <> string.inspect(inf_res.tier),
              reply_markdown: final_markdown,
              actions_proposed: case is_tool_call {
                True -> ["sa_plan_action_validated"]
                False -> []
              },
              inference_result: Some(inf_res),
              confidence: inf_res.confidence,
              timestamp_ms: now_ms + 3 + inf_res.latency_ms,
              trace: Some(trace4),
              footer: footer,
              sa_plan_authorized: True,
            )
          #(decision, updated_pool)
        }
      }
    }
  }
}

pub fn init_state(id: String) -> OodaState {
  OodaState(
    id: id,
    phase: PhaseObserve,
    breaker_pool: init_pool(),
    last_decision: None,
    total_processed: 0,
  )
}

fn handle_message(
  state: OodaState,
  msg: OodaMessage,
) -> actor.Next(OodaState, OodaMessage) {
  case msg {
    ProcessIntent(intent, reply_to, now_ms) -> {
      let #(decision, new_pool) =
        execute_pure_ooda(intent, state.breaker_pool, now_ms)
      process.send(reply_to, decision)
      actor.continue(OodaState(
        ..state,
        phase: PhaseCompleted,
        breaker_pool: new_pool,
        last_decision: Some(decision),
        total_processed: state.total_processed + 1,
      ))
    }
    GetPhase(reply_to) -> {
      process.send(reply_to, state.phase)
      actor.continue(state)
    }
    GetBreakers(reply_to) -> {
      process.send(reply_to, state.breaker_pool)
      actor.continue(state)
    }
    ResetBreakers(reply_to) -> {
      process.send(reply_to, Nil)
      actor.continue(OodaState(..state, breaker_pool: init_pool()))
    }
    Stop -> actor.stop()
  }
}

pub fn start(
  id: String,
) -> Result(actor.Started(Subject(OodaMessage)), actor.StartError) {
  actor.new(init_state(id))
  |> actor.on_message(handle_message)
  |> actor.start()
}

pub fn start_supervised(
  id: String,
) -> Result(actor.Started(Subject(OodaMessage)), actor.StartError) {
  start(id)
}

pub fn supervised(
  id: String,
) -> supervision.ChildSpecification(Subject(OodaMessage)) {
  supervision.worker(fn() { start_supervised(id) })
}
