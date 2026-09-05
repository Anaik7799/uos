//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ha/heartbeat_monitor</module>
////     <fsharp-lineage>None — novel Gleam implementation</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L4_SYSTEM</layer>
////     <mesh-domain>Bidirectional heartbeat: Gleam ↔ Rust sa-plan-daemon</mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-HA-001, SC-FUNC-002, SC-BIO-EVO-001</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective">
////       Gleam pings Rust NIF → measures latency → detects death → failover.
////       Circulatory system: heart pumping blood between Gleam and Rust organs.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// BIDIRECTIONAL HEARTBEAT MONITOR
//// द्विदिशा हृदय-स्पन्दन निगरानी
////
//// Gleam-side monitor that pings the Rust sa-plan-daemon via NIF.
//// If Rust is unresponsive for 3 consecutive checks, triggers failover
//// to pure-Gleam RETE-UL engine (no NIF dependency).
////
//// STAMP: SC-HA-001, SC-FUNC-002, SC-BIO-EVO-001

import cepaf_gleam/c3i/nif as c3i_nif
import gleam/int
import gleam/io
import gleam/string

/// Heartbeat state — tracks Rust daemon liveness.
pub type HeartbeatState {
  HeartbeatState(
    /// Whether the Rust daemon responded to the last ping
    rust_alive: Bool,
    /// Timestamp (cycle count) of last successful ping
    last_pong_cycle: Int,
    /// Number of consecutive ping failures
    consecutive_failures: Int,
    /// Total pings sent
    total_pings: Int,
    /// Total successful pongs received
    total_pongs: Int,
    /// Whether failover to pure-Gleam RETE-UL is active
    failover_active: Bool,
    /// Last latency measurement (string length as proxy)
    last_response_size: Int,
  )
}

/// Result of a heartbeat ping cycle.
pub type HeartbeatResult {
  /// Rust daemon responded with valid data
  RustAlive(response_size: Int)
  /// Rust daemon did not respond (consecutive failures tracked)
  RustUnresponsive(failures: Int)
  /// Failover threshold reached — switch to pure-Gleam RETE-UL
  FailoverTriggered(failures: Int)
}

/// Failover threshold — number of consecutive failures before failover.
const failover_threshold = 3

/// Initialize heartbeat monitor state.
pub fn init() -> HeartbeatState {
  HeartbeatState(
    rust_alive: True,
    last_pong_cycle: 0,
    consecutive_failures: 0,
    total_pings: 0,
    total_pongs: 0,
    failover_active: False,
    last_response_size: 0,
  )
}

/// Execute one heartbeat ping cycle.
/// Calls plan_status NIF — if Rust daemon is alive, it returns data.
/// If dead, returns empty or error → increment failure counter.
pub fn ping(state: HeartbeatState) -> #(HeartbeatState, HeartbeatResult) {
  let new_total = state.total_pings + 1
  let response = c3i_nif.plan_status()
  let response_size = string.length(response)
  let is_alive = response_size > 2 && string.contains(response, "total")

  case is_alive {
    True -> {
      let new_state =
        HeartbeatState(
          rust_alive: True,
          last_pong_cycle: new_total,
          consecutive_failures: 0,
          total_pings: new_total,
          total_pongs: state.total_pongs + 1,
          failover_active: False,
          last_response_size: response_size,
        )
      #(new_state, RustAlive(response_size))
    }
    False -> {
      let new_failures = state.consecutive_failures + 1
      let should_failover = new_failures >= failover_threshold
      let new_state =
        HeartbeatState(
          ..state,
          rust_alive: False,
          consecutive_failures: new_failures,
          total_pings: new_total,
          failover_active: should_failover,
          last_response_size: 0,
        )
      let result = case should_failover {
        True -> FailoverTriggered(new_failures)
        False -> RustUnresponsive(new_failures)
      }
      #(new_state, result)
    }
  }
}

/// Execute the action associated with a heartbeat result (side effects).
pub fn execute_result(result: HeartbeatResult) -> Nil {
  case result {
    RustAlive(_) -> Nil
    RustUnresponsive(n) -> {
      io.println(
        "[HEARTBEAT-WARN] Rust daemon unresponsive — "
        <> int.to_string(n)
        <> " consecutive failures",
      )
      Nil
    }
    FailoverTriggered(n) -> {
      io.println(
        "[HEARTBEAT-FAILOVER] Rust daemon dead after "
        <> int.to_string(n)
        <> " failures — activating pure-Gleam RETE-UL fallback",
      )
      Nil
    }
  }
}

/// Whether failover should be activated.
pub fn should_failover(state: HeartbeatState) -> Bool {
  state.consecutive_failures >= failover_threshold
}

/// Uptime ratio: pongs/pings.
pub fn uptime_ratio(state: HeartbeatState) -> Float {
  case state.total_pings {
    0 -> 1.0
    _ -> int_to_float(state.total_pongs) /. int_to_float(state.total_pings)
  }
}

/// Health score for the circulatory subsystem [0.0, 1.0].
pub fn health(state: HeartbeatState) -> Float {
  case state.rust_alive, state.failover_active {
    True, _ -> 1.0
    False, False ->
      1.0
      -. {
        int_to_float(state.consecutive_failures)
        /. int_to_float(failover_threshold)
      }
    False, True -> 0.2
  }
}

/// Human-readable status string.
pub fn status_string(state: HeartbeatState) -> String {
  let alive_str = case state.rust_alive {
    True -> "ALIVE"
    False -> "DEAD"
  }
  let failover_str = case state.failover_active {
    True -> " [FAILOVER]"
    False -> ""
  }
  "Rust: "
  <> alive_str
  <> failover_str
  <> " (pings: "
  <> int.to_string(state.total_pings)
  <> ", pongs: "
  <> int.to_string(state.total_pongs)
  <> ", failures: "
  <> int.to_string(state.consecutive_failures)
  <> ")"
}

fn int_to_float(n: Int) -> Float {
  int.to_float(n)
}
