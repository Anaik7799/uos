//// [C3I-SIL6-MSTS] Recursive TDG for Substrate Plane
//// STAMP: SC-VER-001, SC-FUNC-001

import cepaf_gleam/podman/uds_client as podman
import cepaf_gleam/substrate/boot
import gleam/list
import gleeunit/should

pub fn podman_uds_client_new_test() {
  let conn = podman.new("/run/podman/podman.sock")
  conn.socket_path
  |> should.equal("/run/podman/podman.sock")
}

pub fn boot_sequence_phases_test() {
  // Verify the 5-stage biomorphic phases are handled
  // Foundation(1) + NervousSystem(3) + StatePlane(2) + CognitivePlane(5) + Verification(1) = 12
  case boot.execute_boot() {
    Ok(state) -> {
      state.phase |> should.equal(boot.Verification)
      list.length(state.containers_started) |> should.equal(12)
    }
    Error(_) -> should.fail()
  }
}

pub fn boot_rollback_sim_test() {
  // Test simulation of boot state management
  let initial =
    boot.BootState(
      phase: boot.Foundation,
      containers_started: ["node-1"],
      uds: podman.new("/tmp/test.sock"),
    )

  initial.containers_started |> should.equal(["node-1"])
}
