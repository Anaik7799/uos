//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/bridge/pi_daemon</module>
////     <fsharp-lineage>No F# lineage — Gleam-native OTP actor</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L4_SYSTEM</layer>
////     <mesh-domain>Pi-mono JSONL RPC Persistent Daemon</mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>DAL-A / SIL-6 / HIGH</criticality>
////     <stamp-controls>
////       SC-PI-RUNTIME-001, SC-PI-RUNTIME-002, SC-PI-RUNTIME-003,
////       SC-PI-RUNTIME-004, SC-PI-RUNTIME-005, SC-PI-RUNTIME-006,
////       SC-PI-RUNTIME-007, SC-PI-RUNTIME-008,
////       SC-GLM-ZEN-001, SC-ARCH-SPLIT-003, SC-MUDA-001
////     </stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective" augmentation="erlang-port-otp">
////       Node.js child process ↪ BEAM OTP actor (gleam_otp actor)
////       via erlang:open_port + JSONL stdio protocol.
////       Mitigation: process exit captured via port exit_status;
////       circuit breaker (3 failures / 60s) prevents crash loops.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// Pi Daemon — Real OTP actor managing a persistent Pi-mono RPC process.
////
//// Architecture:
////   1. Port-spawn: erlang:open_port via pi_port_open/3 FFI
////   2. JSONL-over-stdio: one JSON object per line
////   3. Request correlation: Dict(String, Subject(Result(String,PiError)))
////   4. Circuit breaker: 3 consecutive failures / 60s → Open
////   5. OTel publish to indrajaal/l5/agent/pi/{event} (SC-GLM-ZEN-001)
////   6. Public API: send_prompt/2, is_healthy/1, dashboard_summary/1
////
//// Test mocking: override RuntimeConfig.cli_path to "/bin/cat" so the port
//// stays alive, reads stdin, and echoes back — no real Node.js needed.

import cepaf_gleam/bridge/pi_rpc
import cepaf_gleam/bridge/pi_runtime.{
  type CircuitState, type RuntimeConfig, Closed, HalfOpen, Open, default_config,
}
import cepaf_gleam/ui/domain.{Bridge}
import cepaf_gleam/ui/zenoh_otel.{Observe}
import gleam/bit_array
import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/json
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/string

// =============================================================================
// Public types
// =============================================================================

pub type PiError {
  /// Circuit breaker is open — daemon will not accept requests
  CircuitOpen
  /// Request timed out (no response within deadline)
  Timeout
  /// Port is not open / daemon not running
  NotRunning
  /// The Pi process returned an error in its RPC response
  RpcError(String)
  /// Internal actor mailbox error
  ActorError(String)
}

/// Opaque handle to the running daemon actor
pub opaque type PiDaemon {
  PiDaemon(subject: Subject(DaemonMsg))
}

/// Public accessor for the BEAM Pid hosting this actor — used by the
/// supervisor to register a child Pid (SC-PI-RUNTIME-003 supervision).
pub fn pid(daemon: PiDaemon) -> process.Pid {
  process.subject_owner(daemon.subject)
  |> result_pid_or_self
}

fn result_pid_or_self(r: Result(process.Pid, Nil)) -> process.Pid {
  case r {
    Ok(p) -> p
    Error(_) -> process.self()
  }
}

// =============================================================================
// Internal actor message type
// =============================================================================

type DaemonMsg {
  /// External: send a prompt and return the response
  SendPrompt(prompt: String, reply_to: Subject(Result(String, PiError)))
  /// External: query health
  IsHealthy(reply_to: Subject(Bool))
  /// External: get JSON summary
  DashboardSummary(reply_to: Subject(String))
  /// Internal: data arrived from port
  PortData(data: BitArray)
  /// Internal: port closed / process exited
  PortExit(status: Int)
  /// Internal: stop actor cleanly
  Shutdown
}

// =============================================================================
// Internal actor state
// =============================================================================

type DaemonState {
  DaemonState(
    config: RuntimeConfig,
    port: Option(Port),
    circuit: CircuitState,
    failure_count: Int,
    failure_window_start: Int,
    prompts_ok: Int,
    prompts_err: Int,
    req_counter: Int,
    // pending[id_string] = Subject waiting for the matching RPC response
    pending: Dict(String, Subject(Result(String, PiError))),
    // accumulation buffer for partial JSONL lines
    line_buf: String,
  )
}

// We model the Erlang port as an opaque external value.
type Port =
  #(#())

// =============================================================================
// FFI bindings (Erlang pi_port_open/send/close)
// =============================================================================

@external(erlang, "cepaf_gleam_ffi", "pi_port_open")
fn ffi_port_open(
  cmd: String,
  args: List(String),
  env: List(#(String, String)),
) -> Result(Port, String)

@external(erlang, "cepaf_gleam_ffi", "pi_port_send")
fn ffi_port_send(port: Port, data: BitArray) -> Result(Nil, Nil)

@external(erlang, "cepaf_gleam_ffi", "pi_port_close")
fn ffi_port_close(port: Port) -> Nil

// =============================================================================
// Time helper (milliseconds since epoch)
// =============================================================================

@external(erlang, "cepaf_gleam_ffi", "system_time_nanos")
fn system_time_nanos() -> Int

fn now_ms() -> Int {
  system_time_nanos() / 1_000_000
}

// =============================================================================
// Public API
// =============================================================================

/// Start the Pi daemon actor.
/// Returns Ok(PiDaemon) on success, Error on failure.
pub fn start(config: RuntimeConfig) -> Result(PiDaemon, String) {
  zenoh_otel.emit(Bridge, "pi_daemon_start", Observe)
  let initial_state =
    DaemonState(
      config: config,
      port: None,
      circuit: Closed,
      failure_count: 0,
      failure_window_start: now_ms(),
      prompts_ok: 0,
      prompts_err: 0,
      req_counter: 0,
      pending: dict.new(),
      line_buf: "",
    )

  let res =
    actor.new(initial_state)
    |> actor.on_message(handle_message)
    |> actor.start()

  case res {
    Ok(started) -> Ok(PiDaemon(subject: started.data))
    Error(err) -> Error("pi_daemon start failed: " <> string.inspect(err))
  }
}

/// Start daemon with default config
pub fn start_default() -> Result(PiDaemon, String) {
  start(default_config())
}

/// Send a prompt to Pi. Synchronous, with 30s timeout.
/// Returns Ok(response) or Error(PiError).
pub fn send_prompt(
  daemon: PiDaemon,
  prompt: String,
) -> Result(String, PiError) {
  send_prompt_with_timeout(daemon, prompt, 30_000)
}

/// Same as `send_prompt` but with a caller-supplied timeout in milliseconds.
/// Used by hermetic tests to verify the Timeout path without 30 s waits.
pub fn send_prompt_with_timeout(
  daemon: PiDaemon,
  prompt: String,
  timeout_ms: Int,
) -> Result(String, PiError) {
  let reply_subject = process.new_subject()
  process.send(daemon.subject, SendPrompt(prompt, reply_subject))
  case process.receive(reply_subject, timeout_ms) {
    Ok(result) -> result
    Error(_timeout) -> Error(Timeout)
  }
}

/// Returns True if daemon circuit is Closed/HalfOpen and port is open.
pub fn is_healthy(daemon: PiDaemon) -> Bool {
  let reply_subject = process.new_subject()
  process.send(daemon.subject, IsHealthy(reply_subject))
  case process.receive(reply_subject, 1000) {
    Ok(h) -> h
    Error(_) -> False
  }
}

/// Returns a JSON string summarising the daemon's current state.
pub fn dashboard_summary(daemon: PiDaemon) -> String {
  let reply_subject = process.new_subject()
  process.send(daemon.subject, DashboardSummary(reply_subject))
  case process.receive(reply_subject, 1000) {
    Ok(s) -> s
    Error(_) -> "{\"error\":\"timeout\"}"
  }
}

/// Gracefully stop the daemon.
pub fn stop(daemon: PiDaemon) -> Nil {
  zenoh_otel.emit(Bridge, "pi_daemon_stop", Observe)
  process.send(daemon.subject, Shutdown)
  Nil
}

// =============================================================================
// Actor message handler
// =============================================================================

fn handle_message(
  state: DaemonState,
  msg: DaemonMsg,
) -> actor.Next(DaemonState, DaemonMsg) {
  case msg {
    SendPrompt(prompt, reply_to) -> handle_send_prompt(state, prompt, reply_to)

    IsHealthy(reply_to) -> {
      let healthy = case state.circuit {
        Open -> False
        _ ->
          case state.port {
            None -> False
            Some(_) -> True
          }
      }
      process.send(reply_to, healthy)
      actor.continue(state)
    }

    DashboardSummary(reply_to) -> {
      let summary = build_summary(state)
      process.send(reply_to, summary)
      actor.continue(state)
    }

    PortData(data) -> handle_port_data(state, data)

    PortExit(_status) -> {
      zenoh_otel.emit(Bridge, "pi_daemon_port_exit", Observe)
      let new_state = handle_port_exit(state)
      // Fail all pending requests
      let failed_state = fail_all_pending(new_state, "port exited")
      actor.continue(failed_state)
    }

    Shutdown -> {
      close_port_if_open(state)
      actor.stop()
    }
  }
}

// =============================================================================
// Send prompt — spawns port if needed, enqueues pending reply
// =============================================================================

fn handle_send_prompt(
  state: DaemonState,
  prompt: String,
  reply_to: Subject(Result(String, PiError)),
) -> actor.Next(DaemonState, DaemonMsg) {
  case state.circuit {
    Open -> {
      process.send(reply_to, Error(CircuitOpen))
      actor.continue(state)
    }
    _ -> {
      // Ensure port is open
      let state2 = ensure_port_open(state)
      case state2.port {
        None -> {
          process.send(reply_to, Error(NotRunning))
          actor.continue(state2)
        }
        Some(port) -> {
          let counter = state2.req_counter + 1
          let req_id = int.to_string(counter)
          let cmd = pi_rpc.prompt(counter, prompt)
          let line = pi_rpc.serialize_command(cmd) <> "\n"
          let data = bit_array.from_string(line)
          case ffi_port_send(port, data) {
            Ok(_) -> {
              let new_pending = dict.insert(state2.pending, req_id, reply_to)
              actor.continue(
                DaemonState(
                  ..state2,
                  req_counter: counter,
                  pending: new_pending,
                ),
              )
            }
            Error(_) -> {
              process.send(reply_to, Error(NotRunning))
              let new_state = record_failure(state2)
              actor.continue(DaemonState(..new_state, port: None))
            }
          }
        }
      }
    }
  }
}

// =============================================================================
// Port data — JSONL parsing and response correlation
// =============================================================================

fn handle_port_data(
  state: DaemonState,
  data: BitArray,
) -> actor.Next(DaemonState, DaemonMsg) {
  let chunk = case bit_array.to_string(data) {
    Ok(s) -> s
    Error(_) -> ""
  }
  let combined = state.line_buf <> chunk
  let #(new_buf, state2) = process_lines(combined, state)
  actor.continue(DaemonState(..state2, line_buf: new_buf))
}

fn process_lines(buf: String, state: DaemonState) -> #(String, DaemonState) {
  case string.split_once(buf, "\n") {
    Error(_) ->
      // No newline yet — keep buffering
      #(buf, state)
    Ok(#(line, rest)) -> {
      let new_state = dispatch_response(state, line)
      process_lines(rest, new_state)
    }
  }
}

// Decode {"type":"response","id":"...","success":bool,"data":"...","error":"..."}
fn response_decoder() -> decode.Decoder(
  #(String, Bool, Option(String), Option(String)),
) {
  use id <- decode.field("id", decode.string)
  use success <- decode.field("success", decode.bool)
  use data_opt <- decode.optional_field("data", "", decode.string)
  use error_opt <- decode.optional_field("error", "", decode.string)
  decode.success(#(id, success, Some(data_opt), Some(error_opt)))
}

fn dispatch_response(state: DaemonState, line: String) -> DaemonState {
  let trimmed = string.trim(line)
  case trimmed {
    "" -> state
    _ ->
      case json.parse(trimmed, response_decoder()) {
        Ok(#(req_id, success, data_opt, error_opt)) -> {
          case dict.get(state.pending, req_id) {
            Ok(reply_to) -> {
              let new_pending = dict.delete(state.pending, req_id)
              case success {
                True -> {
                  let payload = case data_opt {
                    Some(d) -> d
                    None -> ""
                  }
                  process.send(reply_to, Ok(payload))
                  DaemonState(
                    ..state,
                    pending: new_pending,
                    prompts_ok: state.prompts_ok + 1,
                  )
                }
                False -> {
                  let err_msg = case error_opt {
                    Some(e) -> e
                    None -> "unknown error"
                  }
                  process.send(reply_to, Error(RpcError(err_msg)))
                  DaemonState(
                    ..record_failure(state),
                    pending: new_pending,
                    prompts_err: state.prompts_err + 1,
                  )
                }
              }
            }
            Error(_) ->
              // No pending request with this ID — ignore
              state
          }
        }
        Error(_) ->
          // Not a valid response envelope — ignore (could be startup noise)
          state
      }
  }
}

// =============================================================================
// Port lifecycle helpers
// =============================================================================

fn ensure_port_open(state: DaemonState) -> DaemonState {
  case state.port {
    Some(_) -> state
    None -> {
      zenoh_otel.emit(Bridge, "pi_daemon_port_open", Observe)
      let cfg = state.config
      let args = [
        cfg.cli_path,
        "--provider",
        cfg.provider,
        "--model",
        cfg.model,
        "--mode",
        "rpc",
      ]
      let env = [#("NODE_NO_WARNINGS", "1")]
      case ffi_port_open("node", args, env) {
        Ok(port) -> DaemonState(..state, port: Some(port))
        Error(_err) -> {
          zenoh_otel.emit(Bridge, "pi_daemon_port_open_failed", Observe)
          state
        }
      }
    }
  }
}

fn close_port_if_open(state: DaemonState) -> Nil {
  case state.port {
    Some(port) -> ffi_port_close(port)
    None -> Nil
  }
}

fn handle_port_exit(state: DaemonState) -> DaemonState {
  DaemonState(..record_failure(state), port: None)
}

// =============================================================================
// Circuit breaker logic (SC-PI-RUNTIME-002)
// =============================================================================

// 3 consecutive failures within 60s → Open circuit
fn record_failure(state: DaemonState) -> DaemonState {
  let now = now_ms()
  let window_ms = state.config.circuit_cooldown_secs * 1000
  // Reset counter if outside window
  let #(count, window_start) = case
    now - state.failure_window_start > window_ms
  {
    True -> #(0, now)
    False -> #(state.failure_count, state.failure_window_start)
  }
  let new_count = count + 1
  let new_circuit = case new_count >= state.config.circuit_threshold {
    True -> {
      zenoh_otel.emit(Bridge, "pi_daemon_circuit_open", Observe)
      Open
    }
    False -> state.circuit
  }
  DaemonState(
    ..state,
    failure_count: new_count,
    failure_window_start: window_start,
    circuit: new_circuit,
  )
}

// =============================================================================
// Fail all pending requests (called on port exit)
// =============================================================================

fn fail_all_pending(state: DaemonState, reason: String) -> DaemonState {
  let _ =
    dict.each(state.pending, fn(_id, reply_to) {
      process.send(reply_to, Error(RpcError(reason)))
    })
  DaemonState(..state, pending: dict.new())
}

// =============================================================================
// Dashboard summary
// =============================================================================

fn build_summary(state: DaemonState) -> String {
  let circuit_str = case state.circuit {
    Closed -> "closed"
    Open -> "open"
    HalfOpen -> "half_open"
  }
  let port_str = case state.port {
    Some(_) -> "open"
    None -> "closed"
  }
  "{"
  <> "\"circuit\":\""
  <> circuit_str
  <> "\","
  <> "\"port\":\""
  <> port_str
  <> "\","
  <> "\"failure_count\":"
  <> int.to_string(state.failure_count)
  <> ","
  <> "\"prompts_ok\":"
  <> int.to_string(state.prompts_ok)
  <> ","
  <> "\"prompts_err\":"
  <> int.to_string(state.prompts_err)
  <> ","
  <> "\"pending\":"
  <> int.to_string(dict.size(state.pending))
  <> "}"
}
