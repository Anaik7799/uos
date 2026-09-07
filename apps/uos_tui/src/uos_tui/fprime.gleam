//// F´ (F Prime) binding: the TUI as an `Active` ground component with typed ports,
//// commands, telemetry channels, events and parameters, plus a ground-dictionary JSON export.
//// Field names mirror `cepaf_gleam/fpp/domain.gleam` one-to-one so an adapter is a pure record copy.
//// Rocha cut: the component only *emits* intents on `cmd_out`; it never executes them.
//// STAMP: SC-TUI-FPRIME-001, SC-FPP-INTENT-001.

import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}

pub type FppPrim {
  U8
  U16
  U32
  U64
  I32
  F64
  BoolType
  StringType(size: Option(Int))
}

pub type QueueFull {
  Assert
  Block
  Drop
}

pub type Direction {
  SyncInput
  GuardedInput
  AsyncInput(priority: Option(Int), queue_full: QueueFull)
  Output
}

pub type SpecialPort {
  CommandRecv
  CommandReg
  CommandResp
  EventPort
  TextEventPort
  TelemetryPort
  TimeGet
  ParamGet
  ParamSet
}

pub type PortInstance {
  General(name: String, port: String, direction: Direction, count: Int)
  Special(SpecialPort)
}

pub type CommandKind {
  SyncCmd
  GuardedCmd
  AsyncCmd(priority: Option(Int), queue_full: QueueFull)
}

pub type Command {
  Command(
    cmd_name: String,
    opcode: Int,
    cmd_kind: CommandKind,
    cmd_params: List(#(String, FppPrim)),
  )
}

pub type Severity {
  ActivityHi
  ActivityLo
  CommandSev
  Diagnostic
  Fatal
  WarningHi
  WarningLo
}

pub type Event {
  Event(
    event_name: String,
    event_id: Int,
    severity: Severity,
    format: String,
    throttle: Option(Int),
  )
}

pub type UpdatePolicy {
  Always
  OnChange
}

pub type Channel {
  Channel(
    chan_name: String,
    chan_id: Int,
    chan_type: FppPrim,
    update: UpdatePolicy,
  )
}

pub type Parameter {
  Parameter(
    param_name: String,
    param_id: Int,
    param_type: FppPrim,
    default: Option(String),
    set_opcode: Int,
    save_opcode: Int,
  )
}

pub type ComponentKind {
  Passive
  Queued
  Active
}

pub type Component {
  Component(
    comp_name: String,
    kind: ComponentKind,
    ports: List(PortInstance),
    commands: List(Command),
    events: List(Event),
    channels: List(Channel),
    parameters: List(Parameter),
  )
}

pub type Instance {
  Instance(
    inst_name: String,
    of_component: String,
    base_id: Int,
    queue_size: Option(Int),
  )
}

/// Ground-segment base id, outside the agent DMC window [0x1000, 0x1400).
pub const base_id = 0x2000

pub const id_span = 64

pub const engine_ports = [
  "zigvm_tlm_in",
  "hermes_evidence_in",
  "max_inference_in",
  "zenoh_tlm_in",
  "agui_event_in",
  "saplan_lease_in",
]

pub fn component() -> Component {
  Component(
    comp_name: "UosTui",
    kind: Active,
    ports: list.append(
      list.map(engine_ports, fn(p) {
        General(p, "Fw.Tlm", AsyncInput(None, Drop), 1)
      }),
      [
        General("key_in", "Tui.Key", AsyncInput(Some(1), Drop), 1),
        General("cmd_out", "Fw.Cmd", Output, 1),
        General("intent_out", "Uos.Intent", Output, 1),
        Special(CommandRecv),
        Special(CommandReg),
        Special(CommandResp),
        Special(EventPort),
        Special(TextEventPort),
        Special(TelemetryPort),
        Special(TimeGet),
        Special(ParamGet),
        Special(ParamSet),
      ],
    ),
    commands: [
      Command("TUI_SET_MODE", 0x01, AsyncCmd(None, Drop), [#("mode", U8)]),
      Command("TUI_SELECT_TAB", 0x02, AsyncCmd(None, Drop), [#("tab", U8)]),
      Command("TUI_PUSH_SCREEN", 0x03, AsyncCmd(None, Drop), [
        #("screen", StringType(Some(32))),
      ]),
      Command("TUI_POP_SCREEN", 0x04, AsyncCmd(None, Drop), []),
      Command("TUI_REQUEST_INTENT", 0x05, GuardedCmd, [
        #("verb", StringType(Some(16))),
        #("target", StringType(Some(64))),
      ]),
      Command("TUI_AUDIT_ASPECTS", 0x06, SyncCmd, []),
    ],
    events: [
      Event("TuiKeyPressed", 0x01, ActivityLo, "key %s", Some(10)),
      Event("TuiScreenChanged", 0x02, ActivityHi, "screen %s depth %d", None),
      Event(
        "TuiIntentEmitted",
        0x03,
        CommandSev,
        "intent %s -> %s awaiting policy",
        None,
      ),
      Event("TuiActionBlocked", 0x04, WarningHi, "action %s blocked: %s", None),
      Event("TuiResize", 0x05, Diagnostic, "resize %dx%d", Some(5)),
      Event("TuiAspectFailed", 0x06, WarningHi, "aspect %d failed: %s", None),
      Event("TuiInterlockViolation", 0x07, Fatal, "interlock %s", None),
    ],
    channels: [
      Channel("FrameCount", 0x01, U64, Always),
      Channel("FrameMicros", 0x02, U32, Always),
      Channel("ScreenDepth", 0x03, U8, OnChange),
      Channel("FocusedWidget", 0x04, StringType(Some(32)), OnChange),
      Channel("AspectsPassed", 0x05, U8, OnChange),
      Channel("AspectsFailed", 0x06, U8, OnChange),
      Channel("CockpitMode", 0x07, U8, OnChange),
    ],
    parameters: [
      Parameter(
        "FqdnBase",
        0x01,
        StringType(Some(64)),
        Some("http://nas-1.tail55d152.ts.net:4100"),
        0x10,
        0x11,
      ),
      Parameter("RefreshMs", 0x02, U16, Some("16"), 0x12, 0x13),
      Parameter(
        "OsNvmeSerial",
        0x03,
        StringType(Some(16)),
        Some("25503L801736"),
        0x14,
        0x15,
      ),
    ],
  )
}

pub fn instance() -> Instance {
  Instance("uosTui", "UosTui", base_id, Some(128))
}

pub fn port_names(c: Component) -> List(String) {
  list.filter_map(c.ports, fn(p) {
    case p {
      General(name, ..) -> Ok(name)
      Special(_) -> Error(Nil)
    }
  })
}

pub fn channel_names(c: Component) -> List(String) {
  list.map(c.channels, fn(ch) { ch.chan_name })
}

/// Structural consistency: unique opcodes/ids and every id inside the instance span.
pub fn validate(c: Component, inst: Instance) -> Result(Nil, String) {
  let opcodes = list.map(c.commands, fn(x) { x.opcode })
  let event_ids = list.map(c.events, fn(x) { x.event_id })
  let chan_ids = list.map(c.channels, fn(x) { x.chan_id })
  let param_ids = list.map(c.parameters, fn(x) { x.param_id })
  let unique = fn(xs: List(Int)) {
    list.length(list.unique(xs)) == list.length(xs)
  }
  let in_span = fn(xs: List(Int)) {
    list.all(xs, fn(x) { x >= 0 && x < id_span })
  }
  case unique(opcodes), unique(event_ids), unique(chan_ids), unique(param_ids) {
    False, _, _, _ -> Error("duplicate command opcode")
    _, False, _, _ -> Error("duplicate event id")
    _, _, False, _ -> Error("duplicate channel id")
    _, _, _, False -> Error("duplicate parameter id")
    _, _, _, _ ->
      case
        in_span(opcodes)
        && in_span(event_ids)
        && in_span(chan_ids)
        && in_span(param_ids)
      {
        False -> Error("id outside instance span")
        True ->
          case inst.base_id >= 0x1000 && inst.base_id < 0x1400 {
            True -> Error("ground component inside agent DMC window")
            False -> Ok(Nil)
          }
      }
  }
}

fn prim_json(p: FppPrim) -> Json {
  json.string(case p {
    U8 -> "U8"
    U16 -> "U16"
    U32 -> "U32"
    U64 -> "U64"
    I32 -> "I32"
    F64 -> "F64"
    BoolType -> "bool"
    StringType(Some(n)) -> "string size " <> int.to_string(n)
    StringType(None) -> "string"
  })
}

fn severity_json(s: Severity) -> Json {
  json.string(case s {
    ActivityHi -> "ACTIVITY_HI"
    ActivityLo -> "ACTIVITY_LO"
    CommandSev -> "COMMAND"
    Diagnostic -> "DIAGNOSTIC"
    Fatal -> "FATAL"
    WarningHi -> "WARNING_HI"
    WarningLo -> "WARNING_LO"
  })
}

/// Ground dictionary in the same top-level shape as `fpp/dictionary.gleam`.
pub fn dictionary_json(c: Component, inst: Instance) -> Json {
  let abs = fn(rel: Int) { inst.base_id + rel }
  json.object([
    #(
      "metadata",
      json.object([
        #("framework_version", json.string("3.4.0-UOS")),
        #("project_version", json.string("2026.09-SIL6")),
        #("topology", json.string("UosGround")),
        #("component", json.string(c.comp_name)),
        #("instance", json.string(inst.inst_name)),
        #("base_id", json.int(inst.base_id)),
      ]),
    ),
    #(
      "ports",
      json.array(c.ports, fn(p) {
        case p {
          General(name, port, dir, count) ->
            json.object([
              #("name", json.string(name)),
              #("type", json.string(port)),
              #(
                "direction",
                json.string(case dir {
                  SyncInput -> "sync input"
                  GuardedInput -> "guarded input"
                  AsyncInput(..) -> "async input"
                  Output -> "output"
                }),
              ),
              #("count", json.int(count)),
            ])
          Special(sp) ->
            json.object([
              #(
                "special",
                json.string(case sp {
                  CommandRecv -> "command recv"
                  CommandReg -> "command reg"
                  CommandResp -> "command resp"
                  EventPort -> "event"
                  TextEventPort -> "text event"
                  TelemetryPort -> "telemetry"
                  TimeGet -> "time get"
                  ParamGet -> "param get"
                  ParamSet -> "param set"
                }),
              ),
            ])
        }
      }),
    ),
    #(
      "commands",
      json.array(c.commands, fn(cmd) {
        json.object([
          #("name", json.string(inst.inst_name <> "." <> cmd.cmd_name)),
          #("opcode", json.int(abs(cmd.opcode))),
          #("relative_opcode", json.int(cmd.opcode)),
          #("instance", json.string(inst.inst_name)),
          #(
            "kind",
            json.string(case cmd.cmd_kind {
              SyncCmd -> "sync"
              GuardedCmd -> "guarded"
              AsyncCmd(..) -> "async"
            }),
          ),
          #(
            "params",
            json.array(cmd.cmd_params, fn(pp) {
              json.object([
                #("name", json.string(pp.0)),
                #("type", prim_json(pp.1)),
              ])
            }),
          ),
        ])
      }),
    ),
    #(
      "events",
      json.array(c.events, fn(ev) {
        json.object([
          #("name", json.string(inst.inst_name <> "." <> ev.event_name)),
          #("id", json.int(abs(ev.event_id))),
          #("severity", severity_json(ev.severity)),
          #("format", json.string(ev.format)),
          #("throttle", case ev.throttle {
            Some(n) -> json.int(n)
            None -> json.null()
          }),
        ])
      }),
    ),
    #(
      "telemetryChannels",
      json.array(c.channels, fn(ch) {
        json.object([
          #("name", json.string(inst.inst_name <> "." <> ch.chan_name)),
          #("id", json.int(abs(ch.chan_id))),
          #("type", prim_json(ch.chan_type)),
          #(
            "update",
            json.string(case ch.update {
              Always -> "always"
              OnChange -> "on change"
            }),
          ),
        ])
      }),
    ),
    #(
      "parameters",
      json.array(c.parameters, fn(p) {
        json.object([
          #("name", json.string(inst.inst_name <> "." <> p.param_name)),
          #("id", json.int(abs(p.param_id))),
          #("type", prim_json(p.param_type)),
          #("default", case p.default {
            Some(d) -> json.string(d)
            None -> json.null()
          }),
          #("set_opcode", json.int(abs(p.set_opcode))),
          #("save_opcode", json.int(abs(p.save_opcode))),
        ])
      }),
    ),
  ])
}

pub fn dictionary_string() -> String {
  json.to_string(dictionary_json(component(), instance()))
}
