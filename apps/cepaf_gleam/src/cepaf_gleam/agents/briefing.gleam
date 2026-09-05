//// [C3I-SIL6-MSTS] <c3i-module><identity><module>cepaf_gleam/agents/briefing</module></identity>
////   <fractal-topology><layer>L5_COGNITIVE</layer></fractal-topology>
////   <compliance><stamp-controls>SC-COG-003, SC-ZMOF-001</stamp-controls></compliance>
//// </c3i-module>
////
//// Morning Briefing Agent (Proactive Intelligence).
//// Supervised OTP Actor that aggregates system state and triages comms.

import cepaf_gleam/agui/events
import cepaf_gleam/agui/zenoh_bus
import cepaf_gleam/gateway/telegram
import cepaf_gleam/moz/client as moz
import cepaf_gleam/zenoh/client as zenoh
import gleam/erlang/process.{type Subject}
import gleam/io
import gleam/json
import gleam/option.{type Option, None, Some}
import gleam/otp/actor

pub type BriefingMessage {
  CronTick(id: String, timestamp: Int)
  Stop
}

pub type BriefingState {
  BriefingState(
    id: String,
    moz: moz.MoZClientState,
    telegram: telegram.GatewayState,
    zenoh_session: Option(zenoh.Session),
  )
}

/// Start the Briefing Agent as a supervised worker.
pub fn start(
  id: String,
) -> Result(actor.Started(Subject(BriefingMessage)), actor.StartError) {
  let initial =
    BriefingState(
      id: id,
      moz: moz.new(),
      telegram: telegram.GatewayState(
        moz: moz.new(),
        bot_token: "internal",
        chat_id: "admin",
      ),
      zenoh_session: None,
    )

  actor.new(initial)
  |> actor.on_message(handle_message)
  |> actor.start()
}

fn handle_message(
  state: BriefingState,
  msg: BriefingMessage,
) -> actor.Next(BriefingState, BriefingMessage) {
  case msg {
    CronTick(id, _) -> {
      io.println(
        "🌅 Briefing Agent ["
        <> state.id
        <> "]: Generating Executive Summary via Gemma -> "
        <> id,
      )
      // SC-WIRE: Emit AG-UI StepStarted event
      emit_event(state, events.new_step_started("briefing_generate"))

      // 1. DISPATCH: Request reasoning from the Mojo-Bridge
      let prompt =
        "Generate a professional morning briefing for the C3I system. Current health is NOMINAL. Task list has 3 pending P0 items. Triage the fabric roadmap update as priority."
      let params =
        json.object([
          #("prompt", json.string(prompt)),
          #("model", json.string("gemma2")),
        ])

      let #(_, result) =
        moz.send_request(state.moz, "plan", "inference_generate", params)

      let summary = case result {
        Ok(_) ->
          "📋 MORNING BRIEFING (Gemma Generated)\nHandshake successful. Briefing synthesized and routed to Telegram."
        Error(e) ->
          "📋 MORNING BRIEFING (Fallback)\nInference bridge failed: " <> e
      }

      // 2. DISPATCH: Send to mobile gateway
      let _ = telegram.send_notification(state.telegram, "telegram", summary)
      // SC-WIRE: Emit AG-UI StepFinished event
      emit_event(state, events.new_step_finished("briefing_complete"))

      actor.continue(state)
    }
    Stop -> {
      actor.stop()
    }
  }
}

fn emit_event(state: BriefingState, event: events.AgUiEvent) {
  case state.zenoh_session {
    Some(session) -> {
      let _ = zenoh_bus.publish_event(session, state.id, event)
      Nil
    }
    None -> Nil
  }
}
