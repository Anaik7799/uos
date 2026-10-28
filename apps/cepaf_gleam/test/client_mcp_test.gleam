import cepaf_gleam/harness/client_mcp
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
