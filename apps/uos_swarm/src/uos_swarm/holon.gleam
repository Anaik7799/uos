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
////
//// HOLARCHY-CENSUS (sa-plan uos/holonic-mapping/20260907-1505): the `Holon` record additionally
//// carries `kind` (what KIND of thing this is — process, subsystem, plane, component, ... per
//// design doc 3.5), `domain` (the C3I Zenoh domain-plane word, e.g. iam/secret/cog/eco/fed, or ""),
//// `process_class` ("" or systemd/otp-child/listener/worker/nif/container/periodic),
//// `status` (integrated/imported-not-wired/absent/superseded/barred/deferred/"" per SC-HOLON rows),
//// `uid` (13 lowercase hex chars, the first 13 hex chars of sha256(id), minted once per holon via
//// `uos_swarm_ffi:sha256_hex/1` — a direct FFI call rather than `uos_swarm/board.sha256_hex` to
//// avoid an import cycle: `board` imports `system_ontology`, which imports `holon`), and
//// `lifecycle` (Dormant/Awakening/Active/Stressed/Healing/Apoptotic, C3I's biological holon
//// lifecycle; defaults to Dormant — this module does not yet drive transitions). The `holon(...)`
//// constructor fills all six with sensible defaults (kind Component, domain "", process_class "",
//// status "", uid computed, lifecycle Dormant) so plain architectural holons stay compact; `with_*`
//// pipe helpers override individual fields for holons that need to say more (kind, domain,
//// process_class+status, audit_subject, board_agent). `address(h)` follows SC-HOLON-NAME-001:
//// `uos/holon/L<level>/<plane-slug>/<id>` (plane now appears in the address, not just level+id).
////
//// `holarchy()` now covers, beyond the 34 original architectural holons: 10 `Subsystem`-kind
//// holons (one per top-level UOS directory named in the design doc: apps/cepaf_gleam,
//// apps/indrajaal_gleam_web, apps/uos_swarm, apps/uos_tui, engines/hermes, engines/zigvm,
//// services/inference/max, tools, ops, native/nifs) and 113 `Process`-kind holons, one per row of
//// the daemon census (`generated/20260907-1320-uos-daemon-process-census-c3i-indrajaal-vs-uos.json`,
//// fixture copy `test/fixtures/20260907-1320-daemon-census.json`). B10 (census parity) checks every
//// census row names a Process holon; B13 is a placeholder for the wider universe census (Appendix B
//// of the design doc) and is not implemented here.
////
//// STAMP: SC-TUI-HOLON-001, SC-HOLON-NAME-001, #fractal-l0..l9.

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

pub type Kind {
  System
  PlaneKind
  Subsystem
  Component
  Process
  Artifact
  Record
  Document
  Rule
  Skill
  AgentRole
  Test
  Spec
  Plan
  Task
  Job
  Workflow
  Resource
  AgentSession
  Legacy
  Dataset
}

/// The C3I biological holon lifecycle (design doc 1.2, Appendix C "HOLON-LIFECYCLE"). For
/// census-derived (`Process`-kind) holons this is DERIVED from the census `status` string at
/// census time (`lifecycle_from_status`, wired through `with_process`) -- it is a one-shot
/// classification of what the census snapshot said, NOT an observed-live state; nothing in this
/// module polls a running process to keep it current. `transition` below is the only sanctioned
/// way to move a holon between lifecycle states once something (a future supervisor/monitor) does
/// track it live.
pub type Lifecycle {
  Dormant
  Awakening
  Active
  Stressed
  Healing
  Apoptotic
}

/// Events that drive `transition`. Names match the biological metaphor: a holon `Wake`s from
/// `Dormant`, becomes `Ready`, comes under `Stress`, is given a chance to `Heal`, and may
/// `Recover` back to `Active`; `Die` is the one event legal from every non-terminal state.
pub type LifecycleEvent {
  Wake
  Ready
  Stress
  Heal
  Recover
  Die
}

pub fn lifecycle_event_label(e: LifecycleEvent) -> String {
  case e {
    Wake -> "Wake"
    Ready -> "Ready"
    Stress -> "Stress"
    Heal -> "Heal"
    Recover -> "Recover"
    Die -> "Die"
  }
}

/// The sole legal lifecycle state machine (HOLON-LIFECYCLE). Legal edges:
///   Dormant + Wake -> Awakening
///   Awakening + Ready -> Active
///   Active + Stress -> Stressed
///   Stressed + Heal -> Healing
///   Healing + Recover -> Active
///   any state except Apoptotic + Die -> Apoptotic
/// `Apoptotic` is terminal: every event from it (including another `Die`) is an `Error`. Every
/// other `(state, event)` pair not listed above is also an `Error` naming both the state and the
/// event, so a caller always gets a precise diagnostic rather than a silently-ignored transition.
pub fn transition(
  from: Lifecycle,
  event: LifecycleEvent,
) -> Result(Lifecycle, String) {
  case from, event {
    Dormant, Wake -> Ok(Awakening)
    Awakening, Ready -> Ok(Active)
    Active, Stress -> Ok(Stressed)
    Stressed, Heal -> Ok(Healing)
    Healing, Recover -> Ok(Active)
    Dormant, Die -> Ok(Apoptotic)
    Awakening, Die -> Ok(Apoptotic)
    Active, Die -> Ok(Apoptotic)
    Stressed, Die -> Ok(Apoptotic)
    Healing, Die -> Ok(Apoptotic)
    Apoptotic, _ ->
      Error(
        "lifecycle "
        <> lifecycle_label(Apoptotic)
        <> " is terminal: "
        <> lifecycle_event_label(event)
        <> " has no legal transition",
      )
    _, _ ->
      Error(
        "illegal lifecycle transition: "
        <> lifecycle_label(from)
        <> " + "
        <> lifecycle_event_label(event),
      )
  }
}

/// Maps a daemon-census `status` string (SC-HOLON-CENSUS rows) onto its DERIVED lifecycle at
/// census time -- not an observed-live state (see the `Lifecycle` doc comment above). "running"
/// is Active; "stopped" and "absent" are Dormant (present in the census but not currently up);
/// "failed" is Stressed (up but unhealthy); "superseded" is Apoptotic (retired by design, not
/// coming back); anything else (including "integrated", "imported-not-wired", "barred",
/// "deferred", and "" -- none of which are literal census-observed run states) defaults to
/// Dormant, the safe/unknown default the `holon()` constructor already used before this field was
/// derived.
pub fn lifecycle_from_status(status: String) -> Lifecycle {
  case status {
    "running" -> Active
    "stopped" -> Dormant
    "absent" -> Dormant
    "failed" -> Stressed
    "superseded" -> Apoptotic
    _ -> Dormant
  }
}

pub type Vitals {
  Vitals(
    heartbeat_age_s: Option(Int),
    restarts: Int,
    last_transition: Option(String),
  )
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
    kind: Kind,
    domain: String,
    process_class: String,
    status: String,
    uid: String,
    lifecycle: Lifecycle,
    vitals: Option(Vitals),
  )
}

/// sha256(data), lowercase hex, via a direct FFI call to `uos_swarm_ffi:sha256_hex/1` (the same
/// primitive `uos_swarm/board.sha256_hex` wraps). `holon.gleam` cannot import `uos_swarm/board`
/// itself: `board` imports `system_ontology`, and `system_ontology` imports `holon` — importing
/// `board` from here would close that cycle, which Gleam's compiler rejects.
@external(erlang, "uos_swarm_ffi", "sha256_hex")
fn sha256_hex(data: String) -> String

/// 13 lowercase hex characters: the first 13 hex chars of sha256(id) (SC-HOLON-NAME-001 `uid`).
/// Deterministic and minted once per holon id (computed fresh each time `holarchy()` runs, from
/// the id string alone, so it is stable across runs).
fn uid_of(id: String) -> String {
  string.slice(sha256_hex(id), 0, 13)
}

/// Compact constructor for the common case: fills `audit_subject`/`board_agent` with `None`,
/// `kind` with `Component`, `domain`/`process_class`/`status` with `""`, `uid` computed from
/// `id`, `lifecycle` with `Dormant`, and `vitals` with `None`. Chain the `with_*` helpers below to
/// override any of those seven fields — keeps the 34 original architectural entries (and the
/// census-derived ones) compact instead of repeating ten unchanged trailing arguments on every
/// holon.
pub fn holon(
  id: String,
  name: String,
  sanskrit: String,
  level: Int,
  plane: Plane,
  whole: Option(String),
  parts: List(String),
  module: String,
) -> Holon {
  Holon(
    id: id,
    name: name,
    sanskrit: sanskrit,
    level: level,
    plane: plane,
    whole: whole,
    parts: parts,
    module: module,
    audit_subject: None,
    board_agent: None,
    kind: Component,
    domain: "",
    process_class: "",
    status: "",
    uid: uid_of(id),
    lifecycle: Dormant,
    vitals: None,
  )
}

pub fn with_kind(h: Holon, k: Kind) -> Holon {
  Holon(..h, kind: k)
}

pub fn with_domain(h: Holon, d: String) -> Holon {
  Holon(..h, domain: d)
}

/// Sets both `process_class` and `status` together (census rows always carry both), and derives
/// `lifecycle` from `status` via `lifecycle_from_status` (HOLON-LIFECYCLE) so census-derived
/// holons no longer all default to `Dormant` regardless of their recorded status. This lifecycle
/// is DERIVED from the census status at census time, not observed live -- see the `Lifecycle` doc
/// comment. Call `with_lifecycle` afterwards to override it explicitly if a caller has a better
/// (live-observed) value.
pub fn with_process(h: Holon, process_class: String, status: String) -> Holon {
  Holon(
    ..h,
    process_class: process_class,
    status: status,
    lifecycle: lifecycle_from_status(status),
  )
}

pub fn with_lifecycle(h: Holon, l: Lifecycle) -> Holon {
  Holon(..h, lifecycle: l)
}

pub fn with_vitals(h: Holon, v: Vitals) -> Holon {
  Holon(..h, vitals: Some(v))
}

pub fn with_audit_subject(h: Holon, a: String) -> Holon {
  Holon(..h, audit_subject: Some(a))
}

pub fn with_board_agent(h: Holon, a: String) -> Holon {
  Holon(..h, board_agent: Some(a))
}

/// Lowercase slug for the address (SC-HOLON-NAME-001): DataPlane -> "data", not "dataplane" or
/// "data-plane" -- matches design doc 3.1 ("data" is one of the seven listed plane words).
pub fn plane_slug(p: Plane) -> String {
  case p {
    Control -> "control"
    Structure -> "structure"
    Runtime -> "runtime"
    DataPlane -> "data"
    Messaging -> "messaging"
    Intelligence -> "intelligence"
    Language -> "language"
  }
}

/// SC-HOLON-NAME-001: `uos/holon/L<level>/<plane>/<id>` (plane now appears in the address).
pub fn address(h: Holon) -> String {
  "uos/holon/L"
  <> int.to_string(h.level)
  <> "/"
  <> plane_slug(h.plane)
  <> "/"
  <> h.id
}

/// The holarchy of this system (data, so it can be audited and shared).
///
/// LEVEL RULE for census-derived (`Process`-kind) and `Subsystem`-kind holons, applied
/// mechanically to every row of the daemon census, in this priority order (first match wins):
///   1. L6 if the census `class` field itself is tagged `6-container` (checked first, by the
///      row's own declared class, so a container row is never reclassified by a keyword that
///      happens to appear in its name/path/note -- e.g. a Dockerfile list mentioning
///      "kms-catalog", or a k8s manifest row mentioning "ferriskey").
///   2. L0 for constitutional/IAM/secret/clock-guard/governance rows (keyword match against the
///      row's own name/source_path/started_by ONLY -- never against `note`, which is comparison
///      commentary that frequently names OTHER unrelated UOS files/subsystems for context and
///      would otherwise cause false-positive L0 hits).
///   3. L1 for NIF (`class` contains `5-nif`) and native-kernel rows (Rust/Zig sources under a
///      `native/` tree).
///   4. L7 for federation/peer/tailnet rows (e.g. the Matrix chat federation server).
///   5. L5 for inference/cognitive workers: MAX, MCP, rule-engine, Rete, and Hermes evidence
///      rows (Hermes OCaml `dune` executables are treated as Cognitive-layer evidence workers).
///   6. L4 for the remaining systemd services, network listeners and OTP runtime children
///      (`class` starts `1-`, `2-`, or `3-`).
///   7. Anything not matching any of the above gets level 4 AND `domain = "unassigned"` --
///      never silently guessed. 6 of the 113 rows fall through to this case (ad hoc dev/test
///      scripts and the superseded Elixir/Phoenix `indrajaal_web`).
///
/// L0-CONSTITUTIONAL WHOLE (HOLON-LIFECYCLE, superseding the first cut of this comment): the L0
/// constitutional/IAM/secret/clock-guard/governance rows identified by rule 2 above do NOT sit
/// under their subsystem (`cepaf-gleam`, `uos-swarm`, `native-nifs`) as HOLARCHY-CENSUS first
/// wired them. The level-monotonic rule (B4: a part's level >= its whole's level) cascaded through
/// that wiring: an L0 process under `cepaf-gleam` forced `cepaf-gleam` itself down to L0, which
/// forced `control-plane` down to L0, which forced `planes` down to L0 -- three of the seven
/// architectural plane holons and the `planes` grouping node were pulled down to sit at the same
/// level as `uos`, even though nothing about "control plane" or "the seven planes" is itself L0
/// constitutional. This is fixed by giving those L0 rows their own L0 whole: `constitution`
/// (id "constitution", kind `Subsystem`, whole `uos`, module
/// `apps/cepaf_gleam/src/cepaf_gleam/fractal/l0_constitutional.gleam`), sibling to `supervisor`
/// and `planes` under `uos`. The 9 census rows that matched rule 2 (`c3i-iam-native-guard-service`,
/// `uos-clock-guard-service`, `iam-supervisor-gleam`, `vault-supervisor-gleam`,
/// `fractal-l0-constitutional-gleam`, `ferriskey-vendored-operator-rust`,
/// `rusty-vault-vendored-rust-source-of-rusty-vault-nif-so`, `ferriskey-nif`, `rusty-vault-nif`)
/// now name `constitution` as their whole (and are listed in `constitution.parts`) instead of
/// their former subsystem; `domain`, `process_class` and `status` are untouched by the move.
///
/// With those 9 rows gone, each formerly-affected subsystem's level is recomputed as
/// `min(2, min level of its remaining parts)` -- 2 is every `Subsystem` holon's natural level
/// (one below its plane), and the `min` keeps B4 honest if a subsystem still has a lower-level
/// (L1 NIF/native-kernel) child: `cepaf-gleam` and `uos-swarm` have no L0 or L1 children left, so
/// both return to L2; `native-nifs` still parents L1 native-kernel/NIF rows (`ferriskey-nif` and
/// `rusty-vault-nif` left, but `graphene-nif-loader`, `c3i-ocaml-nif`, etc. remain), so it settles
/// at L1, not L2. `tools` never had an L0 child (only L1 Rust rows), so it was already correctly
/// at L1 before this fix and is untouched. `control-plane`, `runtime-plane` and `messaging-plane`
/// -- whose minimum-level part was one of the now-restored subsystems -- return to their original
/// L1 (matching `structure-plane`/`data-plane`/`intelligence-plane`/`language-plane`, which never
/// picked up an L0/L1 child and were never pulled down); `planes` itself, whose minimum-level part
/// is now L1 across all seven plane holons, returns to L1. `uos` (L0, the root) and `supervisor`
/// (L0, peer-level design authority) are untouched -- both were already consistent with B4 once
/// their parts (`planes` at L1, `constitution` at L0) are at or above L0.
///
/// Level distribution after this fix (158 holons): L0 12, L1 24, L2 24, L3 7, L4 58, L5 26, L6 6,
/// L7 1.
pub fn holarchy() -> List(Holon) {
  [
    // -- Original architectural holons (uos root, planes, and their level-2/3 members) --
    holon(
      "uos",
      "Unified Operational System",
      "ekīkṛta-kārya-tantra (एकीकृत-कार्य-तन्त्र)",
      0,
      Control,
      None,
      ["supervisor", "planes", "constitution"],
      "apps/uos_tui",
    )
      |> with_kind(System),
    holon(
      "supervisor",
      "L0 design authority (Fable)",
      "adhiṣṭhātṛ (अधिष्ठातृ)",
      0,
      Control,
      Some("uos"),
      [],
      "uos_tui/coord (policy)",
    )
      |> with_kind(AgentRole)
      |> with_audit_subject("coordination policy")
      |> with_board_agent("L0-fable"),
    holon(
      "constitution",
      "L0 constitutional whole: IAM, secrets, clock guard, governance",
      "saṃvidhāna (संविधान)",
      0,
      Control,
      Some("uos"),
      [
        "c3i-iam-native-guard-service",
        "uos-clock-guard-service",
        "iam-supervisor-gleam",
        "vault-supervisor-gleam",
        "fractal-l0-constitutional-gleam",
        "ferriskey-vendored-operator-rust",
        "rusty-vault-vendored-rust-source-of-rusty-vault-nif-so",
        "ferriskey-nif",
        "rusty-vault-nif",
      ],
      "apps/cepaf_gleam/src/cepaf_gleam/fractal/l0_constitutional.gleam",
    )
      |> with_kind(Subsystem),
    holon(
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
    )
      |> with_kind(PlaneKind),
    holon(
      "control-plane",
      "Control plane",
      "niyantraṇa-tala (नियन्त्रण-तल)",
      1,
      Control,
      Some("planes"),
      ["coord", "stpa", "cepaf-gleam", "tools"],
      "uos_tui/coord",
    )
      |> with_kind(PlaneKind)
      |> with_audit_subject("coordination policy")
      |> with_board_agent("uos-coord"),
    holon(
      "structure-plane",
      "Structure plane",
      "saṃracanā-tala (संरचना-तल)",
      1,
      Structure,
      Some("planes"),
      ["ontology", "fprime", "aspects", "jujutsu"],
      "uos_tui/ontology",
    )
      |> with_kind(PlaneKind)
      |> with_audit_subject("fractal ontology"),
    holon(
      "runtime-plane",
      "Runtime plane",
      "pravartana-tala (प्रवर्तन-तल)",
      1,
      Runtime,
      Some("planes"),
      [
        "live",
        "headless",
        "app",
        "indrajaal-gleam-web",
        "uos-tui",
        "zigvm",
        "ops",
        "native-nifs",
      ],
      "uos_tui/live",
    )
      |> with_kind(PlaneKind)
      |> with_audit_subject("cockpit screen"),
    holon(
      "data-plane",
      "Data plane",
      "dattāṃśa-tala (दत्तांश-तल)",
      1,
      DataPlane,
      Some("planes"),
      ["ledger", "ets", "zenoh-storage"],
      "uos_tui/board (ledger)",
    )
      |> with_kind(PlaneKind)
      |> with_audit_subject("message board"),
    holon(
      "messaging-plane",
      "Messaging plane",
      "sandeśa-tala (सन्देश-तल)",
      1,
      Messaging,
      Some("planes"),
      ["board", "zenoh-router", "uos-swarm"],
      "uos_tui/board",
    )
      |> with_kind(PlaneKind)
      |> with_audit_subject("zenoh infra"),
    holon(
      "intelligence-plane",
      "Intelligence plane",
      "buddhi-tala (बुद्धि-तल)",
      1,
      Intelligence,
      Some("planes"),
      ["manager", "system-audit", "hermes", "inference-max"],
      "uos_tui/manager",
    )
      |> with_kind(PlaneKind)
      |> with_audit_subject("telemetry")
      |> with_board_agent("uos-manager"),
    holon(
      "language-plane",
      "Language plane",
      "bhāṣā-tala (भाषा-तल)",
      1,
      Language,
      Some("planes"),
      ["acl"],
      "uos_tui/acl",
    )
      |> with_kind(PlaneKind),
    holon(
      "coord",
      "Coordination & sync",
      "samanvaya (समन्वय)",
      2,
      Control,
      Some("control-plane"),
      ["leases", "heartbeats", "policy"],
      "uos_tui/coord",
    )
      |> with_audit_subject("coordination policy")
      |> with_board_agent("uos-coord"),
    holon(
      "stpa",
      "STPA & FMEA safety",
      "surakṣā (सुरक्षा)",
      2,
      Control,
      Some("control-plane"),
      [],
      "uos_tui/stpa",
    ),
    holon(
      "ontology",
      "Fractal Textual ontology",
      "sattā-śāstra (सत्ता-शास्त्र)",
      2,
      Structure,
      Some("structure-plane"),
      [],
      "uos_tui/ontology",
    )
      |> with_audit_subject("fractal ontology"),
    holon(
      "fprime",
      "F´ dictionaries",
      "śabda-kośa (शब्द-कोश)",
      2,
      Structure,
      Some("structure-plane"),
      [],
      "uos_tui/fprime",
    )
      |> with_audit_subject("F´ dictionary"),
    holon(
      "aspects",
      "17-aspect audit",
      "saptadaśa-pakṣa (सप्तदश-पक्ष)",
      2,
      Structure,
      Some("structure-plane"),
      [],
      "uos_tui/aspects",
    ),
    holon(
      "jujutsu",
      "Jujutsu version control",
      "parivartana-tantra (परिवर्तन-तन्त्र)",
      2,
      Structure,
      Some("structure-plane"),
      [],
      "uos_swarm/jj",
    ),
    holon(
      "live",
      "OTP live driver",
      "jīva-cālaka (जीव-चालक)",
      2,
      Runtime,
      Some("runtime-plane"),
      [],
      "uos_tui/live",
    )
      |> with_audit_subject("cockpit screen"),
    holon(
      "headless",
      "Headless pilot",
      "parīkṣaka (परीक्षक)",
      2,
      Runtime,
      Some("runtime-plane"),
      [],
      "uos_tui/headless",
    ),
    holon(
      "app",
      "TEA application core",
      "mūla-yantra (मूल-यन्त्र)",
      2,
      Runtime,
      Some("runtime-plane"),
      ["widgets", "render"],
      "uos_tui/app",
    )
      |> with_audit_subject("cockpit screen"),
    holon(
      "ledger",
      "Append-only JSONL ledger",
      "lekhā (लेखा)",
      2,
      DataPlane,
      Some("data-plane"),
      [],
      "uos_tui/board (jsonl)",
    ),
    holon(
      "ets",
      "ETS live table",
      "smṛti (स्मृति)",
      2,
      DataPlane,
      Some("data-plane"),
      [],
      "uos_swarm_ffi.erl (ets)",
    ),
    holon(
      "zenoh-storage",
      "Zenoh memory storages",
      "megha-smṛti (मेघ-स्मृति)",
      2,
      DataPlane,
      Some("data-plane"),
      [],
      "ops/zenoh (storage_manager)",
    ),
    holon(
      "board",
      "Message board",
      "sandeśa-phalaka (सन्देश-फलक)",
      2,
      Messaging,
      Some("messaging-plane"),
      [],
      "uos_tui/board",
    )
      |> with_audit_subject("message board"),
    holon(
      "zenoh-router",
      "Zenoh router c3i-zenoh-router-1",
      "mārga-darśaka (मार्ग-दर्शक)",
      2,
      Messaging,
      Some("messaging-plane"),
      [],
      "ops/zenoh",
    )
      |> with_audit_subject("zenoh infra"),
    holon(
      "manager",
      "F´ managing agent",
      "prabandhaka (प्रबन्धक)",
      2,
      Intelligence,
      Some("intelligence-plane"),
      ["ooda"],
      "uos_tui/manager",
    )
      |> with_audit_subject("telemetry")
      |> with_board_agent("uos-manager"),
    holon(
      "system-audit",
      "System-wide audit",
      "sarva-parīkṣā (सर्व-परीक्षा)",
      2,
      Intelligence,
      Some("intelligence-plane"),
      [],
      "uos_tui/system_audit",
    ),
    holon(
      "acl",
      "Agent communication language",
      "sambhāṣā (सम्भाषा)",
      2,
      Language,
      Some("language-plane"),
      ["lexicon"],
      "uos_tui/acl",
    ),
    holon(
      "widgets",
      "Widget catalog (17 families)",
      "aṅga (अङ्ग)",
      3,
      Runtime,
      Some("app"),
      [],
      "uos_tui/widget",
    ),
    holon(
      "render",
      "Compositor",
      "citra-kāra (चित्र-कार)",
      3,
      Runtime,
      Some("app"),
      [],
      "uos_tui/render",
    ),
    holon(
      "ooda",
      "Fast OODA controller",
      "cakra (चक्र)",
      3,
      Intelligence,
      Some("manager"),
      [],
      "uos_tui/ooda",
    ),
    holon(
      "leases",
      "Fenced leases",
      "paṭṭā (पट्टा)",
      3,
      Control,
      Some("coord"),
      [],
      "uos_tui/coord (acquire/renew/release)",
    ),
    holon(
      "heartbeats",
      "Freshness monitor",
      "spandana (स्पन्दन)",
      3,
      Control,
      Some("coord"),
      [],
      "uos_tui/coord (beat/stale)",
    ),
    holon(
      "policy",
      "Hierarchical authority",
      "adhikāra (अधिकार)",
      3,
      Control,
      Some("coord"),
      [],
      "uos_tui/coord (authorize)",
    ),
    holon(
      "lexicon",
      "Sanskrit/English lexicon",
      "kośa (कोश)",
      3,
      Language,
      Some("acl"),
      [],
      "uos_tui/acl (lexicon)",
    ),
    // -- Subsystem holons (one per top-level UOS directory the census maps daemons onto) --
    holon(
      "cepaf-gleam",
      "CEPAF Gleam control plane",
      "niyantrana-yantra (नियन्त्रण-यन्त्र)",
      2,
      Control,
      Some("control-plane"),
      [
        "c3i-gleam-server-service",
        "c3i-pi-runtime-service",
        "c3i-tls-proxy-service",
        "uos-sup-gleam-root-supervisor",
        "spec-child-cepaf-gleam-wisp",
        "spec-child-planning-worker",
        "cepaf-gleam-gleam-main-0",
        "cepaf-gleam-agents-cybernetic-executive-supervisor",
        "unified-verification-supervisor-gleam",
        "c3i-knowledge-supervisor-gleam",
        "pi-supervisor-gleam",
        "cpig-supervisor-gleam",
        "ha-supervisor-config-gleam",
        "prajna-circuit-breaker-gleam",
        "ha-lyapunov-proof-gleam",
        "ha-freshness-monitor-gleam",
        "cepaf-gleam-web-server-gleam-mist-http-listener",
        "cepaf-gleam-web-server-gleam-mist-https-listener",
        "ag-ui-sse-stream-ag-ui-events",
      ],
      "apps/cepaf_gleam",
    )
      |> with_kind(Subsystem),
    holon(
      "indrajaal-gleam-web",
      "Indrajaal Gleam web",
      "jala-yantra (जाल-यन्त्र)",
      2,
      Runtime,
      Some("runtime-plane"),
      [
        "c3i-sa-plan-http-service",
        "spec-child-indrajaal-web",
        "apps-indrajaal-gleam-library",
        "indrajaal-gleam-web-mist-http-listener-4100",
        "indrajaal-web-elixir-phoenix-legacy",
      ],
      "apps/indrajaal_gleam_web",
    )
      |> with_kind(Subsystem),
    holon(
      "uos-swarm",
      "UOS swarm package",
      "jhunda (झुण्ड)",
      2,
      Messaging,
      Some("messaging-plane"),
      [
        "spec-child-max-isolated-worker",
        "max-worker-py",
        "swarm-dune-module",
      ],
      "apps/uos_swarm",
    )
      |> with_kind(Subsystem),
    holon(
      "uos-tui",
      "UOS TUI cockpit",
      "calaka-patala (चालक-पटल)",
      2,
      Runtime,
      Some("runtime-plane"),
      ["spec-child-holon-swarm-mesh", "run-tui-py"],
      "apps/uos_tui",
    )
      |> with_kind(Subsystem),
    holon(
      "hermes",
      "Hermes OCaml evidence engine",
      "pramana-yantra (प्रमाण-यन्त्र)",
      2,
      Intelligence,
      Some("intelligence-plane"),
      [
        "c3i-rete-autofix-service",
        "c3i-sa-plan-cortex-service",
        "spec-child-hermes-oracle-supervisor",
        "spec-child-rete-ul-engine",
        "mcp-stdio-servers-zigvm-harness-mcp-hermes-ops-mcp",
        "mcp-timestamp-sync-rust",
        "hermes-harness-incl-hermes-rete-ml-compiled-zenoh-c-stub",
        "hermes-dependability-dune-dependability-clock-ml",
        "tailscale-monitor-dune-exe",
        "hermes-server-dune-exe",
        "hermes-ops-dune-exe-ops-main-exe-mcp",
        "hermes-mirage-dune-exe",
        "hermes-vision-dune-exe",
        "hermes-wiki-tools-frontend-dune-exe",
        "hermes-ops-dashboard-dune-exe",
        "hermes-zellij-dune-exe",
        "hermes-sysml-dune-exe",
        "hermes-tooling-modules-toolchain-nix-vcs-fpp-authority-dune-graph-harness-stubber-fetch-cowboy-sa-plan-test",
        "tools-sa-plan-ocaml-sa-plan-main-exe",
      ],
      "engines/hermes",
    )
      |> with_kind(Subsystem),
    holon(
      "zigvm",
      "ZigVM deterministic runtime",
      "niyata-yantra (नियत-यन्त्र)",
      1,
      Runtime,
      Some("runtime-plane"),
      ["spec-child-zigvm-port-manager", "indrajaal-ark-zig-zig"],
      "engines/zigvm",
    )
      |> with_kind(Subsystem),
    holon(
      "inference-max",
      "Modular MAX inference tier",
      "anumana-yantra (अनुमान-यन्त्र)",
      2,
      Intelligence,
      Some("intelligence-plane"),
      ["c3i-sa-plan-inference-service", "max-kernel-mojo"],
      "services/inference/max",
    )
      |> with_kind(Subsystem),
    holon(
      "tools",
      "UOS CLI tooling",
      "upakarana (उपकरण)",
      1,
      Control,
      Some("control-plane"),
      [
        "c3i-docs-server-service",
        "c3i-health-publisher-service",
        "c3i-history-compactor-service",
        "c3i-muda-prune-service",
        "c3i-ops-status-service",
        "c3i-pressure-publisher-service",
        "c3i-robustness-gate-service",
        "c3i-sa-plan-default-scheduler-service",
        "c3i-slo-guard-service",
        "c3i-sutra-service",
        "c3i-symbiosis-monitor-service",
        "sa-plan-tls-service-deploy-packaging",
        "scripts-gleam-service-timer-template",
        "openclaw-auth-monitor-service",
        "openclaw-auth-monitor-timer",
        "spec-child-indrajaal-holon-runtime",
        "spec-child-mcp-unified-gateway",
        "spec-child-lease-fencing-monitor",
        "services-stan-worker-stub",
        "services-rule-engine-worker-stub",
        "services-solver-worker-stub",
        "zenoh-router-rest-8000-alt",
        "sa-plan-http-dashboard-4200",
        "sa-plan-tls-proxy-8443-8088",
        "sa-plan-inference-uds-socket",
        "e2e-ui-tester-py",
        "generate-ui-py",
        "fix-gleam-warnings-py",
        "exhaustive-parity-audit-py",
        "mcp-c3i-server-rust",
        "indrajaal-ark-rust",
        "indrajaal-env-checker-rust",
        "containers-dockerfile-precompiled",
        "containers-signoz-docker-compose-observability-stack",
        "sub-projects-c3i-dockerfile-cluster-db-sil4-db-sil4-app-sil4-obs-cortex-kms-catalog-cepaf-bridge-mojo-fix-sopv51-app-sopv51-app-hardened-sopv51-base",
        "ferriskey-vendored-containers-k8s-manifests",
        "openclaw-containers-k8s-manifest",
      ],
      "tools",
    )
      |> with_kind(Subsystem),
    holon(
      "ops",
      "UOS operational units",
      "karma-tantra (कर्म-तन्त्र)",
      2,
      Runtime,
      Some("runtime-plane"),
      [
        "c3i-target",
        "c3i-zenoh-router-service-alt-8000",
        "c3i-zenoh-router-1-service",
        "zenoh-router-tcp-7447-rest-8080",
        "k8s-lab-rust-cli-render-kube-apply-spec",
      ],
      "ops",
    )
      |> with_kind(Subsystem),
    holon(
      "native-nifs",
      "Native bounded NIF kernels",
      "mula-bija (मूल-बीज)",
      1,
      Runtime,
      Some("runtime-plane"),
      [
        "native-wireframe-renderer-rust",
        "native-planning-daemon-rust",
        "native-ignition-daemon-rust",
        "graphene-nif-rust-crate-lib-cepaf-gleam-native-graphene-nif",
        "graphite-editor-bevy-based-rust-desktop-editor",
        "c3i-ocaml-nif",
        "rule-engine-nif",
        "planning-nif",
        "c3i-nif",
        "graphene-nif-loader",
      ],
      "native/nifs",
    )
      |> with_kind(Subsystem),

    // -- Census-derived Process holons (one per row of the 113-row daemon census) --
    holon(
      "c3i-target",
      "c3i.target",
      "prakriya (प्रक्रिया)",
      4,
      Runtime,
      Some("ops"),
      [],
      "~/.config/systemd/user/c3i.target (installed; authoritative def not found as a tracked file in /home/an/dev/ver/c3i, host-local unit)",
    )
      |> with_kind(Process)
      |> with_process("systemd", "imported-not-wired")
      |> with_domain("sync"),
    holon(
      "c3i-docs-server-service",
      "c3i-docs-server.service",
      "prakriya (प्रक्रिया)",
      4,
      Runtime,
      Some("tools"),
      [],
      "~/.config/systemd/user/c3i-docs-server.service",
    )
      |> with_kind(Process)
      |> with_process("systemd", "absent"),
    holon(
      "c3i-gleam-server-service",
      "c3i-gleam-server.service",
      "prakriya (प्रक्रिया)",
      4,
      Runtime,
      Some("cepaf-gleam"),
      [],
      "/home/an/NAS-setup/c3i/sa-gleam-start",
    )
      |> with_kind(Process)
      |> with_process("systemd", "imported-not-wired"),
    holon(
      "c3i-health-publisher-service",
      "c3i-health-publisher.service",
      "prakriya (प्रक्रिया)",
      4,
      Runtime,
      Some("tools"),
      [],
      "gleam run -m scripts/sysd/health_publish",
    )
      |> with_kind(Process)
      |> with_process("systemd", "absent"),
    holon(
      "c3i-history-compactor-service",
      "c3i-history-compactor.service",
      "prakriya (प्रक्रिया)",
      4,
      Runtime,
      Some("tools"),
      [],
      "gleam run -m scripts/pass10/p10_history_compactor",
    )
      |> with_kind(Process)
      |> with_process("systemd", "absent"),
    holon(
      "c3i-iam-native-guard-service",
      "c3i-iam-native-guard.service",
      "prakriya (प्रक्रिया)",
      0,
      Runtime,
      Some("constitution"),
      [],
      "/home/an/NAS-setup/c3i/scripts/systemd/c3i-user/iam-native-guard.sh",
    )
      |> with_kind(Process)
      |> with_process("systemd", "imported-not-wired")
      |> with_domain("iam"),
    holon(
      "c3i-muda-prune-service",
      "c3i-muda-prune.service",
      "prakriya (प्रक्रिया)",
      4,
      Runtime,
      Some("tools"),
      [],
      "gleam run -m scripts/sysd/muda_prune",
    )
      |> with_kind(Process)
      |> with_process("systemd", "absent"),
    holon(
      "c3i-ops-status-service",
      "c3i-ops-status.service",
      "prakriya (प्रक्रिया)",
      4,
      Runtime,
      Some("tools"),
      [],
      "gleam run -m scripts/pass10/p10_ops_status",
    )
      |> with_kind(Process)
      |> with_process("systemd", "absent"),
    holon(
      "c3i-pi-runtime-service",
      "c3i-pi-runtime.service",
      "prakriya (प्रक्रिया)",
      4,
      Runtime,
      Some("cepaf-gleam"),
      [],
      "node packages/coding-agent/dist/cli.js --provider google --mode rpc (Pi-mono)",
    )
      |> with_kind(Process)
      |> with_process("systemd", "imported-not-wired"),
    holon(
      "c3i-pressure-publisher-service",
      "c3i-pressure-publisher.service",
      "prakriya (प्रक्रिया)",
      4,
      Runtime,
      Some("tools"),
      [],
      "gleam run -m scripts/sysd/pressure_publish",
    )
      |> with_kind(Process)
      |> with_process("systemd", "absent"),
    holon(
      "c3i-rete-autofix-service",
      "c3i-rete-autofix.service",
      "prakriya (प्रक्रिया)",
      5,
      Runtime,
      Some("hermes"),
      [],
      "gleam run -m scripts/pass10/p10_rete_autofix",
    )
      |> with_kind(Process)
      |> with_process("systemd", "absent")
      |> with_domain("cog"),
    holon(
      "c3i-robustness-gate-service",
      "c3i-robustness-gate.service",
      "prakriya (प्रक्रिया)",
      4,
      Runtime,
      Some("tools"),
      [],
      "gleam run -m scripts/pass10/p10_robustness_gate",
    )
      |> with_kind(Process)
      |> with_process("systemd", "absent"),
    holon(
      "c3i-sa-plan-cortex-service",
      "c3i-sa-plan-cortex.service",
      "prakriya (प्रक्रिया)",
      4,
      Runtime,
      Some("hermes"),
      [],
      "/home/an/NAS-setup/c3i/sa-plan daemon",
    )
      |> with_kind(Process)
      |> with_process("systemd", "superseded"),
    holon(
      "c3i-sa-plan-default-scheduler-service",
      "c3i-sa-plan-default-scheduler.service",
      "prakriya (प्रक्रिया)",
      4,
      Runtime,
      Some("tools"),
      [],
      "sa-plan scheduler-run --queue default --limit 8 --interval 2",
    )
      |> with_kind(Process)
      |> with_process("systemd", "absent"),
    holon(
      "c3i-sa-plan-http-service",
      "c3i-sa-plan-http.service",
      "prakriya (प्रक्रिया)",
      4,
      Runtime,
      Some("indrajaal-gleam-web"),
      [],
      "sa-plan serve --port 4200",
    )
      |> with_kind(Process)
      |> with_process("systemd", "superseded"),
    holon(
      "c3i-sa-plan-inference-service",
      "c3i-sa-plan-inference.service",
      "prakriya (प्रक्रिया)",
      5,
      Runtime,
      Some("inference-max"),
      [],
      "sa-plan inference-serve --sock %t/c3i/inference.sock",
    )
      |> with_kind(Process)
      |> with_process("systemd", "absent")
      |> with_domain("cog"),
    holon(
      "c3i-slo-guard-service",
      "c3i-slo-guard.service",
      "prakriya (प्रक्रिया)",
      4,
      Runtime,
      Some("tools"),
      [],
      "gleam run -m scripts/pass10/p10_slo_guard",
    )
      |> with_kind(Process)
      |> with_process("systemd", "absent"),
    holon(
      "c3i-sutra-service",
      "c3i-sutra.service",
      "prakriya (प्रक्रिया)",
      7,
      Runtime,
      Some("tools"),
      [],
      "gleam run (Sutra Matrix/federation server, sub-projects/sutra)",
    )
      |> with_kind(Process)
      |> with_process("systemd", "absent")
      |> with_domain("fed"),
    holon(
      "c3i-symbiosis-monitor-service",
      "c3i-symbiosis-monitor.service",
      "prakriya (प्रक्रिया)",
      4,
      Runtime,
      Some("tools"),
      [],
      "gleam run -m scripts/pass9/p9_symbiosis_monitor",
    )
      |> with_kind(Process)
      |> with_process("systemd", "absent"),
    holon(
      "c3i-tls-proxy-service",
      "c3i-tls-proxy.service",
      "prakriya (प्रक्रिया)",
      4,
      Runtime,
      Some("cepaf-gleam"),
      [],
      "sa-plan tls serve --https-port 8443 --http-port 8088",
    )
      |> with_kind(Process)
      |> with_process("systemd", "absent"),
    holon(
      "c3i-zenoh-router-service-alt-8000",
      "c3i-zenoh-router.service (alt/:8000)",
      "prakriya (प्रक्रिया)",
      4,
      Runtime,
      Some("ops"),
      [],
      "~/.config/systemd/user/c3i-zenoh-router.service; podman run ... --rest-http-port 8000",
    )
      |> with_kind(Process)
      |> with_process("systemd", "superseded"),
    holon(
      "c3i-zenoh-router-1-service",
      "c3i-zenoh-router-1.service",
      "prakriya (प्रक्रिया)",
      4,
      Runtime,
      Some("ops"),
      [],
      "~/.config/systemd/user/c3i-zenoh-router-1.service; podman start c3i-zenoh-router-1 (docker.io/eclipse/zenoh)",
    )
      |> with_kind(Process)
      |> with_process("systemd", "integrated"),
    holon(
      "sa-plan-tls-service-deploy-packaging",
      "sa-plan-tls.service (deploy packaging)",
      "prakriya (प्रक्रिया)",
      4,
      Runtime,
      Some("tools"),
      [],
      "/home/an/dev/ver/c3i/sub-projects/c3i/deploy/systemd/sa-plan-tls.service",
    )
      |> with_kind(Process)
      |> with_process("systemd", "absent"),
    holon(
      "scripts-gleam-service-timer-template",
      "scripts-gleam@.service / .timer (template)",
      "prakriya (प्रक्रिया)",
      4,
      Runtime,
      Some("tools"),
      [],
      "/home/an/dev/ver/c3i/sub-projects/scripts-gleam/deploy/systemd/scripts-gleam@.{service,timer}",
    )
      |> with_kind(Process)
      |> with_process("systemd", "absent"),
    holon(
      "openclaw-auth-monitor-service",
      "openclaw-auth-monitor.service",
      "prakriya (प्रक्रिया)",
      4,
      Runtime,
      Some("tools"),
      [],
      "/home/an/dev/ver/c3i/sub-projects/openclaw/scripts/systemd/openclaw-auth-monitor.service",
    )
      |> with_kind(Process)
      |> with_process("systemd", "absent"),
    holon(
      "openclaw-auth-monitor-timer",
      "openclaw-auth-monitor.timer",
      "prakriya (प्रक्रिया)",
      4,
      Runtime,
      Some("tools"),
      [],
      "same dir, .timer",
    )
      |> with_kind(Process)
      |> with_process("systemd", "absent"),
    holon(
      "uos-clock-guard-service",
      "uos-clock-guard@.service",
      "prakriya (प्रक्रिया)",
      0,
      Runtime,
      Some("constitution"),
      [],
      "~/.config/systemd/user/uos-clock-guard@.service; UOS copy at ops/observability/20260907-0941-uos-clock-guard@.service",
    )
      |> with_kind(Process)
      |> with_process("systemd", "integrated")
      |> with_domain("sync"),
    holon(
      "uos-sup-gleam-root-supervisor",
      "uos_sup.gleam root supervisor",
      "prakriya (प्रक्रिया)",
      4,
      Runtime,
      Some("cepaf-gleam"),
      [],
      "apps/cepaf_gleam/src/cepaf_gleam/uos_sup.gleam",
    )
      |> with_kind(Process)
      |> with_process("otp-child", "imported-not-wired"),
    holon(
      "spec-child-cepaf-gleam-wisp",
      "spec-child: cepaf_gleam_wisp",
      "prakriya (प्रक्रिया)",
      4,
      Runtime,
      Some("cepaf-gleam"),
      [],
      "uos_sup.gleam AppsDomain child (string only)",
    )
      |> with_kind(Process)
      |> with_process("otp-child", "absent"),
    holon(
      "spec-child-indrajaal-holon-runtime",
      "spec-child: indrajaal_holon_runtime",
      "prakriya (प्रक्रिया)",
      4,
      Runtime,
      Some("tools"),
      [],
      "uos_sup.gleam AppsDomain child (string only)",
    )
      |> with_kind(Process)
      |> with_process("otp-child", "absent"),
    holon(
      "spec-child-indrajaal-web",
      "spec-child: indrajaal_web",
      "prakriya (प्रक्रिया)",
      4,
      Runtime,
      Some("indrajaal-gleam-web"),
      [],
      "uos_sup.gleam AppsDomain child (string only)",
    )
      |> with_kind(Process)
      |> with_process("otp-child", "imported-not-wired"),
    holon(
      "spec-child-zigvm-port-manager",
      "spec-child: zigvm_port_manager",
      "prakriya (प्रक्रिया)",
      4,
      Runtime,
      Some("zigvm"),
      [],
      "uos_sup.gleam EnginesDomain child (string only)",
    )
      |> with_kind(Process)
      |> with_process("otp-child", "absent"),
    holon(
      "spec-child-hermes-oracle-supervisor",
      "spec-child: hermes_oracle_supervisor",
      "prakriya (प्रक्रिया)",
      5,
      Runtime,
      Some("hermes"),
      [],
      "uos_sup.gleam EnginesDomain child (string only)",
    )
      |> with_kind(Process)
      |> with_process("otp-child", "absent")
      |> with_domain("cog"),
    holon(
      "spec-child-max-isolated-worker",
      "spec-child: max_isolated_worker",
      "prakriya (प्रक्रिया)",
      4,
      Runtime,
      Some("uos-swarm"),
      [],
      "uos_sup.gleam ServicesDomain child (string only)",
    )
      |> with_kind(Process)
      |> with_process("otp-child", "imported-not-wired"),
    holon(
      "spec-child-mcp-unified-gateway",
      "spec-child: mcp_unified_gateway",
      "prakriya (प्रक्रिया)",
      5,
      Runtime,
      Some("tools"),
      [],
      "uos_sup.gleam ServicesDomain child (string only)",
    )
      |> with_kind(Process)
      |> with_process("otp-child", "absent")
      |> with_domain("cog"),
    holon(
      "spec-child-planning-worker",
      "spec-child: planning_worker",
      "prakriya (प्रक्रिया)",
      4,
      Runtime,
      Some("cepaf-gleam"),
      [],
      "uos_sup.gleam ServicesDomain child (string only)",
    )
      |> with_kind(Process)
      |> with_process("otp-child", "absent"),
    holon(
      "spec-child-holon-swarm-mesh",
      "spec-child: holon_swarm_mesh",
      "prakriya (प्रक्रिया)",
      4,
      Runtime,
      Some("uos-tui"),
      [],
      "uos_sup.gleam IntelligenceDomain child (string only)",
    )
      |> with_kind(Process)
      |> with_process("otp-child", "absent"),
    holon(
      "spec-child-lease-fencing-monitor",
      "spec-child: lease_fencing_monitor",
      "prakriya (प्रक्रिया)",
      4,
      Runtime,
      Some("tools"),
      [],
      "uos_sup.gleam IntelligenceDomain child (string only)",
    )
      |> with_kind(Process)
      |> with_process("otp-child", "absent"),
    holon(
      "spec-child-rete-ul-engine",
      "spec-child: rete_ul_engine",
      "prakriya (प्रक्रिया)",
      5,
      Runtime,
      Some("hermes"),
      [],
      "uos_sup.gleam IntelligenceDomain child (string only)",
    )
      |> with_kind(Process)
      |> with_process("otp-child", "imported-not-wired")
      |> with_domain("cog"),
    holon(
      "cepaf-gleam-gleam-main-0",
      "cepaf_gleam.gleam main/0",
      "prakriya (प्रक्रिया)",
      4,
      Runtime,
      Some("cepaf-gleam"),
      [],
      "apps/cepaf_gleam/src/cepaf_gleam.gleam",
    )
      |> with_kind(Process)
      |> with_process("otp-child", "integrated")
      |> with_domain("otel"),
    holon(
      "cepaf-gleam-agents-cybernetic-executive-supervisor",
      "cepaf_gleam/agents/cybernetic executive supervisor",
      "prakriya (प्रक्रिया)",
      4,
      Runtime,
      Some("cepaf-gleam"),
      [],
      "apps/cepaf_gleam/src/cepaf_gleam/agents/cybernetic.gleam",
    )
      |> with_kind(Process)
      |> with_process("otp-child", "integrated"),
    holon(
      "unified-verification-supervisor-gleam",
      "unified_verification_supervisor.gleam",
      "prakriya (प्रक्रिया)",
      4,
      Runtime,
      Some("cepaf-gleam"),
      [],
      "apps/cepaf_gleam/src/cepaf_gleam/verification/unified_verification_supervisor.gleam",
    )
      |> with_kind(Process)
      |> with_process("otp-child", "integrated"),
    holon(
      "c3i-knowledge-supervisor-gleam",
      "c3i_knowledge_supervisor.gleam",
      "prakriya (प्रक्रिया)",
      4,
      Runtime,
      Some("cepaf-gleam"),
      [],
      "apps/cepaf_gleam/src/cepaf_gleam/knowledge/c3i_knowledge_supervisor.gleam",
    )
      |> with_kind(Process)
      |> with_process("otp-child", "integrated"),
    holon(
      "pi-supervisor-gleam",
      "pi_supervisor.gleam",
      "prakriya (प्रक्रिया)",
      4,
      Runtime,
      Some("cepaf-gleam"),
      [],
      "apps/cepaf_gleam/src/cepaf_gleam/bridge/pi_supervisor.gleam",
    )
      |> with_kind(Process)
      |> with_process("otp-child", "imported-not-wired"),
    holon(
      "cpig-supervisor-gleam",
      "cpig_supervisor.gleam",
      "prakriya (प्रक्रिया)",
      4,
      Runtime,
      Some("cepaf-gleam"),
      [],
      "apps/cepaf_gleam/src/cepaf_gleam/actors/cpig_supervisor.gleam",
    )
      |> with_kind(Process)
      |> with_process("otp-child", "integrated")
      |> with_domain("cpig"),
    holon(
      "iam-supervisor-gleam",
      "iam/supervisor.gleam",
      "prakriya (प्रक्रिया)",
      0,
      Runtime,
      Some("constitution"),
      [],
      "apps/cepaf_gleam/src/cepaf_gleam/iam/supervisor.gleam",
    )
      |> with_kind(Process)
      |> with_process("otp-child", "integrated")
      |> with_domain("iam"),
    holon(
      "vault-supervisor-gleam",
      "vault_supervisor.gleam",
      "prakriya (प्रक्रिया)",
      0,
      Runtime,
      Some("constitution"),
      [],
      "apps/cepaf_gleam/src/cepaf_gleam/vault_supervisor.gleam",
    )
      |> with_kind(Process)
      |> with_process("otp-child", "integrated")
      |> with_domain("secret"),
    holon(
      "ha-supervisor-config-gleam",
      "ha/supervisor_config.gleam",
      "prakriya (प्रक्रिया)",
      4,
      Runtime,
      Some("cepaf-gleam"),
      [],
      "apps/cepaf_gleam/src/cepaf_gleam/ha/supervisor_config.gleam",
    )
      |> with_kind(Process)
      |> with_process("otp-child", "integrated"),
    holon(
      "prajna-circuit-breaker-gleam",
      "prajna/circuit_breaker.gleam",
      "prakriya (प्रक्रिया)",
      4,
      Runtime,
      Some("cepaf-gleam"),
      [],
      "apps/cepaf_gleam/src/cepaf_gleam/prajna/circuit_breaker.gleam",
    )
      |> with_kind(Process)
      |> with_process("otp-child", "integrated"),
    holon(
      "ha-lyapunov-proof-gleam",
      "ha/lyapunov_proof.gleam",
      "prakriya (प्रक्रिया)",
      4,
      Runtime,
      Some("cepaf-gleam"),
      [],
      "apps/cepaf_gleam/src/cepaf_gleam/ha/lyapunov_proof.gleam",
    )
      |> with_kind(Process)
      |> with_process("otp-child", "integrated"),
    holon(
      "ha-freshness-monitor-gleam",
      "ha/freshness_monitor.gleam",
      "prakriya (प्रक्रिया)",
      4,
      Runtime,
      Some("cepaf-gleam"),
      [],
      "apps/cepaf_gleam/src/cepaf_gleam/ha/freshness_monitor.gleam",
    )
      |> with_kind(Process)
      |> with_process("otp-child", "integrated")
      |> with_domain("sync"),
    holon(
      "fractal-l0-constitutional-gleam",
      "fractal/l0_constitutional.gleam",
      "prakriya (प्रक्रिया)",
      0,
      Runtime,
      Some("constitution"),
      [],
      "apps/cepaf_gleam/src/cepaf_gleam/fractal/l0_constitutional.gleam",
    )
      |> with_kind(Process)
      |> with_process("otp-child", "integrated")
      |> with_domain("const"),
    holon(
      "services-stan-worker-stub",
      "services/stan_worker (stub)",
      "prakriya (प्रक्रिया)",
      4,
      Runtime,
      Some("tools"),
      [],
      "services/stan_worker/README.md",
    )
      |> with_kind(Process)
      |> with_process("otp-child", "absent"),
    holon(
      "services-rule-engine-worker-stub",
      "services/rule_engine_worker (stub)",
      "prakriya (प्रक्रिया)",
      5,
      Runtime,
      Some("tools"),
      [],
      "services/rule_engine_worker/README.md",
    )
      |> with_kind(Process)
      |> with_process("otp-child", "absent")
      |> with_domain("cog"),
    holon(
      "services-solver-worker-stub",
      "services/solver_worker (stub)",
      "prakriya (प्रक्रिया)",
      4,
      Runtime,
      Some("tools"),
      [],
      "services/solver_worker/README.md",
    )
      |> with_kind(Process)
      |> with_process("otp-child", "absent"),
    holon(
      "apps-indrajaal-gleam-library",
      "apps/indrajaal_gleam (library)",
      "prakriya (प्रक्रिया)",
      4,
      Runtime,
      Some("indrajaal-gleam-web"),
      [],
      "apps/indrajaal_gleam/{gleam.toml,manifest.toml,README.md}",
    )
      |> with_kind(Process)
      |> with_process("otp-child", "integrated"),
    holon(
      "indrajaal-gleam-web-mist-http-listener-4100",
      "indrajaal_gleam_web Mist HTTP listener :4100",
      "prakriya (प्रक्रिया)",
      4,
      Messaging,
      Some("indrajaal-gleam-web"),
      [],
      "apps/indrajaal_gleam_web/src/indrajaal_gleam_web.gleam:988-990 (mist.new/port/bind)",
    )
      |> with_kind(Process)
      |> with_process("listener", "integrated"),
    holon(
      "cepaf-gleam-web-server-gleam-mist-http-listener",
      "cepaf_gleam web/server.gleam Mist HTTP listener",
      "prakriya (प्रक्रिया)",
      4,
      Messaging,
      Some("cepaf-gleam"),
      [],
      "apps/cepaf_gleam/src/cepaf_gleam/web/server.gleam:1228-1230",
    )
      |> with_kind(Process)
      |> with_process("listener", "imported-not-wired"),
    holon(
      "cepaf-gleam-web-server-gleam-mist-https-listener",
      "cepaf_gleam web/server.gleam Mist HTTPS listener",
      "prakriya (प्रक्रिया)",
      4,
      Messaging,
      Some("cepaf-gleam"),
      [],
      "apps/cepaf_gleam/src/cepaf_gleam/web/server.gleam:1243-1245",
    )
      |> with_kind(Process)
      |> with_process("listener", "imported-not-wired"),
    holon(
      "zenoh-router-tcp-7447-rest-8080",
      "Zenoh router TCP:7447 / REST:8080",
      "prakriya (प्रक्रिया)",
      4,
      Messaging,
      Some("ops"),
      [],
      "c3i-zenoh-router-1 podman container (docker.io/eclipse/zenoh); config ops/zenoh/20260907-0450-uos-zenoh-router-1.json5",
    )
      |> with_kind(Process)
      |> with_process("listener", "integrated"),
    holon(
      "zenoh-router-rest-8000-alt",
      "Zenoh router REST:8000 (alt)",
      "prakriya (प्रक्रिया)",
      4,
      Messaging,
      Some("tools"),
      [],
      "c3i-zenoh-router.service (non -1 variant)",
    )
      |> with_kind(Process)
      |> with_process("listener", "superseded"),
    holon(
      "sa-plan-http-dashboard-4200",
      "sa-plan HTTP dashboard :4200",
      "prakriya (प्रक्रिया)",
      4,
      Messaging,
      Some("tools"),
      [],
      "c3i-sa-plan-http.service",
    )
      |> with_kind(Process)
      |> with_process("listener", "absent"),
    holon(
      "sa-plan-tls-proxy-8443-8088",
      "sa-plan TLS proxy :8443/:8088",
      "prakriya (प्रक्रिया)",
      4,
      Messaging,
      Some("tools"),
      [],
      "c3i-tls-proxy.service",
    )
      |> with_kind(Process)
      |> with_process("listener", "absent"),
    holon(
      "sa-plan-inference-uds-socket",
      "sa-plan inference UDS socket",
      "prakriya (प्रक्रिया)",
      5,
      Messaging,
      Some("tools"),
      [],
      "c3i-sa-plan-inference.service, %t/c3i/inference.sock",
    )
      |> with_kind(Process)
      |> with_process("listener", "absent")
      |> with_domain("cog"),
    holon(
      "mcp-stdio-servers-zigvm-harness-mcp-hermes-ops-mcp",
      "MCP stdio servers (zigvm_harness --mcp, hermes_ops mcp)",
      "prakriya (प्रक्रिया)",
      5,
      Messaging,
      Some("hermes"),
      [],
      "/home/an/dev/ver/zigvm ... zigvm_harness.exe --mcp; /home/an/NAS-setup/harness-bionic/_build/.../hermes_ops/ops_main.exe mcp",
    )
      |> with_kind(Process)
      |> with_process("listener", "imported-not-wired")
      |> with_domain("cog"),
    holon(
      "ag-ui-sse-stream-ag-ui-events",
      "AG-UI SSE stream /ag-ui/events",
      "prakriya (प्रक्रिया)",
      4,
      Messaging,
      Some("cepaf-gleam"),
      [],
      "apps/indrajaal_gleam_web/src/indrajaal_gleam_web.gleam router ('ag-ui' path branch calling cepaf_gleam/ui/wisp/router as c3i_router)",
    )
      |> with_kind(Process)
      |> with_process("listener", "integrated"),
    holon(
      "max-worker-py",
      "max_worker.py",
      "prakriya (प्रक्रिया)",
      5,
      Runtime,
      Some("uos-swarm"),
      [],
      "services/inference/max/max_worker.py",
    )
      |> with_kind(Process)
      |> with_process("worker", "imported-not-wired")
      |> with_domain("cog"),
    holon(
      "max-kernel-mojo",
      "max_kernel.mojo",
      "prakriya (प्रक्रिया)",
      5,
      Intelligence,
      Some("inference-max"),
      [],
      "services/inference/max/max_kernel.mojo",
    )
      |> with_kind(Process)
      |> with_process("worker", "integrated")
      |> with_domain("cog"),
    holon(
      "e2e-ui-tester-py",
      "e2e_ui_tester.py",
      "prakriya (प्रक्रिया)",
      4,
      Runtime,
      Some("tools"),
      [],
      "/home/an/dev/ver/c3i/e2e_ui_tester.py",
    )
      |> with_kind(Process)
      |> with_process("worker", "absent")
      |> with_domain("unassigned"),
    holon(
      "generate-ui-py",
      "generate_ui.py",
      "prakriya (प्रक्रिया)",
      4,
      Runtime,
      Some("tools"),
      [],
      "/home/an/dev/ver/c3i/generate_ui.py",
    )
      |> with_kind(Process)
      |> with_process("worker", "absent")
      |> with_domain("unassigned"),
    holon(
      "run-tui-py",
      "run_tui.py",
      "prakriya (प्रक्रिया)",
      4,
      Runtime,
      Some("uos-tui"),
      [],
      "/home/an/dev/ver/c3i/run_tui.py",
    )
      |> with_kind(Process)
      |> with_process("worker", "absent")
      |> with_domain("unassigned"),
    holon(
      "fix-gleam-warnings-py",
      "fix_gleam_warnings.py",
      "prakriya (प्रक्रिया)",
      4,
      Runtime,
      Some("tools"),
      [],
      "/home/an/dev/ver/c3i/fix_gleam_warnings.py",
    )
      |> with_kind(Process)
      |> with_process("worker", "absent")
      |> with_domain("unassigned"),
    holon(
      "exhaustive-parity-audit-py",
      "exhaustive_parity_audit.py",
      "prakriya (प्रक्रिया)",
      4,
      Runtime,
      Some("tools"),
      [],
      "/home/an/dev/ver/c3i/scripts/exhaustive_parity_audit.py",
    )
      |> with_kind(Process)
      |> with_process("worker", "absent")
      |> with_domain("unassigned"),
    holon(
      "mcp-c3i-server-rust",
      "mcp/c3i_server (Rust)",
      "prakriya (प्रक्रिया)",
      5,
      Runtime,
      Some("tools"),
      [],
      "/home/an/dev/ver/c3i/sub-projects/c3i/mcp/c3i_server (Cargo [[bin]])",
    )
      |> with_kind(Process)
      |> with_process("worker", "absent")
      |> with_domain("cog"),
    holon(
      "mcp-timestamp-sync-rust",
      "mcp/timestamp_sync (Rust)",
      "prakriya (प्रक्रिया)",
      5,
      Intelligence,
      Some("hermes"),
      [],
      "/home/an/dev/ver/c3i/sub-projects/c3i/mcp/timestamp_sync",
    )
      |> with_kind(Process)
      |> with_process("worker", "superseded")
      |> with_domain("cog"),
    holon(
      "native-wireframe-renderer-rust",
      "native/wireframe_renderer (Rust)",
      "prakriya (प्रक्रिया)",
      1,
      Runtime,
      Some("native-nifs"),
      [],
      "/home/an/dev/ver/c3i/sub-projects/c3i/native/wireframe_renderer",
    )
      |> with_kind(Process)
      |> with_process("worker", "absent"),
    holon(
      "native-planning-daemon-rust",
      "native/planning_daemon (Rust)",
      "prakriya (प्रक्रिया)",
      1,
      Runtime,
      Some("native-nifs"),
      [],
      "/home/an/dev/ver/c3i/sub-projects/c3i/native/planning_daemon",
    )
      |> with_kind(Process)
      |> with_process("worker", "absent"),
    holon(
      "native-ignition-daemon-rust",
      "native/ignition_daemon (Rust)",
      "prakriya (प्रक्रिया)",
      1,
      Runtime,
      Some("native-nifs"),
      [],
      "/home/an/dev/ver/c3i/sub-projects/c3i/native/ignition_daemon",
    )
      |> with_kind(Process)
      |> with_process("worker", "absent"),
    holon(
      "ferriskey-vendored-operator-rust",
      "ferriskey-vendored/operator (Rust)",
      "prakriya (प्रक्रिया)",
      0,
      Runtime,
      Some("constitution"),
      [],
      "/home/an/dev/ver/c3i/sub-projects/ferriskey-vendored/operator (Cargo [[bin]])",
    )
      |> with_kind(Process)
      |> with_process("worker", "absent")
      |> with_domain("iam"),
    holon(
      "rusty-vault-vendored-rust-source-of-rusty-vault-nif-so",
      "rusty_vault_vendored (Rust, source of rusty_vault_nif.so)",
      "prakriya (प्रक्रिया)",
      0,
      Runtime,
      Some("constitution"),
      [],
      "/home/an/dev/ver/c3i/sub-projects/rusty_vault_vendored",
    )
      |> with_kind(Process)
      |> with_process("worker", "integrated")
      |> with_domain("secret"),
    holon(
      "graphene-nif-rust-crate-lib-cepaf-gleam-native-graphene-nif",
      "graphene_nif Rust crate (lib/cepaf_gleam/native/graphene_nif)",
      "prakriya (प्रक्रिया)",
      1,
      Runtime,
      Some("native-nifs"),
      [],
      "/home/an/dev/ver/c3i/lib/cepaf_gleam/native/graphene_nif (Cargo [[bin]]/cdylib wrapping graphene/tiny-skia/kurbo/resvg/plotters/vega-lite/petgraph crates)",
    )
      |> with_kind(Process)
      |> with_process("worker", "superseded"),
    holon(
      "graphite-editor-bevy-based-rust-desktop-editor",
      "graphite-editor (Bevy-based Rust desktop editor)",
      "prakriya (प्रक्रिया)",
      1,
      Runtime,
      Some("native-nifs"),
      [],
      "/home/an/dev/ver/c3i/lib/cepaf_gleam/native/graphite-editor/desktop (+ platform/linux, platform/mac, platform/win Cargo.toml)",
    )
      |> with_kind(Process)
      |> with_process("worker", "barred"),
    holon(
      "indrajaal-ark-rust",
      "indrajaal_ark (Rust)",
      "prakriya (प्रक्रिया)",
      1,
      Runtime,
      Some("tools"),
      [],
      "/home/an/dev/ver/c3i/sub-projects/c3i/lib/indrajaal_ark (Cargo.toml)",
    )
      |> with_kind(Process)
      |> with_process("worker", "absent"),
    holon(
      "indrajaal-ark-zig-zig",
      "indrajaal_ark_zig (Zig)",
      "prakriya (प्रक्रिया)",
      1,
      Runtime,
      Some("zigvm"),
      [],
      "/home/an/dev/ver/c3i/sub-projects/c3i/lib/indrajaal_ark_zig/src/main.zig",
    )
      |> with_kind(Process)
      |> with_process("worker", "absent"),
    holon(
      "indrajaal-env-checker-rust",
      "indrajaal_env_checker (Rust)",
      "prakriya (प्रक्रिया)",
      1,
      Runtime,
      Some("tools"),
      [],
      "/home/an/dev/ver/c3i/sub-projects/c3i/src/rust/indrajaal_env_checker",
    )
      |> with_kind(Process)
      |> with_process("worker", "absent"),
    holon(
      "indrajaal-web-elixir-phoenix-legacy",
      "indrajaal_web (Elixir/Phoenix, legacy)",
      "prakriya (प्रक्रिया)",
      4,
      Runtime,
      Some("indrajaal-gleam-web"),
      [],
      "/home/an/dev/ver/c3i/sub-projects/c3i/lib/indrajaal_web/{endpoint,router,presence,telemetry,guardian,gettext,rate_limiter,connection_tracker,open_api,unified_controller_patterns}.ex",
    )
      |> with_kind(Process)
      |> with_process("worker", "superseded")
      |> with_domain("unassigned"),
    holon(
      "hermes-harness-incl-hermes-rete-ml-compiled-zenoh-c-stub",
      "hermes_harness (incl. hermes_rete.ml + compiled Zenoh C-stub)",
      "prakriya (प्रक्रिया)",
      5,
      Intelligence,
      Some("hermes"),
      [],
      "engines/hermes/modules/hermes_harness/{hermes_rete.ml,.mli,.gospel, dune}; compiled dllhermes_harness_hermes_zenoh_stubs.so",
    )
      |> with_kind(Process)
      |> with_process("worker", "integrated")
      |> with_domain("cog"),
    holon(
      "hermes-dependability-dune-dependability-clock-ml",
      "hermes_dependability (dune, dependability_clock.ml)",
      "prakriya (प्रक्रिया)",
      5,
      Intelligence,
      Some("hermes"),
      [],
      "engines/hermes/modules/hermes_dependability/dune",
    )
      |> with_kind(Process)
      |> with_process("worker", "integrated")
      |> with_domain("cog"),
    holon(
      "tailscale-monitor-dune-exe",
      "tailscale_monitor (dune exe)",
      "prakriya (प्रक्रिया)",
      5,
      Intelligence,
      Some("hermes"),
      [],
      "engines/hermes/modules/tailscale_monitor/dune",
    )
      |> with_kind(Process)
      |> with_process("worker", "integrated")
      |> with_domain("cog"),
    holon(
      "hermes-server-dune-exe",
      "hermes_server (dune exe)",
      "prakriya (प्रक्रिया)",
      5,
      Intelligence,
      Some("hermes"),
      [],
      "engines/hermes/modules/hermes_server/dune",
    )
      |> with_kind(Process)
      |> with_process("worker", "integrated")
      |> with_domain("cog"),
    holon(
      "hermes-ops-dune-exe-ops-main-exe-mcp",
      "hermes_ops (dune exe, ops_main.exe mcp)",
      "prakriya (प्रक्रिया)",
      5,
      Intelligence,
      Some("hermes"),
      [],
      "engines/hermes/modules/hermes_ops/dune",
    )
      |> with_kind(Process)
      |> with_process("worker", "imported-not-wired")
      |> with_domain("cog"),
    holon(
      "hermes-mirage-dune-exe",
      "hermes_mirage (dune exe)",
      "prakriya (प्रक्रिया)",
      5,
      Intelligence,
      Some("hermes"),
      [],
      "engines/hermes/modules/hermes_mirage/dune",
    )
      |> with_kind(Process)
      |> with_process("worker", "imported-not-wired")
      |> with_domain("cog"),
    holon(
      "hermes-vision-dune-exe",
      "hermes_vision (dune exe)",
      "prakriya (प्रक्रिया)",
      5,
      Intelligence,
      Some("hermes"),
      [],
      "engines/hermes/modules/hermes_vision/dune",
    )
      |> with_kind(Process)
      |> with_process("worker", "imported-not-wired")
      |> with_domain("cog"),
    holon(
      "hermes-wiki-tools-frontend-dune-exe",
      "hermes_wiki tools+frontend (dune exe)",
      "prakriya (प्रक्रिया)",
      5,
      Intelligence,
      Some("hermes"),
      [],
      "engines/hermes/modules/hermes_wiki/src/{tools,frontend}/dune",
    )
      |> with_kind(Process)
      |> with_process("worker", "integrated")
      |> with_domain("cog"),
    holon(
      "hermes-ops-dashboard-dune-exe",
      "hermes_ops_dashboard (dune exe)",
      "prakriya (प्रक्रिया)",
      5,
      Intelligence,
      Some("hermes"),
      [],
      "engines/hermes/modules/hermes_ops_dashboard/dune",
    )
      |> with_kind(Process)
      |> with_process("worker", "imported-not-wired")
      |> with_domain("cog"),
    holon(
      "hermes-zellij-dune-exe",
      "hermes_zellij (dune exe)",
      "prakriya (प्रक्रिया)",
      5,
      Intelligence,
      Some("hermes"),
      [],
      "engines/hermes/modules/hermes_zellij/dune",
    )
      |> with_kind(Process)
      |> with_process("worker", "imported-not-wired")
      |> with_domain("cog"),
    holon(
      "hermes-sysml-dune-exe",
      "hermes_sysml (dune exe)",
      "prakriya (प्रक्रिया)",
      5,
      Intelligence,
      Some("hermes"),
      [],
      "engines/hermes/modules/hermes_sysml/dune",
    )
      |> with_kind(Process)
      |> with_process("worker", "imported-not-wired")
      |> with_domain("cog"),
    holon(
      "swarm-dune-module",
      "swarm (dune module)",
      "prakriya (प्रक्रिया)",
      5,
      Runtime,
      Some("uos-swarm"),
      [],
      "engines/hermes/modules/swarm/dune",
    )
      |> with_kind(Process)
      |> with_process("worker", "imported-not-wired")
      |> with_domain("cog"),
    holon(
      "hermes-tooling-modules-toolchain-nix-vcs-fpp-authority-dune-graph-harness-stubber-fetch-cowboy-sa-plan-test",
      "hermes tooling modules (toolchain/nix/vcs/fpp_authority/dune_graph/harness_stubber/fetch_cowboy/sa_plan test)",
      "prakriya (प्रक्रिया)",
      5,
      Intelligence,
      Some("hermes"),
      [],
      "engines/hermes/modules/{hermes_toolchain,hermes_nix,hermes_vcs,hermes_fpp_authority,hermes_dune_graph,hermes_harness_stubber,fetch_cowboy}/dune, engines/hermes/modules/sa_plan/test/dune",
    )
      |> with_kind(Process)
      |> with_process("worker", "integrated")
      |> with_domain("cog"),
    holon(
      "ferriskey-nif",
      "ferriskey_nif",
      "prakriya (प्रक्रिया)",
      0,
      Runtime,
      Some("constitution"),
      [],
      "apps/cepaf_gleam/src/ferriskey_nif.erl -> priv/ferriskey_nif.so",
    )
      |> with_kind(Process)
      |> with_process("nif", "integrated")
      |> with_domain("iam"),
    holon(
      "c3i-ocaml-nif",
      "c3i_ocaml_nif",
      "prakriya (प्रक्रिया)",
      1,
      Runtime,
      Some("native-nifs"),
      [],
      "apps/cepaf_gleam/src/c3i_ocaml_nif.erl -> priv/c3i_ocaml_nif.so",
    )
      |> with_kind(Process)
      |> with_process("nif", "integrated"),
    holon(
      "rule-engine-nif",
      "rule_engine_nif",
      "prakriya (प्रक्रिया)",
      1,
      Runtime,
      Some("native-nifs"),
      [],
      "apps/cepaf_gleam/src/rule_engine_nif.erl -> priv/rule_engine_nif.so",
    )
      |> with_kind(Process)
      |> with_process("nif", "integrated"),
    holon(
      "planning-nif",
      "planning_nif",
      "prakriya (प्रक्रिया)",
      1,
      Runtime,
      Some("native-nifs"),
      [],
      "apps/cepaf_gleam/src/planning_nif.erl -> priv/native/planning_nif.so",
    )
      |> with_kind(Process)
      |> with_process("nif", "imported-not-wired"),
    holon(
      "c3i-nif",
      "c3i_nif",
      "prakriya (प्रक्रिया)",
      1,
      Runtime,
      Some("native-nifs"),
      [],
      "apps/cepaf_gleam/src/c3i_nif.erl -> priv/c3i_nif.so",
    )
      |> with_kind(Process)
      |> with_process("nif", "integrated"),
    holon(
      "graphene-nif-loader",
      "graphene_nif (loader)",
      "prakriya (प्रक्रिया)",
      1,
      Runtime,
      Some("native-nifs"),
      [],
      "apps/cepaf_gleam/src/graphene_nif.erl",
    )
      |> with_kind(Process)
      |> with_process("nif", "superseded"),
    holon(
      "rusty-vault-nif",
      "rusty_vault_nif",
      "prakriya (प्रक्रिया)",
      0,
      Runtime,
      Some("constitution"),
      [],
      "apps/cepaf_gleam/src/rusty_vault_nif.erl -> priv/rusty_vault_nif.so",
    )
      |> with_kind(Process)
      |> with_process("nif", "integrated")
      |> with_domain("secret"),
    holon(
      "containers-dockerfile-precompiled",
      "containers/Dockerfile.precompiled",
      "prakriya (प्रक्रिया)",
      6,
      Runtime,
      Some("tools"),
      [],
      "/home/an/dev/ver/c3i/containers/Dockerfile.precompiled (also under sub-projects/c3i/containers/)",
    )
      |> with_kind(Process)
      |> with_process("container", "absent"),
    holon(
      "containers-signoz-docker-compose-observability-stack",
      "containers/signoz docker-compose (observability stack)",
      "prakriya (प्रक्रिया)",
      6,
      Runtime,
      Some("tools"),
      [],
      "/home/an/dev/ver/c3i/containers/signoz/docker-compose.yml",
    )
      |> with_kind(Process)
      |> with_process("container", "absent"),
    holon(
      "sub-projects-c3i-dockerfile-cluster-db-sil4-db-sil4-app-sil4-obs-cortex-kms-catalog-cepaf-bridge-mojo-fix-sopv51-app-sopv51-app-hardened-sopv51-base",
      "sub-projects/c3i Dockerfile.* cluster (db, sil4-db, sil4-app, sil4-obs, cortex, kms-catalog, cepaf-bridge, mojo, fix, sopv51-app, sopv51-app-hardened, sopv51-base)",
      "prakriya (प्रक्रिया)",
      6,
      Runtime,
      Some("tools"),
      [],
      "/home/an/dev/ver/c3i/sub-projects/c3i/Dockerfile.* (12 files)",
    )
      |> with_kind(Process)
      |> with_process("container", "absent"),
    holon(
      "ferriskey-vendored-containers-k8s-manifests",
      "ferriskey-vendored containers + k8s manifests",
      "prakriya (प्रक्रिया)",
      6,
      Runtime,
      Some("tools"),
      [],
      "/home/an/dev/ver/c3i/sub-projects/ferriskey-vendored/{Dockerfile, charts/ferriskey/templates/{api,webapp}/deployment.yaml, charts/ferriskey/templates/postgresql/statefulset.yaml, operator/k8s/deployment.yaml}",
    )
      |> with_kind(Process)
      |> with_process("container", "imported-not-wired"),
    holon(
      "openclaw-containers-k8s-manifest",
      "openclaw containers + k8s manifest",
      "prakriya (प्रक्रिया)",
      6,
      Runtime,
      Some("tools"),
      [],
      "/home/an/dev/ver/c3i/sub-projects/openclaw/{Dockerfile, Dockerfile.sandbox*, docker-compose.yml, scripts/k8s/manifests/deployment.yaml, scripts/e2e/Dockerfile*}",
    )
      |> with_kind(Process)
      |> with_process("container", "absent"),
    holon(
      "tools-sa-plan-ocaml-sa-plan-main-exe",
      "tools/sa-plan (OCaml sa_plan_main.exe)",
      "prakriya (प्रक्रिया)",
      5,
      Intelligence,
      Some("hermes"),
      [],
      "tools/sa-plan (bash wrapper) -> engines/hermes/_build/default/modules/sa_plan/test/sa_plan_main.exe; live DB at var/sa-plan/uos.sqlite3",
    )
      |> with_kind(Process)
      |> with_process("worker", "integrated")
      |> with_domain("cog"),
    holon(
      "k8s-lab-rust-cli-render-kube-apply-spec",
      "k8s-lab Rust CLI (render/kube_apply/spec)",
      "prakriya (प्रक्रिया)",
      6,
      Runtime,
      Some("ops"),
      [],
      "/home/an/NAS-setup/k8s-lab/src/{main.rs,spec.rs,render.rs,kube_apply.rs}",
    )
      |> with_kind(Process)
      |> with_process("worker", "integrated"),
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

/// Non-Process holons still carry a Sanskrit name; census-derived `Process` holons are allowed
/// a blank `sanskrit` (design doc 3.2: "sanskrit = \"\" is acceptable for census-derived holons").
fn rule_b5(hs: List(Holon)) -> #(String, Bool, String) {
  case list.find(hs, fn(h) { h.sanskrit == "" && h.kind != Process }) {
    Error(_) -> #(
      "B5",
      True,
      "all non-Process holons carry a Sanskrit name ("
        <> int.to_string(list.length(hs))
        <> " holons total; Process/census holons may be \"\")",
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

/// B10: census parity. Returns the census `name`s that do not match any `Process`-kind holon's
/// `name` field. Empty list = pass. Pure (no file IO): the caller loads/parses the census JSON
/// (see `holon_test.gleam`'s `b10_census_parity_test`, which reads
/// `test/fixtures/20260907-1320-daemon-census.json`) and passes just the extracted names.
pub fn b10_missing(
  hs: List(Holon),
  census_names: List(String),
) -> List(String) {
  let process_names =
    list.filter_map(hs, fn(h) {
      case h.kind {
        Process -> Ok(h.name)
        _ -> Error(Nil)
      }
    })
  list.filter(census_names, fn(n) { !list.contains(process_names, n) })
}

/// B10 as a `#(rule id, ok, detail)` triple, matching the B1..B9 shape (see `base_rules`). Not
/// folded into `base_rules` itself because it needs the census names as an extra argument, which
/// `base_rules(hs)` (and its callers, e.g. `base_rules_markdown`, `holon rules` CLI arm) do not
/// carry -- this module has no file IO of its own (design doc 3.3, B10).
pub fn rule_b10(
  hs: List(Holon),
  census_names: List(String),
) -> #(String, Bool, String) {
  case b10_missing(hs, census_names) {
    [] -> #(
      "B10",
      True,
      "all "
        <> int.to_string(list.length(census_names))
        <> " daemon-census rows name a Process holon",
    )
    missing -> #(
      "B10",
      False,
      int.to_string(list.length(missing))
        <> " census row(s) have no matching Process holon: "
        <> string.join(missing, ", "),
    )
  }
}

/// B13 (PLACEHOLDER -- design doc 3.5/Appendix B, NOT implemented beyond this stub): "every
/// tracked file, every process, every provisioned artifact, every sa-plan unit, every board
/// agent and every resource ... belongs to exactly one holon of a declared kind". The oracle for
/// B13 is the universe census (`generated/20260907-1525-uos-holon-universe-census.json`), not
/// the daemon census B10 uses; wiring B13 to that census the way B10 is wired to the daemon
/// census is future work (HOLON-LIFECYCLE / PROJECTIONS tasks), left undone here on purpose.
pub fn rule_b13() -> #(String, Bool, String) {
  #(
    "B13",
    True,
    "placeholder -- not implemented; oracle is the universe census (design doc Appendix B), not yet wired",
  )
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
      #("kind", json.string(kind_label(h.kind))),
      #("domain", json.string(h.domain)),
      #("process_class", json.string(h.process_class)),
      #("status", json.string(h.status)),
      #("uid", json.string(h.uid)),
      #("lifecycle", json.string(lifecycle_label(h.lifecycle))),
      #("vitals", case h.vitals {
        None -> json.null()
        Some(v) ->
          json.object([
            #("heartbeat_age_s", case v.heartbeat_age_s {
              Some(s) -> json.int(s)
              None -> json.null()
            }),
            #("restarts", json.int(v.restarts)),
            #("last_transition", case v.last_transition {
              Some(t) -> json.string(t)
              None -> json.null()
            }),
          ])
      }),
      #("address", json.string(address(h))),
    ])
  })
}

pub fn kind_label(k: Kind) -> String {
  case k {
    System -> "system"
    PlaneKind -> "plane"
    Subsystem -> "subsystem"
    Component -> "component"
    Process -> "process"
    Artifact -> "artifact"
    Record -> "record"
    Document -> "document"
    Rule -> "rule"
    Skill -> "skill"
    AgentRole -> "agent-role"
    Test -> "test"
    Spec -> "spec"
    Plan -> "plan"
    Task -> "task"
    Job -> "job"
    Workflow -> "workflow"
    Resource -> "resource"
    AgentSession -> "agent-session"
    Legacy -> "legacy"
    Dataset -> "dataset"
  }
}

pub fn lifecycle_label(l: Lifecycle) -> String {
  case l {
    Dormant -> "dormant"
    Awakening -> "awakening"
    Active -> "active"
    Stressed -> "stressed"
    Healing -> "healing"
    Apoptotic -> "apoptotic"
  }
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
