//// =============================================================================
//// [C3I-TEST-FIXTURE] Private HTTP Fixture for Candidate Telemetry Responses
//// =============================================================================
//// Verifies exact candidate HTTP endpoint responses through Wisp router.

import cepaf_gleam/ui/wisp/router
import gleam/dynamic/decode
import gleam/json
import gleam/string
import gleeunit/should

pub fn private_http_health_freshness_candidate_test() {
  let response = router.route("/api/v1/health/freshness")

  // Must not be empty or generic error
  { string.length(response) > 20 } |> should.be_true()

  // Must NOT falsely claim all_wiring_functional = true without ws evidence
  response
  |> string.contains("\"all_wiring_functional\":false")
  |> should.be_true()
  response
  |> string.contains("\"ws_planning_active\":false")
  |> should.be_true()
  response
  |> string.contains("\"ws_dashboard_active\":false")
  |> should.be_true()
  response
  |> string.contains("\"ws_planning_availability\":\"unknown\"")
  |> should.be_true()

  // Must NOT falsely claim freshness without verified timestamp provenance
  { response |> string.contains("\"staleness\":\"fresh\"") }
  |> should.be_false()

  // Must parse as valid JSON with required schema fields
  let decoder = {
    use page <- decode.field("page", decode.string)
    use staleness <- decode.field("staleness", decode.string)
    use all_wiring <- decode.field("all_wiring_functional", decode.bool)
    use runtime_loaded <- decode.field("runtime_loaded", decode.bool)
    use ws_plan <- decode.field("ws_planning_active", decode.bool)
    decode.success(#(page, staleness, all_wiring, runtime_loaded, ws_plan))
  }

  case json.parse(response, decoder) {
    Ok(#(page, staleness, all_wiring, _runtime_loaded, ws_plan)) -> {
      page |> should.equal("Data Freshness")
      { staleness == "unavailable" || staleness == "unknown" }
      |> should.be_true()
      all_wiring |> should.be_false()
      ws_plan |> should.be_false()
    }
    Error(_) -> panic as "Freshness response failed JSON decoding"
  }
}

pub fn private_http_health_candidate_test() {
  let response = router.route("/health")

  // Must contain threat_level to satisfy request guard
  response |> string.contains("\"threat_level\"") |> should.be_true()

  // Verify /api/health alias behaves identically in structure
  let alias_response = router.route("/api/health")
  alias_response |> string.contains("\"threat_level\"") |> should.be_true()

  // This fixture deliberately has no native library. Missing observation is
  // unavailable, and never evidence that the underlying service is healthy.
  response |> should.equal(alias_response)
  response |> string.contains("\"runtime_loaded\":false") |> should.be_true()
  response
  |> string.contains("\"telemetry_status\":\"unavailable\"")
  |> should.be_true()
  response |> string.contains("\"status\":\"ok\"") |> should.be_false()
}

pub fn private_http_snapshot_candidate_test() {
  let response = router.route("/api/v1/system/snapshot")

  // Must contain snapshot with health and freshness components
  response |> string.contains("\"snapshot\"") |> should.be_true()
  // Freshness must NOT falsely claim fresh
  { response |> string.contains("\"staleness\":\"fresh\"") }
  |> should.be_false()
}
