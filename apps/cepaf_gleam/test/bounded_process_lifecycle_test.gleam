import gleam/erlang/process
import gleam/int
import gleam/string
import gleeunit/should
import simplifile

@external(erlang, "ecology_capability_ffi", "run_bounded")
fn run(
  path: String,
  args: List(String),
  timeout_ms: Int,
) -> Result(#(Int, BitArray), String)

const root = "/home/an/NAS-setup/uos"

@external(erlang, "erlang", "unique_integer")
fn unique_integer() -> Int

@external(erlang, "erlang", "system_time")
fn system_time() -> Int

@external(erlang, "filelib", "is_file")
fn file_exists(path: String) -> Bool

fn child(args: List(String), deadline: Int) {
  run(
    root <> "/toolchains/opam-ocaml/bin/ocaml",
    [
      "-I",
      "+unix",
      root <> "/tools/validation/ecology_process_fixture.ml",
      ..args
    ],
    deadline,
  )
}

fn fixture(mode: String, delay: String, code: String, deadline: Int) {
  child([mode, delay, code], deadline)
}

pub fn closed_output_is_not_process_completion_test() {
  fixture("closed-output", "0.05", "7", 3000) |> should.equal(Ok(#(7, <<>>)))
}

pub fn open_output_exit_status_control_test() {
  fixture("open-output", "0.05", "7", 3000) |> should.equal(Ok(#(7, <<>>)))
}

pub fn closed_output_does_not_cancel_absolute_deadline_test() {
  fixture("closed-output", "2.0", "0", 250) |> should.equal(Error("timeout"))
}

pub fn closed_output_preserves_success_test() {
  fixture("closed-output", "0.05", "0", 3000) |> should.equal(Ok(#(0, <<>>)))
}

pub fn closed_output_does_not_hide_signal_failure_test() {
  child(["closed-signal"], 3000)
  |> should.equal(Error("backend_output_or_process_failure"))
}

pub fn output_overflow_stays_refused_test() {
  child(["flood"], 3000) |> should.be_error
}

pub fn closed_output_descendants_are_killed_before_reaping_test() {
  let marker = "/tmp/uos-closed-tree-" <> int.to_string(unique_integer())
  child(["closed-tree", marker], 3000) |> should.equal(Ok(#(0, <<>>)))
  process.sleep(1000)
  file_exists(marker) |> should.be_false
}

pub fn timeout_descendants_are_killed_test() {
  let marker = "/tmp/uos-timeout-tree-" <> int.to_string(unique_integer())
  child(["tree", marker], 250) |> should.equal(Error("timeout"))
  process.sleep(1100)
  file_exists(marker) |> should.be_false
}

fn fault_after(point: String) {
  let unique =
    int.to_string(system_time()) <> "-" <> int.to_string(unique_integer())
  let script = "/tmp/uos-guardian-fault-" <> unique <> ".ml"
  let marker = "/tmp/uos-guardian-post-reap-kill-" <> unique
  let assert Ok(source) = simplifile.read(root <> "/tools/ecology_process.ml")
  let reached = marker <> ".reached"
  string.contains(source, point) |> should.be_true
  let instrumentation =
    "open Unix\nlet test_reaped=ref false\n"
    <> "let kill target signal = if !test_reaped then (let channel=open_out \""
    <> marker
    <> "\" in output_string channel \"unsafe_kill\";close_out channel) else Unix.kill target signal\n"
  let injected =
    source
    |> string.replace("open Unix\n", instrumentation)
    |> string.replace(
      point,
      point
        <> " test_reaped:=true;let reached=open_out \""
        <> reached
        <> "\" in close_out reached;raise Exit;",
    )
  let assert Ok(Nil) = simplifile.write(script, injected)
  let result =
    run(
      root <> "/toolchains/opam-ocaml/bin/ocaml",
      [
        "-I",
        "+unix",
        script,
        "1000",
        "4096",
        "merged",
        root <> "/toolchains/nix-profile/bin/true",
      ],
      3000,
    )
  file_exists(reached) |> should.be_true
  file_exists(marker) |> should.be_false
  result |> should.equal(Error("timeout"))
}

pub fn exception_after_reap_never_kills_reused_identity_test() {
  fault_after("let _,status=waitpid [] pid in")
}

pub fn exception_after_descriptor_close_is_idempotent_test() {
  fault_after("let _,status=waitpid [] pid in close input;")
}
