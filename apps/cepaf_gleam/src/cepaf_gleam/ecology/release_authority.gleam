//// Supervised release PREPARATION owner. Authentic identity and signed evidence
//// precede durable grant facts; a fresh consume ACK precedes a single dispatch
//// handoff. Historical rows/unknown ACKs never reconstruct a dispatch permit.
//// All blocking observation, native transport and actuation runs in the linked
//// dedicated worker. No production deployment/admission follows from starting
//// this component: trusted configuration and actual boundary adapters are
//// separate prerequisites. Revoke AFTER handoff cannot undo an existing effect.

import cepaf_gleam/ecology/release_approval as approval
import cepaf_gleam/ecology/release_identity as identity
import cepaf_gleam/ecology/release_intent as intent
import cepaf_gleam/ecology/release_store as store
import cepaf_gleam/harness/files
import cepaf_gleam/harness/telegram_store_transport as transport
import gleam/erlang/process.{type Pid, type Subject}
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/otp/supervision
import gleam/result
import gleam/string

pub type ClockUnit {
  Millisecond
}

@external(erlang, "erlang", "system_time")
fn utc(unit: ClockUnit) -> Int

@external(erlang, "erlang", "monotonic_time")
fn mono(unit: ClockUnit) -> Int

pub type Clock {
  Clock(utc_ms: Int, mono_ms: Int)
}

pub fn host_clock() -> Clock {
  Clock(utc(Millisecond), mono(Millisecond))
}

pub type Step {
  Step(epoch: Int, generation: Int, command: store.Command)
}

pub type Observation {
  Startup
  BeforeDispatch(step: Step)
}

/// Trusted adapter hooks, never network-provided booleans. Startup must prove
/// predecessor/native quiescence. BeforeDispatch must read actual task/risk/KM,
/// source, runtime lease and phase-appropriate reader/health facts. Defaults deny.
pub type Boundary {
  Boundary(
    observe: fn(intent.Intent, Observation) -> Result(Nil, String),
    dispatch: fn(Handoff) -> Result(Nil, String),
  )
}

pub fn unavailable_boundary() -> Boundary {
  Boundary(fn(_, _) { Error("ACTUAL_RELEASE_FENCES_UNAVAILABLE") }, fn(_) {
    Error("ACTUAL_RELEASE_DISPATCH_UNAVAILABLE")
  })
}

/// This value exists only during one owner-local worker handoff. It is not a
/// bearer grant or a reusable admission ticket. Adapter code must bind the exact
/// step and still recheck physical effect-time fences in its executor.
pub opaque type Handoff {
  Handoff(
    request: intent.Intent,
    step: Step,
    grant_id: String,
    event: store.EventIdentity,
    expires_utc_ms: Int,
    expires_mono_ms: Int,
    caller: identity.Identity,
    evidence: approval.VerifiedEvidence,
  )
}

pub fn handoff_intent(h: Handoff) -> intent.Intent {
  h.request
}

pub fn handoff_step(h: Handoff) -> Step {
  h.step
}

pub fn handoff_grant_id(h: Handoff) -> String {
  h.grant_id
}

pub fn handoff_event(h: Handoff) -> store.EventIdentity {
  h.event
}

pub fn handoff_expires_utc_ms(h: Handoff) -> Int {
  h.expires_utc_ms
}

pub fn handoff_expires_mono_ms(h: Handoff) -> Int {
  h.expires_mono_ms
}

fn handoff_window_valid_at(
  h: Handoff,
  host: String,
  boot: String,
  domain: String,
  now: Clock,
) -> Bool {
  intent.valid_at(h.request, host, boot, domain, now.utc_ms, now.mono_ms)
  && now.utc_ms < h.expires_utc_ms
  && now.mono_ms < h.expires_mono_ms
}

pub fn handoff_still_valid(
  h: Handoff,
  configuration: Configuration,
  now: Clock,
) -> Bool {
  handoff_window_valid_at(
    h,
    configuration.host,
    configuration.boot,
    configuration.clock_domain,
    now,
  )
  && identity.still_valid(
    configuration.identity,
    h.caller,
    configuration.host,
    configuration.boot,
    configuration.clock_domain,
    now.utc_ms,
    now.mono_ms,
  )
  && approval.still_valid(
    h.evidence,
    configuration.roster,
    h.request,
    configuration.host,
    configuration.boot,
    configuration.clock_domain,
    now.utc_ms,
    now.mono_ms,
  )
}

pub type Configuration {
  Configuration(
    identity: identity.Configuration,
    roster: approval.Roster,
    transport: transport.LocalConfiguration,
    allowed_subjects: List(String),
    host: String,
    boot: String,
    clock_domain: String,
    job_timeout_ms: Int,
    read_clock: fn() -> Clock,
  )
}

pub type Phase {
  NoGrant
  Preparing
  GrantRecorded
  Checking
  Dispatching
  Stopped
  Held(reason: String)
}

pub type Snapshot {
  Snapshot(
    phase: Phase,
    grant_id: Option(String),
    intent_digest: Option(String),
    generation: Int,
    dispatch_handoffs: Int,
    revocation_requested: Bool,
  )
}

type Session {
  Session(
    request: intent.Intent,
    evidence: approval.VerifiedEvidence,
    binding: store.Binding,
    caller: identity.Identity,
  )
}

type JobKind {
  StartupCheck
  IssueRecord
  ConsumeRecord(step: Step)
  LiveCheck(step: Step, fact: store.StepFact)
  DispatchHandoff(step: Step, fact: store.StepFact, deadline_mono_ms: Int)
  RevokeRecord
}

type Job {
  Job(
    sequence: Int,
    kind: JobKind,
    reply: Subject(Result(Snapshot, String)),
    timer: process.Timer,
    deadline_mono_ms: Int,
  )
}

type WorkerResult {
  StoreResult(store.FactResult)
  Observed(Result(Nil, String))
  Dispatched(Result(Nil, String))
}

type WorkerMessage {
  StoreJob(sequence: Int, request: store.Request, reply: Subject(Message))
  ObserveJob(
    sequence: Int,
    request: intent.Intent,
    observation: Observation,
    reply: Subject(Message),
  )
  DispatchJob(sequence: Int, handoff: Handoff, reply: Subject(Message))
}

pub opaque type Message {
  Get(Subject(Snapshot))
  GetBound(String, Subject(Result(Snapshot, String)))
  Issue(
    String,
    intent.Intent,
    List(approval.Receipt),
    Subject(Result(Snapshot, String)),
  )
  Dispatch(String, String, Step, Subject(Result(Snapshot, String)))
  Revoke(String, String, store.RevokeReason, Subject(Result(Snapshot, String)))
  Returned(Int, WorkerResult)
  Timeout(Int)
  Down(process.Down)
  LinkedExit(process.ExitMessage)
}

type WorkerState {
  WorkerState(
    client: Option(store.Client),
    boundary: Boundary,
    config: Configuration,
  )
}

type State {
  State(
    config: Configuration,
    boundary: Boundary,
    self: Subject(Message),
    parent: Pid,
    worker: Option(actor.Started(Subject(WorkerMessage))),
    effect_worker: Option(actor.Started(Subject(WorkerMessage))),
    session: Option(Session),
    job: Option(Job),
    sequence: Int,
    generation: Int,
    handoffs: Int,
    phase: Phase,
    revoke_pending: Option(
      #(store.RevokeReason, Subject(Result(Snapshot, String))),
    ),
    revocation_requested: Bool,
    owner_lost: Bool,
    revoke_job: Option(Job),
  )
}

fn snapshot(s: State) -> Snapshot {
  Snapshot(
    s.phase,
    option.map(s.session, fn(x) { x.binding.grant_id }),
    option.map(s.session, fn(x) { intent.digest(x.request) }),
    s.generation,
    s.handoffs,
    s.revocation_requested,
  )
}

fn tag(value: String) -> String {
  store.tag_digest(value) |> result.unwrap("INVALID_DIGEST")
}

fn digest(fields: List(json.Json)) -> String {
  json.preprocessed_array(fields) |> json.to_string |> files.digest |> tag
}

pub fn command_key(c: store.Command) -> String {
  case c {
    store.Stage -> "stage"
    store.FenceReaders -> "fence_readers"
    store.Replace(i) -> "replace:" <> int.to_string(i)
    store.VerifyCandidate -> "verify_candidate"
    store.Restore(i) -> "restore:" <> int.to_string(i)
    store.VerifyPrevious -> "verify_previous"
    store.ResumeReaders -> "resume_readers"
  }
}

pub fn step_digest(request: intent.Intent, step: Step) -> String {
  digest([
    json.string("uos.ecology.release.step.v1"),
    json.string(intent.digest(request)),
    json.int(step.epoch),
    json.int(step.generation),
    json.string(command_key(step.command)),
  ])
}

fn binding(
  request: intent.Intent,
  evidence: approval.VerifiedEvidence,
) -> store.Binding {
  let e = intent.execution(request)
  let owner =
    digest([
      json.string("uos.ecology.release.owner.v1"),
      json.string(e.workspace),
      json.string(e.plan),
      json.string(e.task),
      json.string(e.worker),
      json.int(e.attempt),
      json.string(intent.host(request)),
      json.string(intent.boot(request)),
      json.string(intent.clock_domain(request)),
      json.string(intent.runtime_resource(request)),
      json.int(intent.runtime_epoch(request)),
    ])
  let approved = tag(approval.approval_set_digest(evidence))
  let grant =
    digest([
      json.string("uos.ecology.release.grant.v1"),
      json.string(intent.digest(request)),
      json.string(approved),
      json.string(owner),
    ])
  store.Binding(
    grant,
    tag(intent.digest(request)),
    approved,
    owner,
    int.min(intent.expires_utc_ms(request), approval.expires_utc_ms(evidence)),
  )
}

fn request_id(s: State, operation: String, extra: String) -> String {
  digest([
    json.string("uos.ecology.release.request.v1"),
    json.string(
      option.map(s.session, fn(x) { x.binding.grant_id }) |> option.unwrap(""),
    ),
    json.string(operation),
    json.string(extra),
  ])
}

fn worker_handle(state: WorkerState, message: WorkerMessage) {
  case message {
    StoreJob(seq, request, reply) -> {
      case state.client {
        None -> {
          process.send(reply, Returned(seq, StoreResult(store.RequestBlocked)))
          actor.continue(state)
        }
        Some(client) -> {
          let t = store.request(client, request)
          process.send(reply, Returned(seq, StoreResult(t.result)))
          actor.continue(WorkerState(..state, client: Some(t.client)))
        }
      }
    }
    ObserveJob(seq, request, observation, reply) -> {
      let observed = state.boundary.observe(request, observation)
      process.send(reply, Returned(seq, Observed(observed)))
      actor.continue(state)
    }
    DispatchJob(seq, handoff, reply) -> {
      // A queued handoff can expire before its worker runs. Check the shorter
      // identity/approval bounds, not only the intent's longer window.
      let now = state.config.read_clock()
      let outcome = case handoff_still_valid(handoff, state.config, now) {
        True -> state.boundary.dispatch(handoff)
        False -> Error("RELEASE_HANDOFF_EXPIRED")
      }
      process.send(reply, Returned(seq, Dispatched(outcome)))
      actor.continue(state)
    }
  }
}

fn authenticated(s: State, token: String) -> Result(identity.Identity, String) {
  let now = s.config.read_clock()
  use who <- result.try(identity.authenticate(
    s.config.identity,
    token,
    s.config.host,
    s.config.boot,
    s.config.clock_domain,
    now.utc_ms,
    now.mono_ms,
  ))
  case list.contains(s.config.allowed_subjects, identity.subject(who)) {
    True -> Ok(who)
    False -> Error("RELEASE_CALLER_NOT_CONFIGURED")
  }
}

fn fresh(s: State) -> Bool {
  case s.session {
    None -> False
    Some(session) -> {
      let now = s.config.read_clock()
      identity.still_valid(
        s.config.identity,
        session.caller,
        s.config.host,
        s.config.boot,
        s.config.clock_domain,
        now.utc_ms,
        now.mono_ms,
      )
      && approval.still_valid(
        session.evidence,
        s.config.roster,
        session.request,
        s.config.host,
        s.config.boot,
        s.config.clock_domain,
        now.utc_ms,
        now.mono_ms,
      )
      && now.utc_ms < session.binding.expires_utc_ms
    }
  }
}

fn held(s: State, reason: String) -> State {
  case s.job {
    Some(job) -> {
      let _ = process.cancel_timer(job.timer)
      process.send(job.reply, Error(reason))
    }
    None -> Nil
  }
  case s.revoke_job {
    Some(job) -> {
      let _ = process.cancel_timer(job.timer)
      process.send(job.reply, Error(reason))
    }
    None -> Nil
  }
  State(..s, job: None, revoke_job: None, phase: Held(reason))
}

fn begin_job(
  s: State,
  kind: JobKind,
  reply: Subject(Result(Snapshot, String)),
) -> State {
  let seq = s.sequence + 1
  let timer = process.send_after(s.self, s.config.job_timeout_ms, Timeout(seq))
  let now = s.config.read_clock()
  State(
    ..s,
    sequence: seq,
    job: Some(Job(
      seq,
      kind,
      reply,
      timer,
      now.mono_ms + s.config.job_timeout_ms,
    )),
  )
}

fn enqueue(
  s: State,
  kind: JobKind,
  reply: Subject(Result(Snapshot, String)),
) -> State {
  let s = begin_job(s, kind, reply)
  let selected_worker = case kind {
    StartupCheck | LiveCheck(_, _) | DispatchHandoff(_, _, _) -> s.effect_worker
    _ -> s.worker
  }
  case selected_worker, s.session {
    Some(worker), Some(session) -> {
      let message = case kind {
        StartupCheck -> ObserveJob(s.sequence, session.request, Startup, s.self)
        IssueRecord ->
          StoreJob(s.sequence, store.Issue(request_id(s, "issue", "")), s.self)
        ConsumeRecord(step) ->
          StoreJob(
            s.sequence,
            store.Consume(
              request_id(s, "consume", step_digest(session.request, step)),
              step_digest(session.request, step),
              step.epoch,
              step.generation,
              step.command,
            ),
            s.self,
          )
        LiveCheck(step, _) ->
          ObserveJob(s.sequence, session.request, BeforeDispatch(step), s.self)
        DispatchHandoff(step, fact, deadline) ->
          DispatchJob(
            s.sequence,
            Handoff(
              session.request,
              step,
              session.binding.grant_id,
              fact.event,
              int.min(
                session.binding.expires_utc_ms,
                identity.expires_utc_ms(session.caller),
              ),
              int.min(
                deadline,
                int.min(
                  approval.expires_mono_ms(session.evidence),
                  identity.expires_mono_ms(session.caller),
                ),
              ),
              session.caller,
              session.evidence,
            ),
            s.self,
          )
        RevokeRecord -> {
          let reason =
            option.map(s.revoke_pending, fn(x) { x.0 })
            |> option.unwrap(store.Containment)
          StoreJob(
            s.sequence,
            store.Revoke(request_id(s, "revoke", "permanent"), reason),
            s.self,
          )
        }
      }
      process.send(worker.data, message)
      s
    }
    _, _ -> held(s, "RELEASE_OWNER_UNAVAILABLE")
  }
}

fn finish(s: State, job: Job, phase: Phase) -> State {
  let _ = process.cancel_timer(job.timer)
  let s = State(..s, job: None, phase: phase)
  process.send(job.reply, Ok(snapshot(s)))
  s
}

fn schedule_revoke(s: State) -> State {
  let ledger_busy = case s.job {
    Some(Job(_, IssueRecord, _, _, _))
    | Some(Job(_, ConsumeRecord(_), _, _, _)) -> True
    _ -> False
  }
  case s.revoke_pending, s.revoke_job, s.worker, ledger_busy {
    Some(#(reason, reply)), None, Some(worker), False -> {
      let seq = s.sequence + 1
      let timer =
        process.send_after(s.self, s.config.job_timeout_ms, Timeout(seq))
      let deadline = s.config.read_clock().mono_ms + s.config.job_timeout_ms
      process.send(
        worker.data,
        StoreJob(
          seq,
          store.Revoke(request_id(s, "revoke", "permanent"), reason),
          s.self,
        ),
      )
      State(
        ..s,
        sequence: seq,
        revoke_job: Some(Job(seq, RevokeRecord, reply, timer, deadline)),
      )
    }
    _, _, _, _ -> s
  }
}

fn returned(s: State, seq: Int, value: WorkerResult) -> State {
  case s.revoke_job {
    Some(job) if job.sequence == seq -> {
      let _ = process.cancel_timer(job.timer)
      case s.config.read_clock().mono_ms < job.deadline_mono_ms, value {
        True, StoreResult(store.Revoked(_, _))
        | True, StoreResult(store.AlreadyRevoked(_, _))
        -> {
          let next =
            State(..s, revoke_job: None, revoke_pending: None, phase: Stopped)
          process.send(job.reply, Ok(snapshot(next)))
          next
        }
        _, _ -> held(s, "REVOKE_PERSISTENCE_UNKNOWN")
      }
    }
    _ -> returned_primary(s, seq, value)
  }
}

fn returned_primary(s: State, seq: Int, value: WorkerResult) -> State {
  case s.job {
    None -> s
    Some(job) if job.sequence != seq -> s
    Some(job) -> {
      let _ = process.cancel_timer(job.timer)
      let cleared = State(..s, job: None)
      case s.config.read_clock().mono_ms < job.deadline_mono_ms {
        False -> {
          stop_worker(s)
          held(s, "RELEASE_JOB_DEADLINE_EXPIRED")
        }
        True -> returned_before_deadline(s, cleared, job, value)
      }
    }
  }
}

fn returned_before_deadline(
  s: State,
  cleared: State,
  job: Job,
  value: WorkerResult,
) -> State {
  case s.revocation_requested, job.kind {
    True, RevokeRecord -> {
      case value {
        StoreResult(store.Revoked(_, _))
        | StoreResult(store.AlreadyRevoked(_, _)) ->
          State(..finish(cleared, job, Stopped), revoke_pending: None)
        _ ->
          held(State(..cleared, job: Some(job)), "REVOKE_PERSISTENCE_UNKNOWN")
      }
    }
    True, _ -> {
      let cancelled = finish(cleared, job, Stopped)
      schedule_revoke(cancelled)
    }
    False, _ -> {
      case fresh(cleared), job.kind, value {
        True, StartupCheck, Observed(Ok(_)) ->
          enqueue(cleared, IssueRecord, job.reply)
        // A fresh owner must not resurrect an already-issued intent after
        // a crash or unconfirmed revocation. Historical rows are facts.
        True, IssueRecord, StoreResult(store.Issued(grant, _)) ->
          case grant.revocation == None && !grant.expired {
            True -> finish(cleared, job, GrantRecorded)
            False -> held(State(..cleared, job: Some(job)), "GRANT_NOT_CURRENT")
          }
        True, ConsumeRecord(step), StoreResult(store.Consumed(grant, fact, _))
        ->
          case grant.revocation == None && !grant.expired {
            True -> enqueue(cleared, LiveCheck(step, fact), job.reply)
            False -> held(State(..cleared, job: Some(job)), "GRANT_NOT_CURRENT")
          }
        True, LiveCheck(step, fact), Observed(Ok(_)) -> {
          // Owner-local handoff linearization. Revoke accepted after this
          // send cannot retroactively undo the queued/executing operation.
          let next =
            State(
              ..cleared,
              generation: cleared.generation + 1,
              handoffs: cleared.handoffs + 1,
              phase: Dispatching,
            )
          enqueue(
            next,
            DispatchHandoff(step, fact, job.deadline_mono_ms),
            job.reply,
          )
        }
        True, DispatchHandoff(_, _, _), Dispatched(Ok(_)) ->
          finish(cleared, job, GrantRecorded)
        _, _, _ ->
          held(
            State(..cleared, job: Some(job)),
            "RELEASE_STEP_UNCERTAIN_OR_EXPIRED",
          )
      }
    }
  }
}

fn stop_worker(s: State) -> Nil {
  case s.worker {
    Some(w) -> process.kill(w.pid)
    None -> Nil
  }
  case s.effect_worker {
    Some(w) -> process.kill(w.pid)
    None -> Nil
  }
}

fn handle(s: State, message: Message) {
  case message {
    Get(reply) -> {
      process.send(reply, snapshot(s))
      actor.continue(s)
    }
    GetBound(expected, reply) -> {
      let matches = case s.session {
        None -> True
        Some(session) -> expected == intent.digest(session.request)
      }
      process.send(reply, case matches {
        True -> Ok(snapshot(s))
        False -> Error("RELEASE_INTENT_BINDING_MISMATCH")
      })
      actor.continue(s)
    }
    Issue(token, request, receipts, reply) -> {
      case s.session, s.job, authenticated(s, token) {
        None, None, Ok(caller) -> {
          let now = s.config.read_clock()
          case
            approval.verify(
              s.config.roster,
              request,
              s.config.host,
              s.config.boot,
              s.config.clock_domain,
              now.utc_ms,
              now.mono_ms,
              receipts,
            )
          {
            Error(_) -> {
              process.send(reply, Error("RELEASE_APPROVAL_REFUSED"))
              actor.continue(s)
            }
            Ok(evidence) -> {
              let bound = binding(request, evidence)
              case store.new_client(s.config.transport, bound) {
                Error(_) -> {
                  process.send(reply, Error("RELEASE_STORE_CONFIG_INVALID"))
                  actor.continue(s)
                }
                Ok(client) -> {
                  case
                    actor.new(WorkerState(Some(client), s.boundary, s.config))
                    |> actor.on_message(worker_handle)
                    |> actor.start
                  {
                    Error(_) -> {
                      process.send(reply, Error("RELEASE_STORE_START_FAILED"))
                      actor.continue(s)
                    }
                    Ok(worker) -> {
                      let _ = process.monitor(worker.pid)
                      case
                        actor.new(WorkerState(None, s.boundary, s.config))
                        |> actor.on_message(worker_handle)
                        |> actor.start
                      {
                        Error(_) -> {
                          process.kill(worker.pid)
                          process.send(
                            reply,
                            Error("RELEASE_EFFECT_WORKER_START_FAILED"),
                          )
                          actor.continue(
                            State(
                              ..s,
                              phase: Held("RELEASE_START_CLEANUP_UNKNOWN"),
                            ),
                          )
                        }
                        Ok(effect_worker) -> {
                          let _ = process.monitor(effect_worker.pid)
                          let next =
                            State(
                              ..s,
                              worker: Some(worker),
                              effect_worker: Some(effect_worker),
                              session: Some(Session(
                                request,
                                evidence,
                                bound,
                                caller,
                              )),
                              phase: Preparing,
                            )
                          actor.continue(enqueue(next, StartupCheck, reply))
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
        _, _, _ -> {
          process.send(reply, Error("RELEASE_ISSUE_REFUSED"))
          actor.continue(s)
        }
      }
    }
    Dispatch(token, expected, step, reply) -> {
      case s.phase, s.job, s.session, authenticated(s, token) {
        GrantRecorded, None, Some(session), Ok(caller)
          if !s.revocation_requested
        -> {
          case
            expected == intent.digest(session.request)
            && step.epoch == intent.runtime_epoch(session.request)
            && step.generation == s.generation
          {
            False -> {
              process.send(reply, Error("RELEASE_STEP_BINDING_MISMATCH"))
              actor.continue(s)
            }
            True -> {
              let next =
                State(
                  ..s,
                  session: Some(Session(..session, caller: caller)),
                  phase: Checking,
                )
              case fresh(next) {
                True ->
                  actor.continue(enqueue(next, ConsumeRecord(step), reply))
                False -> {
                  process.send(reply, Error("RELEASE_EVIDENCE_EXPIRED"))
                  actor.continue(next)
                }
              }
            }
          }
        }
        _, _, _, _ -> {
          process.send(reply, Error("RELEASE_DISPATCH_REFUSED"))
          actor.continue(s)
        }
      }
    }
    Revoke(token, expected, reason, reply) -> {
      case s.session, authenticated(s, token), s.revocation_requested {
        Some(session), Ok(caller), False -> {
          case expected == intent.digest(session.request) {
            False -> {
              process.send(reply, Error("RELEASE_INTENT_BINDING_MISMATCH"))
              actor.continue(s)
            }
            True -> {
              let next =
                State(
                  ..s,
                  session: Some(Session(..session, caller: caller)),
                  revocation_requested: True,
                  revoke_pending: Some(#(reason, reply)),
                  phase: Stopped,
                )
              actor.continue(schedule_revoke(next))
            }
          }
        }
        _, _, _ -> {
          process.send(reply, Error("RELEASE_REVOKE_REFUSED"))
          actor.continue(s)
        }
      }
    }
    Returned(seq, value) -> actor.continue(returned(s, seq, value))
    Timeout(seq) ->
      case s.job, s.revoke_job {
        Some(job), _ if job.sequence == seq -> {
          stop_worker(s)
          actor.continue(held(s, "RELEASE_WORKER_TIMEOUT_UNKNOWN"))
        }
        _, Some(job) if job.sequence == seq -> {
          stop_worker(s)
          actor.continue(held(s, "RELEASE_REVOKE_TIMEOUT_UNKNOWN"))
        }
        _, _ -> actor.continue(s)
      }
    Down(process.ProcessDown(_, pid, _)) -> {
      case pid == s.parent {
        True -> {
          stop_worker(s)
          actor.stop()
        }
        False ->
          case s.worker, s.effect_worker {
            Some(worker), _ if worker.pid == pid ->
              actor.continue(held(s, "RELEASE_WORKER_LOST_UNKNOWN"))
            _, Some(worker) if worker.pid == pid ->
              actor.continue(held(s, "RELEASE_EFFECT_WORKER_LOST_UNKNOWN"))
            _, _ -> actor.continue(s)
          }
      }
    }
    LinkedExit(process.ExitMessage(pid, _)) -> {
      case pid == s.parent {
        True -> {
          stop_worker(s)
          actor.stop()
        }
        False ->
          case s.worker, s.effect_worker {
            Some(worker), _ if worker.pid == pid ->
              actor.continue(held(s, "RELEASE_WORKER_LOST_UNKNOWN"))
            _, Some(worker) if worker.pid == pid ->
              actor.continue(held(s, "RELEASE_EFFECT_WORKER_LOST_UNKNOWN"))
            _, _ -> actor.continue(s)
          }
      }
    }
    Down(_) -> actor.continue(s)
  }
}

pub fn start(
  config: Configuration,
  boundary: Boundary,
) -> actor.StartResult(Subject(Message)) {
  let parent = process.self()
  actor.new_with_initialiser(2000, fn(self) {
    process.trap_exits(True)
    let _ = process.monitor(parent)
    use _ <- result.try(
      case
        config.job_timeout_ms >= 1000
        && config.job_timeout_ms <= 60_000
        && config.allowed_subjects != []
        && list.length(list.take(config.allowed_subjects, 17)) <= 16
        && list.all(config.allowed_subjects, fn(x) {
          string.byte_size(x) > 0 && string.byte_size(x) <= 128
        })
      {
        True -> Ok(Nil)
        False -> Error("RELEASE_OWNER_CONFIGURATION_INVALID")
      },
    )
    let selector =
      process.new_selector()
      |> process.select(self)
      |> process.select_monitors(Down)
      |> process.select_trapped_exits(LinkedExit)
    let state =
      State(
        config,
        boundary,
        self,
        parent,
        None,
        None,
        None,
        None,
        0,
        0,
        0,
        NoGrant,
        None,
        False,
        False,
        None,
      )
    Ok(
      actor.initialised(state)
      |> actor.selecting(selector)
      |> actor.returning(self),
    )
  })
  |> actor.on_message(handle)
  |> actor.start
}

pub fn child_spec(
  config: Configuration,
  boundary: Boundary,
) -> supervision.ChildSpecification(Subject(Message)) {
  supervision.worker(fn() { start(config, boundary) })
}

fn call(
  owner: Subject(Message),
  build: fn(Subject(Result(Snapshot, String))) -> Message,
  within: Int,
) -> Result(Snapshot, String) {
  case within > 0 && within <= 60_000 {
    False -> Error("RELEASE_REPLY_WAIT_INVALID")
    True -> {
      let reply = process.new_subject()
      process.send(owner, build(reply))
      process.receive(reply, within)
      |> result.replace_error("RELEASE_REPLY_TIMEOUT_UNKNOWN")
      |> result.flatten
    }
  }
}

pub fn issue(
  owner: Subject(Message),
  token: String,
  request: intent.Intent,
  receipts: List(approval.Receipt),
  within: Int,
) -> Result(Snapshot, String) {
  call(owner, fn(reply) { Issue(token, request, receipts, reply) }, within)
}

pub fn dispatch(
  owner: Subject(Message),
  token: String,
  expected_intent_digest: String,
  step: Step,
  within: Int,
) -> Result(Snapshot, String) {
  call(
    owner,
    fn(reply) { Dispatch(token, expected_intent_digest, step, reply) },
    within,
  )
}

pub fn revoke(
  owner: Subject(Message),
  token: String,
  expected_intent_digest: String,
  reason: store.RevokeReason,
  within: Int,
) -> Result(Snapshot, String) {
  call(
    owner,
    fn(reply) { Revoke(token, expected_intent_digest, reason, reply) },
    within,
  )
}

pub fn get_bound(
  owner: Subject(Message),
  expected_intent_digest: String,
  within: Int,
) -> Result(Snapshot, String) {
  call(owner, fn(reply) { GetBound(expected_intent_digest, reply) }, within)
}

pub fn get(owner: Subject(Message), within: Int) -> Result(Snapshot, String) {
  case within > 0 && within <= 60_000 {
    False -> Error("RELEASE_REPLY_WAIT_INVALID")
    True -> {
      let reply = process.new_subject()
      process.send(owner, Get(reply))
      process.receive(reply, within)
      |> result.replace_error("RELEASE_OWNER_UNAVAILABLE")
    }
  }
}
