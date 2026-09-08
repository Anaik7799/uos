//// Restricted manual-acceptance listener; no file, MCP or operational routes.
import gleam/bytes_tree
import gleam/erlang/process
import gleam/http
import gleam/http/request.{type Request}
import gleam/http/response
import gleam/int
import gleam/io
import gleam/string
import indrajaal/homeostasis_http
import indrajaal/runtime_identity
import mist.{type Connection}

pub type Route { Homeostasis Identity Refused }

pub fn route(method: http.Method, path: List(String)) -> Route {
  case method, path {
    http.Get, [] | http.Get, ["homeostasis"]
    | http.Get, ["homeostasis", "evolution"]
    | http.Get, ["homeostasis", "components"]
    | http.Get, ["homeostasis", "terminal"]
    | http.Get, ["homeostasis", "stream"]
    | http.Get, ["api", "v1", "homeostasis"]
    | http.Get, ["api", "v1", "homeostasis", "stream"]
    | http.Get, ["api", "v1", "homeostasis", "terminal"]
    | http.Get, ["api", "v1", "homeostasis", "review"] -> Homeostasis
    http.Get, ["api", "v1", "runtime", "identity"] -> Identity
    _, _ -> Refused
  }
}

pub fn bounded_target(host: String, port: Int) -> Bool {
  port >= 49152 && port <= 65535 && case string.split(host, ".") {
    ["100", second, third, fourth] -> case int.parse(second), int.parse(third), int.parse(fourth) {
      Ok(b), Ok(c), Ok(d) -> b >= 64 && b <= 127 && c >= 0 && c <= 255 && d >= 0 && d <= 255
      _, _, _ -> False
    }
    _ -> False
  }
}

@external(erlang, "indrajaal_web_ffi", "listen_port")
fn listen_port(default: Int) -> Int
@external(erlang, "indrajaal_web_ffi", "listen_host")
fn listen_host() -> String

pub fn main() {
  let port = listen_port(0)
  let host = listen_host()
  let report = runtime_identity.observe()
  let assert True = bounded_target(host, port) && report.runtime_ready
  let handler = fn(req: Request(Connection)) {
    case route(req.method, request.path_segments(req)) {
      Homeostasis -> homeostasis_http.handle(req)
      Identity -> response.new(200)
        |> response.set_header("content-type", "application/json")
        |> response.set_header("cache-control", "no-store")
        |> response.set_body(mist.Bytes(bytes_tree.from_string(runtime_identity.to_json(runtime_identity.observe()))))
      Refused -> response.new(case req.method { http.Get -> 404 _ -> 405 })
        |> response.set_header("allow", "GET")
        |> response.set_header("cache-control", "no-store")
        |> response.set_body(mist.Bytes(bytes_tree.from_string("Manual testing only: read-only homeostasis routes; no file access or operational actions.")))
    }
  }
  let assert Ok(_) = mist.new(handler) |> mist.port(port) |> mist.bind(host) |> mist.start
  io.println("Manual testing: http://nas-1.tail55d152.ts.net:" <> int.to_string(port) <> "/homeostasis/evolution")
  process.sleep_forever()
}
