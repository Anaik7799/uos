import cepaf_gleam/harness/telegram_action_intent as action
import gleam/list
import gleam/result
import gleam/string
import gleeunit/should

fn binding() {
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
    "nas-1.tail55d152.ts.net",
    "boot-1",
    action.Execution("mapping-1", "lease-1", 3, string.repeat("d", 64)),
  )
}

fn target() {
  action.Target("uos/example/job1", "worker", 2, 2_000_000_000_000)
}

fn window() {
  action.Window(1_000_000, 20_000, 1_060_000, 80_000)
}

fn intent() {
  let assert Ok(value) =
    action.new(
      binding(),
      target(),
      window(),
      "Operator requested cancellation",
      string.repeat("b", 64),
    )
  value
}

fn make(b, t, w, reason, nonce) {
  action.new(b, t, w, reason, nonce)
}

fn made(b, t, w, reason, nonce) {
  let assert Ok(value) = make(b, t, w, reason, nonce)
  value
}

pub fn canonical_golden_vector_test() {
  action.canonical_json(intent())
  |> should.equal(
    "[\"uos.telegram.action-intent.v2\",\"cancel_job_lease\",7,-11,13,19,\"uos/example\",\"TASK\",\"operator\",6,9,\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"nas-1.tail55d152.ts.net\",\"boot-1\",\"mapping-1\",\"lease-1\",3,\"dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"uos/example/job1\",\"worker\",2,2000000000000,1000000,20000,1060000,80000,\"Operator requested cancellation\",\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"]",
  )
  action.digest(intent())
  |> should.equal(
    "e260ea54e3a9e1a36278c0a00a770cf3b8e7c8d340ad2886bdaf3091db4bc4e4",
  )
  action.effect_id(intent())
  |> should.equal(
    "4718876da639ea2767fcc2578ffad8bc7a981b2414339b28ac7e35a557565899",
  )
}

pub fn every_binding_field_changes_request_digest_test() {
  let b = binding()
  list.each(
    [
      action.Binding(..b, bot_id: 8),
      action.Binding(..b, chat_id: -12),
      action.Binding(..b, user_id: 14),
      action.Binding(..b, update_id: 20),
      action.Binding(..b, task: "TASK2"),
      action.Binding(..b, worker: "other"),
      action.Binding(..b, attempt: 7),
      action.Binding(..b, epoch: 10),
      action.Binding(..b, candidate_sha256: string.repeat("c", 64)),
      action.Binding(..b, host: "vm-1.tail55d152.ts.net"),
      action.Binding(..b, boot_id: "boot-2"),
    ],
    fn(changed) {
      let value =
        made(
          changed,
          target(),
          window(),
          "Operator requested cancellation",
          string.repeat("b", 64),
        )
      action.digest(value) |> different(action.digest(intent()))
      action.matches_binding(intent(), changed) |> should.be_false
    },
  )
  let t = target()
  let value =
    made(
      action.Binding(..b, plan: "uos/other"),
      action.Target(..t, job: "uos/other/job1"),
      window(),
      "Operator requested cancellation",
      string.repeat("b", 64),
    )
  action.digest(value) |> different(action.digest(intent()))
}

pub fn every_target_field_changes_request_digest_test() {
  let t = target()
  list.each(
    [
      action.Target(..t, job: "uos/example/job2"),
      action.Target(..t, worker: "other"),
      action.Target(..t, attempt: 3),
      action.Target(..t, lease_until_ns: 2_000_000_000_001),
    ],
    fn(changed) {
      let value =
        made(
          binding(),
          changed,
          window(),
          "Operator requested cancellation",
          string.repeat("b", 64),
        )
      action.digest(value) |> different(action.digest(intent()))
      action.matches_target(intent(), changed) |> should.be_false
    },
  )
  action.matches_binding(intent(), binding()) |> should.be_true
  action.matches_target(intent(), target()) |> should.be_true
}

pub fn request_binds_reason_nonce_and_time_test() {
  let w = window()
  list.each(
    [
      action.Window(..w, created_utc_ms: 1_000_001, deadline_utc_ms: 1_060_001),
      action.Window(..w, created_boot_ms: 20_001, deadline_boot_ms: 80_001),
      action.Window(..w, deadline_utc_ms: 1_060_001, deadline_boot_ms: 80_001),
    ],
    fn(changed) {
      action.digest(made(
        binding(),
        target(),
        changed,
        "Operator requested cancellation",
        string.repeat("b", 64),
      ))
      |> different(action.digest(intent()))
    },
  )
  action.digest(made(
    binding(),
    target(),
    window(),
    "Different reason",
    string.repeat("b", 64),
  ))
  |> different(action.digest(intent()))
  action.digest(made(
    binding(),
    target(),
    window(),
    "Operator requested cancellation",
    string.repeat("c", 64),
  ))
  |> different(action.digest(intent()))
}

pub fn stable_effect_across_retry_context_test() {
  let b = binding()
  let t = target()
  let value =
    made(
      action.Binding(
        ..b,
        attempt: 7,
        epoch: 10,
        candidate_sha256: string.repeat("c", 64),
      ),
      action.Target(..t, attempt: 3, lease_until_ns: 2_000_000_000_001),
      window(),
      "New reason",
      string.repeat("c", 64),
    )
  action.effect_id(value) |> should.equal(action.effect_id(intent()))
  action.digest(value) |> different(action.digest(intent()))
  list.each(
    [
      action.Binding(..b, bot_id: 8),
      action.Binding(..b, chat_id: -12),
      action.Binding(..b, user_id: 14),
      action.Binding(..b, update_id: 20),
    ],
    fn(changed) {
      action.effect_id(made(
        changed,
        target(),
        window(),
        "Reason",
        string.repeat("b", 64),
      ))
      |> different(action.effect_id(intent()))
    },
  )
  action.effect_id(made(
    binding(),
    action.Target(..t, job: "uos/example/job2"),
    window(),
    "Reason",
    string.repeat("b", 64),
  ))
  |> different(action.effect_id(intent()))
}

pub fn invalid_identity_and_fence_values_test() {
  let b = binding()
  list.each(
    [
      action.Binding(..b, bot_id: 0),
      action.Binding(..b, user_id: 0),
      action.Binding(..b, chat_id: 0),
      action.Binding(..b, update_id: -1),
      action.Binding(..b, update_id: 2_147_483_648),
      action.Binding(..b, bot_id: 4_503_599_627_370_496),
      action.Binding(..b, attempt: 0),
      action.Binding(..b, epoch: 0),
      action.Binding(..b, attempt: 2_147_483_648),
      action.Binding(..b, epoch: 2_147_483_648),
    ],
    fn(changed) {
      make(changed, target(), window(), "Reason", string.repeat("b", 64))
      |> result.is_error
      |> should.be_true
    },
  )
}

pub fn invalid_identifiers_test() {
  let b = binding()
  list.each(
    [
      "",
      "../bad",
      "x' OR 1=1",
      "x;bad",
      "x\u{0}",
      "ｘ",
      "a b",
      string.repeat("x", 241),
    ],
    fn(id) {
      list.each(
        [
          action.Binding(..b, task: id),
          action.Binding(..b, worker: id),
          action.Binding(..b, plan: id),
        ],
        fn(changed) {
          make(changed, target(), window(), "Reason", string.repeat("b", 64))
          |> result.is_error
          |> should.be_true
        },
      )
    },
  )
  list.each(
    [
      "",
      ".host",
      "host.",
      "host..name",
      "host/name",
      "http://host",
      "ho st",
      "høst",
      string.repeat("x", 254),
    ],
    fn(host) {
      make(
        action.Binding(..b, host: host),
        target(),
        window(),
        "Reason",
        string.repeat("b", 64),
      )
      |> result.is_error
      |> should.be_true
    },
  )
  list.each(
    ["", "boot.id", "boot/id", "boot id", "bøøt", string.repeat("x", 129)],
    fn(boot) {
      make(
        action.Binding(..b, boot_id: boot),
        target(),
        window(),
        "Reason",
        string.repeat("b", 64),
      )
      |> result.is_error
      |> should.be_true
    },
  )
}

pub fn invalid_target_and_expiring_lease_test() {
  let t = target()
  list.each(
    [
      action.Target(..t, job: "other/job"),
      action.Target(..t, job: "uos/example/"),
      action.Target(..t, job: "uos/example/../bad"),
      action.Target(..t, worker: ""),
      action.Target(..t, attempt: 0),
      action.Target(..t, attempt: 2_147_483_648),
      action.Target(..t, lease_until_ns: 1_060_000_000_000),
      action.Target(..t, lease_until_ns: 1),
    ],
    fn(changed) {
      make(binding(), changed, window(), "Reason", string.repeat("b", 64))
      |> result.is_error
      |> should.be_true
    },
  )
}

pub fn invalid_digests_test() {
  let b = binding()
  list.each(
    [
      "",
      string.repeat("A", 64),
      string.repeat("g", 64),
      string.repeat("a", 63),
      string.repeat("a", 65),
    ],
    fn(value) {
      make(
        action.Binding(..b, candidate_sha256: value),
        target(),
        window(),
        "Reason",
        string.repeat("b", 64),
      )
      |> result.is_error
      |> should.be_true
      make(b, target(), window(), "Reason", value)
      |> result.is_error
      |> should.be_true
    },
  )
}

pub fn invalid_windows_test() {
  let w = window()
  list.each(
    [
      action.Window(..w, created_utc_ms: 0),
      action.Window(..w, created_boot_ms: -1),
      action.Window(..w, deadline_utc_ms: 1_000_000),
      action.Window(..w, deadline_boot_ms: 20_000),
      action.Window(..w, deadline_utc_ms: 1_060_001),
      action.Window(..w, deadline_utc_ms: 1_300_001, deadline_boot_ms: 320_001),
      action.Window(..w, deadline_utc_ms: 9_007_199_254_740_992),
      action.Window(..w, deadline_boot_ms: 9_007_199_254_740_992),
      action.Window(..w, created_utc_ms: 9_007_199_254_740_992),
    ],
    fn(changed) {
      make(binding(), target(), changed, "Reason", string.repeat("b", 64))
      |> result.is_error
      |> should.be_true
    },
  )
  make(
    binding(),
    target(),
    action.Window(..w, deadline_utc_ms: 1_300_000, deadline_boot_ms: 320_000),
    "Reason",
    string.repeat("b", 64),
  )
  |> result.is_ok
  |> should.be_true
}

pub fn bounded_reason_and_control_bytes_test() {
  list.each(
    [
      "",
      "   ",
      string.repeat("x", 257),
      "x\u{0}y",
      "x\u{1}y",
      "x\u{2}y",
      "x\u{3}y",
      "x\u{4}y",
      "x\u{5}y",
      "x\u{6}y",
      "x\u{7}y",
      "x\u{8}y",
      "x\u{9}y",
      "x\u{a}y",
      "x\u{b}y",
      "x\u{c}y",
      "x\u{d}y",
      "x\u{e}y",
      "x\u{f}y",
      "x\u{10}y",
      "x\u{11}y",
      "x\u{12}y",
      "x\u{13}y",
      "x\u{14}y",
      "x\u{15}y",
      "x\u{16}y",
      "x\u{17}y",
      "x\u{18}y",
      "x\u{19}y",
      "x\u{1a}y",
      "x\u{1b}y",
      "x\u{1c}y",
      "x\u{1d}y",
      "x\u{1e}y",
      "x\u{1f}y",
      "x\u{7f}y",
    ],
    fn(reason) {
      make(binding(), target(), window(), reason, string.repeat("b", 64))
      |> result.is_error
      |> should.be_true
    },
  )
  make(
    binding(),
    target(),
    window(),
    string.repeat("é", 129),
    string.repeat("b", 64),
  )
  |> result.is_error
  |> should.be_true
  make(
    binding(),
    target(),
    window(),
    string.repeat("é", 128),
    string.repeat("b", 64),
  )
  |> result.is_ok
  |> should.be_true
  make(
    binding(),
    target(),
    window(),
    "Quote \" and slash \\ retained",
    string.repeat("b", 64),
  )
  |> result.is_ok
  |> should.be_true
}

pub fn exact_expiry_and_domain_test() {
  let value = intent()
  action.valid_at(value, "nas-1.tail55d152.ts.net", "boot-1", 1_000_000, 20_000)
  |> should.be_true
  action.valid_at(value, "nas-1.tail55d152.ts.net", "boot-1", 1_059_999, 79_999)
  |> should.be_true
  action.valid_at(value, "nas-1.tail55d152.ts.net", "boot-1", 1_060_000, 80_000)
  |> should.be_false
  action.valid_at(value, "nas-1.tail55d152.ts.net", "boot-1", 999_999, 20_000)
  |> should.be_false
  action.valid_at(value, "nas-1.tail55d152.ts.net", "boot-1", 1_000_000, 19_999)
  |> should.be_false
  action.valid_at(value, "vm-1.tail55d152.ts.net", "boot-1", 1_000_000, 20_000)
  |> should.be_false
  action.valid_at(value, "nas-1.tail55d152.ts.net", "boot-2", 1_000_000, 20_000)
  |> should.be_false
  action.valid_at(
    value,
    "nas-1.tail55d152.ts.net",
    "boot-1",
    9_007_199_254_740_992,
    20_000,
  )
  |> should.be_false
}

pub fn clock_jump_is_not_freshness_test() {
  let value = intent()
  action.valid_at(value, "nas-1.tail55d152.ts.net", "boot-1", 1_012_000, 30_000)
  |> should.be_true
  action.valid_at(value, "nas-1.tail55d152.ts.net", "boot-1", 1_012_001, 30_000)
  |> should.be_false
  action.valid_at(value, "nas-1.tail55d152.ts.net", "boot-1", 1_008_000, 30_000)
  |> should.be_true
  action.valid_at(value, "nas-1.tail55d152.ts.net", "boot-1", 1_007_999, 30_000)
  |> should.be_false
}

fn different(actual: String, expected: String) {
  should.be_false(actual == expected)
}

pub fn execution_context_is_signed_and_effect_is_stable_test() {
  let b = binding()
  let e = b.execution
  list.each(
    [
      action.Execution(..e, mapping_id: "mapping-2"),
      action.Execution(..e, lease_id: "lease-2"),
      action.Execution(..e, fencing_token: 4),
      action.Execution(..e, profile_sha256: string.repeat("e", 64)),
    ],
    fn(changed) {
      let i =
        made(
          action.Binding(..b, execution: changed),
          target(),
          window(),
          "Operator requested cancellation",
          string.repeat("b", 64),
        )
      action.digest(i) |> different(action.digest(intent()))
      action.effect_id(i) |> should.equal(action.effect_id(intent()))
      action.matches_execution(i, e) |> should.be_false
    },
  )
  action.execution_profile(intent()) |> should.equal(string.repeat("d", 64))
  action.worker_artifact(intent()) |> should.equal(string.repeat("a", 64))
}

pub fn execution_context_rejects_invalid_fields_test() {
  let b = binding()
  let e = b.execution
  list.each(
    [
      action.Execution(..e, mapping_id: ""),
      action.Execution(..e, lease_id: "../unsafe"),
      action.Execution(..e, fencing_token: 0),
      action.Execution(..e, fencing_token: 9_007_199_254_740_992),
      action.Execution(..e, profile_sha256: string.repeat("D", 64)),
    ],
    fn(changed) {
      make(
        action.Binding(..b, execution: changed),
        target(),
        window(),
        "Reason",
        string.repeat("b", 64),
      )
      |> result.is_error
      |> should.be_true
    },
  )
}

pub fn native_deadline_cannot_expand_intent_test() {
  list.each([0, 1_000_000, 1_060_001], fn(deadline) {
    action.native_request(intent(), deadline)
    |> result.is_error
    |> should.be_true
    action.native_request_hash(intent(), deadline)
    |> result.is_error
    |> should.be_true
  })
  action.native_request(intent(), 1_000_001) |> result.is_ok |> should.be_true
  action.native_request(intent(), 1_060_000) |> result.is_ok |> should.be_true
  let assert Ok(a) = action.native_request_hash(intent(), 1_060_000)
  let assert Ok(b) = action.native_request_hash(intent(), 1_030_000)
  a |> different(b)
}

pub fn native_request_independent_golden_vector_test() {
  let assert Ok(raw) = action.native_request(intent(), 1_030_000)
  raw
  |> should.equal(
    "{\"schema\":\"uos.sa-plan.cancel-job-request.v1\",\"mapping_id\":\"mapping-1\",\"effect_id\":\"4718876da639ea2767fcc2578ffad8bc7a981b2414339b28ac7e35a557565899\",\"intent_sha256\":\"e260ea54e3a9e1a36278c0a00a770cf3b8e7c8d340ad2886bdaf3091db4bc4e4\",\"owner\":\"operator\",\"lease_id\":\"lease-1\",\"fencing_token\":3,\"target_job_id\":\"uos/example/job1\",\"target_worker\":\"worker\",\"target_attempt\":2,\"target_lease_until_ns\":2000000000000,\"reason\":\"Operator requested cancellation\",\"expires_at_ns\":1030000000000}",
  )
  action.native_request_hash(intent(), 1_030_000)
  |> should.equal(Ok(
    "717d84d1568e5e123bbbd42fbf0f2a7feb8b5b9356947f52a3d1687b15aed411",
  ))
}
