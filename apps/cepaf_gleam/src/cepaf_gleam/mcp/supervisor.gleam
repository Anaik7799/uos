//// OTP Supervision for the Unified MCP Gateway (`mcp_unified_gateway`) and
//// bounded isolated worker pool with automatic poisoned-worker replacement.

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

pub fn start_supervised_gateway() -> Result(SupervisedGateway, actor.StartError) {
  case start_gateway_actor() {
    Error(err) -> Error(err)
    Ok(started_gateway) -> {
      case
        sup.new(sup.OneForOne)
        |> sup.restart_tolerance(intensity: 5, period: 60)
        |> sup.add(supervised())
        |> sup.start
      {
        Error(err) -> Error(err)
        Ok(started_sup) ->
          Ok(SupervisedGateway(
            child_id: "mcp_unified_gateway",
            supervisor_pid: started_sup.pid,
            gateway_subject: started_gateway.data,
          ))
      }
    }
  }
}

pub fn is_gateway_alive(gateway: SupervisedGateway) -> Bool {
  process.is_alive(gateway.supervisor_pid)
  && process.call(gateway.gateway_subject, 1000, Ping)
}

pub fn child_id(gateway: SupervisedGateway) -> String {
  gateway.child_id
}

pub fn start_worker_pool(size size: Int) -> Result(WorkerPool, String) {
  case size > 0 {
    False -> Error("worker_pool_size_must_be_positive")
    True ->
      Ok(WorkerPool(
        size: size,
        active_generation: 1,
        poisoned_count: 0,
        ledger: receipts.new_ledger("uos-mcp-candidate"),
      ))
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
