import cepaf_gleam/harness/telegram_impact_report as r
import cepaf_gleam/harness/telegram_impact_reader as reader
import cepaf_gleam/harness/telegram_ingress_guard as guard
import cepaf_gleam/harness/telegram_tool_command as tool
import cepaf_gleam/harness/files
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/string
import gleeunit/should

const candidate="1111111111111111111111111111111111111111"
const sha="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
fn node(name:String,targets:List(String))->r.Node {
 r.Node(name,sha,list.map(targets,fn(t){r.Import(t,"read",1)}))
}
fn graph()->List(r.Node) {
 // A <- B <- C; A <- D <- C; C <- B is a cycle. E has no dependents.
 [node("a",[]),node("b",["a","c"]),node("c",["b","d"]),node("d",["a"]),node("e",[])]
}
fn snapshot(nodes:List(r.Node))->String {
 json.object([
 #("schema",json.string("uos.telegram.impact-snapshot.v1")),
 #("candidate",json.string(candidate)),
 #("closure_sha256",json.string(r.closure_digest(nodes))),
 #("source_kind",json.string("compiled_beam_imports")),
 #("modules",json.array(nodes,fn(n){json.object([
  #("name",json.string(n.name)),#("beam_sha256",json.string(n.sha)),
  #("imports",json.array(n.imports,fn(i){json.preprocessed_array([json.string(i.module),json.string(i.function),json.int(i.arity)])}))
 ])}))
 ]) |> json.to_string
}
fn project(nodes:List(r.Node),target:String)->Result(String,String) {
 let raw=snapshot(nodes)
 r.project(raw,files.digest(raw),candidate,r.closure_digest(nodes),target,1000)
}
fn count(raw:String,key:String)->Int {
 let assert Ok(value)=json.parse(raw,{use v<-decode.field(key,decode.int) decode.success(v)})
 value
}
pub fn diamond_cycle_counts_test(){
 let assert Ok(raw)=project(graph(),"a")
 count(raw,"direct_dependents_count") |> should.equal(2)
 count(raw,"transitive_dependents_count") |> should.equal(1)
 count(raw,"all_dependents_count") |> should.equal(3)
 count(raw,"direct_import_references_count") |> should.equal(2)
 assert string.contains(raw,"\"transitive_dependents\":[\"c\"]")
 assert string.contains(raw,"UNASSESSED")
 assert !string.contains(raw,"safe to modify")
}
pub fn zero_and_unknown_are_distinct_test(){
 let assert Ok(zero)=project(graph(),"e")
 let assert Ok(unknown)=project(graph(),"unknown")
 count(zero,"all_dependents_count") |> should.equal(0)
 assert string.contains(zero,"\"status\":\"observed\"")
 assert string.contains(unknown,"module_not_in_snapshot")
 assert !string.contains(unknown,"all_dependents_count")
}
pub fn self_import_does_not_inflate_counts_test(){
 let nodes=[node("a",["a"]),node("b",["a","b"])]
 let assert Ok(raw)=project(nodes,"a")
 count(raw,"direct_dependents_count") |> should.equal(1)
 count(raw,"transitive_dependents_count") |> should.equal(0)
 count(raw,"direct_import_references_count") |> should.equal(1)
}
pub fn multiple_import_functions_count_exactly_test(){
 let nodes=[node("a",[]),r.Node("b",sha,[r.Import("a","x",0),r.Import("a","x",1)])]
 let assert Ok(raw)=project(nodes,"a")
 count(raw,"direct_dependents_count") |> should.equal(1)
 count(raw,"direct_import_references_count") |> should.equal(2)
}
pub fn graph_validation_test(){
 list.each([
 [],[node("a",[]),node("a",[])],[node("a",["b","b"])],
 [r.Node("a","bad",[])],[node("bad name",[])],
 [r.Node("a",sha,[r.Import("b","read",-1)])],
 [r.Node("a",sha,[r.Import("b","read",256)])]
 ],fn(nodes){project(nodes,"a") |> should.be_error})
}
pub fn canonical_closure_digest_test(){
 r.closure_digest(graph()) |> should.equal(r.closure_digest(list.reverse(graph())))
 let altered=[r.Node("a",string.repeat("b",64),[]),..list.drop(graph(),1)]
 assert r.closure_digest(graph())!=r.closure_digest(altered)
}
pub fn digest_candidate_and_closure_binding_test(){
 let raw=snapshot(graph())
 list.each([
 #(string.repeat("b",64),candidate,r.closure_digest(graph())),
 #(files.digest(raw),string.repeat("2",40),r.closure_digest(graph())),
 #(files.digest(raw),candidate,string.repeat("b",64))
 ],fn(p){r.project(raw,p.0,p.1,p.2,"a",1000) |> should.be_error})
 r.project("not json","bad",candidate,sha,"a",1000) |> should.equal(Error("impact_snapshot_binding_refused"))
}
pub fn embedded_closure_refused_test(){
 let raw=string.replace(snapshot(graph()),r.closure_digest(graph()),sha)
 r.project(raw,files.digest(raw),candidate,sha,"a",1000) |> should.equal(Error("impact_graph_refused"))
}
pub fn schema_and_extra_fields_refused_test(){
 let raw=string.replace(snapshot(graph()),"\"schema\":","\"extra\":true,\"schema\":")
 r.project(raw,files.digest(raw),candidate,r.closure_digest(graph()),"a",1000) |> should.equal(Error("impact_snapshot_invalid"))
}
pub fn byte_and_node_bounds_test(){
 let too_large=string.repeat("x",1_048_577)
 r.project(too_large,files.digest(too_large),candidate,sha,"a",1000) |> should.be_error
 project(list.repeat(node("a",[]),1025),"a") |> should.be_error
}
pub fn truncation_preserves_exact_counts_test(){
 let others=list.index_map(list.repeat("x",101),fn(_,i){node("n"<>string.repeat("x",i),["a"])})
 let assert Ok(raw)=project([node("a",[]),..others],"a")
 count(raw,"direct_dependents_count") |> should.equal(101)
 count(raw,"direct_import_references_count") |> should.equal(101)
 assert string.contains(raw,"\"lists_truncated\":true")
}
pub fn module_and_source_path_selectors_test(){
 list.each(["cepaf_gleam/harness/telegram_service","apps/cepaf_gleam/src/cepaf_gleam/harness/telegram_service.gleam","cepaf_gleam@harness@telegram_service"],fn(s){
 r.selector(s) |> should.equal(Ok("cepaf_gleam@harness@telegram_service"))
 })
 list.each(["","../a","/tmp/a","a//b","a/./b","a;halt()","a b","a\\b","a?b","a\u{0}b"],fn(s){r.selector(s) |> should.be_error})
}
pub fn command_tool_and_scope_refusal_test(){
 guard.classify_directive("/blast-radius a") |> should.equal(guard.PreservedDirective("/blast-radius",["a"]))
 guard.classify_directive("/action query_blast_radius {\"module\":\"a\"}") |> should.equal(guard.PreservedDirective("/blast-radius",["a"]))
 tool.parse("query_blast_radius {\"module\":\"a\"}") |> should.equal(Ok(tool.BlastRadius("a")))
 list.each(["{}","{\"module\":1}","{\"module\":\"a\",\"path\":\"/tmp/x\"}","{\"module\":\"../a\"}"],fn(s){r.tool_selector(s) |> should.be_error})
}
pub fn source_validation_test(){
 reader.valid_source(reader.Source("/tmp/test.json",sha,candidate,sha),True) |> should.be_true
 reader.valid_source(reader.Source("/tmp/test.json",sha,candidate,sha),False) |> should.be_false
 reader.valid_source(reader.Source("/tmp/test.json",sha,candidate,"bad"),True) |> should.be_false
}
pub fn positive_clock_required_test(){
 let raw=snapshot(graph())
 r.project(raw,files.digest(raw),candidate,r.closure_digest(graph()),"a",0) |> should.be_error
}

pub fn fixture()->String { snapshot(graph()) }
pub fn fixture_binding()->#(String,String) { #(candidate,r.closure_digest(graph())) }
