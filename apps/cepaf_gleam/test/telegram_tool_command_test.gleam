import cepaf_gleam/harness/telegram_tool_command as tool
import gleam/list
import gleam/result
import gleam/string
import gleeunit/should

pub fn supported_reads_test() {
  tool.parse("") |> should.equal(Ok(tool.Help))
  tool.parse("help {}") |> should.equal(Ok(tool.Help))
  tool.parse("query_doctor") |> should.equal(Ok(tool.Doctor))
  tool.parse("query_saplan {}") |> should.equal(Ok(tool.Plan))
  tool.parse("query_task {\"task_id\":\"LEASE_1\"}") |> should.equal(Ok(tool.Task("LEASE_1")))
}

pub fn whitespace_preserves_json_test() {
  tool.parse(" \tquery_doctor\t{\n }\n") |> should.equal(Ok(tool.Doctor))
  tool.parse("query_task\n{\"task_id\":\"a/b-1\"}") |> should.equal(Ok(tool.Task("a/b-1")))
  tool.parse("query_task {\"task_id\":\"a\\tb\"}") |> result.is_error |> should.be_true
}

pub fn strict_empty_arguments_test() {
  list.each(["query_doctor []", "query_saplan null", "help false",
    "help {\"force\":true}", "query_doctor {\"path\":\"x\"}",
    "query_saplan {} trailing", "query_doctor {", "help query_doctor"], fn(args) {
    tool.parse(args) |> result.is_error |> should.be_true
  })
}

pub fn strict_task_shape_test() {
  list.each(["", "{}", "[]", "null", "{\"task_id\":1}",
    "{\"task_id\":\"\"}", "{\"task_id\":\"a\",\"plan\":\"b\"}",
    "{\"task_id\":\"a\",\"authority\":\"admin\"}", "{\"other\":\"a\"}",
    "{\"task_id\":\" a\"}", "{\"task_id\":\"a \"}", "{\"task_id\":\"x;DROP\"}"], fn(args) {
    tool.parse("query_task " <> args) |> result.is_error |> should.be_true
  })
}

pub fn control_and_bound_refusal_test() {
  list.each(["query_doctor\u{0}", "query_doctor\r{}", "help\u{7f}",
    "query_task " <> string.repeat("x", 1025),
    "query_doctor {" <> string.repeat(" ",256) <> "}",
    string.repeat("x",2049)], fn(args) {
    tool.parse(args) |> result.is_error |> should.be_true
  })
}

pub fn no_echo_or_authority_test() {
  let assert Error(reason) = tool.parse("CANARY_PRIVATE_TOOL {}")
  string.contains(reason, "CANARY") |> should.be_false
  list.each(["rotate_keys {}", "invoke_zigvm {}", "resuscitate_node {}"], fn(args) {
    tool.parse(args) |> result.is_error |> should.be_true
  })
  string.contains(tool.help(), "configured plan only") |> should.be_true
  string.contains(tool.help(), "/action") |> should.be_true
}

pub fn cancellation_grammar_test() {
 tool.parse("cancel_job_lease p/job-1 -- Operator requested cancellation") |> should.equal(Ok(tool.CancelLease("p/job-1","Operator requested cancellation")))
 list.each(["cancel_job_lease", "cancel_job_lease p/job", "cancel_job_lease ../job -- reason", "cancel_job_lease p/job -- ", "cancel_job_lease p/job -- a -- b", "cancel_job_lease p/job --  reason", "cancel_job_lease p/job;DROP -- reason", "cancel_job_lease p/job -- " <> string.repeat("x",257)],fn(s){tool.parse(s) |> should.be_error})
}


pub fn ha_direct_tool_scope_test() {
  assert tool.parse("query_ha {}") == Ok(tool.Ha)
  let assert Error(_) = tool.parse("query_ha {\"host\":\"other\"}")
}

pub fn finops_tool_exact_scope_test() {
 assert tool.parse("query_finops {}")==Ok(tool.Finops)
 assert tool.parse("query_finops")==Ok(tool.Finops)
 list.each(["[]","null","true","0","\"\"","{} trailing","{\"day\":\"tomorrow\"}"],fn(a){tool.parse("query_finops "<>a) |> should.be_error})
}
