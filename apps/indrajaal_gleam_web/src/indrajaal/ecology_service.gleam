//// Dedicated read-only ecology service. Its route set exposes no repository
//// files, credentials, arbitrary tools or task mutation. Agent capability
//// invocation remains a typed in-VM API behind the selected activation mask.
import cepaf_gleam/ecology/capability_port
import cepaf_gleam/ecology/living_swarm.{type SwarmEcology}
import cepaf_gleam/ecology/living_swarm_actor
import gleam/bytes_tree
import gleam/erlang/process
import gleam/http.{Get}
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/int
import gleam/io
import gleam/json
import gleam/otp/static_supervisor
import indrajaal/ecology_http
import indrajaal/runtime_identity
import mist.{type ResponseData}

@external(erlang, "indrajaal_web_ffi", "listen_port")
fn listen_port(default: Int) -> Int

@external(erlang, "indrajaal_web_ffi", "listen_host")
fn listen_host() -> String

fn json_response(status: Int, body: String) -> Response(ResponseData) {
  response.new(status)
  |> response.set_body(mist.Bytes(bytes_tree.from_string(body)))
  |> response.set_header("content-type", "application/json; charset=utf-8")
  |> response.set_header("cache-control", "no-store")
  |> response.set_header("x-content-type-options", "nosniff")
}

pub fn handle_snapshot(req: Request(body), snapshot: Result(SwarmEcology, String), identity: runtime_identity.Report) -> Response(ResponseData) {
  case req.method, request.path_segments(req) {
    Get, [] -> response.new(302)
      |> response.set_header("location", "/ecology")
      |> response.set_body(mist.Bytes(bytes_tree.new()))
    Get, ["api", "v1", "runtime", "identity"] ->
      json_response(200, runtime_identity.to_json(identity))
    Get, ["health"] -> case snapshot, identity.runtime_ready {
      Ok(state), True if state.cycle_counter > 0 -> json_response(200, json.to_string(json.object([
        #("status", json.string("running")),
        #("cycle", json.int(state.cycle_counter)),
        #("application_admitted", json.bool(False)),
        #("scope", json.string("shared ecology actor and observed OTP identity")),
      ])))
      _, _ -> json_response(503, "{\"status\":\"unavailable\"}")
    }
    Get, ["api", "v1", "ecology", "capabilities"] ->
      json_response(200, capability_port.probe_report_json() |> json.to_string)
    Get, ["ecology", ..] | Get, ["api", "v1", "ecology", ..] ->
      ecology_http.handle_snapshot(req, snapshot)
    Get, _ -> json_response(404, "{\"error\":\"not_found\"}")
    _, _ -> json_response(405, "{\"error\":\"read_only_service\"}")
  }
}

pub fn main() {
  let assert Ok(Nil) = runtime_identity.observe() |> runtime_identity.startup_check
  let assert Ok(_) = static_supervisor.new(static_supervisor.RestForOne)
    |> static_supervisor.restart_tolerance(intensity: 3, period: 60)
    |> static_supervisor.add(living_swarm_actor.runtime_supervised(1000))
    |> static_supervisor.start
  let runtime = living_swarm_actor.runtime_subject()
  let port = listen_port(4110)
  let assert Ok(_) = mist.new(fn(req) {
    handle_snapshot(req, living_swarm_actor.get_swarm(runtime, 250), runtime_identity.observe())
  })
    |> mist.port(port)
    |> mist.bind(listen_host())
    |> mist.start
  io.println("UOS ecology: http://nas-1.tail55d152.ts.net:" <> int.to_string(port) <> "/ecology")
  process.sleep_forever()
}
