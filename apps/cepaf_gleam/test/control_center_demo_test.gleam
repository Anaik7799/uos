//// [C3I-SIL6-MSTS] TEST SUITE
//// <c3i-test>
////   <target>cepaf_gleam/ui/lustre/control_center_demo</target>
////   <compliance>SC-GLM-UI-001, SC-HMI-010, SC-JIDOKA-001, SC-CHECKLIST-001</compliance>
//// </c3i-test>

import cepaf_gleam/ui/lustre/control_center_demo as demo
import gleeunit/should

pub fn demo_init_state_test() {
  let model = demo.init()
  model.spring_cover_open |> should.equal(False)
  model.spring_armed |> should.equal(False)
  model.spring_timer_ms |> should.equal(5000)
  model.key_a_turned |> should.equal(False)
  model.key_b_turned |> should.equal(False)
  model.andon_tripped |> should.equal(False)
  model.os_drive_serial |> should.equal("25503L801736")
  model.os_drive_locked |> should.equal(True)
  model.cohomology_h1_zero |> should.equal(True)
}

pub fn spring_cover_actuation_lifecycle_test() {
  let m0 = demo.init()

  // 1. Attempt actuation while closed -> Blocked
  let m_blocked = demo.update(m0, demo.ConfirmSpringActuate)
  m_blocked.spring_cover_open |> should.equal(False)

  // 2. Open cover
  let m1 = demo.update(m0, demo.ToggleSpringCover)
  m1.spring_cover_open |> should.equal(True)
  m1.spring_armed |> should.equal(True)
  m1.spring_timer_ms |> should.equal(5000)

  // 3. Actuate while open -> Success, snaps shut
  let m2 = demo.update(m1, demo.ConfirmSpringActuate)
  m2.spring_cover_open |> should.equal(False)
  m2.spring_armed |> should.equal(False)
}

pub fn spring_cover_auto_timeout_test() {
  let m0 = demo.init()
  let m1 = demo.update(m0, demo.ToggleSpringCover)
  m1.spring_cover_open |> should.equal(True)

  // Partial tick (2000ms elapsed) -> still open
  let m2 = demo.update(m1, demo.TickAutoClose(2000))
  m2.spring_cover_open |> should.equal(True)
  m2.spring_timer_ms |> should.equal(3000)

  // Remainder tick (3500ms elapsed) -> timeout, snaps shut
  let m3 = demo.update(m2, demo.TickAutoClose(3500))
  m3.spring_cover_open |> should.equal(False)
  m3.spring_timer_ms |> should.equal(0)
}

pub fn two_man_rule_interlock_test() {
  let m0 = demo.init()

  // Turn Key A only
  let m1 = demo.update(m0, demo.TurnKeyA)
  m1.key_a_turned |> should.equal(True)
  m1.key_b_turned |> should.equal(False)

  // Turn Key B -> dual consensus closed circuit
  let m2 = demo.update(m1, demo.TurnKeyB)
  m2.key_a_turned |> should.equal(True)
  m2.key_b_turned |> should.equal(True)

  // Disengage Key A -> consensus broken
  let m3 = demo.update(m2, demo.TurnKeyA)
  m3.key_a_turned |> should.equal(False)
  m3.key_b_turned |> should.equal(True)
}

pub fn andon_cord_jidoka_halt_test() {
  let m0 = demo.init()

  // Trip cord
  let m1 =
    demo.update(
      m0,
      demo.PullAndonCord(
        "Split-brain quorum loss detected in Ceph storage mesh",
      ),
    )
  m1.andon_tripped |> should.equal(True)
  m1.andon_reason
  |> should.equal("Split-brain quorum loss detected in Ceph storage mesh")

  // Reset cord with clearance key
  let m2 = demo.update(m1, demo.ResetAndonCord)
  m2.andon_tripped |> should.equal(False)
  m2.andon_reason |> should.equal("")
}

pub fn storage_sentry_hardware_lock_test() {
  let m0 = demo.init()
  m0.os_drive_serial |> should.equal("25503L801736")
  m0.os_drive_locked |> should.equal(True)
}

pub fn lyapunov_energy_update_test() {
  let m0 = demo.init()
  let m1 = demo.update(m0, demo.UpdateLyapunov(0.085))
  m1.lyapunov_energy |> should.equal(0.085)
}

pub fn demo_view_render_test() {
  let m0 = demo.init()
  let _el = demo.view(m0)
  True |> should.equal(True)
}
