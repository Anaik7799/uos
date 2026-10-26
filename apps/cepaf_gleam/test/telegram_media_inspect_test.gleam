//// Media design T3: bounded content inspection by magic bytes.
//// Laws: each signature maps to its type, a short signature is Unknown, bytes
//// past the bound never matter, nothing claims to analyse content, the
//// allowlist table is exact, and declared_mime is never consulted.

import cepaf_gleam/harness/telegram_media_download as dl
import cepaf_gleam/harness/telegram_media_inspect as insp
import cepaf_gleam/harness/telegram_media_ref as ref
import gleam/bit_array
import gleam/list
import gleam/option.{None, Some}
import gleeunit/should

const jpeg = <<0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3>>

const png = <<0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 9, 9>>

const gif = <<0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 1, 2>>

const webp = <<
  0x52, 0x49, 0x46, 0x46, 0xAA, 0xBB, 0xCC, 0xDD, 0x57, 0x45, 0x42, 0x50, 7,
>>

const ogg = <<0x4F, 0x67, 0x67, 0x53, 0, 2>>

const mp3_id3 = <<0x49, 0x44, 0x33, 4, 0>>

const mp4 = <<0, 0, 0, 0x20, 0x66, 0x74, 0x79, 0x70, 0x69, 0x73, 0x6F, 0x6D>>

const pdf = <<0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x37>>

const zip = <<0x50, 0x4B, 0x03, 0x04, 0, 0>>

fn all_kinds() -> List(ref.MediaKind) {
  [
    ref.Photo,
    ref.Document,
    ref.Audio,
    ref.Voice,
    ref.Video,
    ref.Sticker,
    ref.Animation,
    ref.Unsupported("poll"),
  ]
}

pub fn signatures_map_to_types_test() {
  insp.sniff(jpeg) |> should.equal(insp.Jpeg)
  insp.sniff(png) |> should.equal(insp.Png)
  insp.sniff(gif) |> should.equal(insp.Gif)
  insp.sniff(webp) |> should.equal(insp.Webp)
  insp.sniff(ogg) |> should.equal(insp.Ogg)
  insp.sniff(mp3_id3) |> should.equal(insp.Mp3)
  insp.sniff(<<0xFF, 0xFB, 0x90>>) |> should.equal(insp.Mp3)
  insp.sniff(<<0xFF, 0xF3, 0x90>>) |> should.equal(insp.Mp3)
  insp.sniff(<<0xFF, 0xF2, 0x90>>) |> should.equal(insp.Mp3)
  insp.sniff(mp4) |> should.equal(insp.Mp4)
  insp.sniff(pdf) |> should.equal(insp.Pdf)
  insp.sniff(zip) |> should.equal(insp.Zip)
}

pub fn webp_ignores_riff_length_field_test() {
  insp.sniff(<<0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x45, 0x42, 0x50>>)
  |> should.equal(insp.Webp)
  // RIFF container that is not WEBP (e.g. WAVE) is not recognised.
  insp.sniff(<<0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x41, 0x56, 0x45>>)
  |> should.equal(insp.Unknown)
}

pub fn one_byte_short_signature_is_unknown_test() {
  insp.sniff(<<0xFF, 0xD8>>) |> should.equal(insp.Unknown)
  insp.sniff(<<0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A>>)
  |> should.equal(insp.Unknown)
  insp.sniff(<<0x47, 0x49, 0x46>>) |> should.equal(insp.Unknown)
  insp.sniff(<<0x52, 0x49, 0x46, 0x46, 1, 2, 3, 4, 0x57, 0x45, 0x42>>)
  |> should.equal(insp.Unknown)
  insp.sniff(<<0x4F, 0x67, 0x67>>) |> should.equal(insp.Unknown)
  insp.sniff(<<0x49, 0x44>>) |> should.equal(insp.Unknown)
  insp.sniff(<<0xFF>>) |> should.equal(insp.Unknown)
  insp.sniff(<<0, 0, 0, 0, 0x66, 0x74, 0x79>>) |> should.equal(insp.Unknown)
  insp.sniff(<<0x25, 0x50, 0x44, 0x46>>) |> should.equal(insp.Unknown)
  insp.sniff(<<0x50, 0x4B, 0x03>>) |> should.equal(insp.Unknown)
  insp.sniff(<<>>) |> should.equal(insp.Unknown)
}

pub fn prefix_is_bounded_test() {
  let long = bit_array.concat([png, <<0:size(8000)>>])
  insp.prefix_bytes |> should.equal(64)
  bit_array.byte_size(insp.examined_prefix(long)) |> should.equal(64)
  bit_array.byte_size(insp.examined_prefix(<<1, 2, 3>>)) |> should.equal(3)
}

pub fn bytes_beyond_prefix_never_change_result_test() {
  let head = bit_array.concat([jpeg, <<0:size(456)>>])
  // head is exactly 64 bytes long.
  bit_array.byte_size(head) |> should.equal(64)
  let a = bit_array.concat([head, <<1, 2, 3>>])
  let b =
    bit_array.concat([head, <<0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A>>])
  insp.sniff(a) |> should.equal(insp.sniff(b))
  insp.examined_prefix(a) |> should.equal(insp.examined_prefix(b))
  // A signature that only appears after the bound is never seen.
  let late = bit_array.concat([<<0:size(512)>>, pdf])
  insp.sniff(late) |> should.equal(insp.Unknown)
}

pub fn unrelated_contents_are_unknown_and_rejected_test() {
  let a = <<"hello world, plain text":utf8>>
  let b = <<0, 1, 2, 3, 4, 5, 6, 7, 8, 9>>
  a |> should.not_equal(b)
  insp.sniff(a) |> should.equal(insp.Unknown)
  insp.sniff(b) |> should.equal(insp.Unknown)
  list.each(all_kinds(), fn(kind) {
    case insp.inspect(kind, a), insp.inspect(kind, b) {
      insp.Rejected(_, insp.Unknown), insp.Rejected(_, insp.Unknown) -> Nil
      _, _ -> should.fail()
    }
  })
}

pub fn allowlist_table_is_exact_test() {
  insp.allowlist(ref.Photo) |> should.equal([insp.Jpeg, insp.Png, insp.Webp])
  insp.allowlist(ref.Sticker) |> should.equal([insp.Webp, insp.Png])
  insp.allowlist(ref.Voice) |> should.equal([insp.Ogg])
  insp.allowlist(ref.Audio) |> should.equal([insp.Mp3, insp.Ogg])
  insp.allowlist(ref.Video) |> should.equal([insp.Mp4])
  insp.allowlist(ref.Animation) |> should.equal([insp.Mp4])
  insp.allowlist(ref.Document)
  |> should.equal([insp.Pdf, insp.Png, insp.Jpeg, insp.Zip])
  insp.allowlist(ref.Unsupported("poll")) |> should.equal([])
}

pub fn gif_accepted_for_no_kind_test() {
  list.each(all_kinds(), fn(kind) {
    list.contains(insp.allowlist(kind), insp.Gif) |> should.equal(False)
    insp.inspect(kind, gif)
    |> should.not_equal(insp.Accepted(insp.Gif))
  })
  insp.inspect(ref.Photo, gif)
  |> should.equal(insp.Rejected("sniffed_type_not_allowed_for_kind", insp.Gif))
  insp.inspect(ref.Animation, gif)
  |> should.equal(insp.Rejected("sniffed_type_not_allowed_for_kind", insp.Gif))
}

pub fn zip_accepted_for_document_only_test() {
  insp.inspect(ref.Document, zip) |> should.equal(insp.Accepted(insp.Zip))
  list.each(all_kinds(), fn(kind) {
    case kind {
      ref.Document -> Nil
      _ ->
        case insp.inspect(kind, zip) {
          insp.Accepted(_) -> should.fail()
          insp.Rejected(_, insp.Zip) -> Nil
          insp.Rejected(_, _) -> should.fail()
        }
    }
  })
}

pub fn kind_content_verdicts_test() {
  insp.inspect(ref.Photo, png) |> should.equal(insp.Accepted(insp.Png))
  insp.inspect(ref.Photo, pdf)
  |> should.equal(insp.Rejected("sniffed_type_not_allowed_for_kind", insp.Pdf))
  insp.inspect(ref.Voice, mp4)
  |> should.equal(insp.Rejected("sniffed_type_not_allowed_for_kind", insp.Mp4))
  insp.inspect(ref.Voice, ogg) |> should.equal(insp.Accepted(insp.Ogg))
  insp.inspect(ref.Audio, mp3_id3) |> should.equal(insp.Accepted(insp.Mp3))
  insp.inspect(ref.Video, mp4) |> should.equal(insp.Accepted(insp.Mp4))
  insp.inspect(ref.Sticker, webp) |> should.equal(insp.Accepted(insp.Webp))
  insp.inspect(ref.Photo, <<1, 2, 3>>)
  |> should.equal(insp.Rejected("unknown_content_type", insp.Unknown))
  insp.inspect(ref.Unsupported("poll"), png)
  |> should.equal(insp.Rejected("unsupported_kind", insp.Png))
}

fn fetched(kind: ref.MediaKind, content: BitArray) -> dl.Outcome {
  dl.Fetched(
    kind: kind,
    file_unique_id: "u1",
    bytes: bit_array.byte_size(content),
    sha256_hex: "00",
    content: content,
  )
}

pub fn inspect_fetched_inspects_content_test() {
  insp.inspect_fetched(fetched(ref.Photo, png))
  |> should.equal(Ok(insp.Accepted(insp.Png)))
  insp.inspect_fetched(fetched(ref.Photo, pdf))
  |> should.equal(
    Ok(insp.Rejected("sniffed_type_not_allowed_for_kind", insp.Pdf)),
  )
}

pub fn inspect_fetched_never_accepts_non_fetched_test() {
  insp.inspect_fetched(dl.Aborted(observed_bytes: 100, cap_bytes: 50))
  |> should.equal(Error("download_aborted"))
  let rejections = [
    dl.UnsupportedKind("poll"),
    dl.AlreadyFetched("u1"),
    dl.DeclaredOverCap(2, 1),
    dl.TokenUnavailable("t"),
    dl.GetFileFailed("g"),
    dl.StreamOpenFailed("o"),
    dl.StreamReadFailed("r"),
  ]
  list.each(rejections, fn(r) {
    case insp.inspect_fetched(dl.Rejected(r)) {
      Error(msg) -> msg |> should.not_equal("")
      Ok(_) -> should.fail()
    }
  })
  insp.inspect_fetched(dl.Rejected(dl.DeclaredOverCap(2, 1)))
  |> should.equal(Error("download_rejected:declared_over_cap"))
}

pub fn declared_mime_is_never_consulted_test() {
  let lying = fn(mime) {
    ref.MediaRef(
      kind: ref.Photo,
      file_unique_id: "u1",
      file_id: "f1",
      declared_size_bytes: Some(10),
      declared_mime: mime,
      declared_duration_s: None,
      caption: None,
    )
  }
  let honest = lying(Some("image/png"))
  let liar = lying(Some("application/pdf"))
  let absent = lying(None)
  // inspect takes only kind and bytes: the same bytes give the same verdict
  // whatever the ref claims.
  let v1 = insp.inspect(honest.kind, pdf)
  let v2 = insp.inspect(liar.kind, pdf)
  let v3 = insp.inspect(absent.kind, pdf)
  v1 |> should.equal(v2)
  v2 |> should.equal(v3)
  v1
  |> should.equal(insp.Rejected("sniffed_type_not_allowed_for_kind", insp.Pdf))
  insp.inspect(liar.kind, png) |> should.equal(insp.Accepted(insp.Png))
}
