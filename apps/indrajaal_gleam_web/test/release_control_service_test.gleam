import gleam/int
import gleam/list
import gleam/result
import gleeunit/should
import indrajaal/release_control_service as service
import indrajaal/release_mcp
import release_mcp_test

pub fn canonical_finite_http_content_length_test() {
  list.each([1, 64, release_mcp.maximum_body_bytes], fn(n) {
    service.validate_headers([#("content-length", int.to_string(n))])
    |> should.equal(Ok(n))
  })
  list.each(
    [
      "",
      "0",
      "-1",
      "01",
      "+1",
      "1 ",
      " 1",
      "65537",
      "9999999999999999999999999",
    ],
    fn(raw) {
      service.validate_headers([#("content-length", raw)])
      |> result.is_error
      |> should.be_true
    },
  )
}

pub fn ambiguous_or_streaming_framing_refused_test() {
  list.each(
    [
      [],
      [#("content-length", "1"), #("Content-Length", "1")],
      [#("content-length", "1"), #("transfer-encoding", "chunked")],
      [#("content-length", "1"), #("Transfer-Encoding", "identity")],
    ],
    fn(hs) { service.validate_headers(hs) |> result.is_error |> should.be_true },
  )
}

pub fn explicit_tailnet_tls_configuration_has_no_plaintext_default_test() {
  let #(mcp, _, _, _, _, _, _) = release_mcp_test.fixture()
  service.configure(
    mcp,
    release_mcp_test.host,
    service.Loopback,
    4443,
    "/private/fixture/cert.pem",
    "/private/fixture/key.pem",
  )
  |> result.is_ok
  |> should.be_true
  list.each(
    [
      "0.0.0.0",
      "127.0.0.1",
      "localhost",
      "nas-1.tail55d152.ts.net.evil",
      "https://nas-1.tail55d152.ts.net",
      ".tail55d152.ts.net",
    ],
    fn(host) {
      service.configure(
        mcp,
        host,
        service.Loopback,
        4443,
        "/private/cert",
        "/private/key",
      )
      |> result.is_error
      |> should.be_true
    },
  )
  list.each(
    [
      #("relative", "/private/key"),
      #("/private/../cert", "/private/key"),
      #("/private/cert", "/private/cert"),
      #("/private/cert\n", "/private/key"),
    ],
    fn(p) {
      service.configure(
        mcp,
        release_mcp_test.host,
        service.Loopback,
        4443,
        p.0,
        p.1,
      )
      |> result.is_error
      |> should.be_true
    },
  )
  service.configure(
    mcp,
    release_mcp_test.host,
    service.Loopback,
    0,
    "/private/cert",
    "/private/key",
  )
  |> result.is_error
  |> should.be_true
  list.each(
    [
      service.TailnetIpv4(63, 0, 1),
      service.TailnetIpv4(128, 0, 1),
      service.TailnetIpv4(87, -1, 1),
      service.TailnetIpv4(87, 7, 256),
    ],
    fn(a) {
      service.configure(
        mcp,
        release_mcp_test.host,
        a,
        4443,
        "/private/cert",
        "/private/key",
      )
      |> result.is_error
      |> should.be_true
    },
  )
  service.configure(
    mcp,
    release_mcp_test.host,
    service.TailnetIpv4(87, 7, 78),
    4443,
    "/private/cert",
    "/private/key",
  )
  |> result.is_ok
  |> should.be_true
}
