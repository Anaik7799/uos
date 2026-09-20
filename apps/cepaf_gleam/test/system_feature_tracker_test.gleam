import cepaf_gleam/harness/system_features as features
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import gleeunit/should

pub fn digest() -> String {
  "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
}

pub fn endpoint() -> features.Endpoint {
  features.Endpoint(
    "uos",
    features.Tool,
    "read_file",
    Some(digest()),
    Some(digest()),
    Some(digest()),
    ["read"],
  )
}

pub fn declaration(id: String, dependencies: List(String)) -> features.Feature {
  features.Feature(
    id,
    "Read a file",
    "harness",
    Some("gleam"),
    None,
    "apps/cepaf_gleam/src/cepaf_gleam/harness/files.gleam",
    digest(),
    features.Implemented,
    Some(dependencies),
    [endpoint()],
    features.aspect_ids(),
    Some([0, 4]),
    ["deny-dominance", "no-authority-amplification"],
    ["t1-tracker"],
  )
}

pub fn catalog() -> features.Catalog {
  let assert Ok(catalog) =
    features.catalog(digest(), [declaration("files.read", [])])
  catalog
}

pub fn receipt(id: String) -> features.Observation {
  features.Observation(
    id,
    "files.read",
    features.endpoint_key(endpoint()),
    features.fingerprint(catalog()),
    digest(),
    digest(),
    1000,
    2000,
    features.ProbeSuccess,
    features.RuntimeProbe,
    digest(),
    "fixture-client",
    "stdio",
    "codex-test",
  )
}

pub fn context(now: Int) -> features.Context {
  features.Context(
    digest(),
    digest(),
    now,
    [features.observation_fingerprint(receipt("one"))],
    "fixture-client",
    "stdio",
    "codex-test",
  )
}

pub fn catalog_roundtrip_and_permutation_are_observationally_equal_test() {
  let assert Ok(first) =
    features.catalog(digest(), [
      declaration("parent", []),
      declaration("child", ["parent"]),
    ])
  let assert Ok(second) =
    features.catalog(digest(), [
      declaration("child", ["parent"]),
      declaration("parent", []),
    ])
  features.fingerprint(first) |> should.equal(features.fingerprint(second))
  first
  |> features.encode_catalog
  |> features.parse_catalog
  |> should.equal(Ok(first))
}

pub fn missing_duplicate_cyclic_or_unbounded_inventory_is_refused_test() {
  features.catalog(digest(), []) |> should.be_error
  features.catalog(digest(), [declaration("a", ["absent"])]) |> should.be_error
  features.catalog(digest(), [declaration("a", []), declaration("a", [])])
  |> should.be_error
  features.catalog(digest(), [declaration("a", ["b"]), declaration("b", ["a"])])
  |> should.be_error
  features.catalog(digest(), list.repeat(declaration("a", []), 129))
  |> should.be_error
  features.catalog("unbound", [declaration("a", [])]) |> should.be_error
}

pub fn all_aspects_source_and_remediation_are_required_test() {
  let good = declaration("a", [])
  features.catalog(digest(), [features.Feature(..good, aspects: [])])
  |> should.be_error
  features.catalog(digest(), [features.Feature(..good, source: "../foreign")])
  |> should.be_error
  features.catalog(digest(), [features.Feature(..good, remediation_tasks: [])])
  |> should.be_error
  features.catalog(digest(), [features.Feature(..good, layers: Some([10]))])
  |> should.be_error
}

pub fn declaration_is_not_runtime_availability_test() {
  features.availability(
    catalog(),
    "files.read",
    endpoint(),
    features.empty(),
    context(1500),
  )
  |> should.equal(features.Unknown)
  let assert Ok(ledger) =
    features.record(
      features.empty(),
      features.Observation(..receipt("one"), scope: features.DeclarationOnly),
    )
  features.availability(
    catalog(),
    "files.read",
    endpoint(),
    ledger,
    context(1500),
  )
  |> should.equal(features.Unknown)
}

pub fn missing_schema_is_recorded_without_fabricating_a_fingerprint_test() {
  let raw =
    features.encode_catalog(catalog())
    |> string.replace(
      "\"output_schema\":\"" <> digest() <> "\"",
      "\"output_schema\":null",
    )
    |> string.replace(
      "\"refusal_schema\":\"" <> digest() <> "\"",
      "\"refusal_schema\":null",
    )
  let assert Ok(incomplete) = features.parse_catalog(raw)
  features.encode_catalog(incomplete) |> should.equal(raw)
  let assert [declaration] = features.declarations(incomplete)
  let assert [endpoint] = declaration.endpoints
  let observed =
    features.Observation(
      ..receipt("one"),
      catalog_sha256: features.fingerprint(incomplete),
    )
  let assert Ok(ledger) = features.record(features.empty(), observed)
  let trusted =
    features.Context(..context(1500), trusted_receipts: [
      features.observation_fingerprint(observed),
    ])
  features.availability(incomplete, "files.read", endpoint, ledger, trusted)
  |> should.equal(features.Unknown)
}

pub fn unknown_schema_is_not_an_empty_or_malformed_digest_test() {
  list.each(["", "UNKNOWN", "not-a-hash"], fn(invalid) {
    features.encode_catalog(catalog())
    |> string.replace(
      "\"output_schema\":\"" <> digest() <> "\"",
      "\"output_schema\":\"" <> invalid <> "\"",
    )
    |> features.parse_catalog
    |> should.be_error
  })
}

pub fn unknown_dependencies_and_layers_are_not_empty_declarations_test() {
  let raw =
    features.encode_catalog(catalog())
    |> string.replace("\"dependencies\":[]", "\"dependencies\":null")
    |> string.replace("\"layers\":[0,4]", "\"layers\":null")
    |> string.replace(
      "\"declared_stage\":\"implemented\"",
      "\"declared_stage\":\"declaration:PLANNED\"",
    )
  let assert Ok(parsed) = features.parse_catalog(raw)
  features.encode_catalog(parsed) |> should.equal(raw)
}

pub fn unknown_owner_is_null_and_invalid_known_metadata_is_refused_test() {
  let known = declaration("a", [])
  let assert Ok(unknown) =
    features.catalog(digest(), [features.Feature(..known, owner: None)])
  let encoded = features.encode_catalog(unknown)
  string.contains(encoded, "\"owner\":null") |> should.be_true
  features.parse_catalog(encoded) |> should.equal(Ok(unknown))
  features.catalog(digest(), [features.Feature(..known, owner: Some(""))])
  |> should.be_error
  features.catalog(digest(), [features.Feature(..known, layers: Some([]))])
  |> should.be_error
  features.catalog(digest(), [
    features.Feature(..known, declared_stage: features.Declaration("")),
  ])
  |> should.be_error
}

pub fn usable_requires_trusted_runtime_receipt_and_matching_context_test() {
  let assert Ok(ledger) = features.record(features.empty(), receipt("one"))
  features.availability(
    catalog(),
    "files.read",
    endpoint(),
    ledger,
    context(1500),
  )
  |> should.equal(features.Usable)
  features.availability(
    catalog(),
    "files.read",
    endpoint(),
    ledger,
    features.Context(..context(1500), trusted_receipts: []),
  )
  |> should.equal(features.Unknown)
  features.availability(
    catalog(),
    "files.read",
    endpoint(),
    ledger,
    features.Context(
      ..context(1500),
      authorization_sha256: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    ),
  )
  |> should.equal(features.Unknown)
  features.availability(
    catalog(),
    "files.read",
    endpoint(),
    ledger,
    features.Context(
      ..context(1500),
      candidate: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    ),
  )
  |> should.equal(features.Unknown)
}

pub fn expiry_future_wrong_manifest_and_fixture_never_promote_test() {
  let assert Ok(ledger) = features.record(features.empty(), receipt("one"))
  features.availability(
    catalog(),
    "files.read",
    endpoint(),
    ledger,
    context(2000),
  )
  |> should.equal(features.Stale)
  features.availability(
    catalog(),
    "files.read",
    endpoint(),
    ledger,
    context(999),
  )
  |> should.equal(features.Unknown)
  list.each([features.PrivateFixture, features.DeclarationOnly], fn(scope) {
    let assert Ok(ledger) =
      features.record(
        features.empty(),
        features.Observation(..receipt("one"), scope: scope),
      )
    features.availability(
      catalog(),
      "files.read",
      endpoint(),
      ledger,
      context(1500),
    )
    |> should.equal(features.Unknown)
  })
  let assert Ok(ledger) =
    features.record(
      features.empty(),
      features.Observation(
        ..receipt("one"),
        catalog_sha256: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      ),
    )
  features.availability(
    catalog(),
    "files.read",
    endpoint(),
    ledger,
    context(1500),
  )
  |> should.equal(features.Unknown)
}

pub fn newest_failure_supersedes_success_and_equal_time_conflict_is_unknown_test() {
  let assert Ok(first) = features.record(features.empty(), receipt("one"))
  let assert Ok(second) =
    features.record(
      first,
      features.Observation(
        ..receipt("two"),
        observed_at_ms: 1200,
        outcome: features.ProbeFailed,
      ),
    )
  let trusted =
    features.Context(
      ..context(1500),
      trusted_receipts: list.map(
        features.observations(second),
        features.observation_fingerprint,
      ),
    )
  features.availability(catalog(), "files.read", endpoint(), second, trusted)
  |> should.equal(features.Failing)
  let assert Ok(conflict) =
    features.record(
      first,
      features.Observation(..receipt("two"), outcome: features.ProbeFailed),
    )
  features.availability(
    catalog(),
    "files.read",
    endpoint(),
    conflict,
    context(1500),
  )
  |> should.equal(features.Unknown)
}

pub fn replay_conflict_is_refused_and_merge_laws_hold_test() {
  let assert Ok(first) = features.record(features.empty(), receipt("one"))
  features.record(first, receipt("one")) |> should.equal(Ok(first))
  features.record(
    first,
    features.Observation(..receipt("one"), outcome: features.ProbeFailed),
  )
  |> should.be_error
  let assert Ok(second) = features.record(features.empty(), receipt("two"))
  let assert Ok(third) = features.record(features.empty(), receipt("three"))
  features.merge(first, features.empty()) |> should.equal(Ok(first))
  features.merge(first, first) |> should.equal(Ok(first))
  features.merge(first, second) |> should.equal(features.merge(second, first))
  let assert Ok(left) = features.merge(first, second)
  let assert Ok(right) = features.merge(second, third)
  features.merge(left, third) |> should.equal(features.merge(first, right))
}

pub fn reconciliation_reports_both_missing_and_orphaned_endpoints_test() {
  let other = features.Endpoint(..endpoint(), name: "unknown")
  features.reconcile(catalog(), [other])
  |> should.equal(
    Ok(
      features.Coverage(
        [features.endpoint_key(endpoint())],
        [features.endpoint_key(other)],
        [],
      ),
    ),
  )
  features.reconcile(catalog(), [endpoint(), endpoint()]) |> should.be_error
}

pub fn schema_drift_is_not_hidden_by_matching_endpoint_name_test() {
  let changed =
    features.Endpoint(..endpoint(), input_schema: Some(string.repeat("b", 64)))
  features.reconcile(catalog(), [changed])
  |> should.equal(
    Ok(features.Coverage([], [], [features.endpoint_key(changed)])),
  )
  let second =
    features.Feature(..declaration("second", []), endpoints: [changed])
  features.catalog(digest(), [declaration("first", []), second])
  |> should.be_error
}

pub fn escaped_endpoint_key_must_fit_observation_bound_test() {
  let impossible =
    features.Endpoint(..endpoint(), name: string.repeat("\n", 512))
  let declaration =
    features.Feature(..declaration("escape", []), endpoints: [impossible])
  features.catalog(digest(), [declaration]) |> should.be_error
  let supported = features.Endpoint(..endpoint(), name: string.repeat("x", 512))
  features.catalog(digest(), [
    features.Feature(..declaration, endpoints: [supported]),
  ])
  |> should.be_ok
}

pub fn receipt_locator_does_not_attest_modified_claims_test() {
  list.each(
    [
      features.Observation(..receipt("one"), expires_at_ms: 3000),
      features.Observation(..receipt("one"), observed_at_ms: 1100),
      features.Observation(..receipt("one"), client: "other-client"),
      features.Observation(..receipt("one"), transport: "http"),
      features.Observation(..receipt("one"), actor: "other-actor"),
      features.Observation(..receipt("one"), outcome: features.ProbeAbsent),
    ],
    fn(changed) {
      let assert Ok(ledger) = features.record(features.empty(), changed)
      features.availability(
        catalog(),
        "files.read",
        endpoint(),
        ledger,
        context(1500),
      )
      |> should.equal(features.Unknown)
    },
  )
}

pub fn newer_untrusted_or_future_observation_never_resurrects_old_green_test() {
  let assert Ok(first) = features.record(features.empty(), receipt("one"))
  list.each([1200, 1600], fn(observed) {
    let assert Ok(ledger) =
      features.record(
        first,
        features.Observation(..receipt("two"), observed_at_ms: observed),
      )
    features.availability(
      catalog(),
      "files.read",
      endpoint(),
      ledger,
      context(1500),
    )
    |> should.equal(features.Unknown)
  })
}

pub fn observation_roundtrip_and_bounds_are_checked_test() {
  let observation = receipt("one")
  observation
  |> features.encode_observation
  |> features.parse_observation
  |> should.equal(Ok(observation))
  features.record(
    features.empty(),
    features.Observation(..observation, observed_at_ms: 0),
  )
  |> should.be_error
  features.record(
    features.empty(),
    features.Observation(..observation, expires_at_ms: 1000),
  )
  |> should.be_error
  features.record(
    features.empty(),
    features.Observation(..observation, expires_at_ms: 3_601_001),
  )
  |> should.be_error
  observation
  |> features.encode_observation
  |> string.replace("runtime_probe", "invented")
  |> features.parse_observation
  |> should.be_error
  features.parse_observation(string.repeat(" ", 16_385)) |> should.be_error
}

fn reference_ledger(
  items: List(features.Observation),
) -> Result(List(features.Observation), Nil) {
  list.try_fold(items, [], fn(saved: List(features.Observation), observation) {
    case list.find(saved, fn(existing) { existing.id == observation.id }) {
      Error(_) -> Ok([observation, ..saved])
      Ok(existing) if existing == observation -> Ok(saved)
      Ok(_) -> Error(Nil)
    }
  })
  |> result.map(fn(items) {
    list.sort(items, fn(left, right) { string.compare(left.id, right.id) })
  })
}

pub fn independent_list_oracle_agrees_with_dictionary_interpreter_test() {
  list.repeat(Nil, 64)
  |> list.index_map(fn(_, seed) {
    let observations =
      list.repeat(Nil, 6)
      |> list.index_map(fn(_, index) {
        let identity = int.to_string({ seed + index } % 3)
        features.Observation(
          ..receipt("receipt-" <> identity),
          observed_at_ms: 1000 + { seed * index } % 3,
        )
      })
    let actual =
      list.try_fold(observations, features.empty(), features.record)
      |> result.map(features.observations)
      |> result.replace_error(Nil)
    actual |> should.equal(reference_ledger(observations))
    let reversed = list.reverse(observations)
    list.try_fold(reversed, features.empty(), features.record)
    |> result.map(features.observations)
    |> result.replace_error(Nil)
    |> should.equal(reference_ledger(reversed))
  })
  |> list.length
  |> should.equal(64)
}

pub fn maximum_count_large_catalog_roundtrips_within_total_bound_test() {
  let laws =
    list.repeat(Nil, 64)
    |> list.index_map(fn(_, index) {
      int.to_string(index) <> string.repeat("x", 230)
    })
  let entries =
    list.repeat(Nil, 128)
    |> list.index_map(fn(_, index) {
      features.Feature(
        ..declaration("feature-" <> int.to_string(index), []),
        laws: laws,
      )
    })
  let assert Ok(catalog) = features.catalog(digest(), entries)
  let encoded = features.encode_catalog(catalog)
  { string.byte_size(encoded) <= 2_097_152 } |> should.be_true
  features.parse_catalog(encoded) |> should.equal(Ok(catalog))
}
