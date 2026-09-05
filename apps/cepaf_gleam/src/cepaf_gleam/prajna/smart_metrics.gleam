//// [C3I-SIL6-MSTS] <c3i-module><identity><module>cepaf_gleam/prajna/smart_metrics</module>
////   <fsharp-lineage>Cepaf.Prajna.SmartMetrics</fsharp-lineage></identity>
////   <fractal-topology><layer>L5_COGNITIVE</layer></fractal-topology></c3i-module>

import gleam/float
import gleam/int
import gleam/list

pub fn detect_anomaly(
  values: List(Float),
  threshold: Float,
) -> Result(Bool, String) {
  case list.length(values) < 2 {
    True -> Error("Need at least 2 values for anomaly detection")
    False -> {
      let mean = compute_mean(values)
      let std_dev = compute_std_dev(values, mean)
      case std_dev == 0.0 {
        True -> Ok(False)
        False -> {
          let last = last_value(values)
          let z = z_score(last, mean, std_dev)
          Ok(float.absolute_value(z) >. threshold)
        }
      }
    }
  }
}

pub fn moving_average(values: List(Float), window: Int) -> List(Float) {
  let len = list.length(values)
  case window <= 0 || window > len {
    True -> []
    False -> compute_moving_averages(values, window, 0, len - window + 1)
  }
}

pub fn z_score(value: Float, mean: Float, std_dev: Float) -> Float {
  case std_dev == 0.0 {
    True -> 0.0
    False -> { value -. mean } /. std_dev
  }
}

fn compute_mean(values: List(Float)) -> Float {
  let sum = list.fold(values, 0.0, fn(acc, v) { acc +. v })
  let len = int.to_float(list.length(values))
  sum /. len
}

fn compute_std_dev(values: List(Float), mean: Float) -> Float {
  let sum_sq =
    list.fold(values, 0.0, fn(acc, v) {
      let diff = v -. mean
      acc +. diff *. diff
    })
  let variance = sum_sq /. int.to_float(list.length(values))
  sqrt_approx(variance)
}

fn sqrt_approx(x: Float) -> Float {
  case x <=. 0.0 {
    True -> 0.0
    False -> newton_sqrt(x, x /. 2.0, 0)
  }
}

fn newton_sqrt(x: Float, guess: Float, iterations: Int) -> Float {
  case iterations >= 50 {
    True -> guess
    False -> {
      let next = { guess +. x /. guess } /. 2.0
      let diff = float.absolute_value(next -. guess)
      case diff <. 0.0000001 {
        True -> next
        False -> newton_sqrt(x, next, iterations + 1)
      }
    }
  }
}

fn last_value(values: List(Float)) -> Float {
  case list.last(values) {
    Ok(v) -> v
    Error(_) -> 0.0
  }
}

fn compute_moving_averages(
  values: List(Float),
  window: Int,
  index: Int,
  count: Int,
) -> List(Float) {
  case index >= count {
    True -> []
    False -> {
      let window_values = list.take(list.drop(values, index), window)
      let avg = compute_mean(window_values)
      [avg, ..compute_moving_averages(values, window, index + 1, count)]
    }
  }
}
