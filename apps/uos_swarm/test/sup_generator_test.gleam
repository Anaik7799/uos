// =============================================================================
// SUP-GENERATOR Verification Tests
// Invariant Verification: SC-HOLON-GEN-001, SC-HOLON-NAME-001, SC-OTP-001, SC-ZERO-MUDA-001
// =============================================================================

import gleam/list
import gleam/string
import gleeunit/should
import uos_swarm/holon
import uos_swarm/sup_generator

pub fn generate_from_holarchy_test() {
  let holarchy = holon.holarchy()
  case sup_generator.generate(holarchy) {
    Ok(plan) -> {
      // Must have scanned all holons
      plan.total_candidates_scanned |> should.equal(list.length(holarchy))

      // Must have filtered barred and absent items
      { plan.total_filtered_barred > 0 } |> should.be_true
      { plan.total_filtered_absent > 0 } |> should.be_true

      // Plan must validate
      case sup_generator.validate_plan(plan) {
        Ok(count) -> {
          { count >= 10 } |> should.be_true
        }
        Error(err) -> panic as err
      }
    }
    Error(err) -> panic as err
  }
}

pub fn four_domains_populated_test() {
  let holarchy = holon.holarchy()
  let assert Ok(plan) = sup_generator.generate(holarchy)

  let grouped = sup_generator.group_by_domain(plan.otp_children)
  list.length(grouped) |> should.equal(4)

  list.each(grouped, fn(pair) {
    let #(_domain, children) = pair
    { children != [] } |> should.be_true
  })
}

pub fn systemd_units_syntax_test() {
  let holarchy = holon.holarchy()
  let assert Ok(plan) = sup_generator.generate(holarchy)

  { list.length(plan.systemd_units) >= 5 } |> should.be_true

  // Check target unit
  let target_opt =
    list.find(plan.systemd_units, fn(u) { u.unit_type == "target" })
  case target_opt {
    Ok(t) -> {
      t.file_name |> should.equal("c3i.target")
      string.contains(t.content, "[Unit]") |> should.be_true
      string.contains(t.content, "[Install]") |> should.be_true
      string.contains(t.content, "WantedBy=default.target") |> should.be_true
    }
    Error(_) -> panic as "missing c3i.target unit"
  }

  // Check service units
  let service_units =
    list.filter(plan.systemd_units, fn(u) { u.unit_type == "service" })
  { list.length(service_units) >= 4 } |> should.be_true

  list.each(service_units, fn(s) {
    string.contains(s.content, "[Unit]") |> should.be_true
    string.contains(s.content, "[Service]") |> should.be_true
    string.contains(s.content, "[Install]") |> should.be_true
    string.contains(s.content, "Restart=on-failure") |> should.be_true
    string.contains(s.content, "25503L801736") |> should.be_true
  })
}

pub fn barred_and_absent_strictly_excluded_test() {
  let holarchy = holon.holarchy()
  let assert Ok(plan) = sup_generator.generate(holarchy)

  // No child may be barred or absent
  list.each(plan.otp_children, fn(c) {
    { c.status != "barred" } |> should.be_true
    { c.status != "absent" } |> should.be_true
    { c.status != "superseded" } |> should.be_true
  })
}

pub fn write_systemd_units_test() {
  let holarchy = holon.holarchy()
  let assert Ok(plan) = sup_generator.generate(holarchy)

  let scratch_dir = "test/scratch_systemd"
  case sup_generator.write_systemd_units(plan.systemd_units, scratch_dir) {
    Ok(count) -> {
      count |> should.equal(list.length(plan.systemd_units))
    }
    Error(err) -> panic as err
  }
}
