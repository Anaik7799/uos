//// Unified System Ontology: ONE concept registry for the whole UOS swarm — dictionary,
//// glossary, wiki and knowledge-map in one place, so every message on the board is aligned
//// against the same vocabulary. Populated from the code that exists: every Textual concept of
//// `uos_tui/ontology.concepts()` (id = `textual_name`, so existing board messages resolve
//// unchanged), every holon of `uos_swarm/holon.holarchy()`, the 17 aspects of
//// `uos_tui/aspects`, the STPA control actions of `uos_swarm/stpa.model()`, plus the muda,
//// board kinds, ACL performatives, OODA modes/phases, TPS terms, coordination and governance
//// terms, agent-kernel terms, review/admission terms, economy terms and the Hindu thinking and
//// memory structures (antaḥkaraṇa, pramāṇa, citta-vṛtti, guṇa, kośa) the operator asked to map
//// onto the running system, and the four musical anchors (svara, thāṭ, rāga, tāla).
////
//// Every concept carries IAST and Devanagari: reused from the system's existing Sanskrit
//// (holon.gleam, acl.gleam's lexicon shape, agent_runtime.gleam's state/capability labels)
//// where one already exists, otherwise a short Sanskrit gloss coined for this registry.
//// STAMP: SC-SWARM-ONTOLOGY-001, #km-triad, #fractal-l0..l9.

import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import uos_swarm/holon
import uos_swarm/stpa
import uos_tui/aspects.{
  type Aspect, A2UiCatalog, AgUiEventStream, BiosemioticCybernetics,
  ComprehensiveChecklist, GleamOtpSupervisor, HermesEvidence, KnowledgeTriad,
  MathematicalAuthority, PentaStackAccessibility, QuarantinedMaxInference,
  SaPlanDurability, StandaloneJujutsu, SubstrateStorageSafety,
  TailscaleFqdnNavigation, ZenohTelemetry, ZeroMudaPurity, ZigVmEngine,
}
import uos_tui/ontology.{
  type FractalLayer, L0Constitutional, L1Atomic, L2Component, L3Transaction,
  L4System, L5Cognitive, L6Ecosystem, L7Federation, L8Evolution, L9Singularity,
}

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

pub type Domain {
  TuiLibrary
  Structure
  Runtime
  Data
  Messaging
  Intelligence
  Language
  Thinking
  Memory
  Music
  Governance
  Review
  Coordination
  Safety
  Economy
  Vcs
}

pub const all_domains = [
  TuiLibrary,
  Structure,
  Runtime,
  Data,
  Messaging,
  Intelligence,
  Language,
  Thinking,
  Memory,
  Music,
  Governance,
  Review,
  Coordination,
  Safety,
  Economy,
  Vcs,
]

pub fn domain_label(d: Domain) -> String {
  case d {
    TuiLibrary -> "TUI Library"
    Structure -> "Structure"
    Runtime -> "Runtime"
    Data -> "Data"
    Messaging -> "Messaging"
    Intelligence -> "Intelligence"
    Language -> "Language"
    Thinking -> "Thinking"
    Memory -> "Memory"
    Music -> "Music"
    Governance -> "Governance"
    Review -> "Review"
    Coordination -> "Coordination"
    Safety -> "Safety"
    Economy -> "Economy"
    Vcs -> "Version control (Jujutsu)"
  }
}

fn domain_node(d: Domain) -> String {
  case d {
    TuiLibrary -> "TuiLibrary"
    Structure -> "Structure"
    Runtime -> "Runtime"
    Data -> "Data"
    Messaging -> "Messaging"
    Intelligence -> "Intelligence"
    Language -> "Language"
    Thinking -> "Thinking"
    Memory -> "Memory"
    Music -> "Music"
    Governance -> "Governance"
    Review -> "Review"
    Coordination -> "Coordination"
    Safety -> "Safety"
    Economy -> "Economy"
    Vcs -> "Vcs"
  }
}

pub type Concept {
  Concept(
    id: String,
    english: String,
    iast: String,
    devanagari: String,
    domain: Domain,
    layer: Int,
    aspects: List(Int),
    plane: String,
    definition: String,
    relates: List(String),
    source: String,
  )
}

fn mk(
  id: String,
  english: String,
  iast: String,
  devanagari: String,
  domain: Domain,
  layer: Int,
  aspects: List(Int),
  plane: String,
  definition: String,
  relates: List(String),
  source: String,
) -> Concept {
  Concept(
    id,
    english,
    iast,
    devanagari,
    domain,
    layer,
    aspects,
    plane,
    definition,
    relates,
    source,
  )
}

// ---------------------------------------------------------------------------
// 1. Textual concepts (uos_tui/ontology.concepts()) — id = textual_name, so every existing
//    board message referencing e.g. "Worker" or "17 Aspect audit" keeps resolving.
// ---------------------------------------------------------------------------

fn fractal_layer_int(l: FractalLayer) -> Int {
  case l {
    L0Constitutional -> 0
    L1Atomic -> 1
    L2Component -> 2
    L3Transaction -> 3
    L4System -> 4
    L5Cognitive -> 5
    L6Ecosystem -> 6
    L7Federation -> 7
    L8Evolution -> 8
    L9Singularity -> 9
  }
}

fn textual_gloss(name: String) -> #(String, String) {
  case name {
    "App" -> #("yantra", "यन्त्र")
    "Screen" -> #("paṭala", "पटल")
    "Widget" -> #("aṅga", "अङ्ग")
    "DOM" -> #("vṛkṣa", "वृक्ष")
    "compose()" -> #("racanā", "रचना")
    "TCSS" -> #("śailī", "शैली")
    "Scalar / fr units" -> #("mātrā", "मात्रा")
    "Vertical/Horizontal/Grid" -> #("vinyāsa", "विन्यास")
    "Region/Size/Offset" -> #("kṣetra", "क्षेत्र")
    "Segment / Strip" -> #("khaṇḍa", "खण्ड")
    "Compositor" -> #("citra-kāra", "चित्र-कार")
    "reactive" -> #("pratikriyā", "प्रतिक्रिया")
    "Message / Event" -> #("sandeśa", "सन्देश")
    "Binding / action" -> #("bandhana", "बन्धन")
    "Focus chain" -> #("dṛṣṭi-śṛṅkhalā", "दृष्टि-शृङ्खला")
    "Worker" -> #("kārmakara", "कार्मकर")
    "Driver" -> #("cālaka", "चालक")
    "Pilot / run_test" -> #("parīkṣaka", "परीक्षक")
    "Command palette" -> #("ādeśa-thālī", "आदेश-थाली")
    "Themes" -> #("varṇa-vinyāsa", "वर्ण-विन्यास")
    "Header/Footer" -> #("śiras-pāda", "शिरस्-पाद")
    "Static/Label" -> #("nāma-paṭṭikā", "नाम-पट्टिका")
    "Button" -> #("sparśaka", "स्पर्शक")
    "Input" -> #("praveśa", "प्रवेश")
    "DataTable" -> #("dattāṃśa-sāraṇī", "दत्तांश-सारणी")
    "Tree" -> #("vṛkṣa", "वृक्ष")
    "ListView" -> #("sūcī", "सूची")
    "ProgressBar" -> #("pragati-paṭṭī", "प्रगति-पट्टी")
    "Sparkline" -> #("laghu-rekhā", "लघु-रेखा")
    "Tabs / TabbedContent" -> #("vibhāga", "विभाग")
    "RichLog / Log" -> #("vṛttānta", "वृत्तान्त")
    "Rule" -> #("rekhā", "रेखा")
    "Collapsible" -> #("saṅkocanīya", "सङ्कोचनीय")
    "Container" -> #("pātra", "पात्र")
    "17 Aspect audit" -> #("saptadaśa-pakṣa", "सप्तदश-पक्ष")
    "F´ component" -> #("upāṅga", "उपाङ्ग")
    "Textual Web / serve" -> #("jāla-sevā", "जाल-सेवा")
    "Evolution" -> #("vikāsa", "विकास")
    other -> #(other, other)
  }
}

fn textual_relates(name: String) -> List(String) {
  ontology.edges()
  |> list.filter(fn(e) { e.from == name })
  |> list.map(fn(e) { e.to })
}

fn from_textual(tc: ontology.Concept) -> Concept {
  let #(iast, dev) = textual_gloss(tc.textual_name)
  mk(
    tc.textual_name,
    tc.textual_name,
    iast,
    dev,
    TuiLibrary,
    fractal_layer_int(tc.layer),
    [],
    "runtime-plane",
    tc.textual_locus
      <> " -> "
      <> tc.uos_module
      <> "."
      <> tc.uos_symbol
      <> " ("
      <> ontology.fidelity_label(tc.fidelity)
      <> "). "
      <> tc.note,
    textual_relates(tc.textual_name),
    tc.uos_module <> ":" <> tc.uos_symbol,
  )
}

fn textual_concepts() -> List(Concept) {
  list.map(ontology.concepts(), from_textual)
}

// ---------------------------------------------------------------------------
// 2. Holons (uos_swarm/holon.holarchy()) — id = holon id, iast/devanagari parsed from the
//    holon's `sanskrit` field ("iast (devanāgarī)").
// ---------------------------------------------------------------------------

fn split_sanskrit(s: String) -> #(String, String) {
  case string.split_once(s, " (") {
    Ok(#(iast, rest)) -> #(iast, string.drop_end(rest, 1))
    Error(_) -> #(s, "")
  }
}

fn holon_domain(p: holon.Plane) -> Domain {
  case p {
    holon.Control -> Coordination
    holon.Structure -> Structure
    holon.Runtime -> Runtime
    holon.DataPlane -> Data
    holon.Messaging -> Messaging
    holon.Intelligence -> Intelligence
    holon.Language -> Language
  }
}

fn whole_label(w: Option(String)) -> String {
  case w {
    Some(id) -> id
    None -> "(root)"
  }
}

fn from_holon(h: holon.Holon) -> Concept {
  let #(iast, dev) = split_sanskrit(h.sanskrit)
  mk(
    h.id,
    h.name,
    iast,
    dev,
    holon_domain(h.plane),
    h.level,
    [],
    holon.plane_label(h.plane),
    "Holon "
      <> holon.address(h)
      <> " ("
      <> h.module
      <> "), whole "
      <> whole_label(h.whole)
      <> ".",
    h.parts,
    "uos_swarm/holon.gleam:holarchy",
  )
}

fn holon_concepts() -> List(Concept) {
  list.map(holon.holarchy(), from_holon)
}

// ---------------------------------------------------------------------------
// 3. 17-aspect audit (uos_tui/aspects) — id "aspect:<TypeName>", english = aspects.name(a).
// ---------------------------------------------------------------------------

fn aspect_key(a: Aspect) -> String {
  case a {
    SubstrateStorageSafety -> "SubstrateStorageSafety"
    StandaloneJujutsu -> "StandaloneJujutsu"
    ZeroMudaPurity -> "ZeroMudaPurity"
    GleamOtpSupervisor -> "GleamOtpSupervisor"
    ZigVmEngine -> "ZigVmEngine"
    HermesEvidence -> "HermesEvidence"
    MathematicalAuthority -> "MathematicalAuthority"
    BiosemioticCybernetics -> "BiosemioticCybernetics"
    QuarantinedMaxInference -> "QuarantinedMaxInference"
    ZenohTelemetry -> "ZenohTelemetry"
    AgUiEventStream -> "AgUiEventStream"
    A2UiCatalog -> "A2UiCatalog"
    PentaStackAccessibility -> "PentaStackAccessibility"
    TailscaleFqdnNavigation -> "TailscaleFqdnNavigation"
    ComprehensiveChecklist -> "ComprehensiveChecklist"
    KnowledgeTriad -> "KnowledgeTriad"
    SaPlanDurability -> "SaPlanDurability"
  }
}

fn aspect_gloss(a: Aspect) -> #(String, String) {
  case a {
    SubstrateStorageSafety -> #("saṃgraha-surakṣā", "संग्रह-सुरक्षा")
    StandaloneJujutsu -> #("svatantra-saṃskaraṇa", "स्वतन्त्र-संस्करण")
    ZeroMudaPurity -> #("śūnya-vyartha-śuddhi", "शून्य-व्यर्थ-शुद्धि")
    GleamOtpSupervisor -> #("adhyakṣa", "अध्यक्ष")
    ZigVmEngine -> #("niyata-yantra", "नियत-यन्त्र")
    HermesEvidence -> #("pramāṇa-sākṣya", "प्रमाण-साक्ष्य")
    MathematicalAuthority -> #("gaṇita-adhikāra", "गणित-अधिकार")
    BiosemioticCybernetics -> #("jīva-saṅketa-vijñāna", "जीव-सङ्केत-विज्ञान")
    QuarantinedMaxInference -> #("saṅgarodhita-anumāna", "सङ्गरोधित-अनुमान")
    ZenohTelemetry -> #("dūra-mitī", "दूर-मिती")
    AgUiEventStream -> #("ghaṭanā-srota", "घटना-स्रोत")
    A2UiCatalog -> #("sūcī-kośa", "सूची-कोश")
    PentaStackAccessibility -> #("pañca-stara-sulabhatā", "पञ्च-स्तर-सुलभता")
    TailscaleFqdnNavigation -> #("jāla-mārga-darśana", "जाल-मार्ग-दर्शन")
    ComprehensiveChecklist -> #("samagra-sūcī-patra", "समग्र-सूची-पत्र")
    KnowledgeTriad -> #("jñāna-trika", "ज्ञान-त्रिक")
    SaPlanDurability -> #("sthāyitā-yojanā", "स्थायिता-योजना")
  }
}

fn from_aspect(a: Aspect) -> Concept {
  let #(iast, dev) = aspect_gloss(a)
  mk(
    "aspect:" <> aspect_key(a),
    aspects.name(a),
    iast,
    dev,
    Safety,
    0,
    [aspects.number(a)],
    "structure-plane",
    "17-aspect audit check #"
      <> int.to_string(aspects.number(a))
      <> ": "
      <> aspects.name(a)
      <> ".",
    ["17 Aspect audit"],
    "uos_tui/aspects.gleam:Aspect/check",
  )
}

fn aspect_concepts() -> List(Concept) {
  list.map(aspects.all, from_aspect)
}

// ---------------------------------------------------------------------------
// 4. STPA control actions (uos_swarm/stpa.model().control_actions) — id = "CA-...".
// ---------------------------------------------------------------------------

fn ca_gloss(name: String) -> #(String, String) {
  case name {
    "emit_intent" -> #("abhisandhi-utsarjana", "अभिसन्धि-उत्सर्जन")
    "push_confirm_screen" -> #("puṣṭi-paṭala-preṣaṇa", "पुष्टि-पटल-प्रेषण")
    "paint_frame" -> #("citrāṅkana", "चित्राङ्कन")
    "enter_raw" -> #("kaccā-praveśa", "कच्चा-प्रवेश")
    "restore_terminal" -> #("pravartaka-punaḥsthāpana", "प्रवर्तक-पुनःस्थापना")
    "audit_screen" -> #("paṭala-parīkṣā", "पटल-परीक्षा")
    "integrate_slice" -> #("khaṇḍa-saṃyojana", "खण्ड-संयोजन")
    "verify_slice" -> #("khaṇḍa-satyāpana", "खण्ड-सत्यापन")
    "write_owned_file" -> #("svāmitva-patra-lekhana", "स्वामित्व-पत्र-लेखन")
    other -> #(other, other)
  }
}

fn from_control_action(ca: stpa.ControlAction) -> Concept {
  let #(iast, dev) = ca_gloss(ca.name)
  mk(
    ca.id,
    ca.name,
    iast,
    dev,
    Safety,
    3,
    [],
    "control-plane",
    "STPA control action `"
      <> ca.name
      <> "` dispatched by "
      <> ca.controller
      <> ".",
    [],
    "uos_swarm/stpa.gleam:model/control_actions",
  )
}

fn control_action_concepts() -> List(Concept) {
  list.map(stpa.model().control_actions, from_control_action)
}

// ---------------------------------------------------------------------------
// 5. The seven muda (classical Toyota Production System wastes; board.muda_labels).
// ---------------------------------------------------------------------------

fn muda_concepts() -> List(Concept) {
  [
    mk(
      "Overproduction",
      "Overproduction",
      "atyutpādana",
      "अत्युत्पादन",
      Coordination,
      3,
      [],
      "control-plane",
      "Muda: producing more, sooner, or faster than the next station needs.",
      [],
      "uos_swarm/board.gleam:muda_labels; uos_swarm/tps.gleam:Muda",
    ),
    mk(
      "Waiting",
      "Waiting",
      "pratīkṣā",
      "प्रतीक्षा",
      Coordination,
      3,
      [],
      "control-plane",
      "Muda: idle time while a card sits blocked on another resource.",
      [],
      "uos_swarm/board.gleam:muda_labels; uos_swarm/tps.gleam:Muda",
    ),
    mk(
      "Transport",
      "Transport",
      "parivahana",
      "परिवहन",
      Coordination,
      3,
      [],
      "control-plane",
      "Muda: unnecessary movement of work or artifacts between agents.",
      [],
      "uos_swarm/board.gleam:muda_labels; uos_swarm/tps.gleam:Muda",
    ),
    mk(
      "Overprocessing",
      "Overprocessing",
      "atiprakriyā",
      "अतिप्रक्रिया",
      Coordination,
      3,
      [],
      "control-plane",
      "Muda: doing more work on a slice than the spec requires.",
      [],
      "uos_swarm/board.gleam:muda_labels; uos_swarm/tps.gleam:Muda",
    ),
    mk(
      "Inventory",
      "Inventory",
      "saṃgraha",
      "संग्रह",
      Coordination,
      3,
      [],
      "control-plane",
      "Muda: unclaimed or unmerged work piling up (WIP above takt capacity).",
      [],
      "uos_swarm/board.gleam:muda_labels; uos_swarm/tps.gleam:Muda",
    ),
    mk(
      "Motion",
      "Motion",
      "gati",
      "गति",
      Coordination,
      3,
      [],
      "control-plane",
      "Muda: unnecessary context switching or re-reading by an agent.",
      [],
      "uos_swarm/board.gleam:muda_labels; uos_swarm/tps.gleam:Muda",
    ),
    mk(
      "Defects",
      "Defects",
      "doṣa",
      "दोष",
      Coordination,
      3,
      [],
      "control-plane",
      "Muda: rework caused by a verification failure that should have been caught earlier.",
      [],
      "uos_swarm/board.gleam:muda_labels; uos_swarm/tps.gleam:Muda",
    ),
  ]
}

// ---------------------------------------------------------------------------
// 6. Board message kinds (uos_swarm/board.Kind) — id "kind:<Name>".
// ---------------------------------------------------------------------------

fn board_kind_concepts() -> List(Concept) {
  let row = fn(name: String, iast: String, dev: String, def: String) -> Concept {
    mk(
      "kind:" <> name,
      name,
      iast,
      dev,
      Messaging,
      3,
      [],
      "messaging-plane",
      def,
      [],
      "uos_swarm/board.gleam:Kind",
    )
  }
  [
    row("Plan", "yojanā", "योजना", "A broadcast plan for the swarm."),
    row("Dispatch", "preṣaṇa", "प्रेषण", "L0/L1 dispatch of work to an agent."),
    row(
      "Claim",
      "adhigrahaṇa",
      "अधिग्रहण",
      "An agent claims a task under a fenced lease.",
    ),
    row("Progress", "pragati", "प्रगति", "An in-flight progress update."),
    row("Question", "praśna", "प्रश्न", "A question posted to another agent."),
    row("Answer", "uttara", "उत्तर", "An answer to a Question."),
    row("Report", "vivaraṇa", "विवरण", "A worker's report of completed work."),
    row("Verdict", "nirṇaya", "निर्णय", "A verifier's admit/reject decision."),
    row("Andon", "sāvadhāna", "सावधान", "A line-status alert (yellow/red)."),
    row("Jidoka", "svayaṃ-nirodha", "स्वयं-निरोध", "A stop-the-line signal."),
    row(
      "Integrate",
      "saṃyojana",
      "संयोजन",
      "L0/L1 integration of a verified slice.",
    ),
    row("Heartbeat", "spandana", "स्पन्दन", "A freshness pulse from a live agent."),
    row(
      "Intent",
      "abhisandhi",
      "अभिसन्धि",
      "A declared intent, rank-strict (must target L0/L1).",
    ),
    row(
      "LeaseGrant",
      "paṭṭā-anujñā",
      "पट्टा-अनुज्ञा",
      "Grant of a fenced lease/epoch.",
    ),
    row("LeaseRelease", "paṭṭā-mukti", "पट्टा-मुक्ति", "Release of a held lease."),
    row("Ack", "svīkṛti", "स्वीकृति", "Acknowledgement of receipt/delivery."),
    row(
      "DeadLetter",
      "mṛta-patra",
      "मृत-पत्र",
      "A message retried past its limit and dead-lettered.",
    ),
  ]
}

// ---------------------------------------------------------------------------
// 7. ACL performatives (uos_swarm/acl.Performative) — id "perf:<Name>".
// ---------------------------------------------------------------------------

fn performative_concepts() -> List(Concept) {
  let row = fn(name: String, iast: String, dev: String, def: String) -> Concept {
    mk(
      "perf:" <> name,
      name,
      iast,
      dev,
      Language,
      3,
      [],
      "language-plane",
      def,
      [],
      "uos_swarm/acl.gleam:Performative/semantics_of",
    )
  }
  [
    row(
      "Inform",
      "sūcanā",
      "सूचना",
      "B(s,φ) ∧ ¬B(s,K(r,φ)) ⇒ K(r,φ): the sender shares a belief the receiver did not know.",
    ),
    row(
      "Request",
      "prārthanā",
      "प्रार्थना",
      "Requests the receiver to accept or reject doing an action.",
    ),
    row(
      "Propose",
      "prastāva",
      "प्रस्ताव",
      "Proposes a feasible action for the receiver to accept or reject.",
    ),
    row(
      "Accept",
      "svīkāra",
      "स्वीकार",
      "Accepts a prior Request/Propose; the speaker now intends to act.",
    ),
    row(
      "Reject",
      "nirākaraṇa",
      "निराकरण",
      "Rejects a prior Request/Propose, with a reason.",
    ),
    row(
      "Query",
      "praśna",
      "प्रश्न",
      "Asks the receiver to Inform on a proposition.",
    ),
    row(
      "Confirm",
      "puṣṭi",
      "पुष्टि",
      "Confirms a belief the receiver was uncertain of.",
    ),
    row(
      "Commit",
      "saṅkalpa",
      "सङ्कल्प",
      "Commits the speaker to completing an action by a deadline.",
    ),
    row(
      "Assert",
      "pratijñā",
      "प्रतिज्ञा",
      "Asserts a known proposition into the shared ledger.",
    ),
    row(
      "Retract",
      "pratyāhāra",
      "प्रत्याहार",
      "Withdraws a previously asserted proposition.",
    ),
    row(
      "Hypothesize",
      "kalpanā",
      "कल्पना",
      "Offers an unproven proposition for testing (the dream module's output).",
    ),
    row(
      "Andon",
      "sāvadhāna",
      "सावधान",
      "Raises a hazard; forces a decide obligation and a yellow/red line state.",
    ),
  ]
}

// ---------------------------------------------------------------------------
// 8. OODA modes (uos_swarm/ooda.Mode) and phases (Observe/Orient/Decide/Act).
// ---------------------------------------------------------------------------

fn ooda_concepts() -> List(Concept) {
  let mode = fn(name: String, iast: String, dev: String, def: String) -> Concept {
    mk(
      "ooda-mode:" <> name,
      name,
      iast,
      dev,
      Intelligence,
      5,
      [],
      "intelligence-plane",
      def,
      [],
      "uos_swarm/ooda.gleam:Mode",
    )
  }
  let phase = fn(name: String, iast: String, dev: String, def: String) -> Concept {
    mk(
      "ooda-phase:" <> name,
      name,
      iast,
      dev,
      Intelligence,
      5,
      [],
      "intelligence-plane",
      def,
      [],
      "uos_swarm/ooda.gleam:step",
    )
  }
  [
    mode(
      "Dark",
      "andhakāra",
      "अन्धकार",
      "Cockpit mode: minimum draw, only heartbeats.",
    ),
    mode("Dim", "manda", "मन्द", "Cockpit mode: low draw, occasional repaint."),
    mode(
      "Normal",
      "sāmānya",
      "सामान्य",
      "Cockpit mode: steady-state repaint cadence.",
    ),
    mode(
      "Bright",
      "prakāśa",
      "प्रकाश",
      "Cockpit mode: elevated cadence plus an aspect audit.",
    ),
    mode(
      "Emergency",
      "āpad",
      "आपद्",
      "Cockpit mode: halt admission, raise Andon, repaint every cycle.",
    ),
    phase(
      "observe",
      "avalokana",
      "अवलोकन",
      "OODA: gather the observation window (manas).",
    ),
    phase(
      "orient",
      "vicāra",
      "विचार",
      "OODA: weigh the observation against the trend.",
    ),
    phase(
      "decide",
      "nirṇaya",
      "निर्णय",
      "OODA: choose the mode and actions (buddhi).",
    ),
    phase("act", "kriyā", "क्रिया", "OODA: emit the chosen actions for this cycle."),
  ]
}

// ---------------------------------------------------------------------------
// 9. TPS terms (uos_swarm/tps.gleam): WIP, takt, jidoka, andon, kanban columns.
// ---------------------------------------------------------------------------

fn tps_concepts() -> List(Concept) {
  let kanban = fn(name: String, iast: String, dev: String, def: String) -> Concept {
    mk(
      "kanban:" <> name,
      name,
      iast,
      dev,
      Coordination,
      3,
      [],
      "control-plane",
      def,
      [],
      "uos_swarm/tps.gleam:Column",
    )
  }
  [
    mk(
      "wip-limit",
      "WIP limit",
      "kārya-sīmā",
      "कार्य-सीमा",
      Coordination,
      3,
      [],
      "control-plane",
      "The maximum number of cards a swarm may hold In Progress at once.",
      [],
      "uos_swarm/tps.gleam:Board.wip_limit",
    ),
    mk(
      "takt-time",
      "Takt time",
      "gati-kāla",
      "गति-काल",
      Coordination,
      3,
      [],
      "control-plane",
      "The target minutes per card that keeps the swarm at customer pace.",
      [],
      "uos_swarm/tps.gleam:Board.takt_minutes",
    ),
    mk(
      "jidoka",
      "Jidoka (stop-the-line)",
      "svayaṃ-nirodha",
      "स्वयं-निरोध",
      Coordination,
      3,
      [],
      "control-plane",
      "Autonomation: stop the line the instant a defect is detected, rather than pass it on.",
      ["kind:Jidoka"],
      "uos_swarm/tps.gleam:Board.jidoka_stops/line_stopped",
    ),
    mk(
      "andon-signal",
      "Andon signal",
      "sāvadhāna-saṅketa",
      "सावधान-सङ्केत",
      Coordination,
      3,
      [],
      "control-plane",
      "Green/Yellow/Red line-status signal raised by a card in trouble.",
      ["kind:Andon"],
      "uos_swarm/tps.gleam:Andon",
    ),
    kanban(
      "Planned",
      "yojita",
      "योजित",
      "Kanban column: queued, not yet started.",
    ),
    kanban(
      "Running",
      "pravartamāna",
      "प्रवर्तमान",
      "Kanban column: actively being worked.",
    ),
    kanban(
      "Verifying",
      "parīkṣyamāṇa",
      "परीक्ष्यमाण",
      "Kanban column: submitted, awaiting verification.",
    ),
    kanban("Done", "siddha", "सिद्ध", "Kanban column: verified and accepted."),
    kanban(
      "Failed",
      "viphala",
      "विफल",
      "Kanban column: verification failed, awaiting rework.",
    ),
  ]
}

// ---------------------------------------------------------------------------
// 10. Coordination terms (uos_swarm/coord.gleam, uos_swarm/board.gleam).
// ---------------------------------------------------------------------------

fn coordination_concepts() -> List(Concept) {
  [
    mk(
      "lease",
      "Lease",
      "paṭṭā",
      "पट्टा",
      Coordination,
      3,
      [],
      "control-plane",
      "A fenced, time-bounded hold on a resource with a monotonically increasing epoch.",
      ["leases"],
      "uos_swarm/coord.gleam:Lease/acquire",
    ),
    mk(
      "epoch",
      "Epoch (fencing token)",
      "yuga",
      "युग",
      Coordination,
      3,
      [],
      "control-plane",
      "The monotonically increasing token that fences a lease against a stale holder.",
      ["lease"],
      "uos_swarm/coord.gleam:Lease.epoch",
    ),
    mk(
      "claim",
      "Claim",
      "adhigrahaṇa",
      "अधिग्रहण",
      Coordination,
      3,
      [],
      "control-plane",
      "A lease on `task:<id>` subject to the swarm's WIP limit.",
      ["lease", "wip-limit"],
      "uos_swarm/coord.gleam:claim",
    ),
    mk(
      "heartbeat",
      "Heartbeat",
      "spandana",
      "स्पन्दन",
      Coordination,
      3,
      [],
      "control-plane",
      "A periodic freshness pulse; its absence trips the dead-man's-switch.",
      ["heartbeats"],
      "uos_swarm/coord.gleam:beat/stale; uos_swarm/board.gleam:Heartbeat kind",
    ),
    mk(
      "reconcile",
      "Reconcile",
      "samanvaya",
      "समन्वय",
      Coordination,
      3,
      [],
      "control-plane",
      "Merge a remote view of the board into the local one; a differing prior digest is a conflict, quarantined by refusal.",
      ["coord"],
      "uos_swarm/coord.gleam:reconcile",
    ),
    mk(
      "causal-gap",
      "Causal gap",
      "kāraṇa-antara",
      "कारण-अन्तर",
      Coordination,
      3,
      [],
      "control-plane",
      "An explicit record documenting a reply target that is provably lost, so it never has to be forged or recreated.",
      [],
      "uos_swarm/board.gleam:causal_gaps",
    ),
    mk(
      "outbox",
      "Transactional outbox",
      "nirgama-peṭikā",
      "निर्गम-पेटिका",
      Coordination,
      3,
      [],
      "control-plane",
      "Durable ledger acceptance gates publication: a message is Outboxed before any Zenoh put is attempted.",
      [],
      "uos_swarm/board.gleam:deliver/delivery_state",
    ),
    mk(
      "per-sender-chain",
      "Per-sender digest chain",
      "preṣaka-śṛṅkhalā",
      "प्रेषक-शृङ्खला",
      Coordination,
      3,
      [],
      "control-plane",
      "One SHA-256 hash chain per sender (multi-writer safe), ordered by id within the sender.",
      ["signature"],
      "uos_swarm/board.gleam:validate (per-sender chain check)",
    ),
    mk(
      "signature",
      "Signature",
      "hastākṣara",
      "हस्ताक्षर",
      Coordination,
      3,
      [],
      "control-plane",
      "An HMAC over the message digest with a per-agent derived key; a shared master key never signs directly.",
      [],
      "uos_swarm/board.gleam:sign_with_agent_key/agent_key",
    ),
  ]
}

// ---------------------------------------------------------------------------
// 11. Governance terms (uos_swarm/coord.gleam design authority; system_audit two-key gate).
// ---------------------------------------------------------------------------

fn governance_concepts() -> List(Concept) {
  [
    mk(
      "design-authority",
      "Design authority",
      "adhiṣṭhātṛ",
      "अधिष्ठातृ",
      Governance,
      0,
      [],
      "control-plane",
      "Design decisions (Plan/Dispatch/Integrate/Andon broadcasts) come only from the design authority model roster.",
      ["supervisor"],
      "uos_swarm/coord.gleam:Policy.design_models/authorize (DesignAuthorityRequired)",
    ),
    mk(
      "rank-strict-intent",
      "Rank-strict intent",
      "śreṇī-niyata-saṅkalpa",
      "श्रेणी-नियत-सङ्कल्प",
      Governance,
      3,
      [],
      "control-plane",
      "An Intent message must target a strictly higher-ranked layer than its sender.",
      ["kind:Intent"],
      "uos_swarm/coord.gleam:authorize (IntentMustGoUpward)",
    ),
    mk(
      "sovereign-review",
      "Sovereign review",
      "sārvabhauma-parīkṣā",
      "सार्वभौम-परीक्षा",
      Governance,
      0,
      [],
      "structure-plane",
      "Tri-sovereign multi-agent review consensus (Antigravity/AGY, Claude, Codex) verified and ratified.",
      [],
      "uos_swarm/cockpit.gleam:CHK-17-SOV",
    ),
    mk(
      "two-key-verification",
      "Two-key verification",
      "dvi-kuñcikā-satyāpana",
      "द्वि-कुञ्चिका-सत्यापन",
      Governance,
      0,
      [],
      "structure-plane",
      "Trust requires BOTH fresh observed runtime behaviour AND a machine-verifiable formal specification.",
      ["admissible"],
      "uos_swarm/system_audit.gleam:admissible (strict two-key admission)",
    ),
    mk(
      "quarantine",
      "Quarantine",
      "saṅgarodha",
      "सङ्गरोध",
      Governance,
      0,
      [],
      "data-plane",
      "A malformed or refused artifact is preserved verbatim for inspection, never dropped and never silently absorbed.",
      [],
      "uos_swarm/board.gleam:quarantined/open (<ledger>.quarantine.jsonl)",
    ),
  ]
}

// ---------------------------------------------------------------------------
// 12. Agent kernel terms (uos_swarm/agent_runtime.gleam): memory namespaces, grant,
//     capability, F´ lifecycle states, Rete, Bayes.
// ---------------------------------------------------------------------------

fn agent_kernel_concepts() -> List(Concept) {
  let lifecycle = fn(name: String, iast: String, dev: String, def: String) -> Concept {
    mk(
      "lifecycle:" <> name,
      name,
      iast,
      dev,
      Intelligence,
      4,
      [],
      "intelligence-plane",
      def,
      [],
      "uos_swarm/agent_runtime.gleam:State/state_label",
    )
  }
  [
    mk(
      "memory:working",
      "Working memory",
      "kārya-smṛti",
      "कार्य-स्मृति",
      Intelligence,
      4,
      [],
      "data-plane",
      "Namespace `working/`: scratch memory for the task in flight.",
      ["ets"],
      "uos_swarm/agent_runtime.gleam:Memory (working/)",
    ),
    mk(
      "memory:episodic",
      "Episodic memory",
      "prasaṅga-smṛti",
      "प्रसङ्ग-स्मृति",
      Intelligence,
      4,
      [],
      "data-plane",
      "Namespace `episodic/<id>`: a remembered board message.",
      ["ets"],
      "uos_swarm/agent_runtime.gleam:remember (episodic/)",
    ),
    mk(
      "memory:belief",
      "Belief memory",
      "matam",
      "मतम्",
      Intelligence,
      4,
      [],
      "data-plane",
      "Namespace `belief/`: doxastic state the agent holds but has not asserted.",
      ["ets"],
      "uos_swarm/agent_runtime.gleam:Memory (belief/)",
    ),
    mk(
      "memory:goal",
      "Goal memory",
      "lakṣya",
      "लक्ष्य",
      Intelligence,
      4,
      [],
      "data-plane",
      "Namespace `goal/`: the agent's current objectives.",
      ["ets"],
      "uos_swarm/agent_runtime.gleam:Memory (goal/)",
    ),
    mk(
      "grant",
      "Grant",
      "anujñā",
      "अनुज्ञा",
      Intelligence,
      4,
      [],
      "intelligence-plane",
      "A scoped, expiring, opaque capability token minted only by L0/L1 and tracked as a board message.",
      ["capability"],
      "uos_swarm/agent_runtime.gleam:grant/Grant",
    ),
    mk(
      "capability",
      "Capability",
      "sāmarthya",
      "सामर्थ्य",
      Intelligence,
      4,
      [],
      "intelligence-plane",
      "A default-deny permission class (Memory, Rete, Bayes, Zenoh, Lean, Quint, STM) gated by a live grant.",
      ["grant"],
      "uos_swarm/agent_runtime.gleam:Capability/capability_label",
    ),
    lifecycle(
      "Idle",
      "niṣkriya",
      "निष्क्रिय",
      "F´ lifecycle: unclaimed, no lease held.",
    ),
    lifecycle(
      "Claimed",
      "gṛhīta",
      "गृहीत",
      "F´ lifecycle: claimed under a lease, not yet started.",
    ),
    lifecycle(
      "Working",
      "kāryarata",
      "कार्यरत",
      "F´ lifecycle: actively being worked.",
    ),
    lifecycle(
      "Verifying",
      "parīkṣyamāṇa",
      "परीक्ष्यमाण",
      "F´ lifecycle: submitted, awaiting verification.",
    ),
    lifecycle("Done", "siddha", "सिद्ध", "F´ lifecycle: verified and accepted."),
    lifecycle("Failed", "viphala", "विफल", "F´ lifecycle: verification failed."),
    mk(
      "rete",
      "Rete (rule matcher)",
      "niyama",
      "नियम",
      Intelligence,
      4,
      [],
      "intelligence-plane",
      "Bounded forward-chaining matcher over typed facts (naive unification, not a full Rete network).",
      ["pramana:anumana"],
      "uos_swarm/agent_runtime.gleam:Fact/Pattern (ReteCap)",
    ),
    mk(
      "bayes",
      "Bayes (Beta-Binomial belief)",
      "sambhāvanā",
      "सम्भावना",
      Intelligence,
      4,
      [],
      "intelligence-plane",
      "Bayesian (Beta-Binomial) success belief per (agent, model), used for cheapest-adequate routing.",
      ["pramana:anumana"],
      "uos_swarm/agent_runtime.gleam:BayesCap",
    ),
  ]
}

// ---------------------------------------------------------------------------
// 13. Review / admission terms (uos_tui/aspects.Verdict, admissible/no_failures).
// ---------------------------------------------------------------------------

fn review_concepts() -> List(Concept) {
  let verdict = fn(name: String, iast: String, dev: String, def: String) -> Concept {
    mk(
      "verdict:" <> name,
      name,
      iast,
      dev,
      Review,
      0,
      [],
      "structure-plane",
      def,
      [],
      "uos_tui/aspects.gleam:Verdict",
    )
  }
  [
    verdict("Pass", "siddha", "सिद्ध", "Freshly, positively evidenced."),
    verdict(
      "Declared",
      "ghoṣita",
      "घोषित",
      "Bound by declaration/config, not fresh observed behaviour.",
    ),
    verdict(
      "Fail",
      "viphala",
      "विफल",
      "Not positively evidenced; fail-closed default.",
    ),
    mk(
      "admissible",
      "Admissible",
      "svīkārya",
      "स्वीकार्य",
      Review,
      0,
      [],
      "structure-plane",
      "Strict two-key admission: zero Fail AND zero Declared findings.",
      ["verdict:Pass"],
      "uos_tui/aspects.gleam:admissible; uos_swarm/system_audit.gleam:admissible",
    ),
    mk(
      "no-failures",
      "No-failures gate",
      "aviphala",
      "अविफल",
      Review,
      0,
      [],
      "structure-plane",
      "The softer gate: zero Fail findings, Declared tolerated (used for jidoka stop/resume).",
      ["verdict:Fail"],
      "uos_tui/aspects.gleam:no_failures",
    ),
    mk(
      "hold",
      "Hold",
      "avarodha",
      "अवरोध",
      Review,
      0,
      [],
      "control-plane",
      "The line-stopped state entered by jidoka when no_failures fails, pending a fix and sovereign review.",
      ["no-failures", "jidoka"],
      "uos_swarm/tps.gleam:Board.line_stopped",
    ),
    mk(
      "guna",
      "Guṇa (the three qualities)",
      "guṇa",
      "गुण",
      Review,
      8,
      [],
      "structure-plane",
      "Sāṃkhya's three qualities, used here as a state classification for system health: sattva, rajas, tamas.",
      ["guna:sattva", "guna:rajas", "guna:tamas"],
      "uos_swarm/system_ontology.gleam (state-classification mapping)",
    ),
    mk(
      "guna:sattva",
      "Sattva (clarity)",
      "sattva",
      "सत्त्व",
      Review,
      8,
      [],
      "structure-plane",
      "Clear, balanced quality; maps onto a subject with zero Fail and zero Declared findings.",
      ["admissible"],
      "uos_tui/aspects.gleam:admissible",
    ),
    mk(
      "guna:rajas",
      "Rajas (activity)",
      "rajas",
      "रजस्",
      Review,
      8,
      [],
      "structure-plane",
      "Active, restless quality; maps onto churn — high Progress/Dispatch traffic on the board.",
      ["kind:Progress"],
      "uos_swarm/board.gleam:Progress kind",
    ),
    mk(
      "guna:tamas",
      "Tamas (inertia)",
      "tamas",
      "तमस्",
      Review,
      8,
      [],
      "structure-plane",
      "Dull, inert quality; maps onto a stale subject — no heartbeat, Dark OODA mode.",
      ["ooda-mode:Dark"],
      "uos_swarm/ooda.gleam:Dark mode",
    ),
  ]
}

// ---------------------------------------------------------------------------
// 14. Economy terms (uos_swarm/openrouter_worker.gleam tier/budget/price ceiling; the global
//     intelligence-routing rule's R0..R6 classes).
// ---------------------------------------------------------------------------

fn economy_concepts() -> List(Concept) {
  let routing = fn(
    n: String,
    label: String,
    iast: String,
    dev: String,
    def: String,
  ) -> Concept {
    mk(
      "routing-class:" <> n,
      n <> " " <> label,
      iast,
      dev,
      Economy,
      6,
      [],
      "intelligence-plane",
      def,
      [],
      "contracts/rules/intelligence-routing-rule.md (SC-INTEL-ROUTING-001)",
    )
  }
  [
    mk(
      "tier",
      "Tier",
      "śreṇī",
      "श्रेणी",
      Economy,
      6,
      [],
      "intelligence-plane",
      "Free or Paid classification of an allowlisted advisory model.",
      [],
      "uos_swarm/openrouter_worker.gleam:Tier",
    ),
    routing(
      "R0",
      "deterministic code",
      "śūnya-śreṇī",
      "शून्य-श्रेणी",
      "Runtime control: deterministic code, 0 tokens.",
    ),
    routing(
      "R1",
      "mechanical verification",
      "prathama-śreṇī",
      "प्रथम-श्रेणी",
      "Mechanical verification: script, else Haiku.",
    ),
    routing(
      "R2",
      "docs/summaries",
      "dvitīya-śreṇī",
      "द्वितीय-श्रेणी",
      "Docs/summaries: Haiku or OpenRouter nano.",
    ),
    routing(
      "R3",
      "advisory second opinion",
      "tṛtīya-śreṇī",
      "तृतीय-श्रेणी",
      "Advisory second opinion: free-first bounded OpenRouter.",
    ),
    routing(
      "R4",
      "bounded implementation",
      "caturtha-śreṇī",
      "चतुर्थ-श्रेणी",
      "Bounded implementation: Sonnet.",
    ),
    routing(
      "R5",
      "sovereign review",
      "pañcama-śreṇī",
      "पञ्चम-श्रेणी",
      "Sovereign security/architecture review: Codex Astra and Antigravity.",
    ),
    routing(
      "R6",
      "design authority",
      "ṣaṣṭha-śreṇī",
      "षष्ठ-श्रेणी",
      "Design authority, integration, admission: Fable only.",
    ),
    mk(
      "budget",
      "Budget",
      "vyaya-sīmā",
      "व्यय-सीमा",
      Economy,
      6,
      [],
      "intelligence-plane",
      "The USD ceiling an advisory call may not exceed (default 0.02 USD).",
      [],
      "uos_swarm/openrouter_worker.gleam:budget_usd_ceiling/Policy.budget_usd",
    ),
    mk(
      "price-ceiling",
      "Price ceiling",
      "mūlya-sīmā",
      "मूल्य-सीमा",
      Economy,
      6,
      [],
      "intelligence-plane",
      "The highest per-token price (USD) accepted for an allowlisted model.",
      ["budget"],
      "uos_swarm/openrouter_worker.gleam:Allowed.prompt_ceiling/completion_ceiling",
    ),
    mk(
      "free-first",
      "Free-first",
      "prathamataḥ-niḥśulka",
      "प्रथमतः-निःशुल्क",
      Economy,
      6,
      [],
      "intelligence-plane",
      "Free tiers are tried before any paid model; free-only is the default policy.",
      ["tier"],
      "uos_swarm/openrouter_worker.gleam:default_policy (free_only = True)",
    ),
  ]
}

// ---------------------------------------------------------------------------
// 15. Hindu thinking structures: antaḥkaraṇa and its four parts, the four pramāṇa.
// ---------------------------------------------------------------------------

fn hindu_thinking_concepts() -> List(Concept) {
  [
    mk(
      "antahkarana",
      "Antaḥkaraṇa (inner instrument)",
      "antaḥkaraṇa",
      "अन्तःकरण",
      Thinking,
      5,
      [],
      "intelligence-plane",
      "The fourfold inner instrument of cognition; maps onto the agent's cognitive stack end to end.",
      [
        "antahkarana:manas", "antahkarana:buddhi", "antahkarana:ahamkara",
        "antahkarana:citta",
      ],
      "uos_swarm/system_ontology.gleam (Hindu thinking-structure mapping)",
    ),
    mk(
      "antahkarana:manas",
      "Manas (sensing mind)",
      "manas",
      "मनस्",
      Thinking,
      5,
      [],
      "intelligence-plane",
      "Manas gathers and filters sense-data; maps onto the OODA Observe phase.",
      ["ooda-phase:observe"],
      "uos_swarm/ooda.gleam:step (Observe)",
    ),
    mk(
      "antahkarana:buddhi",
      "Buddhi (discerning intellect)",
      "buddhi",
      "बुद्धि",
      Thinking,
      5,
      [],
      "intelligence-plane",
      "Buddhi discriminates and decides; maps onto the OODA Decide phase and manager.step's control decision. The intelligence plane's own Sanskrit name is buddhi-tala.",
      ["ooda-phase:decide"],
      "uos_swarm/manager.gleam:step (Decide); holon.gleam Intelligence plane = buddhi-tala",
    ),
    mk(
      "antahkarana:ahamkara",
      "Ahaṃkāra (I-maker, self-model)",
      "ahaṃkāra",
      "अहंकार",
      Thinking,
      5,
      [],
      "intelligence-plane",
      "Ahaṃkāra is the sense of 'I'; maps onto the agent's self-model as posted on the board (Agent id/layer/model).",
      [],
      "uos_swarm/board.gleam:Agent (self-model on the board)",
    ),
    mk(
      "antahkarana:citta",
      "Citta (mind-stuff, memory store)",
      "citta",
      "चित्त",
      Memory,
      5,
      [],
      "data-plane",
      "Citta is the substrate that retains impressions; maps onto the agent's ETS live memory table.",
      ["ets"],
      "uos_swarm/agent_runtime.gleam:Memory; holon.gleam ets = smṛti",
    ),
    mk(
      "pramana",
      "Pramāṇa (valid means of knowledge)",
      "pramāṇa",
      "प्रमाण",
      Thinking,
      5,
      [],
      "intelligence-plane",
      "The four accepted means of valid cognition; maps onto the system's evidence sources for two-key verification.",
      [
        "pramana:pratyaksa", "pramana:anumana", "pramana:sabda",
        "pramana:upamana",
      ],
      "uos_swarm/system_ontology.gleam (epistemology mapping); DMC-TCM two-key verification",
    ),
    mk(
      "pramana:pratyaksa",
      "Pratyakṣa (perception)",
      "pratyakṣa",
      "प्रत्यक्ष",
      Thinking,
      5,
      [],
      "intelligence-plane",
      "Direct perception; maps onto observed runtime behaviour, the first key of two-key verification.",
      ["two-key-verification"],
      "DMC-TCM mandate: Fresh Empirical Behavior key",
    ),
    mk(
      "pramana:anumana",
      "Anumāna (inference)",
      "anumāna",
      "अनुमान",
      Thinking,
      5,
      [],
      "intelligence-plane",
      "Inference from evidence; maps onto Rete forward-chaining rules and Bayesian belief updates.",
      ["rete", "bayes"],
      "uos_swarm/agent_runtime.gleam:ReteCap/BayesCap",
    ),
    mk(
      "pramana:sabda",
      "Śabda (testimony)",
      "śabda",
      "शब्द",
      Thinking,
      5,
      [],
      "intelligence-plane",
      "Verbal testimony from a trusted source; maps onto board Report messages and sovereign reviews.",
      ["kind:Report", "sovereign-review"],
      "uos_swarm/board.gleam:Report kind; sovereign review",
    ),
    mk(
      "pramana:upamana",
      "Upamāna (comparison)",
      "upamāna",
      "उपमान",
      Thinking,
      5,
      [],
      "intelligence-plane",
      "Knowledge by comparison/analogy; maps onto differential oracles and the 17-aspect audit.",
      ["17 Aspect audit"],
      "uos_swarm/system_audit.gleam:Subject (audits); Hermes differential oracles",
    ),
  ]
}

// ---------------------------------------------------------------------------
// 16. The five citta-vṛtti (Yoga Sūtra 1.6) as memory/cognitive states.
// ---------------------------------------------------------------------------

fn citta_vrtti_concepts() -> List(Concept) {
  [
    mk(
      "citta-vrtti",
      "Citta-vṛtti (modifications of mind-stuff)",
      "citta-vṛtti",
      "चित्त-वृत्ति",
      Memory,
      5,
      [],
      "data-plane",
      "The five fluctuations of mind-stuff (Yoga Sūtra 1.6); maps onto the agent's cognitive/memory states.",
      [
        "citta-vrtti:pramana", "citta-vrtti:viparyaya", "citta-vrtti:vikalpa",
        "citta-vrtti:nidra", "citta-vrtti:smrti",
      ],
      "Yoga Sūtra 1.6; uos_swarm/agent_runtime.gleam:Memory",
    ),
    mk(
      "citta-vrtti:pramana",
      "Pramāṇa (valid cognition)",
      "pramāṇa",
      "प्रमाण",
      Memory,
      5,
      [],
      "data-plane",
      "Valid cognition grounded in perception/inference/testimony; maps onto a verified, Pass-admitted evidence state.",
      ["verdict:Pass"],
      "Yoga Sūtra 1.6; DMC-TCM evidence states",
    ),
    mk(
      "citta-vrtti:viparyaya",
      "Viparyaya (error, misconception)",
      "viparyaya",
      "विपर्यय",
      Memory,
      5,
      [],
      "data-plane",
      "False cognition; maps onto a Fail verdict.",
      ["verdict:Fail"],
      "Yoga Sūtra 1.6; uos_tui/aspects.gleam:Fail",
    ),
    mk(
      "citta-vrtti:vikalpa",
      "Vikalpa (imagination, conceptualisation)",
      "vikalpa",
      "विकल्प",
      Memory,
      5,
      [],
      "data-plane",
      "Cognition built from words/imagination without a directly grounded object; maps onto the dream module's speculative output posted as a Hypothesize.",
      ["perf:Hypothesize"],
      "Yoga Sūtra 1.6; uos_swarm/acl.gleam:Hypothesize (dream output)",
    ),
    mk(
      "citta-vrtti:nidra",
      "Nidrā (sleep)",
      "nidrā",
      "निद्रा",
      Memory,
      5,
      [],
      "data-plane",
      "The vṛtti of contentless sleep; maps onto an agent's Idle lifecycle line.",
      ["lifecycle:Idle"],
      "Yoga Sūtra 1.6; uos_swarm/agent_runtime.gleam:Idle",
    ),
    mk(
      "citta-vrtti:smrti",
      "Smṛti (memory)",
      "smṛti",
      "स्मृति",
      Memory,
      5,
      [],
      "data-plane",
      "Retention of past experience; maps onto the ETS live table and the episodic memory namespace.",
      ["ets", "memory:episodic"],
      "holon.gleam:ets = smṛti; uos_swarm/agent_runtime.gleam:remember",
    ),
  ]
}

// ---------------------------------------------------------------------------
// 17. The five kośa (Taittirīya Upaniṣad 2) as the system's layers, hardware to harmony.
// ---------------------------------------------------------------------------

fn kosha_concepts() -> List(Concept) {
  [
    mk(
      "kosha",
      "Pañca-kośa (the five sheaths)",
      "pañca-kośa",
      "पञ्च-कोश",
      Structure,
      5,
      [],
      "structure-plane",
      "The five sheaths from gross to subtle; maps onto the system's layers from hardware to admitted harmony.",
      [
        "kosha:annamaya", "kosha:pranamaya", "kosha:manomaya",
        "kosha:vijnanamaya", "kosha:anandamaya",
      ],
      "Taittirīya Upaniṣad 2; uos_swarm/system_ontology.gleam (layer mapping)",
    ),
    mk(
      "kosha:annamaya",
      "Annamaya-kośa (matter sheath)",
      "annamaya",
      "अन्नमय",
      Structure,
      1,
      [1],
      "structure-plane",
      "The gross material sheath; maps onto the hardware substrate and the BEAM VM it runs on.",
      ["aspect:SubstrateStorageSafety"],
      "uos_tui/aspects.gleam:SubstrateStorageSafety",
    ),
    mk(
      "kosha:pranamaya",
      "Prāṇamaya-kośa (vital-breath sheath)",
      "prāṇamaya",
      "प्राणमय",
      Structure,
      4,
      [4],
      "runtime-plane",
      "The sheath of vital energy; maps onto running BEAM processes and the OTP supervisor.",
      ["aspect:GleamOtpSupervisor"],
      "uos_tui/aspects.gleam:GleamOtpSupervisor",
    ),
    mk(
      "kosha:manomaya",
      "Manomaya-kośa (mind sheath)",
      "manomaya",
      "मनोमय",
      Structure,
      5,
      [],
      "intelligence-plane",
      "The sheath of mind; maps onto the agents themselves and their OODA loops.",
      ["ooda"],
      "uos_swarm/ooda.gleam (agent mind loop)",
    ),
    mk(
      "kosha:vijnanamaya",
      "Vijñānamaya-kośa (discernment sheath)",
      "vijñānamaya",
      "विज्ञानमय",
      Structure,
      0,
      [],
      "structure-plane",
      "The sheath of discerning knowledge; maps onto formal verification and the 17-aspect audit.",
      ["17 Aspect audit"],
      "uos_tui/aspects.gleam (verification)",
    ),
    mk(
      "kosha:anandamaya",
      "Ānandamaya-kośa (bliss sheath)",
      "ānandamaya",
      "आनन्दमय",
      Structure,
      9,
      [],
      "structure-plane",
      "The innermost sheath of bliss/harmony; maps onto the final `admitted` evidence state where discovered -> ... -> admitted closes without residue.",
      [],
      "CLAUDE.md Section 6: Evidence, Gates, and Completion Semantics (admitted)",
    ),
  ]
}

// ---------------------------------------------------------------------------
// 18. Music anchors used by the music module (definitions only; not imported to avoid
//     coupling to a module owned by another worker).
// ---------------------------------------------------------------------------

fn music_concepts() -> List(Concept) {
  [
    mk(
      "swara",
      "Svara (musical note)",
      "svara",
      "स्वर",
      Music,
      2,
      [],
      "runtime-plane",
      "The seven svara (sa ri ga ma pa dha ni), the base pitches used by the music module.",
      [],
      "music domain (definitions only; out of this worker's owned scope)",
    ),
    mk(
      "thaat",
      "Thāṭ (parent scale)",
      "thāṭ",
      "थाट",
      Music,
      2,
      [],
      "runtime-plane",
      "A parent scale (one of the 10 Hindustani thāṭ) from which rāga are derived.",
      ["raga"],
      "music domain (definitions only; out of this worker's owned scope)",
    ),
    mk(
      "raga",
      "Rāga (melodic framework)",
      "rāga",
      "राग",
      Music,
      2,
      [],
      "runtime-plane",
      "A melodic framework of specific notes, phrases and mood used by the music module.",
      ["swara", "thaat"],
      "music domain (definitions only; out of this worker's owned scope)",
    ),
    mk(
      "tala",
      "Tāla (rhythmic cycle)",
      "tāla",
      "ताल",
      Music,
      2,
      [],
      "runtime-plane",
      "A cyclic rhythmic pattern counted in beats (mātrā), used by the music module.",
      [],
      "music domain (definitions only; out of this worker's owned scope)",
    ),
  ]
}

// ---------------------------------------------------------------------------
// 19. Jujutsu (VCS) ontology: the standalone, non-colocated Jujutsu discipline (CLAUDE.md §4
//     Version Control Discipline) — identity/content, working copy/operations, bookmarks and
//     workspaces, editing verbs, and the integration/main-move rules this repo enforces.
//     Operator directive (verbatim): "create jujutsu ontology".
// ---------------------------------------------------------------------------

const jj_source = "contracts: CLAUDE.md §4 Version Control Discipline; apps/README.md work streams; ADR-063"

fn jj(
  id: String,
  english: String,
  iast: String,
  devanagari: String,
  layer: Int,
  aspects: List(Int),
  definition: String,
  relates: List(String),
) -> Concept {
  mk(
    "jj:" <> id,
    english,
    iast,
    devanagari,
    Vcs,
    layer,
    aspects,
    "structure-plane",
    definition,
    relates,
    jj_source,
  )
}

fn jj_concepts() -> List(Concept) {
  [
    jj(
      "change-id",
      "Change id",
      "parivartana-nāma",
      "परिवर्तन-नाम",
      2,
      [2],
      "The stable identity of an edit across rewrites (rebase/squash/split change its content but never its change id) — the primary handle a worker or reviewer names.",
      ["jj:commit-id", "jj:change-vs-commit", "jj:rebase"],
    ),
    jj(
      "commit-id",
      "Commit id",
      "sthāpita-sāra",
      "स्थापित-सार",
      2,
      [2],
      "The content hash of one specific snapshot of a change; every rewrite (rebase, squash, describe) produces a new commit id even though the change id is unchanged.",
      ["jj:change-id", "jj:change-vs-commit", "jj:immutable-commit"],
    ),
    jj(
      "working-copy",
      "Working copy",
      "kārya-pratilipi",
      "कार्य-प्रतिलिपि",
      2,
      [2],
      "The live checked-out files of a workspace, itself tracked as an ordinary (mutable) commit that jj auto-snapshots before every command.",
      ["jj:snapshot", "jj:workspace", "jj:stale-working-copy"],
    ),
    jj(
      "operation-log",
      "Operation log",
      "kriyā-lekha",
      "क्रिया-लेख",
      2,
      [2, 17],
      "The append-only ledger of every repository-mutating operation; the sole audit trail from which any prior state can be restored (BG 2.40: no effort is lost).",
      ["jj:op-restore", "jj:undo"],
    ),
    jj(
      "op-restore",
      "Operation restore",
      "kriyā-punaḥsthāpana",
      "क्रिया-पुनःस्थापना",
      2,
      [2, 17],
      "Restoring the repository to an exact prior operation-log entry (`jj op restore`) — whole-repository time-travel, distinct from undoing a single change.",
      ["jj:operation-log", "jj:undo"],
    ),
    jj(
      "undo",
      "Undo",
      "pratyāvartana",
      "प्रत्यावर्तन",
      2,
      [2, 17],
      "Reversing the most recent operation-log entry (`jj undo`); operations are always restored or undone, never hand-edited in place.",
      ["jj:operation-log", "jj:op-restore"],
    ),
    jj(
      "bookmark",
      "Bookmark",
      "saṅketa",
      "सङ्केत",
      2,
      [2],
      "A named, movable pointer to a change (Jujutsu's analogue of a Git branch); moved explicitly, never implicitly by commit.",
      ["jj:main-bookmark", "jj:integration-bookmark", "jj:revset"],
    ),
    jj(
      "main-bookmark",
      "Main bookmark",
      "mukhya-saṅketa",
      "मुख्य-सङ्केत",
      0,
      [2],
      "The `main` bookmark, left uncreated until final system admission (EV-15); until then work proceeds only on feature and `integration/*` bookmarks.",
      ["jj:bookmark", "jj:lease-gated-main-move"],
    ),
    jj(
      "integration-bookmark",
      "Integration bookmark",
      "saṃyojana-saṅketa",
      "संयोजन-सङ्केत",
      4,
      [2],
      "An `integration/*` bookmark (e.g. `integration/main`) where verified sibling-workspace slices are rebased in and serialized under a live lease.",
      ["jj:bookmark", "jj:linear-chain-integration", "jj:lease-gated-main-move"],
    ),
    jj(
      "workspace",
      "Workspace",
      "kārya-kṣetra",
      "कार्य-क्षेत्र",
      2,
      [2],
      "A checkout of the repository with its own working copy, sharing the same underlying `.jj/` operation log and store as its siblings.",
      ["jj:sibling-workspace", "jj:working-copy"],
    ),
    jj(
      "sibling-workspace",
      "Sibling workspace",
      "sahodara-kārya-kṣetra",
      "सहोदर-कार्य-क्षेत्र",
      2,
      [2],
      "One of the `.uos-workspaces/*` peer workspaces used for parallel work streams (e.g. this worker's `jj-2`); each owns a disjoint file scope (BG 3.35, svadharma).",
      ["jj:workspace"],
    ),
    jj(
      "stale-working-copy",
      "Stale working copy",
      "jīrṇa-kārya-pratilipi",
      "जीर्ण-कार्य-प्रतिलिपि",
      2,
      [2],
      "A workspace's working copy that no longer matches its recorded commit because another process wrote to the shared repository; readers avoid provoking it against a workspace they do not own (`--ignore-working-copy`).",
      ["jj:working-copy", "jj:sibling-workspace"],
    ),
    jj(
      "revset",
      "Revset",
      "parivartana-cayana",
      "परिवर्तन-चयन",
      2,
      [2],
      "A revset-language expression that selects a set of changes (by id, bookmark, ancestry, or predicate) for a command to act on.",
      ["jj:change-id", "jj:bookmark"],
    ),
    jj(
      "rebase",
      "Rebase",
      "punar-ādhāra",
      "पुनराधार",
      2,
      [2],
      "Replaying a change (and its descendants) onto a new parent, producing new commit ids while preserving change ids; the mechanism by which integration serializes worker changes in order.",
      ["jj:linear-chain-integration", "jj:conflict", "jj:change-id"],
    ),
    jj(
      "squash",
      "Squash",
      "saṅkoca",
      "सङ्कोच",
      2,
      [2],
      "Folding a change's content into its parent, contracting two commits into one while the parent's change id survives.",
      ["jj:change-id"],
    ),
    jj(
      "split",
      "Split",
      "vibhajana",
      "विभजन",
      2,
      [2],
      "Dividing one change into two or more successive changes, each with its own new change id.",
      ["jj:change-id"],
    ),
    jj(
      "abandon",
      "Abandon",
      "parityāga",
      "परित्याग",
      2,
      [2],
      "Discarding a change (and rebasing its descendants onto its parent); recorded in the operation log and reversible by undo, never a silent deletion.",
      ["jj:change-id", "jj:operation-log"],
    ),
    jj(
      "describe",
      "Describe",
      "varṇana",
      "वर्णन",
      2,
      [2],
      "Setting or editing a change's commit message without altering its file content; produces a new commit id under the same change id.",
      ["jj:change-id", "jj:commit-id"],
    ),
    jj(
      "new",
      "New",
      "navīna",
      "नवीन",
      2,
      [2],
      "Creating a new, empty working-copy change on top of one or more parents (`jj new`), the usual way work begins.",
      ["jj:change-id", "jj:working-copy"],
    ),
    jj(
      "conflict",
      "Conflict",
      "virodha",
      "विरोध",
      2,
      [2],
      "A first-class conflict state stored directly in the commit itself (never a special repository mode); a conflicted change can be rebased, described, and inspected like any other, and is resolved by editing the working copy.",
      ["jj:rebase", "jj:commit-id", "jj:linear-chain-integration"],
    ),
    jj(
      "immutable-commit",
      "Immutable commit",
      "acala-sthāpana",
      "अचल-स्थापन",
      2,
      [2, 17],
      "A commit past the configured immutable boundary (e.g. already integrated); jj refuses to rewrite it, protecting shared history from silent mutation.",
      ["jj:commit-id", "jj:standalone-repo"],
    ),
    jj(
      "snapshot",
      "Snapshot",
      "kṣaṇa-citra",
      "क्षण-चित्र",
      2,
      [2],
      "The automatic recording of the working copy's current file state into the working-copy commit before every command runs, so nothing typed is ever silently lost.",
      ["jj:working-copy"],
    ),
    jj(
      "standalone-repo",
      "Standalone repository",
      "svatantra-nikṣepa",
      "स्वतन्त्र-निक्षेप",
      0,
      [2],
      "A non-colocated `.jj/` repository with no backing `.git/` directory — the sole VCS mode admitted for UOS (CLAUDE.md §4).",
      ["jj:colocated-repo", "jj:native-git-mutation"],
    ),
    jj(
      "colocated-repo",
      "Colocated repository",
      "sahasthita-nikṣepa",
      "सहस्थित-निक्षेप",
      0,
      [2],
      "A `.jj/` repository backed by a sibling `.git/` directory; permitted by upstream Jujutsu but strictly barred inside `/home/an/NAS-setup/uos`.",
      ["jj:standalone-repo"],
    ),
    jj(
      "native-git-mutation",
      "Native git mutation",
      "prākṛta-git-vikāra",
      "प्राकृत-गिट्-विकार",
      0,
      [2],
      "Any direct Git-mutating command (`git commit`, `git push`, `git checkout`, etc.); strictly prohibited inside the standalone UOS repository regardless of tooling convenience.",
      ["jj:standalone-repo"],
    ),
    jj(
      "linear-chain-integration",
      "Linear-chain integration",
      "rekhā-śṛṅkhala-saṃyojana",
      "रेखा-शृङ्खला-संयोजन",
      4,
      [2],
      "The integration pattern by which verified worker changes are rebased onto the integration bookmark one after another, in order, rather than merged concurrently; a conflict stops the chain.",
      ["jj:rebase", "jj:integration-bookmark", "jj:conflict"],
    ),
    jj(
      "lease-gated-main-move",
      "Lease-gated main move",
      "paṭṭa-niyantrita-mukhya-gamana",
      "पट्ट-नियन्त्रित-मुख्य-गमन",
      0,
      [2],
      "The rule that the `main` bookmark (once created) may move only under a live `integration/main` lease together with a recorded decision — never by an unaudited direct move (BG 18.63: full analysis offered, the choice remains the authority's).",
      [
        "jj:main-bookmark", "jj:linear-chain-integration", "lease",
        "design-authority",
      ],
    ),
    jj(
      "change-vs-commit",
      "Change vs. commit",
      "parivartana-sthāpana-bheda",
      "परिवर्तन-स्थापन-भेद",
      0,
      [2],
      "The fundamental Jujutsu distinction: change id is stable identity, commit id is a content hash of one revision of that identity — a worker must never equate the two.",
      ["jj:change-id", "jj:commit-id"],
    ),
  ]
}

// ---------------------------------------------------------------------------
// 20. Holon meta-vocabulary (sa-plan uos/holonic-mapping/20260907-1505, task KM): the ten core
//     structural terms of the holon model itself (`uos_swarm/holon.gleam`) -- distinct from the
//     158 holons `holon_concepts()` derives from `holarchy()`, whose ids these never collide with
//     (namespaced `holon-meta:*`).
// ---------------------------------------------------------------------------

fn holon_meta(
  id: String,
  english: String,
  iast: String,
  devanagari: String,
  domain: Domain,
  layer: Int,
  plane: String,
  definition: String,
  relates: List(String),
) -> Concept {
  mk(
    "holon-meta:" <> id,
    english,
    iast,
    devanagari,
    domain,
    layer,
    [],
    plane,
    definition,
    relates,
    "uos_swarm/holon.gleam:HOLARCHY-CENSUS",
  )
}

fn holon_meta_concepts() -> List(Concept) {
  [
    holon_meta(
      "holon",
      "Holon",
      "svayaṃ-pūrṇa-aṅga",
      "स्वयं-पूर्ण-अङ्ग",
      Structure,
      2,
      "structure-plane",
      "A self-complete part: a unit simultaneously whole to its own parts and part of a larger whole (Koestler); every entry of `holon.holarchy()` instantiates this pattern via the `Holon` record (id, whole, parts, level, plane, kind, uid, lifecycle, vitals).",
      ["holon-meta:holarchy", "holon-meta:whole", "holon-meta:part"],
    ),
    holon_meta(
      "holarchy",
      "Holarchy",
      "aṅga-sopāna",
      "अङ्ग-सोपान",
      Structure,
      2,
      "structure-plane",
      "The layered structure formed by holons nested through whole/part relationships across levels (`holon.holarchy()`), validated acyclic and level-monotonic by the nine core base rules B1..B9 (`holon.base_rules`).",
      ["holon-meta:holon", "holon-meta:level", "uos"],
    ),
    holon_meta(
      "constitution",
      "Constitution",
      "saṃvidhāna",
      "संविधान",
      Governance,
      0,
      "control-plane",
      "The L0 constitutional-whole pattern: a `Subsystem`-kind holon (e.g. the `constitution` holon itself) grouping IAM, secrets, clock-guard and governance rows so their L0 level never pulls an unrelated subsystem down (HOLON-LIFECYCLE).",
      ["constitution", "holon-meta:holon", "holon-meta:level"],
    ),
    holon_meta(
      "census",
      "Census",
      "gaṇanā",
      "गणना",
      Structure,
      4,
      "runtime-plane",
      "The 113-row daemon census that census-derived `Process`-kind holons mirror one-to-one (base rule B10, `holon.rule_b10`/`holon.b10_missing`), so every observed daemon names exactly one Process holon and vice versa.",
      ["holon-meta:holon", "holon-meta:lifecycle"],
    ),
    holon_meta(
      "lifecycle",
      "Lifecycle",
      "jīvana-cakra",
      "जीवन-चक्र",
      Structure,
      4,
      "runtime-plane",
      "The six-state biological holon lifecycle (Dormant/Awakening/Active/Stressed/Healing/Apoptotic, HOLON-LIFECYCLE) and its legal `holon.transition` state machine; census-derived holons start from `holon.lifecycle_from_status`.",
      ["holon-meta:holon", "holon-meta:vitals", "holon-meta:census"],
    ),
    holon_meta(
      "vitals",
      "Vitals",
      "prāṇa-lakṣaṇa",
      "प्राण-लक्षण",
      Structure,
      4,
      "runtime-plane",
      "The optional observed-liveness record on a holon (`heartbeat_age_s`, `restarts`, `last_transition`, `holon.Vitals`) -- distinct from the census-derived `lifecycle` classification, which is a one-shot snapshot, not a live poll.",
      ["holon-meta:lifecycle", "holon-meta:holon"],
    ),
    holon_meta(
      "plane",
      "Plane",
      "tala",
      "तल",
      Structure,
      1,
      "structure-plane",
      "One of the seven control/structure/runtime/data/messaging/intelligence/language planes (`holon.Plane`) every holon is assigned to; each plane sounds one Hindustani svara via `holon.swara_of_plane`.",
      ["holon-meta:holon", "planes"],
    ),
    holon_meta(
      "whole",
      "Whole",
      "pūrṇa",
      "पूर्ण",
      Structure,
      2,
      "structure-plane",
      "The optional parent holon id a holon names as its whole (`Holon.whole`); `None` only for the root (`uos`); reciprocated by the parent's `parts` list under base rule B2.",
      ["holon-meta:holon", "holon-meta:part"],
    ),
    holon_meta(
      "part",
      "Part",
      "aṅga",
      "अङ्ग",
      Structure,
      2,
      "structure-plane",
      "One child holon id listed in a holon's `parts` field (`Holon.parts`); every part's `whole` must name this holon back (base rule B2) and every part's `level` must be at or above this holon's `level` (base rule B4).",
      ["holon-meta:holon", "holon-meta:whole", "holon-meta:level"],
    ),
    holon_meta(
      "level",
      "Level",
      "stara",
      "स्तर",
      Structure,
      2,
      "structure-plane",
      "The integer fractal layer (0..9) a holon occupies (`Holon.level`), used verbatim in its board address (`uos/holon/L<level>/<plane>/<id>`, `holon.address`) and constrained level-monotonic across whole/part edges (base rule B4).",
      ["holon-meta:holon", "holon-meta:whole", "holon-meta:part"],
    ),
  ]
}

// ---------------------------------------------------------------------------
// Registry
// ---------------------------------------------------------------------------

pub fn concepts() -> List(Concept) {
  list.flatten([
    textual_concepts(),
    holon_concepts(),
    holon_meta_concepts(),
    aspect_concepts(),
    control_action_concepts(),
    muda_concepts(),
    board_kind_concepts(),
    performative_concepts(),
    ooda_concepts(),
    tps_concepts(),
    coordination_concepts(),
    governance_concepts(),
    agent_kernel_concepts(),
    review_concepts(),
    economy_concepts(),
    hindu_thinking_concepts(),
    citta_vrtti_concepts(),
    kosha_concepts(),
    music_concepts(),
    jj_concepts(),
  ])
}

/// Resolve any surface form of a concept: id, English, or IAST — case-sensitive first, then
/// case-insensitive across all three fields.
pub fn resolve(name: String) -> Result(Concept, Nil) {
  let cs = concepts()
  case
    list.find(cs, fn(c) { c.id == name || c.english == name || c.iast == name })
  {
    Ok(c) -> Ok(c)
    Error(_) -> {
      let lname = string.lowercase(name)
      list.find(cs, fn(c) {
        string.lowercase(c.id) == lname
        || string.lowercase(c.english) == lname
        || string.lowercase(c.iast) == lname
      })
    }
  }
}

pub fn by_domain(d: Domain) -> List(Concept) {
  list.filter(concepts(), fn(c) { c.domain == d })
}

pub fn by_layer(layer: Int) -> List(Concept) {
  list.filter(concepts(), fn(c) { c.layer == layer })
}

pub fn by_aspect(aspect: Int) -> List(Concept) {
  list.filter(concepts(), fn(c) { list.contains(c.aspects, aspect) })
}

/// Registry invariants: unique ids, layer 0..9, aspects 1..17, Devanagari present, and every
/// `relates` target resolves to a real concept id.
pub fn validate_registry() -> Result(Nil, String) {
  let cs = concepts()
  let ids = list.map(cs, fn(c) { c.id })
  use _ <- result.try(case list.length(list.unique(ids)) == list.length(ids) {
    True -> Ok(Nil)
    False -> Error("duplicate concept id")
  })
  use _ <- result.try(
    list.try_each(cs, fn(c) {
      case c.layer >= 0 && c.layer <= 9 {
        True -> Ok(Nil)
        False -> Error(c.id <> ": layer out of range 0..9")
      }
    }),
  )
  use _ <- result.try(
    list.try_each(cs, fn(c) {
      case list.all(c.aspects, fn(a) { a >= 1 && a <= 17 }) {
        True -> Ok(Nil)
        False -> Error(c.id <> ": aspect out of range 1..17")
      }
    }),
  )
  use _ <- result.try(
    list.try_each(cs, fn(c) {
      case c.devanagari != "" {
        True -> Ok(Nil)
        False -> Error(c.id <> ": missing Devanagari")
      }
    }),
  )
  list.try_each(cs, fn(c) {
    list.try_each(c.relates, fn(r) {
      case list.contains(ids, r) {
        True -> Ok(Nil)
        False -> Error(c.id <> ": relates to unknown concept " <> r)
      }
    })
  })
}

// ---------------------------------------------------------------------------
// Markdown / JSON views
// ---------------------------------------------------------------------------

pub fn dictionary_markdown() -> String {
  let header =
    "| id | Devanagari | IAST | English | domain | layer | aspects | definition | source |\n|---|---|---|---|---|---|---|---|---|"
  let rows =
    list.map(concepts(), fn(c) {
      "| "
      <> c.id
      <> " | "
      <> c.devanagari
      <> " | "
      <> c.iast
      <> " | "
      <> c.english
      <> " | "
      <> domain_label(c.domain)
      <> " | "
      <> int.to_string(c.layer)
      <> " | "
      <> string.join(list.map(c.aspects, int.to_string), ",")
      <> " | "
      <> c.definition
      <> " | `"
      <> c.source
      <> "` |"
    })
  string.join([header, ..rows], "\n")
}

/// Alphabetical by IAST: term -> English -> one-line definition.
pub fn glossary_markdown() -> String {
  let header = "| IAST | Devanagari | English | Definition |\n|---|---|---|---|"
  let rows =
    concepts()
    |> list.sort(fn(a, b) { string.compare(a.iast, b.iast) })
    |> list.map(fn(c) {
      "| "
      <> c.iast
      <> " | "
      <> c.devanagari
      <> " | "
      <> c.english
      <> " | "
      <> c.definition
      <> " |"
    })
  string.join([header, ..rows], "\n")
}

fn domain_graph_mermaid(cs: List(Concept)) -> String {
  let edges =
    cs
    |> list.flat_map(fn(c) {
      list.filter_map(c.relates, fn(r) {
        case resolve(r) {
          Error(_) -> Error(Nil)
          Ok(target) ->
            case target.domain == c.domain {
              True -> Error(Nil)
              False ->
                Ok(
                  "  "
                  <> domain_node(c.domain)
                  <> " --> "
                  <> domain_node(target.domain),
                )
            }
        }
      })
    })
    |> list.unique
  string.join(["graph TD", ..edges], "\n")
}

/// Per-domain sections listing every concept and its relations, plus a Mermaid graph of the
/// cross-domain edges induced by `relates`.
pub fn wiki_markdown() -> String {
  let cs = concepts()
  let sections =
    list.map(all_domains, fn(d) {
      let ds = by_domain(d)
      let header =
        "## "
        <> domain_label(d)
        <> " ("
        <> int.to_string(list.length(ds))
        <> " concepts)"
      let rows =
        list.map(ds, fn(c) {
          let rel = case c.relates {
            [] -> ""
            xs -> " _(relates: " <> string.join(xs, ", ") <> ")_"
          }
          "- **"
          <> c.id
          <> "** ("
          <> c.devanagari
          <> " / "
          <> c.iast
          <> ") — "
          <> c.english
          <> ": "
          <> c.definition
          <> rel
        })
      header <> "\n" <> string.join(rows, "\n")
    })
  string.join(sections, "\n\n")
  <> "\n\n## Domain graph\n\n```mermaid\n"
  <> domain_graph_mermaid(cs)
  <> "\n```"
}

pub fn to_json() -> Json {
  json.array(concepts(), fn(c) {
    json.object([
      #("id", json.string(c.id)),
      #("english", json.string(c.english)),
      #("iast", json.string(c.iast)),
      #("devanagari", json.string(c.devanagari)),
      #("domain", json.string(domain_label(c.domain))),
      #("layer", json.int(c.layer)),
      #("aspects", json.array(c.aspects, json.int)),
      #("plane", json.string(c.plane)),
      #("definition", json.string(c.definition)),
      #("relates", json.array(c.relates, json.string)),
      #("source", json.string(c.source)),
    ])
  })
}

/// How many of `concept_names` resolve, and the ones that do not.
pub fn alignment_report(concept_names: List(String)) -> #(Int, List(String)) {
  let unresolved =
    list.filter(concept_names, fn(n) {
      case resolve(n) {
        Ok(_) -> False
        Error(_) -> True
      }
    })
  #(list.length(concept_names) - list.length(unresolved), unresolved)
}
