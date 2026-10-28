import cepaf_gleam/harness/client_config
import cepaf_gleam/harness/client_profiles as profiles
import cepaf_gleam/harness/value
import gleam/json
import gleam/list
import gleam/string
import gleeunit/should
import simplifile

const session = "session-fixture"

const grant_sha = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

const fake_private_value = "FAKE_PRIVATE_CREDENTIAL_MUST_NEVER_ESCAPE"

fn fixture() -> String {
  let owned =
    value.Object([
      #("command", value.Text("/fixture/erl")),
      #(
        "args",
        value.Array([
          value.Text("-noshell"),
          value.Text("cepaf_gleam@harness@successor_mcp:main()"),
        ]),
      ),
      #(
        "env",
        value.Object([
          #("UOS_HARNESS_SESSION", value.Text(session)),
          #("UOS_HARNESS_GRANT_SHA256", value.Text(grant_sha)),
        ]),
      ),
    ])
  let legacy =
    value.Object([
      #("command", value.Text("legacy-server")),
      #("args", value.Array([])),
      #("env", value.Object([#("API_TOKEN", value.Text(fake_private_value))])),
    ])
  value.Object([
    #(
      "mcpServers",
      value.Object([
        #("uos-gleam-dev-fixture", owned),
        #("legacy", legacy),
      ]),
    ),
  ])
  |> value.encode
  |> json.to_string
}

fn expected_env() -> List(String) {
  [
    "UOS_HARNESS_SESSION=" <> session,
    "UOS_HARNESS_GRANT_SHA256=" <> grant_sha,
  ]
}

fn agy_expected_env() -> List(String) {
  [
    "UOS_HARNESS_GRANT_PATH=var/harness/fake-grant.json",
    "UOS_HARNESS_GRANT_SHA256=" <> grant_sha,
    "UOS_HARNESS_ROLE=development",
    "UOS_HARNESS_PLAN=uos/development-harness/20261028-0105",
    "UOS_HARNESS_TASK=CLIENT_PARITY",
    "UOS_HARNESS_WORKER=codex-client-parity-fixture",
    "UOS_HARNESS_ATTEMPT=1",
    "UOS_HARNESS_SESSION=session-fixture",
    "UOS_HARNESS_EPOCH=2",
    "ERL_CRASH_DUMP_SECONDS=0",
  ]
}

fn agy_native_fixture(disabled: value.Value) -> String {
  let profile = profiles.profile_at(profiles.Agy, "/candidate")
  let env =
    value.Object(
      list.map(agy_expected_env(), fn(pair) {
        case string.split(pair, "=") {
          [key, text] -> #(key, value.Text(text))
          _ -> #("invalid", value.Null)
        }
      }),
    )
  let entry =
    value.Object([
      #("command", value.Text(profile.command)),
      #("args", value.Array(list.map(profile.args, value.Text))),
      #("env", env),
      #("disabled", disabled),
    ])
  value.Object([
    #("mcpServers", value.Object([#("uos-gleam-dev-fixture", entry)])),
  ])
  |> value.encode
  |> json.to_string
}

pub fn unrelated_private_values_do_not_escape_metadata_receipts_test() {
  let observed =
    client_config.inspect_json(
      profiles.Pi,
      "uos-gleam-dev-fixture",
      fixture(),
      "/fixture/erl",
      ["-noshell", "cepaf_gleam@harness@successor_mcp:main()"],
      expected_env(),
    )
  observed
  |> should.equal(Ok(client_config.Exact))
  let receipt = client_config.observation_label(client_config.Exact)
  string.contains(receipt, fake_private_value)
  |> should.be_false()
  receipt
  |> should.equal("exact")
}

pub fn exact_owned_entry_distinguishes_missing_and_conflict_test() {
  client_config.inspect_json(
    profiles.Agy,
    "absent-server",
    fixture(),
    "/fixture/erl",
    ["-noshell", "cepaf_gleam@harness@successor_mcp:main()"],
    expected_env(),
  )
  |> should.equal(Ok(client_config.Missing))
  client_config.inspect_json(
    profiles.Gemini,
    "uos-gleam-dev-fixture",
    fixture(),
    "/different/erl",
    ["-noshell", "cepaf_gleam@harness@successor_mcp:main()"],
    expected_env(),
  )
  |> should.equal(Ok(client_config.Conflict))
}

pub fn unexpected_owned_entry_fields_fail_closed_test() {
  let malformed =
    string.replace(
      fixture(),
      "\"command\":\"/fixture/erl\"",
      "\"command\":\"/fixture/erl\",\"credential\":\"fake\"",
    )
  client_config.inspect_json(
    profiles.Pi,
    "uos-gleam-dev-fixture",
    malformed,
    "/fixture/erl",
    ["-noshell", "cepaf_gleam@harness@successor_mcp:main()"],
    expected_env(),
  )
  |> should.equal(Ok(client_config.Conflict))
}

pub fn json_byte_and_depth_bounds_fail_closed_test() {
  client_config.bounded_json(string.repeat("x", 262_145))
  |> should.be_false()
  client_config.bounded_json(string.repeat("[", 33) <> string.repeat("]", 33))
  |> should.be_false()
  client_config.bounded_json(fixture())
  |> should.be_true()
}

pub fn agy_private_profile_accepts_only_the_single_owned_server_test() {
  client_config.inspect_agy_profile_json(
    "{\"mcpServers\":{\"uos-gleam-dev-fixture\":{\"command\":\"/fixture/erl\",\"args\":[\"-noshell\",\"cepaf_gleam@harness@successor_mcp:main()\"],\"env\":{\"UOS_HARNESS_SESSION\":\"session-fixture\",\"UOS_HARNESS_GRANT_SHA256\":\"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef\"}}}}",
    "uos-gleam-dev-fixture",
    "/fixture/erl",
    ["-noshell", "cepaf_gleam@harness@successor_mcp:main()"],
    expected_env(),
  )
  |> should.equal(Ok(client_config.Exact))
  client_config.inspect_agy_profile_json(
    fixture(),
    "uos-gleam-dev-fixture",
    "/fixture/erl",
    ["-noshell", "cepaf_gleam@harness@successor_mcp:main()"],
    expected_env(),
  )
  |> should.equal(Error("agy_profile_has_unexpected_servers"))
}

pub fn agy_native_disabled_false_entry_and_all_grant_environment_fields_are_exact_test() {
  let profile = profiles.profile_at(profiles.Agy, "/candidate")
  client_config.inspect_agy_profile_json(
    agy_native_fixture(value.Boolean(False)),
    "uos-gleam-dev-fixture",
    profile.command,
    profile.args,
    agy_expected_env(),
  )
  |> should.equal(Ok(client_config.Exact))
}

pub fn agy_profile_disabled_true_nonboolean_and_unknown_fields_fail_closed_test() {
  let profile = profiles.profile_at(profiles.Agy, "/candidate")
  let base = agy_native_fixture(value.Boolean(False))
  client_config.inspect_agy_profile_json(
    agy_native_fixture(value.Boolean(True)),
    "uos-gleam-dev-fixture",
    profile.command,
    profile.args,
    agy_expected_env(),
  )
  |> should.equal(Ok(client_config.Conflict))
  client_config.inspect_agy_profile_json(
    string.replace(base, "\"disabled\":false", "\"disabled\":\"false\""),
    "uos-gleam-dev-fixture",
    profile.command,
    profile.args,
    agy_expected_env(),
  )
  |> should.equal(Ok(client_config.Conflict))
  client_config.inspect_agy_profile_json(
    string.replace(
      base,
      "\"disabled\":false",
      "\"disabled\":false,\"unknown\":true",
    ),
    "uos-gleam-dev-fixture",
    profile.command,
    profile.args,
    agy_expected_env(),
  )
  |> should.equal(Ok(client_config.Conflict))
}

pub fn agy_profile_changed_args_or_environment_fail_closed_test() {
  let profile = profiles.profile_at(profiles.Agy, "/candidate")
  let body = agy_native_fixture(value.Boolean(False))
  client_config.inspect_agy_profile_json(
    body,
    "uos-gleam-dev-fixture",
    profile.command,
    list.append(profile.args, ["unexpected-arg"]),
    agy_expected_env(),
  )
  |> should.equal(Ok(client_config.Conflict))
  client_config.inspect_agy_profile_json(
    body,
    "uos-gleam-dev-fixture",
    profile.command,
    profile.args,
    list.append(agy_expected_env(), ["EXTRA=value"]),
  )
  |> should.equal(Ok(client_config.Conflict))
}

pub fn cleanup_agy_profile_success_returns_gleam_ok_and_removes_private_tree_test() {
  let grant_id = "fixture-cleanup-parity"
  let assert Ok(root) = client_config.agy_profile_path(grant_id)
  case simplifile.is_directory(root) {
    Ok(True) -> client_config.cleanup_agy_profile(grant_id) |> should.be_ok
    _ -> Nil
  }
  let assert Ok(Nil) = simplifile.create_directory_all(root)
  let assert Ok(Nil) = simplifile.set_permissions_octal(root, 0o700)
  let marker = root <> "/synthetic-fixture"
  let assert Ok(Nil) = simplifile.write(marker, fake_private_value)

  client_config.cleanup_agy_profile(grant_id)
  |> should.equal(Ok(Nil))
  simplifile.is_directory(root)
  |> should.equal(Ok(False))
}

pub fn cleanup_agy_profile_missing_and_invalid_targets_fail_closed_test() {
  client_config.cleanup_agy_profile("fixture-cleanup-absent")
  |> should.equal(Error("agy_private_profile_cleanup_failed"))
  client_config.cleanup_agy_profile("../outside")
  |> should.equal(Error("agy_private_profile_cleanup_failed"))
}
