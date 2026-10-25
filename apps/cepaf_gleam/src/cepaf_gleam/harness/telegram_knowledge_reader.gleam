//// Bounded isolated knowledge observation; no effect authority.
import cepaf_gleam/harness/observer_policy as obs
import cepaf_gleam/harness/telegram_knowledge_report as report
import gleam/bit_array
import gleam/dynamic/decode
import gleam/json
import gleam/result

@external(erlang, "telegram_coordination_binding", "launch_knowledge_eval")
fn launch_eval(view: String, query: String) -> Result(String, String)

@external(erlang, "sa_plan_observer_ffi", "observe_checked")
fn invoke(guardian: String, sha: String, args: List(String), deadline: Int, max_bytes: Int)
  -> Result(obs.Observation, String)

fn envelope(view: String) -> decode.Decoder(String) {
  use schema <- decode.field("schema", decode.string)
  use actual_view <- decode.field("view", decode.string)
  use authority <- decode.field("authority", decode.string)
  use admission <- decode.field("runtime_admission", decode.string)
  case schema == "uos.telegram.knowledge.v1" && view == actual_view
    && authority == "observation_only" && admission == "NOT_GRANTED" {
    True -> decode.success(schema)
    False -> decode.failure("valid knowledge envelope", schema)
  }
}
pub fn observe(view: String, query: String) -> Result(String, String) {
  use _ <- result.try(case view {
    "wiki" | "zk" | "all" -> Ok(Nil)
    _ -> Error("knowledge_view_refused")
  })
  use clean <- result.try(report.validate_query(query))
  use expression <- result.try(launch_eval(view,clean))
  use receipt <- result.try(invoke(
    "/home/an/NAS-setup/uos/tools/validation/obs_guardian.exe",
    "b7bab1a85ffa3689a2548ff28a391e659c0537104dec7be0f774bae1820ec4be",
    ["--exe", "/nix/store/96cqahwqjxzx4pywz1bj53apncjmhhdg-erlang-29.0.5/bin/erl",
      "--sha256", "ef4292ee944622942f2e961553eae2222a9dce112eb7e5bfec04dcb9a0d54970",
      "--deadline-ms", "3000", "--max-bytes", "32768", "--",
      "+S", "2:2", "+A", "2", "-noshell", "-eval", expression],
    3000,32768) |> result.replace_error("knowledge_read_unavailable"))
  use _ <- result.try(case receipt.guardian_result == "child_exited"
    && receipt.cleanup == "confirmed" && receipt.child_exit == 0
    && bit_array.byte_size(receipt.payload) <= 32768 {
    True -> Ok(Nil)
    False -> Error("knowledge_receipt_refused")
  })
  use raw <- result.try(bit_array.to_string(receipt.payload)
    |> result.replace_error("knowledge_payload_refused"))
  use _ <- result.try(json.parse(raw,envelope(view))
    |> result.replace_error("knowledge_payload_refused"))
  Ok(raw)
}
