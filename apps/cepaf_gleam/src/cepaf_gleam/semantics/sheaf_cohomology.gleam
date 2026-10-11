//// Bounded numeric chart-consistency observations.
//// A sampled Float residual is not a proof of global sheaf cohomology.
//// Exact reference laws: formal/lean/Telegram_Numeric_Contract.lean.

import gleam/float
import gleam/int
import gleam/list
import gleam/result

pub const max_charts = 10

pub const max_sample = 1.0e12

pub const residual_tolerance = 0.0001

pub opaque type Observation {
  Observation(
    charts: Int,
    comparisons: Int,
    sample: Float,
    maximum_residual: Float,
  )
}

pub fn observation_charts(o: Observation) -> Int {
  o.charts
}

pub fn observation_comparisons(o: Observation) -> Int {
  o.comparisons
}

pub fn observation_sample(o: Observation) -> Float {
  o.sample
}

pub fn observation_residual(o: Observation) -> Float {
  o.maximum_residual
}

fn valid_chart(i: Int) -> Bool {
  i >= 0 && i < max_charts
}

fn valid_sample(x: Float) -> Bool {
  x >=. -1.0e12 && x <=. max_sample
}

fn int_range(from: Int, to: Int) -> List(Int) {
  case from > to {
    True -> []
    False -> [from, ..int_range(from + 1, to)]
  }
}

/// Low-level arithmetic kernel. Call checked_transition for untrusted inputs.
/// Precondition: indices 0..9 and finite bounded sample; not exact Float algebra.
pub fn transition_morphism(from: Int, to: Int, x: Float) -> Float {
  let scale = int.to_float(to + 1) /. int.to_float(from + 1)
  x *. scale
}

pub fn checked_transition(
  from: Int,
  to: Int,
  x: Float,
) -> Result(Float, String) {
  case valid_chart(from) && valid_chart(to) && valid_sample(x) {
    True -> Ok(transition_morphism(from, to, x))
    False -> Error("invalid_numeric_chart_or_sample")
  }
}

/// Low-level residual kernel with the same bounded-input preconditions.
pub fn cech_coboundary(i: Int, j: Int, k: Int, x: Float) -> Float {
  let via_j = transition_morphism(j, k, transition_morphism(i, j, x))
  let direct = transition_morphism(i, k, x)
  float.absolute_value(via_j -. direct)
}

/// Measure this one input over all triples of 1..10 charts; at most 1000 steps.
/// Returns actual residual evidence only when it meets the explicit tolerance.
pub fn observe_cocycle(
  charts_count: Int,
  test_x: Float,
) -> Result(Observation, String) {
  use _ <- result.try(
    case
      charts_count >= 1 && charts_count <= max_charts && valid_sample(test_x)
    {
      True -> Ok(Nil)
      False -> Error("invalid_numeric_chart_count_or_sample")
    },
  )
  let indices = int_range(0, charts_count - 1)
  let max_defect =
    list.fold(indices, 0.0, fn(acc_i, i) {
      list.fold(indices, acc_i, fn(acc_j, j) {
        list.fold(indices, acc_j, fn(acc_k, k) {
          float.max(cech_coboundary(i, j, k, test_x), acc_k)
        })
      })
    })
  case max_defect >=. 0.0 && max_defect <. residual_tolerance {
    True ->
      Ok(Observation(
        charts_count,
        charts_count * charts_count * charts_count,
        test_x,
        max_defect,
      ))
    False -> Error("observed_chart_residual_exceeds_tolerance")
  }
}

/// Compatibility entrypoint. Despite its historical name, this is only a
/// finite numeric observation at test_x, not a theorem that H^1 vanishes.
pub fn verify_h1_vanishing(
  charts_count: Int,
  test_x: Float,
) -> Result(Float, String) {
  observe_cocycle(charts_count, test_x) |> result.map(observation_residual)
}

fn validate_sections(
  sections: List(#(Int, Float)),
  count: Int,
) -> Result(Nil, String) {
  case sections {
    [] -> Ok(Nil)
    [#(chart, value), ..rest] -> {
      case count >= max_charts || !valid_chart(chart) || !valid_sample(value) {
        True -> Error("invalid_numeric_section")
        False -> validate_sections(rest, count + 1)
      }
    }
  }
}

/// Check at most ten observed sections against the first projection.
pub fn glue_global_section(
  local_sections: List(#(Int, Float)),
) -> Result(Float, String) {
  use _ <- result.try(validate_sections(local_sections, 0))
  case local_sections {
    [] -> Error("empty_numeric_sections")
    [#(first_chart, first_val), ..rest] -> {
      let global_val = transition_morphism(first_chart, 0, first_val)
      let compatible =
        list.all(rest, fn(entry) {
          let #(chart, val) = entry
          float.absolute_value(transition_morphism(chart, 0, val) -. global_val)
          <. residual_tolerance
        })
      case compatible {
        True -> Ok(global_val)
        False -> Error("incompatible_numeric_sections")
      }
    }
  }
}
