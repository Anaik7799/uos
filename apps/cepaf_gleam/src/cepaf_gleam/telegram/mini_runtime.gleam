//// Server-owned Mini App configuration and bounded read adapters.
//// No credential or initData is returned to the browser or placed on the bus.

import cepaf_gleam/harness/observer_policy as observer
import cepaf_gleam/telegram/mini_api as api
import cepaf_gleam/telegram/types
import gleam/bit_array
import gleam/dict
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string

@external(erlang, "cepaf_gleam_ffi", "get_env")
fn get_env(name: String) -> Result(String, Nil)

@external(erlang, "mini_app_clock_ffi", "unix_seconds")
pub fn clock() -> Int

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
  let observed_now = clock()
  let task_decoder = {
    use id <- decode.field("task_id", decode.string)
    use state <- decode.field("state", decode.string)
    use lease <- decode.field("lease_until_ns", decode.optional(decode.string))
    let display_state = case state == "executing", lease {
      True, Some(raw) ->
        case int.parse(raw) {
          Ok(until) if until > observed_now * 1_000_000_000 -> state
          Ok(_) -> state <> " (lease expired)"
          Error(_) -> state <> " (lease unknown)"
        }
      True, None -> state <> " (lease unknown)"
      False, _ -> state
    }
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

pub fn observe(read: api.AuthorizedRead) -> api.Observation {
  case api.page(read) {
    types.MiniPlanning ->
      observe_tasks()
      |> result.unwrap(api.Unavailable("task_observation_failed"))
    types.MiniDashboard
    | types.MiniHealthGrid
    | types.MiniCockpit
    | types.MiniImmune
    | types.MiniInference
    | types.MiniConversation
    | types.MiniConfig
    | types.MiniPodman
    | types.MiniFederation
    | types.MiniVerification
    | types.MiniFmea
    | types.MiniTelemetry
    | types.MiniZenohBrowser -> api.Unavailable("backend_not_integrated")
  }
}
