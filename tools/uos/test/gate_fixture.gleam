//// Test-only isolated repository and exact loaded CLI child binding.
@external(erlang, "uos_gate_test_fixture", "with_empty_repository")
pub fn with_empty_repository(run: fn() -> a) -> a

@external(erlang, "uos_gate_test_fixture", "cli_invocation")
pub fn cli_invocation() -> #(String, List(String))
