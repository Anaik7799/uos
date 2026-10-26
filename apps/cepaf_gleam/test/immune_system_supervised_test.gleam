//// Laws of the immune actor's supervised start (Mini App residual closed):
//// no supervisor, no actor, and the observer says so; a supervisor that owns
//// `child_spec` makes the actor discoverable by name, the observer reports
//// live state, a crash is restarted under the same name, and stopping the
//// supervisor returns the system to the truthful not-running answer.

import cepaf_gleam/immune/system
import cepaf_gleam/telegram/mini_api as api
import cepaf_gleam/telegram/mini_immune_observer as immune_observer
import gleam/erlang/process
import gleam/option.{None, Some}
import gleam/otp/static_supervisor as sup
import gleeunit/should

fn observed_fields_or_reason() -> Result(Int, String) {
  case immune_observer.observe_live(1_700_000_000, system.lookup(), 1000) {
    api.Observed(_, _, fields) -> Ok(dict_size(fields))
    api.Unavailable(reason) -> Error(reason)
    _ -> Error("unexpected_observation")
  }
}

@external(erlang, "maps", "size")
fn dict_size(d: a) -> Int

pub fn law_no_supervisor_means_not_running_test() {
  system.lookup() |> should.equal(None)
  observed_fields_or_reason()
  |> should.equal(Error(immune_observer.not_running_reason))
}

pub fn law_supervised_actor_is_discovered_restarted_and_observed_test() {
  let assert Ok(supervisor) =
    sup.new(sup.OneForOne)
    |> sup.restart_tolerance(intensity: 5, period: 10)
    |> sup.add(system.child_spec())
    |> sup.start
  let assert Some(actor) = system.lookup()
  // the observer reports live state through the discovered subject
  let assert Ok(fields) = observed_fields_or_reason()
  { fields > 0 } |> should.be_true
  // a crash is restarted under the same name: lookup finds the new incarnation
  let assert Ok(pid) = process.subject_owner(actor)
  process.unlink(pid)
  process.kill(pid)
  process.sleep(50)
  let assert Some(reborn) = system.lookup()
  let assert Ok(new_pid) = process.subject_owner(reborn)
  { new_pid != pid } |> should.be_true
  let assert Ok(_) = observed_fields_or_reason()
  // stopping the supervisor takes the actor with it and the answer is honest again
  process.unlink(supervisor.pid)
  process.kill(supervisor.pid)
  process.sleep(50)
  system.lookup() |> should.equal(None)
  observed_fields_or_reason()
  |> should.equal(Error(immune_observer.not_running_reason))
}
