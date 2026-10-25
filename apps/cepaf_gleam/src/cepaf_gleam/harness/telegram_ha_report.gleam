//// Bounded current-VM pressure observation, not cluster HA or failover proof.
import cepaf_gleam/ha/beam_metrics as beam
import gleam/json
import gleam/list
import gleam/result

pub type Io {
  Io(snapshot: fn(Int) -> Result(beam.BeamMetrics,String),
    monotonic_ms: fn() -> Int, unix_us: fn() -> Int)
}
type Unit { Millisecond Microsecond }
@external(erlang,"beam_metrics_ffi","snapshot_checked")
fn snapshot_checked(budget: Int) -> Result(beam.BeamMetrics,String)
@external(erlang,"erlang","monotonic_time")
fn monotonic_time(unit: Unit) -> Int
@external(erlang,"erlang","system_time")
fn system_time(unit: Unit) -> Int

pub fn live_io() -> Io {
  Io(snapshot_checked,fn() { monotonic_time(Millisecond) },
    fn() { system_time(Microsecond) })
}
fn fields(m: beam.BeamMetrics) -> List(#(String,Int)) {
  [#("scheduler_count",m.scheduler_count),#("process_count",m.process_count),
   #("memory_total_mb",m.memory_total_mb),#("memory_processes_mb",m.memory_processes_mb),
   #("memory_ets_mb",m.memory_ets_mb),#("memory_binary_mb",m.memory_binary_mb),
   #("run_queue_length",m.run_queue_length),#("uptime_seconds",m.uptime_seconds),
   #("io_input_mb",m.io_input_mb),#("io_output_mb",m.io_output_mb),
   #("atom_count",m.atom_count),#("port_count",m.port_count)]
}
fn require(ok: Bool,reason: String) -> Result(Nil,String) {
  case ok { True -> Ok(Nil) False -> Error(reason) }
}
pub fn observe(io: Io,authorize: fn() -> Result(Int,String)) -> Result(String,String) {
  use remaining <- result.try(authorize() |> result.replace_error("ha_authority_refused"))
  use _ <- result.try(require(remaining >= 200,"ha_authority_window_too_short"))
  let started=io.monotonic_ms()
  let at=io.unix_us()
  use _ <- result.try(require(at > 0,"ha_clock_refused"))
  let sample=io.snapshot(100)
  let ended=io.monotonic_ms()
  let wall_ended=io.unix_us()
  use after <- result.try(authorize() |> result.replace_error("ha_authority_refused"))
  use _ <- result.try(require(after > 0,"ha_authority_expired"))
  use _ <- result.try(require(ended >= started && ended-started < 200
    && wall_ended >= at && wall_ended-at < 200_000,"ha_deadline_or_clock_refused"))
  use m <- result.try(sample |> result.replace_error("ha_metrics_unavailable"))
  use _ <- result.try(require(m.scheduler_count > 0 && m.process_count > 0
    && list.all(fields(m),fn(f) { f.1 >= 0 }),"ha_metrics_invalid"))
  Ok(json.object([
    #("schema",json.string("uos.telegram.ha.v1")),
    #("status",json.string("partially_observed")),
    #("source",json.string("current_telegram_beam_vm")),
    #("scope",json.string("local_runtime_pressure")),
    #("runtime_admission",json.string("NOT_GRANTED")),
    #("cluster_healthy",json.null()),
    #("failover_verified",json.bool(False)),
    #("observed_at_us",json.int(at)),#("elapsed_ms",json.int(ended-started)),
    #("metrics",json.object(list.map(fields(m),fn(f) { #(f.0,json.int(f.1)) }))),
    #("warnings",json.array(beam.check_thresholds(m),json.string)),
    #("note",json.string("Sequential counters from the Telegram service VM; memory fields use whole MiB. Threshold warnings are local pressure indicators. Cluster redundancy, replication, failover and recovery are not verified by this observation."))
  ]) |> json.to_string)
}
