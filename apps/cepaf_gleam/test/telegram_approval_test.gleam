import cepaf_gleam/harness/telegram_action_intent as action
import cepaf_gleam/harness/telegram_approval as approval
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import gleeunit/should

const host = "nas-1.tail55d152.ts.net"

const boot = "boot-1"

const now = 1_030_000

const boot_now = 50_000

fn intent() {
  let assert Ok(value) =
    action.new(
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
      ),
      action.Target("uos/example/job1", "worker", 2, 2_000_000_000_000),
      action.Window(1_000_000, 20_000, 1_060_000, 80_000),
      "Operator requested cancellation",
      string.repeat("b", 64),
    )
  value
}

fn signer(role) {
  let name = approval.role_name(role)
  approval.Signer(role, name <> "-subject", name <> "-key", public_key(name))
}

fn signers() {
  list.map(
    [approval.Codex, approval.Agy, approval.Claude, approval.Operator],
    signer,
  )
}

fn roster() {
  let assert Ok(value) = approval.new_roster(signers(), 900_000, 1_200_000)
  value
}

fn fields(role, policy) {
  [
    #("version", json.string("uos.telegram.approval.v1")),
    #("purpose", json.string("cancel_job_lease")),
    #("role", json.string(approval.role_name(role))),
    #("subject", json.string(approval.role_name(role) <> "-subject")),
    #("decision", json.string("approve")),
    #("intent_digest", json.string(action.digest(intent()))),
    #("effect_id", json.string(action.effect_id(intent()))),
    #("iat_ms", json.int(1_000_000)),
    #("nbf_ms", json.int(1_000_000)),
    #("exp_ms", json.int(1_060_000)),
    #("roster_digest", json.string(approval.roster_digest(policy))),
  ]
}

fn replace(fields: List(#(String, json.Json)), key: String, value: json.Json) {
  list.map(fields, fn(pair) {
    case pair.0 == key {
      True -> #(key, value)
      False -> pair
    }
  })
}

fn receipt(role, policy) {
  signed(role, fields(role, policy))
}

fn signed(role, pairs) {
  approval.Receipt(
    role,
    sign(approval.role_name(role), json.to_string(json.object(pairs))),
  )
}

fn receipts(policy) {
  list.map([approval.Codex, approval.Agy, approval.Operator], fn(role) {
    receipt(role, policy)
  })
}

fn verify(policy, rs) {
  approval.verify(policy, intent(), host, boot, now, boot_now, rs)
}

fn rejected(rs, policy) {
  verify(policy, rs) |> result.is_error |> should.be_true
}

pub fn each_sovereign_pair_and_all_three_test() {
  let p = roster()
  list.each(
    [
      [approval.Codex, approval.Agy, approval.Operator],
      [approval.Codex, approval.Claude, approval.Operator],
      [approval.Agy, approval.Claude, approval.Operator],
      [approval.Codex, approval.Agy, approval.Claude, approval.Operator],
    ],
    fn(roles) {
      let assert Ok(evidence) =
        verify(p, list.map(roles, fn(r) { receipt(r, p) }))
      approval.receipt_digests(evidence)
      |> list.length
      |> should.equal(list.length(roles))
      approval.still_valid(evidence, p, intent(), host, boot, now, boot_now)
      |> should.be_true
    },
  )
}

pub fn unavailable_third_key_is_not_a_vote_test() {
  let assert Ok(p) =
    approval.new_roster(
      list.map([approval.Codex, approval.Agy, approval.Operator], signer),
      900_000,
      1_200_000,
    )
  verify(p, receipts(p)) |> result.is_ok |> should.be_true
  verify(p, [
    receipt(approval.Codex, p),
    receipt(approval.Claude, p),
    receipt(approval.Operator, p),
  ])
  |> result.is_error
  |> should.be_true
}

pub fn missing_operator_or_quorum_test() {
  let p = roster()
  list.each(
    [
      [],
      [receipt(approval.Operator, p)],
      [receipt(approval.Codex, p), receipt(approval.Operator, p)],
      [
        receipt(approval.Codex, p),
        receipt(approval.Agy, p),
        receipt(approval.Claude, p),
      ],
    ],
    fn(rs) { rejected(rs, p) },
  )
}

pub fn extra_duplicate_and_invalid_receipts_test() {
  let p = roster()
  rejected(list.append(receipts(p), [receipt(approval.Codex, p)]), p)
  rejected(
    list.append(receipts(p), [approval.Receipt(approval.Claude, "malformed")]),
    p,
  )
  rejected(
    list.append(receipts(p), [
      receipt(approval.Claude, p),
      receipt(approval.Operator, p),
    ]),
    p,
  )
}

pub fn wrong_or_changed_signature_test() {
  let p = roster()
  let good = receipt(approval.Codex, p)
  let wrong =
    approval.Receipt(
      approval.Codex,
      sign("stranger", json.to_string(json.object(fields(approval.Codex, p)))),
    )
  let tampered = approval.Receipt(approval.Codex, good.token <> "A")
  list.each(
    [wrong, tampered, approval.Receipt(approval.Agy, good.token)],
    fn(r) {
      rejected([r, receipt(approval.Agy, p), receipt(approval.Operator, p)], p)
    },
  )
}

pub fn every_signed_binding_is_enforced_test() {
  let p = roster()
  list.each(
    [
      #("version", "wrong"),
      #("purpose", "storage_rebalance"),
      #("role", "agy"),
      #("subject", "other-subject"),
      #("decision", "reject"),
      #("intent_digest", string.repeat("c", 64)),
      #("effect_id", string.repeat("d", 64)),
      #("roster_digest", string.repeat("e", 64)),
    ],
    fn(change) {
      let r =
        signed(
          approval.Codex,
          replace(fields(approval.Codex, p), change.0, json.string(change.1)),
        )
      rejected([r, receipt(approval.Agy, p), receipt(approval.Operator, p)], p)
    },
  )
}

pub fn third_sovereign_rejection_vetoes_test() {
  let p = roster()
  let r =
    signed(
      approval.Claude,
      replace(fields(approval.Claude, p), "decision", json.string("reject")),
    )
  rejected(list.append(receipts(p), [r]), p)
}

pub fn exact_claim_schema_test() {
  let p = roster()
  let base = fields(approval.Codex, p)
  let extra =
    signed(approval.Codex, list.append(base, [#("admin", json.bool(True))]))
  let duplicate =
    signed(
      approval.Codex,
      list.append(base, [#("decision", json.string("approve"))]),
    )
  let missing =
    signed(approval.Codex, list.filter(base, fn(pair) { pair.0 != "purpose" }))
  let wrong_type =
    signed(approval.Codex, replace(base, "exp_ms", json.string("1060000")))
  list.each([extra, duplicate, missing, wrong_type], fn(r) {
    rejected([r, receipt(approval.Agy, p), receipt(approval.Operator, p)], p)
  })
}

pub fn receipt_time_boundaries_test() {
  let p = roster()
  list.each(
    [
      #("iat_ms", 999_999),
      #("iat_ms", 1_000_001),
      #("nbf_ms", 999_999),
      #("nbf_ms", now + 1),
      #("exp_ms", now),
      #("exp_ms", 1_060_001),
      #("exp_ms", 9_007_199_254_740_992),
    ],
    fn(change) {
      let r =
        signed(
          approval.Codex,
          replace(fields(approval.Codex, p), change.0, json.int(change.1)),
        )
      rejected([r, receipt(approval.Agy, p), receipt(approval.Operator, p)], p)
    },
  )
  let just_valid =
    signed(
      approval.Codex,
      replace(fields(approval.Codex, p), "exp_ms", json.int(now + 1)),
    )
  let assert Ok(e) =
    verify(p, [
      just_valid,
      receipt(approval.Agy, p),
      receipt(approval.Operator, p),
    ])
  approval.still_valid(e, p, intent(), host, boot, now + 1, boot_now + 1)
  |> should.be_false
}

pub fn host_boot_clock_and_intent_expiry_test() {
  let p = roster()
  list.each(
    [
      #("other.tail55d152.ts.net", boot, now, boot_now),
      #(host, "other-boot", now, boot_now),
      #(host, boot, now + 2001, boot_now),
      #(host, boot, 999_999, 19_999),
      #(host, boot, 1_060_000, 80_000),
    ],
    fn(t) {
      approval.verify(p, intent(), t.0, t.1, t.2, t.3, receipts(p))
      |> result.is_error
      |> should.be_true
    },
  )
}

pub fn roster_duplicates_and_empty_fields_test() {
  let a = signer(approval.Codex)
  let b = signer(approval.Agy)
  let c = signer(approval.Claude)
  let o = signer(approval.Operator)
  list.each(
    [
      [],
      [a, b, c],
      [a, o],
      [a, a, o],
      [a, approval.Signer(..b, subject: a.subject), o],
      [a, approval.Signer(..b, kid: a.kid), o],
      [a, approval.Signer(..b, public_key: a.public_key), o],
      [a, approval.Signer(..b, kid: ""), o],
      [a, approval.Signer(..b, subject: "line\nfeed"), o],
      [a, approval.Signer(..b, public_key: "bad-key"), o],
      [a, approval.Signer(..b, public_key: b.public_key <> "="), o],
      [a, b, c, o, o],
    ],
    fn(keys) {
      approval.new_roster(keys, 900_000, 1_200_000)
      |> result.is_error
      |> should.be_true
    },
  )
}

pub fn roster_time_and_replacement_test() {
  list.each(
    [
      #(-1, 1),
      #(1, 1),
      #(2, 1),
      #(0, 3_600_001),
      #(9_007_199_254_740_990, 9_007_199_254_740_992),
    ],
    fn(t) {
      approval.new_roster(signers(), t.0, t.1)
      |> result.is_error
      |> should.be_true
    },
  )
  let p = roster()
  let assert Ok(e) = verify(p, receipts(p))
  let assert Ok(expired) = approval.new_roster(signers(), 900_000, now)
  verify(expired, receipts(expired)) |> result.is_error |> should.be_true
  let assert Ok(future) = approval.new_roster(signers(), now + 1, 1_200_000)
  verify(future, receipts(future)) |> result.is_error |> should.be_true
  let assert Ok(changed) = approval.new_roster(signers(), 900_001, 1_200_000)
  approval.still_valid(e, changed, intent(), host, boot, now, boot_now)
  |> should.be_false
}

pub fn signed_header_policy_and_token_bound_test() {
  let p = roster()
  list.each(
    [
      "{\"alg\":\"none\",\"kid\":\"codex-key\",\"typ\":\"JWT\"}",
      "{\"alg\":\"EdDSA\",\"kid\":\"codex-key\",\"typ\":\"JWT\",\"jku\":\"https://attacker.invalid/keys\"}",
      "{\"alg\":\"EdDSA\",\"kid\":\"codex-key\",\"kid\":\"codex-key\",\"typ\":\"JWT\"}",
    ],
    fn(header) {
      let token =
        sign_header(
          "codex",
          json.to_string(json.object(fields(approval.Codex, p))),
          header,
        )
      rejected(
        [
          approval.Receipt(approval.Codex, token),
          receipt(approval.Agy, p),
          receipt(approval.Operator, p),
        ],
        p,
      )
    },
  )
  rejected(
    [
      approval.Receipt(approval.Codex, string.repeat("x", 8193)),
      receipt(approval.Agy, p),
      receipt(approval.Operator, p),
    ],
    p,
  )
}

pub fn evidence_and_error_do_not_retain_tokens_test() {
  let p = roster()
  let rs = receipts(p)
  let assert Ok(e) = verify(p, rs)
  list.each(approval.receipt_digests(e), fn(hash) {
    string.length(hash) |> should.equal(64)
    string.contains(hash, ".") |> should.be_false
  })
  let secret_like = "PRIVATE-COMPACT-TOKEN.NOT-A-JWT"
  let assert Error(error) =
    verify(p, [
      approval.Receipt(approval.Codex, secret_like),
      receipt(approval.Agy, p),
      receipt(approval.Operator, p),
    ])
  string.contains(error, secret_like) |> should.be_false
}

pub fn receipt_window_helper_test() {
  action.valid_receipt_window(intent(), now, 1_000_000, now, now + 1)
  |> should.be_true
  action.valid_receipt_window(intent(), now, 999_999, now, now + 1)
  |> should.be_false
  action.valid_receipt_window(intent(), now, now, now, now) |> should.be_false
  action.valid_receipt_window(intent(), now, now, now, 1_060_001)
  |> should.be_false
}

@external(erlang, "telegram_approval_test_crypto", "public_key")
fn public_key(role: String) -> String

@external(erlang, "telegram_approval_test_crypto", "sign")
fn sign(role: String, payload: String) -> String

@external(erlang, "telegram_approval_test_crypto", "sign_header")
fn sign_header(role: String, payload: String, header: String) -> String

pub fn recheck_rejects_clock_rollback_and_new_request_test() {
  let p = roster()
  let assert Ok(e) = verify(p, receipts(p))
  approval.still_valid(e, p, intent(), host, boot, now - 1, boot_now - 1)
  |> should.be_false
  approval.still_valid(e, p, intent(), host, boot, now, boot_now - 1)
  |> should.be_false
  approval.still_valid(e, p, intent(), host, "other", now, boot_now)
  |> should.be_false
  let assert Ok(changed) =
    action.new(
      action.Binding(
        7,
        -11,
        13,
        19,
        "uos/example",
        "TASK",
        "operator",
        7,
        10,
        string.repeat("a", 64),
        host,
        boot,
        action.Execution("mapping-1", "lease-1", 3, string.repeat("d", 64)),
      ),
      action.Target("uos/example/job1", "worker", 2, 2_000_000_000_000),
      action.Window(1_000_000, 20_000, 1_060_000, 80_000),
      "Operator requested cancellation",
      string.repeat("b", 64),
    )
  action.effect_id(changed) |> should.equal(action.effect_id(intent()))
  approval.still_valid(e, p, changed, host, boot, now, boot_now)
  |> should.be_false
  approval.verify(p, changed, host, boot, now, boot_now, receipts(p))
  |> result.is_error
  |> should.be_true
}

pub fn correct_header_wrong_cryptographic_key_test() {
  let p = roster()
  let header = "{\"alg\":\"EdDSA\",\"kid\":\"codex-key\",\"typ\":\"JWT\"}"
  let token =
    sign_header(
      "stranger",
      json.to_string(json.object(fields(approval.Codex, p))),
      header,
    )
  rejected(
    [
      approval.Receipt(approval.Codex, token),
      receipt(approval.Agy, p),
      receipt(approval.Operator, p),
    ],
    p,
  )
}

pub fn native_deadline_includes_shorter_receipt_and_roster_test() {
  let p = roster()
  let shortened =
    signed(
      approval.Codex,
      replace(fields(approval.Codex, p), "exp_ms", json.int(now + 1)),
    )
  let assert Ok(e) =
    verify(p, [
      shortened,
      receipt(approval.Agy, p),
      receipt(approval.Operator, p),
    ])
  approval.execution_deadline_ms(e) |> should.equal(now + 1)
  let assert Ok(short_roster) = approval.new_roster(signers(), 900_000, now + 2)
  let assert Ok(re) = verify(short_roster, receipts(short_roster))
  approval.execution_deadline_ms(re) |> should.equal(now + 2)
}
