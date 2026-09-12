// control_center_demo.gleam — Interactive Lustre MVU SSR Demonstration of
// UOS Tactile Flight Instruments, NASA JPL F' Statecharts & Dark Cockpit Affordances.
//
// Governing Contracts:
// - SC-GLM-UI-001 (Triple-Interface Mandate)
// - SC-HMI-010 (Dark Cockpit Ergonomics)
// - SC-JIDOKA-001 (Fail-Closed Andon Stop Line)
// - SC-CHECKLIST-001 (Comprehensive 18-Checkpoint Checklist)

import gleam/float
import gleam/int
import gleam/list
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

pub type ControlCenterDemoModel {
  ControlCenterDemoModel(
    // Instrument 1: Spring-Loaded Cover
    spring_cover_open: Bool,
    spring_timer_ms: Int,
    spring_armed: Bool,
    // Instrument 2: Two-Man Interlock
    key_a_turned: Bool,
    key_b_turned: Bool,
    interlock_skew_ms: Int,
    // Instrument 3: Andon Pull Cord
    andon_tripped: Bool,
    andon_reason: String,
    // Instrument 4: Hardware OS Drive Sentry
    os_drive_serial: String,
    os_drive_locked: Bool,
    // Instrument 5: Lyapunov Stability Dial
    lyapunov_energy: Float,
    lyapunov_damping: Float,
    // Instrument 6: Rocha Semiotics Scope
    rocha_divergence: Float,
    // Instrument 7: Heijunka Pull Rack
    active_worker_tasks: List(String),
    // Instrument 8: Sheaf Cohomology Matrix
    cohomology_h1_zero: Bool,
    // Operational Audit Log
    event_log: List(String),
  )
}

pub type ControlCenterDemoMsg {
  ToggleSpringCover
  ConfirmSpringActuate
  TurnKeyA
  TurnKeyB
  PullAndonCord(reason: String)
  ResetAndonCord
  TickAutoClose(delta_ms: Int)
  UpdateLyapunov(new_energy: Float)
  ClearLog
}

pub fn init() -> ControlCenterDemoModel {
  ControlCenterDemoModel(
    spring_cover_open: False,
    spring_timer_ms: 5000,
    spring_armed: False,
    key_a_turned: False,
    key_b_turned: False,
    interlock_skew_ms: 30000,
    andon_tripped: False,
    andon_reason: "",
    os_drive_serial: "25503L801736",
    os_drive_locked: True,
    lyapunov_energy: 0.142,
    lyapunov_damping: -0.048,
    rocha_divergence: 0.042,
    active_worker_tasks: ["Task-42 (L0 Const)", "Task-43 (L4 OODA)"],
    cohomology_h1_zero: True,
    event_log: ["[21:05:00Z] System initialized into Dark Cockpit Standby"],
  )
}

pub fn update(
  model: ControlCenterDemoModel,
  msg: ControlCenterDemoMsg,
) -> ControlCenterDemoModel {
  case msg {
    ToggleSpringCover -> {
      let new_state = !model.spring_cover_open
      let log_msg = case new_state {
        True -> "[ACTUATION] Spring-loaded cover flipped OPEN (5.0s timer active)"
        False -> "[SAFETY] Spring-loaded cover snapped SHUT"
      }
      ControlCenterDemoModel(
        ..model,
        spring_cover_open: new_state,
        spring_armed: new_state,
        spring_timer_ms: 5000,
        event_log: [log_msg, ..model.event_log],
      )
    }

    ConfirmSpringActuate -> {
      case model.spring_cover_open {
        True -> {
          let log_msg =
            "[DISPATCH] High-consequence command confirmed & dispatched to F' CmdIn port"
          ControlCenterDemoModel(
            ..model,
            spring_cover_open: False,
            spring_armed: False,
            event_log: [log_msg, ..model.event_log],
          )
        }
        False -> {
          let log_msg =
            "[TRIPWIRE] Blocked actuation: Cover is CLOSED (ERR_COVER_CLOSED)"
          ControlCenterDemoModel(..model, event_log: [log_msg, ..model.event_log])
        }
      }
    }

    TurnKeyA -> {
      let new_a = !model.key_a_turned
      let both_turned = new_a && model.key_b_turned
      let log_msg = case new_a {
        True ->
          "[CONSENSUS] Sovereign Key A turned 90-deg (Awaiting Sovereign Key B)"
        False -> "[CONSENSUS] Sovereign Key A disengaged"
      }
      let final_log = case both_turned {
        True -> [
          "[CIRCUIT CLOSED] Dual-Key Consensus Achieved -> Solenoid Relay Engaged",
          log_msg,
          ..model.event_log
        ]
        False -> [log_msg, ..model.event_log]
      }
      ControlCenterDemoModel(..model, key_a_turned: new_a, event_log: final_log)
    }

    TurnKeyB -> {
      let new_b = !model.key_b_turned
      let both_turned = model.key_a_turned && new_b
      let log_msg = case new_b {
        True ->
          "[CONSENSUS] Sovereign Key B turned 90-deg (Awaiting Sovereign Key A)"
        False -> "[CONSENSUS] Sovereign Key B disengaged"
      }
      let final_log = case both_turned {
        True -> [
          "[CIRCUIT CLOSED] Dual-Key Consensus Achieved -> Solenoid Relay Engaged",
          log_msg,
          ..model.event_log
        ]
        False -> [log_msg, ..model.event_log]
      }
      ControlCenterDemoModel(..model, key_b_turned: new_b, event_log: final_log)
    }

    PullAndonCord(reason) -> {
      let log_msg =
        "[ANDON HALT] Jidoka Stop Line tripped: "
        <> reason
        <> " (Error -32002 Fail-Closed)"
      ControlCenterDemoModel(
        ..model,
        andon_tripped: True,
        andon_reason: reason,
        event_log: [log_msg, ..model.event_log],
      )
    }

    ResetAndonCord -> {
      let log_msg =
        "[JIDOKA RESUME] Root Supervisor L0 physical clearance key verified. Line resumed."
      ControlCenterDemoModel(
        ..model,
        andon_tripped: False,
        andon_reason: "",
        event_log: [log_msg, ..model.event_log],
      )
    }

    TickAutoClose(delta_ms) -> {
      case model.spring_cover_open {
        True -> {
          let rem = model.spring_timer_ms - delta_ms
          case rem <= 0 {
            True -> {
              let log_msg =
                "[TIMEOUT] 5000ms window elapsed. Spring cover automatically snapped SHUT."
              ControlCenterDemoModel(
                ..model,
                spring_cover_open: False,
                spring_armed: False,
                spring_timer_ms: 0,
                event_log: [log_msg, ..model.event_log],
              )
            }
            False -> ControlCenterDemoModel(..model, spring_timer_ms: rem)
          }
        }
        False -> model
      }
    }

    UpdateLyapunov(new_energy) -> {
      let delta = new_energy -. model.lyapunov_energy
      let log_msg =
        "[LYAPUNOV] V(e) updated to "
        <> float.to_string(new_energy)
        <> " (dV/dt = "
        <> float.to_string(delta)
        <> ")"
      ControlCenterDemoModel(
        ..model,
        lyapunov_energy: new_energy,
        lyapunov_damping: delta,
        event_log: [log_msg, ..model.event_log],
      )
    }

    ClearLog -> ControlCenterDemoModel(..model, event_log: [])
  }
}

pub fn view(model: ControlCenterDemoModel) -> Element(ControlCenterDemoMsg) {
  html.div(
    [
      attribute.class(
        "control-center-demo bg-slate-950 text-slate-100 min-h-screen p-6 font-mono",
      ),
    ],
    [
      render_masthead(model),
      html.div([attribute.class("grid grid-cols-1 lg:grid-cols-2 gap-6 mt-6")], [
        render_spring_cover_card(model),
        render_two_man_card(model),
        render_andon_cord_card(model),
        render_storage_sentry_card(model),
        render_lyapunov_card(model),
        render_rocha_scope_card(model),
        render_heijunka_card(model),
        render_sheaf_card(model),
      ]),
      render_event_log(model),
    ],
  )
}

fn render_masthead(
  model: ControlCenterDemoModel,
) -> Element(ControlCenterDemoMsg) {
  html.header(
    [
      attribute.class(
        "flex justify-between items-center bg-slate-900 border border-slate-800 p-4 rounded-lg shadow-lg",
      ),
    ],
    [
      html.div([attribute.class("flex items-center space-x-3")], [
        html.span([attribute.class("text-red-500 font-bold text-xl")], [
          element.text("[C3I-SIL6]"),
        ]),
        html.h1([attribute.class("text-lg font-semibold text-slate-200")], [
          element.text("Cybernetic Control Center Tactile Flight Instruments"),
        ]),
      ]),
      html.div([attribute.class("flex items-center space-x-4 text-xs")], [
        html.span([attribute.class("text-slate-400")], [
          element.text("Tailnet: nas-1.tail55d152.ts.net:4100"),
        ]),
        case model.andon_tripped {
          True ->
            html.span(
              [
                attribute.class(
                  "bg-red-900/80 text-red-200 px-2 py-1 rounded border border-red-700 animate-pulse",
                ),
              ],
              [element.text("ANDON HALT ACTIVE")],
            )
          False ->
            html.span(
              [
                attribute.class(
                  "bg-emerald-900/60 text-emerald-300 px-2 py-1 rounded border border-emerald-700",
                ),
              ],
              [element.text("DARK COCKPIT NOMINAL")],
            )
        },
      ]),
    ],
  )
}

fn render_spring_cover_card(
  model: ControlCenterDemoModel,
) -> Element(ControlCenterDemoMsg) {
  html.div(
    [
      attribute.class(
        "bg-slate-900 border border-slate-800 rounded-lg p-5 shadow",
      ),
    ],
    [
      html.div([attribute.class("flex justify-between items-center mb-3")], [
        html.h2([attribute.class("text-sm font-bold text-amber-500")], [
          element.text("1. SPRING-LOADED COVER BUTTON (Two-Stage Switch)"),
        ]),
        html.span([attribute.class("text-xs text-slate-400")], [
          element.text("Target: /dev/nvme0n1"),
        ]),
      ]),
      html.div([attribute.class("p-4 bg-slate-950 rounded border border-slate-800 my-2")], [
        case model.spring_cover_open {
          False ->
            html.button(
              [
                attribute.class(
                  "w-full py-6 text-center text-xs font-bold text-slate-300 rounded border border-slate-700 hover:border-amber-500 transition cursor-pointer",
                ),
                attribute.attribute(
                  "style",
                  "background: repeating-linear-gradient(45deg, #1e293b, #1e293b 10px, #334155 10px, #334155 20px);",
                ),
                event.on_click(ToggleSpringCover),
              ],
              [element.text("[ CLICK TO FLIP SPRING COVER OPEN ]")],
            )
          True ->
            html.div([attribute.class("space-y-3")], [
              html.div([attribute.class("flex justify-between text-xs text-red-400")], [
                html.span([], [element.text("COVER: OPEN (DANGER)")]),
                html.span([attribute.class("font-bold")], [
                  element.text(
                    "TIMER: "
                    <> float.to_string(int.to_float(model.spring_timer_ms) /. 1000.0)
                    <> "s",
                  ),
                ]),
              ]),
              html.button(
                [
                  attribute.class(
                    "w-full py-4 text-center text-sm font-bold text-white bg-red-600 hover:bg-red-500 rounded border border-red-400 shadow-[0_0_15px_rgba(220,38,38,0.7)] cursor-pointer animate-pulse",
                  ),
                  event.on_click(ConfirmSpringActuate),
                ],
                [element.text(">>> PRESS TO CONFIRM REBOOT <<<")],
              ),
              html.button(
                [
                  attribute.class(
                    "w-full py-1 text-center text-xs text-slate-400 hover:text-slate-200 cursor-pointer",
                  ),
                  event.on_click(ToggleSpringCover),
                ],
                [element.text("[ Snap Cover Shut (Cancel) ]")],
              ),
            ])
        },
      ]),
      html.p([attribute.class("text-xs text-slate-500 mt-2")], [
        element.text(
          "Mechanical spring resistance prevents accidental clicks. 5-second vulnerability window automatically snaps shut on expiry.",
        ),
      ]),
    ],
  )
}

fn render_two_man_card(
  model: ControlCenterDemoModel,
) -> Element(ControlCenterDemoMsg) {
  let circuit_closed = model.key_a_turned && model.key_b_turned
  html.div(
    [
      attribute.class(
        "bg-slate-900 border border-slate-800 rounded-lg p-5 shadow",
      ),
    ],
    [
      html.div([attribute.class("flex justify-between items-center mb-3")], [
        html.h2([attribute.class("text-sm font-bold text-amber-500")], [
          element.text("2. TWO-MAN SOVEREIGN INTERLOCK (Dual-Key)"),
        ]),
        html.span([attribute.class("text-xs text-slate-400")], [
          element.text("Quorum: 2/2"),
        ]),
      ]),
      html.div([attribute.class("grid grid-cols-2 gap-4 my-2")], [
        html.button(
          [
            attribute.class(case model.key_a_turned {
              True ->
                "py-4 rounded border border-cyan-500 bg-cyan-950 text-cyan-300 font-bold text-xs"
              False ->
                "py-4 rounded border border-slate-700 bg-slate-950 text-slate-400 hover:border-slate-500 font-bold text-xs"
            }),
            event.on_click(TurnKeyA),
          ],
          [
            element.text(case model.key_a_turned {
              True -> "KEY A: [ TURNED 90-DEG ]"
              False -> "KEY A: [ DISENGAGED ]"
            }),
          ],
        ),
        html.button(
          [
            attribute.class(case model.key_b_turned {
              True ->
                "py-4 rounded border border-cyan-500 bg-cyan-950 text-cyan-300 font-bold text-xs"
              False ->
                "py-4 rounded border border-slate-700 bg-slate-950 text-slate-400 hover:border-slate-500 font-bold text-xs"
            }),
            event.on_click(TurnKeyB),
          ],
          [
            element.text(case model.key_b_turned {
              True -> "KEY B: [ TURNED 90-DEG ]"
              False -> "KEY B: [ DISENGAGED ]"
            }),
          ],
        ),
      ]),
      html.div(
        [
          attribute.class(case circuit_closed {
            True ->
              "p-2 rounded bg-emerald-950 border border-emerald-600 text-emerald-300 text-xs text-center font-bold"
            False ->
              "p-2 rounded bg-slate-950 border border-slate-800 text-slate-500 text-xs text-center"
          }),
        ],
        [
          element.text(case circuit_closed {
            True -> "SOLENOID RELAY ENGAGED (CONSENSUS RATIFIED)"
            False -> "SOLENOID INTERLOCK: HARD LOCKED (0/2)"
          }),
        ],
      ),
      html.p([attribute.class("text-xs text-slate-500 mt-2")], [
        element.text(
          "Requires two independent cryptographic signers within a 30-second skew window to close the command ignition circuit.",
        ),
      ]),
    ],
  )
}

fn render_andon_cord_card(
  model: ControlCenterDemoModel,
) -> Element(ControlCenterDemoMsg) {
  html.div(
    [
      attribute.class(
        "bg-slate-900 border border-slate-800 rounded-lg p-5 shadow",
      ),
    ],
    [
      html.div([attribute.class("flex justify-between items-center mb-3")], [
        html.h2([attribute.class("text-sm font-bold text-red-500")], [
          element.text("3. FRACTAL JIDOKA TPS ANDON CORD (Stop Line)"),
        ]),
        html.span([attribute.class("text-xs text-slate-400")], [
          element.text("Mandate: SC-JIDOKA-001"),
        ]),
      ]),
      html.div([attribute.class("p-4 bg-slate-950 rounded border border-slate-800 my-2 text-center")], [
        case model.andon_tripped {
          False ->
            html.button(
              [
                attribute.class(
                  "py-3 px-6 bg-red-950/40 hover:bg-red-900/60 border border-red-700 text-red-300 font-bold rounded cursor-pointer transition",
                ),
                event.on_click(PullAndonCord("Manual Operator Emergency Stop")),
              ],
              [element.text("||| YANK BRAIDED ANDON PULL CORD |||")],
            )
          True ->
            html.div([attribute.class("space-y-3")], [
              html.div([attribute.class("text-red-400 font-bold text-xs")], [
                element.text("! STOP LINE ACTIVE ! Reason: " <> model.andon_reason),
              ]),
              html.button(
                [
                  attribute.class(
                    "py-2 px-4 bg-slate-800 hover:bg-slate-700 border border-slate-600 text-xs text-slate-200 rounded cursor-pointer",
                  ),
                  event.on_click(ResetAndonCord),
                ],
                [element.text("[ Reset Stop Line via L0 Clearance Key ]")],
              ),
            ])
        },
      ]),
      html.p([attribute.class("text-xs text-slate-500 mt-2")], [
        element.text(
          "Immediately halts autonomous worker pull queues across all 10 fractal layers, failing closed to bottom state Bot (code -32002).",
        ),
      ]),
    ],
  )
}

fn render_storage_sentry_card(
  model: ControlCenterDemoModel,
) -> Element(ControlCenterDemoMsg) {
  html.div(
    [
      attribute.class(
        "bg-slate-900 border border-slate-800 rounded-lg p-5 shadow",
      ),
    ],
    [
      html.div([attribute.class("flex justify-between items-center mb-3")], [
        html.h2([attribute.class("text-sm font-bold text-amber-500")], [
          element.text("4. HARDWARE OS DRIVE SENTRY PADLOCK"),
        ]),
        html.span([attribute.class("text-xs text-emerald-400 font-bold")], [
          element.text("[ LOCKED ]"),
        ]),
      ]),
      html.div([attribute.class("p-3 bg-slate-950 rounded border border-slate-800 my-2 text-xs space-y-1")], [
        html.div([attribute.class("flex justify-between text-slate-400")], [
          html.span([], [element.text("Drive Serial:")]),
          html.span([attribute.class("font-bold text-slate-200")], [
            element.text(model.os_drive_serial),
          ]),
        ]),
        html.div([attribute.class("flex justify-between text-slate-400")], [
          html.span([], [element.text("Interlock Rule:")]),
          html.span([attribute.class("text-red-400")], [
            element.text("HARD_DENIED_SYSTEM_OS_SERIAL"),
          ]),
        ]),
        html.div([attribute.class("flex justify-between text-slate-400")], [
          html.span([], [element.text("Enforcement:")]),
          html.span([attribute.class("text-cyan-400")], [
            element.text("Tri-Kernel (Rust + OCaml + Gleam)"),
          ]),
        ]),
      ]),
      html.p([attribute.class("text-xs text-slate-500 mt-2")], [
        element.text(
          "Host NVMe system root drive is mathematically barred from Rook-Ceph allocation, wiping, or persistent volume formatting.",
        ),
      ]),
    ],
  )
}

fn render_lyapunov_card(
  model: ControlCenterDemoModel,
) -> Element(ControlCenterDemoMsg) {
  html.div(
    [
      attribute.class(
        "bg-slate-900 border border-slate-800 rounded-lg p-5 shadow",
      ),
    ],
    [
      html.div([attribute.class("flex justify-between items-center mb-3")], [
        html.h2([attribute.class("text-sm font-bold text-emerald-500")], [
          element.text("5. LYAPUNOV STABILITY ENERGY DIAL (V(e))"),
        ]),
        html.span([attribute.class("text-xs text-slate-400")], [
          element.text("Ceiling: 0.850"),
        ]),
      ]),
      html.div([attribute.class("p-3 bg-slate-950 rounded border border-slate-800 my-2 space-y-2")], [
        html.div([attribute.class("flex justify-between text-xs")], [
          html.span([attribute.class("text-slate-400")], [
            element.text("Energy: V(e)"),
          ]),
          html.span([attribute.class("text-emerald-400 font-bold")], [
            element.text(float.to_string(model.lyapunov_energy) <> " Joules"),
          ]),
        ]),
        html.div([attribute.class("flex justify-between text-xs")], [
          html.span([attribute.class("text-slate-400")], [
            element.text("Damping: dV/dt"),
          ]),
          html.span([attribute.class("text-cyan-400 font-bold")], [
            element.text(float.to_string(model.lyapunov_damping) <> " / s"),
          ]),
        ]),
        html.div([attribute.class("w-full bg-slate-800 h-2 rounded overflow-hidden")], [
          html.div(
            [
              attribute.class("bg-emerald-500 h-full"),
              attribute.attribute(
                "style",
                "width: "
                <> float.to_string(model.lyapunov_energy *. 100.0)
                <> "%",
              ),
            ],
            [],
          ),
        ]),
      ]),
      html.p([attribute.class("text-xs text-slate-500 mt-2")], [
        element.text(
          "Asymptotic stability monitor ensuring negative decay rate dV/dt < 0. Dynamically throttles swarm pull rates on divergence.",
        ),
      ]),
    ],
  )
}

fn render_rocha_scope_card(
  model: ControlCenterDemoModel,
) -> Element(ControlCenterDemoMsg) {
  html.div(
    [
      attribute.class(
        "bg-slate-900 border border-slate-800 rounded-lg p-5 shadow",
      ),
    ],
    [
      html.div([attribute.class("flex justify-between items-center mb-3")], [
        html.h2([attribute.class("text-sm font-bold text-cyan-400")], [
          element.text("6. ROCHA SEMIOTICS DUAL-BEAM CRT SCOPE"),
        ]),
        html.span([attribute.class("text-xs text-slate-400")], [
          element.text("D_EA <= 10.0%"),
        ]),
      ]),
      html.div([attribute.class("p-3 bg-slate-950 rounded border border-slate-800 my-2 space-y-2")], [
        html.div([attribute.class("flex justify-between text-xs")], [
          html.span([attribute.class("text-slate-400")], [
            element.text("Beam Congruence D_EA:"),
          ]),
          html.span([attribute.class("text-cyan-300 font-bold")], [
            element.text(
              float.to_string(model.rocha_divergence *. 100.0) <> "% (NOMINAL)",
            ),
          ]),
        ]),
        html.div([attribute.class("font-mono text-xs text-cyan-600")], [
          element.text("CH1: /\\/\\/\\/\\/\\ (Syntactic Intent)"),
        ]),
        html.div([attribute.class("font-mono text-xs text-amber-500")], [
          element.text("CH2: =/\\/\\/\\/\\/= (Observed Semantics)"),
        ]),
      ]),
      html.p([attribute.class("text-xs text-slate-500 mt-2")], [
        element.text(
          "Measures divergence between declarative user intent and actual runtime execution. Prevents hallucinated drift.",
        ),
      ]),
    ],
  )
}

fn render_heijunka_card(
  model: ControlCenterDemoModel,
) -> Element(ControlCenterDemoMsg) {
  html.div(
    [
      attribute.class(
        "bg-slate-900 border border-slate-800 rounded-lg p-5 shadow",
      ),
    ],
    [
      html.div([attribute.class("flex justify-between items-center mb-3")], [
        html.h2([attribute.class("text-sm font-bold text-amber-500")], [
          element.text("7. HEIJUNKA LEVELED KANBAN PULL RACK"),
        ]),
        html.span([attribute.class("text-xs text-slate-400")], [
          element.text("Cadence: 100ms"),
        ]),
      ]),
      html.div([attribute.class("p-3 bg-slate-950 rounded border border-slate-800 my-2 text-xs space-y-2")], [
        html.div([attribute.class("text-slate-400")], [
          element.text("Active Leased Slots:"),
        ]),
        html.div(
          [attribute.class("space-y-1")],
          list.map(model.active_worker_tasks, fn(task) {
            html.div(
              [
                attribute.class(
                  "p-1.5 rounded bg-slate-900 border border-slate-800 text-slate-300 flex justify-between",
                ),
              ],
              [
                html.span([], [element.text(task)]),
                html.span([attribute.class("text-emerald-400 font-bold")], [
                  element.text("LEASED"),
                ]),
              ],
            )
          }),
        ),
      ]),
      html.p([attribute.class("text-xs text-slate-500 mt-2")], [
        element.text(
          "Paces and level-loads work across autonomous workers, preventing resource starvation and eliminating Muda waste.",
        ),
      ]),
    ],
  )
}

fn render_sheaf_card(
  _model: ControlCenterDemoModel,
) -> Element(ControlCenterDemoMsg) {
  html.div(
    [
      attribute.class(
        "bg-slate-900 border border-slate-800 rounded-lg p-5 shadow",
      ),
    ],
    [
      html.div([attribute.class("flex justify-between items-center mb-3")], [
        html.h2([attribute.class("text-sm font-bold text-cyan-400")], [
          element.text("8. SHEAF COHOMOLOGY AGREEMENT MATRIX"),
        ]),
        html.span([attribute.class("text-xs text-emerald-400 font-bold")], [
          element.text("H^1(U, F) = 0"),
        ]),
      ]),
      html.div([attribute.class("p-3 bg-slate-950 rounded border border-slate-800 my-2 text-xs space-y-1 font-mono text-center")], [
        html.div([attribute.class("text-emerald-400")], [
          element.text("[U0..U9]: 45/45 INTERSECTIONS COMMUTATIVE"),
        ]),
        html.div([attribute.class("text-slate-500 text-[10px]")], [
          element.text("phi_jk o phi_ij == phi_ik on all triple overlaps"),
        ]),
      ]),
      html.p([attribute.class("text-xs text-slate-500 mt-2")], [
        element.text(
          "Zero first cohomology group mathematically guarantees no cross-screen tearing or stale state hallucination.",
        ),
      ]),
    ],
  )
}

fn render_event_log(
  model: ControlCenterDemoModel,
) -> Element(ControlCenterDemoMsg) {
  html.section(
    [
      attribute.class(
        "mt-6 bg-slate-900 border border-slate-800 rounded-lg p-5 shadow",
      ),
    ],
    [
      html.div([attribute.class("flex justify-between items-center mb-3")], [
        html.h2([attribute.class("text-sm font-bold text-slate-300")], [
          element.text("OPERATIONAL AUDIT TRAIL (C3I Telemetry Stream)"),
        ]),
        html.button(
          [
            attribute.class(
              "text-xs text-slate-500 hover:text-slate-300 cursor-pointer",
            ),
            event.on_click(ClearLog),
          ],
          [element.text("[ Clear Log ]")],
        ),
      ]),
      html.div(
        [
          attribute.class(
            "p-3 bg-slate-950 rounded border border-slate-800 max-h-40 overflow-y-auto space-y-1 text-xs font-mono text-slate-400",
          ),
        ],
        list.map(model.event_log, fn(entry) {
          html.div([attribute.class("hover:text-slate-200")], [
            element.text(entry),
          ])
        }),
      ),
    ],
  )
}
