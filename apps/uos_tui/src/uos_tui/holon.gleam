//// Holonic (fractal) model of the system: every unit is a holon, a whole to its parts and a
//// part to its whole, and every holon exposes the same interface at every level: an OODA loop,
//// a board address on the a2a plane, a 17-aspect audit subject, and a control/data/messaging/
//// intelligence/language plane assignment. The holarchy is validated (acyclic, level-monotonic)
//// and published on Zenoh under `uos/holon/**` so agents discover the structure they live in.
//// Sanskrit mirror: holon = aṃśa-pūrṇa (अंश-पूर्ण, "part-whole"); whole = pūrṇa (पूर्ण); part = aṃśa (अंश).
//// STAMP: SC-TUI-HOLON-001, #fractal-l0..l9.

import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub type Plane {
  Control
  Structure
  Runtime
  DataPlane
  Messaging
  Intelligence
  Language
}

pub fn plane_label(p: Plane) -> String {
  case p {
    Control -> "control · niyantraṇa (नियन्त्रण)"
    Structure -> "structure · saṃracanā (संरचना)"
    Runtime -> "runtime · pravartana (प्रवर्तन)"
    DataPlane -> "data plane · dattāṃśa (दत्तांश)"
    Messaging -> "messaging · sandeśa (सन्देश)"
    Intelligence -> "intelligence · buddhi (बुद्धि)"
    Language -> "language · bhāṣā (भाषा)"
  }
}

pub type Holon {
  Holon(
    id: String,
    name: String,
    sanskrit: String,
    level: Int,
    plane: Plane,
    whole: Option(String),
    parts: List(String),
    module: String,
    audit_subject: Option(String),
    board_agent: Option(String),
  )
}

pub fn address(h: Holon) -> String {
  "uos/holon/L" <> int.to_string(h.level) <> "/" <> h.id
}

/// The holarchy of this system (data, so it can be audited and shared).
pub fn holarchy() -> List(Holon) {
  [
    Holon(
      "uos",
      "Unified Operational System",
      "ekīkṛta-kārya-tantra (एकीकृत-कार्य-तन्त्र)",
      0,
      Control,
      None,
      ["supervisor", "planes"],
      "apps/uos_tui",
      None,
      None,
    ),
    Holon(
      "supervisor",
      "L0 design authority (Fable)",
      "adhiṣṭhātṛ (अधिष्ठातृ)",
      0,
      Control,
      Some("uos"),
      [],
      "uos_tui/coord (policy)",
      Some("coordination policy"),
      Some("L0-fable"),
    ),
    Holon(
      "planes",
      "Seven planes",
      "sapta-tala (सप्त-तल)",
      1,
      Structure,
      Some("uos"),
      [
        "control-plane",
        "structure-plane",
        "runtime-plane",
        "data-plane",
        "messaging-plane",
        "intelligence-plane",
        "language-plane",
      ],
      "uos_tui/holon",
      None,
      None,
    ),
    Holon(
      "control-plane",
      "Control plane",
      "niyantraṇa-tala (नियन्त्रण-तल)",
      1,
      Control,
      Some("planes"),
      ["coord", "stpa"],
      "uos_tui/coord",
      Some("coordination policy"),
      Some("uos-coord"),
    ),
    Holon(
      "structure-plane",
      "Structure plane",
      "saṃracanā-tala (संरचना-तल)",
      1,
      Structure,
      Some("planes"),
      ["ontology", "fprime", "aspects"],
      "uos_tui/ontology",
      Some("fractal ontology"),
      None,
    ),
    Holon(
      "runtime-plane",
      "Runtime plane",
      "pravartana-tala (प्रवर्तन-तल)",
      1,
      Runtime,
      Some("planes"),
      ["live", "headless", "app"],
      "uos_tui/live",
      Some("cockpit screen"),
      None,
    ),
    Holon(
      "data-plane",
      "Data plane",
      "dattāṃśa-tala (दत्तांश-तल)",
      1,
      DataPlane,
      Some("planes"),
      ["ledger", "ets", "zenoh-storage"],
      "uos_tui/board (ledger)",
      Some("message board"),
      None,
    ),
    Holon(
      "messaging-plane",
      "Messaging plane",
      "sandeśa-tala (सन्देश-तल)",
      1,
      Messaging,
      Some("planes"),
      ["board", "zenoh-router"],
      "uos_tui/board",
      Some("zenoh infra"),
      None,
    ),
    Holon(
      "intelligence-plane",
      "Intelligence plane",
      "buddhi-tala (बुद्धि-तल)",
      1,
      Intelligence,
      Some("planes"),
      ["manager", "system-audit"],
      "uos_tui/manager",
      Some("telemetry"),
      Some("uos-manager"),
    ),
    Holon(
      "language-plane",
      "Language plane",
      "bhāṣā-tala (भाषा-तल)",
      1,
      Language,
      Some("planes"),
      ["acl"],
      "uos_tui/acl",
      None,
      None,
    ),
    Holon(
      "coord",
      "Coordination & sync",
      "samanvaya (समन्वय)",
      2,
      Control,
      Some("control-plane"),
      ["leases", "heartbeats", "policy"],
      "uos_tui/coord",
      Some("coordination policy"),
      Some("uos-coord"),
    ),
    Holon(
      "stpa",
      "STPA & FMEA safety",
      "surakṣā (सुरक्षा)",
      2,
      Control,
      Some("control-plane"),
      [],
      "uos_tui/stpa",
      None,
      None,
    ),
    Holon(
      "ontology",
      "Fractal Textual ontology",
      "sattā-śāstra (सत्ता-शास्त्र)",
      2,
      Structure,
      Some("structure-plane"),
      [],
      "uos_tui/ontology",
      Some("fractal ontology"),
      None,
    ),
    Holon(
      "fprime",
      "F´ dictionaries",
      "śabda-kośa (शब्द-कोश)",
      2,
      Structure,
      Some("structure-plane"),
      [],
      "uos_tui/fprime",
      Some("F´ dictionary"),
      None,
    ),
    Holon(
      "aspects",
      "17-aspect audit",
      "saptadaśa-pakṣa (सप्तदश-पक्ष)",
      2,
      Structure,
      Some("structure-plane"),
      [],
      "uos_tui/aspects",
      None,
      None,
    ),
    Holon(
      "live",
      "OTP live driver",
      "jīva-cālaka (जीव-चालक)",
      2,
      Runtime,
      Some("runtime-plane"),
      [],
      "uos_tui/live",
      Some("cockpit screen"),
      None,
    ),
    Holon(
      "headless",
      "Headless pilot",
      "parīkṣaka (परीक्षक)",
      2,
      Runtime,
      Some("runtime-plane"),
      [],
      "uos_tui/headless",
      None,
      None,
    ),
    Holon(
      "app",
      "TEA application core",
      "mūla-yantra (मूल-यन्त्र)",
      2,
      Runtime,
      Some("runtime-plane"),
      ["widgets", "render"],
      "uos_tui/app",
      Some("cockpit screen"),
      None,
    ),
    Holon(
      "ledger",
      "Append-only JSONL ledger",
      "lekhā (लेखा)",
      2,
      DataPlane,
      Some("data-plane"),
      [],
      "uos_tui/board (jsonl)",
      None,
      None,
    ),
    Holon(
      "ets",
      "ETS live table",
      "smṛti (स्मृति)",
      2,
      DataPlane,
      Some("data-plane"),
      [],
      "uos_tui_ffi.erl (ets)",
      None,
      None,
    ),
    Holon(
      "zenoh-storage",
      "Zenoh memory storages",
      "megha-smṛti (मेघ-स्मृति)",
      2,
      DataPlane,
      Some("data-plane"),
      [],
      "ops/zenoh (storage_manager)",
      None,
      None,
    ),
    Holon(
      "board",
      "Message board",
      "sandeśa-phalaka (सन्देश-फलक)",
      2,
      Messaging,
      Some("messaging-plane"),
      [],
      "uos_tui/board",
      Some("message board"),
      None,
    ),
    Holon(
      "zenoh-router",
      "Zenoh router c3i-zenoh-router-1",
      "mārga-darśaka (मार्ग-दर्शक)",
      2,
      Messaging,
      Some("messaging-plane"),
      [],
      "ops/zenoh",
      Some("zenoh infra"),
      None,
    ),
    Holon(
      "manager",
      "F´ managing agent",
      "prabandhaka (प्रबन्धक)",
      2,
      Intelligence,
      Some("intelligence-plane"),
      ["ooda"],
      "uos_tui/manager",
      Some("telemetry"),
      Some("uos-manager"),
    ),
    Holon(
      "system-audit",
      "System-wide audit",
      "sarva-parīkṣā (सर्व-परीक्षा)",
      2,
      Intelligence,
      Some("intelligence-plane"),
      [],
      "uos_tui/system_audit",
      None,
      None,
    ),
    Holon(
      "acl",
      "Agent communication language",
      "sambhāṣā (सम्भाषा)",
      2,
      Language,
      Some("language-plane"),
      ["lexicon"],
      "uos_tui/acl",
      None,
      None,
    ),
    Holon(
      "widgets",
      "Widget catalog (17 families)",
      "aṅga (अङ्ग)",
      3,
      Runtime,
      Some("app"),
      [],
      "uos_tui/widget",
      None,
      None,
    ),
    Holon(
      "render",
      "Compositor",
      "citra-kāra (चित्र-कार)",
      3,
      Runtime,
      Some("app"),
      [],
      "uos_tui/render",
      None,
      None,
    ),
    Holon(
      "ooda",
      "Fast OODA controller",
      "cakra (चक्र)",
      3,
      Intelligence,
      Some("manager"),
      [],
      "uos_tui/ooda",
      None,
      None,
    ),
    Holon(
      "leases",
      "Fenced leases",
      "paṭṭā (पट्टा)",
      3,
      Control,
      Some("coord"),
      [],
      "uos_tui/coord (acquire/renew/release)",
      None,
      None,
    ),
    Holon(
      "heartbeats",
      "Freshness monitor",
      "spandana (स्पन्दन)",
      3,
      Control,
      Some("coord"),
      [],
      "uos_tui/coord (beat/stale)",
      None,
      None,
    ),
    Holon(
      "policy",
      "Hierarchical authority",
      "adhikāra (अधिकार)",
      3,
      Control,
      Some("coord"),
      [],
      "uos_tui/coord (authorize)",
      None,
      None,
    ),
    Holon(
      "lexicon",
      "Sanskrit/English lexicon",
      "kośa (कोश)",
      3,
      Language,
      Some("acl"),
      [],
      "uos_tui/acl (lexicon)",
      None,
      None,
    ),
  ]
}

pub fn find(hs: List(Holon), id: String) -> Result(Holon, Nil) {
  list.find(hs, fn(h) { h.id == id })
}

/// Structural validation: unique ids, every part exists and names this holon as its whole,
/// every whole exists, levels never decrease from whole to part, no cycles (bounded walk).
pub fn validate(hs: List(Holon)) -> Result(Nil, String) {
  let ids = list.map(hs, fn(h) { h.id })
  use _ <- result.try(case list.length(list.unique(ids)) == list.length(ids) {
    True -> Ok(Nil)
    False -> Error("duplicate holon id")
  })
  use _ <- result.try(
    list.try_each(hs, fn(h) {
      list.try_each(h.parts, fn(p) {
        case find(hs, p) {
          Error(_) -> Error(h.id <> " lists unknown part " <> p)
          Ok(part) ->
            case part.whole == Some(h.id), part.level >= h.level {
              True, True -> Ok(Nil)
              False, _ ->
                Error(p <> " does not name " <> h.id <> " as its whole")
              _, False ->
                Error(p <> " has a lower level than its whole " <> h.id)
            }
        }
      })
    }),
  )
  use _ <- result.try(
    list.try_each(hs, fn(h) {
      case h.whole {
        Some(w) ->
          case find(hs, w) {
            Ok(_) -> Ok(Nil)
            Error(_) -> Error(h.id <> " names unknown whole " <> w)
          }
        None -> Ok(Nil)
      }
    }),
  )
  list.try_each(hs, fn(h) { acyclic(hs, h.id, 0) })
}

fn acyclic(hs: List(Holon), id: String, depth: Int) -> Result(Nil, String) {
  case depth > 16 {
    True -> Error("cycle or excessive depth at " <> id)
    False ->
      case find(hs, id) {
        Ok(Holon(whole: Some(w), ..)) -> acyclic(hs, w, depth + 1)
        _ -> Ok(Nil)
      }
  }
}

pub fn roots(hs: List(Holon)) -> List(Holon) {
  list.filter(hs, fn(h) { h.whole == None })
}

pub fn depth(hs: List(Holon)) -> Int {
  list.fold(hs, 0, fn(acc, h) { int.max(acc, h.level) })
}

pub fn by_plane(hs: List(Holon), p: Plane) -> List(Holon) {
  list.filter(hs, fn(h) { h.plane == p })
}

/// ASCII tree (SC-DIAGRAM-001 fallback form).
pub fn to_tree(hs: List(Holon)) -> String {
  roots(hs)
  |> list.map(fn(r) { tree_lines(hs, r, "") })
  |> list.flatten
  |> string.join("\n")
}

fn tree_lines(hs: List(Holon), h: Holon, indent: String) -> List(String) {
  let line =
    indent
    <> "L"
    <> int.to_string(h.level)
    <> " "
    <> h.id
    <> " · "
    <> h.name
    <> " · "
    <> h.sanskrit
  [
    line,
    ..list.flat_map(h.parts, fn(p) {
      case find(hs, p) {
        Ok(child) -> tree_lines(hs, child, indent <> "  ")
        Error(_) -> [indent <> "  ? " <> p]
      }
    })
  ]
}

pub fn to_mermaid(hs: List(Holon)) -> String {
  let edges =
    list.flat_map(hs, fn(h) {
      list.map(h.parts, fn(p) {
        "  "
        <> string.replace(h.id, "-", "_")
        <> " --> "
        <> string.replace(p, "-", "_")
      })
    })
  string.join(["graph TD", ..edges], "\n")
}

pub fn to_json(hs: List(Holon)) -> Json {
  json.array(hs, fn(h) {
    json.object([
      #("id", json.string(h.id)),
      #("name", json.string(h.name)),
      #("sanskrit", json.string(h.sanskrit)),
      #("level", json.int(h.level)),
      #("plane", json.string(plane_label(h.plane))),
      #("whole", case h.whole {
        Some(w) -> json.string(w)
        None -> json.null()
      }),
      #("parts", json.array(h.parts, json.string)),
      #("module", json.string(h.module)),
      #("audit_subject", case h.audit_subject {
        Some(a) -> json.string(a)
        None -> json.null()
      }),
      #("board_agent", case h.board_agent {
        Some(a) -> json.string(a)
        None -> json.null()
      }),
      #("address", json.string(address(h))),
    ])
  })
}

pub fn to_markdown(hs: List(Holon)) -> String {
  let header =
    "| L | id | name | Sanskrit | plane | whole | parts | module | audit subject |\n|---|---|---|---|---|---|---|---|---|"
  let rows =
    list.map(hs, fn(h) {
      "| "
      <> int.to_string(h.level)
      <> " | "
      <> h.id
      <> " | "
      <> h.name
      <> " | "
      <> h.sanskrit
      <> " | "
      <> plane_label(h.plane)
      <> " | "
      <> option.unwrap(h.whole, "—")
      <> " | "
      <> string.join(h.parts, ", ")
      <> " | `"
      <> h.module
      <> "` | "
      <> option.unwrap(h.audit_subject, "—")
      <> " |"
    })
  string.join([header, ..rows], "\n")
  <> "\n\n```text\n"
  <> to_tree(hs)
  <> "\n```\n\n```mermaid\n"
  <> to_mermaid(hs)
  <> "\n```"
}
