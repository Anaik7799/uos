//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/planning/math_optimization</module>
////     <fsharp-lineage>Cepaf.Core.MathOptimization.fs</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L3_TRANSACTION</layer>
////     <mesh-domain>CPM Scheduling, Container DFA, Startup Optimization</mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>DAL-A / SIL-6 / CRITICAL</criticality>
////     <stamp-controls>SC-MATH-001 to SC-MATH-014</stamp-controls>
////     <aor-rules>AOR-MATH-001 to AOR-MATH-010</aor-rules>
////   </compliance>
////   <transformations>
////     <morphism type="isomorphic">
////       F# ContainerDef ≅ Gleam ContainerDef
////     </morphism>
////     <morphism type="isomorphic">
////       F# CpmResult ≅ Gleam CpmResult
////     </morphism>
////     <morphism type="injective" loss="fsharp-async">
////       F# `CriticalPathMethod.compute` ↪ Gleam `forward_pass` + `backward_pass`
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================

import cepaf_gleam/planning/graph_verification
import gleam/dict.{type Dict}
import gleam/int
import gleam/json
import gleam/list
import gleam/result

// =============================================================================
// Type Definitions
// =============================================================================

/// A container definition with its resource requirements and dependencies.
pub type ContainerDef {
  ContainerDef(
    name: String,
    dependencies: List(String),
    cpu_cores: Float,
    memory_mb: Int,
    startup_ms: Int,
  )
}

/// Container lifecycle states (deterministic finite automaton).
pub type ContainerState {
  NotCreated
  Created
  Starting
  Running
  Healthy
  Unhealthy
  Degraded
  Lameduck
  Draining
  Checkpointing
  Stopping
  Stopped
  Failed
  Removed
}

/// Critical Path Method result for a single container.
pub type CpmResult {
  CpmResult(
    early_start: Int,
    early_finish: Int,
    late_start: Int,
    late_finish: Int,
    slack: Int,
    critical: Bool,
  )
}

/// A wave of containers that can be started in parallel.
pub type ExecutionWave {
  ExecutionWave(wave_number: Int, containers: List(String))
}

// =============================================================================
// Container State DFA (SC-MATH-001, SC-MATH-002, SC-MATH-003)
// =============================================================================

/// Convert a ContainerState to its string representation.
pub fn state_to_string(state: ContainerState) -> String {
  case state {
    NotCreated -> "NotCreated"
    Created -> "Created"
    Starting -> "Starting"
    Running -> "Running"
    Healthy -> "Healthy"
    Unhealthy -> "Unhealthy"
    Degraded -> "Degraded"
    Lameduck -> "Lameduck"
    Draining -> "Draining"
    Checkpointing -> "Checkpointing"
    Stopping -> "Stopping"
    Stopped -> "Stopped"
    Failed -> "Failed"
    Removed -> "Removed"
  }
}

/// Return the list of valid target states from a given state (DFA transitions).
pub fn valid_transitions(state: ContainerState) -> List(ContainerState) {
  case state {
    NotCreated -> [Created]
    Created -> [Starting, Removed]
    Starting -> [Running, Failed]
    Running -> [Healthy, Unhealthy, Stopping, Failed]
    Healthy -> [Degraded, Unhealthy, Lameduck, Stopping, Failed]
    Unhealthy -> [Healthy, Degraded, Stopping, Failed]
    Degraded -> [Healthy, Unhealthy, Lameduck, Stopping, Failed]
    Lameduck -> [Draining, Stopping, Failed]
    Draining -> [Checkpointing, Stopping, Failed]
    Checkpointing -> [Stopping, Failed]
    Stopping -> [Stopped, Failed]
    Stopped -> [Starting, Removed]
    Failed -> [Starting, Removed]
    Removed -> []
  }
}

/// Check whether transitioning from one state to another is allowed.
pub fn can_transition(from: ContainerState, to: ContainerState) -> Bool {
  list.contains(valid_transitions(from), to)
}

// =============================================================================
// Dependency Graph Construction (SC-MATH-004)
// =============================================================================

/// Build a dependency DAG from container definitions using the graph_verification module.
pub fn build_dependency_dag(
  containers: List(ContainerDef),
) -> graph_verification.Graph {
  let graph =
    list.fold(containers, graph_verification.new_graph(), fn(g, c) {
      graph_verification.add_node(
        g,
        graph_verification.Node(
          id: c.name,
          label: c.name,
          node_type: "container",
        ),
      )
    })
  list.fold(containers, graph, fn(g, c) {
    list.fold(c.dependencies, g, fn(g2, dep) {
      graph_verification.add_edge(
        g2,
        graph_verification.Edge(
          from: dep,
          to: c.name,
          label: "depends_on",
          is_allowed: True,
        ),
      )
    })
  })
}

// =============================================================================
// Topological Ordering (SC-MATH-005)
// =============================================================================

/// Compute a topological ordering of containers via graph-based Kahn's algorithm.
/// Returns Error if the dependency graph contains cycles.
pub fn topological_order(
  containers: List(ContainerDef),
) -> Result(List(String), String) {
  let graph = build_dependency_dag(containers)
  graph_verification.topological_sort(graph)
}

// =============================================================================
// Execution Waves (SC-MATH-006)
// =============================================================================

/// Group containers into parallel execution waves based on dependency depth.
/// Wave 0 has no dependencies; wave N depends only on waves < N.
pub fn compute_waves(containers: List(ContainerDef)) -> List(ExecutionWave) {
  let dep_map =
    list.fold(containers, dict.new(), fn(d, c) {
      dict.insert(d, c.name, c.dependencies)
    })
  let all_names = list.map(containers, fn(c) { c.name })
  compute_waves_loop(dep_map, all_names, [], 0)
}

fn compute_waves_loop(
  dep_map: Dict(String, List(String)),
  remaining: List(String),
  assigned: List(String),
  wave_num: Int,
) -> List(ExecutionWave) {
  case list.is_empty(remaining) {
    True -> []
    False -> {
      // Find containers whose dependencies are all already assigned
      let ready =
        list.filter(remaining, fn(name) {
          let deps = dict.get(dep_map, name) |> result.unwrap([])
          list.all(deps, fn(d) { list.contains(assigned, d) })
        })
      case list.is_empty(ready) {
        // No progress means circular dependency; stop
        True -> []
        False -> {
          let wave = ExecutionWave(wave_number: wave_num, containers: ready)
          let new_assigned = list.append(assigned, ready)
          let new_remaining =
            list.filter(remaining, fn(n) { !list.contains(ready, n) })
          [
            wave,
            ..compute_waves_loop(
              dep_map,
              new_remaining,
              new_assigned,
              wave_num + 1,
            )
          ]
        }
      }
    }
  }
}

// =============================================================================
// Critical Path Method — Forward Pass (SC-MATH-007)
// =============================================================================

/// Compute early start and early finish times for each container.
/// ES = max(EF of all predecessors), EF = ES + duration.
pub fn forward_pass(containers: List(ContainerDef)) -> Dict(String, CpmResult) {
  let order = topological_order(containers) |> result.unwrap([])
  let duration_map =
    list.fold(containers, dict.new(), fn(d, c) {
      dict.insert(d, c.name, c.startup_ms)
    })
  let dep_map =
    list.fold(containers, dict.new(), fn(d, c) {
      dict.insert(d, c.name, c.dependencies)
    })
  let initial: Dict(String, CpmResult) = dict.new()
  list.fold(order, initial, fn(results, name) {
    let deps = dict.get(dep_map, name) |> result.unwrap([])
    let duration = dict.get(duration_map, name) |> result.unwrap(0)
    let es = compute_early_start(deps, results)
    let ef = es + duration
    let cpm =
      CpmResult(
        early_start: es,
        early_finish: ef,
        late_start: 0,
        late_finish: 0,
        slack: 0,
        critical: False,
      )
    dict.insert(results, name, cpm)
  })
}

fn compute_early_start(
  deps: List(String),
  results: Dict(String, CpmResult),
) -> Int {
  case list.is_empty(deps) {
    True -> 0
    False ->
      list.fold(deps, 0, fn(max_ef, dep_name) {
        case dict.get(results, dep_name) {
          Ok(r) -> int.max(max_ef, r.early_finish)
          Error(_) -> max_ef
        }
      })
  }
}

// =============================================================================
// Critical Path Method — Backward Pass (SC-MATH-008)
// =============================================================================

/// Compute late start and late finish times, then derive slack and criticality.
/// LF = min(LS of all successors), LS = LF - duration.
pub fn backward_pass(
  containers: List(ContainerDef),
  forward: Dict(String, CpmResult),
) -> Dict(String, CpmResult) {
  let order = topological_order(containers) |> result.unwrap([])
  let reversed = list.reverse(order)
  let duration_map =
    list.fold(containers, dict.new(), fn(d, c) {
      dict.insert(d, c.name, c.startup_ms)
    })
  // Build successor map: for each container, which containers depend on it?
  let successor_map =
    list.fold(containers, dict.new(), fn(d, c) {
      list.fold(c.dependencies, d, fn(d2, dep) {
        let existing = dict.get(d2, dep) |> result.unwrap([])
        dict.insert(d2, dep, [c.name, ..existing])
      })
    })
  // Project finish time = max early_finish across all containers
  let project_finish =
    dict.fold(forward, 0, fn(max_val, _name, cpm) {
      int.max(max_val, cpm.early_finish)
    })
  list.fold(reversed, forward, fn(results, name) {
    let duration = dict.get(duration_map, name) |> result.unwrap(0)
    let successors = dict.get(successor_map, name) |> result.unwrap([])
    let lf = case list.is_empty(successors) {
      True -> project_finish
      False ->
        list.fold(successors, project_finish, fn(min_ls, succ_name) {
          case dict.get(results, succ_name) {
            Ok(r) -> int.min(min_ls, r.late_start)
            Error(_) -> min_ls
          }
        })
    }
    let ls = lf - duration
    let es = case dict.get(forward, name) {
      Ok(r) -> r.early_start
      Error(_) -> 0
    }
    let ef = case dict.get(forward, name) {
      Ok(r) -> r.early_finish
      Error(_) -> 0
    }
    let slack = ls - es
    let cpm =
      CpmResult(
        early_start: es,
        early_finish: ef,
        late_start: ls,
        late_finish: lf,
        slack: slack,
        critical: slack == 0,
      )
    dict.insert(results, name, cpm)
  })
}

// =============================================================================
// Critical Path Extraction (SC-MATH-009)
// =============================================================================

/// Extract container names on the critical path (slack == 0).
pub fn critical_path(cpm_results: Dict(String, CpmResult)) -> List(String) {
  dict.to_list(cpm_results)
  |> list.filter_map(fn(pair) {
    let #(name, cpm) = pair
    case cpm.critical {
      True -> Ok(name)
      False -> Error(Nil)
    }
  })
}

// =============================================================================
// Total Startup Time (SC-MATH-010)
// =============================================================================

/// Calculate the total startup time as the maximum early_finish across all containers.
pub fn total_startup_time(cpm_results: Dict(String, CpmResult)) -> Int {
  dict.fold(cpm_results, 0, fn(max_val, _name, cpm) {
    int.max(max_val, cpm.early_finish)
  })
}

// =============================================================================
// Default C3I Container Definitions (SC-MATH-011)
// =============================================================================

/// The 7 core C3I containers with real dependency relationships.
pub fn default_containers() -> List(ContainerDef) {
  [
    ContainerDef(
      name: "indrajaal-db-prod",
      dependencies: [],
      cpu_cores: 1.0,
      memory_mb: 512,
      startup_ms: 3000,
    ),
    ContainerDef(
      name: "zenoh-router-1",
      dependencies: ["indrajaal-db-prod"],
      cpu_cores: 0.5,
      memory_mb: 256,
      startup_ms: 2000,
    ),
    ContainerDef(
      name: "zenoh-router-2",
      dependencies: ["indrajaal-db-prod"],
      cpu_cores: 0.5,
      memory_mb: 256,
      startup_ms: 2000,
    ),
    ContainerDef(
      name: "zenoh-router-3",
      dependencies: ["indrajaal-db-prod"],
      cpu_cores: 0.5,
      memory_mb: 256,
      startup_ms: 2000,
    ),
    ContainerDef(
      name: "cepaf-bridge",
      dependencies: ["zenoh-router-1"],
      cpu_cores: 0.5,
      memory_mb: 256,
      startup_ms: 1500,
    ),
    ContainerDef(
      name: "indrajaal-obs-prod",
      dependencies: ["indrajaal-db-prod", "zenoh-router-1"],
      cpu_cores: 0.5,
      memory_mb: 256,
      startup_ms: 1500,
    ),
    ContainerDef(
      name: "indrajaal-cortex",
      dependencies: ["indrajaal-db-prod", "zenoh-router-1", "cepaf-bridge"],
      cpu_cores: 1.0,
      memory_mb: 512,
      startup_ms: 2000,
    ),
    ContainerDef(
      name: "indrajaal-ex-app-1",
      dependencies: ["indrajaal-cortex"],
      cpu_cores: 0.5,
      memory_mb: 256,
      startup_ms: 1000,
    ),
  ]
}

// =============================================================================
// Full Optimization Pipeline (SC-MATH-012)
// =============================================================================

/// Run the full startup optimization: build DAG, compute CPM, return execution waves.
pub fn optimize_startup() -> List(ExecutionWave) {
  let containers = default_containers()
  compute_waves(containers)
}

// =============================================================================
// JSON Serialization (SC-GLM-UI-003)
// =============================================================================

/// Serialize CPM results to JSON.
pub fn cpm_to_json(results: Dict(String, CpmResult)) -> json.Json {
  json.object(
    dict.to_list(results)
    |> list.map(fn(pair) {
      let #(name, cpm) = pair
      #(
        name,
        json.object([
          #("early_start", json.int(cpm.early_start)),
          #("early_finish", json.int(cpm.early_finish)),
          #("late_start", json.int(cpm.late_start)),
          #("late_finish", json.int(cpm.late_finish)),
          #("slack", json.int(cpm.slack)),
          #("critical", json.bool(cpm.critical)),
        ]),
      )
    }),
  )
}

/// Serialize execution waves to JSON.
pub fn waves_to_json(waves: List(ExecutionWave)) -> json.Json {
  json.array(waves, fn(wave) {
    json.object([
      #("wave_number", json.int(wave.wave_number)),
      #("containers", json.array(wave.containers, json.string)),
    ])
  })
}
