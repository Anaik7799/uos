import cepaf_gleam/harness/recovery_model as r
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleeunit/should

pub fn digest() -> String {
  "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
}

pub fn bindings() -> r.ClaimedBindings {
  r.ClaimedBindings(
    digest(),
    digest(),
    digest(),
    digest(),
    digest(),
    digest(),
    digest(),
    digest(),
  )
}

pub fn members() -> List(r.Member) {
  [
    r.Member(
      "OI02B_ALL_AGENT_SYMBIOSIS_PREFLIGHT",
      "codex-symbiosis-preflight-20261031",
      2,
      90_000_000,
      3,
      60_000,
    ),
    r.Member(
      "OI02E_RELEASE_AUTHORITY_PREPARATION",
      "codex-release-authority-20261031",
      1,
      95_000_000,
      2,
      60_000,
    ),
    r.Member(
      "OI02_ATOMIC_11_TARGET_CAPSULE_CUTOVER",
      "codex-hive-cutover-20261031",
      1,
      100_000_000,
      2,
      60_000,
    ),
  ]
}

pub fn proposal() -> r.Proposal {
  r.Proposal(
    "fixture-request-1",
    r.plan,
    "fixture-issuer",
    "fixture-session",
    "fixture-peer",
    "fixture-peer-session",
    bindings(),
    r.Window("fixture-host", "fixture-boot", "fixture-vm", 90, 1000, -110, 800),
    members(),
  )
}

pub fn context() -> r.SuppliedContext {
  r.SuppliedContext(
    "fixture-host",
    "fixture-boot",
    "fixture-vm",
    100,
    -100,
    bindings(),
    ["fixture-issuer"],
    ["fixture-session"],
    list.map(members(), fn(m) {
      r.TaskObservation(
        m.task,
        r.Executing,
        Some(m.worker),
        m.old_attempt,
        Some(m.old_lease_ns),
        0,
        False,
        None,
      )
    }),
  )
}

pub fn complete_exact_set_produces_candidate_data_only_test() {
  r.validate(proposal(), context()) |> result.is_ok |> should.be_true()
}

pub fn omitting_expired_e_is_refused_test() {
  let p = proposal()
  r.validate(r.Proposal(..p, members: list.take(p.members, 2)), context())
  |> result.is_error
  |> should.be_true()
}

pub fn every_semantic_binding_is_checked_test() {
  let p = proposal()
  let c = context()
  let b = bindings()
  let other =
    "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  list.each(
    [
      r.ClaimedBindings(..b, snapshot: other),
      r.ClaimedBindings(..b, portfolio: other),
      r.ClaimedBindings(..b, selection: other),
      r.ClaimedBindings(..b, selection_proof: other),
      r.ClaimedBindings(..b, review: other),
      r.ClaimedBindings(..b, source: other),
      r.ClaimedBindings(..b, native_worker: other),
      r.ClaimedBindings(..b, guardian: other),
    ],
    fn(b) {
      r.validate(r.Proposal(..p, bindings: b), c)
      |> result.is_error
      |> should.be_true()
    },
  )
}

pub fn malformed_identity_digest_and_wrong_plan_refuse_test() {
  let p = proposal()
  let b = bindings()
  list.each(
    [
      r.Proposal(..p, request_id: "bad\u{0}id"),
      r.Proposal(..p, plan: "other-plan"),
      r.Proposal(..p, bindings: r.ClaimedBindings(..b, snapshot: "sha256:AAAA")),
    ],
    fn(p) { r.validate(p, context()) |> result.is_error |> should.be_true() },
  )
}

pub fn strict_clock_boundaries_and_domains_refuse_test() {
  let p = proposal()
  let w = p.window
  let c = context()
  list.each(
    [
      r.Window(..w, host: "other-host"),
      r.Window(..w, boot: "other-boot"),
      r.Window(..w, clock_domain: "other-vm"),
      r.Window(
        ..w,
        expires_utc_ms: c.utc_ms,
        expires_mono_ms: w.created_mono_ms + c.utc_ms - w.created_utc_ms,
      ),
      r.Window(
        ..w,
        expires_mono_ms: c.mono_ms,
        expires_utc_ms: w.created_utc_ms + c.mono_ms - w.created_mono_ms,
      ),
      r.Window(..w, created_utc_ms: 101, expires_utc_ms: 1011),
      r.Window(..w, expires_mono_ms: w.expires_mono_ms + 1),
      r.Window(..w, expires_utc_ms: 1_000_001, expires_mono_ms: 999_801),
    ],
    fn(w) {
      r.validate(r.Proposal(..p, window: w), c)
      |> result.is_error
      |> should.be_true()
    },
  )
}

pub fn exact_member_owner_attempt_lease_and_duration_checked_test() {
  let p = proposal()
  let assert Ok(first) = list.first(p.members)
  list.each(
    [
      r.Member(..first, worker: "someone-else"),
      r.Member(..first, old_attempt: 1, next_attempt: 2),
      r.Member(..first, next_attempt: 4),
      r.Member(..first, old_lease_ns: first.old_lease_ns - 1),
      r.Member(..first, lease_ms: 0),
      r.Member(..first, lease_ms: 3_600_001),
    ],
    fn(m) {
      r.validate(
        r.Proposal(..p, members: [m, ..list.drop(p.members, 1)]),
        context(),
      )
      |> result.is_error
      |> should.be_true()
    },
  )
}

pub fn duplicate_and_extra_expired_members_refuse_test() {
  let p = proposal()
  let c = context()
  let assert Ok(first) = list.first(p.members)
  r.validate(r.Proposal(..p, members: [first, ..p.members]), c)
  |> result.is_error
  |> should.be_true()
  let extra =
    r.TaskObservation(
      "unreviewed-expiry",
      r.Executing,
      Some("another-worker"),
      1,
      Some(90_000_000),
      0,
      False,
      None,
    )
  r.validate(p, r.SuppliedContext(..c, tasks: [extra, ..c.tasks]))
  |> result.is_error
  |> should.be_true()
}

pub fn renewed_lease_and_changed_metadata_refuse_test() {
  let c = context()
  let assert Ok(first) = list.first(c.tasks)
  list.each(
    [
      r.TaskObservation(..first, lease_until_ns: Some(101_000_000)),
      r.TaskObservation(..first, attempt: first.attempt + 1),
      r.TaskObservation(..first, worker: Some("another-worker")),
      r.TaskObservation(..first, blocked: 1),
      r.TaskObservation(..first, result_present: True),
      r.TaskObservation(..first, lease_until_ns: None),
    ],
    fn(t) {
      r.validate(
        proposal(),
        r.SuppliedContext(..c, tasks: [t, ..list.drop(c.tasks, 1)]),
      )
      |> result.is_error
      |> should.be_true()
    },
  )
}

pub fn reviewer_independence_includes_all_actors_and_sessions_test() {
  let p = proposal()
  let c = context()
  list.each(
    [
      r.SuppliedContext(..c, assessment_actors: [p.reviewer]),
      r.SuppliedContext(..c, assessment_sessions: [p.reviewer_session]),
    ],
    fn(c) { r.validate(p, c) |> result.is_error |> should.be_true() },
  )
  r.validate(r.Proposal(..p, reviewer: "codex-hive-cutover-20261031"), c)
  |> result.is_error
  |> should.be_true()
}

pub fn candidate_revalidation_cannot_refresh_expiry_or_regress_clocks_test() {
  let c = context()
  let assert Ok(candidate) = r.validate(proposal(), c)
  r.revalidate(candidate, c) |> should.equal(Ok(Nil))
  r.revalidate(candidate, r.SuppliedContext(..c, utc_ms: 99))
  |> should.equal(Error(r.ClockRegression))
  r.revalidate(candidate, r.SuppliedContext(..c, mono_ms: -101))
  |> should.equal(Error(r.ClockRegression))
  r.revalidate(candidate, r.SuppliedContext(..c, mono_ms: 800))
  |> should.equal(Error(r.Expired))
}

pub fn member_permutation_preserves_digest_but_semantics_change_it_test() {
  let p = proposal()
  r.proposal_digest(r.Proposal(..p, members: list.reverse(p.members)))
  |> should.equal(r.proposal_digest(p))
  {
    r.proposal_digest(r.Proposal(..p, request_id: "different-request"))
    == r.proposal_digest(p)
  }
  |> should.be_false()
}
