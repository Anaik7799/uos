//// Bounded paid calibration dispatch foundation. No queue, retries, optimizer
//// or autonomous runtime is created here. The injected owner pins one canonical
//// ledger and current Sa-plan task; a budget value alone grants no task authority.

import cepaf_gleam/ecology/daily_budget as budget
import gleam/float
import gleam/result
import uos_swarm/openrouter_worker as worker

pub type EngineIo {
  EngineIo(
    worker_io: worker.Io,
    authorize: fn() -> Result(Nil, String),
    reserve: fn(String, String) -> Result(Nil, String),
  )
}

pub opaque type Prepared {
  Prepared(
    request: worker.Request,
    policy: worker.Policy,
    reservation: budget.Reservation,
    body: String,
  )
}

/// Pure preparation binds the actual request and its exact serialized bytes.
/// The worker will independently require current catalog prices before POST.
pub fn prepare(
  call_id: String,
  profile: worker.Profile,
  request: worker.Request,
) -> Result(Prepared, String) {
  use _ <- result.try(case profile {
    worker.FreeAdvisory -> Error("invalid_request: paid_profile_required")
    _ -> Ok(Nil)
  })
  use _ <- result.try(case request.model == worker.profile_model(profile) {
    True -> Ok(Nil)
    False -> Error("invalid_request: profile_model_mismatch")
  })
  use _ <- result.try(
    worker.sanitize_check(request.system)
    |> result.map_error(worker.refusal_label),
  )
  use _ <- result.try(
    worker.sanitize_check(request.user)
    |> result.map_error(worker.refusal_label),
  )
  use price <- result.try(budget.provider_ceiling(request.model))
  let body = worker.request_json(request)
  use reservation <- result.try(budget.admit(
    call_id,
    request.model,
    request.max_tokens,
    request.system <> request.user,
    body,
    price,
  ))
  Ok(Prepared(request, worker.profile_policy(profile), reservation, body))
}

/// The checked continuation used by the worker's single POST. Exposed for
/// direct boundary tests; usual callers execute the complete engine below.
/// Each call still needs a fresh owner-issued grant and two exact task fences.
pub fn post_bound(
  prepared: Prepared,
  io: EngineIo,
  credential: String,
  actual_body: String,
  timeout_ms: Int,
) -> Result(#(Int, String), String) {
  use _ <- result.try(case actual_body == prepared.body {
    True -> Ok(Nil)
    False -> Error("request_body_binding_mismatch")
  })
  use _ <- result.try(
    case
      timeout_ms > 0
      && timeout_ms <= prepared.policy.timeout_ms
      && timeout_ms <= worker.timeout_ms
    {
      True -> Ok(Nil)
      False -> Error("invalid_request: timeout_bound")
    },
  )
  use _ <- result.try(io.authorize())
  use _ <- result.try(io.reserve(
    budget.ledger_request_json(prepared.reservation),
    prepared.body,
  ))
  use _ <- result.try(io.authorize())
  io.worker_io.post(credential, prepared.body, timeout_ms)
}

pub fn execute(
  call_id: String,
  profile: worker.Profile,
  request: worker.Request,
  io: EngineIo,
) -> Result(worker.Outcome, String) {
  use prepared <- result.try(prepare(call_id, profile, request))
  // No credential lookup or public catalog fetch precedes the initial fence.
  use _ <- result.try(io.authorize())
  let wrapped =
    worker.Io(..io.worker_io, post: fn(key, body, timeout_ms) {
      post_bound(prepared, io, key, body, timeout_ms)
    })
  use outcome <- result.try(
    worker.run(prepared.policy, wrapped, prepared.request)
    |> result.map_error(worker.refusal_label),
  )
  // Worker checks the measured paid receipt first. Reject non-finite/out-of-bound
  // values before integer conversion, then round liability upward to nanodollars.
  use _ <- result.try(
    case
      outcome.cost_usd >=. 0.0
      && outcome.cost_usd <=. worker.paid_budget_usd_ceiling
    {
      True -> Ok(Nil)
      False -> Error("provider_violated_reservation_bound")
    },
  )
  let nanodollars =
    outcome.cost_usd *. 1_000_000_000.0 |> float.ceiling |> float.truncate
  use _ <- result.try(budget.validate_usage(
    prepared.reservation,
    outcome.reply.prompt_tokens,
    outcome.reply.completion_tokens,
    nanodollars,
  ))
  Ok(outcome)
}
