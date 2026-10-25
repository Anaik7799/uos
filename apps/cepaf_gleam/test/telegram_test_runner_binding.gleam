//// Test-only candidate-bound child launch. No production caller.
@external(erlang, "telegram_test_runtime", "launch_eval")
fn prepare(config_path: String) -> Result(String, String)

pub fn launch_eval(config_path: String) -> String {
  let assert Ok(expression) = prepare(config_path)
  expression
}
