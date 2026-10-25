import gate_fixture
import gleeunit/should
import main

// A successful process exit must not be interpreted as observed system health
// when this command has not executed any runtime probe.
pub fn unobserved_runtime_status_cannot_return_success_test() {
  main.execute(main.Status) |> should.equal(1)
}

// Exercise the entry point in a child VM: returning an Int from main does not
// propagate that value to the operating system's exit status.
pub fn cli_process_preserves_failure_exit_status_test() {
  let #(executable, arguments) = gate_fixture.cli_invocation()
  let #(code, _) = main.run_command(executable, arguments, 15_000)
  code |> should.equal(1)
}
