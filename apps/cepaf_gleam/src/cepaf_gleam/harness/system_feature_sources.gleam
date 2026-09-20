import cepaf_gleam/harness/files
import cepaf_gleam/harness/system_features as features
import cepaf_gleam/harness/tracking
import cepaf_gleam/harness/value
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub type Source {
  HarnessCatalog
  ProductManifest
}

pub type Pin {
  Pin(
    candidate: String,
    source: Source,
    sha256: String,
    expected_ids: List(String),
  )
}

pub type SourceRecord {
  SourceRecord(source_id: String, feature_id: String, raw_stage: String)
}

pub opaque type Snapshot {
  Snapshot(pin: Pin, records: List(SourceRecord), catalog: features.Catalog)
}

pub fn source_path(source: Source) -> String {
  case source {
    HarnessCatalog ->
      "governance/capability-inventory/20260909-0412-harness-feature-catalog.json"
    ProductManifest ->
      "governance/capability-inventory/20260907-1837-agentic-product-manifest.json"
  }
}

fn require(condition: Bool, refusal: String) -> Result(Nil, String) {
  case condition {
    True -> Ok(Nil)
    False -> Error(refusal)
  }
}

fn text(object: value.Value, key: String) -> Result(String, String) {
  case value.get(object, key) {
    Ok(value.Text(text)) -> Ok(text)
    _ -> Error("source_text_required:" <> key)
  }
}

fn schema(source: Source) -> String {
  case source {
    HarnessCatalog -> "uos.harness-feature-catalog.v1"
    ProductManifest -> "uos.product-catalog/v1"
  }
}

fn prefix(source: Source) -> String {
  case source {
    HarnessCatalog -> "harness."
    ProductManifest -> "product."
  }
}

fn declaration(
  pin: Pin,
  id: String,
  title: String,
  claim: String,
  dependencies: Option(List(String)),
  layers: Option(List(Int)),
) -> #(SourceRecord, features.Feature) {
  let qualified = prefix(pin.source) <> string.lowercase(id)
  #(
    SourceRecord(id, qualified, claim),
    features.Feature(
      qualified,
      title,
      case pin.source {
        HarnessCatalog -> "harness-declarations"
        ProductManifest -> "product-declarations"
      },
      None,
      None,
      source_path(pin.source),
      pin.sha256,
      features.Declaration(claim),
      dependencies,
      [],
      features.aspect_ids(),
      layers,
      ["source-record-conservation", "no-authority-amplification"],
      ["t1-tracker"],
    ),
  )
}

fn harness(
  pin: Pin,
  body: String,
  root: value.Value,
) -> Result(List(#(SourceRecord, features.Feature)), String) {
  use version <- result.try(text(root, "schema_version"))
  use _ <- result.try(require(
    version == schema(pin.source),
    "source_schema_mismatch",
  ))
  use catalog <- result.try(tracking.parse_catalog(body))
  list.try_map(catalog.features, fn(feature) {
    use _ <- result.try(require(
      list.contains(
        ["PLANNED", "MAPPED", "IMPLEMENTED", "EXECUTED"],
        feature.stage,
      ),
      "unsupported_harness_stage",
    ))
    Ok(declaration(
      pin,
      feature.id,
      feature.title,
      feature.stage,
      Some(list.map(feature.dependencies, fn(id) { prefix(pin.source) <> id })),
      None,
    ))
  })
}

fn product_layer(record: value.Value) -> Result(Option(List(Int)), String) {
  case value.get(record, "fractal_layer") {
    Error("missing_field:fractal_layer") | Ok(value.Null) -> Ok(None)
    Ok(value.Text(layer)) -> {
      use _ <- result.try(require(
        string.byte_size(layer) == 2 && string.starts_with(layer, "L"),
        "source_layer_invalid",
      ))
      use number <- result.try(
        int.parse(string.drop_start(layer, 1))
        |> result.replace_error("source_layer_invalid"),
      )
      use _ <- result.try(require(
        number >= 0 && number <= 9,
        "source_layer_invalid",
      ))
      Ok(Some([number]))
    }
    _ -> Error("source_layer_invalid")
  }
}

fn product(
  pin: Pin,
  root: value.Value,
) -> Result(List(#(SourceRecord, features.Feature)), String) {
  use version <- result.try(text(root, "schema"))
  use _ <- result.try(require(
    version == schema(pin.source),
    "source_schema_mismatch",
  ))
  use entries <- result.try(case value.get(root, "features") {
    Ok(value.Array(entries)) -> Ok(entries)
    _ -> Error("source_features_array_required")
  })
  use _ <- result.try(require(
    entries != [] && list.length(entries) <= 128,
    "source_record_bound",
  ))
  list.try_map(entries, fn(record) {
    use id <- result.try(text(record, "id"))
    use title <- result.try(text(record, "name"))
    use claim <- result.try(text(record, "status"))
    use admission <- result.try(text(record, "admission_status"))
    use _ <- result.try(require(
      list.contains(["MAPPED", "REVIEWED"], claim)
        && admission == "NOT_ADMITTED",
      "unsupported_product_stage_or_admission",
    ))
    use _ <- result.try(case value.get(record, "dependencies") {
      Error("missing_field:dependencies") -> Ok(Nil)
      _ -> Error("product_dependency_schema_changed")
    })
    use layers <- result.try(product_layer(record))
    Ok(declaration(pin, id, title, claim, None, layers))
  })
}

pub fn extract(pin: Pin, body: String) -> Result(Snapshot, String) {
  use _ <- result.try(require(
    features.valid_digest(pin.candidate)
      && features.valid_digest(pin.sha256)
      && string.byte_size(body) > 0
      && string.byte_size(body) <= 1_048_576
      && pin.expected_ids != []
      && list.length(pin.expected_ids) <= 128
      && list.length(list.unique(pin.expected_ids))
      == list.length(pin.expected_ids)
      && list.all(pin.expected_ids, fn(id) {
      string.byte_size(id) <= 64
      && tracking.valid_feature_id(string.lowercase(id))
    }),
    "source_pin_or_byte_bound",
  ))
  use _ <- result.try(require(
    files.digest(body) == pin.sha256,
    "source_digest_mismatch",
  ))
  use root <- result.try(
    json.parse(body, value.decoder()) |> result.replace_error("source_json"),
  )
  use extracted <- result.try(case pin.source {
    HarnessCatalog -> harness(pin, body, root)
    ProductManifest -> product(pin, root)
  })
  let records =
    list.map(extracted, fn(entry) { entry.0 })
    |> list.sort(fn(left, right) {
      string.compare(left.source_id, right.source_id)
    })
  let expected = list.sort(pin.expected_ids, string.compare)
  use _ <- result.try(require(
    list.map(records, fn(record) { record.source_id }) == expected,
    "source_record_set_mismatch",
  ))
  use catalog <- result.try(features.catalog(
    pin.candidate,
    list.map(extracted, fn(entry) { entry.1 }),
  ))
  Ok(Snapshot(Pin(..pin, expected_ids: expected), records, catalog))
}

pub fn catalog(snapshot: Snapshot) -> features.Catalog {
  snapshot.catalog
}

pub fn records(snapshot: Snapshot) -> List(SourceRecord) {
  snapshot.records
}

pub fn encode_manifest(snapshot: Snapshot) -> String {
  let pin = snapshot.pin
  let ids_hash =
    pin.expected_ids
    |> json.array(json.string)
    |> json.to_string
    |> files.digest
  json.object([
    #("schema", json.string("uos.system-feature-source.v1")),
    #("adapter", json.string("raw-json-features.v1")),
    #("candidate", json.string(pin.candidate)),
    #("source", json.string(source_path(pin.source))),
    #("source_sha256", json.string(pin.sha256)),
    #("source_schema", json.string(schema(pin.source))),
    #("pointer", json.string("/features")),
    #("expected_count", json.int(list.length(pin.expected_ids))),
    #("extracted_count", json.int(list.length(snapshot.records))),
    #("source_ids_sha256", json.string(ids_hash)),
    #("catalog_sha256", json.string(features.fingerprint(snapshot.catalog))),
    #("selected_feature_array_complete", json.bool(True)),
    #("inventory_complete", json.bool(False)),
    #("runtime_availability", json.string("unknown")),
    #(
      "endpoint_knowledge",
      json.string("unmapped; empty does not prove absence"),
    ),
    #("owner_knowledge", json.string("unknown; actor intent is not identity")),
    #("effect_authority", json.bool(False)),
    #("system_admission", json.bool(False)),
    #(
      "stage_semantics",
      json.string("unverified source claim; not an execution stage"),
    ),
    #(
      "service_semantics",
      json.string("source namespace; not observed service identity"),
    ),
    #(
      "aspect_semantics",
      json.string("17 review obligations; not passing evidence"),
    ),
    #(
      "law_semantics",
      json.string("inventory adapter laws; not feature verification"),
    ),
    #(
      "remediation_semantics",
      json.string("inventory task; not source feature completion"),
    ),
    #(
      "dependency_knowledge",
      json.string(case pin.source {
        HarnessCatalog -> "source_declared"
        ProductManifest -> "unknown"
      }),
    ),
    #(
      "excluded",
      json.array(
        [
          "other source arrays and documents", "service specification bindings",
          "oracles and imported/reference catalogs",
          "implementation-file verification",
          "runtime endpoint discovery and probes", "global source census",
        ],
        json.string,
      ),
    ),
    #(
      "records",
      json.array(snapshot.records, fn(record) {
        json.object([
          #("source_id", json.string(record.source_id)),
          #("feature_id", json.string(record.feature_id)),
          #("raw_stage", json.string(record.raw_stage)),
        ])
      }),
    ),
  ])
  |> json.to_string
}
