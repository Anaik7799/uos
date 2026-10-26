//// Truthful Mini App observers for the Immune, Inference, Federation and
//// Telemetry pages. Pure: every input is injected, so no environment is read.
//// Confidence vocabulary: "observed" only when live state was read,
//// "declared" for configuration. "simulated" is never produced here.

import cepaf_gleam/config/mesh_config as mesh
import cepaf_gleam/config/mesh_source
import cepaf_gleam/telegram/mini_api as api
import gleam/dict
import gleam/float
import gleam/int
import gleam/list
import gleam/string

pub const max_fields = 24

pub const max_value_bytes = 512

const max_tiers = 8

pub const immune_reason = "immune_actor_not_observable"

pub const federation_reason = "mesh_configuration_invalid"

pub type Tier {
  Tier(tier: Int, name: String, model: String, enabled_by_default: Bool)
}

fn clip(value: String) -> String {
  case string.byte_size(value) <= max_value_bytes {
    True -> value
    False -> string.slice(value, 0, max_value_bytes - 3) <> "..."
  }
}

fn build(
  at: Int,
  source: String,
  confidence: String,
  rows: List(#(String, String)),
) -> api.Observation {
  let all = [#("Source", source), #("Confidence", confidence), ..rows]
  let fields =
    all
    |> list.take(max_fields)
    |> list.map(fn(r) { #(r.0, clip(r.1)) })
    |> dict.from_list
  api.Observed(at, source, fields)
}

/// immune/system is an OTP actor with no synchronous snapshot message.
pub fn immune() -> api.Observation {
  api.Unavailable(immune_reason)
}

/// Declared inference cascade and MAX protocol methods. The live daemon is
/// never contacted, so confidence is "declared" and live status is stated.
pub fn inference(
  at: Int,
  tiers: List(Tier),
  methods: List(String),
) -> api.Observation {
  let shown = list.take(tiers, max_tiers)
  let tier_rows =
    list.map(shown, fn(t) {
      #(
        "Tier " <> int.to_string(t.tier),
        t.name
          <> " | model="
          <> t.model
          <> " | enabled_by_default="
          <> bool(t.enabled_by_default),
      )
    })
  build(
    at,
    "ui/lustre/inference_tier",
    "declared",
    list.append(
      [
        #("Kind", "configured_cascade"),
        #("Live status", "not_observed"),
        #("Runtime admission", "NOT_GRANTED"),
        #("Tier count", int.to_string(list.length(tiers))),
        #("Protocol method count", int.to_string(list.length(methods))),
        #("Protocol methods", string.join(methods, ", ")),
      ],
      tier_rows,
    ),
  )
}

/// Declared mesh configuration; deployment is never confirmed by this read.
pub fn federation(
  at: Int,
  declaration: Result(mesh_source.Declaration, String),
) -> api.Observation {
  case declaration {
    Error(_) -> api.Unavailable(federation_reason)
    Ok(d) -> {
      let c = mesh_source.configuration(d)
      build(at, "config/mesh_source", "declared", [
        #("Configuration source", mesh_source.source(d)),
        #("Deployment", "Not confirmed"),
        #("Runtime admission", "NOT_GRANTED"),
        #("Containers", int.to_string(list.length(c.containers))),
        #("Networks", int.to_string(list.length(c.networks))),
        #("Volumes", int.to_string(list.length(c.volumes))),
        #("Quorum", int.to_string(c.quorum_size)),
        #("Declared CPU cores", float.to_string(mesh.total_cpu_allocation(c))),
        #("Declared memory MB", int.to_string(mesh.total_memory_allocation(c))),
      ])
    }
  }
}

/// Telemetry comes from the live in-process span collector. Pass its
/// observation through, naming source and confidence in the fields.
pub fn telemetry(observation: api.Observation) -> api.Observation {
  case observation {
    api.Observed(at, source, fields) ->
      api.Observed(
        at,
        source,
        fields
          |> dict.insert("Source", source)
          |> dict.insert("Confidence", "observed"),
      )
    other -> other
  }
}

fn bool(value: Bool) -> String {
  case value {
    True -> "true"
    False -> "false"
  }
}
