// =============================================================================
// UI Report Quality Gate Regression Tests
// =============================================================================
// These tests guard against the specific failure where SVG diagrams contain
// useful text but the generated PNGs lose all readable information.
// STAMP: SC-UI-REPORT-QUALITY-002, SC-UI-REPORT-QUALITY-003,
//        SC-UI-REPORT-QUALITY-010, SC-UI-REPORT-QUALITY-020,
//        SC-UI-REPORT-QUALITY-021, SC-UI-REPORT-QUALITY-023,
//        SC-UI-REPORT-QUALITY-024, SC-UI-REPORT-QUALITY-025

import gleam/list
import gleam/string
import gleeunit/should
import simplifile

@external(erlang, "erlang", "byte_size")
fn byte_size(bits: BitArray) -> Int

const root = "/home/an/dev/ver/c3i"

const bundle = root <> "/docs/journal/task-20260524-ui-closure"

const gate_source = root
  <> "/lib/cepaf_gleam/src/cepaf_gleam/tools/ui_diagram_quality_gate.gleam"

const generator_source = root
  <> "/lib/cepaf_gleam/src/cepaf_gleam/tools/ui_task_closure_bundle.gleam"

type ContractTokenSet {
  ContractTokenSet(name: String, tokens: List(String))
}

pub fn gate_source_requires_render_parity_test() {
  let source = read_file(gate_source)

  contains(source, "validate_png_matches_svg")
  contains(source, "/usr/bin/magick")
  contains(source, "validate_png_pixel_match")
  contains(source, "font_renderer=magick")
  contains(source, "contrast_mode=high")
  contains(source, "fresh_render_match=true")
  contains(source, "png_stale_or_unmatched")
}

pub fn gate_source_requires_vector_text_and_evidence_refs_test() {
  let source = read_file(gate_source)

  contains(source, "vector_text_cells")
  contains(source, "unique_visible_terms")
  contains(source, "data-c3i-evidence-path")
  contains(source, "validate_expected_evidence_refs")
}

pub fn gate_source_requires_semantic_contextual_visual_scores_test() {
  let source = read_file(gate_source)

  contains(source, "semantic_transmission_score")
  contains(source, "contextual_correctness_score")
  contains(source, "visual_design_score")
  contains(source, "high_contrast_score")
  contains(source, "validate_svg_high_contrast_policy")
  contains(source, "rich_captions")
  contains(source, "hidden_svg_text_opacity")
}

pub fn generator_uses_full_opacity_high_contrast_diagram_text_test() {
  let source = read_file(generator_source)

  contains(source, "data-c3i-contrast=\\\"high\\\"")
  contains(source, "data-c3i-contrast-min-ratio=\\\"7.0\\\"")
  contains(source, "fill-opacity=\\\"1\\\"")
  contains(source, "#050814")
  contains(source, "#ffffff")
  contains(source, "#e2e8f0")
  contains(source, "#93c5fd")
}

pub fn gate_source_requires_cross_artifact_claim_contracts_test() {
  let source = read_file(gate_source)

  contains(source, "type ClaimContract")
  contains(source, "validate_claim_contracts")
  contains(source, "validate_manifest_claim_contracts")
  contains(source, "validate_no_stale_or_placeholder_content")
  contains(source, "Claim Contract Registry")
}

pub fn generator_emits_vector_text_fallback_test() {
  let source = read_file(generator_source)

  contains(source, "fn vector_text")
  contains(source, "vtext-cell")
  contains(source, "fn glyph_rows")
  contains(source, "data-c3i-evidence-anchor")
}

pub fn generator_emits_claim_evidence_risk_quality_captions_test() {
  let source = read_file(generator_source)

  contains(source, "fn visual_caption")
  contains(source, "diagram_claim")
  contains(source, "diagram_evidence")
  contains(source, "diagram_risk")
  contains(source, "diagram_takeaway")
  contains(source, "Architecture diagrams are hypotheses")
  contains(source, "fn email_claim_register")
  contains(source, "Per-diagram claim register")
}

pub fn generated_svgs_have_vector_text_cells_test() {
  diagram_names()
  |> list.each(fn(name) {
    let svg = read_file(bundle <> "/diagrams/" <> name <> ".svg")
    { count_occurrences(svg, "class=\"vtext-cell\"") >= 800 }
    |> should.equal(True)
  })
}

pub fn generated_pngs_have_system_font_render_density_test() {
  diagram_names()
  |> list.each(fn(name) {
    let bits = read_bits(bundle <> "/diagrams/" <> name <> ".png")
    { byte_size(bits) >= 100_000 } |> should.equal(True)
  })
}

pub fn generated_svgs_have_source_evidence_refs_test() {
  diagram_names()
  |> list.each(fn(name) {
    let svg = read_file(bundle <> "/diagrams/" <> name <> ".svg")
    { count_occurrences(svg, "data-c3i-evidence-path=") >= 3 }
    |> should.equal(True)
    { count_occurrences(svg, "data-c3i-evidence-anchor=") >= 3 }
    |> should.equal(True)
  })
}

pub fn generated_svgs_are_accessible_and_not_hidden_text_test() {
  diagram_names()
  |> list.each(fn(name) {
    let svg = read_file(bundle <> "/diagrams/" <> name <> ".svg")
    contains(svg, "role=\"img\"")
    contains(svg, "<title id=")
    contains(svg, "<desc id=")
    { string.contains(svg, "fill-opacity=\"0.01\"") } |> should.equal(False)
  })
}

pub fn deck_embeds_captioned_linked_png_figures_test() {
  let deck = read_file(bundle <> "/deck.html")

  count_occurrences(deck, "data:image/png;base64") |> should.equal(6)
  count_occurrences(deck, "<figure") |> should.equal(6)
  count_occurrences(deck, "<figcaption") |> should.equal(6)
  { count_occurrences(deck, "Takeaway:") >= 6 } |> should.equal(True)
  { count_occurrences(deck, "Claim:") >= 6 } |> should.equal(True)
  { count_occurrences(deck, "Evidence:") >= 6 } |> should.equal(True)
  { count_occurrences(deck, "Risk if wrong:") >= 6 } |> should.equal(True)
  { count_occurrences(deck, "Quality:") >= 6 } |> should.equal(True)
  count_occurrences(deck, ".svg\">SVG") |> should.equal(6)
  count_occurrences(deck, ".png\">PNG") |> should.equal(6)
}

pub fn quality_report_records_semantic_diagram_metrics_test() {
  let report = read_file(bundle <> "/diagram-quality-report.md")

  contains(report, "fresh_render_match=true")
  contains(report, "vector_cells=")
  contains(report, "unique_terms=")
  contains(report, "evidence_refs=")
  contains(report, "semantic_score=")
  contains(report, "contextual_score=")
  contains(report, "visual_design_score=")
  contains(report, "contrast_score=")
  contains(report, "font_renderer=magick")
  contains(report, "contrast_mode=high")
  contains(report, "quality report write | PASS")
}

pub fn generated_manifest_preserves_visual_claim_contract_test() {
  let manifest = read_file(bundle <> "/links.json")

  { count_occurrences(manifest, "\"reader_takeaway\"") >= 6 }
  |> should.equal(True)
  { count_occurrences(manifest, "\"claim\"") >= 6 } |> should.equal(True)
  { count_occurrences(manifest, "\"evidence\"") >= 6 } |> should.equal(True)
  { count_occurrences(manifest, "\"risk_if_wrong\"") >= 6 }
  |> should.equal(True)
  contains(manifest, "architecture-diagram reality validation")
}

pub fn generated_claim_contracts_are_cross_artifact_consistent_test() {
  let artifacts = [
    bundle <> "/journal.md",
    bundle <> "/index.html",
    bundle <> "/analysis.html",
    bundle <> "/deck.html",
    bundle <> "/email.md",
    bundle <> "/links.json",
  ]
  let tokens =
    contract_token_sets()
    |> list.map(fn(set) {
      let ContractTokenSet(_, set_tokens) = set
      set_tokens
    })
    |> list.flatten

  artifacts
  |> list.each(fn(path) {
    let text = normalize_artifact(read_file(path))
    tokens |> list.each(fn(token) { contains(text, token) })
  })
}

pub fn generated_svg_metadata_carries_own_claim_contract_test() {
  contract_token_sets()
  |> list.each(fn(set) {
    let ContractTokenSet(name, tokens) = set
    let svg =
      normalize_artifact(read_file(bundle <> "/diagrams/" <> name <> ".svg"))
    tokens |> list.each(fn(token) { contains(svg, token) })
  })
}

pub fn generated_email_contains_per_diagram_claim_register_test() {
  let email = read_file(bundle <> "/email.md")

  contains(email, "Per-diagram claim register")
  { count_occurrences(email, "Risk if wrong:") >= 6 } |> should.equal(True)
  { count_occurrences(email, "Evidence:") >= 6 } |> should.equal(True)
  { count_occurrences(email, "Claim:") >= 6 } |> should.equal(True)
}

pub fn generated_bundle_rejects_stale_or_placeholder_markers_test() {
  let artifacts = [
    bundle <> "/journal.md",
    bundle <> "/index.html",
    bundle <> "/analysis.html",
    bundle <> "/deck.html",
    bundle <> "/email.md",
    bundle <> "/links.json",
  ]
  let forbidden = [
    "9755 passed",
    "9762 passed",
    "9766 passed",
    "9772 passed",
    "Lorem ipsum",
    "TBD",
    "TODO",
    "fill-opacity=\"0.01\"",
    "image placeholder",
    "placeholder image",
    "no useful output",
    "visual slop",
  ]

  artifacts
  |> list.each(fn(path) {
    let text = read_file(path) |> stale_scan_text(path)
    forbidden
    |> list.each(fn(token) {
      string.contains(text, token) |> should.equal(False)
    })
  })
}

fn diagram_names() -> List(String) {
  [
    "01-closure-evidence",
    "02-dashboard-rendering",
    "03-control-plane",
    "04-fractal-clients",
    "05-no-dummy-guardrails",
    "06-code-organization",
  ]
}

fn contract_token_sets() -> List(ContractTokenSet) {
  [
    ContractTokenSet("01-closure-evidence", [
      "Closure Evidence",
      "Closure is evidence-backed only if every build, test, runtime, artifact, and delivery row remains true.",
      "the UI closure is supported by current build, test, runtime, artifact, and delivery evidence rather than by a decorative summary.",
      "sa-plan 0/0/3174, 173 UI Gleam files, 34302 UI LOC, gleam build clean, gleam test 9773 passed, Playwright 1269 passed, /dashboard 200, page-spec all 100%, shell runtime 200, and non-dummy 503/501/404 probes.",
      "operators may accept a closure bundle that omits failed checks, stale artifacts, or missing attachments.",
    ]),
    ContractTokenSet("02-dashboard-rendering", [
      "Dashboard Rendering Data Path",
      "The dashboard is assembled server-side first, then enhanced by a CSP-safe browser runtime.",
      "/dashboard is generated by Browser -> Mist/Wisp -> router.gleam -> page_views -> dashboard_views.gleam -> shell.gleam -> shell-runtime.bundled.js.",
      "source excerpts from router.gleam, dashboard_views.gleam, shell.gleam, page metadata, and live /dashboard plus AG-UI route probes.",
      "a future maintainer may debug the browser instead of the actual server-side route/view/runtime stage that produced the page.",
    ]),
    ContractTokenSet("03-control-plane", [
      "UI Control Plane",
      "The control plane treats unknown or not-wired data sources as explicit non-success states.",
      "startup, routing, auth, status mapping, hot reload, and observability form the UI control plane, and fake 200 statuses are blocked.",
      "route_internal, route_html, expectedApiStatus, /health, /api/v1/pages, AG-UI SSE, tmux/log controls, and no-dummy browser assertions.",
      "mutation routes, hot reload, or missing data sources may accidentally report success or lose operator observability.",
    ]),
    ContractTokenSet("04-fractal-clients", [
      "Fractal Layers and Clients",
      "The UI is a fractal client matrix, not only a browser page.",
      "the route catalog exposes L0-L7 layer metadata and Browser SSR, REST JSON, TUI ANSI, AG-UI, and A2UI client surfaces.",
      "/api/v1/pages metadata, the fractal observability matrix, dashboard L0-L7 rendering, and route/client parity notes.",
      "a routed page may appear complete for one client while failing AG-UI, A2UI, REST, TUI, or an L0-L7 layer obligation.",
    ]),
    ContractTokenSet("05-no-dummy-guardrails", [
      "No-Dummy Guardrails",
      "A non-200 status can be the correct result when the live source is intentionally not wired.",
      "known live-source gaps return 503 or 501 and unknown APIs return 404, so missing implementations cannot masquerade as success.",
      "Playwright expectedApiStatus checks, page-spec empty-array regression, and curl evidence for federation 503, health_grid 501, ai/chat 501, and /api/v1/does_not_exist 404.",
      "dummy code may return 200 and hide that federation or health-grid data is not actually wired.",
    ]),
    ContractTokenSet("06-code-organization", [
      "Touched Code Organization",
      "The touched files form a narrow route/runtime/test/report chain that can be reviewed stage by stage.",
      "the closure edits are scoped to the shell runtime, Wisp routing, dashboard rendering, browser tests, WebKit setup, and report generator/gate.",
      "ui/domain, ui/state, ui/wisp, ui/web, ui/lustre, ui/tui, ui/zenoh_otel, shell-runtime, source excerpts, and generated report/gate/spec files.",
      "reviewers may miss the real ownership boundaries and accidentally change unrelated runtime or test surfaces.",
    ]),
  ]
}

fn read_file(path: String) -> String {
  case simplifile.read(path) {
    Ok(text) -> text
    Error(e) -> {
      let msg = "cannot read " <> path <> ": " <> simplifile.describe_error(e)
      panic as msg
    }
  }
}

fn read_bits(path: String) -> BitArray {
  case simplifile.read_bits(from: path) {
    Ok(bits) -> bits
    Error(e) -> {
      let msg = "cannot read " <> path <> ": " <> simplifile.describe_error(e)
      panic as msg
    }
  }
}

fn count_occurrences(haystack: String, needle: String) -> Int {
  case needle == "" {
    True -> 0
    False -> list.length(string.split(haystack, needle)) - 1
  }
}

fn normalize_artifact(text: String) -> String {
  text
  |> string.replace("&amp;", "&")
  |> string.replace("&lt;", "<")
  |> string.replace("&gt;", ">")
  |> string.replace("&quot;", "\"")
  |> string.replace("&#39;", "'")
}

fn stale_scan_text(text: String, path: String) -> String {
  case string.contains(path, ".html") {
    True -> strip_embedded_png_data(text)
    False -> text
  }
}

fn strip_embedded_png_data(text: String) -> String {
  case string.split_once(text, "data:image/png;base64,") {
    Ok(#(before, after_marker)) ->
      case string.split_once(after_marker, "\"") {
        Ok(#(_encoded_png, after_quote)) ->
          before
          <> "data:image/png;base64,[embedded-png]\""
          <> strip_embedded_png_data(after_quote)
        Error(Nil) -> before <> "data:image/png;base64,[embedded-png]"
      }
    Error(Nil) -> text
  }
}

fn contains(haystack: String, needle: String) {
  string.contains(haystack, needle) |> should.equal(True)
}
