import gleeunit/should
import gleam/list
import gleam/result
import gleam/json
import cepaf_gleam/harness/value as v
import restoration_runtime_cli as runtime

pub fn arbitrary_effects_are_refused_test() {
  ["start", "shell", "restart_other", "install_clock_unit; id", ""]
  |> list.each(fn(name) { runtime.action(name) |> result.is_error |> should.be_true })
}

pub fn release_instance_path_injection_is_refused_test() {
  ["../../etc", "20260930-0600-abc", "20260930-0600-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.service", "20260930-0600-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/.."]
  |> list.each(fn(name) { runtime.valid_instance(name) |> should.be_false })
  runtime.valid_instance("20260930-0600-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa") |> should.be_true
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
  runtime.execute("missing-grant.json", "missing-review.json") |> result.is_error |> should.be_true
}

pub fn runtime_control_set_must_match_exactly_test() {
  let expected = json.object([#("runtime", json.string("abc")), #("ffi", json.string("def"))])
  runtime.controls_match(v.Object([#("ffi", v.Text("def")), #("runtime", v.Text("abc"))]), expected) |> should.be_true
  [v.Object([#("runtime", v.Text("abc"))]),
   v.Object([#("runtime", v.Text("changed")), #("ffi", v.Text("def"))]),
   v.Object([#("runtime", v.Text("abc")), #("ffi", v.Text("def")), #("extra", v.Text("x"))]),
   v.Object([#("runtime", v.Text("abc")), #("runtime", v.Text("abc"))])]
  |> list.each(fn(recorded) { runtime.controls_match(recorded, expected) |> should.be_false })
}

pub fn authority_window_covers_effect_and_cleanup_test() {
  [0, 1, 59_999_999, 60_000_000]
  |> list.each(fn(remaining) { runtime.window_valid(100, 100 + remaining) |> should.be_false })
  runtime.window_valid(100, 60_000_101) |> should.be_true
}
pub fn capability_workflow_is_exact_and_prior_completed_plan_is_refused_test() {
  runtime.authorized_workflow(
    "uos/capability-restoration/20260930-0734", "RELEASE",
    "codex-capability-restoration-20260930",
  ) |> should.be_true
  runtime.authorized_workflow(
    "uos/full-restoration/20260930-0515", "RESTORE",
    "codex-full-restoration-20260930",
  ) |> should.be_false
  runtime.authorized_workflow(
    "uos/capability-restoration/20260930-0734", "TRANSPORT",
    "codex-capability-restoration-20260930",
  ) |> should.be_false
}
