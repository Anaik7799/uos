import cepaf_gleam/harness/telegram_brief_report as brief
import gleam/int
import gleam/json
import gleam/list
import gleam/string
import gleeunit/should

fn task(id: String,state: String) -> json.Json {
  json.object([#("task_id",json.string(id)),#("state",json.string(state)),
    #("worker",json.string("PRIVATE_WORKER")),#("result",json.string("PRIVATE_RESULT"))])
}
fn tasks(rows: List(json.Json)) -> String {
  json.object([
    #("observer",json.string("uos.sa_plan.observer.v1")),
    #("authority",json.string("NONE")),#("runtime_admission",json.string("NOT_GRANTED")),
    #("plan_id",json.string("uos/test/brief")),#("observed_tasks_total",json.int(list.length(rows))),
    #("selected_count",json.int(list.length(rows))),
    #("full_observation_sha256",json.string(string.repeat("a",64))),
    #("tasks",json.array(rows,fn(r) { r })),
  ]) |> json.to_string
}
fn service(name: String,state: String,code: json.Json) -> json.Json {
  json.object([#("service",json.string(name)),#("observation",json.string(state)),
    #("http_status",code),#("elapsed_ms",json.int(10))])
}
fn status() -> String {
  json.object([
    #("schema",json.string("uos.telegram.operational-status.v1")),
    #("status",json.string("partially_observed")),
    #("scope",json.string("fixed_service_http_reachability_and_local_telegram_state")),
    #("runtime_admission",json.string("NOT_GRANTED")),#("global_healthy",json.null()),
    #("observed_at_us",json.int(1001)),
    #("services",json.array([
      service("matrix","responding",json.int(200)),
      service("cockpit","authentication_required",json.int(401)),
      service("zenoh","unreachable_or_refused",json.null()),
      service("peer_runtime","redirect_not_followed",json.int(302)),
    ],fn(r) { r })),
    #("telegram",json.object([
      #("service_epoch",json.int(1)),#("store_generation",json.int(2)),
      #("next_update_offset",json.int(123)),#("pending_recovery",json.bool(True)),
      #("conversation_configured",json.bool(False)),#("model_connectivity",json.string("not_probed")),
    ])),
    #("clock_synchronization",json.object([#("offset",json.float(0.25))])),
    #("unknown",json.string("PRIVATE_UNKNOWN café")),
  ]) |> json.to_string
}
fn project(t: String,s: String) -> Result(String,String) {
  brief.project("uos/test/brief",t,s,1000,2000)
}
pub fn current_counts_and_no_health_inference_test() {
  let assert Ok(out)=project(tasks([task("done","completed"),task("running","executing"),task("waiting","available")]),status())
  string.contains(out,"1/3 task records completed; 1 marked executing; 2 not completed.") |> should.equal(True)
  string.contains(out,"1/4 fixed endpoints returned 2xx.") |> should.equal(True)
  string.contains(out,"Telegram recovery is pending.") |> should.equal(True)
  string.contains(out,"UNASSESSED") |> should.equal(True)
  string.contains(out,"NOT_GRANTED") |> should.equal(True)
  string.contains(out,"dependency-ready") |> should.equal(True)
  string.contains(out,"PRIVATE_") |> should.equal(False)
}
pub fn empty_plan_is_not_full_completion_test() {
  let assert Ok(out)=project(tasks([]),status())
  string.contains(out,"0/0 task records completed") |> should.equal(True)
  string.contains(out,"100%") |> should.equal(False)
}
pub fn unknown_and_private_fields_not_projected_test() {
  let assert Ok(out)=project(tasks([task("a","available")]),status())
  string.contains(out,"PRIVATE_WORKER") |> should.equal(False)
  string.contains(out,"PRIVATE_RESULT") |> should.equal(False)
  string.contains(out,"PRIVATE_UNKNOWN") |> should.equal(False)
  string.contains(out,"clock_synchronization") |> should.equal(False)
}
pub fn standard_json_escape_and_ignored_float_test() {
  let t=tasks([task("task/a","available")]) |> string.replace("task/a","task\\u002fa")
  let assert Ok(out)=project(t,status())
  string.contains(out,"task/a") |> should.equal(True)
}
pub fn plan_and_schema_mismatch_refused_test() {
  let t=tasks([])
  project(string.replace(t,"uos/test/brief","foreign"),status()) |> should.be_error
  project(string.replace(t,"uos.sa_plan.observer.v1","unknown"),status()) |> should.be_error
  project(t,string.replace(status(),"uos.telegram.operational-status.v1","unknown")) |> should.be_error
}
pub fn partial_or_inconsistent_counts_refused_test() {
  let t=tasks([task("a","available")])
  project(string.replace(t,"\"selected_count\":1","\"selected_count\":0"),status()) |> should.be_error
  project(string.replace(t,"\"observed_tasks_total\":1","\"observed_tasks_total\":2"),status()) |> should.be_error
}
pub fn duplicate_and_invalid_task_rows_refused_test() {
  project(tasks([task("a","available"),task("a","completed")]),status()) |> should.be_error
  project(tasks([task("bad id","available")]),status()) |> should.be_error
  project(tasks([task("x","success")]),status()) |> should.be_error
  project(tasks([task(string.repeat("a",201),"available")]),status()) |> should.be_error
}
pub fn all_task_states_and_pending_order_test() {
  let assert Ok(out)=project(tasks([task("z","blocked"),task("b","failed"),task("x","completed"),task("a","executing"),task("c","available")]),status())
  string.contains(out,"\"non_completed_ids\":[\"a\",\"b\",\"c\",\"z\"]") |> should.equal(True)
  string.contains(out,"\"blocked\":1") |> should.equal(True)
  string.contains(out,"\"failed\":1") |> should.equal(True)
}
pub fn truncated_count_is_explicit_test() {
  let rows=indices(25,[]) |> list.map(fn(n) { task("t"<>int.to_string(n),"available") })
  let assert Ok(out)=project(tasks(rows),status())
  string.contains(out,"\"non_completed_total\":25") |> should.equal(True)
  string.contains(out,"\"truncated_count\":5") |> should.equal(True)
}
pub fn size_and_row_bounds_test() {
  project(string.repeat(" ",262_145),status()) |> should.be_error
  project(tasks([]),string.repeat(" ",65_537)) |> should.be_error
  let rows=indices(1001,[]) |> list.map(fn(n) { task("t"<>int.to_string(n),"available") })
  project(tasks(rows),status()) |> should.be_error
}
pub fn time_window_refusals_test() {
  let t=tasks([])
  brief.project("uos/test/brief",t,status(),0,2000) |> should.be_error
  brief.project("uos/test/brief",t,status(),2000,1000) |> should.be_error
  brief.project("uos/test/brief",t,status(),1000,20_001_001) |> should.be_error
  project(t,string.replace(status(),"\"observed_at_us\":1001","\"observed_at_us\":999")) |> should.be_error
  project(t,string.replace(status(),"\"observed_at_us\":1001","\"observed_at_us\":2001")) |> should.be_error
}
pub fn endpoint_and_code_consistency_refused_test() {
  let t=tasks([])
  project(t,string.replace(status(),"\"service\":\"cockpit\"","\"service\":\"matrix\"")) |> should.be_error
  project(t,string.replace(status(),"\"service\":\"cockpit\"","\"service\":\"foreign\"")) |> should.be_error
  project(t,string.replace(status(),"\"http_status\":200","\"http_status\":500")) |> should.be_error
  project(t,string.replace(status(),"\"http_status\":401","\"http_status\":null")) |> should.be_error
  project(t,string.replace(status(),"\"elapsed_ms\":10","\"elapsed_ms\":-1")) |> should.be_error
}
pub fn admission_and_health_claims_refused_test() {
  let t=tasks([])
  project(string.replace(t,"NOT_GRANTED","GRANTED"),status()) |> should.be_error
  project(t,string.replace(status(),"NOT_GRANTED","GRANTED")) |> should.be_error
  project(t,string.replace(status(),"\"global_healthy\":null","\"global_healthy\":true")) |> should.be_error
  project(t,string.replace(status(),"not_probed","connected")) |> should.be_error
}
pub fn invalid_digest_and_json_refused_test() {
  project(string.replace(tasks([]),string.repeat("a",64),"bad"),status()) |> should.be_error
  project("{",status()) |> should.be_error
  project(tasks([]),"{") |> should.be_error
}
pub fn valid_http_failure_is_reported_not_hidden_test() {
  let s=status() |> string.replace("\"observation\":\"responding\"","\"observation\":\"http_error\"") |> string.replace("\"http_status\":200","\"http_status\":503")
  let assert Ok(out)=project(tasks([]),s)
  string.contains(out,"0/4 fixed endpoints returned 2xx") |> should.equal(True)
  string.contains(out,"\"http_status\":503") |> should.equal(True)
}

fn indices(n: Int,acc: List(Int)) -> List(Int) {
  case n { 0 -> acc _ -> indices(n-1,[n,..acc]) }
}
