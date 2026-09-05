/// Lustre component for Device Health Grid (SC-GLM-UI-001).
/// STAMP: SC-GLM-UI-001, SC-GLM-UI-002, SC-GLM-UI-009
import cepaf_gleam/ui/domain.{
  type DeviceHealth, type DeviceStatus, Maintenance, Offline, Online,
}
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

pub type HealthGridModel {
  HealthGridModel(
    devices: List(DeviceHealth),
    selected_id: Option(String),
    filter: DeviceFilter,
  )
}

pub type DeviceFilter {
  AllDevices
  HealthyOnly
  DegradedOnly
  CriticalOnly
}

pub type HealthGridMsg {
  SelectDevice(String)
  SetFilter(DeviceFilter)
  Refresh
  DevicesLoaded(List(DeviceHealth))
}

pub fn init() -> HealthGridModel {
  HealthGridModel(devices: [], selected_id: None, filter: AllDevices)
}

pub fn update(model: HealthGridModel, msg: HealthGridMsg) -> HealthGridModel {
  case msg {
    SelectDevice(id) -> HealthGridModel(..model, selected_id: Some(id))
    SetFilter(f) -> HealthGridModel(..model, filter: f)
    Refresh -> model
    DevicesLoaded(devices) -> HealthGridModel(..model, devices: devices)
  }
}

pub fn view(model: HealthGridModel) -> Element(HealthGridMsg) {
  html.div([attribute.class("health-grid-container")], [
    html.h2([], [element.text("Device Health Grid")]),
    render_filter_bar(model.filter),
    render_grid(model),
    render_details(model),
  ])
}

fn render_filter_bar(current_filter: DeviceFilter) -> Element(HealthGridMsg) {
  html.div([attribute.class("filter-bar")], [
    filter_button("All", AllDevices, current_filter),
    filter_button("Healthy", HealthyOnly, current_filter),
    filter_button("Degraded", DegradedOnly, current_filter),
    filter_button("Critical", CriticalOnly, current_filter),
  ])
}

fn filter_button(
  label: String,
  filter: DeviceFilter,
  current: DeviceFilter,
) -> Element(HealthGridMsg) {
  html.button(
    [
      attribute.class(case filter == current {
        True -> "active"
        False -> ""
      }),
      event.on_click(SetFilter(filter)),
    ],
    [element.text(label)],
  )
}

fn render_grid(model: HealthGridModel) -> Element(HealthGridMsg) {
  let filtered = case model.filter {
    AllDevices -> model.devices
    HealthyOnly -> list.filter(model.devices, fn(d) { d.health_score >. 0.8 })
    DegradedOnly ->
      list.filter(model.devices, fn(d) {
        d.health_score <=. 0.8 && d.health_score >. 0.5
      })
    CriticalOnly -> list.filter(model.devices, fn(d) { d.health_score <=. 0.5 })
  }

  html.div(
    [attribute.class("device-grid")],
    list.map(filtered, render_device_cell(_, model.selected_id)),
  )
}

fn render_device_cell(
  device: DeviceHealth,
  selected_id: Option(String),
) -> Element(HealthGridMsg) {
  let is_selected = case selected_id {
    Some(id) -> id == device.id
    None -> False
  }

  let color_class = case True {
    _ if device.health_score >. 0.8 -> "healthy"
    _ if device.health_score >. 0.5 -> "degraded"
    _ -> "critical"
  }

  html.div(
    [
      attribute.class(
        "device-cell "
        <> color_class
        <> case is_selected {
          True -> " selected"
          False -> ""
        },
      ),
      event.on_click(SelectDevice(device.id)),
    ],
    [
      html.span([attribute.class("device-id")], [element.text(device.id)]),
      html.span([attribute.class("health-pct")], [
        element.text(float_to_pct(device.health_score)),
      ]),
    ],
  )
}

fn render_details(model: HealthGridModel) -> Element(HealthGridMsg) {
  case model.selected_id {
    Some(id) -> {
      let device = list.find(model.devices, fn(d) { d.id == id })
      case device {
        Ok(d) ->
          html.div([attribute.class("device-details")], [
            html.h3([], [element.text("Device: " <> d.id)]),
            html.p([], [element.text("Type: " <> d.device_type)]),
            html.p([], [element.text("Status: " <> status_to_string(d.status))]),
            html.p([], [
              element.text("Health Score: " <> float.to_string(d.health_score)),
            ]),
            html.p([], [
              element.text("Last Seen: " <> int.to_string(d.last_seen)),
            ]),
          ])
        Error(_) -> html.div([], [element.text("Device not found")])
      }
    }
    None -> html.div([], [element.text("Select a device for details")])
  }
}

fn status_to_string(status: DeviceStatus) -> String {
  case status {
    Online -> "Online"
    Offline -> "Offline"
    Maintenance -> "Maintenance"
  }
}

fn float_to_pct(f: Float) -> String {
  int.to_string(float.round(f *. 100.0)) <> "%"
}
