//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/bridge/pi_startup_classifier</module>
////     <fsharp-lineage>Pi Startup Stage Decomposition & Intelligent Telemetry</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L4_SYSTEM</layer>
////     <mesh-domain>Pi-mono Startup Classification, Intelligent Messaging & GUI Events</mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>DAL-A / SIL-6 / HIGH</criticality>
////     <stamp-controls>
////       SC-PI-001, SC-PI-STARTUP-001, SC-AGUI-001, SC-GLM-UI-001, SC-MUDA-001
////     </stamp-controls>
////   </compliance>
//// </c3i-module>
//// =============================================================================
////
//// Pi Startup Classifier — Decomposes the Pi-mono process startup into granular,
//// transparent lifecycle stages with intelligent contextual messaging and
//// visually appealing GUI event generation.
////
//// Resolves Operator Directive:
//// "pi process starting taking too much time, classify the process,
////  create intelligent messaging for every stage with gui events to make
////  process visually appealing"

import cepaf_gleam/agui/events.{type AgUiEvent, AgUiEvent, Custom}
import gleam/int
import gleam/json
import gleam/list
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html

// =============================================================================
// Stage Classification Types
// =============================================================================

/// The 7 canonical stages of the Pi runtime startup lifecycle.
pub type StartupStage {
  /// Step 1: Validating binary paths, node/bun runtime, and filesystem permissions
  StagePreflight
  /// Step 2: Authenticating provider credentials and checking quota limits
  StageProviderAuth
  /// Step 3: Spawning OS child process and attaching standard I/O port pipes
  StageProcessSpawn
  /// Step 4: Exchanging JSONL protocol handshake and verifying RPC probe
  StageProtocolHandshake
  /// Step 5: Federating 26 C3I domain tools and custom MCP schemas
  StageToolFederation
  /// Step 6: Connecting to Zenoh pub/sub mesh topics and binding OTel tracing
  StageMeshSync
  /// Step 7: Warmup ping verified; process is fully operational
  StageOperationalReady
  /// Process startup encountered an error and is recovering or halting
  StageFailed(failed_at: String, reason: String)
}

/// Rich metadata describing a single startup stage.
pub type StageMetadata {
  StageMetadata(
    stage: StartupStage,
    stage_id: String,
    step_number: Int,
    total_steps: Int,
    progress_pct: Int,
    icon: String,
    title: String,
    detail: String,
    troubleshooting_hint: String,
    elapsed_ms: Int,
    estimated_remaining_ms: Int,
    is_active: Bool,
    is_completed: Bool,
  )
}

/// Aggregate state tracking a startup progression over time.
pub type StartupState {
  StartupState(
    current_stage: StartupStage,
    provider: String,
    model: String,
    started_at_ms: Int,
    current_elapsed_ms: Int,
    completed_stages: List(StartupStage),
  )
}

// =============================================================================
// Stage Enumeration & Metadata
// =============================================================================

/// Returns the ordered list of nominal startup stages (1 through 7).
pub fn nominal_stages() -> List(StartupStage) {
  [
    StagePreflight,
    StageProviderAuth,
    StageProcessSpawn,
    StageProtocolHandshake,
    StageToolFederation,
    StageMeshSync,
    StageOperationalReady,
  ]
}

/// Converts a stage to a canonical string identifier.
pub fn stage_to_id(stage: StartupStage) -> String {
  case stage {
    StagePreflight -> "preflight_env"
    StageProviderAuth -> "provider_auth"
    StageProcessSpawn -> "process_spawn"
    StageProtocolHandshake -> "protocol_handshake"
    StageToolFederation -> "tool_federation"
    StageMeshSync -> "mesh_sync"
    StageOperationalReady -> "operational_ready"
    StageFailed(stage_id, _) -> "failed_at_" <> stage_id
  }
}

/// Computes full rich metadata for a given startup stage.
pub fn stage_metadata(
  stage: StartupStage,
  elapsed_ms: Int,
  provider: String,
  model: String,
) -> StageMetadata {
  case stage {
    StagePreflight ->
      StageMetadata(
        stage: stage,
        stage_id: "preflight_env",
        step_number: 1,
        total_steps: 6,
        progress_pct: 15,
        icon: "🔍",
        title: "Environment Preflight",
        detail: "Verifying Node.js v20+ runtime environment, CLI binary integrity, and workspace access.",
        troubleshooting_hint: "Check node/bun executable path in PATH and ensure working directory is writable.",
        elapsed_ms: elapsed_ms,
        estimated_remaining_ms: 850,
        is_active: True,
        is_completed: False,
      )

    StageProviderAuth ->
      StageMetadata(
        stage: stage,
        stage_id: "provider_auth",
        step_number: 2,
        total_steps: 6,
        progress_pct: 30,
        icon: "🔑",
        title: "Provider Authentication",
        detail: "Negotiating credentials and verifying token quota with " <> provider <> " for model " <> model <> ".",
        troubleshooting_hint: "Verify API key in environment and ensure network connectivity to upstream endpoint.",
        elapsed_ms: elapsed_ms,
        estimated_remaining_ms: 650,
        is_active: True,
        is_completed: False,
      )

    StageProcessSpawn ->
      StageMetadata(
        stage: stage,
        stage_id: "process_spawn",
        step_number: 3,
        total_steps: 6,
        progress_pct: 50,
        icon: "⚡",
        title: "Subprocess Allocation",
        detail: "Forking isolated child OS process via BEAM port driver and binding standard I/O pipes.",
        troubleshooting_hint: "Ensure OS process limits (ulimit -u) and memory cgroups allow node spawning.",
        elapsed_ms: elapsed_ms,
        estimated_remaining_ms: 450,
        is_active: True,
        is_completed: False,
      )

    StageProtocolHandshake ->
      StageMetadata(
        stage: stage,
        stage_id: "protocol_handshake",
        step_number: 4,
        total_steps: 6,
        progress_pct: 65,
        icon: "🤝",
        title: "Protocol Handshake",
        detail: "Synchronizing JSONL RPC framing over stdio channels and validating initial get_state probe.",
        troubleshooting_hint: "Confirm that CLI outputs strict single-line JSON without unescaped log noise.",
        elapsed_ms: elapsed_ms,
        estimated_remaining_ms: 300,
        is_active: True,
        is_completed: False,
      )

    StageToolFederation ->
      StageMetadata(
        stage: stage,
        stage_id: "tool_federation",
        step_number: 5,
        total_steps: 6,
        progress_pct: 80,
        icon: "🛠️",
        title: "Tool Federation",
        detail: "Compiling 26 C3I domain tools and MCP tool schemas into Pi-mono agent memory.",
        troubleshooting_hint: "Audit tool schema definitions for embedded NUL bytes or unclosed JSON quotes.",
        elapsed_ms: elapsed_ms,
        estimated_remaining_ms: 150,
        is_active: True,
        is_completed: False,
      )

    StageMeshSync ->
      StageMetadata(
        stage: stage,
        stage_id: "mesh_sync",
        step_number: 6,
        total_steps: 6,
        progress_pct: 95,
        icon: "🌐",
        title: "Mesh Synchronization",
        detail: "Subscribing to Zenoh pub/sub mesh topics (indrajaal/pi/**) and attaching OTel distributed tracing.",
        troubleshooting_hint: "Verify Zenoh router daemon availability on port 7447.",
        elapsed_ms: elapsed_ms,
        estimated_remaining_ms: 50,
        is_active: True,
        is_completed: False,
      )

    StageOperationalReady ->
      StageMetadata(
        stage: stage,
        stage_id: "operational_ready",
        step_number: 6,
        total_steps: 6,
        progress_pct: 100,
        icon: "✅",
        title: "Operational & Ready",
        detail: "Warmup probe succeeded. Pi-mono runtime is fully online and ready to process prompts.",
        troubleshooting_hint: "System nominal.",
        elapsed_ms: elapsed_ms,
        estimated_remaining_ms: 0,
        is_active: False,
        is_completed: True,
      )

    StageFailed(stage_id, reason) ->
      StageMetadata(
        stage: stage,
        stage_id: "failed",
        step_number: 0,
        total_steps: 6,
        progress_pct: 0,
        icon: "❌",
        title: "Startup Failed",
        detail: "Process startup stalled at " <> stage_id <> ": " <> reason,
        troubleshooting_hint: "Inspect error log and check provider status before resetting circuit breaker.",
        elapsed_ms: elapsed_ms,
        estimated_remaining_ms: 0,
        is_active: False,
        is_completed: False,
      )
  }
}

// =============================================================================
// Intelligent Messaging & Human Telemetry
// =============================================================================

/// Emits an intelligent, beautifully formatted human-readable console message.
pub fn format_intelligent_message(meta: StageMetadata) -> String {
  case meta.stage {
    StageOperationalReady ->
      meta.icon
      <> " [pi_startup] "
      <> meta.title
      <> " ("
      <> int.to_string(meta.elapsed_ms)
      <> "ms total): "
      <> meta.detail

    StageFailed(_, _) ->
      meta.icon
      <> " [pi_startup] "
      <> meta.title
      <> ": "
      <> meta.detail
      <> " (Hint: "
      <> meta.troubleshooting_hint
      <> ")"

    _ ->
      meta.icon
      <> " [pi_startup] Step "
      <> int.to_string(meta.step_number)
      <> "/"
      <> int.to_string(meta.total_steps)
      <> " ["
      <> int.to_string(meta.progress_pct)
      <> "%] ("
      <> int.to_string(meta.elapsed_ms)
      <> "ms elapsed, ~"
      <> int.to_string(meta.estimated_remaining_ms)
      <> "ms remaining): "
      <> meta.detail
  }
}

// =============================================================================
// AG-UI Protocol GUI Events (SC-AGUI-001)
// =============================================================================

/// Converts stage metadata into a structured AG-UI JSON payload.
pub fn stage_to_json(meta: StageMetadata, provider: String, model: String) -> json.Json {
  json.object([
    #("subsystem", json.string("pi_runtime")),
    #("stage_id", json.string(meta.stage_id)),
    #("step_number", json.int(meta.step_number)),
    #("total_steps", json.int(meta.total_steps)),
    #("progress_pct", json.int(meta.progress_pct)),
    #("icon", json.string(meta.icon)),
    #("title", json.string(meta.title)),
    #("detail", json.string(meta.detail)),
    #("troubleshooting_hint", json.string(meta.troubleshooting_hint)),
    #("elapsed_ms", json.int(meta.elapsed_ms)),
    #("estimated_remaining_ms", json.int(meta.estimated_remaining_ms)),
    #("provider", json.string(provider)),
    #("model", json.string(model)),
  ])
}

/// Constructs an authentic AG-UI Custom Event for streaming over SSE or Zenoh.
pub fn to_agui_event(
  meta: StageMetadata,
  provider: String,
  model: String,
  thread_id: String,
  run_id: String,
  timestamp: Int,
) -> AgUiEvent {
  AgUiEvent(
    event_type: Custom,
    timestamp: timestamp,
    thread_id: thread_id,
    run_id: run_id,
    payload: stage_to_json(meta, provider, model),
  )
}

// =============================================================================
// State Machine Transitions
// =============================================================================

/// Initializes a new startup state.
pub fn init_startup(provider: String, model: String, start_ms: Int) -> StartupState {
  StartupState(
    current_stage: StagePreflight,
    provider: provider,
    model: model,
    started_at_ms: start_ms,
    current_elapsed_ms: 0,
    completed_stages: [],
  )
}

/// Advances the startup state machine to the next stage.
pub fn advance_stage(
  state: StartupState,
  next_stage: StartupStage,
  now_ms: Int,
) -> StartupState {
  let elapsed = now_ms - state.started_at_ms
  StartupState(
    ..state,
    current_stage: next_stage,
    current_elapsed_ms: elapsed,
    completed_stages: list.append(state.completed_stages, [state.current_stage]),
  )
}

/// Fails the startup state machine with a specific reason.
pub fn fail_startup(
  state: StartupState,
  reason: String,
  now_ms: Int,
) -> StartupState {
  let elapsed = now_ms - state.started_at_ms
  let failed_stage = StageFailed(stage_to_id(state.current_stage), reason)
  StartupState(
    ..state,
    current_stage: failed_stage,
    current_elapsed_ms: elapsed,
  )
}

// =============================================================================
// Visual UI Rendering (Lustre MVU HTML & ANSI)
// =============================================================================

/// Renders a visually stunning, responsive startup card component for the Lustre Web UI.
pub fn render_html_startup_card(state: StartupState) -> Element(msg) {
  let meta =
    stage_metadata(
      state.current_stage,
      state.current_elapsed_ms,
      state.provider,
      state.model,
    )

  html.div(
    [
      attribute.class(
        "pi-startup-card bg-slate-900 border border-slate-700 rounded-xl p-6 shadow-2xl my-4 text-white",
      ),
      attribute.attribute("data-subsystem", "pi_runtime"),
    ],
    [
      // Header: Status Badge, Title, and Provider
      html.div([attribute.class("flex justify-between items-center mb-4")], [
        html.div([attribute.class("flex items-center space-x-3")], [
          html.span([attribute.class("text-3xl")], [html.text(meta.icon)]),
          html.div([], [
            html.h3([attribute.class("text-lg font-bold text-slate-100")], [
              html.text("Pi-mono Runtime Initialization"),
            ]),
            html.p([attribute.class("text-xs text-slate-400")], [
              html.text("Model: " <> state.provider <> " / " <> state.model),
            ]),
          ]),
        ]),
        html.div([attribute.class("flex items-center space-x-2")], [
          html.span(
            [
              attribute.class(
                "px-3 py-1 text-xs font-semibold rounded-full bg-blue-500/20 text-blue-400 border border-blue-500/40 animate-pulse",
              ),
            ],
            [html.text(int.to_string(meta.progress_pct) <> "% COMPLETE")],
          ),
          html.span(
            [attribute.class("text-xs text-slate-400 font-mono")],
            [html.text(int.to_string(meta.elapsed_ms) <> " ms")],
          ),
        ]),
      ]),

      // Progress Bar
      html.div(
        [attribute.class("w-full bg-slate-800 rounded-full h-2.5 mb-5 overflow-hidden border border-slate-700")],
        [
          html.div(
            [
              attribute.class(
                "bg-gradient-to-r from-blue-500 via-indigo-500 to-cyan-400 h-2.5 rounded-full transition-all duration-500 ease-out",
              ),
              attribute.attribute("style", "width: " <> int.to_string(meta.progress_pct) <> "%;"),
            ],
            [],
          ),
        ],
      ),

      // Active Stage Detail Box
      html.div(
        [attribute.class("bg-slate-950/70 border border-slate-800 rounded-lg p-4 mb-4")],
        [
          html.div([attribute.class("flex items-center justify-between mb-1")], [
            html.span([attribute.class("text-sm font-semibold text-cyan-300 flex items-center gap-2")], [
              html.span([attribute.class("inline-block w-2 h-2 rounded-full bg-cyan-400 animate-ping")], []),
              html.text(meta.title),
            ]),
            html.span([attribute.class("text-xs text-slate-500")], [
              html.text("Step " <> int.to_string(meta.step_number) <> " of " <> int.to_string(meta.total_steps)),
            ]),
          ]),
          html.p([attribute.class("text-xs text-slate-300 leading-relaxed")], [
            html.text(meta.detail),
          ]),
          html.p([attribute.class("text-[11px] text-amber-400/80 mt-2 font-mono flex items-center gap-1")], [
            html.text("💡 " <> meta.troubleshooting_hint),
          ]),
        ],
      ),

      // 6-Step Stepper Icons Row
      html.div(
        [attribute.class("grid grid-cols-6 gap-2 text-center text-xs pt-2 border-t border-slate-800/80")],
        list.map(
          [
            #(1, "🔍", "Preflight", StagePreflight),
            #(2, "🔑", "Auth", StageProviderAuth),
            #(3, "⚡", "Spawn", StageProcessSpawn),
            #(4, "🤝", "RPC", StageProtocolHandshake),
            #(5, "🛠️", "Tools", StageToolFederation),
            #(6, "🌐", "Mesh", StageMeshSync),
          ],
          fn(step_info) {
            let #(num, icon, name, stage_variant) = step_info
            let is_past = list.contains(state.completed_stages, stage_variant)
            let is_curr = state.current_stage == stage_variant

            let badge_class = case is_curr, is_past {
              True, _ -> "border-cyan-500 bg-cyan-500/20 text-cyan-200 font-bold scale-105"
              False, True -> "border-emerald-500/60 bg-emerald-500/10 text-emerald-400"
              False, False -> "border-slate-800 bg-slate-900/50 text-slate-600"
            }

            html.div(
              [
                attribute.class(
                  "p-2 rounded-lg border transition-all duration-300 " <> badge_class,
                ),
              ],
              [
                html.div([attribute.class("text-base")], [html.text(icon)]),
                html.div([attribute.class("text-[10px] mt-1 truncate")], [
                  html.text(int.to_string(num) <> ". " <> name),
                ]),
              ],
            )
          },
        ),
      ),
    ],
  )
}

/// Emits an ANSI colored terminal banner representing the startup stage.
pub fn render_ansi_startup_banner(state: StartupState) -> String {
  let meta =
    stage_metadata(
      state.current_stage,
      state.current_elapsed_ms,
      state.provider,
      state.model,
    )

  let color = case state.current_stage {
    StageOperationalReady -> "\u{001b}[32m"
    StageFailed(_, _) -> "\u{001b}[31m"
    _ -> "\u{001b}[36m"
  }
  let reset = "\u{001b}[0m"

  color
  <> meta.icon
  <> " [PI-STARTUP] Step "
  <> int.to_string(meta.step_number)
  <> "/"
  <> int.to_string(meta.total_steps)
  <> " ("
  <> int.to_string(meta.progress_pct)
  <> "%): "
  <> meta.title
  <> " - "
  <> meta.detail
  <> reset
}
