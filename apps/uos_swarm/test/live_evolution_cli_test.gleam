import gleam/string
import gleeunit/should
import live_evolution_cli

pub fn modules_and_loaded_artifact_inspection_are_runnable_test() {
  live_evolution_cli.run(["modules"])
  |> should.equal(Ok("clock_guard\ncoord\nlive_evolution\nmanager"))
  let inspected =
    live_evolution_cli.run(["inspect-loaded", "manager"]) |> should.be_ok
  string.contains(inspected, "\"module\":\"manager\"")
  |> should.equal(True)
  string.contains(inspected, "\"sha256\":") |> should.equal(True)
}

pub fn invalid_or_unallowlisted_loader_commands_fail_closed_test() {
  live_evolution_cli.run(["inspect-loaded", "other"]) |> should.be_error
  live_evolution_cli.run(["verify", "/tmp", "other", "nope"])
  |> should.be_error
  live_evolution_cli.run(["load", "/tmp", "manager", "nope"])
  |> should.be_error
}

pub fn usage_exposes_separate_primary_and_warm_backup_commands_test() {
  let usage = live_evolution_cli.usage()
  string.contains(usage, "instance-once <primary|backup>")
  |> should.equal(True)
  string.contains(usage, "instance-watch <primary|backup>")
  |> should.equal(True)
  string.contains(usage, "primary_floor_file|backup_floor_file")
  |> should.equal(True)
}
