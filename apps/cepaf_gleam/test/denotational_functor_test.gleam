//// apps/cepaf_gleam/test/denotational_functor_test.gleam
//// STAMP: SC-DENOTATIONAL-INTENT-001, SC-INTENT-ATLAS-001

import gleeunit/should
import cepaf_gleam/intent/denotational.{
  Intent, LatticeState, bottom, evaluate, initial_state, pure, bind, state_leq
}
import gleam/list

pub fn denotational_initial_state_test() {
  let s0 = initial_state()
  s0.is_bottom |> should.be_false
  s0.version |> should.equal(1)
  list.length(s0.trace_coords) |> should.equal(13)
}

pub fn denotational_valid_intent_test() {
  let s0 = initial_state()
  let valid_intent =
    Intent(
      authority: "sa-plan",
      target_drive_serial: "SAMSUNG_990_PRO_SECONDARY",
      criticality: "DAL-C",
      guardian_approved: False,
      delta_coord: 0.5,
      add_containers: ["c3i-cache"],
      add_topics: ["indrajaal/l5/cog/**"],
    )

  let s1 = evaluate(valid_intent, s0)
  s1.is_bottom |> should.be_false
  s1.version |> should.equal(2)
  list.contains(s1.active_containers, "c3i-cache") |> should.be_true
  list.contains(s1.zenoh_topics, "indrajaal/l5/cog/**") |> should.be_true
}

pub fn denotational_unauthorized_authority_fails_closed_test() {
  let s0 = initial_state()
  let unauth_intent =
    Intent(
      authority: "ad-hoc-agent",
      target_drive_serial: "SECONDARY_NVME",
      criticality: "DAL-C",
      guardian_approved: False,
      delta_coord: 0.0,
      add_containers: [],
      add_topics: [],
    )

  let s_err = evaluate(unauth_intent, s0)
  s_err.is_bottom |> should.be_true
  s_err.error_reason |> should.equal("UNAUTHORIZED_AUTHORITY_NOT_SA_PLAN")
}

pub fn denotational_root_os_nvme_hard_denied_test() {
  let s0 = initial_state()
  let bad_drive_intent =
    Intent(
      authority: "sa-plan",
      target_drive_serial: "25503L801736",
      criticality: "DAL-C",
      guardian_approved: False,
      delta_coord: 0.0,
      add_containers: [],
      add_topics: [],
    )

  let s_err = evaluate(bad_drive_intent, s0)
  s_err.is_bottom |> should.be_true
  s_err.error_reason |> should.equal("ROOT_OS_DRIVE_MUTATION_HARD_DENIED")
}

pub fn denotational_dal_a_unapproved_fails_closed_test() {
  let s0 = initial_state()
  let dal_a_unapproved =
    Intent(
      authority: "sa-plan",
      target_drive_serial: "SECONDARY_NVME",
      criticality: "DAL-A",
      guardian_approved: False,
      delta_coord: 0.0,
      add_containers: [],
      add_topics: [],
    )

  let s_err = evaluate(dal_a_unapproved, s0)
  s_err.is_bottom |> should.be_true
  s_err.error_reason |> should.equal("GUARDIAN_APPROVAL_MANDATORY_FOR_DAL_A")
}

pub fn denotational_bottom_absorption_test() {
  let s_bot = bottom("PREVIOUS_ERROR")
  let intent =
    Intent(
      authority: "sa-plan",
      target_drive_serial: "SECONDARY",
      criticality: "DAL-C",
      guardian_approved: False,
      delta_coord: 1.0,
      add_containers: [],
      add_topics: [],
    )

  let res = evaluate(intent, s_bot)
  res.is_bottom |> should.be_true
  res.error_reason |> should.equal("PREVIOUS_ERROR")
}

pub fn denotational_monad_laws_test() {
  let s0 = initial_state()
  // pure(s) == s
  pure(s0) |> should.equal(s0)

  // s >>= pure == s
  bind(s0, pure) |> should.equal(s0)

  // partial order monotonicity: s0 <= s1
  let s1 = LatticeState(..s0, version: 2)
  state_leq(s0, s1) |> should.be_true
  state_leq(bottom("err"), s0) |> should.be_true
}
