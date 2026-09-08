import indrajaal/homeostasis_http
import gleam/http/response
import gleam/string
import gleeunit/should

pub fn unavailable_is_service_unavailable_and_uncacheable_test() {
  let response = homeostasis_http.snapshot_response()
  response.status |> should.equal(503)
  response.get_header(response, "cache-control") |> should.equal(Ok("no-store"))
  response.get_header(response, "content-type") |> should.equal(Ok("application/json; charset=utf-8"))
}

pub fn document_is_actual_homeostasis_and_executable_bridge_test() {
  let document = homeostasis_http.document()
  string.contains(document, "Homeostasis evidence | UOS") |> should.be_true()
  string.contains(document, "UNAVAILABLE") |> should.be_true()
  string.contains(document, "<script>(function()") |> should.be_true()
  string.contains(document, "&lt;0") |> should.be_false()
  string.contains(document, "Status: ONLINE") |> should.be_false()
  homeostasis_http.page_response().status |> should.equal(200)
}
