//// apps/cepaf_gleam/test/multi_surface_verifier_test.gleam
//// Pure Gleam 30-Usecase Multi-Surface Runtime & Acceptance Verifier
//// STAMP: SC-GLM-UI-001, SC-INTENT-ATLAS-001, SC-DENOTATIONAL-INTENT-001, SC-CHECKLIST-001

import gleeunit/should
import gleam/list
import cepaf_gleam/intent/denotational.{
  Intent, bottom, evaluate, initial_state, state_leq
}
import cepaf_gleam/semantics/sheaf_cohomology.{
  transition_morphism, cech_coboundary, verify_h1_vanishing, glue_global_section
}
import cepaf_gleam/intent/parser.{default_baseline, normalize_config}
import cepaf_gleam/intent/config.{
  type ContainerIntent, type IntentConfig, ContainerIntent, IntentConfig,
}
import cepaf_gleam/intent/validator
import cepaf_gleam/testing/tui_test_engine.{
  all_canonical_screens, all_subsystem_views,
  render_screen_buffer, render_subsystem_view_buffer, render_split_screen_buffer,
  verify_frame_buffer
}
import cepaf_gleam/testing/webui_test_engine.{
  all_web_tabs, evaluate_c1_c8, evaluate_checklist_accordion
}
import cepaf_gleam/deployment/orchestrator.{
  run_deployment_preflight, run_full_deployment_cycle
}

pub fn usecase_01_to_07_algebraic_atlas_sheaf_test() {
  // USECASE-01..03: Morphism Identity, Inversion, and Cocycle Law across 10 charts
  let indices = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
  let val = 42.0

  // 1. Identity law: phi_ii(x) = x
  let id_ok =
    list.all(indices, fn(i) {
      transition_morphism(i, i, val) == val
    })
  should.be_true(id_ok)

  // 2. Inversion law: phi_ji(phi_ij(x)) = x
  let inv_ok =
    list.all(indices, fn(i) {
      list.all(indices, fn(j) {
        let forward = transition_morphism(i, j, val)
        let reverse = transition_morphism(j, i, forward)
        let diff = reverse -. val
        let abs_diff = case diff <. 0.0 { True -> 0.0 -. diff False -> diff }
        abs_diff <. 0.0001
      })
    })
  should.be_true(inv_ok)

  // 3. Cocycle law: phi_jk(phi_ij(x)) = phi_ik(x)
  let cocycle_ok =
    list.all(indices, fn(i) {
      list.all(indices, fn(j) {
        list.all(indices, fn(k) {
          let defect = cech_coboundary(i, j, k, val)
          defect <. 0.0001
        })
      })
    })
  should.be_true(cocycle_ok)

  // 4. Sheaf Cohomology H^1 = 0
  case verify_h1_vanishing(10, 100.0) {
    Ok(max_defect) -> should.be_true(max_defect <. 0.0001)
    Error(_) -> should.fail()
  }

  // 5. Sheaf Gluing H^0
  let sections = list.map(indices, fn(i) { #(i, transition_morphism(0, i, 55.5)) })
  case glue_global_section(sections) {
    Ok(recon) -> {
      let diff = recon -. 55.5
      let abs_diff = case diff <. 0.0 { True -> 0.0 -. diff False -> diff }
      should.be_true(abs_diff <. 0.0001)
    }
    Error(_) -> should.fail()
  }
}

pub fn usecase_08_to_13_denotational_intent_test() {
  let s0 = initial_state()

  // 8. Valid intent valuation
  let valid_i = Intent(
    authority: "sa-plan",
    target_drive_serial: "SECONDARY_NVME",
    criticality: "DAL-C",
    guardian_approved: False,
    delta_coord: 0.5,
    add_containers: ["c3i-vector-cache"],
    add_topics: ["indrajaal/l5/cog/**"],
  )
  let s1 = evaluate(valid_i, s0)
  s1.is_bottom |> should.be_false
  s1.version |> should.equal(2)

  // 9. Unauthorized authority fails closed
  let unauth_i = Intent(..valid_i, authority: "unauthorized")
  let s_unauth = evaluate(unauth_i, s0)
  s_unauth.is_bottom |> should.be_true

  // 10. Root OS NVMe fails closed
  let root_i = Intent(..valid_i, target_drive_serial: "25503L801736")
  let s_root = evaluate(root_i, s0)
  s_root.is_bottom |> should.be_true

  // 11. DAL-A without approval fails closed
  let dala_i = Intent(..valid_i, criticality: "DAL-A", guardian_approved: False)
  let s_dala = evaluate(dala_i, s0)
  s_dala.is_bottom |> should.be_true

  // 12. Bottom absorption
  let res_bot = evaluate(valid_i, bottom("STALE"))
  res_bot.is_bottom |> should.be_true

  // 13. Monotonic partial order
  state_leq(s0, s1) |> should.be_true
  state_leq(s1, s0) |> should.be_false
}

pub fn usecase_14_to_17_poka_yoke_validator_test() {
  let baseline = default_baseline()
  normalize_config(baseline).authority |> should.equal("sa-plan")

  let val_cfg = IntentConfig(
    version: "1.0.0",
    name: "baseline-test",
    authority: "sa-plan",
    target_drive_serial: "SAMSUNG_SECONDARY",
    prajna_health_threshold: 0.85,
    topology_nodes: ["nas-1.tail55d152.ts.net"],
    containers: [
      ContainerIntent("app-1", "app:v1", 4100, True),
      ContainerIntent("broker", "zenoh:latest", 7447, True),
    ],
    zenoh_topics: ["indrajaal/l0/const/**", "uos/test/**"],
  )
  validator.validate_intent_config(val_cfg) |> should.be_ok()

  // Failure 1: bad auth
  let bad_auth = IntentConfig(..val_cfg, authority: "invalid")
  validator.validate_intent_config(bad_auth) |> should.be_error()

  // Failure 2: root nvme
  let bad_nvme = IntentConfig(..val_cfg, target_drive_serial: "25503L801736")
  validator.validate_intent_config(bad_nvme) |> should.be_error()

  // Failure 3: priv port
  let bad_port = IntentConfig(..val_cfg, containers: [ContainerIntent("bad", "bad", 0, True)])
  validator.validate_intent_config(bad_port) |> should.be_error()
}

pub fn usecase_18_to_26_system_tui_clusters_and_views_test() {
  // 18..21: All 32 canonical screens in Clusters A..D
  let screens = all_canonical_screens()
  list.length(screens) |> should.equal(32)
  let screens_pass =
    list.all(screens, fn(s) {
      let fb = render_screen_buffer(s)
      case verify_frame_buffer(fb) {
        Ok(len) -> len >= 50
        Error(_) -> False
      }
    })
  should.be_true(screens_pass)

  // 22..25: All 12 specialized subsystem views
  let views = all_subsystem_views()
  list.length(views) |> should.equal(12)
  let views_pass =
    list.all(views, fn(v) {
      let fb = render_subsystem_view_buffer(v)
      case verify_frame_buffer(fb) {
        Ok(len) -> len >= 30
        Error(_) -> False
      }
    })
  should.be_true(views_pass)

  // 26: Split-screen dual-pane view
  let split_fb = render_split_screen_buffer()
  case verify_frame_buffer(split_fb) {
    Ok(len) -> should.be_true(len >= 100)
    Error(_) -> should.fail()
  }
}

pub fn usecase_27_to_30_webui_and_deployment_orchestrator_test() {
  // 27: WebUI 15 canonical tabs satisfy C1-C8 Gold Standard
  let tabs = all_web_tabs()
  list.length(tabs) |> should.equal(15)
  let c1_c8_ok =
    list.all(tabs, fn(t) {
      let score = evaluate_c1_c8(t)
      score.total_passed == 8
    })
  should.be_true(c1_c8_ok)

  // 28: WebUI universal 18-point checklist accordion
  let checklist_ok =
    list.all(tabs, fn(t) {
      case evaluate_checklist_accordion(t) {
        Ok(count) -> count == 18
        Error(_) -> False
      }
    })
  should.be_true(checklist_ok)

  // 29: Deployment preflight
  case run_deployment_preflight() {
    Ok(_) -> should.be_true(True)
    Error(_) -> should.fail()
  }

  // 30: Full deployment cycle report
  case run_full_deployment_cycle() {
    Ok(report) -> {
      report.preflight_passed |> should.be_true
      report.tui_screens_tested |> should.equal(32)
      report.tui_views_tested |> should.equal(12)
      report.webui_tabs_tested |> should.equal(15)
      report.checklist_passed |> should.be_true
    }
    Error(_) -> should.fail()
  }
}
