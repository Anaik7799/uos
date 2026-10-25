
//// Bounded read-only device observations. Threshold bands do not assert whole-device health.
import cepaf_gleam/harness/observer_policy as policy
import cepaf_gleam/telegram/mini_api as api
import gleam/bit_array
import gleam/dict
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub type Io {
  Io(read: fn(Int) -> Result(String,String),monotonic_ms: fn() -> Int,unix_seconds: fn() -> Int)
}
pub type Device {
  Device(id: String,kind: String,label: String,state: String,reading: Option(Int),
    unit: String,high: Option(Int),critical: Option(Int),grade: String,thresholds_valid: Bool)
}
type Unit { Millisecond Second }
@external(erlang,"erlang","monotonic_time")
fn mono(unit: Unit) -> Int
@external(erlang,"erlang","system_time")
fn wall(unit: Unit) -> Int
@external(erlang,"sa_plan_observer_ffi","observe_checked")
fn invoke(guardian: String,sha: String,args: List(String),deadline: Int,max_bytes: Int)
  -> Result(policy.Observation,String)
fn require(ok: Bool) { case ok { True -> Ok(Nil) False -> Error("health_observation_refused") } }

pub fn valid_worker(path: String,sha: String) -> Bool {
  policy.valid_digest(sha)
  && string.starts_with(path,"/home/an/NAS-setup/uos/var/recovery-runtime/")
  && string.ends_with(path,"/mini_health_snapshot.exe")
  && !string.contains(path,"..") && !string.contains(path,"\u{0}")
  && string.byte_size(path) <= 256
}
pub fn live_io(path: String,sha: String) -> Io {
  Io(fn(budget) {
    use _ <- result.try(require(valid_worker(path,sha) && budget >= 100 && budget <= 2500))
    use r <- result.try(invoke(
      "/home/an/NAS-setup/uos/tools/validation/obs_guardian.exe",
      "b7bab1a85ffa3689a2548ff28a391e659c0537104dec7be0f774bae1820ec4be",
      ["--exe",path,"--sha256",sha,"--deadline-ms",int.to_string(budget),
        "--max-bytes","32768","--"],budget,32768))
    use _ <- result.try(require(r.guardian_result == "child_exited"
      && r.cleanup == "confirmed" && r.child_exit == 0 && bit_array.byte_size(r.payload) <= 32768))
    bit_array.to_string(r.payload) |> result.replace_error("health_invalid_encoding")
  },fn() { mono(Millisecond) },fn() { wall(Second) })
}
pub fn observe(io: Io) -> Result(api.Observation,String) {
  let started=io.monotonic_ms()
  use raw <- result.try(io.read(2500))
  let ended=io.monotonic_ms()
  use _ <- result.try(require(ended >= started && ended-started < 2800))
  project(raw,io.unix_seconds(),"linux_sysfs")
}
fn decoder() -> decode.Decoder(Device) {
  use id <- decode.field("id",decode.string)
  use kind <- decode.field("kind",decode.string)
  use label <- decode.field("label",decode.string)
  use state <- decode.field("state",decode.string)
  use reading <- decode.field("reading",decode.optional(decode.int))
  use unit <- decode.field("unit",decode.string)
  use high <- decode.field("high",decode.optional(decode.int))
  use critical <- decode.field("critical",decode.optional(decode.int))
  use grade <- decode.field("grade",decode.string)
  use thresholds_valid <- decode.field("thresholds_valid",decode.bool)
  decode.success(Device(id,kind,label,state,reading,unit,high,critical,grade,thresholds_valid))
}
fn text(s: String,max: Int) -> Bool {
  s != "" && string.byte_size(s) <= max
  && list.all(string.to_utf_codepoints(s),fn(c) { let n=string.utf_codepoint_to_int(c) n >= 32 && n <= 126 })
}
fn range(n: Option(Int),low: Int,high: Int) -> Bool {
  case n { None -> True Some(v) -> v >= low && v <= high }
}
pub fn temperature_grade(value: Option(Int),high: Option(Int),critical: Option(Int)) -> String {
  case high,critical { Some(h),Some(c) if h > c -> "unknown" _,_ ->
    case value,high,critical {
      Some(v),_,Some(c) if v >= c -> "critical"
      Some(v),Some(h),_ if v >= h -> "warning"
      Some(_),_,Some(_) | Some(_),Some(_),_ -> "normal"
      _,_,_ -> "unknown"
    }
  }
}
fn valid(d: Device) -> Bool {
  text(d.id,128) && text(d.label,300) && text(d.state,128)
  && string.starts_with(d.id,d.kind <> ":")
  && case d.kind {
    "temperature" -> d.unit == "milli_celsius" && range(d.reading,-100000,250000)
      && range(d.high,1,250000) && range(d.critical,1,250000)
      && case d.high,d.critical {Some(h),Some(c) if h>c -> !d.thresholds_valid _,_ -> True}
      && d.grade == case d.thresholds_valid {False -> case temperature_grade(d.reading,d.high,d.critical) { "critical" -> "critical" "warning" -> "warning" _ -> "unknown" } True -> temperature_grade(d.reading,d.high,d.critical)}
      && d.state == case d.reading {
        None -> "unavailable"
        Some(_) -> case d.high,d.critical {
          Some(h),Some(c) if h > c -> "inconsistent_thresholds"
          _,_ -> case d.thresholds_valid {True -> "observed" False -> "invalid_thresholds"}
        }
      }
    "network" -> d.unit == "carrier" && range(d.reading,0,1)
      && d.high == None && d.critical == None && d.grade == "unknown"
      && list.contains(["unknown","notpresent","down","lowerlayerdown","testing","dormant","up","unavailable"],d.state)
    "block" -> d.unit == "512_byte_sectors" && range(d.reading,0,9007199254740991)
      && d.high == None && d.critical == None && d.grade == "unknown"
    "sensor" -> d.state == "not_sampled" && d.unit == "none" && d.reading == None && d.high == None && d.critical == None && d.grade == "unknown" && !d.thresholds_valid
    _ -> False
  }
}
fn number(n: Option(Int)) -> json.Json { case n {None -> json.null() Some(v) -> json.int(v)} }
fn encode(d: Device) -> String {
  json.object([#("id",json.string(d.id)),#("kind",json.string(d.kind)),#("label",json.string(d.label)),
    #("state",json.string(d.state)),#("reading",number(d.reading)),#("unit",json.string(d.unit)),
    #("high",number(d.high)),#("critical",number(d.critical)),#("grade",json.string(d.grade)),#("thresholds_valid",json.bool(d.thresholds_valid))])
  |> json.to_string
}
pub fn project(raw: String,now: Int,expected_source: String) -> Result(api.Observation,String) {
  use _ <- result.try(require(string.byte_size(raw) <= 32768
    && list.contains(["linux_sysfs","private_fixture"],expected_source)))
  let dec = {
    use schema <- decode.field("schema",decode.string)
    use at <- decode.field("observed_at",decode.int)
    use source <- decode.field("source",decode.string)
    use complete <- decode.field("complete",decode.bool)
    use truncated <- decode.field("truncated",decode.bool)
    use excluded <- decode.field("excluded_virtual_blocks",decode.optional(decode.int))
    use devices <- decode.field("devices",decode.list(decoder()))
    decode.success(#(schema,at,source,complete,truncated,excluded,devices))
  }
  use #(schema,at,source,complete,truncated,excluded,devices) <- result.try(json.parse(raw,dec)
    |> result.replace_error("health_invalid_snapshot"))
  use _ <- result.try(require(schema == "uos.mini.device-observation.v1"
    && source == expected_source && at > 0 && now >= at && now-at <= 5
    && range(excluded,0,512) && list.length(devices) <= 64
    && case truncated {True -> !complete && list.length(devices)==64 False -> True}
    && list.all(devices,valid) && list.length(list.unique(list.map(devices,fn(d) { d.id }))) == list.length(devices)))
  let rows=list.sort(devices,fn(a,b) { string.compare(a.id,b.id) })
  let fields=[
    #("Host","nas-1.tail55d152.ts.net"),
    #("Scope","Local Linux temperature sensors, network interfaces and block-device metadata; no remote fleet or SMART diagnosis"),
    #("Health meaning","Normal/warning/critical apply only to sampled temperature and kernel-exported thresholds. Link/carrier/disk state does not prove device health."),
    #("Snapshot","Sequential reads; devices can change during collection"),
    #("Sensor policy","Automatic temperature reads restricted to known driver families; other drivers including drivetemp are listed without sampling"),
    #("Scan",case complete {True -> "All three inventory directories scanned; individual readings may be unavailable" False -> "Partial: an inventory directory or sensor listing was unavailable"}),
    #("Device count",int.to_string(list.length(rows))),
    #("Excluded virtual blocks",case excluded {Some(n) -> int.to_string(n) None -> "Not counted; collection truncated"}),
    #("Truncation",case truncated {True -> "First 64 records only; inventory is incomplete" False -> "Not truncated"}),
    #("Runtime admission","NOT_GRANTED"),
    ..list.index_map(rows,fn(d,n) { #("Device " <> int.to_string(n+1),encode(d)) })
  ]
  Ok(api.Observed(at,"local_device_observations",dict.from_list(fields)))
}

//// Revalidate a health projection before another feature derives conditions from it.
pub fn devices_from_observation(observation: api.Observation,now: Int)
  -> Result(#(List(Device),Bool),String) {
  case observation {
    api.Observed(at,"local_device_observations",fields) -> {
      use _ <- result.try(require(at > 0 && now >= at && now-at <= 5))
      use count <- result.try(dict.get(fields,"Device count") |> result.replace_error("health_count_missing"))
      use n <- result.try(int.parse(count) |> result.replace_error("health_count_invalid"))
      use _ <- result.try(require(n >= 0 && n <= 64 && int.to_string(n) == count))
      let entries=dict.to_list(fields) |> list.filter(fn(p) {string.starts_with(p.0,"Device ") && p.0 != "Device count"})
      use _ <- result.try(require(list.length(entries)==n))
      use rows <- result.try(list.try_map(list.index_map(list.repeat(Nil,n),fn(_,i){i+1}),fn(i) {
        use raw <- result.try(dict.get(fields,"Device " <> int.to_string(i)) |> result.replace_error("health_device_missing"))
        use _ <- result.try(require(string.byte_size(raw)<=2048))
        use d <- result.try(json.parse(raw,decoder()) |> result.replace_error("health_device_invalid"))
        use _ <- result.try(require(valid(d)))
        Ok(d)
      }))
      use _ <- result.try(require(list.length(list.unique(list.map(rows,fn(d) {d.id})))==n))
      use scan <- result.try(dict.get(fields,"Scan") |> result.replace_error("health_scan_missing"))
      use truncated <- result.try(dict.get(fields,"Truncation") |> result.replace_error("health_truncation_missing"))
      use _ <- result.try(require(list.contains([
        "All three inventory directories scanned; individual readings may be unavailable",
        "Partial: an inventory directory or sensor listing was unavailable"],scan)
        && list.contains(["Not truncated","First 64 records only; inventory is incomplete"],truncated)
        && case truncated { "Not truncated" -> True _ -> n==64 && scan=="Partial: an inventory directory or sensor listing was unavailable" }))
      Ok(#(rows,string.starts_with(scan,"All three") && truncated=="Not truncated"))
    }
    _ -> Error("health_source_unavailable")
  }
}
