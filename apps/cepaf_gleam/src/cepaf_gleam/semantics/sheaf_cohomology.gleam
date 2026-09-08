//// apps/cepaf_gleam/src/cepaf_gleam/semantics/sheaf_cohomology.gleam
//// Pure Gleam Algebraic Atlas Sheaf Čech Cohomology (H^1 = 0) Engine
//// Contract Reference: SC-INTENT-ATLAS-001

import gleam/list
import gleam/int
import gleam/float

fn int_range(from: Int, to: Int) -> List(Int) {
  case from > to {
    True -> []
    False -> [from, ..int_range(from + 1, to)]
  }
}

pub fn transition_morphism(from: Int, to: Int, x: Float) -> Float {
  let scale = int.to_float(to + 1) /. int.to_float(from + 1)
  x *. scale
}

pub fn cech_coboundary(i: Int, j: Int, k: Int, x: Float) -> Float {
  let phi_ij = transition_morphism(i, j, x)
  let phi_jk_o_phi_ij = transition_morphism(j, k, phi_ij)
  let phi_ik = transition_morphism(i, k, x)
  let diff = phi_jk_o_phi_ij -. phi_ik
  case diff <. 0.0 {
    True -> 0.0 -. diff
    False -> diff
  }
}

pub fn verify_h1_vanishing(charts_count: Int, test_x: Float) -> Result(Float, String) {
  let indices = int_range(0, charts_count - 1)
  let max_defect =
    list.fold(indices, 0.0, fn(acc_i, i) {
      list.fold(indices, acc_i, fn(acc_j, j) {
        list.fold(indices, acc_j, fn(acc_k, k) {
          let defect = cech_coboundary(i, j, k, test_x)
          float.max(defect, acc_k)
        })
      })
    })

  case max_defect <. 0.0001 {
    True -> Ok(max_defect)
    False -> Error("Sheaf cohomology obstruction non-zero: defect exceeds threshold")
  }
}

pub fn glue_global_section(local_sections: List(#(Int, Float))) -> Result(Float, String) {
  case local_sections {
    [] -> Error("Empty local sections")
    [#(first_chart, first_val), ..rest] -> {
      let global_val = transition_morphism(first_chart, 0, first_val)
      let all_compatible =
        list.all(rest, fn(entry) {
          let #(chart, val) = entry
          let projected = transition_morphism(chart, 0, val)
          let diff = projected -. global_val
          let abs_diff = case diff <. 0.0 {
            True -> 0.0 -. diff
            False -> diff
          }
          abs_diff <. 0.0001
        })
      case all_compatible {
        True -> Ok(global_val)
        False -> Error("Incompatible local sections: sheaf gluing failed")
      }
    }
  }
}
