//// Immutable controlled-action request data, NOT an approval or execution grant.
//// Syntax checks do not authenticate caller identities, nonce entropy, artifacts,
//// clocks or canonical leases. A future store/executor must observe those,
//// authenticate required independent receipts and atomically consume the effect.

import cepaf_gleam/harness/files
import cepaf_gleam/harness/telegram_ingress_guard as guard
import gleam/json
import gleam/list
import gleam/string

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

pub opaque type Intent {
  Intent(
    binding: Binding,
    target: Target,
    window: Window,
    reason: String,
    nonce: String,
    digest: String,
    effect_id: String,
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
  binding: Binding,
  target: Target,
  window: Window,
  reason: String,
  nonce: String,
) -> String {
  json.array(
    [
      json.string("uos.telegram.action-intent.v1"),
      json.string("cancel_job_lease"),
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

fn logical_effect(binding: Binding, target: Target) -> String {
  json.array(
    [
      json.string("uos.telegram.action-effect.v1"),
      json.int(binding.bot_id),
      json.int(binding.chat_id),
      json.int(binding.user_id),
      json.int(binding.update_id),
      json.string("cancel_job_lease"),
      json.string(target.job),
    ],
    fn(value) { value },
  )
  |> json.to_string
  |> files.digest
}

/// Validated request data only. No actual allowlist, job or authority is observed.
pub fn new(
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
        binding,
        target,
        window,
        reason,
        nonce,
        files.digest(payload(binding, target, window, reason, nonce)),
        logical_effect(binding, target),
      ))
  }
}

/// Internal canonical request bytes; contains identities and reason, not a public reply.
pub fn canonical_json(value: Intent) -> String {
  payload(value.binding, value.target, value.window, value.reason, value.nonce)
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

pub fn matches_target(value: Intent, target: Target) -> Bool {
  value.target == target
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
