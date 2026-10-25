//// Private read-only UI probe. No OTP control actors or production listeners.

import cepaf_gleam/ecology/harmonic_song
import cepaf_gleam/ecology/living_swarm
import cepaf_gleam/harness/files
import cepaf_gleam/ui/wisp/router
import cepaf_gleam/web/homeostasis_http
import gleam/bytes_tree
import gleam/erlang/process
import gleam/http
import gleam/http/request
import gleam/http/response
import gleam/list
import gleam/string
import mist

pub fn main() {
  let handler = fn(req: request.Request(mist.Connection)) {
    case req.method == http.Get {
      False ->
        response.new(405)
        |> response.set_body(
          mist.Bytes(bytes_tree.from_string("Read-only private probe")),
        )
      True ->
        case homeostasis_http.handles(req.path) {
          True -> homeostasis_http.handle_on_port(req, 49_157)
          False ->
            case req.path == "/ecology-song" {
              True -> {
                let song =
                  living_swarm.step_swarm_cycle(
                    living_swarm.init_living_swarm(),
                  ).current_song
                response.new(200)
                |> response.set_header(
                  "content-type",
                  "text/html; charset=utf-8",
                )
                |> response.set_body(
                  mist.Bytes(bytes_tree.from_string(
                    "<!doctype html><html><head><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'></head><body><h1>Ecology chart: development fixture</h1><a href='http://nas-1.tail55d152.ts.net:4100/'>Cockpit</a><div style='max-width:100%;overflow:auto'>"
                    <> harmonic_song.render_song_svg(song)
                    <> "</div><details><summary>Fixture evidence</summary>Simulated chart; no runtime admission.</details></body></html>",
                  )),
                )
              }
              False ->
                case
                  list.contains(
                    [
                      "/static/dashboard-grid.js", "/static/material.css",
                      "/static/sw-register.js",
                      "/static/20260930-0633-restoration-dashboard.html",
                      "/static/20260930-0633-restoration-state.json",
                    ],
                    req.path,
                  )
                {
                  True -> {
                    let relative = "apps/cepaf_gleam/priv" <> req.path
                    case files.read("/home/an/NAS-setup/uos", relative) {
                      Error(_) ->
                        response.new(404)
                        |> response.set_body(
                          mist.Bytes(bytes_tree.from_string(
                            "Static fixture unavailable",
                          )),
                        )
                      Ok(body) -> {
                        let mime = case string.ends_with(req.path, ".js") {
                          True -> "application/javascript"
                          False ->
                            case string.ends_with(req.path, ".json") {
                              True -> "application/json"
                              False ->
                                case string.ends_with(req.path, ".css") {
                                  True -> "text/css"
                                  False -> "text/html; charset=utf-8"
                                }
                            }
                        }
                        response.new(200)
                        |> response.set_header("content-type", mime)
                        |> response.set_body(
                          mist.Bytes(bytes_tree.from_string(body)),
                        )
                      }
                    }
                  }
                  False ->
                    case
                      list.contains(
                        ["/", "/wiki", "/zk", "/planning", "/mirage"],
                        req.path,
                      )
                    {
                      True -> {
                        let rendered =
                          router.handle_request(request.set_body(req, ""))
                        let result =
                          response.new(rendered.status)
                          |> response.set_body(
                            mist.Bytes(bytes_tree.from_string(rendered.body)),
                          )
                        list.fold(rendered.headers, result, fn(acc, h) {
                          response.set_header(acc, h.0, h.1)
                        })
                      }
                      False ->
                        response.new(404)
                        |> response.set_body(
                          mist.Bytes(bytes_tree.from_string(
                            "Private probe: route unavailable",
                          )),
                        )
                    }
                }
            }
        }
    }
  }
  let assert Ok(_) =
    mist.new(handler)
    |> mist.port(49_157)
    |> mist.bind("127.0.0.1")
    |> mist.start()
  process.sleep(25_000)
}
