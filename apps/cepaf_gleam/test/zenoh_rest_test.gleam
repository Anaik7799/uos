import cepaf_gleam/zenoh/rest
import gleeunit/should

pub fn exact_text_reply_test() {
  rest.decode_reply("c3i/recovery/test", "[{\"key\":\"c3i/recovery/test\",\"encoding\":\"text/plain\",\"value\":\"observed\"}]")
  |> should.equal(Ok("observed"))
}

pub fn json_reply_is_serialized_as_payload_test() {
  rest.decode_reply("c3i/recovery/test", "[{\"key\":\"c3i/recovery/test\",\"encoding\":\"application/json\",\"value\":{\"observed\":true}}]")
  |> should.equal(Ok("{\"observed\":true}"))
}

pub fn missing_reply_is_not_query_success_test() {
  rest.decode_reply("c3i/recovery/test", "[]") |> should.equal(Error("zenoh_no_reply"))
}

pub fn wrong_key_is_not_query_success_test() {
  rest.decode_reply("c3i/recovery/test", "[{\"key\":\"other\",\"encoding\":\"text/plain\",\"value\":\"bad\"}]")
  |> should.equal(Error("zenoh_reply_key_mismatch"))
}

pub fn malformed_or_incomplete_envelope_rejected_test() {
  rest.decode_reply("c3i/recovery/test", "not-json") |> should.equal(Error("invalid_zenoh_rest_envelope"))
  rest.decode_reply("c3i/recovery/test", "[{\"value\":\"bad\"}]") |> should.equal(Error("invalid_zenoh_rest_envelope"))
}

pub fn unknown_encoding_rejected_test() {
  rest.decode_reply("c3i/recovery/test", "[{\"key\":\"c3i/recovery/test\",\"encoding\":\"application/octet-stream\",\"value\":\"bad\"}]")
  |> should.equal(Error("unsupported_zenoh_encoding"))
}

pub fn duplicate_reply_rejected_test() {
  rest.decode_reply("x", "[{\"key\":\"x\",\"encoding\":\"text/plain\",\"value\":\"a\"},{\"key\":\"x\",\"encoding\":\"text/plain\",\"value\":\"b\"}]")
  |> should.equal(Error("ambiguous_zenoh_replies"))
}

pub fn text_value_type_checked_test() {
  rest.decode_reply("x", "[{\"key\":\"x\",\"encoding\":\"text/plain\",\"value\":{}}]")
  |> should.equal(Error("invalid_zenoh_text_value"))
}

pub fn path_injection_and_wildcards_rejected_before_network_test() {
  rest.put("c3i/a2a/foreign/probe/id", "raw-text")
  |> should.equal(Error("invalid_zenoh_key_or_payload_bound"))
  rest.put("c3i/../shared", "x") |> should.equal(Error("invalid_zenoh_key_or_payload_bound"))
  rest.get("c3i/**") |> should.equal(Error("invalid_zenoh_key"))
  rest.get("c3i/x?query=all") |> should.equal(Error("invalid_zenoh_key"))
  rest.get("c3i/x\r\nHost: evil") |> should.equal(Error("invalid_zenoh_key"))
  rest.valid_key("") |> should.be_false
  rest.valid_key("/c3i/x") |> should.be_false
}

pub fn arbitrary_native_or_remote_config_rejected_before_network_test() {
  rest.probe("{\"connect\":{\"endpoints\":[\"tcp/other:7447\"]}}")
  |> should.equal(Error("unsupported_zenoh_rest_config"))
}

pub fn redirects_and_publication_failures_never_pass_test() {
  rest.http_ok(#(302, "redirect")) |> should.equal(Error("zenoh_rest_http_failure"))
  rest.publication_ok(#(500, "failed")) |> should.equal(Error("zenoh_rest_publication_failed"))
  rest.publication_ok(#(204, "")) |> should.equal(Ok(Nil))
}
