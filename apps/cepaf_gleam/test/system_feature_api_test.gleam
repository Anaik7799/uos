import cepaf_gleam/harness/development as dev
import cepaf_gleam/harness/mcp
import cepaf_gleam/harness/system_feature_api as api
import cepaf_gleam/harness/system_feature_intent as intent
import cepaf_gleam/harness/system_features as features
import cepaf_gleam/harness/value
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{Some}
import gleam/string
import gleeunit/should
import system_feature_tracker_test as fixture

fn arguments(catalog: features.Catalog, offset: String) -> value.Value {
  value.Object([
    #("catalog_sha256", value.Text(features.fingerprint(catalog))),
    #("offset", value.Text(offset)),
  ])
}

fn observation_arguments(
  catalog: features.Catalog,
  offset: String,
) -> value.Value {
  value.Object([
    #("catalog_sha256", value.Text(features.fingerprint(catalog))),
    #("ledger_sha256", value.Text(fixture.digest())),
    #("offset", value.Text(offset)),
  ])
}

pub fn paged_query_is_metadata_only_and_has_no_false_availability_test() {
  let entries =
    list.repeat(Nil, 10)
    |> list.index_map(fn(_, index) {
      fixture.declaration("feature-" <> int.to_string(index), [])
    })
  let assert Ok(catalog) = features.catalog(fixture.digest(), entries)
  let assert Ok(page) =
    api.query(arguments(catalog, "0"), fn() { Ok(Nil) }, fn(_) { Ok(catalog) })
  let assert Ok(parsed) = json.parse(json.to_string(page), value.decoder())
  value.get(parsed, "count") |> should.equal(Ok(value.Integer(10)))
  value.get(parsed, "next_offset") |> should.equal(Ok(value.Integer(8)))
  value.get(parsed, "inventory_complete")
  |> should.equal(Ok(value.Boolean(False)))
  let assert Ok(value.Array(rows)) = value.get(parsed, "features")
  list.length(rows) |> should.equal(8)
  list.each(rows, fn(row) {
    value.get(row, "mcp_availability")
    |> should.equal(Ok(value.Text("unknown")))
  })
  let assert Ok(last) =
    api.query(arguments(catalog, "8"), fn() { Ok(Nil) }, fn(_) { Ok(catalog) })
  let assert Ok(parsed) = json.parse(json.to_string(last), value.decoder())
  value.get(parsed, "next_offset") |> should.equal(Ok(value.Null))
  let assert Ok(value.Array(rows)) = value.get(parsed, "features")
  list.length(rows) |> should.equal(2)
}

pub fn strict_query_rejects_injection_noncanonical_offset_and_foreign_readback_test() {
  let catalog = fixture.catalog()
  list.each(
    [
      value.Object([]),
      value.set(arguments(catalog, "0"), "database", value.Text("foreign")),
      arguments(catalog, "-1"),
      arguments(catalog, "01"),
      arguments(catalog, "129"),
      value.set(arguments(catalog, "0"), "offset", value.Integer(0)),
    ],
    fn(args) {
      api.query(args, fn() { panic as "Invalid arguments before fence" }, fn(_) {
        panic as "No read"
      })
      |> should.be_error
    },
  )
  let assert Ok(other) =
    features.catalog(fixture.digest(), [fixture.declaration("different", [])])
  api.query(arguments(catalog, "0"), fn() { Ok(Nil) }, fn(_) { Ok(other) })
  |> should.equal(Error("feature_query_catalog_mismatch"))
}

pub fn denied_query_dominates_read_and_unavailable_is_not_empty_success_test() {
  let args = arguments(fixture.catalog(), "0")
  api.query(args, fn() { Error("denied") }, fn(_) {
    panic as "No read after denied fence"
  })
  |> should.equal(Error("denied"))
  api.query(args, fn() { Ok(Nil) }, fn(_) { Error("unavailable") })
  |> should.equal(Error("unavailable"))
}

pub fn observations_query_reads_persisted_ledger_without_promoting_availability_test() {
  let catalog = fixture.catalog()
  let assert Ok(ledger) =
    features.record(features.empty(), fixture.receipt("one"))
  let assert Ok(body) =
    api.observations(
      observation_arguments(catalog, "0"),
      fn() { Ok(Nil) },
      fn(_) { Ok(catalog) },
      fn(_, _) { Ok(ledger) },
    )
  let assert Ok(parsed) = json.parse(json.to_string(body), value.decoder())
  value.get(parsed, "count") |> should.equal(Ok(value.Integer(1)))
  value.get(parsed, "availability")
  |> should.equal(Ok(value.Text("unknown_without_authorized_context")))
  value.get(parsed, "system_admission")
  |> should.equal(Ok(value.Boolean(False)))
}

pub fn observations_query_refuses_unavailable_ledger_test() {
  let catalog = fixture.catalog()
  api.observations(
    observation_arguments(catalog, "0"),
    fn() { Ok(Nil) },
    fn(_) { Ok(catalog) },
    fn(_, _) { Error("ledger_unavailable") },
  )
  |> should.equal(Error("ledger_unavailable"))
}

pub fn declarative_intent_decision_is_pure_and_denies_authority_test() {
  let args =
    value.Object([
      #("intent", value.Text("observations_read")),
      #("catalog_sha256", value.Text(fixture.digest())),
      #("ledger_sha256", value.Text(fixture.digest())),
      #("offset", value.Text("0")),
    ])
  let assert Ok(decision) = intent.decide(args)
  let encoded = intent.encode(decision) |> json.to_string
  encoded
  |> string.contains("uos.system-feature-intent-decision.v1")
  |> should.be_true
  encoded |> string.contains("\"effect_authority\":false") |> should.be_true
  encoded |> string.contains("\"system_admission\":false") |> should.be_true
}

pub fn declarative_intent_rejects_unknown_and_noncanonical_inputs_test() {
  let base =
    value.Object([
      #("intent", value.Text("mutate")),
      #("catalog_sha256", value.Text(fixture.digest())),
      #("ledger_sha256", value.Text(fixture.digest())),
      #("offset", value.Text("01")),
    ])
  intent.decide(base) |> should.be_error
  intent.decide(value.set(base, "offset", value.Text("0"))) |> should.be_error
  intent.decide(value.set(
    value.set(base, "intent", value.Text("catalog_read")),
    "extra",
    value.Text("x"),
  ))
  |> should.be_error
}

pub fn declarative_intent_replay_is_idempotent_and_conflicts_refuse_test() {
  let args =
    value.Object([
      #("intent", value.Text("catalog_read")),
      #("catalog_sha256", value.Text(fixture.digest())),
      #("ledger_sha256", value.Text(fixture.digest())),
      #("offset", value.Text("0")),
    ])
  let assert Ok(first) = intent.decide(args)
  intent.combine(first, first) |> should.equal(Ok(first))
  let assert Ok(second) =
    intent.decide(value.set(args, "intent", value.Text("observations_read")))
  intent.combine(first, second) |> should.be_error
}

pub fn mcp_lists_catalog_tool_but_unbound_session_cannot_read_test() {
  let binding =
    dev.Binding(
      "development",
      "unbound/plan",
      "unbound",
      "fixture",
      1,
      "fixture",
      1,
    )
  let assert #(state, Some(_)) =
    mcp.handle(
      binding,
      mcp.initial,
      "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\"}",
    )
  let assert #(_, Some(discovery)) =
    mcp.handle(
      binding,
      state,
      "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/list\"}",
    )
  discovery
  |> string.contains("harness_system_feature_catalog")
  |> should.be_true
  discovery
  |> string.contains("harness_system_feature_intent")
  |> should.be_true
  let request =
    json.object([
      #("jsonrpc", json.string("2.0")),
      #("id", json.int(3)),
      #("method", json.string("tools/call")),
      #(
        "params",
        json.object([
          #("name", json.string("harness_system_feature_catalog")),
          #("arguments", value.encode(arguments(fixture.catalog(), "0"))),
        ]),
      ),
    ])
    |> json.to_string
  let assert #(_, Some(denied)) = mcp.handle(binding, state, request)
  denied |> string.contains("\"isError\":true") |> should.be_true
  denied |> string.contains("feature_store_task_scope") |> should.be_true
  denied |> string.contains("mcp_availability") |> should.be_false
}
