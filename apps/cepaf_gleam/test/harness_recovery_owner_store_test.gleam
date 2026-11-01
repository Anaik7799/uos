import cepaf_gleam/harness/recovery_owner_store as s
import gleam/json
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should

fn binding() {
  s.Binding(
    "fixture",
    string.repeat("a", 64),
    string.repeat("b", 64),
    string.repeat("c", 64),
  )
}

pub fn record_digest_is_binding_and_phase_specific_test() {
  let b = binding()
  let r = s.Entry(1, s.Pending, None, None, "")
  s.record_digest(b, r)
  |> should.not_equal(s.record_digest(s.Binding(..b, owner_id: "other"), r))
  s.record_digest(b, r)
  |> should.not_equal(s.record_digest(b, s.Entry(..r, phase: s.Unknown)))
  s.sha(s.record_digest(b, r)) |> should.be_true()
}

pub fn forged_record_sha_and_foreign_identity_are_rejected_test() {
  let b = binding()
  let raw =
    json.to_string(
      json.object([
        #("status", json.string("ok")),
        #("code", json.string("APPENDED")),
        #("binding", s.binding_value(b)),
        #(
          "record",
          json.object([
            #("sequence", json.int(1)),
            #("phase", json.string("pending")),
            #("receipt_sha256", json.null()),
            #("previous_sha256", json.null()),
            #("sha256", json.string(string.repeat("0", 64))),
          ]),
        ),
        #("authority", json.string("NONE")),
      ]),
    )
  s.decode_reply(raw, b) |> should.be_error()
  s.valid_binding(s.Binding(..b, operation_id: "sha256:" <> b.operation_id))
  |> should.be_false()
  s.body(b, Some(#(1, s.Pending, None)), None) |> should.be_ok()
}
