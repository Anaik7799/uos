import cepaf_gleam/harness/telegram_fmea_report as report
import cepaf_gleam/harness/telegram_fmea_reader as reader
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{None,Some}
import gleam/result
import gleam/string
import gleeunit/should

const digest="aabbccddaabbccddaabbccddaabbccddaabbccddaabbccddaabbccddaabbccdd"
const now=1_704_067_210_000
fn mode(id:String,s:Int)->json.Json {
  json.object([#("id",json.string(id)),#("cause",json.string("recorded cause")),
    #("effect",json.string("recorded effect")),#("controls",json.string("recorded controls")),
    #("s",json.int(s)),#("o",json.int(3)),#("det",json.int(3)),#("rpn",json.int(s*9)),#("band",json.int(4))])
}
fn row(plan:String,task:String,modes:List(json.Json))->json.Json {
  json.object([#("assessment_id",json.string("assessment")),#("plan_id",json.string(plan)),
    #("task_id",json.string(task)),#("observed_at",json.string("2024-01-01T00:00:00Z")),
    #("valid_until",json.string("2024-01-01T01:00:00Z")),#("task_state",json.string("executing")),
    #("fmea_modes",json.array(modes,fn(x){x}))])
}
fn raw()->String { json.array([row("p","task",[mode("FM-1",4)])],fn(x){x}) |> json.to_string }
pub fn fresh_record_retains_scores_and_limits_claims_test() {
  let assert Ok(out)=report.project(raw(),digest,"p",None,now)
  string.contains(out,"\"rpn\":36") |> should.be_true
  string.contains(out,"\"freshness\":\"fresh\"") |> should.be_true
  string.contains(out,"\"age_ms\":10000") |> should.be_true
  string.contains(out,"NOT_GRANTED") |> should.be_true
  string.contains(out,"not measured runtime failure rates") |> should.be_true
}
pub fn expiry_and_future_are_not_fresh_test() {
  let assert Ok(stale)=report.project(raw(),digest,"p",None,now+3_600_000)
  string.contains(stale,"\"freshness\":\"stale\"") |> should.be_true
  let assert Ok(future)=report.project(raw(),digest,"p",None,now-20_000)
  string.contains(future,"\"freshness\":\"future\"") |> should.be_true
  string.contains(future,"\"age_ms\":null") |> should.be_true
}
pub fn foreign_plan_and_absent_task_test() {
  let raw=json.array([row("p","task",[mode("FM-1",4)]),row("foreign","private-task",[mode("secret-mode",5)])],fn(x){x}) |> json.to_string
  let assert Ok(out)=report.project(raw,digest,"p",Some("task"),now)
  string.contains(out,"private-task") |> should.be_false
  string.contains(out,"secret-mode") |> should.be_false
  report.project(raw,digest,"p",Some("absent"),now) |> should.equal(Error("task_not_found"))
  report.project(raw,digest,"missing-plan",None,now) |> result.is_error |> should.be_true
}
pub fn tampered_rpn_and_scores_refuse_test() {
  list.each(["\"rpn\":35","\"rpn\":-1"],fn(value){
    report.project(string.replace(raw(),"\"rpn\":36",value),digest,"p",None,now) |> result.is_error |> should.be_true
  })
  list.each(["\"s\":0","\"s\":6"],fn(value){
    report.project(string.replace(raw(),"\"s\":4",value),digest,"p",None,now) |> result.is_error |> should.be_true
  })
}
pub fn ambiguous_task_and_mode_identity_refuse_test() {
  let a=row("p","task",[mode("FM-1",4)])
  let duplicate=json.array([a,a],fn(x){x}) |> json.to_string
  report.project(duplicate,digest,"p",None,now) |> result.is_error |> should.be_true
  let modes=json.array([row("p","task",[mode("FM-1",4),mode("FM-1",5)])],fn(x){x}) |> json.to_string
  report.project(modes,digest,"p",None,now) |> result.is_error |> should.be_true
}
pub fn bounded_invalid_and_empty_sources_refuse_test() {
  list.each(["[]","{}","[{",string.repeat(" ",1_048_577)],fn(input){
    report.project(input,digest,"p",None,now) |> result.is_error |> should.be_true
  })
  report.project(raw(),"bad","p",None,now) |> result.is_error |> should.be_true
  report.project(raw(),digest,"../p",None,now) |> result.is_error |> should.be_true
  report.project(raw(),digest,"p",None,0) |> result.is_error |> should.be_true
  let empty=json.array([row("p","task",[])],fn(x){x}) |> json.to_string
  report.project(empty,digest,"p",None,now) |> result.is_error |> should.be_true
}
pub fn deterministic_risk_order_and_truncation_test() {
  let rows=[row("p","z",[mode("FM",1)]),row("p","b",[mode("FM",5)]),row("p","a",[mode("FM",5)]),
    row("p","c",[mode("FM",4)]),row("p","d",[mode("FM",3)]),row("p","e",[mode("FM",2)])]
  let assert Ok(out)=report.project(json.array(rows,fn(x){x}) |> json.to_string,digest,"p",None,now)
  let decoder=decode.field("assessments",decode.list(decode.field("task_id",decode.string,decode.success)),decode.success)
  json.parse(out,decoder) |> should.equal(Ok(["a","b","c","d","e"]))
  string.contains(out,"\"truncated\":true") |> should.be_true
  string.contains(out,"\"total_matching_tasks\":6") |> should.be_true
}
pub fn invalid_timestamps_and_controls_refuse_test() {
  list.each(["2024-02-30T00:00:00Z","not-a-date"],fn(value){
    report.project(string.replace(raw(),"2024-01-01T00:00:00Z",value),digest,"p",None,now)
      |> result.is_error |> should.be_true
  })
  report.project(string.replace(raw(),"recorded cause","bad\\u0000cause"),digest,"p",None,now)
    |> result.is_error |> should.be_true
}
pub fn trusted_source_scope_test() {
  reader.valid_source("/home/an/NAS-setup/uos/governance/planning/20261024-1325-telegram-runtime-risk.json",False) |> should.be_true
  list.each(["/private/risk.json","/home/an/NAS-setup/uos/governance/planning/../private.json","relative.json"],fn(p){
    reader.valid_source(p,False) |> should.be_false
  })
  reader.valid_source("/tmp/uos-test/risk.json",True) |> should.be_true
}
