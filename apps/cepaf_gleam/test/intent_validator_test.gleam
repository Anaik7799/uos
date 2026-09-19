//// [C3I-SIL6-MSTS] TEST SUITE
//// <c3i-test>
////   <target>cepaf_gleam/intent/validator</target>
////   <compliance>SC-JIDOKA-001, SC-INTENT-ATLAS-001</compliance>
//// </c3i-test>
////
//// Unit tests for Declarative Intent Poka-Yoke Validator.

import cepaf_gleam/intent/config.{
  ContainerIntent, type IntentConfig, IntentConfig,
}
import cepaf_gleam/intent/validator
import gleeunit/should

fn valid_baseline_config() -> IntentConfig {
  IntentConfig(
    version: "1.0.0",
    name: "test-intent",
    authority: "sa-plan",
    target_drive_serial: "SAMSUNG_990_PRO_SECONDARY",
    prajna_health_threshold: 0.85,
    topology_nodes: ["nas-1.tail55d152.ts.net"],
    containers: [
      ContainerIntent(
        name: "test-router",
        image: "zenoh:1.2.1",
        port: 8080,
        enabled: True,
      ),
    ],
    zenoh_topics: ["indrajaal/l0/const/**"],
  )
}

pub fn valid_config_passes_test() {
  let cfg = valid_baseline_config()
  validator.validate_intent_config(cfg) |> should.be_ok()
}

pub fn invalid_authority_fails_test() {
  let cfg = IntentConfig(..valid_baseline_config(), authority: "ad-hoc-script")
  let res = validator.validate_intent_config(cfg)
  res |> should.be_error()
}

pub fn hard_denied_drive_fails_test() {
  let cfg =
    IntentConfig(..valid_baseline_config(), target_drive_serial: "25503L801736")
  let res = validator.validate_intent_config(cfg)
  res |> should.be_error()
}

pub fn invalid_health_threshold_fails_test() {
  let cfg =
    IntentConfig(..valid_baseline_config(), prajna_health_threshold: 0.50)
  let res = validator.validate_intent_config(cfg)
  res |> should.be_error()
}

pub fn invalid_container_port_fails_test() {
  let invalid_container =
    ContainerIntent(
      name: "bad-port-container",
      image: "img:1",
      port: 99_999,
      enabled: True,
    )
  let cfg =
    IntentConfig(..valid_baseline_config(), containers: [invalid_container])
  let res = validator.validate_intent_config(cfg)
  res |> should.be_error()
}
