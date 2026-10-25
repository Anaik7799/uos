//// Local participant snapshot. Historical ANDON records never establish live service health.
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

@external(erlang,"telegram_matrix_http","get_snapshot")
fn get(host:String,port:Int,path:String,timeout:Int,max_bytes:Int)->Result(String,String)
@external(erlang,"telegram_ecology_clock","now_ms")
fn now_ms()->Int

type Holon { Holon(id:String,kind:String,external:Bool,plane:String,level:Int,lifecycle:String,mode:String) }
type Andon { Andon(capability:String,phase:String,failures:Int,attempts:Int,recoveries:Int,recovered:Option(Int),failed:Option(Int)) }
type Snapshot { Snapshot(epoch:Int,cycle:Int,total:Int,kind:String,hosting:String,external:Bool,harmonic:Bool,holons:List(Holon),andon:List(Andon)) }

fn holon_decoder() {
 use id <- decode.field("id",decode.string)
 use kind <- decode.field("participant_kind",decode.string)
 use external <- decode.field("external_system_binding",decode.bool)
 use plane <- decode.field("plane",decode.string)
 use level <- decode.field("level",decode.int)
 use lifecycle <- decode.field("lifecycle",decode.string)
 use mode <- decode.field("mode",decode.string)
 decode.success(Holon(id,kind,external,plane,level,lifecycle,mode))
}
fn event_decoder() {
 use time <- decode.field("observed_at_us",decode.int)
 decode.success(time)
}
fn andon_decoder() {
 use capability <- decode.field("capability",decode.string)
 use phase <- decode.field("phase",decode.string)
 use failures <- decode.field("failure_count",decode.int)
 use attempts <- decode.field("recovery_attempts",decode.int)
 use recoveries <- decode.field("recovery_count",decode.int)
 use recovered <- decode.field("last_recovery",decode.optional(event_decoder()))
 use failed <- decode.field("last_failure",decode.optional(event_decoder()))
 decode.success(Andon(capability,phase,failures,attempts,recoveries,recovered,failed))
}
fn decoder() {
 use epoch <- decode.field("epoch_us",decode.int)
 use cycle <- decode.field("cycle_counter",decode.int)
 use total <- decode.field("total_holons",decode.int)
 use kind <- decode.field("participant_kind",decode.string)
 use hosting <- decode.field("hosting",decode.string)
 use external <- decode.field("external_system_binding",decode.bool)
 use harmonic <- decode.field("is_harmonic",decode.bool)
 use holons <- decode.field("holons",decode.list(holon_decoder()))
 use andon <- decode.field("service_andon",decode.list(andon_decoder()))
 decode.success(Snapshot(epoch,cycle,total,kind,hosting,external,harmonic,holons,andon))
}
fn identifier(s:String)->Bool {
 string.byte_size(s)>0 && string.byte_size(s)<=64
 && list.all(string.to_graphemes(s),fn(c){string.contains("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-",c)})
}
fn count(n:Int)->Bool { n>=0 && n<=9_007_199_254_740_991 }
fn positive(n:Int)->Bool { n>0 && count(n) }
fn timestamp(t:Option(Int))->Bool { case t {None->True Some(n)->positive(n)} }
fn valid(s:Snapshot)->Bool {
 positive(s.epoch) && count(s.cycle) && s.total>=1 && s.total<=128
 && list.length(s.holons)==s.total && s.kind=="local_agentic_model"
 && s.hosting=="one_shared_ecology_actor" && !s.external
 && list.length(list.unique(list.map(s.holons,fn(h){h.id})))==s.total
 && list.all(s.holons,fn(h){
   identifier(h.id) && h.kind=="local_agentic_model" && !h.external
   && identifier(h.plane) && h.level>=0 && h.level<=9
   && identifier(h.lifecycle) && identifier(h.mode)
 })
 && list.length(s.andon)<=32
 && list.length(list.unique(list.map(s.andon,fn(a){a.capability})))==list.length(s.andon)
 && list.all(s.andon,fn(a){
   identifier(a.capability) && identifier(a.phase)
   && count(a.failures) && count(a.attempts) && count(a.recoveries)
   && timestamp(a.recovered) && timestamp(a.failed)
 })
}
fn nullable(t:Option(Int))->json.Json { case t {None->json.null() Some(n)->json.int(n)} }
fn holon_json(h:Holon)->json.Json {json.object([
 #("id",json.string(h.id)),#("plane",json.string(h.plane)),#("level",json.int(h.level)),
 #("lifecycle",json.string(h.lifecycle)),#("mode",json.string(h.mode)),
])}
fn andon_json(a:Andon)->json.Json {json.object([
 #("capability",json.string(a.capability)),#("reported_phase",json.string(a.phase)),
 #("failure_count",json.int(a.failures)),#("recovery_attempts",json.int(a.attempts)),
 #("recovery_count",json.int(a.recoveries)),#("last_recovery_at_us",nullable(a.recovered)),
 #("last_failure_at_us",nullable(a.failed)),
])}
pub fn project(raw:String,observed_at_ms:Int)->Result(String,String) {
 use _ <- result.try(case string.byte_size(raw)<=131072 && positive(observed_at_ms) {
   True->Ok(Nil) False->Error("ecology_payload_refused")
 })
 use s <- result.try(json.parse(raw,decoder()) |> result.replace_error("ecology_payload_refused"))
 use _ <- result.try(case valid(s) {True->Ok(Nil) False->Error("ecology_payload_refused")})
 let age=observed_at_ms-s.epoch/1000
 let future=s.epoch>observed_at_ms*1000
 let freshness=case future,age<=30000 {True,_->"future" False,True->"fresh" False,False->"stale"}
 let rendered=json.object([
 #("schema",json.string("uos.telegram.ecology.v1")),#("status",json.string("observed")),
 #("authority",json.string("observation_only")),#("runtime_admission",json.string("NOT_GRANTED")),
 #("endpoint",json.string("http://nas-1.tail55d152.ts.net:4110/api/v1/ecology/swarm")),
 #("scope",json.string("local_participant_plane_not_service_admission")),
 #("observed_at_ms",json.int(observed_at_ms)),#("source_epoch_us",json.int(s.epoch)),
 #("snapshot_age_ms",case future {True->json.null() False->json.int(age)}),
 #("freshness",json.string(freshness)),#("cycle_counter",json.int(s.cycle)),
 #("reported_holons",json.int(s.total)),#("total_holons",json.int(list.length(s.holons))),
 #("hosting",json.string(s.hosting)),#("participant_kind",json.string(s.kind)),
 #("external_system_binding",json.bool(False)),#("reported_harmonic",json.bool(s.harmonic)),
 #("service_health",json.string("UNVERIFIED")),
 #("participants",json.array(s.holons,holon_json)),#("andon",json.array(s.andon,andon_json)),
 ]) |> json.to_string
 case string.byte_size(rendered)<=32768 {True->Ok(rendered) False->Error("ecology_payload_refused")}
}
pub fn read()->Result(String,String) {
 use raw <- result.try(get("nas-1.tail55d152.ts.net",4110,"/api/v1/ecology/swarm",1500,131072) |> result.replace_error("ecology_read_unavailable"))
 project(raw,now_ms())
}
