import cepaf_gleam/harness/client_profiles as profiles
import gleam/list
import gleam/result
import gleeunit/should

pub fn admits_only_named_clients_test() {
  ["agy", "gemini", "codex", "claude", "pi"]
  |> list.all(fn(client) { result.is_ok(profiles.parse_client(client)) })
  |> should.be_true()
  profiles.parse_client("unknown")
  |> result.is_error
  |> should.be_true()
}

pub fn every_profile_uses_one_fixed_stdio_server_test() {
  profiles.all()
  |> list.all(fn(profile) {
    profile.server_name == "uos-gleam-dev-"
    && profile.command
    == "/home/an/NAS-setup/uos/toolchains/nix-profile/bin/erl"
    && profile.args != []
    && list.contains(profile.env_names, "UOS_HARNESS_GRANT_PATH")
    && list.contains(profile.env_names, "UOS_HARNESS_GRANT_SHA256")
    && list.contains(profile.env_names, "ERL_CRASH_DUMP_SECONDS")
    && list.contains(profile.args, "-noinput")
  })
  |> should.be_true()
}

pub fn profiles_are_named_for_distinct_client_modes_test() {
  profiles.all()
  |> list.map(fn(profile) { profile.configuration_mode })
  |> list.unique
  |> list.length
  |> should.equal(5)
}

pub fn stdio_module_path_uses_approved_source_root_test() {
  let eval = case
    list.last(profiles.profile_at(profiles.Codex, "/reviewed/workspace").args)
  {
    Ok(text) -> text
    Error(_) -> "missing_eval"
  }
  eval
  |> should.equal(
    "code:add_paths(filelib:wildcard(\"/reviewed/workspace/apps/cepaf_gleam/build/dev/erlang/*/ebin\")), cepaf_gleam@harness@successor_mcp:main(), halt(0).",
  )
}
