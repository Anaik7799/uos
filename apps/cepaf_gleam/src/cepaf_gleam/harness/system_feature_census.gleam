import cepaf_gleam/a2ui/core_catalog
import cepaf_gleam/a2ui/schema as component_schema
import cepaf_gleam/a2ui/wave1_catalog
import cepaf_gleam/a2ui/wave2_catalog
import cepaf_gleam/ecology/capability_port
import cepaf_gleam/ha/autonomous_capabilities as autonomous
import cepaf_gleam/harness/files
import cepaf_gleam/harness/mcp as development_mcp
import cepaf_gleam/harness/successor_mcp
import cepaf_gleam/harness/system_features as features
import cepaf_gleam/harness/tracking
import cepaf_gleam/knowledge/zigvm_feature_tracker as knowledge
import cepaf_gleam/mcp/protocol.{type ToolDefinition}
import cepaf_gleam/mcp/tools
import cepaf_gleam/sciviz/extension_catalog
import cepaf_gleam/services/max_inference_daemon as max_client
import cepaf_gleam/uos_sup
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub type Source {
  McpTools
  DevelopmentHarness
  SuccessorHarness
  MaxClient
  RootSupervision
  Ecology
  Autonomous
  Extensions
  Knowledge
  Components
}

pub type SourceBinding {
  SourceBinding(path: String, sha256: String)
}

pub type Pin {
  Pin(
    candidate: String,
    source: Source,
    bindings: List(SourceBinding),
    expected_count: Int,
    expected_ids_sha256: String,
  )
}

pub type DeclaredEntry {
  DeclaredEntry(source_id: String, feature: features.Feature)
}

pub opaque type Snapshot {
  Snapshot(
    pin: Pin,
    entries: List(DeclaredEntry),
    catalogs: List(features.Catalog),
  )
}

const source_root = "apps/cepaf_gleam/src/cepaf_gleam/"

fn require(condition: Bool, refusal: String) -> Result(Nil, String) {
  case condition {
    True -> Ok(Nil)
    False -> Error(refusal)
  }
}

pub fn source_name(source: Source) -> String {
  case source {
    McpTools -> "mcp"
    DevelopmentHarness -> "development_mcp"
    SuccessorHarness -> "successor_mcp"
    MaxClient -> "max_client"
    RootSupervision -> "supervision"
    Ecology -> "ecology"
    Autonomous -> "autonomous"
    Extensions -> "extensions"
    Knowledge -> "knowledge"
    Components -> "components"
  }
}

pub fn source_paths(source: Source) -> List(String) {
  let relative = case source {
    McpTools -> ["mcp/tools.gleam", "mcp/protocol.gleam"]
    DevelopmentHarness -> [
      "harness/mcp.gleam",
      "harness/development.gleam",
      "harness/peers.gleam",
      "harness/tracking.gleam",
      "mcp/protocol.gleam",
    ]
    SuccessorHarness -> [
      "harness/successor_mcp.gleam",
      "harness/operations.gleam",
      "harness/mcp.gleam",
      "mcp/protocol.gleam",
    ]
    MaxClient -> ["services/max_inference_daemon.gleam"]
    RootSupervision -> ["uos_sup.gleam"]
    Ecology -> ["ecology/capability_port.gleam"]
    Autonomous -> ["ha/autonomous_capabilities.gleam"]
    Extensions -> ["sciviz/extension_catalog.gleam"]
    Knowledge -> ["knowledge/zigvm_feature_tracker.gleam"]
    Components -> [
      "a2ui/catalog.gleam",
      "a2ui/core_catalog.gleam",
      "a2ui/wave1_catalog.gleam",
      "a2ui/wave2_catalog.gleam",
      "a2ui/schema.gleam",
    ]
  }
  [
    "apps/cepaf_gleam/manifest.toml",
    ..list.map(relative, fn(path) { source_root <> path })
  ]
  |> list.sort(string.compare)
}

fn validate_pin(
  pin: Pin,
  bodies: List(#(String, String)),
) -> Result(Pin, String) {
  use _ <- result.try(require(
    features.valid_digest(pin.candidate)
      && features.valid_digest(pin.expected_ids_sha256)
      && pin.expected_count > 0
      && pin.expected_count <= 512
      && list.length(pin.bindings) <= 8
      && list.length(bodies) <= 8,
    "census_pin_bound",
  ))
  let bindings =
    list.sort(pin.bindings, fn(left, right) {
      string.compare(left.path, right.path)
    })
  let sorted_bodies =
    list.sort(bodies, fn(left, right) { string.compare(left.0, right.0) })
  let paths = source_paths(pin.source)
  use _ <- result.try(require(
    list.map(bindings, fn(binding) { binding.path }) == paths
      && list.map(sorted_bodies, fn(body) { body.0 }) == paths,
    "census_exact_source_set_required",
  ))
  use _ <- result.try(
    list.try_map(list.zip(bindings, sorted_bodies), fn(pair) {
      require(
        features.valid_digest(pair.0.sha256)
          && string.byte_size(pair.1.1) > 0
          && string.byte_size(pair.1.1) <= files.max_bytes
          && files.digest(pair.1.1) == pair.0.sha256,
        "census_source_digest_or_bound",
      )
    }),
  )
  Ok(Pin(..pin, bindings: bindings))
}

fn qualified_id(source: Source, raw: String) -> String {
  let readable = source_name(source) <> "." <> string.lowercase(raw)
  case tracking.valid_feature_id(readable) {
    True -> readable
    False -> source_name(source) <> "." <> files.digest(raw)
  }
}

fn declaration(
  pin: Pin,
  relative: String,
  raw: String,
  title: String,
  claim: String,
  layers: Option(List(Int)),
  endpoints: List(features.Endpoint),
) -> Result(DeclaredEntry, String) {
  use binding <- result.try(
    list.find(pin.bindings, fn(binding) {
      binding.path == source_root <> relative
    })
    |> result.replace_error("census_record_source_unbound"),
  )
  use _ <- result.try(require(
    string.byte_size(raw) > 0
      && string.byte_size(raw) <= 512
      && !string.contains(raw, "\u{0}"),
    "census_source_id_bound",
  ))
  Ok(DeclaredEntry(
    raw,
    features.Feature(
      qualified_id(pin.source, raw),
      title,
      source_name(pin.source) <> "-declarations",
      None,
      None,
      binding.path,
      binding.sha256,
      features.Declaration(claim),
      None,
      endpoints,
      features.aspect_ids(),
      layers,
      [
        "source-record-conservation",
        "no-authority-amplification",
        "shard-conservation",
      ],
      ["t1-tracker"],
    ),
  ))
}

fn component_layer(layer: component_schema.FractalLayer) -> Int {
  case layer {
    component_schema.L0Constitutional -> 0
    component_schema.L1AtomicDebug -> 1
    component_schema.L2Component -> 2
    component_schema.L3Transaction -> 3
    component_schema.L4System -> 4
    component_schema.L5Cognitive -> 5
    component_schema.L6Ecosystem -> 6
    component_schema.L7Federation -> 7
  }
}

fn component_entries(
  pin: Pin,
  relative: String,
  components: List(#(String, component_schema.ComponentSpec)),
) -> Result(List(DeclaredEntry), String) {
  list.try_map(components, fn(entry) {
    use _ <- result.try(require(
      entry.0 == entry.1.component_type,
      "component_key_type_mismatch",
    ))
    declaration(
      pin,
      relative,
      entry.0,
      entry.1.description,
      "COMPONENT_SPECIFICATION",
      Some([component_layer(entry.1.layer)]),
      [],
    )
  })
}

fn harness_entries(
  pin: Pin,
  relative: String,
  server: String,
  definitions: List(ToolDefinition),
) -> Result(List(DeclaredEntry), String) {
  list.try_map(definitions, fn(tool) {
    declaration(
      pin,
      relative,
      tool.name,
      tool.description,
      "TOOL_DECLARED_RUNTIME_UNPROBED",
      None,
      [
        features.Endpoint(
          server,
          features.Tool,
          tool.name,
          Some(files.digest(json.to_string(tool.input_schema))),
          None,
          None,
          ["unknown"],
        ),
      ],
    )
  })
}

fn declared_entries(pin: Pin) -> Result(List(DeclaredEntry), String) {
  case pin.source {
    MaxClient ->
      list.try_map(max_client.all_methods(), fn(method) {
        let name = max_client.method_name(method)
        declaration(
          pin,
          "services/max_inference_daemon.gleam",
          name,
          name,
          "CLIENT_METHOD_DECLARED_TRANSPORT_UNVERIFIED",
          None,
          [],
        )
      })
    DevelopmentHarness ->
      harness_entries(
        pin,
        "harness/mcp.gleam",
        "uos-gleam-development-harness",
        development_mcp.tool_definitions(),
      )
    SuccessorHarness ->
      harness_entries(
        pin,
        "harness/successor_mcp.gleam",
        "uos-gleam-successor-harness",
        successor_mcp.tool_definitions(),
      )
    McpTools ->
      list.try_map(tools.get_tool_definitions(), fn(tool) {
        let claim = case list.contains(tools.unavailable_tools, tool.name) {
          True -> "NO_RUNTIME_BINDING_DECLARED"
          False -> "TOOL_DECLARED_RUNTIME_UNPROBED"
        }
        declaration(
          pin,
          "mcp/tools.gleam",
          tool.name,
          tool.description,
          claim,
          None,
          [
            features.Endpoint(
              "cepaf-unified",
              features.Tool,
              tool.name,
              Some(files.digest(json.to_string(tool.input_schema))),
              None,
              None,
              ["unknown"],
            ),
          ],
        )
      })
    RootSupervision ->
      uos_sup.uos_root_spec().domains
      |> list.flat_map(fn(domain) { domain.children })
      |> list.try_map(fn(child) {
        declaration(
          pin,
          "uos_sup.gleam",
          child,
          child,
          "SUPERVISION_SPECIFICATION",
          None,
          [],
        )
      })
    Ecology ->
      list.try_map(capability_port.all_capabilities, fn(capability) {
        use backend <- result.try(capability_port.backend_for(capability))
        declaration(
          pin,
          "ecology/capability_port.gleam",
          capability,
          capability <> ": " <> capability_port.backend_name(backend),
          "BACKEND_MAPPING_DECLARATION",
          None,
          [],
        )
      })
    Autonomous ->
      autonomous.build_inventory().capabilities
      |> list.try_map(fn(capability) {
        declaration(
          pin,
          "ha/autonomous_capabilities.gleam",
          int.to_string(capability.id),
          capability.name,
          autonomous.score_to_string(capability.score),
          Some([capability.fractal_layer]),
          [],
        )
      })
    Extensions ->
      extension_catalog.all_167_extensions()
      |> list.try_map(fn(extension) {
        declaration(
          pin,
          "sciviz/extension_catalog.gleam",
          extension.name,
          extension.name,
          "EXTERNAL_REFERENCE_METADATA",
          None,
          [],
        )
      })
    Knowledge ->
      knowledge.all_features()
      |> list.try_map(fn(feature) {
        declaration(
          pin,
          "knowledge/zigvm_feature_tracker.gleam",
          feature.id,
          feature.name,
          knowledge.status_to_string(feature.status),
          None,
          [],
        )
      })
    Components -> {
      use core <- result.try(component_entries(
        pin,
        "a2ui/core_catalog.gleam",
        core_catalog.components(),
      ))
      use first <- result.try(component_entries(
        pin,
        "a2ui/wave1_catalog.gleam",
        wave1_catalog.components(),
      ))
      use second <- result.try(component_entries(
        pin,
        "a2ui/wave2_catalog.gleam",
        wave2_catalog.components(),
      ))
      Ok(list.flatten([core, first, second]))
    }
  }
}

fn ids_fingerprint(entries: List(DeclaredEntry)) -> String {
  entries
  |> list.map(fn(entry) { entry.source_id })
  |> list.sort(string.compare)
  |> json.array(json.string)
  |> json.to_string
  |> files.digest
}

pub fn extract(
  pin: Pin,
  bodies: List(#(String, String)),
) -> Result(Snapshot, String) {
  use pin <- result.try(validate_pin(pin, bodies))
  use entries <- result.try(declared_entries(pin))
  let entries =
    list.sort(entries, fn(left, right) {
      string.compare(left.source_id, right.source_id)
    })
  let raw_ids = list.map(entries, fn(entry) { entry.source_id })
  use _ <- result.try(require(
    list.length(entries) == pin.expected_count
      && list.length(list.unique(raw_ids)) == pin.expected_count
      && ids_fingerprint(entries) == pin.expected_ids_sha256,
    "census_record_set_mismatch",
  ))
  use catalogs <- result.try(shards(
    pin.candidate,
    list.map(entries, fn(entry) { entry.feature }),
  ))
  Ok(Snapshot(pin, entries, catalogs))
}

pub fn shards(
  candidate: String,
  declarations: List(features.Feature),
) -> Result(List(features.Catalog), String) {
  use _ <- result.try(require(
    features.valid_digest(candidate)
      && declarations != []
      && list.length(declarations) <= 4096,
    "census_shard_bound",
  ))
  let ids = list.map(declarations, fn(feature) { feature.id })
  use _ <- result.try(require(
    list.length(list.unique(ids)) == list.length(ids),
    "census_duplicate_feature_id",
  ))
  use catalogs <- result.try(
    declarations
    |> list.sort(fn(left, right) { string.compare(left.id, right.id) })
    |> partition(candidate, []),
  )
  use _ <- result.try(require(
    features.catalog_endpoints_compatible(catalogs),
    "census_cross_shard_endpoint_conflict",
  ))
  Ok(catalogs)
}

fn partition(
  declarations: List(features.Feature),
  candidate: String,
  reversed: List(features.Catalog),
) -> Result(List(features.Catalog), String) {
  case declarations {
    [] -> Ok(list.reverse(reversed))
    _ -> {
      let #(current, remaining) = list.split(declarations, 128)
      use catalog <- result.try(features.catalog(candidate, current))
      partition(remaining, candidate, [catalog, ..reversed])
    }
  }
}

pub fn entries(snapshot: Snapshot) -> List(DeclaredEntry) {
  snapshot.entries
}

pub fn catalogs(snapshot: Snapshot) -> List(features.Catalog) {
  snapshot.catalogs
}

pub fn encode_manifest(snapshot: Snapshot) -> String {
  json.object([
    #("schema", json.string("uos.compiled-feature-census.v1")),
    #("adapter", json.string("compiled-declarations.v1")),
    #("source", json.string(source_name(snapshot.pin.source))),
    #("candidate", json.string(snapshot.pin.candidate)),
    #("expected_count", json.int(snapshot.pin.expected_count)),
    #("extracted_count", json.int(list.length(snapshot.entries))),
    #("raw_ids_sha256", json.string(snapshot.pin.expected_ids_sha256)),
    #("selected_record_set_complete", json.bool(True)),
    #("inventory_complete", json.bool(False)),
    #("runtime_availability", json.string("unknown")),
    #("build_source_binding", json.string("external_verification_required")),
    #("effect_authority", json.bool(False)),
    #("system_admission", json.bool(False)),
    #(
      "identity_semantics",
      json.string(
        "raw record identity; namespaces do not deduplicate semantic overlap",
      ),
    ),
    #(
      "endpoint_semantics",
      json.string(
        "declared logical server namespace; not an authenticated session; empty means unmapped",
      ),
    ),
    #(
      "obligation_semantics",
      json.string(
        "17 aspects and adapter laws are review obligations, not feature verification",
      ),
    ),
    #(
      "bindings",
      json.array(snapshot.pin.bindings, fn(binding) {
        json.object([
          #("path", json.string(binding.path)),
          #("sha256", json.string(binding.sha256)),
        ])
      }),
    ),
    #(
      "shards",
      json.array(snapshot.catalogs, fn(catalog) {
        json.object([
          #("catalog_sha256", json.string(features.fingerprint(catalog))),
          #("count", json.int(list.length(features.declarations(catalog)))),
        ])
      }),
    ),
    #(
      "records",
      json.array(snapshot.entries, fn(entry) {
        json.object([
          #("source_id", json.string(entry.source_id)),
          #("feature_id", json.string(entry.feature.id)),
          #("source_path", json.string(entry.feature.source)),
          #(
            "raw_stage",
            json.string(case entry.feature.declared_stage {
              features.Declaration(claim) -> claim
              features.Discovered
              | features.Classified
              | features.Mapped
              | features.Implemented
              | features.Built
              | features.Executed
              | features.Passed
              | features.Verified
              | features.Admitted ->
                features.stage_name(entry.feature.declared_stage)
            }),
          ),
        ])
      }),
    ),
  ])
  |> json.to_string
}
