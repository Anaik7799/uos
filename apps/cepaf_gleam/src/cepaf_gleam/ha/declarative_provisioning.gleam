//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ha/declarative_provisioning</module>
////     <fsharp-lineage>None — novel Gleam module for declarative container provisioning</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L4_SYSTEM</layer>
////     <mesh-domain>
////       Declarative Provisioning Engine — desired-state reconciliation for the
////       16-container SIL-6 mesh. Computes a typed ReconciliationPlan by diffing
////       a DesiredState against the set of currently-running container names, then
////       emits Create / Update / Delete / NoChange actions ordered by dependency.
////       All logic is pure; callers own I/O and Zenoh publishing.
////     </mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>HIGH</criticality>
////     <stamp-controls>SC-HA-001, SC-FUNC-001, SC-MUDA-001, SC-TRUTH-001</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective">
////       Kubernetes Deployment / Podman Quadlet desired-state ↪ Gleam DesiredState ADT.
////       Topological sort of dependency graph ↪ Gleam List(String) ordering.
////       All arithmetic is pure; no panics; no I/O side-effects.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// Declarative Provisioning Engine — इच्छित स्थिति (Desired State)
//// "In whatever form a devotee seeks to worship Me, I sustain their faith." (Gita 7.21)
////
//// Design invariants:
////   I1: reconcile(desired, actual) never produces duplicate actions for the same name.
////   I2: dependency_order(specs) produces a stable topological ordering.
////   I3: validate_spec returns Error for any spec with empty name, cpu <= 0, or memory <= 0.
////   I4: action_count(plan) == list.length(plan.actions).
////
//// STAMP: SC-HA-001, SC-FUNC-001, SC-MUDA-001, SC-TRUTH-001

import gleam/float
import gleam/int
import gleam/list
import gleam/string

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

/// Resource limits for a container.
pub type ResourceSpec {
  ResourceSpec(
    /// Maximum CPU share as a fraction (e.g. 0.5 = 50% of one core).
    cpu_limit: Float,
    /// Maximum resident memory in megabytes.
    memory_limit_mb: Int,
  )
}

/// Liveness / readiness probe specification.
pub type HealthCheckSpec {
  HealthCheckSpec(
    /// HTTP or TCP endpoint to probe, e.g. "/health" or "tcp://7447".
    endpoint: String,
    /// Probe frequency in milliseconds.
    interval_ms: Int,
    /// Per-probe timeout in milliseconds.
    timeout_ms: Int,
    /// Number of consecutive failures before the container is considered unhealthy.
    retries: Int,
  )
}

/// Full specification for a single container.
pub type ContainerSpec {
  ContainerSpec(
    /// Unique container name within the mesh.
    name: String,
    /// OCI image reference, e.g. "eclipse/zenoh:1.0.0".
    image: String,
    /// Desired replica count (>= 1).
    replicas: Int,
    /// CPU and memory limits.
    resources: ResourceSpec,
    /// Health probe configuration.
    health_check: HealthCheckSpec,
    /// Names of containers that must be running before this one starts.
    dependencies: List(String),
  )
}

/// The full desired state of the mesh — a collection of container specs.
pub type DesiredState {
  DesiredState(containers: List(ContainerSpec))
}

/// A single reconciliation action produced by comparing desired vs actual state.
pub type ReconciliationAction {
  /// Container is in desired state but not running — must be created.
  Create(spec: ContainerSpec)
  /// Container is running but spec has changed — must be updated.
  Update(name: String, spec: ContainerSpec)
  /// Container is running but is not in desired state — must be deleted.
  Delete(name: String)
  /// Container matches desired state — no action required.
  NoChange(name: String)
}

/// A complete reconciliation plan: ordered actions + stable boot order.
pub type ReconciliationPlan {
  ReconciliationPlan(
    /// Actions to apply in order.
    actions: List(ReconciliationAction),
    /// Container names in dependency-resolved start order.
    dependency_order: List(String),
  )
}

// ---------------------------------------------------------------------------
// Construction
// ---------------------------------------------------------------------------

/// Returns a fresh empty desired state.
pub fn desired_state_new() -> DesiredState {
  DesiredState(containers: [])
}

/// Appends a container spec to the desired state.
pub fn add_container(state: DesiredState, spec: ContainerSpec) -> DesiredState {
  DesiredState(containers: list.append(state.containers, [spec]))
}

// ---------------------------------------------------------------------------
// Validation
// ---------------------------------------------------------------------------

/// Validates a ContainerSpec for basic correctness.
///
/// Returns Ok(spec) when all invariants hold, or Error(reason) otherwise.
pub fn validate_spec(spec: ContainerSpec) -> Result(ContainerSpec, String) {
  case string.is_empty(spec.name) {
    True -> Error("container name must not be empty")
    False ->
      case spec.resources.cpu_limit <=. 0.0 {
        True ->
          Error(
            "cpu_limit must be > 0.0, got "
            <> float.to_string(spec.resources.cpu_limit),
          )
        False ->
          case spec.resources.memory_limit_mb <= 0 {
            True ->
              Error(
                "memory_limit_mb must be > 0, got "
                <> int.to_string(spec.resources.memory_limit_mb),
              )
            False ->
              case spec.replicas <= 0 {
                True ->
                  Error(
                    "replicas must be > 0, got " <> int.to_string(spec.replicas),
                  )
                False -> Ok(spec)
              }
          }
      }
  }
}

// ---------------------------------------------------------------------------
// Reconciliation
// ---------------------------------------------------------------------------

/// Produces a ReconciliationPlan by diffing desired state against actual names.
///
/// Containers in desired but not in actual -> Create.
/// Containers in both desired and actual     -> NoChange (no spec diff available here).
/// Containers in actual but not in desired   -> Delete.
pub fn reconcile(
  desired: DesiredState,
  actual_names: List(String),
) -> ReconciliationPlan {
  let desired_names = list.map(desired.containers, fn(s) { s.name })

  // Create: desired but missing from actual
  let creates =
    list.filter_map(desired.containers, fn(spec) {
      case list.contains(actual_names, spec.name) {
        True -> Error(Nil)
        False -> Ok(Create(spec))
      }
    })

  // NoChange: present in both
  let no_changes =
    list.filter_map(desired.containers, fn(spec) {
      case list.contains(actual_names, spec.name) {
        True -> Ok(NoChange(spec.name))
        False -> Error(Nil)
      }
    })

  // Delete: actual but not in desired
  let deletes =
    list.filter_map(actual_names, fn(name) {
      case list.contains(desired_names, name) {
        True -> Error(Nil)
        False -> Ok(Delete(name))
      }
    })

  let actions = list.flatten([creates, no_changes, deletes])
  let dep_order = dependency_order(desired.containers)
  ReconciliationPlan(actions: actions, dependency_order: dep_order)
}

// ---------------------------------------------------------------------------
// Dependency ordering (topological sort — Kahn's algorithm)
// ---------------------------------------------------------------------------

/// Returns container names in dependency-resolved start order.
///
/// Containers with no dependencies come first. Cycles are broken by
/// appending remaining nodes at the end (safe degradation).
pub fn dependency_order(specs: List(ContainerSpec)) -> List(String) {
  let names = list.map(specs, fn(s) { s.name })
  kahn_sort(names, specs, [])
}

/// Iterative Kahn's topological sort.
fn kahn_sort(
  remaining: List(String),
  specs: List(ContainerSpec),
  acc: List(String),
) -> List(String) {
  case remaining {
    [] -> acc
    _ -> {
      let ready =
        list.filter(remaining, fn(name) {
          let deps = deps_of(name, specs)
          list.all(deps, fn(d) { list.contains(acc, d) })
        })
      case ready {
        [] -> list.append(acc, remaining)
        _ -> {
          let next_acc = list.append(acc, ready)
          let next_remaining =
            list.filter(remaining, fn(n) {
              case list.contains(ready, n) {
                True -> False
                False -> True
              }
            })
          kahn_sort(next_remaining, specs, next_acc)
        }
      }
    }
  }
}

/// Returns the dependency list for a given container name.
fn deps_of(name: String, specs: List(ContainerSpec)) -> List(String) {
  case list.find(specs, fn(s) { s.name == name }) {
    Ok(spec) -> spec.dependencies
    Error(_) -> []
  }
}

// ---------------------------------------------------------------------------
// Plan utilities
// ---------------------------------------------------------------------------

/// Returns the total number of actions in the plan.
pub fn action_count(plan: ReconciliationPlan) -> Int {
  list.length(plan.actions)
}

/// Returns a human-readable summary of the reconciliation plan.
pub fn summary(plan: ReconciliationPlan) -> String {
  let creates =
    list.filter(plan.actions, fn(a) {
      case a {
        Create(_) -> True
        _ -> False
      }
    })
    |> list.length()

  let updates =
    list.filter(plan.actions, fn(a) {
      case a {
        Update(_, _) -> True
        _ -> False
      }
    })
    |> list.length()

  let deletes =
    list.filter(plan.actions, fn(a) {
      case a {
        Delete(_) -> True
        _ -> False
      }
    })
    |> list.length()

  let no_changes =
    list.filter(plan.actions, fn(a) {
      case a {
        NoChange(_) -> True
        _ -> False
      }
    })
    |> list.length()

  "ReconciliationPlan{"
  <> "create="
  <> int.to_string(creates)
  <> ",update="
  <> int.to_string(updates)
  <> ",delete="
  <> int.to_string(deletes)
  <> ",no_change="
  <> int.to_string(no_changes)
  <> ",dep_order=["
  <> string.join(plan.dependency_order, ",")
  <> "]}"
}
