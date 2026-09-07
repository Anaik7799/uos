//// MirageOS Unikernel Simulation State
////
//// This module models lifecycle and policy behavior. It does not start an OTP
//// actor, a Solo5 tender, or any other operating-system process.

import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/string

pub type TargetPlatform {
  TargetUnix
  TargetSolo5Hvt
  TargetSolo5Spt
  TargetXen
}

pub type RuntimeMode {
  SimulationOnly
}

pub type RuntimeObservation {
  RuntimeUnobserved(reason: String)
}

pub type UnikernelStatus {
  StatusSimulatedRunning
  StatusSimulatedTerminated
}

pub type UnikernelInstance {
  UnikernelInstance(
    id: String,
    name: String,
    platform: TargetPlatform,
    configured_memory_mb: Int,
    projected_cold_start_ms: Float,
    status: UnikernelStatus,
    simulated_invocations: Int,
    simulated_trapped_threats: Int,
  )
}

pub type MirageDaemonState {
  MirageDaemonState(
    instances: Dict(String, UnikernelInstance),
    configured_max_memory_mb: Int,
    simulated_boots: Int,
    simulated_trapped: Int,
    mode: RuntimeMode,
    observation: RuntimeObservation,
  )
}

pub type InterceptVerdict {
  VerdictSimulationAllowed
  VerdictTrappedNullByte
  VerdictTrappedSqlInjection(pattern: String)
}

pub fn new_daemon_state() -> MirageDaemonState {
  MirageDaemonState(
    instances: dict.new(),
    configured_max_memory_mb: 64,
    simulated_boots: 0,
    simulated_trapped: 0,
    mode: SimulationOnly,
    observation: RuntimeUnobserved(
      "No supervised Mirage actor or Solo5 runtime observation is connected",
    ),
  )
}

pub fn runtime_mode_label(mode: RuntimeMode) -> String {
  case mode {
    SimulationOnly -> "simulation_only"
  }
}

pub fn observation_status(observation: RuntimeObservation) -> String {
  case observation {
    RuntimeUnobserved(_) -> "unknown"
  }
}

pub fn observation_reason(observation: RuntimeObservation) -> String {
  case observation {
    RuntimeUnobserved(reason) -> reason
  }
}

pub fn platform_label(platform: TargetPlatform) -> String {
  case platform {
    TargetUnix -> "unix"
    TargetSolo5Hvt -> "solo5-hvt"
    TargetSolo5Spt -> "solo5-spt"
    TargetXen -> "xen"
  }
}

pub fn status_label(status: UnikernelStatus) -> String {
  case status {
    StatusSimulatedRunning -> "simulated_running"
    StatusSimulatedTerminated -> "simulated_terminated"
  }
}

/// Simulate a lifecycle transition. No process is launched and the cold-start
/// value is a projection derived from configured memory.
pub fn simulate_boot_unikernel(
  state: MirageDaemonState,
  id: String,
  name: String,
  platform: TargetPlatform,
  memory_mb: Int,
) -> Result(#(MirageDaemonState, UnikernelInstance), String) {
  case memory_mb <= 0 || memory_mb > state.configured_max_memory_mb {
    True ->
      Error(
        "Configured memory "
        <> int.to_string(memory_mb)
        <> "MB must be within 1.."
        <> int.to_string(state.configured_max_memory_mb)
        <> "MB",
      )
    False ->
      case id == "" || name == "" {
        True -> Error("Simulation id and name must be non-empty")
        False ->
          case dict.has_key(state.instances, id) {
            True -> Error("Simulation instance already exists: " <> id)
            False -> {
              let projected_cold_start = 8.5 +. int.to_float(memory_mb) *. 0.15
              let instance =
                UnikernelInstance(
                  id: id,
                  name: name,
                  platform: platform,
                  configured_memory_mb: memory_mb,
                  projected_cold_start_ms: projected_cold_start,
                  status: StatusSimulatedRunning,
                  simulated_invocations: 0,
                  simulated_trapped_threats: 0,
                )
              let updated_state =
                MirageDaemonState(
                  ..state,
                  instances: dict.insert(state.instances, id, instance),
                  simulated_boots: state.simulated_boots + 1,
                )
              Ok(#(updated_state, instance))
            }
          }
      }
  }
}

/// Apply the model's bounded string screen. An allowed result is not an
/// execution authorization or a cryptographic admission receipt.
pub fn simulate_dispatch_tool_call(
  state: MirageDaemonState,
  instance_id: String,
  payload: String,
) -> Result(#(MirageDaemonState, InterceptVerdict), String) {
  case dict.get(state.instances, instance_id) {
    Error(_) -> Error("Simulation instance not found: " <> instance_id)
    Ok(instance) ->
      case instance.status {
        StatusSimulatedRunning -> {
          let verdict = inspect_payload(payload)
          let #(instance_trapped, state_trapped) = case verdict {
            VerdictSimulationAllowed -> #(
              instance.simulated_trapped_threats,
              state.simulated_trapped,
            )
            _ -> #(
              instance.simulated_trapped_threats + 1,
              state.simulated_trapped + 1,
            )
          }
          let updated_instance =
            UnikernelInstance(
              ..instance,
              simulated_invocations: instance.simulated_invocations + 1,
              simulated_trapped_threats: instance_trapped,
            )
          let updated_state =
            MirageDaemonState(
              ..state,
              instances: dict.insert(
                state.instances,
                instance_id,
                updated_instance,
              ),
              simulated_trapped: state_trapped,
            )
          Ok(#(updated_state, verdict))
        }
        StatusSimulatedTerminated -> Error("Simulation instance is terminated")
      }
  }
}

pub fn simulate_terminate_unikernel(
  state: MirageDaemonState,
  instance_id: String,
) -> Result(MirageDaemonState, String) {
  case dict.get(state.instances, instance_id) {
    Error(_) -> Error("Simulation instance not found: " <> instance_id)
    Ok(instance) -> {
      let updated_instance =
        UnikernelInstance(..instance, status: StatusSimulatedTerminated)
      Ok(
        MirageDaemonState(
          ..state,
          instances: dict.insert(state.instances, instance_id, updated_instance),
        ),
      )
    }
  }
}

pub fn simulated_running_count(state: MirageDaemonState) -> Int {
  state.instances
  |> dict.values
  |> list.count(fn(instance) { instance.status == StatusSimulatedRunning })
}

pub fn simulated_terminated_count(state: MirageDaemonState) -> Int {
  state.instances
  |> dict.values
  |> list.count(fn(instance) { instance.status == StatusSimulatedTerminated })
}

pub fn inspect_payload(payload: String) -> InterceptVerdict {
  case string.contains(payload, "\u{0000}") {
    True -> VerdictTrappedNullByte
    False -> {
      let upper = string.uppercase(payload)
      let dangerous_sql = [
        "DROP TABLE",
        "DELETE FROM",
        "TRUNCATE",
        "UNION SELECT",
        "INSERT INTO",
        "UPDATE ",
        "--",
        ";--",
      ]
      case
        list.find(dangerous_sql, fn(pattern) { string.contains(upper, pattern) })
      {
        Ok(pattern) -> VerdictTrappedSqlInjection(pattern)
        Error(_) -> VerdictSimulationAllowed
      }
    }
  }
}
