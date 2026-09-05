import cepaf_gleam/moz/client as moz
import gleam/io
import gleam/json
import gleam/list

pub fn main() {
  let state = moz.new()

  io.println("--- TESTING ALL MCP ENDPOINTS ---")

  let endpoints = [
    #("plan", "plan_list", json.object([])),
    #(
      "plan",
      "plan_get_pref",
      json.object([#("key", json.string("telegram_token"))]),
    ),
    #(
      "plan",
      "workspace_get_auth_url",
      json.object([#("client_id", json.string("test_client"))]),
    ),
    #("plan", "gmail_list_unread", json.object([])),
    #(
      "plan",
      "browser_screenshot",
      json.object([#("url", json.string("https://example.com"))]),
    ),
    #(
      "plan",
      "exec",
      json.object([#("command", json.string("echo 'hello from exec'"))]),
    ),
    #(
      "plan",
      "read_file",
      json.object([#("path", json.string("PROJECT_TODOLIST.md"))]),
    ),
    #("plan", "web_search", json.object([#("query", json.string("openclaw"))])),
  ]

  list.each(endpoints, fn(ep) {
    let #(domain, method, params) = ep
    io.print("Testing " <> method <> "... ")
    let #(_, result) = moz.send_request(state, domain, method, params)
    case result {
      Ok(req_id) -> io.println("DISPATCHED (ReqID: " <> req_id <> ")")
      Error(e) -> io.println("FAILED: " <> e)
    }
  })
}
