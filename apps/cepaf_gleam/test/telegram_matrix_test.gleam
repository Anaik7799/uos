import cepaf_gleam/harness/telegram_matrix_report as report
import cepaf_gleam/harness/telegram_ingress_guard as guard
import cepaf_gleam/harness/telegram_tool_command as tool
import gleam/list
import gleam/result
import gleam/string
import gleeunit/should

pub fn observed_versions_not_federation_claim_test() {
  let assert Ok(raw)=report.project("{\"versions\":[\"r0.6.1\",\"v1.18\"],\"unstable_features\":{\"feature\":true},\"private\":\"CANARY\"}")
  string.contains(raw,"\"supported_versions\":[\"r0.6.1\",\"v1.18\"]") |> should.be_true
  string.contains(raw,"\"unstable_feature_count\":1") |> should.be_true
  string.contains(raw,"\"federation_health\":\"UNOBSERVED\"") |> should.be_true
  string.contains(raw,"CANARY") |> should.be_false
  string.contains(raw,"http://nas-1.tail55d152.ts.net:6167/") |> should.be_true
}
pub fn malformed_versions_refused_test() {
  list.each(["{}","[]","{\"versions\":[]}","{\"versions\":[\"v1.1\",\"v1.1\"]}",
    "{\"versions\":[\"CURRENT\"]}","{\"versions\":[\"v1.1\n\"]}",
    "{\"versions\":[\"v1.1\"],\"unstable_features\":{\"x\":\"yes\"}}",
    string.repeat("x",16385)],fn(raw){report.project(raw) |> result.is_error |> should.be_true})
}
pub fn optional_flags_and_version_bounds_test() {
  report.project("{\"versions\":[\"v1.18\"]}") |> result.is_ok |> should.be_true
  list.each(["v1","v1..2","v+1.2","v1.1234567","v1.2.3.4.5"],fn(v){
    report.project("{\"versions\":[\""<>v<>"\"]}") |> result.is_error |> should.be_true
  })
}
pub fn fixed_scope_at_ingress_test() {
  guard.classify_directive("/sutra") |> should.equal(guard.DirectReadTool("query_matrix_versions"))
  tool.parse("query_matrix_versions {}") |> should.equal(Ok(tool.Matrix))
  tool.parse("query_matrix_versions {\"url\":\"http://evil/\"}") |> result.is_error |> should.be_true
  case guard.classify_directive("/sutra foreign") {
    guard.DeniedMutation(_,_) -> True
    _ -> False
  } |> should.be_true
}
