//// [C3I-SIL6-MSTS] MODULE CONTRACT
//// <c3i-module>
////   <identity><module>cepaf_gleam/ui/lustre/heartbeat_page</module></identity>
////   <fractal-topology><layer>L4_SYSTEM</layer></fractal-topology>
////   <compliance><stamp-controls>SC-GLM-UI-001, SC-HA-001, SC-BIO-EVO-001</stamp-controls></compliance>
//// </c3i-module>
////
//// Lustre MVU model for the Heartbeat page.
//// Displays Gleam↔Rust bidirectional heartbeat status and failover state.

import gleam/option.{type Option, None, Some}

pub type HeartbeatModel {
  HeartbeatModel(
    rust_alive: Bool,
    failover_active: Bool,
    total_pings: Int,
    total_pongs: Int,
    consecutive_failures: Int,
    uptime_ratio: Float,
    health_score: Float,
    loading: Bool,
    error: Option(String),
  )
}

pub type HeartbeatMsg {
  HeartbeatLoaded(
    alive: Bool,
    failover: Bool,
    pings: Int,
    pongs: Int,
    failures: Int,
    uptime: Float,
    health: Float,
  )
  PingResult(alive: Bool, response_size: Int)
  RefreshHeartbeat
  ErrorReceived(String)
}

pub fn init() -> HeartbeatModel {
  HeartbeatModel(
    rust_alive: True,
    failover_active: False,
    total_pings: 0,
    total_pongs: 0,
    consecutive_failures: 0,
    uptime_ratio: 1.0,
    health_score: 1.0,
    loading: True,
    error: None,
  )
}

pub fn update(model: HeartbeatModel, msg: HeartbeatMsg) -> HeartbeatModel {
  case msg {
    HeartbeatLoaded(alive, failover, pings, pongs, failures, uptime, health) ->
      HeartbeatModel(
        rust_alive: alive,
        failover_active: failover,
        total_pings: pings,
        total_pongs: pongs,
        consecutive_failures: failures,
        uptime_ratio: uptime,
        health_score: health,
        loading: False,
        error: None,
      )
    PingResult(alive, _size) ->
      HeartbeatModel(
        ..model,
        rust_alive: alive,
        total_pings: model.total_pings + 1,
        total_pongs: case alive {
          True -> model.total_pongs + 1
          False -> model.total_pongs
        },
        consecutive_failures: case alive {
          True -> 0
          False -> model.consecutive_failures + 1
        },
      )
    RefreshHeartbeat -> HeartbeatModel(..model, loading: True)
    ErrorReceived(e) -> HeartbeatModel(..model, error: Some(e), loading: False)
  }
}
