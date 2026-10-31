//// Explicit TLS-only listener. No default port/configuration, global start,
//// inference startup, secret logging or production admission. The reviewed
//// owner supplies certificate/key paths and an independently trusted registry.

import cepaf_gleam/ecology/release_identity
import cepaf_gleam/mcp/http_auth
import cepaf_gleam/mcp/transports/http
import gleam/bit_array
import gleam/bytes_tree
import gleam/http as gleam_http
import gleam/http/request
import gleam/http/response
import gleam/int
import gleam/list
import gleam/otp/supervision
import gleam/result
import gleam/string
import indrajaal/release_mcp
import mist

pub opaque type Configuration {
  Configuration(
    ingress: release_mcp.Configuration,
    host: String,
    bind: String,
    port: Int,
    certificate: String,
    private_key: String,
  )
}

/// Glisten accepts numeric bind addresses, not FQDNs. The explicit trusted
/// provider must bind the advertised Tailnet FQDN, IP and certificate together;
/// this finite socket configuration cannot authenticate that association.
pub type ListenAddress {
  Loopback
  TailnetIpv4(second: Int, third: Int, fourth: Int)
}

fn listen_address(address: ListenAddress) -> Result(String, String) {
  case address {
    Loopback -> Ok("127.0.0.1")
    TailnetIpv4(b, c, d)
      if b >= 64 && b <= 127 && c >= 0 && c <= 255 && d >= 0 && d <= 255
    ->
      Ok(
        "100."
        <> int.to_string(b)
        <> "."
        <> int.to_string(c)
        <> "."
        <> int.to_string(d),
      )
    _ -> Error("RELEASE_SERVICE_CONFIGURATION_REFUSED")
  }
}

fn path(s: String) -> Bool {
  string.starts_with(s, "/")
  && string.byte_size(s) <= 4096
  && list.all(string.split(s, "/") |> list.drop(1), fn(p) {
    p != ""
    && p != "."
    && p != ".."
    && list.all(string.to_utf_codepoints(p), fn(c) {
      let n = string.utf_codepoint_to_int(c)
      n > 32 && n != 127 && n != 92
    })
  })
}

pub fn configure(
  ingress: release_mcp.Configuration,
  host: String,
  listen: ListenAddress,
  port: Int,
  certificate: String,
  private_key: String,
) -> Result(Configuration, String) {
  use bind <- result.try(listen_address(listen))
  case
    release_identity.tailnet_issuer("https://" <> host)
    && !string.contains(host, "/")
    && !string.contains(host, ":")
    && port >= 1
    && port <= 65_535
    && path(certificate)
    && path(private_key)
    && certificate != private_key
  {
    True ->
      Ok(Configuration(ingress, host, bind, port, certificate, private_key))
    False -> Error("RELEASE_SERVICE_CONFIGURATION_REFUSED")
  }
}

fn reply(r: http.HttpResponse) {
  list.fold(
    r.headers,
    response.new(r.status)
      |> response.set_body(mist.Bytes(bytes_tree.from_string(r.body))),
    fn(acc, h) { response.set_header(acc, h.0, h.1) },
  )
}

/// Reject ambiguous framing BEFORE pulling the body. Mist's read_body uses
/// Content-Length, so this service accepts exactly one canonical finite length
/// and no Transfer-Encoding. The handler has no public plaintext listener.
pub fn validate_headers(
  headers: List(#(String, String)),
) -> Result(Int, String) {
  let hs = list.take(headers, 33)
  use _ <- result.try(
    case
      list.length(hs) <= 32
      && list.all(hs, fn(h) {
        string.byte_size(h.0) <= 128 && string.byte_size(h.1) <= 16_384
      })
      && !list.any(hs, fn(h) { string.lowercase(h.0) == "transfer-encoding" })
    {
      True -> Ok(Nil)
      False -> Error("RELEASE_HTTP_FRAMING_REFUSED")
    },
  )
  use raw <- result.try(
    http_auth.header(hs, "content-length")
    |> result.replace_error("RELEASE_HTTP_FRAMING_REFUSED"),
  )
  use n <- result.try(
    int.parse(raw) |> result.replace_error("RELEASE_HTTP_FRAMING_REFUSED"),
  )
  case
    n >= 1 && n <= release_mcp.maximum_body_bytes && int.to_string(n) == raw
  {
    True -> Ok(n)
    False -> Error("RELEASE_HTTP_FRAMING_REFUSED")
  }
}

fn refused() {
  reply(http.HttpResponse(
    400,
    http.security_headers(),
    "{\"error\":\"RELEASE_HTTP_FRAMING_REFUSED\"}",
  ))
}

pub fn handle(config: Configuration, req: request.Request(mist.Connection)) {
  case
    req.method == gleam_http_post(),
    req.path == "/mcp",
    validate_headers(req.headers)
  {
    True, True, Ok(expected) ->
      case mist.read_body(req, release_mcp.maximum_body_bytes) {
        Ok(body) ->
          case bit_array.to_string(body.body) {
            Ok(raw) ->
              case string.byte_size(raw) == expected {
                True ->
                  release_mcp.handle_http(
                    config.ingress,
                    http.HttpRequest("POST", "/mcp", req.headers, raw),
                  )
                  |> reply
                False -> refused()
              }
            _ -> refused()
          }
        Error(_) -> refused()
      }
    _, _, _ -> refused()
  }
}

// Constructor isolated from request strings; method cannot be spoofed by args.
fn gleam_http_post() {
  gleam_http.Post
}

pub fn start(config: Configuration) {
  mist.new(fn(req) { handle(config, req) })
  |> mist.bind(config.bind)
  |> mist.port(config.port)
  |> mist.with_tls(config.certificate, config.private_key)
  |> mist.start
}

pub fn child_spec(config: Configuration) {
  supervision.supervisor(fn() { start(config) })
}
