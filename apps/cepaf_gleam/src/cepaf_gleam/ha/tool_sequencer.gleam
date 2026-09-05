//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ha/tool_sequencer</module>
////     <fsharp-lineage>None — novel Gleam module for dependency-ordered tool execution</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L3_TRANSACTION</layer>
////     <mesh-domain>
////       Tool Sequencer — orders MCP tool steps by dependency and groups them
////       into parallel execution waves using a topological sort. Tracks step
////       results (Pending / Running / Completed / Failed) and provides guards
////       that prevent a step from executing until all of its dependencies have
////       completed successfully.
////     </mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>HIGH</criticality>
////     <stamp-controls>SC-HA-001, SC-FUNC-001, SC-MUDA-001</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective">
////       Temporal / Oban workflow DAG ↪ Gleam ToolSequence ADT.
////       Parallel wave grouping ↪ List(List(String)) (waves of concurrent steps).
////       All computations are pure; callers own scheduling and I/O.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// Tool Sequencer — उपकरण अनुक्रमक (क्रमबद्ध कर्म — Ordered Action)
//// "The actions of a wise person are bound together like beads on a thread." (Gita 3.25)
////
//// Design invariants:
////   I1: execution_order produces waves where each step's deps are in earlier waves.
////   I2: can_proceed = True only when all deps have status Completed(_).
////   I3: all_completed = True iff every step has status Completed(_) or Failed(_).
////   I4: all_passed = True iff every step has status Completed(_).
////   I5: validate_dependencies returns Error if any dep name is not a known step.
////
//// STAMP: SC-HA-001, SC-FUNC-001, SC-MUDA-001

import gleam/int
import gleam/list
import gleam/string

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

/// A single step in a tool execution sequence.
pub type ToolStep {
  ToolStep(
    /// Unique name for this step within the sequence.
    tool_name: String,
    /// Arguments to pass to the tool.
    args: List(String),
    /// Per-step execution timeout in milliseconds.
    timeout_ms: Int,
    /// Names of steps that must complete before this step can run.
    depends_on: List(String),
  )
}

/// Lifecycle status of a single step.
pub type StepStatus {
  /// Not yet started.
  Pending
  /// Currently executing.
  Running
  /// Finished successfully; payload contains the tool output.
  Completed(output: String)
  /// Finished with an error; payload contains the error message.
  Failed(error: String)
}

/// The recorded outcome of a single step after execution.
pub type StepResult {
  StepResult(
    /// Name of the step this result belongs to.
    step_name: String,
    /// Final status of the step.
    status: StepStatus,
    /// Wall-clock duration of the step in milliseconds.
    duration_ms: Int,
  )
}

/// A complete tool execution sequence: steps definition + accumulated results.
pub type ToolSequence {
  ToolSequence(
    /// Ordered list of step definitions.
    steps: List(ToolStep),
    /// Results recorded so far (one per completed or failed step).
    results: List(StepResult),
  )
}

// ---------------------------------------------------------------------------
// Construction
// ---------------------------------------------------------------------------

/// Wraps a list of ToolSteps into a new sequence with no results yet.
pub fn sequence_new(steps: List(ToolStep)) -> ToolSequence {
  ToolSequence(steps: steps, results: [])
}

// ---------------------------------------------------------------------------
// Validation
// ---------------------------------------------------------------------------

/// Validates that all dependency names refer to known steps in the sequence.
///
/// Returns Error with a descriptive message if any dependency is unresolvable.
/// Does not detect cycles (cycles produce an empty execution_order, not an error).
pub fn validate_dependencies(
  sequence: ToolSequence,
) -> Result(ToolSequence, String) {
  let known = list.map(sequence.steps, fn(s) { s.tool_name })
  let bad =
    list.flat_map(sequence.steps, fn(step) {
      list.filter(step.depends_on, fn(dep) { !list.contains(known, dep) })
    })
  case bad {
    [] -> Ok(sequence)
    _ -> Error("unknown dependencies: [" <> string.join(bad, ", ") <> "]")
  }
}

// ---------------------------------------------------------------------------
// Execution order
// ---------------------------------------------------------------------------

/// Groups steps into parallel execution waves using Kahn's algorithm.
///
/// Each inner list is a wave of steps that can run concurrently.
/// Steps whose dependencies are all satisfied by prior waves appear together.
/// Unresolvable dependencies (cycles) are appended as a final wave.
pub fn execution_order(sequence: ToolSequence) -> List(List(String)) {
  let names = list.map(sequence.steps, fn(s) { s.tool_name })
  build_waves(names, sequence.steps, [])
}

fn build_waves(
  remaining: List(String),
  steps: List(ToolStep),
  resolved: List(String),
) -> List(List(String)) {
  case remaining {
    [] -> []
    _ -> {
      let wave =
        list.filter(remaining, fn(name) {
          let deps = step_deps(name, steps)
          list.all(deps, fn(d) { list.contains(resolved, d) })
        })
      case wave {
        [] ->
          // Cycle detected — emit remaining as final wave
          [remaining]
        _ -> {
          let next_resolved = list.append(resolved, wave)
          let next_remaining =
            list.filter(remaining, fn(n) { !list.contains(wave, n) })
          [wave, ..build_waves(next_remaining, steps, next_resolved)]
        }
      }
    }
  }
}

fn step_deps(name: String, steps: List(ToolStep)) -> List(String) {
  case list.find(steps, fn(s) { s.tool_name == name }) {
    Ok(step) -> step.depends_on
    Error(_) -> []
  }
}

// ---------------------------------------------------------------------------
// Result recording
// ---------------------------------------------------------------------------

/// Records the result of a completed or failed step.
///
/// If a result already exists for the step name it is replaced.
pub fn record_result(
  sequence: ToolSequence,
  step_name: String,
  status: StepStatus,
  duration_ms: Int,
) -> ToolSequence {
  let new_result =
    StepResult(step_name: step_name, status: status, duration_ms: duration_ms)
  let filtered =
    list.filter(sequence.results, fn(r) { r.step_name != step_name })
  ToolSequence(..sequence, results: list.append(filtered, [new_result]))
}

// ---------------------------------------------------------------------------
// Guards
// ---------------------------------------------------------------------------

/// Returns True when all dependencies of the named step have Completed status.
pub fn can_proceed(sequence: ToolSequence, step_name: String) -> Bool {
  let deps = step_deps(step_name, sequence.steps)
  list.all(deps, fn(dep) {
    case list.find(sequence.results, fn(r) { r.step_name == dep }) {
      Ok(result) ->
        case result.status {
          Completed(_) -> True
          _ -> False
        }
      Error(_) -> False
    }
  })
}

/// Returns True when every step has a result with status Completed or Failed.
pub fn all_completed(sequence: ToolSequence) -> Bool {
  let step_names = list.map(sequence.steps, fn(s) { s.tool_name })
  list.all(step_names, fn(name) {
    case list.find(sequence.results, fn(r) { r.step_name == name }) {
      Ok(result) ->
        case result.status {
          Completed(_) -> True
          Failed(_) -> True
          _ -> False
        }
      Error(_) -> False
    }
  })
}

/// Returns True when every step has a result with status Completed (no failures).
pub fn all_passed(sequence: ToolSequence) -> Bool {
  let step_names = list.map(sequence.steps, fn(s) { s.tool_name })
  list.all(step_names, fn(name) {
    case list.find(sequence.results, fn(r) { r.step_name == name }) {
      Ok(result) ->
        case result.status {
          Completed(_) -> True
          _ -> False
        }
      Error(_) -> False
    }
  })
}

// ---------------------------------------------------------------------------
// Summary
// ---------------------------------------------------------------------------

/// Returns a human-readable summary of the sequence state.
pub fn summary(sequence: ToolSequence) -> String {
  let total = list.length(sequence.steps)
  let completed =
    list.filter(sequence.results, fn(r) {
      case r.status {
        Completed(_) -> True
        _ -> False
      }
    })
    |> list.length()
  let failed =
    list.filter(sequence.results, fn(r) {
      case r.status {
        Failed(_) -> True
        _ -> False
      }
    })
    |> list.length()
  let waves = list.length(execution_order(sequence))
  "ToolSequence{steps="
  <> int.to_string(total)
  <> ",completed="
  <> int.to_string(completed)
  <> ",failed="
  <> int.to_string(failed)
  <> ",waves="
  <> int.to_string(waves)
  <> "}"
}
