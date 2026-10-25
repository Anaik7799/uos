import gleam/erlang/process
import gleam/result

pub const http_timeout_min_ms = 1

pub const http_timeout_max_ms = 60_000

// FFI HTTP timeout cleanup path can take up to 500ms + 3 * 250ms = 1250ms,
// plus 250ms margin = 1500ms; BEAM scheduler delays are still possible, so
// unconfirmed cleanup or worker timeout/down requires ServiceWriterHold.
pub const rpc_timeout_margin_ms = 1500

pub const rpc_timeout_min_ms = 1

pub const rpc_timeout_max_ms = 61_500

pub fn deadline(http_timeout_ms: Int) -> Result(Int, String) {
  case
    http_timeout_ms >= http_timeout_min_ms
    && http_timeout_ms <= http_timeout_max_ms
  {
    True -> Ok(http_timeout_ms + rpc_timeout_margin_ms)
    False -> Error("invalid_http_timeout_ms")
  }
}

fn validate_rpc_timeout(timeout_ms: Int) -> Result(Int, String) {
  case timeout_ms >= rpc_timeout_min_ms && timeout_ms <= rpc_timeout_max_ms {
    True -> Ok(timeout_ms)
    False -> Error("invalid_poller_rpc_timeout_ms")
  }
}

fn resolve_worker_pid(
  worker: process.Subject(message),
) -> Result(process.Pid, String) {
  // Poller actors return PID-bound subjects. Reject name lookup races: a
  // registered name could disappear or bind another PID between monitor/send.
  case process.subject_name(worker) {
    Ok(_) -> Error("named_poller_worker_not_supported")
    Error(Nil) ->
      case process.subject_owner(worker) {
        Ok(pid) -> Ok(pid)
        Error(Nil) -> Error("poller_worker_down")
      }
  }
}

pub fn call(
  worker: process.Subject(message),
  timeout_ms: Int,
  make_request: fn(process.Subject(Result(value, String))) -> message,
) -> Result(value, String) {
  use valid_timeout_ms <- result.try(validate_rpc_timeout(timeout_ms))
  use pid <- result.try(resolve_worker_pid(worker))
  let mon = process.monitor(pid)
  let reply_subject = process.new_subject()
  let selector =
    process.new_selector()
    |> process.select(reply_subject)
    |> process.select_specific_monitor(mon, fn(_down) {
      Error("poller_worker_down")
    })
  process.send(worker, make_request(reply_subject))
  let outcome = case process.selector_receive(selector, valid_timeout_ms) {
    Ok(reply) -> reply
    Error(Nil) -> Error("poller_worker_timeout")
  }
  process.demonitor_process(mon)
  outcome
}
