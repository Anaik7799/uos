//// [C3I-SIL6-MSTS] <c3i-module><identity><module>cepaf_gleam/ignition_launch_request</module></identity>
////   <fractal-topology><layer>L5_COGNITIVE</layer></fractal-topology>
////   <compliance><stamp-controls>SC-ZMOF-001, SC-ZMOF-005, SC-BOOT-001</stamp-controls></compliance>
//// </c3i-module>
////
//// One-shot operator entry point for dispatching a Rust ignition launch request
//// through the C3I Gleam MoZ client. This keeps the operator surface in
//// cepaf_gleam while the authoritative ignition daemon owns container mutation.

import cepaf_gleam/c3i/nif as c3i_nif
import gleam/io
import gleam/json

@external(erlang, "cepaf_gleam_ffi", "generate_id")
fn generate_id() -> String

pub fn main() {
  let request_id = generate_id()
  let response_topic = "indrajaal/l5/cog/mcp/res/" <> request_id
  let params =
    json.object([
      #("mode", json.string("prod")),
      #("scope", json.string("swarm")),
      #(
        "reason",
        json.string("operator requested swarm start from cepaf_gleam"),
      ),
      #("source", json.string("cepaf_gleam/ignition_launch_request")),
    ])
  let topic = "indrajaal/l5/cog/mcp/req/ignition_launch/" <> request_id
  let payload =
    json.object([
      #("jsonrpc", json.string("2.0")),
      #("method", json.string("ignition_launch")),
      #("params", params),
      #("id", json.string(request_id)),
    ])
    |> json.to_string()

  let open_result = c3i_nif.zenoh_open("{}")
  let put_result = c3i_nif.zenoh_put(topic, payload)

  io.println(
    "Ignition launch request published via cepaf_gleam native Zenoh NIF",
  )
  io.println("request_id=" <> request_id)
  io.println("response_topic=" <> response_topic)
  io.println("zenoh_open=" <> open_result)
  io.println("zenoh_put=" <> put_result)
}
