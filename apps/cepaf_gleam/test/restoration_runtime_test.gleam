import cepaf_gleam/harness/value as v
import gleam/json
import gleam/list
import gleam/result
import gleeunit/should
import restoration_runtime_cli as runtime

pub fn arbitrary_effects_are_refused_test() {
  ["start", "shell", "restart_other", "install_clock_unit; id", ""]
  |> list.each(fn(name) {
    runtime.action(name) |> result.is_error |> should.be_true
  })
}

pub fn release_instance_path_injection_is_refused_test() {
  [
    "../../etc",
    "20260930-0600-abc",
    "20260930-0600-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.service",
    "20260930-0600-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/..",
  ]
  |> list.each(fn(name) { runtime.valid_instance(name) |> should.be_false })
  runtime.valid_instance(
    "20260930-0600-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  )
  |> should.be_true
}

pub fn service_authority_is_separated_by_resource_test() {
  runtime.resource(runtime.InstallClock) |> should.equal("runtime:clock-guard")
  runtime.resource(runtime.StartEcology) |> should.equal("runtime:ecology")
  runtime.resource(runtime.ReloadUnits) |> should.equal("integration/main")
  runtime.resource(runtime.RestartCockpit) |> should.equal("runtime:cockpit")
  runtime.resource(runtime.EnableCockpit) |> should.equal("runtime:cockpit")
  runtime.resource(runtime.EnableEcology) |> should.equal("runtime:ecology")
  runtime.resource(runtime.DisableOldEcology) |> should.equal("runtime:ecology")
}

pub fn missing_private_review_cannot_execute_test() {
  runtime.execute("missing-grant.json", "missing-review.json")
  |> result.is_error
  |> should.be_true
}

pub fn runtime_control_set_must_match_exactly_test() {
  let expected =
    json.object([#("runtime", json.string("abc")), #("ffi", json.string("def"))])
  runtime.controls_match(
    v.Object([#("ffi", v.Text("def")), #("runtime", v.Text("abc"))]),
    expected,
  )
  |> should.be_true
  [
    v.Object([#("runtime", v.Text("abc"))]),
    v.Object([#("runtime", v.Text("changed")), #("ffi", v.Text("def"))]),
    v.Object([
      #("runtime", v.Text("abc")),
      #("ffi", v.Text("def")),
      #("extra", v.Text("x")),
    ]),
    v.Object([#("runtime", v.Text("abc")), #("runtime", v.Text("abc"))]),
  ]
  |> list.each(fn(recorded) {
    runtime.controls_match(recorded, expected) |> should.be_false
  })
}

pub fn authority_window_covers_effect_and_cleanup_test() {
  [0, 1, 59_999_999, 60_000_000]
  |> list.each(fn(remaining) {
    runtime.window_valid(100, 100 + remaining) |> should.be_false
  })
  runtime.window_valid(100, 60_000_101) |> should.be_true
}

pub fn capability_workflow_is_exact_and_prior_completed_plan_is_refused_test() {
  runtime.authorized_workflow(
    "uos/capability-restoration/20260930-0734",
    "RELEASE",
    "codex-capability-restoration-20260930",
  )
  |> should.be_true
  runtime.authorized_workflow(
    "uos/full-restoration/20260930-0515",
    "RESTORE",
    "codex-full-restoration-20260930",
  )
  |> should.be_false
  runtime.authorized_workflow(
    "uos/capability-restoration/20260930-0734",
    "TRANSPORT",
    "codex-capability-restoration-20260930",
  )
  |> should.be_false
}

pub fn cognitive_release_cannot_inherit_unrelated_effects_test() {
  let new_plan = "uos/direct-dispatch/20261001-0440"
  let worker = "codex-direct-dispatch-20261001"
  [runtime.InstallCognitive, runtime.RestartCognitive, runtime.ReloadUnits]
  |> list.each(fn(selected) {
    runtime.authorized_action(new_plan, "RELEASE", worker, selected)
    |> should.be_true
    runtime.authorized_action(new_plan, "RUNTIME_PREP", worker, selected)
    |> should.be_false
    runtime.authorized_action(new_plan, "RELEASE", "other", selected)
    |> should.be_false
  })
  [
    runtime.InstallClock,
    runtime.InstallEcology,
    runtime.InstallCockpit,
    runtime.StopOldEcology,
    runtime.StartEcology,
    runtime.StopEcology,
    runtime.RestartPrimary,
    runtime.RestartBackup,
    runtime.RestartCockpit,
    runtime.EnableEcology,
    runtime.DisableOldEcology,
    runtime.EnableCockpit,
  ]
  |> list.each(fn(selected) {
    runtime.authorized_action(new_plan, "RELEASE", worker, selected)
    |> should.be_false
  })
  [runtime.InstallCognitive, runtime.RestartCognitive]
  |> list.each(fn(selected) {
    runtime.authorized_action(
      "uos/capability-restoration/20260930-0734",
      "RELEASE",
      "codex-capability-restoration-20260930",
      selected,
    )
    |> should.be_false
    runtime.resource(selected) |> should.equal("runtime:cognitive-worker")
  })
}

pub fn completed_cognitive_workflow_is_not_reused_test() {
  [runtime.InstallCognitive, runtime.RestartCognitive, runtime.ReloadUnits]
  |> list.each(fn(selected) {
    runtime.authorized_action(
      "uos/fractal-recheck/20261001-0226",
      "RELEASE",
      "codex-fractal-recheck-20261001",
      selected,
    )
    |> should.be_false
  })
}
