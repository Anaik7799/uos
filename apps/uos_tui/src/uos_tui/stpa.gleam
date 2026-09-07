//// STPA (System-Theoretic Process Analysis) model for the uos_tui app and
//// its build swarm: losses, hazards, controllers, control actions,
//// unsafe control actions (UCAs), and constraints with enforcement.
////
//// Reference: STPA (Leveson) unsafe-control-action taxonomy; Textual/TUI
//// analog is the app <-> driver <-> terminal control loop.
//// STAMP id: SC-TUI-W07-001

import gleam/float
import gleam/int
import gleam/list
import gleam/string

pub type Loss {
  Loss(id: String, text: String)
}

pub type Hazard {
  Hazard(id: String, text: String, losses: List(String))
}

pub type Controller {
  Controller(id: String, name: String)
}

pub type ControlAction {
  ControlAction(id: String, controller: String, name: String)
}

pub type UcaType {
  NotProvided
  ProvidedUnsafe
  WrongTiming
  StoppedTooSoon
}

pub type Uca {
  Uca(
    id: String,
    source: String,
    uca_type: UcaType,
    control_action: String,
    context: String,
    hazards: List(String),
    pms: Int,
    cif: Int,
    sif: Int,
    ej: Float,
    band: String,
  )
}

pub type Enforcement {
  HarnessCheck(String)
  Production(String)
  ProcessRule(String)
}

pub type Constraint {
  Constraint(
    id: String,
    uca_ids: List(String),
    text: String,
    enforcement: Enforcement,
  )
}

pub type StpaModel {
  StpaModel(
    losses: List(Loss),
    hazards: List(Hazard),
    controllers: List(Controller),
    control_actions: List(ControlAction),
    ucas: List(Uca),
    constraints: List(Constraint),
  )
}

fn band_for(ej: Float) -> String {
  case ej >=. 4.0 {
    True -> "P1"
    False ->
      case ej >=. 3.0 {
        True -> "P2"
        False -> "P3"
      }
  }
}

fn mk_uca(
  id: String,
  source: String,
  uca_type: UcaType,
  control_action: String,
  context: String,
  hazards: List(String),
  pms: Int,
  cif: Int,
  ej: Float,
) -> Uca {
  Uca(
    id: id,
    source: source,
    uca_type: uca_type,
    control_action: control_action,
    context: context,
    hazards: hazards,
    pms: pms,
    cif: cif,
    sif: pms * cif,
    ej: ej,
    band: band_for(ej),
  )
}

pub fn model() -> StpaModel {
  let losses = [
    Loss("L1", "Unsafe side effect executed from the TUI"),
    Loss("L2", "Operator misled by a false-green screen"),
    Loss("L3", "Loss of terminal (raw mode not restored)"),
    Loss("L4", "Unverified code integrated"),
  ]

  let hazards = [
    Hazard("H1", "TUI dispatches a mutating intent without confirmation", [
      "L1",
    ]),
    Hazard("H2", "Screen paints a passing state that audit did not verify", [
      "L2",
    ]),
    Hazard("H3", "Process exits or crashes while raw mode is active", ["L3"]),
    Hazard("H4", "Swarm integrates a slice that was not verified at HEAD", [
      "L4",
    ]),
  ]

  let controllers = [
    Controller("CTRL-TUI-APP", "Pure step controller"),
    Controller("CTRL-TUI-DRIVER", "Live terminal driver actor"),
    Controller("CTRL-TUI-ASPECTS", "Audit / aspects controller"),
    Controller("CTRL-SWARM-L0", "Swarm supervisor"),
    Controller("CTRL-SWARM-VERIFIER", "Swarm verifier"),
  ]

  let control_actions = [
    ControlAction("CA-emit_intent", "CTRL-TUI-APP", "emit_intent"),
    ControlAction(
      "CA-push_confirm_screen",
      "CTRL-TUI-APP",
      "push_confirm_screen",
    ),
    ControlAction("CA-paint_frame", "CTRL-TUI-DRIVER", "paint_frame"),
    ControlAction("CA-enter_raw", "CTRL-TUI-DRIVER", "enter_raw"),
    ControlAction("CA-restore_terminal", "CTRL-TUI-DRIVER", "restore_terminal"),
    ControlAction("CA-audit_screen", "CTRL-TUI-ASPECTS", "audit_screen"),
    ControlAction("CA-integrate_slice", "CTRL-SWARM-L0", "integrate_slice"),
    ControlAction("CA-verify_slice", "CTRL-SWARM-VERIFIER", "verify_slice"),
    ControlAction("CA-write_owned_file", "CTRL-SWARM-L0", "write_owned_file"),
  ]

  let ucas = [
    mk_uca(
      "UCA-01",
      "CTRL-TUI-APP",
      NotProvided,
      "CA-push_confirm_screen",
      "Mutating action selected without confirm screen shown",
      ["H1"],
      4,
      5,
      4.5,
    ),
    mk_uca(
      "UCA-02",
      "CTRL-SWARM-VERIFIER",
      NotProvided,
      "CA-verify_slice",
      "Slice integrated before any verification ran",
      ["H4"],
      4,
      5,
      4.6,
    ),
    mk_uca(
      "UCA-03",
      "CTRL-TUI-APP",
      ProvidedUnsafe,
      "CA-emit_intent",
      "Intent emitted for a widget outside the focus chain",
      ["H1"],
      3,
      4,
      3.4,
    ),
    mk_uca(
      "UCA-04",
      "CTRL-TUI-ASPECTS",
      ProvidedUnsafe,
      "CA-audit_screen",
      "Audit marks screen PASS while a fail-closed finding exists",
      ["H2"],
      4,
      4,
      4.0,
    ),
    mk_uca(
      "UCA-05",
      "CTRL-TUI-DRIVER",
      WrongTiming,
      "CA-enter_raw",
      "Raw mode entered before terminal size probe completes",
      ["H3"],
      2,
      3,
      2.4,
    ),
    mk_uca(
      "UCA-06",
      "CTRL-SWARM-L0",
      WrongTiming,
      "CA-integrate_slice",
      "Slice integrated before the verifier's PASS verdict is recorded",
      ["H4"],
      4,
      4,
      4.2,
    ),
    mk_uca(
      "UCA-07",
      "CTRL-TUI-DRIVER",
      StoppedTooSoon,
      "CA-restore_terminal",
      "Terminal restore aborted mid-sequence on signal",
      ["H3"],
      3,
      5,
      3.8,
    ),
    mk_uca(
      "UCA-08",
      "CTRL-SWARM-VERIFIER",
      StoppedTooSoon,
      "CA-verify_slice",
      "Verifier halts after compile check, skips test execution",
      ["H4", "H2"],
      3,
      4,
      3.3,
    ),
    mk_uca(
      "UCA-09",
      "CTRL-TUI-DRIVER",
      NotProvided,
      "CA-paint_frame",
      "Frame not repainted after a state change, stale screen shown",
      ["H2"],
      2,
      2,
      2.0,
    ),
    mk_uca(
      "UCA-10",
      "CTRL-SWARM-L0",
      ProvidedUnsafe,
      "CA-write_owned_file",
      "Worker writes a file outside its declared ownership boundary",
      ["H4", "H1"],
      3,
      4,
      3.6,
    ),
    mk_uca(
      "UCA-11",
      "CTRL-TUI-APP",
      WrongTiming,
      "CA-emit_intent",
      "Intent emitted twice for a single key event (double dispatch)",
      ["H1"],
      2,
      3,
      2.5,
    ),
  ]

  let constraints = [
    Constraint(
      "C-01",
      ["UCA-01"],
      "Every mutating control action must route through push_confirm_screen",
      HarnessCheck("aspects.audit fail-closed"),
    ),
    Constraint(
      "C-02",
      ["UCA-02", "UCA-06"],
      "No slice may be integrated without a recorded verifier PASS verdict",
      ProcessRule("integrate only after PASS verdict"),
    ),
    Constraint(
      "C-03",
      ["UCA-03"],
      "emit_intent is only valid for widgets present in focus_chain",
      HarnessCheck("focus_chain membership check"),
    ),
    Constraint(
      "C-04",
      ["UCA-04"],
      "audit_screen must report FAIL whenever any finding is fail-closed",
      HarnessCheck("aspects.admissible fail-closed"),
    ),
    Constraint(
      "C-05",
      ["UCA-05"],
      "enter_raw must not run until probe_size returns a resolved size",
      Production("live.probe_size ordering guard"),
    ),
    Constraint(
      "C-06",
      ["UCA-07"],
      "restore_terminal must complete under signal handlers before exit",
      Production("live driver signal-safe teardown"),
    ),
    Constraint(
      "C-07",
      ["UCA-08"],
      "verify_slice must run compile and test phases before PASS",
      HarnessCheck("verifier gleam build + gleam test gate"),
    ),
    Constraint(
      "C-08",
      ["UCA-10"],
      "write_owned_file must stay inside the worker's declared package path",
      HarnessCheck("verifier jj diff --summary ownership"),
    ),
    Constraint(
      "C-09",
      ["UCA-09"],
      "paint_frame must run after every accepted state transition",
      Production("app.step / frame_rendered invariant"),
    ),
    Constraint(
      "C-10",
      ["UCA-11"],
      "emit_intent must be idempotent per key event id",
      ProcessRule("dedupe intents by event sequence number"),
    ),
  ]

  StpaModel(
    losses: losses,
    hazards: hazards,
    controllers: controllers,
    control_actions: control_actions,
    ucas: ucas,
    constraints: constraints,
  )
}

fn unique_strings(xs: List(String)) -> Bool {
  list.length(xs) == list.length(list.unique(xs))
}

fn all_ids(m: StpaModel) -> List(String) {
  let a = list.map(m.losses, fn(x) { x.id })
  let b = list.map(m.hazards, fn(x) { x.id })
  let c = list.map(m.controllers, fn(x) { x.id })
  let d = list.map(m.control_actions, fn(x) { x.id })
  let e = list.map(m.ucas, fn(x) { x.id })
  let f = list.map(m.constraints, fn(x) { x.id })
  list.flatten([a, b, c, d, e, f])
}

fn has_types(ucas: List(Uca), types: List(UcaType)) -> Bool {
  list.all(types, fn(t) { list.any(ucas, fn(u) { u.uca_type == t }) })
}

pub fn validate(m: StpaModel) -> Result(Nil, String) {
  case unique_strings(all_ids(m)) {
    False -> Error("duplicate id across STPA model")
    True -> {
      let ca_names = list.map(m.control_actions, fn(c) { c.id })
      let hazard_ids = list.map(m.hazards, fn(h) { h.id })
      let uca_ids = list.map(m.ucas, fn(u) { u.id })

      let uca_refs_ok =
        list.all(m.ucas, fn(u) {
          list.contains(ca_names, u.control_action)
          && list.all(u.hazards, fn(h) { list.contains(hazard_ids, h) })
        })

      let sif_ok = list.all(m.ucas, fn(u) { u.sif == u.pms * u.cif })

      let constraint_refs_ok =
        list.all(m.constraints, fn(c) {
          list.all(c.uca_ids, fn(u) { list.contains(uca_ids, u) })
        })

      let types_ok =
        has_types(m.ucas, [
          NotProvided,
          ProvidedUnsafe,
          WrongTiming,
          StoppedTooSoon,
        ])

      case uca_refs_ok {
        False -> Error("uca references unknown control action or hazard")
        True ->
          case sif_ok {
            False -> Error("sif does not equal pms * cif for some uca")
            True ->
              case constraint_refs_ok {
                False -> Error("constraint references unknown uca id")
                True ->
                  case types_ok {
                    False -> Error("not all four uca types are present")
                    True -> Ok(Nil)
                  }
              }
          }
      }
    }
  }
}

pub fn ucas_by_type(m: StpaModel, t: UcaType) -> List(Uca) {
  list.filter(m.ucas, fn(u) { u.uca_type == t })
}

fn uca_type_label(t: UcaType) -> String {
  case t {
    NotProvided -> "NotProvided"
    ProvidedUnsafe -> "ProvidedUnsafe"
    WrongTiming -> "WrongTiming"
    StoppedTooSoon -> "StoppedTooSoon"
  }
}

fn enforcement_label(e: Enforcement) -> String {
  case e {
    HarnessCheck(s) -> "HarnessCheck: " <> s
    Production(s) -> "Production: " <> s
    ProcessRule(s) -> "ProcessRule: " <> s
  }
}

pub fn to_markdown(m: StpaModel) -> String {
  let losses_md =
    "## Losses\n"
    <> string.join(
      list.map(m.losses, fn(l) { "- " <> l.id <> ": " <> l.text }),
      "\n",
    )

  let hazards_md =
    "## Hazards\n"
    <> string.join(
      list.map(m.hazards, fn(h) {
        "- "
        <> h.id
        <> ": "
        <> h.text
        <> " (losses: "
        <> string.join(h.losses, ", ")
        <> ")"
      }),
      "\n",
    )

  let control_structure_md =
    "## Control structure\n"
    <> string.join(
      list.map(m.controllers, fn(c) { "- " <> c.id <> ": " <> c.name }),
      "\n",
    )
    <> "\n"
    <> string.join(
      list.map(m.control_actions, fn(ca) {
        "  - " <> ca.id <> " (" <> ca.controller <> "): " <> ca.name
      }),
      "\n",
    )

  let ucas_md =
    "## UCAs\n"
    <> "| id | source | type | action | pms | cif | sif | ej | band |\n"
    <> "|---|---|---|---|---|---|---|---|---|\n"
    <> string.join(
      list.map(m.ucas, fn(u) {
        "| "
        <> u.id
        <> " | "
        <> u.source
        <> " | "
        <> uca_type_label(u.uca_type)
        <> " | "
        <> u.control_action
        <> " | "
        <> int.to_string(u.pms)
        <> " | "
        <> int.to_string(u.cif)
        <> " | "
        <> int.to_string(u.sif)
        <> " | "
        <> float.to_string(u.ej)
        <> " | "
        <> u.band
        <> " |"
      }),
      "\n",
    )

  let constraints_md =
    "## Constraints\n"
    <> "| id | ucas | text | enforcement |\n"
    <> "|---|---|---|---|\n"
    <> string.join(
      list.map(m.constraints, fn(c) {
        "| "
        <> c.id
        <> " | "
        <> string.join(c.uca_ids, ", ")
        <> " | "
        <> c.text
        <> " | "
        <> enforcement_label(c.enforcement)
        <> " |"
      }),
      "\n",
    )

  losses_md
  <> "\n\n"
  <> hazards_md
  <> "\n\n"
  <> control_structure_md
  <> "\n\n"
  <> ucas_md
  <> "\n\n"
  <> constraints_md
}
