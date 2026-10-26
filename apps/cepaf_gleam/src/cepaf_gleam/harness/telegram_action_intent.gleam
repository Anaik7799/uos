//// Immutable controlled-action request data, NOT an approval or execution grant.
//// Syntax checks do not authenticate caller identities, nonce entropy, artifacts,
//// clocks or canonical leases. A future store/executor must observe those,
//// authenticate required independent receipts and atomically consume the effect.

import cepaf_gleam/harness/files
import cepaf_gleam/harness/telegram_ingress_guard as guard
import gleam/json
import gleam/list
import gleam/result
import gleam/string

pub type Execution {
  Execution(
    mapping_id: String,
    lease_id: String,
    fencing_token: Int,
    profile_sha256: String,
  )
}

pub type Binding {
  Binding(
    bot_id: Int,
    chat_id: Int,
    user_id: Int,
    update_id: Int,
    plan: String,
    task: String,
    worker: String,
    attempt: Int,
    epoch: Int,
    candidate_sha256: String,
    host: String,
    boot_id: String,
    execution: Execution,
  )
}

pub type Target {
  Target(job: String, worker: String, attempt: Int, lease_until_ns: Int)
}

pub type Window {
  Window(
    created_utc_ms: Int,
    created_boot_ms: Int,
    deadline_utc_ms: Int,
    deadline_boot_ms: Int,
  )
}

/// What an approval authorises. The kind is inside the signed canonical
/// payload and the logical effect, and every receipt's `purpose` must equal
/// its name, so receipts for one kind can never satisfy another.
pub type Kind {
  /// Revoke one Sa-plan job lease (`/cancel_job_lease`).
  CancelJobLease
  /// Run the pinned verify guardian for one reserved verify job (`/verify`).
  VerifyProfile
}

pub fn kind_name(kind: Kind) -> String {
  case kind {
    CancelJobLease -> "cancel_job_lease"
    VerifyProfile -> "verify_profile"
  }
}

pub fn kind_from_name(name: String) -> Result(Kind, Nil) {
  case name {
    "cancel_job_lease" -> Ok(CancelJobLease)
    "verify_profile" -> Ok(VerifyProfile)
    _ -> Error(Nil)
  }
}

pub opaque type Intent {
  Intent(
    binding: Binding,
    target: Target,
    window: Window,
    reason: String,
    nonce: String,
    digest: String,
    effect_id: String,
    kind: Kind,
  )
}

const max_time = 9_007_199_254_740_991

const max_attempt = 2_147_483_647

fn bounded_ascii(value: String, limit: Int, alphabet: String) -> Bool {
  string.byte_size(value) > 0
  && string.byte_size(value) <= limit
  && list.all(string.to_graphemes(value), fn(char) {
    string.contains(alphabet, char)
  })
}

fn identifier(value: String) -> Bool {
  bounded_ascii(
    value,
    240,
    "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_./:",
  )
  && !string.contains(value, "..")
}

fn valid_host(value: String) -> Bool {
  bounded_ascii(
    value,
    253,
    "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-",
  )
  && !string.starts_with(value, ".")
  && !string.ends_with(value, ".")
  && !string.contains(value, "..")
}

fn valid_boot(value: String) -> Bool {
  bounded_ascii(
    value,
    128,
    "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_",
  )
}

fn positive_attempt(value: Int) -> Bool {
  value > 0 && value <= max_attempt
}

fn valid_execution(value: Execution) -> Bool {
  identifier(value.mapping_id)
  && identifier(value.lease_id)
  && value.fencing_token > 0
  && value.fencing_token <= max_time
  && guard.valid_digest(value.profile_sha256)
}

fn valid_binding(value: Binding) -> Bool {
  guard.valid_positive_id(value.bot_id)
  && guard.valid_chat_id(value.chat_id)
  && guard.valid_positive_id(value.user_id)
  && guard.valid_update_id(value.update_id)
  && list.all([value.plan, value.task, value.worker], identifier)
  && positive_attempt(value.attempt)
  && positive_attempt(value.epoch)
  && guard.valid_digest(value.candidate_sha256)
  && valid_host(value.host)
  && valid_boot(value.boot_id)
  && valid_execution(value.execution)
}

fn valid_window(value: Window) -> Bool {
  let utc = value.deadline_utc_ms - value.created_utc_ms
  let boot = value.deadline_boot_ms - value.created_boot_ms
  value.created_utc_ms > 0
  && value.created_boot_ms >= 0
  && list.all(
    [
      value.created_utc_ms,
      value.created_boot_ms,
      value.deadline_utc_ms,
      value.deadline_boot_ms,
    ],
    fn(time) { time >= 0 && time <= max_time },
  )
  && utc > 0
  && utc <= 300_000
  && boot == utc
}

fn valid_reason(value: String) -> Bool {
  string.byte_size(value) <= 256
  && string.trim(value) != ""
  && !list.any(
    [
      "\u{0}",
      "\u{1}",
      "\u{2}",
      "\u{3}",
      "\u{4}",
      "\u{5}",
      "\u{6}",
      "\u{7}",
      "\u{8}",
      "\u{9}",
      "\u{a}",
      "\u{b}",
      "\u{c}",
      "\u{d}",
      "\u{e}",
      "\u{f}",
      "\u{10}",
      "\u{11}",
      "\u{12}",
      "\u{13}",
      "\u{14}",
      "\u{15}",
      "\u{16}",
      "\u{17}",
      "\u{18}",
      "\u{19}",
      "\u{1a}",
      "\u{1b}",
      "\u{1c}",
      "\u{1d}",
      "\u{1e}",
      "\u{1f}",
      "\u{7f}",
    ],
    fn(control) { string.contains(value, control) },
  )
}

fn payload(
  kind: Kind,
  binding: Binding,
  target: Target,
  window: Window,
  reason: String,
  nonce: String,
) -> String {
  let execution = binding.execution
  json.array(
    [
      json.string("uos.telegram.action-intent.v2"),
      json.string(kind_name(kind)),
      json.int(binding.bot_id),
      json.int(binding.chat_id),
      json.int(binding.user_id),
      json.int(binding.update_id),
      json.string(binding.plan),
      json.string(binding.task),
      json.string(binding.worker),
      json.int(binding.attempt),
      json.int(binding.epoch),
      json.string(binding.candidate_sha256),
      json.string(binding.host),
      json.string(binding.boot_id),
      json.string(execution.mapping_id),
      json.string(execution.lease_id),
      json.int(execution.fencing_token),
      json.string(execution.profile_sha256),
      json.string(target.job),
      json.string(target.worker),
      json.int(target.attempt),
      json.int(target.lease_until_ns),
      json.int(window.created_utc_ms),
      json.int(window.created_boot_ms),
      json.int(window.deadline_utc_ms),
      json.int(window.deadline_boot_ms),
      json.string(reason),
      json.string(nonce),
    ],
    fn(value) { value },
  )
  |> json.to_string
}

fn logical_effect(kind: Kind, binding: Binding, target: Target) -> String {
  json.array(
    [
      json.string("uos.telegram.action-effect.v1"),
      json.int(binding.bot_id),
      json.int(binding.chat_id),
      json.int(binding.user_id),
      json.int(binding.update_id),
      json.string(kind_name(kind)),
      json.string(target.job),
    ],
    fn(value) { value },
  )
  |> json.to_string
  |> files.digest
}

/// Validated request data only. No actual allowlist, job or authority is observed.
/// A lease-cancellation intent; see `new_kind` for other kinds.
pub fn new(
  binding: Binding,
  target: Target,
  window: Window,
  reason: String,
  nonce: String,
) -> Result(Intent, String) {
  new_kind(CancelJobLease, binding, target, window, reason, nonce)
}

/// Validated request data of the given kind. The kind enters the signed
/// payload, the digest and the logical effect.
pub fn new_kind(
  kind: Kind,
  binding: Binding,
  target: Target,
  window: Window,
  reason: String,
  nonce: String,
) -> Result(Intent, String) {
  let prefix = binding.plan <> "/"
  let valid_target =
    identifier(target.job)
    && identifier(target.worker)
    && string.starts_with(target.job, prefix)
    && target.job != prefix
    && positive_attempt(target.attempt)
    && target.lease_until_ns <= 9_223_372_036_854_775_807
    && target.lease_until_ns > window.deadline_utc_ms * 1_000_000
  case
    valid_binding(binding)
    && valid_window(window)
    && valid_target
    && valid_reason(reason)
    && guard.valid_digest(nonce)
  {
    False -> Error("invalid_controlled_action_request")
    True ->
      Ok(Intent(
        binding: binding,
        target: target,
        window: window,
        reason: reason,
        nonce: nonce,
        digest: files.digest(payload(
          kind,
          binding,
          target,
          window,
          reason,
          nonce,
        )),
        effect_id: logical_effect(kind, binding, target),
        kind: kind,
      ))
  }
}

/// Internal canonical request bytes; contains identities and reason, not a public reply.
pub fn canonical_json(value: Intent) -> String {
  payload(
    value.kind,
    value.binding,
    value.target,
    value.window,
    value.reason,
    value.nonce,
  )
}

pub fn kind(value: Intent) -> Kind {
  value.kind
}

/// The receipt `purpose` every approver must sign for this intent.
pub fn purpose(value: Intent) -> String {
  kind_name(value.kind)
}

pub fn target(value: Intent) -> Target {
  value.target
}

pub fn digest(value: Intent) -> String {
  value.digest
}

/// Stable across attempt changes. The future durable store must enforce uniqueness
/// and reject a different request digest for the same logical effect.
pub fn effect_id(value: Intent) -> String {
  value.effect_id
}

pub fn matches_binding(value: Intent, binding: Binding) -> Bool {
  value.binding == binding
}

pub fn matches_execution(value: Intent, expected: Execution) -> Bool {
  value.binding.execution == expected
}

pub fn matches_target(value: Intent, target: Target) -> Bool {
  value.target == target
}

pub fn execution_profile(value: Intent) -> String {
  value.binding.execution.profile_sha256
}

pub fn worker_artifact(value: Intent) -> String {
  value.binding.candidate_sha256
}

pub fn native_request(
  value: Intent,
  expires_at_ms: Int,
) -> Result(String, String) {
  use _ <- result.try(native_cancel_kind(value))
  use _ <- result.try(native_deadline(value, expires_at_ms))
  Ok(json.to_string(native_value(value, expires_at_ms)))
}

/// The native cancel-once request exists only for lease cancellations; a
/// verify intent has no native cancellation form and must never gain one.
fn native_cancel_kind(value: Intent) -> Result(Nil, String) {
  case value.kind {
    CancelJobLease -> Ok(Nil)
    VerifyProfile -> Error("native_request_kind_mismatch")
  }
}

fn native_value(value: Intent, expires_at_ms: Int) -> json.Json {
  let binding = value.binding
  let execution = binding.execution
  let target = value.target
  json.object([
    #("schema", json.string("uos.sa-plan.cancel-job-request.v1")),
    #("mapping_id", json.string(execution.mapping_id)),
    #("effect_id", json.string(value.effect_id)),
    #("intent_sha256", json.string(value.digest)),
    #("owner", json.string(binding.worker)),
    #("lease_id", json.string(execution.lease_id)),
    #("fencing_token", json.int(execution.fencing_token)),
    #("target_job_id", json.string(target.job)),
    #("target_worker", json.string(target.worker)),
    #("target_attempt", json.int(target.attempt)),
    #("target_lease_until_ns", json.int(target.lease_until_ns)),
    #("reason", json.string(value.reason)),
    #("expires_at_ns", json.int(expires_at_ms * 1_000_000)),
  ])
}

/// Hash of the exact request and canonical mapping, not an execution grant.
pub fn native_request_hash(
  value: Intent,
  expires_at_ms: Int,
) -> Result(String, String) {
  use _ <- result.try(native_cancel_kind(value))
  use _ <- result.try(native_deadline(value, expires_at_ms))
  let binding = value.binding
  let execution = binding.execution
  let target = value.target
  json.array(
    [
      json.string("uos.sa-plan.cancel-job-once.v1"),
      json.string(execution.mapping_id),
      json.string(value.effect_id),
      json.string(value.digest),
      json.string(binding.worker),
      json.string(execution.lease_id),
      json.int(execution.fencing_token),
      json.string(target.job),
      json.string(target.worker),
      json.int(target.attempt),
      json.int(target.lease_until_ns),
      json.string(value.reason),
      json.int(expires_at_ms * 1_000_000),
      json.string(binding.plan),
      json.string(binding.task),
    ],
    fn(item) { item },
  )
  |> json.to_string
  |> files.digest
  |> Ok
}

fn native_deadline(value: Intent, expires_at_ms: Int) -> Result(Nil, String) {
  case
    expires_at_ms > value.window.created_utc_ms
    && expires_at_ms <= value.window.deadline_utc_ms
  {
    True -> Ok(Nil)
    False -> Error("invalid_native_action_deadline")
  }
}

/// Pure freshness predicate on supplied observations, never an execution grant.
/// The caller must obtain a synchronized clock and fresh canonical fences.
pub fn valid_at(
  value: Intent,
  host: String,
  boot_id: String,
  now_utc_ms: Int,
  now_boot_ms: Int,
) -> Bool {
  let window = value.window
  let delta =
    now_utc_ms
    - window.created_utc_ms
    - { now_boot_ms - window.created_boot_ms }
  host == value.binding.host
  && boot_id == value.binding.boot_id
  && now_utc_ms >= window.created_utc_ms
  && now_utc_ms <= max_time
  && now_boot_ms >= window.created_boot_ms
  && now_boot_ms <= max_time
  && now_utc_ms < window.deadline_utc_ms
  && now_boot_ms < window.deadline_boot_ms
  && delta >= -2000
  && delta <= 2000
}

/// Pure receipt-time bounds in milliseconds, not authentication or authority.
pub fn valid_receipt_window(
  value: Intent,
  now_utc_ms: Int,
  issued_at_ms: Int,
  not_before_ms: Int,
  expires_at_ms: Int,
) -> Bool {
  value.window.created_utc_ms <= issued_at_ms
  && issued_at_ms <= not_before_ms
  && not_before_ms <= now_utc_ms
  && now_utc_ms < expires_at_ms
  && expires_at_ms <= value.window.deadline_utc_ms
}

/// Exact arguments approved for this request; command aliases use the shared parser.
pub fn command_args(value: Intent) -> String {
  kind_name(value.kind) <> " " <> value.target.job <> " -- " <> value.reason
}
