//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/actors/pi_subscriber</module>
////     <fsharp-lineage>N/A — new Gleam-first module</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L6_ECOSYSTEM</layer>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-PI-001, SC-PI-AUTO-001, SC-GLM-ZEN-001</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective">
////       Pi bridge pub/sub ↪ Gleam OTP actor (gleam/otp/actor).
////       Mitigation: Pi event types are proxied through the AG-UI 32-event bridge.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================

import cepaf_gleam/bridge/pi_agent
import cepaf_gleam/bridge/pi_claude_code
import cepaf_gleam/bridge/pi_provider
import cepaf_gleam/bridge/pi_tools
import cepaf_gleam/bridge/pi_zenoh
import cepaf_gleam/ui/domain.{Bridge}
import cepaf_gleam/ui/zenoh_otel.{Observe}
import gleam/int
import gleam/io
import gleam/string

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/// State held by the Pi subscriber actor.
pub type PiSubscriberState {
  PiSubscriberState(
    /// Number of Pi events processed since start.
    events_processed: Int,
    /// Number of tool invocations forwarded.
    tools_invoked: Int,
    /// Whether the Pi bridge is currently reachable.
    bridge_healthy: Bool,
  )
}

/// Messages handled by this actor.
pub type PiSubscriberMsg {
  /// Periodic health tick — re-probe Pi bridge and emit OTel span.
  PiHealthTick
  /// Process an inbound Pi event (topic, payload).
  PiEvent(topic: String, payload: String)
  /// Graceful shutdown request.
  PiShutdown
}

// ---------------------------------------------------------------------------
// Actor entry point
// ---------------------------------------------------------------------------

/// Initialize the Pi subscriber state (pure state machine, no OTP actor yet).
pub fn start() -> PiSubscriberState {
  initial_state()
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

fn initial_state() -> PiSubscriberState {
  PiSubscriberState(
    events_processed: 0,
    tools_invoked: 0,
    bridge_healthy: False,
  )
}

/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">Pi event pub/sub ↪ Gleam OTP actor message</morphism>
///   <formal-proof>
///     <P> Pre-condition: Actor is running and state is valid. </P>
///     <C> handle_message(state, msg) </C>
///     <Q> Post-condition: Returns Next(state, _). Never panics. </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn handle_message(
  state: PiSubscriberState,
  msg: PiSubscriberMsg,
) -> PiSubscriberState {
  case msg {
    PiHealthTick -> handle_health_tick(state)
    PiEvent(topic, payload) -> handle_pi_event(state, topic, payload)
    PiShutdown -> state
  }
}

pub fn handle_health_tick(state: PiSubscriberState) -> PiSubscriberState {
  // Probe Pi bridge vitals via the public API surface.
  let tool_count = pi_tools.tool_count()
  let event_count = pi_claude_code.mapped_pi_event_count()
  let tier_count = pi_provider.tier_count()
  let topics = pi_zenoh.all_pi_topics()
  let topic_count = list_length(topics)

  // Derive health from federated_tool_count parity.
  let healthy = tool_count == pi_agent.federated_tool_count

  // Emit OTel span (SC-GLM-ZEN-001).
  zenoh_otel.emit(Bridge, "pi_subscriber_tick", Observe)

  let summary =
    "PiSubscriber tick: tools="
    <> int.to_string(tool_count)
    <> " events="
    <> int.to_string(event_count)
    <> " tiers="
    <> int.to_string(tier_count)
    <> " topics="
    <> int.to_string(topic_count)
    <> " healthy="
    <> string.inspect(healthy)

  io.println(summary)

  PiSubscriberState(..state, bridge_healthy: healthy)
}

pub fn handle_pi_event(
  state: PiSubscriberState,
  topic: String,
  payload: String,
) -> PiSubscriberState {
  // Emit OTel span for each inbound Pi event (SC-PI-001, SC-GLM-ZEN-001).
  zenoh_otel.emit(Bridge, "pi_event", Observe)

  io.println("PiSubscriber event on " <> topic <> ": " <> payload)

  PiSubscriberState(..state, events_processed: state.events_processed + 1)
}

// ---------------------------------------------------------------------------
// Utility — avoids importing gleam/list just for length
// ---------------------------------------------------------------------------

fn list_length(lst: List(a)) -> Int {
  do_list_length(lst, 0)
}

fn do_list_length(lst: List(a), acc: Int) -> Int {
  case lst {
    [] -> acc
    [_, ..rest] -> do_list_length(rest, acc + 1)
  }
}

// ---------------------------------------------------------------------------
// Public introspection helpers
// ---------------------------------------------------------------------------

/// Return a summary string describing the current Pi bridge configuration.
pub fn bridge_summary() -> String {
  let tool_count = pi_tools.tool_count()
  let event_count = pi_claude_code.mapped_pi_event_count()
  let tier_count = pi_provider.tier_count()

  "Pi bridge: "
  <> int.to_string(tool_count)
  <> " tools, "
  <> int.to_string(event_count)
  <> " events, "
  <> int.to_string(tier_count)
  <> " inference tiers"
}

/// Emit a health probe span and return whether the bridge is at expected parity.
pub fn probe_health() -> Bool {
  zenoh_otel.emit(Bridge, "pi_health_probe", Observe)
  pi_tools.tool_count() == pi_agent.federated_tool_count
}

// ---------------------------------------------------------------------------
// Wiring guard helpers — used by testing/wiring_guard.gleam
// ---------------------------------------------------------------------------

/// Construct an initial PiSubscriberState (for wiring guard).
pub fn init_state() -> PiSubscriberState {
  initial_state()
}

/// Construct the PiHealthTick message (for wiring guard).
pub fn tick_msg() -> PiSubscriberMsg {
  PiHealthTick
}

/// Construct a PiEvent message (for wiring guard).
pub fn event_msg(topic: String, payload: String) -> PiSubscriberMsg {
  PiEvent(topic: topic, payload: payload)
}

/// Determine whether a shutdown has been requested.
pub fn is_shutdown(msg: PiSubscriberMsg) -> Bool {
  case msg {
    PiShutdown -> True
    _ -> False
  }
}
