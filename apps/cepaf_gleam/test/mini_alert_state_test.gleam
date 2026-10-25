import cepaf_gleam/telegram/mini_alert_state as state
import cepaf_gleam/telegram/mini_alerts as alerts
import gleam/list
import gleam/option.{None,Some}
import gleam/string
import gleeunit/should

fn owner() { state.new(string.repeat("a",64)) |> should.be_ok }
fn alert() { alerts.Alert("cpu","local_linux_sysfs","warning","Temperature threshold exceeded","85000",">=80000") }
fn sample(s: state.State,rows: List(alerts.Alert),wall: Int,mono: Int) {
  let #(next,r)=state.observe(s,rows,wall,mono)
  r |> should.be_ok
  next
}
fn initial() {sample(owner(),[alert()],100,0)}
fn entry(s: state.State) {state.entries(s) |> list.first |> should.be_ok}
fn receipt(at: Int) { state.Review(42,at,"mini-control/"<>string.repeat("b",64)) }
fn ack(s: state.State,wall: Int,mono: Int) {
  let selection=state.select(s,state.All(state.set_digest(s)),wall,mono) |> should.be_ok
  state.apply_review(s,selection,receipt(wall),wall,mono) |> should.be_ok
}
pub fn acknowledgement_retains_condition_test() {
  let s=initial() |> ack(100,0)
  entry(s).alert |> should.equal(alert())
  entry(s).review |> should.equal(Some(receipt(100)))
}
pub fn measurement_change_retains_episode_and_review_test() {
  let s=initial() |> ack(100,0)
  let t=sample(s,[alerts.Alert(..alert(),measured:"86000")],101,1000)
  entry(t).episode |> should.equal(entry(s).episode)
  entry(t).review |> should.equal(entry(s).review)
  entry(t).alert.measured |> should.equal("86000")
}
pub fn observed_clear_and_rebreach_require_review_test() {
  let s=initial() |> ack(100,0)
  let clear=sample(s,[],101,1000)
  state.entries(clear) |> should.equal([])
  let next=sample(clear,[alert()],102,2000)
  {entry(next).episode != entry(s).episode} |> should.be_true
  entry(next).review |> should.equal(None)
}
pub fn changed_condition_does_not_inherit_review_test() {
  let s=initial() |> ack(100,0)
  list.each([
    alerts.Alert(..alert(),severity:"critical"),
    alerts.Alert(..alert(),threshold:">=70000"),
    alerts.Alert(..alert(),source:"other_source"),
    alerts.Alert(..alert(),condition:"New breach mode"),
    alerts.Alert(..alert(),severity:"unknown"),
  ],fn(a){
    let next=sample(s,[a],101,1000)
    {entry(next).episode!=entry(s).episode} |> should.be_true
    entry(next).review |> should.equal(None)
  })
}
pub fn full_observer_failure_invalidates_episode_test() {
  let s=initial() |> ack(100,0)
  let lost=state.invalidate(s)
  state.select(lost,state.All(state.set_digest(lost)),100,0) |> should.be_error
  let next=sample(lost,[alert()],101,1000)
  entry(next).review |> should.equal(None)
  {entry(next).episode!=entry(s).episode} |> should.be_true
}
pub fn too_long_observation_gap_requires_review_test() {
  let s=initial() |> ack(100,0)
  let next=sample(s,[alert()],161,61000)
  entry(next).review |> should.equal(None)
  {entry(next).episode!=entry(s).episode} |> should.be_true
}
pub fn new_owner_cannot_apply_old_selection_test() {
  let s=initial()
  let selection=state.select(s,state.All(state.set_digest(s)),100,0) |> should.be_ok
  let other=state.new(string.repeat("c",64)) |> should.be_ok |> sample([alert()],100,0)
  state.apply_review(other,selection,receipt(100),100,0) |> should.be_error
}
pub fn ack_all_requires_exact_current_set_test() {
  let s=initial()
  let selected=state.select(s,state.All(state.set_digest(s)),100,0) |> should.be_ok
  let next=sample(s,[alert(),alerts.Alert(..alert(),id:"second")],101,1000)
  state.select(next,state.All(state.set_digest(s)),101,1000) |> should.be_error
  state.apply_review(next,selected,receipt(101),101,1000) |> should.be_error
  state.entries(next) |> list.all(fn(e){e.review==None}) |> should.be_true
}
pub fn single_selection_ignores_unrelated_new_alert_test() {
  let s=initial()
  let selected=state.select(s,state.Single(entry(s).episode),100,0) |> should.be_ok
  let next=sample(s,[alert(),alerts.Alert(..alert(),id:"second")],101,1000)
    |> state.apply_review(selected,receipt(101),101,1000) |> should.be_ok
  state.entries(next) |> list.filter(fn(e){e.review!=None}) |> list.length |> should.equal(1)
}
pub fn stale_or_backward_clock_rejects_selection_test() {
  let s=initial()
  list.each([#(106,6000),#(99,0),#(100,-1),#(100,5001)],fn(t){
    state.select(s,state.All(state.set_digest(s)),t.0,t.1) |> should.be_error
  })
}
pub fn bad_observation_returns_invalidated_state_test() {
  let s=initial() |> ack(100,0)
  list.each([[alert(),alert()],[alerts.Alert(..alert(),severity:"healthy")],
    list.repeat(alert(),81),[alerts.Alert(..alert(),id:"")]],fn(rows){
    let #(next,r)=state.observe(s,rows,101,1000)
    r |> should.be_error
    state.entries(next) |> should.equal([])
    state.select(next,state.Single(entry(s).episode),101,1000) |> should.be_error
  })
}
pub fn rollback_observation_cannot_restore_ack_test() {
  let s=initial() |> ack(100,0)
  let #(lost,r)=state.observe(s,[alert()],99,1000)
  r |> should.be_error
  let next=sample(lost,[alert()],101,2000)
  entry(next).review |> should.equal(None)
}
pub fn all_marks_only_unreviewed_and_does_not_overwrite_test() {
  let a=alert()
  let s=sample(owner(),[a,alerts.Alert(..a,id:"second")],100,0)
  let one=state.select(s,state.Single(entry(s).episode),100,0) |> should.be_ok
  let t=state.apply_review(s,one,receipt(100),100,0) |> should.be_ok
  let all=state.select(t,state.All(state.set_digest(t)),101,1000) |> should.be_ok
  state.selected_episodes(all) |> list.length |> should.equal(1)
  let result=state.apply_review(t,all,state.Review(43,101,"mini-control/"<>string.repeat("c",64)),101,1000) |> should.be_ok
  entry(result).review |> should.equal(Some(receipt(100)))
  state.entries(result) |> list.all(fn(e){e.review!=None}) |> should.be_true
  state.select(result,state.All(state.set_digest(result)),101,1000) |> should.be_error
}
pub fn empty_set_cannot_be_acknowledged_test() {
  let s=sample(owner(),[],100,0)
  state.select(s,state.All(state.set_digest(s)),100,0) |> should.be_error
}
pub fn receipt_must_be_bound_and_valid_test() {
  let s=initial()
  let selection=state.select(s,state.All(state.set_digest(s)),100,0) |> should.be_ok
  list.each([state.Review(0,100,receipt(100).receipt),state.Review(42,101,receipt(100).receipt),
    state.Review(42,100,"not_a_job")],fn(r){
    state.apply_review(s,selection,r,100,0) |> should.be_error
  })
}
pub fn row_order_does_not_change_set_digest_test() {
  let a=alert()
  let s=sample(owner(),[a,alerts.Alert(..a,id:"second")],100,0)
  let t=sample(s,[alerts.Alert(..a,id:"second"),a],101,1000)
  state.set_digest(t) |> should.equal(state.set_digest(s))
}
