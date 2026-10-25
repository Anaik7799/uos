//// Exact-topic Telegram reads. Trusted launch configuration grants a user/chat
//// pair a bounded topic set. Observation does not grant effects or admission.
import cepaf_gleam/zenoh/rest
import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/result
import gleam/string

pub type Grant { Grant(user_id:Int, chat_id:Int, topic:String) }
pub opaque type Configuration { Configuration(grants:List(Grant)) }
pub const max_payload_bytes = 32_768
const max_id = 4_503_599_627_370_495

pub fn valid_topic(topic:String)->Bool { topic=="" || rest.valid_key(topic) }

pub fn configuration(grants:List(Grant))->Result(Configuration,String) {
 use _ <- result.try(case grants!=[] && list.length(grants)<=256 {
  True->Ok(Nil) False->Error("zenoh_grant_bound")
 })
 use _ <- result.try(validate_grants(grants,[]))
 Ok(Configuration(grants))
}
fn validate_grants(remaining:List(Grant),seen:List(Grant))->Result(Nil,String) {
 case remaining {
  []->Ok(Nil)
  [g,..tail]->{
   use _ <- result.try(case g.user_id>0 && g.user_id<=max_id
     && g.chat_id!=0 && g.chat_id>=0-max_id && g.chat_id<=max_id
     && rest.valid_key(g.topic) && !list.contains(seen,g)
     && list.length(list.filter(seen,fn(x){x.user_id==g.user_id && x.chat_id==g.chat_id}))<20 {
    True->Ok(Nil) False->Error("zenoh_grant_invalid")
   })
   validate_grants(tail,[g,..seen])
  }
 }
}
pub fn tool_topic(raw:String)->Result(String,String) {
 let raw=case raw { ""->"{}" _->raw }
 use _ <- result.try(case string.byte_size(raw)<=1024 {
  True->Ok(Nil) False->Error("Zenoh arguments exceed the bound.")
 })
 use entries <- result.try(json.parse(raw,decode.dict(decode.string,decode.string))
  |> result.replace_error("Use query_zenoh with an optional topic string only."))
 case dict.to_list(entries) {
  []->Ok("")
  [#("topic",topic)]->case rest.valid_key(topic) {
   True->Ok(topic) False->Error("Use an exact topic without wildcards or selectors.")
  }
  _->Error("Zenoh scope overrides are refused.")
 }
}

fn envelope(status:String,at_ms:Int,fields:List(#(String,json.Json)))->String {
 json.object([
  #("schema",json.string("uos.telegram.zenoh.v1")),
  #("status",json.string(status)),
  #("observed_at_ms",json.int(at_ms)),
  #("authority",json.string("observation_only")),
  #("runtime_admission",json.string("NOT_GRANTED")),
  #("scope",json.string("Granted exact-topic REST reads; no subscription, native-session, write or durability claim.")),
  ..fields
 ]) |> json.to_string
}
pub fn unavailable()->String {
 envelope("unavailable",0,[#("error",json.string("Zenoh source unavailable, invalid, oversized, timed out or outside current authority."))])
}
pub fn forbidden()->String { envelope("forbidden",0,[]) }

pub fn observe(config:Configuration,user:Int,chat:Int,topic:String,
 query:fn(String)->Result(String,String),clock_ms:fn()->Int)->Result(String,String) {
 let Configuration(grants)=config
 let topics=list.filter_map(grants,fn(g){case g.user_id==user && g.chat_id==chat {True->Ok(g.topic) False->Error(Nil)}})
 use _ <- result.try(case topics!=[] && valid_topic(topic) && {topic=="" || list.contains(topics,topic)} {
  True->Ok(Nil) False->Error("zenoh_forbidden")
 })
 let before=clock_ms()
 use _ <- result.try(case before>0 {True->Ok(Nil) False->Error("zenoh_clock")})
 case topic {
  ""->Ok(envelope("topic_list",before,[#("topics",json.array(topics,json.string))]))
  _->{
   let response=query(topic)
   let after=clock_ms()
   use _ <- result.try(case after>=before && after-before<=4000 {
    True->Ok(Nil) False->Error("zenoh_clock_or_deadline")
   })
   case response {
    Error("zenoh_no_reply")->Ok(envelope("no_retained_reply",after,[#("topic",json.string(topic)),#("source",json.string("zenoh_rest"))]))
    Error(_)->Error("zenoh_query_failed")
    Ok(payload)->{
     use _ <- result.try(case string.byte_size(payload)<=max_payload_bytes
      && list.all(string.to_utf_codepoints(payload),fn(cp){
       let n=string.utf_codepoint_to_int(cp)
       n==9 || n==10 || n==13 || n>=32 && n!=127 && !{n>=128 && n<=159}
      }) {True->Ok(Nil) False->Error("zenoh_payload_invalid")})
     let output=envelope("retained_reply",after,[#("topic",json.string(topic)),#("source",json.string("zenoh_rest")),#("payload",json.string(payload))])
     case string.byte_size(output)<=60_000 {
      True->Ok(output) False->Error("zenoh_output_bound")
     }
    }
   }
  }
 }
}
