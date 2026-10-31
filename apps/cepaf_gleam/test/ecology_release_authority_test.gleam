//// Actual ephemeral signatures and pinned native SQLite/guardian fixtures.
//// Trusted synthetic boundary adapters are explicit; no production admission.

import cepaf_gleam/ecology/release_approval as approval
import cepaf_gleam/ecology/release_authority as authority
import cepaf_gleam/ecology/release_identity as identity
import cepaf_gleam/ecology/release_intent as intent
import cepaf_gleam/ecology/release_store as store
import cepaf_gleam/harness/telegram_store_transport as transport
import envoy
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/erlang/process
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{Some}
import gleam/result
import gleam/string
import gleeunit/should
import simplifile

@external(erlang, "telegram_approval_test_crypto", "public_key")
fn public_key(role: String) -> String

@external(erlang, "telegram_approval_test_crypto", "sign")
fn sign(role: String, payload: String) -> String

@external(erlang, "erlang", "suspend_process")
fn suspend(pid: process.Pid) -> Bool

@external(erlang, "erlang", "resume_process")
fn resume(pid: process.Pid) -> Bool

type QueueKey {
  MessageQueueLen
}

@external(erlang, "erlang", "process_info")
fn mailbox(pid: process.Pid, key: QueueKey) -> #(QueueKey, Int)

@external(erlang, "erlang", "put")
fn set_clock_flag(key: String, value: #(Int, Int)) -> Dynamic

@external(erlang, "erlang", "get")
fn clock_flag(key: String) -> Dynamic

const issuer = "https://nas-1.tail55d152.ts.net:4101/realms/uos"

const host = "nas-1.tail55d152.ts.net"

fn digest(c) {
  "sha256:" <> string.repeat(c, 64)
}

fn environment(k) {
  let assert Ok(v) = envoy.get(k)
  v
}

fn signers() {
  list.map([approval.Operator, approval.Codex, approval.Agy], fn(role) {
    let name = approval.role_name(role)
    approval.Signer(role, name <> "-subject", name <> "-key", public_key(name))
  })
}

fn jwks() {
  json.object([
    #(
      "keys",
      json.array(
        [
          json.object([
            #("kty", json.string("OKP")),
            #("crv", json.string("Ed25519")),
            #("kid", json.string("operator-key")),
            #("alg", json.string("EdDSA")),
            #("x", json.string(public_key("operator"))),
          ]),
        ],
        fn(x) { x },
      ),
    ),
  ])
  |> json.to_string
}

pub fn fixture(lifetime: Int) {
  let clock = authority.host_clock()
  let loaded = clock.utc_ms / 1000 * 1000
  let assert Ok(id_config) =
    identity.configure(
      issuer,
      "uos-release-control",
      jwks(),
      loaded,
      300_000,
      "uos-release-client",
      ["urn:uos:mfa"],
      lifetime,
    )
  let assert Ok(roster) =
    approval.new_roster(signers(), loaded, loaded + 120_000)
  let directory =
    "/home/an/NAS-setup/uos/var/harness/20261031-1334-codex-hive/release-authority-proof/native-fixtures/actor-"
    <> int.to_string(int.random(1_000_000_000))
  let assert Ok(_) = simplifile.create_directory(directory)
  let assert Ok(_) = simplifile.set_permissions_octal(directory, 0o700)
  let native =
    transport.reviewed_local_configuration(
      environment("UOS_RELEASE_TEST_GUARDIAN"),
      environment("UOS_RELEASE_TEST_GUARDIAN_SHA"),
      environment("UOS_RELEASE_TEST_WORKER"),
      environment("UOS_RELEASE_TEST_WORKER_SHA"),
      directory <> "/grants.sqlite3",
    )
  let assert Ok(request) =
    intent.new(intent.Proposal(
      intent.Digests(
        digest("a"),
        digest("b"),
        digest("c"),
        digest("d"),
        digest("e"),
        digest("f"),
        digest("1"),
        digest("2"),
        digest("3"),
        digest("4"),
      ),
      intent.Execution(
        "/home/an/NAS-setup/uos",
        "fixture-plan",
        "fixture-task",
        "fixture-worker",
        1,
      ),
      host,
      "boot-fixture",
      "vm-fixture",
      "runtime:fixture-only",
      1,
      "fixture-nonce",
      intent.Window(
        clock.utc_ms,
        clock.utc_ms + 60_000,
        clock.mono_ms,
        clock.mono_ms + 60_000,
      ),
    ))
  let receipts =
    list.map([approval.Operator, approval.Codex, approval.Agy], fn(role) {
      let name = approval.role_name(role)
      let body =
        json.object([
          #("version", json.string(intent.approval_purpose)),
          #("purpose", json.string(intent.approval_purpose)),
          #("role", json.string(name)),
          #("subject", json.string(name <> "-subject")),
          #("decision", json.string("approve")),
          #("intent_digest", json.string(intent.digest(request))),
          #("effect_id", json.string(intent.transaction_id(request))),
          #("iat_ms", json.int(clock.utc_ms)),
          #("nbf_ms", json.int(clock.utc_ms)),
          #("exp_ms", json.int(clock.utc_ms + 60_000)),
          #("roster_digest", json.string(approval.roster_digest(roster))),
        ])
        |> json.to_string
      approval.Receipt(role, sign(name, body))
    })
  let token =
    json.object([
      #("sub", json.string("operator-subject")),
      #("iss", json.string(issuer)),
      #("aud", json.string("uos-release-control")),
      #("iat", json.int(loaded / 1000)),
      #("nbf", json.int(loaded / 1000)),
      #("exp", json.int(loaded / 1000 + 120)),
      #(
        "realm_access",
        json.object([
          #("roles", json.array(["uos-release-client"], json.string)),
        ]),
      ),
      #("acr", json.string("urn:uos:mfa")),
    ])
    |> json.to_string
    |> sign("operator", _)
  let config =
    authority.Configuration(
      id_config,
      roster,
      native,
      ["operator-subject"],
      host,
      "boot-fixture",
      "vm-fixture",
      4000,
      authority.host_clock,
    )
  #(config, request, receipts, token, directory)
}

pub fn actual_crypto_sqlite_single_dispatch_then_revoke_test() {
  let #(config, request, receipts, token, directory) = fixture(30_000)
  let events = process.new_subject()
  let boundary =
    authority.Boundary(fn(_, _) { Ok(Nil) }, fn(handoff) {
      let event = authority.handoff_event(handoff)
      { event.event_index > 0 } |> should.be_true
      let assert Ok(_) =
        simplifile.write(directory <> "/effect", "one owned fixture effect")
      process.send(events, authority.handoff_step(handoff))
      Ok(Nil)
    })
  let assert Ok(owner) = authority.start(config, boundary)
  let assert Ok(issued) =
    authority.issue(owner.data, token, request, receipts, 3000)
  issued.phase |> should.equal(authority.GrantRecorded)
  authority.dispatch(
    owner.data,
    token,
    digest("9"),
    authority.Step(1, 0, store.Stage),
    1000,
  )
  |> result.is_error
  |> should.be_true
  authority.revoke(owner.data, token, digest("9"), store.OperatorRevoked, 1000)
  |> result.is_error
  |> should.be_true
  authority.get_bound(owner.data, digest("9"), 1000)
  |> result.is_error
  |> should.be_true
  let assert Ok(still_owned) =
    authority.get_bound(owner.data, intent.digest(request), 1000)
  still_owned.intent_digest |> should.equal(Some(intent.digest(request)))
  still_owned.revocation_requested |> should.be_false
  let step = authority.Step(1, 0, store.Stage)
  let assert Ok(done) =
    authority.dispatch(owner.data, token, intent.digest(request), step, 3000)
  done.dispatch_handoffs |> should.equal(1)
  process.receive(events, 1000) |> should.equal(Ok(step))
  authority.dispatch(owner.data, token, intent.digest(request), step, 3000)
  |> result.is_error
  |> should.be_true
  let assert Ok(revoked) =
    authority.revoke(
      owner.data,
      token,
      intent.digest(request),
      store.OperatorRevoked,
      3000,
    )
  revoked.phase |> should.equal(authority.Stopped)
  authority.dispatch(
    owner.data,
    token,
    intent.digest(request),
    authority.Step(1, 1, store.FenceReaders),
    1000,
  )
  |> result.is_error
  |> should.be_true
  simplifile.read(directory <> "/effect")
  |> should.equal(Ok("one owned fixture effect"))
}

fn await_veto(owner, tries: Int) {
  case tries {
    0 -> should.fail()
    _ -> {
      let assert Ok(view) = authority.get(owner, 1000)
      case view.revocation_requested {
        True -> Nil
        False -> {
          process.sleep(5)
          await_veto(owner, tries - 1)
        }
      }
    }
  }
}

pub fn revocation_during_blocking_fence_prevents_actual_handoff_test() {
  let #(config, request, receipts, token, _) = fixture(30_000)
  let entered = process.new_subject()
  let effects = process.new_subject()
  let boundary =
    authority.Boundary(
      fn(_, observation) {
        case observation {
          authority.Startup -> Ok(Nil)
          authority.BeforeDispatch(_) -> {
            let resume = process.new_subject()
            process.send(entered, resume)
            let assert Ok(_) = process.receive(resume, 3000)
            Ok(Nil)
          }
        }
      },
      fn(_) {
        process.send(effects, Nil)
        Ok(Nil)
      },
    )
  let assert Ok(owner) = authority.start(config, boundary)
  let assert Ok(_) = authority.issue(owner.data, token, request, receipts, 3000)
  let dispatch_done = process.new_subject()
  let _ =
    process.spawn(fn() {
      process.send(
        dispatch_done,
        authority.dispatch(
          owner.data,
          token,
          intent.digest(request),
          authority.Step(1, 0, store.Stage),
          4000,
        ),
      )
    })
  let assert Ok(resume) = process.receive(entered, 1000)
  let revoke_done = process.new_subject()
  let _ =
    process.spawn(fn() {
      process.send(
        revoke_done,
        authority.revoke(
          owner.data,
          token,
          intent.digest(request),
          store.OperatorRevoked,
          4000,
        ),
      )
    })
  await_veto(owner.data, 100)
  // Revoke persists through a separate ledger worker BEFORE the blocked live
  // observer is released. A single serial worker cannot satisfy this check.
  let assert Ok(Ok(revoked)) = process.receive(revoke_done, 4000)
  revoked.phase |> should.equal(authority.Stopped)
  process.send(resume, Nil)
  let assert Ok(_) = process.receive(dispatch_done, 1000)
  let assert Ok(view) = authority.get(owner.data, 1000)
  view.dispatch_handoffs |> should.equal(0)
  process.receive(effects, 20) |> result.is_error |> should.be_true
}

pub fn actual_expiry_after_last_blocking_observation_prevents_handoff_test() {
  let #(config, request, receipts, token, _) = fixture(1000)
  let entered = process.new_subject()
  let effects = process.new_subject()
  let boundary =
    authority.Boundary(
      fn(_, observation) {
        case observation {
          authority.Startup -> Ok(Nil)
          authority.BeforeDispatch(_) -> {
            let resume = process.new_subject()
            process.send(entered, resume)
            let assert Ok(_) = process.receive(resume, 3000)
            Ok(Nil)
          }
        }
      },
      fn(_) {
        process.send(effects, Nil)
        Ok(Nil)
      },
    )
  let assert Ok(owner) = authority.start(config, boundary)
  let assert Ok(_) = authority.issue(owner.data, token, request, receipts, 3000)
  let reply = process.new_subject()
  let _ =
    process.spawn(fn() {
      process.send(
        reply,
        authority.dispatch(
          owner.data,
          token,
          intent.digest(request),
          authority.Step(1, 0, store.Stage),
          4000,
        ),
      )
    })
  let assert Ok(resume) = process.receive(entered, 1000)
  process.sleep(1100)
  process.send(resume, Nil)
  let assert Ok(outcome) = process.receive(reply, 3000)
  outcome |> result.is_error |> should.be_true
  process.receive(effects, 20) |> result.is_error |> should.be_true
}

pub fn default_boundary_refuses_before_native_issue_test() {
  let #(config, request, receipts, token, directory) = fixture(30_000)
  let assert Ok(owner) =
    authority.start(config, authority.unavailable_boundary())
  authority.issue(owner.data, token, request, receipts, 3000)
  |> result.is_error
  |> should.be_true
  simplifile.read(directory <> "/grants.sqlite3")
  |> result.is_error
  |> should.be_true
}

pub fn owner_restart_cannot_resurrect_historical_issue_test() {
  let #(config, request, receipts, token, _) = fixture(30_000)
  let events = process.new_subject()
  let boundary =
    authority.Boundary(fn(_, _) { Ok(Nil) }, fn(_) {
      process.send(events, Nil)
      Ok(Nil)
    })
  let assert Ok(first) = authority.start(config, boundary)
  let assert Ok(_) = authority.issue(first.data, token, request, receipts, 3000)
  let _ = process.unlink(first.pid)
  process.kill(first.pid)
  let assert Ok(second) = authority.start(config, boundary)
  authority.issue(second.data, token, request, receipts, 3000)
  |> result.is_error
  |> should.be_true
  authority.dispatch(
    second.data,
    token,
    intent.digest(request),
    authority.Step(1, 0, store.Stage),
    1000,
  )
  |> result.is_error
  |> should.be_true
  process.receive(events, 20) |> result.is_error |> should.be_true
}

fn await_mailbox(pid, tries: Int) {
  case tries {
    0 -> should.fail()
    _ ->
      case mailbox(pid, MessageQueueLen).1 > 0 {
        True -> Nil
        False -> {
          process.sleep(1)
          await_mailbox(pid, tries - 1)
        }
      }
  }
}

pub fn overdue_return_before_timeout_message_cannot_dispatch_test() {
  let #(base_config, request, receipts, token, _) = fixture(30_000)
  let config = authority.Configuration(..base_config, job_timeout_ms: 1000)
  let entered = process.new_subject()
  let effects = process.new_subject()
  let boundary =
    authority.Boundary(
      fn(_, observation) {
        case observation {
          authority.Startup -> Ok(Nil)
          authority.BeforeDispatch(_) -> {
            let release = process.new_subject()
            process.send(entered, release)
            let assert Ok(_) = process.receive(release, 3000)
            Ok(Nil)
          }
        }
      },
      fn(_) {
        process.send(effects, Nil)
        Ok(Nil)
      },
    )
  let assert Ok(owner) = authority.start(config, boundary)
  let assert Ok(_) = authority.issue(owner.data, token, request, receipts, 3000)
  let reply = process.new_subject()
  let _ =
    process.spawn(fn() {
      process.send(
        reply,
        authority.dispatch(
          owner.data,
          token,
          intent.digest(request),
          authority.Step(1, 0, store.Stage),
          4000,
        ),
      )
    })
  let assert Ok(release) = process.receive(entered, 1000)
  suspend(owner.pid) |> should.be_true
  process.send(release, Nil)
  // The completion is queued while the owner is paused, before its timer is
  // due. Resume only after the absolute deadline, with signatures still valid.
  await_mailbox(owner.pid, 100)
  process.sleep(1100)
  resume(owner.pid) |> should.be_true
  let assert Ok(outcome) = process.receive(reply, 3000)
  outcome |> should.equal(Error("RELEASE_JOB_DEADLINE_EXPIRED"))
  let assert Ok(view) = authority.get(owner.data, 1000)
  view.dispatch_handoffs |> should.equal(0)
  process.receive(effects, 20) |> result.is_error |> should.be_true
}

pub fn worker_rechecks_identity_lower_clock_bound_before_dispatch_test() {
  let #(base_config, request, receipts, token, _) = fixture(30_000)
  let flag = "release-test-clock-rollback"
  let read_clock = fn() {
    let real = authority.host_clock()
    let decoder = {
      use at <- decode.then(decode.at([0], decode.int))
      use unused <- decode.then(decode.at([1], decode.int))
      decode.success(#(at, unused))
    }
    case decode.run(clock_flag(flag), decoder) {
      Ok(#(rolled_utc, _)) -> authority.Clock(rolled_utc, real.mono_ms)
      Error(_) -> real
    }
  }
  let config = authority.Configuration(..base_config, read_clock: read_clock)
  let effects = process.new_subject()
  let boundary =
    authority.Boundary(
      fn(i, observation) {
        case observation {
          authority.Startup -> Ok(Nil)
          authority.BeforeDispatch(_) -> {
            // Flag affects only this isolated effect worker's clock. Owner-side
            // fresh() still sees actual time. Intent's own lower bound still passes.
            let _ = set_clock_flag(flag, #(intent.created_utc_ms(i), 0))
            Ok(Nil)
          }
        }
      },
      fn(_) {
        process.send(effects, Nil)
        Ok(Nil)
      },
    )
  let assert Ok(owner) = authority.start(config, boundary)
  let assert Ok(_) = authority.issue(owner.data, token, request, receipts, 3000)
  process.sleep(10)
  authority.dispatch(
    owner.data,
    token,
    intent.digest(request),
    authority.Step(1, 0, store.Stage),
    3000,
  )
  |> result.is_error
  |> should.be_true
  process.receive(effects, 20) |> result.is_error |> should.be_true
}
