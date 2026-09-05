/// Wisp API for Cockpit plane (SC-GLM-UI-001, SC-GLM-UI-003).
/// STAMP: SC-GLM-UI-001, SC-GLM-UI-003, SC-GLM-UI-007
import cepaf_gleam/cockpit/domain.{
  type Alarm, type AlarmLevel, type MeshNode, Advisory, Caution, Connected,
  Critical, Degraded, Disconnected, Normal, Stale, Warning,
}
import gleam/json
import gleam/list

pub fn nodes_json(nodes: List(MeshNode)) -> String {
  json.object([
    #("plane", json.string("cockpit")),
    #("node_count", json.int(list.length(nodes))),
    #("nodes", json.array(nodes, encode_node)),
  ])
  |> json.to_string()
}

pub fn alarms_json(alarms: List(Alarm)) -> String {
  json.object([
    #("plane", json.string("cockpit")),
    #("alarm_count", json.int(list.length(alarms))),
    #("alarms", json.array(alarms, encode_alarm)),
  ])
  |> json.to_string()
}

fn encode_node(node: MeshNode) -> json.Json {
  json.object([
    #("id", json.string(node.id)),
    #("name", json.string(node.name)),
    #("zone", json.string(node.zone)),
    #("status", json.string(status_string(node.status))),
    #("cpu_value", json.float(node.cpu.value)),
    #("memory_value", json.float(node.memory.value)),
    #("health_score", json.float(node.health_score.value)),
  ])
}

fn encode_alarm(alarm: Alarm) -> json.Json {
  json.object([
    #("id", json.string(alarm.id)),
    #("node_id", json.string(alarm.node_id)),
    #("level", json.string(level_string(alarm.level))),
    #("category", json.string(alarm.category)),
    #("message", json.string(alarm.message)),
    #("occurred_at", json.int(alarm.occurred_at)),
  ])
}

fn status_string(s: domain.ConnectionStatus) -> String {
  case s {
    Connected -> "connected"
    Stale -> "stale"
    Degraded -> "degraded"
    Disconnected -> "disconnected"
  }
}

fn level_string(l: AlarmLevel) -> String {
  case l {
    Critical -> "critical"
    Warning -> "warning"
    Caution -> "caution"
    Advisory -> "advisory"
    Normal -> "normal"
  }
}
