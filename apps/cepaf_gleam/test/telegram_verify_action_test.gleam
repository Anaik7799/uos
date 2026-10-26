//// Laws for the approved /verify action: kind is signature-bound, a
//// cancellation approval never prepares a verification, the record round
//// trips byte-exactly, and readiness expires with the approval.

import cepaf_gleam/harness/telegram_action_intent as action
import cepaf_gleam/harness/telegram_approval as approval
import cepaf_gleam/harness/telegram_cancellation as cancel
import cepaf_gleam/harness/telegram_cancellation_record as record
import cepaf_gleam/harness/telegram_verify_action as verify_action
import cepaf_gleam/harness/telegram_verify_contract as v
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import gleeunit/should

pub const host = "nas-1.tail55d152.ts.net"

pub const boot = "boot-1"

pub const now = 1_030_000

pub const boot_now = 50_000

pub const worker = "verify-worker"

pub const lease_until_ns = 2_000_000_000_000

@external(erlang, "telegram_approval_test_crypto", "public_key")
fn public_key(role: String) -> String

@external(erlang, "telegram_approval_test_crypto", "sign")
fn sign(role: String, payload: String) -> String

pub fn binding() -> action.Binding {
  action.Binding(
    7,
    -11,
    13,
    19,
    "uos/example",
    "TASK",
    "operator",
    6,
    9,
    string.repeat("a", 64),
    host,
    boot,
    action.Execution("mapping-1", "lease-1", 3, string.repeat("d", 64)),
  )
}

pub fn verify_binding() -> v.Binding {
  v.Binding(
    "bot7/inbox19",
    "telegram/verify/" <> string.repeat("1", 64),
    1,
    string.repeat("e", 64),
    string.repeat("c", 40),
    string.repeat("f", 64),
  )
}

pub fn window() -> action.Window {
  action.Window(1_000_000, 20_000, 1_060_000, 80_000)
}

pub fn verify_intent() -> action.Intent {
  let assert Ok(value) =
    action.new_kind(
      action.VerifyProfile,
      binding(),
      verify_action.target_for(
      "uos/example",
      verify_binding(),
      worker,
      lease_until_ns,
    ),
      window(),
      "Operator requested verification of telegram-core",
      string.repeat("b", 64),
    )
  value
}

pub fn cancel_intent() -> action.Intent {
  let assert Ok(value) =
    action.new(
      binding(),
      verify_action.target_for(
      "uos/example",
      verify_binding(),
      worker,
      lease_until_ns,
    ),
      window(),
      "Operator requested verification of telegram-core",
      string.repeat("b", 64),
    )
  value
}

fn signer(role) {
  let name = approval.role_name(role)
  approval.Signer(role, name <> "-subject", name <> "-key", public_key(name))
}

pub fn roster() -> approval.Roster {
  let assert Ok(value) =
    approval.new_roster(
      list.map(
        [approval.Codex, approval.Agy, approval.Claude, approval.Operator],
        signer,
      ),
      900_000,
      1_200_000,
    )
  value
}

/// Receipts over `intent` whose signed purpose is `purpose`.
pub fn receipts(
  intent: action.Intent,
  purpose: String,
  policy: approval.Roster,
) -> List(approval.Receipt) {
  list.map([approval.Codex, approval.Agy, approval.Operator], fn(role) {
    let name = approval.role_name(role)
    let payload =
      json.object([
        #("version", json.string("uos.telegram.approval.v1")),
        #("purpose", json.string(purpose)),
        #("role", json.string(name)),
        #("subject", json.string(name <> "-subject")),
        #("decision", json.string("approve")),
        #("intent_digest", json.string(action.digest(intent))),
        #("effect_id", json.string(action.effect_id(intent))),
        #("iat_ms", json.int(1_000_000)),
        #("nbf_ms", json.int(1_000_000)),
        #("exp_ms", json.int(1_060_000)),
        #("roster_digest", json.string(approval.roster_digest(policy))),
      ])
      |> json.to_string
    approval.Receipt(role, sign(name, payload))
  })
}

pub fn observed() -> cancel.Observation {
  cancel.Observation(host, boot, now, boot_now)
}

pub fn evidence(intent: action.Intent, purpose: String) -> approval.Verified {
  let policy = roster()
  let assert Ok(value) =
    approval.verify(
      policy,
      intent,
      host,
      boot,
      now,
      boot_now,
      receipts(intent, purpose, policy),
    )
  value
}

pub fn prepared() -> verify_action.Prepared {
  let assert Ok(value) =
    verify_action.prepare(
      verify_intent(),
      evidence(verify_intent(), "verify_profile"),
      roster(),
      binding(),
      verify_binding(),
      observed(),
    )
  value
}

pub fn kind_and_purpose_are_signature_bound_test() {
  action.kind(verify_intent()) |> should.equal(action.VerifyProfile)
  action.purpose(verify_intent()) |> should.equal("verify_profile")
  action.kind(cancel_intent()) |> should.equal(action.CancelJobLease)
  // Same binding, target, window, reason and nonce: different digests and
  // different logical effects, because the kind is inside both.
  action.digest(verify_intent())
  |> should.not_equal(action.digest(cancel_intent()))
  action.effect_id(verify_intent())
  |> should.not_equal(action.effect_id(cancel_intent()))
  action.command_args(verify_intent())
  |> string.starts_with("verify_profile uos/example/telegram/verify/")
  |> should.be_true
}

pub fn receipts_with_the_other_purpose_do_not_verify_test() {
  let policy = roster()
  // Cancellation-purpose receipts over a verify intent are refused, and
  // verify-purpose receipts over a cancellation intent are refused.
  approval.verify(
    policy,
    verify_intent(),
    host,
    boot,
    now,
    boot_now,
    receipts(verify_intent(), "cancel_job_lease", policy),
  )
  |> should.equal(Error("receipt_claims_mismatch"))
  approval.verify(
    policy,
    cancel_intent(),
    host,
    boot,
    now,
    boot_now,
    receipts(cancel_intent(), "verify_profile", policy),
  )
  |> should.equal(Error("receipt_claims_mismatch"))
}

pub fn prepare_accepts_a_verify_intent_and_binds_the_deadline_test() {
  let p = prepared()
  verify_action.deadline_ms(p) |> should.equal(1_060_000)
  verify_action.verify_binding(p) |> should.equal(verify_binding())
  verify_action.effect_id(p) |> should.equal(action.effect_id(verify_intent()))
  list.length(verify_action.receipt_digests(p)) |> should.equal(3)
  verify_action.ready(p, roster(), binding(), verify_binding(), observed())
  |> should.be_true
}

pub fn prepare_refuses_a_cancellation_intent_test() {
  verify_action.prepare(
    cancel_intent(),
    evidence(cancel_intent(), "cancel_job_lease"),
    roster(),
    binding(),
    verify_binding(),
    observed(),
  )
  |> should.equal(Error("verify_intent_kind_mismatch"))
}

pub fn prepare_refuses_a_target_that_is_not_the_reservation_test() {
  let other = v.Binding(..verify_binding(), job_id: "telegram/verify/" <> string.repeat("2", 64))
  verify_action.prepare(
    verify_intent(),
    evidence(verify_intent(), "verify_profile"),
    roster(),
    binding(),
    other,
    observed(),
  )
  |> should.equal(Error("verify_target_mismatch"))
  let attempt = v.Binding(..verify_binding(), attempt: 2)
  verify_action.prepare(
    verify_intent(),
    evidence(verify_intent(), "verify_profile"),
    roster(),
    binding(),
    attempt,
    observed(),
  )
  |> should.equal(Error("verify_target_mismatch"))
}

pub fn prepare_refuses_after_the_deadline_test() {
  verify_action.prepare(
    verify_intent(),
    evidence(verify_intent(), "verify_profile"),
    roster(),
    binding(),
    verify_binding(),
    cancel.Observation(host, boot, 1_060_000, boot_now + 30_000),
  )
  |> result.is_error
  |> should.be_true
}

pub fn ready_is_false_for_other_binding_reservation_or_time_test() {
  let p = prepared()
  let other_binding = action.Binding(..binding(), update_id: 20)
  verify_action.ready(p, roster(), other_binding, verify_binding(), observed())
  |> should.be_false
  let other_verify = v.Binding(..verify_binding(), attempt: 2)
  verify_action.ready(p, roster(), binding(), other_verify, observed())
  |> should.be_false
  verify_action.ready(
    p,
    roster(),
    binding(),
    verify_binding(),
    cancel.Observation(host, boot, 1_060_000, boot_now + 30_000),
  )
  |> should.be_false
}

pub fn record_round_trips_byte_exactly_test() {
  let p = prepared()
  let raw = verify_action.encode_record(p)
  let assert Ok(decoded) = verify_action.decode_record(raw)
  action.digest(decoded.intent) |> should.equal(action.digest(verify_intent()))
  decoded.binding |> should.equal(binding())
  decoded.verify |> should.equal(verify_binding())
  decoded.deadline_ms |> should.equal(1_060_000)
  decoded.target
  |> should.equal(verify_action.target_for(
    "uos/example",
    verify_binding(),
    worker,
    lease_until_ns,
  ))
  // Any byte change is refused: a trailing space is not canonical.
  verify_action.decode_record(raw <> " ") |> result.is_error |> should.be_true
  // A deadline that disagrees with the canonical form is refused.
  string.replace(raw, "1060000", "1060001")
  |> verify_action.decode_record
  |> result.is_error
  |> should.be_true
}

pub fn decode_record_refuses_a_cancellation_record_test() {
  let assert Ok(cancel_record) =
    record.new(
      cancel_intent(),
      binding(),
      verify_action.target_for(
      "uos/example",
      verify_binding(),
      worker,
      lease_until_ns,
    ),
      1_060_000,
    )
  verify_action.decode_record(record.encode(cancel_record))
  |> result.is_error
  |> should.be_true
  // The converse: a verify intent cannot become a cancellation record.
  record.new(
    verify_intent(),
    binding(),
    verify_action.target_for(
      "uos/example",
      verify_binding(),
      worker,
      lease_until_ns,
    ),
    1_060_000,
  )
  |> result.is_error
  |> should.be_true
  action.native_request(verify_intent(), 1_050_000)
  |> should.equal(Error("native_request_kind_mismatch"))
}

pub fn decode_record_refuses_a_verify_intent_wrapped_for_another_job_test() {
  // A record whose intent targets job1 but whose reservation names job2.
  let other = v.Binding(..verify_binding(), job_id: "telegram/verify/" <> string.repeat("2", 64))
  verify_action.encode_parts(verify_intent(), 1_060_000, other)
  |> verify_action.decode_record
  |> should.equal(Error("verify_target_mismatch"))
}
