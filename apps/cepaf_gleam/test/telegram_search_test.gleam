import cepaf_gleam/harness/telegram_task_command as task
import cepaf_gleam/harness/telegram_search_report as report
import cepaf_gleam/harness/telegram_tool_command as tool
import cepaf_gleam/harness/telegram_ingress_guard as guard
import gleam/json
import gleam/list
import gleam/int
import gleam/result
import gleam/string
import gleeunit/should

fn row(id:String,state:String) {
  json.object([#("task_id",json.string(id)),#("state",json.string(state)),
    #("attempt",json.int(1)),#("result_present",json.bool(False)),
    #("dependencies",json.array(["PRIOR"],json.string)),
    #("worker",json.string("PRIVATE_WORKER")),#("result",json.string("PRIVATE_RESULT"))])
}
fn snapshot(rows:List(json.Json)) {
  json.object([#("observer",json.string("uos.sa_plan.observer.v1")),
    #("authority",json.string("NONE")),#("runtime_admission",json.string("NOT_GRANTED")),
    #("plan_id",json.string("plan-a")),#("observed_tasks_total",json.int(list.length(rows))),
    #("selected_count",json.int(list.length(rows))),
    #("full_observation_sha256",json.string(string.repeat("a",64))),
    #("tasks",json.array(rows,fn(x){x}))]) |> json.to_string
}
fn good() { snapshot([row("ALPHA","available"),row("BETA","completed")]) }
pub fn task_id_state_search_and_redaction_test() {
  let assert Ok(a)=task.search_project(good(),"plan-a","alpha")
  string.contains(a,"ALPHA") |> should.be_true
  string.contains(a,"BETA") |> should.be_false
  string.contains(a,"PRIVATE") |> should.be_false
  string.contains(a,"configured_plan_task_ids_and_states") |> should.be_true
  let assert Ok(b)=task.search_project(good(),"plan-a","COMPLETED")
  string.contains(b,"BETA") |> should.be_true
  string.contains(b,"ALPHA") |> should.be_false
  let assert Ok(n)=task.search_project(good(),"plan-a","absent")
  string.contains(n,"\"matched_total\":0") |> should.be_true
}
pub fn empty_plan_and_truncated_catalog_test() {
  let assert Ok(empty)=task.search_project(snapshot([]),"plan-a","")
  string.contains(empty,"\"matched_total\":0") |> should.be_true
  let rows=list.repeat(0,21) |> list.index_map(fn(_,i){row("TASK-"<>int.to_string(i),"available")})
  let assert Ok(raw)=task.search_project(snapshot(rows),"plan-a","task")
  string.contains(raw,"\"shown\":20") |> should.be_true
  string.contains(raw,"\"matched_total\":21") |> should.be_true
  string.contains(raw,"\"truncated\":true") |> should.be_true
}
pub fn snapshot_identity_completeness_and_duplicates_test() {
  list.each([
    string.replace(good(),"uos.sa_plan.observer.v1","forged"),
    string.replace(good(),"NONE","GRANTED"),
    string.replace(good(),"NOT_GRANTED","ADMITTED"),
    string.replace(good(),"plan-a","plan-b"),
    string.replace(good(),"\"selected_count\":2","\"selected_count\":1"),
    string.replace(good(),"\"observed_tasks_total\":2","\"observed_tasks_total\":3"),
    snapshot([row("ALPHA","available"),row("ALPHA","completed")]),
    snapshot([row("BAD ID","available")]),
    snapshot([row("ALPHA","magic")]),
    string.replace(good(),"\"attempt\":1","\"attempt\":-1"),
    string.replace(good(),"[\"PRIOR\"]","[\"PRIOR\",\"PRIOR\"]"),
    string.replace(good(),string.repeat("a",64),string.repeat("A",64)),
  ],fn(raw){task.search_project(raw,"plan-a","") |> result.is_error |> should.be_true})
}
pub fn query_and_payload_limits_test() {
  list.each(["x\n","x\r","x\t","x\u{0}",string.repeat("é",65)],fn(q){
    task.search_project(good(),"plan-a",q) |> result.is_error |> should.be_true
  })
  task.search_project(string.repeat("x",262145),"plan-a","") |> result.is_error |> should.be_true
}
fn envelope(schema:String,authority:String) {
  "{\"schema\":\""<>schema<>"\",\"status\":\"observed\",\"authority\":\""<>authority
  <>"\",\"runtime_admission\":\"NOT_GRANTED\"}"
}
pub fn combined_partial_failure_is_not_empty_success_test() {
  let t=envelope("uos.telegram.task_search.v1","NONE")
  let d=envelope("uos.telegram.knowledge.v1","observation_only")
  string.contains(report.combine(Ok(t),Ok(d)),"\"status\":\"observed\"") |> should.be_true
  let partial=report.combine(Ok(t),Error("PRIVATE_FAILURE"))
  string.contains(partial,"\"status\":\"partial\"") |> should.be_true
  string.contains(partial,"PRIVATE_FAILURE") |> should.be_false
  let unavailable=report.combine(Error("secret"),Ok("{bad"))
  string.contains(unavailable,"\"status\":\"unavailable\"") |> should.be_true
  string.contains(unavailable,"{bad") |> should.be_false
  string.contains(report.combine(Ok(string.repeat("x",16385)),Ok(d)),"\"status\":\"partial\"") |> should.be_true
}
pub fn command_tool_scope_test() {
  guard.classify_directive("/search ALPHA") |> should.equal(guard.PreservedDirective("/search",["ALPHA"]))
  tool.parse("query_search {\"query\":\"ALPHA\"}") |> should.equal(Ok(tool.Search("ALPHA")))
  tool.parse("query_search {}") |> should.equal(Ok(tool.Search("")))
  list.each(["{\"plan\":\"foreign\"}","{\"query\":1}","{\"query\":\"a\",\"root\":\"/etc\"}"],fn(q){
    tool.parse("query_search "<>q) |> result.is_error |> should.be_true
  })
}
