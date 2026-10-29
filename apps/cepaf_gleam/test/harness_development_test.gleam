import cepaf_gleam/harness/admission
import cepaf_gleam/harness/clock
import cepaf_gleam/harness/development as dev
import cepaf_gleam/harness/files
import cepaf_gleam/harness/mcp
import cepaf_gleam/harness/value
import gleam/bit_array
import gleam/crypto
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import simplifile

fn binding() {
  dev.Binding("development", "plan", "task", "worker", 4, "session", 2)
}

pub fn clock_reference_and_fresh_receipt_are_independent_test() {
  // A valid five-minute-old NTP reference cannot make a stale receipt fresh.
  clock.reference_and_delivery_valid(600_000_000, 300_000_000, 1000)
  |> should.be_true
  clock.reference_and_delivery_valid(600_000_000, 300_000_000, 3_000_001)
  |> should.be_false
  clock.reference_and_delivery_valid(3_600_000_001, 0, 1000)
  |> should.be_false
  clock.reference_and_delivery_valid(600_000_000, 600_000_001, 1000)
  |> should.be_false
  clock.reference_and_delivery_valid(600_000_000, 300_000_000, -1)
  |> should.be_false
}

pub fn loaded_control_identity_is_observed_from_otp_test() {
  dev.control_id() |> string.length |> should.equal(32)
}

pub fn client_control_ids_are_required_and_revision_bound_test() {
  let ids = admission.control_ids()
  let parsed = json.parse(json.to_string(ids), value.decoder())
  case parsed {
    Ok(value.Object(entries)) -> {
      let omitted =
        value.Object(
          list.filter(entries, fn(entry) {
            entry.0 != "cepaf_gleam@harness@client_mcp"
          }),
        )
      admission.control_ids_match(omitted, ids) |> should.be_false
      let changed =
        value.Object(
          list.map(entries, fn(entry) {
            case entry.0 {
              "cepaf_gleam@harness@client_mcp" -> #(
                "cepaf_gleam@harness@client_mcp",
                value.Text("changed"),
              )
              _ -> entry
            }
          }),
        )
      admission.control_ids_match(changed, ids) |> should.be_false
    }
    _ -> should.fail()
  }
}

pub fn frame_deadline_is_absolute_and_supports_signed_monotonic_instants_test() {
  mcp.frame_budget(-10_000, -9000) |> should.equal(Ok(4000))
  mcp.frame_budget(-10_000, -5000) |> should.equal(Error("frame_deadline"))
  mcp.frame_budget(-10_000, -10_001) |> should.equal(Error("frame_deadline"))
}

pub fn replay_preserves_failure_and_rejects_corrupt_or_unbound_receipts_test() {
  let fields = [
    #("schema", json.string("uos.harness-effect.v1")),
    #("intent_id", json.string("one")),
    #("tool", json.string("harness_test")),
    #("signature", json.string("digest")),
  ]
  let failed =
    json.object([
      #("status", json.string("FAILED_OR_UNVERIFIED")),
      #("verification", json.string("backend_exit:1")),
      ..fields
    ])
    |> json.to_string
  dev.replay_receipt(failed, "one", "harness_test", "digest")
  |> should.equal(Error("saved_effect_failed_or_unverified_no_retry"))
  dev.replay_receipt("broken json", "one", "harness_test", "digest")
  |> should.be_error
  let success =
    json.object([
      #("status", json.string("EXECUTED")),
      #("verification", json.string("passed")),
      ..fields
    ])
    |> json.to_string
  dev.replay_receipt(success, "other", "harness_test", "digest")
  |> should.equal(Error("saved_receipt_binding_mismatch"))
  dev.replay_receipt(success, "one", "harness_test", "altered-signature")
  |> should.equal(Error("saved_receipt_binding_mismatch"))
  dev.replay_receipt(success, "one", "harness_test", "digest") |> should.be_ok
}

fn fixture(check: fn(String) -> Nil) {
  let root =
    "/tmp/uos-harness-"
    <> { crypto.strong_random_bytes(12) |> bit_array.base16_encode }
  let assert Ok(_) = simplifile.create_directory(root)
  check(root)
  // Only this freshly generated fixture directory is removed.
  let assert Ok(_) = simplifile.delete(root)
}

pub fn bounded_utf8_and_empty_reader_test() {
  fixture(fn(root) {
    files.create(root, "text", "Gleam λ 日本語") |> should.equal(Ok(Nil))
    files.read(root, "text") |> should.equal(Ok("Gleam λ 日本語"))
    files.create(root, "empty", "") |> should.equal(Ok(Nil))
    files.read(root, "empty") |> should.equal(Ok(""))
  })
}

pub fn invalid_utf8_is_a_typed_error_test() {
  fixture(fn(root) {
    let assert Ok(_) = simplifile.write_bits(root <> "/invalid", <<255>>)
    files.read(root, "invalid") |> should.equal(Error("invalid_utf8"))
  })
}

pub fn traversal_and_absolute_paths_fail_test() {
  files.relative_path("../file") |> should.be_error
  files.relative_path("/etc/passwd") |> should.be_error
  files.relative_path("a/../b") |> should.be_error
  files.relative_path("a//b") |> should.be_error
  files.relative_path("a\u{0}") |> should.be_error
}

pub fn source_workspace_root_is_confined_to_a_real_direct_workspace_test() {
  fixture(fn(root) {
    let assert Ok(_) = simplifile.create_directory(root <> "/.uos-workspaces")
    let assert Ok(_) =
      simplifile.create_directory(root <> "/.uos-workspaces/candidate")
    files.workspace_root(root, ".uos-workspaces/candidate")
    |> should.equal(Ok(root <> "/.uos-workspaces/candidate"))
    let assert Error(_) = files.workspace_root(root, "apps/cepaf_gleam")
    let assert Error(_) =
      files.workspace_root(root, ".uos-workspaces/candidate/nested")
    let assert Error(_) =
      files.workspace_root(root, ".uos-workspaces/../escape")
    let assert Ok(_) = simplifile.create_directory(root <> "/outside")
    let assert Ok(_) =
      simplifile.create_symlink(
        root <> "/outside",
        root <> "/.uos-workspaces/alias",
      )
    let assert Error(_) = files.workspace_root(root, ".uos-workspaces/alias")
    Nil
  })
}

pub fn symlink_and_parent_aliases_fail_without_reading_target_test() {
  fixture(fn(root) {
    let assert Ok(_) = simplifile.create_directory(root <> "/real")
    let assert Ok(_) = files.create(root, "real/target", "public fixture")
    let assert Ok(_) =
      simplifile.create_symlink("real/target", root <> "/alias")
    let assert Ok(_) = simplifile.create_symlink("real", root <> "/parent")
    files.read(root, "alias")
    |> should.equal(Error("regular_single_link_file_bound"))
    files.read(root, "parent/target")
    |> should.equal(Error("parent_not_regular_directory"))
  })
}

pub fn hardlink_and_oversized_files_fail_test() {
  fixture(fn(root) {
    let assert Ok(_) = files.create(root, "target", "public fixture")
    let assert Ok(_) =
      simplifile.create_link(root <> "/target", root <> "/alias")
    files.read(root, "target")
    |> should.equal(Error("regular_single_link_file_bound"))
    let assert Ok(_) =
      simplifile.write(
        root <> "/large",
        string.repeat("x", files.max_bytes + 1),
      )
    files.read(root, "large")
    |> should.equal(Error("regular_single_link_file_bound"))
  })
}

pub fn exclusive_create_and_compare_replace_preserve_conflicts_test() {
  fixture(fn(root) {
    files.create(root, "document", "before") |> should.equal(Ok(Nil))
    files.create(root, "document", "overwrite")
    |> should.equal(Error("exclusive_create_failed"))
    files.replace(root, "document", files.digest("wrong"), "after")
    |> should.equal(Error("source_digest_conflict"))
    files.read(root, "document") |> should.equal(Ok("before"))
    files.replace(root, "document", files.digest("before"), "after")
    |> should.equal(Ok(Nil))
    files.read(root, "document") |> should.equal(Ok("after"))
  })
}

pub fn production_wrong_worker_attempt_and_expiry_are_rejected_test() {
  let b = binding()
  dev.evaluate_fence(b, "executing", "worker", 4, 80_000_000_000, 0, 0)
  |> should.equal(Ok(Nil))
  dev.evaluate_fence(
    dev.Binding(..b, role: "production"),
    "executing",
    "worker",
    4,
    80_000_000_000,
    0,
    0,
  )
  |> should.be_error
  dev.evaluate_fence(b, "executing", "other", 4, 80_000_000_000, 0, 0)
  |> should.be_error
  dev.evaluate_fence(b, "executing", "worker", 5, 80_000_000_000, 0, 0)
  |> should.be_error
  dev.evaluate_fence(b, "executing", "worker", 4, 70_000_000_000, 0, 0)
  |> should.be_error
  dev.evaluate_fence(b, "executing", "worker", 4, 80_000_000_000, 1, 0)
  |> should.be_error
  dev.evaluate_fence(b, "completed", "worker", 4, 80_000_000_000, 0, 0)
  |> should.be_error
}

pub fn payload_cannot_supply_role_identity_or_backend_test() {
  dev.validate_arguments(
    "harness_build",
    value.Object([
      #("intent_id", value.Text("build")),
      #("role", value.Text("production")),
    ]),
  )
  |> should.be_error
  dev.validate_arguments(
    "harness_test",
    value.Object([
      #("intent_id", value.Text("test")),
      #("backend", value.Text("shell")),
    ]),
  )
  |> should.be_error
  dev.valid_identifier("plan'; DROP TABLE t;") |> should.be_false
}

pub fn finite_file_scope_excludes_credentials_and_external_trees_test() {
  dev.readable(".env") |> should.be_false
  dev.readable("/home/an/dev/ver/zigvm/config.json") |> should.be_false
  dev.source_allowed("tools/arbitrary.sh") |> should.be_false
  dev.document_allowed("docs/design/old.md") |> should.be_false
  dev.source_allowed("apps/cepaf_gleam/src/cepaf_gleam/harness/files.gleam")
  |> should.be_true
}

pub fn mcp_lifecycle_notifications_and_unknown_tools_fail_closed_test() {
  let b = binding()
  let assert #(_, Some(uninitialized)) =
    mcp.handle(
      b,
      mcp.initial,
      "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/list\"}",
    )
  uninitialized |> string.contains("initialize_required") |> should.be_true
  let assert #(state, Some(reply)) =
    mcp.handle(
      b,
      mcp.initial,
      "{\"jsonrpc\":\"2.0\",\"id\":\"init\",\"method\":\"initialize\"}",
    )
  reply |> string.contains("uos-gleam-development-harness") |> should.be_true
  mcp.handle(
    b,
    state,
    "{\"jsonrpc\":\"2.0\",\"method\":\"tools/call\",\"params\":{\"name\":\"harness_build\",\"arguments\":{\"intent_id\":\"must-not-run\"}}}",
  )
  |> should.equal(#(state, None))
  let assert #(_, Some(unknown)) =
    mcp.handle(
      b,
      state,
      "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"arbitrary_shell\",\"arguments\":{}}}",
    )
  unknown |> string.contains("unknown_or_unadmitted_tool") |> should.be_true
}

pub fn generic_json_preserves_nested_types_test() {
  let source =
    "{\"integer\":1788936215572413498,\"boolean\":false,\"null\":null,\"array\":[\"λ\",0.25]}"
  let assert Ok(parsed) = json.parse(source, value.decoder())
  let assert Ok(again) =
    json.parse(json.to_string(value.encode(parsed)), value.decoder())
  again |> should.equal(parsed)
}


pub fn bounded_profile_refuses_noncanonical_executable_and_profile_test() {
  dev.bounded_profile(
    "/bin/true",
    [],
    "/tmp/not-an-agy-private-profile",
    1000,
  )
  |> should.equal(Error("agy_profile_isolation_refused"))
}

pub fn bounded_profile_refuses_non_private_profile_root_test() {
  dev.bounded_profile(
    "/home/an/.local/bin/agy",
    [],
    "/tmp/uos-harness-client-profiles/agy/fixture-grant",
    1000,
  )
  |> should.equal(Error("agy_profile_isolation_refused"))
}

pub fn bounded_profile_refuses_wrong_profile_root_test() {
  dev.bounded_profile(
    "/home/an/.local/bin/agy",
    [],
    "/run/user/1000/not-uos-harness-client-profiles/agy/fixture-grant",
    1000,
  )
  |> should.equal(Error("agy_profile_isolation_refused"))
}

pub fn bounded_profile_refuses_traversal_profile_root_test() {
  dev.bounded_profile(
    "/home/an/.local/bin/agy",
    [],
    "/run/user/1000/uos-harness-client-profiles/agy/../fixture-grant",
    1000,
  )
  |> should.equal(Error("agy_profile_isolation_refused"))
}

pub fn bounded_profile_rejects_timeout_outside_bounds_test() {
  dev.bounded_profile(
    "/home/an/.local/bin/agy",
    [],
    "/tmp/not-an-agy-private-profile",
    0,
  )
  |> should.equal(Error("invalid_profile_bound"))
  dev.bounded_profile(
    "/home/an/.local/bin/agy",
    [],
    "/tmp/not-an-agy-private-profile",
    60001,
  )
  |> should.equal(Error("invalid_profile_bound"))
}

pub fn mcp_client_config_is_not_readable_or_writable_as_project_file_test() {
  dev.readable("/home/an/.gemini/antigravity/mcp_config.json")
  |> should.be_false
  dev.readable(".gemini/antigravity/mcp_config.json") |> should.be_false
  dev.source_allowed(".gemini/antigravity/mcp_config.json")
  |> should.be_false
  dev.document_allowed(".gemini/antigravity/mcp_config.json")
  |> should.be_false
  dev.readable("/home/an/.codex/config.toml") |> should.be_false
  dev.readable("/home/an/.claude.json") |> should.be_false
  dev.readable("/home/an/.pi/agent/mcp.json") |> should.be_false
}
