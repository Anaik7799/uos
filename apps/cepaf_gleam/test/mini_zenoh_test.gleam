import cepaf_gleam/telegram/mini_zenoh as z
import cepaf_gleam/telegram/mini_api as api
import gleam/dict
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import gleeunit/should
import mini_test_vectors as vectors

fn read(topic: Option(String)) -> api.AuthorizedRead {
  let assert Ok(config)=api.configuration("synthetic-mini-test-token",[api.AllowedIdentity(42,None)],300)
  let fields=[#("init_data",json.string(vectors.valid)),#("path",json.string("/mini-app/zenoh"))]
  let body=json.object(case topic {None -> fields Some(t) -> [#("topic",json.string(t)),..fields]}) |> json.to_string
  let assert Ok(r)=api.authorize(body,config,1000)
  r
}
fn config() -> z.Configuration {
  let assert Ok(c)=z.configuration([z.Grant(42,"test/a"),z.Grant(42,"test/b"),z.Grant(43,"test/private")])
  c
}
pub fn invalid_configuration_test() {
  z.configuration([]) |> should.be_error
  list.each(["","/a","a/","a//b","a/../b","a/*","a?x","a%2fb","a\nB"],fn(t){z.configuration([z.Grant(42,t)]) |> should.be_error})
  z.configuration([z.Grant(0,"a")]) |> should.be_error
  z.configuration([z.Grant(9007199254740992,"a")]) |> should.be_error
  z.configuration([z.Grant(42,"a"),z.Grant(42,"a")]) |> should.be_error
}
pub fn grant_limits_test() {
  let grants=list.repeat(Nil,20) |> list.index_map(fn(_,i){i+1}) |> list.map(fn(n){z.Grant(42,"key/"<>int.to_string(n))})
  z.configuration(grants) |> should.be_ok
  z.configuration([z.Grant(42,"extra"),..grants]) |> should.be_error
  z.configuration(list.repeat(Nil,257) |> list.index_map(fn(_,i){i+1}) |> list.map(fn(n){z.Grant(n,"same")})) |> should.be_error
}
pub fn topic_list_is_scoped_without_query_test() {
  let assert api.Observed(1000,"server_topic_grants",f)=z.observe(config(),read(None),fn(_){panic as "listing queried backend"},fn(){1000})
  dict.get(f,"Available topic 01") |> should.equal(Ok("test/a"))
  dict.get(f,"Topic count") |> should.equal(Ok("2"))
  dict.values(f) |> list.contains("test/private") |> should.be_false
}
pub fn forbidden_grants_never_query_test() {
  z.observe(config(),read(Some("test/private")),fn(_){panic as "cross-user query"},fn(){1000}) |> should.equal(api.Forbidden)
  let assert Ok(c)=z.configuration([z.Grant(43,"test/private")])
  z.observe(c,read(None),fn(_){panic as "ungranted query"},fn(){1000}) |> should.equal(api.Forbidden)
  z.observe(config(),read(Some("test/*")),fn(_){panic as "wildcard query"},fn(){1000}) |> should.equal(api.Forbidden)
}
pub fn selected_topic_and_value_test() {
  let assert api.Observed(1000,"zenoh_rest",f)=z.observe(config(),read(Some("test/b")),fn(key){key |> should.equal("test/b") Ok("actual value")},fn(){1000})
  dict.get(f,"Selected topic") |> should.equal(Ok("test/b"))
  dict.get(f,"Message part 01") |> should.equal(Ok("actual value"))
}
pub fn no_reply_is_distinct_from_failure_test() {
  let assert api.Observed(_,_,f)=z.observe(config(),read(Some("test/a")),fn(_){Error("zenoh_no_reply")},fn(){1000})
  dict.get(f,"Query result") |> should.equal(Ok("No retained reply"))
  z.observe(config(),read(Some("test/a")),fn(_){Error("zenoh_connect_failed")},fn(){1000}) |> should.equal(api.Unavailable("zenoh_connect_failed"))
}
pub fn unicode_and_long_graphemes_preserved_test() {
  list.each(["",string.repeat("🧪",8192),"e"<>string.repeat("́",12000),string.repeat("<script>literal</script>",400)],fn(raw){
    let assert api.Observed(_,_,f)=z.observe(config(),read(Some("test/a")),fn(_){Ok(raw)},fn(){1000})
    let parts=dict.to_list(f) |> list.filter(fn(p){string.starts_with(p.0,"Message part ")}) |> list.sort(fn(a,b){string.compare(a.0,b.0)})
    parts |> list.map(fn(p){p.1}) |> string.join("") |> should.equal(raw)
    list.all(parts,fn(p){string.byte_size(p.1)<=2048}) |> should.be_true
    {dict.size(f)<=100} |> should.be_true
  })
}
pub fn oversized_and_control_payloads_refused_test() {
  list.each([string.repeat("a",32769),"bad\u{0}","bad\u{1b}","bad\u{7f}"],fn(raw){
    case z.observe(config(),read(Some("test/a")),fn(_){Ok(raw)},fn(){1000}) {api.Unavailable(_) -> True _ -> False} |> should.be_true
  })
}
pub fn timestamp_must_be_positive_test() {
  case z.observe(config(),read(None),fn(_){panic as "query"},fn(){0}) {api.Unavailable(_) -> True _ -> False} |> should.be_true
}
pub fn topic_parameter_not_valid_on_other_pages_test() {
  let assert Ok(c)=api.configuration("synthetic-mini-test-token",[api.AllowedIdentity(42,None)],300)
  let body=json.object([#("init_data",json.string(vectors.valid)),#("path",json.string("/mini-app/chat")),#("topic",json.string("test/a"))]) |> json.to_string
  api.authorize(body,c,1000) |> should.equal(Error(api.InvalidRequest))
}
pub fn topic_parameter_size_bound_test() {
  let assert Ok(c)=api.configuration("synthetic-mini-test-token",[api.AllowedIdentity(42,None)],300)
  let body=json.object([#("init_data",json.string(vectors.valid)),#("path",json.string("/mini-app/zenoh")),#("topic",json.string(string.repeat("a",513)))]) |> json.to_string
  api.authorize(body,c,1000) |> should.equal(Error(api.InvalidRequest))
}
