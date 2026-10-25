//// Serializes alert observations, durable receipt commits and uncertain-outcome recovery.
//// No scheduler or persistent task database: injected commits use canonical Sa-plan.
import cepaf_gleam/telegram/mini_alert_state as state
import cepaf_gleam/telegram/mini_alerts as alerts
import cepaf_gleam/telegram/mini_api as api
import gleam/dict
import gleam/erlang/process
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option,None,Some}
import gleam/otp/actor
import gleam/result
import gleam/string

type Name { UosMiniAlertOwner }
pub type Commit {
  Commit(run: fn() -> Result(state.Review,String),
    lookup: fn() -> Result(Option(state.Review),String))
}
pub type Message {
  Read(Int,process.Subject(api.Observation))
  Reconcile(process.Subject(Result(Nil,String)))
  Acknowledge(state.Target,Int,fn(state.Selection,Int) -> Commit,
    process.Subject(Result(state.Review,String)))
}
type Pending { Pending(selection: state.Selection,lookup: fn() -> Result(Option(state.Review),String)) }
type Owner { Owner(io: alerts.Io,state: state.State,expires: Int,pending: Option(Pending)) }
@external(erlang,"gleam_erlang_ffi","identity")
fn name(value: Name) -> process.Name(Message)
@external(erlang,"mini_control_ffi","safe_call")
fn safe_call(call: fn() -> a) -> Result(a,Nil)

pub fn start(io: alerts.Io,instance: String,expires: Int) -> actor.StartResult(process.Subject(Message)) {
  let assert Ok(initial)=state.new(instance)
  actor.new(Owner(io,initial,expires,None))
  |> actor.named(name(UosMiniAlertOwner))
  |> actor.on_message(receive)
  |> actor.start
}
fn reconcile(o: Owner) -> #(Owner,Result(Nil,String)) {
  case o.pending {
    None -> #(o,Ok(Nil))
    Some(pending) -> case pending.lookup() {
      Error(_) -> #(o,Error("alert_commit_pending"))
      Ok(None) -> #(Owner(..o,pending:None),Ok(Nil))
      Ok(Some(review)) -> {
        // Reconcile before collecting again; later observation gaps still invalidate.
        let marked=case o.io.unix_seconds()>=review.at {
          True -> state.recover_review(o.state,pending.selection,review)
          False -> Error("acknowledgement_clock_reversal")
        }
        case marked {
          Ok(s) -> #(Owner(..o,state:s,pending:None),Ok(Nil))
          Error(_) -> #(o,Error("alert_commit_pending"))
        }
      }
    }
  }
}
fn refresh(o: Owner,deadline: Int) -> #(Owner,Result(alerts.Snapshot,String)) {
  let #(o,recovered)=reconcile(o)
  let before=o.io.monotonic_ms()
  let collected={
    use _ <- result.try(recovered)
    case before<deadline && o.io.unix_seconds()<o.expires {
      True -> alerts.collect(o.io)
      False -> Error("alert_owner_expired")
    }
  }
  case collected {
    Error("alert_commit_pending") -> #(o,Error("alert_commit_pending"))
    Error(reason) -> #(Owner(..o,state:state.invalidate(o.state)),Error(reason))
    Ok(snapshot) -> {
      let after=o.io.monotonic_ms()
      case after>=before && after<deadline && o.io.unix_seconds()<o.expires {
        False -> #(Owner(..o,state:state.invalidate(o.state)),Error("alert_observation_expired"))
        True -> {
          let #(current,valid)=state.observe(o.state,snapshot.rows,snapshot.at,after)
          #(Owner(..o,state:current),result.map(valid,fn(_){snapshot}))
        }
      }
    }
  }
}
fn entry_json(e: state.Entry) -> json.Json {
  let a=e.alert
  json.object([
    #("id",json.string(a.id)),#("source",json.string(a.source)),
    #("severity",json.string(a.severity)),#("condition",json.string(a.condition)),
    #("measured",json.string(a.measured)),#("threshold",json.string(a.threshold)),
    #("episode",json.string(e.episode)),
    #("review",case e.review {
      None -> json.null()
      Some(r) -> json.object([#("user",json.int(r.user)),#("at",json.int(r.at)),#("receipt",json.string(r.receipt))])
    })
  ])
}
fn project(o: Owner,snapshot: alerts.Snapshot) -> api.Observation {
  let assert api.Observed(at,source,fields)=alerts.project(snapshot)
  let fields=dict.insert(fields,"Acknowledgement","Review only; conditions remain visible. Restart or an observation gap over 60 seconds requires re-review; historical receipts remain.")
  let fields=dict.insert(fields,"Episode set SHA256",state.set_digest(o.state))
  let fields=dict.insert(fields,"Owner incarnation",state.incarnation(o.state))
  let encoded=list.index_map(state.entries(o.state),fn(e,i){#("Alert "<>int.to_string(i+1),json.to_string(entry_json(e)))})
  case list.all(encoded,fn(p){string.byte_size(p.1)<=2048}) {
    True -> api.Observed(at,source,dict.merge(fields,dict.from_list(encoded)))
    False -> api.Unavailable("alert_review_projection_bound")
  }
}
fn receive(o: Owner,message: Message) -> actor.Next(Owner,Message) {
  case message {
    Reconcile(to) -> {
      let #(next,r)=reconcile(o)
      process.send(to,r)
      actor.continue(next)
    }
    Read(deadline,to) -> {
      let #(next,snapshot)=refresh(o,deadline)
      process.send(to,case snapshot {Ok(s)->project(next,s) Error(reason)->api.Unavailable(reason)})
      actor.continue(next)
    }
    Acknowledge(target,deadline,prepare,to) -> {
      let #(next,snapshot)=refresh(o,deadline)
      let selected={
        use _ <- result.try(snapshot)
        state.select(next.state,target,next.io.unix_seconds(),next.io.monotonic_ms())
      }
      case selected {
        Error(reason) -> {
          process.send(to,Error(reason))
          actor.continue(next)
        }
        Ok(selection) -> {
          let commit=prepare(selection,next.io.unix_seconds())
          let pending=Owner(..next,pending:Some(Pending(selection,commit.lookup)))
          case commit.run() {
            Error("alert_commit_uncertain") -> {
              process.send(to,Error("alert_commit_uncertain"))
              actor.continue(pending)
            }
            Error(reason) -> {
              process.send(to,Error(reason))
              actor.continue(next)
            }
            Ok(review) -> {
              // Even successful run is reconciled from the exact canonical receipt.
              let #(confirmed,status)=reconcile(pending)
              process.send(to,case status {Ok(_) -> Ok(review) Error(_) -> Error("alert_commit_uncertain")})
              actor.continue(confirmed)
            }
          }
        }
      }
    }
  }
}
pub fn observe(fallback: alerts.Io) -> api.Observation {
  case process.named(name(UosMiniAlertOwner)) {
    Error(_) -> alerts.observe(fallback)
    Ok(_) -> safe_call(fn(){
      process.call(process.named_subject(name(UosMiniAlertOwner)),6000,
        fn(to){Read(fallback.monotonic_ms()+5000,to)})
    }) |> result.unwrap(api.Unavailable("alert_owner_observation_unavailable"))
  }
}
pub fn reconcile_receipt() -> Result(Nil,String) {
  safe_call(fn(){
    process.call(process.named_subject(name(UosMiniAlertOwner)),5000,Reconcile)
  }) |> result.unwrap(Error("alert_owner_unavailable"))
}
pub fn acknowledge(target: state.Target,deadline: Int,
  prepare: fn(state.Selection,Int) -> Commit) -> Result(state.Review,String) {
  safe_call(fn(){
    process.call(process.named_subject(name(UosMiniAlertOwner)),45000,
      fn(to){Acknowledge(target,deadline,prepare,to)})
  }) |> result.unwrap(Error("acknowledgement_outcome_uncertain"))
}
