//// Current operational brief from pinned observer outputs; no inferred health.
import gleam/dict
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{None, Some, type Option}
import gleam/result
import gleam/string

pub const schema = "uos.telegram.exec-brief.v1"
const states = ["available", "executing", "completed", "failed", "blocked"]
const endpoints = ["matrix", "cockpit", "zenoh", "peer_runtime"]
type Task { Task(id: String, state: String) }
type Tasks { Tasks(observer: String, authority: String, admission: String,
  plan: String, total: Int, selected: Int, digest: String, rows: List(Task)) }
type Service { Service(name: String, state: String, code: Option(Int), elapsed: Int) }
type Status { Status(schema: String, state: String, scope: String, admission: String,
  global_healthy: Option(Bool), observed: Int, services: List(Service),
  epoch: Int, generation: Int, offset: Int, recovery: Bool, conversation: Bool,
  model: String) }

fn task_decoder() -> decode.Decoder(Task) {
  use id <- decode.field("task_id",decode.string)
  use state <- decode.field("state",decode.string)
  decode.success(Task(id,state))
}
fn tasks_decoder() -> decode.Decoder(Tasks) {
  use observer <- decode.field("observer",decode.string)
  use authority <- decode.field("authority",decode.string)
  use admission <- decode.field("runtime_admission",decode.string)
  use plan <- decode.field("plan_id",decode.string)
  use total <- decode.field("observed_tasks_total",decode.int)
  use selected <- decode.field("selected_count",decode.int)
  use digest <- decode.field("full_observation_sha256",decode.string)
  use rows <- decode.field("tasks",decode.list(task_decoder()))
  decode.success(Tasks(observer,authority,admission,plan,total,selected,digest,rows))
}
fn service_decoder() -> decode.Decoder(Service) {
  use name <- decode.field("service",decode.string)
  use state <- decode.field("observation",decode.string)
  use code <- decode.field("http_status",decode.optional(decode.int))
  use elapsed <- decode.field("elapsed_ms",decode.int)
  decode.success(Service(name,state,code,elapsed))
}
fn status_decoder() -> decode.Decoder(Status) {
  use schema <- decode.field("schema",decode.string)
  use state <- decode.field("status",decode.string)
  use scope <- decode.field("scope",decode.string)
  use admission <- decode.field("runtime_admission",decode.string)
  use global_healthy <- decode.field("global_healthy",decode.optional(decode.bool))
  use observed <- decode.field("observed_at_us",decode.int)
  use services <- decode.field("services",decode.list(service_decoder()))
  use epoch <- decode.subfield(["telegram","service_epoch"],decode.int)
  use generation <- decode.subfield(["telegram","store_generation"],decode.int)
  use offset <- decode.subfield(["telegram","next_update_offset"],decode.int)
  use recovery <- decode.subfield(["telegram","pending_recovery"],decode.bool)
  use conversation <- decode.subfield(["telegram","conversation_configured"],decode.bool)
  use model <- decode.subfield(["telegram","model_connectivity"],decode.string)
  decode.success(Status(schema,state,scope,admission,global_healthy,observed,services,
    epoch,generation,offset,recovery,conversation,model))
}
fn require(value: Bool) -> Result(Nil,String) {
  case value { True -> Ok(Nil) False -> Error("brief_observation_invalid") }
}
fn id(value: String) -> Bool {
  string.byte_size(value)>0 && string.byte_size(value)<=200
  && list.all(string.to_graphemes(value),fn(c) {
    string.contains("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_./",c)
  })
}
fn unique(values: List(String)) -> Bool {
  let index = dict.from_list(list.map(values,fn(v) { #(v,Nil) }))
  dict.size(index)==list.length(values)
}
fn valid_service(row: Service) -> Bool {
  let status_ok=case row.state,row.code {
    "responding",Some(n) if n>=200 && n<300 -> True
    "redirect_not_followed",Some(n) if n>=300 && n<400 -> True
    "authentication_required",Some(401) | "authentication_required",Some(403) -> True
    "http_error",Some(n) if n>=400 && n<=599 && n!=401 && n!=403 -> True
    "invalid_response",None | "unreachable_or_refused",None -> True
    _,_ -> False
  }
  list.contains(endpoints,row.name) && status_ok && row.elapsed>=0 && row.elapsed<=6000
}
fn count(rows: List(Task),state: String) -> Int {
  list.length(list.filter(rows,fn(r) { r.state==state }))
}
fn service_json(row: Service) -> json.Json {
  json.object([
    #("service",json.string(row.name)),#("observation",json.string(row.state)),
    #("http_status",case row.code { Some(n)->json.int(n) None->json.null() }),
    #("elapsed_ms",json.int(row.elapsed)),
  ])
}

/// Inputs come from the service's pinned read-only adapters, not caller payloads.
/// Standard JSON decoding preserves escaping and ignores unprojected fields.
/// This pure projection does not independently verify the supplied source digest.
pub fn project(expected_plan: String,tasks_raw: String,status_raw: String,
  started_us: Int,finished_us: Int) -> Result(String,String) {
  use _ <- result.try(require(id(expected_plan) && started_us>0
    && finished_us>=started_us && finished_us-started_us<=20_000_000
    && string.byte_size(tasks_raw)>0 && string.byte_size(tasks_raw)<=262_144
    && string.byte_size(status_raw)>0 && string.byte_size(status_raw)<=65_536))
  use tasks <- result.try(json.parse(tasks_raw,tasks_decoder())
    |> result.replace_error("brief_observation_invalid"))
  use status <- result.try(json.parse(status_raw,status_decoder())
    |> result.replace_error("brief_observation_invalid"))
  use _ <- result.try(require(tasks.observer=="uos.sa_plan.observer.v1"
    && tasks.authority=="NONE" && tasks.admission=="NOT_GRANTED"
    && tasks.plan==expected_plan && tasks.total>=0 && tasks.total<=1000
    && tasks.selected==tasks.total && list.length(tasks.rows)==tasks.total
    && unique(list.map(tasks.rows,fn(t) { t.id }))
    && list.all(tasks.rows,fn(t) { id(t.id) && list.contains(states,t.state) })
    && string.byte_size(tasks.digest)==64
    && list.all(string.to_graphemes(tasks.digest),fn(c) { string.contains("0123456789abcdef",c) })))
  use _ <- result.try(require(status.schema=="uos.telegram.operational-status.v1"
    && status.state=="partially_observed"
    && status.scope=="fixed_service_http_reachability_and_local_telegram_state"
    && status.admission=="NOT_GRANTED" && status.global_healthy==None
    && status.observed>=started_us && status.observed<=finished_us
    && list.length(status.services)==4
    && unique(list.map(status.services,fn(s) { s.name }))
    && list.all(status.services,valid_service)
    && status.epoch>0 && status.generation>=0 && status.offset>=0
    && status.model=="not_probed"))
  let pending=tasks.rows |> list.filter(fn(t) { t.state!="completed" })
    |> list.map(fn(t) { t.id }) |> list.sort(string.compare)
  let shown=list.take(pending,20)
  let pending_count=list.length(pending)
  let responding=list.length(list.filter(status.services,fn(s) { s.state=="responding" }))
  let services=list.sort(status.services,fn(a,b) { string.compare(a.name,b.name) })
  let summary=int.to_string(count(tasks.rows,"completed"))<>"/"<>int.to_string(tasks.total)
    <>" task records completed; "<>int.to_string(count(tasks.rows,"executing"))
    <>" marked executing; "<>int.to_string(pending_count)<>" not completed. "
    <>int.to_string(responding)<>"/4 fixed endpoints returned 2xx. "
    <>case status.recovery { True->"Telegram recovery is pending." False->"No pending recovery in the local Telegram state." }
  let rendered=json.object([
    #("schema",json.string(schema)),#("summary",json.string(summary)),
    #("status",json.string("partially_observed")),
    #("runtime_admission",json.string("NOT_GRANTED")),#("global_health",json.string("UNASSESSED")),
    #("started_at_us",json.int(started_us)),#("finished_at_us",json.int(finished_us)),
    #("status_observed_at_us",json.int(status.observed)),
    #("sources",json.object([
      #("plan_id",json.string(tasks.plan)),
      #("full_observation_sha256",json.string(tasks.digest)),
      #("task_source",json.string("pinned_sa_plan_read_only_observer")),
      #("status_source",json.string("fixed_service_probes_and_local_telegram_state")),
    ])),
    #("tasks",json.object([
      #("total",json.int(tasks.total)),
      #("counts",json.object(list.map(states,fn(s) { #(s,json.int(count(tasks.rows,s))) }))),
      #("non_completed_total",json.int(pending_count)),
      #("non_completed_ids",json.array(shown,json.string)),
      #("truncated_count",json.int(pending_count-list.length(shown))),
    ])),
    #("reachability",json.object([
      #("responding",json.int(responding)),#("total",json.int(4)),
      #("services",json.array(services,service_json)),
    ])),
    #("telegram",json.object([
      #("service_epoch",json.int(status.epoch)),#("store_generation",json.int(status.generation)),
      #("next_update_offset",json.int(status.offset)),#("pending_recovery",json.bool(status.recovery)),
      #("conversation_configured",json.bool(status.conversation)),
      #("model_connectivity",json.string("not_probed")),
    ])),
    #("note",json.string("Sequential snapshots, not an atomic system snapshot. Available does not mean dependency-ready; executing does not prove a live process. Task counts are not feature completion. HTTP responses are not application health. The source digest is reported by the pinned observer; this projection does not independently verify it.")),
  ]) |> json.to_string
  use _ <- result.try(require(string.byte_size(rendered)<=16_384))
  Ok(rendered)
}
