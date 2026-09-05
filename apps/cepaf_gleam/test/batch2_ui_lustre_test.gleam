// =============================================================================
// Batch 2: UI Lustre Module Tests
// =============================================================================
// Coverage: ui/domain, ui/lustre/app, ui/lustre/cockpit_view, ui/lustre/immune,
//           ui/lustre/knowledge, ui/lustre/planning, ui/lustre/verification,
//           ui/lustre/zenoh_mesh
// STAMP: SC-GLM-UI-001, SC-GLM-UI-009

import cepaf_gleam/cockpit/domain as cockpit_domain
import cepaf_gleam/immune/domain as immune_domain
import cepaf_gleam/knowledge/domain as knowledge_domain
import cepaf_gleam/ui/domain
import cepaf_gleam/ui/lustre/app
import cepaf_gleam/ui/lustre/cockpit_view
import cepaf_gleam/ui/lustre/immune
import cepaf_gleam/ui/lustre/knowledge
import cepaf_gleam/ui/lustre/planning
import cepaf_gleam/ui/lustre/verification
import cepaf_gleam/ui/lustre/zenoh_mesh
import cepaf_gleam/verification/swarm
import cepaf_gleam/zenoh/domain as zenoh_domain
import gleam/list
import gleam/option.{None, Some}
import gleeunit/should

// =============================================================================
// ui/domain — page_to_path
// =============================================================================

pub fn page_to_path_dashboard_test() {
  domain.page_to_path(domain.Dashboard)
  |> should.equal("/dashboard")
}

pub fn page_to_path_planning_test() {
  domain.page_to_path(domain.Planning)
  |> should.equal("/planning")
}

pub fn page_to_path_immune_test() {
  domain.page_to_path(domain.Immune)
  |> should.equal("/immune")
}

pub fn page_to_path_knowledge_test() {
  domain.page_to_path(domain.Knowledge)
  |> should.equal("/knowledge")
}

pub fn page_to_path_zenoh_test() {
  domain.page_to_path(domain.Zenoh)
  |> should.equal("/zenoh")
}

pub fn page_to_path_cockpit_test() {
  domain.page_to_path(domain.Cockpit)
  |> should.equal("/cockpit")
}

pub fn page_to_path_verification_test() {
  domain.page_to_path(domain.Verification)
  |> should.equal("/verification")
}

pub fn page_to_path_substrate_test() {
  domain.page_to_path(domain.Substrate)
  |> should.equal("/substrate")
}

// =============================================================================
// ui/domain — page_to_label
// =============================================================================

pub fn page_to_label_dashboard_test() {
  domain.page_to_label(domain.Dashboard)
  |> should.equal("Dashboard")
}

pub fn page_to_label_planning_test() {
  domain.page_to_label(domain.Planning)
  |> should.equal("Planning")
}

pub fn page_to_label_immune_test() {
  domain.page_to_label(domain.Immune)
  |> should.equal("Immune System")
}

pub fn page_to_label_knowledge_test() {
  domain.page_to_label(domain.Knowledge)
  |> should.equal("Knowledge (Smriti)")
}

pub fn page_to_label_zenoh_test() {
  domain.page_to_label(domain.Zenoh)
  |> should.equal("Zenoh Mesh")
}

pub fn page_to_label_cockpit_test() {
  domain.page_to_label(domain.Cockpit)
  |> should.equal("Cockpit")
}

pub fn page_to_label_verification_test() {
  domain.page_to_label(domain.Verification)
  |> should.equal("Verification")
}

pub fn page_to_label_substrate_test() {
  domain.page_to_label(domain.Substrate)
  |> should.equal("Substrate")
}

// =============================================================================
// ui/lustre/app — init
// =============================================================================

pub fn app_init_defaults_test() {
  let model = app.init()
  model.dark_cockpit |> should.be_true()
  model.selected_page |> should.equal(domain.Dashboard)
  model.context.page |> should.equal(domain.Dashboard)
  model.context.health |> should.equal(domain.Unknown)
  model.context.telemetry |> should.equal([])
  model.context.zenoh_connected |> should.equal(False)
}

// =============================================================================
// ui/lustre/app — update (all Msg variants)
// =============================================================================

pub fn app_update_navigate_to_test() {
  let model = app.init()
  let updated = app.update(model, app.NavigateTo(domain.Planning))
  updated.selected_page |> should.equal(domain.Planning)
}

pub fn app_update_telemetry_received_test() {
  let model = app.init()
  let point =
    domain.TelemetryPoint(key: "cpu", value: 0.75, timestamp: 1000, unit: "%")
  let updated = app.update(model, app.TelemetryReceived(point))
  list.length(updated.context.telemetry) |> should.equal(1)
}

pub fn app_update_telemetry_prepends_test() {
  let model = app.init()
  let p1 =
    domain.TelemetryPoint(key: "cpu", value: 0.5, timestamp: 1, unit: "%")
  let p2 =
    domain.TelemetryPoint(key: "mem", value: 0.8, timestamp: 2, unit: "GB")
  let updated =
    model
    |> app.update(app.TelemetryReceived(p1))
    |> app.update(app.TelemetryReceived(p2))
  list.length(updated.context.telemetry) |> should.equal(2)
}

pub fn app_update_health_updated_test() {
  let model = app.init()
  let updated = app.update(model, app.HealthUpdated(domain.Healthy))
  updated.context.health |> should.equal(domain.Healthy)
}

pub fn app_update_health_degraded_test() {
  let model = app.init()
  let updated =
    app.update(model, app.HealthUpdated(domain.Degraded("high load")))
  updated.context.health |> should.equal(domain.Degraded("high load"))
}

pub fn app_update_health_critical_test() {
  let model = app.init()
  let updated =
    app.update(model, app.HealthUpdated(domain.Critical("node down")))
  updated.context.health |> should.equal(domain.Critical("node down"))
}

pub fn app_update_zenoh_connection_changed_test() {
  let model = app.init()
  let updated = app.update(model, app.ZenohConnectionChanged(True))
  updated.context.zenoh_connected |> should.equal(True)
}

pub fn app_update_zenoh_disconnect_test() {
  let model = app.init()
  let updated =
    model
    |> app.update(app.ZenohConnectionChanged(True))
    |> app.update(app.ZenohConnectionChanged(False))
  updated.context.zenoh_connected |> should.equal(False)
}

pub fn app_update_toggle_dark_cockpit_test() {
  let model = app.init()
  // starts True, toggle once -> False
  let updated = app.update(model, app.ToggleDarkCockpit)
  updated.dark_cockpit |> should.be_false()
  // toggle again -> True
  let updated2 = app.update(updated, app.ToggleDarkCockpit)
  updated2.dark_cockpit |> should.be_true()
}

pub fn app_update_tick_noop_test() {
  let model = app.init()
  let updated = app.update(model, app.Tick)
  updated |> should.equal(model)
}

// =============================================================================
// ui/lustre/app — health_class
// =============================================================================

pub fn health_class_healthy_test() {
  app.health_class(domain.Healthy) |> should.equal("health-ok")
}

pub fn health_class_degraded_test() {
  app.health_class(domain.Degraded("lag")) |> should.equal("health-warn")
}

pub fn health_class_critical_test() {
  app.health_class(domain.Critical("crash")) |> should.equal("health-critical")
}

pub fn health_class_unknown_test() {
  app.health_class(domain.Unknown) |> should.equal("health-unknown")
}

// =============================================================================
// ui/lustre/cockpit_view — init
// =============================================================================

pub fn cockpit_init_defaults_test() {
  let model = cockpit_view.init()
  model.nodes |> should.equal([])
  model.alarms |> should.equal([])
  model.view_mode |> should.equal(cockpit_domain.Overview)
  model.dark_cockpit |> should.be_true()
  model.selected_node |> should.equal(None)
}

// =============================================================================
// ui/lustre/cockpit_view — update
// =============================================================================

pub fn cockpit_update_set_view_mode_test() {
  let model = cockpit_view.init()
  let updated =
    cockpit_view.update(model, cockpit_view.SetViewMode(cockpit_domain.Alarms))
  updated.view_mode |> should.equal(cockpit_domain.Alarms)
}

pub fn cockpit_update_select_node_test() {
  let model = cockpit_view.init()
  let updated = cockpit_view.update(model, cockpit_view.SelectNode("node-1"))
  updated.selected_node |> should.equal(Some("node-1"))
}

pub fn cockpit_update_toggle_dark_cockpit_test() {
  let model = cockpit_view.init()
  let updated = cockpit_view.update(model, cockpit_view.ToggleDarkCockpit)
  updated.dark_cockpit |> should.be_false()
}

pub fn cockpit_update_refresh_noop_test() {
  let model = cockpit_view.init()
  let updated = cockpit_view.update(model, cockpit_view.RefreshCockpit)
  updated |> should.equal(model)
}

pub fn cockpit_update_acknowledge_alarm_noop_test() {
  let model = cockpit_view.init()
  let updated = cockpit_view.update(model, cockpit_view.AcknowledgeAlarm("a1"))
  updated |> should.equal(model)
}

// =============================================================================
// ui/lustre/cockpit_view — visible_nodes (Dark Cockpit filtering)
// =============================================================================

fn make_smart_metric() -> cockpit_domain.SmartMetric {
  cockpit_domain.SmartMetric(
    value: 50.0,
    previous_value: None,
    last_updated: 0,
    trend: cockpit_domain.Stable,
    level: cockpit_domain.Normal,
    thresholds: None,
    unit: "%",
    label: "metric",
    sparkline: [],
  )
}

fn make_mesh_node(
  id: String,
  status: cockpit_domain.ConnectionStatus,
) -> cockpit_domain.MeshNode {
  let m = make_smart_metric()
  cockpit_domain.MeshNode(
    id: id,
    name: "Node " <> id,
    zone: "zone-a",
    role: cockpit_domain.Worker,
    status: status,
    cpu: m,
    memory: m,
    battery: None,
    network_latency: m,
    capabilities: [],
    health_score: m,
    location: None,
    ai_insight: None,
    ai_insight_updated_at: None,
  )
}

pub fn cockpit_visible_nodes_dark_cockpit_filters_connected_test() {
  let nodes = [
    make_mesh_node("n1", cockpit_domain.Connected),
    make_mesh_node("n2", cockpit_domain.Degraded),
    make_mesh_node("n3", cockpit_domain.Disconnected),
  ]
  let model =
    cockpit_view.CockpitModel(
      nodes: nodes,
      alarms: [],
      view_mode: cockpit_domain.Overview,
      dark_cockpit: True,
      selected_node: None,
      biomorphic_data: None,
      cpu_threshold: 0.85,
      mem_threshold: 0.75,
      reasoning_buffer: "",
      agui_event_count: 0,
    )
  let visible = cockpit_view.visible_nodes(model)
  // Dark cockpit hides Connected nodes — only non-Connected show
  list.length(visible) |> should.equal(2)
}

pub fn cockpit_visible_nodes_normal_mode_shows_all_test() {
  let nodes = [
    make_mesh_node("n1", cockpit_domain.Connected),
    make_mesh_node("n2", cockpit_domain.Degraded),
  ]
  let model =
    cockpit_view.CockpitModel(
      nodes: nodes,
      alarms: [],
      view_mode: cockpit_domain.Overview,
      dark_cockpit: False,
      selected_node: None,
      biomorphic_data: None,
      cpu_threshold: 0.85,
      mem_threshold: 0.75,
      reasoning_buffer: "",
      agui_event_count: 0,
    )
  let visible = cockpit_view.visible_nodes(model)
  list.length(visible) |> should.equal(2)
}

pub fn cockpit_visible_nodes_empty_test() {
  let model = cockpit_view.init()
  cockpit_view.visible_nodes(model) |> should.equal([])
}

// =============================================================================
// ui/lustre/cockpit_view — active_alarms (severity sorting)
// =============================================================================

fn make_alarm(
  id: String,
  level: cockpit_domain.AlarmLevel,
) -> cockpit_domain.Alarm {
  cockpit_domain.Alarm(
    id: id,
    node_id: "node-1",
    level: level,
    category: "test",
    message: "test alarm",
    details: None,
    occurred_at: 0,
    acknowledged_at: None,
    acknowledged_by: None,
    auto_clearable: False,
  )
}

pub fn cockpit_active_alarms_filters_normal_test() {
  let alarms = [
    make_alarm("a1", cockpit_domain.Normal),
    make_alarm("a2", cockpit_domain.Warning),
    make_alarm("a3", cockpit_domain.Critical),
  ]
  let model =
    cockpit_view.CockpitModel(
      nodes: [],
      alarms: alarms,
      view_mode: cockpit_domain.Overview,
      dark_cockpit: True,
      selected_node: None,
      biomorphic_data: None,
      cpu_threshold: 0.85,
      mem_threshold: 0.75,
      reasoning_buffer: "",
      agui_event_count: 0,
    )
  let active = cockpit_view.active_alarms(model)
  // Normal alarm filtered out, so 2 remain
  list.length(active) |> should.equal(2)
}

pub fn cockpit_active_alarms_sorted_critical_first_test() {
  let alarms = [
    make_alarm("a1", cockpit_domain.Advisory),
    make_alarm("a2", cockpit_domain.Critical),
    make_alarm("a3", cockpit_domain.Warning),
  ]
  let model =
    cockpit_view.CockpitModel(
      nodes: [],
      alarms: alarms,
      view_mode: cockpit_domain.Overview,
      dark_cockpit: True,
      selected_node: None,
      biomorphic_data: None,
      cpu_threshold: 0.85,
      mem_threshold: 0.75,
      reasoning_buffer: "",
      agui_event_count: 0,
    )
  let active = cockpit_view.active_alarms(model)
  // First alarm should be Critical (highest severity)
  case active {
    [first, ..] -> first.id |> should.equal("a2")
    _ -> should.fail()
  }
}

pub fn cockpit_active_alarms_empty_when_all_normal_test() {
  let alarms = [
    make_alarm("a1", cockpit_domain.Normal),
    make_alarm("a2", cockpit_domain.Normal),
  ]
  let model =
    cockpit_view.CockpitModel(
      nodes: [],
      alarms: alarms,
      view_mode: cockpit_domain.Overview,
      dark_cockpit: True,
      selected_node: None,
      biomorphic_data: None,
      cpu_threshold: 0.85,
      mem_threshold: 0.75,
      reasoning_buffer: "",
      agui_event_count: 0,
    )
  cockpit_view.active_alarms(model) |> should.equal([])
}

// =============================================================================
// ui/lustre/immune — init
// =============================================================================

pub fn immune_init_defaults_test() {
  let model = immune.init()
  model.antibodies |> should.equal([])
  model.recent_events |> should.equal([])
  model.active_attacks |> should.equal([])
  model.mara_running |> should.be_false()
}

// =============================================================================
// ui/lustre/immune — update
// =============================================================================

pub fn immune_update_antibody_added_test() {
  let model = immune.init()
  let ab =
    immune_domain.Antibody(
      id: "ab1",
      target_pattern: "*.crash",
      reason: "test",
      expires_at: 9999,
    )
  let updated = immune.update(model, immune.AntibodyAdded(ab))
  list.length(updated.antibodies) |> should.equal(1)
}

pub fn immune_update_event_received_test() {
  let model = immune.init()
  let evt = immune_domain.AttackBlocked(id: "ev1", reason: "blocked")
  let updated = immune.update(model, immune.EventReceived(evt))
  list.length(updated.recent_events) |> should.equal(1)
}

pub fn immune_update_attack_detected_test() {
  let model = immune.init()
  let atk = immune_domain.ContainerAssault(name: "nginx", mode: "kill")
  let updated = immune.update(model, immune.AttackDetected(atk))
  list.length(updated.active_attacks) |> should.equal(1)
}

pub fn immune_update_attack_resolved_noop_test() {
  let model = immune.init()
  let updated = immune.update(model, immune.AttackResolved("atk1"))
  updated |> should.equal(model)
}

pub fn immune_update_toggle_mara_test() {
  let model = immune.init()
  let updated = immune.update(model, immune.ToggleMara)
  updated.mara_running |> should.be_true()
  let updated2 = immune.update(updated, immune.ToggleMara)
  updated2.mara_running |> should.be_false()
}

pub fn immune_update_refresh_noop_test() {
  let model = immune.init()
  let updated = immune.update(model, immune.RefreshImmune)
  updated |> should.equal(model)
}

// =============================================================================
// ui/lustre/immune — threat_level
// =============================================================================

pub fn immune_threat_level_nominal_test() {
  let model = immune.init()
  immune.threat_level(model) |> should.equal("nominal")
}

pub fn immune_threat_level_elevated_one_attack_test() {
  let model = immune.init()
  let atk = immune_domain.HeartbeatSabotage(target: "node-1")
  let updated = immune.update(model, immune.AttackDetected(atk))
  immune.threat_level(updated) |> should.equal("elevated")
}

pub fn immune_threat_level_elevated_two_attacks_test() {
  let model = immune.init()
  let atk1 = immune_domain.HeartbeatSabotage(target: "node-1")
  let atk2 = immune_domain.ZenohFlood(topic: "test", count: 100)
  let updated =
    model
    |> immune.update(immune.AttackDetected(atk1))
    |> immune.update(immune.AttackDetected(atk2))
  immune.threat_level(updated) |> should.equal("elevated")
}

pub fn immune_threat_level_critical_three_attacks_test() {
  let model = immune.init()
  let atk1 = immune_domain.HeartbeatSabotage(target: "n1")
  let atk2 = immune_domain.ZenohFlood(topic: "t", count: 10)
  let atk3 = immune_domain.ResourceDrain(cpu_percent: 90, duration_ms: 5000)
  let updated =
    model
    |> immune.update(immune.AttackDetected(atk1))
    |> immune.update(immune.AttackDetected(atk2))
    |> immune.update(immune.AttackDetected(atk3))
  immune.threat_level(updated) |> should.equal("critical")
}

// =============================================================================
// ui/lustre/knowledge — init
// =============================================================================

pub fn knowledge_init_defaults_test() {
  let model = knowledge.init()
  model.nodes |> should.equal([])
  model.links |> should.equal([])
  model.selected_node |> should.equal(None)
  model.filter_level |> should.equal(None)
  model.search_query |> should.equal("")
}

// =============================================================================
// ui/lustre/knowledge — update
// =============================================================================

pub fn knowledge_update_select_node_test() {
  let model = knowledge.init()
  let updated = knowledge.update(model, knowledge.SelectNode("kn-1"))
  updated.selected_node |> should.equal(Some("kn-1"))
}

pub fn knowledge_update_set_level_filter_test() {
  let model = knowledge.init()
  let updated =
    knowledge.update(
      model,
      knowledge.SetLevelFilter(Some(knowledge_domain.Atomic)),
    )
  updated.filter_level |> should.equal(Some(knowledge_domain.Atomic))
}

pub fn knowledge_update_set_level_filter_none_test() {
  let model = knowledge.init()
  let updated = knowledge.update(model, knowledge.SetLevelFilter(None))
  updated.filter_level |> should.equal(None)
}

pub fn knowledge_update_set_search_test() {
  let model = knowledge.init()
  let updated = knowledge.update(model, knowledge.SetSearch("zenoh"))
  updated.search_query |> should.equal("zenoh")
}

pub fn knowledge_update_nodes_loaded_test() {
  let model = knowledge.init()
  let node =
    knowledge_domain.KnowledgeNode(
      id: "k1",
      title: "Test",
      level: knowledge_domain.Atomic,
      rhetorical: knowledge_domain.Axiom,
      entropy: 0.1,
      drift: 0.0,
      tags: [],
    )
  let link =
    knowledge_domain.KnowledgeLink(
      source_id: "k1",
      target_id: "k2",
      relation_type: "depends_on",
    )
  let updated = knowledge.update(model, knowledge.NodesLoaded([node], [link]))
  list.length(updated.nodes) |> should.equal(1)
  list.length(updated.links) |> should.equal(1)
}

pub fn knowledge_update_refresh_noop_test() {
  let model = knowledge.init()
  let updated = knowledge.update(model, knowledge.RefreshKnowledge)
  updated |> should.equal(model)
}

// =============================================================================
// ui/lustre/knowledge — filtered_nodes
// =============================================================================

fn make_knowledge_node(
  id: String,
  level: knowledge_domain.HolonLevel,
) -> knowledge_domain.KnowledgeNode {
  knowledge_domain.KnowledgeNode(
    id: id,
    title: "Node " <> id,
    level: level,
    rhetorical: knowledge_domain.Evidence,
    entropy: 0.5,
    drift: 0.0,
    tags: [],
  )
}

pub fn knowledge_filtered_nodes_no_filter_test() {
  let nodes = [
    make_knowledge_node("a", knowledge_domain.Atomic),
    make_knowledge_node("b", knowledge_domain.Ecosystem),
  ]
  let model =
    knowledge.KnowledgeModel(
      nodes: nodes,
      links: [],
      selected_node: None,
      filter_level: None,
      search_query: "",
    )
  knowledge.filtered_nodes(model) |> list.length |> should.equal(2)
}

pub fn knowledge_filtered_nodes_with_filter_test() {
  let nodes = [
    make_knowledge_node("a", knowledge_domain.Atomic),
    make_knowledge_node("b", knowledge_domain.Ecosystem),
    make_knowledge_node("c", knowledge_domain.Atomic),
  ]
  let model =
    knowledge.KnowledgeModel(
      nodes: nodes,
      links: [],
      selected_node: None,
      filter_level: Some(knowledge_domain.Atomic),
      search_query: "",
    )
  knowledge.filtered_nodes(model) |> list.length |> should.equal(2)
}

pub fn knowledge_filtered_nodes_empty_result_test() {
  let nodes = [
    make_knowledge_node("a", knowledge_domain.Atomic),
  ]
  let model =
    knowledge.KnowledgeModel(
      nodes: nodes,
      links: [],
      selected_node: None,
      filter_level: Some(knowledge_domain.Organism),
      search_query: "",
    )
  knowledge.filtered_nodes(model) |> should.equal([])
}

// =============================================================================
// ui/lustre/knowledge — node_count_by_level
// =============================================================================

pub fn knowledge_node_count_by_level_test() {
  let nodes = [
    make_knowledge_node("a", knowledge_domain.Atomic),
    make_knowledge_node("b", knowledge_domain.Atomic),
    make_knowledge_node("c", knowledge_domain.Molecular),
    make_knowledge_node("d", knowledge_domain.Ecosystem),
  ]
  knowledge.node_count_by_level(nodes, knowledge_domain.Atomic)
  |> should.equal(2)
  knowledge.node_count_by_level(nodes, knowledge_domain.Molecular)
  |> should.equal(1)
  knowledge.node_count_by_level(nodes, knowledge_domain.Ecosystem)
  |> should.equal(1)
  knowledge.node_count_by_level(nodes, knowledge_domain.Organism)
  |> should.equal(0)
}

// =============================================================================
// ui/lustre/planning — init
// =============================================================================

pub fn planning_init_defaults_test() {
  let model = planning.init()
  model.tasks |> should.equal([])
  model.filter |> should.equal(planning.AllTasks)
  model.selected_id |> should.equal(None)
}

// =============================================================================
// ui/lustre/planning — update
// =============================================================================

pub fn planning_update_set_filter_test() {
  let model = planning.init()
  let updated = planning.update(model, planning.SetFilter(planning.PendingOnly))
  updated.filter |> should.equal(planning.PendingOnly)
}

pub fn planning_update_select_task_test() {
  let model = planning.init()
  let updated = planning.update(model, planning.SelectTask("t-1"))
  updated.selected_id |> should.equal(Some("t-1"))
}

pub fn planning_update_refresh_noop_test() {
  let model = planning.init()
  let updated = planning.update(model, planning.RefreshTasks)
  updated |> should.equal(model)
}

pub fn planning_update_tasks_loaded_test() {
  let model = planning.init()
  let task =
    planning.PlanningTask(
      id: "t1",
      title: "Fix bug",
      status: "pending",
      priority: "P1",
      owner: None,
    )
  let updated = planning.update(model, planning.TasksLoaded([task]))
  list.length(updated.tasks) |> should.equal(1)
}

// =============================================================================
// ui/lustre/planning — filtered_tasks
// =============================================================================

fn make_planning_task(id: String, status: String) -> planning.PlanningTask {
  planning.PlanningTask(
    id: id,
    title: "Task " <> id,
    status: status,
    priority: "P2",
    owner: None,
  )
}

pub fn planning_filtered_tasks_all_test() {
  let tasks = [
    make_planning_task("1", "pending"),
    make_planning_task("2", "completed"),
    make_planning_task("3", "in_progress"),
  ]
  let model =
    planning.PlanningModel(
      tasks: tasks,
      filter: planning.AllTasks,
      selected_id: None,
    )
  planning.filtered_tasks(model) |> list.length |> should.equal(3)
}

pub fn planning_filtered_tasks_pending_only_test() {
  let tasks = [
    make_planning_task("1", "pending"),
    make_planning_task("2", "completed"),
    make_planning_task("3", "pending"),
  ]
  let model =
    planning.PlanningModel(
      tasks: tasks,
      filter: planning.PendingOnly,
      selected_id: None,
    )
  planning.filtered_tasks(model) |> list.length |> should.equal(2)
}

pub fn planning_filtered_tasks_in_progress_only_test() {
  let tasks = [
    make_planning_task("1", "in_progress"),
    make_planning_task("2", "completed"),
  ]
  let model =
    planning.PlanningModel(
      tasks: tasks,
      filter: planning.InProgressOnly,
      selected_id: None,
    )
  planning.filtered_tasks(model) |> list.length |> should.equal(1)
}

pub fn planning_filtered_tasks_completed_only_test() {
  let tasks = [
    make_planning_task("1", "completed"),
    make_planning_task("2", "pending"),
  ]
  let model =
    planning.PlanningModel(
      tasks: tasks,
      filter: planning.CompletedOnly,
      selected_id: None,
    )
  planning.filtered_tasks(model) |> list.length |> should.equal(1)
}

pub fn planning_filtered_tasks_blocked_only_test() {
  let tasks = [
    make_planning_task("1", "blocked"),
    make_planning_task("2", "pending"),
    make_planning_task("3", "blocked"),
  ]
  let model =
    planning.PlanningModel(
      tasks: tasks,
      filter: planning.BlockedOnly,
      selected_id: None,
    )
  planning.filtered_tasks(model) |> list.length |> should.equal(2)
}

// =============================================================================
// ui/lustre/planning — task_count_by_status
// =============================================================================

pub fn planning_task_count_by_status_test() {
  let tasks = [
    make_planning_task("1", "pending"),
    make_planning_task("2", "pending"),
    make_planning_task("3", "completed"),
    make_planning_task("4", "blocked"),
  ]
  planning.task_count_by_status(tasks, "pending") |> should.equal(2)
  planning.task_count_by_status(tasks, "completed") |> should.equal(1)
  planning.task_count_by_status(tasks, "blocked") |> should.equal(1)
  planning.task_count_by_status(tasks, "in_progress") |> should.equal(0)
}

// =============================================================================
// ui/lustre/verification — init
// =============================================================================

pub fn verification_init_defaults_test() {
  let model = verification.init()
  model.last_report |> should.equal(None)
  model.running |> should.be_false()
  model.history |> should.equal([])
}

// =============================================================================
// ui/lustre/verification — update
// =============================================================================

pub fn verification_update_start_test() {
  let model = verification.init()
  let updated = verification.update(model, verification.StartVerification)
  updated.running |> should.be_true()
}

pub fn verification_update_report_received_test() {
  let model = verification.init()
  let report =
    swarm.SwarmReport(
      healthy_containers: 12,
      total_containers: 15,
      ooda_metrics: swarm.OodaMetrics(
        agent_latency_ms: 20,
        intelligence_latency_ms: 50,
        compliance: True,
      ),
      fractal_layers: [],
    )
  let started = verification.update(model, verification.StartVerification)
  let updated =
    verification.update(started, verification.ReportReceived(report))
  updated.running |> should.be_false()
  updated.last_report |> should.equal(Some(report))
  list.length(updated.history) |> should.equal(1)
}

pub fn verification_update_refresh_noop_test() {
  let model = verification.init()
  let updated = verification.update(model, verification.RefreshVerification)
  updated |> should.equal(model)
}

// =============================================================================
// ui/lustre/verification — compliance_percent
// =============================================================================

pub fn verification_compliance_percent_all_healthy_test() {
  let report =
    swarm.SwarmReport(
      healthy_containers: 15,
      total_containers: 15,
      ooda_metrics: swarm.OodaMetrics(
        agent_latency_ms: 10,
        intelligence_latency_ms: 40,
        compliance: True,
      ),
      fractal_layers: [],
    )
  verification.compliance_percent(report) |> should.equal(100.0)
}

pub fn verification_compliance_percent_partial_test() {
  let report =
    swarm.SwarmReport(
      healthy_containers: 12,
      total_containers: 15,
      ooda_metrics: swarm.OodaMetrics(
        agent_latency_ms: 10,
        intelligence_latency_ms: 40,
        compliance: True,
      ),
      fractal_layers: [],
    )
  verification.compliance_percent(report) |> should.equal(80.0)
}

pub fn verification_compliance_percent_zero_total_test() {
  let report =
    swarm.SwarmReport(
      healthy_containers: 0,
      total_containers: 0,
      ooda_metrics: swarm.OodaMetrics(
        agent_latency_ms: 0,
        intelligence_latency_ms: 0,
        compliance: False,
      ),
      fractal_layers: [],
    )
  verification.compliance_percent(report) |> should.equal(0.0)
}

pub fn verification_compliance_percent_none_healthy_test() {
  let report =
    swarm.SwarmReport(
      healthy_containers: 0,
      total_containers: 10,
      ooda_metrics: swarm.OodaMetrics(
        agent_latency_ms: 0,
        intelligence_latency_ms: 0,
        compliance: False,
      ),
      fractal_layers: [],
    )
  verification.compliance_percent(report) |> should.equal(0.0)
}

// =============================================================================
// ui/lustre/zenoh_mesh — init
// =============================================================================

pub fn zenoh_mesh_init_defaults_test() {
  let model = zenoh_mesh.init()
  model.health |> should.equal(zenoh_domain.empty_health())
  model.lifecycle |> should.equal(zenoh_domain.Uninitialized)
  model.subscriptions |> should.equal([])
  model.message_log |> should.equal([])
}

// =============================================================================
// ui/lustre/zenoh_mesh — update
// =============================================================================

pub fn zenoh_mesh_update_health_updated_test() {
  let model = zenoh_mesh.init()
  let health =
    zenoh_domain.ZenohHealth(
      status: zenoh_domain.Connected,
      session_id: "s1",
      connected_at: 100,
      last_heartbeat: 200,
      reconnect_count: 0,
      messages_published: 50,
      messages_received: 30,
      error_count: 0,
    )
  let updated = zenoh_mesh.update(model, zenoh_mesh.HealthUpdated(health))
  updated.health.status |> should.equal(zenoh_domain.Connected)
  updated.health.session_id |> should.equal("s1")
}

pub fn zenoh_mesh_update_lifecycle_changed_test() {
  let model = zenoh_mesh.init()
  let updated =
    zenoh_mesh.update(
      model,
      zenoh_mesh.LifecycleChanged(zenoh_domain.Running(connected_at: 42)),
    )
  updated.lifecycle |> should.equal(zenoh_domain.Running(connected_at: 42))
}

pub fn zenoh_mesh_update_message_received_test() {
  let model = zenoh_mesh.init()
  let updated =
    zenoh_mesh.update(
      model,
      zenoh_mesh.MessageReceived(key: "sensor/temp", size: 128, timestamp: 1000),
    )
  list.length(updated.message_log) |> should.equal(1)
}

pub fn zenoh_mesh_update_subscription_added_test() {
  let model = zenoh_mesh.init()
  let updated =
    zenoh_mesh.update(model, zenoh_mesh.SubscriptionAdded(topic: "sensor/**"))
  list.length(updated.subscriptions) |> should.equal(1)
}

pub fn zenoh_mesh_update_subscription_removed_test() {
  let model = zenoh_mesh.init()
  let with_sub =
    zenoh_mesh.update(model, zenoh_mesh.SubscriptionAdded(topic: "sensor/**"))
  let updated =
    zenoh_mesh.update(
      with_sub,
      zenoh_mesh.SubscriptionRemoved(topic: "sensor/**"),
    )
  updated.subscriptions |> should.equal([])
}

pub fn zenoh_mesh_update_refresh_noop_test() {
  let model = zenoh_mesh.init()
  let updated = zenoh_mesh.update(model, zenoh_mesh.RefreshZenoh)
  updated |> should.equal(model)
}

// =============================================================================
// ui/lustre/zenoh_mesh — is_connected
// =============================================================================

pub fn zenoh_mesh_is_connected_false_by_default_test() {
  let model = zenoh_mesh.init()
  zenoh_mesh.is_connected(model) |> should.be_false()
}

pub fn zenoh_mesh_is_connected_true_when_connected_test() {
  let model = zenoh_mesh.init()
  let health =
    zenoh_domain.ZenohHealth(
      status: zenoh_domain.Connected,
      session_id: "s1",
      connected_at: 100,
      last_heartbeat: 200,
      reconnect_count: 0,
      messages_published: 0,
      messages_received: 0,
      error_count: 0,
    )
  let updated = zenoh_mesh.update(model, zenoh_mesh.HealthUpdated(health))
  zenoh_mesh.is_connected(updated) |> should.be_true()
}

pub fn zenoh_mesh_is_connected_false_when_connecting_test() {
  let model = zenoh_mesh.init()
  let health =
    zenoh_domain.ZenohHealth(
      status: zenoh_domain.Connecting,
      session_id: "",
      connected_at: 0,
      last_heartbeat: 0,
      reconnect_count: 0,
      messages_published: 0,
      messages_received: 0,
      error_count: 0,
    )
  let updated = zenoh_mesh.update(model, zenoh_mesh.HealthUpdated(health))
  zenoh_mesh.is_connected(updated) |> should.be_false()
}

// =============================================================================
// ui/lustre/zenoh_mesh — message_rate
// =============================================================================

pub fn zenoh_mesh_message_rate_zero_by_default_test() {
  let model = zenoh_mesh.init()
  zenoh_mesh.message_rate(model) |> should.equal(0)
}

pub fn zenoh_mesh_message_rate_sums_pub_and_recv_test() {
  let model = zenoh_mesh.init()
  let health =
    zenoh_domain.ZenohHealth(
      status: zenoh_domain.Connected,
      session_id: "s1",
      connected_at: 100,
      last_heartbeat: 200,
      reconnect_count: 0,
      messages_published: 42,
      messages_received: 58,
      error_count: 0,
    )
  let updated = zenoh_mesh.update(model, zenoh_mesh.HealthUpdated(health))
  zenoh_mesh.message_rate(updated) |> should.equal(100)
}
