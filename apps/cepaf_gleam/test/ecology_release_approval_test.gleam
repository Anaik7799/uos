//// Real ephemeral Ed25519 signatures; fixture helper is test-only and no actual
//// operator/agent key, signature, roster or production approval is asserted.

import cepaf_gleam/ecology/release_approval as a
import cepaf_gleam/ecology/release_intent as i
import ecology_release_intent_test as f
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import gleeunit/should

@external(erlang, "telegram_approval_test_crypto", "public_key")
fn public_key(role: String) -> String

@external(erlang, "telegram_approval_test_crypto", "sign")
fn sign(role: String, payload: String) -> String

@external(erlang, "telegram_approval_test_crypto", "sign_header")
fn sign_header(role: String, payload: String, header: String) -> String

fn signer(role) {
  let name = a.role_name(role)
  a.Signer(role, name <> "-subject", name <> "-key", public_key(name))
}

fn signers() {
  list.map([a.Operator, a.Codex, a.Agy], signer)
}

fn roster() {
  let assert Ok(p) = a.new_roster(signers(), 900_000, 1_200_000)
  p
}

fn fields(role, p) {
  [
    #("version", json.string(i.approval_purpose)),
    #("purpose", json.string(i.approval_purpose)),
    #("role", json.string(a.role_name(role))),
    #("subject", json.string(a.role_name(role) <> "-subject")),
    #("decision", json.string("approve")),
    #("intent_digest", json.string(i.digest(f.intent()))),
    #("effect_id", json.string(i.transaction_id(f.intent()))),
    #("iat_ms", json.int(1_000_000)),
    #("nbf_ms", json.int(1_000_000)),
    #("exp_ms", json.int(1_060_000)),
    #("roster_digest", json.string(a.roster_digest(p))),
  ]
}

fn replace(fs: List(#(String, json.Json)), k: String, v: json.Json) {
  list.map(fs, fn(p) {
    case p.0 == k {
      True -> #(k, v)
      False -> p
    }
  })
}

fn signed(role, fs) {
  a.Receipt(role, sign(a.role_name(role), json.to_string(json.object(fs))))
}

fn receipts(p) {
  list.map([a.Operator, a.Codex, a.Agy], fn(r) { signed(r, fields(r, p)) })
}

fn verify(p, rs) {
  a.verify(
    p,
    f.intent(),
    f.host,
    f.boot,
    f.clock_domain,
    1_030_000,
    -50_000,
    rs,
  )
}

fn rejects(p, rs) {
  verify(p, rs) |> result.is_error |> should.be_true
}

pub fn real_three_signature_positive_and_order_invariance_test() {
  let p = roster()
  let rs = receipts(p)
  let assert Ok(e) = verify(p, rs)
  let assert Ok(reverse) = verify(p, list.reverse(rs))
  a.evidence_digest(e) |> should.equal(a.evidence_digest(reverse))
  a.intent_digest(e) |> should.equal(i.digest(f.intent()))
  a.expires_utc_ms(e) |> should.equal(1_060_000)
  a.expires_mono_ms(e) |> should.equal(-20_000)
  a.still_valid(
    e,
    p,
    f.intent(),
    f.host,
    f.boot,
    f.clock_domain,
    1_030_000,
    -50_000,
  )
  |> should.be_true
  a.still_valid(
    e,
    p,
    f.intent(),
    f.host,
    f.boot,
    f.clock_domain,
    1_060_000,
    -50_000,
  )
  |> should.be_false
  a.still_valid(
    e,
    p,
    f.intent(),
    f.host,
    f.boot,
    f.clock_domain,
    1_030_000,
    -20_000,
  )
  |> should.be_false
  a.still_valid(
    e,
    p,
    f.intent(),
    f.host,
    "reboot",
    f.clock_domain,
    1_030_000,
    -50_000,
  )
  |> should.be_false
  string.contains(a.profile, "NOT_ADMITTED") |> should.be_true
}

pub fn missing_duplicate_and_unavailable_role_refusals_test() {
  let p = roster()
  let op = signed(a.Operator, fields(a.Operator, p))
  let co = signed(a.Codex, fields(a.Codex, p))
  let ag = signed(a.Agy, fields(a.Agy, p))
  list.each(
    [[], [op], [co, ag], [op, co], [op, ag], [op, co, co], [op, co, ag, op]],
    fn(rs) { rejects(p, rs) },
  )
  let wrong = a.Receipt(a.Agy, co.token)
  rejects(p, [op, co, wrong])
}

pub fn strict_all_eleven_claim_bindings_test() {
  let p = roster()
  let others = [
    signed(a.Operator, fields(a.Operator, p)),
    signed(a.Agy, fields(a.Agy, p)),
  ]
  list.each(
    [
      #("version", json.string("uos.telegram.approval.v1")),
      #("purpose", json.string("verify_profile")),
      #("purpose", json.string("cancel_job_lease")),
      #("role", json.string("agy")),
      #("subject", json.string("operator-subject")),
      #("decision", json.string("deny")),
      #("intent_digest", json.string(string.repeat("0", 64))),
      #("effect_id", json.string(f.dg("9"))),
      #("roster_digest", json.string(string.repeat("0", 64))),
      #("iat_ms", json.int(1_030_001)),
      #("iat_ms", json.int(999_999)),
      #("nbf_ms", json.int(1_030_001)),
      #("exp_ms", json.int(1_030_000)),
      #("exp_ms", json.int(1_060_001)),
    ],
    fn(change) {
      rejects(p, [
        signed(a.Codex, replace(fields(a.Codex, p), change.0, change.1)),
        ..others
      ])
    },
  )
  rejects(p, [
    signed(a.Codex, [#("extra", json.bool(True)), ..fields(a.Codex, p)]),
    ..others
  ])
  rejects(p, [
    signed(a.Codex, [#("role", json.string("codex")), ..fields(a.Codex, p)]),
    ..others
  ])
  rejects(p, [
    signed(a.Codex, list.filter(fields(a.Codex, p), fn(x) { x.0 != "purpose" })),
    ..others
  ])
}

pub fn bad_signature_header_and_malformed_jwt_test() {
  let p = roster()
  let rs = receipts(p)
  let others = list.drop(rs, 1)
  list.each(["", "x.y.z", string.repeat("x", 8193)], fn(t) {
    rejects(p, [a.Receipt(a.Operator, t), ..others])
  })
  list.each(
    [
      "{\"alg\":\"none\",\"kid\":\"operator-key\",\"typ\":\"JWT\"}",
      "{\"alg\":\"HS256\",\"kid\":\"operator-key\",\"typ\":\"JWT\"}",
      "{\"alg\":\"EdDSA\",\"kid\":\"codex-key\",\"typ\":\"JWT\"}",
      "{\"alg\":\"EdDSA\",\"kid\":\"operator-key\",\"typ\":\"JWT\",\"jku\":\"https://foreign.invalid\"}",
    ],
    fn(h) {
      rejects(p, [
        a.Receipt(
          a.Operator,
          sign_header(
            "operator",
            json.to_string(json.object(fields(a.Operator, p))),
            h,
          ),
        ),
        ..others
      ])
    },
  )
  let co = signed(a.Codex, fields(a.Codex, p))
  rejects(p, [a.Receipt(a.Operator, co.token), ..others])
}

pub fn roster_independence_windows_and_aliases_test() {
  let ss = signers()
  let assert [op, co, ag] = ss
  list.each(
    [
      [],
      [op, co],
      [op, co, ag, op],
      [op, co, co],
      [op, a.Signer(..co, subject: op.subject), ag],
      [op, a.Signer(..co, kid: op.kid), ag],
      [op, a.Signer(..co, public_key: op.public_key), ag],
      [op, a.Signer(..co, public_key: co.public_key <> "="), ag],
      [op, a.Signer(..co, subject: "unsafe\u{0000}"), ag],
    ],
    fn(ss) {
      a.new_roster(ss, 900_000, 1_200_000) |> result.is_error |> should.be_true
    },
  )
  let assert Ok(p) = a.new_roster(ss, 900_000, 1_200_000)
  let assert Ok(reverse) = a.new_roster(list.reverse(ss), 900_000, 1_200_000)
  a.roster_digest(p) |> should.equal(a.roster_digest(reverse))
  list.each([#(-1, 1000), #(1000, 1000), #(0, 3_600_001)], fn(w) {
    a.new_roster(ss, w.0, w.1) |> result.is_error |> should.be_true
  })
  let assert Ok(expired) = a.new_roster(ss, 900_000, 1_030_000)
  verify(expired, receipts(expired)) |> result.is_error |> should.be_true
  let assert Ok(future) = a.new_roster(ss, 1_030_001, 1_090_000)
  verify(future, receipts(future)) |> result.is_error |> should.be_true
}

pub fn cross_intent_clock_binding_and_short_receipt_no_refresh_test() {
  let p = roster()
  let rs = receipts(p)
  let proposal = f.proposal()
  let assert Ok(other) =
    i.new(i.Proposal(..proposal, nonce: "different-occurrence"))
  a.verify(p, other, f.host, f.boot, f.clock_domain, 1_030_000, -50_000, rs)
  |> result.is_error
  |> should.be_true
  a.verify(
    p,
    f.intent(),
    f.host,
    "reboot",
    f.clock_domain,
    1_030_000,
    -50_000,
    rs,
  )
  |> result.is_error
  |> should.be_true
  let assert Ok(e) = verify(p, rs)
  a.still_valid(
    e,
    p,
    f.intent(),
    f.host,
    f.boot,
    f.clock_domain,
    1_029_999,
    -49_999,
  )
  |> should.be_false
  a.still_valid(
    e,
    p,
    f.intent(),
    f.host,
    f.boot,
    f.clock_domain,
    1_030_001,
    -50_001,
  )
  |> should.be_false
  let short =
    list.map([a.Operator, a.Codex, a.Agy], fn(r) {
      signed(r, replace(fields(r, p), "exp_ms", json.int(1_040_000)))
    })
  let assert Ok(e) = verify(p, short)
  a.expires_mono_ms(e) |> should.equal(-40_000)
  // UTC still reads 1_030_000, but signed creation-pair TTL already elapsed in
  // the independent boot domain: a second verify must not refresh it.
  a.verify(
    p,
    f.intent(),
    f.host,
    f.boot,
    f.clock_domain,
    1_030_000,
    -39_999,
    short,
  )
  |> result.is_error
  |> should.be_true
}

pub fn verified_evidence_rejects_cross_vm_clock_origin_test() {
  let p = roster()
  let rs = receipts(p)
  a.verify(
    p,
    f.intent(),
    f.host,
    f.boot,
    "different-vm-same-linux-boot",
    1_030_000,
    -50_000,
    rs,
  )
  |> result.is_error
  |> should.be_true
  let assert Ok(e) = verify(p, rs)
  a.still_valid(
    e,
    p,
    f.intent(),
    f.host,
    f.boot,
    "different-vm-same-linux-boot",
    1_030_000,
    -50_000,
  )
  |> should.be_false
  let short =
    list.map([a.Operator, a.Codex, a.Agy], fn(r) {
      signed(r, replace(fields(r, p), "exp_ms", json.int(1_040_000)))
    })
  let assert Ok(first) = verify(p, short)
  let assert Ok(later) =
    a.verify(
      p,
      f.intent(),
      f.host,
      f.boot,
      f.clock_domain,
      1_030_000,
      -45_000,
      short,
    )
  a.expires_mono_ms(first) |> should.equal(a.expires_mono_ms(later))
}

pub fn cryptographic_wrong_key_and_current_roster_freshness_test() {
  let p = roster()
  let op_fields = json.to_string(json.object(fields(a.Operator, p)))
  // Correct algorithm/kid/claims but signature made by a DIFFERENT private key:
  // this reaches actual Ed25519 signature rejection, not only claim validation.
  let header = "{\"alg\":\"EdDSA\",\"kid\":\"operator-key\",\"typ\":\"JWT\"}"
  let forged = a.Receipt(a.Operator, sign_header("codex", op_fields, header))
  rejects(p, [
    forged,
    signed(a.Codex, fields(a.Codex, p)),
    signed(a.Agy, fields(a.Agy, p)),
  ])
  let assert Ok(e) = verify(p, receipts(p))
  let assert Ok(current) = a.new_roster(signers(), 900_001, 1_200_000)
  a.still_valid(
    e,
    current,
    f.intent(),
    f.host,
    f.boot,
    f.clock_domain,
    1_030_000,
    -50_000,
  )
  |> should.be_false
  let assert Ok(short) = a.new_roster(signers(), 900_000, 1_040_000)
  let assert Ok(e) = verify(short, receipts(short))
  a.expires_utc_ms(e) |> should.equal(1_040_000)
  a.expires_mono_ms(e) |> should.equal(-40_000)
  a.still_valid(
    e,
    short,
    f.intent(),
    f.host,
    f.boot,
    f.clock_domain,
    1_030_000,
    -40_000,
  )
  |> should.be_false
}

pub fn approval_set_identity_survives_reverification_without_ttl_refresh_test() {
  let p = roster()
  let rs = receipts(p)
  let assert Ok(first) = verify(p, rs)
  let assert Ok(later) =
    a.verify(
      p,
      f.intent(),
      f.host,
      f.boot,
      f.clock_domain,
      1_030_001,
      -49_999,
      list.reverse(rs),
    )
  a.approval_set_digest(first) |> should.equal(a.approval_set_digest(later))
  { a.evidence_digest(first) != a.evidence_digest(later) } |> should.be_true
  a.expires_utc_ms(first) |> should.equal(a.expires_utc_ms(later))
  a.expires_mono_ms(first) |> should.equal(a.expires_mono_ms(later))
}
