import cepaf_gleam/ecology/daily_budget as budget
import cepaf_gleam/ecology/openrouter_engine as engine
import gleam/erlang/process
import gleam/json
import gleam/list
import gleam/option.{Some}
import gleeunit/should
import uos_swarm/openrouter_worker as worker

type Event {
  Authorize
  Credential
  Fetch
  Reserve(String, String)
  Post(String)
}

fn request() {
  worker.Request(
    "moonshotai/kimi-k3",
    "Offer bounded advice.",
    "Assess one lease invariant.",
    256,
  )
}

fn reply(prompt: Int, completion: Int, cost: Float) {
  json.object([
    #("model", json.string("moonshotai/kimi-k3")),
    #("provider", json.string("fixture")),
    #(
      "choices",
      json.array(
        [
          json.object([
            #("finish_reason", json.string("stop")),
            #(
              "message",
              json.object([#("content", json.string("Check stale epochs."))]),
            ),
          ]),
        ],
        fn(x) { x },
      ),
    ),
    #(
      "usage",
      json.object([
        #("prompt_tokens", json.int(prompt)),
        #("completion_tokens", json.int(completion)),
        #("total_tokens", json.int(prompt + completion)),
        #("cost", json.float(cost)),
      ]),
    ),
  ])
  |> json.to_string
}

fn fixture(
  authorizations: List(Result(Nil, String)),
  reservation: Result(Nil, String),
  response: Result(#(Int, String), String),
) {
  let events = process.new_subject()
  let answers = process.new_subject()
  list.each(authorizations, fn(answer) { process.send(answers, answer) })
  let io =
    engine.EngineIo(
      worker.Io(
        credential: fn() {
          process.send(events, Credential)
          Some("fixture")
        },
        fetch_prices: fn(_) {
          process.send(events, Fetch)
          Ok(#(
            200,
            "{\"data\":[{\"id\":\"moonshotai/kimi-k3\",\"pricing\":{\"prompt\":\"0.000003\",\"completion\":\"0.000015\"}}]}",
          ))
        },
        post: fn(_, body, _) {
          process.send(events, Post(body))
          response
        },
        now_ms: fn() { 0 },
      ),
      authorize: fn() {
        process.send(events, Authorize)
        let assert Ok(answer) = process.receive(answers, 100)
        answer
      },
      reserve: fn(json, body) {
        process.send(events, Reserve(json, body))
        reservation
      },
    )
  #(io, events)
}

fn run(io: engine.EngineIo) {
  engine.execute("calibration:one", worker.CodingKimi, request(), io)
}

fn no_more(events) {
  process.receive(events, 0) |> should.be_error
}

fn event(events, expected) {
  process.receive(events, 100) |> should.equal(Ok(expected))
}

fn before_post(events) {
  event(events, Authorize)
  event(events, Credential)
  event(events, Fetch)
  event(events, Authorize)
}

fn reservation_event(events) {
  let assert Ok(Reserve(ledger_json, body)) = process.receive(events, 100)
  body |> should.equal(worker.request_json(request()))
  let assert Ok(price) = budget.provider_ceiling(request().model)
  let req = request()
  let assert Ok(admitted) =
    budget.admit(
      "calibration:one",
      req.model,
      req.max_tokens,
      req.system <> req.user,
      body,
      price,
    )
  ledger_json |> should.equal(budget.ledger_request_json(admitted))
}

pub fn success_orders_three_fences_one_reservation_one_post_test() {
  let #(io, events) =
    fixture(
      [Ok(Nil), Ok(Nil), Ok(Nil)],
      Ok(Nil),
      Ok(#(200, reply(100, 20, 0.001))),
    )
  let assert Ok(outcome) = run(io)
  outcome.reply.content |> should.equal("Check stale epochs.")
  before_post(events)
  reservation_event(events)
  event(events, Authorize)
  event(events, Post(worker.request_json(request())))
  no_more(events)
}

pub fn initial_fence_denial_prevents_credential_catalog_budget_and_post_test() {
  let #(io, events) =
    fixture([Error("task_expired")], Ok(Nil), Ok(#(200, reply(1, 1, 0.0))))
  run(io) |> should.equal(Error("task_expired"))
  event(events, Authorize)
  no_more(events)
}

pub fn fence_after_catalog_denies_before_reservation_test() {
  let #(io, events) =
    fixture(
      [Ok(Nil), Error("stale_attempt")],
      Ok(Nil),
      Ok(#(200, reply(1, 1, 0.0))),
    )
  run(io) |> should.equal(Error("transport: stale_attempt"))
  before_post(events)
  no_more(events)
}

pub fn unavailable_exhausted_duplicate_budget_cannot_post_or_refund_test() {
  list.each(
    [
      "ledger_missing",
      "ledger_corrupt",
      "budget_exhausted",
      "duplicate_call_id",
    ],
    fn(reason) {
      let #(io, events) =
        fixture([Ok(Nil), Ok(Nil)], Error(reason), Ok(#(200, reply(1, 1, 0.0))))
      run(io) |> should.equal(Error("transport: " <> reason))
      before_post(events)
      reservation_event(events)
      no_more(events)
    },
  )
}

pub fn fence_after_reservation_denies_post_and_keeps_liability_test() {
  let #(io, events) =
    fixture(
      [Ok(Nil), Ok(Nil), Error("lease_lost")],
      Ok(Nil),
      Ok(#(200, reply(1, 1, 0.0))),
    )
  run(io) |> should.equal(Error("transport: lease_lost"))
  before_post(events)
  reservation_event(events)
  event(events, Authorize)
  no_more(events)
}

pub fn body_binding_mismatch_has_no_authority_budget_or_post_io_test() {
  let #(io, events) = fixture([], Ok(Nil), Ok(#(200, reply(1, 1, 0.0))))
  let assert Ok(prepared) =
    engine.prepare("calibration:one", worker.CodingKimi, request())
  engine.post_bound(
    prepared,
    io,
    "fixture",
    worker.request_json(request()) <> " ",
    30_000,
  )
  |> should.equal(Error("request_body_binding_mismatch"))
  no_more(events)
}

pub fn direct_post_timeout_cannot_exceed_the_prepared_bound_test() {
  let #(io, events) = fixture([], Ok(Nil), Ok(#(200, reply(1, 1, 0.0))))
  let assert Ok(prepared) =
    engine.prepare("calibration:one", worker.CodingKimi, request())
  list.each([-1, 0, 30_001, 1_000_000], fn(timeout_ms) {
    engine.post_bound(
      prepared,
      io,
      "fixture",
      worker.request_json(request()),
      timeout_ms,
    )
    |> should.equal(Error("invalid_request: timeout_bound"))
  })
  no_more(events)
}

pub fn free_profile_mismatched_model_bad_id_and_unsafe_input_have_no_io_test() {
  let #(io, events) = fixture([], Ok(Nil), Ok(#(200, reply(1, 1, 0.0))))
  engine.execute("valid", worker.FreeAdvisory, request(), io) |> should.be_error
  engine.execute("valid", worker.DecisionGemma, request(), io)
  |> should.be_error
  engine.execute("bad/id", worker.CodingKimi, request(), io) |> should.be_error
  engine.execute(
    "valid",
    worker.CodingKimi,
    worker.Request(..request(), user: "private /home/example"),
    io,
  )
  |> should.be_error
  engine.execute(
    "valid",
    worker.CodingKimi,
    worker.Request(..request(), max_tokens: 4097),
    io,
  )
  |> should.be_error
  no_more(events)
}

pub fn untrusted_live_prices_prevent_reservation_and_post_test() {
  let #(io, events) = fixture([Ok(Nil)], Ok(Nil), Ok(#(200, reply(1, 1, 0.0))))
  let changed =
    engine.EngineIo(
      ..io,
      worker_io: worker.Io(..io.worker_io, fetch_prices: fn(_) {
        Error("catalog_unavailable")
      }),
    )
  run(changed) |> should.equal(Error("transport: catalog_unavailable"))
  event(events, Authorize)
  event(events, Credential)
  no_more(events)
}

pub fn returned_prompt_usage_must_fit_actual_admitted_input_test() {
  let #(io, events) =
    fixture(
      [Ok(Nil), Ok(Nil), Ok(Nil)],
      Ok(Nil),
      Ok(#(200, reply(18_432, 20, 0.001))),
    )
  run(io) |> should.equal(Error("provider_violated_reservation_bound"))
  before_post(events)
  reservation_event(events)
  event(events, Authorize)
  event(events, Post(worker.request_json(request())))
  no_more(events)
}

pub fn worker_strict_receipt_checks_and_transport_failure_never_retry_test() {
  list.each(
    [
      Ok(#(200, reply(100, 257, 0.001))),
      Ok(#(200, reply(100, 20, 0.2500001))),
      Ok(#(200, "{}")),
      Error("timeout_uncertain"),
    ],
    fn(response) {
      let #(io, events) =
        fixture([Ok(Nil), Ok(Nil), Ok(Nil)], Ok(Nil), response)
      run(io) |> should.be_error
      before_post(events)
      reservation_event(events)
      event(events, Authorize)
      event(events, Post(worker.request_json(request())))
      no_more(events)
    },
  )
}
