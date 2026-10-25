//// Pure data contract for forthcoming /verify execution. No IO or authority.
//// A caller must independently pin actual profile/source/executable/evidence
//// bytes and observe process/job/task/runtime fences. These values cannot grant
//// execution or admission. This module is not a verification executor.
import cepaf_gleam/harness/files
import cepaf_gleam/harness/telegram_store_codec as codec
import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/result
import gleam/string

pub type Gate {
  Gate(id: String, executable_sha256: String, input_sha256: String, timeout_ms: Int)
}
pub opaque type Profile {
  Profile(id: String, candidate: String, closure: String, gates: List(Gate),
    timeout_ms: Int, digest: String)
}
pub type Binding {
  Binding(request_id: String, job_id: String, attempt: Int,
    profile_sha256: String, candidate: String, source_closure_sha256: String)
}
pub type ProcessObservation {
  ProcessObservation(exit_code: Int, timed_out: Bool, reaped: Bool, elapsed_ms: Int)
}
pub type Assessment {
  VerifiedEvidence
  Failed(String)
  Indeterminate(String)
}
type Row {
  Row(id: String, executable: String, input: String, status: String,
    evidence: String, elapsed: Int)
}
type Receipt { Receipt(schema: String, binding: Binding, gates: List(Row)) }

fn hex(value: String,n: Int) -> Bool {
  string.byte_size(value)==n && list.all(string.to_graphemes(value),
    fn(c) { string.contains("0123456789abcdef",c) })
}
fn token(value: String,limit: Int,extra: String) -> Bool {
  string.byte_size(value)>0 && string.byte_size(value)<=limit
  && list.all(string.to_graphemes(value),fn(c) {
    string.contains("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_"<>extra,c)
  })
}
fn require(ok: Bool,reason: String) -> Result(Nil,String) {
  case ok { True->Ok(Nil) False->Error(reason) }
}
fn unique(values: List(String)) -> Bool {
  dict.size(dict.from_list(list.map(values,fn(v) { #(v,Nil) })))==list.length(values)
}
fn gate_json(g: Gate) -> json.Json {
  json.object([#("id",json.string(g.id)),
    #("executable_sha256",json.string(g.executable_sha256)),
    #("input_sha256",json.string(g.input_sha256)),#("timeout_ms",json.int(g.timeout_ms))])
}
fn encode_profile(id: String,candidate: String,closure: String,gates: List(Gate),timeout: Int) -> String {
  json.object([#("schema",json.string("uos.telegram.verify-profile.v1")),
    #("profile_id",json.string(id)),#("candidate",json.string(candidate)),
    #("source_closure_sha256",json.string(closure)),
    #("required_gates",json.array(gates,gate_json)),#("total_timeout_ms",json.int(timeout))])
    |> json.to_string
}
/// Validates data, not provenance. Trusted loaders must verify the raw artifact
/// digest and the executable/input closure before an execution is authorized.
pub fn profile(id: String,candidate: String,closure: String,gates: List(Gate),
  total_timeout_ms: Int) -> Result(Profile,String) {
  use _ <- result.try(require(token(id,80,"") && {hex(candidate,40)||hex(candidate,64)}
    && hex(closure,64) && total_timeout_ms>0 && total_timeout_ms<=120_000,
    "invalid_profile"))
  use _ <- result.try(require(gates!=[] && list.length(gates)<=64
    && unique(list.map(gates,fn(g) { g.id }))
    && list.all(gates,fn(g) { token(g.id,80,"") && hex(g.executable_sha256,64)
      && hex(g.input_sha256,64) && g.timeout_ms>0 && g.timeout_ms<=30_000 })
    && list.fold(gates,0,fn(sum,g) { sum+g.timeout_ms })<=total_timeout_ms,
    "invalid_gate_set"))
  let sorted=list.sort(gates,fn(a,b) { string.compare(a.id,b.id) })
  let digest=files.digest(encode_profile(id,candidate,closure,sorted,total_timeout_ms))
  Ok(Profile(id,candidate,closure,sorted,total_timeout_ms,digest))
}
pub fn canonical_json(p: Profile) -> String {
  encode_profile(p.id,p.candidate,p.closure,p.gates,p.timeout_ms)
}
pub fn profile_digest(p: Profile) -> String { p.digest }
pub fn required_gates(p: Profile) -> List(Gate) { p.gates }
pub fn timeout_ms(p: Profile) -> Int { p.timeout_ms }

fn job_id(p: Profile,request_id: String) -> String {
  "telegram/verify/"<>files.digest(json.object([
    #("request_id",json.string(request_id)),#("profile_sha256",json.string(p.digest))
  ]) |> json.to_string)
}
/// The caller must first persist a unique reservation keyed by inbox identity.
/// Recovery must reload that reservation, never resolve a changed profile to
/// create a second job for the same inbox request.
pub fn binding(p: Profile,request_id: String,attempt: Int) -> Result(Binding,String) {
  use _ <- result.try(require(token(request_id,240,"./:") && attempt>0
    && attempt<=2_147_483_647,"invalid_request_binding"))
  Ok(Binding(request_id,job_id(p,request_id),attempt,p.digest,p.candidate,p.closure))
}
fn valid_binding(p: Profile,b: Binding) -> Bool {
  binding(p,b.request_id,b.attempt)==Ok(b)
}
fn row_decoder() {
  use id <- decode.field("id",decode.string)
  use executable <- decode.field("executable_sha256",decode.string)
  use input <- decode.field("input_sha256",decode.string)
  use status <- decode.field("status",decode.string)
  use evidence <- decode.field("evidence_sha256",decode.string)
  use elapsed <- decode.field("elapsed_ms",decode.int)
  decode.success(Row(id,executable,input,status,evidence,elapsed))
}
fn receipt_decoder() {
  use schema <- decode.field("schema",decode.string)
  use request <- decode.field("request_id",decode.string)
  use job <- decode.field("job_id",decode.string)
  use attempt <- decode.field("attempt",decode.int)
  use digest <- decode.field("profile_sha256",decode.string)
  use candidate <- decode.field("candidate",decode.string)
  use closure <- decode.field("source_closure_sha256",decode.string)
  use gates <- decode.field("gates",decode.list(row_decoder()))
  decode.success(Receipt(schema,Binding(request,job,attempt,digest,candidate,closure),gates))
}
fn valid_row(p: Profile,row: Row) -> Bool {
  case list.find(p.gates,fn(g) { g.id==row.id }) {
    Error(_) -> False
    Ok(gate) -> row.executable==gate.executable_sha256
      && row.input==gate.input_sha256 && hex(row.evidence,64)
      && list.contains(["PASS","FAIL","ERROR","SKIPPED"],row.status)
      && row.elapsed>=0 && row.elapsed<=gate.timeout_ms
  }
}
fn closed(fields: List(#(String,codec.StrictJsonValue)),keys: List(String)) -> Bool {
  let observed=list.map(fields,fn(f) { f.0 })
  list.length(observed)==list.length(keys) && unique(observed)
    && list.all(observed,fn(k) { list.contains(keys,k) })
}
fn valid_shape(raw: String) -> Bool {
  case codec.parse_strict_json(raw) {
    Ok(codec.JsonObject(fields)) -> closed(fields,["schema","request_id","job_id","attempt","profile_sha256","candidate","source_closure_sha256","gates"])
      && case list.key_find(fields,"gates") {
        Ok(codec.JsonArray(rows)) -> list.length(rows)<=64 && list.all(rows,fn(row) {
          case row {
            codec.JsonObject(values) -> closed(values,["id","executable_sha256","input_sha256","status","evidence_sha256","elapsed_ms"])
            _ -> False
          }
        })
        _ -> False
      }
    _ -> False
  }
}
fn assess_receipt(p: Profile,b: Binding,elapsed: Int,raw: String) -> Assessment {
  case json.parse(raw,receipt_decoder()) {
    Error(_) -> Failed("malformed_receipt")
    Ok(r) -> case r.schema=="uos.telegram.verify-result.v1" && r.binding==b {
      False -> Failed("receipt_binding_mismatch")
      True -> case list.length(r.gates)==list.length(p.gates)
        && unique(list.map(r.gates,fn(g) { g.id }))
        && list.all(r.gates,fn(g) { valid_row(p,g) })
        && list.fold(r.gates,0,fn(sum,g) { sum+g.elapsed })<=elapsed {
        False -> Failed("gate_receipt_incomplete_or_invalid")
        True -> case list.all(r.gates,fn(g) { g.status=="PASS" }) {
          True -> VerifiedEvidence
          False -> Failed("gate_not_passed")
        }
      }
    }
  }
}
/// Classifies only an already observed execution. A digest's shape is checked
/// here, not its artifact bytes. A real supervisor must bind these observations
/// and preserve raw/partial failures outside public Telegram output.
pub fn assess(p: Profile,b: Binding,process: ProcessObservation,raw: String) -> Assessment {
  case valid_binding(p,b) {
    False -> Failed("invalid_expected_binding")
    True -> case process.reaped {
      False -> Indeterminate("process_not_reaped")
      True -> case process.elapsed_ms<0 {
        True -> Indeterminate("process_time_unknown")
        False -> case process.timed_out || process.elapsed_ms>p.timeout_ms {
          True -> Failed("process_deadline_exceeded")
          False -> case process.exit_code!=0 {
            True -> Failed("process_exit_nonzero")
            False -> case string.byte_size(raw)>0 && string.byte_size(raw)<=65_536 {
              False -> Failed("receipt_size_refused")
              True -> case valid_shape(raw) {
                False -> Failed("invalid_receipt_shape")
                True -> assess_receipt(p,b,process.elapsed_ms,raw)
              }
            }
          }
        }
      }
    }
  }
}
