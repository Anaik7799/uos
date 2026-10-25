//// Observed corpus search. Document claims do not grant runtime admission.
import cepaf_gleam/harness/observer_policy as policy
import gleam/json
import gleam/list
import gleam/order
import gleam/result
import gleam/string
import gleam/uri

pub type Document { Document(path: String, text: String, sha256: String, bytes: Int) }
pub type Catalog { Catalog(documents: List(Document), excluded_symlinks: Int) }

@external(erlang,"telegram_knowledge_files","catalog")
fn catalog(roots: List(#(String,String)),max_files: Int,max_bytes: Int,max_file: Int,max_depth: Int)
  -> Result(Catalog,String)

pub fn validate_query(raw: String) -> Result(String,String) {
  case string.byte_size(raw) <= 2048
    && !list.any(["\u{0}","\n","\r","\t","\u{7f}"],fn(c){string.contains(raw,c)}) {
    False -> Error("invalid_knowledge_query")
    True -> {
      let query=string.trim(raw)
      case string.byte_size(query) <= 128 {
        True -> Ok(query)
        False -> Error("invalid_knowledge_query")
      }
    }
  }
}
fn roots(view: String) -> Result(List(#(String,String)),String) {
  let wiki=#("/home/an/NAS-setup/uos/docs/wiki","docs/wiki")
  let zk=#("/home/an/NAS-setup/uos/docs/zk","docs/zk")
  case view {
    "wiki" -> Ok([wiki])
    "zk" -> Ok([zk])
    "all" -> Ok([wiki,zk])
    _ -> Error("invalid_knowledge_view")
  }
}
pub fn read(view: String,query: String) -> Result(String,String) {
  use selected <- result.try(roots(view))
  use clean <- result.try(validate_query(query))
  use observed <- result.try(catalog(selected,1024,8_388_608,262_144,4)
    |> result.replace_error("knowledge_observation_unavailable"))
  project(observed,view,clean)
}
fn valid_document(doc: Document) -> Bool {
  doc.bytes >= 0 && doc.bytes <= 262_144 && doc.bytes == string.byte_size(doc.text)
  && policy.valid_digest(doc.sha256) && string.byte_size(doc.path) <= 512
  && string.ends_with(doc.path,".md")
  && { string.starts_with(doc.path,"docs/wiki/") || string.starts_with(doc.path,"docs/zk/") }
  && list.all(string.split(doc.path,"/"),fn(p){p != "" && p != "." && p != ".."})
  && !list.any(["\u{0}","\r","\n","\t","\u{7f}"],fn(c){string.contains(doc.path,c)})
}
fn belongs(doc: Document,view: String) -> Bool {
  case view { "all" -> True _ -> string.starts_with(doc.path,"docs/" <> view <> "/") }
}
fn encode(doc: Document) -> json.Json {
  let title=string.split(doc.path,"/") |> list.last |> result.unwrap(doc.path)
  let escaped=string.split(doc.path,"/") |> list.map(uri.percent_encode) |> string.join("/")
  json.object([
    #("path",json.string(doc.path)),
    #("title",json.string(title)),
    #("url",json.string("http://nas-1.tail55d152.ts.net:4100/files/" <> escaped)),
    #("content_sha256",json.string(doc.sha256)),
    #("bytes",json.int(doc.bytes)),
  ])
}
pub fn project(observed: Catalog,view: String,query: String) -> Result(String,String) {
  use _ <- result.try(roots(view))
  use clean <- result.try(validate_query(query))
  let total_bytes=list.fold(observed.documents,0,fn(n,d){n+d.bytes})
  use _ <- result.try(case list.length(observed.documents) <= 1024
    && total_bytes <= 8_388_608 && observed.excluded_symlinks >= 0
    && list.all(observed.documents,valid_document) {
    True -> Ok(Nil)
    False -> Error("knowledge_projection_unavailable")
  })
  let docs=list.filter(observed.documents,fn(d){belongs(d,view)})
  let needle=string.lowercase(clean)
  let path_matches=fn(d: Document){string.contains(string.lowercase(d.path),needle)}
  let matches=docs |> list.filter(fn(d){
    clean == "" || path_matches(d) || string.contains(string.lowercase(d.text),needle)
  }) |> list.sort(fn(a,b){
    case path_matches(a),path_matches(b) {
      True,False -> order.Lt
      False,True -> order.Gt
      _,_ -> string.compare(a.path,b.path)
    }
  })
  let shown=list.take(matches,20)
  let rendered=json.object([
    #("schema",json.string("uos.telegram.knowledge.v1")),
    #("status",json.string("observed")),
    #("view",json.string(view)),
    #("authority",json.string("observation_only")),
    #("runtime_admission",json.string("NOT_GRANTED")),
    #("scope",json.string("observed_document_corpus")),
    #("claims_note",json.string("Document claims are historical evidence, not runtime admission.")),
    #("scanned_documents",json.int(list.length(docs))),
    #("scanned_bytes",json.int(list.fold(docs,0,fn(n,d){n+d.bytes}))),
    #("excluded_symlinks",json.int(observed.excluded_symlinks)),
    #("matched_total",json.int(list.length(matches))),
    #("shown",json.int(list.length(shown))),
    #("truncated",json.bool(list.length(matches)>list.length(shown))),
    #("results",json.array(shown,encode)),
  ]) |> json.to_string
  case string.byte_size(rendered) <= 32768 {
    True -> Ok(rendered)
    False -> Error("knowledge_projection_unavailable")
  }
}
