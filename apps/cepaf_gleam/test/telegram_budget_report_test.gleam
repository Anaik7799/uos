import cepaf_gleam/harness/telegram_budget_report as r
import gleam/json
import gleam/list
import gleam/string
import gleeunit/should

const at=1_700_000_000_000_000
const ledger="/home/an/NAS-setup/uos/var/ecology/openrouter_budget.sqlite3"
pub fn fixture(count:Int)->String {
 json.object([
 #("status",json.string("status")),#("dispatch_authorized",json.bool(False)),#("task_authority",json.bool(False)),
 #("budget_scope",json.string("this_database_only")),#("ledger_path",json.string(ledger)),
 #("call_id",json.null()),#("utc_day",json.string("2023-11-14")),#("observed_us",json.int(at)),
 #("reservation_nanodollars",json.int(250_000_000)),#("daily_limit_nanodollars",json.int(10_000_000_000)),
 #("daily_reserved_nanodollars",json.int(count*250_000_000)),#("remaining_nanodollars",json.int(10_000_000_000-count*250_000_000)),
 #("reservation_count",json.int(count)),#("actual_spend_nanodollars",json.null()),#("refunds_supported",json.bool(False))
 ]) |> json.to_string
}
pub fn observed_empty_reserved_and_exhausted_test() {
 list.each([0,1,40],fn(n){
 let assert Ok(raw)=r.project(fixture(n),ledger,at-1000,at+1000)
 assert string.contains(raw,"\"status\":\"observed\"")
 assert string.contains(raw,"\"actual_spend_nanodollars\":null")
 assert !string.contains(raw,ledger)
 assert !string.contains(raw,"call_id")
 })
}
pub fn rejects_false_authority_and_spend_test(){
 list.each([#("\"dispatch_authorized\":false","\"dispatch_authorized\":true"),
 #("\"task_authority\":false","\"task_authority\":true"),
 #("\"actual_spend_nanodollars\":null","\"actual_spend_nanodollars\":0"),
 #("\"refunds_supported\":false","\"refunds_supported\":true"),
 #("\"call_id\":null","\"call_id\":\"private\"")],fn(pair){
 r.project(string.replace(fixture(1),pair.0,pair.1),ledger,at-1,at+1) |> should.be_error
 })
}
pub fn rejects_arithmetic_and_scope_test(){
 list.each([#("9750000000","10000000000"),#("250000000","250000001"),
 #("this_database_only","whole_account"),#("\"reservation_count\":1","\"reservation_count\":1.0"),
 #("\"status\":\"status\"","\"status\":\"reserved\""),#("2023-11-14","2023-11-15")],fn(pair){
 r.project(string.replace(fixture(1),pair.0,pair.1),ledger,at-1,at+1) |> should.be_error
 })
 r.project(fixture(-1),ledger,at-1,at+1) |> should.be_error
 r.project(fixture(41),ledger,at-1,at+1) |> should.be_error
 r.project(fixture(1),ledger<>"foreign",at-1,at+1) |> should.be_error
}
pub fn rejects_clock_regression_future_stale_and_midnight_test(){
 list.each([#(at+1,at+2),#(at-2,at-1),#(at+1,at-1),#(at-1,at+5_000_000),#(0,at)],fn(t){
 r.project(fixture(1),ledger,t.0,t.1) |> should.be_error
 })
 // A fresh observation just before UTC midnight is not today's budget after rollover.
 let raw=string.replace(fixture(1),"1700000000000000","1700006399999999")
 r.project(raw,ledger,1_700_006_399_999_998,1_700_006_400_000_001) |> should.be_error
}
pub fn rejects_missing_extra_malformed_and_large_envelopes_test(){
 list.each(["{}","[]","null",fixture(1)<>" trailing",
 string.replace(fixture(1),"{","{\"extra\":0,"),string.repeat("x",8193)],fn(raw){
 r.project(raw,ledger,at-1,at+1) |> should.be_error
 })
}
pub fn trusted_source_scope_test(){
 let prod=r.Source("/home/an/NAS-setup/uos/var/releases/budget/ecology_budget.exe",string.repeat("a",64),ledger)
 assert r.valid_source(prod,False)
 let private=r.Source(..prod,executable:"/home/an/NAS-setup/uos/var/recovery-runtime/test/ecology_budget.exe",ledger:"/tmp/uos_tg_service_e2e_test_1/budget.sqlite3")
 assert r.valid_source(private,True)
 assert !r.valid_source(private,False)
 assert !r.valid_source(r.Source(..prod,ledger:"/tmp/foreign.sqlite3"),True)
 assert !r.valid_source(r.Source(..prod,executable:prod.executable<>"/../ecology_budget.exe"),True)
 assert !r.valid_source(r.Source(..prod,sha256:"bad"),True)
}
pub fn unavailable_has_no_zero_or_paths_test(){
 let raw=r.unavailable()
 assert string.contains(raw,"\"status\":\"unavailable\"")
 assert !string.contains(raw,"daily_reserved_nanodollars")
 assert !string.contains(raw,"remaining_nanodollars")
 assert !string.contains(raw,"/home/")
}
