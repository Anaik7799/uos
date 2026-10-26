//// Media design T1: typed MediaRef, total parsing, declared-only fields.

import cepaf_gleam/harness/telegram_media_ref as ref
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should

fn wrap(message_fields: String) -> String {
  "{\"update_id\":7,\"message\":{\"message_id\":3,\"date\":1,\"chat\":{\"id\":5,\"type\":\"private\"},\"from\":{\"id\":9,\"is_bot\":false}"
  <> message_fields
  <> "}}"
}

fn must(update: String) -> ref.MediaRef {
  case ref.from_update(update) {
    Ok(Some(r)) -> r
    other -> {
      should.equal(other, Ok(None))
      panic as "expected media"
    }
  }
}

pub fn photo_parses_and_picks_largest_declared_size_test() {
  let r =
    must(wrap(
      ",\"photo\":[{\"file_id\":\"s\",\"file_unique_id\":\"us\",\"file_size\":100,\"width\":10,\"height\":10},{\"file_id\":\"l\",\"file_unique_id\":\"ul\",\"file_size\":9000,\"width\":99,\"height\":99},{\"file_id\":\"m\",\"file_unique_id\":\"um\",\"file_size\":500,\"width\":50,\"height\":50}]",
    ))
  r.kind |> should.equal(ref.Photo)
  r.file_unique_id |> should.equal("ul")
  r.file_id |> should.equal("l")
  r.declared_size_bytes |> should.equal(Some(9000))
  r.declared_mime |> should.equal(None)
  string.contains(ref.describe(r), "\"declared_size_bytes\":9000")
  |> should.be_true
  string.contains(ref.describe(r), "\"confidence\":\"declared\"")
  |> should.be_true
}

pub fn photo_without_sizes_takes_last_entry_test() {
  let r =
    must(wrap(
      ",\"photo\":[{\"file_id\":\"a\",\"file_unique_id\":\"ua\"},{\"file_id\":\"b\",\"file_unique_id\":\"ub\"}]",
    ))
  r.file_unique_id |> should.equal("ub")
  r.declared_size_bytes |> should.equal(None)
}

pub fn every_typed_kind_parses_test() {
  let one = fn(key, extra) {
    must(wrap(
      ",\""
      <> key
      <> "\":{\"file_id\":\"f\",\"file_unique_id\":\"u\""
      <> extra
      <> "}",
    ))
  }
  one("document", ",\"mime_type\":\"application/pdf\",\"file_size\":12").kind
  |> should.equal(ref.Document)
  one("audio", ",\"duration\":30").declared_duration_s
  |> should.equal(Some(30))
  one("voice", ",\"duration\":4").kind |> should.equal(ref.Voice)
  one("video", ",\"duration\":8").kind |> should.equal(ref.Video)
  one("sticker", "").kind |> should.equal(ref.Sticker)
  one("animation", "").kind |> should.equal(ref.Animation)
}

pub fn unknown_kind_is_unsupported_and_reported_test() {
  let r =
    must(wrap(",\"hologram\":{\"file_id\":\"f\",\"file_unique_id\":\"u\"}"))
  r.kind |> should.equal(ref.Unsupported("hologram"))
  ref.is_unsupported(r) |> should.be_true
  r.file_unique_id |> should.equal("u")
  string.contains(ref.describe(r), "\"declared_kind\":\"unsupported:hologram\"")
  |> should.be_true
}

pub fn unknown_kind_without_file_object_is_still_reported_test() {
  let r = must(wrap(",\"location\":{\"latitude\":1.5,\"longitude\":2.5}"))
  r.kind |> should.equal(ref.Unsupported("location"))
  r.file_unique_id |> should.equal("")
}

pub fn unknown_kinds_are_reported_deterministically_test() {
  let r = must(wrap(",\"zeta\":{},\"alpha\":{}"))
  r.kind |> should.equal(ref.Unsupported("alpha"))
}

pub fn text_only_update_has_no_media_test() {
  ref.from_update(wrap(",\"text\":\"/status\""))
  |> should.equal(Ok(None))
}

pub fn non_message_update_has_no_media_test() {
  ref.from_update("{\"update_id\":1,\"callback_query\":{\"id\":\"c\"}}")
  |> should.equal(Ok(None))
}

pub fn service_message_is_not_media_test() {
  ref.from_update(wrap(",\"new_chat_title\":\"x\""))
  |> should.equal(Ok(None))
}

pub fn no_caption_never_becomes_empty_command_test() {
  let r = must(wrap(",\"voice\":{\"file_id\":\"f\",\"file_unique_id\":\"u\"}"))
  r.caption |> should.equal(None)
  ref.caption_text(r) |> should.equal(None)
  let empty =
    must(wrap(
      ",\"voice\":{\"file_id\":\"f\",\"file_unique_id\":\"u\"},\"caption\":\"\"",
    ))
  ref.caption_text(empty) |> should.equal(None)
  let blank =
    must(wrap(
      ",\"voice\":{\"file_id\":\"f\",\"file_unique_id\":\"u\"},\"caption\":\"  \"",
    ))
  ref.caption_text(blank) |> should.equal(None)
  let full =
    must(wrap(
      ",\"voice\":{\"file_id\":\"f\",\"file_unique_id\":\"u\"},\"caption\":\"/status now\"",
    ))
  ref.caption_text(full) |> should.equal(Some("/status now"))
}

pub fn declared_mime_never_selects_anything_test() {
  let base = fn(mime) {
    must(wrap(
      ",\"document\":{\"file_id\":\"f\",\"file_unique_id\":\"u\",\"mime_type\":\""
      <> mime
      <> "\"}",
    ))
  }
  let a = base("application/pdf")
  let b = base("image/png")
  a.kind |> should.equal(b.kind)
  ref.kind_label(a.kind) |> should.equal(ref.kind_label(b.kind))
  a.declared_mime |> should.equal(Some("application/pdf"))
  b.declared_mime |> should.equal(Some("image/png"))
  // describe differs only in the declared_mime value
  let da = ref.describe(a)
  let db = ref.describe(b)
  string.replace(da, "application/pdf", "image/png") |> should.equal(db)
  string.contains(da, "\"declared_kind\":\"document\"") |> should.be_true
  // a mime that lies about the kind does not change it
  base("audio/ogg").kind |> should.equal(ref.Document)
}

pub fn describe_names_every_field_as_declared_test() {
  let r =
    must(wrap(
      ",\"audio\":{\"file_id\":\"f\",\"file_unique_id\":\"u\",\"file_size\":5,\"mime_type\":\"audio/mpeg\",\"duration\":3},\"caption\":\"hi\"",
    ))
  ref.describe(r)
  |> should.equal(
    "{\"declared_kind\":\"audio\",\"declared_file_unique_id\":\"u\",\"declared_file_id\":\"f\",\"declared_size_bytes\":5,\"declared_mime\":\"audio/mpeg\",\"declared_duration_s\":3,\"declared_caption\":\"hi\",\"confidence\":\"declared\"}",
  )
}

pub fn describe_nulls_missing_fields_and_is_bounded_test() {
  let r =
    must(wrap(",\"sticker\":{\"file_id\":\"f\",\"file_unique_id\":\"u\"}"))
  string.contains(ref.describe(r), "\"declared_size_bytes\":null")
  |> should.be_true
  let long = string.repeat("a", 256)
  let big =
    must(wrap(
      ",\"document\":{\"file_id\":\""
      <> long
      <> "\",\"file_unique_id\":\""
      <> long
      <> "\",\"mime_type\":\""
      <> long
      <> "\"},\"caption\":\""
      <> long
      <> "\"",
    ))
  { string.byte_size(ref.describe(big)) < 2048 } |> should.be_true
}

pub fn string_bounds_are_enforced_test() {
  let long = string.repeat("a", 257)
  let doc = fn(file_id, unique, mime) {
    ref.from_update(wrap(
      ",\"document\":{\"file_id\":\""
      <> file_id
      <> "\",\"file_unique_id\":\""
      <> unique
      <> "\",\"mime_type\":\""
      <> mime
      <> "\"}",
    ))
  }
  doc("f", "u", "ok") |> should.be_ok
  doc(long, "u", "ok") |> should.equal(Error("out_of_bounds_file_id"))
  doc("f", long, "ok") |> should.equal(Error("out_of_bounds_file_unique_id"))
  doc("f", "u", long) |> should.equal(Error("out_of_bounds_mime_type"))
  // Review M2-09 (wave 6p): the caption bound is Telegram's 1024 characters
  // with a 4096-byte ceiling, so a 257-byte caption is in bounds.
  let caption = fn(text) {
    ref.from_update(wrap(
      ",\"voice\":{\"file_id\":\"f\",\"file_unique_id\":\"u\"},\"caption\":\""
      <> text
      <> "\"",
    ))
  }
  caption(long) |> should.be_ok
  caption(string.repeat("k", ref.max_caption_chars)) |> should.be_ok
  caption(string.repeat("k", ref.max_caption_chars + 1))
  |> should.equal(Error("out_of_bounds_caption"))
  caption(string.repeat("€", 1024)) |> should.be_ok
  caption(string.repeat("€", 1366))
  |> should.equal(Error("out_of_bounds_caption"))
  ref.from_update(wrap(
    ",\"voice\":{\"file_id\":\"f\",\"file_unique_id\":\"u\"},\"caption\":\"a\\u0000b\"",
  ))
  |> should.equal(Error("out_of_bounds_caption"))
  ref.from_update(wrap(
    ",\""
    <> string.repeat("k", 257)
    <> "\":{\"file_id\":\"f\",\"file_unique_id\":\"u\"}",
  ))
  |> should.equal(Error("out_of_bounds_raw_media_key"))
}

pub fn numeric_bounds_are_enforced_test() {
  let with = fn(extra) {
    ref.from_update(wrap(
      ",\"video\":{\"file_id\":\"f\",\"file_unique_id\":\"u\"" <> extra <> "}",
    ))
  }
  with(",\"file_size\":0") |> should.be_ok
  with(",\"file_size\":-1") |> should.equal(Error("out_of_bounds_file_size"))
  with(",\"duration\":-5") |> should.equal(Error("out_of_bounds_duration"))
}

pub fn malformed_input_is_an_error_not_a_panic_test() {
  ref.from_update("not json") |> should.equal(Error("malformed_update"))
  ref.from_update("{\"message\":5}") |> should.equal(Error("malformed_update"))
  ref.from_update(wrap(",\"photo\":[]"))
  |> should.equal(Error("malformed_photo"))
  ref.from_update(wrap(",\"photo\":{}"))
  |> should.equal(Error("malformed_photo"))
  ref.from_update(wrap(",\"voice\":{\"file_id\":\"f\"}"))
  |> should.equal(Error("malformed_voice"))
  ref.from_update(wrap(",\"voice\":{\"file_id\":\"\",\"file_unique_id\":\"u\"}"))
  |> should.equal(Error("missing_file_identity_voice"))
  ref.from_update(wrap(
    ",\"voice\":{\"file_id\":\"f\",\"file_unique_id\":\"u\",\"duration\":\"x\"}",
  ))
  |> should.equal(Error("malformed_voice"))
}

pub fn two_typed_kinds_are_ambiguous_test() {
  ref.from_update(wrap(
    ",\"voice\":{\"file_id\":\"f\",\"file_unique_id\":\"u\"},\"audio\":{\"file_id\":\"g\",\"file_unique_id\":\"v\"}",
  ))
  |> should.equal(Error("ambiguous_multiple_media_kinds"))
}

pub fn typed_kind_wins_over_unknown_extra_key_test() {
  must(wrap(
    ",\"voice\":{\"file_id\":\"f\",\"file_unique_id\":\"u\"},\"future_field\":{}",
  )).kind
  |> should.equal(ref.Voice)
}

pub fn kind_labels_are_distinct_test() {
  let labels =
    list.map(
      [
        ref.Photo,
        ref.Document,
        ref.Audio,
        ref.Voice,
        ref.Video,
        ref.Sticker,
        ref.Animation,
        ref.Unsupported("x"),
      ],
      ref.kind_label,
    )
  list.unique(labels) |> list.length |> should.equal(8)
}
