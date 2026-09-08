//// apps/cepaf_gleam/src/cepaf_gleam/intent/parser.gleam
//// Pure Gleam Declarative Intent Config Parser & AST Normalizer
//// Contract Reference: SC-INTENT-ATLAS-001

import gleam/list
import gleam/string

pub type ContainerIntent {
  ContainerIntent(
    name: String,
    image: String,
    port: Int,
    enabled: Bool,
  )
}

pub type TopologyNodeIntent {
  TopologyNodeIntent(
    id: String,
    role: String,
    ip: String,
    status: String,
  )
}

pub type SystemIntentConfig {
  SystemIntentConfig(
    version: String,
    authority: String,
    target_drive_serial: String,
    topology_nodes: List(TopologyNodeIntent),
    containers: List(ContainerIntent),
    zenoh_topics: List(String),
  )
}

pub fn default_baseline() -> SystemIntentConfig {
  SystemIntentConfig(
    version: "1.0.0",
    authority: "sa-plan",
    target_drive_serial: "SAMSUNG_990_PRO_SECONDARY",
    topology_nodes: [
      TopologyNodeIntent("nas-1", "primary-cockpit", "100.87.7.78", "online"),
      TopologyNodeIntent("vm-1", "worker-node", "100.78.98.18", "online"),
    ],
    containers: [
      ContainerIntent("c3i-core-broker", "zenoh/zenoh:latest", 7447, True),
      ContainerIntent("c3i-sentinel", "uos/sentinel:v1", 8081, True),
      ContainerIntent("c3i-gleam-cockpit", "uos/cockpit:v1", 4100, True),
    ],
    zenoh_topics: [
      "indrajaal/l0/const/**",
      "indrajaal/otel/spans/**",
      "indrajaal/l2/health/**",
      "indrajaal/l4/system/**",
    ],
  )
}

pub fn normalize_config(cfg: SystemIntentConfig) -> SystemIntentConfig {
  let sorted_topics = list.sort(cfg.zenoh_topics, string.compare)
  SystemIntentConfig(..cfg, zenoh_topics: sorted_topics)
}
