//// Injected development observer, not production ingress or effect authority.
//// One owned timer and one collector globally per instance. Collector children
//// must be trusted BEAM-preemptible code, must not trap exits, and must not
//// spawn untracked children. This is not a sandbox or native-code time bound.
//// Raw bodies/errors never reach snapshots. No model, task, restart, or grant API.

import gleam/erlang/process.{type Pid, type Subject}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/otp/supervision
import gleam/result
import gleam/string
import uos_swarm/symbiosis_preflight as policy

type Unit {
  Millisecond
}

@external(erlang, "erlang", "monotonic_time")
fn monotonic(unit: Unit) -> Int

/// One native monotonic epoch; never compare this value with UTC.
pub fn now_ms() -> Int {
  monotonic(Millisecond)
}

pub type Config {
  Config(poll_ms: Int, max_body_bytes: Int, reap_ms: Int)
}

pub fn defaults() -> Config {
  Config(1000, 4096, 1000)
}

pub type Collected {
  Collected(observation: policy.Observation, body: String)
  CollectedWithCoverage(
    observation: policy.Observation,
    body: String,
    evidence: policy.CoverageEvidence,
  )
}

pub type Outcome {
  Starting
  Accepted
  CollectorFailed
  CollectorExited
  DeadlineExceeded
  BodyRefused
  StaleResult
  PolicyRefused
  ReapUnconfirmed
}

pub type Counters {
  Counters(
    ticks: Int,
    started: Int,
    heartbeats: Int,
    functional: Int,
    coverage: Int,
    completed: Int,
    errors: Int,
    timeouts: Int,
    oversized: Int,
    stale: Int,
    coalesced: Int,
    cancelled: Int,
    body_bytes: Int,
  )
}

pub type Snapshot {
  Snapshot(
    policy: policy.State,
    counters: Counters,
    in_flight: Bool,
    outcome: Outcome,
  )
}

pub opaque type Message {
  TimerTick(Int)
  Tick
  Demand(policy.Agent, policy.Probe)
  Rebind(policy.Agent, policy.Binding, Subject(Result(Nil, String)))
  Get(Subject(Snapshot))
  AwaitIdle(Subject(Result(Snapshot, String)))
  Stop(Subject(Result(Nil, String)))
  Finished(Int, Terminal)
  ReapBlocked(Int)
  Down(process.Down)
}

type Terminal {
  Observed(policy.Observation, Int)
  CoverageObserved(policy.Observation, Int, policy.CoverageEvidence)
  Failed
  Exited
  Expired
  TooLarge
  IdentityRejected
}

type Control {
  Begin
  Cancel(Subject(Result(Nil, String)))
}

type GuardMessage {
  ControlMessage(Control)
  Returned(Terminal)
  OwnerDown(process.Down)
  WorkerDown(process.Down)
}

type Flight {
  Flight(
    request: policy.Request,
    pid: Pid,
    monitor: process.Monitor,
    control: Subject(Control),
  )
}

type Runtime {
  Runtime(
    policy: policy.State,
    policy_config: policy.Config,
    config: Config,
    collector: fn(policy.Request) -> Result(Collected, String),
    self: Subject(Message),
    parent: Pid,
    timer: process.Timer,
    timer_seq: Int,
    flight: Option(Flight),
    counters: Counters,
    outcome: Outcome,
    waiters: List(Subject(Result(Snapshot, String))),
    bindings: List(#(policy.Agent, policy.Binding)),
  )
}

fn zero() -> Counters {
  Counters(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
}

fn view(r: Runtime) -> Snapshot {
  Snapshot(r.policy, r.counters, r.flight != None, r.outcome)
}

fn settled(r: Runtime) -> Runtime {
  list.each(r.waiters, fn(reply) { process.send(reply, Ok(view(r))) })
  Runtime(..r, waiters: [])
}

fn valid(c: Config) -> Bool {
  c.poll_ms >= 10
  && c.poll_ms <= 60_000
  && c.max_body_bytes >= 0
  && c.max_body_bytes <= 65_536
  && c.reap_ms >= 10
  && c.reap_ms <= 1000
}

fn safe_result(
  request: policy.Request,
  max_bytes: Int,
  collected: Result(Collected, String),
) -> Terminal {
  case collected {
    Error(_) -> Failed
    Ok(c) ->
      case string.byte_size(c.body) > max_bytes {
        True -> TooLarge
        False -> {
          let o = c.observation
          case
            o.seq == request.seq
            && o.binding == request.binding
            && o.observed_ms >= request.started_ms
            && o.observed_ms <= 9_000_000_000_000
            && o.elapsed_ms >= 0
            && o.elapsed_ms <= 60_000
          {
            True ->
              case c {
                Collected(_, _) -> Observed(o, string.byte_size(c.body))
                CollectedWithCoverage(_, _, evidence) ->
                  case bounded_proof(evidence, request) {
                    True ->
                      CoverageObserved(o, string.byte_size(c.body), evidence)
                    False -> IdentityRejected
                  }
              }
            False -> IdentityRejected
          }
        }
      }
  }
}

fn bounded_proof(
  evidence: policy.CoverageEvidence,
  request: policy.Request,
) -> Bool {
  evidence.agent == request.agent
  && evidence.binding == request.binding
  && list.length(evidence.services) <= 256
  && list.all(evidence.services, fn(s) {
    s.agent == request.agent
    && s.binding == request.binding
    && string.byte_size(s.service_id) <= 128
    && list.all(
      [
        s.function.observed_ms,
        s.performance.observed_ms,
        s.operation.observed_ms,
      ],
      fn(t) { t >= -9_000_000_000_000 && t <= 9_000_000_000_000 },
    )
  })
}

// A guardian is finite per invocation, not a ticker. It is deliberately not
// linked to its owner, so even normal/abrupt owner death runs worker cleanup.
// Its collector is linked: unexpected guardian failure kills a conforming
// non-trapping collector. If that trust boundary is violated, the owner fences
// the unconfirmed flight; full hostile-code cleanup is explicitly not promised.
fn guardian(
  owner: Pid,
  reply: Subject(Message),
  request: policy.Request,
  timeout_ms: Int,
  config: Config,
  collector: fn(policy.Request) -> Result(Collected, String),
  hello: Subject(Subject(Control)),
) -> Nil {
  process.trap_exits(True)
  let owner_monitor = process.monitor(owner)
  let control = process.new_subject()
  process.send(hello, control)
  let initial =
    process.new_selector()
    |> process.select_map(control, ControlMessage)
    |> process.select_specific_monitor(owner_monitor, OwnerDown)
  case process.selector_receive(initial, 1000) {
    Ok(ControlMessage(Begin)) -> {
      let returned = process.new_subject()
      let worker =
        process.spawn(fn() {
          let out =
            safe_result(request, config.max_body_bytes, collector(request))
          process.send(returned, out)
        })
      let monitor = process.monitor(worker)
      let selector =
        initial
        |> process.select_map(returned, Returned)
        |> process.select_specific_monitor(monitor, WorkerDown)
      // Policy's elapsed bound is inclusive; expiry occurs at timeout + 1ms.
      let deadline = request.started_ms + timeout_ms + 1
      guard_wait(
        reply,
        request.seq,
        deadline,
        worker,
        monitor,
        selector,
        config.reap_ms,
      )
    }
    Ok(ControlMessage(Cancel(ack))) -> process.send(ack, Ok(Nil))
    _ -> Nil
  }
  process.demonitor_process(owner_monitor)
}

fn reap(worker: Pid, monitor: process.Monitor, within: Int) -> Bool {
  process.kill(worker)
  let down =
    process.new_selector()
    |> process.select_specific_monitor(monitor, fn(d) { d })
  case process.selector_receive(down, within) {
    Ok(_) -> True
    Error(_) -> False
  }
}

fn finish(
  reply: Subject(Message),
  seq: Int,
  terminal: Terminal,
  worker: Pid,
  monitor: process.Monitor,
  selector: process.Selector(GuardMessage),
  within: Int,
  ack: Option(Subject(Result(Nil, String))),
  owner_alive: Bool,
) -> Nil {
  case reap(worker, monitor, within) {
    True -> {
      case ack {
        Some(a) -> process.send(a, Ok(Nil))
        None -> Nil
      }
      case owner_alive {
        True -> process.send(reply, Finished(seq, terminal))
        False -> Nil
      }
    }
    False -> {
      case ack {
        Some(a) -> process.send(a, Error("worker_reap_unconfirmed"))
        None -> Nil
      }
      case owner_alive {
        True -> process.send(reply, ReapBlocked(seq))
        False -> Nil
      }
      // Keep the flight fenced; neither a timeout nor an unconfirmed kill frees
      // capacity. This path cannot promise native-code preemption or liveness.
      wait_reap(reply, seq, terminal, worker, selector, owner_alive)
    }
  }
}

fn wait_reap(
  reply: Subject(Message),
  seq: Int,
  terminal: Terminal,
  worker: Pid,
  selector: process.Selector(GuardMessage),
  owner_alive: Bool,
) -> Nil {
  case process.selector_receive_forever(selector) {
    WorkerDown(_) ->
      case owner_alive {
        True -> process.send(reply, Finished(seq, terminal))
        False -> Nil
      }
    OwnerDown(_) -> {
      process.kill(worker)
      wait_reap(reply, seq, terminal, worker, selector, False)
    }
    ControlMessage(Cancel(ack)) -> {
      process.send(ack, Error("worker_reap_unconfirmed"))
      wait_reap(reply, seq, terminal, worker, selector, owner_alive)
    }
    _ -> wait_reap(reply, seq, terminal, worker, selector, owner_alive)
  }
}

fn guard_wait(
  reply: Subject(Message),
  seq: Int,
  deadline: Int,
  worker: Pid,
  monitor: process.Monitor,
  selector: process.Selector(GuardMessage),
  within: Int,
) -> Nil {
  case process.selector_receive(selector, int.max(0, deadline - now_ms())) {
    Ok(Returned(terminal)) -> {
      let terminal = case now_ms() < deadline {
        True -> terminal
        False -> Expired
      }
      finish(
        reply,
        seq,
        terminal,
        worker,
        monitor,
        selector,
        within,
        None,
        True,
      )
    }
    Ok(WorkerDown(_)) -> process.send(reply, Finished(seq, Exited))
    Ok(OwnerDown(_)) ->
      finish(reply, seq, Failed, worker, monitor, selector, within, None, False)
    Ok(ControlMessage(Cancel(ack))) ->
      finish(
        reply,
        seq,
        Failed,
        worker,
        monitor,
        selector,
        within,
        Some(ack),
        True,
      )
    Error(_) ->
      finish(reply, seq, Expired, worker, monitor, selector, within, None, True)
    _ -> guard_wait(reply, seq, deadline, worker, monitor, selector, within)
  }
}

fn launch(r: Runtime, request: policy.Request) -> Runtime {
  let hello = process.new_subject()
  let owner = process.self()
  let pid =
    process.spawn_unlinked(fn() {
      guardian(
        owner,
        r.self,
        request,
        r.policy_config.timeout_ms,
        r.config,
        r.collector,
        hello,
      )
    })
  let monitor = process.monitor(pid)
  case process.receive(hello, 1000) {
    Ok(control) -> {
      let c = r.counters
      let #(h, f, all) = case policy.request_check(request) {
        policy.Heartbeat -> #(1, 0, 0)
        policy.Functional -> #(0, 1, 0)
        policy.FullCoverage -> #(0, 0, 1)
      }
      process.send(control, Begin)
      Runtime(
        ..r,
        flight: Some(Flight(request, pid, monitor, control)),
        counters: Counters(
          ..c,
          started: c.started + 1,
          heartbeats: c.heartbeats + h,
          functional: c.functional + f,
          coverage: c.coverage + all,
        ),
        outcome: Starting,
      )
    }
    Error(_) -> {
      process.kill(pid)
      process.demonitor_process(monitor)
      Runtime(
        ..r,
        outcome: CollectorExited,
        counters: Counters(..r.counters, errors: r.counters.errors + 1),
      )
    }
  }
}

fn drive(r: Runtime) -> Runtime {
  case r.flight {
    Some(_) ->
      Runtime(
        ..r,
        counters: Counters(..r.counters, coalesced: r.counters.coalesced + 1),
      )
    None ->
      case policy.poll(r.policy, now_ms()) {
        Error(_) -> Runtime(..r, outcome: PolicyRefused)
        Ok(#(p, None)) -> Runtime(..r, policy: p)
        Ok(#(p, Some(request))) -> launch(Runtime(..r, policy: p), request)
      }
  }
}

fn completion(r: Runtime, flight: Flight, terminal: Terminal) -> Runtime {
  process.demonitor_process(flight.monitor)
  let now = now_ms()
  let #(observed, outcome) = case terminal {
    Observed(o, _) -> #(
      policy.record(r.policy, flight.request, o, now),
      Accepted,
    )
    CoverageObserved(o, _, evidence) -> #(
      policy.record_coverage(r.policy, flight.request, o, evidence, now),
      Accepted,
    )
    Failed -> #(
      policy.record_failure(r.policy, flight.request, policy.ProbeFailed, now),
      CollectorFailed,
    )
    Exited -> #(
      policy.record_failure(
        r.policy,
        flight.request,
        policy.ProbeUnavailable,
        now,
      ),
      CollectorExited,
    )
    Expired -> #(
      policy.record_failure(r.policy, flight.request, policy.TimedOut, now),
      DeadlineExceeded,
    )
    TooLarge -> #(
      policy.record_failure(r.policy, flight.request, policy.ProbeFailed, now),
      BodyRefused,
    )
    IdentityRejected -> #(
      policy.record_failure(
        r.policy,
        flight.request,
        policy.ProbeUnavailable,
        now,
      ),
      StaleResult,
    )
  }
  // Expiry is recorded without reserving any replacement request. A late or
  // rejected response cannot retain a timed-out pending entry indefinitely.
  // A refused observation is a failed invocation, not a successful health
  // refresh. Record its failure when still within the policy deadline.
  let observed_state = case observed {
    Ok(p) -> p
    Error(_) ->
      policy.record_failure(r.policy, flight.request, policy.ProbeFailed, now)
      |> result.unwrap(r.policy)
  }
  let p = observed_state
  let p = policy.advance_time(p, now) |> result.unwrap(p)
  let outcome = case terminal, observed {
    Observed(_, _), Error(_) -> PolicyRefused
    CoverageObserved(_, _, _), Error(_) -> PolicyRefused
    _, _ -> outcome
  }
  let c = r.counters
  let c = Counters(..c, completed: c.completed + 1)
  let c = case outcome {
    PolicyRefused -> Counters(..c, errors: c.errors + 1)
    _ -> c
  }
  let c = case terminal {
    Observed(_, bytes) -> Counters(..c, body_bytes: bytes)
    CoverageObserved(_, bytes, _) -> Counters(..c, body_bytes: bytes)
    Expired -> Counters(..c, timeouts: c.timeouts + 1)
    TooLarge -> Counters(..c, oversized: c.oversized + 1, errors: c.errors + 1)
    IdentityRejected -> Counters(..c, stale: c.stale + 1, errors: c.errors + 1)
    _ -> Counters(..c, errors: c.errors + 1)
  }
  // The next owner timer/manual demand drives scheduling; completion itself
  // does not recursively dispatch a burst of all forty missing checks.
  settled(Runtime(..r, policy: p, flight: None, counters: c, outcome: outcome))
}

fn cancel(r: Runtime) -> Result(Runtime, String) {
  case r.flight {
    None -> Ok(r)
    Some(f) -> {
      let ack = process.new_subject()
      process.send(f.control, Cancel(ack))
      case process.receive(ack, r.config.reap_ms + 100) {
        Ok(Ok(_)) -> {
          process.demonitor_process(f.monitor)
          Ok(settled(
            Runtime(
              ..r,
              flight: None,
              counters: Counters(
                ..r.counters,
                cancelled: r.counters.cancelled + 1,
              ),
            ),
          ))
        }
        _ -> Error("worker_reap_unconfirmed")
      }
    }
  }
}

fn handle(r: Runtime, message: Message) -> actor.Next(Runtime, Message) {
  case message {
    TimerTick(seq) if seq == r.timer_seq -> {
      let seq = seq + 1
      let timer = process.send_after(r.self, r.config.poll_ms, TimerTick(seq))
      actor.continue(drive(
        Runtime(
          ..r,
          timer: timer,
          timer_seq: seq,
          counters: Counters(..r.counters, ticks: r.counters.ticks + 1),
        ),
      ))
    }
    TimerTick(_) -> actor.continue(r)
    Tick ->
      actor.continue(drive(
        Runtime(
          ..r,
          counters: Counters(..r.counters, ticks: r.counters.ticks + 1),
        ),
      ))
    Demand(agent, probe) -> {
      case policy.demand(r.policy, agent, probe, now_ms()) {
        Ok(p) -> actor.continue(drive(Runtime(..r, policy: p)))
        Error(_) -> actor.continue(Runtime(..r, outcome: PolicyRefused))
      }
    }
    Rebind(agent, binding, reply) -> {
      case list.any(r.bindings, fn(pair) { pair == #(agent, binding) }) {
        True -> {
          process.send(reply, Ok(Nil))
          actor.continue(r)
        }
        False ->
          case policy.rebind(r.policy, agent, binding, now_ms()) {
            Error(_) -> {
              process.send(reply, Error("invalid_rebind"))
              actor.continue(r)
            }
            Ok(p) -> {
              // A different agent's binding never invalidates this collector.
              let cancelled = case r.flight {
                Some(f) if f.request.agent == agent -> cancel(r)
                _ -> Ok(r)
              }
              case cancelled {
                Error(e) -> {
                  process.send(reply, Error(e))
                  actor.continue(Runtime(..r, outcome: ReapUnconfirmed))
                }
                Ok(r) -> {
                  let bindings =
                    list.map(r.bindings, fn(pair) {
                      case pair.0 == agent {
                        True -> #(agent, binding)
                        False -> pair
                      }
                    })
                  process.send(reply, Ok(Nil))
                  actor.continue(drive(
                    Runtime(..r, policy: p, bindings: bindings),
                  ))
                }
              }
            }
          }
      }
    }
    Get(reply) -> {
      process.send(reply, view(r))
      actor.continue(r)
    }
    AwaitIdle(reply) ->
      case r.flight {
        None -> {
          process.send(reply, Ok(view(r)))
          actor.continue(r)
        }
        Some(_) ->
          case list.length(r.waiters) < 16 {
            True -> actor.continue(Runtime(..r, waiters: [reply, ..r.waiters]))
            False -> {
              process.send(reply, Error("observer_waiter_limit"))
              actor.continue(r)
            }
          }
      }
    Finished(seq, terminal) ->
      case r.flight {
        Some(f) if f.request.seq == seq ->
          actor.continue(completion(r, f, terminal))
        _ ->
          actor.continue(
            Runtime(
              ..r,
              counters: Counters(..r.counters, stale: r.counters.stale + 1),
            ),
          )
      }
    ReapBlocked(seq) ->
      case r.flight {
        Some(f) if f.request.seq == seq ->
          actor.continue(Runtime(..r, outcome: ReapUnconfirmed))
        _ -> actor.continue(r)
      }
    Down(down) ->
      case down {
        process.ProcessDown(_, pid, _) if pid == r.parent -> {
          let _ = process.cancel_timer(r.timer)
          case cancel(r) {
            Ok(_) -> actor.stop()
            Error(_) ->
              actor.stop_abnormal("observer_owner_lost_reap_unconfirmed")
          }
        }
        process.ProcessDown(_, pid, _) ->
          case r.flight {
            // Guardian death alone does not prove its collector was reaped. Keep
            // the slot fenced rather than infer release from a parent DOWN.
            Some(f) if f.pid == pid ->
              actor.continue(
                Runtime(
                  ..r,
                  outcome: ReapUnconfirmed,
                  counters: Counters(
                    ..r.counters,
                    errors: r.counters.errors + 1,
                  ),
                ),
              )
            _ -> actor.continue(r)
          }
        _ -> actor.continue(r)
      }
    Stop(reply) ->
      case cancel(r) {
        Ok(_) -> {
          let _ = process.cancel_timer(r.timer)
          process.send(reply, Ok(Nil))
          actor.stop()
        }
        Error(e) -> {
          process.send(reply, Error(e))
          actor.continue(Runtime(..r, outcome: ReapUnconfirmed))
        }
      }
  }
}

fn start(
  bindings: List(#(policy.Agent, policy.Binding)),
  pconfig: policy.Config,
  config: Config,
  registries: Option(List(policy.Registry)),
  collector: fn(policy.Request) -> Result(Collected, String),
) -> actor.StartResult(Subject(Message)) {
  let parent = process.self()
  actor.new_with_initialiser(2000, fn(self) {
    use _ <- result.try(case valid(config) {
      True -> Ok(Nil)
      False -> Error("invalid_watchdog_config")
    })
    use p <- result.try(case registries {
      None -> policy.new(bindings, pconfig, now_ms())
      Some(registries) ->
        policy.new_with_registry(bindings, pconfig, registries, now_ms())
    })
    let _ = process.monitor(parent)
    let selector =
      process.new_selector()
      |> process.select(self)
      |> process.select_monitors(Down)
    let timer = process.send_after(self, config.poll_ms, TimerTick(1))
    let r =
      Runtime(
        p,
        pconfig,
        config,
        collector,
        self,
        parent,
        timer,
        1,
        None,
        zero(),
        Starting,
        [],
        bindings,
      )
    Ok(
      actor.initialised(drive(r))
      |> actor.selecting(selector)
      |> actor.returning(self),
    )
  })
  |> actor.on_message(handle)
  |> actor.start
}

pub fn start_actor(
  bindings: List(#(policy.Agent, policy.Binding)),
  pconfig: policy.Config,
  config: Config,
  collector: fn(policy.Request) -> Result(Collected, String),
) -> actor.StartResult(Subject(Message)) {
  start(bindings, pconfig, config, None, collector)
}

/// Readiness is scoped to these configured service IDs; it proves neither
/// authentication nor discovery of every service in the live installation.
pub fn start_actor_with_registry(
  bindings: List(#(policy.Agent, policy.Binding)),
  pconfig: policy.Config,
  config: Config,
  registries: List(policy.Registry),
  collector: fn(policy.Request) -> Result(Collected, String),
) -> actor.StartResult(Subject(Message)) {
  start(bindings, pconfig, config, Some(registries), collector)
}

pub fn child_spec_with_registry(
  bindings: List(#(policy.Agent, policy.Binding)),
  pconfig: policy.Config,
  config: Config,
  registries: List(policy.Registry),
  collector: fn(policy.Request) -> Result(Collected, String),
) -> supervision.ChildSpecification(Subject(Message)) {
  supervision.worker(fn() {
    start_actor_with_registry(bindings, pconfig, config, registries, collector)
  })
}

pub fn child_spec(
  bindings: List(#(policy.Agent, policy.Binding)),
  pconfig: policy.Config,
  config: Config,
  collector: fn(policy.Request) -> Result(Collected, String),
) -> supervision.ChildSpecification(Subject(Message)) {
  supervision.worker(fn() { start_actor(bindings, pconfig, config, collector) })
}

pub fn tick(observer: Subject(Message)) -> Nil {
  process.send(observer, Tick)
}

pub fn demand(
  observer: Subject(Message),
  agent: policy.Agent,
  probe: policy.Probe,
) -> Nil {
  process.send(observer, Demand(agent, probe))
}

pub fn snapshot(
  observer: Subject(Message),
  within: Int,
) -> Result(Snapshot, String) {
  let reply = process.new_subject()
  process.send(observer, Get(reply))
  process.receive(reply, within)
  |> result.replace_error("observer_reply_timeout")
}

/// Bounded sixteen-waiter barrier for worker reaping, not a passing-health gate.
pub fn await_idle(
  observer: Subject(Message),
  within: Int,
) -> Result(Snapshot, String) {
  let reply = process.new_subject()
  process.send(observer, AwaitIdle(reply))
  case process.receive(reply, within) {
    Ok(reply) -> reply
    Error(_) -> Error("observer_reply_timeout")
  }
}

pub fn stop(observer: Subject(Message), within: Int) -> Result(Nil, String) {
  let reply = process.new_subject()
  process.send(observer, Stop(reply))
  case process.receive(reply, within) {
    Ok(reply) -> reply
    Error(_) -> Error("observer_reply_timeout")
  }
}

pub fn rebind(
  observer: Subject(Message),
  agent: policy.Agent,
  binding: policy.Binding,
  within: Int,
) -> Result(Nil, String) {
  let reply = process.new_subject()
  process.send(observer, Rebind(agent, binding, reply))
  case process.receive(reply, within) {
    Ok(reply) -> reply
    Error(_) -> Error("observer_reply_timeout")
  }
}
