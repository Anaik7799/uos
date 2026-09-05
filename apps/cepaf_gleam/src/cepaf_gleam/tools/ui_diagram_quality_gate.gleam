//// Quality gate for C3I UI closure report bundles.
//// This intentionally validates more than "file exists":
//// - SVGs must contain diagram structure, not only text bullets.
//// - PNGs must be rendered at the expected dimensions and byte size.
//// - HTML reports must embed all six generated PNGs.
//// - Journal, analysis, deck, manifest, email, and companion docs must carry
////   the required evidence, local references, and no-dummy status semantics.
//// - Each diagram must transmit a claim, carry source-backed context, and meet
////   measurable visual-design quality thresholds.
//// - Rules, skills, agents, hooks, and STAMP registry mirrors must exist.
//// Run from lib/cepaf_gleam with:
////   gleam run -m cepaf_gleam/tools/ui_diagram_quality_gate
//// Optional:
////   C3I_UI_REPORT_DIR=/abs/path/to/docs/journal/<bundle>

import cepaf_gleam/substrate/file_system
import envoy
import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/list
import gleam/string
import simplifile

@external(erlang, "erlang", "byte_size")
fn byte_size(bits: BitArray) -> Int

@external(erlang, "erlang", "halt")
fn halt(code: Int) -> Nil

const root = "/home/an/dev/ver/c3i"

const default_dir = root <> "/docs/journal/task-20260524-ui-closure"

fn bundle_dir() -> String {
  case envoy.get("C3I_UI_REPORT_DIR") {
    Ok(value) -> {
      let trimmed = string.trim(value)
      case trimmed == "" {
        True -> default_dir
        False -> trimmed
      }
    }
    Error(Nil) -> default_dir
  }
}

fn diagram_dir() -> String {
  bundle_dir() <> "/diagrams"
}

pub type Check {
  Check(
    name: String,
    min_svg_bytes: Int,
    min_png_bytes: Int,
    min_rects: Int,
    min_lines: Int,
    min_arrows: Int,
    min_texts: Int,
    max_circles: Int,
    min_vector_cells: Int,
    min_unique_terms: Int,
    min_numeric_claims: Int,
    min_status_claims: Int,
    min_semantic_score: Int,
    min_contextual_score: Int,
    min_visual_design_score: Int,
    required_tokens: List(String),
  )
}

pub type EvidenceRef {
  EvidenceRef(path: String, anchor: String)
}

type ClaimContract {
  ClaimContract(
    name: String,
    title: String,
    takeaway: String,
    claim: String,
    evidence: String,
    risk: String,
    source_tokens: List(String),
  )
}

type ReportAspectContract {
  ReportAspectContract(
    name: String,
    decision_value: String,
    evidence: String,
    guardrail: String,
  )
}

pub type ResultLine {
  ResultLine(name: String, status: String, detail: String)
}

type LaneResult {
  LaneResult(index: Int, results: List(ResultLine))
}

pub fn main() {
  let all_results = run_parallel_checks()
  let report = report_markdown(all_results)

  let write_results = case
    simplifile.write(to: report_path(), contents: report)
  {
    Ok(Nil) -> [ResultLine("quality report write", "PASS", report_path())]
    Error(e) -> [
      ResultLine(
        "quality report write",
        "FAIL",
        report_path() <> ": " <> simplifile.describe_error(e),
      ),
    ]
  }

  let final_results = list.append(all_results, write_results)
  let write_succeeded = case write_results {
    [ResultLine(_, "PASS", _)] -> True
    _ -> False
  }

  let final_write_failures = case write_succeeded {
    True -> {
      let final_report = report_markdown(final_results)
      case simplifile.write(to: report_path(), contents: final_report) {
        Ok(Nil) -> []
        Error(e) -> [
          ResultLine(
            "quality report write finalization",
            "FAIL",
            report_path() <> ": " <> simplifile.describe_error(e),
          ),
        ]
      }
    }
    False -> []
  }

  let failures =
    list.append(final_results, final_write_failures)
    |> list.filter(fn(r) { r.status != "PASS" })

  case failures {
    [] -> {
      io.println("ui report quality gate PASS")
      io.println(report_path())
    }
    _ -> {
      io.println("ui report quality gate FAIL")
      failures
      |> list.each(fn(r) { io.println("- " <> r.name <> ": " <> r.detail) })
      io.println(report_path())
      halt(1)
    }
  }
}

fn run_parallel_checks() -> List(ResultLine) {
  let subject = process.new_subject()
  let checks = expected_checks()
  let diagram_count = list.length(checks)

  checks
  |> list.index_map(fn(c, index) {
    let lane_index = index + 1
    process.spawn_unlinked(fn() {
      process.send(subject, LaneResult(lane_index, [validate_diagram(c)]))
    })
  })

  let _ =
    process.spawn_unlinked(fn() {
      process.send(
        subject,
        LaneResult(diagram_count + 1, validate_html_embeddings()),
      )
    })

  let _ =
    process.spawn_unlinked(fn() {
      process.send(
        subject,
        LaneResult(diagram_count + 2, validate_content_files()),
      )
    })

  let _ =
    process.spawn_unlinked(fn() {
      process.send(
        subject,
        LaneResult(diagram_count + 3, validate_integrity_files()),
      )
    })

  let _ =
    process.spawn_unlinked(fn() {
      process.send(
        subject,
        LaneResult(diagram_count + 4, validate_deep_evidence()),
      )
    })

  let _ =
    process.spawn_unlinked(fn() {
      process.send(
        subject,
        LaneResult(diagram_count + 5, [validate_governance_surfaces()]),
      )
    })

  collect_lane_results(subject, diagram_count + 5, [])
}

fn collect_lane_results(
  subject: process.Subject(LaneResult),
  remaining: Int,
  acc: List(LaneResult),
) -> List(ResultLine) {
  case remaining <= 0 {
    True -> flatten_lane_results(acc)
    False ->
      case process.receive(from: subject, within: 120_000) {
        Ok(lane) -> collect_lane_results(subject, remaining - 1, [lane, ..acc])
        Error(Nil) ->
          list.append(flatten_lane_results(acc), [
            ResultLine(
              "parallel quality gate",
              "FAIL",
              "timed out waiting for "
                <> int.to_string(remaining)
                <> " report-check lanes",
            ),
          ])
      }
  }
}

fn flatten_lane_results(lanes: List(LaneResult)) -> List(ResultLine) {
  lanes
  |> list.sort(by: compare_lane)
  |> list.map(fn(lane) { lane.results })
  |> list.flatten
}

fn compare_lane(a: LaneResult, b: LaneResult) {
  int.compare(a.index, b.index)
}

fn expected_checks() -> List(Check) {
  [
    Check(
      "01-closure-evidence",
      6500,
      100_000,
      15,
      9,
      9,
      34,
      2,
      800,
      35,
      4,
      3,
      80,
      80,
      75,
      [
        "Evidence chain",
        "Published outputs",
        "Closure decision",
        "Residual known gaps",
      ],
    ),
    Check(
      "02-dashboard-rendering",
      6500,
      100_000,
      18,
      10,
      10,
      36,
      2,
      800,
      30,
      3,
      2,
      78,
      80,
      75,
      [
        "HTTP page generation path",
        "Data sources and browser runtime",
        "Parallel dynamic surfaces",
        "/ag-ui/events",
      ],
    ),
    Check(
      "03-control-plane",
      6500,
      100_000,
      16,
      9,
      9,
      36,
      2,
      800,
      30,
      3,
      2,
      78,
      80,
      75,
      [
        "Startup and serving authority",
        "Route outcome branches",
        "Observability control points",
        "dummy 200 path blocked",
      ],
    ),
    Check(
      "04-fractal-clients",
      6500,
      100_000,
      48,
      0,
      0,
      58,
      2,
      800,
      30,
      2,
      0,
      75,
      75,
      70,
      [
        "Fractal route metadata matrix",
        "L0 constitutional",
        "L7 federation",
        "Browser SSR",
        "A2UI",
      ],
    ),
    Check(
      "05-no-dummy-guardrails",
      6500,
      100_000,
      14,
      6,
      5,
      36,
      2,
      800,
      30,
      3,
      3,
      80,
      80,
      75,
      [
        "API truth decision tree",
        "Return 501/503",
        "blocked: fake 200",
        "/api/v1/health_grid",
      ],
    ),
    Check(
      "06-code-organization",
      6500,
      100_000,
      16,
      6,
      6,
      40,
      2,
      800,
      30,
      1,
      0,
      75,
      75,
      70,
      [
        "Touched file responsibilities",
        "Build and browser runtime",
        "Server-side page assembly",
        "Verification and publication",
      ],
    ),
  ]
}

fn validate_diagram(c: Check) -> ResultLine {
  let diagrams = diagram_dir()
  let svg_path = diagrams <> "/" <> c.name <> ".svg"
  let png_path = diagrams <> "/" <> c.name <> ".png"

  case simplifile.read(svg_path) {
    Error(e) ->
      ResultLine(
        c.name,
        "FAIL",
        "cannot read SVG: " <> simplifile.describe_error(e),
      )
    Ok(svg) -> {
      let svg_failures = validate_svg(c, svg)
      let png_failures = validate_png(c, svg_path, png_path)
      let failures = list.append(svg_failures, png_failures)

      case failures {
        [] -> ResultLine(c.name, "PASS", diagram_pass_detail(svg, png_path))
        _ -> ResultLine(c.name, "FAIL", string.join(failures, "; "))
      }
    }
  }
}

fn diagram_pass_detail(svg: String, png_path: String) -> String {
  let text_nodes = extract_text_nodes(svg)
  let visible_text = string.join(text_nodes, " ")
  let png_bytes = case simplifile.read_bits(from: png_path) {
    Ok(bits) -> byte_size(bits)
    Error(_) -> 0
  }

  "svg_bytes="
  <> int.to_string(string.length(svg))
  <> " text_nodes="
  <> int.to_string(list.length(text_nodes))
  <> " vector_cells="
  <> int.to_string(count_occurrences(svg, "class=\"vtext-cell\""))
  <> " unique_terms="
  <> int.to_string(list.length(unique_terms(visible_text)))
  <> " numeric_claims="
  <> int.to_string(count_numeric_claims(visible_text))
  <> " status_claims="
  <> int.to_string(count_status_claims(visible_text))
  <> " evidence_refs="
  <> int.to_string(count_occurrences(svg, "data-c3i-evidence-path="))
  <> " semantic_score="
  <> int.to_string(semantic_transmission_score(svg, visible_text))
  <> " contextual_score="
  <> int.to_string(contextual_correctness_score(svg, visible_text))
  <> " visual_design_score="
  <> int.to_string(visual_design_score(svg))
  <> " contrast_score="
  <> int.to_string(high_contrast_score(svg))
  <> " png_bytes="
  <> int.to_string(png_bytes)
  <> " font_renderer=magick contrast_mode=high fresh_render_match=true png="
  <> png_path
}

fn validate_svg(c: Check, svg: String) -> List(String) {
  let text_nodes = extract_text_nodes(svg)
  let visible_text = string.join(text_nodes, " ")
  []
  |> require_at_least("svg_bytes", string.length(svg), c.min_svg_bytes)
  |> require_at_least("rects", count_occurrences(svg, "<rect "), c.min_rects)
  |> require_at_least("lines", count_occurrences(svg, "<line "), c.min_lines)
  |> require_at_least(
    "arrows",
    count_occurrences(svg, "marker-end"),
    c.min_arrows,
  )
  |> require_at_least("texts", count_occurrences(svg, "<text "), c.min_texts)
  |> require_at_most(
    "circles",
    count_occurrences(svg, "<circle"),
    c.max_circles,
  )
  |> require_at_most(
    "hidden_svg_text_opacity",
    count_occurrences(svg, "fill-opacity=\"0.01\""),
    0,
  )
  |> require_at_least(
    "vector_text_cells",
    count_occurrences(svg, "class=\"vtext-cell\""),
    c.min_vector_cells,
  )
  |> require_at_least("visible_text_chars", string.length(visible_text), 700)
  |> require_at_least(
    "unique_visible_terms",
    list.length(unique_terms(visible_text)),
    c.min_unique_terms,
  )
  |> require_at_least(
    "numeric_claims",
    count_numeric_claims(visible_text),
    c.min_numeric_claims,
  )
  |> require_at_least(
    "status_claims",
    count_status_claims(visible_text),
    c.min_status_claims,
  )
  |> require_at_least(
    "evidence_refs",
    count_occurrences(svg, "data-c3i-evidence-path="),
    3,
  )
  |> require_at_least(
    "semantic_transmission_score",
    semantic_transmission_score(svg, visible_text),
    c.min_semantic_score,
  )
  |> require_at_least(
    "contextual_correctness_score",
    contextual_correctness_score(svg, visible_text),
    c.min_contextual_score,
  )
  |> require_at_least(
    "visual_design_score",
    visual_design_score(svg),
    c.min_visual_design_score,
  )
  |> require_at_least("high_contrast_score", high_contrast_score(svg), 90)
  |> require_tokens(svg, ["role=\"img\"", "<title id=", "<desc id="])
  |> require_tokens(visible_text, c.required_tokens)
  |> append_failures(validate_expected_evidence_refs(c.name, svg))
}

fn validate_png(c: Check, svg_path: String, path: String) -> List(String) {
  case simplifile.read_bits(from: path) {
    Error(e) -> ["cannot read PNG: " <> simplifile.describe_error(e)]
    Ok(bits) -> {
      let size = byte_size(bits)
      let size_failures =
        []
        |> require_at_least("png_bytes", size, c.min_png_bytes)

      let dim_failures = case png_dimensions(bits) {
        Ok(#(1600, 980)) -> []
        Ok(#(w, h)) -> [
          "png_dimensions expected=1600x980 actual="
          <> int.to_string(w)
          <> "x"
          <> int.to_string(h),
        ]
        Error(e) -> ["png_header " <> e]
      }

      let parity_failures = validate_png_matches_svg(c, svg_path, path, bits)

      list.append(size_failures, dim_failures)
      |> append_failures(parity_failures)
    }
  }
}

fn validate_png_matches_svg(
  c: Check,
  svg_path: String,
  png_path: String,
  committed_bits: BitArray,
) -> List(String) {
  let temp_dir = "/tmp/c3i-ui-diagram-gate"
  let temp_png = temp_dir <> "/" <> c.name <> ".png"

  case simplifile.create_directory_all(temp_dir) {
    Error(e) -> [
      "cannot create temp render dir: " <> simplifile.describe_error(e),
    ]
    Ok(Nil) ->
      case render_png_with_system_font(svg_path, temp_png) {
        Error(e) -> ["fresh system-font SVG render failed: " <> e]
        Ok(_) ->
          case simplifile.read_bits(from: temp_png) {
            Error(e) -> [
              "cannot read fresh render: " <> simplifile.describe_error(e),
            ]
            Ok(fresh_bits) -> {
              let committed_size = byte_size(committed_bits)
              let fresh_size = byte_size(fresh_bits)
              let dim_failures = case png_dimensions(fresh_bits) {
                Ok(#(1600, 980)) -> []
                Ok(#(w, h)) -> [
                  "fresh_render_dimensions expected=1600x980 actual="
                  <> int.to_string(w)
                  <> "x"
                  <> int.to_string(h),
                ]
                Error(e) -> ["fresh_render_header " <> e]
              }

              let match_failures =
                validate_png_pixel_match(
                  png_path,
                  temp_png,
                  committed_size,
                  fresh_size,
                )

              list.append(dim_failures, match_failures)
            }
          }
      }
  }
}

fn render_png_with_system_font(
  svg_path: String,
  png_path: String,
) -> Result(String, String) {
  let _ = simplifile.write(to: png_path, contents: "")
  let command = "/usr/bin/magick " <> svg_path <> " " <> png_path

  case file_system.run_cmd(command) {
    Error(e) -> Error(e)
    Ok(output) -> {
      case simplifile.read_bits(from: png_path) {
        Error(e) -> Error("png unreadable: " <> simplifile.describe_error(e))
        Ok(bits) -> {
          let size = byte_size(bits)
          case size >= 100_000 {
            True -> Ok(output)
            False ->
              Error(
                "system font renderer produced weak png bytes="
                <> int.to_string(size),
              )
          }
        }
      }
    }
  }
}

fn validate_png_pixel_match(
  committed_png: String,
  fresh_png: String,
  committed_size: Int,
  fresh_size: Int,
) -> List(String) {
  let command =
    "/usr/bin/magick compare -metric AE "
    <> committed_png
    <> " "
    <> fresh_png
    <> " null: 2>&1"

  case file_system.run_cmd(command) {
    Error(e) -> ["png_pixel_compare_failed " <> e]
    Ok(output) -> {
      let metric = string.trim(output)
      case string.starts_with(metric, "0") {
        True -> []
        False -> [
          "png_stale_or_unmatched ae="
          <> metric
          <> " fresh_bytes="
          <> int.to_string(fresh_size)
          <> " committed_bytes="
          <> int.to_string(committed_size)
          <> " path="
          <> committed_png,
        ]
      }
    }
  }
}

fn png_dimensions(bits: BitArray) -> Result(#(Int, Int), String) {
  case bits {
    <<
      137:8,
      80:8,
      78:8,
      71:8,
      13:8,
      10:8,
      26:8,
      10:8,
      _len:32,
      73:8,
      72:8,
      68:8,
      82:8,
      width:32,
      height:32,
      _rest:bits,
    >> -> Ok(#(width, height))
    _ -> Error("missing PNG/IHDR signature")
  }
}

fn validate_html_embeddings() -> List(ResultLine) {
  let bundle = bundle_dir()
  [
    validate_html_count("index.html", bundle <> "/index.html"),
    validate_html_count("analysis.html", bundle <> "/analysis.html"),
    validate_html_count("deck.html", bundle <> "/deck.html"),
    validate_manifest(),
  ]
}

fn validate_html_count(name: String, path: String) -> ResultLine {
  case simplifile.read(path) {
    Error(e) ->
      ResultLine(
        name,
        "FAIL",
        "cannot read HTML: " <> simplifile.describe_error(e),
      )
    Ok(html) -> {
      let embedded = count_occurrences(html, "data:image/png;base64")
      let has_quality_link = string.contains(html, "diagram-quality-report.md")
      let figures = count_occurrences(html, "<figure")
      let captions = count_occurrences(html, "<figcaption")
      let svg_links = count_occurrences(html, ".svg")
      let png_links = count_occurrences(html, ".png")
      let rich_captions =
        count_occurrences(html, "Claim:")
        + count_occurrences(html, "Evidence:")
        + count_occurrences(html, "Risk if wrong:")
        + count_occurrences(html, "Quality:")
      let title_failures =
        diagram_titles()
        |> list.filter(fn(title) { !string.contains(html, title) })

      case
        embedded == 6
        && has_quality_link
        && figures >= 6
        && captions >= 6
        && svg_links >= 6
        && png_links >= 6
        && rich_captions >= 24
        && title_failures == []
      {
        True ->
          ResultLine(
            name,
            "PASS",
            "embedded_pngs=6 figures>=6 captions>=6 rich_captions>=24 links>=6",
          )
        False ->
          ResultLine(
            name,
            "FAIL",
            "embedded_pngs="
              <> int.to_string(embedded)
              <> " quality_report_link="
              <> bool_string(has_quality_link)
              <> " figures="
              <> int.to_string(figures)
              <> " captions="
              <> int.to_string(captions)
              <> " svg_links="
              <> int.to_string(svg_links)
              <> " png_links="
              <> int.to_string(png_links)
              <> " rich_caption_tokens="
              <> int.to_string(rich_captions)
              <> " missing_titles="
              <> string.join(title_failures, ", "),
          )
      }
    }
  }
}

fn diagram_titles() -> List(String) {
  [
    "Closure Evidence",
    "Dashboard Rendering Data Path",
    "UI Control Plane",
    "Fractal Layers and Clients",
    "No-Dummy Guardrails",
    "Touched Code Organization",
  ]
}

fn validate_content_files() -> List(ResultLine) {
  let bundle = bundle_dir()
  [
    validate_required_file("journal.md", bundle <> "/journal.md", 5000, [
      "## Current Evidence",
      "## Live Web Probe Evidence",
      "## Implementation Changes",
      "## Dashboard Data Path",
      "## Control Plane",
      "## Fractal Clients",
      "## UI Folder Novice Guide",
      "## Page Assembly Pattern",
      "## Spec and ZK Alignment",
      "## Agentic UI",
      "## No-Dummy Guardrails",
      "## Web, Rules, STAMP, and Skills Evaluation",
      "## Visualization Quality and Information Transmission",
      "## Report Aspect Coverage Matrix",
      "## Five-Minute Reader Path",
      "## User-Facing UI Runtime Risk Table",
      "## Code Snippets and Call Chain",
      "## Pre-Email Proof Gate",
      "## Startup, Logging, and Observability",
      "## Fractal Criticality Matrix",
      "## RETE-UL and Ruliology Decision Evidence",
      "## STAMP and AOR Governance Evidence",
      "## FMEA/FEMA Risk Evidence",
      "## Coverage Math Gate Evidence",
      "gleam test",
      "9773 passed",
      "Playwright",
      "1269 passed",
      "34302",
      "/api/v1/page-spec/all",
      "HTTP 503",
      "HTTP 501",
      "HTTP 404",
      "ui/wisp/router.gleam",
      "ui/web/dashboard_views.gleam",
      "shell-runtime.bundled.js",
      "route_internal",
      "route_html",
      "pub fn dashboard_view",
      "function expectedApiStatus",
      "GET /api/v1/does_not_exist",
      "ui_report_quality_gate",
      "SC-GLM-UI-001",
      "SC-PASS5-AUTO-001",
      "SC-FRAC-RRF-001",
      "SC-MATH-COV-004",
      "AOR-MATH-COV-001",
      "SC-UI-REPORT-QUALITY-028",
      "AOR-UIRPT-017",
      "semantic_score",
      "contextual_score",
      "visual_design_score",
      "Architecture diagrams are hypotheses",
      "architecture-diagram reality validation",
      "Claim",
      "Risk if wrong",
      "FMEA/FEMA risk evidence",
      "RPN_coverage",
      "RETEULDomains",
      "11,757,312 possible rule configurations",
      "pass5-pipeline",
      "c3i-page-evolution",
    ]),
    validate_required_file(
      "analysis.html",
      bundle <> "/analysis.html",
      120_000,
      [
        "Bundle Index",
        "Diagram Quality Report",
        "data:image/png;base64",
        "sa-plan",
        "Gleam",
        "Playwright",
        "Truthful APIs",
        "Dashboard Data Path",
        "No-Dummy Guardrails",
        "Live Web Probe Evidence",
        "Code Snippets and Call Chain",
        "Pre-Email Proof Gate",
        "AG-UI",
        "Web, Rules, STAMP, and Skills Evaluation",
        "Report Aspect Coverage Matrix",
        "Visualization Quality and Information Transmission",
        "Five-Minute Reader Path",
        "Claim:",
        "Risk if wrong:",
        "semantic_score",
        "contextual_score",
        "visual_design_score",
        "Architecture diagrams are hypotheses",
        "architecture-diagram reality validation",
        "SC-GLM-UI-001",
        "SC-PASS5-AUTO-001",
        "SC-FRAC-RRF-001",
        "SC-MATH-COV-004",
        "AOR-MATH-COV-001",
        "SC-UI-REPORT-QUALITY-028",
        "AOR-UIRPT-017",
        "FMEA/FEMA Risk Evidence",
        "RETE-UL and Ruliology Decision Evidence",
        "pass5-pipeline",
        "c3i-page-evolution",
      ],
    ),
    validate_required_file("deck.html", bundle <> "/deck.html", 115_000, [
      "Diagram Quality Report",
      "Quality Gate and Rules Evaluation",
      "Report Aspect Coverage Matrix",
      "Closure Evidence",
      "Dashboard Rendering Data Path",
      "UI Control Plane",
      "Fractal Layers and Clients",
      "No-Dummy Guardrails",
      "Touched Code Organization",
      "data:image/png;base64",
      "<pre",
      "route_internal",
      "function expectedApiStatus",
      "GET /api/v1/does_not_exist",
      "Takeaway:",
      "Claim:",
      "Risk if wrong:",
      "semantic_score",
      "contextual_score",
      "visual_design_score",
      "SC-GLM-UI-001",
      "SC-PASS5-AUTO-001",
      "SC-FRAC-RRF-001",
      "AOR-MATH-COV-001",
      "SC-UI-REPORT-QUALITY-028",
      "AOR-UIRPT-017",
      "FMEA/FEMA",
      "RETE-UL",
      "ruliology",
      "pass5-pipeline",
      "c3i-page-evolution",
    ]),
    validate_email(),
    validate_companion_doc(
      "architecture guide",
      root <> "/docs/architecture/C3I_ARCHITECTURE_IMPLEMENTATION_USER_GUIDE.md",
    ),
    validate_companion_doc(
      "fractal matrix",
      root
        <> "/docs/architecture/FRACTAL_SYSTEM_VOICE_CHAT_OBSERVABILITY_MATRIX.md",
    ),
    validate_quality_governance_doc(),
    validate_allium_spec(),
  ]
}

fn validate_integrity_files() -> List(ResultLine) {
  [
    validate_expected_artifacts_exist(),
    validate_local_link_targets(),
    validate_email_attachment_files(),
  ]
}

fn validate_deep_evidence() -> List(ResultLine) {
  [
    validate_parallel_gate_implementation(),
    validate_content_depth(),
    validate_source_excerpts(),
    validate_pre_email_gate(),
    validate_png_set_spread(),
    validate_svg_font_stack(),
    validate_svg_high_contrast_policy(),
    validate_claim_contracts(),
    validate_report_aspect_contracts(),
    validate_no_stale_or_placeholder_content(),
    validate_fmea_rete_ruliology_depth(),
  ]
}

fn validate_manifest() -> ResultLine {
  case simplifile.read(bundle_dir() <> "/links.json") {
    Error(e) ->
      ResultLine(
        "links.json",
        "FAIL",
        "cannot read manifest: " <> simplifile.describe_error(e),
      )
    Ok(json) -> {
      let failures =
        []
        |> require_at_least("svg_refs", count_occurrences(json, ".svg"), 6)
        |> require_at_least("png_refs", count_occurrences(json, ".png"), 6)
        |> require_tokens(json, [
          "diagram_quality_report",
          "companion_architecture_guide",
          "fractal_observability_matrix",
          "ui_quality_guardrail_spec",
          "ui_quality_allium_spec",
          "rules_stamp_skills",
          "SC-GLM-UI-001",
          "SC-PASS5-AUTO-001",
          "SC-UI-REPORT-QUALITY-001..028",
          "AOR-UIRPT-001..017",
          "reader_takeaway",
          "risk_if_wrong",
          "quality_aspects",
          "Artifact inventory and links",
          "semantic transmission",
          "contextual correctness",
          "visual design score",
          "architecture-diagram reality validation",
          "FMEA/FEMA",
          "RETE-UL",
          "ruliology",
        ])
        |> append_failures(validate_manifest_claim_contracts(json))

      case failures {
        [] ->
          ResultLine(
            "links.json",
            "PASS",
            "diagram refs, companion docs, and claim contracts present",
          )
        _ -> ResultLine("links.json", "FAIL", string.join(failures, "; "))
      }
    }
  }
}

fn validate_required_file(
  name: String,
  path: String,
  min_bytes: Int,
  tokens: List(String),
) -> ResultLine {
  case simplifile.read(path) {
    Error(e) ->
      ResultLine(name, "FAIL", "cannot read: " <> simplifile.describe_error(e))
    Ok(text) -> {
      let failures =
        []
        |> require_at_least("bytes", string.length(text), min_bytes)
        |> require_tokens(text, tokens)

      case failures {
        [] ->
          ResultLine(
            name,
            "PASS",
            "bytes=" <> int.to_string(string.length(text)),
          )
        _ -> ResultLine(name, "FAIL", string.join(failures, "; "))
      }
    }
  }
}

fn validate_email() -> ResultLine {
  case simplifile.read(bundle_dir() <> "/email.md") {
    Error(e) ->
      ResultLine(
        "email.md",
        "FAIL",
        "cannot read: " <> simplifile.describe_error(e),
      )
    Ok(text) -> {
      let failures =
        []
        |> require_tokens(text, [
          "abhijit.naik@bountytek.com",
          "diagram-quality-report.md",
          "C3I_ARCHITECTURE_IMPLEMENTATION_USER_GUIDE.md",
          "FRACTAL_SYSTEM_VOICE_CHAT_OBSERVABILITY_MATRIX.md",
          "UI_REPORT_QUALITY_GUARDRAIL_SPEC.md",
          "ui_report_quality_gate.allium",
          "federation returns 503",
          "health_grid returns 501",
          "unknown APIs return 404",
          "SVG and PNG originals",
          "ui_report_quality_gate",
          "SC-GLM-UI-001",
          "SC-PASS5-AUTO-001",
          "SC-UI-REPORT-QUALITY-001..028",
          "AOR-UIRPT-001..017",
          "Decision:",
          "Known gaps:",
          "Recommended first artifact:",
          "No action required / action required:",
          "semantic_score",
          "contextual_score",
          "visual_design_score",
          "Claim",
          "Risk",
          "Report aspect coverage matrix",
          "Artifact inventory and links",
          "Per-diagram claim register",
          "FMEA/FEMA",
          "RETE-UL",
          "ruliology",
          "pass5-pipeline",
          "c3i-page-evolution",
        ])
        |> require_at_least(
          "attachment_lines",
          count_occurrences(text, "- `/home/an/dev/ver/c3i/"),
          23,
        )
        |> require_at_least(
          "png_attachments",
          count_occurrences(text, ".png`"),
          6,
        )
        |> require_at_least(
          "svg_attachments",
          count_occurrences(text, ".svg`"),
          6,
        )

      case failures {
        [] ->
          ResultLine("email.md", "PASS", "recipient and 23 attachments present")
        _ -> ResultLine("email.md", "FAIL", string.join(failures, "; "))
      }
    }
  }
}

fn validate_companion_doc(name: String, path: String) -> ResultLine {
  validate_required_file(name, path, 1000, [
    bundle_slug() <> "/index.html",
    "ui_task_closure_bundle.gleam",
    "ui_diagram_quality_gate.gleam",
    "ui_report_quality_gate.gleam",
    "SC-PASS5-AUTO-001",
  ])
}

fn validate_quality_governance_doc() -> ResultLine {
  validate_required_file(
    "ui report quality governance doc",
    root <> "/docs/architecture/UI_REPORT_QUALITY_GUARDRAIL_SPEC.md",
    6500,
    [
      "Parallel Gate Execution Model",
      "STAMP Guardrail Expansion",
      "AOR Operator Rules",
      "FMEA/FEMA Risk Register",
      "RETE-UL Decision Coverage",
      "Ruliological Coverage",
      "After Every Task",
      "C3I_UI_REPORT_DIR",
      "ui_report_quality_gate",
      "system-font PNG rendering",
      "fresh render parity",
      "textless PNGs",
      "SC-UI-REPORT-QUALITY-028",
      "AOR-UIRPT-017",
      "semantic transmission",
      "contextual semantic correctness",
      "visual design score",
      "claim-evidence tuple",
      "Cross-Artifact Claim Contract",
      "Full Report Aspect Coverage",
      "ReportAspectContract",
      "stale or placeholder content",
      "Architecture diagrams are hypotheses",
      "architecture-diagram reality validation",
    ],
  )
}

fn validate_allium_spec() -> ResultLine {
  validate_required_file(
    "ui report quality allium spec",
    root <> "/specs/allium/ui_report_quality_gate.allium",
    4500,
    [
      "-- allium: 3",
      "UiReportQualityGate",
      "GatePasses",
      "NoDummySuccess",
      "EvidenceClaimsAreSourceFirst",
      "ParallelLaneCoverage",
      "FmeaRiskCoverage",
      "ReteUlRuliologyCoverage",
      "TextlessPngFails",
      "SemanticTransmissionRequired",
      "ContextualCorrectnessRequired",
      "BeautifulVisualizationRequired",
      "CrossArtifactInformationTransmission",
      "ClaimContractReconciliation",
      "FullReportAspectCoverage",
      "ReportAspectContract",
      "StalePlaceholderContentFails",
      "fresh_render_match",
      "semantic_transmission_score",
      "contextual_correctness_score",
      "visual_design_score",
      "vector_text_cells",
      "test_generation_instruction",
    ],
  )
}

fn validate_expected_artifacts_exist() -> ResultLine {
  let paths = closure_artifact_paths(False)

  let missing =
    paths
    |> list.filter(fn(path) {
      case simplifile.is_file(path) {
        Ok(True) -> False
        _ -> True
      }
    })

  case missing {
    [] -> ResultLine("artifact inventory", "PASS", "all expected files exist")
    _ -> ResultLine("artifact inventory", "FAIL", string.join(missing, "; "))
  }
}

fn validate_local_link_targets() -> ResultLine {
  let bundle = bundle_dir()
  let diagrams = diagram_dir()
  let linked_paths =
    [
      bundle <> "/journal.md",
      bundle <> "/analysis.html",
      bundle <> "/deck.html",
      bundle <> "/links.json",
      bundle <> "/email.md",
      root <> "/docs/architecture/C3I_ARCHITECTURE_IMPLEMENTATION_USER_GUIDE.md",
      root
        <> "/docs/architecture/FRACTAL_SYSTEM_VOICE_CHAT_OBSERVABILITY_MATRIX.md",
      root <> "/docs/architecture/UI_REPORT_QUALITY_GUARDRAIL_SPEC.md",
      root <> "/specs/allium/ui_report_quality_gate.allium",
    ]
    |> list.append(
      list.map(expected_checks(), fn(c) { diagrams <> "/" <> c.name <> ".svg" }),
    )
    |> list.append(
      list.map(expected_checks(), fn(c) { diagrams <> "/" <> c.name <> ".png" }),
    )

  case missing_files(linked_paths) {
    [] ->
      ResultLine(
        "local html links",
        "PASS",
        "checked local bundle links; diagram-quality-report.md is self-generated by this gate",
      )
    missing ->
      ResultLine("local html links", "FAIL", string.join(missing, "; "))
  }
}

fn validate_email_attachment_files() -> ResultLine {
  let paths = closure_artifact_paths(False)

  case missing_files(paths) {
    [] ->
      ResultLine(
        "email attachment files",
        "PASS",
        "checked attachment files; diagram-quality-report.md is written during this gate",
      )
    missing ->
      ResultLine("email attachment files", "FAIL", string.join(missing, "; "))
  }
}

fn validate_content_depth() -> ResultLine {
  case simplifile.read(bundle_dir() <> "/journal.md") {
    Error(e) ->
      ResultLine(
        "content depth",
        "FAIL",
        "cannot read journal: " <> simplifile.describe_error(e),
      )
    Ok(journal) -> {
      let failures =
        []
        |> require_at_least("sections", count_occurrences(journal, "\n## "), 12)
        |> require_at_least(
          "code_fences",
          count_occurrences(journal, "```"),
          12,
        )
        |> require_at_least(
          "source_refs",
          count_occurrences(journal, "lib/cepaf_gleam/"),
          18,
        )
        |> require_at_least(
          "curl_evidence",
          count_occurrences(journal, "curl "),
          8,
        )
        |> require_at_least(
          "http_statuses",
          count_occurrences(journal, "HTTP "),
          12,
        )
        |> require_tokens(journal, [
          "Live Web Probe Evidence",
          "Code Snippets and Call Chain",
          "Pre-Email Proof Gate",
          "Visualization Quality and Information Transmission",
          "Report Aspect Coverage Matrix",
          "Five-Minute Reader Path",
          "User-Facing UI Runtime Risk Table",
          "semantic_score",
          "contextual_score",
          "visual_design_score",
          "architecture-diagram reality validation",
          "ui_report_quality_gate",
        ])

      case failures {
        [] ->
          ResultLine(
            "content depth",
            "PASS",
            "journal is sectioned and source-backed",
          )
        _ -> ResultLine("content depth", "FAIL", string.join(failures, "; "))
      }
    }
  }
}

fn validate_parallel_gate_implementation() -> ResultLine {
  let path =
    root
    <> "/lib/cepaf_gleam/src/cepaf_gleam/tools/ui_diagram_quality_gate.gleam"

  validate_required_file("parallel gate implementation", path, 10_000, [
    "process.spawn_unlinked",
    "LaneResult",
    "validate_diagram",
    "validate_html_embeddings",
    "validate_content_files",
    "validate_integrity_files",
    "validate_deep_evidence",
    "validate_claim_contracts",
    "validate_report_aspect_contracts",
    "report_aspect_contracts",
    "validate_no_stale_or_placeholder_content",
    "validate_governance_surfaces",
    "semantic_transmission_score",
    "contextual_correctness_score",
    "visual_design_score",
    "collect_lane_results",
  ])
}

fn validate_source_excerpts() -> ResultLine {
  case simplifile.read(bundle_dir() <> "/journal.md") {
    Error(e) ->
      ResultLine(
        "source excerpts",
        "FAIL",
        "cannot read journal: " <> simplifile.describe_error(e),
      )
    Ok(journal) -> {
      let failures =
        []
        |> require_tokens(journal, [
          "route_internal",
          "\"/api/v1/dashboard\" | \"/api/dashboard\"",
          "route_html",
          "\"/dashboard\" ->",
          "/static/shell-runtime.bundled.js?v=2026-05-24-csp2",
          "pub fn dashboard_view",
          "function expectedApiStatus",
          "GET /api/v1/does_not_exist",
        ])

      case failures {
        [] ->
          ResultLine(
            "source excerpts",
            "PASS",
            "current source excerpts present",
          )
        _ -> ResultLine("source excerpts", "FAIL", string.join(failures, "; "))
      }
    }
  }
}

fn validate_pre_email_gate() -> ResultLine {
  let bundle = bundle_dir()
  let files = [
    bundle <> "/journal.md",
    bundle <> "/analysis.html",
    bundle <> "/deck.html",
    bundle <> "/email.md",
    root <> "/docs/architecture/C3I_ARCHITECTURE_IMPLEMENTATION_USER_GUIDE.md",
    root
      <> "/docs/architecture/FRACTAL_SYSTEM_VOICE_CHAT_OBSERVABILITY_MATRIX.md",
    root <> "/docs/architecture/UI_REPORT_QUALITY_GUARDRAIL_SPEC.md",
    root <> "/specs/allium/ui_report_quality_gate.allium",
  ]

  let missing_gate =
    files
    |> list.filter(fn(path) {
      case simplifile.read(path) {
        Ok(text) -> !string.contains(text, "ui_report_quality_gate")
        Error(_) -> True
      }
    })

  case missing_gate {
    [] ->
      ResultLine(
        "pre-email gate",
        "PASS",
        "all human-facing docs cite ui_report_quality_gate",
      )
    _ -> ResultLine("pre-email gate", "FAIL", string.join(missing_gate, "; "))
  }
}

fn closure_artifact_paths(include_report: Bool) -> List(String) {
  let bundle = bundle_dir()
  let diagrams = diagram_dir()
  let base = [
    bundle <> "/index.html",
    bundle <> "/journal.md",
    bundle <> "/analysis.html",
    bundle <> "/deck.html",
    bundle <> "/links.json",
    bundle <> "/email.md",
    root <> "/docs/architecture/C3I_ARCHITECTURE_IMPLEMENTATION_USER_GUIDE.md",
    root
      <> "/docs/architecture/FRACTAL_SYSTEM_VOICE_CHAT_OBSERVABILITY_MATRIX.md",
    root <> "/docs/architecture/UI_REPORT_QUALITY_GUARDRAIL_SPEC.md",
    root <> "/specs/allium/ui_report_quality_gate.allium",
  ]

  let with_report = case include_report {
    True -> [report_path(), ..base]
    False -> base
  }

  with_report
  |> list.append(
    list.map(expected_checks(), fn(c) { diagrams <> "/" <> c.name <> ".svg" }),
  )
  |> list.append(
    list.map(expected_checks(), fn(c) { diagrams <> "/" <> c.name <> ".png" }),
  )
}

fn missing_files(paths: List(String)) -> List(String) {
  paths
  |> list.filter(fn(path) {
    case simplifile.is_file(path) {
      Ok(True) -> False
      _ -> True
    }
  })
}

fn validate_png_set_spread() -> ResultLine {
  let diagrams = diagram_dir()
  let sizes =
    expected_checks()
    |> list.map(fn(c) {
      let path = diagrams <> "/" <> c.name <> ".png"
      case simplifile.read_bits(from: path) {
        Ok(bits) -> byte_size(bits)
        Error(_) -> 0
      }
    })

  let unique_sizes = unique_ints(sizes)
  let min_size = min_ints(sizes, 999_999_999)
  let max_size = max_ints(sizes, 0)
  let spread = max_size - min_size

  let failures =
    []
    |> require_at_least("unique_png_sizes", list.length(unique_sizes), 4)
    |> require_at_least("png_size_spread", spread, 4000)
    |> require_at_least("smallest_png", min_size, 100_000)

  case failures {
    [] ->
      ResultLine(
        "png set spread",
        "PASS",
        "unique_sizes="
          <> int.to_string(list.length(unique_sizes))
          <> " spread="
          <> int.to_string(spread),
      )
    _ -> ResultLine("png set spread", "FAIL", string.join(failures, "; "))
  }
}

fn validate_svg_font_stack() -> ResultLine {
  let diagrams = diagram_dir()
  let expected = "font-family=\"Arial,sans-serif\""
  let failures =
    expected_checks()
    |> list.map(fn(c) {
      let path = diagrams <> "/" <> c.name <> ".svg"
      case simplifile.read(path) {
        Ok(svg) ->
          case string.contains(svg, expected) {
            True -> ""
            False -> c.name <> " missing Arial SVG font stack"
          }
        Error(e) -> c.name <> " unreadable: " <> simplifile.describe_error(e)
      }
    })
    |> list.filter(fn(message) { message != "" })

  case failures {
    [] ->
      ResultLine(
        "svg font stack",
        "PASS",
        "all diagrams use Arial,sans-serif SVG font stack",
      )
    _ -> ResultLine("svg font stack", "FAIL", string.join(failures, "; "))
  }
}

fn validate_svg_high_contrast_policy() -> ResultLine {
  let diagrams = diagram_dir()
  let failures =
    expected_checks()
    |> list.map(fn(c) {
      let path = diagrams <> "/" <> c.name <> ".svg"
      case simplifile.read(path) {
        Ok(svg) -> {
          let score = high_contrast_score(svg)
          case score >= 90 {
            True -> ""
            False ->
              c.name
              <> " weak high-contrast policy score="
              <> int.to_string(score)
          }
        }
        Error(e) -> c.name <> " unreadable: " <> simplifile.describe_error(e)
      }
    })
    |> list.filter(fn(message) { message != "" })

  case failures {
    [] ->
      ResultLine(
        "svg high contrast policy",
        "PASS",
        "all diagrams declare high contrast, full-opacity visible text, bright foregrounds, and dark backgrounds",
      )
    _ ->
      ResultLine(
        "svg high contrast policy",
        "FAIL",
        string.join(failures, "; "),
      )
  }
}

fn validate_claim_contracts() -> ResultLine {
  let bundle = bundle_dir()
  let common_artifacts = [
    #("journal.md", bundle <> "/journal.md"),
    #("index.html", bundle <> "/index.html"),
    #("analysis.html", bundle <> "/analysis.html"),
    #("deck.html", bundle <> "/deck.html"),
    #("email.md", bundle <> "/email.md"),
  ]

  let failures =
    claim_contracts()
    |> list.fold([], fn(acc, contract) {
      let ClaimContract(
        name,
        title,
        takeaway,
        claim,
        evidence,
        risk,
        source_tokens,
      ) = contract
      let common_tokens = [title, takeaway, claim, evidence, risk]
      let artifact_failures =
        common_artifacts
        |> list.fold([], fn(inner_acc, artifact) {
          let #(label, path) = artifact
          list.append(
            inner_acc,
            file_contract_failures(label <> " " <> name, path, common_tokens),
          )
        })

      let svg_tokens =
        common_tokens
        |> list.append(source_tokens)
        |> list.append(["Claim:", "Evidence:", "Risk if wrong:", "Quality:"])
      let svg_failures =
        file_contract_failures(
          "svg " <> name,
          diagram_dir() <> "/" <> name <> ".svg",
          svg_tokens,
        )

      list.append(acc, artifact_failures)
      |> append_failures(svg_failures)
    })
    |> append_failures(
      file_contract_failures("links.json", bundle <> "/links.json", [
        "reader_takeaway",
        "claim",
        "evidence",
        "risk_if_wrong",
        "quality_contract",
        "architecture-diagram reality validation",
      ]),
    )

  case failures {
    [] ->
      ResultLine(
        "cross-artifact claim contracts",
        "PASS",
        "6 diagrams reconciled across journal, index, analysis, deck, email, manifest, and SVG metadata",
      )
    _ ->
      ResultLine(
        "cross-artifact claim contracts",
        "FAIL",
        string.join(failures, "; "),
      )
  }
}

fn validate_report_aspect_contracts() -> ResultLine {
  let bundle = bundle_dir()
  let artifacts = [
    #("journal.md", bundle <> "/journal.md"),
    #("index.html", bundle <> "/index.html"),
    #("analysis.html", bundle <> "/analysis.html"),
    #("deck.html", bundle <> "/deck.html"),
    #("email.md", bundle <> "/email.md"),
    #("links.json", bundle <> "/links.json"),
  ]

  let failures =
    report_aspect_contracts()
    |> list.fold([], fn(acc, contract) {
      let ReportAspectContract(name, decision_value, evidence, guardrail) =
        contract
      let tokens = [name, decision_value, evidence, guardrail]
      let artifact_failures =
        artifacts
        |> list.fold([], fn(inner_acc, artifact) {
          let #(label, path) = artifact
          list.append(
            inner_acc,
            file_contract_failures(label <> " aspect " <> name, path, tokens),
          )
        })
      list.append(acc, artifact_failures)
    })

  case failures {
    [] ->
      ResultLine(
        "full report aspect contracts",
        "PASS",
        "13 report aspects reconciled across journal, index, analysis, deck, email, and manifest",
      )
    _ ->
      ResultLine(
        "full report aspect contracts",
        "FAIL",
        string.join(failures, "; "),
      )
  }
}

fn validate_manifest_claim_contracts(json: String) -> List(String) {
  claim_contracts()
  |> list.fold([], fn(acc, contract) {
    let ClaimContract(
      name,
      title,
      takeaway,
      claim,
      evidence,
      risk,
      _source_tokens,
    ) = contract
    let tokens = [name, title, takeaway, claim, evidence, risk]
    list.append(acc, text_token_failures("links.json " <> name, json, tokens))
  })
}

fn validate_no_stale_or_placeholder_content() -> ResultLine {
  let bundle = bundle_dir()
  let artifacts =
    [
      #("journal.md", bundle <> "/journal.md"),
      #("index.html", bundle <> "/index.html"),
      #("analysis.html", bundle <> "/analysis.html"),
      #("deck.html", bundle <> "/deck.html"),
      #("links.json", bundle <> "/links.json"),
      #("email.md", bundle <> "/email.md"),
    ]
    |> list.append(
      expected_checks()
      |> list.map(fn(c) {
        #("svg " <> c.name, diagram_dir() <> "/" <> c.name <> ".svg")
      }),
    )

  let forbidden = [
    "9755 passed",
    "9762 passed",
    "9766 passed",
    "9772 passed",
    "Lorem ipsum",
    "TBD",
    "TODO",
    "fill-opacity=\"0.01\"",
    "decorative-only",
    "image placeholder",
    "placeholder image",
    "no useful output",
    "visual slop",
  ]

  let failures =
    artifacts
    |> list.fold([], fn(acc, artifact) {
      let #(label, path) = artifact
      list.append(acc, forbidden_token_failures(label, path, forbidden))
    })

  case failures {
    [] ->
      ResultLine(
        "stale and placeholder content guard",
        "PASS",
        "no stale counts, TODO/TBD, placeholder-image, hidden-text, or slop markers found in generated artifacts",
      )
    _ ->
      ResultLine(
        "stale and placeholder content guard",
        "FAIL",
        string.join(failures, "; "),
      )
  }
}

fn claim_contracts() -> List(ClaimContract) {
  [
    ClaimContract(
      "01-closure-evidence",
      "Closure Evidence",
      "Closure is evidence-backed only if every build, test, runtime, artifact, and delivery row remains true.",
      "the UI closure is supported by current build, test, runtime, artifact, and delivery evidence rather than by a decorative summary.",
      "sa-plan 0/0/3174, 173 UI Gleam files, 34302 UI LOC, gleam build clean, gleam test 9773 passed, Playwright 1269 passed, /dashboard 200, page-spec all 100%, shell runtime 200, and non-dummy 503/501/404 probes.",
      "operators may accept a closure bundle that omits failed checks, stale artifacts, or missing attachments.",
      [
        "ui_task_closure_bundle.gleam",
        "ui_diagram_quality_gate.gleam",
        "GET /api/v1/does_not_exist",
      ],
    ),
    ClaimContract(
      "02-dashboard-rendering",
      "Dashboard Rendering Data Path",
      "The dashboard is assembled server-side first, then enhanced by a CSP-safe browser runtime.",
      "/dashboard is generated by Browser -> Mist/Wisp -> router.gleam -> page_views -> dashboard_views.gleam -> shell.gleam -> shell-runtime.bundled.js.",
      "source excerpts from router.gleam, dashboard_views.gleam, shell.gleam, page metadata, and live /dashboard plus AG-UI route probes.",
      "a future maintainer may debug the browser instead of the actual server-side route/view/runtime stage that produced the page.",
      [
        "ui/wisp/router.gleam",
        "ui/web/dashboard_views.gleam",
        "ui/lustre/shell.gleam",
      ],
    ),
    ClaimContract(
      "03-control-plane",
      "UI Control Plane",
      "The control plane treats unknown or not-wired data sources as explicit non-success states.",
      "startup, routing, auth, status mapping, hot reload, and observability form the UI control plane, and fake 200 statuses are blocked.",
      "route_internal, route_html, expectedApiStatus, /health, /api/v1/pages, AG-UI SSE, tmux/log controls, and no-dummy browser assertions.",
      "mutation routes, hot reload, or missing data sources may accidentally report success or lose operator observability.",
      ["route_internal", "route_html", "function expectedApiStatus"],
    ),
    ClaimContract(
      "04-fractal-clients",
      "Fractal Layers and Clients",
      "The UI is a fractal client matrix, not only a browser page.",
      "the route catalog exposes L0-L7 layer metadata and Browser SSR, REST JSON, TUI ANSI, AG-UI, and A2UI client surfaces.",
      "/api/v1/pages metadata, the fractal observability matrix, dashboard L0-L7 rendering, and route/client parity notes.",
      "a routed page may appear complete for one client while failing AG-UI, A2UI, REST, TUI, or an L0-L7 layer obligation.",
      [
        "/api/v1/pages",
        "L0-L7",
        "FRACTAL_SYSTEM_VOICE_CHAT_OBSERVABILITY_MATRIX.md",
      ],
    ),
    ClaimContract(
      "05-no-dummy-guardrails",
      "No-Dummy Guardrails",
      "A non-200 status can be the correct result when the live source is intentionally not wired.",
      "known live-source gaps return 503 or 501 and unknown APIs return 404, so missing implementations cannot masquerade as success.",
      "Playwright expectedApiStatus checks, page-spec empty-array regression, and curl evidence for federation 503, health_grid 501, ai/chat 501, and /api/v1/does_not_exist 404.",
      "dummy code may return 200 and hide that federation or health-grid data is not actually wired.",
      ["function expectedApiStatus", "GET /api/v1/does_not_exist", "no-dummy"],
    ),
    ClaimContract(
      "06-code-organization",
      "Touched Code Organization",
      "The touched files form a narrow route/runtime/test/report chain that can be reviewed stage by stage.",
      "the closure edits are scoped to the shell runtime, Wisp routing, dashboard rendering, browser tests, WebKit setup, and report generator/gate.",
      "ui/domain, ui/state, ui/wisp, ui/web, ui/lustre, ui/tui, ui/zenoh_otel, shell-runtime, source excerpts, and generated report/gate/spec files.",
      "reviewers may miss the real ownership boundaries and accidentally change unrelated runtime or test surfaces.",
      ["shell-runtime.ts", "build:shell-runtime", "route_html"],
    ),
  ]
}

fn report_aspect_contracts() -> List(ReportAspectContract) {
  [
    ReportAspectContract(
      "Artifact inventory and links",
      "Every generated artifact, local link, and email attachment must resolve before publication.",
      "index.html, journal.md, analysis.html, deck.html, links.json, email.md, companion docs, six SVGs, and six PNGs.",
      "missing files, stale links, or attachment drift block email.",
    ),
    ReportAspectContract(
      "Web and runtime reality",
      "Runtime claims must be backed by current web probes or clearly labeled recorded evidence.",
      "/dashboard 200, /api/v1/pages 200, /api/v1/components 200, /api/v1/page-spec/all 200 with all 6 checked pages at 100%, /ag-ui/health 200, /ag-ui/events 200, shell runtime 200, federation 503, health_grid 501, ai/chat 501, unknown API 404.",
      "historical or invented runtime success cannot pass as current.",
    ),
    ReportAspectContract(
      "Source-backed data path",
      "Every page-generation claim must map to current source excerpts and route/view/runtime ownership.",
      "ui/domain.gleam, ui/state.gleam, router.gleam, page_views, dashboard_views.gleam, shell.gleam, TUI renderers, zenoh_otel.gleam, shell-runtime.ts, and browser test excerpts.",
      "memory-only architecture prose is rejected.",
    ),
    ReportAspectContract(
      "Control plane and no-dummy status",
      "Control routes, mutation gates, startup, hot reload, and status mapping must preserve truthful non-success behavior.",
      "501, 503, and 404 status paths are treated as correct when live sources are not wired.",
      "fake HTTP 200 for missing implementations blocks closure.",
    ),
    ReportAspectContract(
      "Visual information transmission",
      "Diagrams must teach a claim through structure, readable labels, evidence refs, and score thresholds.",
      "semantic_score, contextual_score, visual_design_score, contrast_score, vector_cells, evidence_refs, and fresh_render_match=true.",
      "textless or decorative images block publication.",
    ),
    ReportAspectContract(
      "Rules evaluation",
      "Local rule surfaces must name the report-quality gate and the UI/runtime obligations it enforces.",
      ".agents, .claude, .gemini, AGENTS.md, and docs/webhooks carry matching rule intent.",
      "rule drift or fail-open instructions block closure.",
    ),
    ReportAspectContract(
      "STAMP and AOR coverage",
      "STAMP constraints and AOR operator rules must be visible, mapped to gates, and current.",
      "SC-UI-REPORT-QUALITY-001..028, SC-GLM-UI-001, SC-PASS5-AUTO-001, SC-FRAC-RRF, SC-MATH-COV, AOR-UIRPT, and AOR-MATH-COV.",
      "missing governance coverage blocks email.",
    ),
    ReportAspectContract(
      "Skills agents and hooks",
      "Skills, agents, settings hooks, and webhook docs must reinforce the same quality workflow.",
      "ui-report-quality skill, ui-report-quality-auditor agent, settings hooks, webhook doc, pass5-pipeline, and c3i-page-evolution.",
      "email cannot bypass a failing Gleam gate.",
    ),
    ReportAspectContract(
      "FMEA and FEMA risk",
      "Report-quality failure modes must carry S,O,D,RPN, RPN_coverage, mitigation, and FEMA response notes.",
      "decorative PNGs, textless PNGs, source gaps, dummy 200s, email omissions, and governance drift are modeled.",
      "high-risk content failures block publication until mitigated.",
    ),
    ReportAspectContract(
      "RETE-UL and ruliology",
      "The pass decision must join artifact, visual, runtime, source, governance, and delivery facts.",
      "RETEULDomains, TotalRETERules, RETERuleSpace, 15-dimensional rulial space, and P0->P1->P2->P3 production path.",
      "single-artifact success cannot hide missing adjacent rule-space facts.",
    ),
    ReportAspectContract(
      "Coverage math",
      "Analysis quality must expose entropy, CCM, D_EA, FSI, ITQS, and visual-score thresholds.",
      "H >= 2.5, H_norm >= 0.83, CCM >= 0.90, D_EA <= 0.10, and ITQS >= 0.85.",
      "token-heavy but low-information analysis fails the gate.",
    ),
    ReportAspectContract(
      "Fractal layer and client coverage",
      "Every UI report must cover L0-L7 concerns and Browser SSR, REST JSON, TUI ANSI, AG-UI, and A2UI clients.",
      "fractal route metadata, FRACTAL_SYSTEM_VOICE_CHAT_OBSERVABILITY_MATRIX.md, AG-UI, A2UI, and no-dummy L7 federation behavior.",
      "single-page browser-only analysis is incomplete.",
    ),
    ReportAspectContract(
      "Delivery readiness",
      "The email must be manifest-driven and include the quality report, docs, deck, HTML, SVGs, and PNGs.",
      "email.md lists absolute attachment paths and points the reader to diagram-quality-report.md first.",
      "attachment counts alone are not proof.",
    ),
  ]
}

fn file_contract_failures(
  label: String,
  path: String,
  tokens: List(String),
) -> List(String) {
  case simplifile.read(path) {
    Error(e) -> [label <> " unreadable: " <> simplifile.describe_error(e)]
    Ok(text) -> text_token_failures(label, text, tokens)
  }
}

fn text_token_failures(
  label: String,
  text: String,
  tokens: List(String),
) -> List(String) {
  let normalized = xml_unescape(text)
  tokens
  |> list.filter(fn(token) {
    !string.contains(text, token) && !string.contains(normalized, token)
  })
  |> list.map(fn(token) { label <> " missing contract token " <> token })
}

fn forbidden_token_failures(
  label: String,
  path: String,
  forbidden: List(String),
) -> List(String) {
  case simplifile.read(path) {
    Error(e) -> [label <> " unreadable: " <> simplifile.describe_error(e)]
    Ok(text) -> {
      let scan_text = stale_scan_text(label, text)
      forbidden
      |> list.filter(fn(token) { string.contains(scan_text, token) })
      |> list.map(fn(token) { label <> " contains forbidden token " <> token })
    }
  }
}

fn stale_scan_text(label: String, text: String) -> String {
  case string.contains(label, ".html") {
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

fn validate_fmea_rete_ruliology_depth() -> ResultLine {
  case simplifile.read(bundle_dir() <> "/journal.md") {
    Error(e) ->
      ResultLine(
        "FMEA/RETE/ruliology depth",
        "FAIL",
        "cannot read journal: " <> simplifile.describe_error(e),
      )
    Ok(journal) -> {
      let failures =
        []
        |> require_tokens(journal, [
          "SC-FRAC-RRF-001",
          "SC-FRAC-RRF-002",
          "SC-FRAC-RRF-003",
          "SC-FRAC-RRF-004",
          "SC-FRAC-RRF-005",
          "SC-FRAC-RRF-006",
          "SC-MATH-COV-001",
          "SC-MATH-COV-002",
          "SC-MATH-COV-003",
          "SC-MATH-COV-004",
          "SC-MATH-COV-005",
          "SC-MATH-COV-006",
          "SC-MATH-COV-007",
          "SC-MATH-COV-008",
          "AOR-MATH-COV-001",
          "AOR-MATH-COV-002",
          "AOR-MATH-COV-003",
          "AOR-MATH-COV-004",
          "AOR-MATH-COV-005",
          "AOR-MATH-COV-006",
          "AOR-MATH-COV-007",
          "AOR-MATH-COV-008",
          "AOR-UIRPT-001",
          "AOR-UIRPT-012",
          "AOR-UIRPT-013",
          "AOR-UIRPT-017",
          "SC-UI-REPORT-QUALITY-021",
          "SC-UI-REPORT-QUALITY-028",
          "RETE-UL",
          "ruliology",
          "S,O,D,RPN",
          "RPN_coverage",
          "FEMA response note",
          "P0->P1->P2->P3",
          "L0-L7",
          "H >= 2.5",
          "H_norm >= 0.83",
          "CCM >= 0.90",
          "D_EA <= 0.10",
          "ITQS >= 0.85",
          "RETEULDomains",
          "TotalRETERules",
          "52 rules",
          "RETERuleSpace",
          "11,757,312 possible rule configurations",
          "15-dimensional rulial space",
          "raster text survival",
          "source evidence refs",
          "claim-evidence tuples",
          "semantic transmission",
          "contextual semantic correctness",
          "beautiful visualization",
          "Production system (forward-chaining)",
        ])

      case failures {
        [] ->
          ResultLine(
            "FMEA/RETE/ruliology depth",
            "PASS",
            "fractal criticality, risk, and rule-space evidence present",
          )
        _ ->
          ResultLine(
            "FMEA/RETE/ruliology depth",
            "FAIL",
            string.join(failures, "; "),
          )
      }
    }
  }
}

fn validate_governance_surfaces() -> ResultLine {
  let stamp_tokens = ui_quality_stamp_tokens()
  let surfaces = [
    #(root <> "/.agents/rules/ui-report-quality-gate.md", stamp_tokens),
    #(root <> "/.claude/rules/ui-report-quality-gate.md", stamp_tokens),
    #(root <> "/.gemini/rules/ui-report-quality-gate.md", stamp_tokens),
    #(root <> "/docs/webhooks/ui-report-quality-gate.md", stamp_tokens),
    #(root <> "/.agents/rules/constraint-registry.md", [
      "SC-UI-REPORT-QUALITY",
      "001-028",
      "ui_report_quality_gate",
    ]),
    #(root <> "/.claude/rules/constraint-registry.md", [
      "SC-UI-REPORT-QUALITY",
      "001-028",
      "ui_report_quality_gate",
    ]),
    #(root <> "/.gemini/rules/constraint-registry.md", [
      "SC-UI-REPORT-QUALITY",
      "001-028",
      "ui_report_quality_gate",
    ]),
    #(root <> "/.agents/skills/ui-report-quality/SKILL.md", [
      "ui_report_quality_gate",
      "C3I_UI_REPORT_DIR",
      "Do not send email",
      "vector-text",
      "fresh render parity",
      "FMEA/FEMA",
      "RETE-UL",
      "ruliology",
      "semantic transmission",
      "contextual correctness",
      "visual design score",
    ]),
    #(root <> "/.claude/skills/ui-report-quality/SKILL.md", [
      "ui_report_quality_gate",
      "C3I_UI_REPORT_DIR",
      "Do not send email",
      "vector-text",
      "fresh render parity",
      "FMEA/FEMA",
      "RETE-UL",
      "ruliology",
      "semantic transmission",
      "contextual correctness",
      "visual design score",
    ]),
    #(root <> "/.gemini/skills/ui-report-quality/SKILL.md", [
      "ui_report_quality_gate",
      "C3I_UI_REPORT_DIR",
      "Do not send email",
      "vector-text",
      "fresh render parity",
      "FMEA/FEMA",
      "RETE-UL",
      "ruliology",
      "semantic transmission",
      "contextual correctness",
      "visual design score",
    ]),
    #(root <> "/.agents/agents/ui-report-quality-auditor.md", [
      "ui_report_quality_gate",
      "SC-UI-REPORT-QUALITY",
      "vector-text",
      "fresh render parity",
      "FMEA/FEMA",
      "RETE-UL",
      "claim-evidence",
      "visual design score",
    ]),
    #(root <> "/.claude/agents/ui-report-quality-auditor.md", [
      "ui_report_quality_gate",
      "SC-UI-REPORT-QUALITY",
      "vector-text",
      "fresh render parity",
      "FMEA/FEMA",
      "RETE-UL",
      "claim-evidence",
      "visual design score",
    ]),
    #(root <> "/.gemini/agents/ui-report-quality-auditor.md", [
      "ui_report_quality_gate",
      "SC-UI-REPORT-QUALITY",
      "vector-text",
      "fresh render parity",
      "FMEA/FEMA",
      "RETE-UL",
      "claim-evidence",
      "visual design score",
    ]),
    #(root <> "/.agents/settings.json", [
      "ui_report_quality_gate",
      "C3I_UI_REPORT_DIR",
      "exit 1",
      "sa-plan",
    ]),
    #(root <> "/.claude/settings.json", [
      "ui_report_quality_gate",
      "C3I_UI_REPORT_DIR",
      "exit 1",
      "sa-plan",
    ]),
    #(root <> "/.gemini/settings.json", [
      "ui_report_quality_gate",
      "C3I_UI_REPORT_DIR",
      "exit 1",
      "sa-plan",
    ]),
  ]

  let failures =
    surfaces
    |> list.fold([], fn(acc, surface) {
      let #(path, tokens) = surface
      list.append(acc, file_token_failures(path, tokens))
    })

  case failures {
    [] ->
      ResultLine(
        "governance surfaces",
        "PASS",
        "rules, skills, agents, hooks, webhook, and STAMP registries present",
      )
    _ -> ResultLine("governance surfaces", "FAIL", string.join(failures, "; "))
  }
}

fn file_token_failures(path: String, tokens: List(String)) -> List(String) {
  case simplifile.read(path) {
    Error(e) -> [path <> " unreadable: " <> simplifile.describe_error(e)]
    Ok(text) ->
      tokens
      |> list.filter(fn(token) { !string.contains(text, token) })
      |> list.map(fn(token) { path <> " missing " <> token })
  }
}

fn ui_quality_stamp_tokens() -> List(String) {
  [
    "SC-UI-REPORT-QUALITY-001",
    "SC-UI-REPORT-QUALITY-002",
    "SC-UI-REPORT-QUALITY-003",
    "SC-UI-REPORT-QUALITY-004",
    "SC-UI-REPORT-QUALITY-005",
    "SC-UI-REPORT-QUALITY-006",
    "SC-UI-REPORT-QUALITY-007",
    "SC-UI-REPORT-QUALITY-008",
    "SC-UI-REPORT-QUALITY-009",
    "SC-UI-REPORT-QUALITY-010",
    "SC-UI-REPORT-QUALITY-011",
    "SC-UI-REPORT-QUALITY-012",
    "SC-UI-REPORT-QUALITY-013",
    "SC-UI-REPORT-QUALITY-014",
    "SC-UI-REPORT-QUALITY-015",
    "SC-UI-REPORT-QUALITY-016",
    "SC-UI-REPORT-QUALITY-017",
    "SC-UI-REPORT-QUALITY-018",
    "SC-UI-REPORT-QUALITY-019",
    "SC-UI-REPORT-QUALITY-020",
    "SC-UI-REPORT-QUALITY-021",
    "SC-UI-REPORT-QUALITY-022",
    "SC-UI-REPORT-QUALITY-023",
    "SC-UI-REPORT-QUALITY-024",
    "SC-UI-REPORT-QUALITY-025",
    "SC-UI-REPORT-QUALITY-026",
    "SC-UI-REPORT-QUALITY-027",
    "SC-UI-REPORT-QUALITY-028",
    "vector-text",
    "fresh render parity",
    "textless PNG",
    "claim-evidence tuple",
    "semantic transmission",
    "contextual semantic correctness",
    "visual design score",
  ]
}

fn extract_text_nodes(svg: String) -> List(String) {
  svg
  |> string.split("<text ")
  |> list.drop(1)
  |> list.filter_map(fn(part) {
    case string.split_once(part, ">") {
      Ok(#(_attrs, after_open)) ->
        case string.split_once(after_open, "</text>") {
          Ok(#(text, _rest)) -> Ok(xml_unescape(text))
          Error(_) -> Error(Nil)
        }
      Error(_) -> Error(Nil)
    }
  })
}

fn xml_unescape(text: String) -> String {
  text
  |> string.replace("&amp;", "&")
  |> string.replace("&lt;", "<")
  |> string.replace("&gt;", ">")
  |> string.replace("&quot;", "\"")
  |> string.replace("&#39;", "'")
}

fn unique_terms(text: String) -> List(String) {
  normalize_for_terms(text)
  |> string.split(" ")
  |> list.map(string.trim)
  |> list.filter(fn(term) { string.length(term) >= 3 && !is_stopword(term) })
  |> unique_strings
}

fn normalize_for_terms(text: String) -> String {
  string.lowercase(text)
  |> string.replace("/", " ")
  |> string.replace("\\", " ")
  |> string.replace(".", " ")
  |> string.replace(",", " ")
  |> string.replace(":", " ")
  |> string.replace(";", " ")
  |> string.replace("(", " ")
  |> string.replace(")", " ")
  |> string.replace("[", " ")
  |> string.replace("]", " ")
  |> string.replace("|", " ")
  |> string.replace("-", " ")
  |> string.replace("_", " ")
  |> string.replace(">", " ")
  |> string.replace("<", " ")
  |> string.replace("=", " ")
}

fn is_stopword(term: String) -> Bool {
  list.contains(
    [
      "the", "and", "for", "with", "from", "into", "that", "this", "are", "not",
      "all", "via", "can", "also", "now", "out", "run", "get", "put",
    ],
    term,
  )
}

fn unique_strings(values: List(String)) -> List(String) {
  values
  |> list.fold([], fn(acc, value) {
    case list.contains(acc, value) {
      True -> acc
      False -> [value, ..acc]
    }
  })
}

fn count_numeric_claims(text: String) -> Int {
  text
  |> string.split(" ")
  |> list.filter(has_digit)
  |> list.length
}

fn has_digit(value: String) -> Bool {
  value
  |> string.to_graphemes
  |> list.any(fn(ch) {
    ch == "0"
    || ch == "1"
    || ch == "2"
    || ch == "3"
    || ch == "4"
    || ch == "5"
    || ch == "6"
    || ch == "7"
    || ch == "8"
    || ch == "9"
  })
}

fn count_status_claims(text: String) -> Int {
  let upper = string.uppercase(text)
  [
    "HTTP 200",
    "HTTP 501",
    "HTTP 503",
    "HTTP 404",
    " 200",
    " 501",
    " 503",
    " 404",
    "PASS",
    "PASSED",
    "BLOCKED",
  ]
  |> list.fold(0, fn(acc, token) { acc + count_occurrences(upper, token) })
}

fn semantic_transmission_score(svg: String, visible_text: String) -> Int {
  let lower = string.lowercase(visible_text <> " " <> svg)
  let unique_count = list.length(unique_terms(visible_text))
  let evidence_count = count_occurrences(svg, "data-c3i-evidence-path=")
  let numeric_count = count_numeric_claims(visible_text)
  let status_count = count_status_claims(visible_text)
  let arrow_count = count_occurrences(svg, "marker-end")
  let structure_terms =
    count_present(lower, [
      "flow", "path", "route", "matrix", "decision", "status", "evidence",
      "runtime", "control", "data", "fractal", "client",
    ])

  points_if(unique_count >= 30, 18)
  + points_if(unique_count >= 60, 10)
  + points_if(string.length(visible_text) >= 700, 14)
  + points_if(evidence_count >= 3, 18)
  + points_if(numeric_count >= 2, 10)
  + points_if(status_count >= 1, 8)
  + points_if(arrow_count >= 5 || count_occurrences(svg, "<rect ") >= 48, 10)
  + points_if(structure_terms >= 5, 12)
}

fn contextual_correctness_score(svg: String, visible_text: String) -> Int {
  let lower = string.lowercase(visible_text <> " " <> svg)
  let evidence_paths = count_occurrences(svg, "data-c3i-evidence-path=")
  let evidence_anchors = count_occurrences(svg, "data-c3i-evidence-anchor=")
  let source_paths =
    count_occurrences(svg, "lib/cepaf_gleam/")
    + count_occurrences(svg, "docs/")
    + count_occurrences(svg, "specs/")
  let runtime_terms =
    count_present(lower, [
      "dashboard", "route", "router", "shell", "runtime", "api", "ag-ui",
      "playwright", "gleam", "status", "test", "guardrail",
    ])
  let truth_terms =
    count_present(lower, [
      "503", "501", "404", "no-dummy", "dummy", "not wired", "evidence",
      "source", "verified", "quality", "gate",
    ])

  points_if(evidence_paths >= 3, 20)
  + points_if(evidence_anchors >= 3, 15)
  + points_if(source_paths >= 3, 15)
  + points_if(runtime_terms >= 5, 20)
  + points_if(truth_terms >= 3, 18)
  + points_if(count_occurrences(svg, "<desc>") >= 3, 12)
}

fn visual_design_score(svg: String) -> Int {
  let rects = count_occurrences(svg, "<rect ")
  let texts = count_occurrences(svg, "<text ")
  let vector_cells = count_occurrences(svg, "class=\"vtext-cell\"")
  let arrows = count_occurrences(svg, "marker-end")
  let palette = visual_palette_count(svg)

  points_if(rects >= 14, 14)
  + points_if(rects >= 30, 10)
  + points_if(texts >= 34, 14)
  + points_if(vector_cells >= 800, 18)
  + points_if(palette >= 7, 14)
  + points_if(string.contains(svg, "rx=\""), 8)
  + points_if(string.contains(svg, "stroke-width=\"2\""), 7)
  + points_if(string.contains(svg, "<rect width=\"1600\" height=\"980\""), 7)
  + points_if(arrows >= 5 || rects >= 48, 8)
}

fn high_contrast_score(svg: String) -> Int {
  points_if(string.contains(svg, "data-c3i-contrast=\"high\""), 20)
  + points_if(string.contains(svg, "data-c3i-contrast-min-ratio=\"7.0\""), 15)
  + points_if(
    count_present(svg, ["#050814", "#0b1220", "#ffffff", "#e2e8f0", "#cbd5e1"])
      >= 5,
    20,
  )
  + absent_points(svg, "fill-opacity=\"0.82\"", 15)
  + points_if(
    count_present(svg, ["#60a5fa", "#93c5fd", "#a7f3d0", "#fde047"]) >= 3,
    15,
  )
  + points_if(
    count_occurrences(svg, "font-family=\"Arial,sans-serif\"") >= 10,
    15,
  )
}

fn absent_points(text: String, token: String, points: Int) -> Int {
  case string.contains(text, token) {
    True -> 0
    False -> points
  }
}

fn count_present(text: String, tokens: List(String)) -> Int {
  tokens
  |> list.filter(fn(token) { string.contains(text, token) })
  |> list.length
}

fn points_if(condition: Bool, points: Int) -> Int {
  case condition {
    True -> points
    False -> 0
  }
}

fn visual_palette_count(svg: String) -> Int {
  let colors = [
    "#050814", "#0b1220", "#ffffff", "#e2e8f0", "#cbd5e1", "#60a5fa", "#93c5fd",
    "#a7f3d0", "#fde047", "#f8fafc", "#0f1623", "#121d2d", "#334a68", "#edf5ff",
    "#a9bdd6", "#6ee7b7", "#7ea3c7", "#7dd3fc", "#c6d5e7", "#f2f7ff", "#172438",
    "#17332f", "#25263d", "#342820", "#182c3d", "#132d2a", "#2a2236", "#f87171",
    "#fca5a5", "#fbbf24", "#dff7ed", "#101b2a", "#2c405c",
  ]
  count_present(svg, colors)
}

fn validate_expected_evidence_refs(name: String, svg: String) -> List(String) {
  expected_evidence_refs(name)
  |> list.fold([], fn(acc, ref) {
    let EvidenceRef(path, anchor) = ref
    let svg_failures =
      []
      |> require_tokens(svg, [
        "data-c3i-evidence-path=\"" <> path <> "\"",
        "data-c3i-evidence-anchor=\"" <> anchor <> "\"",
      ])

    let file_failures = case simplifile.read(root <> "/" <> path) {
      Error(e) -> [
        "evidence file unreadable "
        <> path
        <> ": "
        <> simplifile.describe_error(e),
      ]
      Ok(text) ->
        case string.contains(text, anchor) {
          True -> []
          False -> ["evidence file " <> path <> " missing anchor " <> anchor]
        }
    }

    acc
    |> append_failures(svg_failures)
    |> append_failures(file_failures)
  })
}

fn expected_evidence_refs(name: String) -> List(EvidenceRef) {
  case name {
    "01-closure-evidence" -> [
      EvidenceRef(
        "lib/cepaf_gleam/src/cepaf_gleam/tools/ui_task_closure_bundle.gleam",
        "fn write_diagram",
      ),
      EvidenceRef(
        "lib/cepaf_gleam/src/cepaf_gleam/tools/ui_diagram_quality_gate.gleam",
        "validate_png_set_spread",
      ),
      EvidenceRef(
        "lib/cepaf_gleam/test/playwright/e2e_all_pages.spec.ts",
        "GET /api/v1/does_not_exist",
      ),
    ]
    "02-dashboard-rendering" -> [
      EvidenceRef(
        "lib/cepaf_gleam/src/cepaf_gleam/ui/wisp/router.gleam",
        "route_internal",
      ),
      EvidenceRef(
        "lib/cepaf_gleam/src/cepaf_gleam/ui/web/dashboard_views.gleam",
        "pub fn dashboard_view",
      ),
      EvidenceRef(
        "lib/cepaf_gleam/src/cepaf_gleam/ui/lustre/shell.gleam",
        "/static/shell-runtime.bundled.js?v=2026-05-24-csp2",
      ),
    ]
    "03-control-plane" -> [
      EvidenceRef(
        "lib/cepaf_gleam/src/cepaf_gleam/ui/wisp/router.gleam",
        "fn route_internal",
      ),
      EvidenceRef(
        "lib/cepaf_gleam/src/cepaf_gleam/ui/wisp/router.gleam",
        "fn route_html",
      ),
      EvidenceRef(
        "lib/cepaf_gleam/test/playwright/e2e_all_pages.spec.ts",
        "function expectedApiStatus",
      ),
    ]
    "04-fractal-clients" -> [
      EvidenceRef(
        "lib/cepaf_gleam/src/cepaf_gleam/ui/wisp/router.gleam",
        "/api/v1/pages",
      ),
      EvidenceRef(
        "lib/cepaf_gleam/src/cepaf_gleam/ui/web/dashboard_views.gleam",
        "L0-L7",
      ),
      EvidenceRef(
        "docs/architecture/FRACTAL_SYSTEM_VOICE_CHAT_OBSERVABILITY_MATRIX.md",
        "L0",
      ),
    ]
    "05-no-dummy-guardrails" -> [
      EvidenceRef(
        "lib/cepaf_gleam/test/playwright/e2e_all_pages.spec.ts",
        "function expectedApiStatus",
      ),
      EvidenceRef(
        "lib/cepaf_gleam/test/playwright/e2e_all_pages.spec.ts",
        "GET /api/v1/does_not_exist",
      ),
      EvidenceRef(
        "docs/architecture/UI_REPORT_QUALITY_GUARDRAIL_SPEC.md",
        "no-dummy",
      ),
    ]
    "06-code-organization" -> [
      EvidenceRef(
        "lib/cepaf_gleam/priv/web-build/src/shell-runtime.ts",
        "runtime active",
      ),
      EvidenceRef(
        "lib/cepaf_gleam/priv/web-build/package.json",
        "build:shell-runtime",
      ),
      EvidenceRef(
        "lib/cepaf_gleam/src/cepaf_gleam/ui/wisp/router.gleam",
        "route_html",
      ),
    ]
    _ -> []
  }
}

fn append_failures(
  failures: List(String),
  more_failures: List(String),
) -> List(String) {
  list.append(failures, more_failures)
}

fn bundle_slug() -> String {
  case string.split(bundle_dir(), "/") |> list.reverse {
    [slug, ..] -> slug
    [] -> ""
  }
}

fn require_at_least(
  failures: List(String),
  label: String,
  actual: Int,
  minimum: Int,
) -> List(String) {
  case actual >= minimum {
    True -> failures
    False -> [
      label
        <> " expected>="
        <> int.to_string(minimum)
        <> " actual="
        <> int.to_string(actual),
      ..failures
    ]
  }
}

fn require_at_most(
  failures: List(String),
  label: String,
  actual: Int,
  maximum: Int,
) -> List(String) {
  case actual <= maximum {
    True -> failures
    False -> [
      label
        <> " expected<="
        <> int.to_string(maximum)
        <> " actual="
        <> int.to_string(actual),
      ..failures
    ]
  }
}

fn require_tokens(
  failures: List(String),
  text: String,
  tokens: List(String),
) -> List(String) {
  tokens
  |> list.fold(failures, fn(acc, token) {
    case string.contains(text, token) {
      True -> acc
      False -> ["missing token " <> token, ..acc]
    }
  })
}

fn count_occurrences(haystack: String, needle: String) -> Int {
  case needle == "" {
    True -> 0
    False -> list.length(string.split(haystack, needle)) - 1
  }
}

fn unique_ints(values: List(Int)) -> List(Int) {
  values
  |> list.fold([], fn(acc, value) {
    case list.contains(acc, value) {
      True -> acc
      False -> [value, ..acc]
    }
  })
}

fn min_ints(values: List(Int), current: Int) -> Int {
  case values {
    [] -> current
    [first, ..rest] -> {
      let next = case first < current {
        True -> first
        False -> current
      }
      min_ints(rest, next)
    }
  }
}

fn max_ints(values: List(Int), current: Int) -> Int {
  case values {
    [] -> current
    [first, ..rest] -> {
      let next = case first > current {
        True -> first
        False -> current
      }
      max_ints(rest, next)
    }
  }
}

fn report_path() -> String {
  bundle_dir() <> "/diagram-quality-report.md"
}

fn report_markdown(results: List(ResultLine)) -> String {
  let rows =
    results
    |> list.map(fn(r) {
      "| "
      <> r.name
      <> " | "
      <> r.status
      <> " | "
      <> string.replace(r.detail, "|", "/")
      <> " |"
    })
    |> string.join("\n")

  let failed =
    results |> list.filter(fn(r) { r.status != "PASS" }) |> list.length
  let status = case failed {
    0 -> "PASS"
    _ -> "FAIL"
  }

  string.join(
    [
      "# C3I UI Report Quality Gate",
      "",
      "Generated: 2026-05-24",
      "",
      "Bundle directory: `" <> bundle_dir() <> "`",
      "",
      "Overall status: " <> status,
      "",
      "This gate prevents visually empty or low-information report bundles. It checks SVG structure, required semantic labels, semantic transmission score, contextual correctness score, visual design score, high contrast score, vector-text audit cells, Arial/system-font PNG rendering, fresh SVG-to-PNG pixel parity, arrow/link density, PNG dimensions, PNG byte size/spread, embedded PNG propagation, journal sections, source excerpts, analysis/deck content, manifest links, local link targets, email attachments, companion architecture-doc discoverability, web/runtime coverage, local rules coverage, STAMP references, skills alignment, agent/hook/webhook governance, and the pre-email proof gate.",
      "",
      "Parallel Gate Execution Model: `run_parallel_checks` spawns diagram, HTML, content, integrity, deep-evidence, and governance lanes and joins them through `collect_lane_results`. Each diagram row reports text nodes, vector cells, unique visible terms, numeric/status claims, evidence refs, `semantic_score`, `contextual_score`, `visual_design_score`, `contrast_score`, PNG bytes, `font_renderer=magick`, `contrast_mode=high`, and `fresh_render_match=true`. The quality report therefore carries proof rows for the governance spec, Allium spec, parallel gate implementation, FMEA/FEMA risk evidence, RETE-UL decision coverage, and ruliology coverage.",
      "",
      "Claim Contract Registry: every diagram must reconcile the same reader takeaway, claim, evidence, and risk across `journal.md`, `index.html`, `analysis.html`, `deck.html`, `email.md`, `links.json`, and SVG metadata.",
      "",
      claim_contract_registry_markdown(),
      "",
      "Report Aspect Coverage Registry: every report and analysis artifact must carry the same aspect-level decision value, evidence, and guardrail so usefulness is not confined to one file.",
      "",
      report_aspect_registry_markdown(),
      "",
      "| Artifact | Status | Detail |",
      "|---|---|---|",
      rows,
      "",
    ],
    "\n",
  )
}

fn report_aspect_registry_markdown() -> String {
  let rows =
    report_aspect_contracts()
    |> list.map(fn(contract) {
      let ReportAspectContract(name, decision_value, evidence, guardrail) =
        contract
      "| "
      <> name
      <> " | "
      <> decision_value
      <> " | "
      <> evidence
      <> " | "
      <> guardrail
      <> " |"
    })
    |> string.join("\n")

  string.join(
    [
      "| Aspect | Decision Value | Evidence | Guardrail |",
      "|---|---|---|---|",
      rows,
    ],
    "\n",
  )
}

fn claim_contract_registry_markdown() -> String {
  let rows =
    claim_contracts()
    |> list.map(fn(contract) {
      let ClaimContract(
        name,
        title,
        takeaway,
        claim,
        evidence,
        risk,
        _source_tokens,
      ) = contract
      "| "
      <> name
      <> " | "
      <> title
      <> " | "
      <> takeaway
      <> " | "
      <> claim
      <> " | "
      <> evidence
      <> " | "
      <> risk
      <> " |"
    })
    |> string.join("\n")

  string.join(
    [
      "| Diagram | Title | Reader Takeaway | Claim | Evidence | Risk If Wrong |",
      "|---|---|---|---|---|---|",
      rows,
    ],
    "\n",
  )
}

fn bool_string(value: Bool) -> String {
  case value {
    True -> "true"
    False -> "false"
  }
}
