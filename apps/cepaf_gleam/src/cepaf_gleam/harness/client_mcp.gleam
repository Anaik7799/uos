//// Fixed native-client MCP configuration bridge. Each reviewed grant receives
//// a distinct UOS server name; existing entries are never overwritten.

import cepaf_gleam/harness/admission as a
import cepaf_gleam/harness/client_profiles as profiles
import cepaf_gleam/harness/development as dev
import cepaf_gleam/harness/value
import gleam/int
import gleam/json
import gleam/list
import gleam/result
import gleam/string

pub fn perform(
  execution: a.Execution,
  args: value.Value,
  timeout: Int,
) -> Result(String, String) {
  use client_text <- result.try(field(args, "client"))
  use client <- result.try(profiles.parse_client(client_text))
  use action <- result.try(field(args, "action"))
  use intent <- result.try(field(args, "intent_id"))
  use _ <- result.try(a.require(a.intent_valid(intent), "intent_id"))
  use _ <- result.try(a.require(timeout > 0 && timeout <= 60_000, "timeout_bound"))
  use _ <- result.try(a.require(action_admitted(action), "client_action_not_admitted"))
  let profile = profiles.profile(client)
  let owned_name = profile.server_name <> execution.grant.id
  let env = grant_environment(execution)
  let command = cli(client)
  let argv = case action {
    "prepare" ->
      prepare_args(client, owned_name, profile.command, profile.args, env)
    "status" -> status_args(client)
    "rollback" -> rollback_args(client, owned_name)
    _ -> []
  }
  use _ <- result.try(a.require(argv != [], "client_action_not_admitted"))
  let output = case action {
    "prepare" | "rollback" -> {
      let status = safe_run(command, status_args(client), timeout)
      use listing <- result.try(status)
      let exists = string.contains(listing, owned_name)
      use _ <- result.try(case action, exists {
        "prepare", True -> Error("owned_session_server_exists_manual_review")
        "rollback", False -> Error("owned_session_server_absent")
        _, _ -> Ok(Nil)
      })
      safe_run(command, argv, timeout)
    }
    "status" -> safe_run(command, argv, timeout)
    _ -> Error("client_action_not_admitted")
  }
  use output <- result.try(output)
  // The CLI output can contain configuration values. Never return it to the
  // caller; emit only a fixed summary bound to the executing task and client.
  let configured = action == "prepare"
    || (action == "status" && string.contains(output, owned_name))
  Ok(
    json.object([
      #("client", json.string(profiles.name(client))),
      #("action", json.string(action)),
      #("server_name", json.string(owned_name)),
      #("configured", json.bool(configured)),
      #("status_observed", json.bool(action == "status")),
      #("cli_output_redacted", json.bool(True)),
      #("task", json.string(execution.binding.task)),
      #("session", json.string(execution.binding.session)),
      #("grant_id", json.string(execution.grant.id)),
    ])
      |> json.to_string,
  )
}

fn safe_run(command: String, argv: List(String), timeout: Int) -> Result(String, String) {
  case dev.bounded(command, argv, timeout) {
    Ok(output) -> Ok(output)
    Error(_) -> Error("client_cli_failed_redacted")
  }
}

pub fn action_admitted(action: String) -> Bool {
  action == "prepare" || action == "status" || action == "rollback"
}

fn field(args: value.Value, key: String) -> Result(String, String) {
  use found <- result.try(value.get(args, key))
  case found {
    value.Text(text) -> Ok(text)
    _ -> Error("string_field:" <> key)
  }
}

fn cli(client: profiles.Client) -> String {
  case client {
    profiles.Agy -> "/home/an/.local/bin/agy"
    profiles.Gemini -> "/usr/local/bin/gemini"
    profiles.Codex -> "/usr/local/bin/codex"
    profiles.Claude -> "/home/an/.local/bin/claude"
    profiles.Pi -> "/usr/local/bin/pi"
  }
}

fn grant_environment(execution: a.Execution) -> List(String) {
  let binding = execution.binding
  [
    "UOS_HARNESS_GRANT_PATH=" <> execution.grant.path,
    "UOS_HARNESS_GRANT_SHA256=" <> execution.grant.digest,
    "UOS_HARNESS_ROLE=development",
    "UOS_HARNESS_PLAN=" <> binding.plan,
    "UOS_HARNESS_TASK=" <> binding.task,
    "UOS_HARNESS_WORKER=" <> binding.worker,
    "UOS_HARNESS_ATTEMPT=" <> int.to_string(binding.attempt),
    "UOS_HARNESS_SESSION=" <> binding.session,
    "UOS_HARNESS_EPOCH=" <> int.to_string(binding.epoch),
  ]
}

fn prepare_args(
  client: profiles.Client,
  owned_name: String,
  command: String,
  server_args: List(String),
  env: List(String),
) -> List(String) {
  case client {
    profiles.Agy -> ["mcp", "add", ..list.flatten([
      list.map(env, fn(v) { ["--env", v] }),
      [owned_name, command],
      server_args,
    ])]
    profiles.Gemini -> ["mcp", "add", "--scope", "user", ..list.flatten([
      list.map(env, fn(v) { ["--env", v] }),
      [owned_name, command],
      server_args,
    ])]
    profiles.Codex -> ["mcp", "add", owned_name, ..list.flatten([
      list.map(env, fn(v) { ["--env", v] }),
      ["--", command],
      server_args,
    ])]
    profiles.Claude -> ["mcp", "add", "--scope", "user", ..list.flatten([
      list.map(env, fn(v) { ["--env", v] }),
      [owned_name, "--", command],
      server_args,
    ])]
    profiles.Pi -> ["mcp", "add", owned_name, ..list.flatten([
      list.map(env, fn(v) { ["--env", v] }),
      ["--", command],
      server_args,
    ])]
  }
}

fn status_args(client: profiles.Client) -> List(String) {
  case client {
    profiles.Agy | profiles.Gemini | profiles.Codex | profiles.Claude ->
      ["mcp", "list"]
    profiles.Pi -> ["mcp", "list", "--json"]
  }
}

fn rollback_args(client: profiles.Client, owned_name: String) -> List(String) {
  case client {
    profiles.Agy | profiles.Codex -> ["mcp", "remove", owned_name]
    profiles.Gemini -> ["mcp", "remove", "--scope", "user", owned_name]
    profiles.Claude -> ["mcp", "remove", "--scope", "user", owned_name]
    profiles.Pi -> ["mcp", "remove", owned_name]
  }
}
