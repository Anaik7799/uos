//// [C3I-SIL6-MSTS] <c3i-module><identity><module>cepaf_gleam/harness/telegram_media_unsupported</module></identity>
////   <fractal-topology><layer>L5_COGNITIVE</layer></fractal-topology>
////   <compliance><stamp-controls>SC-TELEGRAM-MEDIA-T0, SC-ERGONOMIC-001</stamp-controls></compliance>
//// </c3i-module>
////
//// Typed observable-unsupported record for Telegram media arms (media design T0).
//// Shape follows cognitive_worker `query_voice_status`: capability, backend
//// NOT_IMPLEMENTED, observed false, reason. A reply built from this record asserts
//// no measurement, no detected model, no extracted state and no latency.

import gleam/json

/// A capability that is routed but has no backend. `observed` is False unless the
/// response reflects a fresh observation, which no current media arm provides.
pub type MediaUnsupported {
  MediaUnsupported(
    capability: String,
    status: String,
    backend: String,
    observed: Bool,
    reason: String,
  )
}

/// Build the record for a capability that is not implemented.
pub fn unsupported(capability: String, reason: String) -> MediaUnsupported {
  MediaUnsupported(
    capability: capability,
    status: "UNSUPPORTED",
    backend: "NOT_IMPLEMENTED",
    observed: False,
    reason: reason,
  )
}

/// Canonical JSON for the record (fixed key order, escaped by gleam/json).
pub fn to_json(u: MediaUnsupported) -> String {
  json.object([
    #("status", json.string(u.status)),
    #("capability", json.string(u.capability)),
    #("backend", json.string(u.backend)),
    #("observed", json.bool(u.observed)),
    #("reason", json.string(u.reason)),
  ])
  |> json.to_string
}

/// Reply text. `command` must be a compile-time literal, never sender input.
pub fn render(command: String, u: MediaUnsupported) -> String {
  "⚠️ *"
  <> command
  <> "* media capability is not implemented\n\n```json\n"
  <> to_json(u)
  <> "\n```"
}
