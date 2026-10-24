import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import uos_swarm/board
import uos_swarm/session_store as store
import uos_swarm/session_sync as sync

const schema_version = "uos.telegram.coordination.v1"

const projection_error = "coordination_projection_unavailable"

const observation_error = "coordination_observation_unavailable"

const max_sessions = 256

const max_messages = 10_000

const max_seen = 20_000

const max_shown_sessions = 20

const max_output_bytes = 32_768

type PeerSummary {
  PeerSummary(
    session: String,
    provider: String,
    revision: String,
    status: String,
    pending_messages: Int,
  )
}

pub fn read(path: String, view: String) -> Result(String, String) {
  store.observe_file(path, fn(state, boot, now) {
    project(state, boot, now, view)
    |> result.map_error(store.RefusedError)
  })
  |> result.replace_error(observation_error)
}

pub fn project(
  state: sync.State,
  boot: String,
  now: Int,
  view: String,
) -> Result(String, String) {
  case within_bounds(state) {
    False -> Error(projection_error)
    True ->
      case view {
        "peers" -> project_peers(state, boot, now)
        "board" -> project_board(state)
        _ -> Error(projection_error)
      }
  }
}

fn within_bounds(state: sync.State) -> Bool {
  dict.size(state.sessions) <= max_sessions
  && dict.size(state.messages) <= max_messages
  && dict.size(state.seen) <= max_seen
}

fn project_peers(
  state: sync.State,
  boot: String,
  now: Int,
) -> Result(String, String) {
  let raw_status = sync.status_json(state, boot, now) |> json.to_string
  case json.parse(raw_status, sessions_decoder()) {
    Error(_) -> Error(projection_error)
    Ok(sessions) -> {
      let visible = list.take(sessions, max_shown_sessions)
      let total_sessions = list.length(sessions)
      let shown = list.length(visible)
      let truncated = total_sessions > shown
      envelope_fields(state, "peers", [
        #(
          "meaning",
          json.string(
            "Heartbeat freshness is self-reported; process liveness is not probed.",
          ),
        ),
        #("total_sessions", json.int(total_sessions)),
        #("shown", json.int(shown)),
        #("truncated", json.bool(truncated)),
        #("sessions", json.array(visible, encode_peer_summary)),
      ])
      |> render_bounded
    }
  }
}

fn project_board(state: sync.State) -> Result(String, String) {
  let kind_counts =
    state.messages
    |> dict.values
    |> fold_kind_counts
    |> dict.to_list
    |> list.sort(fn(left, right) { string.compare(left.0, right.0) })

  envelope_fields(state, "board", [
    #("scope", json.string("metadata_counts_only")),
    #(
      "meaning",
      json.string(
        "Counts are observed ledger state, not execution success.",
      ),
    ),
    #("stored_messages", json.int(dict.size(state.messages))),
    #("acknowledgement_records", json.int(dict.size(state.acknowledgements))),
    #(
      "kind_counts",
      json.array(kind_counts, fn(pair) {
        json.object([
          #("kind", json.string(pair.0)),
          #("count", json.int(pair.1)),
        ])
      }),
    ),
  ])
  |> render_bounded
}

fn fold_kind_counts(messages: List(board.Message)) -> Dict(String, Int) {
  list.fold(messages, dict.new(), fn(acc, message) {
    let label = board.kind_label(message.kind)
    let current = dict.get(acc, label) |> result.unwrap(0)
    dict.insert(acc, label, current + 1)
  })
}

fn envelope_fields(
  state: sync.State,
  view: String,
  extra: List(#(String, json.Json)),
) -> json.Json {
  list.append(
    [
      #("schema", json.string(schema_version)),
      #("view", json.string(view)),
      #("sequence", json.int(state.sequence)),
      #("journal_digest", json.string(state.digest)),
      #("authority", json.string("observation_only")),
      #("runtime_admission", json.string("NOT_GRANTED")),
    ],
    extra,
  )
  |> json.object
}

fn render_bounded(payload: json.Json) -> Result(String, String) {
  let rendered = json.to_string(payload)
  case string.byte_size(rendered) <= max_output_bytes {
    True -> Ok(rendered)
    False -> Error(projection_error)
  }
}

fn sessions_decoder() -> decode.Decoder(List(PeerSummary)) {
  use sessions <- decode.field("sessions", decode.list(peer_summary_decoder()))
  decode.success(sessions)
}

fn peer_summary_decoder() -> decode.Decoder(PeerSummary) {
  use session <- decode.field("session", decode.string)
  use provider <- decode.field("provider", decode.string)
  use revision <- decode.field("revision", decode.string)
  use status <- decode.field("status", decode.string)
  use pending_messages <- decode.field("pending_messages", decode.int)
  decode.success(PeerSummary(
    session: session,
    provider: provider,
    revision: revision,
    status: status,
    pending_messages: pending_messages,
  ))
}

fn encode_peer_summary(peer: PeerSummary) -> json.Json {
  json.object([
    #("session", json.string(peer.session)),
    #("provider", json.string(peer.provider)),
    #("revision", json.string(peer.revision)),
    #("status", json.string(peer.status)),
    #("pending_messages", json.int(peer.pending_messages)),
  ])
}
