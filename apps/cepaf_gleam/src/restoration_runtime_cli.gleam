//// Finite, independently reviewed restoration effects. Local private-file trust,
//// not multi-user IAM. Every action requires a live Sa-plan attempt and a fresh
//// canonical coordinator runtime lease. Started receipts prevent blind retries.
import cepaf_gleam/harness/admission as a
import cepaf_gleam/harness/clock
import cepaf_gleam/harness/development as dev
import cepaf_gleam/harness/files
import cepaf_gleam/harness/value as v
import gleam/bit_array
import gleam/dict
import gleam/erlang/atom
import gleam/io
import gleam/json
import gleam/list
import gleam/option.{Some}
import gleam/result
import gleam/string
import simplifile
import uos_swarm/session_authority
import uos_swarm/session_sync

const private_root = "/home/an/uos-recovery-candidates/20260930-0421-fractal-rca"
const config_root = "/home/an/.config/systemd/user"
const release_root = dev.root <> "/var/releases/ecology"
const systemctl = "/usr/bin/systemctl"
const old_ecology = "uos-ecology@20260930-0608-0bc78194a7487b0702381c7b982feae21a831579f6da2f24b06f48d13e7e8748.service"

pub fn authorized_workflow(plan: String, task: String, worker: String) -> Bool {
  plan == "uos/capability-restoration/20260930-0734" && task == "RELEASE"
  && worker == "codex-capability-restoration-20260930"
}

@external(erlang, "recovery_activation_ffi", "sha256_file")
fn sha256_file(path: String) -> Result(String, String)

@external(erlang, "recovery_activation_ffi", "get_argv")
fn arguments() -> List(String)

@external(erlang, "ecology_capability_ffi", "uos_root")
fn backend_root() -> String

@external(erlang, "erlang", "apply")
fn metadata(module: atom.Atom, function: atom.Atom, args: List(atom.Atom)) -> BitArray

@external(erlang, "erlang", "halt")
fn halt(status: Int) -> Nil

pub type Action {
  InstallClock
  InstallEcology
  InstallCockpit
  ReloadUnits
  StopOldEcology
  StartEcology
  StopEcology
  RestartPrimary
  RestartBackup
  RestartCockpit
  EnableEcology
  DisableOldEcology
  EnableCockpit
}

pub fn action(raw: String) -> Result(Action, String) {
  case raw {
    "install_clock_unit" -> Ok(InstallClock)
    "install_ecology_env" -> Ok(InstallEcology)
    "install_cockpit_unit" -> Ok(InstallCockpit)
    "daemon_reload" -> Ok(ReloadUnits)
    "stop_old_ecology" -> Ok(StopOldEcology)
    "start_ecology" -> Ok(StartEcology)
    "stop_ecology" -> Ok(StopEcology)
    "restart_clock_primary" -> Ok(RestartPrimary)
    "restart_clock_backup" -> Ok(RestartBackup)
    "restart_cockpit" -> Ok(RestartCockpit)
    "enable_ecology" -> Ok(EnableEcology)
    "disable_old_ecology" -> Ok(DisableOldEcology)
    "enable_cockpit" -> Ok(EnableCockpit)
    _ -> Error("unsupported_restoration_action")
  }
}

pub fn resource(selected: Action) -> String {
  case selected {
    InstallClock | RestartPrimary | RestartBackup -> "runtime:clock-guard"
    InstallCockpit | RestartCockpit | EnableCockpit -> "runtime:cockpit"
    ReloadUnits -> "integration/main"
    _ -> "runtime:ecology"
  }
}

pub fn valid_instance(instance: String) -> Bool {
  case string.split(instance, "-") {
    [date, time, digest] ->
      string.length(date) == 8 && string.length(time) == 4
      && list.all(string.to_graphemes(date <> time), fn(c) { string.contains("0123456789", c) })
      && a.digest_valid(digest)
    _ -> False
  }
}

pub fn control_ids() -> json.Json {
  json.object(list.map([
    "restoration_runtime_cli", "cepaf_gleam@harness@development",
    "cepaf_gleam@harness@admission", "cepaf_gleam@harness@files",
    "cepaf_gleam@harness@clock", "cepaf_gleam@harness@value",
    "cepaf_gleam@planning@sa_plan_bridge", "ecology_capability_ffi",
    "recovery_activation_ffi", "uos_swarm@session_authority",
    "uos_swarm@session_store", "uos_swarm@session_sync",
    "session_store_ffi", "session_sync_ffi", "uos_swarm@coord",
    "uos_swarm@board", "uos_swarm_ffi", "esqlite3", "esqlite3_nif",
    "uos_swarm@clock_guard", "uos_swarm@clock_contract", "clock_guard_ffi",
  ], fn(name) {
    #(name, json.string(metadata(atom.create(name), atom.create("module_info"), [atom.create("md5")])
      |> bit_array.base16_encode |> string.lowercase))
  }))
}

pub fn controls_match(recorded: v.Value, actual: json.Json) -> Bool {
  case json.parse(json.to_string(actual), v.decoder()) {
    Ok(expected) -> a.same_value(recorded, expected)
    Error(_) -> False
  }
}

fn text(doc: v.Value, key: String) -> Result(String, String) {
  case v.get(doc, key) {
    Ok(v.Text(s)) -> Ok(s)
    _ -> Error("text_field:" <> key)
  }
}

fn number(doc: v.Value, key: String) -> Result(Int, String) {
  case v.get(doc, key) {
    Ok(v.Integer(n)) -> Ok(n)
    _ -> Error("integer_field:" <> key)
  }
}

fn private_read(name: String) -> Result(String, String) {
  use _ <- result.try(a.require(a.component(name), "private_filename"))
  use root <- result.try(simplifile.link_info(private_root) |> result.map_error(string.inspect))
  use info <- result.try(simplifile.link_info(private_root <> "/" <> name) |> result.map_error(string.inspect))
  use _ <- result.try(a.require(
    simplifile.file_info_type(root) == simplifile.Directory && root.mode % 64 == 0
    && simplifile.file_info_type(info) == simplifile.File && info.mode % 64 == 0
    && info.user_id == root.user_id && info.nlinks == 1, "private_owned_file_required"))
  files.read(private_root, name)
}

fn parse(raw: String) -> Result(v.Value, String) {
  json.parse(raw, v.decoder()) |> result.map_error(fn(_) { "invalid_json" })
}

fn reviewed(grant_name: String, review_name: String) -> Result(v.Value, String) {
  use _ <- result.try(a.require(backend_root() == dev.root, "runtime_executor_requires_canonical_backend_root"))
  use body <- result.try(private_read(grant_name))
  use grant <- result.try(parse(body))
  use review_raw <- result.try(private_read(review_name))
  use review <- result.try(parse(review_raw))
  use worker <- result.try(text(grant, "worker"))
  use reviewer <- result.try(text(review, "reviewer"))
  use _ <- result.try(a.require(
    v.get(grant, "schema") == Ok(v.Text("uos.restoration-runtime-grant.v1"))
    && v.get(review, "schema") == Ok(v.Text("uos.restoration-runtime-review.v1"))
    && v.get(review, "verdict") == Ok(v.Text("PASS"))
    && v.get(review, "grant_sha256") == Ok(v.Text(files.digest(body)))
    && reviewer != worker && string.length(reviewer) > 0, "independent_review_binding"))
  use recorded <- result.try(v.get(grant, "control_ids"))
  use _ <- result.try(a.require(controls_match(recorded, control_ids()), "loaded_controls_changed"))
  use deps <- result.try(v.get(grant, "dependencies"))
  use _ <- result.try(case deps {
    v.Object(entries) ->
      list.try_each(entries, fn(pair) {
        use actual <- result.try(sha256_file(pair.0))
        a.require(pair.1 == v.Text(actual), "dependency_changed:" <> pair.0)
      })
    _ -> Error("dependencies_required")
  })
  // Required dependency names are fixed, so omission cannot narrow the binding.
  use _ <- result.try(list.try_each([
    systemctl, dev.root <> "/tools/ecology_process.ml",
    dev.root <> "/tools/ecology_release.ml",
    dev.root <> "/toolchains/opam-ocaml/bin/ocaml",
  ], fn(path) { v.get(deps, path) |> result.map(fn(_) { Nil }) }))
  Ok(grant)
}

fn fence(grant: v.Value, selected: Action) -> Result(Nil, String) {
  use plan <- result.try(text(grant, "plan"))
  use task <- result.try(text(grant, "task"))
  use worker <- result.try(text(grant, "worker"))
  use attempt <- result.try(number(grant, "attempt"))
  use session <- result.try(text(grant, "session"))
  use epoch <- result.try(number(grant, "epoch"))
  use expiry <- result.try(number(grant, "expires_us"))
  use host <- result.try(text(grant, "host"))
  use boot <- result.try(text(grant, "boot"))
  use observed <- result.try(clock.observe())
  let now = observed.sample.observed
  use _ <- result.try(a.require(
    authorized_workflow(plan, task, worker)
    && session == worker && window_valid(now.utc_us, expiry)
    && now.domain.host_id == host && now.domain.boot_id == boot, "finite_grant_or_clock"))
  let binding = dev.Binding("restoration", plan, task, worker, attempt, session, epoch)
  use row <- result.try(dev.read_task(binding))
  use _ <- result.try(a.require(
    row.state == "executing" && row.worker == Some(worker)
    && row.attempt == attempt && row.blocked == 0
    && case row.lease_until_ns {
      Some(deadline) -> deadline > { now.utc_us + 60_000_000 } * 1000
      _ -> False
    }, "canonical_task_lease"))
  session_authority.query_at(session_authority.database, fn(state, actual_boot, tick) {
    use _ <- result.try(session_sync.check(state, session, resource(selected), epoch, actual_boot, tick))
    use lease <- result.try(dict.get(state.coordinator.leases, resource(selected)) |> result.map_error(fn(_) { "runtime_lease_missing" }))
    a.require(window_valid(tick, lease.expires_us), "runtime_lease_window")
  })
}

pub fn window_valid(now: Int, expires: Int) -> Bool {
  expires > now + 60_000_000
}

fn service_binding(grant: v.Value, selected: Action, instance: String) -> Result(Nil, String) {
  let unit = case selected {
    StopOldEcology | DisableOldEcology -> old_ecology
    RestartPrimary -> "uos-clock-guard@primary.service"
    RestartBackup -> "uos-clock-guard@backup.service"
    RestartCockpit | EnableCockpit -> "c3i-gleam-server.service"
    _ -> "uos-ecology@" <> instance <> ".service"
  }
  use expected <- result.try(text(grant, "effective_unit_sha256"))
  use actual <- result.try(dev.bounded(systemctl, ["--user", "cat", unit], 5000))
  use _ <- result.try(a.require(files.digest(actual) == expected, "effective_unit_changed"))
  use reload <- result.try(dev.bounded(systemctl, ["--user", "show", "-p", "NeedDaemonReload", "--value", unit], 5000))
  use _ <- result.try(a.require(string.trim(reload) == "no", "unit_requires_daemon_reload"))
  use deps <- result.try(v.get(grant, "dependencies"))
  let required = case selected {
    StartEcology | EnableEcology -> [release_root <> "/" <> instance <> ".env", release_root <> "/" <> instance <> "/release-manifest.json"]
    RestartPrimary | RestartBackup | RestartCockpit | EnableCockpit -> [release_root <> "/" <> instance <> "/release-manifest.json"]
    _ -> []
  }
  use _ <- result.try(list.try_each(required, fn(path) {
    use actual <- result.try(sha256_file(path))
    a.require(v.get(deps, path) == Ok(v.Text(actual)), "required_service_dependency:" <> path)
  }))
  case selected {
    StartEcology | EnableEcology | RestartPrimary | RestartBackup | RestartCockpit | EnableCockpit ->
      dev.bounded(dev.root <> "/toolchains/opam-ocaml/bin/ocaml",
        [dev.root <> "/tools/ecology_release.ml", "verify", release_root <> "/" <> instance], 30_000)
      |> result.map(fn(_) { Nil })
    _ -> Ok(Nil)
  }
}

fn configuration(grant: v.Value, selected: Action, instance: String, intent: String) -> Result(String, String) {
  use source <- result.try(text(grant, "source"))
  use content <- result.try(private_read(source))
  use expected <- result.try(text(grant, "source_sha256"))
  use _ <- result.try(a.require(files.digest(content) == expected, "configuration_changed"))
  let #(root, target) = case selected {
    InstallClock -> #(config_root, "uos-clock-guard@.service")
    InstallCockpit -> #(config_root, "c3i-gleam-server.service")
    _ -> #(release_root, instance <> ".env")
  }
  use prior <- result.try(text(grant, "expected_target_sha256"))
  case prior {
    "absent" -> {
      use _ <- result.try(files.create(root, target, content))
      Ok("configuration_created")
    }
    _ -> {
      use old <- result.try(files.read(root, target))
      use _ <- result.try(a.require(files.digest(old) == prior, "configuration_target_changed"))
      use _ <- result.try(files.create(private_root, intent <> ".original", old))
      use _ <- result.try(files.replace(root, target, prior, content))
      Ok("configuration_replaced_original_preserved")
    }
  }
}

fn perform(grant: v.Value, selected: Action, instance: String, intent: String) -> Result(String, String) {
  let unit = "uos-ecology@" <> instance <> ".service"
  case selected {
    InstallClock | InstallEcology | InstallCockpit -> configuration(grant, selected, instance, intent)
    _ -> {
      use _ <- result.try(case selected {
        ReloadUnits -> Ok(Nil)
        _ -> service_binding(grant, selected, instance)
      })
      use _ <- result.try(fence(grant, selected))
      let args = case selected {
        ReloadUnits -> ["daemon-reload"]
        StopOldEcology -> ["stop", old_ecology]
        StartEcology -> ["start", unit]
        StopEcology -> ["stop", unit]
        RestartPrimary -> ["restart", "uos-clock-guard@primary.service"]
        RestartBackup -> ["restart", "uos-clock-guard@backup.service"]
        RestartCockpit -> ["restart", "c3i-gleam-server.service"]
        EnableEcology -> ["enable", unit]
        DisableOldEcology -> ["disable", old_ecology]
        EnableCockpit -> ["enable", "c3i-gleam-server.service"]
        _ -> []
      }
      dev.bounded(systemctl, ["--user", ..args], 30_000)
    }
  }
}

pub fn execute(grant_name: String, review_name: String) -> Result(String, String) {
  use grant <- result.try(reviewed(grant_name, review_name))
  use selected_text <- result.try(text(grant, "action"))
  use selected <- result.try(action(selected_text))
  use instance <- result.try(text(grant, "instance"))
  use _ <- result.try(a.require(valid_instance(instance), "release_instance"))
  use intent <- result.try(text(grant, "intent"))
  use _ <- result.try(a.require(a.intent_valid(intent), "intent_id"))
  use _ <- result.try(fence(grant, selected))
  // Exclusive receipt is the stable idempotency barrier. Any uncertain outcome
  // is inspected before a distinct independently reviewed reconciliation intent.
  use _ <- result.try(files.create(private_root, intent <> ".started.json", json.to_string(v.encode(grant))))
  use fresh <- result.try(reviewed(grant_name, review_name))
  use _ <- result.try(a.require(a.same_value(grant, fresh), "grant_changed_before_effect"))
  use _ <- result.try(fence(grant, selected))
  let outcome = perform(grant, selected, instance, intent)
  let receipt = json.to_string(json.object([
    #("schema", json.string("uos.restoration-runtime-result.v1")),
    #("intent", json.string(intent)), #("action", json.string(selected_text)),
    #("ok", json.bool(result.is_ok(outcome))),
    #("result", json.string(case outcome { Ok(s) -> s Error(e) -> "OUTCOME_REQUIRES_RECONCILIATION:" <> e })),
  ]))
  use _ <- result.try(files.create(private_root, intent <> ".result.json", receipt))
  use _ <- result.try(outcome)
  Ok(receipt)
}

pub fn main() {
  let outcome = case arguments() {
    ["control-ids"] -> Ok(json.to_string(control_ids()))
    ["execute", grant, review] -> execute(grant, review)
    _ -> Error("usage: restoration_runtime_cli control-ids | execute GRANT_NAME REVIEW_NAME")
  }
  case outcome {
    Ok(receipt) -> io.println(receipt)
    Error(reason) -> {
      io.println(json.to_string(json.object([#("ok", json.bool(False)), #("error", json.string(reason))])))
      halt(1)
    }
  }
}
