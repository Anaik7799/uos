import cepaf_gleam/harness/admission as a
import cepaf_gleam/harness/client_mcp
import cepaf_gleam/harness/client_profiles as profiles
import cepaf_gleam/harness/development as dev
import cepaf_gleam/harness/value
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
