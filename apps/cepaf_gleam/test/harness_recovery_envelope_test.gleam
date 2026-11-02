//// Fixture-owned ephemeral keys only. No real role/key provisioning is asserted.

import cepaf_gleam/harness/recovery_envelope as a
import cepaf_gleam/harness/recovery_wire as wire
import gleam/bit_array
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import gleeunit/should

@external(erlang, "telegram_approval_test_crypto", "public_key")
fn public_key(role: String) -> String

@external(erlang, "telegram_approval_test_crypto", "sign_header")
fn sign_header(role: String, payload: String, header: String) -> String

fn d(c: String) -> String {
  string.repeat(c, 64)
}

fn signer(role: String) -> a.Signer {
  a.Signer(
    role <> "-subject",
    role <> "-session",
    role <> "-actor",
    role <> "-key",
    public_key(role),
  )
}

fn configuration() -> a.ConfigurationData {
  let assert Ok(c) =
    a.configuration_data(
      signer("reviewer"),
      signer("issuer"),
      900_000,
      1_200_000,
      d("a"),
    )
  c
}

fn member(
  task: String,
  worker: String,
  attempt: Int,
  lease: String,
) -> json.Json {
  json.object([
    #("task_id", json.string(task)),
    #("worker", json.string(worker)),
    #("old_attempt", json.int(attempt)),
    #("old_lease_ns", json.string(lease)),
    #("lease_ms", json.int(60_000)),
  ])
}

fn members() -> List(json.Json) {
  [
    member(
      "OI02B_ALL_AGENT_SYMBIOSIS_PREFLIGHT",
      "codex-symbiosis-preflight-20261031",
      2,
      "900000000000",
    ),
    member(
      "OI02E_RELEASE_AUTHORITY_PREPARATION",
      "codex-release-authority-20261031",
      1,
      "900000000000",
    ),
    member(
      "OI02_ATOMIC_11_TARGET_CAPSULE_CUTOVER",
      "codex-hive-cutover-20261031",
      1,
      "900000000000",
    ),
  ]
}

fn request_raw(
  plan: String,
  members: List(json.Json),
  request_id: String,
) -> String {
  let raw =
    json.object([
      #("request_id", json.string(request_id)),
      #("plan", json.string(plan)),
      #("snapshot_sha256", json.string("sha256:" <> d("0"))),
      #("members", json.preprocessed_array(members)),
      #("deadline_utc_ms", json.int(1_060_000)),
    ])
    |> json.to_string
  raw
}

fn request_with(
  plan: String,
  members: List(json.Json),
  request_id: String,
) -> wire.FactualRequest {
  let assert Ok(r) = wire.decode(request_raw(plan, members, request_id))
  r
}

fn request() -> wire.FactualRequest {
  request_with(a.fixed_plan, members(), "fixture-request")
}

fn bindings() -> a.Bindings {
  a.Bindings(
    d("1"),
    d("2"),
    d("3"),
    d("4"),
    "reviewer-actor",
    [
      "codex-hive-cutover-20261031",
      "codex-release-authority-20261031",
      "codex-symbiosis-preflight-20261031",
    ],
    d("5"),
    d("6"),
    d("7"),
    d("8"),
  )
}

fn window() -> a.Window {
  a.Window(1_000_000, 1_060_000, -100_000, -40_000, 1_100_000, 1_070_000)
}

fn runtime() -> a.Runtime {
  a.Runtime(
    "nas-1.tail55d152.ts.net",
    "boot-fixture",
    "beam-vm-fixture",
    "sa-plan-recovery",
    "fixture-holder",
    109,
  )
}

fn now() -> a.Observation {
  a.Observation(
    "nas-1.tail55d152.ts.net",
    "boot-fixture",
    "beam-vm-fixture",
    1_030_000,
    -70_000,
  )
}

fn context(c: a.ConfigurationData) -> a.Context {
  let assert Ok(ctx) =
    a.context_data(c, request(), bindings(), window(), runtime())
  ctx
}

fn signed(
  c: a.ConfigurationData,
  ctx: a.Context,
  purpose: a.Purpose,
  review: String,
) -> String {
  let assert Ok(payload) = a.signing_payload(c, ctx, purpose, review)
  let role = case purpose {
    a.IndependentReview -> "reviewer"
    a.TaskRecoveryIssuer -> "issuer"
  }
  sign_header(role, payload, a.header_bytes(c, purpose))
}

fn tokens(c: a.ConfigurationData, ctx: a.Context) -> #(String, String) {
  let review = signed(c, ctx, a.IndependentReview, "")
  #(review, signed(c, ctx, a.TaskRecoveryIssuer, review))
}

fn bad(result) {
  result |> result.is_error |> should.be_true
}

fn replace(text: String, before: String, after: String) -> String {
  string.replace(text, before, after)
}

pub fn genuine_two_signature_and_native_binding_test() {
  let c = configuration()
  let ctx = context(c)
  let #(review, issuer) = tokens(c, ctx)
  let assert Ok(e) = a.verify(c, ctx, now(), review, issuer)
  a.verified_request_sha256(e) |> should.equal(wire.request_sha256(request()))
  a.authority(e) |> should.equal("NONE")
  a.expires_mono_ms(e) |> should.equal(-40_000)
  a.still_valid(e, c, ctx, now()) |> should.be_true
  string.contains(a.profile, "NOT_ADMITTED") |> should.be_true
}

pub fn wrong_signature_and_wrong_configured_key_test() {
  let c = configuration()
  let ctx = context(c)
  let #(review, issuer) = tokens(c, ctx)
  let assert Ok(payload) = a.signing_payload(c, ctx, a.IndependentReview, "")
  let wrong =
    sign_header("attacker", payload, a.header_bytes(c, a.IndependentReview))
  bad(a.verify(c, ctx, now(), wrong, issuer))
  // Isolate each signature from issuer-token linking: every OTHER condition
  // is valid. Skipping crypto must make these controls fail.
  let linked_issuer = signed(c, ctx, a.TaskRecoveryIssuer, wrong)
  bad(a.verify(c, ctx, now(), wrong, linked_issuer))
  let assert Ok(issuer_payload) =
    a.signing_payload(c, ctx, a.TaskRecoveryIssuer, review)
  let wrong_issuer =
    sign_header(
      "attacker",
      issuer_payload,
      a.header_bytes(c, a.TaskRecoveryIssuer),
    )
  bad(a.verify(c, ctx, now(), review, wrong_issuer))
  let other = a.Signer(..signer("reviewer"), public_key: public_key("attacker"))
  let assert Ok(wrong_config) =
    a.configuration_data(other, signer("issuer"), 900_000, 1_200_000, d("a"))
  bad(a.verify(wrong_config, ctx, now(), review, issuer))
  let assert Ok(wrong_context) =
    a.context_data(wrong_config, request(), bindings(), window(), runtime())
  bad(a.verify(wrong_config, wrong_context, now(), review, issuer))
}

pub fn missing_swapped_and_cross_purpose_receipts_test() {
  let c = configuration()
  let ctx = context(c)
  let #(review, issuer) = tokens(c, ctx)
  list.each(
    [#("", issuer), #(review, ""), #(issuer, review), #(review, review)],
    fn(pair) { bad(a.verify(c, ctx, now(), pair.0, pair.1)) },
  )
  let assert Ok(raw) = a.signing_payload(c, ctx, a.IndependentReview, "")
  let foreign =
    replace(raw, a.review_purpose, "uos.ecology.cutover.approval.v1")
  bad(a.verify(
    c,
    ctx,
    now(),
    sign_header("reviewer", foreign, a.header_bytes(c, a.IndependentReview)),
    issuer,
  ))
}

pub fn duplicate_unknown_and_noncanonical_signed_json_test() {
  let c = configuration()
  let ctx = context(c)
  let #(review, issuer) = tokens(c, ctx)
  let assert Ok(raw) = a.signing_payload(c, ctx, a.IndependentReview, "")
  let variants = [
    raw <> " ",
    " " <> raw,
    replace(raw, "{", "{\"domain\":\"duplicate\","),
    replace(raw, "{", "{\"caller_public_key\":\"must-not-import\","),
    replace(raw, "attest_evidence_only", "execute"),
    replace(raw, "reviewer-subject", "another-subject"),
    "/*comment*/" <> raw,
    replace(raw, "\"domain\":", "domain:"),
    string.drop_end(raw, 1) <> ",}",
    raw <> "\u{0000}",
  ]
  list.each(variants, fn(body) {
    bad(a.verify(
      c,
      ctx,
      now(),
      sign_header("reviewer", body, a.header_bytes(c, a.IndependentReview)),
      issuer,
    ))
  })
  let noncanonical_header = " " <> a.header_bytes(c, a.IndependentReview)
  bad(a.verify(
    c,
    ctx,
    now(),
    sign_header("reviewer", raw, noncanonical_header),
    issuer,
  ))
  bad(a.verify(c, ctx, now(), review <> ".extra", issuer))
  bad(a.verify(c, ctx, now(), string.repeat("x", 8193), issuer))
}

pub fn canonical_key_alias_and_disallowed_header_are_refused_test() {
  let r = signer("reviewer")
  let i = signer("issuer")
  let assert Ok(last) = list.last(string.to_graphemes(r.public_key))
  let assert Ok(pair) =
    list.find(
      [
        #("A", "B"),
        #("E", "F"),
        #("I", "J"),
        #("M", "N"),
        #("Q", "R"),
        #("U", "V"),
        #("Y", "Z"),
        #("c", "d"),
        #("g", "h"),
        #("k", "l"),
        #("o", "p"),
        #("s", "t"),
        #("w", "x"),
        #("0", "1"),
        #("4", "5"),
        #("8", "9"),
      ],
      fn(pair) { pair.0 == last },
    )
  let alias = string.drop_end(r.public_key, 1) <> pair.1
  // The two encodings decode to the SAME key under a lenient base64 decoder.
  // Existing production FFI enforces canonical encoding and refuses this alias.
  let assert Ok(a_key) = bit_array.base64_url_decode(r.public_key)
  let assert Ok(b_key) = bit_array.base64_url_decode(alias)
  a_key |> should.equal(b_key)
  bad(a.configuration_data(
    r,
    a.Signer(..i, public_key: alias),
    900_000,
    1_200_000,
    d("a"),
  ))
  let c = configuration()
  let ctx = context(c)
  let #(_, issuer) = tokens(c, ctx)
  let assert Ok(payload) = a.signing_payload(c, ctx, a.IndependentReview, "")
  list.each(
    [
      "{\"alg\":\"none\",\"kid\":\"reviewer-key\",\"typ\":\"JWT\"}",
      "{\"alg\":\"EdDSA\",\"kid\":\"reviewer-key\",\"typ\":\"JWT\",\"jku\":\"https://invalid.example\"}",
      "{\"alg\":\"EdDSA\",\"kid\":\"reviewer-key\",\"kid\":\"reviewer-key\",\"typ\":\"JWT\"}",
    ],
    fn(header) {
      bad(a.verify(
        c,
        ctx,
        now(),
        sign_header("reviewer", payload, header),
        issuer,
      ))
    },
  )
}

pub fn every_native_tuple_and_deadline_change_breaks_existing_signatures_test() {
  let c = configuration()
  let ctx = context(c)
  let #(review, issuer) = tokens(c, ctx)
  let raw = request_raw(a.fixed_plan, members(), "fixture-request")
  list.each(
    [
      #("\"old_attempt\":2", "\"old_attempt\":3"),
      #("900000000000", "900000000001"),
      #("\"lease_ms\":60000", "\"lease_ms\":60001"),
      #("\"deadline_utc_ms\":1060000", "\"deadline_utc_ms\":1060001"),
      #("sha256:" <> d("0"), "sha256:" <> d("9")),
    ],
    fn(change) {
      let assert Ok(r) = wire.decode(replace(raw, change.0, change.1))
      { wire.request_sha256(r) == wire.request_sha256(request()) }
      |> should.be_false
      let assert Ok(other) =
        a.context_data(c, r, bindings(), window(), runtime())
      bad(a.verify(c, other, now(), review, issuer))
    },
  )
}

pub fn signed_runtime_holder_resource_and_identity_are_not_outer_metadata_test() {
  let c = configuration()
  let ctx = context(c)
  let #(review, issuer) = tokens(c, ctx)
  let rt = runtime()
  let n = now()
  list.each(
    [
      #(a.Runtime(..rt, resource: "other-resource"), n),
      #(a.Runtime(..rt, coordinator_holder: "other-holder"), n),
      #(a.Runtime(..rt, epoch: 110), n),
      #(
        a.Runtime(..rt, boot: "other-boot"),
        a.Observation(..n, boot: "other-boot"),
      ),
      #(
        a.Runtime(..rt, clock_domain: "other-vm"),
        a.Observation(..n, clock_domain: "other-vm"),
      ),
      #(
        a.Runtime(..rt, host: "other.tail55d152.ts.net"),
        a.Observation(..n, host: "other.tail55d152.ts.net"),
      ),
    ],
    fn(pair) {
      let assert Ok(other) =
        a.context_data(c, request(), bindings(), window(), pair.0)
      bad(a.verify(c, other, pair.1, review, issuer))
    },
  )
  list.each(
    [
      "bad..tail55d152.ts.net",
      "-bad.tail55d152.ts.net",
      "bad?.tail55d152.ts.net",
    ],
    fn(host) {
      bad(a.context_data(
        c,
        request(),
        bindings(),
        window(),
        a.Runtime(..rt, host: host),
      ))
    },
  )
}

pub fn issuer_binds_exact_reviewer_token_test() {
  let c = configuration()
  let ctx = context(c)
  let #(review, _) = tokens(c, ctx)
  let assert Ok(raw) =
    a.signing_payload(c, ctx, a.TaskRecoveryIssuer, "different-review-token")
  let issuer =
    sign_header("issuer", raw, a.header_bytes(c, a.TaskRecoveryIssuer))
  bad(a.verify(c, ctx, now(), review, issuer))
}

pub fn signer_aliases_and_malformed_key_refused_test() {
  let reviewer = signer("reviewer")
  let issuer = signer("issuer")
  list.each(
    [
      a.Signer(..issuer, subject: reviewer.subject),
      a.Signer(..issuer, session: reviewer.session),
      a.Signer(..issuer, actor: reviewer.actor),
      a.Signer(..issuer, kid: reviewer.kid),
      a.Signer(..issuer, public_key: reviewer.public_key),
      a.Signer(..issuer, public_key: string.repeat("!", 43)),
    ],
    fn(i) { bad(a.configuration_data(reviewer, i, 900_000, 1_200_000, d("a"))) },
  )
  bad(a.configuration_data(reviewer, issuer, 900_000, 900_000, d("a")))
  bad(a.configuration_data(reviewer, issuer, 900_000, 9_000_000, d("a")))
}

pub fn fixed_plan_tasks_and_workers_are_enforced_beyond_generic_codec_test() {
  let c = configuration()
  bad(a.context_data(
    c,
    request_with("uos/another-plan", members(), "fixture-request"),
    bindings(),
    window(),
    runtime(),
  ))
  let assert [_, second, third] = members()
  let wrong_task =
    member(
      "another-task",
      "codex-symbiosis-preflight-20261031",
      2,
      "900000000000",
    )
  let wrong_worker =
    member(
      "OI02B_ALL_AGENT_SYMBIOSIS_PREFLIGHT",
      "another-worker",
      2,
      "900000000000",
    )
  list.each([wrong_task, wrong_worker], fn(first) {
    bad(a.context_data(
      c,
      request_with(a.fixed_plan, [first, second, third], "fixture-request"),
      bindings(),
      window(),
      runtime(),
    ))
  })
}

pub fn every_context_digest_binding_detects_tampering_test() {
  let c = configuration()
  let ctx = context(c)
  let #(review, issuer) = tokens(c, ctx)
  let b = bindings()
  list.each(
    [
      a.Bindings(..b, portfolio_sha256: d("9")),
      a.Bindings(..b, selection_sha256: d("9")),
      a.Bindings(..b, proposal_sha256: d("9")),
      a.Bindings(..b, factual_review_sha256: d("9")),
      a.Bindings(..b, source_sha256: d("9")),
      a.Bindings(..b, native_artifact_sha256: d("9")),
      a.Bindings(..b, native_worker_sha256: d("9")),
      a.Bindings(..b, guardian_sha256: d("9")),
    ],
    fn(changed) {
      let assert Ok(other) =
        a.context_data(c, request(), changed, window(), runtime())
      bad(a.verify(c, other, now(), review, issuer))
    },
  )
  let assert Ok(other) =
    a.context_data(
      c,
      request_with(a.fixed_plan, members(), "another-request-id"),
      b,
      window(),
      runtime(),
    )
  bad(a.verify(c, other, now(), review, issuer))
}

pub fn factual_reviewer_independence_and_roster_bounds_test() {
  let c = configuration()
  let b = bindings()
  bad(a.context_data(
    c,
    request(),
    a.Bindings(..b, factual_reviewer: "not-configured-reviewer"),
    window(),
    runtime(),
  ))
  bad(a.context_data(
    c,
    request(),
    a.Bindings(..b, assessment_actors: ["reviewer-actor"]),
    window(),
    runtime(),
  ))
  bad(a.context_data(
    c,
    request(),
    a.Bindings(..b, assessment_actors: ["actor", "actor"]),
    window(),
    runtime(),
  ))
  bad(a.context_data(
    c,
    request(),
    a.Bindings(..b, assessment_actors: list.repeat("actor", 33)),
    window(),
    runtime(),
  ))
}

pub fn utc_mono_strict_expiry_future_and_vm_domain_refusals_test() {
  let c = configuration()
  let ctx = context(c)
  let #(review, issuer) = tokens(c, ctx)
  let n = now()
  list.each(
    [
      a.Observation(..n, utc_ms: 1_060_000),
      a.Observation(..n, mono_ms: -40_000),
      a.Observation(..n, utc_ms: 999_999),
      a.Observation(..n, mono_ms: -100_001),
      a.Observation(..n, host: "other.tail55d152.ts.net"),
      a.Observation(..n, boot: "reboot"),
      a.Observation(..n, clock_domain: "different-beam-origin"),
    ],
    fn(changed) { bad(a.verify(c, ctx, changed, review, issuer)) },
  )
}

pub fn stalled_utc_reverification_never_refreshes_signed_mono_deadline_test() {
  let c = configuration()
  let ctx = context(c)
  let #(review, issuer) = tokens(c, ctx)
  let assert Ok(first) = a.verify(c, ctx, now(), review, issuer)
  let later = a.Observation(..now(), mono_ms: -40_001)
  let assert Ok(second) = a.verify(c, ctx, later, review, issuer)
  a.evidence_sha256(first) |> should.equal(a.evidence_sha256(second))
  a.expires_mono_ms(first) |> should.equal(a.expires_mono_ms(second))
  bad(a.verify(c, ctx, a.Observation(..later, mono_ms: -40_000), review, issuer))
  a.still_valid(second, c, ctx, now()) |> should.be_false
}

pub fn stateless_evidence_does_not_claim_owner_highwater_or_authority_test() {
  let c = configuration()
  let ctx = context(c)
  let #(review, issuer) = tokens(c, ctx)
  let assert Ok(e) = a.verify(c, ctx, now(), review, issuer)
  a.still_valid(e, c, ctx, a.Observation(..now(), mono_ms: -50_000))
  |> should.be_true
  // Regression from a previously checked -50_000 is NOT globally remembered.
  // The future owner, not this pure proof value, must refuse that regression.
  a.still_valid(e, c, ctx, a.Observation(..now(), mono_ms: -60_000))
  |> should.be_true
  a.authority(e) |> should.equal("NONE")
}

pub fn old_lease_nanosecond_precision_is_conservatively_checked_test() {
  let c = configuration()
  let raw =
    request_raw(a.fixed_plan, members(), "fixture-request")
    |> string.replace("900000000000", "1030000000001")
  let assert Ok(r) = wire.decode(raw)
  let assert Ok(ctx) = a.context_data(c, r, bindings(), window(), runtime())
  let #(review, issuer) = tokens(c, ctx)
  bad(a.verify(c, ctx, now(), review, issuer))
  let assert Ok(e) =
    a.verify(c, ctx, a.Observation(..now(), utc_ms: 1_030_001), review, issuer)
  a.authority(e) |> should.equal("NONE")
}

pub fn configuration_and_context_epoch_rebinding_invalidates_old_evidence_test() {
  let c = configuration()
  let ctx = context(c)
  let #(review, issuer) = tokens(c, ctx)
  let assert Ok(e) = a.verify(c, ctx, now(), review, issuer)
  let assert Ok(other_config) =
    a.configuration_data(
      signer("reviewer"),
      signer("issuer"),
      900_000,
      1_200_000,
      d("b"),
    )
  a.still_valid(e, other_config, ctx, now()) |> should.be_false
  let assert Ok(other) =
    a.context_data(
      c,
      request(),
      bindings(),
      window(),
      a.Runtime(..runtime(), epoch: 110),
    )
  a.still_valid(e, c, other, now()) |> should.be_false
  bad(a.verify(c, other, now(), review, issuer))
}

pub fn windows_cannot_outlive_evidence_native_deadline_or_mono_anchor_test() {
  let c = configuration()
  let w = window()
  list.each(
    [
      a.Window(..w, review_until_utc_ms: 1_059_999),
      a.Window(..w, portfolio_until_utc_ms: 1_059_999),
      a.Window(..w, expires_utc_ms: 1_060_001),
      a.Window(..w, expires_mono_ms: -39_999),
      a.Window(..w, created_utc_ms: 899_999),
      a.Window(..w, created_mono_ms: -40_000),
    ],
    fn(changed) {
      bad(a.context_data(c, request(), bindings(), changed, runtime()))
    },
  )
}

pub fn canonical_native_input_order_does_not_change_signed_request_test() {
  let c = configuration()
  let r = request_with(a.fixed_plan, list.reverse(members()), "fixture-request")
  wire.request_sha256(r) |> should.equal(wire.request_sha256(request()))
  let assert Ok(other) = a.context_data(c, r, bindings(), window(), runtime())
  a.context_sha256(other) |> should.equal(a.context_sha256(context(c)))
}
