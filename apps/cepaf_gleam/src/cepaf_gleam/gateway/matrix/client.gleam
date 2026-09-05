//// [C3I-SIL6-MSTS] MODULE CONTRACT
//// <c3i-module>
////   <identity><module>cepaf_gleam/gateway/matrix/client</module></identity>
////   <fractal-topology><layer>L7_FEDERATION</layer></fractal-topology>
////   <compliance><stamp-controls>SC-MATRIX-003</stamp-controls></compliance>
//// </c3i-module>
////
//// Matrix Client-Server API — pure state machine.
//// Every function returns #(new_state, Result) — no side effects.

import cepaf_gleam/gateway/matrix/codec
import cepaf_gleam/gateway/matrix/http
import cepaf_gleam/gateway/matrix/types
import gleam/int
import gleam/option.{type Option, None, Some}
import gleam/string

pub type MatrixClientState {
  MatrixClientState(
    session: Option(types.MatrixSession),
    http_client: http.MatrixHttpClient,
    since: Option(String),
    consecutive_failures: Int,
    max_failures: Int,
    rooms_joined: List(String),
    transaction_id: Int,
  )
}

pub fn new(homeserver_url: String) -> MatrixClientState {
  MatrixClientState(
    session: None,
    http_client: http.new(homeserver_url),
    since: None,
    consecutive_failures: 0,
    max_failures: 5,
    rooms_joined: [],
    transaction_id: 0,
  )
}

pub fn with_session(
  state: MatrixClientState,
  session: types.MatrixSession,
) -> MatrixClientState {
  MatrixClientState(
    ..state,
    session: Some(session),
    http_client: http.with_token(state.http_client, session.access_token),
  )
}

pub fn login_request(
  state: MatrixClientState,
  username: String,
  password: String,
) -> #(MatrixClientState, http.HttpRequest) {
  let body = codec.encode_login(username, password)
  let req =
    http.build_request(
      state.http_client,
      http.Post,
      "/_matrix/client/v3/login",
      Some(body),
    )
  #(state, req)
}

pub fn handle_login_response(
  state: MatrixClientState,
  response: http.MatrixResponse,
) -> #(MatrixClientState, Result(types.MatrixSession, http.MatrixError)) {
  case http.is_success(response.status) {
    True ->
      case codec.decode_login_response(response.body) {
        Ok(session) -> {
          let s =
            types.MatrixSession(
              ..session,
              homeserver_url: state.http_client.base_url,
            )
          #(with_session(state, s) |> record_success, Ok(s))
        }
        Error(e) -> #(record_failure(state), Error(http.HttpError(e)))
      }
    False -> #(
      record_failure(state),
      Error(http.ApiError("M_UNKNOWN", response.body)),
    )
  }
}

pub fn sync_request(
  state: MatrixClientState,
  timeout_ms: Int,
) -> #(MatrixClientState, http.HttpRequest) {
  let path = case state.since {
    Some(since) ->
      "/_matrix/client/v3/sync?timeout="
      <> int.to_string(timeout_ms)
      <> "&since="
      <> since
    None -> "/_matrix/client/v3/sync?timeout=" <> int.to_string(timeout_ms)
  }
  let req = http.build_request(state.http_client, http.Get, path, None)
  #(state, req)
}

pub fn handle_sync_response(
  state: MatrixClientState,
  response: http.MatrixResponse,
) -> #(MatrixClientState, Result(types.SyncResponse, http.MatrixError)) {
  case http.is_success(response.status) {
    True -> {
      let next_batch = case codec.decode_login_response(response.body) {
        _ -> extract_next_batch(response.body)
      }
      let new_state =
        MatrixClientState(..state, since: Some(next_batch))
        |> record_success
      #(new_state, Ok(types.empty_sync()))
    }
    False -> #(
      record_failure(state),
      Error(http.ApiError("M_UNKNOWN", "sync failed")),
    )
  }
}

pub fn send_message_request(
  state: MatrixClientState,
  room_id: String,
  msg: types.MessageContent,
) -> #(MatrixClientState, http.HttpRequest) {
  let #(new_state, txn) = next_txn_id(state)
  let body = codec.encode_message(msg)
  let path =
    "/_matrix/client/v3/rooms/" <> room_id <> "/send/m.room.message/" <> txn
  let req =
    http.build_request(new_state.http_client, http.Put, path, Some(body))
  #(new_state, req)
}

pub fn handle_send_response(
  state: MatrixClientState,
  response: http.MatrixResponse,
) -> #(MatrixClientState, Result(String, http.MatrixError)) {
  case http.is_success(response.status) {
    True ->
      case codec.decode_event_id(response.body) {
        Ok(eid) -> #(record_success(state), Ok(eid))
        Error(e) -> #(record_failure(state), Error(http.HttpError(e)))
      }
    False -> #(
      record_failure(state),
      Error(http.ApiError("M_UNKNOWN", response.body)),
    )
  }
}

pub fn join_room_request(
  state: MatrixClientState,
  room_id_or_alias: String,
) -> #(MatrixClientState, http.HttpRequest) {
  let path = "/_matrix/client/v3/join/" <> room_id_or_alias
  let req = http.build_request(state.http_client, http.Post, path, Some("{}"))
  #(state, req)
}

pub fn handle_join_response(
  state: MatrixClientState,
  response: http.MatrixResponse,
) -> #(MatrixClientState, Result(String, http.MatrixError)) {
  case http.is_success(response.status) {
    True ->
      case codec.decode_room_id(response.body) {
        Ok(rid) -> {
          let new_state =
            MatrixClientState(..state, rooms_joined: [rid, ..state.rooms_joined])
            |> record_success
          #(new_state, Ok(rid))
        }
        Error(e) -> #(record_failure(state), Error(http.HttpError(e)))
      }
    False -> #(
      record_failure(state),
      Error(http.ApiError("M_UNKNOWN", response.body)),
    )
  }
}

pub fn create_room_request(
  state: MatrixClientState,
  name: String,
  topic: String,
  preset: String,
) -> #(MatrixClientState, http.HttpRequest) {
  let body = codec.encode_create_room(name, topic, preset, [])
  let req =
    http.build_request(
      state.http_client,
      http.Post,
      "/_matrix/client/v3/createRoom",
      Some(body),
    )
  #(state, req)
}

pub fn invite_request(
  state: MatrixClientState,
  room_id: String,
  user_id: String,
) -> #(MatrixClientState, http.HttpRequest) {
  let body = codec.encode_invite(user_id)
  let path = "/_matrix/client/v3/rooms/" <> room_id <> "/invite"
  let req = http.build_request(state.http_client, http.Post, path, Some(body))
  #(state, req)
}

pub fn versions_request(
  state: MatrixClientState,
) -> #(MatrixClientState, http.HttpRequest) {
  let req =
    http.build_request(
      state.http_client,
      http.Get,
      "/_matrix/client/versions",
      None,
    )
  #(state, req)
}

pub fn record_failure(state: MatrixClientState) -> MatrixClientState {
  MatrixClientState(
    ..state,
    consecutive_failures: state.consecutive_failures + 1,
  )
}

pub fn record_success(state: MatrixClientState) -> MatrixClientState {
  MatrixClientState(..state, consecutive_failures: 0)
}

pub fn is_healthy(state: MatrixClientState) -> Bool {
  state.consecutive_failures < state.max_failures
}

pub fn next_txn_id(state: MatrixClientState) -> #(MatrixClientState, String) {
  let new_id = state.transaction_id + 1
  #(
    MatrixClientState(..state, transaction_id: new_id),
    "m." <> int.to_string(new_id),
  )
}

pub fn summary(state: MatrixClientState) -> String {
  let session_str = case state.session {
    Some(s) -> s.user_id
    None -> "not logged in"
  }
  "Matrix("
  <> session_str
  <> ", rooms="
  <> int.to_string(list_len(state.rooms_joined))
  <> ", failures="
  <> int.to_string(state.consecutive_failures)
  <> ", txn="
  <> int.to_string(state.transaction_id)
  <> ")"
}

fn extract_next_batch(body: String) -> String {
  case string.split(body, "\"next_batch\":\"") {
    [_, rest, ..] ->
      case string.split(rest, "\"") {
        [batch, ..] -> batch
        _ -> ""
      }
    _ -> ""
  }
}

fn list_len(items: List(a)) -> Int {
  do_len(items, 0)
}

fn do_len(items: List(a), acc: Int) -> Int {
  case items {
    [] -> acc
    [_, ..rest] -> do_len(rest, acc + 1)
  }
}
