// =============================================================================
// webui_pages_comprehensive_test.gleam
// =============================================================================
// Comprehensive functional tests for the first 13 Lustre pages.
// Covers: init() defaults, update() Msg transitions, helper functions,
// and edge cases for each page.
//
// Pages: app, agents, bridge, cockpit_view, config, database, federation,
//        git, health_grid, holon, immune, kms, knowledge
//
// STAMP: SC-GLM-UI-001, SC-GLM-UI-002, SC-UIGT-003, SC-UIGT-007
// =============================================================================

import cepaf_gleam/cockpit/domain as cockpit_domain
import cepaf_gleam/fractal/l7_federation
import cepaf_gleam/immune/domain as immune_domain
import cepaf_gleam/knowledge/domain as knowledge_domain
import cepaf_gleam/ui/domain.{
  Critical, Dashboard, Degraded, Federation, Healthy, Planning, Unknown,
}
import cepaf_gleam/ui/lustre/agents
import cepaf_gleam/ui/lustre/app
import cepaf_gleam/ui/lustre/bridge
import cepaf_gleam/ui/lustre/cockpit_view
import cepaf_gleam/ui/lustre/config
import cepaf_gleam/ui/lustre/database
import cepaf_gleam/ui/lustre/federation
import cepaf_gleam/ui/lustre/git
import cepaf_gleam/ui/lustre/health_grid
import cepaf_gleam/ui/lustre/holon
import cepaf_gleam/ui/lustre/immune
import cepaf_gleam/ui/lustre/kms
import cepaf_gleam/ui/lustre/knowledge
import cepaf_gleam/ui/lustre/widgets/homeostasis_control
import gleam/option.{None, Some}
import gleeunit/should

// =============================================================================
// 1. app.gleam — Dashboard application root
// =============================================================================

pub fn app_init_selected_page_is_dashboard_test() {
  app.init().selected_page
  |> should.equal(Dashboard)
}

pub fn app_init_dark_cockpit_enabled_test() {
  app.init().dark_cockpit
  |> should.equal(True)
}

pub fn app_init_context_page_is_dashboard_test() {
  app.init().context.page
  |> should.equal(Dashboard)
}

pub fn app_init_context_health_is_unknown_test() {
  app.init().context.health
  |> should.equal(Unknown)
}

pub fn app_init_context_zenoh_not_connected_test() {
  app.init().context.zenoh_connected
  |> should.equal(False)
}

pub fn app_init_context_telemetry_empty_test() {
  app.init().context.telemetry
  |> should.equal([])
}

pub fn app_update_navigate_to_changes_page_test() {
  app.init()
  |> app.update(app.NavigateTo(Planning))
  |> fn(m) { m.selected_page }
  |> should.equal(Planning)
}

pub fn app_update_navigate_does_not_change_dark_cockpit_test() {
  app.init()
  |> app.update(app.NavigateTo(Federation))
  |> fn(m) { m.dark_cockpit }
  |> should.equal(True)
}

pub fn app_update_health_updated_sets_status_test() {
  app.init()
  |> app.update(app.HealthUpdated(Healthy))
  |> fn(m) { m.context.health }
  |> should.equal(Healthy)
}

pub fn app_update_health_updated_degraded_test() {
  app.init()
  |> app.update(app.HealthUpdated(Degraded("high cpu")))
  |> fn(m) { m.context.health }
  |> should.equal(Degraded("high cpu"))
}

pub fn app_update_zenoh_connection_changed_true_test() {
  app.init()
  |> app.update(app.ZenohConnectionChanged(True))
  |> fn(m) { m.context.zenoh_connected }
  |> should.equal(True)
}

pub fn app_update_zenoh_connection_changed_false_test() {
  app.init()
  |> app.update(app.ZenohConnectionChanged(True))
  |> app.update(app.ZenohConnectionChanged(False))
  |> fn(m) { m.context.zenoh_connected }
  |> should.equal(False)
}

pub fn app_update_toggle_dark_cockpit_disables_test() {
  app.init()
  |> app.update(app.ToggleDarkCockpit)
  |> fn(m) { m.dark_cockpit }
  |> should.equal(False)
}

pub fn app_update_toggle_dark_cockpit_twice_restores_test() {
  app.init()
  |> app.update(app.ToggleDarkCockpit)
  |> app.update(app.ToggleDarkCockpit)
  |> fn(m) { m.dark_cockpit }
  |> should.equal(True)
}

pub fn app_update_tick_is_identity_test() {
  let m = app.init()
  app.update(m, app.Tick)
  |> should.equal(m)
}

pub fn app_update_telemetry_received_prepends_test() {
  let point =
    domain.TelemetryPoint(key: "cpu", value: 0.5, timestamp: 1000, unit: "%")
  app.init()
  |> app.update(app.TelemetryReceived(point))
  |> fn(m) { m.context.telemetry }
  |> should.equal([point])
}

pub fn app_update_telemetry_received_multiple_prepends_test() {
  let p1 =
    domain.TelemetryPoint(key: "cpu", value: 0.5, timestamp: 1000, unit: "%")
  let p2 =
    domain.TelemetryPoint(key: "mem", value: 0.7, timestamp: 2000, unit: "%")
  app.init()
  |> app.update(app.TelemetryReceived(p1))
  |> app.update(app.TelemetryReceived(p2))
  |> fn(m) { m.context.telemetry }
  |> should.equal([p2, p1])
}

pub fn app_health_class_healthy_test() {
  app.health_class(Healthy)
  |> should.equal("health-ok")
}

pub fn app_health_class_degraded_test() {
  app.health_class(Degraded("slow"))
  |> should.equal("health-warn")
}

pub fn app_health_class_critical_test() {
  app.health_class(Critical("down"))
  |> should.equal("health-critical")
}

pub fn app_health_class_unknown_test() {
  app.health_class(Unknown)
  |> should.equal("health-unknown")
}

// =============================================================================
// 2. agents.gleam — Agent hierarchy plane
// =============================================================================

pub fn agents_init_total_agents_zero_test() {
  agents.init().total_agents
  |> should.equal(0)
}

pub fn agents_init_executives_zero_test() {
  agents.init().executives
  |> should.equal(0)
}

pub fn agents_init_supervisors_zero_test() {
  agents.init().supervisors
  |> should.equal(0)
}

pub fn agents_init_workers_zero_test() {
  agents.init().workers
  |> should.equal(0)
}

pub fn agents_init_efficiency_zero_test() {
  agents.init().efficiency
  |> should.equal(0.0)
}

pub fn agents_init_deadlock_false_test() {
  agents.init().deadlock_detected
  |> should.equal(False)
}

pub fn agents_update_hierarchy_loaded_sets_all_fields_test() {
  agents.init()
  |> agents.update(agents.HierarchyLoaded(25, 1, 4, 20))
  |> fn(m) {
    m.total_agents
    |> should.equal(25)
    m.executives
    |> should.equal(1)
    m.supervisors
    |> should.equal(4)
    m.workers
    |> should.equal(20)
  }
}

pub fn agents_update_efficiency_updated_test() {
  agents.init()
  |> agents.update(agents.EfficiencyUpdated(0.92))
  |> fn(m) { m.efficiency }
  |> should.equal(0.92)
}

pub fn agents_update_deadlock_detected_true_test() {
  agents.init()
  |> agents.update(agents.DeadlockDetected(True))
  |> fn(m) { m.deadlock_detected }
  |> should.equal(True)
}

pub fn agents_update_deadlock_detected_false_test() {
  agents.init()
  |> agents.update(agents.DeadlockDetected(True))
  |> agents.update(agents.DeadlockDetected(False))
  |> fn(m) { m.deadlock_detected }
  |> should.equal(False)
}

pub fn agents_update_refresh_is_identity_test() {
  let m =
    agents.init()
    |> agents.update(agents.HierarchyLoaded(10, 1, 2, 7))
  agents.update(m, agents.RefreshAgents)
  |> should.equal(m)
}

pub fn agents_is_compliant_false_when_zero_agents_test() {
  agents.is_compliant(agents.init())
  |> should.equal(False)
}

pub fn agents_is_compliant_false_when_deadlock_test() {
  agents.init()
  |> agents.update(agents.HierarchyLoaded(25, 1, 4, 20))
  |> agents.update(agents.EfficiencyUpdated(0.9))
  |> agents.update(agents.DeadlockDetected(True))
  |> agents.is_compliant()
  |> should.equal(False)
}

pub fn agents_is_compliant_false_when_low_efficiency_test() {
  agents.init()
  |> agents.update(agents.HierarchyLoaded(25, 1, 4, 20))
  |> agents.update(agents.EfficiencyUpdated(0.3))
  |> agents.is_compliant()
  |> should.equal(False)
}

pub fn agents_is_compliant_true_when_healthy_test() {
  agents.init()
  |> agents.update(agents.HierarchyLoaded(25, 1, 4, 20))
  |> agents.update(agents.EfficiencyUpdated(0.8))
  |> agents.is_compliant()
  |> should.equal(True)
}

pub fn agents_agent_summary_formats_correctly_test() {
  agents.init()
  |> agents.update(agents.HierarchyLoaded(25, 1, 4, 20))
  |> agents.agent_summary()
  |> should.equal("E:1 S:4 W:20")
}

pub fn agents_agent_summary_all_zeros_test() {
  agents.init()
  |> agents.agent_summary()
  |> should.equal("E:0 S:0 W:0")
}

// =============================================================================
// 3. bridge.gleam — Bridge / MCP plane
// =============================================================================

pub fn bridge_init_jsonrpc_methods_empty_test() {
  bridge.init().jsonrpc_methods
  |> should.equal([])
}

pub fn bridge_init_commands_total_zero_test() {
  bridge.init().commands_total
  |> should.equal(0)
}

pub fn bridge_init_commands_implemented_zero_test() {
  bridge.init().commands_implemented
  |> should.equal(0)
}

pub fn bridge_init_commands_stub_zero_test() {
  bridge.init().commands_stub
  |> should.equal(0)
}

pub fn bridge_update_command_executed_increments_implemented_test() {
  bridge.init()
  |> bridge.update(bridge.CommandExecuted("ping"))
  |> fn(m) { m.commands_implemented }
  |> should.equal(1)
}

pub fn bridge_update_command_executed_twice_increments_twice_test() {
  bridge.init()
  |> bridge.update(bridge.CommandExecuted("ping"))
  |> bridge.update(bridge.CommandExecuted("health"))
  |> fn(m) { m.commands_implemented }
  |> should.equal(2)
}

pub fn bridge_update_method_called_adds_method_test() {
  bridge.init()
  |> bridge.update(bridge.MethodCalled("tools/list"))
  |> fn(m) { m.jsonrpc_methods }
  |> should.equal(["tools/list"])
}

pub fn bridge_update_method_called_deduplicates_test() {
  bridge.init()
  |> bridge.update(bridge.MethodCalled("tools/list"))
  |> bridge.update(bridge.MethodCalled("tools/list"))
  |> fn(m) { m.jsonrpc_methods }
  |> should.equal(["tools/list"])
}

pub fn bridge_update_method_called_multiple_unique_test() {
  let m =
    bridge.init()
    |> bridge.update(bridge.MethodCalled("tools/list"))
    |> bridge.update(bridge.MethodCalled("resources/read"))
  m.jsonrpc_methods
  |> should.equal(["resources/read", "tools/list"])
}

pub fn bridge_update_refresh_is_identity_test() {
  let m =
    bridge.init()
    |> bridge.update(bridge.MethodCalled("ping"))
  bridge.update(m, bridge.RefreshBridge)
  |> should.equal(m)
}

pub fn bridge_implementation_percent_zero_when_no_total_test() {
  bridge.implementation_percent(bridge.init())
  |> should.equal(0.0)
}

pub fn bridge_implementation_percent_calculates_correctly_test() {
  let m =
    bridge.BridgeModel(
      jsonrpc_methods: [],
      commands_total: 4,
      commands_implemented: 2,
      commands_stub: 2,
      gateway_history: [],
    )
  bridge.implementation_percent(m)
  |> should.equal(50.0)
}

pub fn bridge_most_used_command_returns_none_when_empty_test() {
  bridge.most_used_command(bridge.init())
  |> should.equal("none")
}

pub fn bridge_most_used_command_returns_first_test() {
  bridge.init()
  |> bridge.update(bridge.MethodCalled("first_method"))
  |> bridge.update(bridge.MethodCalled("second_method"))
  |> bridge.most_used_command()
  |> should.equal("second_method")
}

// =============================================================================
// 4. cockpit_view.gleam — Dark Cockpit plane
// =============================================================================

pub fn cockpit_init_nodes_empty_test() {
  cockpit_view.init().nodes
  |> should.equal([])
}

pub fn cockpit_init_alarms_empty_test() {
  cockpit_view.init().alarms
  |> should.equal([])
}

pub fn cockpit_init_dark_cockpit_true_test() {
  cockpit_view.init().dark_cockpit
  |> should.equal(True)
}

pub fn cockpit_init_selected_node_none_test() {
  cockpit_view.init().selected_node
  |> should.equal(None)
}

pub fn cockpit_init_biomorphic_data_none_test() {
  cockpit_view.init().biomorphic_data
  |> should.equal(None)
}

pub fn cockpit_init_view_mode_is_overview_test() {
  cockpit_view.init().view_mode
  |> should.equal(cockpit_domain.Overview)
}

pub fn cockpit_init_cpu_threshold_test() {
  cockpit_view.init().cpu_threshold
  |> should.equal(0.85)
}

pub fn cockpit_init_mem_threshold_test() {
  cockpit_view.init().mem_threshold
  |> should.equal(0.75)
}

pub fn cockpit_update_set_view_mode_changes_mode_test() {
  cockpit_view.init()
  |> cockpit_view.update(cockpit_view.SetViewMode(cockpit_domain.Alarms))
  |> fn(m) { m.view_mode }
  |> should.equal(cockpit_domain.Alarms)
}

pub fn cockpit_update_select_node_sets_selected_test() {
  cockpit_view.init()
  |> cockpit_view.update(cockpit_view.SelectNode("node-42"))
  |> fn(m) { m.selected_node }
  |> should.equal(Some("node-42"))
}

pub fn cockpit_update_toggle_dark_cockpit_disables_test() {
  cockpit_view.init()
  |> cockpit_view.update(cockpit_view.ToggleDarkCockpit)
  |> fn(m) { m.dark_cockpit }
  |> should.equal(False)
}

pub fn cockpit_update_toggle_dark_cockpit_twice_restores_test() {
  cockpit_view.init()
  |> cockpit_view.update(cockpit_view.ToggleDarkCockpit)
  |> cockpit_view.update(cockpit_view.ToggleDarkCockpit)
  |> fn(m) { m.dark_cockpit }
  |> should.equal(True)
}

pub fn cockpit_update_refresh_is_identity_test() {
  let m = cockpit_view.init()
  cockpit_view.update(m, cockpit_view.RefreshCockpit)
  |> should.equal(m)
}

pub fn cockpit_update_acknowledge_alarm_is_identity_test() {
  let m = cockpit_view.init()
  cockpit_view.update(m, cockpit_view.AcknowledgeAlarm("alarm-1"))
  |> should.equal(m)
}

pub fn cockpit_update_homeostasis_cpu_threshold_test() {
  cockpit_view.init()
  |> cockpit_view.update(
    cockpit_view.HomeostasisEvent(homeostasis_control.SetThreshold("cpu", 0.6)),
  )
  |> fn(m) { m.cpu_threshold }
  |> should.equal(0.6)
}

pub fn cockpit_update_homeostasis_mem_threshold_test() {
  cockpit_view.init()
  |> cockpit_view.update(
    cockpit_view.HomeostasisEvent(homeostasis_control.SetThreshold("mem", 0.5)),
  )
  |> fn(m) { m.mem_threshold }
  |> should.equal(0.5)
}

pub fn cockpit_update_homeostasis_unknown_metric_is_identity_test() {
  let m = cockpit_view.init()
  cockpit_view.update(
    m,
    cockpit_view.HomeostasisEvent(homeostasis_control.SetThreshold("disk", 0.9)),
  )
  |> should.equal(m)
}

pub fn cockpit_update_homeostasis_trigger_equilibrium_is_identity_test() {
  let m = cockpit_view.init()
  cockpit_view.update(
    m,
    cockpit_view.HomeostasisEvent(homeostasis_control.TriggerEquilibrium),
  )
  |> should.equal(m)
}

pub fn cockpit_visible_nodes_dark_mode_filters_connected_test() {
  let connected_node =
    cockpit_domain.MeshNode(
      id: "n1",
      name: "Node1",
      zone: "z1",
      role: cockpit_domain.Worker,
      status: cockpit_domain.Connected,
      cpu: make_metric(0.3),
      memory: make_metric(0.4),
      battery: None,
      network_latency: make_metric(5.0),
      capabilities: [],
      health_score: make_metric(0.9),
      location: None,
      ai_insight: None,
      ai_insight_updated_at: None,
    )
  cockpit_view.init()
  |> cockpit_view.update(cockpit_view.NodesUpdated([connected_node]))
  |> cockpit_view.visible_nodes()
  |> should.equal([])
}

pub fn cockpit_visible_nodes_dark_mode_shows_stale_test() {
  let stale_node =
    cockpit_domain.MeshNode(
      id: "n2",
      name: "Node2",
      zone: "z1",
      role: cockpit_domain.Worker,
      status: cockpit_domain.Stale,
      cpu: make_metric(0.3),
      memory: make_metric(0.4),
      battery: None,
      network_latency: make_metric(5.0),
      capabilities: [],
      health_score: make_metric(0.7),
      location: None,
      ai_insight: None,
      ai_insight_updated_at: None,
    )
  cockpit_view.init()
  |> cockpit_view.update(cockpit_view.NodesUpdated([stale_node]))
  |> cockpit_view.visible_nodes()
  |> should.equal([stale_node])
}

pub fn cockpit_visible_nodes_non_dark_shows_all_test() {
  let connected_node =
    cockpit_domain.MeshNode(
      id: "n1",
      name: "Node1",
      zone: "z1",
      role: cockpit_domain.Worker,
      status: cockpit_domain.Connected,
      cpu: make_metric(0.3),
      memory: make_metric(0.4),
      battery: None,
      network_latency: make_metric(5.0),
      capabilities: [],
      health_score: make_metric(0.9),
      location: None,
      ai_insight: None,
      ai_insight_updated_at: None,
    )
  cockpit_view.init()
  |> cockpit_view.update(cockpit_view.ToggleDarkCockpit)
  |> cockpit_view.update(cockpit_view.NodesUpdated([connected_node]))
  |> cockpit_view.visible_nodes()
  |> should.equal([connected_node])
}

pub fn cockpit_active_alarms_filters_normal_test() {
  let normal_alarm =
    cockpit_domain.Alarm(
      id: "a1",
      node_id: "n1",
      level: cockpit_domain.Normal,
      category: "test",
      message: "all ok",
      details: None,
      occurred_at: 1000,
      acknowledged_at: None,
      acknowledged_by: None,
      auto_clearable: True,
    )
  cockpit_view.init()
  |> cockpit_view.update(cockpit_view.AlarmsUpdated([normal_alarm]))
  |> cockpit_view.active_alarms()
  |> should.equal([])
}

pub fn cockpit_active_alarms_shows_critical_test() {
  let critical_alarm =
    cockpit_domain.Alarm(
      id: "a2",
      node_id: "n1",
      level: cockpit_domain.Critical,
      category: "cpu",
      message: "cpu overload",
      details: None,
      occurred_at: 2000,
      acknowledged_at: None,
      acknowledged_by: None,
      auto_clearable: False,
    )
  cockpit_view.init()
  |> cockpit_view.update(cockpit_view.AlarmsUpdated([critical_alarm]))
  |> cockpit_view.active_alarms()
  |> should.equal([critical_alarm])
}

// Helper: creates a minimal SmartMetric for cockpit tests.
fn make_metric(v: Float) -> cockpit_domain.SmartMetric {
  cockpit_domain.SmartMetric(
    value: v,
    previous_value: None,
    last_updated: 0,
    trend: cockpit_domain.Stable,
    level: cockpit_domain.Normal,
    thresholds: None,
    unit: "",
    label: "",
    sparkline: [],
  )
}

// =============================================================================
// 5. config.gleam — Config Management plane
// =============================================================================

pub fn config_init_containers_empty_test() {
  config.init().containers
  |> should.equal([])
}

pub fn config_init_networks_empty_test() {
  config.init().networks
  |> should.equal([])
}

pub fn config_init_quorum_size_three_test() {
  config.init().quorum_size
  |> should.equal(3)
}

pub fn config_init_is_valid_false_test() {
  config.init().is_valid
  |> should.equal(False)
}

pub fn config_init_total_cpu_zero_test() {
  config.init().total_cpu
  |> should.equal(0)
}

pub fn config_init_total_memory_zero_test() {
  config.init().total_memory
  |> should.equal(0)
}

pub fn config_update_config_loaded_is_identity_test() {
  let m = config.init()
  config.update(m, config.ConfigLoaded)
  |> should.equal(m)
}

pub fn config_update_validation_ran_true_test() {
  config.init()
  |> config.update(config.ValidationRan(True))
  |> fn(m) { m.is_valid }
  |> should.equal(True)
}

pub fn config_update_validation_ran_false_test() {
  config.init()
  |> config.update(config.ValidationRan(True))
  |> config.update(config.ValidationRan(False))
  |> fn(m) { m.is_valid }
  |> should.equal(False)
}

pub fn config_update_container_added_prepends_test() {
  config.init()
  |> config.update(config.ContainerAdded("db-prod"))
  |> fn(m) { m.containers }
  |> should.equal(["db-prod"])
}

pub fn config_update_container_added_multiple_test() {
  config.init()
  |> config.update(config.ContainerAdded("db-prod"))
  |> config.update(config.ContainerAdded("obs-prod"))
  |> config.update(config.ContainerAdded("ex-app-1"))
  |> fn(m) { m.containers }
  |> should.equal(["ex-app-1", "obs-prod", "db-prod"])
}

pub fn config_update_refresh_is_identity_test() {
  let m = config.init()
  config.update(m, config.RefreshConfig)
  |> should.equal(m)
}

pub fn config_quorum_met_false_when_empty_test() {
  config.quorum_met(config.init())
  |> should.equal(False)
}

pub fn config_quorum_met_false_below_quorum_test() {
  config.init()
  |> config.update(config.ContainerAdded("a"))
  |> config.update(config.ContainerAdded("b"))
  |> config.quorum_met()
  |> should.equal(False)
}

pub fn config_quorum_met_true_at_quorum_size_test() {
  config.init()
  |> config.update(config.ContainerAdded("a"))
  |> config.update(config.ContainerAdded("b"))
  |> config.update(config.ContainerAdded("c"))
  |> config.quorum_met()
  |> should.equal(True)
}

pub fn config_quorum_met_true_above_quorum_size_test() {
  config.init()
  |> config.update(config.ContainerAdded("a"))
  |> config.update(config.ContainerAdded("b"))
  |> config.update(config.ContainerAdded("c"))
  |> config.update(config.ContainerAdded("d"))
  |> config.quorum_met()
  |> should.equal(True)
}

pub fn config_resource_summary_formats_zero_test() {
  config.resource_summary(config.init())
  |> should.equal("CPU:0 MEM:0MB")
}

pub fn config_resource_summary_formats_nonzero_test() {
  let m =
    config.ConfigModel(
      containers: [],
      networks: [],
      quorum_size: 3,
      is_valid: True,
      total_cpu: 16,
      total_memory: 32_768,
      pii_patterns: [],
      active_model: "gemini",
      available_models: [],
    )
  config.resource_summary(m)
  |> should.equal("CPU:16 MEM:32768MB")
}

// =============================================================================
// 6. database.gleam — Database plane
// =============================================================================

pub fn database_init_supported_types_test() {
  database.init().supported_types
  |> should.equal(["sqlite", "duckdb"])
}

pub fn database_init_active_connections_zero_test() {
  database.init().active_connections
  |> should.equal(0)
}

pub fn database_init_total_queries_zero_test() {
  database.init().total_queries
  |> should.equal(0)
}

pub fn database_init_failed_queries_zero_test() {
  database.init().failed_queries
  |> should.equal(0)
}

pub fn database_init_avg_latency_zero_test() {
  database.init().avg_latency
  |> should.equal(0.0)
}

pub fn database_update_stats_updated_sets_fields_test() {
  database.init()
  |> database.update(database.StatsUpdated(100, 5, 42.5))
  |> fn(m) {
    m.total_queries
    |> should.equal(100)
    m.failed_queries
    |> should.equal(5)
    m.avg_latency
    |> should.equal(42.5)
  }
}

pub fn database_update_connection_opened_increments_test() {
  database.init()
  |> database.update(database.ConnectionOpened)
  |> fn(m) { m.active_connections }
  |> should.equal(1)
}

pub fn database_update_connection_opened_twice_test() {
  database.init()
  |> database.update(database.ConnectionOpened)
  |> database.update(database.ConnectionOpened)
  |> fn(m) { m.active_connections }
  |> should.equal(2)
}

pub fn database_update_connection_closed_decrements_test() {
  database.init()
  |> database.update(database.ConnectionOpened)
  |> database.update(database.ConnectionOpened)
  |> database.update(database.ConnectionClosed)
  |> fn(m) { m.active_connections }
  |> should.equal(1)
}

pub fn database_update_connection_closed_at_zero_stays_zero_test() {
  database.init()
  |> database.update(database.ConnectionClosed)
  |> fn(m) { m.active_connections }
  |> should.equal(0)
}

pub fn database_update_refresh_is_identity_test() {
  let m = database.init()
  database.update(m, database.RefreshDatabase)
  |> should.equal(m)
}

pub fn database_is_healthy_false_when_no_connections_test() {
  database.is_healthy(database.init())
  |> should.equal(False)
}

pub fn database_is_healthy_false_when_high_latency_test() {
  database.init()
  |> database.update(database.ConnectionOpened)
  |> database.update(database.StatsUpdated(10, 0, 200.0))
  |> database.is_healthy()
  |> should.equal(False)
}

pub fn database_is_healthy_true_when_connected_low_latency_test() {
  database.init()
  |> database.update(database.ConnectionOpened)
  |> database.update(database.StatsUpdated(10, 0, 5.0))
  |> database.is_healthy()
  |> should.equal(True)
}

pub fn database_failure_rate_zero_when_no_queries_test() {
  database.failure_rate(database.init())
  |> should.equal(0.0)
}

pub fn database_failure_rate_calculates_correctly_test() {
  database.init()
  |> database.update(database.StatsUpdated(100, 10, 5.0))
  |> database.failure_rate()
  |> should.equal(0.1)
}

pub fn database_failure_rate_zero_when_no_failures_test() {
  database.init()
  |> database.update(database.StatsUpdated(50, 0, 3.0))
  |> database.failure_rate()
  |> should.equal(0.0)
}

// =============================================================================
// 7. federation.gleam — L7 Federation plane
// =============================================================================

pub fn federation_init_state_is_none_test() {
  federation.init().state
  |> should.equal(None)
}

pub fn federation_init_loading_is_false_test() {
  federation.init().loading
  |> should.equal(False)
}

pub fn federation_init_error_is_none_test() {
  federation.init().error
  |> should.equal(None)
}

pub fn federation_update_state_received_sets_state_test() {
  let state = l7_federation.initial_federation("local-1")
  federation.init()
  |> federation.update(federation.StateReceived(state))
  |> fn(m) { m.state }
  |> should.equal(Some(state))
}

pub fn federation_update_state_received_clears_loading_test() {
  federation.init()
  |> federation.update(federation.RefreshFederation)
  |> federation.update(
    federation.StateReceived(l7_federation.initial_federation("local-1")),
  )
  |> fn(m) { m.loading }
  |> should.equal(False)
}

pub fn federation_update_state_received_clears_error_test() {
  federation.init()
  |> federation.update(federation.ErrorReceived("timeout"))
  |> federation.update(
    federation.StateReceived(l7_federation.initial_federation("local-1")),
  )
  |> fn(m) { m.error }
  |> should.equal(None)
}

pub fn federation_update_refresh_sets_loading_true_test() {
  federation.init()
  |> federation.update(federation.RefreshFederation)
  |> fn(m) { m.loading }
  |> should.equal(True)
}

pub fn federation_update_error_received_sets_error_test() {
  federation.init()
  |> federation.update(federation.ErrorReceived("network failure"))
  |> fn(m) { m.error }
  |> should.equal(Some("network failure"))
}

pub fn federation_update_error_received_clears_loading_test() {
  federation.init()
  |> federation.update(federation.RefreshFederation)
  |> federation.update(federation.ErrorReceived("timeout"))
  |> fn(m) { m.loading }
  |> should.equal(False)
}

pub fn federation_update_peer_added_when_no_state_is_identity_test() {
  let peer =
    l7_federation.FederationPeer(
      peer_id: "peer-1",
      endpoint: "tcp/localhost:7448",
      status: l7_federation.PeerConnected,
      version_vector: [],
      attestation_valid: True,
      last_seen: 1000,
    )
  let m = federation.init()
  federation.update(m, federation.PeerAdded(peer))
  |> should.equal(m)
}

pub fn federation_update_peer_removed_when_no_state_is_identity_test() {
  let m = federation.init()
  federation.update(m, federation.PeerRemoved("peer-1"))
  |> should.equal(m)
}

pub fn federation_update_version_incremented_when_no_state_is_identity_test() {
  let m = federation.init()
  federation.update(m, federation.VersionIncremented)
  |> should.equal(m)
}

pub fn federation_update_peer_added_with_state_adds_peer_test() {
  let state = l7_federation.initial_federation("local-1")
  let peer =
    l7_federation.FederationPeer(
      peer_id: "peer-1",
      endpoint: "tcp/localhost:7448",
      status: l7_federation.PeerConnected,
      version_vector: [],
      attestation_valid: True,
      last_seen: 1000,
    )
  federation.init()
  |> federation.update(federation.StateReceived(state))
  |> federation.update(federation.PeerAdded(peer))
  |> federation.total_peer_count()
  |> should.equal(1)
}

pub fn federation_connected_count_zero_when_no_state_test() {
  federation.connected_count(federation.init())
  |> should.equal(0)
}

pub fn federation_all_attested_check_false_when_no_state_test() {
  federation.all_attested_check(federation.init())
  |> should.equal(False)
}

pub fn federation_total_peer_count_zero_when_no_state_test() {
  federation.total_peer_count(federation.init())
  |> should.equal(0)
}

pub fn federation_all_attested_check_true_when_no_peers_test() {
  let state = l7_federation.initial_federation("local-1")
  federation.init()
  |> federation.update(federation.StateReceived(state))
  |> federation.all_attested_check()
  |> should.equal(True)
}

// =============================================================================
// 8. git.gleam — Git Analytics plane
// =============================================================================

pub fn git_init_commit_types_empty_test() {
  git.init().commit_types
  |> should.equal([])
}

pub fn git_init_health_score_zero_test() {
  git.init().health_score
  |> should.equal(0.0)
}

pub fn git_init_total_commits_zero_test() {
  git.init().total_commits
  |> should.equal(0)
}

pub fn git_init_icp_compliance_zero_test() {
  git.init().icp_compliance
  |> should.equal(0.0)
}

pub fn git_update_analysis_loaded_sets_health_test() {
  git.init()
  |> git.update(git.AnalysisLoaded(0.87, 0.92))
  |> fn(m) { m.health_score }
  |> should.equal(0.87)
}

pub fn git_update_analysis_loaded_sets_compliance_test() {
  git.init()
  |> git.update(git.AnalysisLoaded(0.87, 0.92))
  |> fn(m) { m.icp_compliance }
  |> should.equal(0.92)
}

pub fn git_update_commit_parsed_increments_test() {
  git.init()
  |> git.update(git.CommitParsed)
  |> fn(m) { m.total_commits }
  |> should.equal(1)
}

pub fn git_update_commit_parsed_multiple_test() {
  git.init()
  |> git.update(git.CommitParsed)
  |> git.update(git.CommitParsed)
  |> git.update(git.CommitParsed)
  |> fn(m) { m.total_commits }
  |> should.equal(3)
}

pub fn git_update_refresh_is_identity_test() {
  let m = git.init()
  git.update(m, git.RefreshGit)
  |> should.equal(m)
}

pub fn git_is_healthy_false_below_threshold_test() {
  git.init()
  |> git.update(git.AnalysisLoaded(0.5, 0.5))
  |> git.is_healthy()
  |> should.equal(False)
}

pub fn git_is_healthy_false_at_zero_test() {
  git.is_healthy(git.init())
  |> should.equal(False)
}

pub fn git_is_healthy_true_at_threshold_test() {
  git.init()
  |> git.update(git.AnalysisLoaded(0.7, 0.8))
  |> git.is_healthy()
  |> should.equal(True)
}

pub fn git_is_healthy_true_above_threshold_test() {
  git.init()
  |> git.update(git.AnalysisLoaded(0.95, 0.99))
  |> git.is_healthy()
  |> should.equal(True)
}

pub fn git_style_summary_formats_correctly_test() {
  let m =
    git.GitModel(
      commit_types: [],
      health_score: 0.87,
      total_commits: 10,
      icp_compliance: 0.92,
    )
  git.style_summary(m)
  |> should.equal("health:0.87 icp:0.92")
}

// =============================================================================
// 9. health_grid.gleam — Device Health Grid
// =============================================================================

pub fn health_grid_init_devices_empty_test() {
  health_grid.init().devices
  |> should.equal([])
}

pub fn health_grid_init_selected_id_none_test() {
  health_grid.init().selected_id
  |> should.equal(None)
}

pub fn health_grid_init_filter_all_devices_test() {
  health_grid.init().filter
  |> should.equal(health_grid.AllDevices)
}

pub fn health_grid_update_select_device_sets_id_test() {
  health_grid.init()
  |> health_grid.update(health_grid.SelectDevice("device-7"))
  |> fn(m) { m.selected_id }
  |> should.equal(Some("device-7"))
}

pub fn health_grid_update_select_device_overwrites_previous_test() {
  health_grid.init()
  |> health_grid.update(health_grid.SelectDevice("device-1"))
  |> health_grid.update(health_grid.SelectDevice("device-2"))
  |> fn(m) { m.selected_id }
  |> should.equal(Some("device-2"))
}

pub fn health_grid_update_set_filter_healthy_only_test() {
  health_grid.init()
  |> health_grid.update(health_grid.SetFilter(health_grid.HealthyOnly))
  |> fn(m) { m.filter }
  |> should.equal(health_grid.HealthyOnly)
}

pub fn health_grid_update_set_filter_degraded_only_test() {
  health_grid.init()
  |> health_grid.update(health_grid.SetFilter(health_grid.DegradedOnly))
  |> fn(m) { m.filter }
  |> should.equal(health_grid.DegradedOnly)
}

pub fn health_grid_update_set_filter_critical_only_test() {
  health_grid.init()
  |> health_grid.update(health_grid.SetFilter(health_grid.CriticalOnly))
  |> fn(m) { m.filter }
  |> should.equal(health_grid.CriticalOnly)
}

pub fn health_grid_update_refresh_is_identity_test() {
  let m = health_grid.init()
  health_grid.update(m, health_grid.Refresh)
  |> should.equal(m)
}

pub fn health_grid_update_devices_loaded_sets_devices_test() {
  let devices = [
    domain.DeviceHealth(
      id: "d1",
      health_score: 0.9,
      device_type: "sensor",
      status: domain.Online,
      last_seen: 1000,
    ),
    domain.DeviceHealth(
      id: "d2",
      health_score: 0.4,
      device_type: "actuator",
      status: domain.Offline,
      last_seen: 500,
    ),
  ]
  health_grid.init()
  |> health_grid.update(health_grid.DevicesLoaded(devices))
  |> fn(m) { m.devices }
  |> should.equal(devices)
}

pub fn health_grid_update_devices_loaded_empty_test() {
  health_grid.init()
  |> health_grid.update(health_grid.DevicesLoaded([]))
  |> fn(m) { m.devices }
  |> should.equal([])
}

// =============================================================================
// 10. holon.gleam — Holon Registry plane
// =============================================================================

pub fn holon_init_runtimes_has_gleam_test() {
  holon.init().runtimes
  |> should.equal(["gleam", "elixir", "rust", "fsharp"])
}

pub fn holon_init_layers_has_eight_entries_test() {
  holon.init().layers
  |> should.equal(["L0", "L1", "L2", "L3", "L4", "L5", "L6", "L7"])
}

pub fn holon_init_domains_correct_test() {
  holon.init().domains
  |> should.equal(["immune", "metabolic", "cognitive", "substrate"])
}

pub fn holon_init_holon_types_correct_test() {
  holon.init().holon_types
  |> should.equal(["actor", "sensor", "effector", "bridge"])
}

pub fn holon_init_active_uhis_empty_test() {
  holon.init().active_uhis
  |> should.equal([])
}

pub fn holon_update_uhi_registered_prepends_test() {
  holon.init()
  |> holon.update(holon.UhiRegistered("gleam:immune:actor:001"))
  |> fn(m) { m.active_uhis }
  |> should.equal(["gleam:immune:actor:001"])
}

pub fn holon_update_uhi_registered_multiple_test() {
  holon.init()
  |> holon.update(holon.UhiRegistered("uhi-1"))
  |> holon.update(holon.UhiRegistered("uhi-2"))
  |> fn(m) { m.active_uhis }
  |> should.equal(["uhi-2", "uhi-1"])
}

pub fn holon_update_uhi_removed_removes_matching_test() {
  holon.init()
  |> holon.update(holon.UhiRegistered("uhi-1"))
  |> holon.update(holon.UhiRegistered("uhi-2"))
  |> holon.update(holon.UhiRemoved("uhi-1"))
  |> fn(m) { m.active_uhis }
  |> should.equal(["uhi-2"])
}

pub fn holon_update_uhi_removed_nonexistent_is_identity_test() {
  let m =
    holon.init()
    |> holon.update(holon.UhiRegistered("uhi-1"))
  holon.update(m, holon.UhiRemoved("uhi-nonexistent"))
  |> fn(r) { r.active_uhis }
  |> should.equal(["uhi-1"])
}

pub fn holon_update_refresh_is_identity_test() {
  let m = holon.init()
  holon.update(m, holon.RefreshHolon)
  |> should.equal(m)
}

pub fn holon_total_uhis_zero_when_empty_test() {
  holon.total_uhis(holon.init())
  |> should.equal(0)
}

pub fn holon_total_uhis_counts_correctly_test() {
  holon.init()
  |> holon.update(holon.UhiRegistered("uhi-1"))
  |> holon.update(holon.UhiRegistered("uhi-2"))
  |> holon.update(holon.UhiRegistered("uhi-3"))
  |> holon.total_uhis()
  |> should.equal(3)
}

pub fn holon_has_gleam_holons_true_test() {
  holon.has_gleam_holons(holon.init())
  |> should.equal(True)
}

// =============================================================================
// 11. immune.gleam — Immune System plane
// =============================================================================

pub fn immune_init_antibodies_empty_test() {
  immune.init().antibodies
  |> should.equal([])
}

pub fn immune_init_recent_events_empty_test() {
  immune.init().recent_events
  |> should.equal([])
}

pub fn immune_init_active_attacks_empty_test() {
  immune.init().active_attacks
  |> should.equal([])
}

pub fn immune_init_mara_not_running_test() {
  immune.init().mara_running
  |> should.equal(False)
}

pub fn immune_update_antibody_added_prepends_test() {
  let ab =
    immune_domain.Antibody(
      id: "ab-1",
      target_pattern: "*.malicious",
      reason: "flood",
      expires_at: 9999,
    )
  immune.init()
  |> immune.update(immune.AntibodyAdded(ab))
  |> fn(m) { m.antibodies }
  |> should.equal([ab])
}

pub fn immune_update_event_received_prepends_test() {
  let evt = immune_domain.AttackBlocked(id: "evt-1", reason: "pattern match")
  immune.init()
  |> immune.update(immune.EventReceived(evt))
  |> fn(m) { m.recent_events }
  |> should.equal([evt])
}

pub fn immune_update_attack_detected_prepends_test() {
  let atk = immune_domain.ZenohFlood(topic: "indrajaal/test", count: 1000)
  immune.init()
  |> immune.update(immune.AttackDetected(atk))
  |> fn(m) { m.active_attacks }
  |> should.equal([atk])
}

pub fn immune_update_attack_resolved_is_identity_test() {
  let m = immune.init()
  immune.update(m, immune.AttackResolved("atk-1"))
  |> should.equal(m)
}

pub fn immune_update_toggle_mara_enables_test() {
  immune.init()
  |> immune.update(immune.ToggleMara)
  |> fn(m) { m.mara_running }
  |> should.equal(True)
}

pub fn immune_update_toggle_mara_twice_restores_test() {
  immune.init()
  |> immune.update(immune.ToggleMara)
  |> immune.update(immune.ToggleMara)
  |> fn(m) { m.mara_running }
  |> should.equal(False)
}

pub fn immune_update_refresh_is_identity_test() {
  let m = immune.init()
  immune.update(m, immune.RefreshImmune)
  |> should.equal(m)
}

pub fn immune_threat_level_nominal_when_empty_test() {
  immune.threat_level(immune.init())
  |> should.equal("nominal")
}

pub fn immune_threat_level_elevated_with_one_attack_test() {
  let atk = immune_domain.ZenohFlood(topic: "t", count: 10)
  immune.init()
  |> immune.update(immune.AttackDetected(atk))
  |> immune.threat_level()
  |> should.equal("elevated")
}

pub fn immune_threat_level_elevated_with_two_attacks_test() {
  let atk = immune_domain.ZenohFlood(topic: "t", count: 10)
  immune.init()
  |> immune.update(immune.AttackDetected(atk))
  |> immune.update(immune.AttackDetected(atk))
  |> immune.threat_level()
  |> should.equal("elevated")
}

pub fn immune_threat_level_critical_with_three_attacks_test() {
  let atk = immune_domain.ZenohFlood(topic: "t", count: 10)
  immune.init()
  |> immune.update(immune.AttackDetected(atk))
  |> immune.update(immune.AttackDetected(atk))
  |> immune.update(immune.AttackDetected(atk))
  |> immune.threat_level()
  |> should.equal("critical")
}

// =============================================================================
// 12. kms.gleam — KMS Catalog plane
// =============================================================================

pub fn kms_init_checkpoints_empty_test() {
  kms.init().checkpoints
  |> should.equal([])
}

pub fn kms_init_total_keys_zero_test() {
  kms.init().total_keys
  |> should.equal(0)
}

pub fn kms_init_active_keys_zero_test() {
  kms.init().active_keys
  |> should.equal(0)
}

pub fn kms_update_checkpoints_loaded_sets_checkpoints_test() {
  let cps = [
    kms.Checkpoint(id: "cp-1", label: "genesis", timestamp: 1000, key_count: 5),
    kms.Checkpoint(
      id: "cp-2",
      label: "rotation-1",
      timestamp: 2000,
      key_count: 7,
    ),
  ]
  kms.init()
  |> kms.update(kms.CheckpointsLoaded(cps))
  |> fn(m) { m.checkpoints }
  |> should.equal(cps)
}

pub fn kms_update_checkpoints_loaded_empty_test() {
  kms.init()
  |> kms.update(kms.CheckpointsLoaded([]))
  |> fn(m) { m.checkpoints }
  |> should.equal([])
}

pub fn kms_update_key_rotated_is_identity_test() {
  let m = kms.init()
  kms.update(m, kms.KeyRotated("key-abc"))
  |> should.equal(m)
}

pub fn kms_update_refresh_is_identity_test() {
  let m = kms.init()
  kms.update(m, kms.RefreshKms)
  |> should.equal(m)
}

pub fn kms_latest_checkpoint_error_when_empty_test() {
  kms.latest_checkpoint(kms.init())
  |> should.equal(Error(Nil))
}

pub fn kms_latest_checkpoint_returns_first_test() {
  let cp1 =
    kms.Checkpoint(id: "cp-1", label: "genesis", timestamp: 1000, key_count: 5)
  let cp2 =
    kms.Checkpoint(id: "cp-2", label: "rotation", timestamp: 2000, key_count: 7)
  kms.init()
  |> kms.update(kms.CheckpointsLoaded([cp1, cp2]))
  |> kms.latest_checkpoint()
  |> should.equal(Ok(cp1))
}

pub fn kms_checkpoint_count_zero_when_empty_test() {
  kms.checkpoint_count(kms.init())
  |> should.equal(0)
}

pub fn kms_checkpoint_count_returns_length_test() {
  let cps = [
    kms.Checkpoint(id: "cp-1", label: "genesis", timestamp: 1000, key_count: 5),
    kms.Checkpoint(id: "cp-2", label: "rot-1", timestamp: 2000, key_count: 7),
    kms.Checkpoint(id: "cp-3", label: "rot-2", timestamp: 3000, key_count: 9),
  ]
  kms.init()
  |> kms.update(kms.CheckpointsLoaded(cps))
  |> kms.checkpoint_count()
  |> should.equal(3)
}

// =============================================================================
// 13. knowledge.gleam — Knowledge (Smriti) plane
// =============================================================================

pub fn knowledge_init_nodes_empty_test() {
  knowledge.init().nodes
  |> should.equal([])
}

pub fn knowledge_init_links_empty_test() {
  knowledge.init().links
  |> should.equal([])
}

pub fn knowledge_init_selected_node_none_test() {
  knowledge.init().selected_node
  |> should.equal(None)
}

pub fn knowledge_init_filter_level_none_test() {
  knowledge.init().filter_level
  |> should.equal(None)
}

pub fn knowledge_init_search_query_empty_test() {
  knowledge.init().search_query
  |> should.equal("")
}

pub fn knowledge_update_select_node_sets_id_test() {
  knowledge.init()
  |> knowledge.update(knowledge.SelectNode("node-99"))
  |> fn(m) { m.selected_node }
  |> should.equal(Some("node-99"))
}

pub fn knowledge_update_select_node_overwrites_previous_test() {
  knowledge.init()
  |> knowledge.update(knowledge.SelectNode("node-1"))
  |> knowledge.update(knowledge.SelectNode("node-2"))
  |> fn(m) { m.selected_node }
  |> should.equal(Some("node-2"))
}

pub fn knowledge_update_set_level_filter_atomic_test() {
  knowledge.init()
  |> knowledge.update(knowledge.SetLevelFilter(Some(knowledge_domain.Atomic)))
  |> fn(m) { m.filter_level }
  |> should.equal(Some(knowledge_domain.Atomic))
}

pub fn knowledge_update_set_level_filter_none_clears_test() {
  knowledge.init()
  |> knowledge.update(knowledge.SetLevelFilter(Some(knowledge_domain.Organism)))
  |> knowledge.update(knowledge.SetLevelFilter(None))
  |> fn(m) { m.filter_level }
  |> should.equal(None)
}

pub fn knowledge_update_set_search_query_test() {
  knowledge.init()
  |> knowledge.update(knowledge.SetSearch("fractal"))
  |> fn(m) { m.search_query }
  |> should.equal("fractal")
}

pub fn knowledge_update_set_search_empty_string_test() {
  knowledge.init()
  |> knowledge.update(knowledge.SetSearch("fractal"))
  |> knowledge.update(knowledge.SetSearch(""))
  |> fn(m) { m.search_query }
  |> should.equal("")
}

pub fn knowledge_update_nodes_loaded_sets_nodes_and_links_test() {
  let nodes = [
    knowledge_domain.KnowledgeNode(
      id: "n1",
      title: "OODA",
      level: knowledge_domain.Atomic,
      rhetorical: knowledge_domain.Axiom,
      entropy: 1.2,
      drift: 0.1,
      tags: ["core"],
    ),
  ]
  let links = [
    knowledge_domain.KnowledgeLink(
      source_id: "n1",
      target_id: "n2",
      relation_type: "supports",
    ),
  ]
  knowledge.init()
  |> knowledge.update(knowledge.NodesLoaded(nodes, links))
  |> fn(m) {
    m.nodes
    |> should.equal(nodes)
    m.links
    |> should.equal(links)
  }
}

pub fn knowledge_update_refresh_is_identity_test() {
  let m = knowledge.init()
  knowledge.update(m, knowledge.RefreshKnowledge)
  |> should.equal(m)
}

pub fn knowledge_filtered_nodes_returns_all_when_no_filter_test() {
  let nodes = [
    knowledge_domain.KnowledgeNode(
      id: "n1",
      title: "A",
      level: knowledge_domain.Atomic,
      rhetorical: knowledge_domain.Axiom,
      entropy: 0.5,
      drift: 0.0,
      tags: [],
    ),
    knowledge_domain.KnowledgeNode(
      id: "n2",
      title: "B",
      level: knowledge_domain.Ecosystem,
      rhetorical: knowledge_domain.Evidence,
      entropy: 1.0,
      drift: 0.2,
      tags: [],
    ),
  ]
  knowledge.init()
  |> knowledge.update(knowledge.NodesLoaded(nodes, []))
  |> knowledge.filtered_nodes()
  |> should.equal(nodes)
}

pub fn knowledge_filtered_nodes_filters_by_level_test() {
  let n1 =
    knowledge_domain.KnowledgeNode(
      id: "n1",
      title: "A",
      level: knowledge_domain.Atomic,
      rhetorical: knowledge_domain.Axiom,
      entropy: 0.5,
      drift: 0.0,
      tags: [],
    )
  let n2 =
    knowledge_domain.KnowledgeNode(
      id: "n2",
      title: "B",
      level: knowledge_domain.Ecosystem,
      rhetorical: knowledge_domain.Evidence,
      entropy: 1.0,
      drift: 0.2,
      tags: [],
    )
  knowledge.init()
  |> knowledge.update(knowledge.NodesLoaded([n1, n2], []))
  |> knowledge.update(knowledge.SetLevelFilter(Some(knowledge_domain.Atomic)))
  |> knowledge.filtered_nodes()
  |> should.equal([n1])
}

pub fn knowledge_node_count_by_level_zero_when_none_match_test() {
  let nodes = [
    knowledge_domain.KnowledgeNode(
      id: "n1",
      title: "A",
      level: knowledge_domain.Atomic,
      rhetorical: knowledge_domain.Axiom,
      entropy: 0.5,
      drift: 0.0,
      tags: [],
    ),
  ]
  knowledge.node_count_by_level(nodes, knowledge_domain.Ecosystem)
  |> should.equal(0)
}

pub fn knowledge_node_count_by_level_counts_matching_test() {
  let nodes = [
    knowledge_domain.KnowledgeNode(
      id: "n1",
      title: "A",
      level: knowledge_domain.Atomic,
      rhetorical: knowledge_domain.Axiom,
      entropy: 0.5,
      drift: 0.0,
      tags: [],
    ),
    knowledge_domain.KnowledgeNode(
      id: "n2",
      title: "B",
      level: knowledge_domain.Atomic,
      rhetorical: knowledge_domain.Hypothesis,
      entropy: 0.8,
      drift: 0.1,
      tags: [],
    ),
    knowledge_domain.KnowledgeNode(
      id: "n3",
      title: "C",
      level: knowledge_domain.Organism,
      rhetorical: knowledge_domain.Evidence,
      entropy: 1.2,
      drift: 0.3,
      tags: [],
    ),
  ]
  knowledge.node_count_by_level(nodes, knowledge_domain.Atomic)
  |> should.equal(2)
}
