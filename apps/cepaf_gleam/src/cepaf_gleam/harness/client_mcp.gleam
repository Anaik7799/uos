//// Fixed native-client MCP configuration bridge. Each reviewed grant receives
//// a distinct UOS server name; existing entries are never overwritten.

import cepaf_gleam/harness/admission as a
import cepaf_gleam/harness/client_config
import cepaf_gleam/harness/client_profiles as profiles
import cepaf_gleam/harness/development as dev
import cepaf_gleam/harness/value
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub fn perform(
  execution: a.Execution,
  args: value.Value,
  timeout: Int,
) -> Result(String, String) {
  result.flatten({
    use client_text <- result.try(field(args, "client"))
    use client <- result.try(profiles.parse_client(client_text))
    use action <- result.try(field(args, "action"))
    use _ <- result.try(a.require(
      permissions_allow(
        execution.scope.allowed_clients,
        execution.scope.allowed_client_actions,
        client_text,
        action,
      ),
      "client_or_action_permission_denied",
    ))
    use intent <- result.try(field(args, "intent_id"))
    use _ <- result.try(a.require(a.intent_valid(intent), "intent_id"))
    use _ <- result.try(a.require(
      timeout > 0 && timeout <= 60_000,
      "timeout_bound",
    ))
    use _ <- result.try(a.require(
      action_admitted(action),
      "client_action_not_admitted",
    ))
    use source_root <- result.try(a.source_root(execution.grant))
    let profile = profiles.profile_at(client, source_root)
    let owned_name = profile.server_name <> execution.grant.id
    let env = grant_environment(execution)
    let command = cli(client)
    case action {
      "status" -> {
        use observed <- result.try(lookup_entry(
          client,
          owned_name,
          command,
          profile,
          env,
          timeout,
        ))
        case observed {
          None -> Ok(summary(execution, client, action, owned_name, False))
          Some(body) -> {
            use _ <- result.try(a.require(
              exact_entry(
                client,
                body,
                owned_name,
                profile.command,
                profile.args,
                env,
              ),
              "client_entry_conflict_manual_review",
            ))
            Ok(summary(execution, client, action, owned_name, True))
          }
        }
      }
      "prepare" -> {
        use observed <- result.try(lookup_entry(
          client,
          owned_name,
          command,
          profile,
          env,
          timeout,
        ))
        case observed {
          Some(body) -> {
            use _ <- result.try(a.require(
              exact_entry(
                client,
                body,
                owned_name,
                profile.command,
                profile.args,
                env,
              ),
              "client_entry_conflict_no_overwrite",
            ))
            Ok(summary(execution, client, action, owned_name, True))
          }
          None -> {
            let argv =
              prepare_args(
                client,
                owned_name,
                profile.command,
                profile.args,
                env,
              )
            use _ <- result.try(safe_run(command, argv, timeout))
            use after <- result.try(lookup_entry(
              client,
              owned_name,
              command,
              profile,
              env,
              timeout,
            ))
            case after {
              Some(body) -> {
                use _ <- result.try(a.require(
                  exact_entry(
                    client,
                    body,
                    owned_name,
                    profile.command,
                    profile.args,
                    env,
                  ),
                  "client_config_readback_mismatch_manual_reconciliation",
                ))
                Ok(summary(execution, client, action, owned_name, True))
              }
              None ->
                Error("client_config_readback_missing_manual_reconciliation")
            }
          }
        }
      }
      "rollback" -> {
        use observed <- result.try(lookup_entry(
          client,
          owned_name,
          command,
          profile,
          env,
          timeout,
        ))
        case observed {
          None -> Ok(summary(execution, client, action, owned_name, False))
          Some(body) -> {
            use _ <- result.try(a.require(
              exact_entry(
                client,
                body,
                owned_name,
                profile.command,
                profile.args,
                env,
              ),
              "client_entry_conflict_no_remove",
            ))
            let argv = rollback_args(client, owned_name)
            use _ <- result.try(safe_run(command, argv, timeout))
            use after <- result.try(lookup_entry(
              client,
              owned_name,
              command,
              profile,
              env,
              timeout,
            ))
            case after {
              None -> Ok(summary(execution, client, action, owned_name, False))
              Some(_) -> Error("client_rollback_readback_failed")
            }
          }
        }
      }
      _ -> Error("client_action_not_admitted")
    }
  })
}

fn safe_run(
  command: String,
  argv: List(String),
  timeout: Int,
) -> Result(String, String) {
  case dev.bounded(command, argv, timeout) {
    Ok(output) -> Ok(output)
    Error(_) -> Error("client_cli_failed_redacted")
  }
}

fn summary(
  execution: a.Execution,
  client: profiles.Client,
  action: String,
  server: String,
  configured: Bool,
) -> Result(String, String) {
  Ok(
    json.object([
      #("client", json.string(profiles.name(client))),
      #("action", json.string(action)),
      #("server_name", json.string(server)),
      #("configured", json.bool(configured)),
      #("entry_readback_exact", json.bool(True)),
      #("cli_output_redacted", json.bool(True)),
      #("task", json.string(execution.binding.task)),
      #("session", json.string(execution.binding.session)),
      #("grant_id", json.string(execution.grant.id)),
    ])
    |> json.to_string,
  )
}

fn lookup_entry(
  client: profiles.Client,
  owned_name: String,
  command: String,
  profile: profiles.Profile,
  env: List(String),
  timeout: Int,
) -> Result(Option(String), String) {
  case client {
    profiles.Agy | profiles.Gemini | profiles.Pi ->
      case
        client_config.observe(
          client,
          owned_name,
          profile.command,
          profile.args,
          env,
        )
      {
        Ok(client_config.Missing) -> Ok(None)
        Ok(client_config.Exact) -> Ok(Some("UOS_TYPED_METADATA_EXACT"))
        Ok(client_config.Conflict) ->
          Error("client_entry_conflict_manual_review")
        Error(_) -> Error("client_metadata_lookup_failed_redacted")
      }
    profiles.Codex | profiles.Claude ->
      lookup_native_cli(client, owned_name, command, timeout)
  }
}

fn lookup_native_cli(
  client: profiles.Client,
  owned_name: String,
  command: String,
  timeout: Int,
) -> Result(Option(String), String) {
  use argv <- result.try(metadata_lookup_args(client, owned_name))
  case dev.bounded(command, argv, timeout) {
    Ok(output) ->
      case string.contains(output, owned_name) {
        True -> Ok(Some(output))
        False -> Ok(None)
      }
    Error(reason) -> {
      let folded = string.lowercase(reason)
      let missing =
        string.contains(reason, owned_name)
        && {
          string.contains(folded, "not found")
          || string.contains(folded, "not configured")
        }
      case missing {
        True -> Ok(None)
        False -> Error("client_metadata_lookup_failed_redacted")
      }
    }
  }
}

fn metadata_lookup_args(
  client: profiles.Client,
  owned_name: String,
) -> Result(List(String), String) {
  case client {
    profiles.Codex -> Ok(["mcp", "get", "--json", owned_name])
    // Claude's get targets this exact entry rather than probing other servers.
    profiles.Claude -> Ok(["mcp", "get", owned_name])
    // Other clients lack an exact metadata getter; their list commands can
    // connect to unrelated configured servers, so fail closed.
    profiles.Agy | profiles.Gemini | profiles.Pi ->
      Error("metadata_only_entry_lookup_unavailable")
  }
}

fn exact_entry(
  client: profiles.Client,
  output: String,
  name: String,
  command: String,
  expected_args: List(String),
  expected_env: List(String),
) -> Bool {
  case client {
    profiles.Codex ->
      codex_entry_matches(output, name, command, expected_args, expected_env)
    profiles.Claude ->
      string.contains(output, name)
      && string.contains(output, command)
      && string.contains(output, "cepaf_gleam@harness@successor_mcp:main()")
      && list.all(expected_env, fn(pair) { string.contains(output, pair) })
    profiles.Agy | profiles.Gemini | profiles.Pi ->
      output == "UOS_TYPED_METADATA_EXACT"
  }
}

fn codex_entry_matches(
  output: String,
  name: String,
  command: String,
  expected_args: List(String),
  expected_env: List(String),
) -> Bool {
  case json.parse(output, value.decoder()) {
    Ok(record) -> {
      let name_ok = value.get(record, "name") == Ok(value.Text(name))
      let command_ok = value.get(record, "command") == Ok(value.Text(command))
      let args_ok = case value.get(record, "args") {
        Ok(value.Array(found)) -> string_array_equals(found, expected_args)
        _ -> False
      }
      let env_ok = case value.get(record, "env") {
        Ok(found) ->
          list.all(expected_env, fn(pair) {
            case string.split(pair, "=") {
              [key, expected] ->
                value.get(found, key) == Ok(value.Text(expected))
              _ -> False
            }
          })
        _ -> False
      }
      name_ok && command_ok && args_ok && env_ok
    }
    Error(_) -> False
  }
}

fn string_array_equals(
  found: List(value.Value),
  expected: List(String),
) -> Bool {
  list.length(found) == list.length(expected)
  && list.all(list.zip(found, expected), fn(pair) {
    pair.0 == value.Text(pair.1)
  })
}

pub fn action_admitted(action: String) -> Bool {
  action == "prepare" || action == "status" || action == "rollback"
}

pub fn metadata_lookup_supported(client: profiles.Client) -> Bool {
  case client {
    profiles.Agy
    | profiles.Gemini
    | profiles.Codex
    | profiles.Claude
    | profiles.Pi -> True
  }
}

pub fn permissions_allow(
  allowed_clients: List(String),
  allowed_actions: List(String),
  client: String,
  action: String,
) -> Bool {
  list.contains(allowed_clients, client)
  && list.contains(allowed_actions, action)
  && action_admitted(action)
}

fn field(args: value.Value, key: String) -> Result(String, String) {
  case value.get(args, key) {
    Ok(value.Text(text)) -> Ok(text)
    Ok(_) | Error(_) -> Error("string_field:" <> key)
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
    profiles.Agy -> [
      "mcp",
      "add",
      ..list.append(env_args(env), [owned_name, command, ..server_args])
    ]
    profiles.Gemini -> [
      "mcp",
      "add",
      "--scope",
      "user",
      ..list.append(env_args(env), [owned_name, command, ..server_args])
    ]
    profiles.Codex -> [
      "mcp",
      "add",
      owned_name,
      ..list.append(env_args(env), ["--", command, ..server_args])
    ]
    profiles.Claude -> [
      "mcp",
      "add",
      "--scope",
      "user",
      ..list.append(env_args(env), [owned_name, "--", command, ..server_args])
    ]
    profiles.Pi -> [
      "mcp",
      "add",
      owned_name,
      ..list.append(env_args(env), ["--", command, ..server_args])
    ]
  }
}

fn env_args(env: List(String)) -> List(String) {
  list.flatten(list.map(env, fn(item) { ["--env", item] }))
}

fn rollback_args(client: profiles.Client, owned_name: String) -> List(String) {
  case client {
    profiles.Agy | profiles.Codex -> ["mcp", "remove", owned_name]
    profiles.Gemini -> ["mcp", "remove", "--scope", "user", owned_name]
    profiles.Claude -> ["mcp", "remove", "--scope", "user", owned_name]
    profiles.Pi -> ["mcp", "remove", owned_name]
  }
}
