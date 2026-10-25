//// Isolated read of a trusted, hash-pinned candidate record. No user paths or gate execution.
import cepaf_gleam/harness/observer_policy as obs
import cepaf_gleam/harness/telegram_knowledge_report as knowledge
import cepaf_gleam/harness/telegram_fmea_reader as fmea
import cepaf_gleam/harness/telegram_evidence_status as evidence
import cepaf_gleam/harness/telegram_impact_report as report
import gleam/bit_array
import gleam/dynamic/decode
import gleam/json
import gleam/result

pub type Source { Source(path:String,sha256:String,candidate:String,closure_sha256:String) }
@external(erlang,"telegram_coordination_binding","launch_impact_eval")
fn launch_eval(path:String,sha:String,candidate:String,closure:String,selector:String)->Result(String,String)
@external(erlang,"telegram_knowledge_files","read_one")
fn read_one(path:String,max_bytes:Int)->Result(knowledge.Document,String)
@external(erlang,"telegram_ecology_clock","now_ms")
fn now_ms()->Int
@external(erlang,"sa_plan_observer_ffi","observe_checked")
fn invoke(guardian:String,sha:String,args:List(String),deadline:Int,max_bytes:Int)->Result(obs.Observation,String)

pub fn valid_source(source:Source,isolated:Bool)->Bool {
 fmea.valid_source(source.path,isolated) && evidence.valid_hex(source.sha256,64) && evidence.valid_hex(source.candidate,40) && evidence.valid_hex(source.closure_sha256,64)
}
pub fn read(path:String,sha:String,candidate:String,closure:String,selector:String)->Result(String,String) {
 use doc <- result.try(read_one(path,1_048_576))
 report.project(doc.text,sha,candidate,closure,selector,now_ms())
}
fn envelope(source:Source,selector:String) {
 use schema <- decode.field("schema",decode.string)
 use actual <- decode.field("candidate",decode.string)
 use actual_sha <- decode.field("snapshot_sha256",decode.string)
 use closure <- decode.field("closure_sha256",decode.string)
 use actual_selector <- decode.field("module",decode.string)
 use authority <- decode.field("authority",decode.string)
 use admission <- decode.field("runtime_admission",decode.string)
 case schema=="uos.telegram.impact.v1" && actual==source.candidate
   && actual_sha==source.sha256 && closure==source.closure_sha256 && actual_selector==selector
   && authority=="observation_only" && admission=="NOT_GRANTED" {
  True->decode.success(schema) False->decode.failure("impact envelope",schema)
 }
}
pub fn observe(source:Source,selector:String)->Result(String,String) {
 use clean <- result.try(report.selector(selector))
 use expression <- result.try(launch_eval(source.path,source.sha256,source.candidate,source.closure_sha256,clean))
 use receipt <- result.try(invoke(
 "/home/an/NAS-setup/uos/tools/validation/obs_guardian.exe",
 "b7bab1a85ffa3689a2548ff28a391e659c0537104dec7be0f774bae1820ec4be",
 ["--exe","/nix/store/96cqahwqjxzx4pywz1bj53apncjmhhdg-erlang-29.0.5/bin/erl",
 "--sha256","ef4292ee944622942f2e961553eae2222a9dce112eb7e5bfec04dcb9a0d54970",
 "--deadline-ms","3000","--max-bytes","65536","--","+S","2:2","+A","2","-noshell","-eval",expression],
 3000,65536) |> result.replace_error("impact_read_unavailable"))
 use _ <- result.try(case receipt.guardian_result=="child_exited" && receipt.cleanup=="confirmed"
  && receipt.child_exit==0 && bit_array.byte_size(receipt.payload)<=65536 {
  True->Ok(Nil) False->Error("impact_receipt_refused")
 })
 use raw <- result.try(bit_array.to_string(receipt.payload) |> result.replace_error("impact_encoding_refused"))
 use _ <- result.try(json.parse(raw,envelope(source,clean)) |> result.replace_error("impact_envelope_refused"))
 Ok(raw)
}
