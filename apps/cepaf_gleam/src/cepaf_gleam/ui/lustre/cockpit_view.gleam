/// Lustre component for Cockpit plane (SC-GLM-UI-001).
/// Dark Cockpit pattern — anomalies surface, normal is minimal (SC-GLM-UI-008).
/// Imports from cockpit/domain.gleam — no type duplication (SC-GLM-UI-009).
/// STAMP: SC-GLM-UI-001, SC-GLM-UI-002, SC-GLM-UI-008, SC-GLM-UI-009
import cepaf_gleam/cockpit/domain.{
  type Alarm, type AlarmLevel, type MeshNode, type ViewMode, Advisory, Caution,
  Connected, Critical, Normal, Warning,
}
import cepaf_gleam/ui/domain as ui_domain
import cepaf_gleam/ui/zenoh_otel
import cepaf_gleam/ui/lustre/widgets/biomorphic_matrix.{type BiomorphicData}
import cepaf_gleam/ui/lustre/widgets/homeostasis_control.{
  type HomeostasisMsg, SetThreshold, TriggerEquilibrium,
}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order.{Eq, Gt, Lt}

pub type CockpitModel {
  CockpitModel(
    nodes: List(MeshNode),
    alarms: List(Alarm),
    view_mode: ViewMode,
    dark_cockpit: Bool,
    selected_node: Option(String),
    biomorphic_data: Option(BiomorphicData),
    cpu_threshold: Float,
    mem_threshold: Float,
    // SC-WIRE: AG-UI event stream for cockpit display
    reasoning_buffer: String,
    agui_event_count: Int,
  )
}

pub type CockpitMsg {
  NodesUpdated(List(MeshNode))
  AlarmsUpdated(List(Alarm))
  SetViewMode(ViewMode)
  SelectNode(String)
  AcknowledgeAlarm(String)
  ToggleDarkCockpit
  RefreshCockpit
  BiomorphicUpdated(BiomorphicData)
  HomeostasisEvent(HomeostasisMsg)
  // SC-WIRE: AG-UI events received from zenoh_bus
  ReasoningReceived(String)
  AgUiEventReceived(String)
}

pub fn init() -> CockpitModel {
  CockpitModel(
    nodes: [],
    alarms: [],
    view_mode: domain.Overview,
    dark_cockpit: True,
    selected_node: None,
    biomorphic_data: None,
    reasoning_buffer: "",
    agui_event_count: 0,
    cpu_threshold: 0.85,
    mem_threshold: 0.75,
  )
}

pub fn update(model: CockpitModel, msg: CockpitMsg) -> CockpitModel {
  zenoh_otel.emit(ui_domain.Cockpit, "update", zenoh_otel.Act)
  case msg {
    NodesUpdated(nodes) -> CockpitModel(..model, nodes: nodes)
    AlarmsUpdated(alarms) -> CockpitModel(..model, alarms: alarms)
    SetViewMode(mode) -> CockpitModel(..model, view_mode: mode)
    SelectNode(id) -> CockpitModel(..model, selected_node: Some(id))
    // Mark the target alarm as acknowledged by setting acknowledged_at.
    // Uses timestamp 0 as a placeholder — real value arrives via Zenoh SSE.
    // With an empty alarms list this is a structural no-op (model unchanged).
    AcknowledgeAlarm(id) ->
      CockpitModel(
        ..model,
        alarms: list.map(model.alarms, fn(a) {
          case a.id == id {
            True -> domain.Alarm(..a, acknowledged_at: Some(0))
            False -> a
          }
        }),
      )
    ToggleDarkCockpit ->
      CockpitModel(..model, dark_cockpit: !model.dark_cockpit)
    // RefreshCockpit triggers a Zenoh query to reload mesh state; the response
    // arrives as NodesUpdated/AlarmsUpdated msgs.  Model is unchanged here so
    // the pure update() function stays side-effect-free (SC-GLM-UI-002).
    RefreshCockpit -> model
    BiomorphicUpdated(data) ->
      CockpitModel(..model, biomorphic_data: Some(data))
    HomeostasisEvent(homeo_msg) ->
      case homeo_msg {
        SetThreshold("cpu", val) -> CockpitModel(..model, cpu_threshold: val)
        SetThreshold("mem", val) -> CockpitModel(..model, mem_threshold: val)
        SetThreshold(_, _) -> model
        TriggerEquilibrium -> model
      }
    // SC-WIRE: AG-UI event handlers (closes broken link 6)
    ReasoningReceived(content) ->
      CockpitModel(..model, reasoning_buffer: model.reasoning_buffer <> content)
    AgUiEventReceived(_event_json) ->
      CockpitModel(..model, agui_event_count: model.agui_event_count + 1)
  }
}

/// Dark Cockpit: only show nodes with non-normal status (SC-GLM-UI-008).
pub fn visible_nodes(model: CockpitModel) -> List(MeshNode) {
  case model.dark_cockpit {
    True -> list.filter(model.nodes, fn(n) { n.status != Connected })
    False -> model.nodes
  }
}

/// Active alarms sorted by severity (Critical first).
pub fn active_alarms(model: CockpitModel) -> List(Alarm) {
  list.filter(model.alarms, fn(a) { a.level != Normal })
  |> list.sort(fn(a, b) {
    let sa = alarm_severity_rank(a.level)
    let sb = alarm_severity_rank(b.level)
    case sa > sb {
      True -> Lt
      False ->
        case sa == sb {
          True -> Eq
          False -> Gt
        }
    }
  })
}

fn alarm_severity_rank(level: AlarmLevel) -> Int {
  case level {
    Critical -> 5
    Warning -> 4
    Caution -> 3
    Advisory -> 2
    Normal -> 1
  }
}
