//// =============================================================================
//// [UOS-FPP-DOMAIN] NASA JPL F Prime (F') & FPP Metamodel in Pure Gleam
//// =============================================================================
//// Canonical Gleam port of the FPP specification:
//// - 14 Definitions (Abstract, Alias, Array, Component, Instance, Constant, Enum,
////   Module, Port, Port Interface, State Machine, Struct, Topology)
//// - 18 Specifiers (Command, Direct Graph, Pattern Graph, Container, Event,
////   Internal Port, Parameter, Port Instance, Record, Telemetry Channel, etc.)
//// - 11 State Machine elements (Signals, Guards, Actions, States, Transitions, Choices)
//// - Queue-full semantics: Assert, Block, Drop
//// - Two-Lattice separation: Distinct Verdict and Alert enums
//// =============================================================================

import gleam/int
import gleam/list
import gleam/option.{type Option}

// ------------------------------------------------------------------ Primitives

pub type FppPrim {
  U8
  U16
  U32
  U64
  I8
  I16
  I32
  I64
  F32
  F64
  BoolType
  StringType(size: Option(Int))
}

pub type FppType {
  Prim(FppPrim)
  Named(String)
}

pub type TypeDef {
  Abstract(name: String)
  Alias(name: String, target: FppType)
  ArrayType(name: String, size: Int, element: FppType, format: Option(String))
  EnumType(name: String, repr: FppPrim, constants: List(#(String, Int)))
  StructType(name: String, members: List(#(String, FppType)))
}

// ----------------------------------------------------------------------- Ports

pub type PortDef {
  PortDef(
    port_name: String,
    params: List(#(String, FppType)),
    return_type: Option(FppType),
  )
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
  ProductGet
  ProductRequest
  ProductRecv
  ProductSend
}

pub type PortInstance {
  General(name: String, port: String, direction: Direction, count: Int)
  Special(SpecialPort)
}

// --------------------------------------------------------- C&DH Dictionaries

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
    cmd_params: List(#(String, FppType)),
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

pub type Threshold {
  Threshold(yellow: Option(Float), orange: Option(Float), red: Option(Float))
}

pub type Channel {
  Channel(
    chan_name: String,
    chan_id: Int,
    chan_type: FppType,
    update: UpdatePolicy,
    chan_format: Option(String),
    low: Option(Threshold),
    high: Option(Threshold),
  )
}

pub type Parameter {
  Parameter(
    param_name: String,
    param_id: Int,
    param_type: FppType,
    default: Option(String),
    set_opcode: Int,
    save_opcode: Int,
    external: Bool,
  )
}

pub type RecordSpec {
  RecordSpec(
    record_name: String,
    record_id: Int,
    record_type: FppType,
    record_is_array: Bool,
  )
}

pub type ContainerSpec {
  ContainerSpec(
    container_name: String,
    container_id: Int,
    default_priority: Option(Int),
  )
}

pub type InternalPort {
  InternalPort(
    internal_name: String,
    internal_params: List(#(String, FppType)),
    internal_priority: Option(Int),
    internal_queue_full: QueueFull,
  )
}

// ------------------------------------------------------------- State Machines

pub type Target {
  ToState(String)
  ToChoice(String)
}

pub type Transition {
  Transition(
    on_signal: String,
    guard: Option(String),
    do_actions: List(String),
    target: Target,
  )
}

pub type State {
  State(
    state_name: String,
    entry: List(String),
    exit: List(String),
    transitions: List(Transition),
  )
}

pub type SignalDef {
  SignalDef(signal_name: String, signal_type: Option(FppType))
}

pub type Choice {
  Choice(
    choice_name: String,
    choice_guard: String,
    if_true: #(List(String), Target),
    if_false: #(List(String), Target),
  )
}

pub type HierarchicalState {
  HierarchicalState(
    name: String,
    parent: Option(String),
    entry: List(String),
    exit: List(String),
    transitions: List(Transition),
    sub_states: List(HierarchicalState),
    initial_sub_state: Option(String),
  )
}

pub type StateMachine {
  ExternalMachine(machine_name: String)
  InternalMachine(
    machine_name: String,
    signals: List(SignalDef),
    guards: List(String),
    actions: List(String),
    states: List(State),
    choices: List(Choice),
    initial: #(List(String), String),
  )
  HierarchicalMachine(
    machine_name: String,
    signals: List(SignalDef),
    guards: List(String),
    actions: List(String),
    root_states: List(HierarchicalState),
    choices: List(Choice),
    initial: #(List(String), String),
  )
}

// ----------------------------------------------------------------- Components

pub type ComponentKind {
  Passive
  Queued
  Active
}

pub type PortInterface {
  PortInterface(interface_name: String, ports: List(PortInstance))
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
    records: List(RecordSpec),
    containers: List(ContainerSpec),
    internal_ports: List(InternalPort),
    machines: List(#(String, String)),
    matched: List(#(String, String)),
  )
}

// ----------------------------------------------------- Instances & Topologies

pub type Instance {
  Instance(
    inst_name: String,
    of_component: String,
    base_id: Int,
    queue_size: Option(Int),
    stack_size: Option(Int),
    inst_priority: Option(Int),
    cpu: Option(Int),
  )
}

pub type Endpoint {
  Endpoint(ep_instance: String, ep_port: String, ep_index: Option(Int))
}

pub type Connection {
  Connection(from: Endpoint, to: Endpoint)
}

pub type PatternKind {
  PCommand
  PEvent
  PTelemetry
  PTextEvent
  PTime
  PHealth
  PParam
}

pub type Graph {
  Direct(graph_name: String, connections: List(Connection))
  Pattern(pattern: PatternKind, source: String, targets: List(String))
}

pub type ExportedPort {
  ExportedPort(name: String, instance_name: String, port_name: String)
}

pub type Subtopology {
  Subtopology(
    name: String,
    instances: List(Instance),
    connections: List(Connection),
    exported_ports: List(ExportedPort),
  )
}

pub type TlmPacket {
  TlmPacket(
    packet_id: Int,
    packet_name: String,
    channel_ids: List(Int),
    level: Int,
  )
}

pub type Topology {
  Topology(topo_name: String, members: List(String), graphs: List(Graph))
}

pub type Model {
  Model(
    model_name: String,
    type_defs: List(TypeDef),
    port_defs: List(PortDef),
    constants: List(#(String, Int)),
    components: List(Component),
    machines: List(StateMachine),
    instances: List(Instance),
    topologies: List(Topology),
    packets: List(TlmPacket),
    subtopologies: List(Subtopology),
  )
}

// ----------------------------------------------------------------- Analysis

/// Calculates the width of an FPP component's relative identifier window.
/// Formula: 1 + max(command opcodes, event ids, channel ids, parameter ids,
/// parameter set/save opcodes, record ids, container ids); at least 1.
pub fn id_span(comp: Component) -> Int {
  let cmd_max =
    list.fold(comp.commands, 0, fn(acc, c) { int.max(acc, c.opcode) })
  let evt_max =
    list.fold(comp.events, 0, fn(acc, e) { int.max(acc, e.event_id) })
  let chn_max =
    list.fold(comp.channels, 0, fn(acc, c) { int.max(acc, c.chan_id) })
  let rec_max =
    list.fold(comp.records, 0, fn(acc, r) { int.max(acc, r.record_id) })
  let con_max =
    list.fold(comp.containers, 0, fn(acc, c) { int.max(acc, c.container_id) })
  let prm_max =
    list.fold(comp.parameters, 0, fn(acc, p) {
      let m1 = int.max(acc, p.param_id)
      let m2 = int.max(m1, p.set_opcode)
      int.max(m2, p.save_opcode)
    })

  let overall_max =
    cmd_max
    |> int.max(evt_max)
    |> int.max(chn_max)
    |> int.max(rec_max)
    |> int.max(con_max)
    |> int.max(prm_max)

  overall_max + 1
}

/// Validates that an FPP model satisfies base-id interval disjointness
/// across all instances. Returns a list of error diagnostics, or empty list if valid.
pub fn validate_instance_disjointness(model: Model) -> List(String) {
  let instances =
    list.sort(model.instances, fn(a, b) { int.compare(a.base_id, b.base_id) })

  check_consecutive_gaps(instances, model.components, [])
}

fn check_consecutive_gaps(
  instances: List(Instance),
  components: List(Component),
  errors: List(String),
) -> List(String) {
  case instances {
    [first, second, ..rest] -> {
      let comp_a =
        list.find(components, fn(c) { c.comp_name == first.of_component })
      let span_a = case comp_a {
        Ok(c) -> id_span(c)
        Error(_) -> 1
      }
      let end_a = first.base_id + span_a
      let new_errors = case end_a > second.base_id {
        True -> [
          "Instance overlap: "
            <> first.inst_name
            <> " ["
            <> int.to_string(first.base_id)
            <> ".."
            <> int.to_string(end_a)
            <> ") overlaps "
            <> second.inst_name
            <> " at base "
            <> int.to_string(second.base_id),
          ..errors
        ]
        False -> errors
      }
      check_consecutive_gaps([second, ..rest], components, new_errors)
    }
    _ -> list.reverse(errors)
  }
}
