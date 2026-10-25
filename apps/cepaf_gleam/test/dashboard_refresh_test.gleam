import cepaf_gleam/harness/dashboard_refresh.{
  type State, State, due, snapshot_interval_us,
}
import gleam/option.{type Option, None, Some}

pub fn initial_snapshot_is_due_test() {
  let previous: Option(State) = None
  assert snapshot_interval_us == 300_000_000
  assert due(0, "completed:0", previous) == Ok(True)
  assert due(42_000_000, "completed:1", previous) == Ok(True)
}

pub fn boundary_299999999_and_300000000_test() {
  let base_zero: State = State(0, "completed:2")
  assert due(299_999_999, "completed:2", Some(base_zero)) == Ok(False)
  assert due(300_000_000, "completed:2", Some(base_zero)) == Ok(True)
  assert due(300_000_001, "completed:2", Some(base_zero)) == Ok(True)

  let base_offset: State = State(10_000_000, "completed:2")
  assert due(309_999_999, "completed:2", Some(base_offset)) == Ok(False)
  assert due(310_000_000, "completed:2", Some(base_offset)) == Ok(True)
}

pub fn completion_marker_change_before_deadline_is_due_test() {
  let previous: State = State(1_000_000, "completed:1")
  assert due(1_000_000, "completed:2", Some(previous)) == Ok(True)
  assert due(6_000_000, "completed:2", Some(previous)) == Ok(True)
  assert due(300_999_999, "completed:2", Some(previous)) == Ok(True)
}

pub fn unchanged_marker_before_deadline_not_due_test() {
  let previous: State = State(5_000_000, "completed:3")
  assert due(5_000_000, "completed:3", Some(previous)) == Ok(False)
  assert due(5_000_001, "completed:3", Some(previous)) == Ok(False)
  assert due(150_000_000, "completed:3", Some(previous)) == Ok(False)
}

pub fn negative_and_backward_clock_refused_test() {
  let valid_previous: State = State(1_000_000, "completed:1")
  assert due(-1, "completed:1", None)
    == Error("now_boot_us must be non-negative")
  assert due(-500, "completed:1", Some(valid_previous))
    == Error("now_boot_us must be non-negative")

  let negative_previous: State = State(-1, "completed:1")
  assert due(1_000_000, "completed:1", Some(negative_previous))
    == Error("last_snapshot_boot_us must be non-negative")

  assert due(999_999, "completed:1", Some(valid_previous))
    == Error("clock moved backward")
  assert due(0, "completed:1", Some(valid_previous))
    == Error("clock moved backward")
}

pub fn empty_marker_refused_test() {
  let valid_previous: State = State(1_000_000, "completed:1")
  assert due(1_000_000, "", None)
    == Error("completion_marker must not be empty")
  assert due(1_000_000, "   ", None)
    == Error("completion_marker must not be empty")
  assert due(1_000_000, "", Some(valid_previous))
    == Error("completion_marker must not be empty")

  let empty_previous: State = State(1_000_000, "")
  assert due(1_000_000, "completed:1", Some(empty_previous))
    == Error("prior completion_marker must not be empty")
}
