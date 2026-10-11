//// Gleam-owned POLICY for the private read-only Sa-plan observer.
////
//// This module is the policy boundary that acceptance criterion 4 requires:
//// Gleam owns the expected source/binary pin, the request identity and the
//// deadline. The native guardian owns ONLY the child process mechanics, and
//// the Erlang FFI is a thin spawn adapter.
////
//// An earlier draft left policy in Erlang with a comment claiming Gleam was
//// "intended" to own it. A comment is not an owner, so this module exists.

import gleam/int
import gleam/list
import gleam/result
import gleam/string

/// A pinned observation request. Every field is policy-checked here before any
/// process is created.
pub type ObserveRequest {
  ObserveRequest(
    guardian_exe: String,
    guardian_sha256: String,
    observer_exe: String,
    observer_sha256: String,
    db_path: String,
    plan_id: String,
    task_id: TaskSelector,
    deadline_ms: Int,
    max_bytes: Int,
  )
}

/// Minimal local selector to keep the adapter surface explicit.
pub type TaskSelector {
  NoTask
  Task(String)
}

pub type PolicyError {
  ExePathNotAbsolute(String)
  InvalidDigest(String)
  InvalidDeadline(Int)
  InvalidMaxBytes(Int)
  InvalidPlanId(String)
  InvalidTaskId(String)
  InvalidDbPath(String)
}

pub const min_deadline_ms = 1

pub const max_deadline_ms = 60_000

pub const min_max_bytes = 1

pub const max_max_bytes = 4_194_304

pub const digest_len = 64

fn hex_char(c: String) -> Bool {
  string.contains("0123456789abcdef", c)
}

/// A digest pin must be exactly 64 lowercase hex characters. A basename is
/// never accepted as provenance.
pub fn valid_digest(d: String) -> Bool {
  string.length(d) == digest_len
  && list.all(string.to_graphemes(d), hex_char)
}

pub fn valid_absolute(p: String) -> Bool {
  string.starts_with(p, "/") && string.length(p) <= 4096
}

fn id_char(c: String) -> Bool {
  string.contains(
    "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_/.",
    c,
  )
}

pub fn valid_id(s: String) -> Bool {
  let n = string.length(s)
  n > 0 && n <= 200 && list.all(string.to_graphemes(s), id_char)
}

/// The whole policy decision. Pure, total, and the single place where a
/// request becomes admissible.
pub fn check(req: ObserveRequest) -> Result(ObserveRequest, PolicyError) {
  use _ <- result.try(case valid_absolute(req.guardian_exe) {
    True -> Ok(Nil)
    False -> Error(ExePathNotAbsolute(req.guardian_exe))
  })
  use _ <- result.try(case valid_absolute(req.observer_exe) {
    True -> Ok(Nil)
    False -> Error(ExePathNotAbsolute(req.observer_exe))
  })
  use _ <- result.try(case valid_digest(req.guardian_sha256) {
    True -> Ok(Nil)
    False -> Error(InvalidDigest(req.guardian_sha256))
  })
  use _ <- result.try(case valid_digest(req.observer_sha256) {
    True -> Ok(Nil)
    False -> Error(InvalidDigest(req.observer_sha256))
  })
  use _ <- result.try(case valid_absolute(req.db_path) {
    True -> Ok(Nil)
    False -> Error(InvalidDbPath(req.db_path))
  })
  use _ <- result.try(case valid_id(req.plan_id) {
    True -> Ok(Nil)
    False -> Error(InvalidPlanId(req.plan_id))
  })
  use _ <- result.try(case req.task_id {
    NoTask -> Ok(Nil)
    Task(t) ->
      case valid_id(t) {
        True -> Ok(Nil)
        False -> Error(InvalidTaskId(t))
      }
  })
  use _ <- result.try(case
    req.deadline_ms >= min_deadline_ms && req.deadline_ms <= max_deadline_ms
  {
    True -> Ok(Nil)
    False -> Error(InvalidDeadline(req.deadline_ms))
  })
  use _ <- result.try(case
    req.max_bytes >= min_max_bytes && req.max_bytes <= max_max_bytes
  {
    True -> Ok(Nil)
    False -> Error(InvalidMaxBytes(req.max_bytes))
  })
  Ok(req)
}

/// Argument vector handed to the guardian. PRIVATE: reachable only via
/// observe/1, so an unchecked caller cannot hand the adapter its own argv.
/// It was public in the preserved 87eb8095 iteration, which let a caller skip
/// check/1 entirely.
fn guardian_argv(req: ObserveRequest) -> List(String) {
  let base = [
    "--exe", req.observer_exe,
    "--sha256", req.observer_sha256,
    "--deadline-ms", int.to_string(req.deadline_ms),
    "--max-bytes", int.to_string(req.max_bytes),
    "--", "--db", req.db_path,
    "--plan", req.plan_id,
    "--deadline-ms", int.to_string(req.deadline_ms),
  ]
  case req.task_id {
    NoTask -> base
    Task(t) -> list.append(base, ["--task", t])
  }
}

pub fn error_code(e: PolicyError) -> String {
  case e {
    ExePathNotAbsolute(_) -> "exe_path_must_be_absolute"
    InvalidDigest(_) -> "invalid_expected_digest"
    InvalidDeadline(_) -> "invalid_deadline"
    InvalidMaxBytes(_) -> "invalid_max_bytes"
    InvalidPlanId(_) -> "invalid_plan_id"
    InvalidTaskId(_) -> "invalid_task_id"
    InvalidDbPath(_) -> "database_path_must_be_absolute"
  }
}

// ---------------------------------------------------------------------------
// Typed orchestration entrypoint. This is the ONLY public way to run an
// observation: policy is applied, the argv is built here, then the adapter is
// called. The adapter re-validates shape as defence in depth.

/// One explicit typed success value. The guardian receipt and the observer
/// payload are SEPARATE fields; an earlier iteration returned the receipt line
/// concatenated in front of the JSON, which made the success body ambiguous.
pub type Observation {
  Observation(
    guardian_result: String,
    cleanup: String,
    child_exit: Int,
    payload: BitArray,
  )
}

@external(erlang, "sa_plan_observer_ffi", "observe_checked")
fn ffi_observe_checked(
  guardian: String,
  guardian_sha256: String,
  argv: List(String),
  deadline_ms: Int,
  max_bytes: Int,
) -> Result(Observation, String)

/// Run a pinned, bounded, read-only Sa-plan observation.
/// On success the payload field holds ONLY the observer JSON; the guardian
/// receipt fields are returned alongside it, never concatenated into it.
pub fn observe(req: ObserveRequest) -> Result(Observation, String) {
  case check(req) {
    Error(e) -> Error(error_code(e))
    Ok(r) ->
      ffi_observe_checked(
        r.guardian_exe,
        r.guardian_sha256,
        guardian_argv(r),
        r.deadline_ms,
        r.max_bytes,
      )
  }
}
