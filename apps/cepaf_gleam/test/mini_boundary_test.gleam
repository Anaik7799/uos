import cepaf_gleam/telegram/mini_api as api
import cepaf_gleam/telegram/mini_view
import cepaf_gleam/telegram/types
import cepaf_gleam/web/mini_http
import gleam/dict
import gleam/http
import gleam/http/request
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import mini_test_vectors as v

@external(erlang, "mini_boundary_test_ffi", "set_clock")
fn set_clock(times: List(Int)) -> Nil

@external(erlang, "mini_boundary_test_ffi", "clock")
fn clock() -> Int

fn config() -> api.Configuration {
  api.configuration(
    "synthetic-mini-test-token",
    [api.AllowedIdentity(42, None)],
    300,
  )
  |> should.be_ok
}

fn body(init_data: String, path: String) -> String {
  json.object([
    #("init_data", json.string(init_data)),
    #("path", json.string(path)),
  ])
  |> json.to_string
}

fn req(data: String) -> request.Request(String) {
  request.new()
  |> request.set_path(api.data_path)
  |> request.set_method(http.Post)
  |> request.set_header("content-type", "application/json")
  |> request.set_body(data)
}

fn never(_read: api.AuthorizedRead) -> api.Observation {
  panic as "Unauthenticated backend call"
}

fn observed(_read: api.AuthorizedRead) -> api.Observation {
  api.Observed(
    1000,
    "synthetic_fixture",
    dict.from_list([#("Value", "<img src=x onerror=alert(1)>")]),
  )
}

pub fn exact_routes_test() {
  api.all_pages() |> list.length |> should.equal(14)
  list.each(api.all_pages(), fn(page) {
    api.parse_page(types.page_to_path(page)) |> should.equal(Ok(page))
  })
  list.each(
    [
      "/mini-appx",
      "/mini-app/dashboard/extra",
      "/mini-app/nope",
      "/mini-app/tasks?user=42",
      "/mini-app/%74asks",
      "/mini-app//tasks",
    ],
    fn(path) { api.parse_page(path) |> should.be_error },
  )
  api.owns_path("/mini-appx") |> should.equal(False)
  api.owns_path("/mini-app/tasks") |> should.equal(True)
}

pub fn signed_identity_and_chat_test() {
  let read =
    api.authorize(body(v.valid, "/mini-app/tasks"), config(), 1000)
    |> should.be_ok
  api.user_id(read) |> should.equal(42)
  api.page(read) |> should.equal(types.MiniPlanning)
  api.chat_id(read) |> should.equal(None)
  let restricted =
    api.configuration(
      "synthetic-mini-test-token",
      [api.AllowedIdentity(42, Some(-100_123))],
      300,
    )
    |> should.be_ok
  api.authorize(body(v.chat, "/mini-app/tasks"), restricted, 1000)
  |> should.be_ok
  api.authorize(body(v.valid, "/mini-app/tasks"), restricted, 1000)
  |> should.be_error
  api.authorize(body(v.wrong_chat, "/mini-app/tasks"), restricted, 1000)
  |> should.be_error
}

pub fn authentication_refusal_has_zero_backend_calls_test() {
  list.each(
    [v.wrong_user, v.expired, v.future, v.valid <> "0", "user=42"],
    fn(value) {
      let r =
        api.handle_data(
          req(body(value, "/mini-app/tasks")),
          Ok(config()),
          fn() { 1000 },
          never,
        )
      r.status |> should.equal(401)
      string.contains(r.body, "synthetic-mini-test-token")
      |> should.equal(False)
    },
  )
  api.handle_data(req("{}"), Ok(config()), fn() { 1000 }, never).status
  |> should.equal(400)
  api.handle_data(
    req(body(v.valid, "/mini-app/nope")),
    Ok(config()),
    fn() { 1000 },
    never,
  ).status
  |> should.equal(400)
  api.handle_data(
    req(body(v.valid, "/mini-app/tasks")),
    Error(api.ConfigurationUnavailable),
    fn() { 1000 },
    never,
  ).status
  |> should.equal(503)
  api.configuration("", [api.AllowedIdentity(42, None)], 300) |> should.be_error
  api.configuration("token", [], 300) |> should.be_error
}

pub fn method_and_content_type_test() {
  let r = req(body(v.valid, "/mini-app/tasks"))
  api.handle_data(
    request.set_method(r, http.Get),
    Ok(config()),
    fn() { 1000 },
    never,
  ).status
  |> should.equal(405)
  api.handle_data(
    request.set_path(r, "/mini-app/api/datax"),
    Ok(config()),
    fn() { 1000 },
    never,
  ).status
  |> should.equal(404)
  api.handle_data(
    request.set_header(r, "content-type", "text/plain"),
    Ok(config()),
    fn() { 1000 },
    never,
  ).status
  |> should.equal(415)
  api.handle_data(
    request.set_method(r, http.Options),
    Ok(config()),
    fn() { 1000 },
    never,
  ).status
  |> should.equal(204)
  api.handle_data(
    req(string.repeat("x", 8193)),
    Ok(config()),
    fn() { 1000 },
    never,
  ).status
  |> should.equal(400)
}

pub fn observed_and_stale_outputs_test() {
  let r = req(body(v.valid, "/mini-app/tasks"))
  let good = api.handle_data(r, Ok(config()), fn() { 1000 }, observed)
  good.status |> should.equal(200)
  string.contains(good.body, "\"status\":\"observed\"") |> should.be_true
  string.contains(good.body, "synthetic_fixture") |> should.be_true
  let stale =
    api.handle_data(r, Ok(config()), fn() { 1000 }, fn(_) {
      api.Observed(
        900,
        "old_fixture",
        dict.from_list([#("old", "DO_NOT_EXPOSE")]),
      )
    })
  string.contains(stale.body, "\"status\":\"stale\"") |> should.be_true
  string.contains(stale.body, "DO_NOT_EXPOSE") |> should.equal(False)
  let absent =
    api.handle_data(r, Ok(config()), fn() { 1000 }, fn(_) {
      api.Unavailable("private_backend_error")
    })
  string.contains(absent.body, "\"status\":\"unavailable\"") |> should.be_true
  string.contains(absent.body, "private_backend_error") |> should.equal(False)
  let huge =
    api.handle_data(r, Ok(config()), fn() { 1000 }, fn(_) {
      api.Observed(
        1000,
        "fixture",
        dict.from_list([#("large", string.repeat("x", 2049))]),
      )
    })
  huge.status |> should.equal(503)
}

pub fn authorization_expiry_and_clock_change_after_read_test() {
  let r = req(body(v.valid, "/mini-app/tasks"))
  set_clock([1299, 1301])
  api.handle_data(r, Ok(config()), clock, observed).status |> should.equal(401)
  set_clock([1000, 999])
  api.handle_data(r, Ok(config()), clock, observed).status |> should.equal(503)
  set_clock([1000, 1006])
  api.handle_data(r, Ok(config()), clock, observed).status |> should.equal(503)
}

pub fn body_policy_bounds_test() {
  mini_http.body_policy(http.Post, [#("content-length", "8192")])
  |> should.equal(mini_http.ReadBody(8192))
  mini_http.body_policy(http.Post, [#("content-length", "8193")])
  |> should.equal(mini_http.Refuse(413))
  mini_http.body_policy(http.Post, []) |> should.equal(mini_http.Refuse(411))
  list.each(["-1", "0", "1x", "0001"], fn(n) {
    mini_http.body_policy(http.Post, [#("content-length", n)])
    |> should.equal(mini_http.Refuse(400))
  })
  mini_http.body_policy(http.Post, [
    #("transfer-encoding", "chunked"),
    #("content-length", "1"),
  ])
  |> should.equal(mini_http.Refuse(400))
  mini_http.body_policy(http.Post, [
    #("Content-Length", "1"),
    #("content-length", "2"),
  ])
  |> should.equal(mini_http.Refuse(400))
}

pub fn public_shell_has_no_operational_defaults_test() {
  list.each(api.all_pages(), fn(page) {
    let html = mini_view.public_page(page)
    string.contains(html, "Open this page through the configured Telegram bot")
    |> should.be_true
    string.contains(html, "All Clear") |> should.equal(False)
    string.contains(html, ">17<") |> should.equal(False)
    string.contains(html, "CHK-18-JJ") |> should.be_true
    string.contains(html, "http://nas-1.tail55d152.ts.net:4100")
    |> should.be_true
    string.split(html, "type=\"checkbox\"") |> list.length |> should.equal(19)
  })
}
