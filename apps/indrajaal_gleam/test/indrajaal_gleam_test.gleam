import gleeunit
import gleeunit/should
import gleam/option.{None, Some}
import indrajaal/holon.{Act, Decide, Initialized, Observe, new_holon, step_cycle}

pub fn main() {
  gleeunit.main()
}

pub fn holon_initialization_test() {
  let h = new_holon("holon-alpha", None)
  h.coord.id |> should.equal("holon-alpha")
  h.lifecycle |> should.equal(Initialized)
  h.current_phase |> should.equal(Observe)
}

pub fn holon_cycle_transition_test() {
  let h = new_holon("holon-beta", Some("root"))
  let next = step_cycle(h, Decide, 1)
  case next {
    Ok(s) -> {
      s.current_phase |> should.equal(Decide)
    }
    Error(_) -> panic as "Transition failed"
  }
}

pub fn holon_fencing_reject_stale_generation_test() {
  let h = new_holon("holon-gamma", None)
  let stale_step = step_cycle(h, Act, 0)
  case stale_step {
    Ok(_) -> panic as "Fencing token did not reject stale generation"
    Error(err) -> err |> should.equal("FENCING_REJECT: Stale lease generation")
  }
}
