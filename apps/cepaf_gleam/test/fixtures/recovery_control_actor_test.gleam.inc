//// Private composed RECOVERY_CONTROL tests. Fixed test trust, no production admission.
import cepaf_gleam/harness/recovery_owner as c
import cepaf_gleam/harness/recovery_owner_store as s
import cepaf_gleam/harness/recovery_wire as w
import cepaf_gleam/harness/native_launch as n
import cepaf_gleam/harness/value as v
import cepaf_gleam/mcp/json_guard
import envoy
import gleam/erlang/process
import gleam/json
import gleam/int
import gleam/list
import gleam/result
import gleeunit/should
import simplifile

fn env(k) { let assert Ok(x)=envoy.get(k) x }
fn text(x,k) { let assert Ok(x)=s.text(x,k) x }
fn config(locator, worker, pin) {
  let assert Ok(x)=n.reviewed_configuration(n.LinuxX8664,n.NativeStorageV1,
    env("UOS_CONTROL_LAUNCHER"),env("UOS_CONTROL_LAUNCHER_SHA"),
    env("UOS_CONTROL_GUARDIAN"),env("UOS_CONTROL_GUARDIAN_SHA"),worker,pin,locator)
  x
}
fn helper(directory, operation, value) {
  let body=json.to_string(json.object([#("operation",json.string(operation)),#("value",json.int(value))]))
  let raw=s.raw_exchange_finite(config(directory,env("UOS_CONTROL_HELPER"),env("UOS_CONTROL_HELPER_SHA")),body)
  s.successful(raw.cleanup) |> should.be_true()
  let assert Ok(body)=raw.body
  let assert Ok(value)=json_guard.native_inspect(body,16)
  case v.get(value,"status") {
    Ok(v.Text("HOLD"))->panic as text(value,"code")
    _->value
  }
}
type Fixture { Fixture(data:v.Value, config:c.ConfigurationData, native:n.Configuration) }
fn prepare(ttl) {
  let data=helper(env("UOS_CONTROL_DRIVER_LOCATOR"),"prepare",ttl)
  text(data,"checker_status") |> should.equal("PASS")
  let native=config(text(data,"locator"),env("UOS_CONTROL_WORKER"),env("UOS_CONTROL_WORKER_SHA"))
  let journal=config(text(data,"journal"),env("UOS_CONTROL_JOURNAL"),env("UOS_CONTROL_JOURNAL_SHA"))
  let assert Ok(request)=w.decode(text(data,"factual_request"))
  let assert Ok(configuration)=c.finite_configuration_data("control-fixture-owner",request,
    text(data,"context_sha256"),text(data,"commit_body"),text(data,"inspect_body"),journal,5000)
  Fixture(data,configuration,native)
}
fn observe(f:Fixture) { helper(text(f.data,"directory"),"observe",0) }
fn before(f:Fixture) { observe(f) |> should.equal(v.Array([v.Integer(1),v.Integer(1),v.Integer(1)])) }
fn after(f:Fixture) { observe(f) |> should.equal(v.Array([v.Integer(2),v.Integer(2),v.Integer(2)])) }
fn quiet(f:Fixture,stage) {
  case helper(text(f.data,"directory"),case stage=="pending_created_by_this_owner" { True->"probe_pending" False->"probe" },0) {
    v.Boolean(True)->Ok(Nil)
    _->Error("NATIVE_QUIESCENCE_UNKNOWN")
  }
}
fn await(owner,n) {
  let assert Ok(x)=c.get(owner,1000)
  case x.in_flight && n>0 { True->{process.sleep(1) await(owner,n-1)} False->x }
}
fn start(f:Fixture,unknown) {
  let assert Ok(owner)=c.fixture_start(f.config,fn(){Ok(Nil)},fn(){Ok(Nil)},
    fn(stage){case unknown { True->Error("UNCONFIRMED") False->quiet(f,stage) }},
    fn(body){s.raw_exchange_finite(f.native,body)}) |> result.map(fn(x){x.data})
  let _=await(owner,3000)
  owner
}
fn commit(owner) {
  let assert Ok(state)=c.get(owner,1000)
  c.commit(owner,c.Step(state.operation_id,state.revision),10000)
}
fn stop(owner) { let _=c.stop(owner,1000) Nil }

fn actual_bound_evidence(f:Fixture) {
  let evidence=helper(text(f.data,"directory"),"bound_observation",0)
  text(evidence,"sqlite_version") |> should.equal("3.53.3")
  let assert Ok(diagnostics)=v.get(evidence,"diagnostics")
  let assert Ok(v.Array(roles))=v.get(diagnostics,"resources")
  list.length(roles) |> should.equal(3)
  let signed=helper(text(f.data,"directory"),"signed_physical",0)
  list.each(["main","wal","shm"],fn(role){
    let assert Ok(actual)=list.find(roles,fn(row){s.text(row,"role")==Ok(role)})
    let assert Ok(expected)=v.get(signed,role)
    list.each(["device","inode"],fn(key){
      let assert Ok(v.Integer(observed))=v.get(actual,key)
      text(expected,key) |> should.equal(int.to_string(observed))
    })
    v.get(actual,"opens") |> should.equal(Ok(v.Integer(1)))
  })
  let assert Ok(wal)=list.find(roles,fn(row){s.text(row,"role")==Ok("wal")})
  let assert Ok(v.Integer(writes))=v.get(wal,"writes")
  let assert Ok(v.Integer(syncs))=v.get(wal,"syncs")
  { writes>0 && syncs>0 } |> should.be_true()
}

// Missing resource/checker guards would allow real attempt increments here.
pub fn signed_checked_durable_owner_finite_transaction_and_expired_history_test() {
  let f=prepare(5000)
  before(f)
  let owner=start(f,False)
  let assert Ok(done)=commit(owner)
  done.phase |> should.equal(c.HistoricalFact)
  after(f)
  actual_bound_evidence(f)
  helper(text(f.data,"directory"),"resource_receipt",0) |> should.equal(v.Boolean(True))
  stop(owner)
  process.sleep(5100)
  let raw=s.raw_exchange_finite(f.native,text(f.data,"inspect_body"))
  s.successful(raw.cleanup) |> should.be_true()
  let assert Ok(body)=raw.body
  let assert Ok(value)=json_guard.native_inspect(body,16)
  text(value,"status") |> should.equal("HISTORICAL")
  let expired=s.raw_exchange_finite(f.native,text(f.data,"commit_body"))
  let assert Ok(body)=expired.body
  let assert Ok(value)=json_guard.native_inspect(body,16)
  text(value,"status") |> should.equal("HOLD")
  after(f)
}

pub fn public_owner_never_gains_authority_from_fixture_configuration_test() {
  let f=prepare(10000)
  let assert Ok(owner)=c.start(f.config) |> result.map(fn(x){x.data})
  await(owner,3000).phase |> should.equal(c.Unavailable)
  commit(owner) |> should.be_error()
  before(f)
  stop(owner)
}

pub fn cloned_database_and_journal_cannot_reuse_resource_signatures_test() {
  let f=prepare(10000)
  helper(text(f.data,"directory"),"clone",0) |> should.equal(v.Boolean(True))
  let raw=s.raw_exchange_finite(f.native,text(f.data,"commit_body"))
  let assert Ok(body)=raw.body
  let assert Ok(value)=json_guard.native_inspect(body,16)
  text(value,"status") |> should.equal("HOLD")
  before(f)
}

fn postopen_swap(role) {
  let f=prepare(10000)
  helper(text(f.data,"directory"),"pause_after_open",0) |> should.equal(v.Boolean(True))
  let owner=start(f,False)
  let replies=process.new_subject()
  let _=process.spawn(fn(){process.send(replies,commit(owner))})
  ready(text(f.data,"directory")<>"/bound-open-ready",3000)
  helper(text(f.data,"directory"),role,0) |> should.equal(v.Boolean(True))
  helper(text(f.data,"directory"),"release_after_open",0) |> should.equal(v.Boolean(True))
  let _=process.receive(replies,8000)
  await(owner,3000).phase |> should.equal(c.ReconcileOnly)
  helper(text(f.data,"directory"),"probe",0) |> should.equal(v.Boolean(True))
  stop(owner)
  helper(text(f.data,"directory"),"restore_sidecars",0) |> should.equal(v.Boolean(True))
  before(f)
}
pub fn actual_postopen_wal_swap_cannot_retarget_bound_writer_test() { postopen_swap("swap_wal") }
pub fn actual_postopen_shm_swap_cannot_retarget_bound_writer_test() { postopen_swap("swap_shm") }

pub fn new_fourth_expiration_refuses_the_exact_three_set_test() {
  let f=prepare(10000)
  helper(text(f.data,"directory"),"fourth",0) |> should.equal(v.Boolean(True))
  let owner=start(f,False)
  let assert Ok(held)=commit(owner)
  held.phase |> should.equal(c.ReconcileOnly)
  before(f)
  stop(owner)
}

pub fn owner_epoch_substitution_cannot_reuse_signatures_test() {
  let f=prepare(10000)
  helper(text(f.data,"directory"),"epoch",0) |> should.equal(v.Boolean(True))
  let owner=start(f,False)
  let assert Ok(held)=commit(owner)
  held.phase |> should.equal(c.ReconcileOnly)
  before(f)
  stop(owner)
}

pub fn actual_source_drift_cannot_hide_behind_saved_checker_pass_test() {
  let f=prepare(10000)
  helper(text(f.data,"directory"),"source",0) |> should.equal(v.Boolean(True))
  let owner=start(f,False)
  let assert Ok(held)=commit(owner)
  held.phase |> should.equal(c.ReconcileOnly)
  before(f)
  stop(owner)
}

fn corrupt_completed_receipt() {
  let f=prepare(10000)
  let owner=start(f,False)
  let assert Ok(done)=commit(owner)
  done.phase |> should.equal(c.HistoricalFact)
  after(f)
  stop(owner)
  helper(text(f.data,"directory"),"nul_receipt",0) |> should.equal(v.Boolean(True))
  f
}
pub fn both_lookup_interpreters_reject_actual_valid_prefix_nul_suffix_test() {
  let f=corrupt_completed_receipt()
  helper(text(f.data,"directory"),"lookup_integrity",0)
    |> should.equal(v.Array([v.Boolean(False),v.Boolean(False)]))
  after(f)
}
pub fn historical_inspection_rejects_actual_valid_prefix_nul_suffix_test() {
  let f=corrupt_completed_receipt()
  let raw=s.raw_exchange_finite(f.native,text(f.data,"inspect_body"))
  let assert Ok(body)=raw.body
  let assert Ok(value)=json_guard.native_inspect(body,16)
  text(value,"status") |> should.equal("HOLD")
  after(f)
}

pub fn unknown_native_cleanup_cannot_launch_even_first_effect_test() {
  let f=prepare(10000)
  let owner=start(f,True)
  commit(owner) |> should.be_error()
  before(f)
  simplifile.is_file(text(f.data,"directory")<>"/worker.pid") |> should.equal(Ok(False))
  stop(owner)
}

fn ready(path,n) {
  case simplifile.is_file(path),n>0 {
    Ok(True),_->Nil
    _,True->{process.sleep(1) ready(path,n-1)}
    _,False->panic as "private fault marker missing"
  }
}
fn run_crash(mode,expected) {
  let f=prepare(4000)
  helper(text(f.data,"directory"),mode,0) |> should.equal(v.Boolean(True))
  let owner=start(f,False)
  let replies=process.new_subject()
  let _=process.spawn(fn(){process.send(replies,commit(owner))})
  ready(text(f.data,"directory")<>"/fault-ready",4000)
  helper(text(f.data,"directory"),"kill",0) |> should.equal(v.Boolean(True))
  let _=process.receive(replies,8000)
  stop(owner)
  observe(f) |> should.equal(expected)
  helper(text(f.data,"directory"),"probe",0) |> should.equal(v.Boolean(True))
  process.sleep(4100)
  let raw=s.raw_exchange_finite(f.native,text(f.data,"inspect_body"))
  let assert Ok(body)=raw.body
  let assert Ok(value)=json_guard.native_inspect(body,16)
  text(value,"status") |> should.equal(case mode { "kill_after"->"HISTORICAL" _->"HOLD" })
  let restarted=start(f,False)
  let assert Ok(reconciled)=c.reconcile(restarted,10000)
  reconciled.phase |> should.equal(case mode { "kill_after"->c.HistoricalFact _->c.ReconcileOnly })
  stop(restarted)
  observe(f) |> should.equal(expected)
}
pub fn killed_after_first_actual_claim_rolls_back_entire_set_test() {
  run_crash("kill_before",v.Array([v.Integer(1),v.Integer(1),v.Integer(1)]))
}
pub fn committed_without_ack_reconciles_after_expiry_without_second_claim_test() {
  run_crash("kill_after",v.Array([v.Integer(2),v.Integer(2),v.Integer(2)]))
}

pub fn lock_wait_across_native_capability_expiry_cannot_commit_test() {
  let f=prepare(1500)
  let replies=process.new_subject()
  let _=process.spawn(fn(){process.send(replies,helper(text(f.data,"directory"),"lock",2400))})
  ready(text(f.data,"directory")<>"/lock-ready",3000)
  let owner=start(f,False)
  let assert Ok(held)=commit(owner)
  held.phase |> should.equal(c.ReconcileOnly)
  simplifile.is_file(text(f.data,"directory")<>"/before-begin") |> should.equal(Ok(True))
  before(f)
  let _=process.receive(replies,3000)
  stop(owner)
}

// ORDINARY_ONLY_BEGIN
// Current authorized run: no corruption, swap, fault, expiry or signal action.
pub fn ordinary_bound_owner_commit_history_test() {
  let f=prepare(30000)
  before(f)
  let owner=start(f,False)
  let assert Ok(done)=commit(owner)
  done.phase |> should.equal(c.HistoricalFact)
  after(f)
  actual_bound_evidence(f)
  helper(text(f.data,"directory"),"resource_receipt",0) |> should.equal(v.Boolean(True))
  stop(owner)
  let raw=s.raw_exchange_finite(f.native,text(f.data,"inspect_body"))
  s.successful(raw.cleanup) |> should.be_true()
  let assert Ok(body)=raw.body
  let assert Ok(value)=json_guard.native_inspect(body,16)
  text(value,"status") |> should.equal("HISTORICAL")
  after(f)
  let restarted=start(f,False)
  let assert Ok(history)=c.reconcile(restarted,10000)
  history.phase |> should.equal(c.HistoricalFact)
  after(f)
  stop(restarted)
}
// ORDINARY_ONLY_END
