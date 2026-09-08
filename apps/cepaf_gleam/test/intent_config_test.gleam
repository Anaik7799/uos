//// [C3I-SIL6-MSTS] TEST SUITE
//// <c3i-test>
////   <target>cepaf_gleam/intent/config</target>
////   <compliance>SC-INTENT-ATLAS-001, SC-JIDOKA-001, SC-CHECKLIST-001</compliance>
//// </c3i-test>

import cepaf_gleam/intent/config
import gleam/json
import gleam/list
import gleeunit/should

pub fn default_config_fields_test() {
  let cfg = config.default_config()
  cfg.version |> should.equal("1.0.0")
  cfg.name |> should.equal("uos-baseline-intent")
  cfg.authority |> should.equal("sa-plan")
  cfg.target_drive_serial |> should.equal("SAMSUNG_990_PRO_SECONDARY")
  cfg.prajna_health_threshold |> should.equal(0.85)
  list.length(cfg.topology_nodes) |> should.equal(2)
  list.length(cfg.containers) |> should.equal(3)
  list.length(cfg.zenoh_topics) |> should.equal(4)
}

pub fn json_roundtrip_test() {
  let cfg = config.default_config()
  let json_str = config.config_to_json(cfg) |> json.to_string

  let decode_res = config.decode_config(json_str)
  decode_res |> should.be_ok
  let assert Ok(decoded) = decode_res

  decoded.version |> should.equal(cfg.version)
  decoded.name |> should.equal(cfg.name)
  decoded.authority |> should.equal(cfg.authority)
  decoded.target_drive_serial |> should.equal(cfg.target_drive_serial)
  decoded.prajna_health_threshold |> should.equal(cfg.prajna_health_threshold)
  list.length(decoded.containers) |> should.equal(3)
}

pub fn compute_delta_no_change_test() {
  let cfg = config.default_config()
  let delta = config.compute_delta(cfg, cfg)

  delta.requires_reconciliation |> should.equal(False)
  delta.added_containers |> should.equal([])
  delta.removed_containers |> should.equal([])
  delta.threshold_drift |> should.equal(0.0)
}

pub fn compute_delta_with_changes_test() {
  let cfg1 = config.default_config()
  let modified_containers = [
    config.ContainerIntent(
      name: "c3i-zenoh-router",
      image: "eclipse/zenoh:1.2.1",
      port: 8080,
      enabled: True,
    ),
    config.ContainerIntent(
      name: "c3i-max-infer-daemon",
      image: "modular/max:24.5",
      port: 9000,
      enabled: True,
    ),
  ]

  let cfg2 =
    config.IntentConfig(
      ..cfg1,
      prajna_health_threshold: 0.90,
      containers: modified_containers,
    )

  let delta = config.compute_delta(cfg1, cfg2)
  delta.requires_reconciliation |> should.equal(True)
  list.contains(delta.added_containers, "c3i-max-infer-daemon")
  |> should.be_true
  list.contains(delta.removed_containers, "c3i-redis-telemetry")
  |> should.be_true
  list.contains(delta.removed_containers, "c3i-postgres-store")
  |> should.be_true
}
