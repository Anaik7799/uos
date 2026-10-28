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
