//// =============================================================================
//// [C3I-SIL6-MSTS] OTP RELEASE PACKAGING TESTS
//// =============================================================================
////
//// विकास — Evolution through typed release packaging (SC-HA-RELOAD-001)
////
//// Tests for cepaf_gleam/ha/otp_release.gleam
////
//// Coverage (10 tests across 4 sections):
////   Section 1 — ReleaseSpec constructors and field contract (3 tests)
////   Section 2 — AppUpSpec from changed module list (2 tests)
////   Section 3 — format_rel / format_appup output contract (3 tests)
////   Section 4 — AppType round-trip and helpers (2 tests)
////
//// STAMP: SC-HA-RELOAD-001, SC-HA-001, SC-FUNC-001
//// Layer: L4_SYSTEM

import cepaf_gleam/ha/otp_release.{
  AddModule, AppUpSpec, DeleteModule, LoadModule, Permanent, Restart, Temporary,
  Transient, UpdateModule,
}
import gleam/list
import gleam/string
import gleeunit/should

// ---------------------------------------------------------------------------
// Section 1 — ReleaseSpec constructors and field contract
// ---------------------------------------------------------------------------

/// current_release/0 must return a spec named "cepaf_gleam".
pub fn current_release_name_test() {
  let spec = otp_release.current_release()
  spec.name |> should.equal("cepaf_gleam")
}

/// current_release/0 must return version "22.12.0".
pub fn current_release_version_test() {
  let spec = otp_release.current_release()
  spec.version |> should.equal("22.12.0")
}

/// current_release/0 applications list must be non-empty and contain
/// a permanent "kernel" entry as the first element.
pub fn current_release_applications_non_empty_test() {
  let spec = otp_release.current_release()
  let apps = spec.applications
  { apps != [] } |> should.be_true()
  // First app must be kernel (required for any valid .rel)
  let first = case apps {
    [a, ..] -> a.name
    [] -> ""
  }
  first |> should.equal("kernel")
}

// ---------------------------------------------------------------------------
// Section 2 — AppUpSpec from changed module list
// ---------------------------------------------------------------------------

/// appup_from_changes/2 must produce the correct version in the spec.
pub fn appup_from_changes_version_test() {
  let spec = otp_release.appup_from_changes("22.12.1", ["my_module"])
  spec.version |> should.equal("22.12.1")
}

/// appup_from_changes/2 must produce upgrade_from and downgrade_to lists
/// with the same length as the input changed_modules list.
pub fn appup_from_changes_instruction_count_test() {
  let modules = ["moduleA", "moduleB", "moduleC"]
  let spec = otp_release.appup_from_changes("22.12.1", modules)
  list.length(spec.upgrade_from) |> should.equal(3)
  list.length(spec.downgrade_to) |> should.equal(3)
}

// ---------------------------------------------------------------------------
// Section 3 — format_rel / format_appup output contract
// ---------------------------------------------------------------------------

/// format_rel/1 output must start with "{release," and end with "}.".
pub fn format_rel_structure_test() {
  let spec = otp_release.current_release()
  let output = otp_release.format_rel(spec)
  output |> string.starts_with("{release,") |> should.be_true()
  output |> string.ends_with("}.") |> should.be_true()
}

/// format_rel/1 output must contain the release name and version.
pub fn format_rel_contains_name_and_version_test() {
  let spec = otp_release.current_release()
  let output = otp_release.format_rel(spec)
  output |> string.contains(spec.name) |> should.be_true()
  output |> string.contains(spec.version) |> should.be_true()
  output |> string.contains(spec.erts_version) |> should.be_true()
}

/// format_appup/1 output must contain the version and both ".*" wildcard
/// patterns for upgrade_from and downgrade_to sections.
pub fn format_appup_contains_version_and_wildcards_test() {
  let spec = otp_release.appup_from_changes("22.12.1", ["test_mod"])
  let output = otp_release.format_appup(spec)
  output |> string.contains("22.12.1") |> should.be_true()
  // Two wildcard patterns — one per direction
  let wildcard_count =
    string.split(output, "\".*\"")
    |> list.length()
  // 2 occurrences → split yields 3 parts
  { wildcard_count >= 3 } |> should.be_true()
}

// ---------------------------------------------------------------------------
// Section 4 — AppType round-trip and UpgradeInstruction formatting
// ---------------------------------------------------------------------------

/// app_type_to_string / app_type_from_string must round-trip for all three
/// canonical AppType variants.
pub fn app_type_round_trip_test() {
  [Permanent, Transient, Temporary]
  |> list.each(fn(t) {
    t
    |> otp_release.app_type_to_string()
    |> otp_release.app_type_from_string()
    |> should.equal(t)
  })
}

/// format_appup/1 must include the correct Erlang instruction atoms for
/// each UpgradeInstruction variant: add_module, update, delete_module,
/// restart_application.
pub fn format_appup_instruction_atoms_test() {
  let spec =
    AppUpSpec(
      version: "1.0",
      upgrade_from: [
        AddModule("mod_a"),
        UpdateModule("mod_b"),
        DeleteModule("mod_c"),
        Restart("app_x"),
        LoadModule("mod_d"),
      ],
      downgrade_to: [],
    )
  let output = otp_release.format_appup(spec)
  output |> string.contains("add_module") |> should.be_true()
  output |> string.contains("update") |> should.be_true()
  output |> string.contains("delete_module") |> should.be_true()
  output |> string.contains("restart_application") |> should.be_true()
  output |> string.contains("load_module") |> should.be_true()
}
