//// Pure Ed25519 recovery-evidence verifier, not an issuer or executor.
//// Reuses UOS oidc_jwt_ffi and the exact separately reviewed recovery_wire.
//// This TWO-PARTY PREPARATION profile is NOT a constitutional permission rule.
//// No key creation, signing, key JSON ingress, environment lookup, database,
//// claims, runtime effects or default signer readiness exists in this module.
////
//// ConfigurationData is PUBLICLY CONSTRUCTED UNTRUSTED DATA until a separately
//// admitted launcher authenticates its pinned source/key custody/role mapping.
//// A successful result proves signatures under those supplied keys, NOT that
//// those keys belong to a real authorized issuer/reviewer. Caller clock values
//// likewise do not prove real time. Portfolio/review truth, live task CAS,
//// revocation, epochs, cleanup and replay consumption remain external gates.

import cepaf_gleam/harness/files
import cepaf_gleam/harness/recovery_wire as wire
import gleam/bit_array
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/result
import gleam/string

pub const profile = "RECOVERY_REVIEWER_ISSUER_2KEY_PREPARATION_NOT_ADMITTED"

pub const review_purpose = "uos.sa-plan.recovery.review-evidence.v1"

pub const issuer_purpose = "uos.sa-plan.recovery.issuer-evidence.v1"

pub const fixed_plan = "uos/codex-handover-open-items-fractal-plan/20261031-1240"

const max_utc = 9_223_372_036_854

const max_mono = 9_000_000_000_000_000

const max_window = 600_000

const max_token = 8192

pub type Purpose {
  IndependentReview
  TaskRecoveryIssuer
}

pub type Signer {
  Signer(
    subject: String,
    session: String,
    actor: String,
    kid: String,
    public_key: String,
  )
}

pub opaque type ConfigurationData {
  ConfigurationData(
    reviewer: Signer,
    issuer: Signer,
    loaded_utc_ms: Int,
    expires_utc_ms: Int,
    launcher_source_sha256: String,
    digest: String,
  )
}

pub type Bindings {
  Bindings(
    portfolio_sha256: String,
    selection_sha256: String,
    proposal_sha256: String,
    factual_review_sha256: String,
    factual_reviewer: String,
    assessment_actors: List(String),
    source_sha256: String,
    native_artifact_sha256: String,
    native_worker_sha256: String,
    guardian_sha256: String,
  )
}

pub type Window {
  Window(
    created_utc_ms: Int,
    expires_utc_ms: Int,
    created_mono_ms: Int,
    expires_mono_ms: Int,
    portfolio_until_utc_ms: Int,
    review_until_utc_ms: Int,
  )
}

pub type Runtime {
  Runtime(
    host: String,
    boot: String,
    clock_domain: String,
    resource: String,
    coordinator_holder: String,
    epoch: Int,
  )
}

pub type Observation {
  Observation(
    host: String,
    boot: String,
    clock_domain: String,
    utc_ms: Int,
    mono_ms: Int,
  )
}

pub opaque type Context {
  Context(
    request: wire.FactualRequest,
    bindings: Bindings,
    window: Window,
    runtime: Runtime,
    configuration_sha256: String,
    canonical: String,
    digest: String,
    old_leases_ns: List(Int),
  )
}

pub opaque type VerifiedUnderConfiguration {
  VerifiedUnderConfiguration(
    context_sha256: String,
    request_sha256: String,
    configuration_sha256: String,
    stable_digest: String,
    expires_utc_ms: Int,
    expires_mono_ms: Int,
    verified_utc_ms: Int,
    verified_mono_ms: Int,
  )
}

@external(erlang, "oidc_jwt_ffi", "validate_jwks_snapshot")
fn validate_jwks(raw: String) -> Result(Nil, String)

@external(erlang, "oidc_jwt_ffi", "verify_ed25519_jwt")
fn verify_jwt(token: String, jwks: String) -> Result(String, String)

fn ensure(ok: Bool, reason: String) -> Result(Nil, String) {
  case ok {
    True -> Ok(Nil)
    False -> Error(reason)
  }
}

fn identifier(s: String) -> Bool {
  string.byte_size(s) >= 1
  && string.byte_size(s) <= 160
  && list.all(string.to_utf_codepoints(s), fn(cp) {
    let c = string.utf_codepoint_to_int(cp)
    c >= 33 && c <= 126 && c != 34 && c != 92
  })
}

fn sha(s: String) -> Bool {
  string.byte_size(s) == 64
  && list.all(string.to_graphemes(s), fn(c) {
    string.contains("0123456789abcdef", c)
  })
}

fn tailnet_host(s: String) -> Bool {
  identifier(s)
  && string.ends_with(s, ".tail55d152.ts.net")
  && list.all(string.split(s, "."), fn(label) {
    string.byte_size(label) >= 1
    && string.byte_size(label) <= 63
    && !string.starts_with(label, "-")
    && !string.ends_with(label, "-")
    && list.all(string.to_utf_codepoints(label), fn(cp) {
      let n = string.utf_codepoint_to_int(cp)
      n >= 97 && n <= 122 || n >= 65 && n <= 90 || n >= 48 && n <= 57 || n == 45
    })
  })
}

fn utc(n: Int) -> Bool {
  n >= 0 && n <= max_utc
}

fn mono(n: Int) -> Bool {
  n >= 0 - max_mono && n <= max_mono
}

fn purpose_name(p: Purpose) -> String {
  case p {
    IndependentReview -> review_purpose
    TaskRecoveryIssuer -> issuer_purpose
  }
}

fn signer_for(c: ConfigurationData, p: Purpose) -> Signer {
  case p {
    IndependentReview -> c.reviewer
    TaskRecoveryIssuer -> c.issuer
  }
}

fn signer_json(s: Signer) -> json.Json {
  json.preprocessed_array([
    json.string(s.subject),
    json.string(s.session),
    json.string(s.actor),
    json.string(s.kid),
    json.string(s.public_key),
  ])
}

fn jwks(s: Signer) -> String {
  json.object([
    #(
      "keys",
      json.preprocessed_array([
        json.object([
          #("kty", json.string("OKP")),
          #("crv", json.string("Ed25519")),
          #("kid", json.string(s.kid)),
          #("alg", json.string("EdDSA")),
          #("x", json.string(s.public_key)),
        ]),
      ]),
    ),
  ])
  |> json.to_string
}

/// Construct DATA, not trust. No JSON decoder or automatic key source exists.
/// Production must authenticate these exact bytes from a pinned launcher;
/// this library cannot establish launcher authenticity or actual key custody.
pub fn configuration_data(
  reviewer: Signer,
  issuer: Signer,
  loaded_utc_ms: Int,
  expires_utc_ms: Int,
  launcher_source_sha256: String,
) -> Result(ConfigurationData, String) {
  use _ <- result.try(ensure(
    utc(loaded_utc_ms)
      && utc(expires_utc_ms)
      && expires_utc_ms > loaded_utc_ms
      && expires_utc_ms - loaded_utc_ms <= 3_600_000
      && sha(launcher_source_sha256),
    "configuration_window_or_pin",
  ))
  use _ <- result.try(ensure(
    list.all([reviewer, issuer], fn(s) {
      list.all([s.subject, s.session, s.actor, s.kid], identifier)
      && string.byte_size(s.kid) <= 128
      && string.byte_size(s.public_key) == 43
    })
      && reviewer.subject != issuer.subject
      && reviewer.session != issuer.session
      && reviewer.actor != issuer.actor
      && reviewer.kid != issuer.kid
      && reviewer.public_key != issuer.public_key,
    "signer_alias_or_identity",
  ))
  use _ <- result.try(
    validate_jwks(jwks(reviewer))
    |> result.map_error(fn(_) { "reviewer_key_invalid" }),
  )
  use _ <- result.try(
    validate_jwks(jwks(issuer))
    |> result.map_error(fn(_) { "issuer_key_invalid" }),
  )
  let bytes =
    json.preprocessed_array([
      json.string("uos.sa-plan.recovery.configuration-data.v1"),
      json.string(profile),
      signer_json(reviewer),
      signer_json(issuer),
      json.int(loaded_utc_ms),
      json.int(expires_utc_ms),
      json.string(launcher_source_sha256),
    ])
    |> json.to_string
  Ok(ConfigurationData(
    reviewer,
    issuer,
    loaded_utc_ms,
    expires_utc_ms,
    launcher_source_sha256,
    files.digest(bytes),
  ))
}

pub fn configuration_sha256(c: ConfigurationData) -> String {
  c.digest
}

type NativeOld {
  NativeOld(task: String, worker: String, lease_ns: String)
}

fn project_native(
  r: wire.FactualRequest,
) -> Result(#(String, String, List(NativeOld)), String) {
  let member = {
    use task <- decode.field("task", decode.string)
    use worker <- decode.field("worker", decode.string)
    use lease <- decode.field("lease", decode.string)
    decode.success(NativeOld(task, worker, lease))
  }
  let projection = {
    use plan <- decode.field("plan", decode.string)
    use deadline <- decode.field("deadline", decode.string)
    use members <- decode.field("old", decode.list(member))
    decode.success(#(plan, deadline, members))
  }
  json.parse(wire.canonical_bytes(r), projection)
  |> result.map_error(fn(_) { "native_projection_invalid" })
}

fn fixed_members() -> List(#(String, String)) {
  [
    #(
      "OI02B_ALL_AGENT_SYMBIOSIS_PREFLIGHT",
      "codex-symbiosis-preflight-20261031",
    ),
    #("OI02E_RELEASE_AUTHORITY_PREPARATION", "codex-release-authority-20261031"),
    #("OI02_ATOMIC_11_TARGET_CAPSULE_CUTOVER", "codex-hive-cutover-20261031"),
  ]
}

/// Context is also DATA until its facts, expiry limits and launcher identity
/// have been independently observed. Canonical native request SHA comes ONLY
/// from the opaque reviewed codec, never a supplied digest string.
pub fn context_data(
  c: ConfigurationData,
  request: wire.FactualRequest,
  bindings: Bindings,
  window: Window,
  runtime: Runtime,
) -> Result(Context, String) {
  use #(plan, deadline, members) <- result.try(project_native(request))
  use deadline_ns <- result.try(
    int.parse(deadline) |> result.map_error(fn(_) { "native_deadline" }),
  )
  use leases <- result.try(
    list.try_map(members, fn(m) {
      int.parse(m.lease_ns) |> result.map_error(fn(_) { "native_old_lease" })
    }),
  )
  use _ <- result.try(ensure(
    plan == fixed_plan
      && list.map(members, fn(m) { #(m.task, m.worker) }) == fixed_members()
      && list.all(leases, fn(n) { n > 0 }),
    "fixed_plan_task_worker_scope",
  ))
  use _ <- result.try(ensure(
    list.all(
      [
        bindings.portfolio_sha256,
        bindings.selection_sha256,
        bindings.proposal_sha256,
        bindings.factual_review_sha256,
        bindings.source_sha256,
        bindings.native_artifact_sha256,
        bindings.native_worker_sha256,
        bindings.guardian_sha256,
      ],
      sha,
    ),
    "context_digest_shape",
  ))
  // Bounded prefix before any walk: arbitrary supplied lists cannot cause an
  // unbounded validator traversal. These are DECLARED actors, not proven authors.
  let actors = list.take(bindings.assessment_actors, 33)
  use _ <- result.try(ensure(
    list.length(actors) >= 1
      && list.length(actors) <= 32
      && list.all(actors, identifier)
      && list.length(list.unique(actors)) == list.length(actors)
      && bindings.factual_reviewer == c.reviewer.actor
      && !list.contains(actors, c.reviewer.actor)
      && !list.contains(list.map(members, fn(m) { m.worker }), c.reviewer.actor)
      && !list.contains(
      list.map(members, fn(m) { m.worker }),
      c.reviewer.subject,
    ),
    "reviewer_declared_independence",
  ))
  use _ <- result.try(ensure(
    utc(window.created_utc_ms)
      && utc(window.expires_utc_ms)
      && utc(window.portfolio_until_utc_ms)
      && utc(window.review_until_utc_ms)
      && mono(window.created_mono_ms)
      && mono(window.expires_mono_ms)
      && window.created_utc_ms >= c.loaded_utc_ms
      && window.expires_utc_ms > window.created_utc_ms
      && window.expires_utc_ms - window.created_utc_ms <= max_window
      && window.expires_mono_ms > window.created_mono_ms
      && window.expires_mono_ms - window.created_mono_ms
      <= window.expires_utc_ms - window.created_utc_ms
      && window.expires_utc_ms <= c.expires_utc_ms
      && window.expires_utc_ms <= window.portfolio_until_utc_ms
      && window.expires_utc_ms <= window.review_until_utc_ms
      && window.expires_utc_ms <= deadline_ns / 1_000_000,
    "context_window_bounds",
  ))
  use _ <- result.try(ensure(
    list.all(
      [
        runtime.host,
        runtime.boot,
        runtime.clock_domain,
        runtime.resource,
        runtime.coordinator_holder,
      ],
      identifier,
    )
      && tailnet_host(runtime.host)
      && runtime.epoch > 0
      && runtime.epoch <= 9_000_000_000_000_000,
    "runtime_binding",
  ))
  let normalized =
    Bindings(..bindings, assessment_actors: list.sort(actors, string.compare))
  let bytes = context_json(request, normalized, window, runtime, c.digest)
  Ok(Context(
    request,
    normalized,
    window,
    runtime,
    c.digest,
    bytes,
    files.digest(bytes),
    leases,
  ))
}

fn context_json(
  r: wire.FactualRequest,
  b: Bindings,
  w: Window,
  rt: Runtime,
  config: String,
) -> String {
  json.preprocessed_array([
    json.string("uos.sa-plan.recovery.context.v1"),
    json.string(profile),
    json.string(wire.request_sha256(r)),
    json.string(config),
    json.preprocessed_array(list.map(
      [
        b.portfolio_sha256,
        b.selection_sha256,
        b.proposal_sha256,
        b.factual_review_sha256,
        b.factual_reviewer,
        b.source_sha256,
        b.native_artifact_sha256,
        b.native_worker_sha256,
        b.guardian_sha256,
      ],
      json.string,
    )),
    json.array(b.assessment_actors, json.string),
    json.preprocessed_array(list.map(
      [
        w.created_utc_ms,
        w.expires_utc_ms,
        w.created_mono_ms,
        w.expires_mono_ms,
        w.portfolio_until_utc_ms,
        w.review_until_utc_ms,
      ],
      json.int,
    )),
    json.preprocessed_array(list.map(
      [rt.host, rt.boot, rt.clock_domain, rt.resource, rt.coordinator_holder],
      json.string,
    )),
    json.int(rt.epoch),
  ])
  |> json.to_string
}

pub fn context_sha256(c: Context) -> String {
  c.digest
}

pub fn request_sha256(c: Context) -> String {
  wire.request_sha256(c.request)
}

pub fn canonical_context(c: Context) -> String {
  c.canonical
}

pub fn header_bytes(c: ConfigurationData, p: Purpose) -> String {
  json.object([
    #("alg", json.string("EdDSA")),
    #("kid", json.string(signer_for(c, p).kid)),
    #("typ", json.string("JWT")),
  ])
  |> json.to_string
}

/// Bytes to give a separately authorized managed signer; this function does
/// not sign, approve a factual review, authenticate a launcher, or authorize I/O.
pub fn signing_payload(
  c: ConfigurationData,
  context: Context,
  p: Purpose,
  review_token: String,
) -> Result(String, String) {
  use _ <- result.try(ensure(
    c.digest == context.configuration_sha256
      && string.byte_size(review_token) <= max_token
      && case p {
      IndependentReview -> review_token == ""
      TaskRecoveryIssuer -> review_token != ""
    },
    "payload_binding",
  ))
  let signer = signer_for(c, p)
  Ok(
    json.object([
      #("domain", json.string(purpose_name(p))),
      #("profile", json.string(profile)),
      #("subject", json.string(signer.subject)),
      #("session", json.string(signer.session)),
      #("actor", json.string(signer.actor)),
      #("configuration_sha256", json.string(c.digest)),
      #("request_sha256", json.string(request_sha256(context))),
      #("context_sha256", json.string(context.digest)),
      #("decision", json.string("attest_evidence_only")),
      #("created_utc_ms", json.int(context.window.created_utc_ms)),
      #("expires_utc_ms", json.int(context.window.expires_utc_ms)),
      #("created_mono_ms", json.int(context.window.created_mono_ms)),
      #("expires_mono_ms", json.int(context.window.expires_mono_ms)),
      #(
        "review_token_sha256",
        json.string(case p {
          IndependentReview -> ""
          TaskRecoveryIssuer -> files.digest(review_token)
        }),
      ),
    ])
    |> json.to_string,
  )
}

fn token_matches(
  c: ConfigurationData,
  context: Context,
  p: Purpose,
  token: String,
  review_token: String,
) -> Result(Nil, String) {
  use _ <- result.try(ensure(
    string.byte_size(token) >= 1 && string.byte_size(token) <= max_token,
    "token_bound",
  ))
  let expected_header =
    header_bytes(c, p)
    |> bit_array.from_string
    |> bit_array.base64_url_encode(False)
  use _ <- result.try(ensure(
    case string.split(token, ".") {
      [header, _, _] -> header == expected_header
      _ -> False
    },
    "canonical_header",
  ))
  use payload <- result.try(
    verify_jwt(token, jwks(signer_for(c, p)))
    |> result.map_error(fn(_) { "signature_or_strict_json_invalid" }),
  )
  use expected <- result.try(signing_payload(c, context, p, review_token))
  ensure(payload == expected, "noncanonical_or_mismatched_signed_claims")
}

fn valid_clock(
  c: ConfigurationData,
  context: Context,
  now: Observation,
) -> Bool {
  let w = context.window
  now.host == context.runtime.host
  && now.boot == context.runtime.boot
  && now.clock_domain == context.runtime.clock_domain
  && utc(now.utc_ms)
  && mono(now.mono_ms)
  && now.utc_ms >= w.created_utc_ms
  && now.utc_ms < w.expires_utc_ms
  && now.mono_ms >= w.created_mono_ms
  && now.mono_ms < w.expires_mono_ms
  && now.utc_ms >= c.loaded_utc_ms
  && now.utc_ms < c.expires_utc_ms
  && list.all(context.old_leases_ns, fn(n) { n <= now.utc_ms * 1_000_000 })
}

/// Signature validity under supplied configuration, never a GrantTicket.
pub fn verify(
  c: ConfigurationData,
  context: Context,
  now: Observation,
  reviewer_token: String,
  issuer_token: String,
) -> Result(VerifiedUnderConfiguration, String) {
  use _ <- result.try(ensure(
    c.digest == context.configuration_sha256,
    "configuration_changed",
  ))
  use _ <- result.try(ensure(
    valid_clock(c, context, now),
    "clock_domain_or_window",
  ))
  use _ <- result.try(token_matches(
    c,
    context,
    IndependentReview,
    reviewer_token,
    "",
  ))
  use _ <- result.try(token_matches(
    c,
    context,
    TaskRecoveryIssuer,
    issuer_token,
    reviewer_token,
  ))
  let digest =
    json.preprocessed_array([
      json.string(profile),
      json.string(context.digest),
      json.string(c.digest),
      json.string(files.digest(reviewer_token)),
      json.string(files.digest(issuer_token)),
    ])
    |> json.to_string
    |> files.digest
  Ok(VerifiedUnderConfiguration(
    context.digest,
    request_sha256(context),
    c.digest,
    digest,
    context.window.expires_utc_ms,
    context.window.expires_mono_ms,
    now.utc_ms,
    now.mono_ms,
  ))
}

pub fn evidence_sha256(e: VerifiedUnderConfiguration) -> String {
  e.stable_digest
}

pub fn verified_request_sha256(e: VerifiedUnderConfiguration) -> String {
  e.request_sha256
}

pub fn expires_mono_ms(e: VerifiedUnderConfiguration) -> Int {
  e.expires_mono_ms
}

pub fn authority(_e: VerifiedUnderConfiguration) -> String {
  "NONE"
}

/// Stateless freshness relative to THIS observation only. Evidence aliases are
/// not linear: an owner must retain its own UTC/mono high-water and current
/// config/epoch/revocation state. A->B->A source/config reuse is not prevented
/// here. Neither this function nor signature re-verification may rearm effects.
pub fn still_valid(
  e: VerifiedUnderConfiguration,
  c: ConfigurationData,
  context: Context,
  now: Observation,
) -> Bool {
  c.digest == e.configuration_sha256
  && context.digest == e.context_sha256
  && now.utc_ms >= e.verified_utc_ms
  && now.mono_ms >= e.verified_mono_ms
  && valid_clock(c, context, now)
}
