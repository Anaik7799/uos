//// [C3I-SIL6-MSTS] MODULE
//// <c3i-core>
////   <layer>L0</layer>
////   <target>cepaf_gleam/intent/validator</target>
////   <compliance>SC-JIDOKA-001, SC-INTENT-ATLAS-001, SC-CHECKLIST-001</compliance>
//// </c3i-core>
////
//// Declarative Intent Poka-Yoke Schema Validator.
//// Enforces strict fail-closed boundary constraints on IntentConfig:
//// 1. Authority must be canonical "sa-plan" (SC-JIDOKA-001)
//// 2. Target drive serial cannot match HARD_DENIED_SYSTEM_OS_SERIAL ("25503L801736")
//// 3. Prajna health threshold must satisfy 0.80 <= h <= 1.0
//// 4. All container ports must fall within [1, 65535]
//// 5. Topology nodes and Zenoh topics must not be empty

import cepaf_gleam/intent/config.{type ContainerIntent, type IntentConfig}
import gleam/list
import gleam/string

pub const hard_denied_system_os_serial = "25503L801736"

pub fn validate_intent_config(
  cfg: IntentConfig,
) -> Result(IntentConfig, List(String)) {
  let errors =
    []
    |> check_authority(cfg.authority)
    |> check_target_drive(cfg.target_drive_serial)
    |> check_health_threshold(cfg.prajna_health_threshold)
    |> check_topology_nodes(cfg.topology_nodes)
    |> check_containers(cfg.containers)
    |> check_zenoh_topics(cfg.zenoh_topics)

  case errors {
    [] -> Ok(cfg)
    _ -> Error(errors)
  }
}

fn check_authority(errors: List(String), authority: String) -> List(String) {
  case authority == "sa-plan" {
    True -> errors
    False -> [
      "AuthorityError: authority '"
        <> authority
        <> "' violates SC-JIDOKA-001; must be 'sa-plan'",
      ..errors
    ]
  }
}

fn check_target_drive(errors: List(String), serial: String) -> List(String) {
  case serial == hard_denied_system_os_serial {
    True -> [
      "DriveSafetyError: target_drive_serial '"
        <> serial
        <> "' matches HARD_DENIED_SYSTEM_OS_SERIAL; mutation forbidden",
      ..errors
    ]
    False -> errors
  }
}

fn check_health_threshold(errors: List(String), threshold: Float) -> List(String) {
  case threshold >=. 0.80 && threshold <=. 1.0 {
    True -> errors
    False -> [
      "HealthThresholdError: prajna_health_threshold must be between 0.80 and 1.0",
      ..errors
    ]
  }
}

fn check_topology_nodes(
  errors: List(String),
  nodes: List(String),
) -> List(String) {
  case nodes {
    [] -> ["TopologyError: topology_nodes cannot be empty", ..errors]
    _ -> errors
  }
}

fn check_containers(
  errors: List(String),
  containers: List(ContainerIntent),
) -> List(String) {
  list.fold(containers, errors, fn(acc, c) {
    let acc1 = case c.port >= 1 && c.port <= 65535 {
      True -> acc
      False -> [
        "ContainerPortError: container '"
          <> c.name
          <> "' has invalid port",
        ..acc
      ]
    }
    case string.is_empty(c.name) || string.is_empty(c.image) {
      True -> ["ContainerSpecError: container name or image is empty", ..acc1]
      False -> acc1
    }
  })
}

fn check_zenoh_topics(
  errors: List(String),
  topics: List(String),
) -> List(String) {
  case topics {
    [] -> ["ZenohTopicError: zenoh_topics cannot be empty", ..errors]
    _ -> errors
  }
}
