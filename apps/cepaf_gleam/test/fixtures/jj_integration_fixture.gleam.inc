// TEST BUILD ONLY, appended to exact production bytes. Fixture owner serializes
// calls and retains terminal cleanup uncertainty; it has no reset. This actor
// is not a production integration owner or a durable global quiescence proof.
// The parent must not trap exits/spawn untracked children. A current bounded
// synchronous exchange may finish after normal parent death; actual liveness
// is checked before EVERY new phase IPC. That check is not atomic with spawn.
// An already dispatched action cannot be undone. Restart needs quiescence.
import gleam/option.{Some, type Option}
import gleam/erlang/process
import gleam/otp/actor
@external(erlang, "telegram_store_transport_ffi", "request_config_with_cleanup")
fn fixture_exchange(local: transport.LocalConfiguration, body: String)
 -> #(Result(String, String), Option(#(Int, Int)))
type FixtureUnit { Millisecond }
@external(erlang, "erlang", "monotonic_time")
fn fixture_mono(unit: FixtureUnit) -> Int
pub opaque type FixtureOwner { FixtureOwner(process.Subject(FixtureMessage)) }
type FixtureMessage {
 FixtureProbe(Intent, Bool, Int, process.Subject(Outcome))
 FixtureDown(process.Down)
}
type FixtureState {
 FixtureState(connection: ConnectionData,
  exchange: fn(transport.LocalConfiguration,String) -> #(Result(String,String),Option(#(Int,Int))),
  terminal: Bool, parent: process.Pid)
}
fn fixture_call(intent: Intent, state: FixtureState, operation: String, deadline: Int) -> Result(#(String, String), Outcome) {
 case fixture_mono(Millisecond) < deadline && process.is_alive(state.parent) {
  False -> Error(ReconcileOnly)
  True -> {
   let ConnectionData(local) = state.connection
   let body = json.to_string(json.object([#("operation",json.string(operation)),#("intent",json.string(intent.bytes))]))
   let #(reply,cleanup) = state.exchange(local,body)
   case cleanup {
    Some(#(code,at)) if at > 0 && at <= 9_000_000_000_000_000 && {code == 0 || code == 124 || code == 125} -> {
     case reply,code {
      Ok(raw),0 -> decode_reply_data(raw,intent) |> result.map_error(fn(_){ReconcileOnly})
      _,_ -> Error(ReconcileOnly)
     }
    }
    _ -> Error(CleanupUnconfirmed)
   }
  }
 }
}
fn fixture_outcome(code: String,fact: String) -> Outcome {
 case code {
  "INTEGRATED" -> IntegratedFact(fact)
  "HISTORICAL" -> HistoricalFact(fact)
  _ -> case string.starts_with(code,"REFUSED_"){True->Refused(code) False->ReconcileOnly}
 }
}
fn fixture_work(intent:Intent,state:FixtureState,history:Bool,deadline:Int)->Outcome {
 case history {
  True -> case fixture_call(intent,state,"history",deadline) {
   Ok(#("HISTORICAL",fact))->HistoricalFact(fact)
   Ok(_)->ReconcileOnly
   Error(x)->x
  }
  False -> case fixture_call(intent,state,"reserve",deadline) {
   Ok(#("PENDING_CREATED",_))->case fixture_call(intent,state,"fast_forward",deadline) {
    Ok(#(code,fact))->fixture_outcome(code,fact)
    Error(x)->x
   }
   Ok(#(code,fact))->fixture_outcome(code,fact)
   Error(x)->x
  }
 }
}
fn fixture_handle(state:FixtureState,message:FixtureMessage)->actor.Next(FixtureState,FixtureMessage) {
 case message {
  FixtureDown(_)->actor.stop()
  FixtureProbe(intent,history,deadline,reply)->{
   let outcome=case state.terminal {True->CleanupUnconfirmed False->fixture_work(intent,state,history,deadline)}
   process.send(reply,outcome)
   actor.continue(FixtureState(..state,terminal:state.terminal || outcome==CleanupUnconfirmed))
  }
 }
}
/// Private-only injected transport is for witness-loss falsifiers, NEVER a
/// public production authority/callback constructor. Default uses REAL FFI.
pub fn fixture_start_with_exchange(connection:ConnectionData,
 exchange:fn(transport.LocalConfiguration,String)->#(Result(String,String),Option(#(Int,Int)))) -> Result(FixtureOwner,String) {
 let parent=process.self()
 actor.new_with_initialiser(1000,fn(self){
  let _=process.monitor(parent)
  let selector=process.new_selector() |> process.select(self) |> process.select_monitors(FixtureDown)
  Ok(actor.initialised(FixtureState(connection,exchange,False,parent)) |> actor.selecting(selector) |> actor.returning(self))
 }) |> actor.on_message(fixture_handle) |> actor.start
 |> result.map(fn(x){FixtureOwner(x.data)}) |> result.map_error(fn(_){"FIXTURE_OWNER_START"})
}
pub fn fixture_start(connection:ConnectionData)->Result(FixtureOwner,String){fixture_start_with_exchange(connection,fixture_exchange)}
fn fixture_request(intent:Intent,owner:FixtureOwner,history:Bool)->Outcome {
 let FixtureOwner(subject)=owner
 let reply=process.new_subject()
 process.send(subject,FixtureProbe(intent,history,fixture_mono(Millisecond)+12_000,reply))
 case process.receive(reply,15_000){Ok(x)->x Error(_)->ReconcileOnly}
}
pub fn fixture_history(intent:Intent,owner:FixtureOwner)->Outcome {fixture_request(intent,owner,True)}
pub fn fixture_integrate(intent:Intent,owner:FixtureOwner)->Outcome {fixture_request(intent,owner,False)}
pub fn fixture_process(owner:FixtureOwner)->Result(process.Pid,Nil){
 let FixtureOwner(subject)=owner
 process.subject_owner(subject)
}
