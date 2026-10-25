//// Evaluation of caller-supplied facts only; a pass grants no runtime authority.
import cepaf_gleam/harness/observer_policy as obs
import gleam/bit_array
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/result
import gleam/string

pub const worker_sha256 = "ca57ba413d3b18b2795578e2854a6315114443956e32affefe6631899fdff306"
const worker = "/home/an/NAS-setup/uos/var/recovery-runtime/20261025-0017-rete/native/telegram_rete_worker.exe"

@external(erlang,"sa_plan_observer_ffi","observe_checked")
fn invoke(guardian:String,sha:String,args:List(String),deadline:Int,max_bytes:Int)->Result(obs.Observation,String)

pub fn canonicalize(raw:String)->Result(String,String) {
 use _ <- result.try(case string.byte_size(raw)>0 && string.byte_size(raw)<=256
   && list.all(string.to_graphemes(raw),fn(c){string.contains("abcdefghijklmnopqrstuvwxyz_=, ",c)}) {
   True->Ok(Nil) False->Error("invalid_fact_schema")
 })
 let pairs=string.split(raw,",")
 use _ <- result.try(case list.length(pairs)<=5 {True->Ok(Nil) False->Error("invalid_fact_schema")})
 use parsed <- result.try(list.try_map(pairs,fn(pair){
   case string.split(pair,"=") {
     [key,value] -> {
       let k=string.trim(key)
       let v=string.trim(value)
       case list.contains(["watchdog","mesh_running","e_stop","high_drift","divergent"],k)
         && {v=="true" || v=="false"} {
         True->Ok(#(k,v)) False->Error("invalid_fact_schema")
       }
     }
     _->Error("invalid_fact_schema")
   }
 }))
 let keys=list.map(parsed,fn(p){p.0})
 case list.length(list.unique(keys))==list.length(keys) {
   True->Ok(list.map(parsed,fn(p){p.0<>"="<>p.1}) |> string.join(","))
   False->Error("invalid_fact_schema")
 }
}
fn decoder() {
 use status <- decode.field("status",decode.string)
 use verdict <- decode.field("verdict",decode.string)
 case status,verdict {
   "ok","pass" -> {
     use rules <- decode.field("rules_fired",decode.list(decode.string))
     use diagnostics <- decode.field("diagnostics_count",decode.int)
     decode.success(#(verdict,"",rules,diagnostics))
   }
   "error","rejected" -> {
     use reason <- decode.field("reason",decode.string)
     decode.success(#(verdict,reason,[],0))
   }
   _,_ -> decode.failure(#("","",[],0),"known rule evaluation")
 }
}
fn safe_text(s:String,limit:Int)->Bool {
 let forbidden="\u{0}\u{1}\u{2}\u{3}\u{4}\u{5}\u{6}\u{7}\u{8}\u{9}\u{a}\u{b}\u{c}\u{d}\u{e}\u{f}\u{10}\u{11}\u{12}\u{13}\u{14}\u{15}\u{16}\u{17}\u{18}\u{19}\u{1a}\u{1b}\u{1c}\u{1d}\u{1e}\u{1f}\u{7f}"
 string.byte_size(s)>0 && string.byte_size(s)<=limit
 && !list.any(string.to_graphemes(forbidden),fn(c){string.contains(s,c)})
}
pub fn project(raw:String)->Result(String,String) {
 use _ <- result.try(case string.byte_size(raw)<=4096 {True->Ok(Nil) False->Error("rete_payload_refused")})
 use r <- result.try(json.parse(raw,decoder()) |> result.replace_error("rete_payload_refused"))
 let #(verdict,reason,rules,diagnostics)=r
 use _ <- result.try(case diagnostics>=0 && diagnostics<=1000 && list.length(rules)<=16
   && list.all(rules,fn(s){safe_text(s,128)}) && {verdict=="pass" || safe_text(reason,256)} {
   True->Ok(Nil) False->Error("rete_payload_refused")
 })
 Ok(json.object([
   #("schema",json.string("uos.telegram.rete.v1")),#("status",json.string("evaluated")),
   #("scope",json.string("caller_supplied_facts_only")),#("engine",json.string("ocaml_fixed_production_rules")),
   #("algorithm",json.string("naive_forward_match_not_rete_ul_network")),
   #("verdict",json.string(verdict)),#("reason",case reason {""->json.null() _->json.string(reason)}),
   #("rules_fired",json.array(rules,json.string)),#("diagnostics_count",json.int(diagnostics)),
   #("worker_sha256",json.string(worker_sha256)),#("runtime_facts_verified",json.bool(False)),
   #("authority",json.string("advisory_only")),#("runtime_admission",json.string("NOT_GRANTED")),
 ]) |> json.to_string)
}
pub fn receipt_payload(receipt:Result(obs.Observation,String))->Result(String,String) {
 use r <- result.try(receipt |> result.replace_error("rete_evaluation_unavailable"))
 use _ <- result.try(case r.guardian_result=="child_exited" && r.cleanup=="confirmed"
   && r.child_exit==0 && bit_array.byte_size(r.payload)<=4096 {
   True->Ok(Nil) False->Error("rete_receipt_refused")
 })
 use raw <- result.try(bit_array.to_string(r.payload) |> result.replace_error("rete_payload_refused"))
 project(raw)
}
pub fn evaluate(facts:String)->Result(String,String) {
 use clean <- result.try(canonicalize(facts))
 invoke("/home/an/NAS-setup/uos/tools/validation/obs_guardian.exe",
 "b7bab1a85ffa3689a2548ff28a391e659c0537104dec7be0f774bae1820ec4be",
 ["--exe",worker,"--sha256",worker_sha256,"--deadline-ms","1000","--max-bytes","4096","--",clean],1000,4096)
 |> receipt_payload
}
