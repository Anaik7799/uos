//// Development-only recovery candidate data. Supplied evidence is not
//// authenticated runtime observation, review approval, or effect permission.

import gleam/bit_array
import gleam/crypto
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub const plan = "uos/codex-handover-open-items-fractal-plan/20261031-1240"

pub type TaskState {
  Available
  Executing
  Completed
}

pub type TaskObservation {
  TaskObservation(
    task: String,
    state: TaskState,
    worker: Option(String),
    attempt: Int,
    lease_until_ns: Option(Int),
    blocked: Int,
    result_present: Bool,
    completed_at_ns: Option(Int),
  )
}

pub type Member {
  Member(
    task: String,
    worker: String,
    old_attempt: Int,
    old_lease_ns: Int,
    next_attempt: Int,
    lease_ms: Int,
  )
}

pub type ClaimedBindings {
  ClaimedBindings(
    snapshot: String,
    portfolio: String,
    selection: String,
    selection_proof: String,
    review: String,
    source: String,
    native_worker: String,
    guardian: String,
  )
}

pub type Window {
  Window(
    host: String,
    boot: String,
    clock_domain: String,
    created_utc_ms: Int,
    expires_utc_ms: Int,
    created_mono_ms: Int,
    expires_mono_ms: Int,
  )
}

pub type Proposal {
  Proposal(
    request_id: String,
    plan: String,
    issuer: String,
    issuer_session: String,
    reviewer: String,
    reviewer_session: String,
    bindings: ClaimedBindings,
    window: Window,
    members: List(Member),
  )
}

/// This is a fixture/read-model input, not a trusted collector constructor.
/// No value of this type can enable native I/O in the candidate ingress.
pub type SuppliedContext {
  SuppliedContext(
    host: String,
    boot: String,
    clock_domain: String,
    utc_ms: Int,
    mono_ms: Int,
    bindings: ClaimedBindings,
    assessment_actors: List(String),
    assessment_sessions: List(String),
    tasks: List(TaskObservation),
  )
}

pub type Rejection {
  InvalidIdentity
  InvalidDigest
  WrongPlan
  WrongSet
  WrongWorker
  InvalidCounter
  NotExpired
  SnapshotMismatch
  EvidenceMismatch
  WrongHostBoot
  WrongClockDomain
  InvalidWindow
  Expired
  FutureObservation
  ReviewerConflict
  ClockRegression
}

pub opaque type Candidate {
  Candidate(
    proposal: Proposal,
    digest: String,
    checked_utc_ms: Int,
    checked_mono_ms: Int,
  )
}

pub type Inspection {
  Inspection(
    request_id: String,
    candidate_digest: String,
    plan: String,
    member_count: Int,
    checked_utc_ms: Int,
    checked_mono_ms: Int,
  )
}

fn ensure(ok: Bool, reason: Rejection) -> Result(Nil, Rejection) {
  case ok {
    True -> Ok(Nil)
    False -> Error(reason)
  }
}

pub fn identifier(value: String) -> Bool {
  string.byte_size(value) > 0
  && string.byte_size(value) <= 160
  && list.all(string.to_graphemes(value), fn(c) {
    string.byte_size(c) == 1
    && string.contains(
      "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.:/-",
      c,
    )
  })
}

pub fn tagged_digest(value: String) -> Bool {
  string.starts_with(value, "sha256:")
  && string.byte_size(value) == 71
  && list.all(string.to_graphemes(string.drop_start(value, 7)), fn(c) {
    string.byte_size(c) == 1 && string.contains("0123456789abcdef", c)
  })
}

fn binding_values(b: ClaimedBindings) -> List(String) {
  [
    b.snapshot,
    b.portfolio,
    b.selection,
    b.selection_proof,
    b.review,
    b.source,
    b.native_worker,
    b.guardian,
  ]
}

fn valid_bindings(b: ClaimedBindings) -> Bool {
  list.all(binding_values(b), tagged_digest)
}

fn utc(value: Int) -> Bool {
  value > 0 && value <= 8_000_000_000_000
}

fn mono(value: Int) -> Bool {
  value >= -9_000_000_000_000_000 && value <= 9_000_000_000_000_000
}

fn ns(value: Int) -> Bool {
  value > 0 && value <= 9_000_000_000_000_000_000
}

fn expected_worker(task: String) -> Result(String, Rejection) {
  case task {
    "OI02B_ALL_AGENT_SYMBIOSIS_PREFLIGHT" ->
      Ok("codex-symbiosis-preflight-20261031")
    "OI02E_RELEASE_AUTHORITY_PREPARATION" ->
      Ok("codex-release-authority-20261031")
    "OI02_ATOMIC_11_TARGET_CAPSULE_CUTOVER" -> Ok("codex-hive-cutover-20261031")
    _ -> Error(WrongSet)
  }
}

fn task_ids() -> List(String) {
  [
    "OI02B_ALL_AGENT_SYMBIOSIS_PREFLIGHT",
    "OI02E_RELEASE_AUTHORITY_PREPARATION",
    "OI02_ATOMIC_11_TARGET_CAPSULE_CUTOVER",
  ]
}

fn sorted(values: List(String)) -> List(String) {
  list.sort(values, string.compare)
}

fn consistent_task(t: TaskObservation, now_ns: Int) -> Bool {
  identifier(t.task)
  && t.attempt >= 0
  && t.attempt <= 1_000_000
  && t.blocked >= 0
  && t.blocked <= 1000
  && case t.state {
    Available ->
      t.worker == None
      && t.lease_until_ns == None
      && !t.result_present
      && t.completed_at_ns == None
    Executing ->
      case t.worker, t.lease_until_ns {
        Some(w), Some(deadline) ->
          identifier(w)
          && t.attempt > 0
          && ns(deadline)
          && !t.result_present
          && t.completed_at_ns == None
        _, _ -> False
      }
    Completed ->
      case t.worker, t.completed_at_ns {
        Some(w), Some(done) ->
          identifier(w)
          && t.attempt > 0
          && t.lease_until_ns == None
          && t.result_present
          && done > 0
          && done <= now_ns
        _, _ -> False
      }
  }
}

fn expired_task(t: TaskObservation, now_ns: Int) -> Bool {
  case t.state, t.lease_until_ns {
    Executing, Some(deadline) -> deadline <= now_ns
    _, _ -> False
  }
}

fn validate_member(m: Member, c: SuppliedContext) -> Result(Nil, Rejection) {
  use worker <- result.try(expected_worker(m.task))
  use _ <- result.try(ensure(m.worker == worker, WrongWorker))
  use _ <- result.try(ensure(
    m.old_attempt > 0
      && m.old_attempt < 1_000_000
      && m.next_attempt == m.old_attempt + 1
      && ns(m.old_lease_ns)
      && m.lease_ms > 0
      && m.lease_ms <= 3_600_000,
    InvalidCounter,
  ))
  use t <- result.try(
    list.find(c.tasks, fn(t) { t.task == m.task })
    |> result.map_error(fn(_) { WrongSet }),
  )
  use _ <- result.try(ensure(
    t.worker == Some(m.worker)
      && t.attempt == m.old_attempt
      && t.lease_until_ns == Some(m.old_lease_ns)
      && t.state == Executing
      && t.blocked == 0
      && !t.result_present
      && t.completed_at_ns == None,
    SnapshotMismatch,
  ))
  ensure(m.old_lease_ns <= c.utc_ms * 1_000_000, NotExpired)
}

/// All arguments are supplied data. Success means a consistent development
/// candidate; there is deliberately no authenticated permit type or worker API.
pub fn validate(
  p: Proposal,
  c: SuppliedContext,
) -> Result(Candidate, Rejection) {
  use _ <- result.try(ensure(p.plan == plan, WrongPlan))
  use _ <- result.try(ensure(
    list.all(
      [
        p.request_id,
        p.issuer,
        p.issuer_session,
        p.reviewer,
        p.reviewer_session,
        c.host,
        c.boot,
        c.clock_domain,
      ],
      identifier,
    ),
    InvalidIdentity,
  ))
  use _ <- result.try(ensure(
    valid_bindings(p.bindings) && valid_bindings(c.bindings),
    InvalidDigest,
  ))
  use _ <- result.try(ensure(
    p.bindings.snapshot == c.bindings.snapshot,
    SnapshotMismatch,
  ))
  use _ <- result.try(ensure(p.bindings == c.bindings, EvidenceMismatch))
  use _ <- result.try(ensure(
    p.window.host == c.host && p.window.boot == c.boot,
    WrongHostBoot,
  ))
  use _ <- result.try(ensure(
    p.window.clock_domain == c.clock_domain,
    WrongClockDomain,
  ))
  let w = p.window
  let utc_span = w.expires_utc_ms - w.created_utc_ms
  let mono_span = w.expires_mono_ms - w.created_mono_ms
  use _ <- result.try(ensure(
    utc(c.utc_ms)
      && mono(c.mono_ms)
      && utc(w.created_utc_ms)
      && utc(w.expires_utc_ms)
      && mono(w.created_mono_ms)
      && mono(w.expires_mono_ms)
      && utc_span > 0
      && utc_span <= 900_000
      && mono_span == utc_span,
    InvalidWindow,
  ))
  use _ <- result.try(ensure(
    c.utc_ms >= w.created_utc_ms && c.mono_ms >= w.created_mono_ms,
    FutureObservation,
  ))
  use _ <- result.try(ensure(
    c.utc_ms < w.expires_utc_ms && c.mono_ms < w.expires_mono_ms,
    Expired,
  ))
  use _ <- result.try(ensure(
    c.tasks != []
      && list.length(c.tasks) <= 1000
      && list.length(list.unique(list.map(c.tasks, fn(t) { t.task })))
      == list.length(c.tasks)
      && list.all(c.tasks, fn(t) { consistent_task(t, c.utc_ms * 1_000_000) }),
    SnapshotMismatch,
  ))
  let declared = list.map(p.members, fn(m) { m.task })
  let expired =
    list.filter(c.tasks, fn(t) { expired_task(t, c.utc_ms * 1_000_000) })
    |> list.map(fn(t) { t.task })
  use _ <- result.try(ensure(
    sorted(declared) == task_ids() && sorted(expired) == task_ids(),
    WrongSet,
  ))
  use _ <- result.try(ensure(
    c.assessment_actors != []
      && list.length(c.assessment_actors) <= 1000
      && list.all(c.assessment_actors, identifier)
      && c.assessment_sessions != []
      && list.length(c.assessment_sessions) <= 1000
      && list.all(c.assessment_sessions, identifier)
      && p.reviewer != p.issuer
      && p.reviewer_session != p.issuer_session
      && !list.contains(c.assessment_actors, p.reviewer)
      && !list.contains(c.assessment_sessions, p.reviewer_session)
      && !list.any(c.tasks, fn(t) { t.worker == Some(p.reviewer) }),
    ReviewerConflict,
  ))
  use _ <- result.try(list.try_each(p.members, fn(m) { validate_member(m, c) }))
  Ok(Candidate(p, proposal_digest(p), c.utc_ms, c.mono_ms))
}

pub fn revalidate(
  candidate: Candidate,
  c: SuppliedContext,
) -> Result(Nil, Rejection) {
  use _ <- result.try(ensure(
    c.utc_ms >= candidate.checked_utc_ms
      && c.mono_ms >= candidate.checked_mono_ms,
    ClockRegression,
  ))
  validate(candidate.proposal, c) |> result.map(fn(_) { Nil })
}

/// Retain separate clock high-water values after a valid observation. The
/// immutable proposal, request identity, digest and original expiry never move.
pub fn advance(
  candidate: Candidate,
  c: SuppliedContext,
) -> Result(Candidate, Rejection) {
  use _ <- result.try(revalidate(candidate, c))
  Ok(
    Candidate(..candidate, checked_utc_ms: c.utc_ms, checked_mono_ms: c.mono_ms),
  )
}

pub fn inspect(candidate: Candidate) -> Inspection {
  Inspection(
    candidate.proposal.request_id,
    candidate.digest,
    candidate.proposal.plan,
    list.length(candidate.proposal.members),
    candidate.checked_utc_ms,
    candidate.checked_mono_ms,
  )
}

pub fn bindings_json(b: ClaimedBindings) -> json.Json {
  json.object([
    #("snapshot", json.string(b.snapshot)),
    #("portfolio", json.string(b.portfolio)),
    #("selection", json.string(b.selection)),
    #("selection_proof", json.string(b.selection_proof)),
    #("review", json.string(b.review)),
    #("source", json.string(b.source)),
    #("native_worker", json.string(b.native_worker)),
    #("guardian", json.string(b.guardian)),
  ])
}

pub fn window_json(w: Window) -> json.Json {
  json.object([
    #("host", json.string(w.host)),
    #("boot", json.string(w.boot)),
    #("clock_domain", json.string(w.clock_domain)),
    #("created_utc_ms", json.int(w.created_utc_ms)),
    #("expires_utc_ms", json.int(w.expires_utc_ms)),
    #("created_mono_ms", json.int(w.created_mono_ms)),
    #("expires_mono_ms", json.int(w.expires_mono_ms)),
  ])
}

pub fn member_json(m: Member) -> json.Json {
  json.object([
    #("task", json.string(m.task)),
    #("worker", json.string(m.worker)),
    #("old_attempt", json.int(m.old_attempt)),
    #("old_lease_ns", json.string(int.to_string(m.old_lease_ns))),
    #("next_attempt", json.int(m.next_attempt)),
    #("lease_ms", json.int(m.lease_ms)),
  ])
}

pub fn proposal_json(p: Proposal) -> json.Json {
  json.object([
    #("schema", json.string("uos.recovery-candidate.v1")),
    #("request_id", json.string(p.request_id)),
    #("plan", json.string(p.plan)),
    #("issuer", json.string(p.issuer)),
    #("issuer_session", json.string(p.issuer_session)),
    #("reviewer", json.string(p.reviewer)),
    #("reviewer_session", json.string(p.reviewer_session)),
    #("bindings", bindings_json(p.bindings)),
    #("window", window_json(p.window)),
    #(
      "members",
      json.array(
        list.sort(p.members, fn(a, b) { string.compare(a.task, b.task) }),
        member_json,
      ),
    ),
  ])
}

pub fn proposal_digest(p: Proposal) -> String {
  let text =
    "uos.recovery-candidate.digest.v1\n" <> json.to_string(proposal_json(p))
  "sha256:"
  <> {
    text
    |> bit_array.from_string
    |> crypto.hash(crypto.Sha256, _)
    |> bit_array.base16_encode
    |> string.lowercase
  }
}

pub fn rejection_code(r: Rejection) -> String {
  case r {
    InvalidIdentity -> "INVALID_IDENTITY"
    InvalidDigest -> "INVALID_DIGEST"
    WrongPlan -> "WRONG_PLAN"
    WrongSet -> "WRONG_EXPIRED_SET"
    WrongWorker -> "WRONG_WORKER"
    InvalidCounter -> "INVALID_COUNTER"
    NotExpired -> "LEASE_NOT_EXPIRED"
    SnapshotMismatch -> "SNAPSHOT_MISMATCH"
    EvidenceMismatch -> "EVIDENCE_MISMATCH"
    WrongHostBoot -> "HOST_BOOT_MISMATCH"
    WrongClockDomain -> "CLOCK_DOMAIN_MISMATCH"
    InvalidWindow -> "INVALID_WINDOW"
    Expired -> "EXPIRED"
    FutureObservation -> "FUTURE_OBSERVATION"
    ReviewerConflict -> "REVIEWER_CONFLICT"
    ClockRegression -> "CLOCK_REGRESSION"
  }
}
