import cepaf_gleam/telegram/mini_control as control
import cepaf_gleam/telegram/mini_api as api
import gleam/http
import gleam/http/request
import gleam/json
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import mini_test_vectors as v

fn config() {
  api.configuration("synthetic-mini-test-token", [api.AllowedIdentity(42, None)], 300)
  |> should.be_ok
}
fn body(auth: String, nonce: String, expected: String, target: String) {
  json.object([
    #("init_data", json.string(auth)), #("path", json.string("/mini-app/telemetry")),
    #("action", json.string("set_vm_logger_level")), #("request_id", json.string(nonce)),
    #("expected_level", json.string(expected)), #("target_level", json.string(target)),
  ]) |> json.to_string
}
const nonce = "0123456789abcdef0123456789abcdef"
pub fn authenticated_identity_and_request_namespace_test() {
  let i = control.parse(body(v.valid, nonce, "notice", "info"), config(), 1000) |> should.be_ok
  control.request_key("123", i) |> should.not_equal(control.request_key("456", i))
  control.request_key("123", i) |> string.length |> should.equal(77)
}
pub fn control_auth_and_expiry_test() {
  control.parse(body(v.wrong_user, nonce, "notice", "info"), config(), 1000) |> should.be_error
  control.parse(body(v.expired, nonce, "notice", "info"), config(), 1000) |> should.be_error
  control.parse(body(v.valid, nonce, "notice", "info"), config(), 1301) |> should.be_error
}
pub fn signed_group_restriction_test() {
  let c = api.configuration("synthetic-mini-test-token",
    [api.AllowedIdentity(42, Some(-100123))], 300) |> should.be_ok
  control.parse(body(v.chat, nonce, "notice", "info"), c, 1000) |> should.be_ok
  control.parse(body(v.wrong_chat, nonce, "notice", "info"), c, 1000) |> should.be_error
  control.parse(body(v.valid, nonce, "notice", "info"), c, 1000) |> should.be_error
}
pub fn closed_action_and_level_schema_test() {
  let b = body(v.valid, nonce, "notice", "info")
  control.parse(string.replace(b, "set_vm_logger_level", "run_shell"), config(), 1000) |> should.be_error
  control.parse(string.replace(b, "telemetry", "config"), config(), 1000) |> should.be_error
  control.parse(body(v.valid, nonce, "notice", "unknown"), config(), 1000) |> should.be_error
  control.parse(body(v.valid, nonce, "notice", "notice"), config(), 1000) |> should.be_error
}
pub fn nonce_and_size_bounds_test() {
  control.parse(body(v.valid, "ABCDEF", "notice", "info"), config(), 1000) |> should.be_error
  control.parse(body(v.valid, string.repeat("a", 33), "notice", "info"), config(), 1000) |> should.be_error
  control.parse(string.repeat("x", 8193), config(), 1000) |> should.be_error
}
pub fn control_absence_never_reports_zero_effect_certainty_test() {
  let r = request.new() |> request.set_path(control.action_path)
    |> request.set_method(http.Post) |> request.set_header("content-type", "application/json")
    |> request.set_body(body(v.valid, nonce, "notice", "info"))
  let result = control.handle(r)
  result.status |> should.equal(503)
  string.contains(result.body, "\"effects_this_request\":null") |> should.be_true
}

fn alert_body(auth: String,action: String,expected: String,target: String) {
  json.to_string(json.object([
    #("init_data",json.string(auth)),#("path",json.string("/mini-app/alerts")),
    #("action",json.string(action)),#("request_id",json.string(nonce)),
    #("expected_episode_set",json.string(expected)),#("target_episode",json.string(target))
  ]))
}
pub fn alert_acknowledgement_closed_schema_test() {
  let sha=string.repeat("a",64)
  control.parse(alert_body(v.valid,"acknowledge_all",sha,"all"),config(),1000) |> should.be_ok
  control.parse(alert_body(v.valid,"acknowledge_alert",sha,sha),config(),1000) |> should.be_ok
  control.parse(alert_body(v.valid,"acknowledge_all",sha,sha),config(),1000) |> should.be_error
  control.parse(alert_body(v.valid,"acknowledge_alert",sha,"all"),config(),1000) |> should.be_error
  control.parse(alert_body(v.valid,"acknowledge_all","bad","all"),config(),1000) |> should.be_error
}
pub fn alert_acknowledgement_auth_and_page_test() {
  let sha=string.repeat("a",64)
  control.parse(alert_body(v.wrong_user,"acknowledge_all",sha,"all"),config(),1000) |> should.be_error
  control.parse(alert_body(v.expired,"acknowledge_all",sha,"all"),config(),1000) |> should.be_error
  let b=alert_body(v.valid,"acknowledge_all",sha,"all")
  control.parse(string.replace(b,"/mini-app/alerts","/mini-app/telemetry"),config(),1000) |> should.be_error
  control.parse(string.replace(b,"\"target_episode\"","\"run_shell\""),config(),1000) |> should.be_error
}

/// Review A-06 (wave 6l): the logger can be made quieter, never silenced.
pub fn logger_target_none_is_refused_test() {
  control.level("none") |> should.equal(False)
  control.level("emergency") |> should.equal(True)
  control.level("all") |> should.equal(True)
  control.level("debug") |> should.equal(True)
}
