import cepaf_gleam/harness/telegram_zenoh_report as r
import cepaf_gleam/harness/telegram_ingress_guard as guard
import cepaf_gleam/harness/telegram_tool_command as tool
import cepaf_gleam/zenoh/rest
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/string
import gleeunit/should

fn config()->r.Configuration {
 let assert Ok(c)=r.configuration([r.Grant(200,100,"public/test"),r.Grant(200,-300,"group/test"),r.Grant(201,100,"other/test")])
 c
}
fn no_query(_topic:String)->Result(String,String) { panic as "Unauthorized network call" }
fn clock()->Int { 1000 }
pub fn pair_scoped_listing_test(){
 let assert Ok(raw)=r.observe(config(),200,100,"",no_query,clock)
 assert string.contains(raw,"public/test")
 assert !string.contains(raw,"group/test")
 assert !string.contains(raw,"other/test")
 assert string.contains(raw,"topic_list")
}
pub fn refusal_precedes_network_test(){
 list.each([#(200,-300,"public/test"),#(201,100,"public/test"),#(0,100,""),#(200,100,"public/*"),#(200,100,"public/test extra")],fn(x){
 r.observe(config(),x.0,x.1,x.2,no_query,clock) |> should.equal(Error("zenoh_forbidden"))
 })
}
pub fn grant_validation_test(){
 r.configuration([]) |> should.be_error
 list.each([r.Grant(0,100,"a"),r.Grant(1,0,"a"),r.Grant(1,100,""),r.Grant(1,100,"a/*"),r.Grant(1,100,"a/../b"),r.Grant(1,100,"https://a")],fn(g){r.configuration([g]) |> should.be_error})
 let g=r.Grant(1,100,"a")
 r.configuration([g,g]) |> should.be_error
 r.configuration(list.repeat(g,257)) |> should.be_error
}
pub fn topic_count_bound_test(){
 let grants=list.index_map(list.repeat("x",21),fn(_,i){r.Grant(1,100,"key"<>string.repeat("a",i))})
 r.configuration(grants) |> should.be_error
}
pub fn payload_roundtrip_test(){
 let payload="a\\b\"c\n"<>string.repeat("é",100)<>"\u{1f642}"
 let assert Ok(raw)=r.observe(config(),200,100,"public/test",fn(_){Ok(payload)},clock)
 let decoder={use p<-decode.field("payload",decode.string) decode.success(p)}
 json.parse(raw,decoder) |> should.equal(Ok(payload))
 assert string.contains(raw,"NOT_GRANTED")
}
pub fn empty_and_no_reply_are_distinct_test(){
 let assert Ok(empty)=r.observe(config(),200,100,"public/test",fn(_){Ok("")},clock)
 let assert Ok(absent)=r.observe(config(),200,100,"public/test",fn(_){Error("zenoh_no_reply")},clock)
 assert string.contains(empty,"retained_reply")
 assert string.contains(empty,"\"payload\":\"\"")
 assert string.contains(absent,"no_retained_reply")
 assert !string.contains(absent,"\"payload\"")
}
pub fn invalid_payload_and_errors_test(){
 list.each([string.repeat("x",32769),"a\u{0}b","\u{1b}","\u{85}"],fn(p){
 r.observe(config(),200,100,"public/test",fn(_){Ok(p)},clock) |> should.be_error
 })
 r.observe(config(),200,100,"public/test",fn(_){Error("private_endpoint_and_credentials")},clock) |> should.equal(Error("zenoh_query_failed"))
 assert !string.contains(r.unavailable(),"private")
}
pub fn json_expansion_bound_test(){
 r.observe(config(),200,100,"public/test",fn(_){Ok(string.repeat("\\",32768))},clock) |> should.equal(Error("zenoh_output_bound"))
}
pub fn invalid_clock_precedes_network_test(){
 r.observe(config(),200,100,"public/test",no_query,fn(){0}) |> should.equal(Error("zenoh_clock"))
}
pub fn command_and_tool_selection_test(){
 guard.classify_directive("/zenoh") |> should.equal(guard.PreservedDirective("/zenoh",[""]))
 guard.classify_directive("/zenoh public/test") |> should.equal(guard.PreservedDirective("/zenoh",["public/test"]))
 guard.classify_directive("/action query_zenoh {\"topic\":\"public/test\"}") |> should.equal(guard.PreservedDirective("/zenoh",["public/test"]))
 tool.parse("query_zenoh {}") |> should.equal(Ok(tool.Zenoh("")))
 list.each(["{\"topic\":\"a/*\"}","{\"topic\":\"a\",\"chat_id\":\"1\"}","{\"endpoint\":\"http://x\"}","{\"topic\":\"\"}","{\"topic\":42}"],fn(raw){tool.parse("query_zenoh "<>raw) |> should.be_error})
}
pub fn decoder_refuses_smuggled_keys_and_multiple_samples_test(){
 let wrong="[{\"key\":\"other/test\",\"encoding\":\"text/plain\",\"value\":\"private\"}]"
 rest.decode_reply("public/test",wrong) |> should.be_error
 rest.decode_reply("public/test","[]") |> should.equal(Error("zenoh_no_reply"))
}

@external(erlang,"telegram_zenoh_test_io","set_clock")
fn set_clock(values:List(Int))->Nil
@external(erlang,"telegram_zenoh_test_io","clock")
fn sequence_clock()->Int
pub fn deadline_and_clock_regression_test(){
 list.each([[1000,5001],[1000,999]],fn(times){
  set_clock(times)
  r.observe(config(),200,100,"public/test",fn(_){Ok("payload")},sequence_clock) |> should.equal(Error("zenoh_clock_or_deadline"))
 })
 set_clock([1000,5000])
 r.observe(config(),200,100,"public/test",fn(_){Ok("payload")},sequence_clock) |> should.be_ok
}

@external(erlang,"telegram_zenoh_test_io","http_reply")
fn http_reply(status:Int,body:String)->Result(#(Int,String),String)
fn http_query(status:Int,body:String,topic:String)->Result(String,String) {
 case http_reply(status,body) {
  Ok(reply)->case rest.http_ok(reply) { Ok(raw)->rest.decode_reply(topic,raw) Error(e)->Error(e) }
  Error(e)->Error(e)
 }
}
pub fn actual_http_retained_payload_test(){
 let body="[{\"key\":\"public/test\",\"encoding\":\"text/plain\",\"value\":\"live fixture payload\"}]"
 let assert Ok(raw)=r.observe(config(),200,100,"public/test",fn(topic){http_query(200,body,topic)},clock)
 assert string.contains(raw,"live fixture payload")
 assert string.contains(raw,"\"status\":\"retained_reply\"")
}
pub fn actual_http_failure_and_no_reply_test(){
 let assert Ok(raw)=r.observe(config(),200,100,"public/test",fn(topic){http_query(200,"[]",topic)},clock)
 assert string.contains(raw,"no_retained_reply")
 list.each([#(500,"private failure"),#(200,"malformed"),#(0,""),#(200,"[{\"key\":\"other/test\",\"encoding\":\"text/plain\",\"value\":\"private\"}]")],fn(pair){
  r.observe(config(),200,100,"public/test",fn(topic){http_query(pair.0,pair.1,topic)},clock) |> should.equal(Error("zenoh_query_failed"))
 })
}
