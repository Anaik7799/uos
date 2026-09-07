//// Runtime-boundary negative controls: no declared proof or task acceptance.

import cepaf_gleam/mcp/server
import cepaf_gleam/mcp/tools
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{Some}
import gleam/string
import gleeunit/should

pub fn declared_stubs_are_not_operational_tools_test() {
  let names = tools.operational_tool_definitions() |> list.map(fn(t) { t.name })
  names |> list.length |> should.equal(26)
  tools.unavailable_tools
  |> list.each(fn(name) { names |> list.contains(name) |> should.be_false })
}

pub fn gates_and_bridge_never_manufacture_success_test() {
  tools.unavailable_tools
  |> list.each(fn(name) {
    let request =
      json.object([
        #("jsonrpc", json.string("2.0")),
        #("id", json.string("probe")),
        #("method", json.string("tools/call")),
        #(
          "params",
          json.object([
            #("name", json.string(name)),
            #("arguments", json.object([])),
          ]),
        ),
      ])
      |> json.to_string
    let assert Some(response) = server.handle_request_raw(request)
    let decoder = {
      use failed <- decode.subfield(["result", "isError"], decode.bool)
      decode.success(failed)
    }
    json.parse(response, decoder) |> should.equal(Ok(True))
    response |> string.contains("UNAVAILABLE") |> should.be_true
  })
}

pub fn numeric_request_ids_are_preserved_test() {
  let assert Some(response) =
    server.handle_request_raw(
      "{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"tools/list\"}",
    )
  let decoder = {
    use id <- decode.field("id", decode.int)
    decode.success(id)
  }
  json.parse(response, decoder) |> should.equal(Ok(7))
}

pub fn catalog_does_not_claim_live_server_or_fake_session_count_test() {
  let body = tools.catalog_json() |> json.to_string
  body |> string.contains("runtime_not_probed") |> should.be_true
  body |> string.contains("\"active_sessions\":null") |> should.be_true
  body |> string.contains("UNAVAILABLE: no runtime binding") |> should.be_true
}
