import cepaf_gleam/harness/admission
import cepaf_gleam/harness/development as dev
import cepaf_gleam/harness/files
import cepaf_gleam/harness/mcp
import cepaf_gleam/harness/successor_mcp as successor
import cepaf_gleam/harness/system_feature_census as census
import cepaf_gleam/harness/system_features as features
import cepaf_gleam/mcp/protocol.{type ToolDefinition}
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import gleeunit/should
import system_feature_tracker_test as fixture

pub fn pin(source: census.Source) -> census.Pin {
  case source {
    census.DevelopmentHarness ->
      census.Pin(
        fixture.digest(),
        source,
        [
          census.SourceBinding(
            "apps/cepaf_gleam/manifest.toml",
            "b9727adbbb2bfb167348da0c7eaa8f3dbdda3b4fd49a456dbb031279944a5169",
          ),
          census.SourceBinding(
            "apps/cepaf_gleam/src/cepaf_gleam/harness/mcp.gleam",
            "f17c4f66adefc761995a07080551a9539473f9fc0d83e8d492451fa9f36c46a1",
          ),
          census.SourceBinding(
            "apps/cepaf_gleam/src/cepaf_gleam/harness/development.gleam",
            "6d327a3c4d2b0570e9305adef3154643e84c95a319e83d348554121766bf41c5",
          ),
          census.SourceBinding(
            "apps/cepaf_gleam/src/cepaf_gleam/harness/peers.gleam",
            "aa7841bfb42513979001489bdbca16f0dfd47d81f5b64998575c068abeb91c91",
          ),
          census.SourceBinding(
            "apps/cepaf_gleam/src/cepaf_gleam/harness/tracking.gleam",
            "b2f893348c2c6099db4a027f876c1e06bf5d9e867eca0e03e89ec9e35c8005b5",
          ),
          census.SourceBinding(
            "apps/cepaf_gleam/src/cepaf_gleam/mcp/protocol.gleam",
            "7415b762c8bfafae63ea5d949f5cdf94b5638dacbc8094261d6864edbb8c4405",
          ),
        ],
        21,
        "61837e3d5980303c9b4da9e7e2658581a63f980eba07790be75c5bed2b3e572d",
      )
    census.SuccessorHarness ->
      census.Pin(
        fixture.digest(),
        source,
        [
          census.SourceBinding(
            "apps/cepaf_gleam/manifest.toml",
            "b9727adbbb2bfb167348da0c7eaa8f3dbdda3b4fd49a456dbb031279944a5169",
          ),
          census.SourceBinding(
            "apps/cepaf_gleam/src/cepaf_gleam/harness/successor_mcp.gleam",
            "103b2ba0dacac5cfe461194559d2c7d7a0b08941902694a26bf1e9300b246d46",
          ),
          census.SourceBinding(
            "apps/cepaf_gleam/src/cepaf_gleam/harness/operations.gleam",
            "a295a873146aa18827fc37b6b810589a18c3bcc231a35240c39a69241ffb40b8",
          ),
          census.SourceBinding(
            "apps/cepaf_gleam/src/cepaf_gleam/harness/mcp.gleam",
            "f17c4f66adefc761995a07080551a9539473f9fc0d83e8d492451fa9f36c46a1",
          ),
          census.SourceBinding(
            "apps/cepaf_gleam/src/cepaf_gleam/mcp/protocol.gleam",
            "7415b762c8bfafae63ea5d949f5cdf94b5638dacbc8094261d6864edbb8c4405",
          ),
        ],
        13,
        "db91328be2943f511092ca52e4c198216c53ce58cc7522a7789018e1ab882184",
      )
    _ -> panic as "not a harness source"
  }
}

fn bodies(pin: census.Pin) -> List(#(String, String)) {
  list.map(pin.bindings, fn(binding) {
    let assert Ok(body) = files.read(dev.root, binding.path)
    #(binding.path, body)
  })
}

pub fn actual(source: census.Source) -> census.Snapshot {
  let pin = pin(source)
  let assert Ok(snapshot) = census.extract(pin, bodies(pin))
  snapshot
}

pub fn every_harness_schema_comes_from_its_actual_typed_definition_test() {
  list.each(
    [
      #(
        census.DevelopmentHarness,
        mcp.tool_definitions(),
        "uos-gleam-development-harness",
      ),
      #(
        census.SuccessorHarness,
        successor.tool_definitions(),
        "uos-gleam-successor-harness",
      ),
    ],
    fn(source) {
      list.each(census.entries(actual(source.0)), fn(entry) {
        let assert Ok(tool) =
          list.find(source.1, fn(tool) { tool.name == entry.source_id })
        let assert [endpoint] = entry.feature.endpoints
        entry.feature.title |> should.equal(tool.description)
        endpoint.server |> should.equal(source.2)
        endpoint.name |> should.equal(tool.name)
        endpoint.input_schema
        |> should.equal(Some(files.digest(json.to_string(tool.input_schema))))
      })
    },
  )
}

pub fn both_harness_sources_require_exact_dependencies_and_ids_test() {
  list.each([census.DevelopmentHarness, census.SuccessorHarness], fn(source) {
    let pin = pin(source)
    let bodies = bodies(pin)
    list.each(bodies, fn(selected) {
      census.extract(
        pin,
        list.filter(bodies, fn(body) { body.0 != selected.0 }),
      )
      |> should.be_error
      census.extract(
        pin,
        list.map(bodies, fn(body) {
          case body.0 == selected.0 {
            True -> #(body.0, body.1 <> " ")
            False -> body
          }
        }),
      )
      |> should.be_error
      census.extract(
        census.Pin(
          ..pin,
          bindings: list.filter(pin.bindings, fn(binding) {
            binding.path != selected.0
          }),
        ),
        bodies,
      )
      |> should.be_error
    })
    let assert [first, ..rest] = bodies
    census.extract(pin, rest) |> should.be_error
    census.extract(pin, [first, ..bodies]) |> should.be_error
    census.extract(pin, [#(first.0, first.1 <> " "), ..rest]) |> should.be_error
    census.extract(
      census.Pin(..pin, expected_count: pin.expected_count + 1),
      bodies,
    )
    |> should.be_error
    census.extract(
      census.Pin(..pin, expected_ids_sha256: fixture.digest()),
      bodies,
    )
    |> should.be_error
    let assert Ok(forward) = census.extract(pin, bodies)
    let assert Ok(reverse) =
      census.extract(
        census.Pin(..pin, bindings: list.reverse(pin.bindings)),
        list.reverse(bodies),
      )
    census.encode_manifest(reverse)
    |> should.equal(census.encode_manifest(forward))
  })
}

pub fn harness_census_keeps_both_servers_and_all_34_declarations_test() {
  let development = actual(census.DevelopmentHarness)
  let successor = actual(census.SuccessorHarness)
  let first = census.entries(development)
  let second = census.entries(successor)
  list.map(first, fn(entry) { entry.source_id })
  |> list.sort(string.compare)
  |> should.equal(list.sort(development_names, string.compare))
  list.map(second, fn(entry) { entry.source_id })
  |> list.sort(string.compare)
  |> should.equal(list.sort(successor_names, string.compare))
  let entries = list.append(first, second)
  list.length(list.unique(list.map(entries, fn(entry) { entry.feature.id })))
  |> should.equal(34)
  list.each(entries, fn(entry) {
    let feature = entry.feature
    feature.declared_stage
    |> should.equal(features.Declaration("TOOL_DECLARED_RUNTIME_UNPROBED"))
    feature.owner |> should.equal(None)
    feature.holon |> should.equal(None)
    feature.dependencies |> should.equal(None)
    let assert [endpoint] = feature.endpoints
    endpoint.output_schema |> should.equal(None)
    endpoint.refusal_schema |> should.equal(None)
    endpoint.effects |> should.equal(["unknown"])
  })
  let assert Ok(first_finish) =
    list.find(first, fn(entry) { entry.source_id == "harness_finish" })
  let assert Ok(second_finish) =
    list.find(second, fn(entry) { entry.source_id == "harness_finish" })
  let assert [first_endpoint] = first_finish.feature.endpoints
  let assert [second_endpoint] = second_finish.feature.endpoints
  first_endpoint.server |> should.equal("uos-gleam-development-harness")
  second_endpoint.server |> should.equal("uos-gleam-successor-harness")
  first_endpoint.input_schema |> should.not_equal(second_endpoint.input_schema)
  census.shards(
    fixture.digest(),
    list.map(entries, fn(entry) { entry.feature }),
  )
  |> should.be_ok
}

pub const development_names = [
  "harness_execution_progress", "harness_system_feature_catalog",
  "harness_system_feature_observations", "harness_system_feature_intent",
  "harness_heartbeat", "harness_status", "harness_clock", "harness_read_file",
  "harness_write_file", "harness_build", "harness_test", "harness_risk_refresh",
  "harness_risk_check", "harness_finish", "harness_peers", "harness_peer_read",
  "harness_peer_review", "harness_peer_note", "harness_feature_initialize",
  "harness_feature_sync", "harness_feature_status",
]

pub const successor_names = [
  "harness_status", "harness_clock", "harness_heartbeat", "harness_claim",
  "harness_attach", "harness_release", "harness_read_file", "harness_write_file",
  "harness_build", "harness_test", "harness_assess", "harness_finish",
  "harness_reconcile",
]

fn binding() {
  dev.Binding("development", "fixture", "fixture", "fixture", 1, "fixture", 1)
}

fn successor_state() {
  successor.State(
    admission.Grant(
      "fixture",
      "fixture",
      "fixture",
      "fixture",
      "fixture",
      "fixture",
      "fixture",
      0,
      [],
      "fixture",
      "fixture",
    ),
    True,
    False,
    None,
    False,
  )
}

fn request(method: String) -> String {
  json.object([
    #("jsonrpc", json.string("2.0")),
    #("id", json.int(1)),
    #("method", json.string(method)),
  ])
  |> json.to_string
}

fn wire(definitions: List(ToolDefinition)) -> String {
  json.object([
    #("jsonrpc", json.string("2.0")),
    #("id", json.int(1)),
    #(
      "result",
      json.object([
        #(
          "tools",
          json.array(definitions, fn(tool) {
            json.object([
              #("name", json.string(tool.name)),
              #("description", json.string(tool.description)),
              #("inputSchema", tool.input_schema),
            ])
          }),
        ),
      ]),
    ),
  ])
  |> json.to_string
}

fn error_code(response: Option(String)) -> Int {
  let assert Some(body) = response
  let assert Ok(code) =
    json.parse(
      body,
      decode.subfield(["error", "code"], decode.int, decode.success),
    )
  code
}

pub fn development_listing_is_exact_pre_refactor_wire_and_unchanged_state_test() {
  let state = mcp.State(True, False)
  let #(next, reply) = mcp.handle(binding(), state, request("tools/list"))
  next |> should.equal(state)
  let assert Some(body) = reply
  files.digest(body)
  |> should.equal(
    "6bb79cc1e4ab20dbcd777ee26f925d333e87ba9ca6cad54dc46cf131e33ad46d",
  )
  string.contains(body, "\"outputSchema\"") |> should.be_true()
  string.contains(body, "\"errorSchema\"") |> should.be_true()
  string.contains(body, "\"harness_system_feature_intent\"")
  |> should.be_true()
  list.map(mcp.tool_definitions(), fn(tool) { tool.name })
  |> should.equal(development_names)
}

pub fn successor_listing_is_exact_pre_refactor_wire_and_unchanged_state_test() {
  let state = successor_state()
  let #(next, reply) = successor.handle(state, request("tools/list"))
  next |> should.equal(state)
  let assert Some(body) = reply
  files.digest(body)
  |> should.equal(
    "2bd0b6b5e292783bd30e719c243bd823eb494942bf500c260c5186314f3d3ca6",
  )
  wire(successor.tool_definitions()) |> should.equal(body)
  list.map(successor.tool_definitions(), fn(tool) { tool.name })
  |> should.equal(successor_names)
}

pub fn overlapping_names_keep_different_finish_schemas_test() {
  let development = mcp.tool_definitions()
  let successor = successor.tool_definitions()
  list.filter(development, fn(tool) {
    list.any(successor, fn(peer) { peer.name == tool.name })
  })
  |> list.length
  |> should.equal(8)
  let assert Ok(first) =
    list.find(development, fn(tool) { tool.name == "harness_finish" })
  let assert Ok(second) =
    list.find(successor, fn(tool) { tool.name == "harness_finish" })
  let assert Ok(first_required) =
    json.parse(
      json.to_string(first.input_schema),
      decode.field("required", decode.list(decode.string), decode.success),
    )
  let assert Ok(second_required) =
    json.parse(
      json.to_string(second.input_schema),
      decode.field("required", decode.list(decode.string), decode.success),
    )
  first_required
  |> should.equal(["journal_path", "build_intent_id", "test_intent_id"])
  second_required
  |> should.equal([
    "intent_id",
    "journal_path",
    "build_intent_id",
    "test_intent_id",
    "verification_path",
  ])
}

pub fn listing_preserves_initialization_and_closed_session_refusals_test() {
  let #(state, reply) =
    mcp.handle(binding(), mcp.initial, request("tools/list"))
  state |> should.equal(mcp.initial)
  error_code(reply) |> should.equal(-32_002)
  let before = successor.State(..successor_state(), initialized: False)
  let #(after, reply) = successor.handle(before, request("tools/list"))
  after |> should.equal(before)
  error_code(reply) |> should.equal(-32_002)
  let closed = successor.State(..successor_state(), closed: True)
  let #(after, reply) = successor.handle(closed, request("tools/list"))
  after |> should.equal(closed)
  error_code(reply) |> should.equal(-32_002)
}

pub fn resource_and_prompt_unsupported_is_only_scoped_dispatch_evidence_test() {
  list.each(["resources/list", "prompts/list"], fn(method) {
    let state = mcp.State(True, False)
    let #(after, reply) = mcp.handle(binding(), state, request(method))
    after |> should.equal(state)
    error_code(reply) |> should.equal(-32_601)
    let before = successor_state()
    let #(after, reply) = successor.handle(before, request(method))
    after |> should.equal(before)
    error_code(reply) |> should.equal(-32_601)
  })
}
