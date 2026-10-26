//// Service-level /verify: a signed verify packet is executed through the
//// real store, a trusted action profile, the verify reservation, a fake
//// sa-plan runner and the pinned verify guardian. Replay returns the stored
//// receipt; refusals name their reason. Test-only keys; no live recipient.

import cepaf_gleam/harness/clock
import cepaf_gleam/harness/development
import cepaf_gleam/harness/files
import cepaf_gleam/harness/telegram_action_intent as action
import cepaf_gleam/harness/telegram_action_profile as profile
import cepaf_gleam/harness/telegram_approval as approval
import cepaf_gleam/harness/telegram_bridge as bridge
import cepaf_gleam/harness/telegram_delivery_ledger as ledger
import cepaf_gleam/harness/telegram_http_client as http
import cepaf_gleam/harness/telegram_ingress_guard as guard
import cepaf_gleam/harness/telegram_service as service
import cepaf_gleam/harness/telegram_store as store
import cepaf_gleam/harness/telegram_store_codec as codec
import cepaf_gleam/harness/telegram_store_transport as transport
import cepaf_gleam/harness/telegram_verify_action as verify_action
import cepaf_gleam/harness/telegram_verify_contract as v
import cepaf_gleam/harness/telegram_verify_executor as executor
import cepaf_gleam/harness/telegram_verify_job as job
import cepaf_gleam/harness/telegram_verify_loader as loader
import cepaf_gleam/harness/telegram_verify_packet as packet
import cepaf_gleam/harness/telegram_verify_run as run
import gleam/bit_array
import gleam/crypto
import gleam/dynamic/decode
import gleam/erlang/process
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import simplifile
import telegram_action_service_test as svc
import uos_swarm/session_store as coord
import uos_swarm/session_sync as sync

@external(erlang, "telegram_approval_test_crypto", "sign")
fn sign(role: String, payload: String) -> String

const text = "/verify telegram-core"

/// The isolated Sa-plan fence (plan, executing task, bridge mapping and lease)
/// is prepared by the OCaml fixture `verify_fence_fixture.exe`; its output
/// names the mapping id and fencing token the signed binding must carry.
const fence_fixture = "/engines/hermes/_build/default/modules/sa_plan/test/verify_fence_fixture.exe"

type Fence {
  Fence(mapping: String, fencing_token: Int, expires_at_ns: Int)
}

/// The Sa-plan frame transport worker (cancel-once, cancellation-result,
/// bind-controller-bridge, controller-bridge-result), built by dune; the
/// pinned telegram store recovery worker serves only the Telegram store.
fn cancel_worker() -> String {
  let assert Ok(cwd) = simplifile.current_directory()
  string.drop_end(cwd, string.length("/apps/cepaf_gleam"))
  <> "/engines/hermes/_build/default/modules/sa_plan/test/sa_plan_cancel_worker.exe"
}

fn file_sha256(path: String) -> String {
  let assert Ok(bits) = simplifile.read_bits(path)
  crypto.hash(crypto.Sha256, bits)
  |> bit_array.base16_encode
  |> string.lowercase
}

fn prepare_fence(database: String, c: profile.Context) -> Fence {
  let assert Ok(cwd) = simplifile.current_directory()
  let exe =
    string.drop_end(cwd, string.length("/apps/cepaf_gleam")) <> fence_fixture
  let assert Ok(out) =
    development.bounded(
      exe,
      [
        database,
        c.plan,
        c.task,
        c.worker,
        "verify-once",
        "control-lease",
        "3600000000000",
      ],
      10_000,
    )
  let assert Ok(fence) =
    json.parse(string.trim(out), {
      use mapping <- decode.field("mapping_id", decode.string)
      use token <- decode.field("fencing_token", decode.int)
      use expires <- decode.field("expires_at_ns", decode.int)
      decode.success(Fence(mapping, token, expires))
    })
  fence
}

const guardian_exe = "/home/an/NAS-setup/uos/tools/validation/telegram_store_transport_guardian.exe"

const guardian_sha = "06a278afd304bb4752522bd632004eb35ecff8a1b65459a3607a70b24e67f0ab"

const recovery_exe = "/home/an/NAS-setup/uos/tools/validation/telegram_store_recovery_worker.exe"

const recovery_sha = "f4f249eaa6ff2c9f4b1bf8c6587426f283ec1754892e847568b5dd1712a55b1e"

const verify_guardian_sha = "d1dc2995fe52915e9c2a7b39309f23a8197cfb273d025f3453ebd904b24f50f4"

type Fixture {
  Fixture(
    root: String,
    p: profile.Profile,
    c: profile.Context,
    state: service.ServiceState,
    inbox: ledger.InboxRecord,
    cfg: service.VerifyConfiguration,
    b: v.Binding,
    now: Int,
    boot: Int,
    fence: Fence,
  )
}

fn script(root: String, name: String, body: String) -> String {
  let content = "#!/bin/sh\n" <> body <> "\n"
  let path = root <> "/gates/" <> name
  let assert Ok(_) = simplifile.write(path, content)
  let assert Ok(_) = simplifile.set_permissions_octal(path, 0o755)
  files.digest(content)
}

/// One passing gate under a pinned verify profile in `root/verify`.
fn verify_source(root: String, worker: String) -> run.Source {
  let vroot = root <> "/verify"
  let assert Ok(_) = simplifile.create_directory_all(vroot <> "/gates")
  let assert Ok(_) = simplifile.create_directory_all(vroot <> "/evidence")
  let assert Ok(_) = simplifile.create_directory_all(vroot <> "/reservations")
  let build = script(vroot, "build.sh", "echo built")
  let assert Ok(_) = simplifile.write(vroot <> "/gates/build.in", "b")
  let assert Ok(p) =
    v.profile(
      "telegram-core",
      string.repeat("a", 40),
      string.repeat("b", 64),
      [v.Gate("build", build, files.digest("b"), 2000)],
      2000,
    )
  let assert Ok(_) =
    simplifile.write(vroot <> "/profile.json", v.canonical_json(p))
  let assert Ok(cwd) = simplifile.current_directory()
  run.Source(
    root: vroot,
    profile_path: "profile.json",
    pin: v.profile_digest(p),
    locators: [loader.Locator("build", "gates/build.sh", "gates/build.in")],
    // configure_verify refuses ".." in any path, so derive the repository
    // root from the app directory instead of walking up with "..".
    guardian: executor.Guardian(
      string.drop_end(cwd, string.length("/apps/cepaf_gleam"))
        <> "/tools/validation/verify_guardian.exe",
      verify_guardian_sha,
    ),
    reservation_dir: "reservations",
    evidence_base: "evidence",
    worker: worker,
  )
}

fn job_row(job_id: String, worker: String, state: String) -> String {
  json.object([
    #("id", json.string(job_id)),
    #("queue", json.string(job.queue)),
    #("worker", json.string(worker)),
    #("state", json.string(state)),
    #("attempt", json.string("1")),
  ])
  |> json.to_string
}

/// Stateless fake sa-plan bound to one job row: enqueue refuses a duplicate
/// id, claim answers the same job as executing, complete succeeds.
fn runner(job_id: String, worker: String) -> job.Runner {
  fn(args) {
    case args {
      ["--format", "json", "job", "list", _] ->
        Ok(job_row(job_id, worker, "available"))
      ["--format", "json", "job", "claim", _, w, _] ->
        Ok(job_row(job_id, w, "executing"))
      ["job", "enqueue", id, ..] if id == job_id ->
        Error("UNIQUE constraint failed: sa_plan_job.id")
      ["job", "enqueue", ..] -> Ok("enqueued")
      ["job", "complete", ..] -> Ok("completed")
      _ -> Error("unexpected_argv")
    }
  }
}

fn fixture(tag: String) -> Fixture {
  let root =
    "/tmp/uos_tg_verify_service_"
    <> tag
    <> "_"
    <> int.to_string(int.random(1_000_000_000))
  let assert Ok(_) = simplifile.create_directory_all(root)
  let assert Ok(_) = simplifile.set_permissions_octal(root, 0o700)
  let database = root <> "/sa-plan.sqlite3"
  let assert Ok(observed) = clock.observe()
  let now = observed.sample.observed.utc_us / 1000
  let boot = observed.sample.observed.boot_us / 1000
  let c =
    profile.Context(
      333_444,
      "verify-plan",
      "controller",
      "controller",
      1,
      1,
      1,
      recovery_sha,
      "nas-1.tail55d152.ts.net",
      observed.sample.observed.domain.boot_id,
      observed.sample.observed.domain.host_id,
    )
  let fence = prepare_fence(database, c)
  // The bridge request in the profile must name the lease exactly as stored.
  let bridge_expiry = fence.expires_at_ns
  let raw =
    svc.profile_raw(
      c,
      fence.mapping,
      bridge_expiry,
      guardian_exe,
      guardian_sha,
      cancel_worker(),
      file_sha256(cancel_worker()),
      database,
      now,
    )
  let assert Ok(p) =
    profile.persist(root, "profile.json", raw, files.digest(raw), c)
  let tg =
    transport.reviewed_local_configuration(
      guardian_exe,
      guardian_sha,
      recovery_exe,
      recovery_sha,
      root <> "/telegram.sqlite3",
    )
  let assert Ok(_) = store.initialize_store(tg, c.bot)
  let coord_path = root <> "/coord.sqlite3"
  let assert Ok(co) = coord.open(coord_path)
  let assert Ok(_) =
    coord.append(
      co,
      sync.Register("controller", "codex", root, "candidate", []),
      "register",
    )
  let assert Ok(_) =
    coord.append(
      co,
      sync.Claim("controller", "runtime:telegram-bridge", 120_000_000),
      "claim",
    )
  let assert Ok(_) = coord.close(co)
  let config =
    service.operational_service_configuration(
      tg,
      http.default_configuration(
        "http://nas-1.tail55d152.ts.net:1",
        "TEST_ONLY",
      ),
      c.bot,
      [#(100, 200)],
      c.plan,
      c.task,
      c.worker,
      "controller",
      1,
      1,
      1,
    )
  let config =
    service.ServiceConfiguration(
      ..config,
      authority_paths: service.IsolatedTestPaths(database, coord_path),
    )
  let source = verify_source(root, c.worker)
  let assert Ok(#(initial, _)) = service.init_service(config, None)
  let assert Ok(#(wm, ver, h)) = store.read_watermark(tg)
  let verdict =
    guard.AcceptedEnvelope(
      10,
      11,
      100,
      200,
      files.digest(text),
      text,
      guard.classify_directive(text),
      c.bot,
      None,
    )
  let assert Ok(prefix) =
    store.commit_prefix(
      tg,
      c.bot,
      "prefix",
      initial.expected_generation,
      wm,
      ver,
      h,
      [verdict],
      now,
    )
  let assert [inbox] = prefix.admitted_records
  let assert Ok(#(receipt, inbox)) =
    store.claim_task_processing(
      tg,
      c.bot,
      "claim",
      prefix.receipt.generation,
      inbox,
      1,
      files.digest(codec.encode_inbox_record(inbox)),
      c.worker,
      1,
      now,
    )
  let assert Ok(worker) = service.start_store_worker(tg, c.bot)
  let state =
    service.ServiceState(
      ..initial,
      expected_generation: receipt.generation,
      store_worker: Some(worker.data),
    )
  let state =
    service.set_authority(
      state,
      service.AuthorityLease("service-test", 1, 1, bridge_expiry / 1000),
    )
  // The reservation binding this request will get, so the packet can name it.
  let assert Ok(loaded) =
    loader.load(source.root, source.profile_path, source.pin, source.locators)
  let assert Ok(b) = v.binding(loader.profile(loaded), inbox.request_id, 1)
  let assert Ok(config) =
    service.configure_verify(
      state.config,
      source,
      database,
      runner(b.job_id, c.worker),
    )
  let state = service.ServiceState(..state, config: config)
  let assert Some(cfg) = config.verify
  Fixture(root, p, c, state, inbox, cfg, b, now, boot, fence)
}

fn binding(f: Fixture) -> action.Binding {
  let c = f.c
  action.Binding(
    c.bot,
    100,
    200,
    10,
    c.plan,
    c.task,
    c.worker,
    c.attempt,
    c.epoch,
    c.candidate,
    c.host,
    c.boot,
    action.Execution(
      f.fence.mapping,
      "control-lease",
      f.fence.fencing_token,
      profile.digest(f.p),
    ),
  )
}

fn verify_packet(f: Fixture, purpose: String) -> String {
  verify_packet_exp(f, purpose, 30_000)
}

/// A signed verify packet whose receipts expire `exp_offset_ms` after now.
fn verify_packet_exp(
  f: Fixture,
  purpose: String,
  exp_offset_ms: Int,
) -> String {
  let assert Ok(intent) =
    action.new_kind(
      action.VerifyProfile,
      binding(f),
      verify_action.target_for(
        f.c.plan,
        f.b,
        f.c.worker,
        { f.now + 120_000 } * 1_000_000,
      ),
      action.Window(f.now, f.boot, f.now + 60_000, f.boot + 60_000),
      "Operator requested verification of telegram-core",
      string.repeat("b", 64),
    )
  let roster = profile.roster(f.p)
  let receipts =
    list.map([approval.Codex, approval.Agy, approval.Operator], fn(role) {
      let n = approval.role_name(role)
      let token =
        sign(
          n,
          json.object([
            #("version", json.string("uos.telegram.approval.v1")),
            #("purpose", json.string(purpose)),
            #("role", json.string(n)),
            #("subject", json.string(n <> "-subject")),
            #("decision", json.string("approve")),
            #("intent_digest", json.string(action.digest(intent))),
            #("effect_id", json.string(action.effect_id(intent))),
            #("iat_ms", json.int(f.now)),
            #("nbf_ms", json.int(f.now)),
            #("exp_ms", json.int(f.now + exp_offset_ms)),
            #("roster_digest", json.string(approval.roster_digest(roster))),
          ])
            |> json.to_string,
        )
      approval.Receipt(role, token)
    })
  json.object([
    #("schema", json.string(packet.expected_schema)),
    #(
      "record_json",
      json.string(verify_action.encode_parts(intent, f.now + exp_offset_ms, f.b)),
    ),
    #(
      "receipts",
      json.array(receipts, fn(r) {
        json.array([approval.role_name(r.role), r.token], json.string)
      }),
    ),
  ])
  |> json.to_string
}

fn run_verify(f: Fixture, name: String) {
  service.execute_approved_verify(f.state, f.p, f.cfg, f.root, name, f.inbox)
}

fn field(reply: String, key: String) -> String {
  let assert Ok(value) =
    json.parse(reply, {
      use value <- decode.field(key, decode.string)
      decode.success(value)
    })
  value
}

fn expect_hold(result, expected: String) {
  let assert Error(service.ServiceError(_, reason)) = result
  reason |> should.equal(expected)
}

pub fn signed_verify_packet_executes_once_and_replays_as_duplicate_test() {
  let f = fixture("ok")
  let packet_name = service.action_packet_filename(f.inbox.request_id)
  let assert Ok(_) =
    files.create(f.root, packet_name, verify_packet(f, "verify_profile"))
  let assert Ok(#(_, reply)) = run_verify(f, packet_name)
  field(reply, "status") |> should.equal("executed")
  field(reply, "assessment") |> should.equal("verified_evidence")
  field(reply, "job_id") |> should.equal(f.b.job_id)
  field(reply, "runtime_admission") |> should.equal("NOT_GRANTED")
  let receipt_digest = field(reply, "receipt_sha256")
  // The receipt is on disk under the evidence directory, and its digest matches.
  let assert Ok(stored) =
    simplifile.read(
      f.cfg.source.root
      <> "/"
      <> executor.evidence_dir(f.cfg.source.evidence_base, f.b)
      <> "/receipt.json",
    )
  files.digest(stored) |> should.equal(receipt_digest)
  // Replay: the stored receipt is returned, the guardian does not run again.
  let assert Ok(#(_, again)) = run_verify(f, packet_name)
  field(again, "status") |> should.equal("duplicate")
  field(again, "assessment") |> should.equal("stored_receipt")
  field(again, "receipt_sha256") |> should.equal(receipt_digest)
  // A receipt exists, so the Sa-plan job was claimed and completed; no .tmp
  // receipt remains from the atomic write.
  let assert Ok(names) =
    simplifile.read_directory(
      f.cfg.source.root
      <> "/"
      <> executor.evidence_dir(f.cfg.source.evidence_base, f.b),
    )
  list.any(names, fn(n) { string.ends_with(n, ".tmp") }) |> should.be_false
}

pub fn replay_after_the_approval_expired_still_answers_duplicate_test() {
  let f = fixture("expiry")
  let packet_name = service.action_packet_filename(f.inbox.request_id)
  // Receipts valid for 2.5 s: long enough for one run, then they expire.
  let assert Ok(_) =
    files.create(
      f.root,
      packet_name,
      verify_packet_exp(f, "verify_profile", 2500),
    )
  let assert Ok(#(_, reply)) = run_verify(f, packet_name)
  field(reply, "status") |> should.equal("executed")
  process.sleep(3000)
  // The packet no longer verifies, but the request is Complete: the stored
  // receipt answers and the writer is never held (review finding V-03).
  let assert Ok(#(_, again)) = run_verify(f, packet_name)
  field(again, "status") |> should.equal("duplicate")
  field(again, "receipt_sha256") |> should.equal(field(reply, "receipt_sha256"))
}

/// The profile transport answers Sa-plan frames (the cancel worker), so the
/// bridge lease named in the signed binding is observed live and current.
pub fn bridge_lease_lookup_is_current_test() {
  let f = fixture("bridge")
  let request = profile.request(f.p)
  let assert Ok(text) =
    transport.exchange(
      profile.transport(f.p),
      bridge.envelope(request, bridge.Lookup),
    )
  // Decode against a fresh host clock, as the service does; the lease was
  // recorded after the fixture's first observation.
  let assert Ok(observed) = clock.observe()
  let now_ns = observed.sample.observed.utc_us * 1000
  let assert Ok(bridge.Found(fence, expiry, _, current)) =
    bridge.decode_response(request, bridge.Lookup, text, now_ns)
  fence |> should.equal(f.fence.fencing_token)
  current |> should.be_true
  { expiry > now_ns } |> should.be_true
}

pub fn recovery_mode_is_answered_not_held_test() {
  let f = fixture("recovery")
  let recovering =
    service.ServiceConfiguration(
      ..f.state.config,
      actions: Some(service.RecoveryActions(f.p)),
    )
  // The dispatch decision for recovery mode is a reply, never a writer hold;
  // delivery itself needs the HTTP fixture and is covered by the service e2e
  // suites for the other reply paths.
  service.verify_dispatch_decision(recovering)
  |> should.equal(service.VerifyRecoveryMode)
  service.verify_dispatch_decision(
    service.ServiceConfiguration(..f.state.config, verify: None),
  )
  |> should.equal(service.VerifyNotConfigured)
  service.verify_dispatch_decision(
    service.ServiceConfiguration(..f.state.config, actions: None),
  )
  |> should.equal(service.VerifyActionsNotConfigured)
  // The fixture drives execute_approved_verify directly, so its config has
  // no signed-actions profile; with one, the decision is the signed path.
  case
    service.verify_dispatch_decision(
      service.ServiceConfiguration(
        ..f.state.config,
        actions: Some(service.SignedActions(f.p, f.root)),
      ),
    )
  {
    service.VerifySigned(_, _, _) -> Nil
    _ -> should.fail()
  }
  simplifile.read_directory(f.cfg.source.root <> "/reservations")
  |> should.equal(Ok([]))
}

pub fn refusals_name_their_reason_and_execute_nothing_test() {
  let f = fixture("refuse")
  let packet_name = service.action_packet_filename(f.inbox.request_id)
  // No packet at all.
  run_verify(f, packet_name) |> expect_hold("verify_packet_invalid")
  // Cancellation-purpose receipts over the verify intent.
  let assert Ok(_) =
    files.create(
      f.root,
      "cancel-purpose.json",
      verify_packet(f, "cancel_job_lease"),
    )
  run_verify(f, "cancel-purpose.json") |> expect_hold("verify_packet_invalid")
  // Recipient outside the allowlist.
  let denied =
    service.ServiceState(
      ..f.state,
      config: service.ServiceConfiguration(..f.state.config, allowed_pairs: []),
    )
  let assert Ok(_) =
    files.create(f.root, packet_name, verify_packet(f, "verify_profile"))
  service.execute_approved_verify(
    denied,
    f.p,
    f.cfg,
    f.root,
    packet_name,
    f.inbox,
  )
  |> expect_hold("action_recipient_refused")
  // Revoked authority.
  service.execute_approved_verify(
    service.revoke_authority(f.state),
    f.p,
    f.cfg,
    f.root,
    packet_name,
    f.inbox,
  )
  |> expect_hold("action_authority_refused")
  // Nothing ran: no evidence directory exists for the job, and the refused
  // requests left no reservation behind (effects start only after approval).
  simplifile.is_directory(
    f.cfg.source.root
    <> "/"
    <> executor.evidence_dir(f.cfg.source.evidence_base, f.b),
  )
  |> should.equal(Ok(False))
  simplifile.read_directory(f.cfg.source.root <> "/reservations")
  |> should.equal(Ok([]))
}

pub fn configure_verify_refuses_unbounded_or_foreign_configuration_test() {
  let f = fixture("config")
  let src = f.cfg.source
  let r = f.cfg.runner
  let db = f.cfg.database
  let base = service.ServiceConfiguration(..f.state.config, verify: None)
  let refused = Error("verify_configuration_refused")
  service.configure_verify(base, src, db, r) |> should.be_ok
  service.configure_verify(
    base,
    run.Source(..src, root: "relative/root"),
    db,
    r,
  )
  |> should.equal(refused)
  service.configure_verify(
    base,
    run.Source(..src, evidence_base: "../up"),
    db,
    r,
  )
  |> should.equal(refused)
  service.configure_verify(
    base,
    run.Source(..src, profile_path: "/abs.json"),
    db,
    r,
  )
  |> should.equal(refused)
  service.configure_verify(base, run.Source(..src, pin: "short"), db, r)
  |> should.equal(refused)
  service.configure_verify(
    base,
    run.Source(..src, worker: "someone-else"),
    db,
    r,
  )
  |> should.equal(refused)
  service.configure_verify(base, run.Source(..src, locators: []), db, r)
  |> should.equal(refused)
  // The verify job store must be the service's own Sa-plan database (V-02).
  service.configure_verify(base, src, f.root <> "/other.sqlite3", r)
  |> should.equal(refused)
  let _ = process.self()
  Nil
}
