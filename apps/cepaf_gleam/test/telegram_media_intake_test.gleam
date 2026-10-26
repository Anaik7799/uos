//// Wave 6h: the media intake chain and its typed reply. Real store roots under
//// scratch, a queued fake transport in the style of the download suite, and
//// the journey status vocabulary asserted on every path.

import cepaf_gleam/harness/telegram_ingress_guard as guard
import cepaf_gleam/harness/telegram_media_download as dl
import cepaf_gleam/harness/telegram_media_inspect as inspect
import cepaf_gleam/harness/telegram_media_intake as intake
import cepaf_gleam/harness/telegram_media_ref as ref
import cepaf_gleam/harness/telegram_media_store as store
import gleam/bit_array
import gleam/dynamic/decode
import gleam/erlang/process
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import simplifile

const png = <<0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3, 4>>

const pdf = <<0x25, 0x50, 0x44, 0x46, 0x2D, 1, 2, 3>>

fn photo_ref(uid: String) -> ref.MediaRef {
  ref.MediaRef(
    kind: ref.Photo,
    file_unique_id: uid,
    file_id: "file-" <> uid,
    declared_size_bytes: Some(12),
    declared_mime: Some("image/png"),
    declared_duration_s: None,
    caption: Some("/status"),
  )
}

fn transport(chunks: List(BitArray)) -> dl.Transport {
  let queue = process.new_subject()
  list.each(chunks, fn(c) { process.send(queue, c) })
  dl.Transport(
    get_file: fn(_fid, _deadline) {
      Ok(dl.FileMeta(file_path: "photos/x.png", declared_size_bytes: None))
    },
    open_stream: fn(_url, _deadline) {
      Ok(fn() {
        case process.receive(queue, 0) {
          Ok(c) -> Ok(Some(c))
          Error(_) -> Ok(None)
        }
      })
    },
  )
}

const scratch_base = "/tmp/uos-tg-media-intake-test"

fn fresh_root() -> String {
  let root =
    scratch_base
    <> "/intake-"
    <> int.to_string(process_now())
    <> "-"
    <> int.to_string(int.random(1_000_000))
  let _ = simplifile.create_directory_all(root <> "/objects")
  root
}

@external(erlang, "erlang", "monotonic_time")
fn process_now() -> Int

fn policy(root: String) -> store.Policy {
  store.Policy(
    root: root,
    base: "objects",
    retention_ms: 60_000,
    total_ceiling_bytes: 1_048_576,
  )
}

fn token() -> Result(String, String) {
  Ok("FAKE-TOKEN")
}

fn field(reply: String, key: String) -> String {
  case
    json.parse(reply, {
      use v <- decode.field(key, decode.string)
      decode.success(v)
    })
  {
    Ok(v) -> v
    Error(_) -> "MISSING"
  }
}

pub fn not_configured_is_backend_unavailable_test() {
  let out = intake.run(None, photo_ref("u1"), token, 1000)
  out |> should.equal(intake.NotConfigured)
  let reply =
    intake.reply_json(out, photo_ref("u1"), "query_system_health", "tg-1")
  field(reply, "status") |> should.equal("backend_unavailable")
  field(reply, "reason") |> should.equal("media_not_configured")
  field(reply, "caption_directive") |> should.equal("query_system_health")
  field(reply, "declared_kind") |> should.equal("photo")
  field(reply, "runtime_admission") |> should.equal("NOT_GRANTED")
  string.contains(reply, "FAKE-TOKEN") |> should.be_false
}

pub fn transport_absent_is_backend_unavailable_and_fetches_nothing_test() {
  let root = fresh_root()
  let binding = Some(intake.Binding(policy(root), None))
  let out = intake.run(binding, photo_ref("u2"), token, 1000)
  out |> should.equal(intake.TransportNotConfigured)
  intake.status(out) |> should.equal("backend_unavailable")
  store.usage(policy(root)) |> should.equal(Ok(0))
}

pub fn png_photo_is_fetched_inspected_and_stored_test() {
  let root = fresh_root()
  let binding = Some(intake.Binding(policy(root), Some(transport([png]))))
  let out = intake.run(binding, photo_ref("u3"), token, 5000)
  let assert intake.Stored(sha, bytes, sniffed, written, expires) = out
  bytes |> should.equal(bit_array.byte_size(png))
  sniffed |> should.equal(inspect.Png)
  written |> should.be_true
  expires |> should.equal(65_000)
  string.length(sha) |> should.equal(64)
  let reply =
    intake.reply_json(out, photo_ref("u3"), "query_system_health", "tg-3")
  field(reply, "status") |> should.equal("ok")
  field(reply, "sniffed") |> should.equal("png")
  field(reply, "sha256") |> should.equal(sha)
  // the bytes are retrievable under the digest the reply names
  let assert Ok(#(stored, content)) = store.get(policy(root), sha, 6000)
  content |> should.equal(png)
  stored.file_unique_id |> should.equal("u3")
  // a second intake of the same bytes is already stored, not written twice
  let binding2 = Some(intake.Binding(policy(root), Some(transport([png]))))
  let assert intake.Stored(_, _, _, written2, _) =
    intake.run(binding2, photo_ref("u3"), token, 7000)
  written2 |> should.be_false
}

pub fn pdf_bytes_under_a_photo_kind_are_denied_and_not_stored_test() {
  let root = fresh_root()
  let binding = Some(intake.Binding(policy(root), Some(transport([pdf]))))
  let out = intake.run(binding, photo_ref("u4"), token, 1000)
  out
  |> should.equal(intake.InspectionRejected(
    "sniffed_type_not_allowed_for_kind",
    inspect.Pdf,
  ))
  intake.status(out) |> should.equal("denied")
  store.usage(policy(root)) |> should.equal(Ok(0))
  let reply =
    intake.reply_json(out, photo_ref("u4"), "query_system_health", "tg-4")
  field(reply, "sniffed") |> should.equal("pdf")
}

pub fn unknown_bytes_are_denied_test() {
  let root = fresh_root()
  let binding =
    Some(intake.Binding(
      policy(root),
      Some(transport([bit_array.from_string("just text")])),
    ))
  let out = intake.run(binding, photo_ref("u5"), token, 1000)
  let assert intake.InspectionRejected("unknown_content_type", inspect.Unknown) =
    out
  intake.status(out) |> should.equal("denied")
}

pub fn unsupported_kind_is_denied_before_any_fetch_test() {
  let root = fresh_root()
  let binding = Some(intake.Binding(policy(root), Some(transport([png]))))
  let poll =
    ref.MediaRef(
      ..photo_ref("u6"),
      kind: ref.Unsupported("poll"),
      caption: None,
    )
  let out = intake.run(binding, poll, token, 1000)
  out
  |> should.equal(intake.DownloadRefused("download_rejected:unsupported_kind"))
  intake.status(out) |> should.equal("denied")
  store.usage(policy(root)) |> should.equal(Ok(0))
}

pub fn store_refusal_is_denied_test() {
  let root = fresh_root()
  // ceiling of 1 byte: the put is refused before any write
  let tiny = store.Policy(..policy(root), total_ceiling_bytes: 1)
  let binding = Some(intake.Binding(tiny, Some(transport([png]))))
  let out = intake.run(binding, photo_ref("u7"), token, 1000)
  out |> should.equal(intake.StoreRefused("ceiling_reached"))
  intake.status(out) |> should.equal("denied")
  store.usage(tiny) |> should.equal(Ok(0))
}

pub fn directive_labels_cover_every_classification_test() {
  intake.directive_label(guard.DirectReadTool("query_x"))
  |> should.equal("query_x")
  intake.directive_label(guard.PreservedDirective("/verify", ["a"]))
  |> should.equal("/verify")
  intake.directive_label(guard.DeniedMutation("tool", "why"))
  |> should.equal("tool")
  intake.directive_label(guard.UnknownDirective("/nope"))
  |> should.equal("/nope")
}

pub fn refusal_reply_is_denied_and_names_the_reason_test() {
  let reply = intake.refusal_reply("invalid_input_media", "tg-9")
  field(reply, "status") |> should.equal("denied")
  field(reply, "reason") |> should.equal("invalid_input_media")
  field(reply, "request_id") |> should.equal("tg-9")
}

pub fn summary_never_carries_the_token_test() {
  let root = fresh_root()
  let binding = Some(intake.Binding(policy(root), Some(transport([png]))))
  let out = intake.run(binding, photo_ref("u8"), token, 1000)
  let s = intake.summary(out)
  string.starts_with(s, "stored ") |> should.be_true
  string.contains(s, "FAKE-TOKEN") |> should.be_false
  string.contains(s, "file-u8") |> should.be_false
}
