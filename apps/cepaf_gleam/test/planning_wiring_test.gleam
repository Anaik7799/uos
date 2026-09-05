/// Planning page wiring tests — verifies all 6 wiring connections.
/// STAMP: SC-GLM-UI-001, SC-AGUI-011, SC-A2UI-002
import cepaf_gleam/a2ui/catalog
import cepaf_gleam/a2ui/schema.{ComponentProposal}
import cepaf_gleam/a2ui/validator
import cepaf_gleam/agui/tools
import cepaf_gleam/planning/zenoh_adapter
import cepaf_gleam/ui/lustre/planning_dashboard
import gleam/json
import gleam/list
import gleam/option.{None}
import gleam/string
import gleeunit/should

// ── C1: Planning Dashboard Init ──────────────────────────────
pub fn dashboard_init_has_dark_mode_test() {
  let model = planning_dashboard.init()
  model.cockpit_mode |> should.equal(planning_dashboard.Dark)
}

pub fn dashboard_init_has_empty_tasks_test() {
  let model = planning_dashboard.init()
  list.length(model.tasks) |> should.equal(0)
}

// ── C5: Drag-Drop ────────────────────────────────────────────
pub fn drag_drop_changes_task_status_test() {
  let model = planning_dashboard.init()
  // Load tasks
  let model =
    planning_dashboard.update(
      model,
      planning_dashboard.TasksLoaded([
        planning_dashboard.TaskCard(
          id: "t1",
          title: "Test",
          status: "pending",
          priority: "P0",
          assignee: None,
        ),
      ]),
    )
  // Drag to in_progress
  let model =
    planning_dashboard.update(
      model,
      planning_dashboard.DragTaskDropped("t1", "in_progress"),
    )
  let task = list.find(model.tasks, fn(t) { t.id == "t1" })
  case task {
    Ok(t) -> t.status |> should.equal("in_progress")
    Error(_) -> should.fail()
  }
}

pub fn drag_drop_preserves_other_tasks_test() {
  let model = planning_dashboard.init()
  let model =
    planning_dashboard.update(
      model,
      planning_dashboard.TasksLoaded([
        planning_dashboard.TaskCard(
          id: "t1",
          title: "A",
          status: "pending",
          priority: "P0",
          assignee: None,
        ),
        planning_dashboard.TaskCard(
          id: "t2",
          title: "B",
          status: "completed",
          priority: "P1",
          assignee: None,
        ),
      ]),
    )
  let model =
    planning_dashboard.update(
      model,
      planning_dashboard.DragTaskDropped("t1", "blocked"),
    )
  let t2 = list.find(model.tasks, fn(t) { t.id == "t2" })
  case t2 {
    Ok(t) -> t.status |> should.equal("completed")
    Error(_) -> should.fail()
  }
}

pub fn drag_start_does_not_change_model_test() {
  let model = planning_dashboard.init()
  let model2 =
    planning_dashboard.update(model, planning_dashboard.DragTaskStarted("t1"))
  model2.cockpit_mode |> should.equal(model.cockpit_mode)
}

// ── AG-UI: Run Lifecycle ─────────────────────────────────────
pub fn agui_run_started_sets_connected_test() {
  let model = planning_dashboard.init()
  let model =
    planning_dashboard.update(
      model,
      planning_dashboard.AgUiRunStarted("thread-1", "run-1"),
    )
  model.ag_ui_connected |> should.be_true()
}

pub fn agui_run_error_escalates_cockpit_mode_test() {
  let model = planning_dashboard.init()
  let model =
    planning_dashboard.update(
      model,
      planning_dashboard.AgUiRunError("timeout", "E001"),
    )
  model.cockpit_mode |> should.equal(planning_dashboard.Bright)
}

pub fn agui_text_content_adds_to_chat_test() {
  let model = planning_dashboard.init()
  let model =
    planning_dashboard.update(
      model,
      planning_dashboard.AgUiTextContent("msg-1", "Hello operator"),
    )
  { model.chat_messages != [] } |> should.be_true()
}

pub fn agui_tool_call_recorded_in_chat_test() {
  let model = planning_dashboard.init()
  let model =
    planning_dashboard.update(
      model,
      planning_dashboard.AgUiToolCallStart("tc-1", "search"),
    )
  { model.chat_messages != [] } |> should.be_true()
}

// ── HITL: Approval ───────────────────────────────────────────
pub fn hitl_approval_changes_cockpit_mode_test() {
  let model = planning_dashboard.init()
  let model =
    planning_dashboard.update(
      model,
      planning_dashboard.HitlApprovalRequested("req-1", "Delete all tasks"),
    )
  model.cockpit_mode |> should.equal(planning_dashboard.Normal)
}

pub fn hitl_approved_adds_to_chat_test() {
  let model = planning_dashboard.init()
  let model =
    planning_dashboard.update(
      model,
      planning_dashboard.HitlUserApproved("req-1"),
    )
  { model.chat_messages != [] } |> should.be_true()
}

// ── A2UI: Catalog Validation ─────────────────────────────────
pub fn a2ui_catalog_has_registered_components_test() {
  let cat = catalog.default_catalog()
  catalog.is_registered(cat, "badge") |> should.be_true()
  catalog.is_registered(cat, "alert") |> should.be_true()
  catalog.is_registered(cat, "unknown_widget") |> should.be_false()
}

pub fn a2ui_valid_proposal_passes_test() {
  let cat = catalog.default_catalog()
  let proposal =
    ComponentProposal(
      id: "b1",
      component_type: "badge",
      props: json.object([
        #("text", json.string("OK")),
        #("severity", json.string("healthy")),
      ]),
      children: [],
      binding: None,
    )
  case validator.validate_proposal(cat, proposal) {
    validator.Valid -> True |> should.be_true()
    validator.Invalid(_) -> should.fail()
  }
}

pub fn a2ui_unknown_component_rejected_test() {
  let cat = catalog.default_catalog()
  let proposal =
    ComponentProposal(
      id: "x1",
      component_type: "unknown_widget",
      props: json.object([]),
      children: [],
      binding: None,
    )
  case validator.validate_proposal(cat, proposal) {
    validator.Valid -> should.fail()
    validator.Invalid(reasons) -> { reasons != [] } |> should.be_true()
  }
}

// ── Zenoh: Topics ────────────────────────────────────────────
pub fn zenoh_planning_topics_defined_test() {
  let topics = zenoh_adapter.all_planning_topics()
  { list.length(topics) >= 4 } |> should.be_true()
}

pub fn zenoh_agui_topic_includes_agent_id_test() {
  let topic = zenoh_adapter.agui_events_topic("cortex")
  string.contains(topic, "cortex") |> should.be_true()
  string.starts_with(topic, "c3i/agui/events/") |> should.be_true()
}

// ── Tool Registry: HITL Queue ────────────────────────────────
pub fn tool_registry_hitl_queue_test() {
  let reg =
    tools.new_registry([
      tools.ToolDef(
        name: "guardian_approve",
        description: "Approval",
        parameters_schema: json.object([]),
        requires_approval: True,
      ),
    ])
  let reg = tools.start_call(reg, "tc-1", "guardian_approve")
  let reg = tools.end_args(reg, "tc-1")
  tools.pending_approvals(reg) |> should.equal(1)
  let reg = tools.approve_call(reg, "tc-1")
  tools.pending_approvals(reg) |> should.equal(0)
}

// ── Health Score: Composite ──────────────────────────────────
pub fn health_score_nominal_is_high_test() {
  let model = planning_dashboard.init()
  let model =
    planning_dashboard.update(
      model,
      planning_dashboard.ServicesUpdated([
        planning_dashboard.ServiceNode(name: "A", status: "online", health: 1.0),
      ]),
    )
  let model =
    planning_dashboard.update(model, planning_dashboard.QuorumChanged(True))
  let score = planning_dashboard.health_score(model)
  { score >. 0.5 } |> should.be_true()
}

pub fn health_score_degraded_triggers_mode_change_test() {
  let model = planning_dashboard.init()
  let model =
    planning_dashboard.update(model, planning_dashboard.ThreatLevelChanged(0.8))
  let mode = planning_dashboard.determine_cockpit_mode(model)
  // High threat should not be Dark mode
  case mode {
    planning_dashboard.Dark -> should.fail()
    _ -> True |> should.be_true()
  }
}
