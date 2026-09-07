import cepaf_gleam/ha/forecast_store.{
  Calibrated, StoredForecast, Undetermined, calculate_calibration,
}
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn empty_forecast_undetermined_test() {
  let res = calculate_calibration([])
  case res {
    Undetermined(reason) -> {
      should.be_true(reason != "")
    }
    Calibrated(_, _) -> should.fail()
  }
}

pub fn single_resolved_forecast_test() {
  let f1 =
    StoredForecast(
      prediction_id: "pred-01",
      predicted_prob: 0.9,
      observed_outcome: True,
      resolved: True,
      timestamp_ns: 1000,
      aspect: "build",
    )

  let res = calculate_calibration([f1])
  case res {
    Calibrated(score, count) -> {
      count |> should.equal(1)
      // (0.9 - 1.0)^2 = 0.01
      { score <. 0.011 && score >. 0.009 } |> should.be_true
    }
    Undetermined(_) -> should.fail()
  }
}

pub fn mixed_forecast_calibration_test() {
  let f1 =
    StoredForecast("p1", 0.8, True, True, 1000, "test")
  let f2 =
    StoredForecast("p2", 0.2, False, True, 2000, "test")
  let f3 =
    StoredForecast("p3", 0.5, False, False, 3000, "test") // unresolved

  let res = calculate_calibration([f1, f2, f3])
  case res {
    Calibrated(score, count) -> {
      count |> should.equal(2)
      // ((0.8-1)^2 + (0.2-0)^2) / 2 = (0.04 + 0.04)/2 = 0.04
      { score <. 0.041 && score >. 0.039 } |> should.be_true
    }
    Undetermined(_) -> should.fail()
  }
}

// ---------------------------------------------------------------------
// Persistence round trip and precommitment enforcement (task s4)
//
// The three tests above score a list held in memory. These score what is
// actually stored, and prove the ledger cannot be edited into looking well
// calibrated after the outcomes are known.
// ---------------------------------------------------------------------

@external(erlang, "cepaf_gleam_ffi", "generate_id")
fn generate_id() -> String

fn fresh_db() -> forecast_store.ForecastDb {
  let path = "/tmp/uos-forecast-store-tests-" <> generate_id() <> ".sqlite3"
  let assert Ok(db) = forecast_store.open_db(path)
  let assert Ok(_) = forecast_store.init_schema(db)
  db
}

pub fn record_load_and_score_round_trip_test() {
  let db = fresh_db()
  let assert Ok(Nil) = forecast_store.record_prediction(db, "p1", 1.0, "l3", 10)
  let assert Ok(Nil) = forecast_store.record_prediction(db, "p2", 0.0, "l3", 20)
  let assert Ok(Nil) = forecast_store.record_prediction(db, "p3", 0.5, "l5", 30)

  // Two resolve; p3 stays open and must not enter the denominator.
  let assert Ok(Nil) = forecast_store.resolve_prediction(db, "p1", True)
  let assert Ok(Nil) = forecast_store.resolve_prediction(db, "p2", False)

  let assert Ok(records) = forecast_store.load_records(db)
  records |> list_len |> should.equal(3)

  // Both resolved predictions were perfect, so the Brier score is 0.0 over a
  // denominator of 2, not 3.
  let assert Ok(Calibrated(brier, count)) = forecast_store.calibration_from_db(db)
  count |> should.equal(2)
  brier |> should.equal(0.0)
  forecast_store.close_db(db)
}

pub fn unresolved_only_ledger_is_undetermined_not_zero_test() {
  let db = fresh_db()
  let assert Ok(Nil) = forecast_store.record_prediction(db, "q1", 0.9, "l3", 10)
  // A zero denominator is unavailable, never perfect performance.
  let assert Ok(Undetermined(_)) = forecast_store.calibration_from_db(db)
  forecast_store.close_db(db)
}

pub fn a_forecast_cannot_be_rewritten_after_the_fact_test() {
  let db = fresh_db()
  let assert Ok(Nil) = forecast_store.record_prediction(db, "r1", 0.1, "l3", 10)
  let assert Ok(Nil) = forecast_store.resolve_prediction(db, "r1", True)
  // Scoring badly, so try to move the prediction toward the observed outcome.
  forecast_store.exec_sql(
    db,
    "UPDATE forecast_ledger SET predicted_prob = 1.0 WHERE prediction_id = 'r1';",
  )
  |> should.be_error
  // The stored prediction is unchanged and still scores badly.
  let assert Ok(Calibrated(brier, 1)) = forecast_store.calibration_from_db(db)
  { brier >. 0.8 } |> should.be_true
  forecast_store.close_db(db)
}

pub fn a_resolved_forecast_cannot_be_re_resolved_test() {
  let db = fresh_db()
  let assert Ok(Nil) = forecast_store.record_prediction(db, "s1", 0.2, "l3", 10)
  let assert Ok(Nil) = forecast_store.resolve_prediction(db, "s1", True)
  // Flipping the recorded outcome would turn a bad score into a good one.
  forecast_store.resolve_prediction(db, "s1", False) |> should.be_error
  let assert Ok(Calibrated(brier, 1)) = forecast_store.calibration_from_db(db)
  { brier >. 0.6 } |> should.be_true
  forecast_store.close_db(db)
}

pub fn ledger_rows_cannot_be_deleted_test() {
  let db = fresh_db()
  let assert Ok(Nil) = forecast_store.record_prediction(db, "t1", 0.3, "l3", 10)
  let assert Ok(Nil) = forecast_store.resolve_prediction(db, "t1", True)
  forecast_store.exec_sql(db, "DELETE FROM forecast_ledger;")
  |> should.be_error
  let assert Ok(records) = forecast_store.load_records(db)
  records |> list_len |> should.equal(1)
  forecast_store.close_db(db)
}

fn list_len(items: List(a)) -> Int {
  case items {
    [] -> 0
    [_, ..rest] -> 1 + list_len(rest)
  }
}
