// PRIVATE EUnit build only. Actual standalone JJ and private Sa-plan fixtures.
import cepaf_gleam/harness/jj_integration as j
import cepaf_gleam/harness/telegram_store_transport as t
import cepaf_gleam/harness/value as v
import cepaf_gleam/mcp/json_guard
import gleam/bit_array
import gleam/erlang/process
import gleam/option.{None, Some, type Option}
import simplifile
import gleeunit/should

@external(erlang, "cepaf_gleam_ffi", "get_env")
fn env(key: String) -> Result(String, Nil)
@external(erlang, "ecology_capability_ffi", "run_bounded")
fn helper(path: String, args: List(String), timeout: Int) -> Result(#(Int, BitArray), String)
fn text(data, key) {
  let assert Ok(v.Text(value)) = v.get(data, key)
  value
}
fn prepare(scenario) {
  let assert Ok(executable) = env("UOS_JJ_FIXTURE_SETUP")
  let assert Ok(#(0, bytes)) = helper(executable, ["prepare", scenario], 30_000)
  let assert Ok(raw) = bit_array.to_string(bytes)
  let assert Ok(data) = json_guard.native_inspect(raw, 6)
  let assert Ok(intent) = j.prepare("private-intent-1", j.BindingData("uos/private-jj", "INTEGRATE", "fixture-worker", 1, "fixture-owner", 1),
    j.CandidateData(text(data, "expected_main"), text(data, "candidate"), text(data, "expected_operation"), text(data, "manifest_sha256"), text(data, "review_sha256"), text(data, "tests_sha256")))
  let local = t.reviewed_local_configuration(text(data, "guardian"), text(data, "guardian_sha256"), text(data, "worker"), text(data, "worker_sha256"), text(data, "locator"))
  let assert Ok(owner) = j.fixture_start(j.connection_data(local))
  #(data, intent, owner)
}
fn observe(data) {
  let assert Ok(executable) = env("UOS_JJ_FIXTURE_SETUP")
  let assert Ok(#(0, bytes)) = helper(executable, ["observe", text(data, "locator")], 10_000)
  let assert Ok(raw) = bit_array.to_string(bytes)
  let assert Ok(value) = json_guard.native_inspect(raw, 6)
  text(value, "main")
}
pub fn actual_standalone_jj_fastforward_prerequisite_test() {
  let #(data, intent, connection) = prepare("good")
  observe(data) |> should.equal(text(data, "expected_main"))
  let assert j.IntegratedFact(_) = j.fixture_integrate(intent, connection)
  observe(data) |> should.equal(text(data, "candidate"))
}
pub fn actual_production_refusal_preserves_jj_test() {
  let #(data, intent, _) = prepare("good")
  j.integrate(intent) |> should.be_error()
  observe(data) |> should.equal(text(data, "expected_main"))
}
fn alter(data, operation) {
  let assert Ok(executable) = env("UOS_JJ_FIXTURE_SETUP")
  let assert Ok(#(0, _)) = helper(executable, ["alter:" <> operation,text(data,"locator")], 10_000)
  Nil
}
pub fn omitted_changes_refused_test() {
 let #(data,intent,connection)=prepare("omitted")
 j.fixture_integrate(intent,connection) |> should.equal(j.Refused("REFUSED_MANIFEST_COVERAGE"))
 observe(data) |> should.equal(text(data,"expected_main"))
}
pub fn conflicting_candidate_refused_test() {
 let #(data,intent,connection)=prepare("conflict")
 j.fixture_integrate(intent,connection) |> should.equal(j.Refused("REFUSED_CANDIDATE_CONFLICT"))
 observe(data) |> should.equal(text(data,"expected_main"))
}
pub fn dirty_unsnapshotted_workspace_refused_test() {
 let #(data,intent,connection)=prepare("dirty")
 j.fixture_integrate(intent,connection) |> should.equal(j.Refused("REFUSED_DIRTY_WORKSPACE"))
 observe(data) |> should.equal(text(data,"expected_main"))
}
pub fn intervening_jj_operation_refuses_stale_cas_test() {
 let #(data,intent,connection)=prepare("good")
 alter(data,"operation")
 j.fixture_integrate(intent,connection) |> should.equal(j.Refused("REFUSED_REVISION_OPERATION_CAS"))
 observe(data) |> should.equal(text(data,"expected_main"))
}
pub fn changed_exclusive_owner_epoch_refuses_test() {
 let #(data,intent,connection)=prepare("good")
 alter(data,"owner")
 j.fixture_integrate(intent,connection) |> should.equal(j.Refused("REFUSED_INTEGRATION_OWNER_EPOCH"))
 observe(data) |> should.equal(text(data,"expected_main"))
}
pub fn expired_actual_task_lease_refuses_test() {
 let #(data,intent,connection)=prepare("good")
 alter(data,"lease")
 j.fixture_integrate(intent,connection) |> should.equal(j.Refused("REFUSED_TASK_LEASE_FENCE"))
 observe(data) |> should.equal(text(data,"expected_main"))
}
pub fn exact_replay_is_historical_never_dispatch_test() {
 let #(data,intent,connection)=prepare("good")
 let assert j.IntegratedFact(first)=j.fixture_integrate(intent,connection)
 j.fixture_integrate(intent,connection) |> should.equal(j.HistoricalFact(first))
 j.fixture_history(intent,connection) |> should.equal(j.HistoricalFact(first))
 observe(data) |> should.equal(text(data,"candidate"))
}
pub fn killed_before_effect_consumes_without_retry_test() {
 let #(data,intent,connection)=prepare("kill_before_effect")
 j.fixture_integrate(intent,connection) |> should.equal(j.ReconcileOnly)
 j.fixture_integrate(intent,connection) |> should.equal(j.ReconcileOnly)
 j.fixture_history(intent,connection) |> should.equal(j.ReconcileOnly)
 observe(data) |> should.equal(text(data,"expected_main"))
}
pub fn killed_after_effect_without_receipt_remains_unknown_test() {
 let #(data,intent,connection)=prepare("kill_after_effect")
 j.fixture_integrate(intent,connection) |> should.equal(j.ReconcileOnly)
 observe(data) |> should.equal(text(data,"candidate"))
 j.fixture_integrate(intent,connection) |> should.equal(j.ReconcileOnly)
 j.fixture_history(intent,connection) |> should.equal(j.ReconcileOnly)
}
pub fn lost_ack_after_durable_receipt_reconciles_test() {
 let #(data,intent,connection)=prepare("kill_after_receipt")
 j.fixture_integrate(intent,connection) |> should.equal(j.ReconcileOnly)
 observe(data) |> should.equal(text(data,"candidate"))
 let assert j.HistoricalFact(fact)=j.fixture_history(intent,connection)
 j.fixture_integrate(intent,connection) |> should.equal(j.HistoricalFact(fact))
}

pub fn concurrent_intents_have_at_most_one_fresh_dispatch_test() {
 let #(data,intent,connection)=prepare("good")
 let replies=process.new_subject()
 let _=process.spawn(fn(){process.send(replies,j.fixture_integrate(intent,connection))})
 let _=process.spawn(fn(){process.send(replies,j.fixture_integrate(intent,connection))})
 let assert Ok(a)=process.receive(replies,12_000)
 let assert Ok(b)=process.receive(replies,12_000)
 let fresh=fn(x){case x { j.IntegratedFact(_)->1 _->0 }}
 { fresh(a)+fresh(b) } |> should.equal(1)
 observe(data) |> should.equal(text(data,"candidate"))
 let assert j.HistoricalFact(_)=j.fixture_history(intent,connection)
}
fn refuse_scenario(scenario, code) {
 let #(data,intent,owner)=prepare(scenario)
 j.fixture_integrate(intent,owner) |> should.equal(j.Refused(code))
 observe(data) |> should.equal(text(data,"expected_main"))
}
pub fn undeclared_candidate_change_refused_test(){refuse_scenario("undeclared","REFUSED_MANIFEST_COVERAGE")}
pub fn duplicate_manifest_refused_test(){refuse_scenario("manifest_duplicate","REFUSED_MANIFEST_DUPLICATE")}
pub fn missing_manifest_path_refused_test(){refuse_scenario("manifest_missing","REFUSED_MANIFEST_COVERAGE")}
pub fn unchanged_extra_manifest_path_refused_test(){refuse_scenario("manifest_extra","REFUSED_MANIFEST_COVERAGE")}
pub fn correctly_hashed_negative_review_refuses_test(){refuse_scenario("bad_review","REFUSED_REVIEW_VERDICT")}
pub fn correctly_hashed_failed_test_refuses_test(){refuse_scenario("bad_tests","REFUSED_TEST_VERDICT")}
fn late_refusal(scenario){
 let #(data,intent,owner)=prepare(scenario)
 j.fixture_integrate(intent,owner) |> should.equal(j.ReconcileOnly)
 observe(data) |> should.equal(text(data,"expected_main"))
 j.fixture_integrate(intent,owner) |> should.equal(j.ReconcileOnly)
}
pub fn lease_changed_after_queries_before_spawn_refuses_test(){late_refusal("expire_before_spawn")}
pub fn deadline_after_blocking_callback_before_spawn_refuses_test(){late_refusal("deadline_before_spawn")}
pub fn output_is_capped_during_subprocess_not_after_exit_test(){
 let #(data,_,_)=prepare("good")
 let assert Ok(executable)=env("UOS_JJ_FIXTURE_SETUP")
 let assert Ok(#(0,bytes))=helper(executable,["probe:output",text(data,"locator")],10_000)
 let assert Ok(raw)=bit_array.to_string(bytes)
 let assert Ok(value)=json_guard.native_inspect(raw,6)
 text(value,"code") |> should.equal("JJ_OUTPUT_BOUND")
 let assert Ok(v.Integer(largest))=v.get(value,"largest_retained_bytes")
 {largest<=262144} |> should.be_true()
}
@external(erlang,"telegram_store_transport_ffi","request_config_with_cleanup")
fn paired(local:t.LocalConfiguration,body:String)->#(Result(String,String),Option(#(Int,Int)))
pub fn terminal_missing_cleanup_witness_suppresses_all_followup_io_test(){
 let #(data,intent,_)=prepare("good")
 let seen=process.new_subject()
 let local=t.reviewed_local_configuration(text(data,"guardian"),text(data,"guardian_sha256"),text(data,"worker"),text(data,"worker_sha256"),text(data,"locator"))
 let assert Ok(owner)=j.fixture_start_with_exchange(j.connection_data(local),fn(config,body){
  let #(response,witness)=paired(config,body)
  // REAL invocation and genuine cleanup happened; this private fault merely
  // redacts the witness. This is not an observed OS reap failure.
  let assert Some(#(0,at))=witness
  {at>0} |> should.be_true()
  process.send(seen,Nil)
  #(response,None)
 })
 j.fixture_integrate(intent,owner) |> should.equal(j.CleanupUnconfirmed)
 process.receive(seen,1000) |> should.be_ok()
 j.fixture_integrate(intent,owner) |> should.equal(j.CleanupUnconfirmed)
 j.fixture_history(intent,owner) |> should.equal(j.CleanupUnconfirmed)
 process.receive(seen,0) |> should.be_error()
 observe(data) |> should.equal(text(data,"expected_main"))
}
pub fn idle_fixture_owner_stops_on_normal_parent_exit_test(){
 let #(data,_,_)=prepare("good")
 let local=t.reviewed_local_configuration(text(data,"guardian"),text(data,"guardian_sha256"),text(data,"worker"),text(data,"worker_sha256"),text(data,"locator"))
 let ready=process.new_subject()
 let _=process.spawn(fn(){
  let done=process.new_subject()
  let assert Ok(owner)=j.fixture_start(j.connection_data(local))
  process.send(ready,#(owner,done))
  let _=process.receive(done,1000)
 })
 let assert Ok(#(owner,done))=process.receive(ready,1000)
 let assert Ok(pid)=j.fixture_process(owner)
 let monitor=process.monitor(pid)
 let selector=process.new_selector() |> process.select_specific_monitor(monitor,fn(_){True})
 process.send(done,Nil)
 process.selector_receive(selector,1000) |> should.equal(Ok(True))
 process.is_alive(pid) |> should.be_false()
}
fn wait_private_file(path,remaining){
 case simplifile.is_file(path),remaining>0 {
  Ok(True),_->Nil
  _,True->{process.sleep(1) wait_private_file(path,remaining-1)}
  _,False->panic as "private native barrier absent"
 }
}
pub fn actual_blocked_reserve_parent_loss_prevents_second_exchange_test(){
 let #(data,intent,_)=prepare("block_reserve")
 let local=t.reviewed_local_configuration(text(data,"guardian"),text(data,"guardian_sha256"),text(data,"worker"),text(data,"worker_sha256"),text(data,"locator"))
 let ready=process.new_subject()
 let seen=process.new_subject()
 let parent=process.spawn(fn(){
  let done=process.new_subject()
  let assert Ok(owner)=j.fixture_start_with_exchange(j.connection_data(local),fn(config,body){
   process.send(seen,Nil)
   paired(config,body)
  })
  process.send(ready,#(owner,done))
  let _=process.receive(done,10_000)
 })
 let assert Ok(#(owner,done))=process.receive(ready,1000)
 let assert Ok(owner_pid)=j.fixture_process(owner)
 let owner_monitor=process.monitor(owner_pid)
 let parent_monitor=process.monitor(parent)
 let replies=process.new_subject()
 let _=process.spawn(fn(){process.send(replies,j.fixture_integrate(intent,owner))})
 let control=text(data,"directory")<>"/control"
 // REAL native worker holds durable Pending and blocks before reserve ACK.
 wait_private_file(control<>"/reserve-ready",3000)
 process.receive(seen,1000) |> should.be_ok()
 process.send(done,Nil)
 let parent_down=process.new_selector() |> process.select_specific_monitor(parent_monitor,fn(_){True})
 process.selector_receive(parent_down,1000) |> should.equal(Ok(True))
 simplifile.write(control<>"/release-reserve","release") |> should.be_ok()
 process.receive(replies,10_000) |> should.equal(Ok(j.ReconcileOnly))
 // No second fast_forward IPC occurred after the observed normal parent death.
 process.receive(seen,0) |> should.be_error()
 let owner_down=process.new_selector() |> process.select_specific_monitor(owner_monitor,fn(_){True})
 process.selector_receive(owner_down,1000) |> should.equal(Ok(True))
 process.is_alive(owner_pid) |> should.be_false()
 observe(data) |> should.equal(text(data,"expected_main"))
}
