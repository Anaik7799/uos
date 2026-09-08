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
import gleam/float
import gleam/int
import gleam/list
import gleam/string

pub fn render(state: HomeostasisSystemState) -> String {
  let header =
    visuals.with_color(
      "  CYBERNETIC HOMEOSTASIS & 4-PARTY QUORUM EVOLUTION (L0/L2/L5)",
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
      "AUTONOMOUS EVOLUTION ACTIVE [Gen " <> int.to_string(g) <> ": " <> cycle <> "]",
      "cyan",
    )
    InstabilityIntervention(reason) -> #(
      "ANDON HALT: " <> reason,
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
      <> c.name
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
      "    AGY Sovereign:         ONLINE (Formal/Lean 4 Proofs)",
      "    Claude Sovereign:      ONLINE (Holistic Architecture & Coordinator)",
      "    Codex Sovereign:       ONLINE (Solo5 Sandboxing & Verification)",
      "    OpenRouter Sovereign:  ONLINE (Bounded Cognitive Advisory)",
      "",
      "  5-Agent Sovereign Workspace & Artifact Allocation Matrix (Herdr Mesh):",
      "    ● uos · 1 (agy):        Master Single File (20260908-0113-...md) & Formal Proofs",
      "    ● uos · 2 (claude):     Lustre Web HUD (homeostasis_evolution_hud.gleam) & SSE Generator",
      "    ○ uos · 3 (codex):      Wisp Router (router.gleam) & F Prime Engine (homeostasis_fprime.gleam)",
      "    ○ uos · 4 (codex):      SSE Test Suite (agui_sse_api_test.gleam) & HUD Test Suite",
      "    ○ uos · 5 (openrouter): Evolutionary Engine & Pareto Fitness & Sa-Plan Ledger Authority",
    ],
    "\n",
  )
}
