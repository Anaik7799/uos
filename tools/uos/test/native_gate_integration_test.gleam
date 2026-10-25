//// Requires a candidate repository with candidate-built native suites.
//// Keep this integration suite separate from isolated CLI verdict unit tests.
import gleeunit/should
import main

pub fn sa_plan_gate_executes_thirteen_suites_and_returns_zero_test() {
  main.execute(main.SelfcheckSaPlan) |> should.equal(0)
}

pub fn mirage_gates_execute_their_suites_and_return_zero_test() {
  main.execute(main.SelfcheckMirage) |> should.equal(0)
  main.execute(main.SelfcheckMirageMigration) |> should.equal(0)
  main.execute(main.SelfcheckMirageProd) |> should.equal(0)
  main.execute(main.SelfcheckMirageTenders) |> should.equal(0)
}
