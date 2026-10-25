//// Read-only projection of the existing OCaml daily reservation ledger.
//// Liability is not invoiced spend or a global account budget.
import cepaf_gleam/harness/observer_policy as obs
import gleam/bit_array
import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/result
import gleam/string

pub type Source { Source(executable:String,sha256:String,ledger:String) }
@external(erlang,"sa_plan_observer_ffi","observe_checked")
fn invoke(guardian:String,sha:String,args:List(String),deadline:Int,max_bytes:Int)->Result(obs.Observation,String)
@external(erlang,"telegram_budget_clock","now_us")
fn now_us()->Int
@external(erlang,"telegram_budget_clock","monotonic_ms")
fn monotonic_ms()->Int
@external(erlang,"telegram_budget_clock","utc_day")
fn utc_day(us:Int)->String

fn clean_path(path:String)->Bool {
 string.starts_with(path,"/") && string.byte_size(path)<=4096
 && list.all(list.drop(string.split(path,"/"),1),fn(p){p!="" && p!="." && p!=".."})
 && list.all(string.to_graphemes(path),fn(c){string.contains("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_./-",c)})
}
pub fn valid_source(s:Source,isolated:Bool)->Bool {
 let root="/home/an/NAS-setup/uos/"
 clean_path(s.executable) && clean_path(s.ledger) && obs.valid_digest(s.sha256)
 && string.ends_with(s.executable,"/ecology_budget.exe")
 && {string.starts_with(s.executable,root<>"var/releases/") ||
   {isolated && string.starts_with(s.executable,root<>"var/recovery-runtime/")}}
 && {s.ledger==root<>"var/ecology/openrouter_budget.sqlite3" ||
   {isolated && {string.starts_with(s.ledger,root<>"var/recovery-runtime/") ||
     string.starts_with(s.ledger,"/tmp/uos_tg_service_e2e_test_")}}}
}
fn require(ok:Bool)->Result(Nil,String) {
 case ok {True->Ok(Nil) False->Error("budget_observation_refused")}
}
const keys=["status","dispatch_authorized","task_authority","budget_scope","ledger_path","call_id","utc_day","observed_us","reservation_nanodollars","daily_limit_nanodollars","daily_reserved_nanodollars","remaining_nanodollars","reservation_count","actual_spend_nanodollars","refunds_supported"]

pub fn project(raw:String,ledger:String,before:Int,after:Int)->Result(String,String) {
 use _ <- result.try(require(string.byte_size(raw)<=8192 && before>0 && after>=before && after-before<5_000_000))
 use entries <- result.try(json.parse(raw,decode.dict(decode.string,decode.dynamic)) |> result.replace_error("budget_json_refused"))
 use _ <- result.try(require(dict.size(entries)==list.length(keys) && list.all(keys,fn(k){dict.has_key(entries,k)})))
 let decoder={
  use status <- decode.field("status",decode.string)
  use dispatch <- decode.field("dispatch_authorized",decode.bool)
  use authority <- decode.field("task_authority",decode.bool)
  use scope <- decode.field("budget_scope",decode.string)
  use path <- decode.field("ledger_path",decode.string)
  use _ <- decode.field("call_id",decode.optional(decode.failure(Nil,"null required")))
  use day <- decode.field("utc_day",decode.string)
  use observed <- decode.field("observed_us",decode.int)
  use reservation <- decode.field("reservation_nanodollars",decode.int)
  use limit <- decode.field("daily_limit_nanodollars",decode.int)
  use reserved <- decode.field("daily_reserved_nanodollars",decode.int)
  use remaining <- decode.field("remaining_nanodollars",decode.int)
  use count <- decode.field("reservation_count",decode.int)
  use _ <- decode.field("actual_spend_nanodollars",decode.optional(decode.failure(Nil,"null required")))
  use refunds <- decode.field("refunds_supported",decode.bool)
  decode.success(#(status=="status" && !dispatch && !authority && scope=="this_database_only"
   && path==ledger && !refunds && reservation==250_000_000 && limit==10_000_000_000
   && count>=0 && count<=40 && reserved==count*reservation && remaining==limit-reserved
   && observed>=before && observed<=after && day==utc_day(observed) && day==utc_day(after),
   day,observed,reserved,remaining,count))
 }
 use #(valid,day,observed,reserved,remaining,count) <- result.try(json.parse(raw,decoder) |> result.replace_error("budget_envelope_refused"))
 use _ <- result.try(require(valid))
 Ok(json.object([
  #("schema",json.string("uos.telegram.finops.v1")),
  #("status",json.string("observed")),
  #("scope",json.string("ecology_daily_reservation_ledger_only")),
  #("currency",json.string("USD")),#("utc_day",json.string(day)),#("observed_at_us",json.int(observed)),
  #("daily_limit_nanodollars",json.int(10_000_000_000)),
  #("reservation_nanodollars",json.int(250_000_000)),
  #("daily_reserved_nanodollars",json.int(reserved)),
  #("remaining_nanodollars",json.int(remaining)),#("reservation_count",json.int(count)),
  #("actual_spend_nanodollars",json.null()),#("refunds_supported",json.bool(False)),
  #("dispatch_authorized",json.bool(False)),#("runtime_admission",json.string("NOT_GRANTED")),
  #("note",json.string("Reserved liability is not invoiced spend. This ledger does not cover unrelated clients or the whole provider account. No refunds, spending or budget changes are performed."))
 ]) |> json.to_string)
}
pub fn observe(source:Source)->Result(String,String) {
 let before=now_us()
 let start=monotonic_ms()
 use receipt <- result.try(invoke(
 "/home/an/NAS-setup/uos/tools/validation/obs_guardian.exe",
 "b7bab1a85ffa3689a2548ff28a391e659c0537104dec7be0f774bae1820ec4be",
 ["--exe",source.executable,"--sha256",source.sha256,"--deadline-ms","3000","--max-bytes","8192","--","status",source.ledger],
 3000,8192) |> result.replace_error("budget_reader_unavailable"))
 let after=now_us()
 let elapsed=monotonic_ms()-start
 use _ <- result.try(require(elapsed>=0 && elapsed<5000 && receipt.guardian_result=="child_exited"
 && receipt.cleanup=="confirmed" && receipt.child_exit==0 && bit_array.byte_size(receipt.payload)<=8192))
 use raw <- result.try(bit_array.to_string(receipt.payload) |> result.replace_error("budget_encoding_refused"))
 project(raw,source.ledger,before,after)
}
pub fn unavailable()->String {
 json.object([#("schema",json.string("uos.telegram.finops.v1")),#("status",json.string("unavailable")),
 #("actual_spend_nanodollars",json.null()),#("runtime_admission",json.string("NOT_GRANTED")),
 #("error",json.string("Reservation ledger unavailable or outside current authority; no zero-spend or remaining-budget conclusion."))]) |> json.to_string
}
