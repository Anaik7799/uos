import cepaf_gleam/telegram/auth
import cepaf_gleam/telegram/mini_api as api
import cepaf_gleam/zenoh/rest
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string

pub type Grant {
  Grant(user_id: Int, topic: String)
}

pub opaque type Configuration {
  Configuration(grants: List(Grant))
}

pub const max_grants = 256

pub const max_topics_per_user = 20

pub const max_payload_bytes = 32_768

pub const max_part_bytes = 2048

pub const max_observation_fields = 100

pub fn configuration(grants: List(Grant)) -> Result(Configuration, String) {
  let count = list.length(grants)
  case count >= 1 && count <= max_grants {
    False -> Error("Grant count must be between 1 and 256")
    True -> {
      use validated <- result.try(validate_grants(grants, [], dict.new()))
      Ok(Configuration(grants: validated))
    }
  }
}

pub fn grants_for_user(config: Configuration, user_id: Int) -> List(String) {
  let Configuration(grants) = config
  list.filter_map(grants, fn(grant) {
    case grant.user_id == user_id {
      True -> Ok(grant.topic)
      False -> Error(Nil)
    }
  })
}

pub fn observe(
  config: Configuration,
  read: api.AuthorizedRead,
  query: fn(String) -> Result(String, String),
  clock: fn() -> Int,
) -> api.Observation {
  let uid = api.user_id(read)
  let user_topics = grants_for_user(config, uid)
  case user_topics {
    [] -> api.Forbidden
    _ ->
      case api.selected_topic(read) {
        None -> observe_topic_list(user_topics, clock)
        Some(topic) ->
          case list.contains(user_topics, topic) {
            False -> api.Forbidden
            True -> observe_selected_topic(user_topics, topic, query, clock)
          }
      }
  }
}

fn observe_topic_list(
  user_topics: List(String),
  clock: fn() -> Int,
) -> api.Observation {
  let at = clock()
  case at > 0 {
    False -> api.Unavailable("Invalid observation timestamp")
    True -> {
      let fields =
        base_topic_fields(user_topics)
        |> dict.insert("Query result", "No topic selected")
        |> dict.insert("Runtime admission", "NOT_GRANTED")
      api.Observed(at_unix: at, source: "server_topic_grants", fields: fields)
    }
  }
}

fn observe_selected_topic(
  user_topics: List(String),
  topic: String,
  query: fn(String) -> Result(String, String),
  clock: fn() -> Int,
) -> api.Observation {
  case query(topic) {
    Error("zenoh_no_reply") -> {
      let at = clock()
      case at > 0 {
        False -> api.Unavailable("Invalid observation timestamp")
        True -> {
          let fields =
            base_topic_fields(user_topics)
            |> dict.insert("Selected topic", topic)
            |> dict.insert("Query result", "No retained reply")
            |> dict.insert("Runtime admission", "NOT_GRANTED")
          api.Observed(at_unix: at, source: "zenoh_rest", fields: fields)
        }
      }
    }
    Error(reason) ->
      case string.is_empty(reason) {
        True -> api.Unavailable("Zenoh query failed")
        False -> api.Unavailable(reason)
      }
    Ok(raw) -> {
      let at = clock()
      case at > 0 {
        False -> api.Unavailable("Invalid observation timestamp")
        True ->
          case chunk_valid_payload(raw) {
            Error(reason) -> api.Unavailable(reason)
            Ok(parts) -> {
              let base =
                base_topic_fields(user_topics)
                |> dict.insert("Selected topic", topic)
                |> dict.insert("Query result", "Retained reply")
                |> dict.insert("Runtime admission", "NOT_GRANTED")
              let fields = insert_message_parts(base, parts, 1)
              case dict.size(fields) <= max_observation_fields {
                False -> api.Unavailable("Observation exceeds 100 fields")
                True ->
                  api.Observed(at_unix: at, source: "zenoh_rest", fields: fields)
              }
            }
          }
      }
    }
  }
}

fn base_topic_fields(user_topics: List(String)) -> Dict(String, String) {
  let topic_entries =
    list.index_map(user_topics, fn(topic, idx) {
      #(padded_label("Available topic ", idx + 1), topic)
    })
  topic_entries
  |> dict.from_list
  |> dict.insert("Topic count", int.to_string(list.length(user_topics)))
}

fn insert_message_parts(
  fields: Dict(String, String),
  parts: List(String),
  index: Int,
) -> Dict(String, String) {
  case parts {
    [] -> fields
    [part, ..rest_parts] -> {
      let next =
        dict.insert(fields, padded_label("Message part ", index), part)
      insert_message_parts(next, rest_parts, index + 1)
    }
  }
}

fn padded_label(prefix: String, index: Int) -> String {
  prefix <> string.pad_start(int.to_string(index), to: 2, with: "0")
}

fn validate_grants(
  remaining: List(Grant),
  seen: List(Grant),
  counts: Dict(Int, Int),
) -> Result(List(Grant), String) {
  case remaining {
    [] -> Ok(list.reverse(seen))
    [grant, ..rest_grants] -> {
      use _ <- result.try(validate_user_id(grant.user_id))
      use _ <- result.try(validate_topic_key(grant.topic))
      use _ <- result.try(check_duplicate_grant(seen, grant))
      let current_count = case dict.get(counts, grant.user_id) {
        Ok(n) -> n
        Error(Nil) -> 0
      }
      case current_count + 1 <= max_topics_per_user {
        False -> Error("User exceeds maximum of 20 granted topics")
        True -> {
          let next_counts =
            dict.insert(counts, grant.user_id, current_count + 1)
          validate_grants(rest_grants, [grant, ..seen], next_counts)
        }
      }
    }
  }
}

fn validate_user_id(user_id: Int) -> Result(Int, String) {
  case user_id >= 1 && user_id <= auth.max_safe_integer {
    True -> Ok(user_id)
    False -> Error("Grant user_id out of valid safe integer range")
  }
}

fn validate_topic_key(topic: String) -> Result(String, String) {
  case rest.valid_key(topic) {
    True -> Ok(topic)
    False -> Error("Invalid Zenoh topic key in grant")
  }
}

fn check_duplicate_grant(
  seen: List(Grant),
  candidate: Grant,
) -> Result(Nil, String) {
  case list.contains(seen, candidate) {
    True -> Error("Duplicate (user_id, topic) grant")
    False -> Ok(Nil)
  }
}

fn chunk_valid_payload(raw: String) -> Result(List(String), String) {
  case string.byte_size(raw) <= max_payload_bytes {
    False -> Error("Payload exceeds 32768 bytes")
    True -> {
      let codepoints = string.to_utf_codepoints(raw)
      use _ <- result.try(validate_codepoints(codepoints))
      case codepoints {
        [] -> Ok([""])
        _ -> Ok(split_codepoints(codepoints, [], 0, []))
      }
    }
  }
}

fn validate_codepoints(codepoints: List(UtfCodepoint)) -> Result(Nil, String) {
  case codepoints {
    [] -> Ok(Nil)
    [cp, ..rest_cps] -> {
      let code = string.utf_codepoint_to_int(cp)
      case is_allowed_codepoint(code) {
        False -> Error("Payload contains disallowed control characters")
        True -> validate_codepoints(rest_cps)
      }
    }
  }
}

fn is_allowed_codepoint(code: Int) -> Bool {
  case code {
    9 | 10 | 13 -> True
    _ if code < 32 -> False
    127 -> False
    _ if code >= 128 && code <= 159 -> False
    _ -> True
  }
}

fn split_codepoints(
  remaining: List(UtfCodepoint),
  current_rev: List(UtfCodepoint),
  current_bytes: Int,
  acc_parts_rev: List(String),
) -> List(String) {
  case remaining {
    [] -> {
      let final_part = string.from_utf_codepoints(list.reverse(current_rev))
      list.reverse([final_part, ..acc_parts_rev])
    }
    [cp, ..rest_cps] -> {
      let cp_bytes = utf8_codepoint_bytes(cp)
      case current_bytes + cp_bytes > max_part_bytes && current_bytes > 0 {
        True -> {
          let completed_part =
            string.from_utf_codepoints(list.reverse(current_rev))
          split_codepoints(
            rest_cps,
            [cp],
            cp_bytes,
            [completed_part, ..acc_parts_rev],
          )
        }
        False ->
          split_codepoints(
            rest_cps,
            [cp, ..current_rev],
            current_bytes + cp_bytes,
            acc_parts_rev,
          )
      }
    }
  }
}

fn utf8_codepoint_bytes(cp: UtfCodepoint) -> Int {
  let code = string.utf_codepoint_to_int(cp)
  case code {
    _ if code <= 0x7F -> 1
    _ if code <= 0x7FF -> 2
    _ if code <= 0xFFFF -> 3
    _ -> 4
  }
}
