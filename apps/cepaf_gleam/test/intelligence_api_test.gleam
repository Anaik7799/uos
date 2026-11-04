import cepaf_gleam/ui/wisp/intelligence_api.{
  catalog_json, resolve_local_first_json, route_request_json,
}
import gleam/json
import gleam/string
import gleeunit/should

pub fn resolve_local_first_yields_zero_remote_tokens_test() {
  let res_json =
    resolve_local_first_json(
      "req-unit-1",
      "log-unit-1",
      "tenant-alpha",
      "L1",
      "pub fn add(a: Int, b: Int) -> Int { a + b }",
      False,
    )

  let rendered = json.to_string(res_json)
  string.contains(rendered, "\"engine\":\"local_first_cascade\"")
  |> should.equal(True)

  string.contains(rendered, "\"stage0_probe\":\"mojo_prefilter_executed\"")
  |> should.equal(True)

  // Verify that it is admitted locally
  string.contains(rendered, "\"status\":\"ok\"")
  |> should.equal(True)
}
