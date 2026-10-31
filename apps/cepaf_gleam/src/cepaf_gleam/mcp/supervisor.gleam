//// OTP Supervision for the Unified MCP Gateway (`mcp_unified_gateway`) and
//// bounded isolated worker pool with automatic poisoned-worker replacement.

import cepaf_gleam/mcp/candidate_id
import cepaf_gleam/mcp/receipts.{type ReceiptLedger}
import gleam/erlang/process
import gleam/otp/actor
import gleam/otp/static_supervisor as sup
import gleam/otp/supervision

pub type GatewayMessage {
  Ping(reply_with: process.Subject(Bool))
}

pub type SupervisedGateway {
  SupervisedGateway(
    child_id: String,
    supervisor_pid: process.Pid,
    gateway_subject: process.Subject(GatewayMessage),
  )
}

pub type WorkerPool {
  WorkerPool(
    size: Int,
    active_generation: Int,
    poisoned_count: Int,
    ledger: ReceiptLedger,
  )
}

pub fn start_gateway_actor() -> Result(
  actor.Started(process.Subject(GatewayMessage)),
  actor.StartError,
) {
  actor.new(True)
  |> actor.on_message(fn(state, msg) {
    case msg {
      Ping(reply) -> {
        process.send(reply, state)
        actor.continue(state)
      }
    }
  })
  |> actor.start
}

pub fn supervised() -> supervision.ChildSpecification(
  process.Subject(GatewayMessage),
) {
  supervision.worker(fn() { start_gateway_actor() })
}

pub type GatewayHandle

@external(erlang, "mcp_stdio_ffi", "gateway_handle_new")
fn handle_new() -> GatewayHandle

@external(erlang, "mcp_stdio_ffi", "gateway_handle_set")
fn handle_set(
  box: GatewayHandle,
  subject: process.Subject(GatewayMessage),
) -> Nil

@external(erlang, "mcp_stdio_ffi", "gateway_handle_register")
fn handle_register(pid: process.Pid, box: GatewayHandle) -> Nil

@external(erlang, "mcp_stdio_ffi", "gateway_handle_get")
fn handle_get(
  pid: process.Pid,
  fallback: process.Subject(GatewayMessage),
) -> process.Subject(GatewayMessage)

pub fn current_gateway_subject(
  gateway: SupervisedGateway,
) -> process.Subject(GatewayMessage) {
  handle_get(gateway.supervisor_pid, gateway.gateway_subject)
}

pub fn start_supervised_gateway() -> Result(SupervisedGateway, actor.StartError) {
  let box = handle_new()
  let child =
    supervision.worker(fn() {
      case start_gateway_actor() {
        Ok(started) -> {
          handle_set(box, started.data)
          Ok(started)
        }
        Error(error) -> Error(error)
      }
    })
  case
    sup.new(sup.OneForOne)
    |> sup.restart_tolerance(intensity: 20, period: 60)
    |> sup.add(child)
    |> sup.start
  {
    Error(error) -> Error(error)
    Ok(started) -> {
      handle_register(started.pid, box)
      Ok(SupervisedGateway(
        "mcp_unified_gateway",
        started.pid,
        handle_get(started.pid, process.new_subject()),
      ))
    }
  }
}

pub fn is_gateway_alive(gateway: SupervisedGateway) -> Bool {
  let subject = current_gateway_subject(gateway)
  case
    process.is_alive(gateway.supervisor_pid),
    process.subject_owner(subject)
  {
    True, Ok(pid) ->
      case process.is_alive(pid) {
        False -> False
        True -> {
          let reply = process.new_subject()
          process.send(subject, Ping(reply))
          process.receive(reply, 1000) == Ok(True)
        }
      }
    _, _ -> False
  }
}

pub fn child_id(gateway: SupervisedGateway) -> String {
  gateway.child_id
}

pub fn start_worker_pool(size size: Int) -> Result(WorkerPool, String) {
  let cand = candidate_id.current()
  case candidate_id.is_sha256_digest(cand) {
    False -> Error("unobserved_or_invalid_source_candidate")
    True -> start_worker_pool_for_candidate(size: size, candidate: cand)
  }
}

pub fn start_worker_pool_for_candidate(
  size size: Int,
  candidate candidate: String,
) -> Result(WorkerPool, String) {
  case size > 0 {
    False -> Error("worker_pool_size_must_be_positive")
    True ->
      case candidate_id.is_valid(candidate) {
        False -> Error("invalid_worker_pool_candidate")
        True ->
          Ok(WorkerPool(
            size: size,
            active_generation: 1,
            poisoned_count: 0,
            ledger: receipts.new_ledger(candidate),
          ))
      }
  }
}

pub fn active_worker_generation(pool: WorkerPool) -> Int {
  pool.active_generation
}

pub fn replace_poisoned_worker(pool: WorkerPool) -> WorkerPool {
  WorkerPool(
    ..pool,
    active_generation: pool.active_generation + 1,
    poisoned_count: pool.poisoned_count + 1,
  )
}
