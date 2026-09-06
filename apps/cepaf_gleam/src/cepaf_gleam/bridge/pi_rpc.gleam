//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/bridge/pi_rpc</module>
////     <fsharp-lineage>No F# lineage — Gleam-native Pi RPC protocol</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L5_COGNITIVE</layer>
////     <mesh-domain>Pi-mono JSONL RPC Protocol Client</mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>DAL-A / SIL-6 / HIGH</criticality>
////     <stamp-controls>
////       SC-PI-001, SC-PI-004, SC-PI-005, SC-PI-008,
////       SC-ZMOF-001, SC-ARCH-SPLIT-003
////     </stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective" augmentation="jsonl-protocol">
////       Pi RPC JSONL protocol ↪ Gleam typed RPC commands/responses.
////       Commands: prompt, get_state, set_model, abort, compact, bash, etc.
////       Responses: JSON with {type: "response", command, success, data/error}.
////       Events: AG-UI event objects streamed between responses.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// Pi RPC Client — Typed Gleam interface to Pi's JSONL-over-stdio protocol.
////
//// This module provides:
////   1. RPC command types matching Pi's rpc-types.ts
////   2. Response parsing and type-safe result extraction
////   3. JSONL serialization for command dispatch
////   4. One-shot prompt execution for non-interactive use
////   5. Model/provider management commands
////
//// The actual process communication happens via Erlang ports in pi_runtime.gleam.
//// This module handles the protocol layer (serialization, command structure).

import gleam/int
import gleam/option.{type Option}
import gleam/string

// =============================================================================
// RPC Command Types (mirrors Pi rpc-types.ts)
// =============================================================================

/// Commands that can be sent to the Pi RPC process
pub type RpcCommand {
  /// Send a prompt to the agent
  Prompt(id: String, message: String)
  /// Interrupt with a steering message
  Steer(id: String, message: String)
  /// Queue a follow-up after current run
  FollowUp(id: String, message: String)
  /// Abort current operation
  Abort(id: String)
  /// Get current session state
  GetState(id: String)
  /// Set model by provider/id
  SetModel(id: String, provider: String, model_id: String)
  /// Cycle to next model
  CycleModel(id: String)
  /// Get available models
  GetAvailableModels(id: String)
  /// Set thinking level (none, low, medium, high)
  SetThinkingLevel(id: String, level: String)
  /// Compact session context
  Compact(id: String)
  /// Execute a bash command
  BashCmd(id: String, command: String)
  /// Start a new session
  NewSession(id: String)
  /// Get session statistics
  GetSessionStats(id: String)
  /// Get all messages
  GetMessages(id: String)
  /// Get available commands
  GetCommands(id: String)
}

/// Response from the Pi RPC process
pub type RpcResponse {
  RpcResponse(
    id: Option(String),
    command: String,
    success: Bool,
    data: Option(String),
    error: Option(String),
  )
}

/// Session state returned by get_state
pub type SessionState {
  SessionState(
    model: String,
    thinking_level: String,
    is_streaming: Bool,
    is_compacting: Bool,
    session_id: String,
    message_count: Int,
  )
}

/// Model info returned by get_available_models
pub type ModelInfo {
  ModelInfo(provider: String, id: String, context_window: Int, reasoning: Bool)
}

// =============================================================================
// JSONL Serialization
// =============================================================================

/// Serialize an RPC command to a JSONL line (JSON + newline)
pub fn serialize_command(cmd: RpcCommand) -> String {
  let json = case cmd {
    Prompt(id, message) ->
      "{\"type\":\"prompt\",\"id\":\""
      <> id
      <> "\",\"message\":"
      <> json_string(message)
      <> "}"

    Steer(id, message) ->
      "{\"type\":\"steer\",\"id\":\""
      <> id
      <> "\",\"message\":"
      <> json_string(message)
      <> "}"

    FollowUp(id, message) ->
      "{\"type\":\"follow_up\",\"id\":\""
      <> id
      <> "\",\"message\":"
      <> json_string(message)
      <> "}"

    Abort(id) -> "{\"type\":\"abort\",\"id\":\"" <> id <> "\"}"

    GetState(id) -> "{\"type\":\"get_state\",\"id\":\"" <> id <> "\"}"

    SetModel(id, provider, model_id) ->
      "{\"type\":\"set_model\",\"id\":\""
      <> id
      <> "\",\"provider\":\""
      <> provider
      <> "\",\"modelId\":\""
      <> model_id
      <> "\"}"

    CycleModel(id) -> "{\"type\":\"cycle_model\",\"id\":\"" <> id <> "\"}"

    GetAvailableModels(id) ->
      "{\"type\":\"get_available_models\",\"id\":\"" <> id <> "\"}"

    SetThinkingLevel(id, level) ->
      "{\"type\":\"set_thinking_level\",\"id\":\""
      <> id
      <> "\",\"level\":\""
      <> level
      <> "\"}"

    Compact(id) -> "{\"type\":\"compact\",\"id\":\"" <> id <> "\"}"

    BashCmd(id, command) ->
      "{\"type\":\"bash\",\"id\":\""
      <> id
      <> "\",\"command\":"
      <> json_string(command)
      <> "}"

    NewSession(id) -> "{\"type\":\"new_session\",\"id\":\"" <> id <> "\"}"

    GetSessionStats(id) ->
      "{\"type\":\"get_session_stats\",\"id\":\"" <> id <> "\"}"

    GetMessages(id) -> "{\"type\":\"get_messages\",\"id\":\"" <> id <> "\"}"

    GetCommands(id) -> "{\"type\":\"get_commands\",\"id\":\"" <> id <> "\"}"
  }

  json <> "\n"
}

/// Get the command ID for correlation
pub fn command_id(cmd: RpcCommand) -> String {
  case cmd {
    Prompt(id, _) -> id
    Steer(id, _) -> id
    FollowUp(id, _) -> id
    Abort(id) -> id
    GetState(id) -> id
    SetModel(id, _, _) -> id
    CycleModel(id) -> id
    GetAvailableModels(id) -> id
    SetThinkingLevel(id, _) -> id
    Compact(id) -> id
    BashCmd(id, _) -> id
    NewSession(id) -> id
    GetSessionStats(id) -> id
    GetMessages(id) -> id
    GetCommands(id) -> id
  }
}

// =============================================================================
// One-Shot Execution (non-interactive mode)
// =============================================================================

/// Build a one-shot Pi command (--print mode, exits after response)
pub fn oneshot_command(
  provider: String,
  model: String,
  prompt: String,
) -> String {
  "source sub-projects/pi-mono/load-env.sh 2>/dev/null; "
  <> "node sub-projects/pi-mono/packages/coding-agent/dist/cli.js"
  <> " --provider "
  <> provider
  <> " --model "
  <> model
  <> " --print "
  <> shell_quote(prompt)
}

/// Build a one-shot command with system prompt
pub fn oneshot_with_system(
  provider: String,
  model: String,
  system_prompt: String,
  prompt: String,
) -> String {
  "source sub-projects/pi-mono/load-env.sh 2>/dev/null; "
  <> "node sub-projects/pi-mono/packages/coding-agent/dist/cli.js"
  <> " --provider "
  <> provider
  <> " --model "
  <> model
  <> " --system-prompt "
  <> shell_quote(system_prompt)
  <> " --print "
  <> shell_quote(prompt)
}

// =============================================================================
// Request ID Generation
// =============================================================================

/// Generate a request ID from a counter
pub fn make_id(counter: Int) -> String {
  "req_" <> int.to_string(counter)
}

// =============================================================================
// Convenience Constructors
// =============================================================================

/// Create a prompt command with auto-generated ID
pub fn prompt(counter: Int, message: String) -> RpcCommand {
  Prompt(make_id(counter), message)
}

/// Create a get_state command
pub fn get_state(counter: Int) -> RpcCommand {
  GetState(make_id(counter))
}

/// Create a set_model command
pub fn set_model(
  counter: Int,
  provider: String,
  model_id: String,
) -> RpcCommand {
  SetModel(make_id(counter), provider, model_id)
}

/// Create an abort command
pub fn abort(counter: Int) -> RpcCommand {
  Abort(make_id(counter))
}

/// Create a compact command
pub fn compact(counter: Int) -> RpcCommand {
  Compact(make_id(counter))
}

/// Create a bash command
pub fn bash(counter: Int, command: String) -> RpcCommand {
  BashCmd(make_id(counter), command)
}

// =============================================================================
// Supported Providers (matching Pi's 15-provider registry)
// =============================================================================

/// List of providers Pi supports
pub fn supported_providers() -> List(String) {
  [
    "anthropic", "google", "openai", "ollama", "bedrock", "mistralai",
    "openrouter", "groq", "deepseek", "xai", "cerebras", "qwen", "sambanova",
    "fireworks", "together",
  ]
}

/// Check if a provider is supported
pub fn is_valid_provider(provider: String) -> Bool {
  list_contains(supported_providers(), provider)
}

// =============================================================================
// Internal Helpers
// =============================================================================

/// JSON-escape a string value
fn json_string(s: String) -> String {
  "\""
  <> s
  |> string.replace("\\", "\\\\")
  |> string.replace("\"", "\\\"")
  |> string.replace("\n", "\\n")
  |> string.replace("\r", "\\r")
  |> string.replace("\t", "\\t")
  <> "\""
}

/// Shell-quote a string
fn shell_quote(s: String) -> String {
  "'" <> string.replace(s, "'", "'\\''") <> "'"
}

/// Check if a list contains a value
fn list_contains(lst: List(String), val: String) -> Bool {
  case lst {
    [] -> False
    [head, ..rest] ->
      case head == val {
        True -> True
        False -> list_contains(rest, val)
      }
  }
}
