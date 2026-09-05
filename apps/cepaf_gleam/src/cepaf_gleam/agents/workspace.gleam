//// [C3I-SIL6-MSTS] <c3i-module><identity><module>cepaf_gleam/agents/workspace</module></identity>
////   <fractal-topology><layer>L5_COGNITIVE</layer></fractal-topology>
////   <compliance><stamp-controls>SC-COG-003, SC-ZMOF-001</stamp-controls></compliance>
//// </c3i-module>
////
//// Google Workspace Orchestrator (Gmail/Calendar/Drive/Sheets/Docs/Slides).
//// Managed OTP Actor that provides deep integration with abhijit.naik@boutytek.com.

import cepaf_gleam/agui/events
import cepaf_gleam/agui/zenoh_bus
import cepaf_gleam/moz/client as moz
import cepaf_gleam/zenoh/client as zenoh
import gleam/erlang/process.{type Subject}
import gleam/io
import gleam/json
import gleam/option.{type Option, None}
import gleam/otp/actor

pub type WorkspaceMessage {
  TriageDailyFlow
  SearchKnowledge(query: String)
  UpdateReport(doc_id: String, content: String)
  UpdateTracking(sheet_id: String, range: String, data: String)
  GenerateBriefingSlides(title: String)
  Stop
}

pub type WorkspaceState {
  WorkspaceState(
    id: String,
    account: String,
    moz: moz.MoZClientState,
    zenoh_session: Option(zenoh.Session),
  )
}

/// Start the Workspace Agent as a supervised worker.
pub fn start(
  id: String,
  account: String,
) -> Result(actor.Started(Subject(WorkspaceMessage)), actor.StartError) {
  let initial =
    WorkspaceState(
      id: id,
      account: account,
      moz: moz.new(),
      zenoh_session: None,
    )

  actor.new(initial)
  |> actor.on_message(handle_message)
  |> actor.start()
}

fn handle_message(
  state: WorkspaceState,
  msg: WorkspaceMessage,
) -> actor.Next(WorkspaceState, WorkspaceMessage) {
  case msg {
    TriageDailyFlow -> {
      io.println(
        "🧠 Workspace [" <> state.id <> "]: Triaging account " <> state.account,
      )
      // SC-WIRE: Emit AG-UI event
      emit_event(state, events.new_step_started("workspace_triage"))
      let _ =
        moz.send_request(
          state.moz,
          "plan",
          "calendar_get_agenda",
          json.object([]),
        )
      let _ =
        moz.send_request(
          state.moz,
          "plan",
          "gmail_list_unread",
          json.object([]),
        )
      actor.continue(state)
    }
    SearchKnowledge(query) -> {
      io.println(
        "🧠 Workspace ["
        <> state.id
        <> "]: Searching knowledge base for '"
        <> query
        <> "'",
      )
      let _ =
        moz.send_request(
          state.moz,
          "plan",
          "drive_search_files",
          json.object([#("query", json.string(query))]),
        )
      actor.continue(state)
    }
    UpdateReport(id, content) -> {
      io.println("🧠 Workspace [" <> state.id <> "]: Updating report " <> id)
      let _ =
        moz.send_request(
          state.moz,
          "plan",
          "docs_create_document",
          json.object([#("title", json.string(content))]),
        )
      actor.continue(state)
    }
    UpdateTracking(id, range, _) -> {
      io.println(
        "🧠 Workspace ["
        <> state.id
        <> "]: Updating tracking sheet "
        <> id
        <> " at "
        <> range,
      )
      let _ =
        moz.send_request(
          state.moz,
          "plan",
          "sheets_update_values",
          json.object([
            #("spreadsheet_id", json.string(id)),
            #("range", json.string(range)),
          ]),
        )
      actor.continue(state)
    }
    GenerateBriefingSlides(title) -> {
      io.println(
        "🧠 Workspace [" <> state.id <> "]: Generating slides: " <> title,
      )
      let _ =
        moz.send_request(
          state.moz,
          "plan",
          "slides_create_presentation",
          json.object([#("title", json.string(title))]),
        )
      actor.continue(state)
    }
    Stop -> actor.stop()
  }
}

fn emit_event(state: WorkspaceState, event: events.AgUiEvent) {
  case state.zenoh_session {
    option.Some(session) -> {
      let _ = zenoh_bus.publish_event(session, state.id, event)
      Nil
    }
    None -> Nil
  }
}
