//// Terminal ANSI & Plain TUI Dashboard for UOS-CORE-EVO Zero-Muda Core
//// Development, 5-Caste Holonic Hive, 8 Integrated Bionic Services &
//// 10-Layer OTP 29 FPP Actor Digital Twin Mesh.
//// STAMP: SC-GLM-UI-001, SC-HARNESS-MCP-001, SC-JIDOKA-001, SC-PROVENANCE-001

import cepaf_gleam/ecology/core_effect_fence
import cepaf_gleam/ecology/core_evolution
import cepaf_gleam/ui/wisp/core_evo_api.{
  type CoreEvoBenefit, type CoreEvoCasteRecord, type CoreEvoServiceRecord,
}
import gleam/int
import gleam/list
import gleam/string

pub fn render() -> String {
  render_dashboard(True)
}

pub fn render_plain() -> String {
  render_dashboard(False)
}

fn render_dashboard(use_ansi: Bool) -> String {
  let benefits = core_evo_api.get_benefits()
  let castes = core_evo_api.get_castes()
  let services = core_evo_api.get_bionic_services()
  let modules = core_evo_api.get_modules()
  let commands = core_evo_api.get_commands()
  let target_count = list.length(core_effect_fence.canonical_14_targets)

  let c_cyan = ansi(use_ansi, "\u{001b}[1;36m")
  let c_green = ansi(use_ansi, "\u{001b}[1;32m")
  let c_yellow = ansi(use_ansi, "\u{001b}[1;33m")
  let c_dim = ansi(use_ansi, "\u{001b}[90m")
  let c_reset = ansi(use_ansi, "\u{001b}[0m")

  let header =
    c_cyan
    <> "▌ UOS-CORE-EVO Zero-Muda Holonic Hive, Bionic Services & OTP 29 Cockpit"
    <> c_reset
    <> "  Runtime: "
    <> c_green
    <> "OTP 29.0.5 (ERTS 17.0.5)"
    <> c_reset
    <> " | Status: "
    <> c_yellow
    <> "candidate_under_review"
    <> c_reset

  let metrics =
    "  MCP Overhead: -82.9% (10->1 uos-gleam) | AGY Share: 1.01% (<2%) | Margin: "
    <> int.to_string(core_evolution.mandatory_margin_bps)
    <> " bps (40.0%, <="
    <> int.to_string(core_evolution.hard_ceiling_bps)
    <> " bps & $6/$10 OR)"

  let sim_line =
    "  Holons: 170 (10x17) x 24 Epochs = 4080 States (12/12 Invariants) | Intelligent FPP Actors: 40/40 (4 Domains x L0..L9) | OI07 Targets: "
    <> int.to_string(target_count)
    <> " (0 mixed readers) | Modules: "
    <> int.to_string(list.length(modules))
    <> " | Commands: "
    <> int.to_string(list.length(commands))

  let benefit_header =
    c_dim
    <> "  ID      Dimension                             Quantitative Delta"
    <> c_reset

  let benefit_rows =
    benefits
    |> list.map(render_benefit_row)
    |> string.join("\n")

  let caste_header =
    c_dim
    <> "  Caste     Role                                  Share                WIP  MCP Slice"
    <> c_reset

  let caste_rows =
    castes
    |> list.map(render_caste_row)
    |> string.join("\n")

  let service_header =
    c_dim
    <> "  Svc  Layer    Bionic & Systems Engineering Service"
    <> c_reset

  let service_rows =
    services
    |> list.map(render_service_row)
    |> string.join("\n")

  let provenance =
    c_yellow
    <> "  Provenance: EV-"
    <> int.to_string(core_evolution.admitted_ev_ceiling)
    <> " ceiling (EV-94..109 NOT_ADMITTED) | system_admitted=false | Cockpit: http://nas-1.tail55d152.ts.net:4100/core-evo"
    <> c_reset

  let boundaries =
    c_dim
    <> "  Boundaries: Gleam/OTP sole authority (SC-HARNESS-MCP-001), Signed Zenoh uos/v1/** (c3i/** fenced), Root NVMe [REDACTED_SYSTEM_OS_SERIAL], Jujutsu .jj/"
    <> c_reset

  string.join(
    [
      header,
      metrics,
      sim_line,
      "",
      benefit_header,
      benefit_rows,
      "",
      caste_header,
      caste_rows,
      "",
      service_header,
      service_rows,
      "",
      provenance,
      boundaries,
    ],
    "\n",
  )
}

fn render_benefit_row(b: CoreEvoBenefit) -> String {
  "  • "
  <> pad_right(sanitize_terminal_text(b.id), 7)
  <> " "
  <> pad_right(sanitize_terminal_text(b.dimension), 37)
  <> " "
  <> sanitize_terminal_text(b.quantitative_delta)
}

fn render_caste_row(c: CoreEvoCasteRecord) -> String {
  "  ◆ "
  <> pad_right(sanitize_terminal_text(c.caste_id), 9)
  <> " "
  <> pad_right(sanitize_terminal_text(c.role_name), 37)
  <> " "
  <> pad_right(sanitize_terminal_text(c.token_share), 20)
  <> " "
  <> pad_right(int.to_string(c.heijunka_wip_limit), 4)
  <> " "
  <> sanitize_terminal_text(c.mcp_slice)
}

fn render_service_row(s: CoreEvoServiceRecord) -> String {
  "  ● "
  <> pad_right(sanitize_terminal_text(s.id), 4)
  <> " "
  <> pad_right(sanitize_terminal_text(s.layer), 8)
  <> " "
  <> sanitize_terminal_text(s.name)
}

/// Strip ESC (\u{001b}), all C0 ASCII control characters (0x00..0x1f — replacing
/// \t, \n, \r with a single ASCII space 0x20 and dropping all others), DEL (0x7f),
/// and 8-bit C1 control characters (0x80..0x9f including CSI \u{009b} and OSC
/// \u{009d}) so untrusted strings retain zero C0/DEL/C1 control bytes.
pub fn sanitize_terminal_text(input: String) -> String {
  let assert Ok(space_cp) = string.utf_codepoint(32)
  input
  |> string.to_utf_codepoints
  |> list.filter_map(fn(cp) {
    let code = string.utf_codepoint_to_int(cp)
    case code == 9 || code == 10 || code == 13 {
      True -> Ok(space_cp)
      False ->
        case code >= 32 && code != 127 && { code < 128 || code > 159 } {
          True -> Ok(cp)
          False -> Error(Nil)
        }
    }
  })
  |> string.from_utf_codepoints
}

fn ansi(enabled: Bool, seq: String) -> String {
  case enabled {
    True -> seq
    False -> ""
  }
}

fn pad_right(value: String, width: Int) -> String {
  let length = string.length(value)
  case length >= width {
    True -> value
    False -> value <> string.repeat(" ", width - length)
  }
}
