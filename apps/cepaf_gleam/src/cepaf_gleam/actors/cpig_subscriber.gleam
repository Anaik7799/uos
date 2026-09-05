//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/actors/cpig_subscriber</module>
////     <fsharp-lineage>N/A — new Gleam-first module (Pass-19)</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L4_SYSTEM</layer>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-CPIG-013, SC-CPIG-002, SC-ZMOF-001, SC-GLM-ZEN-001, SC-ZK-IMP-002</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective">
////       Zenoh `indrajaal/l4/cpig/**` pub/sub ↪ Gleam state machine.
////       Mitigation: Real Zenoh subscription wired via NIF in deployment;
////       this module owns decode + state + log envelope.
////     </morphism>
////     <morphism type="surjective" loss="zenoh-handle">
////       JSON `{score, pct, drift, as_of}` ↠ CpigState.
////       Mitigation: Unparseable payloads are logged + state retains last-good.
////     </morphism>
////   </transformations>
////   <zk-citations>[zk-bb4de67d97f807ac] — selector-guessing anti-pattern; recall:
////     state must be observed via real subscription, not synthesized.</zk-citations>
//// </c3i-module>
//// =============================================================================

import cepaf_gleam/ui/domain.{Bridge}
import cepaf_gleam/ui/zenoh_otel.{Observe}
import cepaf_gleam/zenoh/client as zenoh_client
import gleam/dynamic/decode
import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import simplifile

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/// Topic family this subscriber listens on (catch-all under cpig namespace).
pub const topic_family: String = "indrajaal/l4/cpig/"

/// Specific score topic published by the cpig-validator-hourly drift detector.
pub const score_topic: String = "indrajaal/l4/cpig/score"

/// Append-only log file for human/agent inspection.
pub const log_path: String = "/tmp/cpig-subscriber.log"

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/// CPIG drift snapshot held in memory between Zenoh deliveries.
pub type CpigState {
  CpigState(
    /// Last reported drift score in 0..60 (60 = pristine).
    last_score: Int,
    /// Last reported alignment percentage in 0..100.
    last_pct: Int,
    /// Last reported drift rule names that fired this cycle.
    last_drift: List(String),
    /// ISO-8601 timestamp from the publisher (`as_of` field).
    last_seen: String,
    /// Total number of payloads processed since boot.
    messages_processed: Int,
    /// Whether the most recent payload decoded cleanly.
    bridge_healthy: Bool,
  )
}

/// Messages handled by this subscriber.
pub type CpigSubscriberMsg {
  /// Inbound Zenoh delivery (topic, JSON payload).
  CpigEvent(topic: String, payload: String)
  /// Periodic health probe — re-emits OTel span without mutating score state.
  CpigHealthTick
  /// Graceful shutdown.
  CpigShutdown
}

// ---------------------------------------------------------------------------
// Mutable singleton (in-memory state mirror)
// ---------------------------------------------------------------------------

// We keep the actor pure (state-machine style, matching pi_subscriber). The
// `current_state/0` accessor returns the initial state until a real OTP
// supervisor wires this module to a Zenoh NIF subscription.

/// Public entry point — constructs initial state and emits a startup span.
/// Returns Ok(Nil) so callers can treat startup as a Result, matching the
/// rule contract `pub fn start() -> Result(Nil, String)`.
///
/// Defaults to scaffold-only mode (no live Zenoh subscription) so the actor
/// can be brought up safely even when the Zenoh router is offline. Use
/// `start_with_subscription(True)` (or set the env var `C3I_CPIG_LIVE=1`
/// before calling `start_from_env()`) to wire the real
/// `cepaf_gleam_ffi:zenoh_subscribe/3` primitive against
/// `indrajaal/l4/cpig/**`.
pub fn start() -> Result(Nil, String) {
  start_with_subscription(False)
}

/// Variant of `start/0` that optionally wires the real Zenoh NIF
/// subscription. When `enable_real_subscription` is True, this opens a Zenoh
/// session (singleton-safe — the FFI tolerates re-open) and registers the
/// current process as the receiver for `indrajaal/l4/cpig/**` deliveries.
///
/// Failure to subscribe is logged and reported as Error(_) but does NOT
/// panic — the in-memory state machine remains usable and callers may
/// retry. NIF (.so) absence falls back to scaffold-only mode.
pub fn start_with_subscription(
  enable_real_subscription: Bool,
) -> Result(Nil, String) {
  zenoh_otel.emit(Bridge, "cpig_subscriber_start", Observe)
  io.println(
    "CpigSubscriber start: topic_family="
    <> topic_family
    <> " log="
    <> log_path
    <> " live="
    <> string.inspect(enable_real_subscription),
  )

  case enable_real_subscription {
    False -> Ok(Nil)
    True -> wire_zenoh_subscription()
  }
}

/// Convenience wrapper that consults the `C3I_CPIG_LIVE` environment
/// variable. Set to "1" or "true" to enable real subscription.
pub fn start_from_env() -> Result(Nil, String) {
  let live = case read_env_flag("C3I_CPIG_LIVE") {
    "1" -> True
    "true" -> True
    "TRUE" -> True
    _ -> False
  }
  start_with_subscription(live)
}

@external(erlang, "os", "getenv")
fn os_getenv(name: String) -> String

fn read_env_flag(name: String) -> String {
  // os:getenv/1 returns false (atom) when unset; we coerce via string.inspect
  // to keep this pure-Gleam at the type level.
  let raw = string.inspect(os_getenv(name))
  case raw {
    "false" -> ""
    other -> other
  }
}

fn wire_zenoh_subscription() -> Result(Nil, String) {
  // Open Zenoh session (singleton-safe) — empty config = use defaults.
  case zenoh_client.open_nif("{}") {
    Error(err) -> {
      let line = "[!] cpig_subscriber zenoh_open failed: " <> err
      append_log(line)
      io.println(line)
      Error(err)
    }
    Ok(_) -> {
      // The Erlang FFI variant of subscribe takes a typed Session handle;
      // since the NIF path uses a global session, we re-open via the FFI
      // surface to obtain a Session value.
      case zenoh_client.open("{}") {
        Error(err) -> {
          let line = "[!] cpig_subscriber zenoh_open(ffi) failed: " <> err
          append_log(line)
          io.println(line)
          Error(err)
        }
        Ok(session) -> {
          let self = process.self()
          // Subscribe to the topic-family wildcard. Deliveries arrive as
          // Erlang messages to this Pid; an OTP supervisor (added in a
          // later pass) will translate them into CpigEvent values via
          // handle_message/2.
          case zenoh_client.subscribe(session, topic_family <> "**", self) {
            Error(err) -> {
              let line = "[!] cpig_subscriber zenoh_subscribe failed: " <> err
              append_log(line)
              io.println(line)
              Error(err)
            }
            Ok(_) -> {
              let line =
                "[+] cpig_subscriber subscribed to "
                <> topic_family
                <> "** pid="
                <> string.inspect(self)
              append_log(line)
              io.println(line)
              Ok(Nil)
            }
          }
        }
      }
    }
  }
}

/// Return the canonical initial CpigState.
pub fn current_state() -> CpigState {
  initial_state()
}

fn initial_state() -> CpigState {
  CpigState(
    last_score: 0,
    last_pct: 0,
    last_drift: [],
    last_seen: "",
    messages_processed: 0,
    bridge_healthy: False,
  )
}

// ---------------------------------------------------------------------------
// Message handler
// ---------------------------------------------------------------------------

/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">Zenoh delivery ↪ CpigState transition</morphism>
///   <formal-proof>
///     <P> Pre-condition: state is a valid CpigState. </P>
///     <C> handle_message(state, msg) </C>
///     <Q> Post-condition: returns a CpigState. Never panics. </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn handle_message(state: CpigState, msg: CpigSubscriberMsg) -> CpigState {
  case msg {
    CpigEvent(topic, payload) -> handle_cpig_event(state, topic, payload)
    CpigHealthTick -> handle_health_tick(state)
    CpigShutdown -> state
  }
}

fn handle_health_tick(state: CpigState) -> CpigState {
  zenoh_otel.emit(Bridge, "cpig_subscriber_tick", Observe)
  io.println(
    "CpigSubscriber tick: score="
    <> int.to_string(state.last_score)
    <> "/60 pct="
    <> int.to_string(state.last_pct)
    <> "% msgs="
    <> int.to_string(state.messages_processed),
  )
  state
}

fn handle_cpig_event(
  state: CpigState,
  topic: String,
  payload: String,
) -> CpigState {
  zenoh_otel.emit(Bridge, "cpig_event", Observe)

  case decode_cpig_payload(payload) {
    Ok(parsed) -> {
      let next =
        CpigState(
          last_score: parsed.score,
          last_pct: parsed.pct,
          last_drift: parsed.drift,
          last_seen: parsed.as_of,
          messages_processed: state.messages_processed + 1,
          bridge_healthy: True,
        )
      let line = format_log_line(topic, next)
      append_log(line)
      io.println(line)
      next
    }
    Error(err) -> {
      let line =
        "[?] cpig_subscriber_decode_error topic=" <> topic <> " err=" <> err
      append_log(line)
      io.println(line)
      CpigState(
        ..state,
        messages_processed: state.messages_processed + 1,
        bridge_healthy: False,
      )
    }
  }
}

// ---------------------------------------------------------------------------
// Payload decoding
// ---------------------------------------------------------------------------

type ParsedCpig {
  ParsedCpig(score: Int, pct: Int, drift: List(String), as_of: String)
}

fn decode_cpig_payload(payload: String) -> Result(ParsedCpig, String) {
  let decoder = {
    use score <- decode.field("score", decode.int)
    use pct <- decode.field("pct", decode.int)
    use drift <- decode.field("drift", decode.list(decode.string))
    use as_of <- decode.field("as_of", decode.string)
    decode.success(ParsedCpig(
      score: score,
      pct: pct,
      drift: drift,
      as_of: as_of,
    ))
  }
  json.parse(payload, decoder)
  |> result.map_error(fn(_) { "cpig payload did not match schema" })
}

// ---------------------------------------------------------------------------
// Logging
// ---------------------------------------------------------------------------

fn format_log_line(topic: String, state: CpigState) -> String {
  let drift_str = "[" <> string.join(state.last_drift, ",") <> "]"
  "["
  <> state.last_seen
  <> "] topic="
  <> topic
  <> " score="
  <> int.to_string(state.last_score)
  <> "/60 pct="
  <> int.to_string(state.last_pct)
  <> "% drift="
  <> drift_str
}

fn append_log(line: String) -> Nil {
  // Best-effort append — log failures must never crash the subscriber.
  let _ = simplifile.append(log_path, line <> "\n")
  Nil
}

// ---------------------------------------------------------------------------
// Public introspection / wiring helpers
// ---------------------------------------------------------------------------

/// Topic-family prefix used for subscription configuration. Wiring guard
/// asserts this value remains the canonical `indrajaal/l4/cpig/` prefix.
pub fn subscription_prefix() -> String {
  topic_family
}

/// Construct the initial state (used by wiring guard).
pub fn init_state() -> CpigState {
  initial_state()
}

/// Construct a CpigEvent message (used by wiring guard).
pub fn event_msg(topic: String, payload: String) -> CpigSubscriberMsg {
  CpigEvent(topic: topic, payload: payload)
}

/// Construct a CpigHealthTick message (used by wiring guard).
pub fn tick_msg() -> CpigSubscriberMsg {
  CpigHealthTick
}

/// Whether the message is a shutdown request.
pub fn is_shutdown(msg: CpigSubscriberMsg) -> Bool {
  case msg {
    CpigShutdown -> True
    _ -> False
  }
}

/// Count of drift rules captured in the last delivery.
pub fn drift_rule_count(state: CpigState) -> Int {
  list.length(state.last_drift)
}
