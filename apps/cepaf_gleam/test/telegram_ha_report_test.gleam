import cepaf_gleam/harness/telegram_ha_report as ha
import cepaf_gleam/ha/beam_metrics as beam
import gleam/erlang/process
import gleam/list
import gleam/string

fn metrics() { beam.BeamMetrics(2,100,20,10,2,1,0,10,1,1,200,2) }
fn io(m: beam.BeamMetrics) { ha.Io(fn(b) { assert b == 100 Ok(m) },fn() { -10 },fn() { 1_000_000 }) }
fn sequence(values: List(a)) -> fn() -> a {
  let q=process.new_subject()
  list.each(values,fn(v) { process.send(q,v) })
  fn() { let assert Ok(v)=process.receive(q,0) v }
}
pub fn actual_fields_and_scope_test() {
  let assert Ok(raw)=ha.observe(io(metrics()),fn() { Ok(1000) })
  assert string.contains(raw,"\"process_count\":100")
  assert string.contains(raw,"\"cluster_healthy\":null")
  assert string.contains(raw,"\"failover_verified\":false")
  assert string.contains(raw,"NOT_GRANTED")
}
pub fn pressure_warnings_test() {
  let m=beam.BeamMetrics(..metrics(),process_count:60_000,memory_total_mb:5000,run_queue_length:80)
  let assert Ok(raw)=ha.observe(io(m),fn() { Ok(1000) })
  assert !string.contains(raw,"\"warnings\":[]")
  assert string.contains(raw,"\"status\":\"partially_observed\"")
}
pub fn invalid_counters_test() {
  list.each([beam.BeamMetrics(..metrics(),scheduler_count:0),
    beam.BeamMetrics(..metrics(),process_count:0),
    beam.BeamMetrics(..metrics(),memory_total_mb:-1),
    beam.BeamMetrics(..metrics(),port_count:-1)],fn(m) {
      assert ha.observe(io(m),fn() { Ok(1000) }) == Error("ha_metrics_invalid")
  })
}
pub fn early_refusal_skips_read_test() {
  let calls=process.new_subject()
  let custom=ha.Io(..io(metrics()),snapshot:fn(_) {process.send(calls,True) Ok(metrics())})
  assert ha.observe(custom,fn() { Error("denied") }) == Error("ha_authority_refused")
  assert ha.observe(custom,fn() { Ok(199) }) == Error("ha_authority_window_too_short")
  let assert Error(_) = process.receive(calls,0)
}
pub fn late_authority_loss_test() {
  assert ha.observe(io(metrics()),sequence([Ok(1000),Error("expired")])) == Error("ha_authority_refused")
  assert ha.observe(io(metrics()),sequence([Ok(1000),Ok(0)])) == Error("ha_authority_expired")
}
pub fn collector_failure_test() {
  let custom=ha.Io(..io(metrics()),snapshot:fn(_) {Error("timeout")})
  assert ha.observe(custom,fn() {Ok(1000)}) == Error("ha_metrics_unavailable")
}
pub fn monotonic_regression_and_deadline_test() {
  list.each([[10,9],[10,210]],fn(times) {
    let custom=ha.Io(..io(metrics()),monotonic_ms:sequence(times))
    assert ha.observe(custom,fn(){Ok(1000)}) == Error("ha_deadline_or_clock_refused")
  })
}
pub fn invalid_wall_clock_test() {
  assert ha.observe(ha.Io(..io(metrics()),unix_us:fn(){0}),fn(){Ok(1000)}) == Error("ha_clock_refused")
  list.each([[1_000_000,999_999],[1_000_000,1_200_000]],fn(times) {
    let custom=ha.Io(..io(metrics()),unix_us:sequence(times))
    assert ha.observe(custom,fn(){Ok(1000)}) == Error("ha_deadline_or_clock_refused")
  })
}
