import cepaf_gleam/harness/development as dev
import cepaf_gleam/harness/files
import cepaf_gleam/harness/system_feature_census as census
import cepaf_gleam/harness/system_features as features
import cepaf_gleam/mcp/tools
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import system_feature_inference_test as inference
import system_feature_interfaces_test as interfaces
import system_feature_tracker_test as fixture

pub const sources = [
  census.McpTools,
  census.DevelopmentHarness,
  census.SuccessorHarness,
  census.MaxClient,
  census.RootSupervision,
  census.Ecology,
  census.Autonomous,
  census.Extensions,
  census.Knowledge,
  census.Components,
]

pub fn pin(source: census.Source) -> census.Pin {
  case source {
    census.MaxClient -> inference.pin()
    census.DevelopmentHarness | census.SuccessorHarness ->
      interfaces.pin(source)
    census.McpTools ->
      census.Pin(
        fixture.digest(),
        source,
        [
          census.SourceBinding(
            "apps/cepaf_gleam/src/cepaf_gleam/mcp/tools.gleam",
            "cc3280246b847aac96ad287c03311ef48a559f8a535e3f6a055c6ec21d17c081",
          ),
          census.SourceBinding(
            "apps/cepaf_gleam/src/cepaf_gleam/mcp/protocol.gleam",
            "7415b762c8bfafae63ea5d949f5cdf94b5638dacbc8094261d6864edbb8c4405",
          ),
          census.SourceBinding(
            "apps/cepaf_gleam/manifest.toml",
            "b9727adbbb2bfb167348da0c7eaa8f3dbdda3b4fd49a456dbb031279944a5169",
          ),
        ],
        65,
        "0241247b579e14ae6b1ee3d22ac289076d1790fa56aa1b0540a8e8307effde04",
      )
    census.RootSupervision ->
      census.Pin(
        fixture.digest(),
        source,
        [
          census.SourceBinding(
            "apps/cepaf_gleam/src/cepaf_gleam/uos_sup.gleam",
            "0cc6b9a8e90b9b0b8cf053d01c5f4e7d42a14051418e36a708ca9025a2d239ef",
          ),
          census.SourceBinding(
            "apps/cepaf_gleam/manifest.toml",
            "b9727adbbb2bfb167348da0c7eaa8f3dbdda3b4fd49a456dbb031279944a5169",
          ),
        ],
        26,
        "f30a7bd45b610eb0dd2266d804054c5a9f34c61f5f6949f469f9e98c1e2120cb",
      )
    census.Ecology ->
      census.Pin(
        fixture.digest(),
        source,
        [
          census.SourceBinding(
            "apps/cepaf_gleam/src/cepaf_gleam/ecology/capability_port.gleam",
            "b24e44e5dc01e44eb992a694fafee41bf3a3110df8675e5c3bb5922390e6560e",
          ),
          census.SourceBinding(
            "apps/cepaf_gleam/manifest.toml",
            "b9727adbbb2bfb167348da0c7eaa8f3dbdda3b4fd49a456dbb031279944a5169",
          ),
        ],
        11,
        "1c1fe956c3cf098595e28fa0547233f9314658b54549afa3aa120491d393925c",
      )
    census.Autonomous ->
      census.Pin(
        fixture.digest(),
        source,
        [
          census.SourceBinding(
            "apps/cepaf_gleam/src/cepaf_gleam/ha/autonomous_capabilities.gleam",
            "1b10bec20543a03156192c601fb96ba12db503f5f320f256a3ba4020a6836090",
          ),
          census.SourceBinding(
            "apps/cepaf_gleam/manifest.toml",
            "b9727adbbb2bfb167348da0c7eaa8f3dbdda3b4fd49a456dbb031279944a5169",
          ),
        ],
        75,
        "64389917120ca5e07174c1697ee5efa6526ac9925cafe7fd709ed914480ba216",
      )
    census.Extensions ->
      census.Pin(
        fixture.digest(),
        source,
        [
          census.SourceBinding(
            "apps/cepaf_gleam/src/cepaf_gleam/sciviz/extension_catalog.gleam",
            "7b71077a76afb1697aa8751130bfea1dfa8b513a36b26e69d2b81df0a66c651b",
          ),
          census.SourceBinding(
            "apps/cepaf_gleam/manifest.toml",
            "b9727adbbb2bfb167348da0c7eaa8f3dbdda3b4fd49a456dbb031279944a5169",
          ),
        ],
        167,
        "cd228f3c3beaa41fd76f6d6ad8c4e0f991db68bd9941610426ec76ce3a936dba",
      )
    census.Knowledge ->
      census.Pin(
        fixture.digest(),
        source,
        [
          census.SourceBinding(
            "apps/cepaf_gleam/src/cepaf_gleam/knowledge/zigvm_feature_tracker.gleam",
            "64a3e51444c5f2ce2eee31c8971918abff91d1e82c2c8a4d357c145702fdc918",
          ),
          census.SourceBinding(
            "apps/cepaf_gleam/manifest.toml",
            "b9727adbbb2bfb167348da0c7eaa8f3dbdda3b4fd49a456dbb031279944a5169",
          ),
        ],
        145,
        "cab93ef807266ad9c2df21a825d79d5930c12159c149a7eab1201a3587a1d2dd",
      )
    census.Components ->
      census.Pin(
        fixture.digest(),
        source,
        [
          census.SourceBinding(
            "apps/cepaf_gleam/src/cepaf_gleam/a2ui/catalog.gleam",
            "5533dfea2c892d3941a84ebe8e9ee630889e4ffaba5c3c2ba32c72403b2a39a9",
          ),
          census.SourceBinding(
            "apps/cepaf_gleam/src/cepaf_gleam/a2ui/core_catalog.gleam",
            "b46484b211c81ef891b8b1b2e085621f5954aa47cb1bd8802fa4583979b2c0e6",
          ),
          census.SourceBinding(
            "apps/cepaf_gleam/src/cepaf_gleam/a2ui/wave1_catalog.gleam",
            "edc1a2174c6f9cbd76d190058acdc96f785d0f477063156997d3f7a58f69f60d",
          ),
          census.SourceBinding(
            "apps/cepaf_gleam/src/cepaf_gleam/a2ui/wave2_catalog.gleam",
            "caa5c7be17b12bbcf572728589a968446bfacb8f6516ee44acc6d51ca6db434f",
          ),
          census.SourceBinding(
            "apps/cepaf_gleam/src/cepaf_gleam/a2ui/schema.gleam",
            "fc5778489e8cd7843d391dc49d535c4989a1b46d9566a7b2367043ea895c44fa",
          ),
          census.SourceBinding(
            "apps/cepaf_gleam/manifest.toml",
            "b9727adbbb2bfb167348da0c7eaa8f3dbdda3b4fd49a456dbb031279944a5169",
          ),
        ],
        239,
        "1d3724f84251fc2b904591d41785233ef43f982a00fb5ae4fe3db99e434a6a32",
      )
  }
}

pub fn bodies(pin: census.Pin) -> List(#(String, String)) {
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

pub fn all_ten_actual_sources_conserve_775_records_test() {
  let snapshots = list.map(sources, actual)
  let total = snapshots |> list.flat_map(census.entries) |> list.length
  total |> should.equal(775)
  list.each(snapshots, fn(snapshot) {
    let catalogs = census.catalogs(snapshot)
    list.all(catalogs, fn(catalog) {
      list.length(features.declarations(catalog)) <= 128
    })
    |> should.be_true
    let all_features = list.flat_map(catalogs, features.declarations)
    list.map(all_features, fn(feature) { feature.id })
    |> list.sort(string.compare)
    |> should.equal(
      census.entries(snapshot)
      |> list.map(fn(entry) { entry.feature.id })
      |> list.sort(string.compare),
    )
    list.length(all_features)
    |> should.equal(
      list.length(
        list.unique(list.map(all_features, fn(feature) { feature.id })),
      ),
    )
  })
}

pub fn mcp_input_schemas_are_real_but_output_refusal_effects_are_unknown_test() {
  let snapshot = actual(census.McpTools)
  list.each(census.entries(snapshot), fn(entry) {
    let assert Ok(tool) =
      list.find(tools.get_tool_definitions(), fn(tool) {
        tool.name == entry.source_id
      })
    let assert [endpoint] = entry.feature.endpoints
    endpoint.name |> should.equal(tool.name)
    endpoint.kind |> should.equal(features.Tool)
    endpoint.input_schema
    |> should.equal(Some(files.digest(json.to_string(tool.input_schema))))
    endpoint.output_schema |> should.equal(None)
    endpoint.refusal_schema |> should.equal(None)
    endpoint.effects |> should.equal(["unknown"])
    features.schemas_known(endpoint) |> should.be_false
    entry.feature.owner |> should.equal(None)
  })
}

pub fn unsupported_source_bytes_missing_files_and_duplicate_bindings_are_refused_test() {
  let pin = pin(census.McpTools)
  let bodies = bodies(pin)
  let assert [first, ..rest] = bodies
  census.extract(pin, [#(first.0, first.1 <> " "), ..rest]) |> should.be_error
  census.extract(pin, rest) |> should.be_error
  census.extract(pin, [first, ..bodies]) |> should.be_error
  census.extract(census.Pin(..pin, bindings: []), bodies) |> should.be_error
  census.extract(census.Pin(..pin, expected_count: 54), bodies)
  |> should.be_error
  census.extract(
    census.Pin(..pin, expected_ids_sha256: fixture.digest()),
    bodies,
  )
  |> should.be_error
}

pub fn raw_maturity_claims_and_reference_metadata_never_become_active_test() {
  list.each(
    [census.Autonomous, census.Extensions, census.Knowledge],
    fn(source) {
      let snapshot = actual(source)
      list.each(census.entries(snapshot), fn(entry) {
        case entry.feature.declared_stage {
          features.Declaration(_) -> True
          _ -> False
        }
        |> should.be_true
        entry.feature.owner |> should.equal(None)
        entry.feature.holon |> should.equal(None)
        entry.feature.dependencies |> should.equal(None)
        entry.feature.endpoints |> should.equal([])
      })
      let manifest = census.encode_manifest(snapshot)
      string.contains(manifest, "\"inventory_complete\":false")
      |> should.be_true
      string.contains(manifest, "\"runtime_availability\":\"unknown\"")
      |> should.be_true
      string.contains(manifest, "\"system_admission\":false") |> should.be_true
      string.contains(
        manifest,
        "\"build_source_binding\":\"external_verification_required\"",
      )
      |> should.be_true
    },
  )
}

pub fn component_raw_tuples_are_not_truncated_or_dict_collapsed_test() {
  let snapshot = actual(census.Components)
  list.length(census.entries(snapshot)) |> should.equal(239)
  list.map(census.catalogs(snapshot), fn(catalog) {
    list.length(features.declarations(catalog))
  })
  |> should.equal([128, 111])
  census.entries(snapshot)
  |> list.all(fn(entry) { entry.feature.layers != None })
  |> should.be_true
}

pub fn source_pin_order_is_observationally_irrelevant_test() {
  let pin = pin(census.Components)
  let bodies = bodies(pin)
  let assert Ok(forward) = census.extract(pin, bodies)
  let assert Ok(reverse) =
    census.extract(
      census.Pin(..pin, bindings: list.reverse(pin.bindings)),
      list.reverse(bodies),
    )
  census.encode_manifest(forward)
  |> should.equal(census.encode_manifest(reverse))
}

pub fn shard_partition_is_lossless_deterministic_and_roundtrippable_test() {
  list.each([1, 127, 128, 129, 239, 512], fn(count) {
    let declarations =
      list.repeat(Nil, count)
      |> list.index_map(fn(_, index) {
        fixture.declaration("feature-" <> int.to_string(index), [])
      })
    let assert Ok(forward) = census.shards(fixture.digest(), declarations)
    let assert Ok(reverse) =
      census.shards(fixture.digest(), list.reverse(declarations))
    list.map(forward, features.fingerprint)
    |> should.equal(list.map(reverse, features.fingerprint))
    list.flat_map(forward, features.declarations)
    |> list.length
    |> should.equal(count)
    list.each(forward, fn(catalog) {
      features.parse_catalog(features.encode_catalog(catalog))
      |> should.equal(Ok(catalog))
    })
  })
}

pub fn invalid_oversized_or_cross_shard_dependency_graph_is_refused_test() {
  census.shards(fixture.digest(), []) |> should.be_error
  census.shards(
    fixture.digest(),
    list.repeat(fixture.declaration("same", []), 129),
  )
  |> should.be_error
  census.shards(
    fixture.digest(),
    list.repeat(fixture.declaration("same", []), 4097),
  )
  |> should.be_error
  let declarations =
    list.repeat(Nil, 129)
    |> list.index_map(fn(_, index) {
      let id = string.pad_start(int.to_string(index), 3, "0")
      fixture.declaration(id, case index {
        0 -> ["128"]
        _ -> []
      })
    })
  census.shards(fixture.digest(), declarations) |> should.be_error
}

pub fn endpoint_consistency_is_global_across_shard_boundaries_test() {
  let declarations =
    list.repeat(Nil, 129)
    |> list.index_map(fn(_, index) {
      fixture.declaration(string.pad_start(int.to_string(index), 3, "0"), [])
    })
  let assert Ok(original) = list.last(declarations)
  list.each(
    [
      features.Endpoint(..fixture.endpoint(), effects: ["write"]),
      features.Endpoint(..fixture.endpoint(), output_schema: None),
    ],
    fn(conflict) {
      let changed = features.Feature(..original, endpoints: [conflict])
      census.shards(
        fixture.digest(),
        list.append(list.take(declarations, 128), [changed]),
      )
      |> should.be_error
    },
  )
  let equivalent =
    list.index_map(declarations, fn(feature, index) {
      let effects = case index {
        128 -> ["observe", "read"]
        _ -> ["read", "observe"]
      }
      features.Feature(..feature, endpoints: [
        features.Endpoint(..fixture.endpoint(), effects: effects),
      ])
    })
  census.shards(fixture.digest(), equivalent) |> should.be_ok
}
