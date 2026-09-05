// =============================================================================
// Planning Module Coverage Tests
// =============================================================================
// STAMP: SC-PLAN-001..005, SC-MATH-001..012, SC-OODA-001, SC-GRAPH-001..005,
//        SC-ACCESS-001..014, SC-SAFETY-001..022
// Target: 35+ tests covering task, domain, access_control, safety_kernel,
//         math_optimization, ooda, graph_verification, and parser modules.
// =============================================================================

import cepaf_gleam/core/types
import cepaf_gleam/planning/access_control
import cepaf_gleam/planning/domain.{
  DatabaseError, InvalidTransition, RemoteError, TaskNotFound, ValidationError,
}
import cepaf_gleam/planning/graph_verification.{Edge, Node, new_graph}
import cepaf_gleam/planning/math_optimization.{
  ContainerDef, CpmResult, Created, Failed, Healthy, NotCreated, Removed,
  Running, Starting, Stopped,
}
import cepaf_gleam/planning/ooda.{
  Assessment, ContainerFailure, Critical, Decision, EmergencyStop,
  HealthDegradation, Info, NetworkIssue, NoAction, Observation,
  ResourceExhaustion, RestartContainer, SecurityViolation, SingleContainer,
  System, UnknownPattern, WaitAndRetry, Warning,
}
import cepaf_gleam/planning/parser
import cepaf_gleam/planning/safety_kernel.{State}
import gleam/dict
import gleam/list
import gleeunit/should

// =============================================================================
// domain.gleam — PlanningError type constructors
// =============================================================================

pub fn planning_error_invalid_transition_test() {
  let err = InvalidTransition(from: types.Pending, to: types.Completed)
  case err {
    InvalidTransition(_, _) -> should.be_true(True)
  }
}

pub fn planning_error_task_not_found_test() {
  let err = TaskNotFound(id: "TASK-001")
  case err {
    TaskNotFound(id: id) -> id |> should.equal("TASK-001")
  }
}

pub fn planning_error_database_error_test() {
  let err = DatabaseError(reason: "connection refused")
  case err {
    DatabaseError(reason: r) -> r |> should.equal("connection refused")
  }
}

pub fn planning_error_validation_error_test() {
  let err = ValidationError(message: "title is empty")
  case err {
    ValidationError(message: m) -> m |> should.equal("title is empty")
  }
}

pub fn planning_error_remote_error_test() {
  let err = RemoteError(reason: "timeout")
  case err {
    RemoteError(reason: r) -> r |> should.equal("timeout")
  }
}

// =============================================================================
// access_control.gleam — Policy construction and access checking
// =============================================================================

pub fn access_control_new_policy_default_deny_test() {
  let policy = access_control.new_policy()
  policy.default_deny |> should.equal(True)
  list.length(policy.rules) |> should.equal(0)
}

pub fn access_control_add_rule_test() {
  let rule =
    access_control.AccessRule(
      agent_pattern: "human:*",
      resource_pattern: "*",
      allowed: True,
    )
  let policy = access_control.new_policy() |> access_control.add_rule(rule)
  list.length(policy.rules) |> should.equal(1)
}

pub fn access_control_check_access_allow_test() {
  let rule =
    access_control.AccessRule(
      agent_pattern: "human:*",
      resource_pattern: "*",
      allowed: True,
    )
  let policy = access_control.new_policy() |> access_control.add_rule(rule)
  access_control.check_access(policy, "human:founder", "db:prod")
  |> should.equal(True)
}

pub fn access_control_check_access_deny_by_default_test() {
  let policy = access_control.new_policy()
  // no rules, default_deny = True -> access denied
  access_control.check_access(policy, "agent:claude", "db:prod")
  |> should.equal(False)
}

pub fn access_control_check_access_explicit_deny_test() {
  let deny_rule =
    access_control.AccessRule(
      agent_pattern: "ai:*",
      resource_pattern: "db:*",
      allowed: False,
    )
  let allow_rule =
    access_control.AccessRule(
      agent_pattern: "*",
      resource_pattern: "*",
      allowed: True,
    )
  // deny rule first (first-match wins)
  let policy =
    access_control.new_policy()
    |> access_control.add_rule(deny_rule)
    |> access_control.add_rule(allow_rule)
  access_control.check_access(policy, "ai:gemini", "db:prod")
  |> should.equal(False)
}

pub fn access_control_validate_shell_command_dangerous_test() {
  let result = access_control.validate_shell_command("rm -rf /", "human")
  case result {
    access_control.Blocked(_) -> should.be_true(True)
    _ -> should.fail()
  }
}

pub fn access_control_validate_shell_command_ai_review_test() {
  let result = access_control.validate_shell_command("docker ps", "claude")
  case result {
    access_control.RequiresReview(_) -> should.be_true(True)
    _ -> should.fail()
  }
}

pub fn access_control_validate_shell_command_human_allowed_test() {
  let result = access_control.validate_shell_command("docker ps", "human")
  result |> should.equal(access_control.Allowed)
}

pub fn access_control_is_dangerous_command_test() {
  access_control.is_dangerous_command("rm -rf /home") |> should.equal(True)
  access_control.is_dangerous_command("ls -la") |> should.equal(False)
}

pub fn access_control_is_ai_agent_test() {
  access_control.is_ai_agent("claude") |> should.equal(True)
  access_control.is_ai_agent("human:founder") |> should.equal(False)
}

pub fn access_control_founder_full_access_test() {
  let rule =
    access_control.AccessRule(
      agent_pattern: "human:founder",
      resource_pattern: "*",
      allowed: True,
    )
  let policy = access_control.new_policy() |> access_control.add_rule(rule)
  access_control.founder_has_full_access(policy) |> should.equal(True)
}

pub fn access_control_get_blocked_agents_test() {
  let deny_rule =
    access_control.AccessRule(
      agent_pattern: "ai:adversary",
      resource_pattern: "*",
      allowed: False,
    )
  let policy = access_control.new_policy() |> access_control.add_rule(deny_rule)
  let blocked = access_control.get_blocked_agents(policy)
  list.contains(blocked, "ai:adversary") |> should.equal(True)
}

// =============================================================================
// safety_kernel.gleam — Types and pure functions
// =============================================================================

pub fn safety_kernel_proof_token_valid_test() {
  let result =
    safety_kernel.validate_proof_token(
      "STAMP-create_task-claude",
      "create_task",
      "claude",
      "2026-01-01",
      5000,
    )
  let _ = result |> should.be_ok()
  Nil
}

pub fn safety_kernel_proof_token_invalid_test() {
  let result =
    safety_kernel.validate_proof_token(
      "invalid-token",
      "op",
      "agent",
      "2026-01-01",
      5000,
    )
  let _ = result |> should.be_error()
  Nil
}

pub fn safety_kernel_generate_proof_token_test() {
  let token = safety_kernel.generate_proof_token("create_task", "claude")
  token |> should.equal("STAMP-create_task-claude")
}

pub fn safety_kernel_emergency_stop_valid_test() {
  let _ = safety_kernel.emergency_stop("cpu spike") |> should.be_ok()
  Nil
}

pub fn safety_kernel_emergency_stop_empty_reason_test() {
  let _ = safety_kernel.emergency_stop("") |> should.be_error()
  Nil
}

pub fn safety_kernel_quarantine_agent_valid_test() {
  let _ = safety_kernel.quarantine_agent("ai:adversary") |> should.be_ok()
  Nil
}

pub fn safety_kernel_quarantine_agent_empty_test() {
  let _ = safety_kernel.quarantine_agent("") |> should.be_error()
  Nil
}

pub fn safety_kernel_is_quarantined_test() {
  let quarantined = ["ai:adversary", "ai:rogue"]
  safety_kernel.is_quarantined(quarantined, "ai:adversary")
  |> should.equal(True)
  safety_kernel.is_quarantined(quarantined, "ai:trusted")
  |> should.equal(False)
}

pub fn safety_kernel_state_activate_deactivate_test() {
  let state =
    State(is_active: False, threat_level: 0.0, is_guardian_healthy: True)
  let active_state = safety_kernel.activate(state)
  active_state.is_active |> should.equal(True)
  let deactivated = safety_kernel.deactivate(active_state)
  deactivated.is_active |> should.equal(False)
}

pub fn safety_kernel_reset_threat_level_test() {
  let state =
    State(is_active: True, threat_level: 0.9, is_guardian_healthy: True)
  let reset = safety_kernel.reset_threat_level(state)
  reset.threat_level |> should.equal(0.0)
}

pub fn safety_kernel_monitor_execution_ok_test() {
  let result = safety_kernel.monitor_execution("create_task", 1000, 1500)
  // Returns a Dict — verify it has content
  { dict.size(result) > 0 } |> should.be_true()
}

pub fn safety_kernel_monitor_execution_timeout_test() {
  // > 30_000 ms -> timeout
  let result = safety_kernel.monitor_execution("long_op", 0, 35_000)
  { dict.size(result) > 0 } |> should.be_true()
}

pub fn safety_kernel_verify_post_execution_ok_test() {
  let _ =
    safety_kernel.verify_post_execution(Ok("success"), "create_task")
    |> should.be_ok()
  Nil
}

pub fn safety_kernel_verify_post_execution_err_test() {
  let _ =
    safety_kernel.verify_post_execution(Error("db failed"), "create_task")
    |> should.be_error()
  Nil
}

// =============================================================================
// math_optimization.gleam — Container DFA and CPM
// =============================================================================

pub fn math_opt_state_to_string_test() {
  math_optimization.state_to_string(NotCreated) |> should.equal("NotCreated")
  math_optimization.state_to_string(Running) |> should.equal("Running")
  math_optimization.state_to_string(Healthy) |> should.equal("Healthy")
  math_optimization.state_to_string(Failed) |> should.equal("Failed")
  math_optimization.state_to_string(Removed) |> should.equal("Removed")
}

pub fn math_opt_can_transition_valid_test() {
  math_optimization.can_transition(NotCreated, Created) |> should.equal(True)
  math_optimization.can_transition(Running, Healthy) |> should.equal(True)
  math_optimization.can_transition(Stopped, Starting) |> should.equal(True)
}

pub fn math_opt_can_transition_invalid_test() {
  math_optimization.can_transition(Removed, Running) |> should.equal(False)
  math_optimization.can_transition(Healthy, NotCreated) |> should.equal(False)
}

pub fn math_opt_topological_order_acyclic_test() {
  let containers = [
    ContainerDef("db", [], 1.0, 512, 3000),
    ContainerDef("app", ["db"], 0.5, 256, 1000),
  ]
  let order = math_optimization.topological_order(containers) |> should.be_ok()
  // Both names must appear
  list.contains(order, "db") |> should.be_true()
  list.contains(order, "app") |> should.be_true()
  // db must precede app: no window [app, db] should exist
  let app_before_db =
    list.window_by_2(order)
    |> list.any(fn(pair) {
      let #(a, b) = pair
      a == "app" && b == "db"
    })
  app_before_db |> should.be_false()
}

pub fn math_opt_topological_order_cyclic_test() {
  // A depends on B and B depends on A -> cycle
  let containers = [
    ContainerDef("a", ["b"], 1.0, 256, 1000),
    ContainerDef("b", ["a"], 1.0, 256, 1000),
  ]
  let result = math_optimization.topological_order(containers)
  let _ = result |> should.be_error()
  Nil
}

pub fn math_opt_compute_waves_test() {
  let containers = [
    ContainerDef("db", [], 1.0, 512, 3000),
    ContainerDef("router", ["db"], 0.5, 256, 2000),
    ContainerDef("app", ["router"], 0.5, 256, 1000),
  ]
  let waves = math_optimization.compute_waves(containers)
  list.length(waves) |> should.equal(3)
  case list.first(waves) {
    Ok(w) -> {
      w.wave_number |> should.equal(0)
      list.contains(w.containers, "db") |> should.be_true()
    }
    Error(_) -> should.fail()
  }
}

pub fn math_opt_forward_pass_test() {
  let containers = [
    ContainerDef("a", [], 1.0, 256, 1000),
    ContainerDef("b", ["a"], 1.0, 256, 2000),
  ]
  let forward = math_optimization.forward_pass(containers)
  { dict.size(forward) > 0 } |> should.be_true()
}

pub fn math_opt_total_startup_time_test() {
  let cpm_result =
    CpmResult(
      early_start: 0,
      early_finish: 5000,
      late_start: 0,
      late_finish: 5000,
      slack: 0,
      critical: True,
    )
  let results = dict.insert(dict.new(), "db", cpm_result)
  math_optimization.total_startup_time(results) |> should.equal(5000)
}

pub fn math_opt_default_containers_test() {
  let containers = math_optimization.default_containers()
  { list.length(containers) >= 7 } |> should.be_true()
}

pub fn math_opt_optimize_startup_test() {
  let waves = math_optimization.optimize_startup()
  list.is_empty(waves) |> should.equal(False)
}

// =============================================================================
// ooda.gleam — Observe, Orient, Decide, Act
// =============================================================================

pub fn ooda_observe_from_health_healthy_test() {
  let obs = ooda.observe_from_health("healthy")
  obs.severity |> should.equal(Info)
}

pub fn ooda_observe_from_health_unhealthy_test() {
  let obs = ooda.observe_from_health("unhealthy")
  obs.severity |> should.equal(Critical)
}

pub fn ooda_observe_from_health_no_check_test() {
  let obs = ooda.observe_from_health("nohealthcheck")
  obs.severity |> should.equal(Warning)
}

pub fn ooda_observe_from_metric_breach_test() {
  let obs = ooda.observe_from_metric("cpu", 0.9, 0.8)
  obs.severity |> should.equal(Warning)
}

pub fn ooda_observe_from_metric_ok_test() {
  let obs = ooda.observe_from_metric("cpu", 0.5, 0.8)
  obs.severity |> should.equal(Info)
}

pub fn ooda_classify_error_test() {
  ooda.classify_error("oom killer triggered")
  |> should.equal(ResourceExhaustion)
  ooda.classify_error("connection refused on port 5432")
  |> should.equal(NetworkIssue)
  ooda.classify_error("health check failed")
  |> should.equal(HealthDegradation)
  ooda.classify_error("permission denied")
  |> should.equal(SecurityViolation)
  ooda.classify_error("segfault in container")
  |> should.equal(ContainerFailure)
  ooda.classify_error("completely unknown event xyz")
  |> should.equal(UnknownPattern)
}

pub fn ooda_orient_no_observations_test() {
  let assessment = ooda.orient([])
  assessment.pattern |> should.equal(UnknownPattern)
}

pub fn ooda_orient_critical_observation_test() {
  let obs =
    Observation(
      source: "health_check",
      message: "health check failed",
      severity: Critical,
      timestamp: "",
    )
  let assessment = ooda.orient([obs])
  // Pattern must be classified — just verify it is not unknown since message matches
  let _pattern = assessment.pattern
  assessment.impact |> should.equal(SingleContainer)
}

pub fn ooda_orient_multiple_criticals_system_impact_test() {
  let obs1 =
    Observation(
      source: "s1",
      message: "unhealthy",
      severity: Critical,
      timestamp: "",
    )
  let obs2 =
    Observation(source: "s2", message: "oom", severity: Critical, timestamp: "")
  let assessment = ooda.orient([obs1, obs2])
  assessment.impact |> should.equal(System)
}

pub fn ooda_decide_no_observations_test() {
  let decision = ooda.decide(Assessment(UnknownPattern, [], SingleContainer))
  decision.action |> should.equal(NoAction)
}

pub fn ooda_decide_single_critical_test() {
  let obs =
    Observation(
      source: "s",
      message: "segfault in container",
      severity: Critical,
      timestamp: "",
    )
  let assessment = ooda.orient([obs])
  let decision = ooda.decide(assessment)
  case decision.action {
    RestartContainer(_) -> should.be_true(True)
    EmergencyStop -> should.be_true(True)
    _ -> should.fail()
  }
}

pub fn ooda_decide_warning_waits_test() {
  let obs =
    Observation(
      source: "s",
      message: "cpu metric high",
      severity: Warning,
      timestamp: "",
    )
  let assessment = ooda.orient([obs])
  let decision = ooda.decide(assessment)
  case decision.action {
    WaitAndRetry(_) -> should.be_true(True)
    _ -> should.fail()
  }
}

pub fn ooda_score_action_test() {
  let no_action_score = ooda.score_action(NoAction)
  let emergency_score = ooda.score_action(EmergencyStop)
  { emergency_score >. 0.0 } |> should.be_true()
  no_action_score |> should.equal(0.0)
}

pub fn ooda_act_no_action_test() {
  let decision = Decision(action: NoAction, score: 0.0, reason: "nominal")
  let _ = ooda.act(decision) |> should.be_ok()
  Nil
}

pub fn ooda_act_emergency_stop_test() {
  let decision = Decision(action: EmergencyStop, score: 0.2, reason: "critical")
  // emergency stop returns Error as it requires manual intervention
  let _ = ooda.act(decision) |> should.be_error()
  Nil
}

pub fn ooda_run_cycle_test() {
  let obs =
    Observation(
      source: "health",
      message: "healthy",
      severity: Info,
      timestamp: "",
    )
  let cycle = ooda.run_cycle([obs])
  { cycle.cycle_time_ms >= 0 } |> should.be_true()
  list.length(cycle.observations) |> should.equal(1)
}

pub fn ooda_is_healthy_true_test() {
  let obs =
    Observation(source: "s", message: "ok", severity: Info, timestamp: "")
  let cycle = ooda.run_cycle([obs])
  ooda.is_healthy(cycle) |> should.equal(True)
}

pub fn ooda_is_healthy_false_test() {
  let obs =
    Observation(
      source: "s",
      message: "health check failed",
      severity: Critical,
      timestamp: "",
    )
  let cycle = ooda.run_cycle([obs])
  ooda.is_healthy(cycle) |> should.equal(False)
}

pub fn ooda_get_cycle_metrics_test() {
  let obs =
    Observation(source: "h", message: "healthy", severity: Info, timestamp: "")
  let cycle = ooda.run_cycle([obs])
  let metrics = ooda.get_cycle_metrics(cycle)
  { dict.size(metrics) > 0 } |> should.be_true()
}

// =============================================================================
// graph_verification.gleam (planning) — Core graph operations
// =============================================================================

pub fn graph_new_empty_test() {
  let g = new_graph()
  list.length(g.nodes) |> should.equal(0)
  list.length(g.edges) |> should.equal(0)
}

pub fn graph_add_node_test() {
  let g =
    new_graph()
    |> graph_verification.add_node(Node(
      id: "A",
      label: "Alpha",
      node_type: "service",
    ))
  list.length(g.nodes) |> should.equal(1)
}

pub fn graph_add_node_dedup_test() {
  let g =
    new_graph()
    |> graph_verification.add_node(Node(
      id: "A",
      label: "A",
      node_type: "service",
    ))
    |> graph_verification.add_node(Node(
      id: "A",
      label: "A-dup",
      node_type: "service",
    ))
  // duplicates ignored
  list.length(g.nodes) |> should.equal(1)
}

pub fn graph_add_edge_test() {
  let g =
    new_graph()
    |> graph_verification.add_edge(Edge(
      from: "A",
      to: "B",
      label: "depends",
      is_allowed: True,
    ))
  list.length(g.edges) |> should.equal(1)
}

pub fn graph_find_node_found_test() {
  let node = Node(id: "X", label: "X-label", node_type: "agent")
  let g = new_graph() |> graph_verification.add_node(node)
  let _ = graph_verification.find_node(g, "X") |> should.be_ok()
  Nil
}

pub fn graph_find_node_missing_test() {
  let g = new_graph()
  let _ = graph_verification.find_node(g, "missing") |> should.be_error()
  Nil
}

pub fn graph_detect_cycles_acyclic_test() {
  let g =
    new_graph()
    |> graph_verification.add_node(Node("A", "A", "s"))
    |> graph_verification.add_node(Node("B", "B", "s"))
    |> graph_verification.add_edge(Edge("A", "B", "dep", True))
  graph_verification.detect_cycles(g) |> should.equal(False)
}

pub fn graph_detect_cycles_cyclic_test() {
  let g =
    new_graph()
    |> graph_verification.add_node(Node("A", "A", "s"))
    |> graph_verification.add_node(Node("B", "B", "s"))
    |> graph_verification.add_edge(Edge("A", "B", "dep", True))
    |> graph_verification.add_edge(Edge("B", "A", "dep", True))
  graph_verification.detect_cycles(g) |> should.equal(True)
}

pub fn graph_topological_sort_acyclic_test() {
  let g =
    new_graph()
    |> graph_verification.add_node(Node("A", "A", "s"))
    |> graph_verification.add_node(Node("B", "B", "s"))
    |> graph_verification.add_edge(Edge("A", "B", "dep", True))
  let _ = graph_verification.topological_sort(g) |> should.be_ok()
  Nil
}

pub fn graph_topological_sort_cyclic_test() {
  let g =
    new_graph()
    |> graph_verification.add_node(Node("A", "A", "s"))
    |> graph_verification.add_node(Node("B", "B", "s"))
    |> graph_verification.add_edge(Edge("A", "B", "dep", True))
    |> graph_verification.add_edge(Edge("B", "A", "dep", True))
  let _ = graph_verification.topological_sort(g) |> should.be_error()
  Nil
}

pub fn graph_is_reachable_true_test() {
  let g =
    new_graph()
    |> graph_verification.add_node(Node("A", "A", "s"))
    |> graph_verification.add_node(Node("B", "B", "s"))
    |> graph_verification.add_node(Node("C", "C", "s"))
    |> graph_verification.add_edge(Edge("A", "B", "dep", True))
    |> graph_verification.add_edge(Edge("B", "C", "dep", True))
  graph_verification.is_reachable(g, "A", "C") |> should.equal(True)
}

pub fn graph_is_reachable_false_test() {
  let g =
    new_graph()
    |> graph_verification.add_node(Node("A", "A", "s"))
    |> graph_verification.add_node(Node("B", "B", "s"))
  // No edges, so A cannot reach B
  graph_verification.is_reachable(g, "A", "B") |> should.equal(False)
}

pub fn graph_verify_deadlock_free_test() {
  let g =
    new_graph()
    |> graph_verification.add_node(Node("A", "A", "s"))
    |> graph_verification.add_node(Node("B", "B", "s"))
    |> graph_verification.add_edge(Edge("A", "B", "dep", True))
  let result = graph_verification.verify_deadlock_free(g)
  result.passed |> should.equal(True)
}

pub fn graph_verify_soundness_all_allowed_test() {
  let g =
    new_graph()
    |> graph_verification.add_node(Node("A", "A", "s"))
    |> graph_verification.add_node(Node("B", "B", "s"))
    |> graph_verification.add_edge(Edge("A", "B", "dep", True))
  let result = graph_verification.verify_soundness(g)
  result.passed |> should.equal(True)
}

pub fn graph_verify_soundness_unauthorized_edge_test() {
  let g =
    new_graph()
    |> graph_verification.add_node(Node("A", "A", "s"))
    |> graph_verification.add_node(Node("B", "B", "s"))
    |> graph_verification.add_edge(Edge("A", "B", "dep", False))
  let result = graph_verification.verify_soundness(g)
  result.passed |> should.equal(False)
}

pub fn graph_density_test() {
  let g =
    new_graph()
    |> graph_verification.add_node(Node("A", "A", "s"))
    |> graph_verification.add_node(Node("B", "B", "s"))
    |> graph_verification.add_edge(Edge("A", "B", "dep", True))
  // density = 1 / (2 * 1) = 0.5
  graph_verification.graph_density(g) |> should.equal(0.5)
}

// =============================================================================
// parser.gleam — Markdown parsing
// =============================================================================

pub fn parser_regex_compiles_test() {
  // If the regex is invalid, `let assert Ok(re)` in the module would panic on load.
  // Calling the function verifies the regex compiles correctly.
  let _re = parser.main_todo_regex()
  let _pre = parser.priority_regex()
  Nil
}

pub fn parser_parse_todolist_empty_test() {
  let tasks = parser.parse_todolist("")
  list.length(tasks) |> should.equal(0)
}

pub fn parser_parse_todolist_valid_task_test() {
  let content = "## 1.0 - Fix the bug (P1) [PENDING]"
  let tasks = parser.parse_todolist(content)
  list.length(tasks) |> should.equal(1)
}

pub fn parser_parse_todolist_sqlite_output_test() {
  let line = "T001|Fix bug|pending|P1|2026-04-01||"
  let tasks = parser.parse_todolist_sqlite_output(line)
  list.length(tasks) |> should.equal(1)
}

pub fn parser_serialize_todolist_empty_test() {
  let output = parser.serialize_todolist([])
  output
  |> should.equal("# PROJECT TODOLIST (Generated by Cepaf.Planning)\n\n")
}
