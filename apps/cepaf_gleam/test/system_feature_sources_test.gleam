import cepaf_gleam/harness/files
import cepaf_gleam/harness/system_feature_sources as sources
import cepaf_gleam/harness/system_features as features
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{None}
import gleam/string
import gleeunit/should
import simplifile
import system_feature_tracker_test as fixture

pub fn harness_pin() -> sources.Pin {
  sources.Pin(
    fixture.digest(),
    sources.HarnessCatalog,
    "387f4792a012528114ebc2625aea2cd0e0e19cb1815ab713fe55be31a82fe43f",
    [
      "time.observe",
      "files.read",
      "task.lifecycle",
      "files.edit",
      "peers.review",
      "otp.supervision",
      "models.daily_budget",
      "transport.zenoh",
      "identity.grants",
      "dashboard.ecology",
      "tracking.sa_plan",
      "provenance.vm1",
      "development.build",
      "state.ets",
      "ml.max",
      "knowledge.triad",
      "clients.hooks",
      "deployment.roles",
      "otp.catalog",
      "tracking.jobs",
      "tracking.temporal",
      "review.independent",
      "development.verify",
      "state.stm",
      "agents.superagents",
      "dashboard.completion",
      "toolchain.pins",
      "probability.bayesian",
      "rules.rete_ul",
      "flight.f_prime",
      "formal.lean",
      "formal.quint",
      "native.mojo_generated",
      "state.replication",
      "release.recovery",
      "verification.environment",
      "native.ocaml",
      "models.coding",
      "models.decision",
      "safety.stpa_fmea",
      "twins.model",
      "release.dynamic",
      "deployment.standby",
      "models.routing",
      "replication.failover",
      "supervision.fractal",
      "safety.fractal_tps",
      "ruliad.explore",
      "ucon.binding",
      "formal.specification",
      "formal.algebraic_atlas",
      "observability.tracing",
    ],
  )
}

pub fn product_pin() -> sources.Pin {
  sources.Pin(
    fixture.digest(),
    sources.ProductManifest,
    "e8818cb2b6bd9f418890f1738fdf8bf8945f23e371fa360346ca9afe56c9f394",
    [
      "AINF-S01",
      "AINF-S02",
      "AINF-S03",
      "AINF-S04",
      "AINF-S05",
      "AINF-S06",
      "AINF-S07",
      "AINF-S08",
      "AINF-S09",
      "AINF-S10",
      "AINF-S11",
      "AINF-S12",
      "AINF-S13",
      "AINF-S14",
      "AINF-S15",
      "AINF-S16",
      "AINF-S17",
      "AINF-S18",
      "AINF-S19",
      "AINF-S20",
      "AINF-S21",
      "PM-01",
      "PM-02",
      "PM-03",
      "PM-04",
      "PM-05",
      "PM-06",
      "PM-07",
      "PM-08",
      "PM-09",
      "PM-10",
      "PM-11",
      "PM-12",
      "PM-13",
      "PM-14",
      "PM-15",
      "PM-16",
      "PM-17",
      "PM-18",
      "PM-19",
      "PM-20",
      "PM-21",
      "PM-22",
      "PM-23",
      "PM-24",
      "PM-25",
    ],
  )
}

pub fn actual_source(pin: sources.Pin) -> sources.Snapshot {
  let assert Ok(body) =
    simplifile.read("../../" <> sources.source_path(pin.source))
  let assert Ok(snapshot) = sources.extract(pin, body)
  snapshot
}

fn product_record(id: String, stage: String) -> json.Json {
  json.object([
    #("id", json.string(id)),
    #("name", json.string("Declared feature")),
    #("status", json.string(stage)),
    #("admission_status", json.string("NOT_ADMITTED")),
  ])
}

fn product_body(entries: List(json.Json)) -> String {
  json.object([
    #("schema", json.string("uos.product-catalog/v1")),
    #("features", json.array(entries, fn(entry) { entry })),
  ])
  |> json.to_string
}

fn pin_for(body: String, ids: List(String)) -> sources.Pin {
  sources.Pin(
    fixture.digest(),
    sources.ProductManifest,
    files.digest(body),
    ids,
  )
}

pub fn actual_harness_preserves_all_52_records_and_declarations_test() {
  let snapshot = actual_source(harness_pin())
  list.length(sources.records(snapshot)) |> should.equal(52)
  let declarations = features.declarations(sources.catalog(snapshot))
  list.map(declarations, fn(feature) { feature.id })
  |> should.equal(
    list.map(harness_pin().expected_ids, fn(id) { "harness." <> id })
    |> list.sort(string.compare),
  )
  list.all(declarations, fn(feature) {
    feature.endpoints == []
    && feature.holon == None
    && feature.layers == None
    && feature.dependencies != None
    && feature.owner == None
  })
  |> should.be_true
  sources.records(snapshot)
  |> list.filter(fn(record) { record.raw_stage == "PLANNED" })
  |> list.length
  |> should.equal(22)
  features.encode_catalog(sources.catalog(snapshot))
  |> features.parse_catalog
  |> should.equal(Ok(sources.catalog(snapshot)))
}

pub fn actual_product_preserves_46_ids_and_missing_dependency_knowledge_test() {
  let snapshot = actual_source(product_pin())
  let declarations = features.declarations(sources.catalog(snapshot))
  list.length(declarations) |> should.equal(46)
  list.all(declarations, fn(feature) {
    feature.dependencies == None
    && feature.holon == None
    && feature.endpoints == []
    && feature.owner == None
  })
  |> should.be_true
  declarations
  |> list.filter(fn(feature) { feature.layers == None })
  |> list.length
  |> should.equal(25)
  sources.records(snapshot)
  |> list.filter(fn(record) { record.raw_stage == "REVIEWED" })
  |> list.length
  |> should.equal(25)
  sources.records(snapshot)
  |> list.map(fn(record) { record.source_id })
  |> list.sort(string.compare)
  |> should.equal(product_pin().expected_ids |> list.sort(string.compare))
  list.all(declarations, fn(feature) {
    case feature.declared_stage {
      features.Declaration(_) -> True
      _ -> False
    }
  })
  |> should.be_true
}

pub fn source_hash_and_exact_record_set_are_both_required_test() {
  let body = product_body([product_record("PM-01", "REVIEWED")])
  let pin = pin_for(body, ["PM-01"])
  sources.extract(sources.Pin(..pin, sha256: fixture.digest()), body)
  |> should.be_error
  sources.extract(sources.Pin(..pin, expected_ids: ["PM-02"]), body)
  |> should.be_error
  sources.extract(sources.Pin(..pin, expected_ids: ["PM-01", "PM-02"]), body)
  |> should.be_error
  sources.extract(sources.Pin(..pin, expected_ids: ["PM-01", "PM-01"]), body)
  |> should.be_error
  sources.extract(sources.Pin(..pin, candidate: "unbound"), body)
  |> should.be_error
}

pub fn duplicate_ids_normalized_collisions_and_unknown_variants_are_refused_test() {
  list.each(
    [
      #(
        product_body([
          product_record("PM-01", "REVIEWED"),
          product_record("PM-01", "REVIEWED"),
        ]),
        ["PM-01"],
      ),
      #(
        product_body([
          product_record("PM-01", "REVIEWED"),
          product_record("pm-01", "REVIEWED"),
        ]),
        ["PM-01", "pm-01"],
      ),
      #(product_body([product_record("PM-01", "ADMITTED")]), ["PM-01"]),
      #("{\"schema\":\"foreign\",\"features\":[]}", []),
    ],
    fn(example) {
      sources.extract(pin_for(example.0, example.1), example.0)
      |> should.be_error
    },
  )
}

pub fn catalog_denotation_is_order_invariant_but_source_bytes_remain_bound_test() {
  let body =
    product_body([
      product_record("PM-01", "REVIEWED"),
      product_record("PM-02", "MAPPED"),
    ])
  let pin = pin_for(body, ["PM-01", "PM-02"])
  let assert Ok(forward) = sources.extract(pin, body)
  let assert Ok(reverse) =
    sources.extract(
      sources.Pin(..pin, expected_ids: list.reverse(pin.expected_ids)),
      body,
    )
  sources.encode_manifest(forward)
  |> should.equal(sources.encode_manifest(reverse))
  sources.catalog(forward) |> should.equal(sources.catalog(reverse))
  sources.extract(pin, body <> " ") |> should.be_error
}

pub fn oversized_or_empty_source_is_refused_before_parsing_test() {
  list.each(["", string.repeat("x", 1_048_577)], fn(body) {
    sources.extract(pin_for(body, ["PM-01"]), body) |> should.be_error
  })
}

pub fn declaration_manifest_never_claims_global_or_runtime_completion_test() {
  let snapshot = actual_source(product_pin())
  let manifest = sources.encode_manifest(snapshot)
  string.contains(manifest, "\"selected_feature_array_complete\":true")
  |> should.be_true
  string.contains(manifest, "\"inventory_complete\":false") |> should.be_true
  string.contains(manifest, "\"system_admission\":false") |> should.be_true
  string.contains(manifest, "\"effect_authority\":false") |> should.be_true
  string.contains(manifest, "\"pointer\":\"/features\"") |> should.be_true
  string.contains(manifest, "\"dependency_knowledge\":\"unknown\"")
  |> should.be_true
}

pub fn generated_record_sets_agree_with_independent_list_projection_test() {
  list.each(numbers(32), fn(count) {
    let ids =
      numbers(count)
      |> list.map(fn(number) { "PM-" <> int.to_string(number) })
    let body =
      product_body(list.map(ids, fn(id) { product_record(id, "REVIEWED") }))
    let assert Ok(snapshot) =
      sources.extract(pin_for(body, list.reverse(ids)), body)
    features.declarations(sources.catalog(snapshot))
    |> list.map(fn(feature) { feature.id })
    |> should.equal(
      list.map(ids, fn(id) { "product." <> string.lowercase(id) })
      |> list.sort(string.compare),
    )
    sources.records(snapshot)
    |> list.map(fn(record) { record.source_id })
    |> should.equal(list.sort(ids, string.compare))
  })
}

pub fn future_dependency_schema_and_malformed_layer_are_not_silently_discarded_test() {
  let valid = product_body([product_record("PM-01", "REVIEWED")])
  list.each(
    [
      string.replace(valid, "\"name\":", "\"dependencies\":[],\"name\":"),
      string.replace(valid, "\"name\":", "\"fractal_layer\":\"L10\",\"name\":"),
      string.replace(valid, "\"name\":", "\"fractal_layer\":9,\"name\":"),
      string.replace(valid, "\"name\":", "\"not_name\":"),
    ],
    fn(body) {
      sources.extract(pin_for(body, ["PM-01"]), body) |> should.be_error
    },
  )
}

pub fn overlarge_feature_array_is_not_truncated_to_supported_count_test() {
  let ids =
    numbers(129)
    |> list.map(fn(number) { "PM-" <> int.to_string(number) })
  let body =
    product_body(list.map(ids, fn(id) { product_record(id, "REVIEWED") }))
  sources.extract(pin_for(body, ids), body) |> should.be_error
  sources.extract(pin_for(body, list.take(ids, 128)), body) |> should.be_error
}

fn numbers(count: Int) -> List(Int) {
  list.repeat(Nil, count) |> list.index_map(fn(_, index) { index + 1 })
}
