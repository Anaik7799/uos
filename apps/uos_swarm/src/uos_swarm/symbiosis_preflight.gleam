//// Pure development preflight policy; no task, restart, deployment or spend authority.
//// Caller supplies monotonic elapsed milliseconds in one epoch, never wall time.
//// Eight capability classes do not establish coverage of every MCP service.

import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub type Agent {
  Claude
  Pi
  Agy
  Codex
}

pub type Capability {
  KnowledgeSearch
  KnowledgeRead
  KnowledgeWriteback
  TaskAuthority
  TaskExecution
  Verification
  ModelBudget
  Transport
}

pub type Dimension {
  Function
  Performance
  Operation
}

pub type Check {
  Heartbeat
  Functional
  FullCoverage
}

pub type Probe {
  HeartbeatProbe
  CapabilityProbe(Capability)
  CoverageProbe
}

pub type Health {
  Unknown
  Ready
  Stopped
}

pub type Reason {
  ProbeFailed
  ProbeUnavailable
  TimedOut
  MissingDimension
}

pub type Binding {
  Binding(candidate: String, config: String, session: String)
}

pub type Config {
  Config(
    heartbeat_ms: Int,
    functional_ms: Int,
    coverage_ms: Int,
    timeout_ms: Int,
    minimum_spacing_ms: Int,
    backoff_max_ms: Int,
    jitter_ms: Int,
  )
}

pub type Request {
  Request(
    seq: Int,
    agent: Agent,
    probe: Probe,
    binding: Binding,
    started_ms: Int,
  )
}

pub type Results {
  Results(
    function: Option(Bool),
    performance: Option(Bool),
    operation: Option(Bool),
  )
}

pub type Observation {
  Observation(
    seq: Int,
    binding: Binding,
    observed_ms: Int,
    elapsed_ms: Int,
    results: Results,
    reason: Reason,
  )
}

/// Caller-bound manifest; structural validity does not attest official catalog completeness.
pub type Registry {
  Registry(agent: Agent, binding: Binding, required_services: List(String))
}

pub type ServiceDimension {
  ServiceDimension(passed: Bool, observed_ms: Int)
}

pub type ServiceObservation {
  ServiceObservation(
    agent: Agent,
    service_id: String,
    binding: Binding,
    function: ServiceDimension,
    performance: ServiceDimension,
    operation: ServiceDimension,
  )
}

pub type CoverageEvidence {
  CoverageEvidence(
    agent: Agent,
    binding: Binding,
    services: List(ServiceObservation),
  )
}

type CoverageState {
  CoverageState(
    agent: Agent,
    proof: Option(CoverageEvidence),
    success_at: Option(Int),
    failed: Bool,
    streak: Int,
  )
}

type Evidence {
  Evidence(
    seen: Option(Int),
    success_at: Option(Int),
    failed: Bool,
    streak: Int,
  )
}

type Slot {
  Slot(
    agent: Agent,
    probe: Probe,
    function: Evidence,
    performance: Evidence,
    operation: Evidence,
    due_ms: Int,
    last_seq: Int,
    failures: Int,
  )
}

type Event {
  Event(agent: Agent, probe: Probe, reason: Reason)
}

pub opaque type State {
  State(
    bindings: List(#(Agent, Binding)),
    config: Config,
    slots: List(Slot),
    pending: Option(Request),
    next_seq: Int,
    now_ms: Int,
    last_dispatch_ms: Option(Int),
    history: List(Event),
    heartbeat_streak: Int,
    registries: List(Registry),
    coverage: List(CoverageState),
  )
}

pub fn agents() -> List(Agent) {
  [Claude, Pi, Agy, Codex]
}

pub fn capabilities() -> List(Capability) {
  [
    KnowledgeSearch,
    KnowledgeRead,
    KnowledgeWriteback,
    TaskAuthority,
    TaskExecution,
    Verification,
    ModelBudget,
    Transport,
  ]
}

pub fn defaults() -> Config {
  Config(30_000, 300_000, 1_800_000, 10_000, 1000, 300_000, 500)
}

pub fn request_check(r: Request) -> Check {
  case r.probe {
    HeartbeatProbe -> Heartbeat
    CapabilityProbe(_) -> Functional
    CoverageProbe -> FullCoverage
  }
}

fn empty() -> Evidence {
  Evidence(None, None, False, 0)
}

fn fresh_slot(a: Agent, p: Probe, now: Int) -> Slot {
  Slot(a, p, empty(), empty(), empty(), now, 0, 0)
}

fn valid_time(n: Int) -> Bool {
  n >= -9_000_000_000_000 && n <= 9_000_000_000_000
}

fn chars(s: String, alphabet: String) -> Bool {
  list.all(string.to_graphemes(s), fn(c) {
    string.byte_size(c) == 1 && string.contains(alphabet, c)
  })
}

fn valid_binding(b: Binding) -> Bool {
  string.byte_size(b.candidate) == 40
  && chars(b.candidate, "0123456789abcdef")
  && string.byte_size(b.config) == 64
  && chars(b.config, "0123456789abcdef")
  && string.byte_size(b.session) >= 1
  && string.byte_size(b.session) <= 128
  && chars(
    b.session,
    "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.:-",
  )
}

fn valid_config(c: Config) -> Bool {
  c.heartbeat_ms >= 1000
  && c.heartbeat_ms <= 300_000
  && c.functional_ms >= c.heartbeat_ms
  && c.functional_ms <= 3_600_000
  && c.coverage_ms >= c.functional_ms
  && c.coverage_ms <= 86_400_000
  && c.timeout_ms >= 100
  && c.timeout_ms <= 30_000
  && c.minimum_spacing_ms >= 100
  && c.minimum_spacing_ms <= c.heartbeat_ms
  && c.backoff_max_ms >= c.minimum_spacing_ms
  && c.backoff_max_ms <= 3_600_000
  && c.jitter_ms >= 0
  && c.jitter_ms <= 10_000
}

fn binding_for(s: State, a: Agent) -> Binding {
  // Construction guarantees exactly one binding for each closed agent.
  let assert Ok(#(_, b)) = list.find(s.bindings, fn(pair) { pair.0 == a })
  b
}

pub fn new(
  bindings: List(#(Agent, Binding)),
  config: Config,
  now_ms: Int,
) -> Result(State, String) {
  case
    list.length(list.take(bindings, 5)) == 4
    && list.all(agents(), fn(a) {
      list.count(bindings, fn(p) { p.0 == a }) == 1
    })
    && list.all(bindings, fn(p) { valid_binding(p.1) })
    && valid_config(config)
    && valid_time(now_ms)
  {
    False -> Error("invalid_binding_config_or_epoch")
    True -> {
      let slots =
        list.flat_map(agents(), fn(a) {
          [
            fresh_slot(a, HeartbeatProbe, now_ms),
            ..list.append(
              list.map(capabilities(), fn(c) {
                fresh_slot(a, CapabilityProbe(c), now_ms)
              }),
              [fresh_slot(a, CoverageProbe, now_ms)],
            )
          ]
        })
      Ok(State(bindings, config, slots, None, 1, now_ms, None, [], 0, [], []))
    }
  }
}

fn service_id(id: String) -> Bool {
  string.byte_size(id) >= 1
  && string.byte_size(id) <= 128
  && chars(
    id,
    "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.:/-",
  )
}

fn unique_ids(ids: List(String)) -> Bool {
  list.length(list.take(ids, 257)) <= 256
  && list.all(ids, fn(id) {
    service_id(id) && list.count(ids, fn(other) { other == id }) == 1
  })
}

fn valid_registry(s: State, r: Registry) -> Bool {
  r.binding == binding_for(s, r.agent)
  && r.required_services != []
  && unique_ids(r.required_services)
}

pub fn new_with_registry(
  bindings: List(#(Agent, Binding)),
  config: Config,
  registries: List(Registry),
  now_ms: Int,
) -> Result(State, String) {
  use s <- result.try(new(bindings, config, now_ms))
  case
    list.length(list.take(registries, 5)) <= 4
    && list.all(registries, fn(r) {
      valid_registry(s, r)
      && list.count(registries, fn(other) { other.agent == r.agent }) == 1
    })
  {
    True -> Ok(State(..s, registries: registries))
    False -> Error("invalid_required_service_registry")
  }
}

fn registry_for(s: State, a: Agent) -> Option(Registry) {
  case list.find(s.registries, fn(r) { r.agent == a }) {
    Ok(r) -> Some(r)
    Error(_) -> None
  }
}

fn coverage_for(s: State, a: Agent) -> CoverageState {
  case list.find(s.coverage, fn(c) { c.agent == a }) {
    Ok(c) -> c
    Error(_) -> CoverageState(a, None, None, False, 0)
  }
}

fn fresh_dimension(d: ServiceDimension, now: Int, age: Int) -> Bool {
  d.passed
  && valid_time(d.observed_ms)
  && d.observed_ms <= now
  && now - d.observed_ms <= age
}

fn proof_fresh(proof: CoverageEvidence, now: Int, age: Int) -> Bool {
  list.all(proof.services, fn(service) {
    list.all([service.function, service.performance, service.operation], fn(d) {
      fresh_dimension(d, now, age)
    })
  })
}

fn proof_valid(
  s: State,
  r: Request,
  o: Observation,
  proof: CoverageEvidence,
  now: Int,
) -> Bool {
  case registry_for(s, r.agent), r.probe {
    Some(registry), CoverageProbe -> {
      case list.length(list.take(proof.services, 257)) <= 256 {
        False -> False
        True -> {
          let ids = list.map(proof.services, fn(service) { service.service_id })
          proof.agent == r.agent
          && proof.binding == r.binding
          && registry.binding == r.binding
          && o.results.function == Some(True)
          && o.results.performance == Some(True)
          && o.results.operation == Some(True)
          && unique_ids(ids)
          && list.length(ids) == list.length(registry.required_services)
          && list.all(registry.required_services, fn(id) {
            list.contains(ids, id)
          })
          && list.all(proof.services, fn(service) {
            service.agent == r.agent
            && service.binding == r.binding
            && list.all(
              [service.function, service.performance, service.operation],
              fn(d) { d.observed_ms <= o.observed_ms },
            )
          })
          && proof_fresh(proof, now, s.config.coverage_ms)
        }
      }
    }
    _, _ -> False
  }
}

fn distinct_proof(previous: CoverageEvidence, next: CoverageEvidence) -> Bool {
  list.all(next.services, fn(service) {
    case
      list.find(previous.services, fn(old) {
        old.service_id == service.service_id
      })
    {
      Error(_) -> False
      Ok(old) ->
        service.function.observed_ms > old.function.observed_ms
        && service.performance.observed_ms > old.performance.observed_ms
        && service.operation.observed_ms > old.operation.observed_ms
    }
  })
}

fn coverage_update(
  s: State,
  r: Request,
  o: Observation,
  proof: Option(CoverageEvidence),
  now: Int,
) -> List(CoverageState) {
  case r.probe, registry_for(s, r.agent) {
    CoverageProbe, Some(_) -> {
      let previous = coverage_for(s, r.agent)
      let next = case proof {
        None -> CoverageState(r.agent, None, None, True, 0)
        Some(evidence) -> {
          let streak = case previous.proof, previous.success_at {
            Some(old), Some(at) if o.observed_ms > at ->
              case
                proof_fresh(old, now, s.config.coverage_ms)
                && distinct_proof(old, evidence)
              {
                True ->
                  case previous.streak >= 2 {
                    True -> 2
                    False -> previous.streak + 1
                  }
                False -> 1
              }
            _, _ -> 1
          }
          CoverageState(
            r.agent,
            Some(evidence),
            Some(o.observed_ms),
            previous.failed && streak < 2,
            streak,
          )
        }
      }
      [next, ..list.filter(s.coverage, fn(c) { c.agent != r.agent })]
    }
    _, _ -> s.coverage
  }
}

pub fn coverage_health(s: State, a: Agent, now_ms: Int) -> Health {
  case valid_time(now_ms) && now_ms >= s.now_ms, registry_for(s, a) {
    False, _ -> Stopped
    True, None -> Unknown
    True, Some(registry) -> {
      let c = coverage_for(s, a)
      case c.failed, c.proof {
        True, _ -> Stopped
        False, Some(proof) ->
          case
            registry.binding == binding_for(s, a)
            && proof.agent == a
            && proof.binding == registry.binding
            && proof_fresh(proof, now_ms, s.config.coverage_ms)
          {
            True -> Ready
            False -> Unknown
          }
        _, _ -> Unknown
      }
    }
  }
}

fn interval(c: Config, p: Probe) -> Int {
  case p {
    HeartbeatProbe -> c.heartbeat_ms
    CapabilityProbe(_) -> c.functional_ms
    CoverageProbe -> c.coverage_ms
  }
}

fn same(slot: Slot, r: Request) -> Bool {
  slot.agent == r.agent && slot.probe == r.probe
}

fn evidence_health(e: Evidence, now: Int, age: Int) -> Health {
  case e.failed, e.seen {
    True, _ -> Stopped
    False, Some(seen) if now >= seen && now - seen <= age -> Ready
    _, _ -> Unknown
  }
}

fn slot_healthy(slot: Slot, now: Int, c: Config) -> Bool {
  let age = interval(c, slot.probe)
  case slot.probe {
    HeartbeatProbe -> evidence_health(slot.operation, now, age) == Ready
    CoverageProbe -> False
    CapabilityProbe(_) ->
      list.all([slot.function, slot.performance, slot.operation], fn(e) {
        evidence_health(e, now, age) == Ready
      })
  }
}

fn update(e: Evidence, passed: Option(Bool), at: Int, age: Int) -> Evidence {
  case passed {
    None -> Evidence(None, None, e.failed, 0)
    Some(False) -> Evidence(Some(at), None, True, 0)
    Some(True) -> {
      let streak = case e.success_at {
        Some(previous) if at > previous && at - previous <= age ->
          case e.streak >= 2 {
            True -> 2
            False -> e.streak + 1
          }
        _ -> 1
      }
      Evidence(Some(at), Some(at), e.failed && streak < 2, streak)
    }
  }
}

fn backoff(c: Config, failures: Int, seq: Int) -> Int {
  let multiplier = case failures {
    0 -> 1
    1 -> 2
    2 -> 4
    3 -> 8
    4 -> 16
    _ -> 32
  }
  let base = c.minimum_spacing_ms * multiplier
  let jitter = seq % { c.jitter_ms + 1 }
  case base + jitter > c.backoff_max_ms {
    True -> c.backoff_max_ms
    False -> base + jitter
  }
}

fn apply_with_coverage(
  s: State,
  r: Request,
  o: Observation,
  now: Int,
  verified: Option(CoverageEvidence),
) -> State {
  let coverage = coverage_update(s, r, o, verified, now)
  let slots =
    list.map(s.slots, fn(slot) {
      case same(slot, r) {
        False -> slot
        True -> {
          let age = interval(s.config, r.probe)
          let f = case r.probe {
            CapabilityProbe(_) ->
              update(slot.function, o.results.function, o.observed_ms, age)
            _ -> slot.function
          }
          let p = case r.probe {
            CapabilityProbe(_) ->
              update(
                slot.performance,
                o.results.performance,
                o.observed_ms,
                age,
              )
            _ -> slot.performance
          }
          let op = case r.probe {
            CoverageProbe -> empty()
            _ -> update(slot.operation, o.results.operation, o.observed_ms, age)
          }
          let passed = case r.probe {
            CapabilityProbe(_) ->
              o.results.function == Some(True)
              && o.results.performance == Some(True)
              && o.results.operation == Some(True)
            HeartbeatProbe -> o.results.operation == Some(True)
            CoverageProbe -> verified != None
          }
          let failures = case passed {
            True -> 0
            False ->
              case slot.failures >= 32 {
                True -> 32
                False -> slot.failures + 1
              }
          }
          // Coverage stays UNKNOWN until a separate exact required-service proof exists.
          let delay = case r.probe {
            CoverageProbe ->
              case registry_for(s, r.agent), verified {
                Some(_), None -> backoff(s.config, failures, r.seq)
                _, _ ->
                  case list.find(coverage, fn(c) { c.agent == r.agent }) {
                    Ok(c) if c.failed && verified != None ->
                      s.config.minimum_spacing_ms
                    _ -> age
                  }
              }
            _ ->
              case passed {
                True ->
                  case f.failed || p.failed || op.failed {
                    True -> s.config.minimum_spacing_ms
                    False ->
                      case r.probe {
                        HeartbeatProbe ->
                          age
                          - s.config.minimum_spacing_ms
                          - { now - r.started_ms }
                        _ -> age
                      }
                  }
                False -> backoff(s.config, failures, r.seq)
              }
          }
          Slot(
            ..slot,
            function: f,
            performance: p,
            operation: op,
            due_ms: now + delay,
            last_seq: r.seq,
            failures: failures,
          )
        }
      }
    })
  let unsuccessful = case r.probe {
    CoverageProbe -> verified == None
    HeartbeatProbe -> o.results.operation != Some(True)
    CapabilityProbe(_) ->
      o.results.function != Some(True)
      || o.results.performance != Some(True)
      || o.results.operation != Some(True)
  }
  let history = case unsuccessful {
    True -> list.take([Event(r.agent, r.probe, o.reason), ..s.history], 32)
    False -> s.history
  }
  State(
    ..s,
    slots: slots,
    pending: None,
    now_ms: now,
    history: history,
    coverage: coverage,
  )
}

fn apply(s: State, r: Request, o: Observation, now: Int) -> State {
  apply_with_coverage(s, r, o, now, None)
}

fn advance(s: State, now: Int) -> Result(State, String) {
  case valid_time(now) && now >= s.now_ms {
    False -> Error("monotonic_epoch_regression_or_bound")
    True -> {
      case s.pending {
        Some(r) if now - r.started_ms > s.config.timeout_ms ->
          Ok(apply(
            s,
            r,
            Observation(
              r.seq,
              r.binding,
              now,
              now - r.started_ms,
              Results(Some(False), Some(False), Some(False)),
              TimedOut,
            ),
            now,
          ))
        _ -> Ok(State(..s, now_ms: now))
      }
    }
  }
}

/// Expire pending evidence without reserving or dispatching another probe.
/// Used after an external guardian has actually reaped an expired collector.
pub fn advance_time(s: State, now_ms: Int) -> Result(State, String) {
  advance(s, now_ms)
}

// Earliest due key wins; stable registry order only breaks ties. This prevents
// rapid retries of early agents starving never-observed later agents.
fn oldest_due(slots: List(Slot), now: Int) -> Option(Slot) {
  list.fold(slots, None, fn(best, slot) {
    case slot.due_ms <= now, best {
      False, _ -> best
      True, None -> Some(slot)
      True, Some(previous) ->
        case slot.due_ms < previous.due_ms {
          True -> Some(slot)
          False -> best
        }
    }
  })
}

// A reserved heartbeat lane protects short freshness deadlines. At most four
// consecutive heartbeat dispatches precede an already-due deep probe. This
// bounds starvation even when demand exceeds physical single-flight capacity.
fn choose_due(s: State, now: Int) -> Option(Slot) {
  let heartbeats =
    oldest_due(
      list.filter(s.slots, fn(slot) { slot.probe == HeartbeatProbe }),
      now,
    )
  let deep =
    oldest_due(
      list.filter(s.slots, fn(slot) { slot.probe != HeartbeatProbe }),
      now,
    )
  case heartbeats, deep, s.heartbeat_streak >= 4 {
    Some(_), Some(slot), True -> Some(slot)
    Some(slot), _, _ -> Some(slot)
    None, _, _ -> deep
  }
}

pub fn poll(
  s: State,
  now_ms: Int,
) -> Result(#(State, Option(Request)), String) {
  use s <- result.try(advance(s, now_ms))
  let spaced = case s.last_dispatch_ms {
    None -> True
    Some(last) -> now_ms - last >= s.config.minimum_spacing_ms
  }
  case s.pending, spaced {
    None, True ->
      case choose_due(s, now_ms) {
        None -> Ok(#(s, None))
        Some(slot) -> {
          let r =
            Request(
              s.next_seq,
              slot.agent,
              slot.probe,
              binding_for(s, slot.agent),
              now_ms,
            )
          Ok(#(
            State(
              ..s,
              pending: Some(r),
              next_seq: s.next_seq + 1,
              last_dispatch_ms: Some(now_ms),
              heartbeat_streak: case slot.probe {
                HeartbeatProbe ->
                  case s.heartbeat_streak >= 4 {
                    True -> 4
                    False -> s.heartbeat_streak + 1
                  }
                _ -> 0
              },
            ),
            Some(r),
          ))
        }
      }
    _, _ -> Ok(#(s, None))
  }
}

fn record_verified(
  s: State,
  r: Request,
  o: Observation,
  now_ms: Int,
  proof: Option(CoverageEvidence),
) -> Result(State, String) {
  case
    valid_time(now_ms)
    && now_ms >= s.now_ms
    && s.pending == Some(r)
    && r.binding == binding_for(s, r.agent)
    && o.binding == r.binding
    && o.seq == r.seq
    && o.observed_ms >= r.started_ms
    && o.observed_ms <= now_ms
    && now_ms - r.started_ms <= s.config.timeout_ms
    && o.elapsed_ms == o.observed_ms - r.started_ms
    && o.elapsed_ms >= 0
  {
    True -> Ok(apply_with_coverage(s, r, o, now_ms, proof))
    False -> Error("observation_pending_binding_sequence_or_time_mismatch")
  }
}

pub fn record(
  s: State,
  r: Request,
  o: Observation,
  now_ms: Int,
) -> Result(State, String) {
  record_verified(s, r, o, now_ms, None)
}

/// Invalid proof is refused without mutation. The observer must separately record
/// its failed collection, as for other refused observations, before further work.
pub fn record_coverage(
  s: State,
  r: Request,
  o: Observation,
  proof: CoverageEvidence,
  now_ms: Int,
) -> Result(State, String) {
  case proof_valid(s, r, o, proof, now_ms) {
    True -> record_verified(s, r, o, now_ms, Some(proof))
    False ->
      Error("coverage_registry_identity_dimensions_or_freshness_mismatch")
  }
}

pub fn record_failure(
  s: State,
  r: Request,
  reason: Reason,
  now_ms: Int,
) -> Result(State, String) {
  record(
    s,
    r,
    Observation(
      r.seq,
      r.binding,
      now_ms,
      now_ms - r.started_ms,
      Results(Some(False), Some(False), Some(False)),
      reason,
    ),
    now_ms,
  )
}

pub fn demand(
  s: State,
  a: Agent,
  p: Probe,
  now_ms: Int,
) -> Result(State, String) {
  use s <- result.try(advance(s, now_ms))
  let slots =
    list.map(s.slots, fn(slot) {
      case
        slot.agent == a
        && slot.probe == p
        && slot.failures == 0
        && case p {
          CoverageProbe -> coverage_health(s, a, now_ms) != Ready
          _ -> !slot_healthy(slot, now_ms, s.config)
        }
        && slot.due_ms > now_ms
      {
        True -> Slot(..slot, due_ms: now_ms)
        False -> slot
      }
    })
  Ok(State(..s, slots: slots))
}

pub fn rebind(
  s: State,
  a: Agent,
  b: Binding,
  now_ms: Int,
) -> Result(State, String) {
  use s <- result.try(advance(s, now_ms))
  case valid_binding(b) {
    False -> Error("invalid_binding")
    True ->
      case b == binding_for(s, a) {
        True -> Ok(s)
        False -> {
          let bindings =
            list.map(s.bindings, fn(pair) {
              case pair.0 == a {
                True -> #(a, b)
                False -> pair
              }
            })
          let slots =
            list.map(s.slots, fn(slot) {
              case slot.agent == a {
                True -> fresh_slot(a, slot.probe, now_ms)
                False -> slot
              }
            })
          let pending = case s.pending {
            Some(r) if r.agent == a -> None
            _ -> s.pending
          }
          Ok(
            State(
              ..s,
              bindings: bindings,
              slots: slots,
              pending: pending,
              registries: list.filter(s.registries, fn(r) { r.agent != a }),
              coverage: list.filter(s.coverage, fn(c) { c.agent != a }),
            ),
          )
        }
      }
  }
}

pub fn status(
  s: State,
  a: Agent,
  c: Capability,
  d: Dimension,
  now_ms: Int,
) -> Health {
  case valid_time(now_ms) && now_ms >= s.now_ms {
    False -> Stopped
    True -> {
      let assert Ok(slot) =
        list.find(s.slots, fn(slot) {
          slot.agent == a && slot.probe == CapabilityProbe(c)
        })
      let e = case d {
        Function -> slot.function
        Performance -> slot.performance
        Operation -> slot.operation
      }
      evidence_health(e, now_ms, s.config.functional_ms)
    }
  }
}

fn get_slot(s: State, a: Agent, p: Probe) -> Slot {
  let assert Ok(slot) =
    list.find(s.slots, fn(slot) { slot.agent == a && slot.probe == p })
  slot
}

pub fn heartbeat_health(s: State, a: Agent, now_ms: Int) -> Health {
  case valid_time(now_ms) && now_ms >= s.now_ms {
    False -> Stopped
    True ->
      evidence_health(
        get_slot(s, a, HeartbeatProbe).operation,
        now_ms,
        s.config.heartbeat_ms,
      )
  }
}

fn age_json(e: Evidence, now: Int) -> json.Json {
  case e.seen {
    Some(at) if now >= at -> json.int(now - at)
    _ -> json.null()
  }
}

fn next_due_json(slot: Slot, now: Int) -> json.Json {
  json.int(case slot.due_ms > now {
    True -> slot.due_ms - now
    False -> 0
  })
}

fn agent_name(a: Agent) -> String {
  case a {
    Claude -> "claude"
    Pi -> "pi"
    Agy -> "agy"
    Codex -> "codex"
  }
}

fn health_name(h: Health) -> String {
  case h {
    Unknown -> "UNKNOWN"
    Ready -> "READY_SCOPED_OBSERVATION"
    Stopped -> "STOP_SCOPED_CAPABILITY"
  }
}

fn capability_name(c: Capability) -> String {
  case c {
    KnowledgeSearch -> "knowledge_search"
    KnowledgeRead -> "knowledge_read"
    KnowledgeWriteback -> "knowledge_writeback"
    TaskAuthority -> "task_authority"
    TaskExecution -> "task_execution"
    Verification -> "verification"
    ModelBudget -> "model_budget"
    Transport -> "transport"
  }
}

pub fn to_json(s: State, now_ms: Int) -> json.Json {
  json.object([
    #("schema", json.string("uos-symbiosis-preflight-v1")),
    #("authority", json.string("NONE")),
    #("runtime_enforcement", json.bool(False)),
    #(
      "availability_guarantee",
      json.string("NONE_CAPACITY_AND_COLLECTOR_LATENCY_DEPENDENT"),
    ),
    #("heartbeat_burst_limit", json.int(4)),
    #(
      "cadence_ms",
      json.object([
        #("heartbeat", json.int(s.config.heartbeat_ms)),
        #("functional", json.int(s.config.functional_ms)),
        #("coverage", json.int(s.config.coverage_ms)),
        #("timeout", json.int(s.config.timeout_ms)),
        #("minimum_spacing", json.int(s.config.minimum_spacing_ms)),
        #("backoff_max", json.int(s.config.backoff_max_ms)),
        #("jitter_max", json.int(s.config.jitter_ms)),
      ]),
    ),
    #(
      "required_service_coverage",
      json.string(case s.registries {
        [] -> "UNKNOWN_EXACT_SERVICE_REGISTRY_NOT_PROVEN"
        _ ->
          "SCOPED_CALLER_BOUND_REGISTRIES_OFFICIAL_CATALOG_COMPLETENESS_UNVERIFIED"
      }),
    ),
    #("fixed_probe_keys", json.int(40)),
    #("max_in_flight", json.int(1)),
    #(
      "in_flight",
      json.int(case s.pending {
        None -> 0
        Some(_) -> 1
      }),
    ),
    #("history_retained", json.int(list.length(s.history))),
    #("history_bound", json.int(32)),
    #("clock_valid", json.bool(valid_time(now_ms) && now_ms >= s.now_ms)),
    #(
      "rca_groups",
      json.array(
        [ProbeFailed, ProbeUnavailable, TimedOut, MissingDimension],
        fn(reason) {
          json.object([
            #(
              "reason",
              json.string(case reason {
                ProbeFailed -> "probe_failed"
                ProbeUnavailable -> "probe_unavailable"
                TimedOut -> "timed_out"
                MissingDimension -> "missing_dimension"
              }),
            ),
            #(
              "retained_count",
              json.int(list.count(s.history, fn(e) { e.reason == reason })),
            ),
          ])
        },
      ),
    ),
    #(
      "agents",
      json.array(agents(), fn(a) {
        json.object([
          #("agent", json.string(agent_name(a))),
          #(
            "coverage",
            json.object([
              #(
                "status",
                json.string(case coverage_health(s, a, now_ms) {
                  Ready -> "READY_SCOPED_REGISTRY_OBSERVATION"
                  Unknown -> "UNKNOWN"
                  Stopped -> "STOP_SCOPED_REGISTRY"
                }),
              ),
              #(
                "required_service_count",
                json.int(case registry_for(s, a) {
                  None -> 0
                  Some(r) -> list.length(r.required_services)
                }),
              ),
              #(
                "next_due_in_ms",
                next_due_json(get_slot(s, a, CoverageProbe), now_ms),
              ),
              #("last_seq", json.int(get_slot(s, a, CoverageProbe).last_seq)),
            ]),
          ),
          #(
            "heartbeat",
            json.object([
              #(
                "status",
                json.string(health_name(heartbeat_health(s, a, now_ms))),
              ),
              #(
                "age_ms",
                age_json(get_slot(s, a, HeartbeatProbe).operation, now_ms),
              ),
              #(
                "next_due_in_ms",
                next_due_json(get_slot(s, a, HeartbeatProbe), now_ms),
              ),
              #("last_seq", json.int(get_slot(s, a, HeartbeatProbe).last_seq)),
            ]),
          ),
          #(
            "capabilities",
            json.array(capabilities(), fn(c) {
              let slot = get_slot(s, a, CapabilityProbe(c))
              json.object([
                #("function_age_ms", age_json(slot.function, now_ms)),
                #("performance_age_ms", age_json(slot.performance, now_ms)),
                #("operation_age_ms", age_json(slot.operation, now_ms)),
                #("next_due_in_ms", next_due_json(slot, now_ms)),
                #("last_seq", json.int(slot.last_seq)),
                #("capability", json.string(capability_name(c))),
                #(
                  "function",
                  json.string(health_name(status(s, a, c, Function, now_ms))),
                ),
                #(
                  "performance",
                  json.string(health_name(status(s, a, c, Performance, now_ms))),
                ),
                #(
                  "operation",
                  json.string(health_name(status(s, a, c, Operation, now_ms))),
                ),
              ])
            }),
          ),
        ])
      }),
    ),
  ])
}
