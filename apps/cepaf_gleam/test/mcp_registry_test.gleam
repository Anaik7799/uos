import cepaf_gleam/harness/value
import cepaf_gleam/mcp/evidence
import cepaf_gleam/mcp/registry
import cepaf_gleam/mcp/schema
import cepaf_gleam/mcp/tools
import cepaf_gleam/mcp/types
import gleam/json
import gleam/list
import gleeunit/should

pub fn listed_tool_has_dispatch_schema_and_owner_test() {
  let listed = tools.get_tool_definitions()
  let registered =
    registry.definitions(types.Legacy20241105, types.DeclaredCatalogView)
  list.length(registered) |> should.equal(65)
  list.each(listed, fn(def) {
    let assert Ok(spec) = registry.lookup("public", def.name)
    spec.name |> should.equal(def.name)
    spec.description |> should.equal(def.description)
  })
}

pub fn backend_error_cannot_decode_as_success_test() {
  let err_json = "{\"error\":\"database_locked\",\"ok\":false}"
  let outcome =
    evidence.classify_backend_payload(
      "public",
      "plan_status",
      err_json,
      "cand-1",
    )
  case outcome {
    types.Refused(err) -> err.code |> should.equal("BACKEND_ERROR")
    _ -> panic as "Backend error payload must never classify as Complete"
  }

  let nested_rpc_err =
    "{\"jsonrpc\":\"2.0\",\"id\":1,\"error\":{\"code\":-32603,\"message\":\"boom\"}}"
  case
    evidence.classify_backend_payload(
      "public",
      "plan_status",
      nested_rpc_err,
      "cand-1",
    )
  {
    types.Refused(err) -> err.code |> should.equal("NESTED_JSONRPC_ERROR")
    _ -> panic as "Nested JSON-RPC error must never classify as Complete"
  }
}

pub fn recursive_local_ref_is_bounded_test() {
  let remote_ref_schema =
    json.object([
      #("$ref", json.string("https://example.com/schema.json")),
    ])
  schema.validate(remote_ref_schema, value.Object([]))
  |> should.be_error

  let cyclic_local_ref_schema =
    json.object([
      #("$ref", json.string("#/$defs/loop")),
      #(
        "$defs",
        json.object([
          #(
            "loop",
            json.object([#("$ref", json.string("#/$defs/loop"))]),
          ),
        ]),
      ),
    ])
  schema.validate(cyclic_local_ref_schema, value.Object([]))
  |> should.be_error

  let valid_schema =
    json.object([
      #("type", json.string("object")),
      #("required", json.array([json.string("query")], fn(x) { x })),
    ])
  schema.validate(valid_schema, value.Object([#("query", value.Text("uos"))]))
  |> should.be_ok
  schema.validate(valid_schema, value.Object([]))
  |> should.be_error
}
