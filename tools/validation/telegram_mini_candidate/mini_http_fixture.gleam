//// Private development HTTP fixture; no Telegram API calls or runtime deployment.
import cepaf_gleam/web/server
import gleam/erlang/process
import gleam/http/response
import gleam/bytes_tree
import gleam/string
import mist

pub fn main() {
  let assert Ok(_) = mist.new(fn(req) {
    case string.starts_with(req.path, "/mini-app") || req.path == "/api/v1/plan/update" {
      True -> server.handle_normal_http(req)
      False -> response.new(404) |> response.set_body(mist.Bytes(bytes_tree.from_string("private fixture")))
    }
  })
  |> mist.bind("100.87.7.78")
  |> mist.port(49134)
  |> mist.after_start(fn(_, _, _) { Nil })
  |> mist.start
  process.sleep_forever()
}
