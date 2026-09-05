//// [C3I-SIL6-MSTS] <c3i-module><identity><module>cepaf_gleam/email_artifact_notify</module></identity>
////   <fractal-topology><layer>L7_FEDERATION</layer></fractal-topology>
////   <compliance><stamp-controls>SC-ZMOF-001, SC-NOTIFY</stamp-controls></compliance>
//// </c3i-module>
////
//// One-shot cepaf_gleam publisher for an email notification intent.
//// The actual SMTP sender remains behind the C3I Cortex/Gateway path; this
//// module only publishes the intent through native Zenoh NIF.

import cepaf_gleam/c3i/nif as c3i_nif
import gleam/io
import gleam/json

@external(erlang, "cepaf_gleam_ffi", "generate_id")
fn generate_id() -> String

pub fn main() {
  let intent_id = generate_id()
  let topic = "indrajaal/l5/cog/intent/email/" <> intent_id
  let subject = "C3I swarm ignition evidence 2026-05-11"
  let raw_text = "/email Abhijit.Naik@bountytek.com " <> subject
  let payload =
    json.object([
      #("id", json.string(intent_id)),
      #("raw_text", json.string(raw_text)),
      #("source", json.string("cepaf_gleam/email_artifact_notify")),
      #("timestamp_ms", json.int(1_778_470_697)),
      #("type", json.string("operator_email_notification")),
    ])
    |> json.to_string()

  let open_result = c3i_nif.zenoh_open("{}")
  let put_result = c3i_nif.zenoh_put(topic, payload)

  io.println(
    "Email notification intent published via cepaf_gleam native Zenoh NIF",
  )
  io.println("intent_id=" <> intent_id)
  io.println("topic=" <> topic)
  io.println("zenoh_open=" <> open_result)
  io.println("zenoh_put=" <> put_result)
}
