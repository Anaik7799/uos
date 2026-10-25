import cepaf_gleam/ha/beam_metrics as beam
import cepaf_gleam/telegram/mini_api as api
import cepaf_gleam/telegram/mini_alerts as alerts
import cepaf_gleam/telegram/mini_health as health
import gleam/dict
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{Some}
import gleam/string
import gleeunit/should

fn metrics() {beam.new_metrics(2,100,200,40,20,10,0,10,0,0,1000,10)}
fn device(id: String,reading: Int,high: Int,critical: Int) {
  json.object([#("id",json.string("temperature:"<>id)),#("kind",json.string("temperature")),
    #("label",json.string("CPU "<>id)),#("state",json.string("observed")),
    #("reading",json.int(reading)),#("unit",json.string("milli_celsius")),
    #("high",json.int(high)),#("critical",json.int(critical)),
    #("grade",json.string(health.temperature_grade(Some(reading),Some(high),Some(critical)))),
    #("thresholds_valid",json.bool(True))])
}
fn snapshot(devices: List(json.Json)) {
  health.project(json.to_string(json.object([#("schema",json.string("uos.mini.device-observation.v1")),
    #("observed_at",json.int(100)),#("source",json.string("private_fixture")),
    #("complete",json.bool(True)),#("truncated",json.bool(False)),
    #("excluded_virtual_blocks",json.int(0)),#("devices",json.array(devices,fn(x){x}))])),100,"private_fixture")
}
fn io() {alerts.Io(fn(){snapshot([])},fn(_){Ok(metrics())},fn(_,_){Ok(200)},fn(){0},fn(){100})}
fn fields(o: api.Observation) {let assert api.Observed(100,"operational_alert_conditions",f)=o f}
fn count(o: api.Observation) {fields(o) |> dict.get("Alert count") |> should.be_ok |> int.parse |> should.be_ok}
fn rows(o: api.Observation) {fields(o) |> dict.to_list |> list.filter(fn(p){string.starts_with(p.0,"Alert ") && p.0!="Alert count"}) |> list.map(fn(p){p.1})}

pub fn empty_observation_is_scoped_not_healthy_test() {
  let o=alerts.observe(io())
  count(o) |> should.equal(0)
  fields(o) |> dict.get("Assessment") |> should.be_ok |> string.contains("not all-clear") |> should.be_true
  fields(o) |> dict.get("Acknowledgement") |> should.be_ok |> string.contains("Not yet connected") |> should.be_true
}
pub fn threshold_boundary_test() {
  alerts.metric_alerts(beam.BeamMetrics(..metrics(),run_queue_length:50,process_count:50000,memory_total_mb:4096,atom_count:1000000))
    |> should.equal(Ok([]))
}
pub fn vm_four_thresholds_test() {
  let m=beam.BeamMetrics(..metrics(),run_queue_length:51,process_count:50001,memory_total_mb:4097,atom_count:1000001)
  let o=alerts.observe(alerts.Io(..io(),metrics:fn(_){Ok(m)}))
  count(o) |> should.equal(4)
  rows(o) |> list.all(fn(r){string.contains(r,"warning")}) |> should.be_true
}
pub fn corrupt_metrics_are_coverage_gap_test() {
  let o=alerts.observe(alerts.Io(..io(),metrics:fn(_){Ok(beam.BeamMetrics(..metrics(),memory_total_mb: -1))}))
  count(o) |> should.equal(1)
  rows(o) |> list.all(fn(r){string.contains(r,"unknown")}) |> should.be_true
}
pub fn temperature_and_critical_order_test() {
  let o=alerts.observe(alerts.Io(..io(),health:fn(){snapshot([device("a",85000,80000,95000),device("z",95000,80000,95000)])}))
  count(o) |> should.equal(2)
  fields(o) |> dict.get("Alert 1") |> should.be_ok |> string.contains("\"severity\":\"critical\"") |> should.be_true
}
pub fn clear_and_recurrence_are_current_conditions_test() {
  let breach=alerts.Io(..io(),health:fn(){snapshot([device("cpu",85000,80000,95000)])})
  count(alerts.observe(breach)) |> should.equal(1)
  count(alerts.observe(alerts.Io(..io(),health:fn(){snapshot([device("cpu",70000,80000,95000)])}))) |> should.equal(0)
  count(alerts.observe(breach)) |> should.equal(1)
}
pub fn http_classification_test() {
  list.each([#(200,0),#(299,0),#(301,4),#(401,4),#(403,4),#(404,4),#(503,4)],fn(p){
    count(alerts.observe(alerts.Io(..io(),probe:fn(_,_){Ok(p.0)}))) |> should.equal(p.1)
  })
}
pub fn auth_required_is_not_healthy_test() {
  let o=alerts.observe(alerts.Io(..io(),probe:fn(_,_){Ok(401)}))
  rows(o) |> list.all(fn(r){string.contains(r,"authentication required") && string.contains(r,"advisory")}) |> should.be_true
}
pub fn refused_and_malformed_http_are_unknown_test() {
  list.each([Error("timeout"),Error("header_limit_exceeded"),Ok(199),Ok(600)],fn(p){
    let o=alerts.observe(alerts.Io(..io(),probe:fn(_,_){p}))
    count(o) |> should.equal(4)
    rows(o) |> list.all(fn(r){string.contains(r,"unknown")}) |> should.be_true
  })
}
pub fn all_sources_absent_is_unavailable_test() {
  let assert api.Unavailable(_)=alerts.observe(alerts.Io(..io(),health:fn(){Error("missing")},metrics:fn(_){Error("missing")},probe:fn(_,_){Error("missing")}))
}
pub fn stale_health_is_gap_not_normal_test() {
  let assert Ok(api.Observed(_,source,f))=snapshot([])
  let o=alerts.observe(alerts.Io(..io(),health:fn(){Ok(api.Observed(94,source,f))}))
  count(o) |> should.equal(1)
}
pub fn duplicate_or_missing_devices_are_rejected_test() {
  let assert Ok(api.Observed(at,source,f))=snapshot([device("a",85000,80000,95000)])
  let forged=dict.insert(f,"Device count","2")
  health.devices_from_observation(api.Observed(at,source,forged),100) |> should.be_error
  let assert Ok(row)=dict.get(f,"Device 1")
  let duplicate=dict.insert(forged,"Device 2",row)
  health.devices_from_observation(api.Observed(at,source,duplicate),100) |> should.be_error
}
pub fn partial_inventory_is_visible_test() {
  let assert Ok(api.Observed(at,source,f))=snapshot([])
  let incomplete=dict.insert(f,"Scan","Partial: an inventory directory or sensor listing was unavailable")
  let o=alerts.observe(alerts.Io(..io(),health:fn(){Ok(api.Observed(at,source,incomplete))}))
  count(o) |> should.equal(1)
  rows(o) |> list.first |> should.be_ok |> string.contains("scan partial") |> should.be_true
}
pub fn worst_case_projection_fits_bounds_test() {
  let devices=list.index_map(list.repeat(Nil,64),fn(_,i){i+1}) |> list.map(fn(i){device(int.to_string(i),95000,80000,95000)})
  let m=beam.BeamMetrics(..metrics(),run_queue_length:51,process_count:50001,memory_total_mb:4097,atom_count:1000001)
  let o=alerts.observe(alerts.Io(..io(),health:fn(){snapshot(devices)},metrics:fn(_){Ok(m)},probe:fn(_,_){Ok(503)}))
  count(o) |> should.equal(72)
  {dict.size(fields(o)) <= 100} |> should.be_true
  fields(o) |> dict.to_list |> list.all(fn(p){string.byte_size(p.0)<=128 && string.byte_size(p.1)<=2048}) |> should.be_true
}
pub fn snapshot_digest_changes_with_conditions_test() {
  let a=alerts.observe(io()) |> fields |> dict.get("Snapshot SHA256") |> should.be_ok
  let b=alerts.observe(alerts.Io(..io(),probe:fn(_,_){Ok(503)})) |> fields |> dict.get("Snapshot SHA256") |> should.be_ok
  {a != b} |> should.be_true
  string.byte_size(a) |> should.equal(64)
}
pub fn empty_health_projection_roundtrip_test() {
  let o=snapshot([]) |> should.be_ok
  health.devices_from_observation(o,100) |> should.equal(Ok(#([],True)))
}
pub fn clock_invalid_test() {
  let assert api.Unavailable(_)=alerts.observe(alerts.Io(..io(),unix_seconds:fn(){0}))
}
pub fn budgets_are_bounded_test() {
  let _=alerts.observe(alerts.Io(..io(),metrics:fn(b){b |> should.equal(100) Ok(metrics())},
    probe:fn(n,b){b |> should.equal(300) list.contains(alerts.services,n) |> should.be_true Ok(200)}))
}

@external(erlang,"erlang","put")
fn put_ticks(key: String,values: List(Int)) -> Nil
@external(erlang,"erlang","get")
fn get_ticks(key: String) -> List(Int)
fn next_tick(key: String) -> Int {
  let assert [n,..rest]=get_ticks(key)
  let _=put_ticks(key,rest)
  n
}
pub fn backward_monotonic_clock_refuses_before_read_test() {
  let _=put_ticks("alerts-mono",[0,-1])
  let assert api.Unavailable(_)=alerts.observe(alerts.Io(..io(),
    monotonic_ms:fn(){next_tick("alerts-mono")},
    health:fn(){panic as "read after backward clock"}))
}
pub fn insufficient_remaining_budget_refuses_before_read_test() {
  let _=put_ticks("alerts-mono",[0,2000])
  let assert api.Unavailable(_)=alerts.observe(alerts.Io(..io(),
    monotonic_ms:fn(){next_tick("alerts-mono")},
    health:fn(){panic as "read without required budget"}))
}
pub fn elapsed_deadline_refuses_later_sources_test() {
  let _=put_ticks("alerts-mono",[0,0,4500])
  let assert api.Unavailable(_)=alerts.observe(alerts.Io(..io(),
    monotonic_ms:fn(){next_tick("alerts-mono")},
    metrics:fn(_){panic as "metrics after deadline"}))
}
pub fn clock_rollback_during_read_refuses_later_sources_test() {
  let _=put_ticks("alerts-mono",[0,0,-1])
  let assert api.Unavailable(_)=alerts.observe(alerts.Io(..io(),
    monotonic_ms:fn(){next_tick("alerts-mono")},
    metrics:fn(_){panic as "metrics after clock reversal"}))
}
pub fn wall_clock_jump_and_rollback_refused_test() {
  list.each([99,106],fn(t){
    let _=put_ticks("alerts-wall",[100,t])
    let assert api.Unavailable(_)=alerts.observe(alerts.Io(..io(),unix_seconds:fn(){next_tick("alerts-wall")}))
  })
}
