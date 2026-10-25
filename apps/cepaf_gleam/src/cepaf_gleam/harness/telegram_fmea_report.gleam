//// Recorded FMEA evidence, never invented runtime failure rates or effect authority.
import cepaf_gleam/harness/observer_policy as policy
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/result
import gleam/string

type Mode { Mode(id:String,cause:String,effect:String,controls:String,s:Int,o:Int,det:Int,rpn:Int,band:Int) }
type Assessment {
  Assessment(id:String,plan:String,task:String,observed:String,until:String,state:String,modes:List(Mode))
}
@external(erlang,"telegram_risk_files","parse_utc_ms")
fn parse_utc_ms(value:String)->Result(Int,String)

fn mode_decoder()->decode.Decoder(Mode) {
  use id <- decode.field("id",decode.string)
  use cause <- decode.field("cause",decode.string)
  use effect <- decode.field("effect",decode.string)
  use controls <- decode.field("controls",decode.string)
  use s <- decode.field("s",decode.int)
  use o <- decode.field("o",decode.int)
  use det <- decode.field("det",decode.int)
  use rpn <- decode.field("rpn",decode.int)
  use band <- decode.field("band",decode.int)
  decode.success(Mode(id,cause,effect,controls,s,o,det,rpn,band))
}
fn assessment_decoder()->decode.Decoder(Assessment) {
  use id <- decode.field("assessment_id",decode.string)
  use plan <- decode.field("plan_id",decode.string)
  use task <- decode.field("task_id",decode.string)
  use observed <- decode.field("observed_at",decode.string)
  use until <- decode.field("valid_until",decode.string)
  use state <- decode.field("task_state",decode.string)
  use modes <- decode.field("fmea_modes",decode.list(mode_decoder()))
  decode.success(Assessment(id,plan,task,observed,until,state,modes))
}
fn bounded_text(s:String,limit:Int)->Bool {
  let forbidden="\u{0}\u{1}\u{2}\u{3}\u{4}\u{5}\u{6}\u{7}\u{8}\u{b}\u{c}\u{d}\u{e}\u{f}\u{10}\u{11}\u{12}\u{13}\u{14}\u{15}\u{16}\u{17}\u{18}\u{19}\u{1a}\u{1b}\u{1c}\u{1d}\u{1e}\u{1f}\u{7f}"
  string.trim(s)!="" && string.byte_size(s)<=limit
  && !list.any(string.to_graphemes(forbidden),fn(c){string.contains(s,c)})
}
fn valid_mode(m:Mode)->Bool {
  bounded_text(m.id,128) && bounded_text(m.cause,1024) && bounded_text(m.effect,1024)
  && bounded_text(m.controls,1024) && m.s>=1 && m.s<=5 && m.o>=1 && m.o<=5
  && m.det>=1 && m.det<=5 && m.band>=1 && m.band<=5 && m.rpn==m.s*m.o*m.det
}
fn validate(a:Assessment)->Result(#(Assessment,Int,Int),String) {
  let ids=list.map(a.modes,fn(m){m.id})
  use _ <- result.try(case bounded_text(a.id,128) && policy.valid_id(a.plan) && policy.valid_id(a.task)
    && list.contains(["available","executing","completed","failed","blocked"],a.state)
    && a.modes!=[] && list.length(a.modes)<=32
    && list.length(list.unique(ids))==list.length(ids) && list.all(a.modes,valid_mode) {
    True->Ok(Nil) False->Error("invalid_fmea_record")
  })
  use observed <- result.try(parse_utc_ms(a.observed))
  use until <- result.try(parse_utc_ms(a.until))
  case observed>0 && until>observed {
    True->Ok(#(a,observed,until))
    False->Error("invalid_fmea_window")
  }
}
fn max_rpn(a:Assessment)->Int { list.fold(a.modes,0,fn(v,m){int.max(v,m.rpn)}) }
fn encode_mode(m:Mode)->json.Json {
  json.object([#("id",json.string(m.id)),#("cause",json.string(m.cause)),
    #("effect",json.string(m.effect)),#("controls",json.string(m.controls)),
    #("s",json.int(m.s)),#("o",json.int(m.o)),#("det",json.int(m.det)),
    #("rpn",json.int(m.rpn)),#("band",json.int(m.band))])
}
fn encode_row(row:#(Assessment,Int,Int),now:Int)->json.Json {
  let #(a,observed,until)=row
  let freshness=case now<observed {True->"future" False->case now>=until {True->"stale" False->"fresh"}}
  json.object([
    #("assessment_id",json.string(a.id)),#("task_id",json.string(a.task)),
    #("recorded_task_state",json.string(a.state)),
    #("observed_at",json.string(a.observed)),#("valid_until",json.string(a.until)),
    #("age_ms",case now>=observed {True->json.int(now-observed) False->json.null()}),
    #("freshness",json.string(freshness)),#("max_rpn",json.int(max_rpn(a))),
    #("fmea_modes",json.array(a.modes,encode_mode)),
  ])
}
pub fn project(raw:String,digest:String,expected_plan:String,selected_task:Option(String),now_ms:Int)
 ->Result(String,String) {
  use _ <- result.try(case string.byte_size(raw)<=1_048_576 && policy.valid_digest(digest)
    && policy.valid_id(expected_plan) && now_ms>0
    && case selected_task {None->True Some(t)->policy.valid_id(t)} {
    True->Ok(Nil) False->Error("invalid_fmea_bounds")
  })
  use records <- result.try(json.parse(raw,decode.list(assessment_decoder()))
    |> result.replace_error("invalid_fmea_json"))
  use _ <- result.try(case list.length(records)<=1000 {
    True->Ok(Nil) False->Error("fmea_record_limit")
  })
  let matching=list.filter(records,fn(a){a.plan==expected_plan})
  let ids=list.map(matching,fn(a){a.task})
  use _ <- result.try(case matching!=[] && list.length(list.unique(ids))==list.length(ids) {
    True->Ok(Nil) False->Error("missing_or_ambiguous_fmea_plan")
  })
  use checked <- result.try(list.try_map(matching,validate))
  let selected=case selected_task {None->checked Some(t)->list.filter(checked,fn(row){row.0.task==t})}
  use _ <- result.try(case selected!=[] {True->Ok(Nil) False->Error("task_not_found")})
  let sorted=list.sort(selected,fn(a,b){case int.compare(max_rpn(b.0),max_rpn(a.0)){
    order.Eq->string.compare(a.0.task,b.0.task) other->other
  }})
  let visible=list.take(sorted,5)
  let output=json.object([
    #("schema",json.string("uos.telegram.fmea.v1")),
    #("status",json.string("recorded_assessment")),
    #("authority",json.string("observation_only")),
    #("runtime_admission",json.string("NOT_GRANTED")),
    #("plan_id",json.string(expected_plan)),
    #("source_sha256",json.string(digest)),
    #("observed_at_ms",json.int(now_ms)),
    #("scope",json.string("recorded_engineering_risk_assessments")),
    #("note",json.string("S/O/Det and RPN are recorded engineering estimates, not measured runtime failure rates. File identity and assessment age do not verify underlying evidence or grant admission.")),
    #("total_matching_tasks",json.int(list.length(matching))),
    #("selected_tasks",json.int(list.length(selected))),
    #("shown",json.int(list.length(visible))),
    #("truncated",json.bool(list.length(selected)>list.length(visible))),
    #("assessments",json.array(visible,fn(row){encode_row(row,now_ms)})),
  ]) |> json.to_string
  case string.byte_size(output)<=32768 {True->Ok(output) False->Error("fmea_output_limit")}
}
