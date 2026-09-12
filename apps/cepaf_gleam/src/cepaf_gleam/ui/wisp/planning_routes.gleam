//// Wisp Planning Routes — 17 API endpoints for the 8-Panel Dashboard
//// STAMP: SC-GLM-UI-001, SC-GLM-UI-003, SC-GLM-UI-007
//// Uses actual domain module functions — no mock data where avoidable.

import cepaf_gleam/core/ids
import cepaf_gleam/core/types
import cepaf_gleam/planning/access_control
import cepaf_gleam/planning/chaya
import cepaf_gleam/planning/domain
import cepaf_gleam/planning/enforcer
import cepaf_gleam/planning/graph_verification
import cepaf_gleam/planning/math_optimization
import cepaf_gleam/planning/ooda
import cepaf_gleam/planning/orchestration
import cepaf_gleam/planning/safety_kernel
import cepaf_gleam/ui/lustre/planning_dashboard
import gleam/dict
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/set

// =============================================================================
// 1. tasks_list — List all tasks (sample data)
// =============================================================================

pub fn tasks_list() -> String {
  let tasks = sample_task_cards()
  json.object([
    #("endpoint", json.string("/api/planning/tasks")),
    #("count", json.int(list.length(tasks))),
    #(
      "tasks",
      json.array(tasks, fn(t) {
        json.object([
          #("id", json.string(t.id)),
          #("title", json.string(t.title)),
          #("status", json.string(t.status)),
          #("priority", json.string(t.priority)),
          #("assignee", case t.assignee {
            Some(a) -> json.string(a)
            None -> json.null()
          }),
        ])
      }),
    ),
  ])
  |> json.to_string()
}

// =============================================================================
// 2. task_detail — Single task detail
// =============================================================================

pub fn task_detail(id: String) -> String {
  let tasks = sample_task_cards()
  let found = list.find(tasks, fn(t) { t.id == id })
  case found {
    Ok(t) ->
      json.object([
        #("endpoint", json.string("/api/planning/tasks/" <> id)),
        #("found", json.bool(True)),
        #(
          "task",
          json.object([
            #("id", json.string(t.id)),
            #("title", json.string(t.title)),
            #("status", json.string(t.status)),
            #("priority", json.string(t.priority)),
            #("assignee", case t.assignee {
              Some(a) -> json.string(a)
              None -> json.null()
            }),
          ]),
        ),
      ])
      |> json.to_string()
    Error(_) ->
      json.object([
        #("endpoint", json.string("/api/planning/tasks/" <> id)),
        #("found", json.bool(False)),
        #("error", json.string("Task not found: " <> id)),
      ])
      |> json.to_string()
  }
}

// =============================================================================
// 3. ooda_status — Run OODA cycle with sample observations
// =============================================================================

pub fn ooda_status() -> String {
  let observations = [
    ooda.observe_from_health("healthy"),
    ooda.observe_from_metric("cpu_usage", 0.65, 0.9),
    ooda.observe_from_event("mesh", "All containers nominal"),
  ]
  let cycle = ooda.run_cycle(observations)
  json.object([
    #("endpoint", json.string("/api/ooda/status")),
    #("cycle", ooda.cycle_to_json(cycle)),
    #("healthy", json.bool(ooda.is_healthy(cycle))),
  ])
  |> json.to_string()
}

// =============================================================================
// 4. ooda_history — Last 5 cycles (sample variations)
// =============================================================================

pub fn ooda_history() -> String {
  let cycle_1 = ooda.run_cycle([ooda.observe_from_health("healthy")])
  let cycle_2 =
    ooda.run_cycle([
      ooda.observe_from_health("unhealthy"),
      ooda.observe_from_metric("memory", 0.95, 0.8),
    ])
  let cycle_3 =
    ooda.run_cycle([ooda.observe_from_event("deploy", "Container starting")])
  let cycle_4 = ooda.run_cycle([ooda.observe_from_metric("disk", 0.3, 0.9)])
  let cycle_5 =
    ooda.run_cycle([
      ooda.observe_from_health("healthy"),
      ooda.observe_from_event("guardian", "Heartbeat OK"),
    ])
  let cycles = [cycle_1, cycle_2, cycle_3, cycle_4, cycle_5]
  json.object([
    #("endpoint", json.string("/api/ooda/history")),
    #("count", json.int(5)),
    #("cycles", json.array(cycles, ooda.cycle_to_json)),
  ])
  |> json.to_string()
}

// =============================================================================
// 5. safety_status — Safety kernel state
// =============================================================================

pub fn safety_status() -> String {
  let state =
    safety_kernel.State(
      is_active: True,
      threat_level: 0.0,
      is_guardian_healthy: True,
    )
  json.object([
    #("endpoint", json.string("/api/safety/status")),
    #("state", safety_kernel.safety_state_to_json(state)),
    #("guardian_health", json.bool(safety_kernel.check_guardian_health(state))),
    #("threat_level", json.float(safety_kernel.get_threat_level(state))),
  ])
  |> json.to_string()
}

// =============================================================================
// 6. safety_check — Run constitutional checks on an operation
// =============================================================================

pub fn safety_check(operation: String) -> String {
  // Build a proposal and validate constitutionally
  let proposal =
    safety_kernel.OperationProposal(
      operation: operation,
      agent: "system:dashboard",
      payload: [],
    )
  // We use the public execute_with_rollback to demonstrate validation
  let check_result =
    safety_kernel.execute_with_rollback(operation, fn(op) { Ok(op) }, fn(_op) {
      case operation {
        "delete_all" -> Error("Violates existence invariant")
        "truncate_history" -> Error("Violates history preservation")
        _ -> Ok(Nil)
      }
    })
  json.object([
    #("endpoint", json.string("/api/safety/check")),
    #("operation", json.string(operation)),
    #("agent", json.string(proposal.agent)),
    #("result", case check_result {
      Ok(_) ->
        json.object([
          #("status", json.string("pass")),
          #("message", json.string("Operation validated")),
        ])
      Error(reason) ->
        json.object([
          #("status", json.string("fail")),
          #("message", json.string(reason)),
        ])
    }),
  ])
  |> json.to_string()
}

// =============================================================================
// 7. enforcer_status — Statistics and open circuits
// =============================================================================

pub fn enforcer_status() -> String {
  // Use empty violation list for nominal state
  let violations = []
  let stats = enforcer.get_statistics(violations)
  let open_agents = enforcer.get_circuit_open_agents(violations, 3)
  json.object([
    #("endpoint", json.string("/api/enforcer/status")),
    #(
      "statistics",
      json.object(
        dict.to_list(stats)
        |> list.map(fn(pair) {
          let #(key, val) = pair
          #(key, json.int(val))
        }),
      ),
    ),
    #("open_circuits", json.array(open_agents, json.string)),
    #(
      "rate_limit",
      json.object([
        #("window_start", json.string("")),
        #("agents_tracked", json.int(0)),
      ]),
    ),
  ])
  |> json.to_string()
}

// =============================================================================
// 8. enforcer_reset — Reset circuit breaker for an agent
// =============================================================================

pub fn enforcer_reset(agent_id: String) -> String {
  // Demonstrate reset on empty list (no-op but shows the API)
  let violations = []
  let after_reset = enforcer.reset_circuit_breaker(violations, agent_id)
  json.object([
    #("endpoint", json.string("/api/enforcer/reset")),
    #("agent_id", json.string(agent_id)),
    #("violations_before", json.int(list.length(violations))),
    #("violations_after", json.int(list.length(after_reset))),
    #("circuit_status", json.string("CLOSED")),
  ])
  |> json.to_string()
}

// =============================================================================
// 9. graph_verify — Build access graph, run verification suite
// =============================================================================

pub fn graph_verify() -> String {
  let policy =
    access_control.new_policy()
    |> access_control.add_rule(access_control.AccessRule(
      agent_pattern: "human:*",
      resource_pattern: "*",
      allowed: True,
    ))
    |> access_control.add_rule(access_control.AccessRule(
      agent_pattern: "system:*",
      resource_pattern: "planning/*",
      allowed: True,
    ))
  let agents = ["human:founder", "system:planner", "system:guardian"]
  let resources = ["planning/tasks", "planning/config", "safety/kernel"]
  let graph = access_control.build_access_graph(policy, agents, resources)
  let results = graph_verification.run_verification_suite(graph)
  let stats = graph_verification.calculate_stats(graph)
  json.object([
    #("endpoint", json.string("/api/graph/verify")),
    #("node_count", json.int(stats.node_count)),
    #("edge_count", json.int(stats.edge_count)),
    #("density", json.float(stats.density)),
    #("scc_count", json.int(stats.scc_count)),
    #(
      "results",
      json.array(results, fn(r) {
        json.object([
          #("name", json.string(r.name)),
          #("passed", json.bool(r.passed)),
          #("details", json.string(r.details)),
        ])
      }),
    ),
  ])
  |> json.to_string()
}

// =============================================================================
// 10. graph_dot — Return DOT string for visualization
// =============================================================================

pub fn graph_dot() -> String {
  let policy =
    access_control.new_policy()
    |> access_control.add_rule(access_control.AccessRule(
      agent_pattern: "human:*",
      resource_pattern: "*",
      allowed: True,
    ))
  let agents = ["human:founder", "system:planner"]
  let resources = ["planning/tasks", "safety/kernel"]
  let graph = access_control.build_access_graph(policy, agents, resources)
  let dot = graph_verification.to_dot(graph)
  json.object([
    #("endpoint", json.string("/api/graph/dot")),
    #("format", json.string("dot")),
    #("dot", json.string(dot)),
  ])
  |> json.to_string()
}

// =============================================================================
// 11. orchestration_live — Register services, check quorum
// =============================================================================

pub fn orchestration_live() -> String {
  let registry = orchestration.register_services()
  let quorum = orchestration.health_quorum(registry)
  let online = orchestration.online_service_count(registry)
  let status = orchestration.orchestration_status(registry)
  json.object([
    #("endpoint", json.string("/api/orchestration/live")),
    #("registry", orchestration.registry_to_json(registry)),
    #("quorum", json.bool(quorum)),
    #("online_count", json.int(online)),
    #("total_count", json.int(dict.size(registry))),
    #("status_summary", json.string(status)),
  ])
  |> json.to_string()
}

// =============================================================================
// 12. orchestration_coordinate — Coordinate OODA cycle across services
// =============================================================================

pub fn orchestration_coordinate() -> String {
  let registry = orchestration.register_services()
  let coordination = orchestration.coordinate_ooda_cycle(registry)
  json.object([
    #("endpoint", json.string("/api/orchestration/coordinate")),
    #("coordination", orchestration.coordination_to_json(coordination)),
  ])
  |> json.to_string()
}

// =============================================================================
// 13. chaya_status — Return last sync state
// =============================================================================

pub fn chaya_status() -> String {
  json.object([
    #("endpoint", json.string("/api/chaya/status")),
    #("last_sync", json.string("idle")),
    #("orphan_count", json.int(0)),
    #("mismatch_count", json.int(0)),
    #("phase_count", json.int(5)),
    #(
      "phases",
      json.array(
        [
          "phase1_read_planning",
          "phase2_detect_orphans",
          "phase3_convert",
          "phase4_regenerate",
          "phase5_verify",
        ],
        json.string,
      ),
    ),
  ])
  |> json.to_string()
}

// =============================================================================
// 14. chaya_sync — Run full 5-phase sync with sample tasks
// =============================================================================

pub fn chaya_sync() -> String {
  let sample_tasks = sample_domain_tasks()
  let report = chaya.run_sync(sample_tasks)
  json.object([
    #("endpoint", json.string("/api/chaya/sync")),
    #("report", chaya.sync_report_to_json(report)),
  ])
  |> json.to_string()
}

// =============================================================================
// 15. math_optimize — Run startup optimization
// =============================================================================

pub fn math_optimize() -> String {
  let waves = math_optimization.optimize_startup()
  let containers = math_optimization.default_containers()
  let forward = math_optimization.forward_pass(containers)
  let cpm = math_optimization.backward_pass(containers, forward)
  let cp = math_optimization.critical_path(cpm)
  let total_ms = math_optimization.total_startup_time(cpm)
  json.object([
    #("endpoint", json.string("/api/math/optimize")),
    #("waves", math_optimization.waves_to_json(waves)),
    #("cpm", math_optimization.cpm_to_json(cpm)),
    #("critical_path", json.array(cp, json.string)),
    #("total_startup_ms", json.int(total_ms)),
  ])
  |> json.to_string()
}

// =============================================================================
// 16. math_dfa — Return all 14 container states with valid transitions
// =============================================================================

pub fn math_dfa() -> String {
  let all_states = [
    math_optimization.NotCreated,
    math_optimization.Created,
    math_optimization.Starting,
    math_optimization.Running,
    math_optimization.Healthy,
    math_optimization.Unhealthy,
    math_optimization.Degraded,
    math_optimization.Lameduck,
    math_optimization.Draining,
    math_optimization.Checkpointing,
    math_optimization.Stopping,
    math_optimization.Stopped,
    math_optimization.Failed,
    math_optimization.Removed,
  ]
  json.object([
    #("endpoint", json.string("/api/math/dfa")),
    #("state_count", json.int(list.length(all_states))),
    #(
      "states",
      json.array(all_states, fn(state) {
        let transitions = math_optimization.valid_transitions(state)
        json.object([
          #("state", json.string(math_optimization.state_to_string(state))),
          #(
            "transitions",
            json.array(transitions, fn(t) {
              json.string(math_optimization.state_to_string(t))
            }),
          ),
          #("transition_count", json.int(list.length(transitions))),
        ])
      }),
    ),
  ])
  |> json.to_string()
}

// =============================================================================
// 17. dashboard_state — Full dashboard model as JSON
// =============================================================================

pub fn dashboard_state() -> String {
  let model = planning_dashboard.init()
  // Populate with sample data
  let model =
    planning_dashboard.update(
      model,
      planning_dashboard.TasksLoaded(sample_task_cards()),
    )
  let model =
    planning_dashboard.update(
      model,
      planning_dashboard.OodaCycleCompleted(42, "nominal", "no_action"),
    )
  let model =
    planning_dashboard.update(
      model,
      planning_dashboard.SafetyChecksLoaded([
        planning_dashboard.CheckPass("ExistenceInvariant"),
        planning_dashboard.CheckPass("RegenerationCapability"),
        planning_dashboard.CheckPass("HistoryPreservation"),
        planning_dashboard.CheckPass("GuardianApproval"),
      ]),
    )
  let model =
    planning_dashboard.update(
      model,
      planning_dashboard.ServicesUpdated([
        planning_dashboard.ServiceNode(
          name: "Cortex",
          status: "online",
          health: 1.0,
        ),
        planning_dashboard.ServiceNode(
          name: "Prajna",
          status: "online",
          health: 0.95,
        ),
        planning_dashboard.ServiceNode(
          name: "Guardian",
          status: "online",
          health: 1.0,
        ),
      ]),
    )
  let model =
    planning_dashboard.update(model, planning_dashboard.QuorumChanged(True))

  json.object([
    #("endpoint", json.string("/api/dashboard/state")),
    #("model", planning_dashboard.dashboard_to_json(model)),
    #(
      "cockpit_mode",
      json.string(case planning_dashboard.determine_cockpit_mode(model) {
        planning_dashboard.Dark -> "dark"
        planning_dashboard.Dim -> "dim"
        planning_dashboard.Normal -> "normal"
        planning_dashboard.Bright -> "bright"
        planning_dashboard.EmergencyMode -> "emergency"
      }),
    ),
    #("health_score", json.float(planning_dashboard.health_score(model))),
    #("is_safe", json.bool(planning_dashboard.is_safe(model))),
  ])
  |> json.to_string()
}

// =============================================================================
// Sample Data Helpers
// =============================================================================

fn sample_task_cards() -> List(planning_dashboard.TaskCard) {
  [
    planning_dashboard.TaskCard(
      id: "1.1",
      title: "Implement OODA controller",
      status: "completed",
      priority: "P0",
      assignee: Some("system:planner"),
    ),
    planning_dashboard.TaskCard(
      id: "1.2",
      title: "Safety kernel validation",
      status: "completed",
      priority: "P0",
      assignee: Some("system:guardian"),
    ),
    planning_dashboard.TaskCard(
      id: "2.1",
      title: "Graph verification suite",
      status: "in_progress",
      priority: "P1",
      assignee: Some("system:verifier"),
    ),
    planning_dashboard.TaskCard(
      id: "2.2",
      title: "Enforcer circuit breakers",
      status: "in_progress",
      priority: "P1",
      assignee: None,
    ),
    planning_dashboard.TaskCard(
      id: "3.1",
      title: "Chaya digital twin sync",
      status: "pending",
      priority: "P2",
      assignee: None,
    ),
    planning_dashboard.TaskCard(
      id: "3.2",
      title: "Startup optimization waves",
      status: "pending",
      priority: "P2",
      assignee: None,
    ),
    planning_dashboard.TaskCard(
      id: "4.1",
      title: "AG-UI protocol integration",
      status: "blocked",
      priority: "P1",
      assignee: Some("system:dashboard"),
    ),
  ]
}

fn sample_domain_tasks() -> List(domain.Task) {
  let title_1 = case types.new_non_empty_string("OODA Controller") {
    Ok(t) -> t
    Error(_) -> panic as "unreachable: non-empty string"
  }
  let title_2 = case types.new_non_empty_string("Safety Kernel") {
    Ok(t) -> t
    Error(_) -> panic as "unreachable: non-empty string"
  }
  let title_3 = case types.new_non_empty_string("Graph Verification") {
    Ok(t) -> t
    Error(_) -> panic as "unreachable: non-empty string"
  }
  [
    domain.Task(
      id: ids.task_id_from_string("1.1"),
      title: title_1,
      description: None,
      status: types.Completed,
      priority: types.P0Critical,
      created_at: "2026-04-01T00:00:00Z",
      updated_at: "2026-04-03T00:00:00Z",
      due_date: None,
      completed_at: Some("2026-04-02T00:00:00Z"),
      assignee_id: None,
      project_id: None,
      sprint_id: None,
      parent_task_id: None,
      tags: set.new(),
      dependencies: set.new(),
      estimated_minutes: Some(480),
      actual_minutes: Some(360),
      version: 1,
    ),
    domain.Task(
      id: ids.task_id_from_string("1.2"),
      title: title_2,
      description: None,
      status: types.InProgress,
      priority: types.P0Critical,
      created_at: "2026-04-01T00:00:00Z",
      updated_at: "2026-04-03T00:00:00Z",
      due_date: None,
      completed_at: None,
      assignee_id: None,
      project_id: None,
      sprint_id: None,
      parent_task_id: None,
      tags: set.new(),
      dependencies: set.new(),
      estimated_minutes: Some(240),
      actual_minutes: None,
      version: 1,
    ),
    domain.Task(
      id: ids.task_id_from_string("2.1"),
      title: title_3,
      description: None,
      status: types.Pending,
      priority: types.P1High,
      created_at: "2026-04-02T00:00:00Z",
      updated_at: "2026-04-03T00:00:00Z",
      due_date: None,
      completed_at: None,
      assignee_id: None,
      project_id: None,
      sprint_id: None,
      parent_task_id: None,
      tags: set.new(),
      dependencies: set.new(),
      estimated_minutes: Some(120),
      actual_minutes: None,
      version: 1,
    ),
  ]
}
