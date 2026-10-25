//// Isolated bounded Ecology read; current service fences remain required.
import cepaf_gleam/harness/observer_policy as obs
import gleam/bit_array
import gleam/dynamic/decode
import gleam/json
import gleam/result

@external(erlang,"telegram_coordination_binding","launch_ecology_eval")
fn launch_eval()->Result(String,String)
@external(erlang,"sa_plan_observer_ffi","observe_checked")
fn invoke(guardian:String,sha:String,args:List(String),deadline:Int,max_bytes:Int)->Result(obs.Observation,String)
fn envelope()->decode.Decoder(String) {
  use schema <- decode.field("schema",decode.string)
  use status <- decode.field("status",decode.string)
  use authority <- decode.field("authority",decode.string)
  use admission <- decode.field("runtime_admission",decode.string)
  case schema=="uos.telegram.ecology.v1" && status=="observed"
    && authority=="observation_only" && admission=="NOT_GRANTED" {
    True -> decode.success(schema)
    False -> decode.failure("ecology envelope",schema)
  }
}
pub fn observe()->Result(String,String) {
  use expression <- result.try(launch_eval())
  use receipt <- result.try(invoke(
    "/home/an/NAS-setup/uos/tools/validation/obs_guardian.exe",
    "b7bab1a85ffa3689a2548ff28a391e659c0537104dec7be0f774bae1820ec4be",
    ["--exe","/nix/store/96cqahwqjxzx4pywz1bj53apncjmhhdg-erlang-29.0.5/bin/erl",
      "--sha256","ef4292ee944622942f2e961553eae2222a9dce112eb7e5bfec04dcb9a0d54970",
      "--deadline-ms","3000","--max-bytes","32768","--","+S","2:2","+A","2","-noshell","-eval",expression],
    3000,32768) |> result.replace_error("ecology_read_unavailable"))
  use _ <- result.try(case receipt.guardian_result=="child_exited" && receipt.cleanup=="confirmed"
    && receipt.child_exit==0 && bit_array.byte_size(receipt.payload)<=32768 {
    True -> Ok(Nil)
    False -> Error("ecology_receipt_refused")
  })
  use raw <- result.try(bit_array.to_string(receipt.payload) |> result.replace_error("ecology_payload_refused"))
  use _ <- result.try(json.parse(raw,envelope()) |> result.replace_error("ecology_payload_refused"))
  Ok(raw)
}
