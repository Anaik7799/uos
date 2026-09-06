//// =============================================================================
//// [UOS-FPP-DICTIONARY] NASA JPL F Prime Ground Dictionary Generator in Gleam
//// =============================================================================
//// Serializes an FPP Model to the NASA JPL F Prime JSON Dictionary specification:
//// - Metadata: framework version, project version, topology
//// - Commands: instance-qualified opcodes (base_id + relative), parameters
//// - Channels: instance-qualified IDs, update policies, threshold limits
//// - Events: instance-qualified IDs, severities, format strings
//// - Parameters: instance-qualified IDs, defaults, set/save opcodes
//// - Telemetry Packet Sets: packet definitions and constituent channels
//// =============================================================================

import cepaf_gleam/fpp/domain.{
  type Command, type Event, type Instance, type Model, type Parameter,
  ActivityHi, ActivityLo, Always, CommandSev, Diagnostic, Fatal, OnChange,
  WarningHi, WarningLo,
}
import gleam/json
import gleam/list
import gleam/option.{None, Some}

pub fn generate_ground_dictionary_json(
  model: Model,
  topology_name: String,
) -> String {
  let commands_json =
    list.flat_map(model.instances, fn(inst) {
      case
        list.find(model.components, fn(c) { c.comp_name == inst.of_component })
      {
        Ok(comp) ->
          list.map(comp.commands, fn(cmd) { command_to_json(inst, cmd) })
        Error(_) -> []
      }
    })

  let events_json =
    list.flat_map(model.instances, fn(inst) {
      case
        list.find(model.components, fn(c) { c.comp_name == inst.of_component })
      {
        Ok(comp) -> list.map(comp.events, fn(evt) { event_to_json(inst, evt) })
        Error(_) -> []
      }
    })

  let channels_json =
    list.flat_map(model.instances, fn(inst) {
      case
        list.find(model.components, fn(c) { c.comp_name == inst.of_component })
      {
        Ok(comp) ->
          list.map(comp.channels, fn(chn) { channel_to_json(inst, chn) })
        Error(_) -> []
      }
    })

  let parameters_json =
    list.flat_map(model.instances, fn(inst) {
      case
        list.find(model.components, fn(c) { c.comp_name == inst.of_component })
      {
        Ok(comp) ->
          list.map(comp.parameters, fn(prm) { parameter_to_json(inst, prm) })
        Error(_) -> []
      }
    })

  let packets_json =
    list.map(model.packets, fn(pkt) {
      json.object([
        #("id", json.int(pkt.packet_id)),
        #("name", json.string(pkt.packet_name)),
        #("channel_ids", json.array(pkt.channel_ids, json.int)),
        #("level", json.int(pkt.level)),
      ])
    })

  json.object([
    #(
      "metadata",
      json.object([
        #("framework_version", json.string("3.4.0-UOS")),
        #("project_version", json.string("2026.09-SIL6")),
        #("topology", json.string(topology_name)),
      ]),
    ),
    #("commands", json.array(commands_json, fn(x) { x })),
    #("events", json.array(events_json, fn(x) { x })),
    #("telemetryChannels", json.array(channels_json, fn(x) { x })),
    #("parameters", json.array(parameters_json, fn(x) { x })),
    #("telemetryPacketSets", json.array(packets_json, fn(x) { x })),
  ])
  |> json.to_string
}

fn command_to_json(inst: Instance, cmd: Command) -> json.Json {
  let absolute_opcode = inst.base_id + cmd.opcode
  json.object([
    #("name", json.string(inst.inst_name <> "." <> cmd.cmd_name)),
    #("opcode", json.int(absolute_opcode)),
    #("relative_opcode", json.int(cmd.opcode)),
    #("instance", json.string(inst.inst_name)),
  ])
}

fn event_to_json(inst: Instance, evt: Event) -> json.Json {
  let absolute_id = inst.base_id + evt.event_id
  let severity_str = case evt.severity {
    ActivityHi -> "ACTIVITY_HI"
    ActivityLo -> "ACTIVITY_LO"
    CommandSev -> "COMMAND"
    Diagnostic -> "DIAGNOSTIC"
    Fatal -> "FATAL"
    WarningHi -> "WARNING_HI"
    WarningLo -> "WARNING_LO"
  }
  json.object([
    #("name", json.string(inst.inst_name <> "." <> evt.event_name)),
    #("id", json.int(absolute_id)),
    #("severity", json.string(severity_str)),
    #("format", json.string(evt.format)),
    #("instance", json.string(inst.inst_name)),
  ])
}

fn channel_to_json(inst: Instance, chn: domain.Channel) -> json.Json {
  let absolute_id = inst.base_id + chn.chan_id
  let update_str = case chn.update {
    Always -> "always"
    OnChange -> "on_change"
  }
  json.object([
    #("name", json.string(inst.inst_name <> "." <> chn.chan_name)),
    #("id", json.int(absolute_id)),
    #("update", json.string(update_str)),
    #("instance", json.string(inst.inst_name)),
  ])
}

fn parameter_to_json(inst: Instance, prm: Parameter) -> json.Json {
  let absolute_id = inst.base_id + prm.param_id
  let default_str = case prm.default {
    Some(d) -> d
    None -> ""
  }
  json.object([
    #("name", json.string(inst.inst_name <> "." <> prm.param_name)),
    #("id", json.int(absolute_id)),
    #("default", json.string(default_str)),
    #("set_opcode", json.int(inst.base_id + prm.set_opcode)),
    #("save_opcode", json.int(inst.base_id + prm.save_opcode)),
    #("instance", json.string(inst.inst_name)),
  ])
}
