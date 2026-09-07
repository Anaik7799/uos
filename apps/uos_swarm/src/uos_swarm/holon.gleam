//// Holonic (fractal) model of the system: every unit is a holon, a whole to its parts and a
//// part to its whole, and every holon exposes the same interface at every level: an OODA loop,
//// a board address on the a2a plane, a 17-aspect audit subject, and a control/data/messaging/
//// intelligence/language plane assignment. The holarchy is validated (acyclic, level-monotonic)
//// and published on Zenoh under `uos/holon/**` so agents discover the structure they live in.
//// Sanskrit mirror: holon = aṃśa-pūrṇa (अंश-पूर्ण, "part-whole"); whole = pūrṇa (पूर्ण); part = aṃśa (अंश).
////
//// Each holon also carries a svadharma (स्वधर्म, "own duty") derived from its plane and level
//// (`dharma_of`), and each plane maps onto one of the seven Hindustani svara-s (`swara_of_plane`,
//// `swara_of`) — this module owns that plane<->svara pairing (rather than `uos_swarm/raga`)
//// because `raga.gleam` cannot import `holon` without forming a module import cycle that Gleam's
//// compiler rejects; `raga.gleam` mirrors the same pairing as plain strings for its own display
//// only. `base_rules` evaluates nine core base-layer invariants (B1..B9) over the holarchy,
//// including reciprocal parts<->whole membership (B2) that `validate` alone did not check.
//// STAMP: SC-TUI-HOLON-001, #fractal-l0..l9.

import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import uos_swarm/raga

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

/// The seven planes, in the same declaration order as `Plane` and as the seven svara-s.
pub const planes = [
  Control,
  Structure,
  Runtime,
  DataPlane,
  Messaging,
  Intelligence,
  Language,
]

/// Plane <-> svara pairing, in holon-plane order: Control=Sa, Structure=Re, Runtime=Ga,
/// DataPlane=Ma, Messaging=Pa, Intelligence=Dha, Language=Ni.
pub fn swara_of_plane(p: Plane) -> raga.Swara {
  case p {
    Control -> raga.Sa
    Structure -> raga.Re
    Runtime -> raga.Ga
    DataPlane -> raga.Ma
    Messaging -> raga.Pa
    Intelligence -> raga.Dha
    Language -> raga.Ni
  }
}

/// The svara sounded by this holon's plane.
pub fn swara_of(h: Holon) -> raga.Swara {
  swara_of_plane(h.plane)
}

/// This holon's svadharma (स्वधर्म, "own duty") in one sentence, derived from its plane and
/// level: what it must uphold, for whom, and through which svara it is heard.
pub fn dharma_of(h: Holon) -> String {
  "svadharma (स्वधर्म) of "
  <> h.id
  <> " at L"
  <> int.to_string(h.level)
  <> ": uphold "
  <> plane_label(h.plane)
  <> " for "
  <> option.unwrap(h.whole, "no whole — it is a root")
  <> ", sounding "
  <> raga.swara_label(swara_of(h))
  <> "."
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
      ["ontology", "fprime", "aspects", "jujutsu"],
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
      "jujutsu",
      "Jujutsu version control",
      "parivartana-tantra (परिवर्तन-तन्त्र)",
      2,
      Structure,
      Some("structure-plane"),
      [],
      "uos_swarm/jj",
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
      "uos_swarm_ffi.erl (ets)",
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

// ---------------------------------------------------------------------------
// Base-layer rules (B1..B9): the invariants every holon in the holarchy must satisfy, evaluated
// as `#(rule id, ok, detail)` so a caller can render or audit them individually. `validate`
// above is the structural gate (unique ids, parts<->whole on the parent side, no cycles) used by
// every caller that just needs `Result(Nil, String)`; `base_rules` is the full base-layer audit,
// always returning all nine results (never short-circuiting on the first failure) so a broken
// holarchy is fully diagnosed in one pass.
// ---------------------------------------------------------------------------

fn rule_b1(hs: List(Holon)) -> #(String, Bool, String) {
  case
    list.find(hs, fn(h) {
      case h.whole {
        Some(w) -> w == "" || w == h.id
        None -> False
      }
    })
  {
    Ok(h) -> #("B1", False, h.id <> " has a malformed whole (empty or self)")
    Error(_) -> #(
      "B1",
      True,
      int.to_string(list.length(hs))
        <> " holons each have exactly one whole or are a root ("
        <> int.to_string(list.length(roots(hs)))
        <> " root(s))",
    )
  }
}

/// Reciprocal membership: every part names this holon as its whole (already checked by
/// `validate`), *and* every holon whose whole is `w` is reciprocally listed in `w.parts` — the
/// direction `validate` did not check (Codex found this missing).
fn reciprocal_ok(hs: List(Holon), h: Holon) -> Bool {
  case h.whole {
    None -> True
    Some(w) ->
      case find(hs, w) {
        Error(_) -> False
        Ok(parent) -> list.contains(parent.parts, h.id)
      }
  }
}

fn rule_b2(hs: List(Holon)) -> #(String, Bool, String) {
  case list.find(hs, fn(h) { !reciprocal_ok(hs, h) }) {
    Error(_) -> #(
      "B2",
      True,
      "every child is reciprocally listed in its whole's parts ("
        <> int.to_string(list.length(hs))
        <> " holons)",
    )
    Ok(h) -> #(
      "B2",
      False,
      h.id
        <> " names "
        <> option.unwrap(h.whole, "?")
        <> " as whole but is missing from its parts list",
    )
  }
}

fn rule_b3(hs: List(Holon)) -> #(String, Bool, String) {
  case list.try_each(hs, fn(h) { acyclic(hs, h.id, 0) }) {
    Ok(_) -> #("B3", True, "holarchy is acyclic (bounded 16-hop walk)")
    Error(e) -> #("B3", False, e)
  }
}

/// Level never decreases from whole to part. Kept non-strict (`>=`, matching `validate`'s own
/// established invariant) rather than a strict `>`: `level` encodes the fractal layer (L0..L9),
/// and a few holons are deliberately peer-level with their whole because they share that layer
/// by design — `supervisor` is itself "L0 design authority" (same layer as `uos`), and `planes`
/// is the L1 grouping node whose seven plane-holons collectively *are* L1. A strict increase
/// would misreport these as broken data rather than intentional fractal-layer sharing.
fn rule_b4(hs: List(Holon)) -> #(String, Bool, String) {
  case
    list.find(hs, fn(h) {
      case h.whole {
        None -> False
        Some(w) ->
          case find(hs, w) {
            Ok(parent) -> h.level < parent.level
            Error(_) -> False
          }
      }
    })
  {
    Ok(h) -> #("B4", False, h.id <> " has a lower level than its whole")
    Error(_) -> #(
      "B4",
      True,
      "level never decreases from whole to part (peer-level organizational holons — "
        <> "uos/supervisor, planes/plane-instances — intentionally share a fractal layer)",
    )
  }
}

fn rule_b5(hs: List(Holon)) -> #(String, Bool, String) {
  case list.find(hs, fn(h) { h.sanskrit == "" }) {
    Error(_) -> #(
      "B5",
      True,
      "all "
        <> int.to_string(list.length(hs))
        <> " holons carry a Sanskrit name",
    )
    Ok(h) -> #("B5", False, h.id <> " has no Sanskrit name")
  }
}

fn reaches_root(
  hs: List(Holon),
  id: String,
  root_ids: List(String),
  depth: Int,
) -> Bool {
  case depth > 16 {
    True -> False
    False ->
      case list.contains(root_ids, id) {
        True -> True
        False ->
          case find(hs, id) {
            Ok(Holon(whole: Some(w), ..)) ->
              reaches_root(hs, w, root_ids, depth + 1)
            _ -> False
          }
      }
  }
}

fn rule_b6(hs: List(Holon)) -> #(String, Bool, String) {
  let root_ids = list.map(roots(hs), fn(h) { h.id })
  let missing_plane = list.find(planes, fn(p) { by_plane(hs, p) == [] })
  let unreachable =
    list.find(hs, fn(h) { !reaches_root(hs, h.id, root_ids, 0) })
  case missing_plane, unreachable {
    Ok(p), _ -> #("B6", False, plane_label(p) <> " has no holon")
    _, Ok(h) -> #(
      "B6",
      False,
      h.id <> " has no root path to " <> string.join(root_ids, ","),
    )
    Error(_), Error(_) -> #(
      "B6",
      True,
      "all 7 planes are populated and every holon has a root path to "
        <> string.join(root_ids, ","),
    )
  }
}

fn rule_b7(hs: List(Holon)) -> #(String, Bool, String) {
  let bad_agent =
    list.find(hs, fn(h) {
      case h.board_agent {
        Some(a) -> a == ""
        None -> False
      }
    })
  let bad_audit =
    list.find(hs, fn(h) {
      case h.audit_subject {
        Some(_) -> h.module == ""
        None -> False
      }
    })
  case bad_agent, bad_audit {
    Ok(h), _ -> #("B7", False, h.id <> " has an empty board_agent id")
    _, Ok(h) -> #("B7", False, h.id <> " has an audit_subject but no module")
    Error(_), Error(_) -> #(
      "B7",
      True,
      "every board_agent id is non-empty and every audit_subject has a module",
    )
  }
}

fn rule_b8() -> #(String, Bool, String) {
  let mapped = list.map(planes, swara_of_plane)
  case
    list.length(planes) == 7,
    list.length(list.unique(mapped)) == 7,
    list.length(raga.all_swaras()) == 7
  {
    True, True, True -> #(
      "B8",
      True,
      "7 planes map bijectively onto the 7 svara-s",
    )
    _, _, _ -> #(
      "B8",
      False,
      "plane -> svara mapping is not a 7-to-7 bijection",
    )
  }
}

const kebab_chars = [
  "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p",
  "q", "r", "s", "t", "u", "v", "w", "x", "y", "z", "0", "1", "2", "3", "4", "5",
  "6", "7", "8", "9", "-",
]

fn is_kebab(id: String) -> Bool {
  case id {
    "" -> False
    _ ->
      string.to_graphemes(id)
      |> list.all(fn(c) { list.contains(kebab_chars, c) })
  }
}

fn rule_b9(hs: List(Holon)) -> #(String, Bool, String) {
  let ids = list.map(hs, fn(h) { h.id })
  let dup = list.length(list.unique(ids)) != list.length(ids)
  case dup, list.find(hs, fn(h) { !is_kebab(h.id) }) {
    True, _ -> #("B9", False, "duplicate holon id")
    _, Ok(h) -> #("B9", False, h.id <> " is not lower-kebab-case")
    False, Error(_) -> #(
      "B9",
      True,
      "all "
        <> int.to_string(list.length(hs))
        <> " holon ids are unique and lower-kebab-case",
    )
  }
}

/// The nine core base-layer rules (B1..B9), each as `#(rule id, ok, detail)`. Always evaluates
/// all nine (never short-circuits) so a broken holarchy is fully diagnosed in one pass.
pub fn base_rules(hs: List(Holon)) -> List(#(String, Bool, String)) {
  [
    rule_b1(hs),
    rule_b2(hs),
    rule_b3(hs),
    rule_b4(hs),
    rule_b5(hs),
    rule_b6(hs),
    rule_b7(hs),
    rule_b8(),
    rule_b9(hs),
  ]
}

pub fn base_rules_markdown() -> String {
  let header = "| rule | ok | detail |\n|---|---|---|"
  let rows =
    list.map(base_rules(holarchy()), fn(r) {
      "| "
      <> r.0
      <> " | "
      <> case r.1 {
        True -> "PASS"
        False -> "FAIL"
      }
      <> " | "
      <> r.2
      <> " |"
    })
  string.join([header, ..rows], "\n")
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
    "| L | id | name | Sanskrit | plane | svara | whole | parts | module | audit subject |\n|---|---|---|---|---|---|---|---|---|---|"
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
      <> raga.swara_label(swara_of(h))
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
