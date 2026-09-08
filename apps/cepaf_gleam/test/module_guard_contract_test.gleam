//// Regression oracle for exact parsed top-level field presence.
//// Scope: syntax/presence guard; value schemas and workload authorization remain separate.

import cepaf_gleam/ha/module_guard
import gleam/dynamic/decode
import gleam/io
import gleam/json
import gleam/list
import gleam/string
import gleeunit/should

pub fn cases() -> List(#(String, String, String, Bool)) {
  [
    #("genuine", "{\"status\":\"ok\"}", "status", True),
    #(
      "value_substring",
      "{\"message\":\"no status available\"}",
      "status",
      False,
    ),
    #("longer_key", "{\"substatus\":1}", "status", False),
    #("nested_key", "{\"child\":{\"status\":1}}", "status", False),
    #("array_root", "[{\"status\":1}]", "status", False),
    #("malformed", "{\"status\":", "status", False),
    #("trailing_text", "{\"status\":1}garbage", "status", False),
    #("two_documents", "{\"status\":1}{\"status\":2}", "status", False),
    #("string_root", "\"status\"", "status", False),
    #("missing", "{\"ok\":true}", "status", False),
    #("empty", "", "status", False),
    #("empty_object", "{}", "status", False),
    #("null_value", "{\"status\":null}", "status", True),
    #("false_value", "{\"status\":false}", "status", True),
    #("escaped_key", "{\"st\\u0061tus\":1}", "status", True),
    #("whitespace", " \n{\"status\" : 1}\t", "status", True),
    #("case_sensitive", "{\"Status\":1}", "status", False),
    #("unicode_key", "{\"状態\":\"ok\"}", "状態", True),
    #("quoted_key", "{\"a\\\"b\":1}", "a\"b", True),
    #("nul_name", "{\"a\\u0000b\":1}", "a\u{0000}b", True),
  ]
}

pub fn passed(body: String, field: String) -> Bool {
  case module_guard.guard_json(body, "contract", field) {
    module_guard.GuardPassed(_) -> True
    _ -> False
  }
}

pub fn exact_key_cases_test() {
  list.each(cases(), fn(c) {
    let #(label, body, field, expected) = c
    #(label, passed(body, field)) |> should.equal(#(label, expected))
  })
}

pub fn passing_bytes_preserved_test() {
  list.each(cases(), fn(c) {
    let #(_, body, field, expected) = c
    case expected {
      True ->
        module_guard.guard_json(body, "contract", field)
        |> should.equal(module_guard.GuardPassed(body))
      False -> Nil
    }
  })
}

pub fn fallback_escapes_metadata_test() {
  case module_guard.guard_json("{\"other\":1}", "e\"\n", "s\"\n") {
    module_guard.GuardFailed(_, fallback) ->
      json.parse(fallback, {
        use endpoint <- decode.field("endpoint", decode.string)
        use field <- decode.field("field", decode.string)
        decode.success(#(endpoint, field))
      })
      |> should.equal(Ok(#("e\"\n", "s\"\n")))
    _ -> should.fail()
  }
}

pub fn malformed_nonempty_rejected_test() {
  case module_guard.guard_json_nonempty("not json", "contract") {
    module_guard.GuardFailed(_, _) -> True
    _ -> False
  }
  |> should.be_true()
}

pub fn large_payload_rejected_test() {
  let body =
    "{\"status\":1,\"padding\":\"" <> string.repeat("x", 1_048_576) <> "\"}"
  passed(body, "status") |> should.be_false()
  case module_guard.guard_json_nonempty(body, "contract") {
    module_guard.GuardFailed(_, _) -> True
    _ -> False
  }
  |> should.be_true()
}

pub fn metadata_cannot_change_json_verdict_test() {
  module_guard.guard_json("{\"other\":1}", "empty endpoint", "status")
  |> module_guard.verdict
  |> should.equal(module_guard.FailedMissingField)
  module_guard.guard_json("not json", "empty missing field", "status")
  |> module_guard.verdict
  |> should.equal(module_guard.FailedCorrupted)
}

pub fn report() {
  let rows =
    list.map(cases(), fn(c) {
      let #(id, body, field, expected) = c
      json.object([
        #("id", json.string(id)),
        #("body", json.string(body)),
        #("field", json.string(field)),
        #("expected", json.bool(expected)),
        #("actual", json.bool(passed(body, field))),
      ])
    })
  json.array(rows, fn(x) { x }) |> json.to_string |> io.println
}
