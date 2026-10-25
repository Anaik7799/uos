//// Development AGY dispatcher. Canonical Sa-plan and coordinator fences precede
//// every launch/collection. A completed model response is never task admission.
//// Finite existing private profile; no credential bytes are stored in UOS.

import cepaf_gleam/harness/admission as a
import cepaf_gleam/harness/agy_job_result as outcome
import cepaf_gleam/harness/clock
import cepaf_gleam/harness/development as dev
import cepaf_gleam/harness/files
import gleam/dict
import gleam/dynamic/decode
import gleam/erlang/process
import gleam/int
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import simplifile
import uos_swarm/session_authority
import uos_swarm/session_sync

pub const runtime_root = "/home/an/uos-agent-runtime/20261024-0555"

pub const model = "gemini-4-argon-high"

pub type Request {
  Request(
    binding: dev.Binding,
    job: String,
    job_worker: String,
    job_attempt: Int,
    workspace: String,
    workspace_epoch: Int,
    mode: String,
    seconds: Int,
    prompt: String,
  )
}

pub fn decoder() {
  use plan <- decode.field("plan", decode.string)
  use task <- decode.field("task", decode.string)
  use worker <- decode.field("worker", decode.string)
  use attempt <- decode.field("attempt", decode.int)
  use session <- decode.field("session", decode.string)
  use epoch <- decode.field("epoch", decode.int)
  use job <- decode.field("job", decode.string)
  use job_worker <- decode.field("job_worker", decode.string)
  use job_attempt <- decode.field("job_attempt", decode.int)
  use workspace <- decode.field("workspace", decode.string)
  use workspace_epoch <- decode.field("workspace_epoch", decode.int)
  use mode <- decode.field("mode", decode.string)
  use seconds <- decode.field("seconds", decode.int)
  use prompt <- decode.field("prompt", decode.string)
  decode.success(Request(
    dev.Binding("development", plan, task, worker, attempt, session, epoch),
    job,
    job_worker,
    job_attempt,
    workspace,
    workspace_epoch,
    mode,
    seconds,
    prompt,
  ))
}

pub fn identifier(s: String) -> Bool {
  string.byte_size(s) > 0
  && string.byte_size(s) <= 240
  && list.all(string.to_graphemes(s), fn(c) {
    string.contains(
      "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_./:",
      c,
    )
  })
}

pub fn validate(r: Request) -> Result(Nil, String) {
  a.require(
    list.all(
      [
        r.job,
        r.job_worker,
        r.binding.plan,
        r.binding.task,
        r.binding.worker,
        r.binding.session,
      ],
      identifier,
    )
      && string.starts_with(r.job, r.binding.plan <> "/")
      && a.component(r.workspace)
      && r.workspace_epoch > 0
      && r.binding.attempt > 0
      && r.binding.epoch > 0
      && r.job_attempt > 0
      && { r.mode == "review" || r.mode == "code" }
      && r.seconds >= 30
      && r.seconds <= 900
      && string.byte_size(r.prompt) > 0
      && string.byte_size(r.prompt) <= 65_536,
    "request_identity_scope_or_budget",
  )
}

fn workspace(r: Request) -> String {
  dev.root <> "/.uos-workspaces/" <> r.workspace
}

pub fn job_binding_matches(raw: String, r: Request) -> Bool {
  let d = {
    use plan <- decode.field("plan", decode.string)
    use task <- decode.field("task", decode.string)
    use worker <- decode.field("parent_worker", decode.string)
    use attempt <- decode.field("parent_attempt", decode.int)
    use space <- decode.field("workspace", decode.string)
    use mode <- decode.field("mode", decode.string)
    decode.success(
      plan == r.binding.plan
      && task == r.binding.task
      && worker == r.binding.worker
      && attempt == r.binding.attempt
      && space == r.workspace
      && mode == r.mode,
    )
  }
  json.parse(raw, d) == Ok(True)
}

fn read_job(r: Request) -> Result(outcome.JobClaim, String) {
  use _ <- result.try(validate(r))
  let sql =
    "SELECT id,worker,lease_owner,attempt,state,lease_until_ns,args FROM sa_plan_job WHERE id='"
    <> r.job
    <> "';"
  use raw <- result.try(dev.bounded(
    "/usr/bin/sqlite3",
    ["-readonly", "-json", dev.root <> "/var/sa-plan/uos.sqlite3", sql],
    3000,
  ))
  let row = {
    use id <- decode.field("id", decode.string)
    use worker <- decode.field("worker", decode.string)
    use owner <- decode.field("lease_owner", decode.string)
    use attempt <- decode.field("attempt", decode.int)
    use state <- decode.field("state", decode.string)
    use deadline <- decode.field("lease_until_ns", decode.int)
    use args <- decode.field("args", decode.string)
    decode.success(#(
      outcome.JobClaim(id, worker, owner, attempt, state, deadline),
      args,
    ))
  }
  use rows <- result.try(
    json.parse(raw, decode.list(row))
    |> result.map_error(fn(_) { "canonical_job_decode" }),
  )
  case rows {
    [#(claim, args)] -> {
      use _ <- result.try(a.require(
        job_binding_matches(args, r),
        "job_parent_scope_mismatch",
      ))
      Ok(claim)
    }
    _ -> Error("canonical_job_missing_or_ambiguous")
  }
}

/// UTC task nanoseconds and boot-domain coordinator microseconds remain distinct.
pub fn long_job_window(
  task_ns: Int,
  coordinator_us: Int,
  utc_us: Int,
  boot_us: Int,
  seconds: Int,
) -> Bool {
  seconds >= 30
  && seconds <= 900
  && utc_us > 0
  && boot_us >= 0
  && task_ns > { utc_us + { seconds + 30 } * 1_000_000 } * 1000
  && coordinator_us > boot_us + { seconds + 30 } * 1_000_000
}

/// Launch reserves the requested model runtime. Terminal collection starts no
/// model work and reserves 40s plus the existing 30s margin (70s total), matching
/// the development fence. This phase is chosen internally, never by request JSON.
pub type FencePhase {
  Launch
  TerminalCollection
}

pub fn fence_runtime(phase: FencePhase, requested: Int) -> Result(Int, String) {
  case requested >= 30 && requested <= 900 {
    False -> Error("invalid_requested_runtime")
    True ->
      case phase {
        Launch -> Ok(requested)
        TerminalCollection -> Ok(40)
      }
  }
}

fn fence(r: Request, phase: FencePhase) -> Result(Nil, String) {
  use _ <- result.try(validate(r))
  use seconds <- result.try(fence_runtime(phase, r.seconds))
  use parent <- result.try(dev.fence_for(r.binding, 70_000))
  use _ <- result.try(files.checked_path(
    dev.root,
    ".uos-workspaces/" <> r.workspace,
  ))
  use info <- result.try(
    simplifile.link_info(workspace(r))
    |> result.map_error(fn(_) { "workspace_unavailable" }),
  )
  use _ <- result.try(a.require(
    simplifile.file_info_type(info) == simplifile.Directory,
    "workspace_not_real_directory",
  ))
  use _ <- result.try(dev.bounded_observation(
    fn() {
      session_authority.observe(fn(state, boot, now) {
        use _ <- result.try(session_sync.check(
          state,
          r.binding.session,
          "workspace:" <> workspace(r),
          r.workspace_epoch,
          boot,
          now,
        ))
        use lease <- result.try(
          dict.get(state.coordinator.leases, "workspace:" <> workspace(r))
          |> result.map_error(fn(_) { "workspace_lease_missing" }),
        )
        use _ <- result.try(a.require(
          lease.expires_us > now + { seconds + 30 } * 1_000_000,
          "workspace_lease_too_short",
        ))
        Ok(json.bool(True))
      })
    },
    2000,
  ))
  use row <- result.try(read_job(r))
  use now <- result.try(clock.observe())
  use _ <- result.try(clock.continuity(parent.clock, now))
  use _ <- result.try(a.require(
    long_job_window(
      parent.lease_until_ns,
      parent.coordinator_lease_until_us,
      now.sample.observed.utc_us,
      now.sample.observed.boot_us,
      seconds,
    ),
    "parent_lease_too_short_for_job",
  ))
  outcome.authorize(
    row,
    r.job,
    r.job_worker,
    r.job_attempt,
    now.sample.observed.utc_us * 1000,
    seconds,
  )
}

fn request(name: String) -> Result(#(Request, String), String) {
  use _ <- result.try(a.require(a.component(name), "request_filename"))
  use raw <- result.try(files.read(runtime_root, name))
  use r <- result.try(
    json.parse(raw, decoder()) |> result.map_error(fn(_) { "request_json" }),
  )
  use _ <- result.try(validate(r))
  Ok(#(r, raw))
}

pub fn unit_id(raw: String) -> String {
  "uos-agy-" <> string.slice(files.digest(raw), 0, 24)
}

fn unit_args(unit: String, seconds: Int) -> List(String) {
  [
    "--user",
    "--unit=" <> unit,
    "--property=RuntimeMaxSec=" <> int.to_string(seconds),
    "--property=KillMode=control-group",
    "--property=TimeoutStopSec=3",
    "--property=NoNewPrivileges=yes",
    "--property=MemoryMax=2G",
    "--property=TasksMax=256",
    "--property=RemainAfterExit=yes",
  ]
}

pub fn sandbox_args(r: Request, unit: String) -> List(String) {
  let base = [
    "--ro-bind",
    "/",
    "/",
    "--proc",
    "/proc",
    "--dev",
    "/dev",
    "--tmpfs",
    "/tmp",
    "--tmpfs",
    "/run/user/1000",
    "--tmpfs",
    "/run/dbus",
    "--unshare-pid",
    "--unshare-ipc",
    "--die-with-parent",
    "--new-session",
    "--tmpfs",
    "/home/an/.gemini",
    "--bind",
    runtime_root <> "/profile",
    "/home/an/.gemini/antigravity-cli",
    "--bind",
    runtime_root <> "/config",
    "/home/an/.config/antigravity",
    "--ro-bind",
    runtime_root <> "/ipc",
    "/run/user/1000",
  ]
  let writable = case r.mode {
    "code" -> ["--bind", workspace(r), workspace(r)]
    _ -> []
  }
  list.append(
    base,
    list.append(writable, [
      "--chdir",
      "/tmp",
      "/usr/bin/env",
      "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/" <> unit <> ".bus",
      "/home/an/.local/bin/agy",
      "--print",
      r.prompt,
      "--model",
      model,
      "--effort",
      "high",
      "--mode",
      "accept-edits",
      "--dangerously-skip-permissions",
      "--disable-slash-commands",
      "--sandbox",
      "--output-format",
      "json",
      "--print-timeout",
      int.to_string(r.seconds - 10) <> "s",
    ]),
  )
}

fn socket_ready(path: String, remaining: Int) -> Result(Nil, String) {
  case dev.bounded("/usr/bin/test", ["-S", path], 1000) {
    Ok(_) -> Ok(Nil)
    Error(_) if remaining > 0 -> {
      process.sleep(50)
      socket_ready(path, remaining - 1)
    }
    _ -> Error("authentication_proxy_not_ready")
  }
}

/// An exclusive durable receipt prohibits automatic retry after ambiguous launch.
pub fn launch(name: String) -> Result(String, String) {
  use #(r, raw) <- result.try(request(name))
  use _ <- result.try(fence(r, Launch))
  let unit = unit_id(raw)
  use _ <- result.try(files.create(runtime_root, "active-job.json", raw))
  use _ <- result.try(files.create(runtime_root, unit <> ".stdout.json", ""))
  use _ <- result.try(files.create(runtime_root, unit <> ".stderr.log", ""))
  let socket = runtime_root <> "/ipc/" <> unit <> ".bus"
  use _ <- result.try(dev.bounded(
    "/usr/bin/systemd-run",
    list.append(unit_args(unit <> "-auth", r.seconds + 30), [
      "/usr/bin/xdg-dbus-proxy",
      "unix:path=/run/user/1000/bus",
      socket,
      "--filter",
      "--talk=org.freedesktop.secrets",
    ]),
    5000,
  ))
  use _ <- result.try(socket_ready(socket, 20))
  use _ <- result.try(fence(r, Launch))
  use _ <- result.try(dev.bounded(
    "/usr/bin/systemd-run",
    list.append(
      unit_args(unit, r.seconds),
      list.append(
        [
          "--property=StandardOutput=file:"
            <> runtime_root
            <> "/"
            <> unit
            <> ".stdout.json",
          "--property=StandardError=file:"
            <> runtime_root
            <> "/"
            <> unit
            <> ".stderr.log",
          "/usr/bin/bwrap",
        ],
        sandbox_args(r, unit),
      ),
    ),
    5000,
  ))
  Ok(
    json.to_string(
      json.object([
        #("status", json.string("DISPATCHED_NOT_COMPLETE")),
        #("unit", json.string(unit)),
        #("job", json.string(r.job)),
        #("request_sha256", json.string(files.digest(raw))),
        #("model", json.string(model)),
        #("runtime_seconds", json.int(r.seconds)),
      ]),
    ),
  )
}

fn property(unit: String, key: String) -> Result(String, String) {
  dev.bounded(
    "/usr/bin/systemctl",
    ["--user", "show", unit <> ".service", "--value", "-p", key],
    3000,
  )
  |> result.map(string.trim)
}

/// Collecting preserves failures. Only a nonempty model response can succeed,
/// and even that requires independent task-specific verification before closure.
pub fn collect(name: String) -> Result(String, String) {
  use #(r, raw) <- result.try(request(name))
  use active <- result.try(files.read(runtime_root, "active-job.json"))
  use _ <- result.try(a.require(active == raw, "active_request_mismatch"))
  let unit = unit_id(raw)
  use state <- result.try(property(unit, "SubState"))
  use _ <- result.try(a.require(
    state == "exited" || state == "failed" || state == "dead",
    "JOB_RUNNING_OR_UNKNOWN",
  ))
  use exit_raw <- result.try(property(unit, "ExecMainStatus"))
  use exit_code <- result.try(
    int.parse(exit_raw) |> result.map_error(fn(_) { "exit_status_unknown" }),
  )
  use result_name <- result.try(property(unit, "Result"))
  use stderr <- result.try(files.read(runtime_root, unit <> ".stderr.log"))
  use stdout <- result.try(files.read(runtime_root, unit <> ".stdout.json"))
  let classified =
    outcome.classify(exit_code, result_name != "success", stderr, stdout)
  let authority = fence(r, TerminalCollection)
  let status = case classified, authority {
    Ok(_), Ok(_) -> "MODEL_RESPONSE_COMPLETE_REVIEW_REQUIRED"
    _, Error(_) -> "STALE_AUTHORITY_HOLD"
    Error(_), _ -> "INCOMPLETE_OR_FAILED"
  }
  let report =
    json.to_string(
      json.object([
        #("status", json.string(status)),
        #("job", json.string(r.job)),
        #("request_sha256", json.string(files.digest(raw))),
        #("unit_result", json.string(result_name)),
        #("exit_code", json.int(exit_code)),
        #("classification", case classified {
          Ok(done) ->
            json.object([
              #("conversation_id", json.string(done.conversation_id)),
              #("response_sha256", json.string(files.digest(done.response))),
            ])
          Error(reason) -> json.object([#("error", json.string(reason))])
        }),
        #("authority", json.string(string.inspect(authority))),
        #("task_completion", json.bool(False)),
        #("runtime_admission", json.bool(False)),
      ]),
    )
  use _ <- result.try(files.create(
    runtime_root,
    unit <> ".receipt.json",
    report,
  ))
  use _ <- result.try(dev.bounded(
    "/usr/bin/systemctl",
    ["--user", "stop", unit <> ".service", unit <> "-auth.service"],
    5000,
  ))
  use _ <- result.try(
    simplifile.delete(runtime_root <> "/active-job.json")
    |> result.map_error(fn(_) { "active_receipt_cleanup_failed" }),
  )
  Ok(report)
}
