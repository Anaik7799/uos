import cepaf_gleam/harness/telegram_knowledge_report as report
import cepaf_gleam/harness/telegram_tool_command as tool
import gleam/int
import gleam/list
import gleam/result
import gleam/string
import gleeunit/should

fn doc(path:String,text:String) {
  report.Document(path,text,string.repeat("a",64),string.byte_size(text))
}
pub fn query_bounds_test() {
  report.validate_query("  Mixed Case  ") |> should.equal(Ok("Mixed Case"))
  report.validate_query(string.repeat("é",64)) |> result.is_ok |> should.be_true
  list.each([string.repeat("é",65),string.repeat(" ",2049),"x\n","x\r","x\t","x\u{0}","x\u{7f}"],fn(q){
    report.validate_query(q) |> result.is_error |> should.be_true
  })
}
pub fn literal_case_insensitive_body_and_scope_test() {
  let docs=report.Catalog([doc("docs/wiki/a.md","Hello [world].*"),doc("docs/zk/b.md","Hello")],0)
  let assert Ok(raw)=report.project(docs,"wiki","[WORLD].*")
  string.contains(raw,"docs/wiki/a.md") |> should.be_true
  string.contains(raw,"docs/zk/b.md") |> should.be_false
  string.contains(raw,"Hello") |> should.be_false
  string.contains(raw,"\"matched_total\":1") |> should.be_true
  string.contains(raw,"\"runtime_admission\":\"NOT_GRANTED\"") |> should.be_true
  let assert Ok(empty)=report.project(docs,"all","absent")
  string.contains(empty,"\"results\":[]") |> should.be_true
}
pub fn bounded_ordered_results_test() {
  let docs=list.repeat(0,25) |> list.index_map(fn(_,i){doc("docs/wiki/"<>int.to_string(i)<>".md","needle")})
  let assert Ok(raw)=report.project(report.Catalog([doc("docs/wiki/needle.md","") , ..docs],2),"all","needle")
  string.contains(raw,"\"shown\":20") |> should.be_true
  string.contains(raw,"\"matched_total\":26") |> should.be_true
  string.contains(raw,"\"truncated\":true") |> should.be_true
  string.contains(raw,"\"excluded_symlinks\":2") |> should.be_true
  string.contains(raw,"\"results\":[{\"path\":\"docs/wiki/needle.md\"") |> should.be_true
}
pub fn encoded_link_test() {
  let assert Ok(raw)=report.project(report.Catalog([doc("docs/wiki/a b#?.md","")],0),"all","")
  string.contains(raw,"http://nas-1.tail55d152.ts.net:4100/files/docs/wiki/a%20b%23%3F.md") |> should.be_true
}
pub fn invalid_document_or_catalog_test() {
  list.each(["/etc/a.md","docs/wiki/../a.md","docs/wiki//a.md","docs/wiki/a\n.md","docs/wiki/a.txt"],fn(path){
    report.project(report.Catalog([doc(path,"")],0),"all","") |> result.is_error |> should.be_true
  })
  let d=doc("docs/wiki/a.md","x")
  list.each([report.Document(..d,bytes:2),report.Document(..d,sha256:"invalid")],fn(d){
    report.project(report.Catalog([d],0),"all","") |> result.is_error |> should.be_true
  })
  report.project(report.Catalog([d],-1),"all","") |> result.is_error |> should.be_true
  report.project(report.Catalog(list.repeat(d,1025),0),"all","") |> result.is_error |> should.be_true
  report.project(report.Catalog([],0),"outside","") |> result.is_error |> should.be_true
}
pub fn tool_shape_and_alias_scope_test() {
  tool.parse("query_knowledge {}") |> should.equal(Ok(tool.Knowledge("all","")))
  tool.parse("query_knowledge {\"view\":\"wiki\",\"query\":\"hello\"}") |> should.equal(Ok(tool.Knowledge("wiki","hello")))
  list.each(["{\"root\":\"/etc\"}","{\"view\":\"outside\"}","{\"query\":1}","{\"view\":null}","[]","null","{\"query\":\"a\\nb\"}"],fn(raw){
    tool.parse("query_knowledge "<>raw) |> result.is_error |> should.be_true
  })
}
