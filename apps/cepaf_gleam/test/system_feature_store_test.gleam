import cepaf_gleam/harness/files
import cepaf_gleam/harness/system_feature_census as census
import cepaf_gleam/harness/system_feature_sources as sources
import cepaf_gleam/harness/system_feature_store as store
import cepaf_gleam/harness/system_features as features
import cepaf_gleam/harness/tracking
import cepaf_gleam/planning/sa_plan_bridge
import gleam/bit_array
import gleam/crypto
import gleam/dynamic
import gleam/erlang/atom
import gleam/list
import gleam/result
import gleam/string
import gleeunit/should
import system_feature_census_test as census_fixture
import system_feature_sources_test as source_fixture
import system_feature_tracker_test as fixture

@external(erlang, "erlang", "put")
fn put_clock(key: String, times: List(Int)) -> dynamic.Dynamic

@external(erlang, "erlang", "get")
fn get_clock(key: String) -> List(Int)

fn test_clock(times: List(Int)) -> fn() -> Int {
  let key = crypto.strong_random_bytes(16) |> bit_array.base16_encode
  let _ = put_clock(key, times)
  fn() {
    let assert [now, ..remaining] = get_clock(key)
    let _ = put_clock(key, remaining)
    now
  }
}

pub fn slow_fence_cannot_dispatch_after_reserve_expires_test() {
  let runtime =
    store.Runtime(fn() { Ok(Nil) }, fn(_) {
      panic as "Expired reserve must prevent dispatch"
    })
  let wrapped = store.budgeted_with_clock(runtime, test_clock([0, 0, 58_000]))
  wrapped.fence() |> should.equal(Error("feature_store_operation_deadline"))
}

pub fn late_command_result_is_unknown_not_success_test() {
  let runtime =
    store.Runtime(fn() { Ok(Nil) }, fn(_) {
      Ok(#(0, "persisted before transport delay"))
    })
  let wrapped =
    store.budgeted_with_clock(runtime, test_clock([0, 0, 0, 0, 60_001]))
  wrapped.fence() |> should.be_ok
  wrapped.run(["workflow", "start"])
  |> should.equal(Error("feature_store_deadline_outcome_unknown"))
}

@external(erlang, "ecology_capability_ffi", "run_bounded")
fn native_run(
  path: String,
  args: List(String),
  timeout_ms: Int,
) -> Result(#(Int, BitArray), String)

fn cli(database: String, args: List(String)) -> Result(#(Int, String), String) {
  use #(code, bytes) <- result.try(native_run(
    "/home/an/NAS-setup/uos/toolchains/nix-profile/bin/env",
    [
      "UOS_SA_PLAN_DB=" <> database,
      sa_plan_bridge.resolve_sa_plan_binary(),
      ..args
    ],
    3000,
  ))
  use raw <- result.try(
    bit_array.to_string(bytes) |> result.replace_error("fixture_utf8"),
  )
  Ok(#(code, raw))
}

fn private_runtime() -> #(String, store.Runtime) {
  let nonce = crypto.strong_random_bytes(16) |> bit_array.base16_encode
  let database = "/tmp/uos-feature-store-" <> nonce <> ".sqlite3"
  let assert Ok(#(0, _)) =
    cli(database, [
      "plan",
      "create",
      "fixture/features",
      "fixture/features",
      "Private feature store test",
    ])
  #(database, store.Runtime(fn() { Ok(Nil) }, fn(args) { cli(database, args) }))
}

fn source_roundtrip(pin: sources.Pin) -> Nil {
  let #(_, runtime) = private_runtime()
  let catalog = source_fixture.actual_source(pin) |> sources.catalog
  store.publish(runtime, catalog)
  |> should.equal(Ok(features.fingerprint(catalog)))
  store.load(runtime, features.fingerprint(catalog))
  |> should.equal(Ok(catalog))
}

pub fn actual_harness_inventory_persists_test_() -> #(
  atom.Atom,
  Int,
  fn() -> Nil,
) {
  #(atom.create("timeout"), 90, fn() {
    source_roundtrip(source_fixture.harness_pin())
  })
}

pub fn actual_product_inventory_persists_test_() -> #(
  atom.Atom,
  Int,
  fn() -> Nil,
) {
  #(atom.create("timeout"), 90, fn() {
    source_roundtrip(source_fixture.product_pin())
  })
}

pub fn actual_mcp_declarations_persist_without_schema_invention_test_() -> #(
  atom.Atom,
  Int,
  fn() -> Nil,
) {
  #(atom.create("timeout"), 90, fn() {
    let #(_, runtime) = private_runtime()
    let assert [catalog] =
      census_fixture.actual(census.McpTools) |> census.catalogs
    store.publish(runtime, catalog)
    |> should.equal(Ok(features.fingerprint(catalog)))
    store.load(runtime, features.fingerprint(catalog))
    |> should.equal(Ok(catalog))
  })
}

pub fn actual_max_client_declarations_persist_as_unmapped_test_() -> #(
  atom.Atom,
  Int,
  fn() -> Nil,
) {
  #(atom.create("timeout"), 90, fn() {
    let #(_, runtime) = private_runtime()
    let assert [catalog] =
      census_fixture.actual(census.MaxClient) |> census.catalogs
    store.publish(runtime, catalog)
    |> should.equal(Ok(features.fingerprint(catalog)))
    store.load(runtime, features.fingerprint(catalog))
    |> should.equal(Ok(catalog))
  })
}

pub fn real_sa_plan_persists_catalog_and_replay_does_not_duplicate_test() {
  let #(database, runtime) = private_runtime()
  let catalog = fixture.catalog()
  store.publish(runtime, catalog)
  |> should.equal(Ok(features.fingerprint(catalog)))
  let assert Ok(id) = store.record_id("catalog", features.fingerprint(catalog))
  let assert Ok(#(0, before)) =
    cli(database, ["workflow", "history", id, "--format", "json"])
  store.load(runtime, features.fingerprint(catalog))
  |> should.equal(Ok(catalog))
  store.publish(runtime, catalog)
  |> should.equal(Ok(features.fingerprint(catalog)))
  let assert Ok(#(0, after)) =
    cli(database, ["workflow", "history", id, "--format", "json"])
  tracking.parse_rows(before) |> should.equal(tracking.parse_rows(after))
}

pub fn both_harness_servers_persist_without_collapsing_tool_names_test_() -> #(
  atom.Atom,
  Int,
  fn() -> Nil,
) {
  #(atom.create("timeout"), 90, fn() {
    let #(_, runtime) = private_runtime()
    let declarations =
      [census.DevelopmentHarness, census.SuccessorHarness]
      |> list.flat_map(fn(source) {
        census_fixture.actual(source)
        |> census.entries
        |> list.map(fn(entry) { entry.feature })
      })
    let assert Ok([catalog]) = census.shards(fixture.digest(), declarations)
    features.declarations(catalog) |> list.length |> should.equal(36)
    store.publish(runtime, catalog)
    |> should.equal(Ok(features.fingerprint(catalog)))
    store.load(runtime, features.fingerprint(catalog))
    |> should.equal(Ok(catalog))
  })
}

pub fn denied_fence_dominates_all_reads_and_writes_test() {
  let runtime =
    store.Runtime(fn() { Error("denied") }, fn(_) {
      panic as "Backend must not run"
    })
  store.publish(runtime, fixture.catalog()) |> should.equal(Error("denied"))
  store.load(runtime, features.fingerprint(fixture.catalog()))
  |> should.equal(Error("denied"))
}

pub fn malformed_foreign_and_incomplete_history_are_not_absence_test() {
  let started =
    "{\"sequence\":\"0\",\"kind\":\"workflow_started\",\"payload\":\"{}\",\"occurred_at_ns\":\"1\"}"
  list.each(["", "not json", "{}", started], fn(raw) {
    let runtime =
      store.Runtime(fn() { Ok(Nil) }, fn(args) {
        list.take(args, 2) |> should.equal(["workflow", "history"])
        Ok(#(0, raw))
      })
    store.load(runtime, fixture.digest()) |> should.be_error
  })
  let unavailable =
    store.Runtime(fn() { Ok(Nil) }, fn(_) { Ok(#(1, "database unavailable")) })
  store.publish(unavailable, fixture.catalog()) |> should.be_error
  store.load(unavailable, fixture.digest()) |> should.be_error
}

pub fn unknown_create_outcome_is_not_retried_or_published_test() {
  let #(database, runtime) = private_runtime()
  let interrupted =
    store.Runtime(runtime.fence, fn(args) {
      case list.take(args, 2) == ["workflow", "start"] {
        True -> Error("unknown transport outcome")
        False -> runtime.run(args)
      }
    })
  store.publish(interrupted, fixture.catalog())
  |> should.equal(Error("unknown transport outcome"))
  let assert Ok(id) =
    store.record_id("catalog", features.fingerprint(fixture.catalog()))
  let assert Ok(#(code, _)) =
    cli(database, ["workflow", "history", id, "--format", "json"])
  code |> should.equal(1)
}

pub fn preexisting_same_identity_different_payload_is_refused_test() {
  let #(database, runtime) = private_runtime()
  let declaration = fixture.declaration("files.read", [])
  let digest = features.encode_feature(declaration) |> files.digest
  let assert Ok(id) = store.record_id("feature", digest)
  let assert Ok(#(0, _)) =
    cli(database, ["workflow", "start", id, id, "feature-metadata", "{}"])
  store.publish(runtime, fixture.catalog())
  |> should.equal(Error("feature_record_payload_conflict"))
}

pub fn altered_stored_payload_is_refused_test() {
  let #(_, runtime) = private_runtime()
  let catalog = fixture.catalog()
  store.publish(runtime, catalog) |> should.be_ok
  let changed =
    store.Runtime(runtime.fence, fn(args) {
      use #(code, output) <- result.try(runtime.run(args))
      Ok(#(code, string.replace(output, "Read a file", "Forged file")))
    })
  store.load(changed, features.fingerprint(catalog))
  |> should.equal(Error("feature_record_digest_conflict"))
}

pub fn partial_child_persistence_never_publishes_manifest_test() {
  let #(database, runtime) = private_runtime()
  let assert Ok(catalog) =
    features.catalog(fixture.digest(), [
      fixture.declaration("a", []),
      fixture.declaration("b", []),
    ])
  let assert Ok(second_id) =
    store.record_id(
      "feature",
      features.encode_feature(fixture.declaration("b", [])) |> files.digest,
    )
  let failing =
    store.Runtime(runtime.fence, fn(args) {
      case list.contains(args, second_id) {
        True -> Error("fixture write failure")
        False -> runtime.run(args)
      }
    })
  store.publish(failing, catalog)
  |> should.equal(Error("fixture write failure"))
  let assert Ok(id) = store.record_id("catalog", features.fingerprint(catalog))
  let assert Ok(#(code, _)) =
    cli(database, ["workflow", "history", id, "--format", "json"])
  code |> should.equal(1)
  store.publish(runtime, catalog) |> should.be_ok
  store.load(runtime, features.fingerprint(catalog))
  |> should.equal(Ok(catalog))
}

pub fn invalid_identifiers_fail_before_backend_test() {
  let runtime =
    store.Runtime(fn() { panic as "No fence for invalid input" }, fn(_) {
      panic as "No backend for invalid input"
    })
  list.each(["", "--help", "../catalog", string.repeat("a", 65)], fn(digest) {
    store.load(runtime, digest) |> should.be_error
  })
  store.record_id("task", fixture.digest()) |> should.be_error
}

pub fn observations_persist_but_database_registration_is_not_attestation_test() {
  let #(_, runtime) = private_runtime()
  let catalog = fixture.catalog()
  store.publish(runtime, catalog) |> should.be_ok
  let assert Ok(ledger) =
    features.record(features.empty(), fixture.receipt("one"))
  let assert Ok(digest) = store.publish_ledger(runtime, catalog, ledger)
  store.load_ledger(runtime, catalog, digest) |> should.equal(Ok(ledger))
  store.publish_ledger(runtime, catalog, ledger) |> should.equal(Ok(digest))
  let assert Ok(loaded) = store.load_ledger(runtime, catalog, digest)
  features.availability(
    catalog,
    "files.read",
    fixture.endpoint(),
    loaded,
    features.Context(..fixture.context(1500), trusted_receipts: []),
  )
  |> should.equal(features.Unknown)
}

pub fn foreign_ledger_is_refused_before_any_io_test() {
  let runtime =
    store.Runtime(fn() { panic as "Foreign ledger cannot reach fence" }, fn(_) {
      panic as "No backend"
    })
  let assert Ok(ledger) =
    features.record(
      features.empty(),
      features.Observation(..fixture.receipt("one"), feature_id: "foreign"),
    )
  store.publish_ledger(runtime, fixture.catalog(), ledger)
  |> should.equal(Error("foreign_catalog_observation"))
}
