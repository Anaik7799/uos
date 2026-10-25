import cepaf_gleam/harness/telegram_evidence_status as evidence
import cepaf_gleam/harness/telegram_verification_report as report
import cepaf_gleam/harness/telegram_verification_reader as reader
import cepaf_gleam/harness/telegram_tool_command as tool
import cepaf_gleam/harness/telegram_ingress_guard as guard
import cepaf_gleam/harness/files
import gleam/json
import gleam/list
import gleam/option.{None,Some}
import gleam/result
import gleam/string
import gleeunit/should

pub const candidate="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
const sha="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
fn record(id:String,outcome:String,runtime,formal,reason:String) {
 json.object([#("id",json.string(id)),#("outcome",json.string(outcome)),
 #("runtime_sha256",case runtime {None->json.null() Some(s)->json.string(s)}),
 #("formal_sha256",case formal {None->json.null() Some(s)->json.string(s)}),#("reason",json.string(reason))])
}
pub fn fixture(now:Int,variant:String)->String {
 let observed=case variant {"stale"->now-3_600_001 _->now}
 let id=case variant {"foreign"->"cccccccccccccccccccccccccccccccccccccccc" _->candidate}
 let rows=case variant {
  "empty"->[]
  "all"->list.map(report.checkpoints,fn(p){record(p.0,"PASS",Some(sha),Some(sha),"Synthetic two-key reference fixture")})
  _->[record("CHK-07-DRIVE","PARTIAL",Some(sha),None,"Policy probe only. Production enforcement unestablished")]
 }
 json.object([#("schema",json.string("uos.telegram.verification-record.v1")),
 #("candidate",json.string(id)),#("observed_at_ms",json.int(observed)),#("expires_at_ms",json.int(observed+7_200_000)),
 #("checkpoints",json.array(rows,fn(x){x})),
 #("aspects",json.array([record("A01","PARTIAL",Some(sha),None,"Bounded policy tests only")],fn(x){x})),
 ]) |> json.to_string
}
fn project(raw:String,view:String,selector:String,now:Int) {
 report.project(raw,files.digest(raw),files.digest(raw),candidate,view,selector,now)
}
pub fn complete_catalog_missing_records_unknown_test() {
 let assert Ok(out)=project(fixture(10_000,"empty"),"checklist","",10_000)
 string.contains(out,"\"catalog_size\":18") |> should.be_true
 string.contains(out,"\"missing_count\":18") |> should.be_true
 string.contains(out,"CHK-18-JJ") |> should.be_true
 string.contains(out,"RECORDED_PASS") |> should.be_false
 let assert Ok(aspects)=project(fixture(10_000,"empty"),"aspects","",10_000)
 string.contains(aspects,"\"catalog_size\":17") |> should.be_true
 string.contains(aspects,"A17") |> should.be_true
}
pub fn record_is_not_execution_or_admission_test() {
 let assert Ok(out)=project(fixture(10_000,"all"),"checklist","",10_000)
 string.contains(out,"\"current_recorded_pass_count\":18") |> should.be_true
 string.contains(out,"\"evidence_bytes_verified\":false") |> should.be_true
 string.contains(out,"\"gates_executed\":false") |> should.be_true
 string.contains(out,"\"runtime_admission\":\"NOT_GRANTED\"") |> should.be_true
 string.contains(out,"\"admission_credit\":true") |> should.be_false
}
pub fn stale_and_expired_lose_current_credit_test() {
 let raw=fixture(10_000,"all")
 let assert Ok(out)=project(raw,"checklist","",3_610_001)
 string.contains(out,"\"state\":\"STALE\"") |> should.be_true
 string.contains(out,"\"current_recorded_pass_count\":0") |> should.be_true
 let assert Ok(expired)=project(raw,"checklist","",7_210_000)
 string.contains(expired,"\"stale\":true") |> should.be_true
}
pub fn exact_source_candidate_and_time_binding_test() {
 let raw=fixture(10_000,"all")
 report.project(raw,files.digest(raw),sha,candidate,"checklist","",10_000) |> result.is_error |> should.be_true
 project(fixture(10_000,"foreign"),"checklist","",10_000) |> result.is_error |> should.be_true
 project(raw,"checklist","",9999) |> result.is_error |> should.be_true
 project(raw,"aspects","A18",10_000) |> result.is_error |> should.be_true
 project(raw,"checklist","A01",10_000) |> result.is_error |> should.be_true
 project(string.repeat("x",65537),"checklist","",10_000) |> result.is_error |> should.be_true
}
pub fn malformed_duplicate_and_unknown_rows_refused_test() {
 let raw=fixture(10_000,"all")
 list.each([
 string.replace(raw,"CHK-02-TAIL","CHK-01-TIME"),
 string.replace(raw,"CHK-02-TAIL","CHK-99-UNKNOWN"),
 string.replace(raw,"\"PASS\"","\"ADMITTED\""),
 string.replace(raw,sha,"bad"),
 string.replace(raw,"Synthetic two-key reference fixture","private/path"),
 string.replace(raw,"7210000","-1"),
 ],fn(changed){ {changed != raw} |> should.be_true
 project(changed,"checklist","",10_000) |> result.is_error |> should.be_true})
}
pub fn selected_aspect_preserves_partial_and_unknown_test() {
 let raw=fixture(10_000,"partial")
 let assert Ok(a)=project(raw,"aspects","A01",10_000)
 string.contains(a,"\"selected_count\":1") |> should.be_true
 string.contains(a,"RECORDED_PARTIAL") |> should.be_true
 string.contains(a,"A02") |> should.be_false
 let assert Ok(b)=project(raw,"aspects","A17",10_000)
 string.contains(b,"\"missing_count\":1") |> should.be_true
 string.contains(b,"\"state\":\"UNKNOWN\"") |> should.be_true
}
pub fn outcome_and_digest_algebra_test() {
 let base=evidence.Record("A01","PASS",Some(sha),Some(sha),"Fixture")
 evidence.state(base,False) |> should.equal("RECORDED_PASS")
 evidence.state(evidence.Record(..base,formal_sha256:None),False) |> should.equal("REJECTED")
 evidence.state(evidence.Record(..base,outcome:"FAIL"),False) |> should.equal("RECORDED_FAIL")
 evidence.state(evidence.Record(..base,outcome:"PARTIAL",formal_sha256:None),False) |> should.equal("RECORDED_PARTIAL")
 evidence.state(evidence.Record(..base,outcome:"UNKNOWN",runtime_sha256:None,formal_sha256:None),False) |> should.equal("UNKNOWN")
 evidence.state(evidence.Record(..base,outcome:"UNRUN",runtime_sha256:None,formal_sha256:None),False) |> should.equal("UNRUN")
 evidence.state(evidence.Record(..base,outcome:"NOT_APPLICABLE",runtime_sha256:None,formal_sha256:None),False) |> should.equal("RECORDED_NOT_APPLICABLE")
 list.each([""," ","  ","\n","private/path","https://host","secret\u{0}"],fn(s){evidence.valid_record(evidence.Record(..base,reason:s)) |> should.be_false})
 evidence.valid_record(evidence.Record(..base,id:string.repeat("A",33))) |> should.be_false
 evidence.valid_record(evidence.Record(..base,runtime_sha256:Some(string.uppercase(sha)))) |> should.be_false
}
pub fn tool_and_command_scope_test() {
 tool.parse("query_checklist {}") |> should.equal(Ok(tool.Checklist))
 tool.parse("query_aspects {\"aspect\":\"A01\"}") |> should.equal(Ok(tool.Aspects("A01")))
 guard.classify_directive("/checklist") |> should.equal(guard.DirectReadTool("query_checklist"))
 guard.classify_directive("/aspects A17") |> should.equal(guard.PreservedDirective("/aspects",["A17"]))
 list.each(["query_checklist {\"path\":\"x\"}","query_aspects {\"aspect\":\"A18\"}","query_aspects {\"candidate\":\"x\"}","query_aspects {\"aspect\":\"A01\",\"path\":\"x\"}"],fn(s){tool.parse(s) |> result.is_error |> should.be_true})
}
pub fn configured_source_path_refusal_test() {
 let a=reader.Source("/home/an/NAS-setup/uos/governance/planning/fixture.json",sha,candidate)
 reader.valid_source(a,False) |> should.be_true
 reader.valid_source(reader.Source(..a,path:"/tmp/file.json"),False) |> should.be_false
 reader.valid_source(reader.Source(..a,path:"/tmp/file.json"),True) |> should.be_true
 list.each(["relative.json","/tmp/../file.json","/tmp//file.json","/tmp/file.txt","/tmp/file\u{0}.json"],fn(p){reader.valid_source(reader.Source(..a,path:p),True) |> should.be_false})
}
