//// Bounded Telegram Lifecycle Adapter & Quiescence Proof System
////
//// Enforces whole-unit cgroup isolation and crash-quiescence verification:
//// - Unit and slice names MUST strictly adhere to Poka-Yoke prefixes:
////   - Slices: `app-uos_tg_test_` matching `^app-uos_tg_test_[a-zA-Z0-9_-]+(\.[a-zA-Z0-9_-]+)?$`
////   - Units:  `uos-tg-store-test-` matching `^uos-tg-store-test-[a-zA-Z0-9_-]+(\.[a-zA-Z0-9_-]+)?$`
////   Interacting with production, Herdr, or unvetted units/slices is strictly refused.
//// - `UnitCleanupReceipt` is an opaque type minted ONLY after:
////   1. Retained parent slice verified active with valid InvocationID & ControlGroup.
////   2. Child unit stop confirmed (`ActiveState == "inactive"` or `"failed"`).
////   3. Retained parent slice cgroup recursively verified empty (`cgroup.events` reports `populated 0`).
////   4. Parent slice stopped cleanly.
//// - In the event of an uncoordinated crash or dead VM without a verified
////   `UnitCleanupReceipt`, the service enters in-memory `ServiceWriterHold`,
////   strictly barring all disk mutations until explicit recovery.

import cepaf_gleam/harness/files
import cepaf_gleam/harness/observer_policy as obs_policy
import gleam/bit_array
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub opaque type UnitCleanupReceipt {
  UnitCleanupReceipt(
    unit_name: String,
    slice_name: String,
    invocation_id: String,
    slice_invocation_id: String,
    store_incarnation_id: String,
    service_epoch: Int,
    stopped_at_us: Int,
    exit_status: Int,
    cgroup_path: String,
    store_db_path: String,
    worker_hash: String,
    guardian_hash: String,
  )
}

pub type SystemdUnitState {
  SystemdUnitState(
    active_state: String,
    sub_state: String,
    invocation_id: String,
    control_group: String,
    exec_path: String,
  )
}

pub type ServiceWriterState {
  ServiceWriterClean
  ServiceWriterHold(reason: String)
}

pub type ControlRegistration {
  ControlRegistration(
    unit_name: String,
    slice_name: String,
    unit_invocation_id: String,
    slice_invocation_id: String,
    store_incarnation_id: String,
    store_db_path: String,
    worker_hash: String,
    guardian_hash: String,
    service_epoch: Int,
    registered_at_us: Int,
  )
}

pub fn encode_control_registration(reg: ControlRegistration) -> String {
  json.object([
    #("schema", json.string("uos.telegram-control-registration.v2")),
    #("unit_name", json.string(reg.unit_name)),
    #("slice_name", json.string(reg.slice_name)),
    #("unit_invocation_id", json.string(reg.unit_invocation_id)),
    #("slice_invocation_id", json.string(reg.slice_invocation_id)),
    #("store_incarnation_id", json.string(reg.store_incarnation_id)),
    #("store_db_path", json.string(reg.store_db_path)),
    #("worker_hash", json.string(reg.worker_hash)),
    #("guardian_hash", json.string(reg.guardian_hash)),
    #("service_epoch", json.int(reg.service_epoch)),
    #("registered_at_us", json.int(reg.registered_at_us)),
  ])
  |> json.to_string
}

pub fn decode_control_registration(
  json_str: String,
) -> Result(ControlRegistration, String) {
  let decoder = {
    use schema <- decode.field("schema", decode.string)
    use unit <- decode.field("unit_name", decode.string)
    use slice <- decode.field("slice_name", decode.string)
    use unit_inv <- decode.optional_field(
      "unit_invocation_id",
      "",
      decode.string,
    )
    use slice_inv <- decode.optional_field(
      "slice_invocation_id",
      "",
      decode.string,
    )
    use store_inc <- decode.optional_field(
      "store_incarnation_id",
      "",
      decode.string,
    )
    use db <- decode.field("store_db_path", decode.string)
    use worker <- decode.field("worker_hash", decode.string)
    use guardian <- decode.field("guardian_hash", decode.string)
    use epoch <- decode.field("service_epoch", decode.int)
    use ts <- decode.field("registered_at_us", decode.int)
    case
      schema == "uos.telegram-control-registration.v2"
      || schema == "uos.telegram-control-registration.v1"
    {
      True ->
        decode.success(ControlRegistration(
          unit_name: unit,
          slice_name: slice,
          unit_invocation_id: unit_inv,
          slice_invocation_id: slice_inv,
          store_incarnation_id: store_inc,
          store_db_path: db,
          worker_hash: worker,
          guardian_hash: guardian,
          service_epoch: epoch,
          registered_at_us: ts,
        ))
      False ->
        decode.failure(
          ControlRegistration("", "", "", "", "", "", "", "", 0, 0),
          "unknown_control_registration_schema",
        )
    }
  }
  json.parse(json_str, decoder)
  |> result.map_error(fn(_) { "invalid_control_registration_json" })
}

pub fn write_prelaunch_control(
  path: String,
  reg: ControlRegistration,
) -> Result(Nil, String) {
  use _ <- result.try(validate_test_unit_name(reg.unit_name))
  use _ <- result.try(validate_test_slice_name(reg.slice_name))
  let encoded = encode_control_registration(reg)
  ffi_atomic_write_file(path, encoded)
  |> result.map(fn(_) { Nil })
  |> result.map_error(fn(err) {
    "write_control_registration_failed: " <> err
  })
}

pub const default_max_registration_age_us = 60_000_000

pub fn read_and_verify_prelaunch_control(
  path: String,
  expected_unit: String,
  expected_db: String,
  expected_worker: String,
  expected_guardian: String,
  expected_epoch: Int,
) -> Result(ControlRegistration, String) {
  read_and_verify_prelaunch_control_bounded(
    path,
    expected_unit,
    expected_db,
    expected_worker,
    expected_guardian,
    expected_epoch,
    None,
  )
}

pub fn read_and_verify_prelaunch_control_bounded(
  path: String,
  expected_unit: String,
  expected_db: String,
  expected_worker: String,
  expected_guardian: String,
  expected_epoch: Int,
  max_age_us: Option(Int),
) -> Result(ControlRegistration, String) {
  use _ <- result.try(case string.starts_with(path, "/") && path != "/" && !string.starts_with(path, "//") {
    True -> Ok(Nil)
    False -> Error("absolute_control_registration_path_required")
  })
  use content <- result.try(
    files.read("/", string.drop_start(path, 1))
    |> result.map_error(fn(err) { "read_control_registration_failed: " <> err }),
  )
  use reg <- result.try(decode_control_registration(content))
  use _ <- result.try(case content == encode_control_registration(reg) {
    True -> Ok(Nil)
    False -> Error("noncanonical_control_registration")
  })
  use _ <- result.try(validate_test_unit_name(reg.unit_name))
  use _ <- result.try(validate_test_slice_name(reg.slice_name))
  use _ <- result.try(case expected_epoch > 0 && reg.service_epoch == expected_epoch {
    True -> Ok(Nil)
    False ->
      Error(
        "epoch_mismatch: exp="
        <> int.to_string(expected_epoch)
        <> " reg="
        <> int.to_string(reg.service_epoch),
      )
  })
  use _ <- result.try(case reg.registered_at_us > 0 {
    True -> Ok(Nil)
    False -> Error("registered_at_us_zero")
  })
  use _ <- result.try(case expected_unit == "" || reg.unit_name == expected_unit {
    True -> Ok(Nil)
    False ->
      Error("unit_name_mismatch: exp=" <> expected_unit <> " reg=" <> reg.unit_name)
  })
  use _ <- result.try(case reg.store_db_path == expected_db {
    True -> Ok(Nil)
    False ->
      Error("store_db_path_mismatch: exp=" <> expected_db <> " reg=" <> reg.store_db_path)
  })
  use _ <- result.try(case reg.worker_hash == expected_worker {
    True -> Ok(Nil)
    False ->
      Error("worker_hash_mismatch: exp=" <> expected_worker <> " reg=" <> reg.worker_hash)
  })
  use _ <- result.try(case reg.guardian_hash == expected_guardian {
    True -> Ok(Nil)
    False ->
      Error("guardian_hash_mismatch: exp=" <> expected_guardian <> " reg=" <> reg.guardian_hash)
  })

  // Mandatory non-empty ID invariants
  use _ <- result.try(case reg.unit_invocation_id != "" {
    True -> Ok(Nil)
    False -> Error("empty_unit_invocation_id_in_control_registration")
  })
  use _ <- result.try(case reg.slice_invocation_id != "" {
    True -> Ok(Nil)
    False -> Error("empty_slice_invocation_id_in_control_registration")
  })
  use _ <- result.try(case reg.store_incarnation_id != "" {
    True -> Ok(Nil)
    False -> Error("empty_store_incarnation_id_in_control_registration")
  })

  // Freshness check if bounded
  let now = ffi_now_us()
  use _ <- result.try(case max_age_us {
    Some(max_age) -> {
      case
        now - reg.registered_at_us > max_age
        || reg.registered_at_us > now + 5_000_000
      {
        True -> Error("control_registration_stale_or_future")
        False -> Ok(Nil)
      }
    }
    None -> Ok(Nil)
  })

  // Verify store incarnation against disk
  use actual_inc <- result.try(compute_store_incarnation(reg.store_db_path))
  use _ <- result.try(case actual_inc == reg.store_incarnation_id {
    True -> Ok(Nil)
    False ->
      Error(
        "store_incarnation_mismatch: observed="
        <> actual_inc
        <> " registered="
        <> reg.store_incarnation_id,
      )
  })

  Ok(reg)
}

pub fn verify_live_lifecycle_ownership(
  reg: ControlRegistration,
) -> Result(Nil, String) {
  // Mandatory non-empty ID invariants
  use _ <- result.try(case reg.unit_invocation_id != "" {
    True -> Ok(Nil)
    False -> Error("empty_unit_invocation_id_in_control_registration")
  })
  use _ <- result.try(case reg.slice_invocation_id != "" {
    True -> Ok(Nil)
    False -> Error("empty_slice_invocation_id_in_control_registration")
  })
  use _ <- result.try(case reg.store_incarnation_id != "" {
    True -> Ok(Nil)
    False -> Error("empty_store_incarnation_id_in_control_registration")
  })

  // 1. Verify store incarnation matches registered
  use actual_inc <- result.try(compute_store_incarnation(reg.store_db_path))
  use _ <- result.try(case actual_inc == reg.store_incarnation_id {
    True -> Ok(Nil)
    False ->
      Error(
        "store_incarnation_mismatch: observed="
        <> actual_inc
        <> " registered="
        <> reg.store_incarnation_id,
      )
  })

  // 2. Observe slice status
  use slice_status <- result.try(get_unit_status(reg.slice_name))
  case slice_status.invocation_id == "" || slice_status.control_group == "" {
    True -> Error("slice_not_running_or_missing_control_group")
    False -> {
      // 3. Verify slice InvocationID matches registration
      case slice_status.invocation_id != reg.slice_invocation_id {
        True ->
          Error(
            "slice_invocation_id_mismatch: observed="
            <> slice_status.invocation_id
            <> " registered="
            <> reg.slice_invocation_id,
          )
        False -> {
          // 4. Observe unit status
          use unit_status <- result.try(get_unit_status(reg.unit_name))
          case unit_status.invocation_id == "" {
            True -> Error("unit_not_running_or_missing_invocation_id")
            False -> {
              // 5. Verify unit InvocationID matches registration
              case unit_status.invocation_id != reg.unit_invocation_id {
                True ->
                  Error(
                    "unit_invocation_id_mismatch: observed="
                    <> unit_status.invocation_id
                    <> " registered="
                    <> reg.unit_invocation_id,
                  )
                False -> {
                  // 6. Verify cgroup path-boundary: unit inside slice
                  case
                    unit_status.control_group != ""
                    && slice_status.control_group != ""
                    && {
                      unit_status.control_group == slice_status.control_group
                      || string.starts_with(
                        unit_status.control_group,
                        slice_status.control_group <> "/",
                      )
                    }
                  {
                    False ->
                      Error(
                        "cgroup_path_boundary_violation: unit cgroup="
                        <> unit_status.control_group
                        <> " not inside slice cgroup="
                        <> slice_status.control_group,
                      )
                    True -> {
                      // 7. Refuse non-worker executables (tail and sleep)
                      case
                        unit_status.exec_path != ""
                        && {
                          string.contains(unit_status.exec_path, "tail")
                          || string.contains(unit_status.exec_path, "sleep")
                        }
                      {
                        True ->
                          Error(
                            "refused_non_worker_executable_in_unit: "
                            <> unit_status.exec_path,
                          )
                        False -> {
                          // 8. Require positive admitted BEAM executable
                          case
                            unit_status.exec_path == ""
                            || {
                              !string.contains(unit_status.exec_path, "beam")
                              && !string.contains(unit_status.exec_path, "erl")
                            }
                          {
                            True ->
                              Error(
                                "refused_non_beam_executable_in_unit: "
                                <> unit_status.exec_path,
                              )
                            False -> {
                              // 9. Positive process-to-cgroup ownership: caller must run inside unit cgroup
                              use self_cg <- result.try(read_self_cgroup())
                              case
                                self_cg == unit_status.control_group
                                || string.starts_with(
                                  self_cg,
                                  unit_status.control_group <> "/",
                                )
                              {
                                False ->
                                  Error(
                                    "cgroup_membership_mismatch: current process cgroup="
                                    <> self_cg
                                    <> " is not inside unit cgroup="
                                    <> unit_status.control_group,
                                  )
                                True -> {
                                  // Verify process PID is in cgroup.procs
                                  use in_procs <- result.try(
                                    is_current_pid_in_cgroup(
                                      unit_status.control_group,
                                    ),
                                  )
                                  case in_procs {
                                    False ->
                                      Error(
                                        "process_not_in_unit_cgroup_procs: pid not found in "
                                        <> unit_status.control_group,
                                      )
                                    True -> Ok(Nil)
                                  }
                                }
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}

pub const test_unit_prefix = "uos-tg-store-test-"
pub const test_slice_prefix = "app-uos_tg_test_"

// -----------------------------------------------------------------------------
// Opaque Accessors
// -----------------------------------------------------------------------------

pub fn receipt_unit_name(receipt: UnitCleanupReceipt) -> String {
  receipt.unit_name
}

pub fn receipt_slice_name(receipt: UnitCleanupReceipt) -> String {
  receipt.slice_name
}

pub fn receipt_invocation_id(receipt: UnitCleanupReceipt) -> String {
  receipt.invocation_id
}

pub fn receipt_slice_invocation_id(receipt: UnitCleanupReceipt) -> String {
  receipt.slice_invocation_id
}

pub fn receipt_store_incarnation_id(receipt: UnitCleanupReceipt) -> String {
  receipt.store_incarnation_id
}

pub fn receipt_service_epoch(receipt: UnitCleanupReceipt) -> Int {
  receipt.service_epoch
}

pub fn receipt_stopped_at_us(receipt: UnitCleanupReceipt) -> Int {
  receipt.stopped_at_us
}

pub fn receipt_exit_status(receipt: UnitCleanupReceipt) -> Int {
  receipt.exit_status
}

pub fn receipt_cgroup_path(receipt: UnitCleanupReceipt) -> String {
  receipt.cgroup_path
}

pub fn receipt_store_db_path(receipt: UnitCleanupReceipt) -> String {
  receipt.store_db_path
}

pub fn receipt_worker_hash(receipt: UnitCleanupReceipt) -> String {
  receipt.worker_hash
}

pub fn receipt_guardian_hash(receipt: UnitCleanupReceipt) -> String {
  receipt.guardian_hash
}

pub fn encode_unit_cleanup_receipt(receipt: UnitCleanupReceipt) -> String {
  json.object([
    #("unit_name", json.string(receipt.unit_name)),
    #("slice_name", json.string(receipt.slice_name)),
    #("invocation_id", json.string(receipt.invocation_id)),
    #("slice_invocation_id", json.string(receipt.slice_invocation_id)),
    #("store_incarnation_id", json.string(receipt.store_incarnation_id)),
    #("service_epoch", json.int(receipt.service_epoch)),
    #("stopped_at_us", json.int(receipt.stopped_at_us)),
    #("exit_status", json.int(receipt.exit_status)),
    #("cgroup_path", json.string(receipt.cgroup_path)),
    #("store_db_path", json.string(receipt.store_db_path)),
    #("worker_hash", json.string(receipt.worker_hash)),
    #("guardian_hash", json.string(receipt.guardian_hash)),
  ])
  |> json.to_string
}

// -----------------------------------------------------------------------------
// Poka-Yoke Name Validation
// -----------------------------------------------------------------------------

@external(erlang, "telegram_lifecycle_ffi", "validate_test_unit_name")
fn ffi_validate_test_unit_name(unit_name: String) -> Result(String, String)

@external(erlang, "telegram_lifecycle_ffi", "validate_test_slice_name")
fn ffi_validate_test_slice_name(slice_name: String) -> Result(String, String)

pub fn validate_test_unit_name(unit_name: String) -> Result(String, String) {
  case string.starts_with(unit_name, test_unit_prefix) {
    False ->
      Error(
        "refused_non_test_unit_name: unit must start with "
        <> test_unit_prefix
        <> " (got: "
        <> unit_name
        <> ")",
      )
    True -> {
      let len = string.length(unit_name)
      case len < 18 || len > 80 {
        True -> Error("refused_unit_name_length_out_of_bounds")
        False -> {
          let remainder = string.drop_start(unit_name, string.length(test_unit_prefix))
          let chars_ok =
            string.to_graphemes(remainder)
            |> list.all(fn(c) {
              string.contains(
                "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.",
                c,
              )
            })
          case chars_ok {
            False -> Error("refused_invalid_characters_in_unit_name")
            True -> ffi_validate_test_unit_name(unit_name)
          }
        }
      }
    }
  }
}

pub fn validate_test_slice_name(slice_name: String) -> Result(String, String) {
  case string.starts_with(slice_name, test_slice_prefix) {
    False ->
      Error(
        "refused_non_test_slice_name: slice must start with "
        <> test_slice_prefix
        <> " (got: "
        <> slice_name
        <> ")",
      )
    True -> {
      let len = string.length(slice_name)
      case len < 18 || len > 80 {
        True -> Error("refused_slice_name_length_out_of_bounds")
        False -> {
          let remainder = string.drop_start(slice_name, string.length(test_slice_prefix))
          let chars_ok =
            string.to_graphemes(remainder)
            |> list.all(fn(c) {
              string.contains(
                "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.",
                c,
              )
            })
          case chars_ok {
            False -> Error("refused_invalid_characters_in_slice_name")
            True -> ffi_validate_test_slice_name(slice_name)
          }
        }
      }
    }
  }
}

// -----------------------------------------------------------------------------
// Pinned Executables & SHA256 Authority
// -----------------------------------------------------------------------------

pub const canonical_guardian_exe =
  "/home/an/NAS-setup/uos/tools/validation/obs_guardian.exe"

pub const canonical_guardian_sha256 =
  "b7bab1a85ffa3689a2548ff28a391e659c0537104dec7be0f774bae1820ec4be"

pub const canonical_systemctl_exe = "/usr/bin/systemctl"

pub const canonical_systemctl_sha256 =
  "6394f5e8df92878184de9d4dfb7ac242471cb09daf89d23be4e81ae17e9c03b2"

pub const canonical_systemd_run_exe = "/usr/bin/systemd-run"

pub const canonical_systemd_run_sha256 =
  "03a68bafb0ebc0f5eff41cbdf3cbbdf126a3bb87e21140f9147bf78edce36d88"

pub const canonical_repo_root = "/home/an/NAS-setup/uos"

pub const canonical_beam_exe =
  "/home/an/NAS-setup/uos/toolchains/nix-profile/bin/erl"

pub const canonical_beam_sha256 =
  "ef4292ee944622942f2e961553eae2222a9dce112eb7e5bfec04dcb9a0d54970"

// -----------------------------------------------------------------------------
// Typed Gleam Lifecycle Command Policy
// -----------------------------------------------------------------------------

pub type LifecycleCommand {
  ShowUnit(unit_name: String)
  ShowSlice(slice_name: String)
  StartSlice(slice_name: String)
  StopUnit(unit_name: String)
  StopSlice(slice_name: String)
  RunTestUnit(
    slice_name: String,
    unit_name: String,
    runtime_max_sec: Int,
    executable: String,
    args: List(String),
  )
}

@external(erlang, "sa_plan_observer_ffi", "observe_checked")
fn ffi_observe_checked(
  guardian: String,
  guardian_sha256: String,
  argv: List(String),
  deadline_ms: Int,
  max_bytes: Int,
) -> Result(obs_policy.Observation, String)

pub fn execute_lifecycle_command(
  cmd: LifecycleCommand,
) -> Result(String, String) {
  case cmd {
    ShowUnit(unit_name) -> {
      use valid_unit <- result.try(validate_test_unit_name(unit_name))
      run_systemctl([
        "--user",
        "--no-pager",
        "show",
        valid_unit,
        "--property=LoadState,ActiveState,SubState,InvocationID,ControlGroup,ExecMainPath,ExecStart",
      ])
    }
    ShowSlice(slice_name) -> {
      use valid_slice <- result.try(validate_test_slice_name(slice_name))
      run_systemctl([
        "--user",
        "--no-pager",
        "show",
        valid_slice,
        "--property=LoadState,ActiveState,SubState,InvocationID,ControlGroup,ExecMainPath,ExecStart",
      ])
    }
    StartSlice(slice_name) -> {
      use valid_slice <- result.try(validate_test_slice_name(slice_name))
      run_systemctl(["--user", "--no-pager", "start", valid_slice])
    }
    StopUnit(unit_name) -> {
      use valid_unit <- result.try(validate_test_unit_name(unit_name))
      run_systemctl(["--user", "--no-pager", "stop", valid_unit])
    }
    StopSlice(slice_name) -> {
      use valid_slice <- result.try(validate_test_slice_name(slice_name))
      run_systemctl(["--user", "--no-pager", "stop", valid_slice])
    }
    RunTestUnit(slice_name, unit_name, runtime_max_sec, exe, args) -> {
      use valid_slice <- result.try(validate_test_slice_name(slice_name))
      use valid_unit <- result.try(validate_test_unit_name(unit_name))
      use _ <- result.try(case runtime_max_sec >= 1 && runtime_max_sec <= 60 {
        True -> Ok(Nil)
        False -> Error("refused_runtime_max_sec_out_of_bounds")
      })
      use _ <- result.try(case string.starts_with(exe, "/") {
        True -> Ok(Nil)
        False -> Error("executable_path_must_be_absolute")
      })
      run_systemd_run(valid_slice, valid_unit, runtime_max_sec, exe, args)
    }
  }
}

fn run_systemctl(args: List(String)) -> Result(String, String) {
  let guardian_argv =
    list.flatten([
      [
        "--exe", canonical_systemctl_exe,
        "--sha256", canonical_systemctl_sha256,
        "--deadline-ms", "3500",
        "--max-bytes", "16384",
        "--",
      ],
      args,
    ])
  case
    ffi_observe_checked(
      canonical_guardian_exe,
      canonical_guardian_sha256,
      guardian_argv,
      3500,
      16384,
    )
  {
    Ok(obs) -> {
      case obs.child_exit == 0 {
        True ->
          bit_array.to_string(obs.payload)
          |> result.map_error(fn(_) { "command_output_utf8_decode_failed" })
        False ->
          Error("systemctl_command_failed_exit_" <> int.to_string(obs.child_exit))
      }
    }
    Error(err) -> Error("lifecycle_command_transport_failed: " <> err)
  }
}

fn run_systemd_run(
  slice_name: String,
  unit_name: String,
  runtime_max_sec: Int,
  executable: String,
  args: List(String),
) -> Result(String, String) {
  let target_args =
    list.flatten([
      [
        "--user",
        "--slice=" <> slice_name,
        "--unit=" <> unit_name,
        "--working-directory=" <> canonical_repo_root,
        "--property=RuntimeMaxSec=" <> int.to_string(runtime_max_sec),
        "--property=TimeoutStopSec=2",
        "--property=KillMode=control-group",
        "--property=SendSIGKILL=yes",
        executable,
      ],
      args,
    ])
  let guardian_argv =
    list.flatten([
      [
        "--exe", canonical_systemd_run_exe,
        "--sha256", canonical_systemd_run_sha256,
        "--deadline-ms", "3500",
        "--max-bytes", "16384",
        "--",
      ],
      target_args,
    ])
  case
    ffi_observe_checked(
      canonical_guardian_exe,
      canonical_guardian_sha256,
      guardian_argv,
      3500,
      16384,
    )
  {
    Ok(obs) -> {
      case obs.child_exit == 0 {
        True ->
          bit_array.to_string(obs.payload)
          |> result.map_error(fn(_) { "command_output_utf8_decode_failed" })
        False ->
          Error("systemd_run_command_failed_exit_" <> int.to_string(obs.child_exit))
      }
    }
    Error(err) -> Error("lifecycle_command_transport_failed: " <> err)
  }
}

pub fn parse_systemctl_show(output: String) -> SystemdUnitState {
  let lines = string.split(output, "\n")
  let parse_kv = fn(acc: #(String, String, String, String, String), line: String) {
    case string.split_once(string.trim(line), "=") {
      Ok(#("ActiveState", v)) -> #(v, acc.1, acc.2, acc.3, acc.4)
      Ok(#("SubState", v)) -> #(acc.0, v, acc.2, acc.3, acc.4)
      Ok(#("InvocationID", v)) -> #(acc.0, acc.1, v, acc.3, acc.4)
      Ok(#("ControlGroup", v)) -> #(acc.0, acc.1, acc.2, v, acc.4)
      Ok(#("ExecMainPath", v)) -> #(acc.0, acc.1, acc.2, acc.3, v)
      Ok(#("ExecStart", v)) -> {
        case acc.4 == "" {
          True -> #(acc.0, acc.1, acc.2, acc.3, extract_exec_start_path(v))
          False -> acc
        }
      }
      _ -> acc
    }
  }
  let #(active, sub, inv_id, cgroup, exec) =
    list.fold(lines, #("", "", "", "", ""), parse_kv)
  SystemdUnitState(
    active_state: active,
    sub_state: sub,
    invocation_id: inv_id,
    control_group: cgroup,
    exec_path: exec,
  )
}

fn extract_exec_start_path(raw: String) -> String {
  case string.split_once(raw, "path=") {
    Ok(#(_, rest)) -> {
      case string.split_once(rest, " ;") {
        Ok(#(p, _)) -> string.trim(p)
        Error(_) -> {
          case string.split_once(rest, ";") {
            Ok(#(p, _)) -> string.trim(p)
            Error(_) -> string.trim(rest)
          }
        }
      }
    }
    Error(_) -> ""
  }
}

// -----------------------------------------------------------------------------
// FFI Declarations (Cgroups & Persistence)
// -----------------------------------------------------------------------------

@external(erlang, "telegram_lifecycle_ffi", "read_cgroup_events_populated")
fn ffi_read_cgroup_events_populated(cgroup_path: String) -> Result(Int, String)

@external(erlang, "telegram_lifecycle_ffi", "now_us")
fn ffi_now_us() -> Int

@external(erlang, "telegram_lifecycle_ffi", "sleep_ms")
fn ffi_sleep_ms(ms: Int) -> Nil

@external(erlang, "telegram_lifecycle_ffi", "compute_store_incarnation")
pub fn compute_store_incarnation(db_path: String) -> Result(String, String)

@external(erlang, "telegram_lifecycle_ffi", "atomic_write_file")
fn ffi_atomic_write_file(path: String, content: String) -> Result(Bool, String)

@external(erlang, "telegram_lifecycle_ffi", "read_self_cgroup")
pub fn read_self_cgroup() -> Result(String, String)

@external(erlang, "telegram_lifecycle_ffi", "is_current_pid_in_cgroup")
pub fn is_current_pid_in_cgroup(cgroup_path: String) -> Result(Bool, String)

@external(erlang, "telegram_lifecycle_ffi", "mark_receipt_consumed")
fn ffi_mark_receipt_consumed(
  db_path: String,
  invocation_id: String,
  stopped_at_us: Int,
) -> Result(Bool, String)

pub fn mark_receipt_consumed(receipt: UnitCleanupReceipt) -> Result(Nil, String) {
  case
    ffi_mark_receipt_consumed(
      receipt.store_db_path,
      receipt.invocation_id,
      receipt.stopped_at_us,
    )
  {
    Ok(True) -> Ok(Nil)
    Ok(False) -> Error("cleanup_receipt_already_consumed")
    Error(err) -> Error("cleanup_receipt_consumption_failed: " <> err)
  }
}

// -----------------------------------------------------------------------------
// Bounded Lifecycle Operations
// -----------------------------------------------------------------------------

pub fn run_test_unit(
  slice_name: String,
  unit_name: String,
  executable: String,
  args: List(String),
) -> Result(Bool, String) {
  run_test_unit_bounded(slice_name, unit_name, 15, executable, args)
}

pub fn run_test_unit_bounded(
  slice_name: String,
  unit_name: String,
  runtime_max_sec: Int,
  executable: String,
  args: List(String),
) -> Result(Bool, String) {
  use _ <- result.try(execute_lifecycle_command(RunTestUnit(
    slice_name: slice_name,
    unit_name: unit_name,
    runtime_max_sec: runtime_max_sec,
    executable: executable,
    args: args,
  )))
  Ok(True)
}

pub fn start_test_slice(slice_name: String) -> Result(Bool, String) {
  use _ <- result.try(execute_lifecycle_command(StartSlice(slice_name)))
  Ok(True)
}

pub fn stop_test_slice(slice_name: String) -> Result(Bool, String) {
  use _ <- result.try(execute_lifecycle_command(StopSlice(slice_name)))
  Ok(True)
}

pub fn cleanup_test_unit_and_slice(slice_name: String, unit_name: String) -> Nil {
  let _ = execute_lifecycle_command(StopUnit(unit_name))
  let _ = execute_lifecycle_command(StopSlice(slice_name))
  Nil
}

pub fn get_unit_status(name: String) -> Result(SystemdUnitState, String) {
  let cmd = case validate_test_unit_name(name) {
    Ok(_) -> Ok(ShowUnit(name))
    Error(_) -> {
      case validate_test_slice_name(name) {
        Ok(_) -> Ok(ShowSlice(name))
        Error(_) -> Error("invalid_unit_or_slice_name")
      }
    }
  }
  use valid_cmd <- result.try(cmd)
  use output <- result.try(execute_lifecycle_command(valid_cmd))
  Ok(parse_systemctl_show(output))
}

pub fn verify_cgroup_empty(cgroup_path: String) -> Result(Nil, String) {
  verify_cgroup_empty_poll(cgroup_path, 80)
}

fn verify_cgroup_empty_poll(
  cgroup_path: String,
  retries: Int,
) -> Result(Nil, String) {
  case ffi_read_cgroup_events_populated(cgroup_path) {
    Ok(0) -> Ok(Nil)
    Ok(1) -> {
      case retries > 0 {
        True -> {
          ffi_sleep_ms(25)
          verify_cgroup_empty_poll(cgroup_path, retries - 1)
        }
        False -> Error("cgroup_not_empty: populated is 1")
      }
    }
    Ok(other) ->
      Error("unexpected_cgroup_populated_value: " <> int.to_string(other))
    Error(err) -> Error("cgroup_read_error: " <> err)
  }
}

pub fn stop_and_verify_test_unit(
  slice_name: String,
  unit_name: String,
  store_db_path: String,
  worker_hash: String,
  guardian_hash: String,
) -> Result(UnitCleanupReceipt, String) {
  stop_and_verify_test_unit_epoch(
    slice_name,
    unit_name,
    store_db_path,
    worker_hash,
    guardian_hash,
    1,
  )
}

pub fn stop_and_verify_test_unit_epoch(
  slice_name: String,
  unit_name: String,
  store_db_path: String,
  worker_hash: String,
  guardian_hash: String,
  service_epoch: Int,
) -> Result(UnitCleanupReceipt, String) {
  use validated_slice <- result.try(validate_test_slice_name(slice_name))
  use validated_unit <- result.try(validate_test_unit_name(unit_name))

  // 1. Observe pre-stop slice info
  use slice_info <- result.try(get_unit_status(validated_slice))
  case slice_info.invocation_id == "" || slice_info.control_group == "" {
    True -> Error("slice_not_running_or_missing_control_group")
    False -> {
      // 2. Observe pre-stop unit info
      use pre_unit_info <- result.try(get_unit_status(validated_unit))
      case pre_unit_info.invocation_id == "" {
        True -> Error("cannot_stop_unit_without_invocation_id")
        False -> {
          case
            pre_unit_info.control_group == slice_info.control_group
            || string.starts_with(
              pre_unit_info.control_group,
              slice_info.control_group <> "/",
            )
          {
            False -> Error("unit_not_owned_by_retained_slice")
            True -> {
              case
                pre_unit_info.exec_path != ""
                && {
                  string.contains(pre_unit_info.exec_path, "tail")
                  || string.contains(pre_unit_info.exec_path, "sleep")
                }
              {
                True ->
                  Error(
                    "refused_non_worker_executable_in_test_unit: "
                    <> pre_unit_info.exec_path,
                  )
                False -> {
                  case
                    pre_unit_info.exec_path == ""
                    || {
                      !string.contains(pre_unit_info.exec_path, "beam")
                      && !string.contains(pre_unit_info.exec_path, "erl")
                    }
                  {
                    True ->
                      Error(
                        "refused_non_beam_executable_in_test_unit: "
                        <> pre_unit_info.exec_path,
                      )
                    False -> {
                      use inc <- result.try(compute_store_incarnation(store_db_path))

                      // 3. Stop child unit
                      use _ <- result.try(execute_lifecycle_command(StopUnit(validated_unit)))

                      // 4. Observe post-stop unit status
                      use post_unit_info <- result.try(get_unit_status(validated_unit))
                      case
                        post_unit_info.active_state == "inactive"
                        || post_unit_info.active_state == "failed"
                      {
                        False ->
                          Error("unit_not_inactive_after_stop: " <> post_unit_info.active_state)
                        True -> {
                          // 5. Verify cgroup events populated 0 on retained parent slice
                          let full_cgroup = "/sys/fs/cgroup" <> slice_info.control_group
                          use _ <- result.try(verify_cgroup_empty(full_cgroup))
                          let stopped_at = ffi_now_us()

                          // 6. Stop parent slice
                          use _ <- result.try(execute_lifecycle_command(StopSlice(validated_slice)))

                          // 7. Mint opaque receipt
                          Ok(UnitCleanupReceipt(
                            unit_name: validated_unit,
                            slice_name: validated_slice,
                            invocation_id: pre_unit_info.invocation_id,
                            slice_invocation_id: slice_info.invocation_id,
                            store_incarnation_id: inc,
                            service_epoch: service_epoch,
                            stopped_at_us: stopped_at,
                            exit_status: 0,
                            cgroup_path: full_cgroup,
                            store_db_path: store_db_path,
                            worker_hash: worker_hash,
                            guardian_hash: guardian_hash,
                          ))
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}

pub fn stop_and_verify_registered_unit(
  reg: ControlRegistration,
) -> Result(UnitCleanupReceipt, String) {
  use _ <- result.try(case reg.service_epoch > 0 && reg.registered_at_us > 0 {
    True -> Ok(Nil)
    False -> Error("invalid_registration_epoch_or_timestamp")
  })
  use _ <- result.try(case reg.unit_invocation_id != "" {
    True -> Ok(Nil)
    False -> Error("empty_unit_invocation_id_in_control_registration")
  })
  use _ <- result.try(case reg.slice_invocation_id != "" {
    True -> Ok(Nil)
    False -> Error("empty_slice_invocation_id_in_control_registration")
  })
  use _ <- result.try(case reg.store_incarnation_id != "" {
    True -> Ok(Nil)
    False -> Error("empty_store_incarnation_id_in_control_registration")
  })

  use validated_slice <- result.try(validate_test_slice_name(reg.slice_name))
  use validated_unit <- result.try(validate_test_unit_name(reg.unit_name))

  // 1. Observe pre-stop slice info and match registered InvocationID
  use slice_info <- result.try(get_unit_status(validated_slice))
  case slice_info.invocation_id == "" || slice_info.control_group == "" {
    True -> Error("slice_not_running_or_missing_control_group")
    False -> {
      case slice_info.invocation_id != reg.slice_invocation_id {
        True ->
          Error(
            "slice_invocation_id_mismatch_before_stop: observed="
            <> slice_info.invocation_id
            <> " registered="
            <> reg.slice_invocation_id,
          )
        False -> {
          // 2. Observe pre-stop unit info and match registered InvocationID
          use pre_unit_info <- result.try(get_unit_status(validated_unit))
          case pre_unit_info.invocation_id == "" {
            True -> Error("cannot_stop_unit_without_invocation_id")
            False -> {
              case pre_unit_info.invocation_id != reg.unit_invocation_id {
                True ->
                  Error(
                    "unit_invocation_id_mismatch_before_stop: observed="
                    <> pre_unit_info.invocation_id
                    <> " registered="
                    <> reg.unit_invocation_id,
                  )
                False -> {
                  // 3. Verify cgroup boundary with exact slash check
                  let slice_cg = slice_info.control_group
                  let unit_cg = pre_unit_info.control_group
                  case
                    unit_cg == slice_cg
                    || string.starts_with(unit_cg, slice_cg <> "/")
                  {
                    False -> Error("unit_not_owned_by_retained_slice")
                    True -> {
                      case
                        pre_unit_info.exec_path != ""
                        && {
                          string.contains(pre_unit_info.exec_path, "tail")
                          || string.contains(pre_unit_info.exec_path, "sleep")
                        }
                      {
                        True ->
                          Error(
                            "refused_non_worker_executable_in_registered_unit: "
                            <> pre_unit_info.exec_path,
                          )
                        False -> {
                          case
                            pre_unit_info.exec_path == ""
                            || {
                              !string.contains(pre_unit_info.exec_path, "beam")
                              && !string.contains(pre_unit_info.exec_path, "erl")
                            }
                          {
                            True ->
                              Error(
                                "refused_non_beam_executable_in_registered_unit: "
                                <> pre_unit_info.exec_path,
                              )
                            False -> {
                              // 4. Verify store incarnation before destructive stop
                              use actual_inc <- result.try(compute_store_incarnation(
                                reg.store_db_path,
                              ))
                      case actual_inc != reg.store_incarnation_id {
                        True ->
                          Error(
                            "store_incarnation_mismatch_before_stop: observed="
                            <> actual_inc
                            <> " registered="
                            <> reg.store_incarnation_id,
                          )
                        False -> {
                          // 5. Perform verified stop sequence
                          use _ <- result.try(execute_lifecycle_command(
                            StopUnit(validated_unit),
                          ))
                          use post_unit_info <- result.try(get_unit_status(
                            validated_unit,
                          ))
                          case
                            post_unit_info.active_state == "inactive"
                            || post_unit_info.active_state == "failed"
                          {
                            False ->
                              Error(
                                "unit_not_inactive_after_stop: "
                                <> post_unit_info.active_state,
                              )
                            True -> {
                              let full_cgroup =
                                "/sys/fs/cgroup" <> slice_info.control_group
                              use _ <- result.try(verify_cgroup_empty(full_cgroup))
                              let stopped_at = ffi_now_us()
                              use _ <- result.try(execute_lifecycle_command(
                                StopSlice(validated_slice),
                              ))
                              Ok(UnitCleanupReceipt(
                                unit_name: validated_unit,
                                slice_name: validated_slice,
                                invocation_id: pre_unit_info.invocation_id,
                                slice_invocation_id: slice_info.invocation_id,
                                store_incarnation_id: reg.store_incarnation_id,
                                service_epoch: reg.service_epoch,
                                stopped_at_us: stopped_at,
                                exit_status: 0,
                                cgroup_path: full_cgroup,
                                store_db_path: reg.store_db_path,
                                worker_hash: reg.worker_hash,
                                guardian_hash: reg.guardian_hash,
                              ))
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
                    }
                  }
                }
              }

// -----------------------------------------------------------------------------
// In-Memory Writer Hold Gate
// -----------------------------------------------------------------------------

pub fn evaluate_writer_gate(state: ServiceWriterState) -> Result(Nil, String) {
  case state {
    ServiceWriterClean -> Ok(Nil)
    ServiceWriterHold(reason) ->
      Error("service_writer_held: disk mutations barred: " <> reason)
  }
}
