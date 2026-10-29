import gleam/string
import cepaf_gleam/harness/client_mcp
import cepaf_gleam/harness/client_profiles as profiles
import gleam/list
import gleeunit/should

pub fn only_fixed_configuration_actions_are_admitted_test() {
  client_mcp.action_admitted("prepare")
  |> should.be_true()
  client_mcp.action_admitted("status")
  |> should.be_true()
  client_mcp.action_admitted("rollback")
  |> should.be_true()
  client_mcp.action_admitted("delete-all")
  |> should.be_false()
}

pub fn client_and_action_scopes_default_deny_test() {
  client_mcp.permissions_allow([], [], "codex", "status")
  |> should.be_false()
  client_mcp.permissions_allow(["codex"], ["prepare"], "codex", "status")
  |> should.be_false()
  client_mcp.permissions_allow(["codex"], ["status"], "claude", "status")
  |> should.be_false()
  client_mcp.permissions_allow(["codex"], ["status"], "codex", "status")
  |> should.be_true()
}

pub fn every_client_has_a_nonlegacy_exact_metadata_path_test() {
  [profiles.Agy, profiles.Gemini, profiles.Codex, profiles.Claude, profiles.Pi]
  |> list.all(client_mcp.metadata_lookup_supported)
  |> should.be_true()
}

pub fn claude_entry_requires_structural_exact_json_test() {
  let name = "uos-gleam-dev-fixture"
  let command = "/fixture/erl"
  let args = ["-noinput", "-noshell"]
  let env = ["UOS_HARNESS_SESSION=session-fixture", "UOS_HARNESS_GRANT_SHA256=abc"]
  let exact =
    "{\"name\":\"uos-gleam-dev-fixture\",\"type\":\"stdio\",\"command\":\"/fixture/erl\",\"args\":[\"-noinput\",\"-noshell\"],\"env\":{\"UOS_HARNESS_SESSION\":\"session-fixture\",\"UOS_HARNESS_GRANT_SHA256\":\"abc\"}}"
  client_mcp.claude_entry_matches(exact, name, command, args, env)
  |> should.be_true()

  let wrong_name =
    string.replace(exact, "uos-gleam-dev-fixture", "uos-gleam-dev-fixture-shadow")
  client_mcp.claude_entry_matches(wrong_name, name, command, args, env)
  |> should.be_false()

  let extra_env =
    string.replace(exact, "\"UOS_HARNESS_SESSION\"", "\"UNRELATED\":\"extra\",\"UOS_HARNESS_SESSION\"")
  client_mcp.claude_entry_matches(extra_env, name, command, args, env)
  |> should.be_false()

  let unknown_field =
    string.replace(exact, "\"type\":\"stdio\"", "\"type\":\"stdio\",\"note\":\"uos-gleam-dev-fixture\"")
  client_mcp.claude_entry_matches(unknown_field, name, command, args, env)
  |> should.be_false()

  client_mcp.claude_entry_matches(
    "status includes uos-gleam-dev-fixture and /fixture/erl",
    name,
    command,
    args,
    env,
  )
  |> should.be_false()
}

pub fn agy_mcp_add_places_delimiter_before_command_and_flag_like_args_test() {
  let profile = profiles.profile_at(profiles.Agy, "/candidate")
  client_mcp.prepare_args(
    profiles.Agy,
    "uos-gleam-dev-test",
    profile.command,
    profile.args,
    ["UOS_HARNESS_TASK=SOURCE_FIX"],
  )
  |> should.equal([
    "mcp",
    "add",
    "--env",
    "UOS_HARNESS_TASK=SOURCE_FIX",
    "uos-gleam-dev-test",
    "--",
    profile.command,
    ..profile.args
  ])
}

pub fn codex_nested_transport_json_and_claude_name_before_env_test() {
  let name = "uos-gleam-dev-fixture"
  let command = "/fixture/erl"
  let args = ["-noinput", "-noshell"]
  let env = ["UOS_HARNESS_SESSION=session-fixture", "UOS_HARNESS_GRANT_SHA256=abc"]
  let codex_json =
    "{\"name\":\"uos-gleam-dev-fixture\",\"enabled\":true,\"disabled_reason\":null,\"transport\":{\"type\":\"stdio\",\"command\":\"/fixture/erl\",\"args\":[\"-noinput\",\"-noshell\"],\"env\":{\"UOS_HARNESS_SESSION\":\"session-fixture\",\"UOS_HARNESS_GRANT_SHA256\":\"abc\"},\"env_vars\":[],\"cwd\":null}}"
  client_mcp.codex_entry_matches(codex_json, name, command, args, env)
  |> should.be_true()

  let claude_profile = profiles.profile_at(profiles.Claude, "/candidate")
  client_mcp.prepare_args(
    profiles.Claude,
    "uos-gleam-dev-test",
    claude_profile.command,
    claude_profile.args,
    ["UOS_HARNESS_TASK=SOURCE_FIX"],
  )
  |> should.equal([
    "mcp",
    "add",
    "--scope",
    "user",
    "uos-gleam-dev-test",
    "--env",
    "UOS_HARNESS_TASK=SOURCE_FIX",
    "--",
    claude_profile.command,
    ..claude_profile.args
  ])
}
