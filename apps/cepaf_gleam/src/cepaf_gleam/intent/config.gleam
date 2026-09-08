//// [C3I-SIL6-MSTS] MODULE CONTRACT
//// <c3i-module>
////   <identity><module>cepaf_gleam/intent/config</module></identity>
////   <fractal-topology><layer>L0_CONSTITUTIONAL..L5_COGNITIVE</layer></fractal-topology>
////   <compliance><stamp-controls>SC-INTENT-ATLAS-001, SC-JIDOKA-001, SC-CHECKLIST-001</stamp-controls></compliance>
//// </c3i-module>
////
//// Declarative Intent Configuration Schema, JSON Codecs, Delta Calculation,
//// and Supervised OODA Reconciler Model.
//// Replaces imperative configuration with denotational declarative intents.

import gleam/dynamic/decode
import gleam/json
import gleam/list

/// Container Intent Specification within Declarative Configuration.
pub type ContainerIntent {
  ContainerIntent(
    name: String,
    image: String,
    port: Int,
    enabled: Bool,
  )
}

/// Declarative Intent Configuration for UOS Subsystems.
pub type IntentConfig {
  IntentConfig(
    version: String,
    name: String,
    authority: String,
    target_drive_serial: String,
    prajna_health_threshold: Float,
    topology_nodes: List(String),
    containers: List(ContainerIntent),
    zenoh_topics: List(String),
  )
}

/// Calculated Delta between Current Intent and Target Intent.
pub type ConfigDelta {
  ConfigDelta(
    added_containers: List(String),
    removed_containers: List(String),
    threshold_drift: Float,
    requires_reconciliation: Bool,
  )
}

/// Canonical Default Intent Baseline Configuration.
pub fn default_config() -> IntentConfig {
  IntentConfig(
    version: "1.0.0",
    name: "uos-baseline-intent",
    authority: "sa-plan",
    target_drive_serial: "SAMSUNG_990_PRO_SECONDARY",
    prajna_health_threshold: 0.85,
    topology_nodes: [
      "nas-1.tail55d152.ts.net",
      "vm-1.tail55d152.ts.net",
    ],
    containers: [
      ContainerIntent(
        name: "c3i-zenoh-router",
        image: "eclipse/zenoh:1.2.1",
        port: 8080,
        enabled: True,
      ),
      ContainerIntent(
        name: "c3i-redis-telemetry",
        image: "redis:7.2-alpine",
        port: 6379,
        enabled: True,
      ),
      ContainerIntent(
        name: "c3i-postgres-store",
        image: "postgres:16-alpine",
        port: 5432,
        enabled: True,
      ),
    ],
    zenoh_topics: [
      "indrajaal/l0/const/**",
      "indrajaal/l1/atomic/**",
      "indrajaal/l2/health/**",
      "indrajaal/otel/spans/**",
    ],
  )
}

/// JSON serialization for ContainerIntent.
pub fn container_to_json(c: ContainerIntent) -> json.Json {
  json.object([
    #("name", json.string(c.name)),
    #("image", json.string(c.image)),
    #("port", json.int(c.port)),
    #("enabled", json.bool(c.enabled)),
  ])
}

/// JSON serialization for IntentConfig.
pub fn config_to_json(cfg: IntentConfig) -> json.Json {
  json.object([
    #("version", json.string(cfg.version)),
    #("name", json.string(cfg.name)),
    #("authority", json.string(cfg.authority)),
    #("target_drive_serial", json.string(cfg.target_drive_serial)),
    #("prajna_health_threshold", json.float(cfg.prajna_health_threshold)),
    #("topology_nodes", json.array(cfg.topology_nodes, json.string)),
    #("containers", json.array(cfg.containers, container_to_json)),
    #("zenoh_topics", json.array(cfg.zenoh_topics, json.string)),
  ])
}

/// Computes configuration delta between current active config and target intent.
pub fn compute_delta(current: IntentConfig, target: IntentConfig) -> ConfigDelta {
  let cur_names = list.map(current.containers, fn(c) { c.name })
  let tgt_names = list.map(target.containers, fn(c) { c.name })

  let added = list.filter(tgt_names, fn(n) { !list.contains(cur_names, n) })
  let removed = list.filter(cur_names, fn(n) { !list.contains(tgt_names, n) })
  let drift = target.prajna_health_threshold -. current.prajna_health_threshold

  let has_changes =
    added != []
    || removed != []
    || drift >. 0.001
    || drift <. -0.001

  ConfigDelta(
    added_containers: added,
    removed_containers: removed,
    threshold_drift: drift,
    requires_reconciliation: has_changes,
  )
}

/// JSON decoder for ContainerIntent.
pub fn container_decoder() -> decode.Decoder(ContainerIntent) {
  use name <- decode.field("name", decode.string)
  use image <- decode.field("image", decode.string)
  use port <- decode.field("port", decode.int)
  use enabled <- decode.field("enabled", decode.bool)
  decode.success(ContainerIntent(name:, image:, port:, enabled:))
}

/// JSON decoder for IntentConfig.
pub fn config_decoder() -> decode.Decoder(IntentConfig) {
  use version <- decode.field("version", decode.string)
  use name <- decode.field("name", decode.string)
  use authority <- decode.field("authority", decode.string)
  use target_drive_serial <- decode.field("target_drive_serial", decode.string)
  use prajna_health_threshold <- decode.field(
    "prajna_health_threshold",
    decode.float,
  )
  use topology_nodes <- decode.field(
    "topology_nodes",
    decode.list(decode.string),
  )
  use containers <- decode.field("containers", decode.list(container_decoder()))
  use zenoh_topics <- decode.field("zenoh_topics", decode.list(decode.string))

  decode.success(IntentConfig(
    version:,
    name:,
    authority:,
    target_drive_serial:,
    prajna_health_threshold:,
    topology_nodes:,
    containers:,
    zenoh_topics:,
  ))
}

/// Decodes JSON string into IntentConfig.
pub fn decode_config(json_string: String) -> Result(IntentConfig, String) {
  case json.parse(json_string, config_decoder()) {
    Ok(cfg) -> Ok(cfg)
    Error(_) -> Error("DecodeError: Failed to parse IntentConfig JSON")
  }
}
