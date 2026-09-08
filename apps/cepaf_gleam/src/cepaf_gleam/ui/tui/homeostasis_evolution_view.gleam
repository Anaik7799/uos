//// [C3I-SIL6-MSTS] MODULE CONTRACT
//// <c3i-module>
////   <identity><module>cepaf_gleam/ui/tui/homeostasis_evolution_view</module></identity>
////   <fractal-topology><layer>L0_CONSTITUTIONAL</layer><layer>L2_COMPONENT</layer><layer>L5_COGNITIVE</layer></fractal-topology>
////   <compliance><stamp-controls>SC-GLM-UI-001, SC-MATH-003, SC-HOM-001</stamp-controls></compliance>
//// </c3i-module>

import cepaf_gleam/cockpit/visuals
import cepaf_gleam/ha/homeostasis_evolution_engine.{
  type HomeostasisMetrics, type HomeostasisPhase, type HomeostasisSystemState,
  AutonomousEvolutionActive, Converging, HomeostaticEquilibrium,
  InstabilityIntervention,
}
import cepaf_gleam/ha/pareto_fitness_evaluator.{type CandidateEvaluation}
import cepaf_gleam/ha/physiological_homeostasis.{
  type PhysiologicalState,
  stress_to_string, trend_to_string, variable_to_string,
}
import cepaf_gleam/ui/homeostasis_status as status
import cepaf_gleam/ui/homeostasis_data as data
import gleam/result
import gleam/option.{None, Some}
import gleam/float
import gleam/io
import gleam/int
import gleam/list
import gleam/string

/// Reachable one-shot, plain-text entrypoint. Full-screen input ownership belongs
/// to the UOS TUI host; this view never changes terminal modes or executes effects.
@external(erlang, "cepaf_gleam_ffi", "get_arguments")
fn arguments() -> List(String)

pub fn main() -> Nil {
  let args = arguments()
  let mode = list.first(args) |> result.unwrap("real")
  let scenario = list.first(list.drop(args,1)) |> result.unwrap("nominal")
  let cycle = list.first(list.drop(args,2)) |> result.unwrap("1")
  case data.parse([#("mode",mode),#("scenario",scenario),#("cycle",cycle)]) {
    Error(reason) -> io.println("INVALID: " <> reason)
    Ok(selection) -> {
      let #(snapshot,now) = data.read(selection)
      render_snapshot(snapshot,now,120,100) |> io.println()
    }
  }
}

pub fn render(state: HomeostasisSystemState) -> String {
  let header =
    visuals.with_color(
      "  SIMULATED / CYBERNETIC HOMEOSTASIS & 4-PARTY QUORUM EVOLUTION (L0/L2/L5)",
      "cyan",
    )
  let status_line = render_phase(state.phase, state.generation)
  let metrics_section = render_metrics(state.metrics)
  let phys_section = render_physiological(state.physiological)
  let pareto_section = render_pareto(state.pareto_candidates)
  let quorum_section = render_quorum()

  string.join(
    [
      header,
      status_line,
      "",
      metrics_section,
      "",
      phys_section,
      "",
      pareto_section,
      "",
      quorum_section,
    ],
    "\n",
  )
}

fn render_phase(phase: HomeostasisPhase, gen: Int) -> String {
  let #(badge, color) = case phase {
    Converging(err, _) -> #(
      "CONVERGING (error: " <> float.to_string(err) <> ")",
      "yellow",
    )
    HomeostaticEquilibrium(cycles, err) -> #(
      "HOMEOSTATIC EQUILIBRIUM (" <> int.to_string(cycles) <> " cycles, e=" <> float.to_string(err) <> ")",
      "green",
    )
    AutonomousEvolutionActive(cycle, g) -> #(
      "AUTONOMOUS EVOLUTION ACTIVE [Gen " <> int.to_string(g) <> ": " <> safe_text(cycle) <> "]",
      "cyan",
    )
    InstabilityIntervention(reason) -> #(
      "ANDON HALT: " <> safe_text(reason),
      "red",
    )
  }
  "  Phase:       "
  <> visuals.with_color(badge, color)
  <> " | Generation: "
  <> int.to_string(gen)
}

fn render_metrics(m: HomeostasisMetrics) -> String {
  let status = case m.stable {
    True -> visuals.with_color("STABLE", "green")
    False -> visuals.with_color("CONVERGING", "yellow")
  }
  string.join(
    [
      "  Convergence PID & Lyapunov:",
      "    State:       " <> status,
      "    Health:      " <> float.to_string(m.measured_health),
      "    Error e(t):  " <> float.to_string(m.error),
      "    Control:     " <> float.to_string(m.control_output),
      "    Lyapunov V:  " <> float.to_string(m.lyapunov_v),
    ],
    "\n",
  )
}

fn render_physiological(p: PhysiologicalState) -> String {
  let eq_label = case p.is_homeostatic {
    True -> visuals.with_color("NOMINAL (<=0.70)", "green")
    False -> visuals.with_color("CRITICAL", "red")
  }
  let header =
    "  C3I Physiological Variables (Composite: "
    <> float.to_string(p.composite_stress)
    <> " | Trend: "
    <> trend_to_string(p.stress_trend)
    <> " | "
    <> eq_label
    <> "):"

  let var_lines =
    list.map(p.variables, fn(v) {
      let stress_col = case v.stress {
        physiological_homeostasis.StressLow -> "green"
        physiological_homeostasis.StressOptimal -> "green"
        physiological_homeostasis.StressHigh -> "yellow"
        physiological_homeostasis.StressCritical -> "red"
      }
      "    "
      <> variable_to_string(v.variable)
      <> ": Setpoint="
      <> float.to_string(v.setpoint)
      <> " Actual="
      <> float.to_string(v.measurement)
      <> " Stress="
      <> visuals.with_color(stress_to_string(v.stress), stress_col)
    })

  string.join([header, ..var_lines], "\n")
}

fn render_pareto(candidates: List(CandidateEvaluation)) -> String {
  let header = "  Indrajaal Multi-Objective Evolutionary Pareto Landscape:"
  let candidate_lines =
    list.map(candidates, fn(c) {
      let opt_badge = case c.is_pareto_optimal {
        True -> visuals.with_color("[NON-DOMINATED PARETO FRONT]", "green")
        False -> visuals.with_color("[Dominated]", "yellow")
      }
      "    * "
      <> safe_text(c.name)
      <> " (Fitness: "
      <> float.to_string(c.composite_fitness)
      <> ") "
      <> opt_badge
    })

  string.join([header, ..candidate_lines], "\n")
}

fn render_quorum() -> String {
  string.join(
    [
      "  4-Party Sovereign Quorum Consensus (3-of-4 Supermajority):",
      "    AGY Sovereign:         UNKNOWN (Formal/Lean 4 Proofs)",
      "    Claude Sovereign:      UNKNOWN (Holistic Architecture & Coordinator)",
      "    Codex Sovereign:       UNKNOWN (Solo5 Sandboxing & Verification)",
      "    OpenRouter Sovereign:  UNKNOWN (Bounded Cognitive Advisory)",
      "",
      "  Historical artifact allocation (current owners/presence UNKNOWN):",
      "    uos · 1 (agy):        Master Single File (20260908-0113-...md) & Formal Proofs",
      "    uos · 2 (claude):     Lustre Web HUD (homeostasis_evolution_hud.gleam) & SSE Generator",
      "    uos · 3 (codex):      Wisp Router (router.gleam) & F Prime Engine (homeostasis_fprime.gleam)",
      "    uos · 4 (codex):      SSE Test Suite (agui_sse_api_test.gleam) & HUD Test Suite",
      "    uos · 5 (openrouter): Evolutionary Engine & Pareto Fitness & Sa-Plan Ledger Authority",
    ],
    "\n",
  )
}

/// ASCII fallback for narrow terminals, pipes, NO_COLOR and TERM=dumb.
/// Only printable ASCII reaches this boundary; no OSC, CSI, C1 or bidi controls.
pub fn safe_text(value: String) -> String {
  value
  |> string.to_utf_codepoints()
  |> list.map(fn(cp) {
    let n = string.utf_codepoint_to_int(cp)
    case n >= 32 && n <= 126 {
      True -> string.from_utf_codepoints([cp])
      False -> "?"
    }
  })
  |> string.concat()
}

/// Same evidence projection as GUI and HTTP; dimensions are hard output bounds.
/// No cursor movement or terminal mode changes are performed by this renderer.
pub fn render_snapshot(
  snapshot: status.Snapshot,
  now_us: Int,
  columns: Int,
  rows: Int,
) -> String {
  let state_label = status.status(snapshot, now_us) |> status.label()
  let origin = status.source(snapshot) |> safe_text()
  let time = case status.observed_at(snapshot) {
    Some(at) -> int.to_string(at)
    None -> "UNKNOWN"
  }
  let width = int.clamp(columns, 0, 240)
  let lines = list.flatten([[
    "HOMEOSTASIS | " <> state_label,
    "Source: " <> origin,
    "Source UTC us: " <> time,
  ], list.map(status.fields(snapshot,now_us),fn(f) { safe_text(f.1 <> ": " <> f.2) }), [
    "Peer presence: UNKNOWN",
    "Control authority: NONE",
    "Verification: UNRUN / candidate receipts required",
    "http://nas-1.tail55d152.ts.net:4100/homeostasis/evolution",
  ]])
  case width == 0 {
    True -> ""
    False ->
      lines
      |> list.take(int.clamp(rows, 0, 100))
      |> list.map(fn(line) { string.slice(line, 0, width) })
      |> string.join("\n")
  }
}
