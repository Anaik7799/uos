//// Static compiled dependency impact, never dynamic reachability or safety approval.
import cepaf_gleam/harness/files
import cepaf_gleam/harness/telegram_evidence_status as evidence
import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/result
import gleam/string

pub type Import { Import(module:String,function:String,arity:Int) }
pub type Node { Node(name:String,sha:String,imports:List(Import)) }
pub type Graph { Graph(candidate:String,closure_sha256:String,nodes:List(Node)) }

fn valid_name(name:String)->Bool {
 string.byte_size(name)>0 && string.byte_size(name)<=240
 && list.all(string.to_graphemes(name),fn(c){string.contains("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_@.",c)})
}
fn valid_function(name:String)->Bool {
 string.byte_size(name)>0 && string.byte_size(name)<=128
 && list.all(string.to_utf_codepoints(name),fn(cp){let n=string.utf_codepoint_to_int(cp) n>=33 && n<=126})
}
pub fn selector(raw:String)->Result(String,String) {
 let name=case string.starts_with(raw,"apps/cepaf_gleam/src/") {
  True->string.drop_start(raw,string.length("apps/cepaf_gleam/src/")) False->raw
 }
 let name=case string.ends_with(name,".gleam") {
  True->string.drop_end(name,6)
  False->case string.ends_with(name,".erl") {True->string.drop_end(name,4) False->name}
 }
 let parts=string.split(name,"/")
 let module=string.replace(name,"/","@")
 case string.byte_size(raw)<=512 && valid_name(module)
  && list.all(parts,fn(p){p!="" && p!="." && p!=".." && !string.contains(p,".")}) {
  True->Ok(module) False->Error("Use an exact Gleam module or apps/cepaf_gleam/src file path.")
 }
}
pub fn tool_selector(raw:String)->Result(String,String) {
 use _ <- result.try(case string.byte_size(raw)<=1024 {True->Ok(Nil) False->Error("Impact arguments exceed bounds.")})
 use fields <- result.try(json.parse(raw,decode.dict(decode.string,decode.string)) |> result.replace_error("Expected only a module string."))
 case dict.to_list(fields) {
  [#("module",name)]->selector(name)
  _->Error("Expected exactly one module field; scope overrides refused.")
 }
}
fn keys(expected:List(String))->decode.Decoder(Nil) {
 decode.then(decode.dict(decode.string,decode.dynamic),fn(fields){
  case list.sort(dict.keys(fields),string.compare)==list.sort(expected,string.compare) {
   True->decode.success(Nil) False->decode.failure(Nil,"exact keys")
  }
 })
}
fn import_decoder()->decode.Decoder(Import) {
 decode.then(decode.list(decode.dynamic),fn(fields){
  case fields {
   [m,f,a]->case decode.run(m,decode.string),decode.run(f,decode.string),decode.run(a,decode.int) {
    Ok(m),Ok(f),Ok(a)->decode.success(Import(m,f,a))
    _,_,_->decode.failure(Import("","",0),"import triple")
   }
   _->decode.failure(Import("","",0),"import triple")
  }
 })
}
fn node_decoder()->decode.Decoder(Node) {
 use _ <- decode.then(keys(["name","beam_sha256","imports"]))
 use name <- decode.field("name",decode.string)
 use sha <- decode.field("beam_sha256",decode.string)
 use imports <- decode.field("imports",decode.list(import_decoder()))
 decode.success(Node(name,sha,imports))
}
fn graph_decoder()->decode.Decoder(Graph) {
 use _ <- decode.then(keys(["schema","candidate","closure_sha256","source_kind","modules"]))
 use schema <- decode.field("schema",decode.string)
 use candidate <- decode.field("candidate",decode.string)
 use closure <- decode.field("closure_sha256",decode.string)
 use source <- decode.field("source_kind",decode.string)
 use nodes <- decode.field("modules",decode.list(node_decoder()))
 case schema=="uos.telegram.impact-snapshot.v1" && source=="compiled_beam_imports" {
  True->decode.success(Graph(candidate,closure,nodes))
  False->decode.failure(Graph("","",[]),"impact snapshot")
 }
}
fn unique(items:List(a))->Bool {
 dict.size(dict.from_list(list.map(items,fn(x){#(x,True)})))==list.length(items)
}
pub fn closure_digest(nodes:List(Node))->String {
 list.sort(nodes,fn(a,b){string.compare(a.name,b.name)})
 |> json.array(fn(n){json.array([n.name,n.sha],json.string)})
 |> json.to_string |> files.digest
}
pub fn validate(graph:Graph)->Bool {
 evidence.valid_hex(graph.candidate,40) && evidence.valid_hex(graph.closure_sha256,64)
 && closure_digest(graph.nodes)==graph.closure_sha256
 && graph.nodes!=[] && list.length(graph.nodes)<=1024
 && unique(list.map(graph.nodes,fn(n){n.name}))
 && list.fold(graph.nodes,0,fn(total,n){total+list.length(n.imports)})<=32768
 && list.all(graph.nodes,fn(n){
  valid_name(n.name) && evidence.valid_hex(n.sha,64) && list.length(n.imports)<=2048
  && unique(n.imports)
  && list.all(n.imports,fn(i){valid_name(i.module) && valid_function(i.function) && i.arity>=0 && i.arity<=255})
 })
}
fn reverse_edges(nodes:List(Node))->Dict(String,Dict(String,Bool)) {
 list.fold(nodes,dict.new(),fn(edges,node){
  list.fold(node.imports,edges,fn(acc,i){
   let prior=dict.get(acc,i.module) |> result.unwrap(dict.new())
   dict.insert(acc,i.module,dict.insert(prior,node.name,True))
  })
 })
}
fn reachable(queue:List(String),edges:Dict(String,Dict(String,Bool)),seen:Dict(String,Bool))->Dict(String,Bool) {
 case queue {
  []->seen
  [name,..rest]->case dict.has_key(seen,name) {
   True->reachable(rest,edges,seen)
   False->{
    let next=dict.get(edges,name) |> result.unwrap(dict.new()) |> dict.keys
    reachable(list.append(rest,next),edges,dict.insert(seen,name,True))
   }
  }
 }
}
fn names(values:List(String))->json.Json { json.array(list.take(values,100),json.string) }
fn import_json(pair:#(String,Import))->json.Json {
 json.object([#("dependent",json.string(pair.0)),#("function",json.string(pair.1.function)),#("arity",json.int(pair.1.arity))])
}
pub fn project(raw:String,expected_sha:String,candidate:String,expected_closure:String,target:String,at_ms:Int)->Result(String,String) {
 use _ <- result.try(case string.byte_size(raw)<=1_048_576 && at_ms>0
  && evidence.valid_hex(expected_closure,64) && evidence.valid_hex(expected_sha,64) && evidence.valid_hex(candidate,40)
  && files.digest(raw)==expected_sha {True->Ok(Nil) False->Error("impact_snapshot_binding_refused")})
 use module <- result.try(selector(target))
 use graph <- result.try(json.parse(raw,graph_decoder()) |> result.replace_error("impact_snapshot_invalid"))
 use _ <- result.try(case validate(graph) && graph.candidate==candidate && graph.closure_sha256==expected_closure {True->Ok(Nil) False->Error("impact_graph_refused")})
 let edges=reverse_edges(graph.nodes)
 let known=list.any(graph.nodes,fn(n){n.name==module})
 let base=[
  #("schema",json.string("uos.telegram.impact.v1")),
  #("candidate",json.string(candidate)),
  #("snapshot_sha256",json.string(expected_sha)),
  #("closure_sha256",json.string(expected_closure)),
  #("module",json.string(module)),
  #("observed_at_ms",json.int(at_ms)),
  #("authority",json.string("observation_only")),
  #("runtime_admission",json.string("NOT_GRANTED")),
  #("source_kind",json.string("compiled_beam_imports")),
  #("snapshot_module_count",json.int(list.length(graph.nodes))),
  #("scope",json.string("Static import references in this compiled snapshot only; no live source scan or safe-to-modify conclusion.")),
  #("dynamic_calls",json.string("UNASSESSED")),
  #("caller_function_graph",json.string("UNASSESSED")),
  #("test_and_contract_coverage",json.string("UNASSESSED"))
 ]
 case known {
  False->Ok(json.object([#("status",json.string("module_not_in_snapshot")),..base]) |> json.to_string)
  True->{
   let direct=dict.get(edges,module) |> result.unwrap(dict.new()) |> dict.delete(module) |> dict.keys |> list.sort(string.compare)
   let impacted=reachable(direct,edges,dict.from_list([#(module,True)])) |> dict.delete(module) |> dict.keys |> list.sort(string.compare)
   let direct_set=dict.from_list(list.map(direct,fn(n){#(n,True)}))
   let transitive=list.filter(impacted,fn(n){!dict.has_key(direct_set,n)})
   let refs=list.flat_map(graph.nodes,fn(n){
    list.filter_map(n.imports,fn(i){case i.module==module && n.name!=module {True->Ok(#(n.name,i)) False->Error(Nil)}})
   })
   let output=json.object([
    #("status",json.string("observed")),
    #("direct_dependents_count",json.int(list.length(direct))),
    #("all_dependents_count",json.int(list.length(impacted))),
    #("transitive_scope",json.string("Indirect-only module dependents; direct dependents excluded. No caller-function attribution.")),
    #("transitive_dependents_count",json.int(list.length(transitive))),
    #("direct_dependents",names(direct)),
    #("transitive_dependents",names(transitive)),
    #("direct_import_references_count",json.int(list.length(refs))),
    #("direct_import_references",json.array(list.take(refs,100),import_json)),
    #("lists_truncated",json.bool(list.length(direct)>100 || list.length(transitive)>100 || list.length(refs)>100)),
    ..base
   ]) |> json.to_string
   case string.byte_size(output)<=60_000 {True->Ok(output) False->Error("impact_output_bound")}
  }
 }
}
pub fn unavailable()->String {
 json.object([#("schema",json.string("uos.telegram.impact.v1")),#("status",json.string("unavailable")),
 #("error",json.string("Configured compiled dependency snapshot unavailable, invalid, changed or outside authority.")),
 #("authority",json.string("observation_only")),#("runtime_admission",json.string("NOT_GRANTED"))]) |> json.to_string
}
