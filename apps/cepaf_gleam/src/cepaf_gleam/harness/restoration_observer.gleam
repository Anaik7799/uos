//// Finite read-only operational dashboard observer. Sa-plan job and runtime
//// lease authorize observation; model outputs never authorize publication.

import cepaf_gleam/harness/admission as a
import cepaf_gleam/harness/agy_dispatch as agy
import cepaf_gleam/harness/clock
import cepaf_gleam/harness/dashboard_refresh as refresh
import cepaf_gleam/harness/development as dev
import cepaf_gleam/harness/files
import cepaf_gleam/harness/recovery_activation as io
import cepaf_gleam/harness/value as v
import gleam/bit_array
import gleam/dict
import gleam/erlang/atom
import gleam/erlang/process
import gleam/int
import gleam/io as gleam_io
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/otp/static_supervisor
import gleam/otp/supervision
import gleam/result
import gleam/string
import restoration_runtime_cli as controls
import session_store_cli
import simplifile
import uos_swarm/session_authority
import uos_swarm/session_sync

pub const state_name = "20261024-0712-recovery-state.json"

pub const html_name = "20261024-0712-recovery-dashboard.html"

const static_root = dev.root <> "/apps/cepaf_gleam/priv/static"

const runtime_resource = "runtime:recovery-dashboard-observer"

const base = "http://nas-1.tail55d152.ts.net:4100"

const worker = "uos-dashboard-observer-20261024"

const plan = "uos/agy-operations/20261024-0642"

@external(erlang, "erlang", "apply")
fn metadata(
  module: atom.Atom,
  function: atom.Atom,
  args: List(atom.Atom),
) -> BitArray

pub fn control_ids() -> json.Json {
  json.object([
    #("base", controls.control_ids()),
    #(
      "observer",
      json.object(
        list.map(
          [
            "cepaf_gleam@harness@restoration_observer",
            "cepaf_gleam@harness@dashboard_refresh", "restoration_observer_cli",
            "cepaf_gleam@harness@agy_dispatch",
            "cepaf_gleam@harness@recovery_activation", "cepaf_gleam_ffi",
            "session_store_cli", "simplifile", "simplifile_erl",
          ],
          fn(name) {
            #(
              name,
              json.string(
                metadata(atom.create(name), atom.create("module_info"), [
                  atom.create("md5"),
                ])
                |> bit_array.base16_encode,
              ),
            )
          },
        ),
      ),
    ),
  ])
}

pub type Config {
  Config(
    job: String,
    attempt: Int,
    session: String,
    epoch: Int,
    boot_id: String,
    expires_us: Int,
    source_commit: String,
    digest: String,
  )
}

type Message {
  Tick
}

type State {
  State(
    config: Config,
    subject: process.Subject(Message),
    previous: Option(refresh.State),
    last_heartbeat_us: Int,
  )
}

fn text(doc: v.Value, key: String) -> Result(String, String) {
  case v.get(doc, key) {
    Ok(v.Text(s)) -> Ok(s)
    _ -> Error("text:" <> key)
  }
}

fn number(doc: v.Value, key: String) -> Result(Int, String) {
  case v.get(doc, key) {
    Ok(v.Integer(n)) -> Ok(n)
    _ -> Error("integer:" <> key)
  }
}

fn parse(s: String) -> Result(v.Value, String) {
  json.parse(s, v.decoder()) |> result.map_error(fn(_) { "invalid_json" })
}

fn sql(query: String) -> Result(v.Value, String) {
  use raw <- result.try(dev.bounded(
    "/usr/bin/sqlite3",
    ["-readonly", "-json", dev.root <> "/var/sa-plan/uos.sqlite3", query],
    3000,
  ))
  parse(raw)
}

fn one(data: v.Value) -> Result(v.Value, String) {
  case data {
    v.Array([row]) -> Ok(row)
    _ -> Error("exactly_one_row_required")
  }
}

pub fn load(name: String, review_name: String) -> Result(Config, String) {
  use _ <- result.try(a.require(
    a.component(name) && a.component(review_name),
    "private_filenames",
  ))
  use raw <- result.try(files.read(agy.runtime_root, name))
  use doc <- result.try(parse(raw))
  use review_raw <- result.try(files.read(agy.runtime_root, review_name))
  use review <- result.try(parse(review_raw))
  use job <- result.try(text(doc, "job"))
  use attempt <- result.try(number(doc, "attempt"))
  use session <- result.try(text(doc, "session"))
  use epoch <- result.try(number(doc, "epoch"))
  use boot <- result.try(text(doc, "boot_id"))
  use expiry <- result.try(number(doc, "expires_us"))
  use revision <- result.try(text(doc, "source_commit"))
  use ids <- result.try(v.get(doc, "control_ids"))
  use reviewer <- result.try(text(review, "reviewer"))
  use html_hash <- result.try(io.sha256_file(static_root <> "/" <> html_name))
  use _ <- result.try(a.require(
    v.get(doc, "schema") == Ok(v.Text("uos.dashboard-observer.v1"))
      && v.get(doc, "scope") == Ok(v.Text("read_only_dashboard"))
      && v.get(doc, "worker") == Ok(v.Text(worker))
      && v.get(doc, "plan") == Ok(v.Text(plan))
      && v.get(doc, "output") == Ok(v.Text(state_name))
      && v.get(doc, "html_sha256") == Ok(v.Text(html_hash))
      && controls.controls_match(ids, control_ids())
      && v.get(review, "verdict") == Ok(v.Text("PASS"))
      && v.get(review, "config_sha256") == Ok(v.Text(files.digest(raw)))
      && reviewer != worker
      && string.length(reviewer) > 0
      && string.starts_with(job, plan <> "/")
      && agy.identifier(job)
      && agy.identifier(session)
      && attempt > 0
      && epoch > 0
      && string.length(revision) == 40
      && list.all(string.to_graphemes(revision), fn(c) {
      string.contains("0123456789abcdef", c)
    }),
    "reviewed_finite_observer_binding",
  ))
  let cfg =
    Config(
      job,
      attempt,
      session,
      epoch,
      boot,
      expiry,
      revision,
      files.digest(raw),
    )
  use now <- result.try(clock.observe())
  use _ <- result.try(a.require(
    expiry > now.sample.observed.utc_us + 60_000_000
      && expiry <= now.sample.observed.utc_us + 3_600_000_000,
    "finite_observer_window",
  ))
  Ok(cfg)
}

fn job_fence(cfg: Config) -> Result(Int, String) {
  use row <- result.try(
    sql(
      "SELECT state,worker,lease_owner,attempt,lease_until_ns,json_extract(args,'$.config_sha256') AS config_sha256,json_extract(args,'$.scope') AS scope FROM sa_plan_job WHERE id='"
      <> cfg.job
      <> "';",
    )
    |> result.try(one),
  )
  use now <- result.try(clock.observe())
  use attempt <- result.try(number(row, "attempt"))
  use deadline <- result.try(number(row, "lease_until_ns"))
  use _ <- result.try(a.require(
    v.get(row, "state") == Ok(v.Text("executing"))
      && v.get(row, "worker") == Ok(v.Text(worker))
      && v.get(row, "lease_owner") == Ok(v.Text(worker))
      && attempt == cfg.attempt
      && v.get(row, "config_sha256") == Ok(v.Text(cfg.digest))
      && v.get(row, "scope") == Ok(v.Text("read_only_dashboard"))
      && now.sample.observed.domain.boot_id == cfg.boot_id
      && now.sample.observed.utc_us + 35_000_000 < cfg.expires_us
      && deadline > { now.sample.observed.utc_us + 35_000_000 } * 1000,
    "canonical_observer_job_expired_or_changed",
  ))
  Ok(now.sample.observed.boot_us)
}

fn runtime_fence(cfg: Config) -> Result(Nil, String) {
  use _ <- result.try(dev.bounded_observation(
    fn() {
      session_authority.observe(fn(state, boot, now) {
        use _ <- result.try(session_sync.check(
          state,
          cfg.session,
          runtime_resource,
          cfg.epoch,
          boot,
          now,
        ))
        use lease <- result.try(
          dict.get(state.coordinator.leases, runtime_resource)
          |> result.map_error(fn(_) { "runtime_lease_missing" }),
        )
        use _ <- result.try(a.require(
          lease.expires_us > now + 35_000_000,
          "runtime_lease_too_short",
        ))
        Ok(json.bool(True))
      })
    },
    3000,
  ))
  Ok(Nil)
}

fn heartbeat(cfg: Config, now: Int) -> Result(Nil, String) {
  use _ <- result.try(dev.bounded_observation(
    fn() {
      session_authority.run([
        "heartbeat",
        cfg.session,
        cfg.source_commit,
        "job:" <> cfg.job <> ",scope:read_only_dashboard",
        "dashboard-beat-" <> int.to_string(now),
      ])
    },
    3000,
  ))
  Ok(Nil)
}

fn observed_json(operation: fn() -> Result(String, String)) -> json.Json {
  let observed = io.utc_now_iso8601()
  case operation() |> result.try(parse) {
    Ok(value) ->
      json.object([
        #("status", json.string("ok")),
        #("observed_at", json.string(observed)),
        #("data", v.encode(value)),
        #("error", json.null()),
      ])
    Error(reason) ->
      json.object([
        #("status", json.string("error")),
        #("observed_at", json.string(observed)),
        #("data", json.null()),
        #("error", json.string(reason)),
      ])
  }
}

fn get_json(url: String) -> json.Json {
  observed_json(fn() {
    dev.bounded(
      "/usr/bin/curl",
      ["--max-time", "3", "--fail", "--silent", "--show-error", url],
      4000,
    )
  })
}

fn rows_with_expiry(data: v.Value) -> json.Json {
  case data {
    v.Array(rows) ->
      json.array(rows, fn(row) {
        let expired = v.get(row, "expired") == Ok(v.Integer(1))
        v.set(row, "expired", v.Boolean(expired)) |> v.encode
      })
    _ -> json.null()
  }
}

fn task_filter() -> String {
  "plan_id IN ('uos/telegram-runtime/20261001-1150','uos/telegram-admission/20261001-1015','uos/telegram-tools/20261011-1115','uos/telegram-resume/20261012-0216','uos/telegram-reclaim-tool/20261012-0226','uos/telegram-dashboard/20261012-0230') OR plan_id LIKE '%20261024%'"
}

fn completion_marker() -> Result(String, String) {
  dev.bounded(
    "/usr/bin/sqlite3",
    [
      "-readonly",
      dev.root <> "/var/sa-plan/uos.sqlite3",
      "SELECT count(*) || ':' || COALESCE(MAX(completed_at_ns),0) FROM sa_plan_task WHERE state='completed';",
    ],
    3000,
  )
  |> result.map(string.trim)
}

fn http_status(path: String) -> json.Json {
  let now = io.utc_now_iso8601()
  let result =
    dev.bounded(
      "/usr/bin/curl",
      [
        "--max-time",
        "2",
        "--silent",
        "--show-error",
        "-o",
        "/dev/null",
        "-w",
        "%{http_code}",
        base <> path,
      ],
      3000,
    )
  let status = case result {
    Ok(raw) -> int.parse(string.trim(raw)) |> result.unwrap(0)
    _ -> 0
  }
  json.object([
    #("path", json.string(path)),
    #("status", json.int(status)),
    #("observed_at", json.string(now)),
    #("error", case result {
      Ok(_) -> json.null()
      Error(e) -> json.string(e)
    }),
  ])
}

pub fn snapshot(cfg: Config, reason: String) -> Result(String, String) {
  use tasks <- result.try(sql(
    "SELECT plan_id,id,title,state,worker,attempt,(state='executing' AND lease_until_ns<cast(strftime('%s','now') AS integer)*1000000000) AS expired,CASE WHEN id LIKE '%MEDIA%' THEN 'Enable verified media workflows' WHEN id LIKE '%COMMAND%' THEN 'Verify command execution' WHEN id LIKE '%GATEWAY%' THEN 'Connect authorized ingress and durable delivery' WHEN id LIKE '%MINI%' THEN 'Provide authenticated Mini App APIs' WHEN id LIKE '%E2E%' OR id LIKE '%ACCEPT%' THEN 'Prove real user journey' WHEN id LIKE '%RELEASE%' OR id='ADMISSION' THEN 'Verify exact release and admission' ELSE 'Support reliable operation and evidence' END AS contribution FROM sa_plan_task WHERE "
    <> task_filter()
    <> " ORDER BY plan_id,id;",
  ))
  use counts <- result.try(
    sql(
      "SELECT count(*) AS total,sum(state='completed') AS completed,sum(state='available') AS available,sum(state='executing' AND lease_until_ns<cast(strftime('%s','now') AS integer)*1000000000) AS expired FROM sa_plan_task WHERE "
      <> task_filter()
      <> ";",
    )
    |> result.try(one),
  )
  use jobs <- result.try(sql(
    "SELECT id,worker,state,attempt,(state='executing' AND lease_until_ns<cast(strftime('%s','now') AS integer)*1000000000) AS expired FROM sa_plan_job WHERE id LIKE '%20261024%' ORDER BY id;",
  ))
  use global_tasks <- result.try(sql(
    "SELECT state,count(*) AS n,sum(state='executing' AND lease_until_ns<cast(strftime('%s','now') AS integer)*1000000000) AS expired FROM sa_plan_task GROUP BY state;",
  ))
  use global_jobs <- result.try(sql(
    "SELECT state,count(*) AS n,sum(state='executing' AND lease_until_ns<cast(strftime('%s','now') AS integer)*1000000000) AS expired FROM sa_plan_job GROUP BY state;",
  ))
  use workflows <- result.try(sql(
    "SELECT state,count(*) AS n FROM sa_plan_workflow GROUP BY state;",
  ))
  let service_time = io.utc_now_iso8601()
  let service =
    dev.bounded(
      "/usr/bin/systemctl",
      [
        "--user",
        "show",
        "c3i-gleam-server.service",
        "uos-cognitive-worker.service",
        "uos-telegram-bridge.service",
        "c3i-zenoh-router-1.service",
        "uos-ecology@20260930-0807-5fdb0051061cf1c2dd7cf6e8a5af8f842df205d4c10d6ae04cd41fe1397f2872.service",
        "-p",
        "Id",
        "-p",
        "ActiveState",
        "-p",
        "SubState",
        "-p",
        "NRestarts",
      ],
      3000,
    )
  let coordinator =
    observed_json(fn() {
      dev.bounded_observation(
        fn() {
          session_store_cli.run([
            "verify",
            dev.root <> "/var/coordination/tri-agent/coordinator.sqlite3",
          ])
          |> result.map_error(string.inspect)
        },
        3000,
      )
    })
  let forecast = get_json(base <> "/api/v1/forecast/health")
  let ecology =
    get_json("http://nas-1.tail55d152.ts.net:4110/api/v1/ecology/swarm")
  let http = list.map(["/", "/planning", "/wiki", "/zk"], http_status)
  let observed = io.utc_now_iso8601()
  let checks = [
    "Clock and timestamp",
    "Tailscale navigation",
    "Fractal scope",
    "Knowledge links",
    "Dependency exclusions",
    "Pure graph boundary",
    "Storage interlock",
    "C1-C8 verification",
    "Mathematical gates",
    "Relevant test modalities",
    "Regression evidence",
    "Gleam/OTP supervision",
    "Hermes bounded evidence",
    "ZigVM deterministic kernel",
    "MAX inference observation",
    "Trace correlation",
    "Independent release review",
    "Standalone Jujutsu",
  ]
  Ok(
    json.to_string(
      json.object([
        #("schema", json.string("uos.restoration.snapshot.v1")),
        #("updated_at", json.string(observed)),
        #("overall", json.string("PARTIALLY_OPERATIONAL")),
        #("goal_met", json.bool(False)),
        #("plan", json.string(plan)),
        #(
          "producer",
          json.object([
            #("job", json.string(cfg.job)),
            #("session", json.string(cfg.session)),
          ]),
        ),
        #(
          "refresh",
          json.object([
            #("interval_seconds", json.int(300)),
            #("poll_seconds", json.int(5)),
            #("reason", json.string(reason)),
            #("expires_at", json.string(iso_from_us(cfg.expires_us))),
          ]),
        ),
        #("tasks", rows_with_expiry(tasks)),
        #("counts", v.encode(counts)),
        #("jobs", rows_with_expiry(jobs)),
        #(
          "global",
          json.object([
            #("tasks", v.encode(global_tasks)),
            #("jobs", v.encode(global_jobs)),
            #("workflows", v.encode(workflows)),
          ]),
        ),
        #(
          "services",
          json.object([
            #("observed_at", json.string(service_time)),
            #(
              "status",
              json.string(case service {
                Ok(raw) ->
                  case services_active(raw) {
                    True -> "ok"
                    False -> "degraded"
                  }
                _ -> "error"
              }),
            ),
            #("raw", json.string(result.unwrap(service, ""))),
            #("error", case service {
              Error(e) -> json.string(e)
              _ -> json.null()
            }),
          ]),
        ),
        #("coordinator", coordinator),
        #("forecast", forecast),
        #("ecology", ecology),
        #("http", json.array(http, fn(x) { x })),
        #(
          "as_is",
          json.array(
            [
              #(
                "Coordinator",
                "Recovered at 06:40 UTC; inspect current typed replay observation below.",
              ),
              #(
                "AGY execution",
                "Actual Gemini 4 Argon High launch/collect verified; 14 scoped tests passed at c9b9c6.",
              ),
              #(
                "Telegram",
                "Commands, media, gateway, Mini App and live acceptance remain incomplete. 82 scoped independent cases passed earlier; this is not a feature percentage.",
              ),
              #(
                "Learning",
                "Live forecast and ecology observations below; no demonstrated globally optimal learning or calibrated improvement.",
              ),
              #(
                "Integration",
                "No new mainline merge or global admission from these component observations.",
              ),
            ],
            fn(p) { json.array([p.0, p.1], json.string) },
          ),
        ),
        #(
          "to_be",
          json.array(
            [
              "Known usable user flows with live acceptance",
              "Truthful fresh telemetry and task status",
              "Isolated, bounded and independently verified AGY work",
              "Stable reviewed release integrated using standalone Jujutsu",
            ],
            json.string,
          ),
        ),
        #(
          "risks",
          json.array(
            [
              #(
                "Coordinator recurrence",
                "Critical",
                "Contained; isolation remains required",
                "Keep unrestricted writers stopped; use typed dispatch.",
              ),
              #(
                "Telegram acceptance",
                "High",
                "Pending",
                "Complete command/media/gateway/Mini App paths and authorized live tests.",
              ),
              #(
                "Telemetry overclaim",
                "High",
                "Candidate review pending",
                "Display unknown/error and verify actual network behavior.",
              ),
              #(
                "Dashboard freshness",
                "High",
                "Finite observer job",
                "Show source timestamps, expiry and stale states; no admission inference.",
              ),
              #(
                "Learning effectiveness",
                "High",
                "Not demonstrated",
                "Precommit outcomes; measure calibration, rework, cost and acceptance.",
              ),
              #(
                "Mainline integration",
                "High",
                "Pending stabilization",
                "Merge only independently verified stable candidates.",
              ),
            ],
            fn(r) {
              json.object([
                #("name", json.string(r.0)),
                #("criticality", json.string(r.1)),
                #("status", json.string(r.2)),
                #("mitigation", json.string(r.3)),
              ])
            },
          ),
        ),
        #("checks", json.array(checks, json.string)),
        #(
          "evidence",
          json.object([
            #(
              "summary",
              json.string(
                "Coordinator restoration and isolated AGY dispatch are verified components; full restoration is incomplete.",
              ),
            ),
            #(
              "counts_note",
              json.string(
                "Task counts are not functional coverage. Source errors and expired claims are nonpassing. Historical component tests are not rerun by this observer.",
              ),
            ),
            #(
              "risk",
              json.string(
                "Authority and dependency readiness precede criticality × STPA × FMEA × dependency × impact.",
              ),
            ),
            #(
              "coordinator_candidate",
              json.string("fd85fe743c7476c58ef34586f367caafecd6d1e8"),
            ),
            #(
              "cycle_candidate",
              json.string(
                "Earlier scoped oracle:332rows,24holds,0releases; refresh separately",
              ),
            ),
            #("live_runtime_verified", json.bool(False)),
            #("main_includes_candidate", json.bool(False)),
          ]),
        ),
      ]),
    ),
  )
}

@external(erlang, "cepaf_gleam_ffi", "nanos_to_iso8601")
fn iso_from_ns(ns: Int) -> String

fn iso_from_us(us: Int) -> String {
  iso_from_ns(us * 1000)
}

fn publish(cfg: Config, body: String) -> Result(Nil, String) {
  use _ <- result.try(job_fence(cfg))
  use _ <- result.try(runtime_fence(cfg))
  use #(_, _, _, now) <- result.try(io.ffi_clock())
  let temp = state_name <> "." <> int.to_string(now) <> ".tmp"
  use _ <- result.try(files.create(static_root, temp, body))
  simplifile.rename(
    static_root <> "/" <> temp,
    static_root <> "/" <> state_name,
  )
  |> result.map_error(fn(_) { "snapshot_atomic_rename_failed" })
}

fn step(state: State) -> Result(State, String) {
  use now <- result.try(job_fence(state.config))
  use _ <- result.try(runtime_fence(state.config))
  use beat <- result.try(case now - state.last_heartbeat_us >= 60_000_000 {
    True -> {
      use _ <- result.try(heartbeat(state.config, now))
      Ok(now)
    }
    False -> Ok(state.last_heartbeat_us)
  })
  use _ <- result.try(runtime_fence(state.config))
  use marker <- result.try(completion_marker())
  use due <- result.try(refresh.due(now, marker, state.previous))
  case due {
    False -> Ok(State(..state, last_heartbeat_us: beat))
    True -> {
      let reason = case state.previous {
        None -> "startup"
        Some(previous) if previous.completion_marker != marker ->
          "task_completion"
        _ -> "300_seconds"
      }
      use body <- result.try(snapshot(state.config, reason))
      use _ <- result.try(publish(state.config, body))
      Ok(
        State(
          ..state,
          previous: Some(refresh.State(now, marker)),
          last_heartbeat_us: beat,
        ),
      )
    }
  }
}

fn on_message(state: State, _: Message) -> actor.Next(State, Message) {
  case step(state) {
    Ok(next) -> {
      let _ = process.send_after(state.subject, 5000, Tick)
      actor.continue(next)
    }
    Error(reason) -> {
      log("HOLD", reason, state.config.job)
      actor.stop()
    }
  }
}

fn log(status: String, detail: String, job: String) {
  let now = io.utc_now_iso8601()
  gleam_io.println(
    json.to_string(
      json.object([
        #("status", json.string(status)),
        #("detail", json.string(detail)),
        #("job", json.string(job)),
        #("observed_at", json.string(now)),
        #("fractal_layer", json.int(3)),
        #("trace_id", json.string(string.slice(files.digest(job), 0, 32))),
        #("span_id", json.string(string.slice(files.digest(now), 0, 16))),
      ]),
    ),
  )
}

pub fn run(name: String, review: String) -> Result(Nil, String) {
  use cfg <- result.try(load(name, review))
  use _ <- result.try(job_fence(cfg))
  use _ <- result.try(runtime_fence(cfg))
  let child_pid = process.new_subject()
  let child =
    supervision.worker(fn() {
      let started =
        actor.new_with_initialiser(5000, fn(subject) {
          let _ = process.send_after(subject, 0, Tick)
          Ok(
            actor.initialised(State(cfg, subject, None, -60_000_000))
            |> actor.returning(subject),
          )
        })
        |> actor.on_message(on_message)
        |> actor.start()
      case started {
        Ok(worker) -> {
          process.send(child_pid, worker.pid)
          Ok(worker)
        }
        Error(e) -> Error(e)
      }
    })
    |> supervision.restart(supervision.Temporary)
  use _ <- result.try(
    static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.restart_tolerance(0, 1)
    |> static_supervisor.add(child)
    |> static_supervisor.start()
    |> result.map_error(string.inspect),
  )
  use pid <- result.try(
    process.receive(child_pid, 1000)
    |> result.map_error(fn(_) { "worker_pid_unavailable" }),
  )
  wait_for_worker(pid, 3_600_000)
}

/// The CLI terminates the VM and its finite unit when this returns.
pub fn wait_for_worker(
  pid: process.Pid,
  timeout_ms: Int,
) -> Result(Nil, String) {
  let monitor = process.monitor(pid)
  let selector =
    process.new_selector()
    |> process.select_specific_monitor(monitor, fn(down) { down })
  let ended = process.selector_receive(selector, timeout_ms)
  process.demonitor_process(monitor)
  case ended {
    Ok(_) -> Error("observer_worker_stopped")
    Error(_) -> Error("observer_process_window_expired")
  }
}

pub fn services_active(raw: String) -> Bool {
  let states =
    string.split(raw, "\n")
    |> list.filter(fn(line) { string.starts_with(line, "ActiveState=") })
  list.length(states) == 5
  && list.all(states, fn(line) { line == "ActiveState=active" })
}
