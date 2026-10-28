//// Finite public launch profiles for native MCP clients.
//// These profiles describe the UOS server only; they never import a user's
//// existing server configuration or accept arbitrary commands/paths.

import gleam/list

pub type Client {
  Agy
  Gemini
  Codex
  Claude
  Pi
}

pub type Profile {
  Profile(
    client: Client,
    server_name: String,
    command: String,
    args: List(String),
    env_names: List(String),
    configuration_mode: String,
  )
}

pub fn parse_client(text: String) -> Result(Client, String) {
  case text {
    "agy" -> Ok(Agy)
    "gemini" -> Ok(Gemini)
    "codex" -> Ok(Codex)
    "claude" -> Ok(Claude)
    "pi" -> Ok(Pi)
    _ -> Error("client_not_admitted")
  }
}

pub fn name(client: Client) -> String {
  case client {
    Agy -> "agy"
    Gemini -> "gemini"
    Codex -> "codex"
    Claude -> "claude"
    Pi -> "pi"
  }
}

/// Fixed stdio server invocation. The grant path and digest are inherited from
/// the task-scoped environment of the particular client session.
pub fn profile(client: Client) -> Profile {
  profile_at(client, "/home/an/NAS-setup/uos")
}

/// Binds the stdio module path to the candidate root already approved by the
/// loaded grant. `source_root` validates the exact workspace; this function
/// never discovers or accepts a caller-selected filesystem path.
pub fn profile_at(client: Client, source_root: String) -> Profile {
  Profile(
    client,
    "uos-gleam-dev-",
    "/home/an/NAS-setup/uos/toolchains/nix-profile/bin/erl",
    [
      "+S",
      "2:2",
      "+A",
      "2",
      "-noshell",
      "-eval",
      "code:add_paths(filelib:wildcard(\""
        <> source_root
        <> "/apps/cepaf_gleam/build/dev/erlang/*/ebin\")), cepaf_gleam@harness@successor_mcp:main(), halt(0).",
    ],
    [
      "UOS_HARNESS_GRANT_PATH",
      "UOS_HARNESS_GRANT_SHA256",
      "UOS_HARNESS_ROLE",
      "UOS_HARNESS_PLAN",
      "UOS_HARNESS_TASK",
      "UOS_HARNESS_WORKER",
      "UOS_HARNESS_ATTEMPT",
      "UOS_HARNESS_SESSION",
      "UOS_HARNESS_EPOCH",
    ],
    configuration_mode(client),
  )
}

fn configuration_mode(client: Client) -> String {
  case client {
    Agy -> "agy mcp add/list/remove; one named server entry"
    Gemini -> "--allowed-mcp-server-names with one named server"
    Codex -> "per-run -c mcp_servers.uos-gleam-development.*"
    Claude -> "--strict-mcp-config with one server JSON"
    Pi -> "per-run --extension with filtered MCP SDK extension"
  }
}

pub fn all() -> List(Profile) {
  list.map([Agy, Gemini, Codex, Claude, Pi], profile)
}
