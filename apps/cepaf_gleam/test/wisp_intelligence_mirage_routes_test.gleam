//// Wisp Intelligence & Mirage Telemetry Routes Unit Tests
//// STAMP: SC-GLM-UI-001, SC-ROUTING-001, SC-MIRAGE-PROD-001

import cepaf_gleam/ui/wisp/router
import gleeunit/should

pub fn wisp_intelligence_catalog_route_test() {
  let response = router.route("/api/v1/intelligence/catalog")
  response |> should.not_equal("")
}

pub fn wisp_intelligence_route_test() {
  let response = router.route("/api/v1/intelligence/route")
  response |> should.not_equal("")
}

pub fn wisp_mirage_telemetry_route_test() {
  let response = router.route("/api/v1/mirage/telemetry")
  response |> should.not_equal("")
}
