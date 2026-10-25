//// Fixed operational reads. HTTP reachability is not a health or admission proof.
import gleam/int
import gleam/json
import gleam/list
import gleam/result

pub type Io {
  Io(probe: fn(String, Int) -> Result(Int, String), now_ms: fn() -> Int)
}

pub type LocalState {
  LocalState(observed_at_us: Int, service_epoch: Int, store_generation: Int,
    next_update_offset: Int, pending_recovery: Bool, conversation_configured: Bool,
    clock_report: json.Json, kernel_report: json.Json)
}

type TimeUnit { Millisecond }

@external(erlang, "erlang", "monotonic_time")
fn monotonic_ms(unit: TimeUnit) -> Int

@external(erlang, "telegram_status_probe", "probe")
fn native_probe(name: String, timeout_ms: Int) -> Result(Int, String)

pub fn live_io() -> Io {
  Io(native_probe, fn() { monotonic_ms(Millisecond) })
}

pub const endpoints = ["matrix", "cockpit", "zenoh", "peer_runtime"]

fn available(
  io: Io, authorize: fn() -> Result(Int, String), started: Int, deadline: Int,
) -> Result(Int, String) {
  use lease <- result.try(authorize() |> result.replace_error("status_authority_refused"))
  let now = io.now_ms()
  case now >= started && now < deadline && lease >= 100 {
    True -> Ok(int.min(deadline - now, lease))
    False -> Error("status_deadline_or_clock_refused")
  }
}

fn classify(code: Int) -> String {
  case code {
    n if n >= 200 && n < 300 -> "responding"
    n if n >= 300 && n < 400 -> "redirect_not_followed"
    401 | 403 -> "authentication_required"
    n if n >= 400 && n <= 599 -> "http_error"
    _ -> "invalid_response"
  }
}

pub fn observe(
  local: LocalState, io: Io, authorize: fn() -> Result(Int, String), budget_ms: Int,
) -> Result(String, String) {
  use _ <- result.try(case budget_ms >= 100 && budget_ms <= 6000 {
    True -> Ok(Nil)
    False -> Error("invalid_status_budget")
  })
  let started = io.now_ms()
  let deadline = started + budget_ms
  use rows <- result.try(list.try_map(endpoints, fn(name) {
    use left <- result.try(available(io, authorize, started, deadline))
    use _ <- result.try(case left >= 100 {
      True -> Ok(Nil)
      False -> Error("status_budget_exhausted")
    })
    let before = io.now_ms()
    let observed = io.probe(name, int.min(1200, left))
    use _ <- result.try(available(io, authorize, started, deadline))
    let after = io.now_ms()
    use _ <- result.try(case after >= before {
      True -> Ok(Nil)
      False -> Error("status_clock_regressed")
    })
    let #(state, code) = case observed {
      Ok(n) if n >= 200 && n <= 599 -> #(classify(n), json.int(n))
      Ok(_) -> #("invalid_response", json.null())
      Error(_) -> #("unreachable_or_refused", json.null())
    }
    Ok(json.object([
      #("service", json.string(name)),
      #("observation", json.string(state)),
      #("http_status", code),
      #("elapsed_ms", json.int(after - before)),
    ]))
  }))
  use _ <- result.try(available(io, authorize, started, deadline))
  Ok(json.object([
    #("schema", json.string("uos.telegram.operational-status.v1")),
    #("status", json.string("partially_observed")),
    #("scope", json.string("fixed_service_http_reachability_and_local_telegram_state")),
    #("health_note", json.string("An HTTP response proves reachability only; application health and global admission are not inferred.")),
    #("runtime_admission", json.string("NOT_GRANTED")),
    #("global_healthy", json.null()),
    #("observed_at_us", json.int(local.observed_at_us)),
    #("services", json.array(rows, fn(x) { x })),
    #("telegram", json.object([
      #("service_epoch", json.int(local.service_epoch)),
      #("store_generation", json.int(local.store_generation)),
      #("next_update_offset", json.int(local.next_update_offset)),
      #("pending_recovery", json.bool(local.pending_recovery)),
      #("conversation_configured", json.bool(local.conversation_configured)),
      #("model_connectivity", json.string("not_probed")),
    ])),
    #("zigvm_kernel", local.kernel_report),
    #("clock_synchronization", local.clock_report),
  ]) |> json.to_string)
}
