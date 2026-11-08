// STAMP: SC-ZENOH-MCP-001, SC-BRIDGE-001
// AOR: AOR-GLM-001
// Criticality: Level 2 (HIGH) - Zenoh MCP Bridge
//
// Bridge between Zenoh Pub/Sub and MCP JSON-RPC.
// 1. Subscribes to Zenoh topics for MCP requests.
// 2. Dispatches requests to MCP tool handlers.
// 3. Publishes responses back to Zenoh.

import cepaf_gleam/mcp/runtime_gateway
import cepaf_gleam/zenoh/client as zenoh
import gleam/dynamic.{type Dynamic}
import gleam/erlang/atom
import gleam/erlang/process.{type Subject}
import gleam/option.{None, Some}
import gleam/otp/actor
import gleam/result

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

pub type State {
  State(session: zenoh.Session, node_id: String)
}

pub type Message {
  ZenohMessage(topic: String, payload: String)
  /// A push delivered by the UOS-ZLP-v3 hyperplane subscription.
  ///
  /// `uos_zlp_shard.erl:109` sends the raw tuple
  /// `{zlp_zenoh_push, ShardId, Excl, Digest, JsonBin}` straight to the
  /// subscriber pid, not through the actor's Subject. A matching constructor is
  /// therefore not sufficient on its own: gleam_otp selects on the Subject, so
  /// an unselected raw message is dropped whatever its shape. The selector
  /// installed in `start_subscribed` maps the tuple into this variant.
  ///
  /// Before that selector existed the actor logged
  /// "Actor discarding unexpected message: ZlpZenohPush(...)" and dropped every
  /// inbound MCP request arriving over a ZLP subscription. Observed live in
  /// `formal/lean/ruliad/diff/zenoh_live.erl`.
  ZlpPush(json: String)
}

/// Split a ZLP push into its key and its value re-serialised as JSON text.
/// Public so every consumer of `Message` decodes a push the same way; a second
/// decode path would be a second chance to get the signed bytes wrong.
@external(erlang, "zenoh_mcp_ffi", "split_push")
pub fn split_push(json: String) -> Result(#(String, String), Nil)

/// Pull the JSON body out of a raw ZLP push tuple delivered to the pid.
@external(erlang, "zenoh_mcp_ffi", "push_json")
fn push_json(message: Dynamic) -> Result(String, Nil)

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const request_prefix = "indrajaal/mcp/request/"

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Start the Zenoh MCP Bridge actor.
pub fn start(
  session: zenoh.Session,
  node_id: String,
) -> Result(Subject(Message), actor.StartError) {
  case zenoh.supports_subscriptions(session) {
    False -> Error(actor.InitFailed("zenoh_rest_subscriptions_unsupported"))
    True -> start_subscribed(session, node_id)
  }
}

fn start_subscribed(
  session: zenoh.Session,
  node_id: String,
) -> Result(Subject(Message), actor.StartError) {
  actor.new_with_initialiser(5000, fn(self) {
    // The ZLP shard sends a raw 5-tuple to the pid rather than over the
    // Subject, so the Subject alone cannot see it. Selecting the record tag
    // explicitly is what makes an inbound subscription push reachable.
    let selector =
      process.new_selector()
      |> process.select(self)
      |> process.select_record(
        tag: atom.create("zlp_zenoh_push"),
        fields: 4,
        mapping: fn(message) {
          case push_json(message) {
            Ok(json) -> ZlpPush(json)
            // An undecodable push becomes an empty body, which
            // `handle_message` drops. The gateway is never handed a guess.
            Error(_) -> ZlpPush("")
          }
        },
      )
    Ok(
      actor.initialised(State(session: session, node_id: node_id))
      |> actor.selecting(selector)
      |> actor.returning(self),
    )
  })
  |> actor.on_message(handle_message)
  |> actor.start()
  |> result.map(fn(started) {
    let subject = started.data
    // Subscribe to all MCP requests for this node or broadcast
    case process.subject_owner(subject) {
      Ok(pid) -> {
        let _ = zenoh.subscribe(session, request_prefix <> "**", pid)
        Nil
      }
      Error(_) -> Nil
    }
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
    // A subscription push carries the key and envelope inside its JSON body.
    // A push that does not decode is dropped rather than guessed at: the
    // gateway must never be handed a partially reconstructed envelope, because
    // the signature covers exact bytes.
    ZlpPush("") -> actor.continue(state)
    ZlpPush(json) ->
      case split_push(json) {
        Ok(#(topic, payload)) ->
          case process_request(state, topic, payload) {
            Ok(_) -> actor.continue(state)
            Error(_) -> actor.continue(state)
          }
        Error(_) -> actor.continue(state)
      }
  }
}

fn process_request(
  state: State,
  topic: String,
  payload: String,
) -> Result(Nil, String) {
  case runtime_gateway.handle_zenoh_raw(topic, payload) {
    Some(#(resp_topic, response_json)) ->
      zenoh.put(state.session, resp_topic, response_json)
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
