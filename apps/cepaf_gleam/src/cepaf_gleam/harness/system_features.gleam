import cepaf_gleam/harness/files
import cepaf_gleam/harness/tracking
import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub type Stage {
  Declaration(String)
  Discovered
  Classified
  Mapped
  Implemented
  Built
  Executed
  Passed
  Verified
  Admitted
}

pub type EndpointKind {
  Tool
  Resource
  Prompt
}

pub type Endpoint {
  Endpoint(
    server: String,
    kind: EndpointKind,
    name: String,
    input_schema: Option(String),
    output_schema: Option(String),
    refusal_schema: Option(String),
    effects: List(String),
  )
}

pub type Feature {
  Feature(
    id: String,
    title: String,
    service: String,
    owner: Option(String),
    holon: Option(String),
    source: String,
    source_sha256: String,
    declared_stage: Stage,
    dependencies: Option(List(String)),
    endpoints: List(Endpoint),
    aspects: List(String),
    layers: Option(List(Int)),
    laws: List(String),
    remediation_tasks: List(String),
  )
}

pub opaque type Catalog {
  Catalog(candidate: String, features: List(Feature))
}

pub type EvidenceScope {
  RuntimeProbe
  PrivateFixture
  DeclarationOnly
}

pub type Outcome {
  ProbeSuccess
  ProbeAbsent
  ProbeDisabled
  ProbeFailed
}

pub type Observation {
  Observation(
    id: String,
    feature_id: String,
    endpoint: String,
    catalog_sha256: String,
    candidate: String,
    authorization_sha256: String,
    observed_at_ms: Int,
    expires_at_ms: Int,
    outcome: Outcome,
    scope: EvidenceScope,
    receipt_sha256: String,
    client: String,
    transport: String,
    actor: String,
  )
}

pub opaque type Ledger {
  Ledger(entries: Dict(String, Observation))
}

pub type Context {
  Context(
    candidate: String,
    authorization_sha256: String,
    now_ms: Int,
    trusted_receipts: List(String),
    client: String,
    transport: String,
    actor: String,
  )
}

pub type Availability {
  Unknown
  Absent
  Disabled
  Stale
  Failing
  Usable
}

pub type Coverage {
  Coverage(
    missing: List(String),
    orphaned: List(String),
    schema_mismatched: List(String),
  )
}

pub fn aspect_ids() -> List(String) {
  [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17]
  |> list.map(fn(number) {
    "AINF-A" <> string.pad_start(int.to_string(number), 2, "0")
  })
}

pub fn valid_digest(digest: String) -> Bool {
  string.byte_size(digest) == 64
  && list.all(string.to_graphemes(digest), fn(character) {
    string.contains("0123456789abcdef", character)
  })
}

fn bounded_text(text: String, maximum: Int) -> Bool {
  string.byte_size(text) > 0
  && string.byte_size(text) <= maximum
  && !string.contains(text, "\u{0}")
}

fn valid_source(path: String) -> Bool {
  bounded_text(path, 512)
  && !string.starts_with(path, "/")
  && !string.contains(path, "\\")
  && list.all(string.split(path, "/"), fn(part) {
    part != "" && part != "." && part != ".."
  })
}

fn unique(items: List(a)) -> Bool {
  list.length(items) == list.length(list.unique(items))
}

fn valid_labels(labels: List(String), maximum: Int) -> Bool {
  labels != []
  && list.length(labels) <= maximum
  && unique(labels)
  && list.all(labels, fn(label) { bounded_text(label, 256) })
}

fn kind_name(kind: EndpointKind) -> String {
  case kind {
    Tool -> "tool"
    Resource -> "resource"
    Prompt -> "prompt"
  }
}

pub fn endpoint_key(endpoint: Endpoint) -> String {
  json.array(
    [endpoint.server, kind_name(endpoint.kind), endpoint.name],
    json.string,
  )
  |> json.to_string
}

fn valid_endpoint(endpoint: Endpoint) -> Bool {
  tracking.valid_feature_id(endpoint.server)
  && bounded_text(endpoint.name, 512)
  && string.byte_size(endpoint_key(endpoint)) <= 1024
  && valid_optional_digest(endpoint.input_schema)
  && valid_optional_digest(endpoint.output_schema)
  && valid_optional_digest(endpoint.refusal_schema)
  && valid_labels(endpoint.effects, 32)
}

fn valid_optional_digest(digest: Option(String)) -> Bool {
  case digest {
    None -> True
    Some(digest) -> valid_digest(digest)
  }
}

pub fn schemas_known(endpoint: Endpoint) -> Bool {
  case endpoint.input_schema, endpoint.output_schema, endpoint.refusal_schema {
    Some(_), Some(_), Some(_) -> True
    _, _, _ -> False
  }
}

fn optional_digest_json(digest: Option(String)) -> json.Json {
  case digest {
    None -> json.null()
    Some(digest) -> json.string(digest)
  }
}

fn normalize(feature: Feature) -> Feature {
  Feature(
    ..feature,
    dependencies: option.map(feature.dependencies, list.sort(_, string.compare)),
    endpoints: feature.endpoints
      |> list.map(fn(endpoint) {
        Endpoint(
          ..endpoint,
          effects: list.sort(endpoint.effects, string.compare),
        )
      })
      |> list.sort(fn(left, right) {
        string.compare(endpoint_key(left), endpoint_key(right))
      }),
    aspects: list.sort(feature.aspects, string.compare),
    layers: option.map(feature.layers, list.sort(_, int.compare)),
    laws: list.sort(feature.laws, string.compare),
    remediation_tasks: list.sort(feature.remediation_tasks, string.compare),
  )
}

fn valid_feature(feature: Feature) -> Bool {
  tracking.valid_feature_id(feature.id)
  && bounded_text(feature.title, 512)
  && tracking.valid_feature_id(feature.service)
  && case feature.owner {
    None -> True
    Some(owner) -> tracking.valid_feature_id(owner)
  }
  && case feature.holon {
    None -> True
    Some(holon) -> tracking.valid_feature_id(holon)
  }
  && valid_source(feature.source)
  && valid_digest(feature.source_sha256)
  && case feature.declared_stage {
    Declaration(claim) -> bounded_text(claim, 80)
    Discovered
    | Classified
    | Mapped
    | Implemented
    | Built
    | Executed
    | Passed
    | Verified
    | Admitted -> True
  }
  && case feature.dependencies {
    None -> True
    Some(dependencies) ->
      list.length(dependencies) <= 128
      && unique(dependencies)
      && list.all(dependencies, tracking.valid_feature_id)
      && !list.contains(dependencies, feature.id)
  }
  && list.length(feature.endpoints) <= 32
  && list.all(feature.endpoints, valid_endpoint)
  && unique(list.map(feature.endpoints, endpoint_key))
  && feature.aspects == aspect_ids()
  && case feature.layers {
    None -> True
    Some(layers) ->
      layers != []
      && unique(layers)
      && list.all(layers, fn(layer) { layer >= 0 && layer <= 9 })
  }
  && valid_labels(feature.laws, 64)
  && valid_labels(feature.remediation_tasks, 64)
  && list.all(feature.remediation_tasks, tracking.valid_feature_id)
  && string.byte_size(encode_feature(feature)) <= 16_384
}

fn acyclic(remaining: List(Feature), done: List(String)) -> Bool {
  case remaining {
    [] -> True
    _ -> {
      let #(ready, waiting) =
        list.partition(remaining, fn(feature) {
          list.all(option.unwrap(feature.dependencies, []), fn(dependency) {
            list.contains(done, dependency)
          })
        })
      case ready {
        [] -> False
        _ ->
          acyclic(
            waiting,
            list.append(done, list.map(ready, fn(feature) { feature.id })),
          )
      }
    }
  }
}

pub fn catalog(
  candidate: String,
  declarations: List(Feature),
) -> Result(Catalog, String) {
  use _ <- result.try(
    case
      valid_digest(candidate)
      && declarations != []
      && list.length(declarations) <= 128
    {
      True -> Ok(Nil)
      False -> Error("feature_catalog_bound_or_candidate")
    },
  )
  let declarations =
    list.map(declarations, normalize)
    |> list.sort(fn(left, right) { string.compare(left.id, right.id) })
  let identifiers = list.map(declarations, fn(feature) { feature.id })
  case
    unique(identifiers)
    && list.all(declarations, valid_feature)
    && list.all(declarations, fn(feature) {
      list.all(option.unwrap(feature.dependencies, []), fn(dependency) {
        list.contains(identifiers, dependency)
      })
    })
    && acyclic(declarations, [])
    && compatible_endpoints(declarations)
  {
    True -> {
      let catalog = Catalog(candidate, declarations)
      case string.byte_size(encode_catalog(catalog)) <= 2_097_152 {
        True -> Ok(catalog)
        False -> Error("catalog_byte_bound")
      }
    }
    False -> Error("invalid_feature_declaration_or_graph")
  }
}

pub fn declarations(catalog: Catalog) -> List(Feature) {
  catalog.features
}

pub fn catalog_endpoints_compatible(catalogs: List(Catalog)) -> Bool {
  catalogs |> list.flat_map(declarations) |> compatible_endpoints
}

fn compatible_endpoints(features: List(Feature)) -> Bool {
  let endpoints = list.flat_map(features, fn(feature) { feature.endpoints })
  list.try_fold(endpoints, dict.new(), fn(seen, endpoint) {
    let key = endpoint_key(endpoint)
    case dict.get(seen, key) {
      Ok(existing) if existing != endpoint -> Error(Nil)
      _ -> Ok(dict.insert(seen, key, endpoint))
    }
  })
  |> result.is_ok
}

pub fn candidate(catalog: Catalog) -> String {
  catalog.candidate
}

pub fn stage_name(stage: Stage) -> String {
  case stage {
    Declaration(claim) -> "declaration:" <> claim
    Discovered -> "discovered"
    Classified -> "classified"
    Mapped -> "mapped"
    Implemented -> "implemented"
    Built -> "built"
    Executed -> "executed"
    Passed -> "passed"
    Verified -> "verified"
    Admitted -> "admitted"
  }
}

fn endpoint_json(endpoint: Endpoint) -> json.Json {
  json.object([
    #("server", json.string(endpoint.server)),
    #("kind", json.string(kind_name(endpoint.kind))),
    #("name", json.string(endpoint.name)),
    #("input_schema", optional_digest_json(endpoint.input_schema)),
    #("output_schema", optional_digest_json(endpoint.output_schema)),
    #("refusal_schema", optional_digest_json(endpoint.refusal_schema)),
    #("effects", json.array(endpoint.effects, json.string)),
  ])
}

pub fn feature_json(feature: Feature) -> json.Json {
  json.object([
    #("id", json.string(feature.id)),
    #("title", json.string(feature.title)),
    #("service", json.string(feature.service)),
    #("owner", case feature.owner {
      None -> json.null()
      Some(owner) -> json.string(owner)
    }),
    #("holon", case feature.holon {
      None -> json.null()
      Some(holon) -> json.string(holon)
    }),
    #("source", json.string(feature.source)),
    #("source_sha256", json.string(feature.source_sha256)),
    #("declared_stage", json.string(stage_name(feature.declared_stage))),
    #("dependencies", case feature.dependencies {
      None -> json.null()
      Some(dependencies) -> json.array(dependencies, json.string)
    }),
    #("endpoints", json.array(feature.endpoints, endpoint_json)),
    #("aspects", json.array(feature.aspects, json.string)),
    #("layers", case feature.layers {
      None -> json.null()
      Some(layers) -> json.array(layers, json.int)
    }),
    #("laws", json.array(feature.laws, json.string)),
    #("remediation_tasks", json.array(feature.remediation_tasks, json.string)),
  ])
}

pub fn encode_feature(feature: Feature) -> String {
  feature_json(feature) |> json.to_string
}

pub fn encode_catalog(catalog: Catalog) -> String {
  json.object([
    #("schema", json.string("uos.system-features.v1")),
    #("candidate", json.string(catalog.candidate)),
    #("features", json.array(catalog.features, feature_json)),
  ])
  |> json.to_string
}

pub fn fingerprint(catalog: Catalog) -> String {
  encode_catalog(catalog) |> files.digest
}

fn stage_decoder() -> decode.Decoder(Stage) {
  use name <- decode.then(decode.string)
  case name {
    "discovered" -> decode.success(Discovered)
    "classified" -> decode.success(Classified)
    "mapped" -> decode.success(Mapped)
    "implemented" -> decode.success(Implemented)
    "built" -> decode.success(Built)
    "executed" -> decode.success(Executed)
    "passed" -> decode.success(Passed)
    "verified" -> decode.success(Verified)
    "admitted" -> decode.success(Admitted)
    _ ->
      case string.starts_with(name, "declaration:") {
        True -> decode.success(Declaration(string.drop_start(name, 12)))
        False -> decode.failure(Discovered, "known declaration stage")
      }
  }
}

fn kind_decoder() -> decode.Decoder(EndpointKind) {
  use name <- decode.then(decode.string)
  case name {
    "tool" -> decode.success(Tool)
    "resource" -> decode.success(Resource)
    "prompt" -> decode.success(Prompt)
    _ -> decode.failure(Tool, "known MCP endpoint kind")
  }
}

fn endpoint_decoder() -> decode.Decoder(Endpoint) {
  use server <- decode.field("server", decode.string)
  use kind <- decode.field("kind", kind_decoder())
  use name <- decode.field("name", decode.string)
  use input <- decode.field("input_schema", decode.optional(decode.string))
  use output <- decode.field("output_schema", decode.optional(decode.string))
  use refusal <- decode.field("refusal_schema", decode.optional(decode.string))
  use effects <- decode.field("effects", decode.list(decode.string))
  decode.success(Endpoint(server, kind, name, input, output, refusal, effects))
}

fn feature_decoder() -> decode.Decoder(Feature) {
  use id <- decode.field("id", decode.string)
  use title <- decode.field("title", decode.string)
  use service <- decode.field("service", decode.string)
  use owner <- decode.field("owner", decode.optional(decode.string))
  use holon <- decode.field("holon", decode.optional(decode.string))
  use source <- decode.field("source", decode.string)
  use source_sha256 <- decode.field("source_sha256", decode.string)
  use stage <- decode.field("declared_stage", stage_decoder())
  use dependencies <- decode.field(
    "dependencies",
    decode.optional(decode.list(decode.string)),
  )
  use endpoints <- decode.field("endpoints", decode.list(endpoint_decoder()))
  use aspects <- decode.field("aspects", decode.list(decode.string))
  use layers <- decode.field("layers", decode.optional(decode.list(decode.int)))
  use laws <- decode.field("laws", decode.list(decode.string))
  use tasks <- decode.field("remediation_tasks", decode.list(decode.string))
  decode.success(Feature(
    id,
    title,
    service,
    owner,
    holon,
    source,
    source_sha256,
    stage,
    dependencies,
    endpoints,
    aspects,
    layers,
    laws,
    tasks,
  ))
}

pub fn parse_feature(raw: String) -> Result(Feature, String) {
  use _ <- result.try(case string.byte_size(raw) <= 16_384 {
    True -> Ok(Nil)
    False -> Error("feature_bound")
  })
  use feature <- result.try(
    json.parse(raw, feature_decoder()) |> result.replace_error("feature_json"),
  )
  let feature = normalize(feature)
  case valid_feature(feature) {
    True -> Ok(feature)
    False -> Error("invalid_feature")
  }
}

pub fn parse_catalog(raw: String) -> Result(Catalog, String) {
  use _ <- result.try(case string.byte_size(raw) <= 2_097_152 {
    True -> Ok(Nil)
    False -> Error("catalog_byte_bound")
  })
  let decoder = {
    use schema <- decode.field("schema", decode.string)
    use candidate <- decode.field("candidate", decode.string)
    use features <- decode.field("features", decode.list(feature_decoder()))
    decode.success(#(schema, candidate, features))
  }
  use #(schema, candidate, features) <- result.try(
    json.parse(raw, decoder) |> result.replace_error("catalog_json"),
  )
  case schema == "uos.system-features.v1" {
    True -> catalog(candidate, features)
    False -> Error("catalog_schema")
  }
}

pub fn empty() -> Ledger {
  Ledger(dict.new())
}

pub fn observations(ledger: Ledger) -> List(Observation) {
  dict.values(ledger.entries)
  |> list.sort(fn(left, right) { string.compare(left.id, right.id) })
}

fn valid_observation(observation: Observation) -> Bool {
  tracking.valid_feature_id(observation.id)
  && tracking.valid_feature_id(observation.feature_id)
  && bounded_text(observation.endpoint, 1024)
  && valid_digest(observation.catalog_sha256)
  && valid_digest(observation.candidate)
  && valid_digest(observation.authorization_sha256)
  && valid_digest(observation.receipt_sha256)
  && observation.observed_at_ms > 0
  && observation.expires_at_ms > observation.observed_at_ms
  && observation.expires_at_ms - observation.observed_at_ms <= 3_600_000
  && observation.expires_at_ms <= 9_007_199_254_740_991
  && bounded_text(observation.client, 128)
  && bounded_text(observation.transport, 256)
  && bounded_text(observation.actor, 128)
}

pub fn encode_observation(observation: Observation) -> String {
  observation_json(observation) |> json.to_string
}

pub fn observation_json(observation: Observation) -> json.Json {
  json.object([
    #("id", json.string(observation.id)),
    #("feature_id", json.string(observation.feature_id)),
    #("endpoint", json.string(observation.endpoint)),
    #("catalog_sha256", json.string(observation.catalog_sha256)),
    #("candidate", json.string(observation.candidate)),
    #("authorization_sha256", json.string(observation.authorization_sha256)),
    #("observed_at_ms", json.int(observation.observed_at_ms)),
    #("expires_at_ms", json.int(observation.expires_at_ms)),
    #(
      "outcome",
      json.string(case observation.outcome {
        ProbeSuccess -> "success"
        ProbeAbsent -> "absent"
        ProbeDisabled -> "disabled"
        ProbeFailed -> "failed"
      }),
    ),
    #(
      "scope",
      json.string(case observation.scope {
        RuntimeProbe -> "runtime_probe"
        PrivateFixture -> "private_fixture"
        DeclarationOnly -> "declaration_only"
      }),
    ),
    #("receipt_sha256", json.string(observation.receipt_sha256)),
    #("client", json.string(observation.client)),
    #("transport", json.string(observation.transport)),
    #("actor", json.string(observation.actor)),
  ])
}

pub fn observation_fingerprint(observation: Observation) -> String {
  encode_observation(observation) |> files.digest
}

pub fn parse_observation(raw: String) -> Result(Observation, String) {
  use _ <- result.try(case string.byte_size(raw) <= 16_384 {
    True -> Ok(Nil)
    False -> Error("observation_byte_bound")
  })
  let decoder = {
    use id <- decode.field("id", decode.string)
    use feature <- decode.field("feature_id", decode.string)
    use endpoint <- decode.field("endpoint", decode.string)
    use catalog <- decode.field("catalog_sha256", decode.string)
    use candidate <- decode.field("candidate", decode.string)
    use authorization <- decode.field("authorization_sha256", decode.string)
    use observed <- decode.field("observed_at_ms", decode.int)
    use expires <- decode.field("expires_at_ms", decode.int)
    use outcome <- decode.field("outcome", decode.string)
    use scope <- decode.field("scope", decode.string)
    use receipt <- decode.field("receipt_sha256", decode.string)
    use client <- decode.field("client", decode.string)
    use transport <- decode.field("transport", decode.string)
    use actor <- decode.field("actor", decode.string)
    decode.success(#(
      Observation(
        id,
        feature,
        endpoint,
        catalog,
        candidate,
        authorization,
        observed,
        expires,
        ProbeFailed,
        DeclarationOnly,
        receipt,
        client,
        transport,
        actor,
      ),
      outcome,
      scope,
    ))
  }
  use #(observation, outcome, scope) <- result.try(
    json.parse(raw, decoder) |> result.replace_error("observation_json"),
  )
  use outcome <- result.try(case outcome {
    "success" -> Ok(ProbeSuccess)
    "absent" -> Ok(ProbeAbsent)
    "disabled" -> Ok(ProbeDisabled)
    "failed" -> Ok(ProbeFailed)
    _ -> Error("observation_outcome")
  })
  use scope <- result.try(case scope {
    "runtime_probe" -> Ok(RuntimeProbe)
    "private_fixture" -> Ok(PrivateFixture)
    "declaration_only" -> Ok(DeclarationOnly)
    _ -> Error("observation_scope")
  })
  let observation = Observation(..observation, outcome: outcome, scope: scope)
  case valid_observation(observation) {
    True -> Ok(observation)
    False -> Error("invalid_feature_observation")
  }
}

pub fn validate_ledger(
  catalog: Catalog,
  ledger: Ledger,
) -> Result(Nil, String) {
  let digest = fingerprint(catalog)
  case
    list.all(observations(ledger), fn(observation) {
      observation.catalog_sha256 == digest
      && observation.candidate == catalog.candidate
      && list.any(catalog.features, fn(feature) {
        feature.id == observation.feature_id
        && list.any(feature.endpoints, fn(endpoint) {
          endpoint_key(endpoint) == observation.endpoint
        })
      })
    })
  {
    True -> Ok(Nil)
    False -> Error("foreign_catalog_observation")
  }
}

pub fn record(
  ledger: Ledger,
  observation: Observation,
) -> Result(Ledger, String) {
  use _ <- result.try(case valid_observation(observation) {
    True -> Ok(Nil)
    False -> Error("invalid_feature_observation")
  })
  case dict.get(ledger.entries, observation.id) {
    Ok(existing) if existing == observation -> Ok(ledger)
    Ok(_) -> Error("feature_observation_identity_conflict")
    Error(_) ->
      case dict.size(ledger.entries) < 4096 {
        True ->
          Ok(Ledger(dict.insert(ledger.entries, observation.id, observation)))
        False -> Error("feature_observation_count_bound")
      }
  }
}

pub fn merge(left: Ledger, right: Ledger) -> Result(Ledger, String) {
  list.try_fold(observations(right), left, record)
}

pub fn availability(
  catalog: Catalog,
  feature_id: String,
  endpoint: Endpoint,
  ledger: Ledger,
  context: Context,
) -> Availability {
  let catalog_digest = fingerprint(catalog)
  let declared =
    list.any(catalog.features, fn(feature) {
      feature.id == feature_id && list.contains(feature.endpoints, endpoint)
    })
  case
    declared
    && context.candidate == catalog.candidate
    && valid_digest(context.authorization_sha256)
    && context.now_ms > 0
    && context.now_ms <= 9_007_199_254_740_991
    && list.length(context.trusted_receipts) <= 4096
    && list.all(context.trusted_receipts, valid_digest)
  {
    False -> Unknown
    True -> {
      let trusted_hashes =
        dict.from_list(
          list.map(context.trusted_receipts, fn(digest) { #(digest, Nil) }),
        )
      let relevant =
        observations(ledger)
        |> list.filter(fn(observation) {
          observation.feature_id == feature_id
          && observation.endpoint == endpoint_key(endpoint)
          && observation.catalog_sha256 == catalog_digest
          && observation.candidate == context.candidate
          && observation.authorization_sha256 == context.authorization_sha256
          && observation.client == context.client
          && observation.transport == context.transport
          && observation.actor == context.actor
        })
        |> list.sort(fn(left, right) {
          int.compare(right.observed_at_ms, left.observed_at_ms)
        })
      case relevant {
        [] -> Unknown
        [latest, ..] -> {
          let concurrent =
            list.filter(relevant, fn(observation) {
              observation.observed_at_ms == latest.observed_at_ms
            })
          let trusted =
            list.all(concurrent, fn(observation) {
              observation.scope == RuntimeProbe
              && dict.has_key(
                trusted_hashes,
                observation_fingerprint(observation),
              )
              && observation.outcome == latest.outcome
              && observation.expires_at_ms == latest.expires_at_ms
            })
          case trusted && latest.observed_at_ms <= context.now_ms {
            False -> Unknown
            True ->
              case context.now_ms >= latest.expires_at_ms {
                True -> Stale
                False ->
                  case latest.outcome {
                    ProbeSuccess ->
                      case schemas_known(endpoint) {
                        True -> Usable
                        False -> Unknown
                      }
                    ProbeAbsent -> Absent
                    ProbeDisabled -> Disabled
                    ProbeFailed -> Failing
                  }
              }
          }
        }
      }
    }
  }
}

pub fn reconcile(
  catalog: Catalog,
  discovered: List(Endpoint),
) -> Result(Coverage, String) {
  let observed = list.map(discovered, endpoint_key)
  case
    list.length(discovered) <= 4096
    && list.all(discovered, valid_endpoint)
    && unique(observed)
  {
    False -> Error("discovery_bound_or_duplicate")
    True -> {
      let endpoints =
        catalog.features
        |> list.flat_map(fn(feature) { feature.endpoints })
        |> list.unique
      let declared = list.map(endpoints, endpoint_key)
      Ok(Coverage(
        list.filter(declared, fn(key) { !list.contains(observed, key) })
          |> list.sort(string.compare),
        list.filter(observed, fn(key) { !list.contains(declared, key) })
          |> list.sort(string.compare),
        list.filter(discovered, fn(endpoint) {
          list.contains(declared, endpoint_key(endpoint))
          && !list.contains(
            endpoints,
            Endpoint(
              ..endpoint,
              effects: list.sort(endpoint.effects, string.compare),
            ),
          )
        })
          |> list.map(endpoint_key)
          |> list.sort(string.compare),
      ))
    }
  }
}
