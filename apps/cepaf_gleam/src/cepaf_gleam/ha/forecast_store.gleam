//// SQLite Persistent Forecast History & Brier Calibration Ledger (Workstream S4)
//// #fractal-l3 #fractal-l5 #zero-muda #tailscale-web #sa-plan
////
//// Delivers persistent, durable storage for predictive OODA forecasts and
//// computes real denominator-backed Brier calibration scores per PLAN-UOS-STABILIZE-001.

import gleam/int
import gleam/list

pub type ForecastDb

@external(erlang, "cepaf_gleam_ffi", "sqlite_open")
pub fn open_db(path: String) -> Result(ForecastDb, String)

@external(erlang, "cepaf_gleam_ffi", "sqlite_exec")
pub fn exec_sql(db: ForecastDb, sql: String) -> Result(Int, String)

@external(erlang, "cepaf_gleam_ffi", "sqlite_close")
pub fn close_db(db: ForecastDb) -> Nil

pub type StoredForecast {
  StoredForecast(
    prediction_id: String,
    predicted_prob: Float,
    observed_outcome: Bool,
    resolved: Bool,
    timestamp_ns: Int,
    aspect: String,
  )
}

pub type CalibrationResult {
  Calibrated(brier_score: Float, sample_count: Int)
  Undetermined(reason: String)
}

/// Initializes the forecast table schema with append-only integrity
pub fn init_schema(db: ForecastDb) -> Result(Int, String) {
  let ddl =
    "CREATE TABLE IF NOT EXISTS forecast_ledger (
      prediction_id TEXT PRIMARY KEY,
      predicted_prob REAL NOT NULL,
      observed_outcome INTEGER NOT NULL,
      resolved INTEGER NOT NULL,
      timestamp_ns INTEGER NOT NULL,
      aspect TEXT NOT NULL
    );"
  exec_sql(db, ddl)
}

/// Pure in-memory calculation of Brier calibration carrying denominator
pub fn calculate_calibration(
  records: List(StoredForecast),
) -> CalibrationResult {
  let resolved_records =
    list.filter(records, fn(r) { r.resolved })

  let count = list.length(resolved_records)
  case count {
    0 -> Undetermined("No resolved forecast predictions in ledger (sample_count=0)")
    _ -> {
      let total_squared_error =
        list.fold(resolved_records, 0.0, fn(acc, rec) {
          let outcome_val = case rec.observed_outcome {
            True -> 1.0
            False -> 0.0
          }
          let diff = rec.predicted_prob -. outcome_val
          acc +. { diff *. diff }
        })
      let f_count = int.to_float(count)
      let brier = total_squared_error /. f_count
      Calibrated(brier_score: brier, sample_count: count)
    }
  }
}
