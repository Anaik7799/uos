//// Exact Mini App data ingress; other POST authentication is unchanged.
//// Mist's max-body helper trusts Content-Length. Reject transfer coding and
//// ambiguous/missing lengths before reading, then verify the returned byte count.

import cepaf_gleam/telegram/mini_control
import cepaf_gleam/telegram/mini_api
import cepaf_gleam/ui/wisp/mini_app_routes
import gleam/bit_array
import gleam/bytes_tree
import gleam/http
import gleam/http/request
import gleam/http/response
import gleam/int
import gleam/list
import gleam/string
import mist

pub type BodyPolicy {
  NoBody
  ReadBody(Int)
  Refuse(Int)
}

pub fn body_policy(
  method: http.Method,
  headers: List(#(String, String)),
) -> BodyPolicy {
  case method != http.Post {
    True -> NoBody
    False -> {
      let transfer =
        list.any(headers, fn(h) { string.lowercase(h.0) == "transfer-encoding" })
      let lengths =
        list.filter(headers, fn(h) { string.lowercase(h.0) == "content-length" })
      case transfer, lengths {
        True, _ -> Refuse(400)
        False, [#(_, raw)] ->
          case int.parse(raw) {
            Ok(n) if n > mini_api.max_body_bytes -> Refuse(413)
            Ok(n) ->
              case n > 0 && int.to_string(n) == raw {
                True -> ReadBody(n)
                False -> Refuse(400)
              }
            Error(_) -> Refuse(400)
          }
        False, [] -> Refuse(411)
        False, _ -> Refuse(400)
      }
    }
  }
}

fn convert(
  r: response.Response(String),
) -> response.Response(mist.ResponseData) {
  response.set_body(r, mist.Bytes(bytes_tree.from_string(r.body)))
}

fn refused(status: Int) -> response.Response(mist.ResponseData) {
  response.new(status)
  |> response.set_body("{\"error\":\"invalid_or_oversize_body\"}")
  |> response.set_header("content-type", "application/json")
  |> response.set_header("cache-control", "no-store")
  |> response.set_header("x-content-type-options", "nosniff")
  |> response.set_header("connection", "close")
  |> convert
}

pub fn handle(
  req: request.Request(mist.Connection),
) -> response.Response(mist.ResponseData) {
  case req.path != mini_api.data_path && !mini_control.owns(req.path) {
    True -> refused(404)
    False ->
      case body_policy(req.method, req.headers) {
        Refuse(status) -> refused(status)
        NoBody -> mini_app_routes.handle(request.set_body(req, "")) |> convert
        ReadBody(expected) ->
          case mist.read_body(req, mini_api.max_body_bytes) {
            Error(mist.ExcessBody) -> refused(413)
            Error(mist.MalformedBody) -> refused(400)
            Ok(read) ->
              case bit_array.byte_size(read.body) == expected {
                False -> refused(400)
                True ->
                  case bit_array.to_string(read.body) {
                    Error(_) -> refused(400)
                    Ok(body) ->
                      mini_app_routes.handle(request.set_body(read, body))
                      |> convert
                  }
              }
          }
      }
  }
}
