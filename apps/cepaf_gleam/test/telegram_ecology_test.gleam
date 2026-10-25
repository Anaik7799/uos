import cepaf_gleam/harness/telegram_ecology_report as report
import cepaf_gleam/harness/telegram_ingress_guard as guard
import cepaf_gleam/harness/telegram_tool_command as tool
import gleam/list
import gleam/result
import gleam/string
import gleeunit/should

fn fixture()->String {
 "{\"epoch_us\":100000000,\"cycle_counter\":7,\"total_holons\":1,\"participant_kind\":\"local_agentic_model\",\"hosting\":\"one_shared_ecology_actor\",\"external_system_binding\":false,\"is_harmonic\":true,\"holons\":[{\"id\":\"indrajaal\",\"participant_kind\":\"local_agentic_model\",\"external_system_binding\":false,\"plane\":\"control\",\"level\":0,\"lifecycle\":\"active\",\"mode\":\"observe\",\"secret\":\"CANARY\"}],\"service_andon\":[{\"capability\":\"max\",\"phase\":\"ready\",\"reason\":\"CANARY\",\"failure_count\":0,\"recovery_attempts\":1,\"recovery_count\":1,\"last_failure\":null,\"last_recovery\":{\"observed_at_us\":1000,\"private\":\"CANARY\"}}],\"receipts\":[\"CANARY\"],\"song\":{\"private\":\"CANARY\"}}"
}
pub fn bounded_observation_preserves_scope_test() {
 let assert Ok(raw)=report.project(fixture(),100000)
 string.contains(raw,"\"schema\":\"uos.telegram.ecology.v1\"") |> should.be_true
 string.contains(raw,"\"service_health\":\"UNVERIFIED\"") |> should.be_true
 string.contains(raw,"NOT_GRANTED") |> should.be_true
 string.contains(raw,"CANARY") |> should.be_false
 string.contains(raw,"\"last_recovery_at_us\":1000") |> should.be_true
 string.contains(raw,"\"freshness\":\"fresh\"") |> should.be_true
}
pub fn freshness_boundaries_test() {
 let assert Ok(fresh)=report.project(fixture(),130000)
 let assert Ok(stale)=report.project(fixture(),130001)
 let assert Ok(future)=report.project(fixture(),99999)
 string.contains(fresh,"\"freshness\":\"fresh\"") |> should.be_true
 string.contains(stale,"\"freshness\":\"stale\"") |> should.be_true
 string.contains(future,"\"freshness\":\"future\"") |> should.be_true
 string.contains(future,"\"snapshot_age_ms\":null") |> should.be_true
 report.project(fixture(),0) |> result.is_error |> should.be_true
}
pub fn malformed_or_oversized_refused_test() {
 list.each(["{}","[]","null",string.repeat("x",131073)],fn(raw){report.project(raw,100000) |> result.is_error |> should.be_true})
}
pub fn contradictory_participant_scope_refused_test() {
 list.each([#("\"total_holons\":1","\"total_holons\":2"),
   #("\"external_system_binding\":false","\"external_system_binding\":true"),
   #("\"local_agentic_model\"","\"external_agent\""),
   #("\"one_shared_ecology_actor\"","\"unknown\""),
   #("\"epoch_us\":100000000","\"epoch_us\":0"),
   #("\"cycle_counter\":7","\"cycle_counter\":-1"),
   #("\"level\":0","\"level\":10"),
   #("\"failure_count\":0","\"failure_count\":-1"),
   #("\"observed_at_us\":1000","\"observed_at_us\":0"),
   #("\"phase\":\"ready\"","\"phase\":\"bad\\nphase\""),
   #("\"id\":\"indrajaal\"","\"id\":\"../../etc\"")],fn(pair){
    report.project(string.replace(fixture(),pair.0,pair.1),100000) |> result.is_error |> should.be_true
 })
}
pub fn fixed_command_scope_test() {
 guard.classify_directive("/ecology") |> should.equal(guard.DirectReadTool("query_ecology"))
 tool.parse("query_ecology {}") |> should.equal(Ok(tool.Ecology))
 tool.parse("query_ecology {\"url\":\"http://evil/\"}") |> result.is_error |> should.be_true
 case guard.classify_directive("/ecology foreign") {
   guard.DeniedMutation(_,_) -> True
   _ -> False
 } |> should.be_true
}

pub fn duplicate_identity_and_boundaries_refused_test() {
 let h="{\"id\":\"one\",\"participant_kind\":\"local_agentic_model\",\"external_system_binding\":false,\"plane\":\"control\",\"level\":0,\"lifecycle\":\"active\",\"mode\":\"observe\"}"
 let prefix="{\"epoch_us\":100000000,\"cycle_counter\":7,\"total_holons\":2,\"participant_kind\":\"local_agentic_model\",\"hosting\":\"one_shared_ecology_actor\",\"external_system_binding\":false,\"is_harmonic\":true,"
 report.project(prefix<>"\"holons\":["<>h<>","<>h<>"],\"service_andon\":[]}",100000)
 |> result.is_error |> should.be_true
 list.each([#("\"total_holons\":1","\"total_holons\":129"),
   #("\"last_failure\":null","\"last_failure\":{}"),
   #("\"is_harmonic\":true","\"is_harmonic\":1"),
   #("\"failure_count\":0","\"failure_count\":9007199254740992"),
   #("\"mode\":\"observe\"","\"mode\":\""<> string.repeat("x",65) <>"\"")],fn(pair){
    report.project(string.replace(fixture(),pair.0,pair.1),100000) |> result.is_error |> should.be_true
 })
}
pub fn submillisecond_future_is_not_fresh_test() {
 let assert Ok(raw)=report.project(string.replace(fixture(),"100000000","100000001"),100000)
 string.contains(raw,"\"freshness\":\"future\"") |> should.be_true
}

pub fn top_level_binding_is_checked_independently_test() {
 let changed=string.replace(fixture(),"\"hosting\":\"one_shared_ecology_actor\",\"external_system_binding\":false","\"hosting\":\"one_shared_ecology_actor\",\"external_system_binding\":true")
 report.project(changed,100000) |> result.is_error |> should.be_true
}
