/// Wisp API for Device Health Grid (SC-GLM-UI-001, SC-GLM-UI-003).
/// STAMP: SC-GLM-UI-001, SC-GLM-UI-003, SC-GLM-UI-007
import cepaf_gleam/ui/domain.{
  type DeviceHealth, type DeviceStatus, Maintenance, Offline, Online,
}
import gleam/json
import gleam/list

pub fn health_grid_json(devices: List(DeviceHealth)) -> String {
  json.object([
    #("plane", json.string("health_grid")),
    #("device_count", json.int(list.length(devices))),
    #("devices", json.array(devices, encode_device)),
  ])
  |> json.to_string()
}

fn encode_device(device: DeviceHealth) -> json.Json {
  json.object([
    #("id", json.string(device.id)),
    #("health_score", json.float(device.health_score)),
    #("device_type", json.string(device.device_type)),
    #("status", json.string(status_to_string(device.status))),
    #("last_seen", json.int(device.last_seen)),
  ])
}

fn status_to_string(status: DeviceStatus) -> String {
  case status {
    Online -> "online"
    Offline -> "offline"
    Maintenance -> "maintenance"
  }
}
