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
