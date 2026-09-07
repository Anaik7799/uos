//// SQLite Persistent Forecast History & Brier Calibration Ledger (Workstream S4)
//// #fractal-l3 #fractal-l5 #zero-muda #tailscale-web #sa-plan
////
//// Delivers persistent, durable storage for predictive OODA forecasts and
//// computes real denominator-backed Brier calibration scores per PLAN-UOS-STABILIZE-001.

import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/int
import gleam/list
import gleam/result

pub type ForecastDb

@external(erlang, "cepaf_gleam_ffi", "sqlite_open")
pub fn open_db(path: String) -> Result(ForecastDb, String)

@external(erlang, "cepaf_gleam_ffi", "sqlite_exec")
pub fn exec_sql(db: ForecastDb, sql: String) -> Result(Int, String)

@external(erlang, "cepaf_gleam_ffi", "sqlite_close")
pub fn close_db(db: ForecastDb) -> Nil

/// Parameterized statement. Every write in this module goes through here
/// rather than through string-built SQL: unparameterized SQL is exactly what
/// the zero-trust dispatch interceptor traps (`DMC` code -3).
@external(erlang, "cepaf_gleam_ffi", "sqlite_q")
fn query(
  db: ForecastDb,
  sql: String,
  params: List(Dynamic),
) -> Result(List(List(Dynamic)), String)

@external(erlang, "cepaf_gleam_ffi", "identity")
fn dyn_string(value: String) -> Dynamic

@external(erlang, "cepaf_gleam_ffi", "identity")
fn dyn_float(value: Float) -> Dynamic

@external(erlang, "cepaf_gleam_ffi", "identity")
fn dyn_int(value: Int) -> Dynamic

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

/// Initializes the forecast table schema with append-only integrity.
///
/// The three triggers implement the precommitment rule that makes a Brier
/// score meaningful at all (`SC-HIVE-FORECAST-001`): a prediction may not be
/// rewritten after its outcome is observed, a resolved prediction is final,
/// and nothing may be deleted. Without them a ledger can be made to score
/// perfectly after the fact, so the number would carry no information.
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
  use rows <- result.try(exec_sql(db, ddl))
  use _ <- result.try(exec_sql(
    db,
    "CREATE TRIGGER IF NOT EXISTS forecast_no_delete
     BEFORE DELETE ON forecast_ledger
     BEGIN SELECT RAISE(ABORT, 'forecast ledger is append-only'); END;",
  ))
  use _ <- result.try(exec_sql(
    db,
    "CREATE TRIGGER IF NOT EXISTS forecast_is_precommitted
     BEFORE UPDATE ON forecast_ledger
     WHEN OLD.predicted_prob <> NEW.predicted_prob
       OR OLD.aspect <> NEW.aspect
       OR OLD.timestamp_ns <> NEW.timestamp_ns
     BEGIN SELECT RAISE(ABORT, 'a forecast may not be rewritten after it is made'); END;",
  ))
  use _ <- result.try(exec_sql(
    db,
    "CREATE TRIGGER IF NOT EXISTS forecast_resolution_is_final
     BEFORE UPDATE ON forecast_ledger
     WHEN OLD.resolved = 1
     BEGIN SELECT RAISE(ABORT, 'a resolved forecast may not be re-resolved'); END;",
  ))
  Ok(rows)
}

/// Record a precommitted prediction. `probability` is the forecast that will
/// later be scored; it is fixed at this moment and cannot be changed.
pub fn record_prediction(
  db: ForecastDb,
  prediction_id: String,
  probability: Float,
  aspect: String,
  timestamp_ns: Int,
) -> Result(Nil, String) {
  query(
    db,
    "INSERT INTO forecast_ledger
       (prediction_id, predicted_prob, observed_outcome, resolved, timestamp_ns, aspect)
     VALUES (?1, ?2, 0, 0, ?3, ?4);",
    [
      dyn_string(prediction_id),
      dyn_float(probability),
      dyn_int(timestamp_ns),
      dyn_string(aspect),
    ],
  )
  |> result.replace(Nil)
}

/// Record the observed outcome for a prediction. Permitted exactly once.
pub fn resolve_prediction(
  db: ForecastDb,
  prediction_id: String,
  observed: Bool,
) -> Result(Nil, String) {
  let outcome = case observed {
    True -> 1
    False -> 0
  }
  query(
    db,
    "UPDATE forecast_ledger SET observed_outcome = ?1, resolved = 1
     WHERE prediction_id = ?2;",
    [dyn_int(outcome), dyn_string(prediction_id)],
  )
  |> result.replace(Nil)
}

fn decode_string(value: Dynamic, field: String) -> Result(String, String) {
  decode.run(value, decode.string)
  |> result.replace_error("forecast_ledger." <> field <> " is not text")
}

fn decode_int(value: Dynamic, field: String) -> Result(Int, String) {
  decode.run(value, decode.int)
  |> result.replace_error("forecast_ledger." <> field <> " is not an integer")
}

/// SQLite may hand back an integer where a REAL column holds a whole number,
/// so a probability decoder that only accepted floats would reject a stored
/// 0 or 1. Both are accepted and normalized to Float.
fn decode_number(value: Dynamic, field: String) -> Result(Float, String) {
  case decode.run(value, decode.float) {
    Ok(f) -> Ok(f)
    Error(_) ->
      case decode.run(value, decode.int) {
        Ok(i) -> Ok(int.to_float(i))
        Error(_) ->
          Error("forecast_ledger." <> field <> " is not a number")
      }
  }
}

fn decode_row(row: List(Dynamic)) -> Result(StoredForecast, String) {
  case row {
    [id, prob, outcome, resolved, ts, aspect] -> {
      use prediction_id <- result.try(decode_string(id, "prediction_id"))
      use predicted_prob <- result.try(decode_number(prob, "predicted_prob"))
      use observed_outcome <- result.try(decode_int(outcome, "observed_outcome"))
      use resolved_flag <- result.try(decode_int(resolved, "resolved"))
      use timestamp_ns <- result.try(decode_int(ts, "timestamp_ns"))
      use aspect_name <- result.try(decode_string(aspect, "aspect"))
      Ok(StoredForecast(
        prediction_id: prediction_id,
        predicted_prob: predicted_prob,
        observed_outcome: observed_outcome == 1,
        resolved: resolved_flag == 1,
        timestamp_ns: timestamp_ns,
        aspect: aspect_name,
      ))
    }
    _ -> Error("forecast_ledger row has unexpected arity")
  }
}

/// Read the ledger back. This is the half that was missing: without it
/// `calculate_calibration` could only score a list held in memory, so nothing
/// persisted could ever be scored.
pub fn load_records(db: ForecastDb) -> Result(List(StoredForecast), String) {
  use rows <- result.try(query(
    db,
    "SELECT prediction_id, predicted_prob, observed_outcome, resolved,
            timestamp_ns, aspect
     FROM forecast_ledger ORDER BY timestamp_ns ASC, prediction_id ASC;",
    [],
  ))
  list.try_map(rows, decode_row)
}

/// Calibration over what is actually stored, with its own denominator.
pub fn calibration_from_db(db: ForecastDb) -> Result(CalibrationResult, String) {
  use records <- result.try(load_records(db))
  Ok(calculate_calibration(records))
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
