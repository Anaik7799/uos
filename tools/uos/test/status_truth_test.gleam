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
  let #(code, _) =
    main.run_command(
      "toolchains/nix-profile/bin/erl",
      [
        "+S", "2:2", "+A", "2", "-noshell", "-eval",
        "code:add_paths(filelib:wildcard(\"tools/uos/build/dev/erlang/*/ebin\")), main:main(), halt(0).",
        "-extra", "status",
      ],
      15_000,
    )
  code |> should.equal(1)
}
