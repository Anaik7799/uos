//// [C3I-SIL6-MSTS] MODULE CONTRACT
//// <c3i-module>
////   <identity><module>cepaf_gleam/ui/tui/bicameral_view</module></identity>
////   <fractal-topology><layer>L0_CONSTITUTIONAL</layer></fractal-topology>
////   <compliance><stamp-controls>SC-GLM-UI-001, SC-CONSENSUS-001, SC-SIL4-006</stamp-controls></compliance>
//// </c3i-module>

import cepaf_gleam/cockpit/visuals
import cepaf_gleam/ui/lustre/bicameral.{type BicameralModel, type Chamber}
import gleam/int
import gleam/option.{None, Some}
import gleam/string

pub fn render(model: BicameralModel) -> String {
  let header = visuals.with_color("  BICAMERAL (L0 Constitutional)", "cyan")
  let body = case model.loading {
    True -> "  Loading consensus state..."
    False ->
      case model.error {
        Some(e) -> "  " <> visuals.with_color("ERROR: " <> e, "red")
        None -> render_state(model)
      }
  }
  string.join([header, body], "\n")
}

fn render_state(model: BicameralModel) -> String {
  let consensus_line = case model.consensus_reached {
    True -> "  Consensus: " <> visuals.with_color("2oo3 REACHED", "green")
    False -> "  Consensus: " <> visuals.with_color("PENDING", "yellow")
  }
  let stats_line =
    "  Decisions: "
    <> int.to_string(model.total_decisions)
    <> " | Vetoes: "
    <> int.to_string(model.total_vetoes)
  let chambers_header = "  Chambers (2oo3 Voting):"
  let g = render_chamber(model.guardian)
  let s = render_chamber(model.sentinel)
  let c = render_chamber(model.cortex)
  string.join([consensus_line, stats_line, "", chambers_header, g, s, c], "\n")
}

fn render_chamber(ch: Chamber) -> String {
  let vote_color = vote_to_color(ch.vote)
  "    "
  <> visuals.with_color(ch.name, "white")
  <> ": "
  <> visuals.with_color(ch.vote, vote_color)
  <> " (vetoes: "
  <> int.to_string(ch.veto_count)
  <> ")"
  <> case ch.timestamp {
    "" -> ""
    ts -> " @ " <> ts
  }
}

fn vote_to_color(vote: String) -> String {
  case vote {
    "approve" -> "green"
    "reject" | "veto" -> "red"
    "pending" -> "yellow"
    _ -> "white"
  }
}
