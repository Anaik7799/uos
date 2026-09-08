import cepaf_gleam/ui/homeostasis_data as data
import gleam/http
import gleam/http/request
import gleam/list
import gleam/string
import gleeunit/should
import indrajaal/homeostasis_http
import indrajaal/manual_test
import mist.{type Connection}

@external(erlang, "auth_ingress_test_ffi", "connection_request")
fn connection_request(
  headers: List(#(String, String)),
  initial_body: BitArray,
) -> request.Request(Connection)

pub fn manual_listener_reuses_framing_rejection_before_routing_test() {
  list.each(
    [
      #([#("transfer-encoding", "chunked")], 400),
      #([#("expect", "100-continue")], 417),
      #([#("content-length", "65537")], 413),
      #([#("content-length", "1"), #("content-length", "1")], 400),
    ],
    fn(test_case) {
      let reply = connection_request(test_case.0, <<>>) |> manual_test.handle()
      reply.status |> should.equal(test_case.1)
    },
  )
}

pub fn operational_paths_and_methods_are_refused_test() {
  list.each(
    [[], ["homeostasis"], ["api", "v1", "homeostasis", "review"]],
    fn(path) {
      list.each(
        [http.Post, http.Put, http.Delete, http.Patch, http.Options],
        fn(method) {
          manual_test.route(method, path) |> should.equal(manual_test.Refused)
        },
      )
    },
  )
  list.each(
    [
      ["files", "AGENTS.md"],
      ["raw", "AGENTS.md"],
      ["api", "mcp"],
      ["api", "verify", "patrol"],
      ["planning"],
      ["homeostasis", "..", "files"],
      ["api", "v1", "homeostasis", "execute"],
    ],
    fn(path) {
      manual_test.route(http.Get, path) |> should.equal(manual_test.Refused)
    },
  )
}

pub fn explicit_read_only_routes_are_available_test() {
  list.each(
    [
      [],
      ["homeostasis"],
      ["homeostasis", "evolution"],
      ["homeostasis", "terminal"],
      ["homeostasis", "components"],
      ["api", "v1", "homeostasis"],
      ["api", "v1", "homeostasis", "review"],
      ["api", "v1", "homeostasis", "stream"],
    ],
    fn(path) {
      manual_test.route(http.Get, path) |> should.equal(manual_test.Homeostasis)
    },
  )
  manual_test.route(http.Get, ["api", "v1", "runtime", "identity"])
  |> should.equal(manual_test.Identity)
}

pub fn bind_cannot_select_production_or_all_interfaces_test() {
  manual_test.bounded_target("100.87.7.78", 59_463) |> should.be_true()
  list.each(
    [
      "0.0.0.0",
      "127.0.0.1",
      "100.63.0.1",
      "100.128.0.1",
      "100.87.999.1",
      "100.87.-1.1",
      "100.87.1.x",
    ],
    fn(host) { manual_test.bounded_target(host, 59_463) |> should.be_false() },
  )
  list.each([4100, 0, 49_151, 65_536], fn(port) {
    manual_test.bounded_target("100.87.7.78", port) |> should.be_false()
  })
}

pub fn all_navigation_uses_the_listener_port_test() {
  let html =
    homeostasis_http.selected_document_on_port(data.default(), "all", 59_463)
  string.contains(html, "href=\"http://nas-1.tail55d152.ts.net:4100")
  |> should.be_false()
  string.contains(
    html,
    "href=\"http://nas-1.tail55d152.ts.net:59463/homeostasis/components?",
  )
  |> should.be_true()
  string.contains(
    html,
    "href=\"http://nas-1.tail55d152.ts.net:59463/api/v1/runtime/identity\"",
  )
  |> should.be_true()
}
