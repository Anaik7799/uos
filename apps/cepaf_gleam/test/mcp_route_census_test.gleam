import cepaf_gleam/harness/files
import cepaf_gleam/harness/mcp as dev_mcp
import cepaf_gleam/harness/successor_mcp
import cepaf_gleam/mcp/registry
import cepaf_gleam/mcp/tools
import gleam/json
import gleam/list
import gleam/string
import gleeunit/should

pub fn all_65_public_tools_have_one_owner_test() {
  let public_defs = tools.get_tool_definitions()
  list.length(public_defs) |> should.equal(65)
  list.each(public_defs, fn(def) {
    let res = registry.lookup("public", def.name)
    res |> should.be_ok
    let assert Ok(spec) = res
    spec.route |> should.equal("public")
    spec.name |> should.equal(def.name)
    string.is_empty(spec.owner_task) |> should.be_false
    string.is_empty(spec.family) |> should.be_false
    spec.schema_digest
    |> should.equal(files.digest(json.to_string(def.input_schema)))
  })
}

pub fn private_name_overlap_retains_route_schema_test() {
  let dev_defs = dev_mcp.tool_definitions()
  let succ_defs = successor_mcp.tool_definitions()
  list.length(dev_defs) |> should.equal(21)
  list.length(succ_defs) |> should.equal(15)

  let assert Ok(dev_finish) = registry.lookup("development", "harness_finish")
  let assert Ok(succ_finish) = registry.lookup("successor", "harness_finish")
  dev_finish.route |> should.equal("development")
  succ_finish.route |> should.equal("successor")
  dev_finish.schema_digest |> should.not_equal(succ_finish.schema_digest)
}

pub fn changed_schema_requires_migration_test() {
  let assert Ok(spec) = registry.lookup("public", "plan_status")
  registry.verify_schema_digest(spec, spec.input_schema) |> should.be_ok
  let mutated_schema =
    json.object([
      #("type", json.string("object")),
      #(
        "properties",
        json.object([
          #("unexpected", json.object([#("type", json.string("string"))])),
        ]),
      ),
    ])
  registry.verify_schema_digest(spec, mutated_schema) |> should.be_error
}
