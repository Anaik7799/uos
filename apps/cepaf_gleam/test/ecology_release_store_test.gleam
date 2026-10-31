import cepaf_gleam/ecology/release_store as store
import cepaf_gleam/harness/files
import cepaf_gleam/harness/telegram_store_transport as transport
import envoy
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should

fn h() -> String {
  "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
}

fn digest() -> String {
  "sha256:" <> h()
}

fn binding() -> store.Binding {
  store.Binding("grant-1", digest(), digest(), digest(), 2000)
}

fn config() -> transport.LocalConfiguration {
  transport.reviewed_local_configuration(
    "/fixture/guardian",
    h(),
    "/fixture/worker",
    h(),
    "/fixture/private.sqlite3",
  )
}

fn client() -> store.Client {
  let assert Ok(client) = store.new_client(config(), binding())
  client
}

fn issue_hash(id: String, b: store.Binding) -> String {
  "sha256:"
  <> files.digest(
    "{\"approval_digest\":\""
    <> b.approval_digest
    <> "\",\"expires_utc_ms\":"
    <> int.to_string(b.expires_utc_ms)
    <> ",\"grant_id\":\""
    <> b.grant_id
    <> "\",\"intent_digest\":\""
    <> b.intent_digest
    <> "\",\"operation\":\"issue\",\"owner_binding_digest\":\""
    <> b.owner_binding_digest
    <> "\",\"request_id\":\""
    <> id
    <> "\",\"schema_version\":1}",
  )
}

fn consume_hash(
  id: String,
  b: store.Binding,
  step: String,
  command: String,
) -> String {
  "sha256:"
  <> files.digest(
    "{\"command\":\""
    <> command
    <> "\",\"epoch\":1,\"generation\":0,\"grant_id\":\""
    <> b.grant_id
    <> "\",\"operation\":\"consume\",\"request_id\":\""
    <> id
    <> "\",\"schema_version\":1,\"step_digest\":\""
    <> step
    <> "\"}",
  )
}

fn revoke_hash(id: String, b: store.Binding) -> String {
  "sha256:"
  <> files.digest(
    "{\"grant_id\":\""
    <> b.grant_id
    <> "\",\"operation\":\"revoke\",\"reason\":\"operator_revoked\",\"request_id\":\""
    <> id
    <> "\",\"schema_version\":1}",
  )
}

fn grant(b: store.Binding, revoked: Bool) -> json.Json {
  json.object([
    #("grant_id", json.string(b.grant_id)),
    #("intent_digest", json.string(b.intent_digest)),
    #("approval_digest", json.string(b.approval_digest)),
    #("owner_binding_digest", json.string(b.owner_binding_digest)),
    #("issued_utc_ms", json.int(1000)),
    #("expires_utc_ms", json.int(b.expires_utc_ms)),
    #("issue_request_id", json.string("issue-1")),
    #("issue_request_digest", json.string(issue_hash("issue-1", b))),
    #("issue_event_index", json.int(1)),
    #("revoked", json.bool(revoked)),
    #("revoked_reason", case revoked {
      True -> json.string("operator_revoked")
      False -> json.null()
    }),
    #("revoked_utc_ms", case revoked {
      True -> json.int(1600)
      False -> json.null()
    }),
    #("revoke_request_id", case revoked {
      True -> json.string("revoke-1")
      False -> json.null()
    }),
    #("revoke_event_index", case revoked {
      True -> json.int(3)
      False -> json.null()
    }),
    #("expired", json.bool(False)),
  ])
}

fn step(id: String, command: String) -> json.Json {
  json.object([
    #("request_id", json.string(id)),
    #(
      "request_digest",
      json.string(consume_hash(id, binding(), digest(), command)),
    ),
    #("event_index", json.int(2)),
    #("step_digest", json.string(digest())),
    #("epoch", json.int(1)),
    #("generation", json.int(0)),
    #("command", json.string(command)),
    #("consumed_utc_ms", json.int(1500)),
  ])
}

fn reply(
  status: String,
  id: json.Json,
  hash: json.Json,
  event: json.Json,
  grant: json.Json,
  step: json.Json,
) -> String {
  json.object([
    #("schema_version", json.int(1)),
    #("authority", json.string("NONE")),
    #("authorized", json.bool(False)),
    #("admitted", json.bool(False)),
    #("new_effect_permission", json.bool(False)),
    #("status", json.string(status)),
    #("request_id", id),
    #("request_digest", hash),
    #("event_index", event),
    #("observed_utc_ms", json.int(1700)),
    #("grant", grant),
    #("step", step),
    #("reason", json.null()),
  ])
  |> json.to_string
}

fn issued() -> String {
  reply(
    "issued",
    json.string("issue-1"),
    json.string(issue_hash("issue-1", binding())),
    json.int(1),
    grant(binding(), False),
    json.null(),
  )
}

fn consumed(status: String, id: String, command: String) -> String {
  reply(
    status,
    json.string(id),
    json.string(consume_hash(id, binding(), digest(), command)),
    json.int(2),
    grant(binding(), False),
    step(id, command),
  )
}

fn paired(raw: String) -> store.Exchange {
  store.Exchange(Ok(raw), store.Reaped(0, 1_700_001))
}

pub fn canonical_request_and_explicit_digest_tag_test() {
  store.tag_digest(h()) |> should.equal(Ok(digest()))
  store.tag_digest(digest()) |> should.equal(Ok(digest()))
  store.tag_digest("SHA256:" <> h()) |> should.equal(Error(store.InvalidDigest))
  store.request_digest(binding(), store.Issue("issue-1"))
  |> should.equal(Ok(issue_hash("issue-1", binding())))
  store.request_digest(
    binding(),
    store.Consume("consume-1", digest(), 1, 0, store.Stage),
  )
  |> should.equal(Ok(consume_hash("consume-1", binding(), digest(), "stage")))
}

pub fn malformed_request_refuses_before_io_test() {
  let result =
    store.request_with(
      client(),
      store.Consume("id", digest(), 1, 0, store.Replace(15)),
      fn(_) { panic as "invalid request performed IO" },
    )
  result.result |> should.equal(store.RequestInvalid(store.InvalidRequest))
  store.phase(result.client) |> should.equal(store.Ready)
}

pub fn issue_facts_not_authority_test() {
  let result =
    store.request_with(client(), store.Issue("issue-1"), fn(_) {
      paired(issued())
    })
  let assert store.Issued(fact, 1700) = result.result
  fact.binding |> should.equal(binding())
  fact.revocation |> should.equal(None)
  fact.expired |> should.be_false
  store.cleanup(result.client) |> should.equal(store.Reaped(0, 1_700_001))
}

pub fn fresh_consumption_requires_exact_request_identity_test() {
  let result =
    store.request_with(
      client(),
      store.Consume("consume-NEW", digest(), 1, 0, store.Stage),
      fn(_) { paired(consumed("consumed", "consume-1", "stage")) },
    )
  result.result |> should.equal(store.ProtocolUncertain)
  store.phase(result.client) |> should.equal(store.NeedsReconciliation)
}

pub fn historical_consumption_keeps_original_identity_test() {
  let result =
    store.request_with(
      client(),
      store.Consume("consume-NEW", digest(), 1, 0, store.Stage),
      fn(_) { paired(consumed("already_consumed", "consume-1", "stage")) },
    )
  let assert store.AlreadyConsumed(_, fact, _) = result.result
  fact.event.request_id |> should.equal("consume-1")
  store.phase(result.client) |> should.equal(store.Ready)
}

pub fn unknown_ack_only_exact_readonly_lookup_test() {
  let pending =
    store.request_with(
      client(),
      store.Consume("consume-1", digest(), 1, 0, store.Stage),
      fn(_) {
        store.Exchange(Error(transport.Uncertain), store.Reaped(124, 1_700_001))
      },
    )
  store.phase(pending.client) |> should.equal(store.NeedsReconciliation)
  let blocked =
    store.request_with(
      pending.client,
      store.Consume("consume-1", digest(), 1, 0, store.Stage),
      fn(_) { panic as "consume was resent after unknown ACK" },
    )
  blocked.result |> should.equal(store.RequestBlocked)
  let wrong =
    store.request_with(pending.client, store.Lookup(None), fn(_) {
      panic as "wrong lookup performed IO"
    })
  wrong.result |> should.equal(store.RequestBlocked)
  let found =
    reply(
      "found",
      json.null(),
      json.null(),
      json.null(),
      grant(binding(), False),
      step("consume-1", "stage"),
    )
  let result =
    store.request_with(pending.client, store.Lookup(Some(digest())), fn(_) {
      paired(found)
    })
  let assert store.Found(_, Some(_), _) = result.result
  store.phase(result.client) |> should.equal(store.NeedsReconciliation)
  let blocked_again =
    store.request_with(result.client, store.Issue("other"), fn(_) {
      panic as "historical lookup rearmed mutation"
    })
  blocked_again.result |> should.equal(store.RequestBlocked)
}

pub fn missing_reap_witness_fences_even_lookup_test() {
  let result =
    store.request_with(client(), store.Issue("issue-1"), fn(_) {
      store.Exchange(Ok(issued()), store.Unconfirmed)
    })
  result.result |> should.equal(store.CleanupFenced)
  store.phase(result.client) |> should.equal(store.UnconfirmedCleanup)
  let blocked =
    store.request_with(result.client, store.Lookup(None), fn(_) {
      panic as "lookup ran without reap witness"
    })
  blocked.result |> should.equal(store.RequestBlocked)
}

pub fn bad_exit_or_false_authority_refuses_test() {
  let wrong_exit =
    store.request_with(client(), store.Issue("issue-1"), fn(_) {
      store.Exchange(Ok(issued()), store.Reaped(124, 1_700_001))
    })
  wrong_exit.result |> should.equal(store.CleanupFenced)
  let forged =
    store.request_with(client(), store.Issue("issue-1"), fn(_) {
      paired(string.replace(
        issued(),
        "\"authorized\":false",
        "\"authorized\":true",
      ))
    })
  forged.result |> should.equal(store.ProtocolUncertain)
}

pub fn duplicate_unknown_float_and_oversized_body_refuse_test() {
  let bodies = [
    string.replace(
      issued(),
      "\"schema_version\":1",
      "\"schema_version\":1,\"schema_version\":1",
    ),
    string.replace(
      issued(),
      "\"authority\":\"NONE\"",
      "\"authority\":\"NONE\",\"extra\":false",
    ),
    string.replace(issued(), "\"event_index\":1", "\"event_index\":1.0"),
    string.repeat(" ", store.max_response_bytes + 1),
  ]
  list.each(bodies, fn(raw) {
    store.request_with(client(), store.Issue("issue-1"), fn(_) { paired(raw) }).result
    |> should.equal(store.ProtocolUncertain)
  })
}

pub fn foreign_grant_or_noncanonical_command_refuses_test() {
  let foreign =
    string.replace(
      issued(),
      "\"grant_id\":\"grant-1\"",
      "\"grant_id\":\"foreign\"",
    )
  store.request_with(client(), store.Issue("issue-1"), fn(_) { paired(foreign) }).result
  |> should.equal(store.ProtocolUncertain)
  let noncanonical = consumed("consumed", "consume-1", "replace:00")
  store.request_with(
    client(),
    store.Consume("consume-1", digest(), 1, 0, store.Replace(0)),
    fn(_) { paired(noncanonical) },
  ).result
  |> should.equal(store.ProtocolUncertain)
}

pub fn historical_revocation_preserves_original_reason_test() {
  let raw =
    reply(
      "already_revoked",
      json.string("revoke-1"),
      json.string(revoke_hash("revoke-1", binding())),
      json.int(3),
      grant(binding(), True),
      json.null(),
    )
  let result =
    store.request_with(
      client(),
      store.Revoke("new-id", store.Containment),
      fn(_) { paired(raw) },
    )
  let assert store.AlreadyRevoked(fact, _) = result.result
  let assert Some(revocation) = fact.revocation
  revocation.reason |> should.equal(store.OperatorRevoked)
}

pub fn every_authority_flag_and_foreign_issue_replay_refuses_test() {
  list.each(
    [
      #("\"authority\":\"NONE\"", "\"authority\":\"RELEASE\""),
      #("\"authorized\":false", "\"authorized\":true"),
      #("\"admitted\":false", "\"admitted\":true"),
      #("\"new_effect_permission\":false", "\"new_effect_permission\":true"),
    ],
    fn(change) {
      store.request_with(client(), store.Issue("issue-1"), fn(_) {
        paired(string.replace(issued(), change.0, change.1))
      }).result
      |> should.equal(store.ProtocolUncertain)
    },
  )
  let replay =
    string.replace(
      issued(),
      "\"status\":\"issued\"",
      "\"status\":\"issue_replayed\"",
    )
  store.request_with(client(), store.Issue("foreign-request"), fn(_) {
    paired(replay)
  }).result
  |> should.equal(store.ProtocolUncertain)
}

fn native_error(status: String, reason: String) -> String {
  json.object([
    #("schema_version", json.int(1)),
    #("authority", json.string("NONE")),
    #("authorized", json.bool(False)),
    #("admitted", json.bool(False)),
    #("new_effect_permission", json.bool(False)),
    #("status", json.string(status)),
    #("request_id", json.null()),
    #("request_digest", json.null()),
    #("event_index", json.null()),
    #("observed_utc_ms", json.null()),
    #("grant", json.null()),
    #("step", json.null()),
    #("reason", json.string(reason)),
  ])
  |> json.to_string
}

pub fn strict_unknown_error_and_cleanup_exit_classification_test() {
  let unknown =
    store.request_with(client(), store.Issue("issue-1"), fn(_) {
      paired(native_error("unknown", "commit_unknown"))
    })
  unknown.result |> should.equal(store.NativeUnknown(store.CommitUnknown))
  store.phase(unknown.client) |> should.equal(store.NeedsReconciliation)
  list.each(
    [
      native_error("hold", "commit_unknown"),
      native_error("unknown", "invalid_request"),
      native_error("hold", "invented_error"),
      string.replace(
        native_error("hold", "expired"),
        "\"observed_utc_ms\":null",
        "\"observed_utc_ms\":1700",
      ),
    ],
    fn(raw) {
      store.request_with(client(), store.Issue("issue-1"), fn(_) { paired(raw) }).result
      |> should.equal(store.ProtocolUncertain)
    },
  )
  let fenced =
    store.request_with(client(), store.Issue("issue-1"), fn(_) {
      store.Exchange(Error(transport.Uncertain), store.Reaped(126, 1_700_001))
    })
  fenced.result |> should.equal(store.CleanupFenced)
}

fn env(key: String) -> String {
  let assert Ok(value) = envoy.get(key)
  value
}

/// This test MUST run with an actual pinned native worker and private DB.
/// Missing fixture configuration fails; it never becomes a passing skip.
pub fn native_worker_issue_consume_revoke_lookup_test() {
  let database = env("UOS_RELEASE_TEST_DATABASE")
  string.starts_with(
    database,
    "/home/an/NAS-setup/uos/var/harness/20261031-1334-codex-hive/release-authority-proof/native-fixtures/",
  )
  |> should.be_true
  let assert Ok(expires) = int.parse(env("UOS_RELEASE_TEST_EXPIRES_MS"))
  let b = store.Binding("native-grant-1", digest(), digest(), digest(), expires)
  let c =
    transport.reviewed_local_configuration(
      env("UOS_RELEASE_TEST_GUARDIAN"),
      env("UOS_RELEASE_TEST_GUARDIAN_SHA"),
      env("UOS_RELEASE_TEST_WORKER"),
      env("UOS_RELEASE_TEST_WORKER_SHA"),
      database,
    )
  let assert Ok(c) = store.new_client(c, b)
  let issued = store.request(c, store.Issue("native-issue-1"))
  let assert store.Issued(_, _) = issued.result
  let consumed =
    store.request(
      issued.client,
      store.Consume("native-consume-1", digest(), 1, 0, store.Stage),
    )
  let assert store.Consumed(_, original, _) = consumed.result
  let replay =
    store.request(
      consumed.client,
      store.Consume("native-consume-NEW", digest(), 1, 0, store.Stage),
    )
  let assert store.AlreadyConsumed(_, historical, _) = replay.result
  historical.event |> should.equal(original.event)
  let revoked =
    store.request(
      replay.client,
      store.Revoke("native-revoke-1", store.OperatorRevoked),
    )
  let assert store.Revoked(fact, _) = revoked.result
  { fact.revocation != None } |> should.be_true
  let refused =
    store.request(
      revoked.client,
      store.Consume(
        "native-consume-2",
        "sha256:" <> string.repeat("b", 64),
        1,
        1,
        store.FenceReaders,
      ),
    )
  refused.result |> should.equal(store.Held(store.RevokedGrant))
  let found = store.request(refused.client, store.Lookup(Some(digest())))
  let assert store.Found(fact, Some(saved), _) = found.result
  { fact.revocation != None } |> should.be_true
  saved.event |> should.equal(original.event)
}

pub fn native_worker_hash_mismatch_fences_actual_transport_test() {
  let database = env("UOS_RELEASE_TEST_DATABASE") <> ".bad-hash"
  string.starts_with(
    database,
    "/home/an/NAS-setup/uos/var/harness/20261031-1334-codex-hive/release-authority-proof/native-fixtures/",
  )
  |> should.be_true
  let assert Ok(expires) = int.parse(env("UOS_RELEASE_TEST_EXPIRES_MS"))
  let config =
    transport.reviewed_local_configuration(
      env("UOS_RELEASE_TEST_GUARDIAN"),
      env("UOS_RELEASE_TEST_GUARDIAN_SHA"),
      env("UOS_RELEASE_TEST_WORKER"),
      string.repeat("0", 64),
      database,
    )
  let assert Ok(c) =
    store.new_client(
      config,
      store.Binding("bad-hash-grant", digest(), digest(), digest(), expires),
    )
  let result = store.request(c, store.Issue("bad-hash-issue"))
  result.result |> should.equal(store.CleanupFenced)
  store.phase(result.client) |> should.equal(store.UnconfirmedCleanup)
  store.request_with(result.client, store.Lookup(None), fn(_) {
    panic as "actual transport cleanup uncertainty allowed new lookup"
  }).result
  |> should.equal(store.RequestBlocked)
}
