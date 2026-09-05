//// [C3I-SIL6-MSTS] <c3i-module><identity><module>cepaf_gleam/agents/cortex</module>
////   <fsharp-lineage>Cepaf.Agents.Cortex</fsharp-lineage></identity>
////   <fractal-topology><layer>L5_COGNITIVE</layer></fractal-topology>
////   <compliance><stamp-controls>SC-COG-001, SC-ZMOF-001</stamp-controls></compliance>
//// </c3i-module>
////
//// Prefrontal Cortex — The Seat of Swarm Consciousness (ReAct Loop).
//// Orchestrates MCP tool calls via Zenoh MoZ to achieve User Goals.

import cepaf_gleam/agui/events
import cepaf_gleam/agui/tools.{type ToolRegistry}
import cepaf_gleam/agui/zenoh_bus
import cepaf_gleam/bridge/commands as bridge_commands
import cepaf_gleam/bridge/zenoh_mcp as bridge_zenoh
import cepaf_gleam/fractal/l5_cognitive.{
  type OodaCycleState, type ReasoningState, Act, Decide, Observe, Orient,
}
import cepaf_gleam/moz/client as moz
import cepaf_gleam/telemetry/otel.{type SpanContext}
import cepaf_gleam/zenoh/client as zenoh
import gleam/dict
import gleam/dynamic/decode
import gleam/erlang/process.{type Subject}
import gleam/io
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor

// =============================================================================
// Cortex State & Messages
// =============================================================================

pub type EventLogEntry {
  EventLogEntry(
    id: String,
    timestamp: String,
    agent_id: String,
    intent_id: Option(String),
    action: String,
    payload: Option(String),
    result: Option(String),
    status: String,
  )
}

pub type CortexState {
  CortexState(
    id: String,
    ooda: OodaCycleState,
    reasoning: ReasoningState,
    moz: moz.MoZClientState,
    active_intent: Option(String),
    memory: List(EventLogEntry),
    span_ctx: Option(SpanContext),
    // P1-1: HITL tool registry (SC-AGUI-004)
    tool_registry: ToolRegistry,
    // P1-2: Zenoh session for AG-UI event emission (SC-GLM-ZEN-001)
    zenoh_session: Option(zenoh.Session),
  )
}

pub type CortexMessage {
  /// Ingest a new User Intent stimuli.
  ProcessIntent(id: String, raw_text: String)
  /// Observe the result of an MCP tool call.
  ObserveToolResult(request_id: String, result: String)
  /// Internal tick for the OODA cycle.
  OodaTick
  /// P1-1: HITL approval received from operator (SC-AGUI-004)
  ApprovalReceived(tool_call_id: String, approved: Bool)
}

// =============================================================================
// ReAct Loop Implementation (Task 2.1)
// =============================================================================

/// Default tools with HITL requirements for L0 operations (SC-AGUI-004)
fn default_tools() -> List(tools.ToolDef) {
  [
    tools.ToolDef("container_stop", "Stop a container", json.null(), True),
    tools.ToolDef("container_restart", "Restart a container", json.null(), True),
    tools.ToolDef("db_drop", "Drop a database", json.null(), True),
    tools.ToolDef("emergency_halt", "Emergency system halt", json.null(), True),
    tools.ToolDef("plan_add", "Add a task", json.null(), False),
    tools.ToolDef("plan_update", "Update a task", json.null(), False),
    tools.ToolDef("plan_list", "List tasks", json.null(), False),
    tools.ToolDef("ignition_status", "Check mesh status", json.null(), False),
    tools.ToolDef(
      "knowledge_search",
      "Search knowledge base",
      json.null(),
      False,
    ),
  ]
}

pub fn start(
  id: String,
) -> Result(actor.Started(Subject(CortexMessage)), actor.StartError) {
  let initial_state =
    CortexState(
      id: id,
      ooda: l5_cognitive.initial_ooda(),
      reasoning: l5_cognitive.initial_reasoning(),
      moz: moz.new(),
      active_intent: None,
      memory: [],
      span_ctx: None,
      tool_registry: tools.new_registry(default_tools()),
      zenoh_session: None,
    )

  actor.new(initial_state)
  |> actor.on_message(handle_message)
  |> actor.start()
}

fn handle_message(
  state: CortexState,
  msg: CortexMessage,
) -> actor.Next(CortexState, CortexMessage) {
  case msg {
    ProcessIntent(id, text) -> {
      io.println("🧠 Cortex [" <> state.id <> "]: Ingesting Intent -> " <> id)

      // 1. ORIENT: Fetch context, preferences, and start reasoning stream
      let memory = fetch_context(state.moz)
      let voice_pref = fetch_preference(state.moz, "executive_voice")
      let new_reasoning = l5_cognitive.start_reasoning(state.reasoning, id)
      let new_ooda = l5_cognitive.set_ooda_phase(state.ooda, Orient)

      // 1.1 TELEMETRY: Start a new recursive span for this intent
      let ctx = otel.generate_context(state.span_ctx)
      otel.start_span(["cepaf", "cortex", "intent"], dict.new(), Some(ctx))

      // P1-2: Emit ReasoningStart AG-UI event (SC-AGUI-006)
      emit_reasoning_start(state, id)

      let new_state =
        CortexState(
          ..state,
          active_intent: Some(id),
          reasoning: new_reasoning,
          ooda: new_ooda,
          memory: memory,
          span_ctx: Some(ctx),
        )

      // 1.2 PERSONA INJECTION: Use voice preference if available
      let text_with_persona = case voice_pref {
        Some(voice) -> "Persona[" <> voice <> "]: " <> text
        None -> text
      }

      // 2. DECIDE
      decide_next_action(new_state, text_with_persona)
    }

    ObserveToolResult(req_id, result) -> {
      io.println(
        "👁️ Cortex ["
        <> state.id
        <> "]: Observing Tool Result ["
        <> req_id
        <> "]",
      )

      // 3. OBSERVE: Update reasoning with results
      let new_reasoning =
        l5_cognitive.append_reasoning(state.reasoning, "\nResult: " <> result)
      let new_ooda = l5_cognitive.set_ooda_phase(state.ooda, Observe)

      // P1-2: Emit ReasoningMessageContent + ReasoningEnd (SC-AGUI-006)
      emit_reasoning_content(state, "Result observed: " <> req_id)
      emit_reasoning_end(state)

      // 3.1 TELEMETRY: Close intent span
      otel.stop_span(
        ["cepaf", "cortex", "intent"],
        0.0,
        dict.new(),
        state.span_ctx,
      )

      actor.continue(
        CortexState(..state, reasoning: new_reasoning, ooda: new_ooda),
      )
    }

    OodaTick -> {
      // Periodic OODA cycle maintenance
      actor.continue(state)
    }

    // P1-1: HITL approval handler (SC-AGUI-004, SC-SAFETY-001)
    ApprovalReceived(tool_call_id, approved) -> {
      case approved {
        True -> {
          io.println(
            "✅ Cortex [" <> state.id <> "]: Tool approved: " <> tool_call_id,
          )
          let new_registry =
            tools.approve_call(state.tool_registry, tool_call_id)
          // Now dispatch the approved tool via MoZ
          let #(new_moz, _result) =
            moz.send_request(
              state.moz,
              "plan",
              "plan_execute",
              json.object([
                #("tool_call_id", json.string(tool_call_id)),
              ]),
            )
          actor.continue(
            CortexState(..state, tool_registry: new_registry, moz: new_moz),
          )
        }
        False -> {
          io.println(
            "❌ Cortex [" <> state.id <> "]: Tool rejected: " <> tool_call_id,
          )
          let new_registry =
            tools.reject_call(
              state.tool_registry,
              tool_call_id,
              "Operator rejected",
            )
          actor.continue(CortexState(..state, tool_registry: new_registry))
        }
      }
    }
  }
}

fn decide_next_action(
  state: CortexState,
  text: String,
) -> actor.Next(CortexState, CortexMessage) {
  let new_ooda = l5_cognitive.set_ooda_phase(state.ooda, Decide)

  // 2.1 CONTEXTUAL AWARENESS: Inject summarized memory into logic
  let context_summary = summarize_memory(state.memory)
  io.println("🧠 Cortex Context: " <> context_summary)

  // P1-2: Emit reasoning content during decide phase (SC-AGUI-006)
  emit_reasoning_content(state, "Deciding: classifying intent...")

  // P3-6: Expanded pattern matching (30+ commands matching Rust cortex.rs)
  let #(domain, method, _params) = classify_intent(text)

  // P1-1: Check HITL requirement before dispatch (SC-AGUI-004, SC-SAFETY-001)
  let needs_approval =
    list.any(state.tool_registry.available_tools, fn(t) {
      t.name == method && t.requires_approval
    })

  case needs_approval {
    True -> {
      io.println("🔒 Cortex [" <> state.id <> "]: HITL required for " <> method)
      let call_id = state.id <> "-" <> method
      let new_registry = tools.start_call(state.tool_registry, call_id, method)
      let new_registry2 = tools.end_args(new_registry, call_id)
      emit_reasoning_content(
        state,
        "HITL: awaiting operator approval for " <> method,
      )
      actor.continue(
        CortexState(..state, ooda: new_ooda, tool_registry: new_registry2),
      )
    }
    False -> {
      io.println("🎬 Cortex [" <> state.id <> "]: Acting -> " <> method)
      emit_reasoning_content(state, "Dispatching: " <> method)
      dispatch_tool(state, new_ooda, domain, method, text)
    }
  }
}

/// Dispatch a tool via MoZ (after HITL approval or for non-approval tools)
fn dispatch_tool(
  state: CortexState,
  new_ooda: OodaCycleState,
  domain: String,
  method: String,
  text: String,
) -> actor.Next(CortexState, CortexMessage) {
  // 4. ACT: Dispatch to Motor Strip via Zenoh MCP
  let new_ooda_act = l5_cognitive.set_ooda_phase(new_ooda, Act)

  // 4.1 TELEMETRY: Trace the tool call
  let tool_ctx = otel.generate_context(state.span_ctx)
  otel.start_span(
    ["cepaf", "cortex", "tool"],
    dict.from_list([#("method", method)]),
    Some(tool_ctx),
  )

  // FRACTAL INSTRUMENTATION: Inject context into MCP params
  let params_with_ctx = {
    // Add trace metadata to the JSON object
    let ctx_fields = [
      #("trace_id", json.string(tool_ctx.trace_id)),
      #("span_id", json.string(tool_ctx.span_id)),
    ]

    json.object(
      list.append(ctx_fields, case text {
        "list tasks" -> []
        _ -> [#("prompt", json.string(text))]
      }),
    )
  }

  let #(new_moz, result) =
    moz.send_request(state.moz, domain, method, params_with_ctx)

  // 4.2 EPISODIC LOGGING: Record the action decision
  let _ = log_cortex_action(state, method, "dispatched")

  case result {
    Ok(request_id) -> {
      io.println("  [ok] MoZ request dispatched: " <> request_id)
      // SC-WIRE: Close OODA feedback loop — query for response synchronously
      // In production, this would be a Zenoh subscriber on the response topic.
      // For now, we do a synchronous MoZ query to get the result back.
      let #(moz_after_response, response) =
        moz.send_query(new_moz, domain, method)
      case response {
        Ok(result_json) -> {
          io.println("  [ok] MoZ response received, OODA loop closed")
          emit_reasoning_content(state, "Result: " <> request_id)
          otel.stop_span(
            ["cepaf", "cortex", "tool"],
            0.0,
            dict.new(),
            Some(tool_ctx),
          )
          let new_reasoning =
            l5_cognitive.append_reasoning(
              state.reasoning,
              "\nTool result: " <> result_json,
            )
          let observe_ooda =
            l5_cognitive.set_ooda_phase(new_ooda_act, l5_cognitive.Observe)
          actor.continue(
            CortexState(
              ..state,
              ooda: observe_ooda,
              moz: moz_after_response,
              reasoning: new_reasoning,
            ),
          )
        }
        Error(_) -> {
          otel.stop_span(
            ["cepaf", "cortex", "tool"],
            0.0,
            dict.new(),
            Some(tool_ctx),
          )
          actor.continue(
            CortexState(..state, ooda: new_ooda_act, moz: moz_after_response),
          )
        }
      }
    }
    Error(e) -> {
      io.println("  [!] MoZ dispatch failed: " <> e)
      emit_reasoning_content(state, "Error: " <> e)
      otel.error_span(
        ["cepaf", "cortex", "tool"],
        0.0,
        e,
        dict.new(),
        Some(tool_ctx),
      )
      actor.continue(CortexState(..state, ooda: new_ooda_act, moz: new_moz))
    }
  }
}

fn fetch_context(moz_state: moz.MoZClientState) -> List(EventLogEntry) {
  case moz.send_query(moz_state, "plan", "list_events") {
    #(_, Ok(payload)) -> {
      case parse_event_list(payload) {
        Ok(events) -> events
        Error(_) -> []
      }
    }
    _ -> []
  }
}

fn fetch_preference(
  moz_state: moz.MoZClientState,
  key: String,
) -> Option(String) {
  let _params = json.object([#("key", json.string(key))])
  // Standard MoZ query for a single preference
  case moz.send_query(moz_state, "plan", "plan_get_pref") {
    #(_, Ok(payload)) -> {
      // Decode Option(String) result from McpResponse
      let decoder = {
        use result <- decode.field("result", decode.optional(decode.string))
        decode.success(result)
      }
      case json.parse(from: payload, using: decoder) {
        Ok(val) -> val
        Error(_) -> None
      }
    }
    _ -> None
  }
}

fn parse_event_list(payload: String) -> Result(List(EventLogEntry), String) {
  let event_decoder = {
    use id <- decode.field("id", decode.string)
    use timestamp <- decode.field("timestamp", decode.string)
    use agent_id <- decode.field("agent_id", decode.string)
    use intent_id <- decode.optional_field(
      "intent_id",
      None,
      decode.optional(decode.string),
    )
    use action <- decode.field("action", decode.string)
    use payload_field <- decode.optional_field(
      "payload",
      None,
      decode.optional(decode.string),
    )
    use result <- decode.optional_field(
      "result",
      None,
      decode.optional(decode.string),
    )
    use status <- decode.field("status", decode.string)

    decode.success(EventLogEntry(
      id: id,
      timestamp: timestamp,
      agent_id: agent_id,
      intent_id: intent_id,
      action: action,
      payload: payload_field,
      result: result,
      status: status,
    ))
  }

  let response_decoder = {
    use result <- decode.field("result", decode.list(event_decoder))
    decode.success(result)
  }

  case json.parse(from: payload, using: response_decoder) {
    Ok(events) -> Ok(events)
    Error(_) -> Error("Failed to decode Event log")
  }
}

fn summarize_memory(memory: List(EventLogEntry)) -> String {
  case list.length(memory) {
    0 -> "No previous events."
    n -> "Last " <> int_to_string(n) <> " actions performed successfully."
  }
}

fn log_cortex_action(state: CortexState, action: String, status: String) {
  let params =
    json.object([
      #("agent_id", json.string(state.id)),
      #("action", json.string(action)),
      #("status", json.string(status)),
      #("intent_id", case state.active_intent {
        Some(id) -> json.string(id)
        None -> json.null()
      }),
    ])
  let _ = moz.send_request(state.moz, "plan", "plan_log", params)
  Nil
}

@external(erlang, "erlang", "integer_to_binary")
fn int_to_string(i: Int) -> String

// =============================================================================
// P3-6: Intent Classification (30+ patterns matching Rust cortex.rs)
// =============================================================================

import gleam/string

fn classify_intent(text: String) -> #(String, String, json.Json) {
  let lower = string.lowercase(text)
  let empty = json.object([])
  case lower {
    // Task management
    "list tasks" | "tasks" | "/tasks" | "/list" -> #("plan", "plan_list", empty)
    "status" | "/status" -> #("plan", "plan_status", empty)
    "/sync" | "sync" -> #("plan", "plan_sync", empty)
    // Container operations (HITL required)
    "stop" <> _ -> #("ignition", "container_stop", empty)
    "restart" <> _ -> #("ignition", "container_restart", empty)
    // Health
    "check health" | "health" | "/health" -> #(
      "ignition",
      "ignition_status",
      empty,
    )
    "/pods" | "containers" | "pods" -> #("ignition", "podman_containers", empty)
    // Knowledge
    "search" <> _ -> #(
      "plan",
      "knowledge_search",
      json.object([#("query", json.string(text))]),
    )
    "/web_search" <> _ -> #(
      "plan",
      "web_search",
      json.object([#("query", json.string(text))]),
    )
    // Git
    "git status" | "/git" -> #("plan", "git_status", empty)
    "git log" -> #("plan", "git_log", empty)
    // Zenoh
    "/zenoh" | "zenoh" -> #("ignition", "system_zenoh", empty)
    // Verification
    "verify" | "/verify" -> #("ignition", "verification_run", empty)
    // Help
    "help" | "/help" -> #("plan", "help", empty)
    // Model/inference
    "models" | "/models" -> #("plan", "models", empty)
    // Trace
    "/trace" | "trace" -> #("plan", "trace_recent", empty)
    // Events
    "/events" | "events" -> #("plan", "list_events", empty)
    // Cache
    "/cache" | "cache" -> #("plan", "cache_stats", empty)
    // Preferences
    "/prefs" | "prefs" -> #("plan", "list_prefs", empty)
    // Email
    "email" <> _ -> #(
      "plan",
      "send_email",
      json.object([#("text", json.string(text))]),
    )
    // Emergency (HITL required)
    "emergency" <> _ -> #(
      "ignition",
      "emergency_halt",
      json.object([#("detail", json.string(text))]),
    )
    // Rules
    "rules" | "/rules" -> #("plan", "rules_status", empty)
    // Default: general query
    _ -> #(
      "ignition",
      "ignition_status",
      json.object([#("prompt", json.string(text))]),
    )
  }
}

// =============================================================================
// P1-2: AG-UI Reasoning Event Emitters (SC-AGUI-006, SC-GLM-ZEN-001)
// =============================================================================

fn emit_reasoning_start(state: CortexState, intent_id: String) {
  case state.zenoh_session {
    Some(session) -> {
      let event = events.new_reasoning_start(intent_id)
      let _ = zenoh_bus.publish_event(session, state.id, event)
      Nil
    }
    None -> Nil
  }
}

fn emit_reasoning_content(state: CortexState, content: String) {
  case state.zenoh_session {
    Some(session) -> {
      let msg_id = case state.active_intent {
        Some(id) -> id
        None -> state.id
      }
      let event = events.new_reasoning_message_content(msg_id, content)
      let _ = zenoh_bus.publish_event(session, state.id, event)
      Nil
    }
    None -> Nil
  }
}

fn emit_reasoning_end(state: CortexState) {
  case state.zenoh_session {
    Some(session) -> {
      let msg_id = case state.active_intent {
        Some(id) -> id
        None -> state.id
      }
      let event = events.new_reasoning_end(msg_id)
      let _ = zenoh_bus.publish_event(session, state.id, event)
      Nil
    }
    None -> Nil
  }
}

// ---------------------------------------------------------------------------
// Bridge integration (SC-ZMOF-004, SC-ARCH-SPLIT-003)
// Wires bridge/commands and bridge/zenoh_mcp into the cortex production path.
// ---------------------------------------------------------------------------

/// Returns the list of all registered bridge command names.
/// Used by the cortex OODA orient phase to enumerate available tool calls.
pub fn bridge_command_catalog() -> List(String) {
  bridge_commands.all_commands()
}

/// Decode an incoming Zenoh MCP message payload and dispatch it as a
/// bridge command. Returns Ok with the JSON response, or Error on failure.
pub fn dispatch_bridge_message(
  msg: bridge_zenoh.Message,
) -> Result(String, String) {
  case msg {
    bridge_zenoh.ZenohMessage(_topic, payload) ->
      bridge_commands.dispatch_json(payload)
  }
}
