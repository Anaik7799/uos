import cepaf_gleam/harness/telegram_poll_rpc
import gleam/erlang/process
import gleeunit/should

pub type TestRequest {
  Ping(reply_with: process.Subject(Result(String, String)))
}

fn spawn_worker(
  handler: fn(process.Subject(TestRequest)) -> Nil,
) -> #(process.Pid, process.Subject(TestRequest)) {
  let parent = process.new_subject()
  let pid =
    process.spawn_unlinked(fn() {
      let inbox = process.new_subject()
      process.send(parent, inbox)
      handler(inbox)
    })
  let assert Ok(inbox) = process.receive(parent, 1000)
  #(pid, inbox)
}

pub fn deadline_valid_bounds_test() {
  telegram_poll_rpc.deadline(1)
  |> should.equal(Ok(1501))

  telegram_poll_rpc.deadline(10_000)
  |> should.equal(Ok(11_500))

  telegram_poll_rpc.deadline(60_000)
  |> should.equal(Ok(61_500))
}

pub fn deadline_invalid_bounds_test() {
  telegram_poll_rpc.deadline(0)
  |> should.equal(Error("invalid_http_timeout_ms"))

  telegram_poll_rpc.deadline(-50)
  |> should.equal(Error("invalid_http_timeout_ms"))

  telegram_poll_rpc.deadline(60_001)
  |> should.equal(Error("invalid_http_timeout_ms"))
}

pub fn rpc_invalid_timeout_rejects_before_send_test() {
  let observed = process.new_subject()
  let #(pid, worker) =
    spawn_worker(fn(inbox) {
      case process.receive(inbox, 200) {
        Ok(Ping(_reply)) -> process.send(observed, "received")
        Error(Nil) -> Nil
      }
    })

  telegram_poll_rpc.call(worker, 0, Ping)
  |> should.equal(Error("invalid_poller_rpc_timeout_ms"))

  telegram_poll_rpc.call(worker, -1, Ping)
  |> should.equal(Error("invalid_poller_rpc_timeout_ms"))

  telegram_poll_rpc.call(worker, 61_501, Ping)
  |> should.equal(Error("invalid_poller_rpc_timeout_ms"))

  process.receive(observed, 50)
  |> should.equal(Error(Nil))
  process.kill(pid)
}

pub fn rpc_normal_reply_and_no_duplicate_send_test() {
  let count_subject = process.new_subject()
  let #(pid, worker) =
    spawn_worker(fn(inbox) {
      let assert Ok(Ping(reply)) = process.receive(inbox, 500)
      process.send(count_subject, 1)
      process.send(reply, Ok("pong"))
      case process.receive(inbox, 50) {
        Ok(_) -> process.send(count_subject, 2)
        Error(Nil) -> Nil
      }
    })

  telegram_poll_rpc.call(worker, 500, Ping)
  |> should.equal(Ok("pong"))

  process.receive(count_subject, 200)
  |> should.equal(Ok(1))
  process.receive(count_subject, 80)
  |> should.equal(Error(Nil))
  process.kill(pid)
}

pub fn rpc_typed_error_reply_test() {
  let #(pid, worker) =
    spawn_worker(fn(inbox) {
      let assert Ok(Ping(reply)) = process.receive(inbox, 500)
      process.send(reply, Error("upstream_bad_gateway"))
    })

  telegram_poll_rpc.call(worker, 500, Ping)
  |> should.equal(Error("upstream_bad_gateway"))
  process.kill(pid)
}

pub fn rpc_silent_worker_timeout_and_late_reply_isolation_test() {
  let #(pid, worker) =
    spawn_worker(fn(inbox) {
      let assert Ok(Ping(first_reply)) = process.receive(inbox, 500)
      process.sleep(80)
      process.send(first_reply, Ok("stale_pong"))
      let assert Ok(Ping(second_reply)) = process.receive(inbox, 500)
      process.send(second_reply, Ok("fresh_pong"))
    })

  telegram_poll_rpc.call(worker, 30, Ping)
  |> should.equal(Error("poller_worker_timeout"))

  process.sleep(70)

  telegram_poll_rpc.call(worker, 500, Ping)
  |> should.equal(Ok("fresh_pong"))
  process.kill(pid)
}

pub fn rpc_worker_death_returns_worker_down_test() {
  let #(pid, worker) =
    spawn_worker(fn(inbox) {
      let assert Ok(Ping(_reply)) = process.receive(inbox, 500)
      Nil
    })

  telegram_poll_rpc.call(worker, 500, Ping)
  |> should.equal(Error("poller_worker_down"))

  process.kill(pid)
  telegram_poll_rpc.call(worker, 500, Ping)
  |> should.equal(Error("poller_worker_down"))
}

pub fn named_worker_refused_before_lookup_or_send_test() {
  let name = process.new_name("telegram_poll_rpc_test")
  let subject = process.named_subject(name)
  telegram_poll_rpc.call(subject, 500, Ping)
  |> should.equal(Error("named_poller_worker_not_supported"))
}
