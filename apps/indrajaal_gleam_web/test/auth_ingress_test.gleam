import gleam/bit_array
import gleam/bytes_tree
import gleam/http.{Get, Head, Post}
import gleam/http/request
import gleam/http/response.{type Response}
import gleam/list
import gleam/string
import gleeunit/should
import indrajaal_gleam_web
import mist.{type Connection, type ResponseData, Bytes}

const signed_oidc_token = "eyJhbGciOiJFZERTQSIsImtpZCI6InJmYzgwMzctdGVzdCIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJ1c2VyLTEyMyIsImV4cCI6MjAwMDAwMDMwMCwiaXNzIjoiaHR0cHM6Ly9pc3N1ZXIuZXhhbXBsZS9yZWFsbXMvYzNpIiwiYXVkIjoiYzNpLXdpc3AtYXBpIn0.mfaSQdB3lV47YleIzp9Kr3dFpBgZ87aiQBr3F_BMWdOUjAGJwoiRifw8ZtZcazFPL1gxFfgSQSz04xDhCVtuAg"

@external(erlang, "auth_ingress_test_ffi", "with_oidc_env")
fn with_oidc_env(run: fn() -> Nil) -> Nil

@external(erlang, "auth_ingress_test_ffi", "connection_request")
fn connection_request(
  headers: List(#(String, String)),
  initial_body: BitArray,
) -> request.Request(Connection)

@external(erlang, "auth_ingress_test_ffi", "with_stalled_connection")
fn with_stalled_connection(
  run: fn(request.Request(Connection)) -> Response(ResponseData),
) -> Response(ResponseData)

pub fn method_auth_body_and_response_are_preserved_test() {
  with_oidc_env(fn() {
    let get_reload = send(Get, "/api/v1/reload", "", None)
    get_reload.status |> should.equal(405)
    header(get_reload, "allow") |> should.equal("POST, OPTIONS")

    let head_reload = send(Head, "/api/v1/reload", "", None)
    head_reload.status |> should.equal(405)
    response_body(head_reload) |> should.equal("")

    let unauthenticated = send(Post, "/api/v1/reload", "", None)
    unauthenticated.status |> should.equal(401)

    let no_static_downgrade =
      send(Post, "/ag-ui/run", "", Some("must-not-authorize-in-oidc-mode"))
    no_static_downgrade.status |> should.equal(401)

    let signed = send(Post, "/ag-ui/run", "", Some(signed_oidc_token))
    signed.status |> should.equal(200)
    response_body(signed) |> string.contains("run_id") |> should.be_true()

    let body_sensitive =
      send(
        Post,
        "/api/v1/plan/update",
        "{\"id\":\"fixture-only\",\"status\":\"deliberately_invalid\"}",
        Some(signed_oidc_token),
      )
    body_sensitive.status |> should.equal(400)
    response_body(body_sensitive)
    |> string.contains("invalid status: deliberately_invalid")
    |> should.be_true()

    let missing = send(Get, "/api/v1/not-present", "", None)
    missing.status |> should.equal(404)
    header(missing, "content-type") |> should.equal("application/json")

    let events = send(Get, "/ag-ui/events", "", None)
    events.status |> should.equal(200)
    header(events, "content-type") |> should.equal("text/event-stream")
    header(events, "cache-control") |> should.equal("no-cache")
  })
}

pub fn body_conversion_is_bounded_and_utf8_checked_test() {
  let oversized = send(Get, "/api/v1/health", string.repeat("x", 65_537), None)
  oversized.status |> should.equal(413)
  response_body(oversized)
  |> string.contains("request_body_too_large")
  |> should.be_true()

  let invalid_utf8 =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/api/v1/health")
    |> request.set_body(<<255>>)
    |> indrajaal_gleam_web.handle_c3i_http_request()
  invalid_utf8.status |> should.equal(400)
  response_body(invalid_utf8)
  |> string.contains("request_body_not_utf8")
  |> should.be_true()
}

pub fn actual_mist_adapter_rejects_unsafe_framing_before_read_test() {
  let payload = bit_array.from_string(string.repeat("x", 65_537))
  let chunked_wire =
    bit_array.append(
      bit_array.from_string("10001\r\n"),
      bit_array.append(payload, bit_array.from_string("\r\n0\r\n\r\n")),
    )

  let chunked =
    connection_request([#("transfer-encoding", "chunked")], chunked_wire)
    |> dispatch_connection()
  chunked.status |> should.equal(400)
  response_body(chunked)
  |> string.contains("request_transfer_encoding_unsupported")
  |> should.be_true()

  let ambiguous =
    connection_request([#("content-length", "1"), #("content-length", "1")], <<
      "x":utf8,
    >>)
    |> dispatch_connection()
  ambiguous.status |> should.equal(400)

  let combined =
    connection_request([#("content-length", "1, 1")], <<"x":utf8>>)
    |> dispatch_connection()
  combined.status |> should.equal(400)

  let invalid =
    connection_request([#("content-length", "+1")], <<"x":utf8>>)
    |> dispatch_connection()
  invalid.status |> should.equal(400)

  let oversized =
    connection_request([#("content-length", "65537")], payload)
    |> dispatch_connection()
  oversized.status |> should.equal(413)

  let declared_shorter_than_buffer =
    connection_request([#("content-length", "1")], <<"xx":utf8>>)
    |> dispatch_connection()
  declared_shorter_than_buffer.status |> should.equal(400)

  let declared_empty_with_buffer =
    connection_request([#("content-length", "0")], <<"x":utf8>>)
    |> dispatch_connection()
  declared_empty_with_buffer.status |> should.equal(400)

  let conflicting =
    connection_request(
      [#("transfer-encoding", "chunked"), #("content-length", "1")],
      chunked_wire,
    )
    |> dispatch_connection()
  conflicting.status |> should.equal(400)
}

pub fn actual_mist_adapter_admits_bounded_fixed_length_test() {
  let fixed =
    connection_request(
      [#("content-length", "5")],
      bit_array.from_string("hello"),
    )
    |> dispatch_connection()
  fixed.status |> should.equal(299)
  response_body(fixed) |> should.equal("hello")

  let bodyless =
    connection_request([], bit_array.from_string("unframed-must-not-pass"))
    |> dispatch_connection()
  bodyless.status |> should.equal(299)
  response_body(bodyless) |> should.equal("")
}

pub fn actual_mist_adapter_rejects_expectation_before_read_test() {
  let expectation =
    connection_request(
      [#("expect", "100-continue"), #("content-length", "1")],
      <<>>,
    )
    |> dispatch_connection()
  expectation.status |> should.equal(417)
  response_body(expectation)
  |> string.contains("request_expectation_unsupported")
  |> should.be_true()
}

pub fn actual_mist_adapter_enforces_total_read_deadline_test() {
  let timed_out = with_stalled_connection(dispatch_connection)
  timed_out.status |> should.equal(408)
  response_body(timed_out)
  |> string.contains("request_body_read_timeout")
  |> should.be_true()
}

fn dispatch_connection(
  req: request.Request(Connection),
) -> Response(ResponseData) {
  indrajaal_gleam_web.handle_bounded_connection_request(req, fn(bounded) {
    response.new(299)
    |> response.set_body(mist.Bytes(bytes_tree.from_bit_array(bounded.body)))
  })
}

type MaybeToken {
  None
  Some(String)
}

fn send(
  method: http.Method,
  path: String,
  body: String,
  token: MaybeToken,
) -> Response(ResponseData) {
  let req =
    request.new()
    |> request.set_method(method)
    |> request.set_path(path)
    |> request.set_body(bit_array.from_string(body))
  case token {
    None -> req
    Some(value) -> request.set_header(req, "authorization", "Bearer " <> value)
  }
  |> indrajaal_gleam_web.handle_c3i_http_request()
}

fn response_body(response: Response(ResponseData)) -> String {
  let assert Bytes(body) = response.body
  let bits = bytes_tree.to_bit_array(body)
  let assert Ok(text) = bit_array.to_string(bits)
  text
}

fn header(response: Response(ResponseData), name: String) -> String {
  list.key_find(response.headers, name) |> should.be_ok()
}
