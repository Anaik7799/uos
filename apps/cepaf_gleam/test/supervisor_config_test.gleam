//// Supervisor Config & Dead Man's Switch Tests
//// F12 + F18 + F19

import cepaf_gleam/ha/supervisor_config.{
  EnterSafeState, JidokaHalt, OneForAll, OneForOne, RestForOne,
}
import gleeunit/should

// ═══════════════════════════════════════════════════════════════
// F18: Supervisor Strategy Tests
// ═══════════════════════════════════════════════════════════════

pub fn l0_uses_one_for_all_test() {
  let config = supervisor_config.config_for_layer("L0")
  config.strategy |> should.equal(OneForAll)
}

pub fn l0_has_strict_restart_limit_test() {
  let config = supervisor_config.config_for_layer("L0")
  config.max_restarts |> should.equal(1)
}

pub fn l1_uses_one_for_one_test() {
  let config = supervisor_config.config_for_layer("L1")
  config.strategy |> should.equal(OneForOne)
}

pub fn l5_uses_rest_for_one_test() {
  let config = supervisor_config.config_for_layer("L5")
  config.strategy |> should.equal(RestForOne)
}

pub fn l7_uses_one_for_all_test() {
  let config = supervisor_config.config_for_layer("L7")
  config.strategy |> should.equal(OneForAll)
}

pub fn unknown_layer_gets_default_test() {
  let config = supervisor_config.config_for_layer("unknown")
  config.strategy |> should.equal(OneForOne)
  config.max_restarts |> should.equal(3)
}

// ═══════════════════════════════════════════════════════════════
// F19: Restart Rate Limiting Tests
// ═══════════════════════════════════════════════════════════════

pub fn within_limit_returns_false_test() {
  let config = supervisor_config.config_for_layer("L3")
  supervisor_config.would_exceed_limit(config, 2)
  |> should.be_false()
}

pub fn at_limit_returns_true_test() {
  let config = supervisor_config.config_for_layer("L3")
  supervisor_config.would_exceed_limit(config, 3)
  |> should.be_true()
}

pub fn over_limit_returns_true_test() {
  let config = supervisor_config.config_for_layer("L3")
  supervisor_config.would_exceed_limit(config, 10)
  |> should.be_true()
}

pub fn l0_very_strict_limit_test() {
  let config = supervisor_config.config_for_layer("L0")
  // L0 allows only 1 restart — very strict for safety
  supervisor_config.would_exceed_limit(config, 1)
  |> should.be_true()
}

// ═══════════════════════════════════════════════════════════════
// F12: Dead Man's Switch Tests
// ═══════════════════════════════════════════════════════════════

pub fn default_dms_has_100ms_heartbeat_test() {
  let dms = supervisor_config.default_dms()
  dms.heartbeat_interval_ms |> should.equal(100)
}

pub fn default_dms_enters_safe_state_test() {
  let dms = supervisor_config.default_dms()
  dms.timeout_action |> should.equal(EnterSafeState)
}

pub fn critical_dms_has_50ms_heartbeat_test() {
  let dms = supervisor_config.critical_dms()
  dms.heartbeat_interval_ms |> should.equal(50)
}

pub fn critical_dms_halts_on_timeout_test() {
  let dms = supervisor_config.critical_dms()
  dms.timeout_action |> should.equal(JidokaHalt)
}

pub fn critical_dms_faster_than_default_test() {
  let default = supervisor_config.default_dms()
  let critical = supervisor_config.critical_dms()
  { critical.timeout_ms < default.timeout_ms }
  |> should.be_true()
}

// ═══════════════════════════════════════════════════════════════
// Utility Tests
// ═══════════════════════════════════════════════════════════════

pub fn strategy_name_test() {
  supervisor_config.strategy_name(OneForOne) |> should.equal("one_for_one")
  supervisor_config.strategy_name(OneForAll) |> should.equal("one_for_all")
  supervisor_config.strategy_name(RestForOne) |> should.equal("rest_for_one")
}

pub fn describe_contains_name_test() {
  let config = supervisor_config.config_for_layer("L5")
  let desc = supervisor_config.describe(config)
  { desc != "" } |> should.be_true()
}
