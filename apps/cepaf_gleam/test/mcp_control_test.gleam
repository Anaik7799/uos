import cepaf_gleam/mcp/adapters/control
import cepaf_gleam/mcp/admission.{type ValidatedCall, ValidatedCall}
import cepaf_gleam/mcp/principal
import cepaf_gleam/mcp/registry
import cepaf_gleam/mcp/types.{
  type Outcome, ClientProfile, Complete, NonRetryable, Refused, ToolError,
}
import gleam/dict
import gleam/option.{type Option, None, Some}
import gleam/string
import gleeunit/should

fn call(
  tool: String,
  actor: String,
  args: List(#(String, String)),
  attempt: Option(Int),
) -> ValidatedCall {
  let assert Ok(spec) = registry.lookup("public", tool)
  ValidatedCall(
    spec: spec,
    principal: principal.from_launcher_env(
      actor: actor,
      client: ClientProfile("test"),
      workspace_root: "tenant-a",
      session_id: "test",
    ),
    arguments: dict.from_list(args),
    plan_id: None,
    task_id: None,
    attempt: attempt,
    grant_id: None,
  )
}

fn observed(
  id: String,
  owner: String,
  attempt: Int,
  constraints: Bool,
) -> control.ControllerEntry {
  control.ObservedInstance(
    controller_id: id,
    layer: 0,
    runtime_healthy: True,
    constraints_satisfied: constraints,
    owner_worker: owner,
    attempt: attempt,
    current_stage: "running",
    previous_stage: None,
  )
}

fn healthy() -> control.ControlBackend {
  control.ControlBackend(
    candidate: "uos-mcp",
    stpa_hazards_open: 0,
    interlock_armed: True,
    controllers: dict.from_list([#("c1", observed("c1", "owner-a", 1, True))]),
  )
}

fn refused_code(outcome: Outcome, expected: String) {
  let assert Refused(ToolError(actual, _, NonRetryable)) = outcome
  actual |> should.equal(expected)
}

fn step_args() -> List(#(String, String)) {
  [
    #("mode", "execute"),
    #("action", "pause"),
    #("controller", "c1"),
  ]
}

pub fn registry_declaration_is_not_runtime_health_test() {
  let backend =
    control.ControlBackend(
      candidate: "uos-mcp",
      stpa_hazards_open: 0,
      interlock_armed: True,
      controllers: dict.from_list([
        #("c1", control.DeclaredOnly(controller_id: "c1", layer: 0)),
        #("c2", observed("c2", "owner-b", 3, True)),
      ]),
    )
  let #(outcome, after) =
    control.execute(backend, call("registry_status", "owner-a", [], None))
  let assert Complete(payload, _) = outcome
  string.contains(payload, "\"declared_count\":2") |> should.be_true
  string.contains(payload, "\"observed_running_count\":1") |> should.be_true
  string.contains(payload, "\"runtime_state\":\"unobserved\"")
  |> should.be_true
  string.contains(payload, "\"runtime_healthy\":false") |> should.be_true
  string.contains(payload, "\"runtime_state\":\"observed\"")
  |> should.be_true
  after |> should.equal(backend)
}

pub fn control_preview_has_no_effect_test() {
  let backend = healthy()
  let #(outcome, after) =
    control.execute(
      backend,
      call(
        "control_loop",
        "owner-a",
        [
          #("mode", "preview"),
          #("action", "pause"),
          #("controller", "c1"),
        ],
        Some(1),
      ),
    )
  let assert Complete(payload, _) = outcome
  string.contains(payload, "\"mode\":\"preview\"") |> should.be_true
  string.contains(payload, "\"mutated\":false") |> should.be_true
  after |> should.equal(backend)
}

pub fn execute_rechecks_constraints_and_attempt_test() {
  let declared =
    control.ControlBackend(
      ..healthy(),
      controllers: dict.from_list([
        #("c1", control.DeclaredOnly(controller_id: "c1", layer: 0)),
      ]),
    )
  let #(outcome_declared, after_declared) =
    control.execute(
      declared,
      call("control_loop", "owner-a", step_args(), Some(1)),
    )
  refused_code(outcome_declared, "CONTROLLER_NOT_RUNNING")
  after_declared |> should.equal(declared)

  let disarmed = control.ControlBackend(..healthy(), interlock_armed: False)
  let #(outcome_disarmed, after_disarmed) =
    control.execute(
      disarmed,
      call("control_loop", "owner-a", step_args(), Some(1)),
    )
  refused_code(outcome_disarmed, "SAFETY_CONSTRAINT_VIOLATION")
  after_disarmed |> should.equal(disarmed)

  let hazard = control.ControlBackend(..healthy(), stpa_hazards_open: 1)
  let #(outcome_hazard, _) =
    control.execute(
      hazard,
      call("control_loop", "owner-a", step_args(), Some(1)),
    )
  refused_code(outcome_hazard, "SAFETY_CONSTRAINT_VIOLATION")

  let constrained =
    control.ControlBackend(
      ..healthy(),
      controllers: dict.from_list([
        #("c1", observed("c1", "owner-a", 1, False)),
      ]),
    )
  let #(outcome_constrained, _) =
    control.execute(
      constrained,
      call("control_loop", "owner-a", step_args(), Some(1)),
    )
  refused_code(outcome_constrained, "SAFETY_CONSTRAINT_VIOLATION")

  let backend = healthy()
  let #(outcome_actor, after_actor) =
    control.execute(
      backend,
      call("control_loop", "intruder", step_args(), Some(1)),
    )
  refused_code(outcome_actor, "CONTROL_PRINCIPAL_MISMATCH")
  after_actor |> should.equal(backend)

  let #(outcome_attempt, after_attempt) =
    control.execute(
      backend,
      call("control_loop", "owner-a", step_args(), Some(2)),
    )
  refused_code(outcome_attempt, "CONTROL_STALE_ATTEMPT")
  after_attempt |> should.equal(backend)

  let #(outcome_ok, after_ok) =
    control.execute(
      backend,
      call("control_loop", "owner-a", step_args(), Some(1)),
    )
  let assert Complete(payload, _) = outcome_ok
  string.contains(payload, "\"mode\":\"execute\"") |> should.be_true
  string.contains(payload, "\"mutated\":true") |> should.be_true
  let assert Ok(control.ObservedInstance(_, _, _, _, _, _, stage, _)) =
    dict.get(after_ok.controllers, "c1")
  stage |> should.equal("pause")
}

pub fn reversible_control_step_and_revert_test() {
  let backend = healthy()
  let #(outcome_step, after_step) =
    control.execute(
      backend,
      call("control_loop", "owner-a", step_args(), Some(1)),
    )
  let assert Complete(_, _) = outcome_step
  let assert Ok(control.ObservedInstance(_, _, _, _, _, _, stage, previous)) =
    dict.get(after_step.controllers, "c1")
  stage |> should.equal("pause")
  previous |> should.equal(Some("running"))

  let #(outcome_revert, after_revert) =
    control.execute(
      after_step,
      call(
        "control_loop",
        "owner-a",
        [
          #("mode", "revert"),
          #("action", "last"),
          #("controller", "c1"),
        ],
        Some(1),
      ),
    )
  let assert Complete(_, _) = outcome_revert
  let assert Ok(control.ObservedInstance(
    _,
    _,
    _,
    _,
    _,
    _,
    final_stage,
    final_previous,
  )) = dict.get(after_revert.controllers, "c1")
  final_stage |> should.equal("running")
  final_previous |> should.equal(None)
}

// M2.1 (C1): replaying the same execute must not clobber `previous_stage`, so a
// subsequent revert still restores the original stage.
pub fn repeated_execute_is_idempotent_test() {
  let backend = healthy()
  let #(outcome_first, after_first) =
    control.execute(
      backend,
      call("control_loop", "owner-a", step_args(), Some(1)),
    )
  let assert Complete(_, _) = outcome_first

  let #(outcome_second, after_second) =
    control.execute(
      after_first,
      call("control_loop", "owner-a", step_args(), Some(1)),
    )
  let assert Complete(payload, _) = outcome_second
  string.contains(payload, "\"mutated\":false") |> should.be_true

  let assert Ok(control.ObservedInstance(
    _,
    _,
    _,
    _,
    _,
    _,
    second_stage,
    previous,
  )) = dict.get(after_second.controllers, "c1")
  second_stage |> should.equal("pause")
  previous |> should.equal(Some("running"))

  let #(outcome_revert, after_revert) =
    control.execute(
      after_second,
      call(
        "control_loop",
        "owner-a",
        [
          #("mode", "revert"),
          #("action", "last"),
          #("controller", "c1"),
        ],
        Some(1),
      ),
    )
  let assert Complete(_, _) = outcome_revert
  let assert Ok(control.ObservedInstance(_, _, _, _, _, _, final_stage, _)) =
    dict.get(after_revert.controllers, "c1")
  final_stage |> should.equal("running")
}

// M2.2 (C2): an unhealthy target instance is refused at actuation time.
pub fn unhealthy_observed_controller_refuses_actuation_test() {
  let unhealthy_target =
    control.ControlBackend(
      ..healthy(),
      controllers: dict.from_list([
        #(
          "c1",
          control.ObservedInstance(
            controller_id: "c1",
            layer: 0,
            runtime_healthy: False,
            constraints_satisfied: True,
            owner_worker: "owner-a",
            attempt: 1,
            current_stage: "running",
            previous_stage: None,
          ),
        ),
      ]),
    )
  let #(outcome_target, after_target) =
    control.execute(
      unhealthy_target,
      call("control_loop", "owner-a", step_args(), Some(1)),
    )
  refused_code(outcome_target, "SAFETY_CONSTRAINT_VIOLATION")
  after_target |> should.equal(unhealthy_target)

  // A healthy target must still be refused when any other observed controller
  // in the backend is unhealthy.
  let unhealthy_sibling =
    control.ControlBackend(
      ..healthy(),
      controllers: dict.from_list([
        #("c1", observed("c1", "owner-a", 1, True)),
        #(
          "c2",
          control.ObservedInstance(
            controller_id: "c2",
            layer: 0,
            runtime_healthy: False,
            constraints_satisfied: True,
            owner_worker: "owner-b",
            attempt: 7,
            current_stage: "running",
            previous_stage: None,
          ),
        ),
      ]),
    )
  let #(outcome_sibling, after_sibling) =
    control.execute(
      unhealthy_sibling,
      call("control_loop", "owner-a", step_args(), Some(1)),
    )
  refused_code(outcome_sibling, "SAFETY_CONSTRAINT_VIOLATION")
  after_sibling |> should.equal(unhealthy_sibling)
}

// M2.3 (M1): no observed controllers must not be reported as healthy.
pub fn empty_health_reports_unobserved_test() {
  let backend =
    control.ControlBackend(
      candidate: "uos-mcp",
      stpa_hazards_open: 0,
      interlock_armed: True,
      controllers: dict.new(),
    )
  let #(outcome, _) =
    control.execute(backend, call("safety_status", "owner-a", [], None))
  let assert Complete(payload, _) = outcome
  string.contains(payload, "\"observed_count\":0") |> should.be_true
  string.contains(payload, "\"safety_verdict\":\"unobserved\"")
  |> should.be_true
  string.contains(payload, "\"safety_verdict\":\"healthy\"")
  |> should.be_false
}

// M2.4: arbitrary actions are rejected fail-closed.
pub fn disallowed_action_is_refused_test() {
  let backend = healthy()
  let #(outcome, after) =
    control.execute(
      backend,
      call(
        "control_loop",
        "owner-a",
        [
          #("mode", "execute"),
          #("action", "rm-rf"),
          #("controller", "c1"),
        ],
        Some(1),
      ),
    )
  refused_code(outcome, "DISALLOWED_CONTROL_INTENT")
  after |> should.equal(backend)
}
