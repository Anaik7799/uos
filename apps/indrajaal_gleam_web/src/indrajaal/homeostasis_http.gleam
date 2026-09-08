//// SC-HOMEO-UI-001. HTTP transport for the shared homeostasis evidence view.
//// No source is promoted to observed until a trusted adapter is wired.

import cepaf_gleam/ui/homeostasis_status as status
import cepaf_gleam/ui/homeostasis_data as data
import cepaf_gleam/ui/tui/homeostasis_evolution_view as terminal
import gleam/list
import gleam/option.{Some}
import gleam/json
import gleam/result
import gleam/int
import gleam/float
import cepaf_gleam/ui/lustre/homeostasis_evolution_hud as hud
import gleam/bytes_tree
import gleam/erlang/process
import gleam/http
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/otp/actor
import gleam/string_tree
import lustre/attribute
import lustre/element
import lustre/element/html
import mist.{type Connection, type ResponseData}

pub fn document() -> String { selected_document(data.default(), "all") }

pub fn selected_document(selection: data.Selection, component: String) -> String {
  selected_document_on_port(selection, component, 4100)
}

@external(erlang, "indrajaal_web_ffi", "listen_port")
fn listen_port(default: Int) -> Int

pub fn selected_document_on_port(selection: data.Selection, component: String, port: Int) -> String {
  let #(snapshot, now) = data.read(selection)
  "<!doctype html>" <> element.to_string(html.html([attribute.attribute("lang","en")], [
    html.head([], [
      html.meta([attribute.attribute("charset","utf-8")]),
      html.meta([attribute.name("viewport"),attribute.attribute("content","width=device-width,initial-scale=1")]),
      html.title([], "Homeostasis evidence | UOS"),
    ]),
    html.body([], [
      hud.render_view_on_port(selection,component,snapshot,now,port),
    ]),
  ]))
}

pub fn snapshot_response() -> Response(ResponseData) {
  response.new(503)
  |> response.set_body(mist.Bytes(bytes_tree.from_string(status.to_json(status.unavailable(), 0))))
  |> response.set_header("content-type", "application/json; charset=utf-8")
  |> response.set_header("cache-control", "no-store")
  |> response.set_header("x-content-type-options", "nosniff")
}

pub fn page_response() -> Response(ResponseData) {
  response.new(200)
  |> response.set_body(mist.Bytes(bytes_tree.from_string(document())))
  |> response.set_header("content-type", "text/html; charset=utf-8")
  |> response.set_header("cache-control", "no-store")
  |> response.set_header("x-content-type-options", "nosniff")
}

pub fn handle(req: Request(Connection)) -> Response(ResponseData) {
  let params = request.get_query(req) |> result.unwrap([#("mode","invalid")])
  let component = case request.path_segments(req) { ["homeostasis","terminal"] -> "terminal" _ -> list.key_find(params, "component") |> result.unwrap("all") }
  case data.parse(params) {
    Error(reason) -> json_response(400, json.object([#("message",json.string(reason))]) |> json.to_string())
    Ok(selection) -> case component == "all" || component == "terminal" || list.contains(hud.components,component) {
      False -> json_response(400,"{\"message\":\"unknown homeostasis component\"}")
      True -> case req.method, request.path_segments(req) {
        http.Get, ["api", "v1", "homeostasis", "stream"]
        | http.Get, ["homeostasis", "stream"] -> stream(req, selection)
        http.Get, ["api", "v1", "homeostasis", "review"] -> {
          let cpu = list.key_find(params,"cpu_limit") |> result.unwrap("0.85") |> float.parse()
          let memory = list.key_find(params,"memory_limit") |> result.unwrap("0.75") |> float.parse()
          let decision = case cpu,memory {
            Ok(c),Ok(m) -> data.review(selection,c,m)
            _,_ -> Error("Invalid threshold number")
          }
          let #(code,message) = case decision {
            Error(reason) -> #(400,reason)
            Ok(data.DeniedNoAuthority) -> #(403,"Denied: this read-only surface has no authenticated Sa-plan execution authority.")
            Ok(data.Preview(True)) -> #(200,"SIMULATED review: sample is within requested thresholds; no runtime change.")
            Ok(data.Preview(False)) -> #(200,"SIMULATED review: sample exceeds requested thresholds; no runtime change.")
          }
          json_response(code,json.object([#("message",json.string(message)),#("executed",json.bool(False))]) |> json.to_string())
        }
        http.Get, ["api", "v1", "homeostasis", "terminal"] -> {
          let #(snapshot,now) = data.read(selection)
          response.new(200) |> response.set_body(mist.Bytes(bytes_tree.from_string(terminal.render_snapshot(snapshot,now,120,100))))
            |> response.set_header("content-type","text/plain; charset=utf-8")
            |> response.set_header("cache-control","no-store")
        }
        http.Get, ["api", ..] -> {
          let #(snapshot,now) = data.read(selection)
          json_response(case status.status(snapshot,now) { status.Unavailable | status.Stale -> 503 _ -> 200 },status.to_json(snapshot,now))
        }
        http.Get, _ -> response.new(200)
          |> response.set_body(mist.Bytes(bytes_tree.from_string(selected_document_on_port(selection,component,listen_port(4100)))))
          |> response.set_header("content-type","text/html; charset=utf-8")
          |> response.set_header("cache-control","no-store")
        _, _ -> response.new(405)
          |> response.set_body(mist.Bytes(bytes_tree.from_string("Read-only homeostasis surface")))
          |> response.set_header("allow","GET")
      }
    }
  }
}

fn json_response(code: Int, body: String) -> Response(ResponseData) {
  response.new(code) |> response.set_body(mist.Bytes(bytes_tree.from_string(body)))
    |> response.set_header("content-type","application/json; charset=utf-8")
    |> response.set_header("cache-control","no-store")
    |> response.set_header("x-content-type-options","nosniff")
}

type Message { Tick }
type StreamState { StreamState(subject: process.Subject(Message), remaining: Int, selection: data.Selection) }

/// One timer per connected client; a connection is capped at 120 snapshots.
/// Reconnection is a new current snapshot, not event-history replay. No id is sent.
fn stream(req: Request(Connection), selection: data.Selection) -> Response(ResponseData) {
  mist.server_sent_events(
    request: req,
    initial_response: response.new(200) |> response.set_header("x-accel-buffering", "no"),
    init: fn(subject) {
      process.send(subject, Tick)
      StreamState(subject, 120, selection)
    },
    loop: fn(state, _message, connection) {
      let #(snapshot, now) = data.read(state.selection)
      let event = status.to_json(snapshot, now)
        |> string_tree.from_string()
        |> mist.event()
        |> mist.event_name("homeostasis_status")
        |> mist.event_retry(3000)
      case mist.send_event(connection, event) {
        Error(_) -> actor.stop()
        Ok(_) -> case state.remaining <= 1 {
          True -> actor.stop()
          False -> {
            let _ = process.send_after(state.subject, 1000, Tick)
            actor.continue(StreamState(..state, remaining: state.remaining - 1, selection: data.Selection(..state.selection,cycle: state.selection.cycle % 30 + 1)))
          }
        }
      }
    },
  )
}
