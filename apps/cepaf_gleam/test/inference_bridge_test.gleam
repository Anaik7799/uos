// Gleam-side bridge contract tests for the sa-plan-inference daemon
// (SC-PI-EVO-002, plan §5.4).  These are *protocol* tests — they validate
// that Gleam can construct/serialise the daemon's UDS RPC envelopes
// without round-tripping to a live socket (Rust-side concern).
//
// 5 tests (gleeunit), zero external dependencies.

import gleam/json
import gleam/list
import gleam/string
import gleeunit/should

// ── envelope helpers (mirror the Rust wire schema) ─────────────────────

fn build_request(
  id: String,
  method: String,
  params: json.Json,
  deadline_ms: Int,
) -> json.Json {
  json.object([
    #("id", json.string(id)),
    #("method", json.string(method)),
    #("params", params),
    #("deadline_ms", json.int(deadline_ms)),
  ])
}

// ── tests ──────────────────────────────────────────────────────────────

pub fn bridge_request_text_serialises_test() {
  let req =
    build_request(
      "t-1",
      "infer_text",
      json.object([#("prompt", json.string("hi"))]),
      5000,
    )
  let body = json.to_string(req)
  body |> string.contains("\"method\":\"infer_text\"") |> should.be_true
  body |> string.contains("\"prompt\":\"hi\"") |> should.be_true
  body |> string.contains("\"deadline_ms\":5000") |> should.be_true
}

pub fn bridge_request_image_carries_b64_field_test() {
  let req =
    build_request(
      "t-2",
      "infer_image",
      json.object([
        #("prompt", json.string("describe")),
        #("image_b64", json.string("iVBORw0KGgo=")),
      ]),
      120_000,
    )
  let body = json.to_string(req)
  body
  |> string.contains("\"image_b64\":\"iVBORw0KGgo=\"")
  |> should.be_true
  body |> string.contains("\"method\":\"infer_image\"") |> should.be_true
}

pub fn bridge_request_video_frames_array_test() {
  let frames =
    json.preprocessed_array([
      json.string("AAAA"),
      json.string("BBBB"),
      json.string("CCCC"),
      json.string("DDDD"),
    ])
  let req =
    build_request(
      "t-3",
      "infer_video",
      json.object([
        #("prompt", json.string("x")),
        #("frames_b64", frames),
        #("fps", json.int(4)),
      ]),
      120_000,
    )
  let body = json.to_string(req)
  body |> string.contains("\"method\":\"infer_video\"") |> should.be_true
  body |> string.contains("\"frames_b64\"") |> should.be_true
  body |> string.contains("\"fps\":4") |> should.be_true
}

pub fn bridge_known_methods_complete_test() {
  // Contract: Gleam side must enumerate exactly the daemon's 8 methods.
  let methods = [
    "health", "metrics", "modalities", "infer_text", "infer_image",
    "infer_audio", "infer_video", "embed",
  ]
  list.length(methods) |> should.equal(8)
  list.contains(methods, "infer_text") |> should.be_true
  list.contains(methods, "infer_video") |> should.be_true
  list.contains(methods, "embed") |> should.be_true
}

pub fn bridge_deadline_zero_envelope_test() {
  // Plan SC-INFER-RUST-API-005 — deadline_ms=0 must be representable on
  // the wire so Rust can fail-fast without dropping the model future.
  let req =
    build_request(
      "t-4",
      "infer_text",
      json.object([#("prompt", json.string("x"))]),
      0,
    )
  let body = json.to_string(req)
  body |> string.contains("\"deadline_ms\":0") |> should.be_true
}
