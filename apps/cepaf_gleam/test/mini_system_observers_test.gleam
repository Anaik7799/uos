import cepaf_gleam/config/mesh_source as source
import cepaf_gleam/telegram/mini_api as api
import cepaf_gleam/telegram/mini_system_observers as obs
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{None}
import gleam/string
import gleeunit/should

fn seq(n: Int) -> List(Int) {
  case n <= 0 {
    True -> []
    False -> list.append(seq(n - 1), [n])
  }
}

fn tier(n: Int) -> obs.Tier {
  obs.Tier(
    n,
    "Tier name " <> int.to_string(n),
    "model-" <> int.to_string(n),
    True,
  )
}

fn tiers(n: Int) -> List(obs.Tier) {
  seq(n) |> list.map(tier)
}

fn fields(o: api.Observation) {
  let assert api.Observed(_, _, f) = o
  f
}

fn default_federation() -> api.Observation {
  obs.federation(1000, source.from_environment(None))
}

pub fn immune_is_named_unavailable_test() {
  obs.immune() |> should.equal(api.Unavailable("immune_actor_not_observable"))
}

pub fn inference_is_declared_with_source_test() {
  let o = obs.inference(7, tiers(6), ["health", "infer_text"])
  let assert api.Observed(7, "ui/lustre/inference_tier", f) = o
  dict.get(f, "Source") |> should.equal(Ok("ui/lustre/inference_tier"))
  dict.get(f, "Confidence") |> should.equal(Ok("declared"))
  dict.get(f, "Live status") |> should.equal(Ok("not_observed"))
  dict.get(f, "Tier count") |> should.equal(Ok("6"))
  dict.get(f, "Protocol method count") |> should.equal(Ok("2"))
  dict.get(f, "Protocol methods") |> should.equal(Ok("health, infer_text"))
  dict.get(f, "Tier 1")
  |> should.equal(Ok("Tier name 1 | model=model-1 | enabled_by_default=true"))
}

pub fn federation_default_is_declared_not_deployed_test() {
  let o = default_federation()
  let assert api.Observed(1000, "config/mesh_source", f) = o
  dict.get(f, "Source") |> should.equal(Ok("config/mesh_source"))
  dict.get(f, "Confidence") |> should.equal(Ok("declared"))
  dict.get(f, "Deployment") |> should.equal(Ok("Not confirmed"))
  dict.get(f, "Configuration source") |> should.equal(Ok("compiled_default"))
  dict.get(f, "Containers") |> should.equal(Ok("7"))
}

pub fn federation_invalid_is_named_unavailable_test() {
  obs.federation(1, Error("bad"))
  |> should.equal(api.Unavailable("mesh_configuration_invalid"))
}

pub fn telemetry_annotates_live_observation_test() {
  let live =
    api.Observed(5, "local_mini_telemetry", dict.from_list([#("A", "1")]))
  let f = obs.telemetry(live) |> fields
  dict.get(f, "Source") |> should.equal(Ok("local_mini_telemetry"))
  dict.get(f, "Confidence") |> should.equal(Ok("observed"))
  dict.get(f, "A") |> should.equal(Ok("1"))
}

pub fn telemetry_passes_unavailable_through_test() {
  obs.telemetry(api.Unavailable("telemetry_collector_unavailable"))
  |> should.equal(api.Unavailable("telemetry_collector_unavailable"))
}

pub fn never_backend_not_integrated_and_never_simulated_test() {
  [
    obs.immune(),
    obs.inference(1, tiers(6), ["health"]),
    default_federation(),
    obs.federation(1, Error("x")),
  ]
  |> list.each(fn(o) {
    case o {
      api.Unavailable(reason) -> {
        reason |> should.not_equal("backend_not_integrated")
        string.starts_with(reason, "backend_") |> should.be_false
      }
      api.Observed(_, source, f) -> {
        string.is_empty(source) |> should.be_false
        dict.get(f, "Source") |> should.equal(Ok(source))
        let assert Ok(c) = dict.get(f, "Confidence")
        { c == "declared" || c == "observed" } |> should.be_true
      }
      api.Forbidden -> should.fail()
    }
  })
}

pub fn inference_is_bounded_test() {
  let long = string.repeat("x", 2000)
  let many = seq(100) |> list.map(fn(n) { obs.Tier(n, long, long, False) })
  let f =
    obs.inference(1, many, list.repeat(long, 50))
    |> fields
  { dict.size(f) <= 24 } |> should.be_true
  dict.get(f, "Tier count") |> should.equal(Ok("100"))
  dict.to_list(f)
  |> list.all(fn(r) { string.byte_size(r.1) <= 512 })
  |> should.be_true
  dict.has_key(f, "Source") |> should.be_true
  dict.has_key(f, "Confidence") |> should.be_true
}

pub fn federation_fields_are_bounded_test() {
  let f = default_federation() |> fields
  { dict.size(f) <= 24 } |> should.be_true
  dict.to_list(f)
  |> list.all(fn(r) { string.byte_size(r.1) <= 512 })
  |> should.be_true
}
