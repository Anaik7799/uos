//// Durable single-operation recovery owner PREPARATION. Public start has NO
//// admitted authority/worker adapter and cannot dispatch a task effect. A
//// private test-only appended extension exercises the same interpreter against
//// actual isolated workers. Journal commit and task commit are DIFFERENT DBs:
//// only Pending-before-dispatch and reconcile-only crash handling are claimed.
//// BEAM worker death is not native reaping; missing cleanup is terminal for
//// this owner. Trusted adapters must be BEAM-preemptible, not trap exits, and
//// not spawn untracked children. Clock/issuer/custody/revocation remain external.

import cepaf_gleam/harness/files
import cepaf_gleam/harness/native_launch
import cepaf_gleam/harness/recovery_factual_reply
import cepaf_gleam/harness/recovery_owner_store as store
import cepaf_gleam/harness/recovery_wire as wire
import cepaf_gleam/harness/telegram_store_transport as transport
import cepaf_gleam/harness/value as v
import cepaf_gleam/mcp/json_guard
import gleam/erlang/process.{type Pid, type Subject}
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/otp/supervision
import gleam/result
import gleam/string

type Unit {
  Millisecond
}

@external(erlang, "erlang", "monotonic_time")
fn mono(unit: Unit) -> Int

pub fn monotonic_ms() -> Int {
  mono(Millisecond)
}

pub opaque type ConfigurationData {
  ConfigurationData(
    journal: store.ConnectionData,
    binding: store.Binding,
    commit_body: String,
    inspect_body: String,
    request: String,
    capability_sha256: String,
    timeout_ms: Int,
  )
}

pub type Phase {
  Starting
  DataOnly
  Running
  ReconcileOnly
  CleanupUnconfirmed
  HistoricalFact
  Unavailable
}

/// durable is the LAST OBSERVED journal entry, not proof of absence during a
/// flight. observed_effect_exchanges counts returned exchange observations;
/// zero after a lost completion/timeout does NOT mean zero possible attempts.
/// No field supplies current task authority or financial/budget permission.
pub type Snapshot {
  Snapshot(
    operation_id: String,
    revision: Int,
    phase: Phase,
    in_flight: Bool,
    durable: Option(store.Entry),
    cleanup: store.Cleanup,
    observed_effect_exchanges: Int,
  )
}

pub type Step {
  Step(operation_id: String, revision: Int)
}

type QuiescenceContext {
  Startup
  BeforePending
  PendingCreatedByThisOwner
  Reconciliation
}

type Adapter {
  Adapter(
    admit: fn() -> Result(Nil, String),
    read_authority: fn() -> Result(Nil, String),
    quiescence: fn(QuiescenceContext) -> Result(Nil, String),
    effect: fn(String) -> store.RawExchange,
  )
}

fn unavailable() -> Adapter {
  Adapter(
    fn() { Error("ADMITTED_RECOVERY_AUTHORITY_UNAVAILABLE") },
    fn() { Error("READ_AUTHORITY_UNAVAILABLE") },
    fn(_) { Error("NATIVE_QUIESCENCE_UNAVAILABLE") },
    fn(_) { store.RawExchange(Error("WORKER_UNAVAILABLE"), store.Unconfirmed) },
  )
}

fn closed(value: v.Value, keys: List(String)) -> Result(Nil, String) {
  case value {
    v.Object(fs) ->
      case
        list.length(fs) == list.length(keys)
        && list.all(fs, fn(f) { list.contains(keys, f.0) })
      {
        True -> Ok(Nil)
        False -> Error("CLOSED_SCHEMA")
      }
    _ -> Error("CLOSED_SCHEMA")
  }
}

fn prepared(raw: String, operation: String) -> Result(v.Value, String) {
  use _ <- result.try(
    case string.byte_size(raw) > 0 && string.byte_size(raw) <= 32_768 {
      True -> Ok(Nil)
      False -> Error("PREPARED_BODY_BOUND")
    },
  )
  use value <- result.try(
    json_guard.native_inspect(raw, 6)
    |> result.map_error(fn(_) { "INVALID_JSON" }),
  )
  use _ <- result.try(
    closed(value, [
      "operation",
      "request",
      "capability",
      "reviewer_signature",
      "issuer_signature",
    ]),
  )
  use op <- result.try(store.text(value, "operation"))
  use _ <- result.try(case op == operation {
    True -> Ok(Nil)
    False -> Error("PREPARED_OPERATION")
  })
  Ok(value)
}

pub fn configuration_data(
  owner_id: String,
  request: wire.FactualRequest,
  context_sha256: String,
  commit_body: String,
  inspect_body: String,
  journal: transport.LocalConfiguration,
  timeout_ms: Int,
) -> Result(ConfigurationData, String) {
  configured_data(
    owner_id,
    request,
    context_sha256,
    commit_body,
    inspect_body,
    store.legacy_connection_data(journal),
    timeout_ms,
  )
}

/// Opt-in transport data only. Public start still uses unavailable(), and this
/// constructor authenticates neither artifact ownership nor signed DB identity.
pub fn finite_configuration_data(
  owner_id: String,
  request: wire.FactualRequest,
  context_sha256: String,
  commit_body: String,
  inspect_body: String,
  journal: native_launch.Configuration,
  timeout_ms: Int,
) -> Result(ConfigurationData, String) {
  configured_data(
    owner_id,
    request,
    context_sha256,
    commit_body,
    inspect_body,
    store.finite_connection_data(journal),
    timeout_ms,
  )
}

fn configured_data(
  owner_id: String,
  request: wire.FactualRequest,
  context_sha256: String,
  commit_body: String,
  inspect_body: String,
  journal: store.ConnectionData,
  timeout_ms: Int,
) -> Result(ConfigurationData, String) {
  use commit <- result.try(prepared(commit_body, "commit"))
  use inspect <- result.try(prepared(inspect_body, "inspect"))
  use native_request <- result.try(store.text(commit, "request"))
  use capability <- result.try(store.text(commit, "capability"))
  use _ <- result.try(
    case
      store.identifier(owner_id)
      && store.sha(context_sha256)
      && timeout_ms >= 50
      && timeout_ms <= 60_000
      && native_request == wire.canonical_bytes(request)
      && list.all(
        ["request", "capability", "reviewer_signature", "issuer_signature"],
        fn(k) { v.get(commit, k) == v.get(inspect, k) },
      )
    {
      True -> Ok(Nil)
      False -> Error("CONFIGURATION_DATA_BINDING")
    },
  )
  let operation =
    files.digest(
      json.to_string(
        json.object([
          #("domain", json.string("uos.recovery-owner-operation.v1")),
          #("request_sha256", json.string(wire.request_sha256(request))),
          #("context_sha256", json.string(context_sha256)),
          #("commit_body_sha256", json.string(files.digest(commit_body))),
        ]),
      ),
    )
  Ok(ConfigurationData(
    journal,
    store.Binding(
      owner_id,
      operation,
      wire.request_sha256(request),
      context_sha256,
    ),
    commit_body,
    inspect_body,
    native_request,
    files.digest(capability),
    timeout_ms,
  ))
}

pub fn operation_id(c: ConfigurationData) -> String {
  c.binding.operation_id
}

pub fn binding(c: ConfigurationData) -> store.Binding {
  c.binding
}

type Work {
  Load
  Dispatch
  Inspect
}

type ResultState {
  Settled(Phase, Option(store.Entry), store.Cleanup, Int)
}

type Completion {
  Completion(sequence: Int, result: ResultState)
}

type Flight {
  Flight(
    sequence: Int,
    pid: Pid,
    monitor: process.Monitor,
    timer: process.Timer,
    deadline: Int,
    reply: Option(Subject(Result(Snapshot, String))),
    done: Option(Completion),
  )
}

pub opaque type Message {
  Commit(Step, Subject(Result(Snapshot, String)))
  Reconcile(Subject(Result(Snapshot, String)))
  Get(Subject(Snapshot))
  Stop(Subject(Result(Nil, String)))
  Returned(Completion)
  Timeout(Int)
  Down(process.Down)
  LinkedExit(process.ExitMessage)
}

type State {
  State(
    config: ConfigurationData,
    adapter: Adapter,
    self: Subject(Message),
    completion: Subject(Completion),
    parent: Pid,
    parent_monitor: process.Monitor,
    owner_lost: Bool,
    flight: Option(Flight),
    sequence: Int,
    revision: Int,
    phase: Phase,
    durable: Option(store.Entry),
    cleanup: store.Cleanup,
    effects: Int,
    stop_reply: Option(Subject(Result(Nil, String))),
  )
}

fn snapshot(s: State) -> Snapshot {
  Snapshot(
    s.config.binding.operation_id,
    s.revision,
    s.phase,
    s.flight != None,
    s.durable,
    s.cleanup,
    s.effects,
  )
}

fn fresh(deadline: Int) -> Result(Nil, String) {
  case monotonic_ms() < deadline {
    True -> Ok(Nil)
    False -> Error("OWNER_MONOTONIC_DEADLINE")
  }
}

fn live(
  a: Adapter,
  stage: QuiescenceContext,
  read_only: Bool,
  deadline: Int,
) -> Result(Nil, String) {
  use _ <- result.try(fresh(deadline))
  use _ <- result.try(a.quiescence(stage))
  use _ <- result.try(fresh(deadline))
  use _ <- result.try(case read_only {
    True -> a.read_authority()
    False -> a.admit()
  })
  fresh(deadline)
}

fn latest(c: ConfigurationData, deadline: Int) -> store.Exchange {
  case fresh(deadline) {
    Ok(_) -> store.exchange_connection_data(c.journal, c.binding, None, None)
    Error(code) -> store.Exchange(Error(code), store.Unconfirmed)
  }
}

fn append(
  c: ConfigurationData,
  r: Option(store.Entry),
  p: store.Phase,
  digest: Option(String),
  deadline: Int,
) -> store.Exchange {
  let #(sequence, previous) = case r {
    None -> #(1, None)
    Some(r) -> #(r.sequence + 1, Some(r.sha256))
  }
  case fresh(deadline) {
    Ok(_) ->
      store.exchange_connection_data(
        c.journal,
        c.binding,
        Some(#(sequence, p, digest)),
        previous,
      )
    Error(code) -> store.Exchange(Error(code), store.Unconfirmed)
  }
}

fn saved_result(
  exchange: store.Exchange,
  fallback: Option(store.Entry),
  desired: Phase,
  effects: Int,
) -> ResultState {
  case store.successful(exchange.cleanup), exchange.reply {
    True, Ok(reply) -> Settled(desired, reply.record, exchange.cleanup, effects)
    _, _ ->
      Settled(
        case store.cleanup_known(exchange.cleanup) {
          True -> ReconcileOnly
          False -> CleanupUnconfirmed
        },
        fallback,
        exchange.cleanup,
        effects,
      )
  }
}

fn positive_ns(value: v.Value, k: String) -> Result(Int, String) {
  use raw <- result.try(store.text(value, k))
  use _ <- result.try(
    case string.byte_size(raw) > 0 && string.byte_size(raw) <= 19 {
      True -> Ok(Nil)
      False -> Error("NATIVE_INTEGER_BOUND")
    },
  )
  use n <- result.try(
    int.parse(raw) |> result.map_error(fn(_) { "NATIVE_INTEGER" }),
  )
  case n > 0 && n <= 9_223_372_036_854_775_807 && int.to_string(n) == raw {
    True -> Ok(n)
    False -> Error("NATIVE_INTEGER")
  }
}

fn receipt(c: ConfigurationData, raw: String) -> Result(String, String) {
  use _ <- result.try(case string.byte_size(raw) <= 32_768 {
    True -> Ok(Nil)
    False -> Error("NATIVE_REPLY_BOUND")
  })
  use r <- result.try(recovery_factual_reply.committed_receipt(raw))
  use _ <- result.try(
    closed(r, ["domain", "evidence_sha256", "capability_sha256", "factual"]),
  )
  use domain <- result.try(store.text(r, "domain"))
  use evidence <- result.try(store.text(r, "evidence_sha256"))
  use capability <- result.try(store.text(r, "capability_sha256"))
  use f <- result.try(v.get(r, "factual"))
  use _ <- result.try(
    closed(f, [
      "domain",
      "request",
      "request_sha256",
      "observed_ns",
      "precommit_ns",
      "after_snapshot",
      "new",
    ]),
  )
  use fdomain <- result.try(store.text(f, "domain"))
  use request_sha <- result.try(store.text(f, "request_sha256"))
  use after <- result.try(store.text(f, "after_snapshot"))
  use actual_request <- result.try(v.get(f, "request"))
  use expected_request <- result.try(
    json_guard.native_inspect(c.request, 6)
    |> result.map_error(fn(_) { "INVALID_JSON" }),
  )
  use observed <- result.try(positive_ns(f, "observed_ns"))
  use precommit <- result.try(positive_ns(f, "precommit_ns"))
  use duration <- result.try(positive_ns(expected_request, "duration"))
  use deadline <- result.try(positive_ns(expected_request, "deadline"))
  use old <- result.try(case v.get(expected_request, "old") {
    Ok(v.Array(xs)) -> Ok(xs)
    _ -> Error("OLD_SET")
  })
  use new <- result.try(case v.get(f, "new") {
    Ok(v.Array(xs)) -> Ok(xs)
    _ -> Error("NEW_SET")
  })
  use _ <- result.try(
    case
      domain == "uos.sa-plan.recovery-cap-receipt.v1"
      && store.sha(evidence)
      && capability == c.capability_sha256
      && fdomain == "uos.sa-plan.reclaim-receipt.v1"
      && request_sha == c.binding.request_sha256
      && actual_request == expected_request
      && store.sha(after)
      && observed <= precommit
      && precommit < deadline
      && precommit < observed + duration
      && list.length(old) == 3
      && list.length(new) == 3
    {
      True -> Ok(Nil)
      False -> Error("NATIVE_RECEIPT_BINDING")
    },
  )
  use _ <- result.try(
    list.try_each(list.zip(old, new), fn(pair) {
      let #(o, n) = pair
      use _ <- result.try(closed(n, ["task", "worker", "attempt", "lease"]))
      use lease <- result.try(positive_ns(n, "lease"))
      let attempts = case v.get(o, "attempt"), v.get(n, "attempt") {
        Ok(v.Integer(a)), Ok(v.Integer(b)) -> b == a + 1
        _, _ -> False
      }
      case
        v.get(o, "task") == v.get(n, "task")
        && v.get(o, "worker") == v.get(n, "worker")
        && attempts
        && lease == observed + duration
      {
        True -> Ok(Nil)
        False -> Error("NATIVE_NEW_TUPLE")
      }
    }),
  )
  Ok(files.digest(json.to_string(v.encode(r))))
}

fn after_effect(
  c: ConfigurationData,
  r: store.Entry,
  exchange: store.RawExchange,
  deadline: Int,
) -> ResultState {
  case store.cleanup_known(exchange.cleanup) {
    False -> Settled(CleanupUnconfirmed, Some(r), exchange.cleanup, 1)
    True ->
      case
        exchange.body |> result.try(fn(raw) { receipt(c, raw) }),
        store.successful(exchange.cleanup)
      {
        Ok(digest), True ->
          saved_result(
            append(c, Some(r), store.CommittedFact, Some(digest), deadline),
            Some(r),
            HistoricalFact,
            1,
          )
        _, _ ->
          saved_result(
            append(c, Some(r), store.Unknown, None, deadline),
            Some(r),
            ReconcileOnly,
            1,
          )
      }
  }
}

fn execute(c: ConfigurationData, a: Adapter, deadline: Int) -> ResultState {
  case live(a, BeforePending, False, deadline) {
    Error(_) -> Settled(Unavailable, None, store.Unconfirmed, 0)
    Ok(_) -> {
      let pending = append(c, None, store.Pending, None, deadline)
      case pending.reply, pending.cleanup {
        Ok(store.Reply("APPENDED", Some(r))), store.Reaped(0, _) -> {
          // Recheck after the blocking durable append. The last potentially
          // blocking quiescence callback precedes the fresh admission read.
          // This context exists ONLY after the first durable APPENDED ACK in
          // this exact flight. REPLAY/restart/uncertain-cleanup cannot obtain
          // it. No task worker has been spawned on this path yet. It is an
          // ownership/absence fact, never permission or a replaceable bool.
          case live(a, PendingCreatedByThisOwner, False, deadline) {
            Error(_) -> Settled(ReconcileOnly, Some(r), pending.cleanup, 0)
            Ok(_) ->
              case fresh(deadline) {
                Error(_) -> Settled(ReconcileOnly, Some(r), pending.cleanup, 0)
                Ok(_) -> after_effect(c, r, a.effect(c.commit_body), deadline)
              }
          }
        }
        Ok(reply), cleanup ->
          Settled(
            case store.cleanup_known(cleanup) {
              True -> ReconcileOnly
              False -> CleanupUnconfirmed
            },
            reply.record,
            cleanup,
            0,
          )
        Error(_), cleanup ->
          Settled(
            case store.cleanup_known(cleanup) {
              True -> ReconcileOnly
              False -> CleanupUnconfirmed
            },
            None,
            cleanup,
            0,
          )
      }
    }
  }
}

fn inspect(c: ConfigurationData, a: Adapter, deadline: Int) -> ResultState {
  case live(a, Reconciliation, True, deadline) {
    Error(_) -> Settled(Unavailable, None, store.Unconfirmed, 0)
    Ok(_) -> {
      let journal = latest(c, deadline)
      case journal.reply, store.successful(journal.cleanup) {
        Ok(store.Reply(_, Some(r))), True ->
          case live(a, Reconciliation, True, deadline) {
            Error(_) -> Settled(ReconcileOnly, Some(r), journal.cleanup, 0)
            Ok(_) -> {
              let observed = case fresh(deadline) {
                Ok(_) -> a.effect(c.inspect_body)
                Error(code) -> store.RawExchange(Error(code), store.Unconfirmed)
              }
              case
                store.cleanup_known(observed.cleanup),
                observed.body |> result.try(fn(raw) { receipt(c, raw) }),
                store.successful(observed.cleanup)
              {
                False, _, _ ->
                  Settled(CleanupUnconfirmed, Some(r), observed.cleanup, 0)
                True, Ok(digest), True ->
                  case
                    r.phase == store.CommittedFact
                    && r.receipt_sha256 == Some(digest)
                  {
                    True ->
                      Settled(HistoricalFact, Some(r), observed.cleanup, 0)
                    False ->
                      saved_result(
                        append(
                          c,
                          Some(r),
                          store.CommittedFact,
                          Some(digest),
                          deadline,
                        ),
                        Some(r),
                        HistoricalFact,
                        0,
                      )
                  }
                _, _, _ -> Settled(ReconcileOnly, Some(r), observed.cleanup, 0)
              }
            }
          }
        Ok(store.Reply(_, None)), True ->
          Settled(ReconcileOnly, None, journal.cleanup, 0)
        _, _ ->
          Settled(
            case store.cleanup_known(journal.cleanup) {
              True -> ReconcileOnly
              False -> CleanupUnconfirmed
            },
            None,
            journal.cleanup,
            0,
          )
      }
    }
  }
}

fn work(
  c: ConfigurationData,
  a: Adapter,
  w: Work,
  deadline: Int,
) -> ResultState {
  case w {
    Dispatch -> execute(c, a, deadline)
    Inspect -> inspect(c, a, deadline)
    Load ->
      case
        fresh(deadline)
        |> result.try(fn(_) { a.quiescence(Startup) })
        |> result.try(fn(_) { fresh(deadline) })
      {
        Error(_) -> Settled(Unavailable, None, store.Unconfirmed, 0)
        Ok(_) -> {
          let exchange = latest(c, deadline)
          case exchange.reply, store.successful(exchange.cleanup) {
            Ok(reply), True ->
              Settled(
                case reply.record {
                  None -> DataOnly
                  Some(_) -> ReconcileOnly
                },
                reply.record,
                exchange.cleanup,
                0,
              )
            _, _ ->
              Settled(
                case store.cleanup_known(exchange.cleanup) {
                  True -> ReconcileOnly
                  False -> CleanupUnconfirmed
                },
                None,
                exchange.cleanup,
                0,
              )
          }
        }
      }
  }
}

fn launch(
  s: State,
  w: Work,
  reply: Option(Subject(Result(Snapshot, String))),
) -> State {
  let sequence = s.sequence + 1
  let completion = s.completion
  let owner = process.self()
  // One immutable BEAM-monotonic deadline is captured BEFORE spawn and passed
  // through all callbacks and IO gates. No result/retry refreshes it. A strict
  // pre-call check does not eliminate OS scheduling/physical fsync latency.
  let deadline = monotonic_ms() + s.config.timeout_ms
  let pid =
    process.spawn(fn() {
      process.link(owner)
      process.send(
        completion,
        Completion(sequence, work(s.config, s.adapter, w, deadline)),
      )
    })
  let monitor = process.monitor(pid)
  let timer = process.send_after(s.self, s.config.timeout_ms, Timeout(sequence))
  State(
    ..s,
    flight: Some(Flight(sequence, pid, monitor, timer, deadline, reply, None)),
    sequence: sequence,
    revision: s.revision + 1,
    phase: Running,
  )
}

fn lose(s: State) -> actor.Next(State, Message) {
  case s.flight {
    None -> actor.stop()
    Some(f) -> {
      process.kill(f.pid)
      let _ = process.cancel_timer(f.timer)
      case f.reply {
        Some(reply) -> process.send(reply, Error("OWNER_LOST_OUTCOME_UNKNOWN"))
        None -> Nil
      }
      actor.continue(
        State(
          ..s,
          owner_lost: True,
          phase: CleanupUnconfirmed,
          cleanup: store.Unconfirmed,
          flight: Some(Flight(..f, reply: None, done: None)),
        ),
      )
    }
  }
}

fn handle(s: State, message: Message) -> actor.Next(State, Message) {
  case message {
    Get(reply) -> {
      process.send(reply, snapshot(s))
      actor.continue(s)
    }
    Commit(step, reply) ->
      case
        step.operation_id == s.config.binding.operation_id
        && step.revision == s.revision,
        s.flight,
        s.phase,
        s.durable
      {
        True, None, DataOnly, None ->
          actor.continue(launch(s, Dispatch, Some(reply)))
        _, _, _, _ -> {
          process.send(
            reply,
            Error("RECOVERY_CAS_SINGLE_FLIGHT_OR_RECONCILE_ONLY"),
          )
          actor.continue(s)
        }
      }
    Reconcile(reply) ->
      case s.flight, s.phase {
        None, CleanupUnconfirmed -> {
          process.send(reply, Error("RECOVERY_CLEANUP_UNCONFIRMED"))
          actor.continue(s)
        }
        None, _ -> actor.continue(launch(s, Inspect, Some(reply)))
        _, _ -> {
          process.send(reply, Error("RECOVERY_SINGLE_FLIGHT"))
          actor.continue(s)
        }
      }
    Returned(completion) ->
      case s.flight {
        Some(f) if f.sequence == completion.sequence && !s.owner_lost ->
          case monotonic_ms() < f.deadline {
            True ->
              actor.continue(
                State(..s, flight: Some(Flight(..f, done: Some(completion)))),
              )
            False -> {
              process.kill(f.pid)
              actor.continue(
                State(
                  ..s,
                  phase: CleanupUnconfirmed,
                  cleanup: store.Unconfirmed,
                  flight: Some(Flight(..f, done: None)),
                ),
              )
            }
          }
        _ -> actor.continue(s)
      }
    Timeout(sequence) ->
      case s.flight {
        Some(f) if f.sequence == sequence -> {
          process.kill(f.pid)
          actor.continue(
            State(
              ..s,
              phase: CleanupUnconfirmed,
              cleanup: store.Unconfirmed,
              flight: Some(Flight(..f, done: None)),
            ),
          )
        }
        _ -> actor.continue(s)
      }
    Down(process.ProcessDown(monitor, pid, _))
      if pid == s.parent && monitor == s.parent_monitor
    -> lose(s)
    Down(process.ProcessDown(monitor, pid, _)) ->
      case s.flight {
        Some(f) if f.pid == pid && f.monitor == monitor -> {
          let _ = process.cancel_timer(f.timer)
          case s.owner_lost, s.stop_reply {
            True, _ -> actor.stop()
            _, Some(reply) -> {
              process.send(
                reply,
                Error("STOPPED_RECONCILE_ONLY_CLEANUP_UNCONFIRMED"),
              )
              actor.stop()
            }
            _, _ -> {
              let next = case f.done {
                Some(Completion(_, Settled(phase, durable, cleanup, effects))) ->
                  State(
                    ..s,
                    phase: phase,
                    durable: durable,
                    cleanup: cleanup,
                    effects: s.effects + effects,
                    flight: None,
                    revision: s.revision + 1,
                  )
                None ->
                  State(
                    ..s,
                    phase: CleanupUnconfirmed,
                    cleanup: store.Unconfirmed,
                    flight: None,
                    revision: s.revision + 1,
                  )
              }
              case f.reply {
                Some(reply) -> process.send(reply, Ok(snapshot(next)))
                None -> Nil
              }
              actor.continue(next)
            }
          }
        }
        _ -> actor.continue(s)
      }
    Down(_) -> actor.continue(s)
    LinkedExit(process.ExitMessage(pid, _)) if pid == s.parent -> lose(s)
    LinkedExit(_) -> actor.continue(s)
    Stop(reply) ->
      case s.flight {
        None -> {
          process.send(reply, Ok(Nil))
          actor.stop()
        }
        Some(f) -> {
          process.kill(f.pid)
          let _ = process.cancel_timer(f.timer)
          case f.reply {
            Some(waiting) ->
              process.send(waiting, Error("OWNER_STOPPED_OUTCOME_UNKNOWN"))
            None -> Nil
          }
          actor.continue(
            State(
              ..s,
              stop_reply: Some(reply),
              phase: CleanupUnconfirmed,
              cleanup: store.Unconfirmed,
              flight: Some(Flight(..f, reply: None, done: None)),
            ),
          )
        }
      }
  }
}

fn start_internal(
  c: ConfigurationData,
  a: Adapter,
) -> actor.StartResult(Subject(Message)) {
  let parent = process.self()
  actor.new_with_initialiser(2000, fn(self) {
    process.trap_exits(True)
    let completion = process.new_subject()
    let pm = process.monitor(parent)
    let selector =
      process.new_selector()
      |> process.select(self)
      |> process.select_map(completion, Returned)
      |> process.select_monitors(Down)
      |> process.select_trapped_exits(LinkedExit)
    let s =
      State(
        c,
        a,
        self,
        completion,
        parent,
        pm,
        False,
        None,
        0,
        0,
        Starting,
        None,
        store.Unconfirmed,
        0,
        None,
      )
    Ok(
      actor.initialised(launch(s, Load, None))
      |> actor.selecting(selector)
      |> actor.returning(self),
    )
  })
  |> actor.on_message(handle)
  |> actor.start
}

/// No public boundary constructor or flag enables task dispatch. An actual
/// trusted production issuer/owner/worker integration is deliberately absent.
pub fn start(c: ConfigurationData) -> actor.StartResult(Subject(Message)) {
  start_internal(c, unavailable())
}

pub fn child_spec(
  c: ConfigurationData,
) -> supervision.ChildSpecification(Subject(Message)) {
  supervision.worker(fn() { start(c) })
}

fn wait(within: Int) -> Result(Nil, String) {
  case within > 0 && within <= 60_000 {
    True -> Ok(Nil)
    False -> Error("WAIT_BOUND")
  }
}

pub fn get(owner: Subject(Message), within: Int) -> Result(Snapshot, String) {
  use _ <- result.try(wait(within))
  let r = process.new_subject()
  process.send(owner, Get(r))
  process.receive(r, within) |> result.replace_error("OWNER_REPLY_TIMEOUT")
}

pub fn commit(
  owner: Subject(Message),
  step: Step,
  within: Int,
) -> Result(Snapshot, String) {
  use _ <- result.try(wait(within))
  let r = process.new_subject()
  process.send(owner, Commit(step, r))
  process.receive(r, within)
  |> result.replace_error("OWNER_REPLY_TIMEOUT")
  |> result.flatten
}

pub fn reconcile(
  owner: Subject(Message),
  within: Int,
) -> Result(Snapshot, String) {
  use _ <- result.try(wait(within))
  let r = process.new_subject()
  process.send(owner, Reconcile(r))
  process.receive(r, within)
  |> result.replace_error("OWNER_REPLY_TIMEOUT")
  |> result.flatten
}

pub fn stop(owner: Subject(Message), within: Int) -> Result(Nil, String) {
  use _ <- result.try(wait(within))
  let r = process.new_subject()
  process.send(owner, Stop(r))
  process.receive(r, within)
  |> result.replace_error("OWNER_REPLY_TIMEOUT")
  |> result.flatten
}
