import gleam/bit_array
import gleam/bytes_tree
import gleam/http.{Get, Head, Post}
import gleam/http/request
import gleam/http/response.{type Response}
import gleam/list
import gleam/string
import gleeunit/should
import indrajaal_gleam_web
import mist.{type ResponseData, Bytes}

const signed_oidc_token = "eyJhbGciOiJFZERTQSIsImtpZCI6InJmYzgwMzctdGVzdCIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJ1c2VyLTEyMyIsImV4cCI6MjAwMDAwMDMwMCwiaXNzIjoiaHR0cHM6Ly9pc3N1ZXIuZXhhbXBsZS9yZWFsbXMvYzNpIiwiYXVkIjoiYzNpLXdpc3AtYXBpIn0.mfaSQdB3lV47YleIzp9Kr3dFpBgZ87aiQBr3F_BMWdOUjAGJwoiRifw8ZtZcazFPL1gxFfgSQSz04xDhCVtuAg"

@external(erlang, "auth_ingress_test_ffi", "with_oidc_env")
fn with_oidc_env(run: fn() -> Nil) -> Nil

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
