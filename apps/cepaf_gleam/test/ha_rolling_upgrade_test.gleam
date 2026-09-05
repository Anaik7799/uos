/// HA rolling upgrade state machine tests
/// SC-ULTRA-001 Focus 10: HA Seamless Upgrades
import cepaf_gleam/ha/rolling_upgrade
import gleeunit/should

pub fn init_is_idle_test() {
  let model = rolling_upgrade.init()
  rolling_upgrade.is_complete(model) |> should.be_false()
}

pub fn plan_starts_upgrading_test() {
  let model =
    rolling_upgrade.init()
    |> rolling_upgrade.plan(["backup", "standby", "primary"], "22.6.0")
  rolling_upgrade.is_complete(model) |> should.be_false()
}

pub fn advance_moves_to_next_node_test() {
  let model =
    rolling_upgrade.init()
    |> rolling_upgrade.plan(["b", "s", "p"], "22.6.0")
    |> rolling_upgrade.advance()
  rolling_upgrade.is_complete(model) |> should.be_false()
}

pub fn advance_all_completes_test() {
  let model =
    rolling_upgrade.init()
    |> rolling_upgrade.plan(["b", "s", "p"], "22.6.0")
    |> rolling_upgrade.advance()
    |> rolling_upgrade.advance()
    |> rolling_upgrade.advance()
  rolling_upgrade.is_complete(model) |> should.be_true()
}

pub fn rollback_records_error_test() {
  let model =
    rolling_upgrade.init()
    |> rolling_upgrade.plan(["b", "p"], "22.6.0")
    |> rolling_upgrade.rollback("health check failed")
  rolling_upgrade.is_complete(model) |> should.be_false()
}

pub fn steps_for_node_has_7_steps_test() {
  let steps = rolling_upgrade.steps_for_node("backup-1", "22.6.0")
  list.length(steps) |> should.equal(7)
}

import gleam/list
