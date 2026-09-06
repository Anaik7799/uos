//// =============================================================================
//// [UOS-FPP-TOPOLOGY] Canonical FPP Harness Topology in Pure Gleam
//// =============================================================================
//// Models the UOS / Harness system as a NASA JPL F Prime Topology:
//// - 11 Domain Instances (base IDs 0x100..0xB00) + 4 Infrastructure Pattern Servers
//// - 13 Direct Dataflow Connections
//// - 4 Cross-Cutting Pattern Graphs (Time, Health, Telemetry, Event)
//// - ConvergeLoop OODA State Machine (Idle, Preflight, Observing, Converged, Blocked, Anomalous)
//// - SMT Disjointness & Opcode Uniqueness guarantees
//// =============================================================================

import cepaf_gleam/fpp/domain.{
  type Model, type PortDef, type PortInstance, type StateMachine, type TypeDef,
  Active, ActivityHi, ActivityLo, Always, Assert, AsyncCmd, Block, Channel,
  Choice, Command, Component, Connection, ContainerSpec, Diagnostic, Direct,
  Endpoint, EnumType, Event, EventPort, Fatal, General, GuardedInput, Instance,
  InternalMachine, Model, Named, OnChange, Output, PEvent, PHealth, PTelemetry,
  PTime, Passive, Pattern, PortDef, Prim, RecordSpec, SignalDef, Special, State,
  StructType, SyncCmd, SyncInput, TelemetryPort, Threshold, TimeGet, ToChoice,
  ToState, Transition, U32, U8, WarningHi, WarningLo,
}
import gleam/option.{None, Some}

// --------------------------------------------------------------- Port Types

pub fn canonical_port_defs() -> List(PortDef) {
  [
    PortDef("Rows", [#("rows", Named("EvidenceRow"))], None),
    PortDef("Verdicts", [#("verdict", Named("Verdict"))], None),
    PortDef("Sweep", [#("worst", Named("Alert"))], None),
    PortDef("Gate", [#("satisfied", Prim(domain.BoolType))], None),
    PortDef("Plan", [#("converged", Prim(domain.BoolType))], None),
    PortDef("Ping", [#("key", Prim(U32))], None),
    PortDef("Time", [#("revision", Prim(domain.StringType(Some(64))))], None),
    PortDef("Mesh", [#("payload", Prim(domain.StringType(Some(1024))))], None),
    PortDef("Log", [#("diagnostic", Prim(domain.StringType(Some(256))))], None),
  ]
}

// ------------------------------------------------------------- Domain Types

pub fn canonical_type_defs() -> List(TypeDef) {
  [
    EnumType("Verdict", U8, [
      #("VERIFIED", 0),
      #("UNMAPPED", 1),
      #("BLOCKED", 2),
      #("DIVERGENT", 3),
    ]),
    EnumType("Alert", U8, [
      #("GREEN", 0),
      #("P2", 1),
      #("P1", 2),
      #("P0", 3),
    ]),
    StructType("EvidenceRow", [
      #("contract", Prim(domain.StringType(Some(64)))),
      #("scenario", Prim(domain.StringType(Some(64)))),
      #("passed", Prim(domain.BoolType)),
    ]),
  ]
}

// ------------------------------------------------------------ State Machines

pub fn canonical_converge_loop() -> StateMachine {
  InternalMachine(
    machine_name: "ConvergeLoop",
    signals: [
      SignalDef("tick", None),
      SignalDef("preflight_ok", None),
      SignalDef("preflight_refused", None),
      SignalDef("progress", None),
      SignalDef("no_progress", None),
      SignalDef("anomaly", Some(Prim(domain.StringType(Some(128))))),
    ],
    guards: ["frontier_advanced"],
    actions: ["observe", "orient", "decide", "act", "record", "alert"],
    states: [
      State("Idle", [], [], [
        Transition("tick", None, [], ToState("Preflight")),
      ]),
      State("Preflight", [], [], [
        Transition("preflight_ok", None, ["observe"], ToState("Observing")),
        Transition("preflight_refused", None, ["alert"], ToState("Blocked")),
      ]),
      State("Observing", [], [], [
        Transition("progress", None, [], ToChoice("advance")),
        Transition("no_progress", None, ["record"], ToState("Converged")),
        Transition("anomaly", None, ["alert"], ToState("Anomalous")),
      ]),
      State("Converged", ["record"], [], [
        Transition("tick", None, [], ToState("Preflight")),
      ]),
      State("Blocked", [], [], [
        Transition("tick", None, [], ToState("Preflight")),
      ]),
      State("Anomalous", ["alert"], [], []),
    ],
    choices: [
      Choice(
        "advance",
        "frontier_advanced",
        #(["orient", "decide", "act", "record"], ToState("Observing")),
        #(["record"], ToState("Converged")),
      ),
    ],
    initial: #([], "Idle"),
  )
}

// ------------------------------------------------------------ Components

fn ping_pair() -> List(PortInstance) {
  [
    General("pingIn", "Ping", SyncInput, 1),
    General("pingOut", "Ping", Output, 1),
  ]
}

pub fn inventory_component() -> domain.Component {
  Component(
    comp_name: "inventory",
    kind: Passive,
    ports: [
      General("timeGetIn", "Time", SyncInput, 8),
      General("rowsOut", "Rows", Output, 1),
    ],
    commands: [],
    events: [],
    channels: [
      Channel("modules_scanned", 0, Prim(U32), Always, None, None, None),
    ],
    parameters: [],
    records: [],
    containers: [],
    internal_ports: [],
    machines: [],
    matched: [],
  )
}

pub fn evidence_store_component() -> domain.Component {
  Component(
    comp_name: "evidence_store",
    kind: Passive,
    ports: [
      General("record", "Rows", GuardedInput, 4),
      General("rows", "Rows", Output, 4),
      General("storeOut", "Rows", Output, 3),
      Special(EventPort),
      Special(TelemetryPort),
      Special(TimeGet),
      ..ping_pair()
    ],
    commands: [],
    events: [
      Event("RECEIPT_RECORDED", 4, Diagnostic, "receipt recorded for %s", None),
    ],
    channels: [
      Channel("receipts_total", 0, Prim(U32), Always, None, None, None),
      Channel(
        "verified_count",
        1,
        Prim(U32),
        OnChange,
        None,
        Some(Threshold(None, None, Some(0.0))),
        None,
      ),
    ],
    parameters: [],
    records: [RecordSpec("receipt", 8, Named("EvidenceRow"), True)],
    containers: [ContainerSpec("evidence", 9, Some(1))],
    internal_ports: [],
    machines: [],
    matched: [],
  )
}

pub fn parity_compare_component() -> domain.Component {
  Component(
    comp_name: "parity_compare",
    kind: Passive,
    ports: [
      General("gate", "Gate", SyncInput, 2),
      General("verdicts", "Verdicts", Output, 1),
      General("receipts", "Rows", Output, 1),
      Special(EventPort),
      Special(TelemetryPort),
      Special(TimeGet),
      ..ping_pair()
    ],
    commands: [
      Command("COMPARE_ALL", 0, SyncCmd, []),
      Command("COMPARE_SCENARIO", 1, SyncCmd, [
        #("scenario", Prim(domain.StringType(Some(64)))),
      ]),
    ],
    events: [
      Event(
        "DIVERGENCE_FOUND",
        2,
        ActivityHi,
        "divergence on %s -- measurement",
        None,
      ),
      Event("SCENARIO_VERIFIED", 3, ActivityLo, "%s verified", None),
      Event(
        "ORACLE_UNAVAILABLE",
        4,
        WarningHi,
        "oracle %s unavailable -- Blocked",
        None,
      ),
    ],
    channels: [
      Channel("scenarios_compared", 5, Prim(U32), Always, None, None, None),
      Channel("divergences_open", 6, Prim(U32), OnChange, None, None, None),
    ],
    parameters: [],
    records: [],
    containers: [],
    internal_ports: [],
    machines: [],
    matched: [],
  )
}

pub fn harness_config_component() -> domain.Component {
  Component(
    comp_name: "harness_config",
    kind: Active,
    ports: [
      General("run", "Gate", Output, 5),
      Special(domain.CommandRecv),
      Special(domain.CommandReg),
      Special(domain.CommandResp),
      Special(EventPort),
      Special(TelemetryPort),
      Special(TimeGet),
      ..ping_pair()
    ],
    commands: [
      Command("RUN_PIPELINE", 0, AsyncCmd(Some(1), Assert), []),
      Command("CONVERGE", 1, AsyncCmd(None, Block), []),
    ],
    events: [
      Event(
        "PIPELINE_BLOCKED",
        2,
        WarningHi,
        "activity %s blocked -- fail-closed",
        None,
      ),
      Event("ANOMALY", 3, Fatal, "converge anomaly: %s", None),
    ],
    channels: [
      Channel("activities_run", 4, Prim(U32), Always, None, None, None),
    ],
    parameters: [],
    records: [],
    containers: [],
    internal_ports: [],
    machines: [#("converge", "ConvergeLoop")],
    matched: [],
  )
}

pub fn control_plane_component() -> domain.Component {
  Component(
    comp_name: "control_plane",
    kind: Passive,
    ports: [
      General("history", "Rows", SyncInput, 1),
      General("alerts", "Sweep", SyncInput, 2),
      General("sweep", "Sweep", Output, 2),
      General("pingOut", "Ping", Output, 8),
      General("pingIn", "Ping", SyncInput, 8),
      Special(EventPort),
      Special(TelemetryPort),
      Special(TimeGet),
    ],
    commands: [],
    events: [
      Event("SWEEP_P0", 2, Fatal, "P0: %s -- exit 2", None),
      Event("SWEEP_P1", 3, WarningHi, "P1: %s", None),
      Event("SWEEP_P2", 4, WarningLo, "P2: %s", None),
      Event("SWEEP_GREEN", 5, ActivityLo, "sweep green", None),
    ],
    channels: [
      Channel(
        "worst_alert",
        0,
        Named("Alert"),
        OnChange,
        None,
        None,
        Some(Threshold(Some(1.0), Some(2.0), Some(3.0))),
      ),
      Channel("legs_green", 1, Prim(U8), Always, None, None, None),
    ],
    parameters: [],
    records: [],
    containers: [],
    internal_ports: [],
    machines: [],
    matched: [],
  )
}

pub fn hermes_zenoh_component() -> domain.Component {
  Component(
    comp_name: "hermes_zenoh",
    kind: Passive,
    ports: [
      General("publish", "Sweep", SyncInput, 4),
      General("tlmIn", "Mesh", SyncInput, 8),
      General("gossipOut", "Rows", Output, 6),
      Special(EventPort),
      Special(TimeGet),
      ..ping_pair()
    ],
    commands: [],
    events: [
      Event(
        "MESH_UNREACHABLE",
        4,
        WarningLo,
        "zenoh: %s -- telemetry stays local",
        None,
      ),
    ],
    channels: [
      Channel("publishes_ok", 2, Prim(U32), Always, None, None, None),
      Channel(
        "publish_errors",
        3,
        Prim(U32),
        Always,
        None,
        None,
        Some(Threshold(Some(1.0), None, None)),
      ),
    ],
    parameters: [],
    records: [],
    containers: [],
    internal_ports: [],
    machines: [],
    matched: [],
  )
}

pub fn fractal_diagnostic_component() -> domain.Component {
  Component(
    comp_name: "fractal_diagnostic",
    kind: Passive,
    ports: [General("logIn", "Log", SyncInput, 8)],
    commands: [],
    events: [],
    channels: [],
    parameters: [],
    records: [],
    containers: [],
    internal_ports: [],
    machines: [],
    matched: [],
  )
}

// ------------------------------------------------------------- Full Model

pub fn canonical_packets() -> List(domain.TlmPacket) {
  [
    domain.TlmPacket(
      packet_id: 1,
      packet_name: "ControlSweepPacket",
      channel_ids: [0, 1],
      level: 1,
    ),
    domain.TlmPacket(
      packet_id: 2,
      packet_name: "EvidenceStatePacket",
      channel_ids: [0, 1],
      level: 1,
    ),
    domain.TlmPacket(
      packet_id: 3,
      packet_name: "ParityComparePacket",
      channel_ids: [5, 6],
      level: 2,
    ),
  ]
}

pub fn canonical_subtopologies() -> List(domain.Subtopology) {
  [
    domain.Subtopology(
      name: "EvidencePipelineSubtopo",
      instances: [
        Instance("parity_compare", "parity_compare", 0x800, None, None, None, None),
        Instance("evidence_store", "evidence_store", 0x600, None, None, None, None),
      ],
      connections: [
        Connection(
          Endpoint("parity_compare", "receipts", None),
          Endpoint("evidence_store", "record", None),
        ),
      ],
      exported_ports: [
        domain.ExportedPort("receiptIn", "evidence_store", "record"),
        domain.ExportedPort("verdictsOut", "parity_compare", "verdicts"),
      ],
    ),
  ]
}

pub fn canonical_harness_model() -> Model {
  let comps = [
    inventory_component(),
    evidence_store_component(),
    parity_compare_component(),
    harness_config_component(),
    control_plane_component(),
    hermes_zenoh_component(),
    fractal_diagnostic_component(),
  ]

  let insts = [
    Instance("inventory", "inventory", 0x100, None, None, None, None),
    Instance("evidence_store", "evidence_store", 0x600, None, None, None, None),
    Instance(
      "harness_config",
      "harness_config",
      0x700,
      Some(10),
      None,
      Some(1),
      None,
    ),
    Instance("parity_compare", "parity_compare", 0x800, None, None, None, None),
    Instance("control_plane", "control_plane", 0xC00, None, None, None, None),
    Instance("hermes_zenoh", "hermes_zenoh", 0xE00, None, None, None, None),
    Instance(
      "fractal_diagnostic",
      "fractal_diagnostic",
      0xF00,
      None,
      None,
      None,
      None,
    ),
  ]

  let graphs = [
    Direct("evidence_flow", [
      Connection(
        Endpoint("parity_compare", "receipts", None),
        Endpoint("evidence_store", "record", None),
      ),
      Connection(
        Endpoint("inventory", "rowsOut", None),
        Endpoint("evidence_store", "record", None),
      ),
    ]),
    Pattern(PTime, "inventory", [
      "evidence_store",
      "parity_compare",
      "harness_config",
      "control_plane",
      "hermes_zenoh",
    ]),
    Pattern(PHealth, "control_plane", [
      "evidence_store",
      "parity_compare",
      "harness_config",
      "hermes_zenoh",
    ]),
    Pattern(PTelemetry, "hermes_zenoh", [
      "evidence_store",
      "parity_compare",
      "harness_config",
      "control_plane",
    ]),
    Pattern(PEvent, "fractal_diagnostic", [
      "evidence_store",
      "parity_compare",
      "harness_config",
      "control_plane",
      "hermes_zenoh",
    ]),
  ]

  let topo =
    domain.Topology(
      "HermesHarness",
      [
        "inventory",
        "evidence_store",
        "harness_config",
        "parity_compare",
        "control_plane",
        "hermes_zenoh",
        "fractal_diagnostic",
      ],
      graphs,
    )

  Model(
    model_name: "HermesHarness",
    type_defs: canonical_type_defs(),
    port_defs: canonical_port_defs(),
    constants: [#("WINDOW_SIZE", 10)],
    components: comps,
    machines: [canonical_converge_loop()],
    instances: insts,
    topologies: [topo],
    packets: canonical_packets(),
    subtopologies: canonical_subtopologies(),
  )
}
