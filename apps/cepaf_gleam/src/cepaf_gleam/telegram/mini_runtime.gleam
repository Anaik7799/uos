import cepaf_gleam/harness/files
//// Server-owned Mini App configuration and bounded read adapters.
//// No credential or initData is returned to the browser or placed on the bus.

import cepaf_gleam/config/mesh_source
import cepaf_gleam/telegram/mini_config
import cepaf_gleam/ha/beam_metrics
import cepaf_gleam/harness/observer_policy as observer
import cepaf_gleam/harness/telegram_coordination_reader as coordination
import cepaf_gleam/harness/telegram_fmea_reader as fmea
import cepaf_gleam/harness/telegram_store as history_store
import cepaf_gleam/harness/telegram_store_transport as history_transport
import cepaf_gleam/harness/telegram_verification_reader as verification
import cepaf_gleam/telegram/mini_api as api
import cepaf_gleam/telegram/mini_health
import cepaf_gleam/telegram/mini_dashboard
import cepaf_gleam/telegram/mini_evidence
import cepaf_gleam/telegram/mini_memory
import cepaf_gleam/telegram/mini_history
import cepaf_gleam/telegram/mini_podman
import cepaf_gleam/telegram/mini_telemetry
import cepaf_gleam/telegram/mini_zenoh
import cepaf_gleam/telegram/types
import cepaf_gleam/zenoh/rest as zenoh_rest
import gleam/bit_array
import gleam/dict
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

@external(erlang, "cepaf_gleam_ffi", "get_env")
fn get_env(name: String) -> Result(String, Nil)

@external(erlang, "mini_app_clock_ffi", "unix_seconds")
pub fn clock() -> Int

type TimeUnit {
  Nanosecond
}

@external(erlang, "erlang", "system_time")
fn system_time(unit: TimeUnit) -> Int

pub fn task_state(state: String, lease: Option(String), now_ns: Int) -> String {
  case state == "executing", lease {
    True, Some(raw) ->
      case int.parse(raw) {
        Ok(until) if until > now_ns -> state
        Ok(_) -> state <> " (lease expired)"
        Error(_) -> state <> " (lease unknown)"
      }
    True, None -> state <> " (lease unknown)"
    False, _ -> state
  }
}

pub fn load_configuration() -> Result(api.Configuration, api.ApiError) {
  use token <- result.try(
    get_env("UOS_TELEGRAM_MINI_BOT_TOKEN")
    |> result.replace_error(api.ConfigurationUnavailable),
  )
  use identities <- result.try(
    get_env("UOS_TELEGRAM_MINI_IDENTITIES")
    |> result.replace_error(api.ConfigurationUnavailable),
  )
  use _ <- result.try(case string.byte_size(identities) <= 8192 {
    True -> Ok(Nil)
    False -> Error(api.ConfigurationUnavailable)
  })
  let identity_decoder = {
    use user <- decode.field("user_id", decode.int)
    use chat <- decode.optional_field(
      "chat_id",
      None,
      decode.optional(decode.int),
    )
    decode.success(api.AllowedIdentity(user, chat))
  }
  use allowed <- result.try(
    json.parse(identities, decode.list(identity_decoder))
    |> result.replace_error(api.ConfigurationUnavailable),
  )
  api.configuration(token, allowed, 300)
}

fn observe_tasks() -> Result(api.Observation, Nil) {
  use plan <- result.try(get_env("UOS_TELEGRAM_MINI_PLAN"))
  use _ <- result.try(case observer.valid_id(plan) {
    True -> Ok(Nil)
    False -> Error(Nil)
  })
  let database =
    get_env("UOS_TELEGRAM_MINI_DATABASE")
    |> result.unwrap("/home/an/NAS-setup/uos/var/sa-plan/uos.sqlite3")
  use observation <- result.try(
    observer.observe(observer.ObserveRequest(
      guardian_exe: "/home/an/NAS-setup/uos/tools/validation/obs_guardian.exe",
      guardian_sha256: "b7bab1a85ffa3689a2548ff28a391e659c0537104dec7be0f774bae1820ec4be",
      observer_exe: "/home/an/NAS-setup/uos/tools/validation/sa_plan_observer.exe",
      observer_sha256: "5b9dab694c7486f39decb0f3db4238b74753941a659106d5e12fee3c0fe656e2",
      db_path: database,
      plan_id: plan,
      task_id: observer.NoTask,
      deadline_ms: 2500,
      max_bytes: 262_144,
    ))
    |> result.replace_error(Nil),
  )
  use raw <- result.try(bit_array.to_string(observation.payload))
  let observed_now = system_time(Nanosecond)
  let task_decoder = {
    use id <- decode.field("task_id", decode.string)
    use state <- decode.field("state", decode.string)
    use lease <- decode.field("lease_until_ns", decode.optional(decode.string))
    let display_state = task_state(state, lease, observed_now)
    decode.success(#(id, display_state))
  }
  let decoder = {
    use returned_plan <- decode.field("plan_id", decode.string)
    use tasks <- decode.field("tasks", decode.list(task_decoder))
    decode.success(#(returned_plan, tasks))
  }
  use #(returned_plan, tasks) <- result.try(
    json.parse(raw, decoder) |> result.replace_error(Nil),
  )
  use _ <- result.try(case returned_plan == plan && list.length(tasks) <= 90 {
    True -> Ok(Nil)
    False -> Error(Nil)
  })
  let fields =
    dict.from_list([
      #("Plan", plan),
      #("Task count", int.to_string(list.length(tasks))),
      ..list.map(tasks, fn(t) { #("Task " <> t.0, t.1) })
    ])
  Ok(api.Observed(clock(), "canonical_sa_plan_snapshot", fields))
}

fn observe_fmea() -> Result(api.Observation, Nil) {
  use path <- result.try(get_env("UOS_TELEGRAM_MINI_FMEA_SOURCE"))
  use plan <- result.try(get_env("UOS_TELEGRAM_MINI_FMEA_PLAN"))
  use _ <- result.try(
    case fmea.valid_source(path, False) && observer.valid_id(plan) {
      True -> Ok(Nil)
      False -> Error(Nil)
    },
  )
  use raw <- result.try(
    fmea.observe(path, plan, "") |> result.replace_error(Nil),
  )
  mini_evidence.fmea(raw, plan, clock()) |> result.replace_error(Nil)
}

fn observe_verification() -> Result(api.Observation, Nil) {
  use path <- result.try(get_env("UOS_TELEGRAM_MINI_VERIFICATION_SOURCE"))
  use sha <- result.try(get_env("UOS_TELEGRAM_MINI_VERIFICATION_SHA256"))
  use candidate <- result.try(get_env(
    "UOS_TELEGRAM_MINI_VERIFICATION_CANDIDATE",
  ))
  let source = verification.Source(path, sha, candidate)
  use _ <- result.try(case verification.valid_source(source, False) {
    True -> Ok(Nil)
    False -> Error(Nil)
  })
  use raw <- result.try(
    verification.observe(source, "checklist", "") |> result.replace_error(Nil),
  )
  mini_evidence.verification(raw, candidate, clock())
  |> result.replace_error(Nil)
}

fn observe_podman() -> Result(api.Observation, Nil) {
  use sha <- result.try(get_env("UOS_TELEGRAM_MINI_PODMAN_SHA256"))
  use _ <- result.try(case observer.valid_digest(sha) {
    True -> Ok(Nil)
    False -> Error(Nil)
  })
  mini_podman.observe(mini_podman.live_io(sha)) |> result.replace_error(Nil)
}

fn observe_history_environment(read: api.AuthorizedRead) -> Result(api.Observation, Nil) {
  use token <- result.try(get_env("UOS_TELEGRAM_MINI_BOT_TOKEN"))
  use raw <- result.try(get_env("UOS_TELEGRAM_MINI_HISTORY_GRANTS"))
  use _ <- result.try(case string.byte_size(raw) <= 8192 {
    True -> Ok(Nil)
    False -> Error(Nil)
  })
  let grant_decoder = {
    use user <- decode.field("user_id", decode.int)
    use chat <- decode.field("chat_id", decode.int)
    decode.success(mini_history.Grant(user, chat))
  }
  use grants <- result.try(
    json.parse(raw, decode.list(grant_decoder)) |> result.replace_error(Nil),
  )
  use config <- result.try(
    mini_history.configuration(token, grants) |> result.replace_error(Nil),
  )
  use database <- result.try(get_env("UOS_TELEGRAM_MINI_HISTORY_DATABASE"))
  let transport =
    history_transport.reviewed_local_configuration(
      "/home/an/NAS-setup/uos/tools/validation/telegram_store_transport_guardian.exe",
      "06a278afd304bb4752522bd632004eb35ecff8a1b65459a3607a70b24e67f0ab",
      "/home/an/NAS-setup/uos/tools/validation/telegram_store_recovery_worker.exe",
      "f4f249eaa6ff2c9f4b1bf8c6587426f283ec1754892e847568b5dd1712a55b1e",
      database,
    )
  mini_history.observe(
    config,
    read,
    fn(keys) {
      history_store.read_keys(transport, keys)
      |> result.replace_error("history_store_unavailable")
    },
    clock,
  )
  |> result.replace_error(Nil)
}

fn observe_zenoh(read: api.AuthorizedRead) -> api.Observation {
  let config = {
    use raw <- result.try(get_env("UOS_TELEGRAM_MINI_ZENOH_GRANTS"))
    use _ <- result.try(case string.byte_size(raw) <= 65_536 {
      True -> Ok(Nil)
      False -> Error(Nil)
    })
    let grant = {
      use user <- decode.field("user_id", decode.int)
      use topic <- decode.field("topic", decode.string)
      decode.success(mini_zenoh.Grant(user, topic))
    }
    use grants <- result.try(
      json.parse(raw, decode.list(grant)) |> result.replace_error(Nil),
    )
    mini_zenoh.configuration(grants) |> result.replace_error(Nil)
  }
  case config {
    Ok(config) -> mini_zenoh.observe(config, read, zenoh_rest.get, clock)
    Error(_) -> api.Unavailable("zenoh_configuration_unavailable")
  }
}

@external(erlang, "erlang", "monotonic_time")
fn monotonic_ms(unit: DashboardTimeUnit) -> Int

type DashboardTimeUnit {
  Millisecond
}

@external(erlang, "telegram_status_probe", "probe")
fn dashboard_probe(name: String, budget_ms: Int) -> Result(Int, String)

fn dashboard_podman(budget_ms: Int) -> Result(api.Observation, String) {
  use sha <- result.try(
    get_env("UOS_TELEGRAM_MINI_PODMAN_SHA256")
    |> result.replace_error("podman_configuration_unavailable"),
  )
  use _ <- result.try(case observer.valid_digest(sha) {
    True -> Ok(Nil)
    False -> Error("podman_configuration_unavailable")
  })
  mini_podman.observe_with_budget(mini_podman.live_io(sha), budget_ms)
}

fn dashboard_peers(budget_ms: Int) -> Result(String, String) {
  use database <- result.try(
    get_env("UOS_TELEGRAM_MINI_COORDINATION_DATABASE")
    |> result.replace_error("coordination_configuration_unavailable"),
  )
  coordination.observe_with_budget(database, "peers", budget_ms)
}

@external(erlang, "beam_metrics_ffi", "snapshot_checked")
fn dashboard_metrics(budget_ms: Int) -> Result(beam_metrics.BeamMetrics, String)

fn dashboard_io() -> mini_dashboard.Io {
  mini_dashboard.Io(
    podman: dashboard_podman,
    peers: dashboard_peers,
    probe: dashboard_probe,
    metrics: dashboard_metrics,
    monotonic_ms: fn() { monotonic_ms(Millisecond) },
    unix_seconds: clock,
  )
}

pub fn observe(read: api.AuthorizedRead) -> api.Observation {
  case api.page(read) {
    types.MiniTelemetry -> mini_telemetry.observe()
    page -> mini_telemetry.with_span(page, fn() { observe_backend(read) })
  }
}

fn observe_backend(read: api.AuthorizedRead) -> api.Observation {
  case api.page(read) {
    types.MiniPlanning ->
      observe_tasks()
      |> result.unwrap(api.Unavailable("task_observation_failed"))
    types.MiniFmea ->
      observe_fmea()
      |> result.unwrap(api.Unavailable("fmea_observation_failed"))
    types.MiniVerification ->
      observe_verification()
      |> result.unwrap(api.Unavailable("verification_observation_failed"))
    types.MiniPodman ->
      observe_podman()
      |> result.unwrap(api.Unavailable("podman_observation_failed"))
    types.MiniConversation ->
      observe_history(read)
      |> result.unwrap(api.Unavailable("history_observation_failed"))
    types.MiniZenohBrowser -> observe_zenoh(read)
    types.MiniDashboard -> mini_dashboard.observe(dashboard_io())
    types.MiniHealthGrid -> observe_health() |> result.unwrap(api.Unavailable("health_observation_failed"))
    types.MiniConfig -> mini_config.project(mesh_source.load(),clock())
    types.MiniCockpit
    | types.MiniImmune
    | types.MiniInference
    | types.MiniFederation
    | types.MiniTelemetry -> api.Unavailable("backend_not_integrated")
  }
}

fn observe_history(read: api.AuthorizedRead) -> Result(api.Observation, Nil) {
  case get_env("UOS_MINI_CONTROL_FIXTURE_PROFILE") {
    Error(_) -> observe_history_environment(read)
    Ok(raw) -> {
      use expected <- result.try(get_env("UOS_MINI_CONTROL_FIXTURE_SHA256"))
      use _ <- result.try(case files.digest(raw) == expected {True -> Ok(Nil) False -> Error(Nil)})
      use token <- result.try(get_env("UOS_TELEGRAM_MINI_BOT_TOKEN"))
      use config <- result.try(mini_memory.configuration(raw,token) |> result.replace_error(Nil))
      case config {
        None -> observe_history_environment(read)
        Some(c) -> mini_memory.observe(c,api.user_id(read),api.chat_id(read),clock()) |> result.replace_error(Nil)
      }
    }
  }
}

fn observe_health() -> Result(api.Observation,Nil) {
  use path <- result.try(get_env("UOS_TELEGRAM_MINI_HEALTH_WORKER"))
  use sha <- result.try(get_env("UOS_TELEGRAM_MINI_HEALTH_SHA256"))
  mini_health.observe(mini_health.live_io(path,sha)) |> result.replace_error(Nil)
}
