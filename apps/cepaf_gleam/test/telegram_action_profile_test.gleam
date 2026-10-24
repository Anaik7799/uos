import cepaf_gleam/harness/files
import cepaf_gleam/harness/telegram_action_profile as profile
import cepaf_gleam/harness/telegram_bridge as bridge
import cepaf_gleam/harness/telegram_store_transport as transport
import gleam/int
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import gleeunit/should
import simplifile

@external(erlang, "telegram_approval_test_crypto", "public_key")
fn public_key(role: String) -> String

pub fn context() {
  profile.Context(
    7,
    "fence",
    "controller",
    "owner",
    1,
    9,
    1,
    string.repeat("a", 64),
    "nas-1.tail55d152.ts.net",
    "test-boot",
  )
}

fn directory() {
  let root =
    "/tmp/uos-action-profile-" <> int.to_string(int.random(1_000_000_000))
  let assert Ok(_) = simplifile.create_directory_all(root)
  let assert Ok(_) = simplifile.set_permissions_octal(root, 0o700)
  root
}

pub fn raw(
  mapping,
  expiry,
  guardian,
  guardian_sha,
  worker,
  worker_sha,
  database,
  loaded_ms,
  roster_expiry_ms,
) {
  let c = context()
  let assert Ok(r) =
    bridge.new(
      mapping,
      c.plan,
      c.task,
      c.worker,
      c.attempt,
      "runtime-bridge",
      expiry,
    )
  let signers =
    list.map(["codex", "agy", "operator"], fn(role) {
      json.array(
        [
          json.string(role),
          json.string(role <> "-subject"),
          json.string(role <> "-key"),
          json.string(public_key(role)),
        ],
        fn(x) { x },
      )
    })
  json.object([
    #("schema", json.string("uos.telegram.action-profile.v1")),
    #(
      "context",
      json.array(
        [
          json.int(c.bot),
          json.string(c.plan),
          json.string(c.task),
          json.string(c.worker),
          json.int(c.attempt),
          json.int(c.epoch),
          json.int(c.service_epoch),
          json.string(c.candidate),
          json.string(c.host),
          json.string(c.boot),
        ],
        fn(x) { x },
      ),
    ),
    #("provision_json", json.string(bridge.request_json(r))),
    #(
      "transport",
      json.array(
        [guardian, guardian_sha, worker, worker_sha, database],
        json.string,
      ),
    ),
    #(
      "roster",
      json.array(
        [
          json.int(loaded_ms),
          json.int(roster_expiry_ms),
          json.array(signers, fn(x) { x }),
        ],
        fn(x) { x },
      ),
    ),
  ])
  |> json.to_string
}

fn fixture() {
  raw(
    "mapping-1",
    2_000_000_000,
    "/safe/guardian",
    string.repeat("b", 64),
    "/safe/worker",
    string.repeat("c", 64),
    "/safe/plan.sqlite3",
    1000,
    3000,
  )
}

fn save(root, raw) {
  profile.persist(root, "profile.json", raw, files.digest(raw), context())
}

pub fn persists_and_loads_exact_original_test() {
  let root = directory()
  let raw = fixture()
  let assert Ok(p) = save(root, raw)
  let assert Ok(loaded) =
    profile.load(root, "profile.json", files.digest(raw), context())
  profile.digest(p) |> should.equal(files.digest(raw))
  profile.context(loaded) |> should.equal(context())
  bridge.request_json(profile.request(loaded))
  |> should.equal(bridge.request_json(profile.request(p)))
  bridge.expires_at_ns(profile.request(loaded)) |> should.equal(2_000_000_000)
  let assert Ok(_) = profile.recheck(loaded, context(), 1_500_000_000)
}

pub fn bad_digest_and_payload_never_create_file_test() {
  let root = directory()
  profile.persist(
    root,
    "profile.json",
    fixture(),
    string.repeat("0", 64),
    context(),
  )
  |> result.is_error
  |> should.be_true
  files.read(root, "profile.json") |> result.is_error |> should.be_true
  list.each(["", "{}", string.repeat("x", 16_385)], fn(raw) {
    save(root, raw) |> result.is_error |> should.be_true
    files.read(root, "profile.json") |> result.is_error |> should.be_true
  })
}

pub fn every_context_field_is_bound_test() {
  let root = directory()
  let raw = fixture()
  let assert Ok(_) = save(root, raw)
  let c = context()
  list.each(
    [
      profile.Context(..c, bot: 8),
      profile.Context(..c, plan: "other"),
      profile.Context(..c, task: "other"),
      profile.Context(..c, worker: "other"),
      profile.Context(..c, attempt: 2),
      profile.Context(..c, epoch: 10),
      profile.Context(..c, service_epoch: 2),
      profile.Context(..c, candidate: string.repeat("d", 64)),
      profile.Context(..c, host: "vm-1.tail55d152.ts.net"),
      profile.Context(..c, boot: "other-boot"),
    ],
    fn(changed) {
      profile.load(root, "profile.json", files.digest(raw), changed)
      |> result.is_error
      |> should.be_true
    },
  )
}

pub fn invalid_context_and_schema_are_refused_test() {
  let root = directory()
  let raw = fixture()
  list.each(
    [
      raw |> string.replace("\"uos.telegram.action-profile.v1\"", "\"future\""),
      raw |> string.replace("\"schema\":", "\"extra\":true,\"schema\":"),
      raw |> string.replace("\"context\":", "\"context\":[],\"context\":"),
      raw |> string.replace("[7,\"fence\"", "[0,\"fence\""),
      raw |> string.replace("\"test-boot\"", "\"../test-boot\""),
      raw |> string.replace("\"nas-1.tail55d152.ts.net\"", "\"localhost\""),
    ],
    fn(value) { save(root, value) |> result.is_error |> should.be_true },
  )
}

pub fn malformed_transport_and_roster_are_refused_test() {
  let root = directory()
  let raw = fixture()
  list.each(
    [
      raw |> string.replace("/safe/guardian", "../guardian"),
      raw |> string.replace("/safe/worker", "/safe/../worker"),
      raw |> string.replace("/safe/plan.sqlite3", "//safe/plan.sqlite3"),
      raw |> string.replace(string.repeat("b", 64), string.repeat("B", 64)),
      raw |> string.replace("\"operator\"", "\"claude\""),
      raw |> string.replace("\"agy\"", "\"codex\""),
      raw |> string.replace("\"roster\":[1000,3000", "\"roster\":[3000,1000"),
    ],
    fn(value) { save(root, value) |> result.is_error |> should.be_true },
  )
}

pub fn mismatched_or_noncanonical_provision_refused_test() {
  let root = directory()
  let raw = fixture()
  list.each(
    [
      raw
        |> string.replace(
          "\\\"owner\\\":\\\"owner\\\"",
          "\\\"owner\\\":\\\"other\\\"",
        ),
      raw |> string.replace("\\\"task_attempt\\\":1", "\\\"task_attempt\\\":2"),
      raw |> string.replace("\"provision_json\":\"", "\"provision_json\":\" "),
    ],
    fn(value) {
      { value == raw } |> should.be_false
      save(root, value) |> result.is_error |> should.be_true
    },
  )
}

pub fn historical_load_never_renews_or_activates_expired_profile_test() {
  let root = directory()
  let raw = fixture()
  let assert Ok(p) = save(root, raw)
  let original = bridge.request_json(profile.request(p))
  let assert Ok(loaded) =
    profile.load(root, "profile.json", files.digest(raw), context())
  list.each([-1, 999_999_999, 2_000_000_000, 4_000_000_000], fn(now) {
    profile.active_at(loaded, context(), now) |> should.be_false
    profile.recheck(loaded, context(), now) |> result.is_error |> should.be_true
  })
  bridge.request_json(profile.request(loaded)) |> should.equal(original)
  profile.active_at(loaded, context(), 1_999_999_999) |> should.be_true
}

pub fn exclusive_create_and_changed_source_recheck_test() {
  let root = directory()
  let raw = fixture()
  let assert Ok(p) = save(root, raw)
  save(root, raw) |> result.is_error |> should.be_true
  files.read(root, "profile.json") |> should.equal(Ok(raw))
  let assert Ok(_) = simplifile.write(root <> "/profile.json", raw <> " ")
  profile.recheck(p, context(), 1_500_000_000)
  |> result.is_error
  |> should.be_true
}

/// First BEAM writes/fsyncs public profile, then binds; no private key leaves test memory.
pub fn persist_and_bind(
  root,
  mapping,
  expiry,
  guardian,
  gsha,
  worker,
  wsha,
  database,
  now_ms,
) {
  let text =
    raw(
      mapping,
      expiry,
      guardian,
      gsha,
      worker,
      wsha,
      database,
      now_ms - 1,
      now_ms + 120_000,
    )
  let assert Ok(p) = save(root, text)
  let assert Ok(raw) =
    transport.exchange(
      profile.transport(p),
      bridge.envelope(profile.request(p), bridge.Bind),
    )
  let assert Ok(bridge.Found(1, _, _, False)) =
    bridge.decode_response(
      profile.request(p),
      bridge.Bind,
      raw,
      time(Nanosecond),
    )
  files.digest(text)
}

type TimeUnit {
  Nanosecond
}

@external(erlang, "erlang", "system_time")
fn time(unit: TimeUnit) -> Int

/// New BEAM loads only public pinned bytes and reads historical binding; no signing.
pub fn recover_lookup(root, digest) {
  let assert Ok(p) = profile.load(root, "profile.json", digest, context())
  let r = profile.request(p)
  profile.active_at(p, context(), bridge.expires_at_ns(r)) |> should.be_false
  let assert Ok(raw) =
    transport.exchange(profile.transport(p), bridge.envelope(r, bridge.Lookup))
  let assert Ok(bridge.Found(1, _, _, True)) =
    bridge.decode_response(r, bridge.Lookup, raw, time(Nanosecond))
  "profile_reloaded_exact_bridge"
}
