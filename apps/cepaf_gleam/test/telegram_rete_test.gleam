import cepaf_gleam/harness/telegram_rete_report as rete
import cepaf_gleam/harness/observer_policy as obs
import cepaf_gleam/harness/telegram_ingress_guard as guard
import cepaf_gleam/harness/telegram_tool_command as tool
import gleam/bit_array
import gleam/list
import gleam/result
import gleam/string
import gleeunit/should

pub fn strict_facts_and_no_default_nominal_test() {
 rete.canonicalize(" watchdog = true ,mesh_running=false ") |> should.equal(Ok("watchdog=true,mesh_running=false"))
 rete.canonicalize("e_stop=true") |> should.equal(Ok("e_stop=true"))
 list.each(["","safety_mode=nominal","watchdog=true,watchdog=false","watchdog=TRUE",
 "watchdog=1","watchdog=true,,","watchdog=true,","x=true","watchdog=true=bad",
 "watchdog= true\n","watchdog=true\u{0}",string.repeat("a",257),
 "watchdog=true,mesh_running=true,e_stop=false,high_drift=false,divergent=false,x=true"],
 fn(s){rete.canonicalize(s) |> result.is_error |> should.be_true})
}
pub fn output_truth_and_private_omission_test() {
 let assert Ok(raw)=rete.project("{\"status\":\"ok\",\"verdict\":\"pass\",\"rules_fired\":[\"OODA_Nominal_Advisory\"],\"diagnostics_count\":1,\"private\":\"CANARY\"}")
 list.each(["caller_supplied_facts_only","naive_forward_match_not_rete_ul_network","NOT_GRANTED","advisory_only","\"runtime_facts_verified\":false"],fn(x){string.contains(raw,x) |> should.be_true})
 string.contains(raw,"CANARY") |> should.be_false
 let assert Ok(denied)=rete.project("{\"status\":\"error\",\"verdict\":\"rejected\",\"reason\":\"Emergency stop active\"}")
 string.contains(denied,"\"verdict\":\"rejected\"") |> should.be_true
}
pub fn malformed_or_inconsistent_output_refused_test() {
 list.each(["{}","[]","{\"status\":\"error\",\"verdict\":\"pass\"}",
 "{\"status\":\"ok\",\"verdict\":\"pass\",\"rules_fired\":[],\"diagnostics_count\":-1}",
 "{\"status\":\"error\",\"verdict\":\"rejected\",\"reason\":\"\"}",
 "{\"status\":\"error\",\"verdict\":\"rejected\",\"reason\":\"line\\nnext\"}",
 string.repeat("x",4097)],fn(s){rete.project(s) |> result.is_error |> should.be_true})
}
pub fn receipt_fencing_and_redaction_test() {
 let good=obs.Observation("child_exited","confirmed",0,bit_array.from_string("{\"status\":\"error\",\"verdict\":\"rejected\",\"reason\":\"rejected\"}"))
 rete.receipt_payload(Ok(good)) |> result.is_ok |> should.be_true
 list.each([obs.Observation(..good,guardian_result:"deadline"),obs.Observation(..good,cleanup:"unconfirmed"),
 obs.Observation(..good,child_exit:1),obs.Observation(..good,payload:<<255>>)],fn(r){rete.receipt_payload(Ok(r)) |> result.is_error |> should.be_true})
 rete.receipt_payload(Error("CANARY")) |> should.equal(Error("rete_evaluation_unavailable"))
}
pub fn command_and_tool_scope_test() {
 guard.classify_directive("/rete watchdog=true,mesh_running=true") |> should.equal(guard.PreservedDirective("/rete",["watchdog=true,mesh_running=true"]))
 tool.parse("evaluate_rete {\"facts\":\"e_stop=true\"}") |> should.equal(Ok(tool.Rete("e_stop=true")))
 list.each(["evaluate_rete {}","evaluate_rete {\"facts\":\"e_stop=true\",\"path\":\"/private\"}",
 "evaluate_rete {\"facts\":1}"],fn(s){tool.parse(s) |> result.is_error |> should.be_true})
 case guard.classify_directive("/rete") {guard.DeniedMutation(_,_)->True _->False} |> should.be_true
}
pub fn real_worker_positive_and_rejected_test() {
 let assert Ok(pass)=rete.evaluate("watchdog=true,mesh_running=true")
 string.contains(pass,"\"verdict\":\"pass\"") |> should.be_true
 list.each(["e_stop=true","watchdog=false,mesh_running=true","watchdog=true,mesh_running=false",
 "high_drift=true","divergent=true","watchdog=true"],fn(s){
   let assert Ok(denied)=rete.evaluate(s)
   string.contains(denied,"\"verdict\":\"rejected\"") |> should.be_true
 })
}

fn bool_text(value:Bool)->String {case value {True->"true" False->"false"}}
pub fn exhaustive_five_boolean_oracle_test() {
 list.each([True,False],fn(w){list.each([True,False],fn(m){list.each([True,False],fn(e){list.each([True,False],fn(h){list.each([True,False],fn(d){
   let facts="watchdog="<>bool_text(w)<>",mesh_running="<>bool_text(m)<>",e_stop="<>bool_text(e)<>",high_drift="<>bool_text(h)<>",divergent="<>bool_text(d)
   let assert Ok(raw)=rete.evaluate(facts)
   let expected=case w && m && !e && !h && !d {True->"pass" False->"rejected"}
   string.contains(raw,"\"verdict\":\""<>expected<>"\"") |> should.be_true
 })})})})})
}
