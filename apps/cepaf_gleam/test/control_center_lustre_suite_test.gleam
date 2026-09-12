//// [C3I-SIL6-MSTS] TEST SUITE
//// <c3i-test>
////   <target>cepaf_gleam/ui/lustre/control_center_lustre_suite</target>
////   <compliance>SC-GLM-UI-001, SC-HMI-010, SC-JIDOKA-001, SC-CHECKLIST-001</compliance>
//// </c3i-test>

import cepaf_gleam/ui/lustre/control_center_lustre_suite as suite
import gleeunit/should

pub fn lustre_suite_init_state_test() {
  let model = suite.init()
  model.active_page |> should.equal(suite.CockpitPage)
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

pub fn lustre_suite_page_navigation_test() {
  let m0 = suite.init()
  let m1 = suite.update(m0, suite.SelectPage(suite.PlanningPage))
  m1.active_page |> should.equal(suite.PlanningPage)

  let m2 = suite.update(m1, suite.SelectPage(suite.ChecklistPage))
  m2.active_page |> should.equal(suite.ChecklistPage)

  let m3 = suite.update(m2, suite.SelectPage(suite.TestingPage))
  m3.active_page |> should.equal(suite.TestingPage)

  let m4 = suite.update(m3, suite.SelectPage(suite.KnowledgePage))
  m4.active_page |> should.equal(suite.KnowledgePage)

  let m5 = suite.update(m4, suite.SelectPage(suite.LinkTrackerPage))
  m5.active_page |> should.equal(suite.LinkTrackerPage)
}

pub fn lustre_suite_spring_cover_lifecycle_test() {
  let m0 = suite.init()

  // 1. Actuation blocked while closed
  let m_blocked = suite.update(m0, suite.ConfirmSpringActuation)
  m_blocked.spring_cover_open |> should.equal(False)

  // 2. Flip open
  let m1 = suite.update(m0, suite.ToggleSpringCover)
  m1.spring_cover_open |> should.equal(True)
  m1.spring_armed |> should.equal(True)

  // 3. Actuate while open -> dispatches and snaps shut
  let m2 = suite.update(m1, suite.ConfirmSpringActuation)
  m2.spring_cover_open |> should.equal(False)
  m2.spring_armed |> should.equal(False)
}

pub fn lustre_suite_two_man_interlock_test() {
  let m0 = suite.init()

  // Turn Key A
  let m1 = suite.update(m0, suite.ToggleKeyA)
  m1.key_a_turned |> should.equal(True)
  m1.key_b_turned |> should.equal(False)

  // Turn Key B -> dual consensus closed
  let m2 = suite.update(m1, suite.ToggleKeyB)
  m2.key_a_turned |> should.equal(True)
  m2.key_b_turned |> should.equal(True)

  // Release Key B -> consensus broken
  let m3 = suite.update(m2, suite.ToggleKeyB)
  m3.key_a_turned |> should.equal(True)
  m3.key_b_turned |> should.equal(False)
}

pub fn lustre_suite_andon_jidoka_halt_test() {
  let m0 = suite.init()

  let m1 =
    suite.update(
      m0,
      suite.PullAndonCord(
        "Ceph OSD quorum desynchronization detected across mesh",
      ),
    )
  m1.andon_tripped |> should.equal(True)
  m1.andon_reason
  |> should.equal("Ceph OSD quorum desynchronization detected across mesh")

  let m2 = suite.update(m1, suite.ResetAndonCord)
  m2.andon_tripped |> should.equal(False)
  m2.andon_reason |> should.equal("")
}

pub fn lustre_suite_heijunka_claim_release_test() {
  let m0 = suite.init()
  let target_task = "Task-101: OODA Loop Convergence"

  let m1 = suite.update(m0, suite.ClaimHeijunkaTask(target_task))
  m1.worker_queue |> should.not_equal(m0.worker_queue)

  let m2 = suite.update(m1, suite.ReleaseHeijunkaTask("Worker-Active: " <> target_task))
  m2.active_worker_leases |> should.equal(m0.active_worker_leases)
}

pub fn lustre_suite_view_render_test() {
  let m0 = suite.init()
  let _el = suite.view(m0)
  True |> should.equal(True)
}
