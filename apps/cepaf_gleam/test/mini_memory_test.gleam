import cepaf_gleam/telegram/mini_control as control
import cepaf_gleam/telegram/mini_memory as memory
import cepaf_gleam/telegram/mini_api as api
import gleam/json
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import mini_test_vectors as v
fn body(action: String, version: Int, sha: String) {
  json.to_string(json.object([
    #("init_data",json.string(v.valid)),#("path",json.string("/mini-app/chat")),
    #("action",json.string(action)),#("request_id",json.string("0123456789abcdef0123456789abcdef")),
    #("expected_version",json.int(version)),#("expected_sha256",json.string(sha)),
  ]))
}
fn config() { api.configuration("synthetic-mini-test-token",[api.AllowedIdentity(42,None)],300) |> should.be_ok }
pub fn memory_schema_and_namespace_test() {
  let a=control.parse(body("clear_history",0,""),config(),1000) |> should.be_ok
  let b=control.parse(body("reset_history",0,""),config(),1000) |> should.be_ok
  control.request_key("333444",a) |> should.not_equal(control.request_key("333444",b))
  control.parse(body("clear_history",-1,""),config(),1000) |> should.be_error
  control.parse(body("clear_history",1,""),config(),1000) |> should.be_error
  control.parse(body("clear_history",0,string.repeat("a",64)),config(),1000) |> should.be_error
}
pub fn memory_auth_page_and_scope_test() {
  let b=body("clear_history",1,string.repeat("a",64))
  control.parse(b,config(),1000) |> should.be_ok
  control.parse(string.replace(b,v.valid,v.wrong_user),config(),1000) |> should.be_error
  control.parse(string.replace(b,"/mini-app/chat","/mini-app/telemetry"),config(),1000) |> should.be_error
  control.parse(b,config(),1301) |> should.be_error
}
pub fn memory_profile_scope_test() {
  let profile="{\"memory\":{\"database\":\"/home/an/uos-agent-runtime/20261024-0555/mini-history-unit/history.sqlite3\",\"grants\":[{\"user_id\":42,\"chat_id\":42}]}}"
  let assert Some(c)=memory.configuration(profile,"333444:token") |> should.be_ok
  memory.scope(c,42,None) |> should.be_ok
  memory.scope(c,43,None) |> should.be_error
  memory.scope(c,42,Some(-100123)) |> should.be_error
  memory.configuration(string.replace(profile,"mini-history-unit","../elsewhere"),"333444:token") |> should.be_error
  memory.configuration("{}", "333444:token") |> should.equal(Ok(None))
}
