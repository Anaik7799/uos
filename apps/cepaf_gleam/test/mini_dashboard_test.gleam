import cepaf_gleam/telegram/mini_dashboard as dashboard
import cepaf_gleam/telegram/mini_api as api
import cepaf_gleam/ha/beam_metrics as beam
import cepaf_gleam/harness/telegram_coordination_reader as coordination
import gleam/dict
import gleam/list
import gleam/string
import gleeunit/should

@external(erlang, "mini_boundary_test_ffi", "set_clock")
fn set_clock(times: List(Int)) -> Nil
@external(erlang, "mini_boundary_test_ffi", "clock")
fn clock() -> Int

const peers = "{\"schema\":\"uos.telegram.coordination.v1\",\"view\":\"peers\",\"authority\":\"observation_only\",\"runtime_admission\":\"NOT_GRANTED\",\"sequence\":12,\"journal_digest\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"total_sessions\":1,\"shown\":1,\"truncated\":false,\"sessions\":[{\"private\":\"PRIVATE_PEER_CONTENT\"}]}"

fn metrics() -> beam.BeamMetrics {
  beam.new_metrics(2,120,20,5,2,2,0,123,0,1,5000,8)
}
fn podman() -> api.Observation {
  api.Observed(2000,"local_podman_cli",dict.from_list([
    #("Container count","3"),#("Running containers","2"),#("Image references","4"),
    #("Container private","PRIVATE_CONTAINER_DETAIL"),
  ]))
}
fn io() -> dashboard.Io {
  dashboard.Io(
    fn(budget) { budget |> should.equal(1200) Ok(podman()) },
    fn(budget) { budget |> should.equal(1500) Ok(peers) },
    fn(name,budget) {
      budget |> should.equal(300)
      Ok(case name { "matrix" -> 200 "cockpit" -> 302 "zenoh" -> 401 _ -> 500 })
    },
    fn(budget){budget |> should.equal(100) Ok(metrics())},
    fn(){1000},
    fn(){2000},
  )
}
fn fields(observation: api.Observation) -> dict.Dict(String,String) {
  let assert api.Observed(2000,"operational_dashboard",f)=observation
  f
}
fn value(f:dict.Dict(String,String),key:String)->String {dict.get(f,key) |> should.be_ok}

pub fn actual_source_values_and_scope_test() {
  let f=dashboard.observe(io()) |> fields
  value(f,"Container count") |> should.equal("3")
  value(f,"Registered sessions") |> should.equal("1")
  value(f,"Coordinator sequence") |> should.equal("12")
  value(f,"Online schedulers") |> should.equal("2")
  value(f,"VM uptime seconds") |> should.equal("123")
  value(f,"Overall health") |> string.starts_with("UNKNOWN") |> should.be_true
  value(f,"Runtime admission") |> should.equal("NOT_GRANTED")
  {dict.size(f)<=100} |> should.be_true
  dict.values(f) |> string.join(" ") |> string.contains("PRIVATE_") |> should.be_false
}

pub fn service_statuses_are_not_health_test() {
  let f=dashboard.observe(io()) |> fields
  value(f,"Service matrix") |> should.equal("HTTP 200: responding")
  value(f,"Service cockpit") |> should.equal("HTTP 302: redirect not followed")
  value(f,"Service zenoh") |> should.equal("HTTP 401: authentication required")
  value(f,"Service peer_runtime") |> should.equal("HTTP 500: HTTP error")
}

pub fn source_failure_is_explicit_partial_test() {
  let base=io()
  let f=dashboard.observe(dashboard.Io(..base,podman:fn(_){Error("failed")},peers:fn(_){Error("failed")})) |> fields
  dict.get(f,"Container count") |> should.be_error
  dict.get(f,"Registered sessions") |> should.be_error
  value(f,"Podman observation") |> string.contains("unknown") |> should.be_true
  value(f,"Observation completeness") |> string.starts_with("Partial") |> should.be_true
}

pub fn local_vm_alone_does_not_claim_dashboard_sources_test() {
  let base=io()
  dashboard.observe(dashboard.Io(..base,podman:fn(_){Error("failed")},peers:fn(_){Error("failed")},probe:fn(_,_){Error("failed")}))
  |> should.equal(api.Unavailable("dashboard_sources_unavailable"))
}

pub fn podman_freshness_source_and_counts_test() {
  let base=io()
  list.each([
    api.Observed(1989,"local_podman_cli",dict.from_list([#("Container count","3")])),
    api.Observed(2001,"local_podman_cli",dict.new()),
    api.Observed(2000,"untrusted",dict.new()),
    api.Forbidden,
    api.Unavailable("x"),
    api.Observed(2000,"local_podman_cli",dict.from_list([#("Container count","3"),#("Running containers","4"),#("Image references","0")])),
    api.Observed(2000,"local_podman_cli",dict.from_list([#("Container count","03"),#("Running containers","0"),#("Image references","0")])),
  ],fn(bad){
    let f=dashboard.observe(dashboard.Io(..base,podman:fn(_){Ok(bad)})) |> fields
    dict.get(f,"Container count") |> should.be_error
  })
}

pub fn peers_envelope_count_and_output_bounds_test() {
  let base=io()
  list.each(["{}",string.repeat("x",32769),
    string.replace(peers,"\"NOT_GRANTED\"","\"ADMITTED\""),
    string.replace(peers,"\"sequence\":12","\"sequence\":-1"),
    string.replace(peers,"\"shown\":1","\"shown\":0"),
    string.replace(peers,"\"total_sessions\":1","\"total_sessions\":257"),
    string.replace(peers,"\"truncated\":false","\"truncated\":true"),
    string.replace(peers,"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","bad"),
  ],fn(raw){
    let f=dashboard.observe(dashboard.Io(..base,peers:fn(_){Ok(raw)})) |> fields
    dict.get(f,"Registered sessions") |> should.be_error
  })
}

pub fn invalid_http_codes_do_not_count_as_observation_test() {
  let base=io()
  list.each([0,199,600],fn(code){
    let f=dashboard.observe(dashboard.Io(..base,probe:fn(_,_){Ok(code)})) |> fields
    value(f,"Service matrix") |> should.equal("Unavailable or refused")
    value(f,"Observation completeness") |> string.starts_with("Partial") |> should.be_true
  })
}

pub fn invalid_vm_stats_never_become_zeros_test() {
  let base=io()
  list.each([beam.BeamMetrics(..metrics(),scheduler_count:0),beam.BeamMetrics(..metrics(),process_count:-1)],fn(m){
    let f=dashboard.observe(dashboard.Io(..base,metrics:fn(_){Ok(m)})) |> fields
    dict.get(f,"VM processes") |> should.be_error
    value(f,"VM observation") |> string.contains("unknown") |> should.be_true
  })
}

pub fn monotonic_deadline_and_regression_fail_closed_test() {
  let base=io()
  list.each([[1000,999],[1000,1000,999],[1000,1000,5500],[1000,5450]],fn(times){
    set_clock(times)
    dashboard.observe(dashboard.Io(..base,monotonic_ms:clock))
    |> should.equal(api.Unavailable("dashboard_deadline_or_clock_refused"))
  })
  dashboard.observe(dashboard.Io(..base,unix_seconds:fn(){0}))
  |> should.equal(api.Unavailable("dashboard_deadline_or_clock_refused"))
}

pub fn real_vm_counters_and_cumulative_labels_test() {
  let base=io()
  let f=dashboard.observe(dashboard.Io(..base,metrics:fn(_){Ok(beam.snapshot())})) |> fields
  dict.get(f,"VM memory MiB") |> should.be_ok |> string.is_empty |> should.be_false
  dict.get(f,"VM cumulative input MiB") |> should.be_ok |> string.is_empty |> should.be_false
  dict.get(f,"CPU percent") |> should.be_error
}

pub fn reader_invalid_budget_refused_test() {
  coordination.observe_with_budget("/does/not/exist","peers",99) |> should.equal(Error("coordination_budget_refused"))
  coordination.observe_with_budget("/does/not/exist","peers",3001) |> should.equal(Error("coordination_budget_refused"))
}

@external(erlang,"beam_metrics_ffi","snapshot_checked")
fn checked_metrics(budget: Int) -> Result(beam.BeamMetrics,String)
pub fn native_metrics_bound_and_failure_test() {
  checked_metrics(0) |> should.equal(Error("invalid_metrics_budget"))
  checked_metrics(101) |> should.equal(Error("invalid_metrics_budget"))
  checked_metrics(100) |> should.be_ok
  let base=io()
  let f=dashboard.observe(dashboard.Io(..base,metrics:fn(_){Error("worker_failed")})) |> fields
  dict.get(f,"VM memory MiB") |> should.be_error
  value(f,"VM observation") |> string.contains("unknown") |> should.be_true
}
