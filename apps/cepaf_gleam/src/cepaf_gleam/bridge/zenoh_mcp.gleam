// STAMP: SC-ZENOH-MCP-001, SC-BRIDGE-001
// AOR: AOR-GLM-001
// Criticality: Level 2 (HIGH) - Zenoh MCP Bridge
//
// Bridge between Zenoh Pub/Sub and MCP JSON-RPC.
// 1. Subscribes to Zenoh topics for MCP requests.
// 2. Dispatches requests to MCP tool handlers.
// 3. Publishes responses back to Zenoh.

import cepaf_gleam/mcp/server
import cepaf_gleam/zenoh/client as zenoh
import gleam/erlang/process.{type Subject}
import gleam/option.{None, Some}
import gleam/otp/actor
import gleam/result
import gleam/string

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

pub type State {
  State(session: zenoh.Session, node_id: String)
}

pub type Message {
  ZenohMessage(topic: String, payload: String)
}

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const request_prefix = "indrajaal/mcp/request/"

const response_prefix = "indrajaal/mcp/response/"

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Start the Zenoh MCP Bridge actor.
pub fn start(
  session: zenoh.Session,
  node_id: String,
) -> Result(Subject(Message), actor.StartError) {
  actor.new(State(session: session, node_id: node_id))
  |> actor.on_message(handle_message)
  |> actor.start()
  |> result.map(fn(started) {
    let subject = started.data
    // Subscribe to all MCP requests for this node or broadcast
    let assert Ok(pid) = process.subject_owner(subject)
    let _ = zenoh.subscribe(session, request_prefix <> "**", pid)
    subject
  })
}

// ---------------------------------------------------------------------------
// Message Handling
// ---------------------------------------------------------------------------

fn handle_message(state: State, msg: Message) -> actor.Next(State, Message) {
  case msg {
    ZenohMessage(topic, payload) -> {
      // Process the MCP request
      case process_request(state, topic, payload) {
        Ok(_) -> actor.continue(state)
        Error(_) -> actor.continue(state)
      }
    }
  }
}

fn process_request(
  state: State,
  topic: String,
  payload: String,
) -> Result(Nil, String) {
  // Extract client_id and request_id from topic if possible
  // Topic format: indrajaal/mcp/request/{client_id}/{request_id}
  let parts = string.split(topic, "/")
  let #(client_id, request_id) = case parts {
    [_, _, _, c, r] -> #(c, r)
    _ -> #("unknown", "unknown")
  }

  // Dispatch to MCP server logic
  // mcp/server.process_line returns Option(String) as JSON-RPC response
  case server.handle_request_raw(payload) {
    Some(response_json) -> {
      let resp_topic = response_prefix <> client_id <> "/" <> request_id
      zenoh.put(state.session, resp_topic, response_json)
    }
    None -> Ok(Nil)
  }
}

// ---------------------------------------------------------------------------
// FFI / Integration Helpers
// ---------------------------------------------------------------------------

/// This function should be called by the Erlang side when a Zenoh message arrives.
/// It maps the Erlang message to the Gleam Message type.
pub fn receive_zenoh_message(
  subject: Subject(Message),
  topic: String,
  payload: String,
) {
  process.send(subject, ZenohMessage(topic, payload))
}
