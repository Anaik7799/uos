import cepaf_gleam/ui/wisp/router.{route}
import gleam/string
import gleeunit/should

pub fn wisp_ai_resolve_endpoint_test() {
  let res = route("/api/v1/ai/resolve?q=pub%20fn%20hello()%20->%20Int%20{%201%20}")

  string.contains(res, "\"engine\":\"local_first_cascade\"")
  |> should.equal(True)

  string.contains(res, "\"stage0_probe\":\"mojo_prefilter_executed\"")
  |> should.equal(True)

  string.contains(res, "\"status\":\"ok\"")
  |> should.equal(True)
}
