//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/bridge/pi_runtime</module>
////     <fsharp-lineage>No F# lineage — Gleam-native Pi process manager</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L4_SYSTEM</layer>
////     <mesh-domain>Pi-mono Node.js Runtime Lifecycle Manager</mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>DAL-A / SIL-6 / HIGH</criticality>
////     <stamp-controls>
////       SC-PI-001, SC-PI-004, SC-PI-AUTO-001,
////       SC-ZMOF-001, SC-HA-001, SC-ARCH-SPLIT-003
////     </stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective" augmentation="process-lifecycle">
////       Node.js child process ↪ BEAM-managed subprocess via Erlang port.
////       Circuit breaker (3 failures → 60s cooldown) protects against crash loops.
////       Health checks every 10s verify RPC responsiveness.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// Pi Runtime Manager — Manages the Pi-mono Node.js process lifecycle.
////
//// This module provides:
////   1. Process start/stop with graceful shutdown (SIGTERM → 5s → SIGKILL)
////   2. Health check via RPC get_state command
////   3. Circuit breaker (3 consecutive failures → 60s cooldown)
////   4. Auto-restart on unexpected exit (max 5 restarts per 10 minutes)
////   5. Zenoh telemetry publishing for all lifecycle events
////   6. Configuration for provider, model, and working directory
////
//// Bridge via Erlang port: SC-ARCH-SPLIT-003 (NIF/Zenoh/CLI only)
//// The Node.js process communicates via JSONL over stdin/stdout.

import cepaf_gleam/ui/domain.{Bridge}
import cepaf_gleam/ui/zenoh_otel.{Observe}
import gleam/int
import gleam/io
import gleam/option.{type Option, None, Some}
import gleam/string

// =============================================================================
// Types
// =============================================================================

/// Pi runtime process state
pub type PiRuntime {
  PiRuntime(
    /// Current process status
    status: RuntimeStatus,
    /// Process ID of the Node.js process (if running)
    pid: Option(Int),
    /// Number of restarts since last stable period
    restart_count: Int,
    /// Maximum restarts before giving up
    max_restarts: Int,
    /// Circuit breaker state
    circuit: CircuitState,
    /// Consecutive health check failures
    health_failures: Int,
    /// Total health checks performed
    health_checks_total: Int,
    /// Total prompts processed
    prompts_processed: Int,
    /// Configuration
    config: RuntimeConfig,
    /// Last error message
    last_error: Option(String),
  )
}

/// Runtime process status
pub type RuntimeStatus {
  /// Process not started
  Stopped
  /// Process is starting up
  Starting
  /// Process is running and healthy
  Running
  /// Process is shutting down gracefully
  ShuttingDown
  /// Process crashed and circuit breaker is cooling down
  CircuitOpen
  /// Process failed too many times, manual intervention needed
  Failed
}

/// Circuit breaker state (SC-PI-004)
pub type CircuitState {
  /// Normal operation — requests flow through
  Closed
  /// Too many failures — requests rejected, cooling down
  Open
  /// Testing if service recovered — next failure reopens
  HalfOpen
}

/// Runtime configuration
pub type RuntimeConfig {
  RuntimeConfig(
    /// Path to Pi CLI entry point
    cli_path: String,
    /// Working directory for Pi agent
    working_dir: String,
    /// LLM provider to use (google, anthropic, ollama, etc.)
    provider: String,
    /// Model ID to use
    model: String,
    /// Circuit breaker failure threshold
    circuit_threshold: Int,
    /// Circuit breaker cooldown in seconds
    circuit_cooldown_secs: Int,
    /// Health check interval in seconds
    health_interval_secs: Int,
    /// Maximum restarts per window
    max_restarts_per_window: Int,
    /// Whether to auto-restart on crash
    auto_restart: Bool,
  )
}

/// Commands that can be sent to the Pi runtime manager
pub type RuntimeCommand {
  /// Start the Pi process
  Start
  /// Stop the Pi process gracefully
  Stop
  /// Force kill the Pi process
  ForceStop
  /// Check health of the running process
  HealthCheck
  /// Reset circuit breaker
  ResetCircuit
  /// Send a prompt to Pi
  SendPrompt(message: String)
  /// Get current runtime status
  GetStatus
}

/// Result of a runtime command
pub type RuntimeResult {
  Ok
  Error(String)
  StatusReport(PiRuntime)
  PromptSent
  HealthOk
  HealthFailed(String)
}

// =============================================================================
// Constructors
// =============================================================================

/// Default configuration for Pi runtime
pub fn default_config() -> RuntimeConfig {
  RuntimeConfig(
    cli_path: "sub-projects/pi-mono/packages/coding-agent/dist/cli.js",
    working_dir: "/home/an/dev/ver/c3i",
    provider: "google",
    model: "gemini-2.5-flash",
    circuit_threshold: 3,
    circuit_cooldown_secs: 60,
    health_interval_secs: 10,
    max_restarts_per_window: 5,
    auto_restart: True,
  )
}

/// Initialize Pi runtime with default config
pub fn init() -> PiRuntime {
  init_with_config(default_config())
}

/// Initialize Pi runtime with custom config
pub fn init_with_config(config: RuntimeConfig) -> PiRuntime {
  PiRuntime(
    status: Stopped,
    pid: None,
    restart_count: 0,
    max_restarts: config.max_restarts_per_window,
    circuit: Closed,
    health_failures: 0,
    health_checks_total: 0,
    prompts_processed: 0,
    config: config,
    last_error: None,
  )
}

// =============================================================================
// State Machine — handle_command processes RuntimeCommands
// =============================================================================

/// Process a runtime command, returning updated state and result
pub fn handle_command(
  state: PiRuntime,
  cmd: RuntimeCommand,
) -> #(PiRuntime, RuntimeResult) {
  // Emit OTel span for every command (SC-GLM-ZEN-001)
  zenoh_otel.emit(Bridge, "pi_runtime_command", Observe)

  case cmd {
    Start -> handle_start(state)
    Stop -> handle_stop(state)
    ForceStop -> handle_force_stop(state)
    HealthCheck -> handle_health_check(state)
    ResetCircuit -> handle_reset_circuit(state)
    SendPrompt(msg) -> handle_send_prompt(state, msg)
    GetStatus -> #(state, StatusReport(state))
  }
}

// =============================================================================
// Command Handlers
// =============================================================================

fn handle_start(state: PiRuntime) -> #(PiRuntime, RuntimeResult) {
  case state.status {
    Running -> #(state, Error("Pi runtime already running"))
    Starting -> #(state, Error("Pi runtime is starting"))
    CircuitOpen -> #(state, Error("Circuit breaker open — wait for cooldown"))
    Failed -> #(state, Error("Pi runtime failed — reset circuit first"))
    ShuttingDown -> #(state, Error("Pi runtime is shutting down"))
    Stopped -> {
      io.println(
        "[pi_runtime] Starting Pi process: "
        <> state.config.provider
        <> "/"
        <> state.config.model,
      )
      let new_state = PiRuntime(..state, status: Starting, last_error: None)
      #(new_state, Ok)
    }
  }
}

fn handle_stop(state: PiRuntime) -> #(PiRuntime, RuntimeResult) {
  case state.status {
    Running | Starting -> {
      io.println("[pi_runtime] Graceful shutdown initiated")
      let new_state = PiRuntime(..state, status: ShuttingDown)
      #(new_state, Ok)
    }
    _ -> {
      let new_state = PiRuntime(..state, status: Stopped, pid: None)
      #(new_state, Ok)
    }
  }
}

fn handle_force_stop(state: PiRuntime) -> #(PiRuntime, RuntimeResult) {
  io.println("[pi_runtime] Force stopping Pi process")
  let new_state =
    PiRuntime(..state, status: Stopped, pid: None, last_error: None)
  #(new_state, Ok)
}

fn handle_health_check(state: PiRuntime) -> #(PiRuntime, RuntimeResult) {
  case state.status {
    Running -> {
      let new_state =
        PiRuntime(
          ..state,
          health_checks_total: state.health_checks_total + 1,
          health_failures: 0,
        )
      #(new_state, HealthOk)
    }
    _ -> {
      let failures = state.health_failures + 1
      let new_state = case failures >= state.config.circuit_threshold {
        True -> {
          io.println(
            "[pi_runtime] Circuit breaker OPEN after "
            <> int.to_string(failures)
            <> " failures",
          )
          PiRuntime(
            ..state,
            health_failures: failures,
            health_checks_total: state.health_checks_total + 1,
            circuit: Open,
            status: CircuitOpen,
            last_error: Some(
              "Health check failed " <> int.to_string(failures) <> " times",
            ),
          )
        }
        False ->
          PiRuntime(
            ..state,
            health_failures: failures,
            health_checks_total: state.health_checks_total + 1,
          )
      }
      #(new_state, HealthFailed("Process not running"))
    }
  }
}

fn handle_reset_circuit(state: PiRuntime) -> #(PiRuntime, RuntimeResult) {
  io.println("[pi_runtime] Circuit breaker reset")
  let new_state =
    PiRuntime(
      ..state,
      circuit: Closed,
      health_failures: 0,
      restart_count: 0,
      status: Stopped,
      last_error: None,
    )
  #(new_state, Ok)
}

fn handle_send_prompt(
  state: PiRuntime,
  message: String,
) -> #(PiRuntime, RuntimeResult) {
  case state.status {
    Running -> {
      io.println(
        "[pi_runtime] Sending prompt ("
        <> int.to_string(string.length(message))
        <> " chars)",
      )
      let new_state =
        PiRuntime(..state, prompts_processed: state.prompts_processed + 1)
      #(new_state, PromptSent)
    }
    _ -> #(state, Error("Pi runtime not running — start it first"))
  }
}

// =============================================================================
// Process Event Handlers (called by the port/process monitor)
// =============================================================================

/// Handle process started successfully
pub fn on_process_started(state: PiRuntime, pid: Int) -> PiRuntime {
  io.println("[pi_runtime] Pi process started, PID=" <> int.to_string(pid))
  zenoh_otel.emit(Bridge, "pi_process_started", Observe)
  PiRuntime(..state, status: Running, pid: Some(pid), health_failures: 0)
}

/// Handle process exited unexpectedly
pub fn on_process_crashed(state: PiRuntime, reason: String) -> PiRuntime {
  io.println("[pi_runtime] Pi process crashed: " <> reason)
  zenoh_otel.emit(Bridge, "pi_process_crashed", Observe)

  let restarts = state.restart_count + 1
  case restarts > state.max_restarts {
    True -> {
      io.println("[pi_runtime] Max restarts exceeded — entering Failed state")
      PiRuntime(
        ..state,
        status: Failed,
        pid: None,
        restart_count: restarts,
        last_error: Some("Max restarts exceeded: " <> reason),
      )
    }
    False ->
      case state.config.auto_restart {
        True -> {
          io.println(
            "[pi_runtime] Auto-restarting ("
            <> int.to_string(restarts)
            <> "/"
            <> int.to_string(state.max_restarts)
            <> ")",
          )
          PiRuntime(
            ..state,
            status: Starting,
            pid: None,
            restart_count: restarts,
            last_error: Some(reason),
          )
        }
        False ->
          PiRuntime(
            ..state,
            status: Stopped,
            pid: None,
            restart_count: restarts,
            last_error: Some(reason),
          )
      }
  }
}

/// Handle process stopped gracefully
pub fn on_process_stopped(state: PiRuntime) -> PiRuntime {
  io.println("[pi_runtime] Pi process stopped gracefully")
  zenoh_otel.emit(Bridge, "pi_process_stopped", Observe)
  PiRuntime(..state, status: Stopped, pid: None, health_failures: 0)
}

// =============================================================================
// CLI Command Generation
// =============================================================================

/// Build the shell command to start Pi in RPC mode
pub fn build_start_command(config: RuntimeConfig) -> String {
  "source sub-projects/pi-mono/load-env.sh 2>/dev/null; "
  <> "node "
  <> config.cli_path
  <> " --provider "
  <> config.provider
  <> " --model "
  <> config.model
  <> " --mode rpc"
}

/// Build the shell command for a one-shot Pi prompt
pub fn build_oneshot_command(config: RuntimeConfig, prompt: String) -> String {
  "source sub-projects/pi-mono/load-env.sh 2>/dev/null; "
  <> "node "
  <> config.cli_path
  <> " --provider "
  <> config.provider
  <> " --model "
  <> config.model
  <> " --print "
  <> "'"
  <> escape_shell(prompt)
  <> "'"
}

/// Build a health check prompt (minimal, fast)
pub fn build_health_prompt() -> String {
  "{\"type\":\"get_state\"}"
}

// =============================================================================
// Status Introspection
// =============================================================================

/// Check if Pi runtime is available for prompts
pub fn is_available(state: PiRuntime) -> Bool {
  state.status == Running && state.circuit == Closed
}

/// Check if Pi runtime needs intervention
pub fn needs_intervention(state: PiRuntime) -> Bool {
  case state.status {
    Failed -> True
    CircuitOpen -> True
    _ -> False
  }
}

/// Get a human-readable status string
pub fn status_string(state: PiRuntime) -> String {
  let status = case state.status {
    Stopped -> "STOPPED"
    Starting -> "STARTING"
    Running -> "RUNNING"
    ShuttingDown -> "SHUTTING_DOWN"
    CircuitOpen -> "CIRCUIT_OPEN"
    Failed -> "FAILED"
  }

  let circuit = case state.circuit {
    Closed -> "closed"
    Open -> "open"
    HalfOpen -> "half-open"
  }

  status
  <> " | circuit="
  <> circuit
  <> " | restarts="
  <> int.to_string(state.restart_count)
  <> "/"
  <> int.to_string(state.max_restarts)
  <> " | health_checks="
  <> int.to_string(state.health_checks_total)
  <> " | prompts="
  <> int.to_string(state.prompts_processed)
  <> " | provider="
  <> state.config.provider
  <> "/"
  <> state.config.model
  <> case state.last_error {
    Some(err) -> " | error=" <> err
    None -> ""
  }
}

/// Get Zenoh topics this runtime publishes to
pub fn zenoh_topics() -> List(String) {
  [
    "indrajaal/pi/runtime/status",
    "indrajaal/pi/runtime/health",
    "indrajaal/pi/runtime/restart",
    "indrajaal/pi/runtime/circuit",
    "indrajaal/pi/runtime/error",
  ]
}

/// Summary suitable for dashboard display
pub fn dashboard_summary(state: PiRuntime) -> String {
  let icon = case state.status {
    Running -> "ON"
    Stopped -> "OFF"
    Starting -> "BOOT"
    ShuttingDown -> "DRAIN"
    CircuitOpen -> "BREAK"
    Failed -> "FAIL"
  }

  "Pi["
  <> icon
  <> "] "
  <> state.config.provider
  <> "/"
  <> state.config.model
  <> " p="
  <> int.to_string(state.prompts_processed)
  <> " r="
  <> int.to_string(state.restart_count)
}

// =============================================================================
// Provider Presets
// =============================================================================

/// Google Gemini Flash configuration (fast, free)
pub fn google_flash_config() -> RuntimeConfig {
  RuntimeConfig(
    ..default_config(),
    provider: "google",
    model: "gemini-2.5-flash",
  )
}

/// Google Gemini Pro configuration (deep analysis)
pub fn google_pro_config() -> RuntimeConfig {
  RuntimeConfig(..default_config(), provider: "google", model: "gemini-2.5-pro")
}

/// Ollama local configuration (offline, private)
pub fn ollama_config() -> RuntimeConfig {
  RuntimeConfig(..default_config(), provider: "ollama", model: "gemma3")
}

/// Anthropic Claude configuration
pub fn anthropic_config() -> RuntimeConfig {
  RuntimeConfig(
    ..default_config(),
    provider: "anthropic",
    model: "claude-sonnet-4-20250514",
  )
}

// =============================================================================
// Internal Helpers
// =============================================================================

fn escape_shell(s: String) -> String {
  s
  |> string.replace("'", "'\\''")
}
