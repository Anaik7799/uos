//// Private development HTTP fixture; no Telegram API calls or runtime deployment.

import cepaf_gleam/telegram/mini_telemetry
import cepaf_gleam/web/server
import gleam/bytes_tree
import gleam/erlang/process
import gleam/http/response
import gleam/string
import mist

@external(erlang, "cepaf_gleam_ffi", "get_env")
fn get_env(name: String) -> Result(String, Nil)

pub fn main() {
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
