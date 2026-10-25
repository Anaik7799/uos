//// Candidate-bound recorded verification evidence. This reader never runs gates or admits a release.
import cepaf_gleam/harness/telegram_evidence_status as evidence
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{None,Some}
import gleam/result
import gleam/string

pub const checkpoints = [
 #("CHK-01-TIME","Timestamp"),#("CHK-02-TAIL","Tailscale navigation"),
 #("CHK-03-FRACT","Fractal scope"),#("CHK-04-KM","Knowledge links"),
 #("CHK-05-MUDA","Dependency exclusions"),#("CHK-06-GRAPH","Pure graph boundary"),
 #("CHK-07-DRIVE","Storage safety"),#("CHK-08-C1C8","C1-C8 verification"),
 #("CHK-09-MATH","Mathematical gates"),#("CHK-10-9MOD","Test modalities"),
 #("CHK-11-REGR","Regression"),#("CHK-12-GLEAM","Gleam and OTP"),
 #("CHK-13-HERMES","Hermes"),#("CHK-14-ZIGVM","ZigVM"),
 #("CHK-15-MAX","Isolated inference"),#("CHK-16-OTEL","Trace correlation"),
 #("CHK-17-SOV","Independent review and admission"),#("CHK-18-JJ","Jujutsu"),
]
pub const aspects = [
 #("A01","Substrate and hardware safety"),#("A02","Version control discipline"),
 #("A03","Zero-Muda purity"),#("A04","Supervision and actor hierarchy"),
 #("A05","Deterministic runtime engine"),#("A06","Formal evidence and analysis"),
 #("A07","Mathematical authority"),#("A08","Feedback semiotics and homeostasis"),
 #("A09","Quarantined AI inference"),#("A10","Mesh telemetry and observability"),
 #("A11","Agent event bus protocol"),#("A12","Declarative UI component catalog"),
 #("A13","Multi-interface accessibility"),#("A14","Universal Tailscale web navigation"),
 #("A15","Comprehensive verification checklist"),#("A16","Knowledge management triad"),
 #("A17","Durable execution workflow"),
]
pub fn valid_scope(view:String,selector:String)->Bool {
 case view {
  "checklist"->selector==""
  "aspects"->selector=="" || list.any(aspects,fn(p){p.0==selector})
  _->False
 }
}
type Source { Source(schema:String,candidate:String,observed:Int,expires:Int,checks:List(evidence.Record),aspects:List(evidence.Record)) }
fn record_decoder() {
 use id <- decode.field("id",decode.string)
 use outcome <- decode.field("outcome",decode.string)
 use runtime <- decode.field("runtime_sha256",decode.optional(decode.string))
 use formal <- decode.field("formal_sha256",decode.optional(decode.string))
 use reason <- decode.field("reason",decode.string)
 decode.success(evidence.Record(id,outcome,runtime,formal,reason))
}
fn source_decoder() {
 use schema <- decode.field("schema",decode.string)
 use candidate <- decode.field("candidate",decode.string)
 use observed <- decode.field("observed_at_ms",decode.int)
 use expires <- decode.field("expires_at_ms",decode.int)
 use checks <- decode.field("checkpoints",decode.list(record_decoder()))
 use aspects <- decode.field("aspects",decode.list(record_decoder()))
 decode.success(Source(schema,candidate,observed,expires,checks,aspects))
}
fn valid_rows(rows:List(evidence.Record),catalog:List(#(String,String)))->Bool {
 list.length(rows)<=list.length(catalog)
 && list.length(list.unique(list.map(rows,fn(r){r.id})))==list.length(rows)
 && list.all(rows,fn(r){evidence.valid_record(r) && list.any(catalog,fn(p){p.0==r.id})})
}
fn optional_hash(h) { case h {None->json.null() Some(s)->json.string(s)} }
fn row(pair:#(String,String),records:List(evidence.Record),stale:Bool)->json.Json {
 let record=case list.find(records,fn(r){r.id==pair.0}) {
   Ok(r)->r
   Error(_)->evidence.Record(pair.0,"UNKNOWN",None,None,"No record supplied")
 }
 let present=list.any(records,fn(r){r.id==pair.0})
 json.object([
 #("id",json.string(pair.0)),#("name",json.string(pair.1)),
 #("state",json.string(case present {True->evidence.state(record,stale) False->"UNKNOWN"})),
 #("recorded_outcome",json.string(record.outcome)),#("record_present",json.bool(present)),
 #("reason",json.string(record.reason)),#("runtime_sha256",optional_hash(record.runtime_sha256)),
 #("formal_sha256",optional_hash(record.formal_sha256)),#("admission_credit",json.bool(False)),
 ])
}
pub fn project(raw:String,actual_sha:String,expected_sha:String,candidate:String,view:String,selector:String,now:Int)->Result(String,String) {
 use _ <- result.try(case string.byte_size(raw)<=65536 && evidence.valid_hex(actual_sha,64)
  && actual_sha==expected_sha && evidence.valid_hex(candidate,40) && valid_scope(view,selector)
  && now>0 && now<=9_007_199_254_740_991 {
  True->Ok(Nil) False->Error("verification_binding_refused")
 })
 use source <- result.try(json.parse(raw,source_decoder()) |> result.replace_error("verification_source_refused"))
 use _ <- result.try(case source.schema=="uos.telegram.verification-record.v1" && source.candidate==candidate
  && source.observed>0 && source.observed<=now && source.expires>source.observed
  && source.expires<=9_007_199_254_740_991 && source.expires-source.observed<=86_400_000
  && valid_rows(source.checks,checkpoints) && valid_rows(source.aspects,aspects) {
  True->Ok(Nil) False->Error("verification_source_refused")
 })
 let stale=now>=source.expires || now-source.observed>3_600_000
 let catalog=case view {"checklist"->checkpoints _->aspects}
 let selected=list.filter(catalog,fn(p){selector=="" || p.0==selector})
 let records=case view {"checklist"->source.checks _->source.aspects}
 let chosen=list.filter(records,fn(r){selector=="" || r.id==selector})
 let current_recorded_passes=case stale {True->0 False->list.count(chosen,fn(r){r.outcome=="PASS"})}
 let out=json.object([
 #("schema",json.string("uos.telegram.verification.v1")),#("status",json.string("observed")),
 #("scope",json.string("configured_candidate_record_only")),#("candidate",json.string(candidate)),
 #("view",json.string(view)),#("selector",json.string(selector)),
 #("source_sha256",json.string(actual_sha)),#("observed_at_ms",json.int(now)),
 #("record_observed_at_ms",json.int(source.observed)),#("record_expires_at_ms",json.int(source.expires)),
 #("stale",json.bool(stale)),#("catalog_size",json.int(list.length(catalog))),
 #("selected_count",json.int(list.length(selected))),#("recorded_count",json.int(list.length(chosen))),
 #("missing_count",json.int(list.length(selected)-list.length(chosen))),
 #("current_recorded_pass_count",json.int(current_recorded_passes)),
 #("rows",json.array(selected,fn(p){row(p,records,stale)})),
 #("evidence_bytes_verified",json.bool(False)),#("gates_executed",json.bool(False)),
 #("authority",json.string("observation_only")),#("runtime_admission",json.string("NOT_GRANTED")),
 #("limitation",json.string("Recorded outcomes and evidence hashes only. Referenced evidence bytes and producer authority are not verified by this read.")),
 ]) |> json.to_string
 case string.byte_size(out)<=32768 {True->Ok(out) False->Error("verification_output_bound")}
}
