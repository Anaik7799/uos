//// Wave 6i: the HTTP media transport against the local HTTP fixture. Every
//// byte the transport fetches comes from the fixture on the configured base
//// host; the api.telegram.org prefix the download adapter builds is accepted
//// only for the configured token and rewritten onto that host.

import cepaf_gleam/harness/telegram_http_client as http_client
import cepaf_gleam/harness/telegram_media_download as dl
import cepaf_gleam/harness/telegram_media_inspect as inspect
import cepaf_gleam/harness/telegram_media_intake as intake
import cepaf_gleam/harness/telegram_media_ref as ref
import cepaf_gleam/harness/telegram_media_store as store
import cepaf_gleam/harness/telegram_media_transport as transport
import gleam/bit_array
import gleam/crypto
import gleam/dynamic.{type Dynamic}
import gleam/erlang/process.{type Pid}
import gleam/int
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import simplifile

@external(erlang, "telegram_http_test_fixture", "start")
fn fixture_start() -> Result(#(Pid, Int, String), Dynamic)

@external(erlang, "telegram_http_test_fixture", "stop")
fn fixture_stop(pid: Pid) -> Dynamic

@external(erlang, "telegram_http_test_fixture", "set_file_opts")
fn fixture_set_file_opts(
  pid: Pid,
  file_id: String,
  file_path: String,
  bytes: BitArray,
  declare_size: Bool,
) -> Dynamic

@external(erlang, "telegram_http_test_fixture", "set_file")
fn fixture_set_file(
  pid: Pid,
  file_id: String,
  file_path: String,
  bytes: BitArray,
) -> Dynamic

@external(erlang, "erlang", "monotonic_time")
fn monotonic_now() -> Int

const token = "test-token-media-transport"

const png = <<0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 9, 8, 7, 6, 5, 4>>

fn config(base_url: String) -> http_client.TelegramHttpConfiguration {
  http_client.TelegramHttpConfiguration(
    base_url: base_url,
    bot_token: token,
    timeout_ms: 5000,
    max_response_bytes: 65_536,
  )
}

fn fresh_root() -> String {
  let root =
    "/tmp/uos-tg-media-transport-test/root-"
    <> int.to_string(monotonic_now())
    <> "-"
    <> int.to_string(int.random(1_000_000))
  let _ = simplifile.create_directory_all(root <> "/objects")
  root
}

fn policy(root: String) -> store.Policy {
  store.Policy(
    root: root,
    base: "objects",
    retention_ms: 60_000,
    total_ceiling_bytes: 1_048_576,
  )
}

fn photo_ref(file_id: String, declared: option.Option(Int)) -> ref.MediaRef {
  ref.MediaRef(
    kind: ref.Photo,
    file_unique_id: "uniq-" <> file_id,
    file_id: file_id,
    declared_size_bytes: declared,
    declared_mime: Some("image/png"),
    declared_duration_s: None,
    caption: Some("/status"),
  )
}

fn sha256_hex(bytes: BitArray) -> String {
  crypto.hash(crypto.Sha256, bytes)
  |> bit_array.base16_encode
  |> string.lowercase
}

pub fn get_file_answers_the_registered_locator_test() {
  let assert Ok(#(pid, _port, base_url)) = fixture_start()
  fixture_set_file(pid, "fid-1", "photos/one.png", png)
  http_client.get_file(config(base_url), "fid-1", 3000)
  |> should.equal(
    Ok(http_client.FileLocator(
      file_path: "photos/one.png",
      declared_size_bytes: Some(bit_array.byte_size(png)),
    )),
  )
  http_client.get_file(config(base_url), "fid-unknown", 3000)
  |> should.equal(Error("get_file_status_400"))
  http_client.get_file(config(base_url), "", 3000)
  |> should.equal(Error("invalid_file_id"))
  fixture_stop(pid)
}

pub fn fetch_file_bytes_is_bounded_and_exact_test() {
  let assert Ok(#(pid, _port, base_url)) = fixture_start()
  fixture_set_file(pid, "fid-2", "photos/two.png", png)
  http_client.fetch_file_bytes(config(base_url), "photos/two.png", 1024, 3000)
  |> should.equal(Ok(png))
  // a body larger than the bound is an error, never a truncated success
  let assert Error(reason) =
    http_client.fetch_file_bytes(config(base_url), "photos/two.png", 4, 3000)
  string.starts_with(reason, "fetch_file_") |> should.be_true
  // a path the fixture does not serve
  http_client.fetch_file_bytes(config(base_url), "photos/none.png", 1024, 3000)
  |> should.equal(Error("fetch_file_status_404"))
  // hostile paths never leave the client
  http_client.fetch_file_bytes(config(base_url), "../etc/passwd", 1024, 3000)
  |> should.equal(Error("fetch_file_invalid_file_path"))
  fixture_stop(pid)
}

pub fn file_url_is_accepted_only_for_this_bot_test() {
  let cfg = config("http://unused.invalid")
  transport.file_path_of(
    cfg,
    "https://api.telegram.org/file/bot" <> token <> "/photos/x.png",
  )
  |> should.equal(Ok("photos/x.png"))
  transport.file_path_of(
    cfg,
    "https://api.telegram.org/file/botOTHER-TOKEN/photos/x.png",
  )
  |> should.equal(Error("file_url_not_for_this_bot"))
  transport.file_path_of(cfg, "https://evil.example/file/bot" <> token <> "/x")
  |> should.equal(Error("file_url_not_for_this_bot"))
  transport.file_path_of(
    cfg,
    "https://api.telegram.org/file/bot" <> token <> "/../secrets",
  )
  |> should.equal(Error("file_url_invalid_path"))
  transport.file_path_of(
    cfg,
    "https://api.telegram.org/file/bot" <> token <> "/a?b=c",
  )
  |> should.equal(Error("file_url_invalid_path"))
}

pub fn intake_through_the_http_transport_stores_the_fixture_bytes_test() {
  let assert Ok(#(pid, _port, base_url)) = fixture_start()
  fixture_set_file(pid, "fid-3", "photos/three.png", png)
  let root = fresh_root()
  let cfg = config(base_url)
  let binding =
    Some(intake.Binding(policy(root), Some(transport.from_http(cfg))))
  let out =
    intake.run(binding, photo_ref("fid-3", None), fn() { Ok(token) }, 5000)
  let assert intake.Stored(sha, bytes, sniffed, written, _) = out
  sha |> should.equal(sha256_hex(png))
  bytes |> should.equal(bit_array.byte_size(png))
  sniffed |> should.equal(inspect.Png)
  written |> should.be_true
  let assert Ok(#(_, content)) = store.get(policy(root), sha, 6000)
  content |> should.equal(png)
  // the reply carries the digest and never the token or the file URL
  let reply =
    intake.reply_json(
      out,
      photo_ref("fid-3", None),
      "query_system_health",
      "tg-3",
    )
  string.contains(reply, sha) |> should.be_true
  string.contains(reply, token) |> should.be_false
  string.contains(reply, "/file/bot") |> should.be_false
  fixture_stop(pid)
}

pub fn declared_over_cap_is_refused_before_any_fetch_test() {
  let assert Ok(#(pid, _port, base_url)) = fixture_start()
  let root = fresh_root()
  let binding =
    Some(intake.Binding(
      policy(root),
      Some(transport.from_http(config(base_url))),
    ))
  let huge = photo_ref("fid-4", Some(dl.cap_for(ref.Photo) + 1))
  intake.run(binding, huge, fn() { Ok(token) }, 1000)
  |> should.equal(intake.DownloadRefused("download_rejected:declared_over_cap"))
  store.usage(policy(root)) |> should.equal(Ok(0))
  fixture_stop(pid)
}

pub fn unknown_file_id_is_a_denied_download_test() {
  let assert Ok(#(pid, _port, base_url)) = fixture_start()
  let root = fresh_root()
  let binding =
    Some(intake.Binding(
      policy(root),
      Some(transport.from_http(config(base_url))),
    ))
  let out =
    intake.run(
      binding,
      photo_ref("fid-missing", None),
      fn() { Ok(token) },
      1000,
    )
  let assert intake.DownloadRefused(label) = out
  string.starts_with(label, "download_rejected:") |> should.be_true
  intake.status(out) |> should.equal("denied")
  fixture_stop(pid)
}

pub fn transport_bound_is_the_ffi_ceiling_test() {
  transport.max_body_bytes |> should.equal(10_485_760)
  http_client.max_file_body_bytes |> should.equal(10_485_760)
}

pub fn get_file_refuses_a_hostile_declared_path_test() {
  let assert Ok(#(pid, _port, base_url)) = fixture_start()
  fixture_set_file(pid, "fid-5", "../../etc/passwd", png)
  http_client.get_file(config(base_url), "fid-5", 3000)
  |> should.equal(Error("get_file_invalid_file_path"))
  fixture_set_file(pid, "fid-6", "/abs/path.png", png)
  http_client.get_file(config(base_url), "fid-6", 3000)
  |> should.equal(Error("get_file_invalid_file_path"))
  fixture_stop(pid)
}

// ---------------------------------------------------------------- wave 6j ranges

fn big_png(total: Int) -> BitArray {
  // PNG signature followed by a deterministic filler, so inspection accepts it
  let header = <<0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A>>
  let filler = string.repeat("u", total - 8) |> bit_array.from_string
  bit_array.append(header, filler)
}

fn big_pdf(total: Int) -> BitArray {
  let header = <<0x25, 0x50, 0x44, 0x46, 0x2D>>
  let filler = string.repeat("d", total - 5) |> bit_array.from_string
  bit_array.append(header, filler)
}

pub fn content_range_parser_laws_test() {
  http_client.parse_content_range([
    #("Content-Range", "bytes 0-4194303/12582912"),
  ])
  |> should.equal(Ok(#(0, 4_194_303, Some(12_582_912))))
  http_client.parse_content_range([#("content-range", "bytes 10-19/*")])
  |> should.equal(Ok(#(10, 19, None)))
  http_client.parse_content_range([#("content-range", "bytes 20-19/100")])
  |> should.equal(Error("fetch_file_invalid_content_range"))
  http_client.parse_content_range([#("content-range", "bytes 0-99/50")])
  |> should.equal(Error("fetch_file_invalid_content_range"))
  http_client.parse_content_range([#("x", "y")])
  |> should.equal(Error("fetch_file_missing_content_range"))
}

pub fn ranged_fetch_yields_exact_chunks_and_a_last_flag_test() {
  let assert Ok(#(pid, _port, base_url)) = fixture_start()
  let body = big_pdf(10_000)
  fixture_set_file(pid, "fid-r1", "docs/r1.pdf", body)
  let assert Ok(http_client.RangeChunk(
    bytes: c1,
    total: Some(10_000),
    last: False,
  )) =
    http_client.fetch_file_range(config(base_url), "docs/r1.pdf", 0, 4096, 3000)
  bit_array.byte_size(c1) |> should.equal(4096)
  let assert Ok(http_client.RangeChunk(
    bytes: c2,
    total: Some(10_000),
    last: False,
  )) =
    http_client.fetch_file_range(
      config(base_url),
      "docs/r1.pdf",
      4096,
      4096,
      3000,
    )
  bit_array.byte_size(c2) |> should.equal(4096)
  let assert Ok(http_client.RangeChunk(
    bytes: c3,
    total: Some(10_000),
    last: True,
  )) =
    http_client.fetch_file_range(
      config(base_url),
      "docs/r1.pdf",
      8192,
      4096,
      3000,
    )
  bit_array.byte_size(c3) |> should.equal(1808)
  bit_array.concat([c1, c2, c3]) |> should.equal(body)
  // past the end: a satisfiable-range failure at a non-zero offset is the end
  let assert Ok(http_client.RangeChunk(bytes: <<>>, last: True, ..)) =
    http_client.fetch_file_range(
      config(base_url),
      "docs/r1.pdf",
      10_000,
      4096,
      3000,
    )
  fixture_stop(pid)
}

pub fn twelve_mib_document_streams_through_the_transport_and_is_stored_test() {
  let assert Ok(#(pid, _port, base_url)) = fixture_start()
  let total = 12 * 1_048_576
  let body = big_pdf(total)
  fixture_set_file(pid, "fid-big-doc", "docs/big.pdf", body)
  let root = fresh_root()
  let big_policy =
    store.Policy(..policy(root), total_ceiling_bytes: 64 * 1_048_576)
  let binding =
    Some(intake.Binding(big_policy, Some(transport.from_http(config(base_url)))))
  let document =
    ref.MediaRef(..photo_ref("fid-big-doc", Some(total)), kind: ref.Document)
  let out = intake.run(binding, document, fn() { Ok(token) }, 5000)
  let assert intake.Stored(sha, bytes, sniffed, True, _) = out
  bytes |> should.equal(total)
  sha |> should.equal(sha256_hex(body))
  sniffed |> should.equal(inspect.Pdf)
  let assert Ok(#(stored, _content)) = store.get(big_policy, sha, 6000)
  stored.bytes |> should.equal(total)
  fixture_stop(pid)
}

pub fn twelve_mib_photo_is_aborted_at_the_photo_cap_across_chunks_test() {
  let assert Ok(#(pid, _port, base_url)) = fixture_start()
  let total = 12 * 1_048_576
  // the fixture omits file_size, so the cap is enforced only while streaming
  fixture_set_file_opts(
    pid,
    "fid-big-photo",
    "photos/big.png",
    big_png(total),
    False,
  )
  let root = fresh_root()
  let binding =
    Some(intake.Binding(
      policy(root),
      Some(transport.from_http(config(base_url))),
    ))
  // declared size unknown, so the cap is enforced while streaming
  let out =
    intake.run(
      binding,
      photo_ref("fid-big-photo", None),
      fn() { Ok(token) },
      5000,
    )
  out |> should.equal(intake.DownloadRefused("download_aborted"))
  store.usage(policy(root)) |> should.equal(Ok(0))
  fixture_stop(pid)
}

pub fn chunk_size_is_inside_the_ffi_ceiling_test() {
  { transport.chunk_bytes <= http_client.max_file_body_bytes } |> should.be_true
  transport.chunk_bytes |> should.equal(4_194_304)
}

pub fn oversized_chunk_request_is_clamped_to_the_ceiling_test() {
  // a caller asking for more than the FFI ceiling per range is clamped, not
  // refused by the FFI policy: the request still succeeds within the ceiling
  let assert Ok(#(pid, _port, base_url)) = fixture_start()
  fixture_set_file(pid, "fid-clamp", "docs/clamp.pdf", big_pdf(5000))
  let assert Ok(http_client.RangeChunk(
    bytes: bytes,
    total: Some(5000),
    last: True,
  )) =
    http_client.fetch_file_range(
      config(base_url),
      "docs/clamp.pdf",
      0,
      64 * 1_048_576,
      3000,
    )
  bit_array.byte_size(bytes) |> should.equal(5000)
  fixture_stop(pid)
}
