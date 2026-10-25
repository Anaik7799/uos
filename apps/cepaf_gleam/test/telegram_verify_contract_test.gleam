import cepaf_gleam/harness/telegram_verify_contract as v
import gleam/list
import gleam/string
import gleeunit/should

// Literal cross-language golden fixture computed independently with Node SHA256.
const golden_profile = "{\"schema\":\"uos.telegram.verify-profile.v1\",\"profile_id\":\"telegram-core\",\"candidate\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"source_closure_sha256\":\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"required_gates\":[{\"id\":\"build\",\"executable_sha256\":\"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"input_sha256\":\"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"timeout_ms\":1000},{\"id\":\"unit\",\"executable_sha256\":\"dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"input_sha256\":\"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff\",\"timeout_ms\":2000}],\"total_timeout_ms\":3000}"
const golden_digest = "3b1224f5e73035c5ecefc12efa4581a9c08e8d6ac333b5370e4265cf2d9986a5"
const golden_job = "telegram/verify/94f3fd5503a832f1e9ce36e16c4af608f28296963a0eb5caedf743d95e5da4d3"
const golden_receipt = "{\"schema\":\"uos.telegram.verify-result.v1\",\"request_id\":\"bot999/inbox8001\",\"job_id\":\"telegram/verify/94f3fd5503a832f1e9ce36e16c4af608f28296963a0eb5caedf743d95e5da4d3\",\"attempt\":1,\"profile_sha256\":\"3b1224f5e73035c5ecefc12efa4581a9c08e8d6ac333b5370e4265cf2d9986a5\",\"candidate\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"source_closure_sha256\":\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"gates\":[{\"id\":\"build\",\"executable_sha256\":\"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"input_sha256\":\"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"status\":\"PASS\",\"evidence_sha256\":\"1111111111111111111111111111111111111111111111111111111111111111\",\"elapsed_ms\":100},{\"id\":\"unit\",\"executable_sha256\":\"dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"input_sha256\":\"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff\",\"status\":\"PASS\",\"evidence_sha256\":\"2222222222222222222222222222222222222222222222222222222222222222\",\"elapsed_ms\":200}]}"
fn hash(c: String) -> String { string.repeat(c,64) }
fn gates() { [v.Gate("build",hash("c"),hash("e"),1000),v.Gate("unit",hash("d"),hash("f"),2000)] }
fn profile() { let assert Ok(p)=v.profile("telegram-core",string.repeat("a",40),hash("b"),gates(),3000) p }
fn binding() { v.Binding("bot999/inbox8001",golden_job,1,golden_digest,string.repeat("a",40),hash("b")) }
fn process() { v.ProcessObservation(0,False,True,300) }
fn assess(raw: String) { v.assess(profile(),binding(),process(),raw) }
pub fn golden_canonical_profile_and_binding_test() {
  let p=profile()
  v.canonical_json(p) |> should.equal(golden_profile)
  v.profile_digest(p) |> should.equal(golden_digest)
  v.binding(p,"bot999/inbox8001",1) |> should.equal(Ok(binding()))
  assess(golden_receipt) |> should.equal(v.VerifiedEvidence)
}
pub fn canonical_gate_order_is_independent_test() {
  let assert Ok(p)=v.profile("telegram-core",string.repeat("a",40),hash("b"),list.reverse(gates()),3000)
  v.canonical_json(p) |> should.equal(golden_profile)
  v.profile_digest(p) |> should.equal(golden_digest)
}
pub fn profile_invalid_identity_hashes_and_budget_test() {
  v.profile("",string.repeat("a",40),hash("b"),gates(),3000) |> should.be_error
  v.profile("bad id",string.repeat("a",40),hash("b"),gates(),3000) |> should.be_error
  v.profile("ok",string.repeat("A",40),hash("b"),gates(),3000) |> should.be_error
  v.profile("ok",string.repeat("a",39),hash("b"),gates(),3000) |> should.be_error
  v.profile("ok",string.repeat("a",40),"bad",gates(),3000) |> should.be_error
  v.profile("ok",string.repeat("a",40),hash("b"),gates(),2999) |> should.be_error
  v.profile("ok",string.repeat("a",40),hash("b"),gates(),120001) |> should.be_error
}
pub fn gate_set_empty_duplicate_and_invalid_test() {
  v.profile("ok",string.repeat("a",40),hash("b"),[],3000) |> should.be_error
  v.profile("ok",string.repeat("a",40),hash("b"),list.append(gates(),gates()),6000) |> should.be_error
  v.profile("ok",string.repeat("a",40),hash("b"),[v.Gate("bad id",hash("c"),hash("e"),1)],1) |> should.be_error
  v.profile("ok",string.repeat("a",40),hash("b"),[v.Gate("g","bad",hash("e"),1)],1) |> should.be_error
  v.profile("ok",string.repeat("a",40),hash("b"),[v.Gate("g",hash("c"),"bad",1)],1) |> should.be_error
  v.profile("ok",string.repeat("a",40),hash("b"),[v.Gate("g",hash("c"),hash("e"),0)],1) |> should.be_error
  v.profile("ok",string.repeat("a",40),hash("b"),[v.Gate("g",hash("c"),hash("e"),30001)],30001) |> should.be_error
}
pub fn binding_invalid_request_and_attempt_test() {
  v.binding(profile(),"",1) |> should.be_error
  v.binding(profile(),"bad request",1) |> should.be_error
  v.binding(profile(),"request",0) |> should.be_error
  v.binding(profile(),"request",2147483648) |> should.be_error
  v.binding(profile(),string.repeat("x",241),1) |> should.be_error
}
pub fn wrong_expected_binding_refused_test() {
  v.assess(profile(),v.Binding(..binding(),job_id:"foreign"),process(),golden_receipt) |> should.equal(v.Failed("invalid_expected_binding"))
}
pub fn exact_receipt_identity_required_test() {
  list.each([#("bot999/inbox8001","foreign"),#(golden_job,"foreign"),#("\"attempt\":1","\"attempt\":2"),#(golden_digest,hash("9")),#(string.repeat("a",40),string.repeat("b",40)),#(hash("b"),hash("8")),#("uos.telegram.verify-result.v1","unknown")],fn(pair) {
    let #(from,to)=pair
    assess(string.replace(golden_receipt,from,to)) |> should.equal(v.Failed("receipt_binding_mismatch"))
  })
}
pub fn failed_error_skipped_or_unknown_gate_never_succeeds_test() {
  list.each(["FAIL","ERROR","SKIPPED"],fn(s) { assess(string.replace(golden_receipt,"PASS",s)) |> should.equal(v.Failed("gate_not_passed")) })
  assess(string.replace(golden_receipt,"PASS","UNKNOWN")) |> should.equal(v.Failed("gate_receipt_incomplete_or_invalid"))
}
pub fn missing_duplicate_and_extra_gate_refused_test() {
  assess("{\"schema\":\"uos.telegram.verify-result.v1\",\"request_id\":\"bot999/inbox8001\",\"job_id\":\"telegram/verify/94f3fd5503a832f1e9ce36e16c4af608f28296963a0eb5caedf743d95e5da4d3\",\"attempt\":1,\"profile_sha256\":\"3b1224f5e73035c5ecefc12efa4581a9c08e8d6ac333b5370e4265cf2d9986a5\",\"candidate\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"source_closure_sha256\":\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"gates\":[{\"id\":\"build\",\"executable_sha256\":\"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"input_sha256\":\"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"status\":\"PASS\",\"evidence_sha256\":\"1111111111111111111111111111111111111111111111111111111111111111\",\"elapsed_ms\":100}]}") |> should.equal(v.Failed("gate_receipt_incomplete_or_invalid"))
  assess(string.replace(golden_receipt,"\"id\":\"unit\"","\"id\":\"build\"")) |> should.equal(v.Failed("gate_receipt_incomplete_or_invalid"))
  assess("{\"schema\":\"uos.telegram.verify-result.v1\",\"request_id\":\"bot999/inbox8001\",\"job_id\":\"telegram/verify/94f3fd5503a832f1e9ce36e16c4af608f28296963a0eb5caedf743d95e5da4d3\",\"attempt\":1,\"profile_sha256\":\"3b1224f5e73035c5ecefc12efa4581a9c08e8d6ac333b5370e4265cf2d9986a5\",\"candidate\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"source_closure_sha256\":\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"gates\":[{\"id\":\"build\",\"executable_sha256\":\"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"input_sha256\":\"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"status\":\"PASS\",\"evidence_sha256\":\"1111111111111111111111111111111111111111111111111111111111111111\",\"elapsed_ms\":100},{\"id\":\"unit\",\"executable_sha256\":\"dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"input_sha256\":\"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff\",\"status\":\"PASS\",\"evidence_sha256\":\"2222222222222222222222222222222222222222222222222222222222222222\",\"elapsed_ms\":200},{\"id\":\"extra\",\"executable_sha256\":\"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"input_sha256\":\"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"status\":\"PASS\",\"evidence_sha256\":\"1111111111111111111111111111111111111111111111111111111111111111\",\"elapsed_ms\":100}]}") |> should.equal(v.Failed("gate_receipt_incomplete_or_invalid"))
}
pub fn changed_gate_input_executable_or_evidence_refused_test() {
  list.each([#(hash("c"),hash("9")),#(hash("e"),hash("9")),#(hash("1"),"bad"),#("\"elapsed_ms\":100","\"elapsed_ms\":1001"),#("\"elapsed_ms\":100","\"elapsed_ms\":-1")],fn(pair) {
    let #(from,to)=pair
    assess(string.replace(golden_receipt,from,to)) |> should.equal(v.Failed("gate_receipt_incomplete_or_invalid"))
  })
}
pub fn malformed_or_oversized_receipt_refused_test() {
  assess("{") |> should.equal(v.Failed("invalid_receipt_shape"))
  assess("") |> should.equal(v.Failed("receipt_size_refused"))
  assess(string.repeat(" ",65537)) |> should.equal(v.Failed("receipt_size_refused"))
}
pub fn successful_receipt_cannot_mask_process_failure_test() {
  v.assess(profile(),binding(),v.ProcessObservation(..process(),exit_code:1),golden_receipt) |> should.equal(v.Failed("process_exit_nonzero"))
  v.assess(profile(),binding(),v.ProcessObservation(..process(),timed_out:True),golden_receipt) |> should.equal(v.Failed("process_deadline_exceeded"))
  v.assess(profile(),binding(),v.ProcessObservation(..process(),elapsed_ms:3001),golden_receipt) |> should.equal(v.Failed("process_deadline_exceeded"))
}
pub fn unknown_process_cleanup_and_time_remain_indeterminate_test() {
  v.assess(profile(),binding(),v.ProcessObservation(..process(),reaped:False),golden_receipt) |> should.equal(v.Indeterminate("process_not_reaped"))
  v.assess(profile(),binding(),v.ProcessObservation(..process(),elapsed_ms:-1),golden_receipt) |> should.equal(v.Indeterminate("process_time_unknown"))
}

pub fn duplicate_escaped_keys_and_unknown_fields_refused_test() {
  assess(string.replace(golden_receipt,"\"attempt\":1","\"attempt\":1,\"attempt\":1")) |> should.equal(v.Failed("invalid_receipt_shape"))
  assess(string.replace(golden_receipt,"\"attempt\":1","\"attempt\":1,\"\\u0061ttempt\":1")) |> should.equal(v.Failed("invalid_receipt_shape"))
  assess(string.replace(golden_receipt,"\"attempt\":1","\"attempt\":1,\"extra\":true")) |> should.equal(v.Failed("invalid_receipt_shape"))
  assess(string.replace(golden_receipt,"\"status\":\"PASS\"","\"status\":\"PASS\",\"status\":\"FAIL\"")) |> should.equal(v.Failed("invalid_receipt_shape"))
}
pub fn sequential_gate_duration_cannot_exceed_process_duration_test() {
  v.assess(profile(),binding(),v.ProcessObservation(..process(),elapsed_ms:299),golden_receipt) |> should.equal(v.Failed("gate_receipt_incomplete_or_invalid"))
}
