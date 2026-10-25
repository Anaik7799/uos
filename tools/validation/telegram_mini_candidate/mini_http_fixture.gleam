//// Private development HTTP fixture; no Telegram API calls or runtime deployment.

import cepaf_gleam/telegram/mini_control
import cepaf_gleam/telegram/mini_telemetry
import cepaf_gleam/web/server
import gleam/bytes_tree
import gleam/erlang/process
import gleam/http/response
import gleam/int
import gleam/string
import mist
import gleam/json
import gleam/option.{Some}
import gleam/result
import simplifile
import uos_swarm/openrouter_worker as model
type TimeUnit { Millisecond }
@external(erlang,"erlang","monotonic_time")
fn monotonic_ms(unit: TimeUnit) -> Int

@external(erlang, "cepaf_gleam_ffi", "get_env")
fn get_env(name: String) -> Result(String, Nil)

@external(erlang, "mini_control_test_ffi", "kill_actor")
fn kill_actor() -> Nil

pub fn main() {
  case get_env("UOS_MINI_FIXTURE_CONTROL_CRASH_AFTER_MS") {
    Ok(raw) -> case int.parse(raw) {
      Ok(ms) if ms > 0 && ms <= 30_000 -> {
        let _ = process.spawn_unlinked(fn() { process.sleep(ms) kill_actor() })
        Nil
      }
      _ -> panic as "invalid private fixture crash timer"
    }
    Error(_) -> Nil
  }
  case get_env("UOS_MINI_CONTROL_FIXTURE_PROFILE") {
    Ok(_) -> {
      let assert Ok(_) = case get_env("UOS_MINI_FIXTURE_MODEL_LOG") {
        Ok(_) -> mini_control.start_development_fixture_with_io(fixture_io())
        Error(_) -> mini_control.start_development_fixture()
      }
      Nil
    }
    Error(_) -> Nil
  }
  case get_env("UOS_MINI_FIXTURE_TELEMETRY_DISABLED") {
    Ok("1") -> Nil
    _ -> {
      let assert Ok(_) = mini_telemetry.start()
      Nil
    }
  }
  let assert Ok(_) =
    mist.new(fn(req) {
      case
        string.starts_with(req.path, "/mini-app")
        || req.path == "/api/v1/plan/update"
      {
        True -> server.handle_normal_http(req)
        False ->
          response.new(404)
          |> response.set_body(
            mist.Bytes(bytes_tree.from_string("private fixture")),
          )
      }
    })
    |> mist.bind("100.87.7.78")
    |> mist.port(49_134)
    |> mist.after_start(fn(_, _, _) { Nil })
    |> mist.start
  process.sleep_forever()
}

fn fixture_io() -> model.Io {
  let assert Ok(log) = get_env("UOS_MINI_FIXTURE_MODEL_LOG")
  let assert True = string.starts_with(log,"/home/an/uos-agent-runtime/20261024-0555/mini-history-")
    && string.ends_with(log,"/model-calls.txt") && !string.contains(log,"..")
  model.Io(
    credential: fn() { Some("private-fixture") },
    now_ms: fn() { monotonic_ms(Millisecond) },
    fetch_prices: fn(_) { Ok(#(200,"{\"data\":[{\"id\":\"openrouter/free\",\"pricing\":{\"prompt\":\"0\",\"completion\":\"0\"}}]}")) },
    post: fn(_,body,_) {
      let prior = simplifile.read(log) |> result.unwrap("")
      let assert Ok(_) = simplifile.write(log,prior <> "POST\n")
      case string.contains(body,"fixture-model-crash") { True -> kill_actor() False -> Nil }
      case string.contains(body,"fixture-model-fail") {
        True -> Error("PRIVATE FIXTURE PROVIDER FAILURE")
        False -> Ok(#(200,json.to_string(json.object([
          #("model",json.string("fixture/free")),
          #("choices",json.array([json.object([
            #("finish_reason",json.string("stop")),
            #("message",json.object([#("content",json.string("Fixture reply <script>not executed</script>"))])),
          ])],fn(x) { x })),
          #("usage",json.object([#("prompt_tokens",json.int(20)),#("completion_tokens",json.int(8)),
            #("total_tokens",json.int(28)),#("cost",json.float(0.0))])),
        ]))))
      }
    },
  )
}
