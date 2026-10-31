import gleam/erlang/process.{type Pid, type Subject}
import gleam/list
import gleam/option.{Some}
import gleam/string
import gleeunit/should
import uos_swarm/symbiosis_preflight as policy
import uos_swarm/symbiosis_watchdog as watchdog

type Event {
  Started(Pid, policy.Request, Subject(Nil))
  OwnerReady(Pid, Subject(watchdog.Message), Subject(Nil))
  ObservedRequest(policy.Request)
  HostileStarted(Pid, Pid)
}

type InfoKey {
  Links
}

pub type Timeout {
  Timeout
}

@external(erlang, "erlang", "process_info")
fn linked_processes(pid: Pid, key: InfoKey) -> #(InfoKey, List(Pid))

fn binding(session: String) -> policy.Binding {
  policy.Binding(string.repeat("a", 40), string.repeat("b", 64), session)
}

fn bindings() {
  list.map(policy.agents(), fn(agent) { #(agent, binding("session-one")) })
}

fn config(timeout: Int) -> policy.Config {
  policy.Config(1000, 10_000, 60_000, timeout, 100, 1000, 0)
}

fn observation(r: policy.Request) -> policy.Observation {
  let now = watchdog.now_ms()
  policy.Observation(
    r.seq,
    r.binding,
    now,
    now - r.started_ms,
    policy.Results(Some(True), Some(True), Some(True)),
    policy.MissingDimension,
  )
}

fn blocked(events: Subject(Event)) {
  fn(r: policy.Request) {
    let release = process.new_subject()
    process.send(events, Started(process.self(), r, release))
    process.receive_forever(release)
    Ok(watchdog.Collected(observation(r), "bounded"))
  }
}

fn started(events: Subject(Event)) {
  let assert Ok(Started(pid, request, release)) = process.receive(events, 1500)
  #(pid, request, release)
}

fn down(pid: Pid, monitor: process.Monitor) {
  let selector =
    process.new_selector()
    |> process.select_specific_monitor(monitor, fn(value) { value })
  let assert Ok(process.ProcessDown(_, actual, _)) =
    process.selector_receive(selector, 2000)
  actual |> should.equal(pid)
  process.is_alive(pid) |> should.be_false
}

fn start(collector, timeout) {
  let assert Ok(owner) =
    watchdog.start_actor(
      bindings(),
      config(timeout),
      watchdog.Config(60_000, 32, 1000),
      collector,
    )
  owner
}

pub fn startup_probe_and_manual_storm_singleflight_test() {
  let events = process.new_subject()
  let owner = start(blocked(events), 1000)
  let worker = started(events)
  // No tick was required for the first probe. These ticks never create timers.
  list.each(list.repeat(Nil, 100), fn(_) { watchdog.tick(owner.data) })
  list.each(list.repeat(Nil, 100), fn(_) {
    watchdog.demand(owner.data, worker.1.agent, worker.1.probe)
  })
  let assert Ok(before) = watchdog.snapshot(owner.data, 1000)
  before.counters.started |> should.equal(1)
  before.counters.coalesced |> should.equal(200)
  before.in_flight |> should.be_true
  process.send(worker.2, Nil)
  let assert Ok(after) = watchdog.await_idle(owner.data, 1000)
  after.counters.completed |> should.equal(1)
  after.counters.started |> should.equal(1)
  after.outcome |> should.equal(watchdog.Accepted)
  after.in_flight |> should.be_false
  process.is_alive(worker.0) |> should.be_false
  watchdog.stop(owner.data, 1500) |> should.equal(Ok(Nil))
}

pub fn heartbeat_cannot_promote_deep_function_performance_operation_test() {
  let owner =
    start(fn(r) { Ok(watchdog.Collected(observation(r), "ok")) }, 1000)
  let assert Ok(s) = watchdog.await_idle(owner.data, 1000)
  s.counters.heartbeats |> should.equal(1)
  s.counters.functional |> should.equal(0)
  s.counters.coverage |> should.equal(0)
  list.each(policy.agents(), fn(agent) {
    list.each(policy.capabilities(), fn(capability) {
      list.each(
        [policy.Function, policy.Performance, policy.Operation],
        fn(dimension) {
          policy.status(
            s.policy,
            agent,
            capability,
            dimension,
            watchdog.now_ms(),
          )
          |> should.equal(policy.Unknown)
        },
      )
    })
  })
  watchdog.stop(owner.data, 1500) |> should.equal(Ok(Nil))
}

pub fn timeout_kills_and_reaps_before_releasing_flight_test() {
  let events = process.new_subject()
  let owner = start(blocked(events), 100)
  let worker = started(events)
  let monitor = process.monitor(worker.0)
  down(worker.0, monitor)
  let assert Ok(s) = watchdog.await_idle(owner.data, 1500)
  s.counters.timeouts |> should.equal(1)
  s.counters.completed |> should.equal(1)
  s.counters.started |> should.equal(1)
  s.outcome |> should.equal(watchdog.DeadlineExceeded)
  s.in_flight |> should.be_false
  watchdog.stop(owner.data, 1500) |> should.equal(Ok(Nil))
}

pub fn stop_confirms_worker_and_owner_exit_test() {
  let events = process.new_subject()
  let owner = start(blocked(events), 1000)
  let worker = started(events)
  let wm = process.monitor(worker.0)
  let om = process.monitor(owner.pid)
  watchdog.stop(owner.data, 1500) |> should.equal(Ok(Nil))
  down(worker.0, wm)
  down(owner.pid, om)
  // No collector or independent ticker can restart work after owner stop.
  process.receive(events, 20) |> should.equal(Error(Nil))
}

fn nested_owner(events: Subject(Event)) -> Pid {
  process.spawn_unlinked(fn() {
    let finish = process.new_subject()
    let owner = start(blocked(events), 1000)
    process.send(events, OwnerReady(owner.pid, owner.data, finish))
    process.receive_forever(finish)
  })
}

fn owner_and_worker(events: Subject(Event)) {
  let assert Ok(first) = process.receive(events, 1500)
  let assert Ok(second) = process.receive(events, 1500)
  case first, second {
    OwnerReady(pid, subject, release), Started(worker, _, _) -> #(
      pid,
      subject,
      release,
      worker,
    )
    Started(worker, _, _), OwnerReady(pid, subject, release) -> #(
      pid,
      subject,
      release,
      worker,
    )
    _, _ -> panic as "expected_owner_and_worker_handshakes"
  }
}

pub fn normal_parent_death_reaps_blocked_collector_test() {
  let events = process.new_subject()
  let parent = nested_owner(events)
  let handles = owner_and_worker(events)
  let wm = process.monitor(handles.3)
  let om = process.monitor(handles.0)
  let pm = process.monitor(parent)
  process.send(handles.2, Nil)
  down(parent, pm)
  down(handles.3, wm)
  down(handles.0, om)
}

pub fn abrupt_parent_death_guardian_reaps_collector_test() {
  let events = process.new_subject()
  let parent = nested_owner(events)
  let handles = owner_and_worker(events)
  let wm = process.monitor(handles.3)
  let om = process.monitor(handles.0)
  let pm = process.monitor(parent)
  process.kill(parent)
  down(parent, pm)
  down(handles.0, om)
  down(handles.3, wm)
}

pub fn explicit_collector_error_and_body_limit_have_typed_outcomes_test() {
  let owner =
    start(fn(_) { Error(string.repeat("PRIVATE_RAW_ERROR", 1000)) }, 1000)
  let assert Ok(error) = watchdog.await_idle(owner.data, 1000)
  error.outcome |> should.equal(watchdog.CollectorFailed)
  error.counters.errors |> should.equal(1)
  error.counters.body_bytes |> should.equal(0)
  watchdog.stop(owner.data, 1500) |> should.equal(Ok(Nil))
  let owner =
    start(
      fn(r) { Ok(watchdog.Collected(observation(r), string.repeat("x", 33))) },
      1000,
    )
  let assert Ok(large) = watchdog.await_idle(owner.data, 1000)
  large.outcome |> should.equal(watchdog.BodyRefused)
  large.counters.oversized |> should.equal(1)
  large.counters.body_bytes |> should.equal(0)
  watchdog.stop(owner.data, 1500) |> should.equal(Ok(Nil))
  let owner =
    start(
      fn(r) { Ok(watchdog.Collected(observation(r), string.repeat("x", 32))) },
      1000,
    )
  let assert Ok(exact) = watchdog.await_idle(owner.data, 1000)
  exact.outcome |> should.equal(watchdog.Accepted)
  exact.counters.body_bytes |> should.equal(32)
  watchdog.stop(owner.data, 1500) |> should.equal(Ok(Nil))
}

pub fn stale_sequence_binding_and_time_cannot_refresh_evidence_test() {
  list.each([0, 1, 2], fn(mutant) {
    let owner =
      start(
        fn(r) {
          let o = observation(r)
          let changed = case mutant {
            0 -> policy.Observation(..o, seq: o.seq + 1)
            1 -> policy.Observation(..o, binding: binding("foreign-session"))
            _ -> policy.Observation(..o, observed_ms: r.started_ms - 1)
          }
          Ok(watchdog.Collected(changed, "ok"))
        },
        1000,
      )
    let assert Ok(s) = watchdog.await_idle(owner.data, 1000)
    s.outcome |> should.equal(watchdog.StaleResult)
    s.counters.stale |> should.equal(1)
    s.counters.completed |> should.equal(1)
    watchdog.stop(owner.data, 1500) |> should.equal(Ok(Nil))
  })
}

pub fn collector_exception_does_not_kill_observer_test() {
  let owner = start(fn(_) { panic as "test_collector_exception" }, 1000)
  let assert Ok(s) = watchdog.await_idle(owner.data, 1000)
  s.outcome |> should.equal(watchdog.CollectorExited)
  s.counters.errors |> should.equal(1)
  process.is_alive(owner.pid) |> should.be_true
  watchdog.stop(owner.data, 1500) |> should.equal(Ok(Nil))
}

pub fn rebind_reaps_old_worker_before_new_binding_test() {
  let events = process.new_subject()
  let owner = start(blocked(events), 1000)
  let worker = started(events)
  let wm = process.monitor(worker.0)
  watchdog.rebind(owner.data, worker.1.agent, binding("session-two"), 1500)
  |> should.equal(Ok(Nil))
  down(worker.0, wm)
  let assert Ok(s) = watchdog.snapshot(owner.data, 1000)
  s.counters.cancelled |> should.equal(1)
  s.counters.started |> should.equal(1)
  s.in_flight |> should.be_false
  watchdog.stop(owner.data, 1500) |> should.equal(Ok(Nil))
}

pub fn periodic_owner_timer_reuses_policy_spacing_and_tiers_test() {
  let events = process.new_subject()
  let assert Ok(owner) =
    watchdog.start_actor(
      bindings(),
      config(1000),
      watchdog.Config(10, 32, 1000),
      fn(r) {
        process.send(events, ObservedRequest(r))
        Ok(watchdog.Collected(observation(r), "ok"))
      },
    )
  let requests =
    list.map(list.repeat(Nil, 5), fn(_) {
      let assert Ok(ObservedRequest(r)) = process.receive(events, 2000)
      r
    })
  let assert Ok(s) = watchdog.await_idle(owner.data, 1000)
  s.counters.started |> should.equal(5)
  s.counters.heartbeats |> should.equal(4)
  s.counters.functional |> should.equal(1)
  s.counters.coverage |> should.equal(0)
  { s.counters.ticks > 5 } |> should.be_true
  list.length(list.unique(list.map(requests, fn(r) { r.seq })))
  |> should.equal(5)
  watchdog.stop(owner.data, 1500) |> should.equal(Ok(Nil))
}

pub fn invalid_identical_and_unrelated_rebind_do_not_abort_collector_test() {
  let events = process.new_subject()
  let owner = start(blocked(events), 1000)
  let worker = started(events)
  watchdog.rebind(owner.data, worker.1.agent, worker.1.binding, 1000)
  |> should.equal(Ok(Nil))
  watchdog.rebind(
    owner.data,
    worker.1.agent,
    policy.Binding("invalid", string.repeat("b", 64), "invalid"),
    1000,
  )
  |> should.equal(Error("invalid_rebind"))
  let assert Ok(other) =
    list.find(policy.agents(), fn(a) { a != worker.1.agent })
  watchdog.rebind(owner.data, other, binding("different-agent-session"), 1000)
  |> should.equal(Ok(Nil))
  let assert Ok(s) = watchdog.snapshot(owner.data, 1000)
  s.counters.cancelled |> should.equal(0)
  s.counters.started |> should.equal(1)
  process.is_alive(worker.0) |> should.be_true
  process.send(worker.2, Nil)
  let assert Ok(done) = watchdog.await_idle(owner.data, 1000)
  done.outcome |> should.equal(watchdog.Accepted)
  watchdog.stop(owner.data, 1500) |> should.equal(Ok(Nil))
}

pub fn invalid_configuration_refused_before_collector_test() {
  list.each(
    [
      watchdog.Config(0, 32, 100),
      watchdog.Config(10, -1, 100),
      watchdog.Config(10, 65_537, 100),
      watchdog.Config(10, 32, 0),
    ],
    fn(c) {
      watchdog.start_actor(bindings(), config(1000), c, fn(_) {
        panic as "invalid_config_must_not_collect"
      })
      |> should.be_error
    },
  )
}

pub fn policy_refusal_counts_as_error_for_future_and_elapsed_mismatch_test() {
  list.each([True, False], fn(future) {
    let owner =
      start(
        fn(r) {
          let o = observation(r)
          let changed = case future {
            True ->
              policy.Observation(
                ..o,
                observed_ms: o.observed_ms + 100,
                elapsed_ms: o.elapsed_ms + 100,
              )
            False -> policy.Observation(..o, elapsed_ms: o.elapsed_ms + 1)
          }
          Ok(watchdog.Collected(changed, "ok"))
        },
        1000,
      )
    let assert Ok(s) = watchdog.await_idle(owner.data, 1000)
    s.outcome |> should.equal(watchdog.PolicyRefused)
    s.counters.errors |> should.equal(1)
    s.counters.completed |> should.equal(1)
    watchdog.stop(owner.data, 1500) |> should.equal(Ok(Nil))
  })
}

fn wait_fenced(
  observer: Subject(watchdog.Message),
  deadline: Int,
) -> watchdog.Snapshot {
  let assert Ok(s) = watchdog.snapshot(observer, 1000)
  case s.outcome == watchdog.ReapUnconfirmed || watchdog.now_ms() >= deadline {
    True -> s
    False -> wait_fenced(observer, deadline)
  }
}

pub fn hostile_trap_exit_and_guardian_loss_fence_without_cleanup_claim_test() {
  let events = process.new_subject()
  let owner =
    start(
      fn(_) {
        process.trap_exits(True)
        let assert #(Links, [guardian]) =
          linked_processes(process.self(), Links)
        process.send(events, HostileStarted(process.self(), guardian))
        process.sleep_forever()
        Error("unreachable")
      },
      1000,
    )
  let assert Ok(HostileStarted(worker, guardian)) =
    process.receive(events, 1000)
  let gm = process.monitor(guardian)
  process.kill(guardian)
  down(guardian, gm)
  let s = wait_fenced(owner.data, watchdog.now_ms() + 1000)
  s.outcome |> should.equal(watchdog.ReapUnconfirmed)
  s.in_flight |> should.be_true
  process.is_alive(worker) |> should.be_true
  list.each(list.repeat(Nil, 100), fn(_) { watchdog.tick(owner.data) })
  let assert Ok(still) = watchdog.snapshot(owner.data, 1000)
  still.counters.started |> should.equal(1)
  still.counters.errors |> should.equal(1)
  still.in_flight |> should.be_true
  // Deliberately hostile collector violated the documented trusted boundary.
  // Fixture cleanup is explicit; do not describe this case as automatic reap.
  let wm = process.monitor(worker)
  process.kill(worker)
  down(worker, wm)
  process.unlink(owner.pid)
  let om = process.monitor(owner.pid)
  process.kill(owner.pid)
  down(owner.pid, om)
}

fn registry(agent: policy.Agent) -> policy.Registry {
  policy.Registry(agent, binding("session-one"), [
    "knowledge-search",
    "task-read",
  ])
}

fn proof(r: policy.Request, o: policy.Observation) -> policy.CoverageEvidence {
  let observed = case r.agent {
    // This fixture's coverage freshness window is 300000ms. A receipt from
    // just before dispatch is fresh cache evidence, not a stale falsifier.
    policy.Pi -> r.started_ms - 300_001
    _ -> o.observed_ms
  }
  let services = case r.agent {
    policy.Claude -> ["knowledge-search", "unconfigured-service"]
    _ -> ["knowledge-search", "task-read"]
  }
  let dimension = policy.ServiceDimension(True, observed)
  policy.CoverageEvidence(
    r.agent,
    r.binding,
    list.map(services, fn(id) {
      let leaf_agent = case r.agent {
        policy.Codex -> policy.Agy
        _ -> r.agent
      }
      policy.ServiceObservation(
        leaf_agent,
        id,
        r.binding,
        dimension,
        dimension,
        dimension,
      )
    }),
  )
}

pub fn actual_coverage_wrong_old_valid_and_cross_agent_proof_test_() {
  #(Timeout, 10, coverage_actor_scenario)
}

fn coverage_actor_scenario() {
  let events = process.new_subject()
  // Long cadences keep startup checks due once; only the real owner timer and
  // configured 100ms minimum spacing advance the forty finite checks.
  let pc = policy.Config(300_000, 300_000, 300_000, 1000, 100, 1000, 0)
  let assert Ok(owner) =
    watchdog.start_actor_with_registry(
      bindings(),
      pc,
      watchdog.Config(10, 32, 1000),
      list.map(policy.agents(), registry),
      fn(r) {
        let o = observation(r)
        case r.probe {
          policy.CoverageProbe -> {
            process.send(events, ObservedRequest(r))
            Ok(watchdog.CollectedWithCoverage(o, "proof", proof(r, o)))
          }
          _ -> Ok(watchdog.Collected(o, "ok"))
        }
      },
    )
  let requests =
    list.map(list.repeat(Nil, 4), fn(_) {
      let assert Ok(ObservedRequest(request)) = process.receive(events, 2500)
      let assert Ok(s) = watchdog.await_idle(owner.data, 1500)
      case request.agent {
        policy.Claude | policy.Pi -> {
          s.outcome |> should.equal(watchdog.PolicyRefused)
          {
            policy.coverage_health(s.policy, request.agent, watchdog.now_ms())
            != policy.Ready
          }
          |> should.be_true
        }
        policy.Agy -> {
          s.outcome |> should.equal(watchdog.Accepted)
          policy.coverage_health(s.policy, request.agent, watchdog.now_ms())
          |> should.equal(policy.Ready)
        }
        policy.Codex -> {
          // Bindings and service IDs are identical across all four agents.
          // A correct new header cannot relabel Agy-attributed leaf evidence.
          s.outcome |> should.equal(watchdog.StaleResult)
          {
            policy.coverage_health(s.policy, request.agent, watchdog.now_ms())
            != policy.Ready
          }
          |> should.be_true
        }
      }
      request
    })
  list.map(requests, fn(r) { r.agent })
  |> should.equal([policy.Claude, policy.Pi, policy.Agy, policy.Codex])
  let assert Ok(s) = watchdog.snapshot(owner.data, 1000)
  s.counters.coverage |> should.equal(4)
  s.counters.errors |> should.equal(3)
  s.counters.stale |> should.equal(1)
  watchdog.stop(owner.data, 1500) |> should.equal(Ok(Nil))
}
