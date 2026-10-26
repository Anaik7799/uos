//// [C3I-SIL6-MSTS] <c3i-module><identity><module>cepaf_gleam/harness/telegram_media_ref</module></identity>
////   <fractal-topology><layer>L5_COGNITIVE</layer></fractal-topology>
////   <compliance><stamp-controls>SC-TELEGRAM-MEDIA-T1, SC-ERGONOMIC-001</stamp-controls></compliance>
//// </c3i-module>
////
//// Typed media descriptor for the Telegram inbound boundary (media design T1).
//// Every field is what the SENDER DECLARED. Nothing here is trusted, nothing
//// fetches bytes, and `declared_mime` is carried but never branched on.
//// Parsing is total: an unrecognised media key becomes `Unsupported(raw_key)`.

import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub type MediaKind {
  Photo
  Document
  Audio
  Voice
  Video
  Sticker
  Animation
  Unsupported(String)
}

pub type MediaRef {
  MediaRef(
    kind: MediaKind,
    file_unique_id: String,
    file_id: String,
    declared_size_bytes: Option(Int),
    declared_mime: Option(String),
    declared_duration_s: Option(Int),
    caption: Option(String),
  )
}

/// Maximum byte length of any declared string.
pub const max_string_bytes = 256

/// Recognised, typed media keys in fixed priority order.
const typed_keys = [
  #("photo", Photo),
  #("document", Document),
  #("audio", Audio),
  #("voice", Voice),
  #("video", Video),
  #("sticker", Sticker),
  #("animation", Animation),
]

/// Message keys that are known NOT to be an attachment (metadata, text, service
/// events). Any other key is reported as `Unsupported(key)`.
const non_media_keys = [
  "message_id", "message_thread_id", "from", "sender_chat", "sender_boost_count",
  "sender_business_bot", "business_connection_id", "date", "chat",
  "forward_origin", "forward_from", "forward_from_chat",
  "forward_from_message_id", "forward_signature", "forward_sender_name",
  "forward_date", "is_topic_message", "is_automatic_forward", "reply_to_message",
  "external_reply", "quote", "reply_to_story", "via_bot", "edit_date",
  "has_protected_content", "is_from_offline", "media_group_id",
  "author_signature", "text", "entities", "link_preview_options", "effect_id",
  "caption", "caption_entities", "show_caption_above_media", "has_media_spoiler",
  "reply_markup", "new_chat_members", "left_chat_member", "new_chat_title",
  "new_chat_photo", "delete_chat_photo", "group_chat_created",
  "supergroup_chat_created", "channel_chat_created", "pinned_message",
  "migrate_to_chat_id", "migrate_from_chat_id",
  "message_auto_delete_timer_changed", "forum_topic_created",
  "forum_topic_edited", "forum_topic_closed", "forum_topic_reopened",
  "general_forum_topic_hidden", "general_forum_topic_unhidden",
  "write_access_allowed", "boost_added", "chat_background_set",
  "video_chat_scheduled", "video_chat_started", "video_chat_ended",
  "video_chat_participants_invited",
]

/// Decode the media descriptor of an inbound update. `Ok(None)` when the update
/// carries no media (including non-message updates). `Error` for malformed JSON,
/// a malformed declared field, an out-of-bound value, or ambiguous media.
pub fn from_update(update_json: String) -> Result(Option(MediaRef), String) {
  case json.parse(update_json, update_decoder()) {
    Error(_) -> Error("malformed_update")
    Ok(None) -> Ok(None)
    Ok(Some(message)) -> from_message(message)
  }
}

fn update_decoder() -> decode.Decoder(Option(Dict(String, Dynamic))) {
  use message <- decode.optional_field(
    "message",
    None,
    decode.optional(decode.dict(decode.string, decode.dynamic)),
  )
  decode.success(message)
}

fn from_message(
  message: Dict(String, Dynamic),
) -> Result(Option(MediaRef), String) {
  use caption <- result.try(caption_of(message))
  let present =
    list.filter_map(typed_keys, fn(entry) {
      dict.get(message, entry.0)
      |> result.map(fn(raw) { #(entry.0, entry.1, raw) })
    })
  case present {
    [#(key, kind, raw)] -> {
      use ref <- result.try(typed_ref(kind, key, raw, caption))
      Ok(Some(ref))
    }
    [_, _, ..] -> Error("ambiguous_multiple_media_kinds")
    [] ->
      case unknown_entries(message) {
        [] -> Ok(None)
        [#(raw_key, raw), ..] -> {
          use ref <- result.try(unsupported_ref(raw_key, raw, caption))
          Ok(Some(ref))
        }
      }
  }
}

/// Keys that are neither typed media nor known non-media, in sorted order so the
/// reported raw key is deterministic.
fn unknown_entries(message: Dict(String, Dynamic)) -> List(#(String, Dynamic)) {
  dict.to_list(message)
  |> list.filter(fn(entry) { !list.contains(non_media_keys, entry.0) })
  |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
}

fn caption_of(
  message: Dict(String, Dynamic),
) -> Result(Option(String), String) {
  case dict.get(message, "caption") {
    Error(_) -> Ok(None)
    Ok(raw) ->
      case decode.run(raw, decode.optional(decode.string)) {
        Error(_) -> Error("malformed_caption")
        Ok(None) -> Ok(None)
        Ok(Some(c)) -> bounded_string("caption", c) |> result.map(Some)
      }
  }
}

type RawFile {
  RawFile(
    file_id: String,
    file_unique_id: String,
    size: Option(Int),
    mime: Option(String),
    duration: Option(Int),
  )
}

fn file_decoder() -> decode.Decoder(RawFile) {
  use file_id <- decode.field("file_id", decode.string)
  use unique <- decode.field("file_unique_id", decode.string)
  use size <- decode.optional_field(
    "file_size",
    None,
    decode.optional(decode.int),
  )
  use mime <- decode.optional_field(
    "mime_type",
    None,
    decode.optional(decode.string),
  )
  use duration <- decode.optional_field(
    "duration",
    None,
    decode.optional(decode.int),
  )
  decode.success(RawFile(file_id, unique, size, mime, duration))
}

fn typed_ref(
  kind: MediaKind,
  key: String,
  raw: Dynamic,
  caption: Option(String),
) -> Result(MediaRef, String) {
  let decoded = case kind {
    Photo ->
      case decode.run(raw, decode.list(file_decoder())) {
        Ok(sizes) -> largest_declared(sizes)
        Error(_) -> Error(Nil)
      }
    _ -> decode.run(raw, file_decoder()) |> result.replace_error(Nil)
  }
  case decoded {
    Error(_) -> Error("malformed_" <> key)
    Ok(file) -> {
      use ref <- result.try(build(kind, file, caption))
      case ref.file_id == "" || ref.file_unique_id == "" {
        True -> Error("missing_file_identity_" <> key)
        False -> Ok(ref)
      }
    }
  }
}

/// Telegram lists photo sizes ascending; pick the largest DECLARED file_size,
/// preferring the later entry on ties or when sizes are undeclared.
fn largest_declared(sizes: List(RawFile)) -> Result(RawFile, Nil) {
  case sizes {
    [] -> Error(Nil)
    [first, ..rest] ->
      Ok(
        list.fold(rest, first, fn(best, next) {
          case size_key(next) >= size_key(best) {
            True -> next
            False -> best
          }
        }),
      )
  }
}

fn size_key(file: RawFile) -> Int {
  option.unwrap(file.size, -1)
}

fn unsupported_ref(
  raw_key: String,
  raw: Dynamic,
  caption: Option(String),
) -> Result(MediaRef, String) {
  use key <- result.try(bounded_string("raw_media_key", raw_key))
  let file = case decode.run(raw, file_decoder()) {
    Ok(f) -> f
    Error(_) -> RawFile("", "", None, None, None)
  }
  build(Unsupported(key), file, caption)
}

fn build(
  kind: MediaKind,
  file: RawFile,
  caption: Option(String),
) -> Result(MediaRef, String) {
  use file_id <- result.try(bounded_string("file_id", file.file_id))
  use unique <- result.try(bounded_string("file_unique_id", file.file_unique_id))
  use mime <- result.try(bounded_option("mime_type", file.mime))
  use size <- result.try(non_negative("file_size", file.size))
  use duration <- result.try(non_negative("duration", file.duration))
  Ok(MediaRef(kind, unique, file_id, size, mime, duration, caption))
}

fn bounded_string(field: String, value: String) -> Result(String, String) {
  case
    string.byte_size(value) > max_string_bytes
    || string.contains(value, "\u{0}")
  {
    True -> Error("out_of_bounds_" <> field)
    False -> Ok(value)
  }
}

fn bounded_option(
  field: String,
  value: Option(String),
) -> Result(Option(String), String) {
  case value {
    None -> Ok(None)
    Some(v) -> bounded_string(field, v) |> result.map(Some)
  }
}

fn non_negative(
  field: String,
  value: Option(Int),
) -> Result(Option(Int), String) {
  case value {
    Some(n) if n < 0 -> Error("out_of_bounds_" <> field)
    _ -> Ok(value)
  }
}

/// The caption as command text. A missing, empty or whitespace-only caption is
/// None, never "": a captionless media update must not become an empty command.
pub fn caption_text(ref: MediaRef) -> Option(String) {
  case ref.caption {
    Some(c) ->
      case string.trim(c) {
        "" -> None
        _ -> Some(c)
      }
    None -> None
  }
}

/// Lower-case label of the DECLARED kind (never derived from declared_mime).
pub fn kind_label(kind: MediaKind) -> String {
  case kind {
    Photo -> "photo"
    Document -> "document"
    Audio -> "audio"
    Voice -> "voice"
    Video -> "video"
    Sticker -> "sticker"
    Animation -> "animation"
    Unsupported(raw) -> "unsupported:" <> raw
  }
}

/// Bounded JSON naming every field as declared_*; confidence is always "declared".
pub fn describe(ref: MediaRef) -> String {
  json.object([
    #("declared_kind", json.string(kind_label(ref.kind))),
    #("declared_file_unique_id", json.string(ref.file_unique_id)),
    #("declared_file_id", json.string(ref.file_id)),
    #("declared_size_bytes", json.nullable(ref.declared_size_bytes, json.int)),
    #("declared_mime", json.nullable(ref.declared_mime, json.string)),
    #("declared_duration_s", json.nullable(ref.declared_duration_s, json.int)),
    #("declared_caption", json.nullable(ref.caption, json.string)),
    #("confidence", json.string("declared")),
  ])
  |> json.to_string
}

/// True for an `Unsupported` kind; callers must report these, not drop them.
pub fn is_unsupported(ref: MediaRef) -> Bool {
  case ref.kind {
    Unsupported(_) -> True
    _ -> False
  }
}
