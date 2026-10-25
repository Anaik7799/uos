//// Reuse the existing bounded production observation adapters.
import cepaf_gleam/ha/beam_metrics
import cepaf_gleam/telegram/mini_alerts
import cepaf_gleam/telegram/mini_health
import gleam/result

type Unit { Millisecond Second }
@external(erlang,"erlang","monotonic_time")
fn monotonic(unit: Unit) -> Int
@external(erlang,"erlang","system_time")
fn wall(unit: Unit) -> Int
@external(erlang,"cepaf_gleam_ffi","get_env")
fn env(key: String) -> Result(String,Nil)
@external(erlang,"beam_metrics_ffi","snapshot_checked")
fn metrics(budget_ms: Int) -> Result(beam_metrics.BeamMetrics,String)
@external(erlang,"telegram_status_probe","probe")
fn probe(name: String,budget_ms: Int) -> Result(Int,String)
pub fn live() -> mini_alerts.Io {
  mini_alerts.Io(fn(){
    use path <- result.try(env("UOS_TELEGRAM_MINI_HEALTH_WORKER") |> result.replace_error("health_worker_missing"))
    use sha <- result.try(env("UOS_TELEGRAM_MINI_HEALTH_SHA256") |> result.replace_error("health_digest_missing"))
    mini_health.observe(mini_health.live_io(path,sha))
  },metrics,probe,fn(){monotonic(Millisecond)},fn(){wall(Second)})
}
