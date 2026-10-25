//// Bounded isolated FMEA assessment read. Trusted source, never a Telegram path.
import cepaf_gleam/harness/observer_policy as obs
import cepaf_gleam/harness/telegram_knowledge_report as knowledge
import cepaf_gleam/harness/telegram_fmea_report as report
import gleam/bit_array
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string

@external(erlang,"telegram_coordination_binding","launch_fmea_eval")
fn launch_eval(path:String,plan:String,task:String)->Result(String,String)
@external(erlang,"telegram_knowledge_files","read_one")
fn read_one(path:String,max_bytes:Int)->Result(knowledge.Document,String)
type Unit { Millisecond }
@external(erlang,"erlang","system_time")
fn system_time(unit:Unit)->Int
@external(erlang,"sa_plan_observer_ffi","observe_checked")
fn invoke(guardian:String,sha:String,args:List(String),deadline:Int,max_bytes:Int)->Result(obs.Observation,String)

pub fn valid_source(path:String,isolated:Bool)->Bool {
  let parts=string.split(path,"/")
  string.starts_with(path,"/") && string.byte_size(path)<=4096
  && string.ends_with(path,".json")
  && !list.any(["\u{0}","\r","\n","\t","\u{7f}"],fn(c){string.contains(path,c)})
  && list.all(list.drop(parts,1),fn(p){p!="" && p!="." && p!=".."})
  && {isolated || string.starts_with(path,"/home/an/NAS-setup/uos/governance/planning/")}
}

/// Entry runs only in the isolated bounded child.
pub fn read(path:String,plan:String,task:String)->Result(String,String) {
  use doc <- result.try(read_one(path,1_048_576))
  use _ <- result.try(case doc.bytes==string.byte_size(doc.text) && obs.valid_digest(doc.sha256) {
    True -> Ok(Nil) False -> Error("fmea_source_refused")
  })
  report.project(doc.text,doc.sha256,plan,case task { ""->None _->Some(task) },system_time(Millisecond))
}
fn envelope(plan:String)->decode.Decoder(String) {
  use schema <- decode.field("schema",decode.string)
  use actual <- decode.field("plan_id",decode.string)
  use authority <- decode.field("authority",decode.string)
  use admission <- decode.field("runtime_admission",decode.string)
  case schema=="uos.telegram.fmea.v1" && actual==plan
    && authority=="observation_only" && admission=="NOT_GRANTED" {
    True->decode.success(schema)
    False->decode.failure("scoped FMEA observation",schema)
  }
}
pub fn observe(path:String,plan:String,task:String)->Result(String,String) {
  use _ <- result.try(case obs.valid_id(plan) && {task=="" || obs.valid_id(task)} {
    True -> Ok(Nil) False -> Error("fmea_scope_refused")
  })
  use expression <- result.try(launch_eval(path,plan,task))
  use receipt <- result.try(invoke(
    "/home/an/NAS-setup/uos/tools/validation/obs_guardian.exe",
    "b7bab1a85ffa3689a2548ff28a391e659c0537104dec7be0f774bae1820ec4be",
    ["--exe","/nix/store/96cqahwqjxzx4pywz1bj53apncjmhhdg-erlang-29.0.5/bin/erl",
     "--sha256","ef4292ee944622942f2e961553eae2222a9dce112eb7e5bfec04dcb9a0d54970",
     "--deadline-ms","3000","--max-bytes","32768","--",
     "+S","2:2","+A","2","-noshell","-eval",expression],3000,32768)
    |> result.replace_error("fmea_read_unavailable"))
  use _ <- result.try(case receipt.guardian_result=="child_exited" && receipt.cleanup=="confirmed"
    && receipt.child_exit==0 && bit_array.byte_size(receipt.payload)<=32768 {
    True -> Ok(Nil) False -> Error("fmea_receipt_refused")
  })
  use raw <- result.try(bit_array.to_string(receipt.payload) |> result.replace_error("fmea_encoding_refused"))
  use _ <- result.try(json.parse(raw,envelope(plan)) |> result.replace_error("fmea_payload_refused"))
  Ok(raw)
}
