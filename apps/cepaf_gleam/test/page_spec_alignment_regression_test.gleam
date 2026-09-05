//// Regression tests for page-spec source alignment.
////
//// Empty live collections such as [] are valid evidence. A page with no
//// pending, in-progress, or blocked tasks is aligned when the source endpoint
//// is present and returns a truthful empty array.

import cepaf_gleam/ui/wisp/router
import gleam/string
import gleeunit/should

pub fn planning_page_spec_accepts_empty_live_task_arrays_test() {
  let body = router.route("/api/v1/page-spec/planning")

  body |> string.contains("\"alignment_score_pct\":100") |> should.be_true()
  body
  |> string.contains("\"alignment_status\":\"ALIGNED\"")
  |> should.be_true()
  body
  |> string.contains("{\"endpoint\":\"plan_list_pending\",\"present\":true}")
  |> should.be_true()
  body
  |> string.contains(
    "{\"endpoint\":\"plan_list_in_progress\",\"present\":true}",
  )
  |> should.be_true()
  body
  |> string.contains("{\"endpoint\":\"plan_list_blocked\",\"present\":true}")
  |> should.be_true()
}
