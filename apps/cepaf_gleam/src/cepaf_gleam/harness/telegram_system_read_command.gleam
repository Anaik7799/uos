//// Read-only Telegram observations for /immune, /inference, /rack-cv,
//// /acoustic, /acoustic-hud and /radar.
////
//// Truthfulness contract (Psi5, SC-JIDOKA-001): an "ok" reply is built only
//// from an existing backend module's pure functions. A literal whose backend
//// needs a running actor, a NIF, a sensor, or a live feed that cannot be read
//// synchronously and safely answers "backend_unavailable" naming the closest
//// module. No number is invented and no canned success is returned.
////
//// Backend survey (2026-10-26, workspace fable-w1):
////   /immune      immune/system.gleam is an OTP actor with no snapshot message.
////   /inference   ui/lustre/inference_tier.init + services/max_inference_daemon
////                protocol surface (configuration only; no model is called).
////   /rack-cv     no vision backend; only an encoder in multimodal_features.
////   /acoustic    needs an audio sample and DSP kernel; none is reachable.
////   /acoustic-hud knowledge/raga_cybernetic_synthesis.verify_acoustic_harmony
////                (pure self-audit of the shruti/raga tables, not a live sensor).
////   /radar       ui/lustre/biosemiotics_radar.build_canonical_radar returns
////                fixed constants, not a live measurement.

import cepaf_gleam/knowledge/raga_cybernetic_synthesis as raga
import cepaf_gleam/services/max_inference_daemon as max_daemon
import cepaf_gleam/ui/lustre/inference_tier
import gleam/json
import gleam/list
import gleam/string

const max_reply_bytes = 3500

const max_args_bytes = 256

pub fn literals() -> List(String) {
  ["/immune", "/inference", "/rack-cv", "/acoustic", "/acoustic-hud", "/radar"]
}

/// Dispatch one literal. The reply is always a closed-shape JSON object.
pub fn handle(literal: String, args: String) -> String {
  case list.contains(literals(), literal) {
    False -> denied(literal, "not handled by telegram_system_read_command")
    True ->
      case string.byte_size(args) <= max_args_bytes && string.trim(args) == "" {
        False ->
          denied(literal, "Usage: " <> literal <> " (takes no arguments)")
        True -> bounded(literal, dispatch(literal))
      }
  }
}

fn dispatch(literal: String) -> String {
  case literal {
    "/inference" -> inference()
    "/acoustic-hud" -> acoustic_hud()
    "/immune" ->
      unavailable(
        literal,
        "cepaf_gleam/immune/system",
        "The immune system is an OTP actor with no read-only snapshot message, so antibody state cannot be observed synchronously.",
      )
    "/rack-cv" ->
      unavailable(
        literal,
        "cepaf_gleam/harness/multimodal_features",
        "No computer-vision backend exists; only a caddy-slot encoder is present and no camera or ViT result is reachable.",
      )
    "/acoustic" ->
      unavailable(
        literal,
        "cepaf_gleam/services/max_inference_daemon",
        "Acoustic bearing analysis needs an audio sample and a running MAX daemon, neither of which is observable here.",
      )
    "/radar" ->
      unavailable(
        literal,
        "cepaf_gleam/ui/lustre/biosemiotics_radar",
        "The radar model is built from fixed constants and has no live telemetry feed to read.",
      )
    _ -> denied(literal, "not handled by telegram_system_read_command")
  }
}

fn inference() -> String {
  let model = inference_tier.init()
  let tiers =
    json.array(model.tiers, fn(t) {
      json.object([
        #("tier", json.int(t.tier)),
        #("name", json.string(t.name)),
        #("model", json.string(t.model)),
        #("enabled_by_default", json.bool(t.active)),
      ])
    })
  let methods =
    json.array(max_daemon.all_methods(), fn(m) {
      json.string(max_daemon.method_name(m))
    })
  ok(
    "/inference",
    "cepaf_gleam/ui/lustre/inference_tier",
    json.object([
      #("kind", json.string("configured_cascade")),
      #("live_status", json.string("not_observed")),
      #("tier_count", json.int(list.length(model.tiers))),
      #("tiers", tiers),
      #("max_protocol_methods", methods),
    ]),
  )
}

fn acoustic_hud() -> String {
  let audit = raga.verify_acoustic_harmony()
  ok(
    "/acoustic-hud",
    "cepaf_gleam/knowledge/raga_cybernetic_synthesis",
    json.object([
      #("kind", json.string("shruti_lattice_self_audit")),
      #("live_sensor", json.string("not_observed")),
      #("total_shrutis", json.int(audit.total_shrutis)),
      #("durga_swaras", json.int(audit.durga_swaras_count)),
      #("teentaal_beats", json.int(audit.teentaal_beats_count)),
      #("lyapunov_stable", json.bool(audit.lyapunov_stable)),
      #("entropy_sufficient", json.bool(audit.entropy_sufficient)),
      #("just_intonation_verified", json.bool(audit.just_intonation_verified)),
    ]),
  )
}

fn ok(command: String, backend: String, observation: json.Json) -> String {
  json.object([
    #("status", json.string("ok")),
    #("command", json.string(command)),
    #("backend", json.string(backend)),
    #("observation", observation),
  ])
  |> json.to_string
}

fn unavailable(command: String, backend: String, reason: String) -> String {
  json.object([
    #("status", json.string("backend_unavailable")),
    #("command", json.string(command)),
    #("backend", json.string(backend)),
    #("reason", json.string(reason)),
  ])
  |> json.to_string
}

fn denied(command: String, reason: String) -> String {
  json.object([
    #("status", json.string("denied")),
    #("command", json.string(safe_command(command))),
    #("reason", json.string(reason)),
  ])
  |> json.to_string
}

/// Echo caller text only when short; the command field never exceeds 64 bytes.
fn safe_command(command: String) -> String {
  case string.byte_size(command) <= 64 {
    True -> command
    False -> string.slice(command, 0, 32)
  }
}

fn bounded(literal: String, reply: String) -> String {
  case string.byte_size(reply) <= max_reply_bytes {
    True -> reply
    False -> denied(literal, "reply exceeds the 3500 byte bound")
  }
}
