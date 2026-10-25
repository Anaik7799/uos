import cepaf_gleam/harness/telegram_ingress_guard as guard
import cepaf_gleam/harness/telegram_tool_command as tool
import gleeunit/should
pub fn command_and_tool_share_guard_test() {
  guard.classify_directive("/exec-brief") |> should.equal(guard.DirectReadTool("query_exec_brief"))
  guard.classify_directive("/tool query_exec_brief {}") |> should.equal(guard.DirectReadTool("query_exec_brief"))
  guard.classify_directive("/action query_exec_brief") |> should.equal(guard.DirectReadTool("query_exec_brief"))
}
pub fn scope_override_refused_test() {
  tool.parse("query_exec_brief {\"plan\":\"foreign\"}") |> should.be_error
  tool.parse("query_exec_brief {\"path\":\"/tmp/foreign\"}") |> should.be_error
  tool.parse("query_exec_brief []") |> should.be_error
  let assert guard.DeniedMutation(_,_) = guard.classify_directive("/exec-brief foreign")
  Nil
}
