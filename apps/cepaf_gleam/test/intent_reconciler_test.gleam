//// [C3I-SIL6-MSTS] TEST SUITE
//// <c3i-test>
////   <target>cepaf_gleam/intent/reconciler</target>
////   <compliance>SC-INTENT-ATLAS-001, SC-JIDOKA-001</compliance>
//// </c3i-test>
////
//// Unit tests for Autonomous OODA Reconciler Worker Actor.

import cepaf_gleam/intent/config.{
  type IntentConfig, ContainerIntent, IntentConfig,
}
import cepaf_gleam/intent/reconciler.{
  GetReconcilerStatus, TriggerOodaTick, UpdateDesiredIntent,
}
import gleam/erlang/process
import gleeunit/should

fn baseline_config() -> IntentConfig {
  IntentConfig(
    version: "1.0.0",
    name: "reconciler-baseline",
    authority: "sa-plan",
    target_drive_serial: "SAMSUNG_990_PRO_SECONDARY",
    prajna_health_threshold: 0.85,
    topology_nodes: ["nas-1.tail55d152.ts.net"],
    containers: [
      ContainerIntent(
        name: "test-zenoh",
        image: "eclipse/zenoh:1.2.1",
        port: 8080,
        enabled: True,
      ),
    ],
    zenoh_topics: ["indrajaal/l0/const/**"],
  )
}

pub fn reconciler_init_and_status_test() {
  let cfg = baseline_config()
  let state = reconciler.init_reconciler(cfg)
  state.is_converged |> should.be_true()
  state.cycle_counter |> should.equal(0)
  state.current.name |> should.equal("reconciler-baseline")
}

pub fn reconciler_actor_flow_test() {
  let cfg = baseline_config()
  let assert Ok(subj) = reconciler.start(cfg)

  // 1. Check initial status
  let state1 = process.call(subj, 1000, fn(reply) { GetReconcilerStatus(reply) })
  state1.is_converged |> should.be_true()

  // 2. Submit new desired intent with extra container
  let new_container =
    ContainerIntent(
      name: "test-redis",
      image: "redis:7.2",
      port: 6379,
      enabled: True,
    )
  let desired =
    IntentConfig(..cfg, containers: [new_container, ..cfg.containers])

  let update_res =
    process.call(subj, 1000, fn(reply) { UpdateDesiredIntent(desired, reply) })
  let assert Ok(delta) = update_res
  delta.requires_reconciliation |> should.be_true()

  // 3. Trigger OODA convergence tick
  let #(converged, tick_count) =
    process.call(subj, 1000, fn(reply) { TriggerOodaTick(reply) })
  converged |> should.be_true()
  tick_count |> should.equal(1)

  // 4. Verify converged state
  let state2 = process.call(subj, 1000, fn(reply) { GetReconcilerStatus(reply) })
  state2.is_converged |> should.be_true()
  state2.current.containers |> should.equal(desired.containers)
}
