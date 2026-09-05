// =============================================================================
// UOS Multi-Layer Supervision Tree Verification Tests
// =============================================================================

import cepaf_gleam/uos_sup
import gleeunit/should

pub fn uos_root_spec_valid_test() {
  let spec = uos_sup.uos_root_spec()
  spec.name |> should.equal("UOSRootSupervisor")
  
  case uos_sup.validate_spec(spec) {
    Ok(child_count) -> {
      { child_count >= 8 } |> should.be_true()
    }
    Error(err) -> panic as err
  }
}

pub fn uos_root_supervisor_start_test() {
  case uos_sup.start_root_supervisor() {
    Ok(_) -> should.be_true(True)
    Error(_) -> panic as "failed to start root supervisor"
  }
}
