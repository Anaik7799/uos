import cepaf_gleam/harness/admission as a
import cepaf_gleam/harness/client_mcp
import cepaf_gleam/harness/client_profiles as profiles
import cepaf_gleam/harness/development as dev
import cepaf_gleam/harness/operations as ops
import cepaf_gleam/harness/value
import gleam/json
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

pub fn agy_mcp_add_places_delimiter_before_command_and_flag_like_args_test() {
  let profile = profiles.profile_at(profiles.Agy, "/candidate")
  client_mcp.prepare_args(
    profiles.Agy,
    "uos-gleam-dev-test",
    profile.command,
    profile.args,
    ["UOS_HARNESS_TASK=CLIENT_PARITY"],
  )
  |> should.equal([
    "mcp",
    "add",
    "--env",
    "UOS_HARNESS_TASK=CLIENT_PARITY",
    "uos-gleam-dev-test",
    "--",
    profile.command,
    ..profile.args
  ])
}

pub fn agy_profile_runner_rejects_caller_selected_command_and_home_test() {
  dev.bounded_profile("/bin/true", [], "/tmp", 100)
  |> should.equal(Error("agy_profile_isolation_refused"))
}

pub fn empty_client_permissions_deny_before_native_dispatch_test() {
  let scope =
    a.Scope(
      "uos/test/20261028",
      "CLIENT_PARITY",
      [],
      [],
      ["AGENTS.md"],
      ["client_mcp_test"],
      "var/harness/20261028-0323-current-risk.json",
      [],
      [],
    )
  let grant =
    a.Grant(
      "20261028-test-client",
      "var/harness/20261028-test-client-grant.json",
      "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      "test-client-session",
      "test-client-worker",
      "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      "test-boot",
      1_793_160_000_000_000,
      [scope],
      "",
      "docs/reviews/20261028-test-client-review.json",
      "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
    )
  let binding =
    dev.Binding(
      "development",
      scope.plan,
      scope.task,
      grant.worker,
      1,
      grant.session,
      1,
    )
  let execution = a.Execution(grant, scope, binding, scope.portfolio)
  let args =
    value.Object([
      #("intent_id", value.Text("client-config-deny")),
      #("client", value.Text("codex")),
      #("action", value.Text("prepare")),
    ])
  client_mcp.perform(execution, args, 1000)
  |> should.equal(Error("client_or_action_permission_denied"))
}

pub fn assessment_evidence_accepts_scoped_public_candidate_manifest_test() {
  let manifest =
    "governance/planning/20261028-0530-client-parity-candidate-manifest.json"
  let grant = assessment_grant([manifest, "AGENTS.md"])
  ops.assessment_paths_allowed(grant, evidence_body(manifest))
  |> should.equal(Ok(Nil))
}

pub fn assessment_evidence_rejects_candidate_absolute_workspace_prefix_test() {
  let grant = assessment_grant(["AGENTS.md"])
  ops.assessment_paths_allowed(
    grant,
    evidence_body(
      ".uos-workspaces/client-parity-20261028-0321/apps/cepaf_gleam/src/cepaf_gleam/harness/client_mcp.gleam",
    ),
  )
  |> should.equal(Error("assessment_source_outside_grant"))
}

fn assessment_grant(reads: List(String)) -> a.Grant {
  let scope =
    a.Scope(
      "uos/development-harness/20261028-0105",
      "CLIENT_PARITY",
      reads,
      [],
      ["AGENTS.md"],
      ["client_mcp_test"],
      "var/harness/20261028-0530-codex-client-parity-current-risk.json",
      ["agy"],
      ["prepare", "status", "rollback"],
    )
  a.Grant(
    "20261028-0530-client-v3-01a1802b",
    "var/harness/20261028-0530-client-v3-grant.json",
    "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    "01a1802b-0ee7-7822-b734-42b95dc5515f",
    "codex-client-parity-01a1802b",
    "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    "test-boot",
    1_793_172_300_000_000,
    [scope],
    ".uos-workspaces/client-parity-20261028-0321",
    "docs/reviews/20261028-0530-client-parity-grant-review-v3.json",
    "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
  )
}

fn evidence_body(path: String) -> String {
  value.Array([
    value.Object([
      #(
        "snapshot",
        value.Object([
          #(
            "evidence",
            value.Array([value.Object([#("path", value.Text(path))])]),
          ),
        ]),
      ),
    ]),
  ])
  |> value.encode
  |> json.to_string
}
