//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ui/lustre/pi_startup_visualizer</module>
////     <fsharp-lineage>Cepaf.UI.PiStartupVisualizer.fs</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L4_SYSTEM</layer>
////     <mesh-domain>Lustre MVU Pi Process Startup & Telemetry Visualizer</mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>DAL-A / SIL-6 / HIGH</criticality>
////     <stamp-controls>
////       SC-PI-001, SC-PI-STARTUP-001, SC-AGUI-001, SC-GLM-UI-001, SC-MUDA-001
////     </stamp-controls>
////   </compliance>
//// </c3i-module>
//// =============================================================================

import cepaf_gleam/bridge/pi_startup_classifier.{
  type StartupStage, type StartupState, StageFailed, StageMeshSync,
  StageOperationalReady, StagePreflight, StageProcessSpawn,
  StageProtocolHandshake, StageProviderAuth, StageToolFederation, advance_stage,
  fail_startup, format_intelligent_message, init_startup,
  render_html_startup_card, stage_metadata,
}
import gleam/int
import gleam/list
import gleam/option.{type Option, Some}
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

// =============================================================================
// Types
// =============================================================================

pub type Model {
  Model(
    state: StartupState,
    log_messages: List(String),
    simulated_now_ms: Int,
    selected_step_info: Option(Int),
  )
}

pub type Msg {
  NextStage
  FailStage(String)
  ResetStartup
  SetStepDetail(Int)
  ClearLogs
}

// =============================================================================
// MVU Cycle
// =============================================================================

pub fn init() -> Model {
  let initial_state = init_startup("anthropic", "claude-3-7-sonnet", 0)
  let initial_meta =
    stage_metadata(
      initial_state.current_stage,
      0,
      "anthropic",
      "claude-3-7-sonnet",
    )
  let initial_msg = format_intelligent_message(initial_meta)

  Model(
    state: initial_state,
    log_messages: [initial_msg],
    simulated_now_ms: 0,
    selected_step_info: Some(1),
  )
}

pub fn update(model: Model, msg: Msg) -> Model {
  case msg {
    NextStage -> {
      let next_stage = case model.state.current_stage {
        StagePreflight -> StageProviderAuth
        StageProviderAuth -> StageProcessSpawn
        StageProcessSpawn -> StageProtocolHandshake
        StageProtocolHandshake -> StageToolFederation
        StageToolFederation -> StageMeshSync
        StageMeshSync -> StageOperationalReady
        StageOperationalReady -> StageOperationalReady
        StageFailed(_, _) -> StagePreflight
      }

      let now = model.simulated_now_ms + 140
      let new_state = advance_stage(model.state, next_stage, now)
      let meta =
        stage_metadata(
          new_state.current_stage,
          new_state.current_elapsed_ms,
          new_state.provider,
          new_state.model,
        )
      let msg_str = format_intelligent_message(meta)

      Model(..model, state: new_state, simulated_now_ms: now, log_messages: [
        msg_str,
        ..model.log_messages
      ])
    }

    FailStage(reason) -> {
      let now = model.simulated_now_ms + 50
      let new_state = fail_startup(model.state, reason, now)
      let meta =
        stage_metadata(
          new_state.current_stage,
          new_state.current_elapsed_ms,
          new_state.provider,
          new_state.model,
        )
      let msg_str = format_intelligent_message(meta)

      Model(..model, state: new_state, simulated_now_ms: now, log_messages: [
        msg_str,
        ..model.log_messages
      ])
    }

    ResetStartup -> {
      let fresh_state = init_startup("anthropic", "claude-3-7-sonnet", 0)
      let meta =
        stage_metadata(
          fresh_state.current_stage,
          0,
          "anthropic",
          "claude-3-7-sonnet",
        )
      let msg_str = format_intelligent_message(meta)

      Model(..model, state: fresh_state, simulated_now_ms: 0, log_messages: [
        msg_str,
        ..model.log_messages
      ])
    }

    SetStepDetail(step) -> Model(..model, selected_step_info: Some(step))

    ClearLogs -> Model(..model, log_messages: [])
  }
}

// =============================================================================
// View
// =============================================================================

pub fn view(model: Model) -> Element(Msg) {
  html.div(
    [
      attribute.class(
        "pi-startup-visualizer bg-slate-900 border border-slate-700 rounded-xl p-6 text-white shadow-2xl",
      ),
    ],
    [
      render_header(),
      // Render the rich startup card
      render_html_startup_card(model.state) |> element.map(fn(_) { NextStage }),
      render_ascii_pipeline(model.state.current_stage),
      render_stage_ascii_art(model.state.current_stage),
      render_interactive_controls(model.state.current_stage),
      html.div([attribute.class("grid grid-cols-1 lg:grid-cols-2 gap-6 mt-6")], [
        render_stage_timeline(model.state),
        render_console_telemetry(model.log_messages),
      ]),
    ],
  )
}

fn render_ascii_pipeline(current: StartupStage) -> Element(Msg) {
  let ascii_art =
    "  +-----------------------------------------------------------------------------------------------------------------------------+
  |                                        PI RUNTIME 7-STAGE LIFECYCLE PIPELINE                                                 |
  +----------------+----------------+----------------+----------------+----------------+----------------+-----------------------+
  | 1. PREFLIGHT   | 2. AUTH        | 3. SPAWN       | 4. HANDSHAKE   | 5. TOOLS       | 6. MESH SYNC   | 7. OPERATIONAL READY  |
  | Node Runtime   | API Credentials| BEAM Port Fork | JSONL RPC Sync | 26 MCP Tools   | Zenoh Pub/Sub  | Warmup Probe Verified |
  | [ 15% ]        | [ 30% ]        | [ 50% ]        | [ 65% ]        | [ 80% ]        | [ 95% ]        | [ 100% ]              |
  +----------------+----------------+----------------+----------------+----------------+----------------+-----------------------+"

  let current_stage_str = case current {
    StagePreflight ->
      ">> CURRENTLY EXECUTING: STEP 1 (PREFLIGHT - Node & Binary Sanity Check) <<"
    StageProviderAuth ->
      ">> CURRENTLY EXECUTING: STEP 2 (AUTH - Negotiating Model Quota) <<"
    StageProcessSpawn ->
      ">> CURRENTLY EXECUTING: STEP 3 (SPAWN - Allocating OS Subprocess) <<"
    StageProtocolHandshake ->
      ">> CURRENTLY EXECUTING: STEP 4 (HANDSHAKE - Validating JSONL Framing) <<"
    StageToolFederation ->
      ">> CURRENTLY EXECUTING: STEP 5 (TOOLS - Federating 26 C3I Schemas) <<"
    StageMeshSync ->
      ">> CURRENTLY EXECUTING: STEP 6 (MESH SYNC - Subscribing to Zenoh & OTel) <<"
    StageOperationalReady ->
      ">> PIPELINE COMPLETE: PI RUNTIME IS OPERATIONAL & READY <<"
    StageFailed(stage, reason) ->
      ">> PIPELINE HALTED AT " <> stage <> ": " <> reason <> " <<"
  }

  html.div(
    [
      attribute.class(
        "my-4 bg-slate-950 border border-slate-800 rounded-lg p-4 font-mono text-[11px] overflow-x-auto",
      ),
    ],
    [
      html.div(
        [attribute.class("text-amber-400 font-bold mb-2 tracking-wider")],
        [html.text(current_stage_str)],
      ),
      html.pre([attribute.class("text-cyan-400 leading-tight select-all")], [
        html.text(ascii_art),
      ]),
    ],
  )
}

fn render_header() -> Element(Msg) {
  html.div(
    [
      attribute.class(
        "flex justify-between items-center mb-5 pb-3 border-b border-slate-800",
      ),
    ],
    [
      html.div([], [
        html.h2(
          [
            attribute.class(
              "text-xl font-bold text-amber-400 flex items-center gap-2",
            ),
          ],
          [
            html.span([], [html.text("🚀")]),
            html.text("Pi Runtime Lifecycle & Startup Visualizer"),
          ],
        ),
        html.p([attribute.class("text-xs text-slate-400 mt-1")], [
          html.text(
            "7-Stage Decomposition with Intelligent Contextual Messaging & Real-Time AG-UI Event Streaming",
          ),
        ]),
      ]),
      html.div([attribute.class("flex items-center gap-2")], [
        html.span(
          [
            attribute.class(
              "px-2.5 py-1 text-xs font-mono rounded bg-cyan-500/20 text-cyan-300 border border-cyan-500/40",
            ),
          ],
          [
            html.text("SC-PI-STARTUP-001"),
          ],
        ),
      ]),
    ],
  )
}

fn render_interactive_controls(current: StartupStage) -> Element(Msg) {
  let is_done = current == StageOperationalReady

  html.div(
    [
      attribute.class(
        "flex items-center gap-3 p-4 bg-slate-950 border border-slate-800 rounded-lg flex-wrap",
      ),
    ],
    [
      html.button(
        [
          attribute.class(
            "px-4 py-2 rounded bg-cyan-600 hover:bg-cyan-500 text-white font-bold text-xs flex items-center gap-2 transition-all shadow-lg "
            <> case is_done {
              True -> "opacity-50 cursor-not-allowed"
              False -> ""
            },
          ),
          event.on_click(NextStage),
        ],
        [
          html.span([], [html.text("⏩")]),
          html.text(case is_done {
            True -> "Operational (Completed)"
            False -> "Advance Next Stage"
          }),
        ],
      ),
      html.button(
        [
          attribute.class(
            "px-4 py-2 rounded bg-rose-900/60 hover:bg-rose-800 text-rose-200 border border-rose-700/60 text-xs font-semibold flex items-center gap-2 transition-all",
          ),
          event.on_click(FailStage("Mock quota exhaustion")),
        ],
        [
          html.span([], [html.text("⚠️")]),
          html.text("Simulate Error Intercept"),
        ],
      ),
      html.button(
        [
          attribute.class(
            "px-4 py-2 rounded bg-slate-800 hover:bg-slate-700 text-slate-200 border border-slate-700 text-xs font-semibold flex items-center gap-2 transition-all",
          ),
          event.on_click(ResetStartup),
        ],
        [
          html.span([], [html.text("🔄")]),
          html.text("Reset State Machine"),
        ],
      ),
    ],
  )
}

fn render_stage_timeline(state: StartupState) -> Element(Msg) {
  let stages = [
    #(
      1,
      "Environment Preflight",
      "Verifies Node runtime, binary path & permissions.",
      StagePreflight,
    ),
    #(
      2,
      "Provider Authentication",
      "Verifies API tokens and upstream quota limits.",
      StageProviderAuth,
    ),
    #(
      3,
      "Subprocess Allocation",
      "Spawns OS child process via BEAM port driver.",
      StageProcessSpawn,
    ),
    #(
      4,
      "Protocol Handshake",
      "Synchronizes JSONL framing over stdio pipes.",
      StageProtocolHandshake,
    ),
    #(
      5,
      "Tool Federation",
      "Federates 26 C3I domain tools & MCP tool schemas.",
      StageToolFederation,
    ),
    #(
      6,
      "Mesh Synchronization",
      "Subscribes to Zenoh topics & binds OTel tracing.",
      StageMeshSync,
    ),
    #(
      7,
      "Operational & Ready",
      "Warmup ping completed; ready for agent prompts.",
      StageOperationalReady,
    ),
  ]

  html.div(
    [attribute.class("bg-slate-950/70 border border-slate-800 rounded-lg p-4")],
    [
      html.h3(
        [
          attribute.class(
            "text-xs font-bold text-slate-300 uppercase tracking-wider mb-3 flex items-center justify-between",
          ),
        ],
        [
          html.span([], [html.text("Lifecycle Stage Timeline")]),
          html.span([attribute.class("font-mono text-cyan-400 text-[11px]")], [
            html.text(
              "Elapsed: " <> int.to_string(state.current_elapsed_ms) <> "ms",
            ),
          ]),
        ],
      ),
      html.div(
        [attribute.class("space-y-2")],
        list.map(stages, fn(s) {
          let #(num, title, desc, stage_val) = s
          let is_completed = list.contains(state.completed_stages, stage_val)
          let is_active = state.current_stage == stage_val

          let #(badge_bg, text_col, icon) = case is_active, is_completed {
            True, _ -> #(
              "bg-cyan-500/20 border-cyan-400 text-cyan-300 font-bold",
              "text-cyan-200",
              "⚡",
            )
            False, True -> #(
              "bg-emerald-500/15 border-emerald-500/40 text-emerald-400",
              "text-slate-300",
              "✓",
            )
            False, False -> #(
              "bg-slate-900/60 border-slate-800 text-slate-600",
              "text-slate-500",
              "○",
            )
          }

          html.div(
            [
              attribute.class(
                "p-2.5 rounded border flex items-center justify-between transition-all "
                <> badge_bg,
              ),
            ],
            [
              html.div([attribute.class("flex items-center gap-3")], [
                html.span(
                  [attribute.class("font-mono text-xs w-4 text-center")],
                  [html.text(icon)],
                ),
                html.div([], [
                  html.div(
                    [attribute.class("text-xs font-semibold " <> text_col)],
                    [
                      html.text(int.to_string(num) <> ". " <> title),
                    ],
                  ),
                  html.div([attribute.class("text-[10px] text-slate-400")], [
                    html.text(desc),
                  ]),
                ]),
              ]),
              html.span(
                [attribute.class("font-mono text-[10px] text-slate-500")],
                [
                  html.text(case is_active {
                    True -> "ACTIVE"
                    False ->
                      case is_completed {
                        True -> "DONE"
                        False -> "QUEUED"
                      }
                  }),
                ],
              ),
            ],
          )
        }),
      ),
    ],
  )
}

fn render_console_telemetry(logs: List(String)) -> Element(Msg) {
  html.div(
    [
      attribute.class(
        "bg-slate-950/90 border border-slate-800 rounded-lg p-4 flex flex-col h-[380px]",
      ),
    ],
    [
      html.div(
        [
          attribute.class(
            "flex justify-between items-center mb-2 pb-2 border-b border-slate-800/80",
          ),
        ],
        [
          html.h3(
            [
              attribute.class(
                "text-xs font-bold text-slate-300 uppercase tracking-wider flex items-center gap-2",
              ),
            ],
            [
              html.span(
                [
                  attribute.class(
                    "inline-block w-2 h-2 rounded-full bg-emerald-400 animate-pulse",
                  ),
                ],
                [],
              ),
              html.text("Intelligent Messaging Stream"),
            ],
          ),
          html.button(
            [
              attribute.class(
                "text-[10px] text-slate-500 hover:text-slate-300 font-mono",
              ),
              event.on_click(ClearLogs),
            ],
            [html.text("Clear")],
          ),
        ],
      ),
      html.div(
        [
          attribute.class(
            "flex-1 overflow-y-auto space-y-1.5 font-mono text-[11px] p-2 bg-black/50 rounded border border-slate-900",
          ),
        ],
        list.map(logs, fn(log_line) {
          html.div(
            [
              attribute.class(
                "text-slate-300 leading-relaxed break-words hover:bg-slate-900/50 p-1 rounded",
              ),
            ],
            [
              html.text(log_line),
            ],
          )
        }),
      ),
    ],
  )
}

fn render_stage_ascii_art(current: StartupStage) -> Element(Msg) {
  let #(title, color_class, art) = case current {
    StagePreflight -> #(
      "STAGE 1: PREFLIGHT RUNTIME PROBE",
      "text-cyan-400",
      "         /\\
        /  \\
       | == |      +-------------------------------------------+
       | == |      | NODE & VFS RUNTIME PROBE ACTIVE           |
       /____\\      | - Node.js v22.10.1 Detected               |
      |      |     | - Descriptor-Relative VFS Mounted         |
      |  PI  |     | - Linear Memory Arenas Allocated          |
      |______|     +-------------------------------------------+
     /| |  | |\\
    /_|_|__|_|_\\
      /      \\
     (  FLAME )
      \\______/",
    )
    StageProviderAuth -> #(
      "STAGE 2: MODEL PROVIDER AUTHENTICATION & QUOTA",
      "text-amber-400",
      "     .-----------------------.
    /   PROVIDER AUTH SHIELD  \\
   |   [ ANTHROPIC CLAUDE ]    |     +-------------------------------------------+
   |        .--------.         |     | CRYPTOGRAPHIC TOKEN VERIFICATION          |
   |       /  .---.   \\        |     | - Provider: Anthropic API / Claude 3.7    |
   |      |  /     \\   |       |     | - Token SHA-256 Digest Confirmed          |
   |      |  \\_____/   |       |     | - Ingress Rate-Limit: Nominal             |
   |       \\     |     /       |     +-------------------------------------------+
   |        '----|----'        |
   |             |             |
    \\      KEY VERIFIED       /
     '-----------------------'",
    )
    StageProcessSpawn -> #(
      "STAGE 3: BEAM OS SUBPROCESS FORK & PIPES",
      "text-blue-400",
      "+=============================================================================+
|                      BEAM OS SUBPROCESS SPAWN & IPC                         |
|   +-----------------------+                 +-----------------------+       |
|   | BEAM OTP 29 SUPERVISOR|                 | PI RUNTIME SUBPROCESS |       |
|   | Port Controller       |===============> | Stdio JSON-RPC Daemon |       |
|   | PID: <0.4100.0>       |                 | OS PID: 42109         |       |
|   +-----------------------+                 +-----------------------+       |
|              |                                          |                   |
|              +==========> STDIN PIPE (Requests) =======>+                   |
|              +<========== STDOUT PIPE (Responses) <=====+                   |
|              +<========== STDERR PIPE (Telemetry) <=====+                   |
+=============================================================================+",
    )
    StageProtocolHandshake -> #(
      "STAGE 4: JSONL PROTOCOL HANDSHAKE & FRAMING",
      "text-purple-400",
      "     CLIENT GATEWAY (BEAM)                     PI DAEMON (SUBPROCESS)
           |                                             |
           |========== 1. SYN: PROTOCOL_VERSION =========>|
           |                                             |
           |<========= 2. ACK: v22.10.1-JSONL ===========|
           |                                             |
           |========== 3. REQ: AG-UI 32-EVENT SPEC ======>|
           |                                             |
           |<========= 4. RES: {EVENTS, TOOLS, SSE} =====|
           |                                             |
     [ STATUS: FRAMING LOCKED & RFC 6902 DELTAS SYNCHRONIZED ]",
    )
    StageToolFederation -> #(
      "STAGE 5: MCP FEDERATED TOOL SCHEMA REGISTRATION",
      "text-emerald-400",
      "+=============================================================================+
|                       C3I MCP 26-TOOL FEDERATION ARRAY                      |
+-----------------------------------------------------------------------------+
| [PLAN] plan_status         | [SYS] system_health       | [DOM] ooda_decide  |
| [PLAN] plan_list_pending   | [SYS] system_dashboard    | [DOM] prajna_health|
| [PLAN] plan_add            | [SYS] system_zenoh        | [DOM] dark_cockpit |
| [PLAN] plan_update         | [SYS] system_immune       | [DOM] mesh_topol   |
| [KNOW] knowledge_search    | [SYS] system_verification | [DOM] kms_catalog  |
| [KNOW] verification_run    | [DOM] podman_containers   | [UTIL] read_file   |
+-----------------------------------------------------------------------------+
| ALL 26 MCP TOOL SCHEMAS DIGESTED & BOUND TO BEAM NIF DISPATCH DISCIPLINE    |
+=============================================================================+",
    )
    StageMeshSync -> #(
      "STAGE 6: ZENOH PUB/SUB MESH & OTEL TELEMETRY SYNC",
      "text-teal-400",
      "                  .-''''-.
                .'        '.        ((( ZENOH DISTRIBUTED MESH WAVE )))
               /   (o)  (o) \\      .- - - - - - - - - - - - - - - - - - .
              :     __  __   :    (  TOPIC: indrajaal/otel/span/pi/**    )
              :    |  ||  |  :     '- - - - - - - - - - - - - - - - - - '
               \\   '------' /                     |
                '.        .'                      v
                  '-....-'          +---------------------------+
                     ||             | 128-bit W3C Trace IDs     |
                 .---||---.         | Microsecond UTC ISO 8601  |
                /    ||    \\        | Fractal Scale Annotations |
               *     ||     *       +---------------------------+",
    )
    StageOperationalReady -> #(
      "STAGE 7: OPERATIONAL DARK COCKPIT READY",
      "text-green-400",
      "+=============================================================================+
|             *** CYBERNETIC COMMAND & CONTROL COCKPIT ACTIVE ***             |
+=============================================================================+
|   [BOOT LATENCY] 140ms  |  [RSS MEMORY] 42.8 MB  |  [HEALTH] 100% OPERATIONAL|
|   (●) GAUGES NOMINAL      (●) PRAJNA BREAKER CLOSED  (●) SIL-6 ASSURED      |
|                                                                             |
|                 \\               |               /                           |
|                  \\        .-----|-----.        /                            |
|                   \\      /   100% OK   \\      /                             |
|              -------+---| DARK COCKPIT |---+-------                         |
|                   /      \\   SIL-6 DAL /      \\                             |
|                  /        '-----|-----'        \\                            |
|                 /               |               \\                           |
+=============================================================================+",
    )
    StageFailed(stage, reason) -> #(
      "STARTUP INTERCEPT / CIRCUIT BREAKER TRIPPED",
      "text-rose-400",
      "+=============================================================================+
|                      !!! PRAJNA CIRCUIT BREAKER TRIPPED !!!                 |
+=============================================================================+
|                 /\\                  FAILED AT STAGE: "
        <> stage
        <> "
|                /  \\                 REASON: "
        <> reason
        <> "
|               / !! \\                ACTION: Fail-Closed Interlock Active
|              /______\\               RECOVERY: Click 'Reset State Machine'
|                                                                             |
|  [SAFETY NOTICE] OS Root NVMe serial 25503L801736 remained strictly locked.  |
+=============================================================================+",
    )
  }

  html.div(
    [
      attribute.class(
        "my-4 bg-slate-950 border border-slate-800 rounded-lg p-4 font-mono text-[11px] overflow-x-auto shadow-inner",
      ),
    ],
    [
      html.div(
        [attribute.class("font-bold mb-2 tracking-wider " <> color_class)],
        [html.text(title)],
      ),
      html.pre([attribute.class("leading-tight select-all " <> color_class)], [
        html.text(art),
      ]),
    ],
  )
}
