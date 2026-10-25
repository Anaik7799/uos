//// Bounded alert episode and review model. No I/O, scheduler or effect authority.
//// A review never changes the source condition. Continuity only covers observed
//// samples in one owner incarnation, with a maximum 60-second observation gap.
import cepaf_gleam/harness/files
import cepaf_gleam/telegram/mini_alerts as alerts
import gleam/dict.{type Dict}
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub type Review { Review(user: Int, at: Int, receipt: String) }
pub type Entry { Entry(alert: alerts.Alert, episode: String, review: Option(Review)) }
pub opaque type State {
  State(instance: String, sequence: Int, wall: Int, mono: Int,
    valid: Bool, entries: Dict(String,Entry))
}
pub type Target { Single(String) All(String) }
pub opaque type Selection { Selection(instance: String, target: Target, episodes: List(String)) }
pub const max_gap_ms = 60_000
pub const max_fresh_ms = 5000

fn hex(s: String,n: Int) -> Bool {
  string.byte_size(s)==n && list.all(string.to_graphemes(s),fn(c){string.contains("0123456789abcdef",c)})
}
fn require(ok: Bool,reason: String) -> Result(Nil,String) {case ok {True -> Ok(Nil) False -> Error(reason)}}
pub fn new(instance: String) -> Result(State,String) {
  use _ <- result.try(require(hex(instance,64),"invalid_owner_incarnation"))
  Ok(State(instance,0,0,0,False,dict.new()))
}
pub fn invalidate(s: State) -> State { State(..s,valid:False,entries:dict.new()) }
pub fn entries(s: State) -> List(Entry) {
  dict.values(s.entries) |> list.sort(fn(a,b){string.compare(a.alert.id,b.alert.id)})
}
pub fn incarnation(s: State) -> String {s.instance}
fn signature(a: alerts.Alert) -> String {
  files.digest(json.to_string(json.array([a.id,a.source,case a.severity {"unknown" -> "unknown_gap" _ -> "observed_condition"},a.severity,a.condition,a.threshold],json.string)))
}
fn valid_alert(a: alerts.Alert) -> Bool {
  list.contains(["critical","warning","unknown","advisory"],a.severity)
  && list.all([a.id,a.source,a.condition,a.measured,a.threshold],fn(v){string.byte_size(v)>0 && string.byte_size(v)<=600})
  && string.byte_size(json.to_string(alerts.encode(a)))<=2048
}
fn add_rows(rows: List(alerts.Alert),old: Dict(String,Entry),s: State) -> State {
  case rows {
    [] -> s
    [a,..rest] -> {
      let #(sequence,e)=case dict.get(old,a.id) {
        Ok(prior) -> case signature(prior.alert)==signature(a) {
          True -> #(s.sequence,Entry(..prior,alert:a))
          False -> next(s,a)
        }
        Error(_) -> next(s,a)
      }
      add_rows(rest,old,State(..s,sequence:sequence,entries:dict.insert(s.entries,a.id,e)))
    }
  }
}
fn next(s: State,a: alerts.Alert) -> #(Int,Entry) {
  let sequence=s.sequence+1
  let episode=files.digest(json.to_string(json.array([s.instance,int.to_string(sequence),signature(a)],json.string)))
  #(sequence,Entry(a,episode,None))
}

/// Always return the invalidated state on rejected input; callers must retain it.
pub fn observe(s: State,rows: List(alerts.Alert),wall: Int,mono: Int)
  -> #(State,Result(Nil,String)) {
  let valid=wall>0 && wall>=s.wall && {s.wall==0 || mono>=s.mono}
    && list.length(rows)<=80 && list.all(rows,valid_alert)
    && list.length(list.unique(list.map(rows,fn(a){a.id})))==list.length(rows)
    && s.sequence<=9_007_199_254_740_911
  case valid {
    False -> #(invalidate(s),Error("invalid_alert_observation"))
    True -> {
      let continuous=s.valid && mono-s.mono<=max_gap_ms
        && wall-s.wall<=60
      let old=case continuous {True -> s.entries False -> dict.new()}
      let fresh=State(..s,wall:wall,mono:mono,valid:True,entries:dict.new())
      #(add_rows(rows,old,fresh),Ok(Nil))
    }
  }
}
pub fn set_digest(s: State) -> String {
  files.digest(json.to_string(json.array([s.instance,..list.map(entries(s),fn(e){e.episode<>case e.review {None -> ":unreviewed" Some(_) -> ":reviewed"}})],json.string)))
}
pub fn select(s: State,target: Target,wall: Int,mono: Int) -> Result(Selection,String) {
  use _ <- result.try(require(s.valid && wall>=s.wall && wall-s.wall<=5
    && mono>=s.mono && mono-s.mono<=max_fresh_ms,"alert_observation_stale"))
  let selected=case target {
    Single(episode) -> case hex(episode,64) {
      True -> entries(s) |> list.filter(fn(e){e.episode==episode})
      False -> []
    }
    All(expected) -> case hex(expected,64) && expected==set_digest(s) {
      True -> entries(s)
      False -> []
    }
  }
  use _ <- result.try(require(!list.is_empty(selected),"alert_set_changed_or_empty"))
  let unreviewed=list.filter(selected,fn(e){e.review==None})
  use _ <- result.try(require(!list.is_empty(unreviewed),"already_acknowledged"))
  Ok(Selection(s.instance,target,list.map(unreviewed,fn(e){e.episode})))
}
pub fn selected_episodes(s: Selection) -> List(String) {s.episodes}

/// Apply only after the owner verifies the exact durable terminal Sa-plan receipt.
/// A different owner, intervening observation or concurrent acknowledgement refuses.
pub fn apply_review(s: State,selection: Selection,review: Review,wall: Int,mono: Int)
  -> Result(State,String) {

  use _ <- result.try(select(s,selection.target,wall,mono))
  use _ <- result.try(require(review.at<=wall,"invalid_acknowledgement_time"))
  recover_review(s,selection,review)
}

/// Receipt reconciliation before the next observation. Caller verifies the exact
/// canonical terminal receipt. No new effect occurs; a later gap still resets continuity.
pub fn recover_review(s: State,selection: Selection,review: Review) -> Result(State,String) {
  use _ <- result.try(require(selection.instance==s.instance && s.valid
    && review.user>0 && review.user<=9_007_199_254_740_991
    && review.at>=s.wall
    && string.starts_with(review.receipt,"mini-control/")
    && hex(string.drop_start(review.receipt,13),64),"invalid_acknowledgement_receipt"))
  let selected=list.filter(entries(s),fn(e){list.contains(selection.episodes,e.episode)})
  use _ <- result.try(require(!list.is_empty(selection.episodes)
    && list.length(selected)==list.length(selection.episodes)
    && list.all(selected,fn(e){e.review==None || e.review==Some(review)}),"alert_selection_changed"))
  use _ <- result.try(require(case selection.target {
    Single(episode) -> selection.episodes==[episode]
    All(expected) -> expected==set_digest(s) || list.all(selected,fn(e){e.review==Some(review)})
  },"alert_set_changed"))
  Ok(State(..s,entries:dict.map_values(s.entries,fn(_,e){
    case list.contains(selection.episodes,e.episode) {
      True -> Entry(..e,review:Some(review))
      False -> e
    }
  })))
}

pub fn selection_incarnation(s: Selection) -> String {s.instance}
