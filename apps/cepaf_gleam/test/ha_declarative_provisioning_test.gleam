/// Declarative Provisioning Engine tests
/// Layer: L4_SYSTEM
/// STAMP: SC-HA-001, SC-FUNC-001, SC-MUDA-001
///
/// Covers:
///   DesiredState construction and container addition
///   ContainerSpec validation (happy path + error cases)
///   Reconciliation diff: create / no-change / delete actions
///   Dependency ordering (topological sort)
///   Plan utilities: action_count, summary
import cepaf_gleam/ha/declarative_provisioning.{
  type ContainerSpec, type HealthCheckSpec, type ResourceSpec, ContainerSpec,
  HealthCheckSpec, ReconciliationPlan, ResourceSpec, action_count, add_container,
  dependency_order, desired_state_new, reconcile, summary, validate_spec,
}
import gleam/list
import gleam/string
import gleeunit/should

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn default_resources() -> ResourceSpec {
  ResourceSpec(cpu_limit: 0.5, memory_limit_mb: 512)
}

fn default_health() -> HealthCheckSpec {
  HealthCheckSpec(
    endpoint: "/health",
    interval_ms: 10_000,
    timeout_ms: 2000,
    retries: 3,
  )
}

fn make_spec(name: String, deps: List(String)) -> ContainerSpec {
  ContainerSpec(
    name: name,
    image: "image/" <> name <> ":latest",
    replicas: 1,
    resources: default_resources(),
    health_check: default_health(),
    dependencies: deps,
  )
}

// ---------------------------------------------------------------------------
// DesiredState construction
// ---------------------------------------------------------------------------

pub fn desired_state_new_is_empty_test() {
  let state = desired_state_new()
  list.length(state.containers) |> should.equal(0)
}

pub fn add_container_increases_count_test() {
  let state =
    desired_state_new()
    |> add_container(make_spec("zenoh", []))
  list.length(state.containers) |> should.equal(1)
}

pub fn add_two_containers_test() {
  let state =
    desired_state_new()
    |> add_container(make_spec("zenoh", []))
    |> add_container(make_spec("db", ["zenoh"]))
  list.length(state.containers) |> should.equal(2)
}

// ---------------------------------------------------------------------------
// Validation
// ---------------------------------------------------------------------------

pub fn validate_spec_ok_test() {
  validate_spec(make_spec("app", []))
  |> should.be_ok()
}

pub fn validate_spec_empty_name_test() {
  validate_spec(make_spec("", []))
  |> should.be_error()
}

pub fn validate_spec_zero_cpu_test() {
  let spec =
    ContainerSpec(
      ..make_spec("app", []),
      resources: ResourceSpec(cpu_limit: 0.0, memory_limit_mb: 512),
    )
  validate_spec(spec) |> should.be_error()
}

pub fn validate_spec_negative_cpu_test() {
  let spec =
    ContainerSpec(
      ..make_spec("app", []),
      resources: ResourceSpec(cpu_limit: -1.0, memory_limit_mb: 512),
    )
  validate_spec(spec) |> should.be_error()
}

pub fn validate_spec_zero_memory_test() {
  let spec =
    ContainerSpec(
      ..make_spec("app", []),
      resources: ResourceSpec(cpu_limit: 0.5, memory_limit_mb: 0),
    )
  validate_spec(spec) |> should.be_error()
}

pub fn validate_spec_zero_replicas_test() {
  let spec = ContainerSpec(..make_spec("app", []), replicas: 0)
  validate_spec(spec) |> should.be_error()
}

// ---------------------------------------------------------------------------
// Reconciliation
// ---------------------------------------------------------------------------

pub fn reconcile_create_when_not_running_test() {
  let desired =
    desired_state_new()
    |> add_container(make_spec("zenoh", []))
  let plan = reconcile(desired, [])
  action_count(plan) |> should.equal(1)
}

pub fn reconcile_no_change_when_running_test() {
  let desired =
    desired_state_new()
    |> add_container(make_spec("zenoh", []))
  let plan = reconcile(desired, ["zenoh"])
  // Should produce NoChange, not Create
  let has_create =
    list.any(plan.actions, fn(a) {
      case a {
        declarative_provisioning.Create(_) -> True
        _ -> False
      }
    })
  has_create |> should.be_false()
}

pub fn reconcile_delete_when_not_desired_test() {
  let desired = desired_state_new()
  let plan = reconcile(desired, ["stale-container"])
  let has_delete =
    list.any(plan.actions, fn(a) {
      case a {
        declarative_provisioning.Delete(_) -> True
        _ -> False
      }
    })
  has_delete |> should.be_true()
}

pub fn reconcile_mixed_actions_test() {
  let desired =
    desired_state_new()
    |> add_container(make_spec("new-svc", []))
    |> add_container(make_spec("existing-svc", []))
  let plan = reconcile(desired, ["existing-svc", "old-svc"])
  // new-svc -> Create, existing-svc -> NoChange, old-svc -> Delete
  action_count(plan) |> should.equal(3)
}

// ---------------------------------------------------------------------------
// Dependency ordering
// ---------------------------------------------------------------------------

pub fn dependency_order_no_deps_test() {
  let specs = [make_spec("a", []), make_spec("b", []), make_spec("c", [])]
  let order = dependency_order(specs)
  list.length(order) |> should.equal(3)
}

pub fn dependency_order_linear_chain_test() {
  // a -> b -> c means a starts first
  let specs = [
    make_spec("c", ["b"]),
    make_spec("b", ["a"]),
    make_spec("a", []),
  ]
  let order = dependency_order(specs)
  let a_pos = find_pos(order, "a")
  let b_pos = find_pos(order, "b")
  let c_pos = find_pos(order, "c")
  // a must come before b, b must come before c
  { a_pos < b_pos } |> should.be_true()
  { b_pos < c_pos } |> should.be_true()
}

fn find_pos(lst: List(String), name: String) -> Int {
  list.index_fold(lst, -1, fn(acc, item, idx) {
    case item == name {
      True -> idx
      False -> acc
    }
  })
}

// ---------------------------------------------------------------------------
// Plan utilities
// ---------------------------------------------------------------------------

pub fn action_count_empty_plan_test() {
  let plan = ReconciliationPlan(actions: [], dependency_order: [])
  action_count(plan) |> should.equal(0)
}

pub fn summary_contains_create_test() {
  let desired =
    desired_state_new()
    |> add_container(make_spec("svc", []))
  let plan = reconcile(desired, [])
  let s = summary(plan)
  string.contains(s, "create=1") |> should.be_true()
}
