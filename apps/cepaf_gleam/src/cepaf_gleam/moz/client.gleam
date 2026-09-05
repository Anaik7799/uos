//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/moz/client</module>
////     <fsharp-lineage>Cepaf.Moz.Client.fs (new — no F# lineage, Gleam-native)</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L5_COGNITIVE</layer>
////     <mesh-domain>MCP-over-Zenoh (MoZ) Transport Client</mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>DAL-A / SIL-6 / HIGH</criticality>
////     <stamp-controls>SC-ZMOF-001, SC-ZMOF-005, SC-GLM-UI-003, SC-GLM-UI-004</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective" augmentation="circuit-breaker">
////       JSON-RPC 2.0 request/response layered over Zenoh pub/sub.
////       Circuit breaker guards against cascading failures when the Rust
////       MCP bridge is unavailable.
////     </morphism>
////     <morphism type="surjective" loss="response-correlation">
////       Async request/response correlation (response_topic subscription)
////       is not wired in this module — the caller receives the request_id
////       and subscribes to the response topic independently.
////       Mitigation: build_response_topic/1 exported for caller convenience.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// MoZ Client — JSON-RPC 2.0 request dispatch over Zenoh pub/sub.
////
//// Sends requests to the Rust ignition daemon MCP bridge via:
////   Request  topic: indrajaal/l4/ignition/mcp/req/{method}/{request_id}
////   Response topic: indrajaal/l4/ignition/mcp/res/{request_id}
////
//// Active methods accepted by the bridge: "launch", "restart", "drain"
////
//// Error codes from the bridge:
////   -32601  Method not found
////   -32602  Invalid params
////   -32000  Server error
////
//// SC-ZMOF-001: Zenoh is the SOLE internal transport for mesh communication.
//// SC-ZMOF-005: Actionable features MUST be exposed as MoZ tools.

import cepaf_gleam/prajna/circuit_breaker.{
  type Breaker, BreakerClosed, BreakerHalfOpen, BreakerOpen,
}
import cepaf_gleam/zenoh/client as zenoh
import gleam/json
import gleam/option.{type Option, None, Some}
import gleam/string

// =============================================================================
// FFI Bindings
// =============================================================================

@external(erlang, "cepaf_gleam_ffi", "generate_id")
fn generate_id() -> String

@external(erlang, "cepaf_gleam_ffi", "system_time_nanos")
fn system_time_nanos() -> Int

// =============================================================================
// Constants
// =============================================================================

/// Zenoh topic prefix for MoZ requests.
/// Full topic: {request_topic_prefix}/{domain}/{method}/{request_id}
pub const request_topic_prefix = "indrajaal/l5/cog/mcp/req"

/// Zenoh topic prefix for MoZ responses.
/// Full topic: {response_topic_prefix}/{request_id}
pub const response_topic_prefix = "indrajaal/l5/cog/mcp/res"

/// Zenoh topic prefix for MoZ queries (synchronous GET).
/// Full topic: {query_topic_prefix}/{domain}/{method}
pub const query_topic_prefix = "indrajaal/l5/cog/mcp/query"

/// Number of consecutive Zenoh publish failures before the circuit opens.
pub const max_consecutive_failures = 5

// =============================================================================
// Types
// =============================================================================

/// A pending MoZ JSON-RPC request awaiting a response.
pub type MoZRequest {
  MoZRequest(method: String, params: json.Json, request_id: String)
}

/// An error returned in a JSON-RPC 2.0 response from the Rust bridge.
pub type MoZError {
  MoZError(code: Int, message: String)
}

/// A parsed MoZ JSON-RPC 2.0 response.
pub type MoZResponse {
  MoZResponse(result: Result(json.Json, MoZError), request_id: String)
}

/// Client state holding the circuit breaker and in-flight requests.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <formal-proof>
///     <P> circuit.state in {Closed, HalfOpen, Open} </P>
///     <C> send_request / record_success / record_failure </C>
///     <Q> consecutive_failures monotonically increases until circuit opens;
///         resets to 0 on successful close transition. </Q>
///   </formal-proof>
/// </c3i-atomic>
pub type MoZClientState {
  MoZClientState(
    circuit: Breaker,
    pending: List(MoZRequest),
    consecutive_failures: Int,
    session: Option(zenoh.Session),
  )
}

// =============================================================================
// Constructor
// =============================================================================

/// Create a new MoZ client with a closed circuit breaker.
///
/// The breaker is configured with:
///   failure_threshold  = max_consecutive_failures (5)
///   success_threshold  = 2   (half-open needs 2 successes to close)
///   reset_timeout_ms   = 30_000 (30 s — matches SC-ZENOH-005 reconnect window)
pub fn new() -> MoZClientState {
  MoZClientState(
    circuit: circuit_breaker.create(
      "moz_client",
      max_consecutive_failures,
      2,
      30_000,
    ),
    pending: [],
    consecutive_failures: 0,
    session: None,
  )
}

// =============================================================================
// Topic Builders
// =============================================================================

/// Build the Zenoh publish topic for a request.
///
/// Pattern: {request_topic_prefix}/{domain}/{method}/{request_id}
pub fn build_request_topic(
  domain: String,
  method: String,
  request_id: String,
) -> String {
  string.join([request_topic_prefix, domain, method, request_id], "/")
}

/// Build the Zenoh subscribe topic for the corresponding response.
///
/// Pattern: indrajaal/l5/cog/mcp/res/{request_id}
pub fn build_response_topic(request_id: String) -> String {
  string.join([response_topic_prefix, request_id], "/")
}

// =============================================================================
// JSON-RPC 2.0 Encoder
// =============================================================================

/// Encode a JSON-RPC 2.0 request payload as a JSON string.
///
/// Output:
///   {"jsonrpc":"2.0","method":"<method>","params":<params>,"id":"<request_id>"}
pub fn build_request_json(
  method: String,
  params: json.Json,
  request_id: String,
) -> String {
  json.object([
    #("jsonrpc", json.string("2.0")),
    #("method", json.string(method)),
    #("params", params),
    #("id", json.string(request_id)),
  ])
  |> json.to_string()
}

// =============================================================================
// Core Send
// =============================================================================

/// Attempt to send a JSON-RPC 2.0 request over Zenoh.
///
/// Returns the updated state and either:
///   Ok(request_id)  — request published; caller subscribes to response topic
///   Error(reason)   — circuit open or Zenoh unavailable; request NOT sent
///
/// Graceful degradation (SC-ZMOF-001, SC-GLM-CORE-002):
///   - If circuit is open  → Error("circuit_open"), state unchanged
///   - If Zenoh open fails → Error(reason), record_failure applied
///   - If Zenoh put fails  → Error(reason), record_failure applied
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">Zenoh put ↪ async fire-and-forget dispatch</morphism>
///   <formal-proof>
///     <P> method in {"launch","restart","drain","plan_list",...} (caller responsibility) </P>
///     <C> send_request(state, domain, method, params) </C>
///     <Q> Result(request_id, reason) with state reflecting failure/success delta </Q>
///   </formal-proof>
/// </c3i-atomic>
/// Attaches an existing persistent Zenoh session to the client state (SC-ZMOF-001).
pub fn with_session(state: MoZClientState, session: zenoh.Session) -> MoZClientState {
  MoZClientState(..state, session: Some(session))
}

/// Discards any cached Zenoh session on disconnection or transport failure.
pub fn invalidate_session(state: MoZClientState) -> MoZClientState {
  MoZClientState(..state, session: None)
}

/// Ensures a persistent Zenoh session is active, reusing existing or opening on demand.
pub fn ensure_session(
  state: MoZClientState,
) -> #(MoZClientState, Result(zenoh.Session, String)) {
  case state.session {
    Some(s) -> #(state, Ok(s))
    None -> {
      case zenoh.open("{}") {
        Ok(s) -> {
          let new_state = MoZClientState(..state, session: Some(s))
          #(new_state, Ok(s))
        }
        Error(err) -> #(state, Error(err))
      }
    }
  }
}

pub fn send_request(
  state: MoZClientState,
  domain: String,
  method: String,
  params: json.Json,
) -> #(MoZClientState, Result(String, String)) {
  case circuit_breaker.is_allowed(state.circuit) {
    False -> #(state, Error("circuit_open"))
    True -> {
      let request_id = generate_id()
      let topic = build_request_topic(domain, method, request_id)
      let payload = build_request_json(method, params, request_id)
      let request =
        MoZRequest(method: method, params: params, request_id: request_id)

      let #(state1, session_res) = ensure_session(state)
      case session_res {
        Error(reason) -> {
          let new_state = record_failure(state1)
          #(new_state, Error("zenoh_open_failed: " <> reason))
        }
        Ok(session) -> {
          case zenoh.put(session, topic, payload) {
            Error(reason) -> {
              let new_state = record_failure(state1) |> invalidate_session
              #(new_state, Error("zenoh_put_failed: " <> reason))
            }
            Ok(Nil) -> {
              let new_pending = [request, ..state1.pending]
              let new_state =
                MoZClientState(
                  ..state1,
                  pending: new_pending,
                  consecutive_failures: 0,
                )
              #(new_state, Ok(request_id))
            }
          }
        }
      }
    }
  }
}

/// Attempt to send a JSON-RPC 2.0 query over Zenoh (synchronous GET).
///
/// Returns the updated state and either:
///   Ok(json_payload) — query replied successfully
///   Error(reason)    — circuit open, Zenoh unavailable, or query timeout
pub fn send_query(
  state: MoZClientState,
  domain: String,
  method: String,
) -> #(MoZClientState, Result(String, String)) {
  case circuit_breaker.is_allowed(state.circuit) {
    False -> #(state, Error("circuit_open"))
    True -> {
      let topic = string.join([query_topic_prefix, domain, method], "/")

      let #(state1, session_res) = ensure_session(state)
      case session_res {
        Error(reason) -> {
          let new_state = record_failure(state1)
          #(new_state, Error("zenoh_open_failed: " <> reason))
        }
        Ok(session) -> {
          case zenoh.get(session, topic) {
            Error(reason) -> {
              let new_state = record_failure(state1) |> invalidate_session
              #(new_state, Error("zenoh_get_failed: " <> reason))
            }
            Ok(payload) -> {
              let new_state = record_success(state1)
              #(new_state, Ok(payload))
            }
          }
        }
      }
    }
  }
}

// =============================================================================
// Circuit Feedback
// =============================================================================

/// Record a successful response — resets consecutive failures.
///
/// If the circuit is half-open and the breaker's success threshold is met,
/// the circuit transitions back to closed.
pub fn record_success(state: MoZClientState) -> MoZClientState {
  MoZClientState(
    ..state,
    circuit: circuit_breaker.record_success(state.circuit),
    consecutive_failures: 0,
  )
}

/// Record a transport failure — increments consecutive failures.
///
/// Once consecutive_failures reaches max_consecutive_failures,
/// the circuit opens and all further send_request calls return Error("circuit_open")
/// until the reset_timeout_ms window elapses and a half-open probe succeeds.
pub fn record_failure(state: MoZClientState) -> MoZClientState {
  let now_ms = system_time_nanos() / 1_000_000
  let new_failures = state.consecutive_failures + 1
  MoZClientState(
    ..state,
    circuit: circuit_breaker.record_failure(state.circuit, now_ms),
    consecutive_failures: new_failures,
  )
}

// =============================================================================
// State Query
// =============================================================================

/// Returns True when the circuit is not open (requests can be sent).
pub fn is_available(state: MoZClientState) -> Bool {
  case state.circuit.state {
    BreakerOpen(_) -> False
    BreakerClosed -> True
    BreakerHalfOpen -> True
  }
}

/// Returns the circuit breaker state as a plain string for health reporting.
///
/// Values:
///   "closed"    — circuit healthy, requests flow normally
///   "half_open" — circuit probing recovery (one probe in flight)
///   "open"      — circuit tripped, all requests rejected until reset_timeout_ms elapses
///
/// Intended for use in health endpoints so operators can observe MoZ transport
/// availability without importing circuit_breaker internals (SC-ZMOF-001).
pub fn circuit_status(state: MoZClientState) -> String {
  case state.circuit.state {
    BreakerClosed -> "closed"
    BreakerHalfOpen -> "half_open"
    BreakerOpen(_) -> "open"
  }
}
