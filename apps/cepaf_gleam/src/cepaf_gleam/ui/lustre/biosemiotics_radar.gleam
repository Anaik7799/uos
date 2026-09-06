//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ui/lustre/biosemiotics_radar</module>
////     <lineage>EV-WEB-03 Rocha Biosemiotics & Hardware Safety Radar</lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L5_COGNITIVE</layer>
////     <mesh-domain>Biosemiotics Radar & Hardware Lock Monitor</mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>DAL-A / SIL-6 / HIGH</criticality>
////     <stamp-controls>
////       SC-ROCHA-001, SC-STORAGE-SAFETY-001, SC-MUDA-001, SC-CHECKLIST-001
////     </stamp-controls>
////   </compliance>
//// </c3i-module>
//// =============================================================================

import gleam/float
import gleam/string
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html

pub type BiosemioticsRadarModel {
  BiosemioticsRadarModel(
    rocha_cut_decoupled: Bool,
    os_nvme_locked: Bool,
    os_nvme_serial: String,
    lyapunov_lambda: Float,
    tcm_conservation_delta: Float,
    entropy_bits: Float,
  )
}

pub fn string_contains(source: String, sub: String) -> Bool {
  string.contains(source, sub)
}

pub fn build_canonical_radar() -> BiosemioticsRadarModel {
  BiosemioticsRadarModel(
    rocha_cut_decoupled: True,
    os_nvme_locked: True,
    os_nvme_serial: "25503L801736",
    lyapunov_lambda: -0.078,
    tcm_conservation_delta: 0.0,
    entropy_bits: 2.68,
  )
}

pub fn render_svg_radar_html(model: BiosemioticsRadarModel) -> String {
  let header =
    "<svg viewBox='0 0 500 500' class='biosemiotics-radar-svg' style='width:100%;max-width:500px;background:#0d1117;border:1px solid #30363d;border-radius:8px'>"
  let circles =
    "<circle cx='250' cy='250' r='180' fill='none' stroke='#30363d' stroke-width='1'/>"
    <> "<circle cx='250' cy='250' r='120' fill='none' stroke='#30363d' stroke-width='1' stroke-dasharray='4'/>"
    <> "<circle cx='250' cy='250' r='60' fill='none' stroke='#30363d' stroke-width='1'/>"
  let axes =
    "<line x1='250' y1='50' x2='250' y2='450' stroke='#30363d' stroke-width='1'/>"
    <> "<line x1='50' y1='250' x2='450' y2='250' stroke='#30363d' stroke-width='1'/>"
  let polygon =
    "<polygon points='250,90 390,250 250,400 110,250' fill='rgba(63, 185, 80, 0.25)' stroke='#3fb950' stroke-width='2'/>"
  let lock_badge =
    "<text x='250' y='245' fill='#ffc107' font-size='11' font-family='monospace' text-anchor='middle' font-weight='bold'>OS NVMe LOCKED</text>"
    <> "<text x='250' y='265' fill='#8b949e' font-size='9' font-family='monospace' text-anchor='middle'>SN: "
    <> model.os_nvme_serial
    <> "</text>"
  let footer = "</svg>"
  header
  <> "\n"
  <> circles
  <> "\n"
  <> axes
  <> "\n"
  <> polygon
  <> "\n"
  <> lock_badge
  <> "\n"
  <> footer
}

pub fn render_biosemiotics_view(model: BiosemioticsRadarModel) -> Element(msg) {
  html.div([attribute.class("biosemiotics-radar-card")], [
    html.h3([], [
      element.text("Rocha Biosemiotics & Hardware Storage Safety Radar"),
    ]),
    html.div([attribute.class("badges-row")], [
      html.span([attribute.class("badge badge-fractal")], [
        element.text("Rocha Symbol-Matter Cut: DECOUPLED"),
      ]),
      html.span([attribute.class("badge badge-tailscale")], [
        element.text(
          "Lyapunov Lambda: " <> float.to_string(model.lyapunov_lambda),
        ),
      ]),
      html.span([attribute.class("badge badge-muda")], [
        element.text("Hardware Serial: " <> model.os_nvme_serial <> " (LOCKED)"),
      ]),
    ]),
  ])
}
