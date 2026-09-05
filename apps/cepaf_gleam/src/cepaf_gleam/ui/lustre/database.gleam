/// Lustre component for Database plane (SC-GLM-UI-001).
/// Tracks connections, query stats, latency, and failure rates.
/// STAMP: SC-GLM-UI-001, SC-GLM-UI-002, SC-GLM-UI-009
import gleam/int

pub type DatabaseModel {
  DatabaseModel(
    supported_types: List(String),
    active_connections: Int,
    total_queries: Int,
    failed_queries: Int,
    avg_latency: Float,
  )
}

pub type DatabaseMsg {
  StatsUpdated(Int, Int, Float)
  ConnectionOpened
  ConnectionClosed
  RefreshDatabase
}

pub fn init() -> DatabaseModel {
  DatabaseModel(
    supported_types: ["sqlite", "duckdb"],
    active_connections: 0,
    total_queries: 0,
    failed_queries: 0,
    avg_latency: 0.0,
  )
}

pub fn update(model: DatabaseModel, msg: DatabaseMsg) -> DatabaseModel {
  case msg {
    StatsUpdated(total, failed, latency) ->
      DatabaseModel(
        ..model,
        total_queries: total,
        failed_queries: failed,
        avg_latency: latency,
      )
    ConnectionOpened ->
      DatabaseModel(..model, active_connections: model.active_connections + 1)
    ConnectionClosed ->
      DatabaseModel(
        ..model,
        active_connections: case model.active_connections > 0 {
          True -> model.active_connections - 1
          False -> 0
        },
      )
    RefreshDatabase -> model
  }
}

pub fn is_healthy(model: DatabaseModel) -> Bool {
  model.active_connections > 0 && model.avg_latency <. 100.0
}

pub fn failure_rate(model: DatabaseModel) -> Float {
  case model.total_queries {
    0 -> 0.0
    _ -> int.to_float(model.failed_queries) /. int.to_float(model.total_queries)
  }
}
