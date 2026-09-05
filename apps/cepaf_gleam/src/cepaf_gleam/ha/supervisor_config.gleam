//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ha/supervisor_config</module>
////     <fsharp-lineage>None — OTP supervisor configuration</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L4_SYSTEM</layer>
////     <mesh-domain>OTP supervisor restart strategies and rate limiting</mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>HIGH</criticality>
////     <stamp-controls>SC-SIL4-001, SC-BIO-EVO-001, SC-TPS-001</stamp-controls>
////   </compliance>
//// </c3i-module>
//// =============================================================================
////
//// Supervisor Configuration — F18 + F19 + F12 (Dead Man's Switch)
//// पर्यवेक्षक विन्यास — Restart strategies, rate limiting, DMS
////
//// Erlang/OTP supervisor tuning for safety-critical systems:
//// - Restart intensity (max_restarts) prevents restart storms
//// - Restart period (max_seconds) bounds failure recovery window
//// - Strategy selection based on failure analysis
//// - Dead man's switch: if monitor itself dies, system enters safe state
////
//// STAMP: SC-SIL4-001, SC-BIO-EVO-001, SC-TPS-001

/// Supervisor restart strategy — determines how child failures propagate
pub type RestartStrategy {
  /// Restart only the failed child (default for independent workers)
  OneForOne
  /// Restart all children if one fails (for tightly coupled workers)
  OneForAll
  /// Restart failed child and all younger siblings
  RestForOne
}

/// Supervisor configuration with rate limiting
pub type SupervisorConfig {
  SupervisorConfig(
    /// Restart strategy
    strategy: RestartStrategy,
    /// Maximum restarts allowed in the period (prevents restart storms)
    max_restarts: Int,
    /// Time period in seconds for restart counting
    max_seconds: Int,
    /// Name for logging/monitoring
    name: String,
    /// Fractal layer this supervisor operates at
    layer: String,
  )
}

/// Dead Man's Switch configuration
pub type DeadManSwitch {
  DeadManSwitch(
    /// How often the monitor must check in (milliseconds)
    heartbeat_interval_ms: Int,
    /// How long before declaring the monitor dead (milliseconds)
    timeout_ms: Int,
    /// Action to take when monitor dies
    timeout_action: TimeoutAction,
  )
}

/// Action when dead man's switch triggers
pub type TimeoutAction {
  /// Enter safe state (display "monitor offline" warning)
  EnterSafeState
  /// Attempt to restart the monitor
  RestartMonitor
  /// Escalate to human operator
  EscalateToHuman
  /// Halt system (Jidoka)
  JidokaHalt
}

/// Default supervisor config for each fractal layer
pub fn config_for_layer(layer: String) -> SupervisorConfig {
  case layer {
    "L0" ->
      SupervisorConfig(
        strategy: OneForAll,
        max_restarts: 1,
        max_seconds: 5,
        name: "L0_Constitutional_Supervisor",
        layer: "L0",
      )
    "L1" | "L2" ->
      SupervisorConfig(
        strategy: OneForOne,
        max_restarts: 5,
        max_seconds: 10,
        name: "L1_L2_Worker_Supervisor",
        layer: layer,
      )
    "L3" | "L4" ->
      SupervisorConfig(
        strategy: OneForOne,
        max_restarts: 3,
        max_seconds: 10,
        name: "L3_L4_Service_Supervisor",
        layer: layer,
      )
    "L5" ->
      SupervisorConfig(
        strategy: RestForOne,
        max_restarts: 3,
        max_seconds: 30,
        name: "L5_Cognitive_Supervisor",
        layer: "L5",
      )
    "L6" | "L7" ->
      SupervisorConfig(
        strategy: OneForAll,
        max_restarts: 2,
        max_seconds: 60,
        name: "L6_L7_Federation_Supervisor",
        layer: layer,
      )
    _ ->
      SupervisorConfig(
        strategy: OneForOne,
        max_restarts: 3,
        max_seconds: 10,
        name: "Default_Supervisor",
        layer: "unknown",
      )
  }
}

/// Default dead man's switch for the freshness monitor
pub fn default_dms() -> DeadManSwitch {
  DeadManSwitch(
    heartbeat_interval_ms: 100,
    timeout_ms: 500,
    timeout_action: EnterSafeState,
  )
}

/// Critical DMS for L0 Constitutional monitors
pub fn critical_dms() -> DeadManSwitch {
  DeadManSwitch(
    heartbeat_interval_ms: 50,
    timeout_ms: 200,
    timeout_action: JidokaHalt,
  )
}

/// Check if restart rate would exceed limits
pub fn would_exceed_limit(
  config: SupervisorConfig,
  recent_restarts: Int,
) -> Bool {
  recent_restarts >= config.max_restarts
}

/// Strategy description for logging
pub fn strategy_name(strategy: RestartStrategy) -> String {
  case strategy {
    OneForOne -> "one_for_one"
    OneForAll -> "one_for_all"
    RestForOne -> "rest_for_one"
  }
}

/// Human-readable config summary
pub fn describe(config: SupervisorConfig) -> String {
  config.name
  <> " ("
  <> strategy_name(config.strategy)
  <> ", max "
  <> int_to_string(config.max_restarts)
  <> " restarts in "
  <> int_to_string(config.max_seconds)
  <> "s, layer "
  <> config.layer
  <> ")"
}

fn int_to_string(n: Int) -> String {
  case n {
    0 -> "0"
    1 -> "1"
    2 -> "2"
    3 -> "3"
    4 -> "4"
    5 -> "5"
    10 -> "10"
    30 -> "30"
    50 -> "50"
    60 -> "60"
    100 -> "100"
    200 -> "200"
    500 -> "500"
    _ -> "N"
  }
}
