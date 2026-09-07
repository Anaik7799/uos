import gleam/list
import gleam/option.{Some}
import gleam/string
import gleeunit/should
import prng
import uos_swarm/cockpit.{Container}
import uos_swarm/swarm
import uos_tui/aspects
import uos_tui/event.{KeyPress}
import uos_tui/frame
import uos_tui/geometry.{Size}
import uos_tui/headless
import uos_tui/widget

fn model() -> cockpit.Model {
  let m = cockpit.init_model("2026-09-06T21:23:36Z", "kxqzrlmp")
  cockpit.Model(
    ..m,
    containers: [
      Container("db-prod", "T2", "running", 0.8),
      Container("obs-prod", "T3", "running", 1.2),
    ],
    lease_epoch: 7,
    // Full 18/18: this fixture stands in for a fully-evidenced system, so the
    // ComprehensiveChecklist aspect is genuinely Pass rather than merely structural.
    checklist_passed: [
      "CHK-01-TIME", "CHK-02-TAIL", "CHK-03-FRACT", "CHK-04-KM", "CHK-05-MUDA",
      "CHK-06-GRAPH", "CHK-07-DRIVE", "CHK-08-C1C8", "CHK-09-MATH",
      "CHK-10-9MOD", "CHK-11-REGR", "CHK-12-GLEAM", "CHK-13-HERMES",
      "CHK-14-ZIGVM", "CHK-15-MAX", "CHK-16-OTEL", "CHK-17-SOV", "CHK-18-JJ",
    ],
  )
}

fn keys(s: String) -> List(event.Event) {
  event.parse_keys(s) |> list.map(KeyPress)
}

fn deps() -> List(String) {
  ["gleam_stdlib", "gleam_erlang", "gleam_otp", "gleam_json", "argv"]
}

// BDD: Given the cockpit at 120x40, When rendered, Then the status bar shows FQDN, UTC, mode, drive lock and jj change.
pub fn status_bar_fields_test() {
  let t =
    headless.run(cockpit.app(model()), Size(120, 40), [])
    |> headless.last_frame
    |> frame.to_text
  string.contains(t, aspects.tailnet_fqdn) |> should.be_true
  string.contains(t, "2026-09-06T21:23:36Z") |> should.be_true
  string.contains(t, "DARK") |> should.be_true
  string.contains(t, aspects.os_nvme_serial <> " LOCKED") |> should.be_true
  string.contains(t, "kxqzrlmp") |> should.be_true
}

// BDD: When the operator presses 2, Then the Supervisors tab shows the uos_sup tree.
pub fn tab_switch_shows_supervisor_tree_test() {
  let run = headless.run(cockpit.app(model()), Size(120, 40), keys("2"))
  run.state.model.tab |> should.equal(1)
  headless.last_frame(run)
  |> frame.to_text
  |> string.contains("▾ uos_sup")
  |> should.be_true
}

// BDD: When the operator requests a restart, Then a confirm screen appears and nothing is emitted yet.
pub fn restart_requires_confirmation_test() {
  let run = headless.run(cockpit.app(model()), Size(120, 40), keys("3r"))
  run.state.screen_stack |> should.equal(["confirm", "cockpit"])
  run.state.model.intents |> should.equal([])
  headless.last_frame(run)
  |> frame.to_text
  |> string.contains("Action interlock (C8)")
  |> should.be_true
}

// BDD: When confirmed, Then exactly one Intent is emitted, the screen pops, and the log records the policy hand-off.
pub fn confirm_emits_intent_and_pops_test() {
  let run = headless.run(cockpit.app(model()), Size(120, 40), keys("3r\r"))
  run.state.screen_stack |> should.equal(["cockpit"])
  run.state.model.intents
  |> should.equal([cockpit.Intent("restart", "db-prod", 7)])
  run.state.model.containers
  |> list.map(fn(c) { c.status })
  |> should.equal(["running", "running"])
  headless.last_frame(run)
  |> frame.to_text
  |> string.contains("intent restart db-prod -> policy")
  |> should.be_true
}

// BDD: When cancelled via Tab to the Cancel button, Then no intent is emitted.
pub fn cancel_emits_nothing_test() {
  let run = headless.run(cockpit.app(model()), Size(120, 40), keys("3x\t\r"))
  run.state.model.intents |> should.equal([])
  run.state.screen_stack |> should.equal(["cockpit"])
}

pub fn mode_cycles_all_five_test() {
  let modes =
    prng.range(1, 5)
    |> list.map(fn(n) {
      headless.run(
        cockpit.app(model()),
        Size(120, 40),
        keys(string.repeat("m", n)),
      ).state.model.mode
    })
  modes
  |> should.equal([
    cockpit.Dim,
    cockpit.Normal,
    cockpit.Bright,
    cockpit.Emergency,
    cockpit.Dark,
  ])
}

pub fn command_palette_logs_command_test() {
  // Tab order: nav, tabs, checklist, sa-plan table, command (containers table only exists on tab 3)
  let run =
    headless.run(cockpit.app(model()), Size(120, 40), keys("\t\t\t\tdoctor\r"))
  run.state.focus |> should.equal(Some("command"))
  list.last(run.state.model.log) |> should.equal(Ok("cmd> doctor"))
}

pub fn quit_binding_test() {
  headless.run(cockpit.app(model()), Size(120, 40), keys("q")).state.quit
  |> should.be_true
}

pub fn checklist_toggle_from_keyboard_test() {
  let run = headless.run(cockpit.app(model()), Size(120, 40), keys("\t\t2"))
  run.state.focus |> should.equal(Some("checklist"))
  run.state.model.expanded |> should.equal([1])
}

pub fn cockpit_passes_all_seventeen_aspects_test() {
  let m = model()
  let findings =
    aspects.audit(
      cockpit.view(m),
      cockpit.context(m, Size(120, 40), True, deps()),
    )
  list.length(findings) |> should.equal(17)
  aspects.failed(findings) |> should.equal(0)
  // No Fail anywhere, but 5 aspects are still only Declared (dictionary/config bindings, not
  // fresh observed behaviour), so the softer FAIL-only gate is true while strict two-key
  // admission is honestly false.
  aspects.no_failures(findings) |> should.be_true
  aspects.admissible(findings) |> should.be_false
  aspects.passed(findings) |> should.equal(12)
  aspects.declared(findings) |> should.equal(5)
}

pub fn cockpit_mounts_at_least_eight_catalog_families_test() {
  cockpit.view(model())
  |> widget.flatten
  |> list.map(widget.kind_of)
  |> list.unique
  |> list.length
  |> fn(n) { n >= 8 }
  |> should.be_true
}

// Chaos: random key soup never crashes the cockpit and every frame is well-formed.
pub fn chaos_random_keys_test() {
  list.each(prng.seeds(60), fn(seed) {
    let #(txt, seed) = prng.text(seed, 30)
    let #(w, seed) = prng.int_between(seed, 0, 160)
    let #(h, _) = prng.int_between(seed, 0, 50)
    let run = headless.run(cockpit.app(model()), Size(w, h), keys(txt))
    list.all(run.frames, frame.is_well_formed) |> should.be_true
  })
}

// Scalability: 5,000 containers still render a well-formed frame.
pub fn scalability_large_table_test() {
  let many =
    prng.range(1, 5000)
    |> list.map(fn(i) {
      Container("c" <> string.inspect(i), "T1", "running", 0.1)
    })
  let m = cockpit.Model(..model(), containers: many, container_cursor: 4999)
  let run = headless.run(cockpit.app(m), Size(120, 40), keys("3"))
  headless.last_frame(run) |> frame.is_well_formed |> should.be_true
  headless.last_frame(run)
  |> frame.to_text
  |> string.contains("c5000")
  |> should.be_true
}

pub fn swarm_tab_inherits_cockpit_chrome_and_passes_all_aspects_test() {
  let m =
    cockpit.Model(..model(), tab: 8, ledger: option.Some(swarm.sample_ledger()))
  let findings =
    aspects.audit(
      cockpit.view(m),
      cockpit.context(m, Size(120, 40), True, deps()),
    )
  aspects.failed(findings) |> should.equal(0)
  headless.run(cockpit.app(m), Size(120, 40), keys("9"))
  |> headless.last_frame
  |> frame.to_text
  |> string.contains("Swarm")
  |> should.be_true
}
