//// [C3I-SIL6-MSTS] MODULE CONTRACT
//// <c3i-module>
////   <identity><module>cepaf_gleam/ui/tui/integrity_view</module></identity>
////   <fractal-topology><layer>L0_CONSTITUTIONAL</layer></fractal-topology>
////   <compliance><stamp-controls>SC-GLM-UI-001, SC-VER-074</stamp-controls></compliance>
//// </c3i-module>

import cepaf_gleam/cockpit/visuals
import cepaf_gleam/ui/lustre/integrity.{type IntegrityModel, type PsiCheck}
import gleam/list
import gleam/option.{None, Some}
import gleam/string

pub fn render(model: IntegrityModel) -> String {
  let header = visuals.with_color("  INTEGRITY (L0 Constitutional)", "cyan")
  let body = case model.loading {
    True -> "  Loading verification state..."
    False ->
      case model.error {
        Some(e) -> "  " <> visuals.with_color("ERROR: " <> e, "red")
        None -> render_state(model)
      }
  }
  string.join([header, body], "\n")
}

fn render_state(model: IntegrityModel) -> String {
  let hash_line =
    "  Constitution: "
    <> visuals.with_color(
      case model.constitution_hash {
        "" -> "not loaded"
        h -> h
      },
      "white",
    )
  let chain_line = case model.chain_valid {
    True -> "  Hash Chain:   " <> visuals.with_color("VALID", "green")
    False -> "  Hash Chain:   " <> visuals.with_color("BROKEN", "red")
  }
  let verified_line = "  Last Check:   " <> model.last_verified
  let psi_header = "  Psi Invariants:"
  let psi_table =
    visuals.render_table(
      ["Invariant", "Status", "Detail"],
      list.map(model.psi_results, fn(c) {
        [
          c.name,
          case c.passed {
            True -> "PASS"
            False -> "FAIL"
          },
          c.detail,
        ]
      }),
      [16, 6, 30],
    )
  let psi_rows =
    model.psi_results
    |> list.map(render_psi_check)
    |> string.join("\n")
  let overall = case integrity.all_psi_passed(model) {
    True -> "  Overall:      " <> visuals.with_color("ALL PASS", "green")
    False ->
      "  Overall:      " <> visuals.with_color("VIOLATION DETECTED", "red")
  }
  string.join(
    [
      hash_line,
      chain_line,
      verified_line,
      "",
      psi_header,
      psi_table,
      psi_rows,
      "",
      overall,
    ],
    "\n",
  )
}

fn render_psi_check(check: PsiCheck) -> String {
  let icon = case check.passed {
    True -> visuals.with_color("[PASS]", "green")
    False -> visuals.with_color("[FAIL]", "red")
  }
  "    " <> icon <> " " <> check.name <> " — " <> check.detail
}
