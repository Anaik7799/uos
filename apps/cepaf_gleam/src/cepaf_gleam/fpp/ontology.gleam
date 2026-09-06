//// =============================================================================
//// [UOS-FPP-ONTOLOGY] NASA JPL F Prime Living Ontology & Code Structure
//// =============================================================================
//// Implements the biomorphic living ontology process derived from ZigVM/C3I:
//// 1. Living OntoNode & OntoEdge types with biomorphic presence tracking
//// 2. Automated derivation of living ontology from canonical FPP models
//// 3. Referential integrity & topological closure verification laws
//// 4. Typed JSON serialization for machine introspection & web UI
//// =============================================================================

import cepaf_gleam/fpp/domain.{
  type Model, Active, Direct, HierarchicalMachine, InternalMachine, Passive,
  Pattern, Queued,
}
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{None, Some}

// =============================================================================
// 1. Types & Categories
// =============================================================================

pub type OntoCategory {
  OntoComponentDef
  OntoInstance
  OntoPortDef
  OntoCommandDef
  OntoEventDef
  OntoChannelDef
  OntoParameterDef
  OntoStateMachineDef
  OntoSubtopologyDef
  OntoPacketDef
}

pub fn category_to_string(cat: OntoCategory) -> String {
  case cat {
    OntoComponentDef -> "ComponentDef"
    OntoInstance -> "Instance"
    OntoPortDef -> "PortDef"
    OntoCommandDef -> "CommandDef"
    OntoEventDef -> "EventDef"
    OntoChannelDef -> "ChannelDef"
    OntoParameterDef -> "ParameterDef"
    OntoStateMachineDef -> "StateMachineDef"
    OntoSubtopologyDef -> "SubtopologyDef"
    OntoPacketDef -> "PacketDef"
  }
}

pub type OntoRelation {
  Instantiates
  ConnectsTo
  DefinesCommand
  DefinesEvent
  DefinesChannel
  DefinesParameter
  ExecutesStateMachine
  ContainsSubstate
  TransitsState
  PacksChannel
  PatternTimeSync
  PatternHealthPing
  PatternTlmTelemetry
  PatternDiagEvent
}

pub fn relation_to_string(rel: OntoRelation) -> String {
  case rel {
    Instantiates -> "instantiates"
    ConnectsTo -> "connects_to"
    DefinesCommand -> "defines_command"
    DefinesEvent -> "defines_event"
    DefinesChannel -> "defines_channel"
    DefinesParameter -> "defines_parameter"
    ExecutesStateMachine -> "executes_state_machine"
    ContainsSubstate -> "contains_substate"
    TransitsState -> "transits_state"
    PacksChannel -> "packs_channel"
    PatternTimeSync -> "pattern_time_sync"
    PatternHealthPing -> "pattern_health_ping"
    PatternTlmTelemetry -> "pattern_tlm_telemetry"
    PatternDiagEvent -> "pattern_diag_event"
  }
}

pub type OntoNode {
  OntoNode(
    id: String,
    name: String,
    category: OntoCategory,
    layer: Int,
    plane: String,
    first_seen: String,
    last_seen: String,
    present: Bool,
    metadata: List(#(String, String)),
  )
}

pub type OntoEdge {
  OntoEdge(
    source_id: String,
    target_id: String,
    relation: OntoRelation,
    weight: Float,
    present: Bool,
  )
}

pub type OntoGraph {
  OntoGraph(
    nodes: List(OntoNode),
    edges: List(OntoEdge),
    schema_version: String,
    topology_name: String,
  )
}

// =============================================================================
// 2. Automated Derivation from FPP Model
// =============================================================================

pub fn derive_fpp_ontology(model: Model) -> OntoGraph {
  let now = "2026-09-06T09:40:00.000000Z"

  // 1. Component Definition Nodes
  let comp_nodes =
    list.map(model.components, fn(c) {
      let kind_str = case c.kind {
        Passive -> "Passive"
        Queued -> "Queued"
        Active -> "Active"
      }
      OntoNode(
        id: "comp:" <> c.comp_name,
        name: c.comp_name,
        category: OntoComponentDef,
        layer: 1,
        plane: "DeterministicExecution",
        first_seen: now,
        last_seen: now,
        present: True,
        metadata: [#("kind", kind_str)],
      )
    })

  // 2. Component Detail Nodes & Edges (Commands, Events, Channels, Parameters)
  let #(detail_nodes, detail_edges) =
    list.fold(model.components, #([], []), fn(acc, c) {
      let #(nodes_acc, edges_acc) = acc
      let parent_id = "comp:" <> c.comp_name

      let cmd_nodes =
        list.map(c.commands, fn(cmd) {
          OntoNode(
            id: "cmd:" <> c.comp_name <> "." <> cmd.cmd_name,
            name: cmd.cmd_name,
            category: OntoCommandDef,
            layer: 2,
            plane: "CommandPlane",
            first_seen: now,
            last_seen: now,
            present: True,
            metadata: [#("opcode", int.to_string(cmd.opcode))],
          )
        })

      let cmd_edges =
        list.map(c.commands, fn(cmd) {
          OntoEdge(
            source_id: parent_id,
            target_id: "cmd:" <> c.comp_name <> "." <> cmd.cmd_name,
            relation: DefinesCommand,
            weight: 1.0,
            present: True,
          )
        })

      let evt_nodes =
        list.map(c.events, fn(evt) {
          OntoNode(
            id: "evt:" <> c.comp_name <> "." <> evt.event_name,
            name: evt.event_name,
            category: OntoEventDef,
            layer: 2,
            plane: "EventPlane",
            first_seen: now,
            last_seen: now,
            present: True,
            metadata: [#("event_id", int.to_string(evt.event_id))],
          )
        })

      let evt_edges =
        list.map(c.events, fn(evt) {
          OntoEdge(
            source_id: parent_id,
            target_id: "evt:" <> c.comp_name <> "." <> evt.event_name,
            relation: DefinesEvent,
            weight: 1.0,
            present: True,
          )
        })

      let chn_nodes =
        list.map(c.channels, fn(chn) {
          OntoNode(
            id: "chn:" <> c.comp_name <> "." <> chn.chan_name,
            name: chn.chan_name,
            category: OntoChannelDef,
            layer: 2,
            plane: "TelemetryPlane",
            first_seen: now,
            last_seen: now,
            present: True,
            metadata: [#("channel_id", int.to_string(chn.chan_id))],
          )
        })

      let chn_edges =
        list.map(c.channels, fn(chn) {
          OntoEdge(
            source_id: parent_id,
            target_id: "chn:" <> c.comp_name <> "." <> chn.chan_name,
            relation: DefinesChannel,
            weight: 1.0,
            present: True,
          )
        })

      let prm_nodes =
        list.map(c.parameters, fn(prm) {
          OntoNode(
            id: "prm:" <> c.comp_name <> "." <> prm.param_name,
            name: prm.param_name,
            category: OntoParameterDef,
            layer: 2,
            plane: "ParameterPlane",
            first_seen: now,
            last_seen: now,
            present: True,
            metadata: [#("param_id", int.to_string(prm.param_id))],
          )
        })

      let prm_edges =
        list.map(c.parameters, fn(prm) {
          OntoEdge(
            source_id: parent_id,
            target_id: "prm:" <> c.comp_name <> "." <> prm.param_name,
            relation: DefinesParameter,
            weight: 1.0,
            present: True,
          )
        })

      #(
        list.flatten([nodes_acc, cmd_nodes, evt_nodes, chn_nodes, prm_nodes]),
        list.flatten([edges_acc, cmd_edges, evt_edges, chn_edges, prm_edges]),
      )
    })

  // 3. Instance Nodes & Instantiation Edges
  let inst_nodes =
    list.map(model.instances, fn(inst) {
      OntoNode(
        id: "inst:" <> inst.inst_name,
        name: inst.inst_name,
        category: OntoInstance,
        layer: 3,
        plane: "OperationalMesh",
        first_seen: now,
        last_seen: now,
        present: True,
        metadata: [
          #("component", inst.of_component),
          #("base_id", "0x" <> int.to_base16(inst.base_id)),
        ],
      )
    })

  let inst_edges =
    list.map(model.instances, fn(inst) {
      OntoEdge(
        source_id: "inst:" <> inst.inst_name,
        target_id: "comp:" <> inst.of_component,
        relation: Instantiates,
        weight: 1.0,
        present: True,
      )
    })

  // 4. State Machine Nodes & Transitions
  let #(sm_nodes, sm_edges) =
    list.fold(model.machines, #([], []), fn(acc, sm) {
      let #(nodes_acc, edges_acc) = acc
      case sm {
        domain.ExternalMachine(name) -> #(
          [
            OntoNode(
              id: "sm:" <> name,
              name: name,
              category: OntoStateMachineDef,
              layer: 2,
              plane: "CognitiveControl",
              first_seen: now,
              last_seen: now,
              present: True,
              metadata: [#("kind", "External")],
            ),
            ..nodes_acc
          ],
          edges_acc,
        )
        InternalMachine(
          machine_name: name,
          signals: _,
          guards: _,
          actions: _,
          states: states,
          choices: _,
          initial: _,
        ) -> {
          let sm_node =
            OntoNode(
              id: "sm:" <> name,
              name: name,
              category: OntoStateMachineDef,
              layer: 2,
              plane: "CognitiveControl",
              first_seen: now,
              last_seen: now,
              present: True,
              metadata: [#("kind", "InternalFlat")],
            )

          let state_nodes =
            list.map(states, fn(s) {
              OntoNode(
                id: "st:" <> name <> "." <> s.state_name,
                name: s.state_name,
                category: OntoStateMachineDef,
                layer: 3,
                plane: "StatePlane",
                first_seen: now,
                last_seen: now,
                present: True,
                metadata: [],
              )
            })

          let trans_edges =
            list.flat_map(states, fn(s) {
              list.filter_map(s.transitions, fn(t) {
                case t.target {
                  domain.ToState(target_name) ->
                    Ok(OntoEdge(
                      source_id: "st:" <> name <> "." <> s.state_name,
                      target_id: "st:" <> name <> "." <> target_name,
                      relation: TransitsState,
                      weight: 1.0,
                      present: True,
                    ))
                  domain.ToChoice(_) -> Error(Nil)
                }
              })
            })

          #(
            list.flatten([[sm_node], state_nodes, nodes_acc]),
            list.append(trans_edges, edges_acc),
          )
        }
        HierarchicalMachine(
          machine_name: name,
          signals: _,
          guards: _,
          actions: _,
          root_states: roots,
          choices: _,
          initial: _,
        ) -> {
          let sm_node =
            OntoNode(
              id: "sm:" <> name,
              name: name,
              category: OntoStateMachineDef,
              layer: 2,
              plane: "CognitiveControl",
              first_seen: now,
              last_seen: now,
              present: True,
              metadata: [#("kind", "Hierarchical")],
            )

          let #(h_nodes, h_edges) = flatten_hierarchical_states(name, roots, [])
          #(
            list.flatten([[sm_node], h_nodes, nodes_acc]),
            list.append(h_edges, edges_acc),
          )
        }
      }
    })

  // 5. Direct Connections & Pattern Graph Edges
  let topo_edges =
    list.flat_map(model.topologies, fn(t) {
      list.flat_map(t.graphs, fn(g) {
        case g {
          Direct(_, conns) ->
            list.map(conns, fn(c) {
              OntoEdge(
                source_id: "inst:" <> c.from.ep_instance,
                target_id: "inst:" <> c.to.ep_instance,
                relation: ConnectsTo,
                weight: 1.0,
                present: True,
              )
            })
          Pattern(pat_kind, source, targets) -> {
            let rel = case pat_kind {
              domain.PTime -> PatternTimeSync
              domain.PHealth -> PatternHealthPing
              domain.PTelemetry -> PatternTlmTelemetry
              domain.PEvent -> PatternDiagEvent
              domain.PTextEvent -> PatternDiagEvent
              domain.PParam -> DefinesParameter
              domain.PCommand -> ConnectsTo
            }
            list.map(targets, fn(tgt) {
              OntoEdge(
                source_id: "inst:" <> source,
                target_id: "inst:" <> tgt,
                relation: rel,
                weight: 1.0,
                present: True,
              )
            })
          }
        }
      })
    })

  // 6. Subtopology Nodes
  let subtopo_nodes =
    list.map(model.subtopologies, fn(sub) {
      OntoNode(
        id: "subtopo:" <> sub.name,
        name: sub.name,
        category: OntoSubtopologyDef,
        layer: 3,
        plane: "SubsystemDecomposition",
        first_seen: now,
        last_seen: now,
        present: True,
        metadata: [
          #("instances_count", int.to_string(list.length(sub.instances))),
          #("exported_ports_count", int.to_string(list.length(sub.exported_ports))),
        ],
      )
    })

  // 7. Telemetry Packet Nodes & Packet Channel Edges
  let packet_nodes =
    list.map(model.packets, fn(pkt) {
      OntoNode(
        id: "pkt:" <> pkt.packet_name,
        name: pkt.packet_name,
        category: OntoPacketDef,
        layer: 2,
        plane: "DownlinkPacketPlane",
        first_seen: now,
        last_seen: now,
        present: True,
        metadata: [
          #("packet_id", int.to_string(pkt.packet_id)),
          #("channels_count", int.to_string(list.length(pkt.channel_ids))),
        ],
      )
    })

  let all_nodes =
    list.flatten([
      comp_nodes,
      detail_nodes,
      inst_nodes,
      sm_nodes,
      subtopo_nodes,
      packet_nodes,
    ])

  let all_edges =
    list.flatten([
      detail_edges,
      inst_edges,
      sm_edges,
      topo_edges,
    ])

  OntoGraph(
    nodes: all_nodes,
    edges: all_edges,
    schema_version: "2026.09.06-SIL6",
    topology_name: model.model_name,
  )
}

fn flatten_hierarchical_states(
  sm_name: String,
  states: List(domain.HierarchicalState),
  acc_nodes: List(OntoNode),
) -> #(List(OntoNode), List(OntoEdge)) {
  let now = "2026-09-06T09:40:00.000000Z"
  list.fold(states, #(acc_nodes, []), fn(acc, s) {
    let #(nodes, edges) = acc
    let this_id = "st:" <> sm_name <> "." <> s.name
    let this_node =
      OntoNode(
        id: this_id,
        name: s.name,
        category: OntoStateMachineDef,
        layer: 3,
        plane: "HierarchicalStatePlane",
        first_seen: now,
        last_seen: now,
        present: True,
        metadata: [
          #("parent", option.unwrap(s.parent, "root")),
          #("initial_sub_state", option.unwrap(s.initial_sub_state, "none")),
        ],
      )

    let parent_edge = case s.parent {
      Some(p) -> [
        OntoEdge(
          source_id: "st:" <> sm_name <> "." <> p,
          target_id: this_id,
          relation: ContainsSubstate,
          weight: 1.0,
          present: True,
        ),
      ]
      None -> []
    }

    let trans_edges =
      list.filter_map(s.transitions, fn(t) {
        case t.target {
          domain.ToState(tgt) ->
            Ok(OntoEdge(
              source_id: this_id,
              target_id: "st:" <> sm_name <> "." <> tgt,
              relation: TransitsState,
              weight: 1.0,
              present: True,
            ))
          domain.ToChoice(_) -> Error(Nil)
        }
      })

    let #(sub_nodes, sub_edges) =
      flatten_hierarchical_states(sm_name, s.sub_states, [])

    #(
      list.flatten([[this_node], sub_nodes, nodes]),
      list.flatten([parent_edge, trans_edges, sub_edges, edges]),
    )
  })
}

// =============================================================================
// 3. Topological Closure & Verification Laws
// =============================================================================

pub fn verify_ontology_closure(graph: OntoGraph) -> Result(Int, List(String)) {
  let node_ids = list.map(graph.nodes, fn(n) { n.id })

  let dangling_edges =
    list.filter(graph.edges, fn(e) {
      let src_ok = list.contains(node_ids, e.source_id)
      let tgt_ok = list.contains(node_ids, e.target_id)
      !src_ok || !tgt_ok
    })

  case dangling_edges {
    [] -> Ok(list.length(graph.nodes))
    errs -> {
      let msgs =
        list.map(errs, fn(e) {
          "Dangling edge: "
          <> e.source_id
          <> " -["
          <> relation_to_string(e.relation)
          <> "]-> "
          <> e.target_id
        })
      Error(msgs)
    }
  }
}

// =============================================================================
// 4. JSON Serialization
// =============================================================================

pub fn ontology_to_json(graph: OntoGraph) -> String {
  let nodes_json =
    list.map(graph.nodes, fn(n) {
      json.object([
        #("id", json.string(n.id)),
        #("name", json.string(n.name)),
        #("category", json.string(category_to_string(n.category))),
        #("layer", json.int(n.layer)),
        #("plane", json.string(n.plane)),
        #("first_seen", json.string(n.first_seen)),
        #("last_seen", json.string(n.last_seen)),
        #("present", json.bool(n.present)),
        #(
          "metadata",
          json.object(list.map(n.metadata, fn(m) { #(m.0, json.string(m.1)) })),
        ),
      ])
    })

  let edges_json =
    list.map(graph.edges, fn(e) {
      json.object([
        #("source", json.string(e.source_id)),
        #("target", json.string(e.target_id)),
        #("relation", json.string(relation_to_string(e.relation))),
        #("weight", json.float(e.weight)),
        #("present", json.bool(e.present)),
      ])
    })

  json.object([
    #("schema_version", json.string(graph.schema_version)),
    #("topology_name", json.string(graph.topology_name)),
    #("node_count", json.int(list.length(graph.nodes))),
    #("edge_count", json.int(list.length(graph.edges))),
    #("nodes", json.array(nodes_json, fn(x) { x })),
    #("edges", json.array(edges_json, fn(x) { x })),
  ])
  |> json.to_string
}
