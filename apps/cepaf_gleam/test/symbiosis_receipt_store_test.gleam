//// LOCAL Codex relay tests. Real-worker tests REQUIRE explicit reviewed fixture
//// executable paths/hashes in environment; absence is a failure, never a skip.
//// Every database is a fresh private synthetic /tmp fixture, not a live store.

import cepaf_gleam/ecology/symbiosis_receipt_store as store
import cepaf_gleam/harness/telegram_store_transport as transport
import envoy
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import gleeunit/should
import simplifile
import uos_swarm/symbiosis_preflight as policy

@external(erlang, "erlang", "iolist_to_binary")
fn hostile_bytes(xs: List(Int)) -> String

@external(erlang, "telegram_store_transport_ffi", "request_config_with_cleanup")
fn actual_paired_exchange(
  config: transport.LocalConfiguration,
  body: String,
) -> #(Result(String, String), Option(#(Int, Int)))

fn completed(raw: String) -> store.Exchange {
  store.Exchange(Ok(raw), store.Reaped(0, 1_793_471_000_000_000))
}

fn binding() -> policy.Binding {
  policy.Binding(
    string.repeat("a", 40),
    string.repeat("b", 64),
    "fixture-session",
  )
}

fn request() -> policy.Request {
  policy.Request(
    1,
    policy.Codex,
    policy.CapabilityProbe(policy.KnowledgeRead),
    binding(),
    -1000,
  )
}

fn observation() -> policy.Observation {
  policy.Observation(
    1,
    binding(),
    -990,
    10,
    policy.Results(Some(True), Some(True), Some(True)),
    policy.ProbeFailed,
  )
}

fn context() -> store.Context {
  store.Context(
    "receipt-1",
    "operation-1",
    "owner-1",
    1,
    "fixture-mono-domain",
    1_793_471_000_000_000,
    0,
  )
}

fn intent() -> store.Intent {
  let assert Ok(i) = store.prepare(context(), request(), observation(), None)
  i
}

fn leaf(a: policy.Agent, id: String, at: Int) -> policy.ServiceObservation {
  let d = policy.ServiceDimension(True, at)
  policy.ServiceObservation(a, id, binding(), d, d, d)
}

fn proof() -> policy.CoverageEvidence {
  policy.CoverageEvidence(policy.Codex, binding(), [
    leaf(policy.Codex, "z-service", -995),
    leaf(policy.Codex, "a-service", -996),
  ])
}

fn response(i: store.Intent, status: String) -> String {
  "{\"schema_version\":1,\"authority\":\"NONE\",\"admitted\":false,\"status\":\""
  <> status
  <> "\",\"record_index\":1,\"receipt_id\":\""
  <> store.receipt_id(i)
  <> "\",\"payload_sha256\":\""
  <> store.payload_sha256(i)
  <> "\"}"
}

fn found(i: store.Intent) -> String {
  "{\"schema_version\":1,\"authority\":\"NONE\",\"admitted\":false,\"status\":\"found\",\"stored\":{\"record_index\":1,\"receipt_id\":\""
  <> store.receipt_id(i)
  <> "\",\"payload_sha256\":\""
  <> store.payload_sha256(i)
  <> "\",\"receipt\":"
  <> store.canonical_receipt(i)
  <> "}}"
}

fn uncertain(i: store.Intent) -> store.Intent {
  // Inject a timeout with confirmed cleanup, rather than an unknown process.
  store.submit_with(i, fn(_) {
    store.Exchange(
      Error(transport.Uncertain),
      store.Reaped(124, 1_793_471_000_000_000),
    )
  }).intent
}

fn cannot_exchange(_: String) -> store.Exchange {
  panic as "blocked state must not invoke transport"
}

fn protocol_refuses(i: store.Intent, raw: String) {
  let t = store.submit_with(i, fn(_) { completed(raw) })
  t.outcome |> should.equal(store.ProtocolUncertain)
  store.phase(t.intent) |> should.equal(store.NeedsReconciliation)
  store.acknowledgement(t.intent) |> should.equal(None)
}

pub fn raw_assertions_never_ready_test() {
  let i = intent()
  string.contains(store.canonical_receipt(i), "\"status\":\"unknown\"")
  |> should.be_true
  string.contains(store.canonical_receipt(i), "ready_scoped") |> should.be_false
  list.each([policy.Function, policy.Performance, policy.Operation], fn(d) {
    let values = case d {
      policy.Function -> policy.Results(Some(False), Some(True), Some(True))
      policy.Performance -> policy.Results(Some(True), Some(False), Some(True))
      policy.Operation -> policy.Results(Some(True), Some(True), Some(False))
    }
    let assert Ok(i) =
      store.prepare(
        context(),
        request(),
        policy.Observation(..observation(), results: values),
        None,
      )
    string.contains(store.canonical_receipt(i), "\"status\":\"stop\"")
    |> should.be_true
  })
  let assert Ok(missing) =
    store.prepare(
      context(),
      request(),
      policy.Observation(
        ..observation(),
        results: policy.Results(None, None, None),
      ),
      None,
    )
  string.contains(
    store.canonical_receipt(missing),
    "\"reason\":\"missing_dimension\"",
  )
  |> should.be_true
  let assert Ok(expired) =
    store.prepare(
      store.Context(..context(), expires_mono_ms: -995),
      request(),
      observation(),
      None,
    )
  string.contains(store.canonical_receipt(expired), "\"reason\":\"stale\"")
  |> should.be_true
}

// Finite cross-product: all four agents, eight functional classes and all 27
// ternary dimension combinations. This is not proof of collector truth.
pub fn finite_raw_status_cross_product_test() {
  let values = [None, Some(False), Some(True)]
  list.each(policy.agents(), fn(a) {
    list.each(policy.capabilities(), fn(cap) {
      list.each(values, fn(f) {
        list.each(values, fn(p) {
          list.each(values, fn(op) {
            let assert Ok(i) =
              store.prepare(
                context(),
                policy.Request(
                  ..request(),
                  agent: a,
                  probe: policy.CapabilityProbe(cap),
                ),
                policy.Observation(
                  ..observation(),
                  results: policy.Results(f, p, op),
                ),
                None,
              )
            let payload = store.canonical_receipt(i)
            string.contains(payload, "ready_scoped") |> should.be_false
            case f == Some(False) || p == Some(False) || op == Some(False) {
              True ->
                string.contains(payload, "\"status\":\"stop\"")
                |> should.be_true
              False ->
                string.contains(payload, "\"status\":\"unknown\"")
                |> should.be_true
            }
          })
        })
      })
    })
  })
}

pub fn identity_hash_binding_test() {
  let original = intent()
  list.each(
    [
      store.Context(..context(), receipt_id: "other-receipt"),
      store.Context(..context(), operation_id: "other-operation"),
      store.Context(..context(), owner_id: "other-owner"),
      store.Context(..context(), owner_epoch: 2),
      store.Context(..context(), clock_domain: "other-clock"),
      store.Context(..context(), observed_utc_us: context().observed_utc_us + 1),
      store.Context(..context(), expires_mono_ms: 1),
    ],
    fn(c) {
      let assert Ok(i) = store.prepare(c, request(), observation(), None)
      { store.payload_sha256(i) != store.payload_sha256(original) }
      |> should.be_true
    },
  )
  list.each(
    [
      policy.Binding(..binding(), candidate: string.repeat("c", 40)),
      policy.Binding(..binding(), config: string.repeat("d", 64)),
      policy.Binding(..binding(), session: "other-session"),
    ],
    fn(b) {
      let assert Ok(i) =
        store.prepare(
          context(),
          policy.Request(..request(), binding: b),
          policy.Observation(..observation(), binding: b),
          None,
        )
      { store.payload_sha256(i) != store.payload_sha256(original) }
      |> should.be_true
    },
  )
  let assert Ok(i) = store.prepare(context(), request(), observation(), None)
  store.canonical_receipt(i) |> should.equal(store.canonical_receipt(original))
  store.payload_sha256(i) |> should.equal(store.payload_sha256(original))
}

pub fn context_and_observation_guards_test() {
  list.each(
    [
      store.Context(..context(), receipt_id: "../unsafe\u{0}"),
      store.Context(..context(), receipt_id: string.repeat("a", 257)),
      store.Context(..context(), operation_id: "not an identifier"),
      store.Context(..context(), owner_epoch: -1),
      store.Context(..context(), observed_utc_us: 0),
      store.Context(..context(), observed_utc_us: 9_000_000_000_000_001),
      store.Context(..context(), expires_mono_ms: 9_000_000_000_001),
    ],
    fn(c) {
      store.prepare(c, request(), observation(), None)
      |> should.equal(Error(store.InvalidContext))
    },
  )
  list.each(
    [
      policy.Observation(..observation(), seq: 2),
      policy.Observation(..observation(), elapsed_ms: 11),
      policy.Observation(..observation(), observed_ms: -1001, elapsed_ms: -1),
      policy.Observation(
        ..observation(),
        binding: policy.Binding(..binding(), session: "other"),
      ),
    ],
    fn(o) {
      store.prepare(context(), request(), o, None)
      |> should.equal(Error(store.InvalidObservation))
    },
  )
  store.prepare(
    store.Context(..context(), expires_mono_ms: -1001),
    request(),
    observation(),
    None,
  )
  |> should.equal(Error(store.InvalidObservation))
  store.prepare(
    context(),
    policy.Request(..request(), seq: 0),
    observation(),
    None,
  )
  |> should.equal(Error(store.InvalidObservation))
  store.prepare(
    context(),
    policy.Request(
      ..request(),
      binding: policy.Binding(..binding(), candidate: string.repeat("A", 40)),
    ),
    observation(),
    None,
  )
  |> should.equal(Error(store.InvalidContext))
}

pub fn coverage_canonical_order_and_identity_test() {
  let r = policy.Request(..request(), probe: policy.CoverageProbe)
  let p = proof()
  let assert Ok(a) = store.prepare(context(), r, observation(), Some(p))
  let assert Ok(b) =
    store.prepare(
      context(),
      r,
      observation(),
      Some(policy.CoverageEvidence(..p, services: list.reverse(p.services))),
    )
  store.payload_sha256(a) |> should.equal(store.payload_sha256(b))
  store.canonical_receipt(a) |> should.equal(store.canonical_receipt(b))
  string.contains(store.canonical_receipt(a), "\"status\":\"unknown\"")
  |> should.be_true
  list.each(
    [
      policy.CoverageEvidence(..p, agent: policy.Pi),
      policy.CoverageEvidence(..p, services: []),
      policy.CoverageEvidence(..p, services: [leaf(policy.Pi, "a", -995)]),
      policy.CoverageEvidence(..p, services: [
        leaf(policy.Codex, "a", -995),
        leaf(policy.Codex, "a", -996),
      ]),
      policy.CoverageEvidence(..p, services: [leaf(policy.Codex, "a", -989)]),
      policy.CoverageEvidence(
        ..p,
        binding: policy.Binding(..binding(), session: "other"),
      ),
    ],
    fn(p) {
      store.prepare(context(), r, observation(), Some(p))
      |> should.equal(Error(store.InvalidCoverage))
    },
  )
  store.prepare(context(), request(), observation(), Some(p))
  |> should.equal(Error(store.InvalidCoverage))
  let bad =
    policy.ServiceObservation(
      ..leaf(policy.Codex, "failed", -995),
      operation: policy.ServiceDimension(False, -995),
    )
  let assert Ok(f) =
    store.prepare(
      context(),
      r,
      observation(),
      Some(policy.CoverageEvidence(..p, services: [bad])),
    )
  string.contains(store.canonical_receipt(f), "\"status\":\"stop\"")
  |> should.be_true
}

pub fn coverage_capacity_test() {
  let services =
    list.repeat(Nil, 256)
    |> list.index_map(fn(_, i) {
      leaf(policy.Codex, "service-" <> int.to_string(i), -995)
    })
  let r = policy.Request(..request(), probe: policy.CoverageProbe)
  let p = policy.CoverageEvidence(policy.Codex, binding(), services)
  let assert Ok(i) = store.prepare(context(), r, observation(), Some(p))
  { string.byte_size(store.canonical_receipt(i)) < store.max_request_bytes }
  |> should.be_true
  store.prepare(
    context(),
    r,
    observation(),
    Some(
      policy.CoverageEvidence(..p, services: [
        leaf(policy.Codex, "extra", -995),
        ..services
      ]),
    ),
  )
  |> should.equal(Error(store.InvalidCoverage))
}

pub fn closed_append_response_and_blocking_test() {
  let i = intent()
  list.each(
    [#("stored", store.Stored), #("replayed", store.Replayed)],
    fn(pair) {
      let t = store.submit_with(i, fn(_) { completed(response(i, pair.0)) })
      t.outcome |> should.equal(pair.1)
      store.phase(t.intent) |> should.equal(store.Acknowledged)
      store.acknowledgement(t.intent)
      |> should.equal(
        Some(store.Acknowledgement(
          1,
          store.receipt_id(i),
          store.payload_sha256(i),
          1,
        )),
      )
      store.submit_with(t.intent, cannot_exchange).outcome
      |> should.equal(store.SubmitBlocked)
      store.reconcile_with(t.intent, cannot_exchange).outcome
      |> should.equal(store.SubmitBlocked)
    },
  )
  let uncertain = uncertain(i)
  store.submit_with(uncertain, cannot_exchange).outcome
  |> should.equal(store.SubmitBlocked)
  store.reconcile_with(i, cannot_exchange).outcome
  |> should.equal(store.SubmitBlocked)
}

pub fn hostile_response_controls_test() {
  let i = intent()
  let valid = response(i, "stored")
  list.each(
    [
      "",
      "{}",
      valid <> "true",
      "[" <> valid <> "]",
      string.replace(valid, "\"stored\"", "\"ready_scoped\""),
      string.replace(valid, "\"admitted\":false", "\"admitted\":true"),
      string.replace(valid, "\"NONE\"", "\"SOVEREIGN\""),
      string.replace(
        valid,
        "\"schema_version\":1",
        "\"schema_version\":1,\"schema_version\":1",
      ),
      string.replace(
        valid,
        "\"schema_version\":1",
        "\"schema_version\":1,\"schema_versio\\u006e\":1",
      ),
      string.replace(
        valid,
        "\"schema_version\":1",
        "\"schema_version\":1,\"extra\":null",
      ),
      string.replace(valid, "\"schema_version\":1", "\"schema_version\":1.0"),
      string.replace(valid, "\"record_index\":1", "\"record_index\":0"),
      string.replace(valid, "\"record_index\":1", "\"record_index\":100001"),
      string.replace(
        valid,
        "\"record_index\":1",
        "\"record_index\":9223372036854775808",
      ),
      string.replace(valid, store.receipt_id(i), "wrong"),
      string.replace(valid, store.payload_sha256(i), string.repeat("0", 64)),
      string.replace(valid, "\"authority\":\"NONE\",", ""),
      string.repeat(" ", store.max_response_bytes + 1),
      hostile_bytes([123, 34, 120, 34, 58, 34, 255, 34, 125]),
      string.replace(valid, "\"NONE\"", "\"\\ud800\""),
    ],
    fn(raw) { protocol_refuses(i, raw) },
  )
}

pub fn native_hold_codes_are_closed_test() {
  let codes = [
    #("invalid_json", store.InvalidJson),
    #("invalid_receipt", store.InvalidReceipt),
    #("invalid_request", store.InvalidRequest),
    #("invalid_local_path", store.InvalidPath),
    #("schema_mismatch", store.SchemaMismatch),
    #("nested_transaction", store.NestedTransaction),
    #("store_unavailable", store.StoreUnavailable),
    #("resource_bound", store.ResourceBound),
    #("conflicting_replay", store.Conflict),
    #("stale_epoch", store.StaleEpoch),
    #("out_of_order", store.OutOfOrder),
    #("commit_unknown", store.CommitUnknown),
    #("rollback_failed", store.RollbackFailed),
    #("closed", store.Closed),
  ]
  list.each(codes, fn(pair) {
    let t =
      store.submit_with(intent(), fn(_) {
        completed(
          "{\"schema_version\":1,\"authority\":\"NONE\",\"admitted\":false,\"status\":\"hold\",\"reason\":\""
          <> pair.0
          <> "\"}",
        )
      })
    t.outcome |> should.equal(store.NativeHold(pair.1))
    store.phase(t.intent) |> should.equal(store.NeedsReconciliation)
  })
  protocol_refuses(
    intent(),
    "{\"schema_version\":1,\"authority\":\"NONE\",\"admitted\":false,\"status\":\"hold\",\"reason\":\"secret arbitrary text\"}",
  )
}

pub fn exact_identity_readback_and_absence_test() {
  let i = intent()
  let pending = uncertain(i)
  let valid = found(i)
  let t =
    store.reconcile_with(pending, fn(body) {
      string.contains(body, "\"operation\":\"get\"") |> should.be_true
      string.contains(body, "\"operation\":\"append\"") |> should.be_false
      completed(valid)
    })
  t.outcome |> should.equal(store.Reconciled)
  store.bound_sequence(t.intent) |> should.equal(1)
  list.each(
    [
      string.replace(valid, "\"sequence\":1", "\"sequence\":2"),
      string.replace(
        valid,
        "\"status\":\"unknown\"",
        "\"status\":\"ready_scoped\"",
      ),
      string.replace(
        valid,
        "\"record_index\":1",
        "\"record_index\":1,\"extra\":null",
      ),
      string.replace(
        valid,
        "\"function\":true",
        "\"function\":true,\"function\":true",
      ),
      string.replace(valid, store.payload_sha256(i), string.repeat("0", 64)),
      string.replace(valid, "receipt-1", "receipt-2"),
      string.replace(
        valid,
        "\"observed_utc_us\":1793471000000000",
        "\"observed_utc_us\":9223372036854775808",
      ),
    ],
    fn(raw) {
      store.reconcile_with(pending, fn(_) { completed(raw) }).outcome
      |> should.equal(store.ProtocolUncertain)
    },
  )
  let absent =
    store.reconcile_with(pending, fn(_) {
      completed(
        "{\"schema_version\":1,\"authority\":\"NONE\",\"admitted\":false,\"status\":\"absent\"}",
      )
    })
  absent.outcome |> should.equal(store.UnknownOutcome)
  store.phase(absent.intent) |> should.equal(store.NeedsReconciliation)
  store.submit_with(absent.intent, cannot_exchange).outcome
  |> should.equal(store.SubmitBlocked)
}

pub fn unconfirmed_cleanup_is_terminal_without_io_test() {
  let i = intent()
  let raw = response(i, "stored")
  list.each(
    [
      store.Exchange(Ok(raw), store.Unconfirmed),
      store.Exchange(Ok(raw), store.NotStarted),
      store.Exchange(Error(transport.Uncertain), store.Unconfirmed),
      store.Exchange(Error(transport.CleanupUnknown), store.Unconfirmed),
      store.Exchange(Ok(raw), store.Reaped(124, 1_793_471_000_000_000)),
      store.Exchange(Ok(raw), store.Reaped(125, 1_793_471_000_000_000)),
      store.Exchange(Ok(raw), store.Reaped(0, 0)),
      store.Exchange(Ok(raw), store.Reaped(0, 9_000_000_000_000_001)),
      store.Exchange(
        Error(transport.CleanupUnknown),
        store.Reaped(0, 1_793_471_000_000_000),
      ),
      store.Exchange(
        Error(transport.ConfigurationOrSpawn),
        store.Reaped(0, 1_793_471_000_000_000),
      ),
    ],
    fn(exchange) {
      let t = store.submit_with(i, fn(_) { exchange })
      t.outcome |> should.equal(store.CleanupUnconfirmed)
      store.phase(t.intent) |> should.equal(store.ReapingUnconfirmed)
      store.cleanup(t.intent) |> should.equal(store.Unconfirmed)
      store.acknowledgement(t.intent) |> should.equal(None)
      store.submit_with(t.intent, cannot_exchange).outcome
      |> should.equal(store.SubmitBlocked)
      // Even a perfect stored row must never be fetched while cleanup is unknown.
      store.reconcile_with(t.intent, cannot_exchange).outcome
      |> should.equal(store.SubmitBlocked)
      let again = store.reconcile_with(t.intent, fn(_) { completed(found(i)) })
      again.outcome |> should.equal(store.SubmitBlocked)
      store.phase(again.intent) |> should.equal(store.ReapingUnconfirmed)
    },
  )
  let pending = uncertain(i)
  let unconfirmed_read =
    store.reconcile_with(pending, fn(_) {
      store.Exchange(Ok(found(i)), store.Unconfirmed)
    })
  unconfirmed_read.outcome |> should.equal(store.CleanupUnconfirmed)
  store.reconcile_with(unconfirmed_read.intent, cannot_exchange).outcome
  |> should.equal(store.SubmitBlocked)
}

pub fn paired_reaping_before_readback_test() {
  let i = intent()
  store.cleanup(i) |> should.equal(store.NotStarted)
  list.each([0, 124, 125], fn(code) {
    let t =
      store.submit_with(i, fn(_) {
        store.Exchange(
          Error(transport.Uncertain),
          store.Reaped(code, 1_793_471_000_000_000),
        )
      })
    t.outcome |> should.equal(store.UnknownOutcome)
    store.cleanup(t.intent)
    |> should.equal(store.Reaped(code, 1_793_471_000_000_000))
    store.reconcile_with(t.intent, fn(_) { completed(found(i)) }).outcome
    |> should.equal(store.Reconciled)
  })
  let malformed = store.submit_with(i, fn(_) { completed("{malformed}") })
  malformed.outcome |> should.equal(store.ProtocolUncertain)
  store.reconcile_with(malformed.intent, fn(_) { completed(found(i)) }).outcome
  |> should.equal(store.Reconciled)
}

// Explicit reviewed executable configuration; test never derives/trusts a hash
// from the binary it is about to launch. Parent supplies independently pinned IDs.
fn with_native(test_fn: fn(transport.LocalConfiguration, String) -> a) -> a {
  let assert Ok(g) = envoy.get("UOS_SYMBIOSIS_TEST_GUARDIAN")
  let assert Ok(gh) = envoy.get("UOS_SYMBIOSIS_TEST_GUARDIAN_SHA256")
  let assert Ok(w) = envoy.get("UOS_SYMBIOSIS_TEST_WORKER")
  let assert Ok(wh) = envoy.get("UOS_SYMBIOSIS_TEST_WORKER_SHA256")
  let dir =
    "/tmp/uos_symbiosis_frontend_" <> int.to_string(int.random(1_000_000_000))
  let assert Ok(_) = simplifile.create_directory(dir)
  let assert Ok(_) = simplifile.set_permissions_octal(dir, 0o700)
  let config =
    transport.reviewed_local_configuration(
      g,
      gh,
      w,
      wh,
      dir <> "/synthetic.sqlite3",
    )
  let value = test_fn(config, dir)
  let assert Ok(_) = simplifile.delete(dir)
  value
}

pub fn actual_guardian_canonical_hash_and_four_agent_parity_test() {
  use config, _ <- with_native
  list.each(policy.agents(), fn(a) {
    let suffix = case a {
      policy.Claude -> "claude"
      policy.Pi -> "pi"
      policy.Agy -> "agy"
      policy.Codex -> "codex"
    }
    let c =
      store.Context(
        ..context(),
        receipt_id: "r-" <> suffix,
        operation_id: "op-" <> suffix,
        owner_id: "owner-" <> suffix,
      )
    let r = policy.Request(..request(), agent: a, probe: policy.CoverageProbe)
    let p =
      policy.CoverageEvidence(a, binding(), [
        leaf(a, "z-service", -995),
        leaf(a, "a-service", -996),
      ])
    let assert Ok(i) = store.prepare(c, r, observation(), Some(p))
    let t = store.submit(config, i)
    t.outcome |> should.equal(store.Stored)
    let assert store.Reaped(0, at) = store.cleanup(t.intent)
    { at > 0 } |> should.be_true
    let replay = store.submit(config, i)
    replay.outcome |> should.equal(store.Replayed)
    store.acknowledgement(replay.intent)
    |> should.equal(store.acknowledgement(t.intent))
    // Lose a known completed ACK locally, then exact-ID readback through real worker.
    store.reconcile(config, uncertain(i)).outcome
    |> should.equal(store.Reconciled)
  })
}

pub fn actual_lost_ack_readback_and_absent_no_retry_test() {
  use config, _ <- with_native
  let i = intent()
  let lost =
    store.submit_with(i, fn(body) {
      let assert #(Ok(_), Some(#(0, at))) = actual_paired_exchange(config, body)
      store.Exchange(Error(transport.Uncertain), store.Reaped(0, at))
    })
  lost.outcome |> should.equal(store.UnknownOutcome)
  store.submit_with(lost.intent, cannot_exchange).outcome
  |> should.equal(store.SubmitBlocked)
  let recovered = store.reconcile(config, lost.intent)
  recovered.outcome |> should.equal(store.Reconciled)
  let assert Ok(other) =
    store.prepare(
      store.Context(..context(), receipt_id: "absent", operation_id: "absent"),
      policy.Request(..request(), seq: 2),
      policy.Observation(..observation(), seq: 2),
      None,
    )
  let absent = store.reconcile(config, uncertain(other))
  absent.outcome |> should.equal(store.UnknownOutcome)
  store.submit_with(absent.intent, cannot_exchange).outcome
  |> should.equal(store.SubmitBlocked)
}

pub fn actual_native_conflict_and_invalid_configuration_test() {
  use config, dir <- with_native
  let i = intent()
  store.submit(config, i).outcome |> should.equal(store.Stored)
  let assert Ok(conflict) =
    store.prepare(
      context(),
      request(),
      policy.Observation(
        ..observation(),
        results: policy.Results(Some(False), Some(True), Some(True)),
      ),
      None,
    )
  store.submit(config, conflict).outcome
  |> should.equal(store.NativeHold(store.Conflict))
  let assert Ok(g) = envoy.get("UOS_SYMBIOSIS_TEST_GUARDIAN")
  let assert Ok(gh) = envoy.get("UOS_SYMBIOSIS_TEST_GUARDIAN_SHA256")
  let assert Ok(w) = envoy.get("UOS_SYMBIOSIS_TEST_WORKER")
  let wrong =
    transport.reviewed_local_configuration(
      g,
      gh,
      w,
      string.repeat("0", 64),
      dir <> "/never-opened.sqlite3",
    )
  let t = store.submit(wrong, i)
  t.outcome |> should.equal(store.CleanupUnconfirmed)
  store.submit_with(t.intent, cannot_exchange).outcome
  |> should.equal(store.SubmitBlocked)
  store.reconcile_with(t.intent, cannot_exchange).outcome
  |> should.equal(store.SubmitBlocked)
  simplifile.is_file(dir <> "/never-opened.sqlite3") |> should.equal(Ok(False))
}
