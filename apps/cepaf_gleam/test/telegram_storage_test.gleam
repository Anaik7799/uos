import cepaf_gleam/harness/telegram_storage_report as storage
import cepaf_gleam/harness/telegram_ingress_guard as guard
import cepaf_gleam/harness/telegram_tool_command as tool
import cepaf_gleam/harness/observer_policy as obs
import gleam/bit_array
import gleam/list
import gleam/result
import gleam/string
import gleeunit/should

fn devices()->String {
 "{\"blockdevices\":[{\"name\":\"nvme0n1\",\"pkname\":null,\"type\":\"disk\",\"size\":2000,\"ro\":false,\"mountpoints\":[],\"serial\":\"25503L801736\"},{\"name\":\"nvme0n1p2\",\"pkname\":\"nvme0n1\",\"type\":\"part\",\"size\":1900,\"ro\":false,\"mountpoints\":[\"/\",\"/CANARY_PRIVATE\"],\"serial\":null},{\"name\":\"nvme1n1\",\"pkname\":null,\"type\":\"disk\",\"size\":2000,\"ro\":true,\"mountpoints\":[],\"serial\":\"CANARY_SERIAL\"}]}"
}
fn policy()->String {
 "{\"schema\":\"uos.storage.policy.v1\",\"status\":\"observed\",\"protected_id_configured\":true,\"checks\":{\"default_configuration_valid\":true,\"protected_path_denied\":true,\"protected_partition_denied\":true,\"protected_serial_denied\":true,\"missing_nvme_serial_denied\":true,\"renamed_root_path_denied\":true,\"ordinary_candidate_valid\":true},\"authority\":\"observation_only\",\"runtime_admission\":\"NOT_GRANTED\"}"
}
fn project(d:String,c:String,p:String) { storage.project(d,c,p,1000,1100) }
pub fn actual_scope_and_sensitive_fields_omitted_test() {
 let assert Ok(raw)=project(devices(),"Size Used Available\n1000 400 500\n",policy())
 list.each(["\"root_disk\":\"nvme0n1\"","\"root_serial_matches_protected\":true",
 "\"disk_count\":2","\"used_bytes\":400","\"available_bytes\":500",
 "\"policy_checks_passed\":true","NOT_ESTABLISHED","NOT_GRANTED","\"snapshot_atomic\":false"],
 fn(x){string.contains(raw,x) |> should.be_true})
 list.each(["25503L801736","CANARY"],fn(x){string.contains(raw,x) |> should.be_false})
}
pub fn failed_policy_is_visible_not_green_test() {
 let assert Ok(raw)=project(devices(),"h\n1000 400 500",string.replace(policy(),"\"protected_serial_denied\":true","\"protected_serial_denied\":false"))
 string.contains(raw,"\"policy_checks_passed\":false") |> should.be_true
 string.contains(raw,"\"protected_serial_denied\":false") |> should.be_true
}
pub fn missing_root_or_serial_is_unknown_test() {
 let assert Ok(absent)=project(string.replace(devices(),"\"/\",",""),"h\n1000 400 500",policy())
 string.contains(absent,"\"root_disk\":null") |> should.be_true
 let assert Ok(no_serial)=project(string.replace(devices(),"\"25503L801736\"","null"),"h\n1000 400 500",policy())
 string.contains(no_serial,"\"root_serial_matches_protected\":null") |> should.be_true
 let assert Ok(changed)=project(devices(),"h\n1000 400 500",string.replace(policy(),"\"protected_id_configured\":true","\"protected_id_configured\":false"))
 string.contains(changed,"\"root_serial_matches_protected\":null") |> should.be_true
 string.contains(changed,"\"policy_checks_passed\":false") |> should.be_true
}
pub fn topology_ambiguity_and_cycles_refused_test() {
 list.each([
 #("\"name\":\"nvme1n1\"","\"name\":\"nvme0n1\""),
 #("\"pkname\":\"nvme0n1\"","\"pkname\":\"missing\""),
 #("\"name\":\"nvme0n1\",\"pkname\":null","\"name\":\"nvme0n1\",\"pkname\":\"nvme0n1p2\""),
 #("\"mountpoints\":[]","\"mountpoints\":[\"/\"]"),
 #("\"size\":2000","\"size\":-1"),#("\"ro\":false","\"ro\":0"),
 #("\"serial\":\"CANARY_SERIAL\"","\"serial\":\"bad\\nserial\"")],fn(pair){
 project(string.replace(devices(),pair.0,pair.1),"h\n1000 400 500",policy()) |> result.is_error |> should.be_true
 })
}
pub fn malformed_capacity_policy_and_bounds_refused_test() {
 list.each(["h\n-1 0 0","h\n1000 800 500","h\n0 0 0","h\n1000 400","h\n1000 400 500\nextra","h\n1e3 0 0"],fn(df){
 project(devices(),df,policy()) |> result.is_error |> should.be_true
 })
 list.each(["{}","[]",string.replace(policy(),"\"ordinary_candidate_valid\":true","\"foreign\":true"),
 string.replace(policy(),"\"authority\":\"observation_only\"","\"authority\":\"granted\"")],fn(p){
 project(devices(),"h\n1000 400 500",p) |> result.is_error |> should.be_true
 })
 project(string.repeat("x",65537),"h\n1 0 0",policy()) |> result.is_error |> should.be_true
 storage.project(devices(),"h\n1 0 0",policy(),1000,999) |> result.is_error |> should.be_true
 storage.project(devices(),"h\n1 0 0",policy(),1000,6001) |> result.is_error |> should.be_true
}
pub fn command_and_alias_scope_test() {
 guard.classify_directive("/storage") |> should.equal(guard.DirectReadTool("query_storage"))
 guard.classify_directive("/nvme") |> should.equal(guard.DirectReadTool("query_storage"))
 tool.parse("query_storage {}") |> should.equal(Ok(tool.Storage))
 tool.parse("query_storage {\"path\":\"/private\"}") |> result.is_error |> should.be_true
 case guard.classify_directive("/storage wipe") {guard.DeniedMutation(_,_)->True _->False} |> should.be_true
}
pub fn receipt_failure_and_redaction_test() {
 let good=obs.Observation("child_exited","confirmed",0,bit_array.from_string("{}"))
 storage.receipt_payload(Ok(good),2) |> should.equal(Ok("{}"))
 list.each([obs.Observation(..good,child_exit:1),obs.Observation(..good,cleanup:"unconfirmed"),
 obs.Observation(..good,guardian_result:"deadline"),obs.Observation(..good,payload:<<255>>)],fn(r){
 storage.receipt_payload(Ok(r),2) |> result.is_error |> should.be_true
 })
 storage.receipt_payload(Ok(good),1) |> result.is_error |> should.be_true
 storage.receipt_payload(Error("CANARY"),2) |> should.equal(Error("storage_read_unavailable"))
}
