//// Current alert conditions from bounded observed sources. No synthetic all-clear.
//// Acknowledgement never changes measured conditions; durable acknowledgement is separate.
import cepaf_gleam/ha/beam_metrics as beam
import cepaf_gleam/harness/files
import cepaf_gleam/telegram/mini_api as api
import cepaf_gleam/telegram/mini_health as health
import gleam/dict
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{Some}
import gleam/order
import gleam/result
import gleam/string

pub type Io {
  Io(health: fn() -> Result(api.Observation, String),
    metrics: fn(Int) -> Result(beam.BeamMetrics, String),
    probe: fn(String, Int) -> Result(Int, String),
    monotonic_ms: fn() -> Int, unix_seconds: fn() -> Int)
}
pub type Alert {
  Alert(id: String, source: String, severity: String, condition: String,
    measured: String, threshold: String)
}
type Part { Part(rows: List(Alert), coverage: String, observed: Bool) }
pub const services = ["matrix", "cockpit", "zenoh", "peer_runtime"]
fn require(ok: Bool) { case ok { True -> Ok(Nil) False -> Error("alerts_observation_refused") } }
fn encode(a: Alert) -> json.Json {
  json.object([#("id",json.string(a.id)),#("source",json.string(a.source)),
    #("severity",json.string(a.severity)),#("condition",json.string(a.condition)),
    #("measured",json.string(a.measured)),#("threshold",json.string(a.threshold))])
}
fn unavailable(source: String) -> Part { Part([Alert("coverage:" <> files.digest(source),source,"unknown","Observation unavailable; conditions unknown","Unavailable","A valid bounded observation is required")],source <> ": unavailable; conditions unknown",False) }

pub fn metric_alerts(m: beam.BeamMetrics) -> Result(List(Alert),String) {
  use _ <- result.try(require(m.scheduler_count > 0 && m.scheduler_count <= 65536
    && list.all([m.process_count,m.memory_total_mb,m.memory_processes_mb,m.memory_ets_mb,
      m.memory_binary_mb,m.run_queue_length,m.uptime_seconds,m.io_input_mb,m.io_output_mb,
      m.atom_count,m.port_count],fn(n) { n >= 0 && n <= 9007199254740991 })))
  [#("run_queue",m.run_queue_length,50,"runnable processes"),
   #("process_count",m.process_count,50000,"processes"),
   #("memory",m.memory_total_mb,4096,"MiB"),
   #("atom_count",m.atom_count,1000000,"atoms")]
  |> list.filter(fn(t) { t.1 > t.2 })
  |> list.map(fn(t) { Alert("vm:" <> t.0,"serving_beam_vm","warning",
    t.0 <> " exceeds configured threshold",int.to_string(t.1) <> " " <> t.3,
    "> " <> int.to_string(t.2) <> " " <> t.3) })
  |> Ok
}

fn device_alert(d: health.Device) -> List(Alert) {
  case d.kind,d.grade {
    "temperature","warning" | "temperature","critical" -> {
      let threshold=case d.grade { "critical" -> d.critical _ -> d.high }
      case d.reading,threshold {
        Some(v),Some(t) -> [Alert("temperature:" <> files.digest(d.id),"local_linux_sysfs",d.grade,
          d.label <> " (" <> d.id <> ") temperature at or above kernel threshold",
          int.to_string(v) <> " milli_celsius",">= " <> int.to_string(t) <> " milli_celsius")]
        _,_ -> []
      }
    }
    "temperature","unknown" | "sensor",_ -> [Alert("coverage:" <> files.digest(d.id),"local_linux_sysfs","unknown",d.label <> " (" <> d.id <> ") temperature assessment unavailable","Unknown","A valid reading and kernel threshold are required")]
    _,_ -> []
  }
}
fn health_part(raw: Result(api.Observation,String),now: Int) -> Part {
  let parsed = {
    use o <- result.try(raw)
    use #(devices,complete) <- result.try(health.devices_from_observation(o,now))
    let unknown=list.filter(devices,fn(d) { d.kind == "sensor" || {d.kind == "temperature" && d.grade == "unknown"} }) |> list.length
    Ok(Part(list.append(list.flat_map(devices,device_alert),case complete {
      True -> [] False -> [Alert("coverage:device_scan","local_linux_sysfs","unknown","Device scan partial or truncated","Incomplete inventory","A complete bounded scan is required")] }),
      "Local temperature thresholds: " <> int.to_string(list.length(devices))
      <> " inventory records; " <> int.to_string(unknown) <> " temperature/sensor assessments unknown; "
      <> case complete {True -> "scan complete" False -> "partial/truncated scan; omitted conditions unknown"},True))
  }
  result.unwrap(parsed,unavailable("Local temperature thresholds"))
}
fn probe_part(name: String,raw: Result(Int,String)) -> Part {
  case raw {
    Ok(code) if code >= 200 && code <= 599 -> {
      let rows=case code {
        c if c < 300 -> []
        401 | 403 -> [Alert("http:" <> name,name,"advisory","HTTP authentication required",
          int.to_string(code),"Expected 2xx for unauthenticated reachability probe")]
        c if c < 400 -> [Alert("http:" <> name,name,"warning","HTTP redirect not followed",
          int.to_string(code),"Expected 2xx for fixed endpoint")]
        _ -> [Alert("http:" <> name,name,"warning","HTTP error response",
          int.to_string(code),"Expected 2xx for fixed endpoint")]
      }
      Part(rows,name <> ": HTTP " <> int.to_string(code) <> "; reachability only, application health unassessed",True)
    }
    _ -> unavailable(name)
  }
}
fn step(io: Io,last: Int,deadline: Int,cap: Int,read: fn(Int) -> Result(a,String))
  -> Result(#(Result(a,String),Int),String) {
  let before=io.monotonic_ms()
  use _ <- result.try(require(before >= last && deadline-before >= cap))
  let raw=read(cap)
  let after=io.monotonic_ms()
  use _ <- result.try(require(after >= before && after < deadline))
  Ok(#(raw,after))
}
fn probes(io: Io,names: List(String),last: Int,deadline: Int,parts: List(Part))
  -> Result(#(List(Part),Int),String) {
  case names {
    [] -> Ok(#(list.reverse(parts),last))
    [n,..rest] -> {
      use #(raw,at) <- result.try(step(io,last,deadline,300,fn(b) {io.probe(n,b)}))
      probes(io,rest,at,deadline,[probe_part(n,raw),..parts])
    }
  }
}
fn rank(severity: String) -> Int {case severity {"critical" -> 0 "warning" -> 1 "unknown" -> 2 _ -> 3}}
pub fn observe(io: Io) -> api.Observation {
  collect(io) |> result.unwrap(api.Unavailable("alerts_deadline_or_clock_refused"))
}
fn collect(io: Io) -> Result(api.Observation,String) {
  let started=io.monotonic_ms()
  let wall_started=io.unix_seconds()
  let deadline=started+4500
  use #(devices,t1) <- result.try(step(io,started,deadline,2800,fn(_) {io.health()}))
  use #(metrics,t2) <- result.try(step(io,t1,deadline,100,io.metrics))
  use #(network,t3) <- result.try(probes(io,services,t2,deadline,[]))
  let ended=io.monotonic_ms()
  let now=io.unix_seconds()
  use _ <- result.try(require(ended >= t3 && ended < deadline
    && wall_started > 0 && now >= wall_started && now-wall_started <= 5))
  let vm=case metrics |> result.try(metric_alerts) {
    Ok(rows) -> Part(rows,"Serving BEAM VM: four configured counter thresholds evaluated; sequential counters, not application health",True)
    Error(_) -> unavailable("Serving BEAM VM thresholds")
  }
  let parts=[health_part(devices,now),vm,..network]
  use _ <- result.try(require(list.any(parts,fn(p) {p.observed})))
  let rows=list.flat_map(parts,fn(p) {p.rows}) |> list.sort(fn(a,b) {
    case int.compare(rank(a.severity),rank(b.severity)) {order.Eq -> string.compare(a.id,b.id) other -> other}
  })
  use _ <- result.try(require(list.length(rows) <= 80
    && list.length(list.unique(list.map(rows,fn(r) {r.id}))) == list.length(rows)))
  let encoded=list.map(rows,fn(r) {json.to_string(encode(r))})
  use _ <- result.try(require(list.all(encoded,fn(s) {string.byte_size(s)<=2048})))
  let coverage=list.map(parts,fn(p) {p.coverage})
  let version=files.digest(json.to_string(json.object([
    #("observed_at",json.int(now)),#("alerts",json.array(rows,encode)),
    #("coverage",json.array(coverage,json.string))])))
  let fields=[
    #("Scope","Current local temperature thresholds, serving BEAM VM counters and four fixed HTTP endpoints; no complete fleet or historical alarm coverage"),
    #("Alert count",int.to_string(list.length(rows))),
    #("Assessment",case rows {[] -> "No conditions triggered in answered sources; missing coverage and unassessed services are not all-clear" _ -> "Observed conditions require review; clearing the source condition requires a new observation"}),
    #("Snapshot SHA256",version),
    #("Runtime admission","NOT_GRANTED"),
    #("Acknowledgement","Not yet connected; conditions are not acknowledged by viewing them"),
    ..list.index_map(coverage,fn(c,i) {#("Coverage " <> int.to_string(i+1),c)})
  ]
  Ok(api.Observed(now,"operational_alert_conditions",
    dict.from_list(list.append(fields,list.index_map(encoded,fn(s,i) {#("Alert " <> int.to_string(i+1),s)})))))
}
