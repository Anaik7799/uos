//// Fixed-path, metadata-only reads for native client MCP registries.
//// Only the grant-unique UOS entry is inspected. Existing unrelated config
//// values are never returned, hashed, logged, or included in receipts.

import cepaf_gleam/harness/client_profiles as profiles
import cepaf_gleam/harness/value
import gleam/json
import gleam/list
import gleam/result
import gleam/string

@external(erlang, "client_config_io", "read_bounded")
fn read_bounded(path: String, max_bytes: Int) -> Result(String, String)

pub type Observation {
  Missing
  Exact
  Conflict
}

pub fn observation_label(observation: Observation) -> String {
  case observation {
    Missing -> "missing"
    Exact -> "exact"
    Conflict -> "conflict"
  }
}

pub fn observe(
  client: profiles.Client,
  name: String,
  command: String,
  expected_args: List(String),
  expected_env: List(String),
) -> Result(Observation, String) {
  use path <- result.try(config_path(client))
  use body <- result.try(read_bounded(path, 262_144))
  inspect_json(client, name, body, command, expected_args, expected_env)
}

/// Pure parser used by tests with synthetic config bytes. Runtime callers cannot
/// supply file paths or config bytes: `observe` owns both from the client enum.
pub fn inspect_json(
  client: profiles.Client,
  name: String,
  body: String,
  command: String,
  expected_args: List(String),
  expected_env: List(String),
) -> Result(Observation, String) {
  use _ <- result.try(case bounded_json(body) {
    True -> Ok(Nil)
    False -> Error("client_config_bound_or_depth")
  })
  use parsed <- result.try(
    json.parse(body, value.decoder())
    |> result.map_error(fn(_) { "client_config_json_invalid" }),
  )
  use servers <- result.try(server_map(client, parsed))
  case value.get(servers, name) {
    Error(_) -> Ok(Missing)
    Ok(entry) ->
      case exact_entry(entry, command, expected_args, expected_env) {
        True -> Ok(Exact)
        False -> Ok(Conflict)
      }
  }
}

fn config_path(client: profiles.Client) -> Result(String, String) {
  case client {
    profiles.Agy -> Ok("/home/an/.gemini/config/mcp_config.json")
    profiles.Gemini -> Ok("/home/an/.gemini/settings.json")
    profiles.Pi -> Ok("/home/an/.pi/agent/mcp.json")
    profiles.Codex | profiles.Claude ->
      Error("native_cli_metadata_reader_required")
  }
}

fn server_map(
  client: profiles.Client,
  parsed: value.Value,
) -> Result(value.Value, String) {
  case client {
    profiles.Agy | profiles.Gemini | profiles.Pi -> {
      use servers <- result.try(value.get(parsed, "mcpServers"))
      case servers {
        value.Object(_) -> Ok(servers)
        _ -> Error("client_config_schema_mismatch")
      }
    }
    profiles.Codex | profiles.Claude ->
      Error("native_cli_metadata_reader_required")
  }
}

fn exact_entry(
  entry: value.Value,
  command: String,
  expected_args: List(String),
  expected_env: List(String),
) -> Bool {
  case entry {
    value.Object(fields) -> {
      let keys_ok =
        list.all(fields, fn(field) {
          list.contains(["command", "args", "env", "type"], field.0)
        })
      let command_ok = value.get(entry, "command") == Ok(value.Text(command))
      let args_ok = case value.get(entry, "args") {
        Ok(value.Array(args)) -> string_array_equals(args, expected_args)
        _ -> False
      }
      let env_ok = case value.get(entry, "env") {
        Ok(value.Object(env)) -> environment_equals(env, expected_env)
        _ -> False
      }
      let type_ok = case value.get(entry, "type") {
        Error(_) -> True
        Ok(value.Text("stdio")) -> True
        _ -> False
      }
      keys_ok && command_ok && args_ok && env_ok && type_ok
    }
    _ -> False
  }
}

fn environment_equals(
  actual: List(#(String, value.Value)),
  expected: List(String),
) -> Bool {
  list.length(actual) == list.length(expected)
  && list.all(expected, fn(pair) {
    case string.split(pair, "=") {
      [key, text] ->
        list.any(actual, fn(entry) {
          entry.0 == key && entry.1 == value.Text(text)
        })
      _ -> False
    }
  })
}

fn string_array_equals(
  actual: List(value.Value),
  expected: List(String),
) -> Bool {
  list.length(actual) == list.length(expected)
  && list.all(list.zip(actual, expected), fn(pair) {
    pair.0 == value.Text(pair.1)
  })
}

pub fn bounded_json(body: String) -> Bool {
  string.byte_size(body) <= 262_144
  && depth_ok(string.to_graphemes(body), False, False, 0)
}

fn depth_ok(
  chars: List(String),
  in_string: Bool,
  escaped: Bool,
  depth: Int,
) -> Bool {
  case chars {
    [] -> !in_string && !escaped && depth == 0
    [char, ..rest] ->
      case in_string, escaped, char {
        True, True, _ -> depth_ok(rest, True, False, depth)
        True, False, "\\" -> depth_ok(rest, True, True, depth)
        True, False, "\"" -> depth_ok(rest, False, False, depth)
        True, False, _ -> depth_ok(rest, True, False, depth)
        False, _, "\"" -> depth_ok(rest, True, False, depth)
        False, _, "{" ->
          case depth < 32 {
            True -> depth_ok(rest, False, False, depth + 1)
            False -> False
          }
        False, _, "[" ->
          case depth < 32 {
            True -> depth_ok(rest, False, False, depth + 1)
            False -> False
          }
        False, _, "}" ->
          case depth > 0 {
            True -> depth_ok(rest, False, False, depth - 1)
            False -> False
          }
        False, _, "]" ->
          case depth > 0 {
            True -> depth_ok(rest, False, False, depth - 1)
            False -> False
          }
        False, _, _ -> depth_ok(rest, False, False, depth)
      }
  }
}
