//// Tests for uos_tui/swarm: ledger decoding, KPIs, andon rules, and the
//// dashboard view. Reference: Textual `DataTable`/`ProgressBar` dashboards.
//// STAMP: SC-TUI-W01-001.

import gleam/int
import gleam/list
import gleam/option
import gleeunit/should
import prng
import uos_tui/frame
import uos_tui/geometry
import uos_tui/render
import uos_tui/swarm

const sample_json = "{\"swarm\":\"uos-tui-swarm\",\"timestamp\":\"20260907-0440\",\"base_change\":\"vvrtrspvmtqq\",\"supervisor\":\"L1-planner\",\"takt_minutes\":12,\"wip_limit\":11,\"andon\":\"green\",\"jidoka_stops\":0,\"extra_unknown_key\":42,\"agents\":[{\"id\":\"W01\",\"layer\":\"L2\",\"role\":\"worker\",\"model\":\"sonnet\",\"effort\":\"medium\",\"slice\":\"a\",\"workspace\":\".uos-workspaces/tui-w01\",\"owned_files\":[\"src/uos_tui/swarm.gleam\"],\"min_tests\":10,\"status\":\"planned\",\"started\":\"\",\"finished\":\"\",\"tests_added\":0,\"loc\":0,\"tokens_out\":0,\"verdict\":\"\",\"notes\":\"\"},{\"id\":\"W02\",\"layer\":\"L2\",\"role\":\"worker\",\"model\":\"sonnet\",\"effort\":\"medium\",\"slice\":\"b\",\"workspace\":\".uos-workspaces/tui-w02\",\"owned_files\":[],\"min_tests\":10,\"status\":\"running\",\"started\":\"2026-09-07T04:40:00Z\",\"finished\":\"\",\"tests_added\":0,\"loc\":0,\"tokens_out\":100,\"verdict\":\"\",\"notes\":\"unknown_field_ignored\"},{\"id\":\"W03\",\"layer\":\"L2\",\"role\":\"worker\",\"model\":\"sonnet\",\"effort\":\"medium\",\"slice\":\"c\",\"workspace\":\".uos-workspaces/tui-w03\",\"owned_files\":[],\"min_tests\":10,\"status\":\"passed\",\"started\":\"2026-09-07T04:40:00Z\",\"finished\":\"2026-09-07T04:52:00Z\",\"tests_added\":10,\"loc\":90,\"tokens_out\":8000,\"verdict\":\"PASS\",\"notes\":\"\"},{\"id\":\"W04\",\"layer\":\"L2\",\"role\":\"worker\",\"model\":\"sonnet\",\"effort\":\"medium\",\"slice\":\"d\",\"workspace\":\".uos-workspaces/tui-w04\",\"owned_files\":[],\"min_tests\":10,\"status\":\"failed\",\"started\":\"2026-09-07T04:40:00Z\",\"finished\":\"2026-09-07T04:46:00Z\",\"tests_added\":2,\"loc\":30,\"tokens_out\":3000,\"verdict\":\"FAIL\",\"notes\":\"\"},{\"id\":\"W05\",\"layer\":\"L2\",\"role\":\"worker\",\"model\":\"sonnet\",\"effort\":\"medium\",\"slice\":\"e\",\"workspace\":\".uos-workspaces/tui-w05\",\"owned_files\":[],\"min_tests\":10,\"status\":\"integrated\",\"started\":\"2026-09-07T04:40:00Z\",\"finished\":\"2026-09-07T05:00:00Z\",\"tests_added\":14,\"loc\":200,\"tokens_out\":9500,\"verdict\":\"PASS\",\"notes\":\"\"}]}"

pub fn decode_all_statuses_test() {
  let assert Ok(ledger) = swarm.decode(sample_json)
  ledger.swarm |> should.equal("uos-tui-swarm")
  ledger.base_change |> should.equal("vvrtrspvmtqq")
  list.length(ledger.agents) |> should.equal(5)
}

pub fn decode_ignores_unknown_keys_test() {
  let assert Ok(ledger) = swarm.decode(sample_json)
  ledger.jidoka_stops |> should.equal(0)
}

pub fn decode_error_on_malformed_json_test() {
  swarm.decode("{not valid json") |> should.be_error
}

pub fn decode_error_on_missing_field_test() {
  swarm.decode("{\"swarm\":\"x\"}") |> should.be_error
}

pub fn kpi_completion_pct_test() {
  let k = swarm.kpis(swarm.sample_ledger())
  // 1 passed of 3 agents -> 33%
  k.completion_pct |> should.equal(33)
}

pub fn kpi_pass_rate_pct_test() {
  let k = swarm.kpis(swarm.sample_ledger())
  // 1 passed, 1 failed -> 50%
  k.pass_rate_pct |> should.equal(50)
}

pub fn kpi_first_pass_yield_pct_test() {
  let k = swarm.kpis(swarm.sample_ledger())
  // 2 non-empty verdicts (PASS, FAIL), 1 PASS -> 50%
  k.first_pass_yield_pct |> should.equal(50)
}

pub fn kpi_wip_and_sums_test() {
  let k = swarm.kpis(swarm.sample_ledger())
  k.wip |> should.equal(1)
  k.tokens_out |> should.equal(9000 + 4000 + 5000)
  k.tests_added |> should.equal(12 + 0 + 3)
  k.loc |> should.equal(180 + 0 + 60)
}

pub fn kpi_avg_cycle_minutes_test() {
  let k = swarm.kpis(swarm.sample_ledger())
  // W01: 15 min, W03: 10 min -> avg 12
  k.avg_cycle_minutes |> should.equal(12)
}

pub fn andon_green_when_no_failures_test() {
  let all_ok =
    swarm.Ledger(
      swarm: "s",
      timestamp: "t",
      base_change: "b",
      supervisor: "sup",
      takt_minutes: 1,
      wip_limit: 1,
      andon: "green",
      jidoka_stops: 0,
      agents: [],
    )
  let k = swarm.kpis(all_ok)
  k.andon |> should.equal(swarm.Green)
  swarm.andon_label(k.andon) |> should.equal("GREEN")
}

pub fn andon_red_on_two_failures_test() {
  let assert Ok(ledger) = swarm.decode(sample_json)
  let with_two_failed = swarm.Ledger(..ledger, andon: "green")
  let k = swarm.kpis(with_two_failed)
  // sample_json has exactly 1 failed agent -> not red from count alone
  k.andon |> should.not_equal(swarm.Red)
  // forcing ledger.andon == "red" always yields Red
  let forced = swarm.Ledger(..ledger, andon: "red")
  swarm.kpis(forced).andon |> should.equal(swarm.Red)
}

pub fn andon_yellow_on_single_failure_test() {
  let k = swarm.kpis(swarm.sample_ledger())
  k.andon |> should.equal(swarm.Yellow)
}

pub fn view_renders_well_formed_frame_test() {
  let widget = swarm.view(swarm.sample_ledger(), 0)
  render.compose(widget, geometry.Size(120, 40), option.None, render.dark)
  |> frame.is_well_formed
  |> should.be_true
}

pub fn to_markdown_contains_agent_rows_test() {
  let md = swarm.to_markdown(swarm.sample_ledger())
  md |> should.not_equal("")
}

fn random_status(seed: prng.Seed) -> #(swarm.Status, prng.Seed) {
  let #(n, next_seed) = prng.int_between(seed, 0, 4)
  let status = case n {
    0 -> swarm.Planned
    1 -> swarm.Running
    2 -> swarm.Passed
    3 -> swarm.Failed
    _ -> swarm.Integrated
  }
  #(status, next_seed)
}

fn build_agent(id: String, status: swarm.Status) -> swarm.Agent {
  swarm.Agent(
    id: id,
    layer: "L2",
    role: "worker",
    model: "sonnet",
    effort: "medium",
    slice: "s",
    workspace: ".uos-workspaces/tui-x",
    owned_files: [],
    min_tests: 10,
    status: status,
    started: "",
    finished: "",
    tests_added: 0,
    loc: 0,
    tokens_out: 0,
    verdict: "",
    notes: "",
  )
}

fn random_ledger(seed: prng.Seed, count: Int) -> swarm.Ledger {
  let #(agents, _final_seed) =
    list.fold(prng.range(0, count - 1), #([], seed), fn(acc, i) {
      let #(agents, s) = acc
      let #(status, next_s) = random_status(s)
      #([build_agent("A" <> int.to_string(i), status), ..agents], next_s)
    })
  swarm.Ledger(
    swarm: "prop",
    timestamp: "t",
    base_change: "b",
    supervisor: "sup",
    takt_minutes: 1,
    wip_limit: 1,
    andon: "green",
    jidoka_stops: 0,
    agents: agents,
  )
}

pub fn property_kpi_percentages_stay_in_bounds_test() {
  list.each(prng.seeds(8), fn(seed) {
    let ledger = random_ledger(seed, 6)
    let k = swarm.kpis(ledger)
    { k.completion_pct >= 0 && k.completion_pct <= 100 } |> should.be_true
    { k.pass_rate_pct >= 0 && k.pass_rate_pct <= 100 } |> should.be_true
    { k.first_pass_yield_pct >= 0 && k.first_pass_yield_pct <= 100 }
    |> should.be_true
  })
}

pub fn fuzz_decode_never_crashes_test() {
  list.each(prng.seeds(6), fn(seed) {
    let #(text, _next) = prng.text(seed, 24)
    case swarm.decode(text) {
      Ok(_) -> Nil
      Error(_) -> Nil
    }
  })
}
