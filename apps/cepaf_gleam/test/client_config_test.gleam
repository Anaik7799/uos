import gleam/list
import cepaf_gleam/harness/client_config
import cepaf_gleam/harness/client_profiles as profiles
import cepaf_gleam/harness/value
import gleam/json
import gleam/string
import gleeunit/should

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

pub fn agy_disabled_false_is_the_only_extra_allowed_entry_field_test() {
  let args = ["-noshell", "cepaf_gleam@harness@successor_mcp:main()"]
  let disabled_false =
    string.replace(
      fixture(),
      "\"command\":\"/fixture/erl\"",
      "\"command\":\"/fixture/erl\",\"disabled\":false",
    )
  client_config.inspect_json(
    profiles.Agy,
    "uos-gleam-dev-fixture",
    disabled_false,
    "/fixture/erl",
    args,
    expected_env(),
  )
  |> should.equal(Ok(client_config.Exact))

  client_config.inspect_json(
    profiles.Gemini,
    "uos-gleam-dev-fixture",
    disabled_false,
    "/fixture/erl",
    args,
    expected_env(),
  )
  |> should.equal(Ok(client_config.Conflict))

  let disabled_true =
    string.replace(disabled_false, "\"disabled\":false", "\"disabled\":true")
  client_config.inspect_json(
    profiles.Agy,
    "uos-gleam-dev-fixture",
    disabled_true,
    "/fixture/erl",
    args,
    expected_env(),
  )
  |> should.equal(Ok(client_config.Conflict))

  let disabled_text =
    string.replace(disabled_false, "\"disabled\":false", "\"disabled\":\"false\"")
  client_config.inspect_json(
    profiles.Agy,
    "uos-gleam-dev-fixture",
    disabled_text,
    "/fixture/erl",
    args,
    expected_env(),
  )
  |> should.equal(Ok(client_config.Conflict))
}

pub fn agy_private_profile_parser_accepts_only_its_single_owned_entry_test() {
  let profile = profiles.profile_at(profiles.Agy, "/candidate")
  let env =
    value.Object(
      list.map(expected_env(), fn(pair) {
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
      #("disabled", value.Boolean(False)),
    ])
  let one_server =
    value.Object([
      #("mcpServers", value.Object([#("uos-gleam-dev-fixture", entry)])),
    ])
    |> value.encode
    |> json.to_string
  client_config.inspect_agy_profile_json(
    one_server,
    "uos-gleam-dev-fixture",
    profile.command,
    profile.args,
    expected_env(),
  )
  |> should.equal(Ok(client_config.Exact))

  let two_servers =
    value.Object([
      #(
        "mcpServers",
        value.Object([
          #("uos-gleam-dev-fixture", entry),
          #("legacy", entry),
        ]),
      ),
    ])
    |> value.encode
    |> json.to_string
  client_config.inspect_agy_profile_json(
    two_servers,
    "uos-gleam-dev-fixture",
    profile.command,
    profile.args,
    expected_env(),
  )
  |> should.equal(Error("agy_profile_has_unexpected_servers"))
}

pub fn agy_private_profile_helpers_reject_traversal_ids_without_io_test() {
  client_config.agy_profile_path("../outside")
  |> should.equal(Error("agy_private_profile_path_unavailable"))
  client_config.agy_profile_root("../outside")
  |> should.equal(Error("agy_private_profile_unavailable"))
  client_config.cleanup_agy_profile("../outside")
  |> should.equal(Error("agy_private_profile_cleanup_failed"))
}
