//// [C3I-SIL6-MSTS] MODULE CONTRACT
//// <c3i-module>
////   <identity><module>cepaf_gleam/gateway/matrix/codec</module></identity>
////   <fractal-topology><layer>L2_COMPONENT</layer></fractal-topology>
////   <compliance><stamp-controls>SC-MATRIX-004</stamp-controls></compliance>
//// </c3i-module>
////
//// Matrix JSON encode/decode — production-class codec for Client-Server API v1.18.

import cepaf_gleam/gateway/matrix/types
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

// -- Encoders ----------------------------------------------------------------

pub fn encode_login(username: String, password: String) -> String {
  json.object([
    #("type", json.string("m.login.password")),
    #(
      "identifier",
      json.object([
        #("type", json.string("m.id.user")),
        #("user", json.string(username)),
      ]),
    ),
    #("password", json.string(password)),
    #("initial_device_display_name", json.string("C3I Gleam Client")),
  ])
  |> json.to_string()
}

pub fn encode_message(msg: types.MessageContent) -> String {
  case msg {
    types.TextMessage(body, format, formatted) ->
      json.object(
        [#("msgtype", json.string("m.text")), #("body", json.string(body))]
        |> append_opt("format", format)
        |> append_opt("formatted_body", formatted),
      )
      |> json.to_string()
    types.NoticeMessage(body) ->
      json.object([
        #("msgtype", json.string("m.notice")),
        #("body", json.string(body)),
      ])
      |> json.to_string()
    types.ImageMessage(body, url, mime) ->
      json.object(
        [
          #("msgtype", json.string("m.image")),
          #("body", json.string(body)),
          #("url", json.string(url)),
        ]
        |> append_opt("mimetype", mime),
      )
      |> json.to_string()
    types.FileMessage(body, url, filename, mime) ->
      json.object(
        [
          #("msgtype", json.string("m.file")),
          #("body", json.string(body)),
          #("url", json.string(url)),
          #("filename", json.string(filename)),
        ]
        |> append_opt("mimetype", mime),
      )
      |> json.to_string()
    types.AudioMessage(body, url, mime) ->
      json.object(
        [
          #("msgtype", json.string("m.audio")),
          #("body", json.string(body)),
          #("url", json.string(url)),
        ]
        |> append_opt("mimetype", mime),
      )
      |> json.to_string()
    types.VideoMessage(body, url, mime) ->
      json.object(
        [
          #("msgtype", json.string("m.video")),
          #("body", json.string(body)),
          #("url", json.string(url)),
        ]
        |> append_opt("mimetype", mime),
      )
      |> json.to_string()
    types.EmoteMessage(body) ->
      json.object([
        #("msgtype", json.string("m.emote")),
        #("body", json.string(body)),
      ])
      |> json.to_string()
    types.LocationMessage(body, geo) ->
      json.object([
        #("msgtype", json.string("m.location")),
        #("body", json.string(body)),
        #("geo_uri", json.string(geo)),
      ])
      |> json.to_string()
    types.CustomMessage(msgtype, body) ->
      json.object([
        #("msgtype", json.string(msgtype)),
        #("body", json.string(body)),
      ])
      |> json.to_string()
  }
}

pub fn encode_create_room(
  name: String,
  topic: String,
  preset: String,
  invite_list: List(String),
) -> String {
  json.object([
    #("name", json.string(name)),
    #("topic", json.string(topic)),
    #("preset", json.string(preset)),
    #("invite", json.array(invite_list, json.string)),
    #("room_version", json.string("11")),
  ])
  |> json.to_string()
}

pub fn encode_invite(user_id: String) -> String {
  json.object([#("user_id", json.string(user_id))])
  |> json.to_string()
}

pub fn encode_typing(typing: Bool, timeout_ms: Int) -> String {
  json.object([
    #("typing", json.bool(typing)),
    #("timeout", json.int(timeout_ms)),
  ])
  |> json.to_string()
}

pub fn encode_receipt(event_id: String, receipt_type: String) -> String {
  json.object([
    #("event_id", json.string(event_id)),
    #("type", json.string(receipt_type)),
  ])
  |> json.to_string()
}

// -- Decoders (string-based, safe) -------------------------------------------

pub fn decode_login_response(
  body: String,
) -> Result(types.MatrixSession, String) {
  let user_id = extract_json_string(body, "user_id")
  let device_id = extract_json_string(body, "device_id")
  let token = extract_json_string(body, "access_token")
  case user_id, device_id, token {
    Ok(u), Ok(d), Ok(t) ->
      Ok(types.MatrixSession(
        user_id: u,
        device_id: d,
        access_token: t,
        homeserver_url: "",
      ))
    _, _, _ -> Error("Failed to decode login response")
  }
}

pub fn decode_room_id(body: String) -> Result(String, String) {
  extract_json_string(body, "room_id")
}

pub fn decode_event_id(body: String) -> Result(String, String) {
  extract_json_string(body, "event_id")
}

pub fn decode_versions(body: String) -> Result(List(String), String) {
  case string.contains(body, "versions") {
    True -> Ok(extract_string_array(body, "versions"))
    False -> Error("No versions field")
  }
}

pub fn decode_error(body: String) -> Result(#(String, String), String) {
  let errcode = extract_json_string(body, "errcode")
  let error = extract_json_string(body, "error")
  case errcode, error {
    Ok(c), Ok(e) -> Ok(#(c, e))
    Ok(c), _ -> Ok(#(c, "unknown error"))
    _, _ -> Error("Not a Matrix error response")
  }
}

// -- Helpers -----------------------------------------------------------------

fn append_opt(
  pairs: List(#(String, json.Json)),
  key: String,
  value: Option(String),
) -> List(#(String, json.Json)) {
  case value {
    Some(v) -> [#(key, json.string(v)), ..pairs]
    None -> pairs
  }
}

fn extract_json_string(
  json_str: String,
  key: String,
) -> Result(String, String) {
  let search = "\"" <> key <> "\":\""
  case string.split(json_str, search) {
    [_, rest, ..] ->
      case string.split(rest, "\"") {
        [value, ..] -> Ok(value)
        _ -> Error("Could not extract value for " <> key)
      }
    _ -> Error("Key not found: " <> key)
  }
}

fn extract_string_array(json_str: String, key: String) -> List(String) {
  let search = "\"" <> key <> "\":["
  case string.split(json_str, search) {
    [_, rest, ..] ->
      case string.split(rest, "]") {
        [array_content, ..] ->
          array_content
          |> string.replace("\"", "")
          |> string.split(",")
          |> list.filter(fn(s) { s != "" })
        _ -> []
      }
    _ -> []
  }
}
