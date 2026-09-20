import cepaf_gleam/harness/system_features as features
import cepaf_gleam/harness/value
import gleam/int
import gleam/json
import gleam/list
import gleam/result

fn arguments(args: value.Value) -> Result(#(String, Int), String) {
  use fields <- result.try(case args {
    value.Object(fields) -> Ok(fields)
    _ -> Error("feature_query_exact_arguments")
  })
  let keys = list.map(fields, fn(field) { field.0 })
  use _ <- result.try(
    case
      list.length(fields) == 2
      && list.contains(keys, "catalog_sha256")
      && list.contains(keys, "offset")
    {
      True -> Ok(Nil)
      False -> Error("feature_query_exact_arguments")
    },
  )
  use digest <- result.try(case value.get(args, "catalog_sha256") {
    Ok(value.Text(digest)) -> Ok(digest)
    _ -> Error("feature_query_digest")
  })
  use raw_offset <- result.try(case value.get(args, "offset") {
    Ok(value.Text(offset)) -> Ok(offset)
    _ -> Error("feature_query_offset")
  })
  use offset <- result.try(
    int.parse(raw_offset) |> result.replace_error("feature_query_offset"),
  )
  case
    features.valid_digest(digest)
    && offset >= 0
    && offset <= 128
    && int.to_string(offset) == raw_offset
  {
    True -> Ok(#(digest, offset))
    False -> Error("feature_query_bound")
  }
}

pub fn query(
  args: value.Value,
  fence: fn() -> Result(Nil, String),
  read: fn(String) -> Result(features.Catalog, String),
) -> Result(json.Json, String) {
  use #(digest, offset) <- result.try(arguments(args))
  use _ <- result.try(fence())
  use catalog <- result.try(read(digest))
  use _ <- result.try(case features.fingerprint(catalog) == digest {
    True -> Ok(Nil)
    False -> Error("feature_query_catalog_mismatch")
  })
  let declarations = features.declarations(catalog)
  let count = list.length(declarations)
  use _ <- result.try(case offset <= count {
    True -> Ok(Nil)
    False -> Error("feature_query_offset")
  })
  let page = declarations |> list.drop(offset) |> list.take(8)
  let next = offset + list.length(page)
  Ok(
    json.object([
      #("schema", json.string("uos.system-feature-query.v1")),
      #("catalog_sha256", json.string(digest)),
      #("candidate", json.string(features.candidate(catalog))),
      #("count", json.int(count)),
      #("offset", json.int(offset)),
      #("next_offset", case next < count {
        True -> json.int(next)
        False -> json.null()
      }),
      #(
        "features",
        json.array(page, fn(feature) {
          json.object([
            #("declaration", features.feature_json(feature)),
            #("mcp_availability", json.string("unknown")),
            #(
              "reason",
              json.string(
                "Catalog persistence is not runtime evidence; trusted client-probe verifier not connected",
              ),
            ),
          ])
        }),
      ),
      #("metadata_only", json.bool(True)),
      #("inventory_complete", json.bool(False)),
      #("effect_authority", json.bool(False)),
      #("system_admission", json.bool(False)),
    ]),
  )
}

fn ledger_arguments(
  args: value.Value,
) -> Result(#(String, String, Int), String) {
  use fields <- result.try(case args {
    value.Object(fields) -> Ok(fields)
    _ -> Error("feature_observations_exact_arguments")
  })
  let keys = list.map(fields, fn(field) { field.0 })
  use _ <- result.try(
    case
      list.length(fields) == 3
      && list.contains(keys, "catalog_sha256")
      && list.contains(keys, "ledger_sha256")
      && list.contains(keys, "offset")
    {
      True -> Ok(Nil)
      False -> Error("feature_observations_exact_arguments")
    },
  )
  use catalog <- result.try(case value.get(args, "catalog_sha256") {
    Ok(value.Text(digest)) -> Ok(digest)
    _ -> Error("feature_observations_catalog_digest")
  })
  use ledger <- result.try(case value.get(args, "ledger_sha256") {
    Ok(value.Text(digest)) -> Ok(digest)
    _ -> Error("feature_observations_ledger_digest")
  })
  use raw_offset <- result.try(case value.get(args, "offset") {
    Ok(value.Text(offset)) -> Ok(offset)
    _ -> Error("feature_observations_offset")
  })
  use offset <- result.try(
    int.parse(raw_offset) |> result.replace_error("feature_observations_offset"),
  )
  case
    features.valid_digest(catalog)
    && features.valid_digest(ledger)
    && offset >= 0
    && offset <= 128
    && int.to_string(offset) == raw_offset
  {
    True -> Ok(#(catalog, ledger, offset))
    False -> Error("feature_observations_bound")
  }
}

pub fn observations(
  args: value.Value,
  fence: fn() -> Result(Nil, String),
  read_catalog: fn(String) -> Result(features.Catalog, String),
  read_ledger: fn(features.Catalog, String) -> Result(features.Ledger, String),
) -> Result(json.Json, String) {
  use #(catalog_digest, ledger_digest, offset) <- result.try(ledger_arguments(
    args,
  ))
  use _ <- result.try(fence())
  use catalog <- result.try(read_catalog(catalog_digest))
  use ledger <- result.try(read_ledger(catalog, ledger_digest))
  use _ <- result.try(features.validate_ledger(catalog, ledger))
  let entries = features.observations(ledger)
  use _ <- result.try(case offset <= list.length(entries) {
    True -> Ok(Nil)
    False -> Error("feature_observations_offset")
  })
  let page = entries |> list.drop(offset) |> list.take(8)
  let next = offset + list.length(page)
  Ok(
    json.object([
      #("schema", json.string("uos.system-feature-observations-query.v1")),
      #("catalog_sha256", json.string(catalog_digest)),
      #("ledger_sha256", json.string(ledger_digest)),
      #("count", json.int(list.length(entries))),
      #("offset", json.int(offset)),
      #("next_offset", case next < list.length(entries) {
        True -> json.int(next)
        False -> json.null()
      }),
      #("observations", json.array(page, features.observation_json)),
      #("availability", json.string("unknown_without_authorized_context")),
      #("effect_authority", json.bool(False)),
      #("system_admission", json.bool(False)),
    ]),
  )
}
