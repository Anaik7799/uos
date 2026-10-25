import cepaf_gleam/ha/beam_metrics as beam
import cepaf_gleam/telegram/mini_alert_owner as owner
import cepaf_gleam/telegram/mini_alert_state as state
import cepaf_gleam/telegram/mini_alerts as alerts
import cepaf_gleam/telegram/mini_api as api
import gleam/dict
import gleam/erlang/process
import gleam/int
import gleam/json
import gleam/dynamic/decode
import gleam/list
import gleam/option.{None,Some}
import gleam/otp/actor
import gleam/string
import gleeunit/should

type Control { SetReceipt(Int,process.Subject(Nil)) GetReceipt(process.Subject(Int)) Probe(process.Subject(Int)) Probes(process.Subject(Int)) }
fn control_receive(s: #(Int,Int),m: Control) {
  case m {
    SetReceipt(n,to) -> {process.send(to,Nil) actor.continue(#(n,s.1))}
    GetReceipt(to) -> {process.send(to,s.0) actor.continue(s)}
    Probe(to) -> {process.send(to,503) actor.continue(#(s.0,s.1+1))}
    Probes(to) -> {process.send(to,s.1) actor.continue(s)}
  }
}
fn fields(o: api.Observation) {let assert api.Observed(_,_,f)=o f}
fn reviewed(f: dict.Dict(String,String)) {
  f |> dict.to_list |> list.filter(fn(p){string.starts_with(p.0,"Alert ")&&p.0!="Alert count"})
  |> list.map(fn(p){json.parse(p.1,{use r <- decode.field("review",decode.optional(decode.dynamic)) decode.success(r!=None)}) |> should.be_ok})
}
pub fn actual_owner_pending_commit_reconciles_before_observation_or_mutation_test() {
  let assert Ok(ctrl)=actor.new(#(0,0)) |> actor.on_message(control_receive) |> actor.start
  let io=alerts.Io(fn(){Error("missing")},fn(_){Ok(beam.new_metrics(2,100,200,40,20,10,0,10,0,0,1000,10))},
    fn(_,_){Ok(process.call(ctrl.data,1000,Probe))},fn(){0},fn(){100})
  let assert Ok(started)=owner.start(io,string.repeat("a",64),200)
  let initial=owner.observe(io) |> fields
  let set=dict.get(initial,"Episode set SHA256") |> should.be_ok
  let review=state.Review(42,100,"mini-control/"<>string.repeat("b",64))
  let lookup=fn(){
    case process.call(ctrl.data,1000,GetReceipt) {
      1 -> Ok(Some(review))
      2 -> Ok(None)
      _ -> Error("not_observed")
    }
  }
  owner.acknowledge(state.All(set),1000,fn(_,_){
    owner.Commit(fn(){Error("alert_commit_uncertain")},lookup)
  }) |> should.equal(Error("alert_commit_uncertain"))
  let probes_before=process.call(ctrl.data,1000,Probes)
  let assert api.Unavailable("alert_commit_pending")=owner.observe(io)
  owner.acknowledge(state.All(set),1000,fn(_,_){panic as "mutation must not run while receipt is pending"})
    |> should.equal(Error("alert_commit_pending"))
  process.call(ctrl.data,1000,Probes) |> should.equal(probes_before)
  process.call(ctrl.data,1000,fn(to){SetReceipt(2,to)})
  let refused=owner.observe(io) |> fields
  reviewed(refused) |> list.all(fn(v){!v}) |> should.be_true
  process.call(ctrl.data,1000,fn(to){SetReceipt(0,to)})
  owner.acknowledge(state.All(dict.get(refused,"Episode set SHA256") |> should.be_ok),1000,fn(_,_){
    owner.Commit(fn(){Error("alert_commit_uncertain")},lookup)
  }) |> should.equal(Error("alert_commit_uncertain"))
  process.call(ctrl.data,1000,fn(to){SetReceipt(1,to)})
  let restored=owner.observe(io) |> fields
  reviewed(restored) |> list.all(fn(v){v}) |> should.be_true
  {dict.get(restored,"Episode set SHA256")!=Ok(set)} |> should.be_true
  // Recovery is idempotent; a new nonce must not write an empty acknowledgement.
  owner.reconcile_receipt() |> should.be_ok
  let latest=dict.get(restored,"Episode set SHA256") |> should.be_ok
  owner.acknowledge(state.All(latest),1000,fn(_,_){panic as "already reviewed"})
    |> should.equal(Error("already_acknowledged"))
  process.unlink(started.pid)
  process.kill(started.pid)
  process.unlink(ctrl.pid)
  process.kill(ctrl.pid)
}
