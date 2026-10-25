---
name: ui-report-quality
description: Validate C3I UI closure/report bundles before publication or email. Use when a task produces journal.md, analysis.html, deck.html, diagrams, PNG/SVG renders, links.json, email.md, or asks to prove content quality. Enforces Gleam-only report generation and `ui_report_quality_gate`.
---

# UI Report Quality

## Trigger

Use this skill for UI closure packs, page-generation reports, dashboard reports, AG-UI/A2UI reports, slide decks, diagram bundles, and any email containing generated UI analysis artifacts.

## Procedure

1. Generate or refresh the bundle with the Gleam generator.
2. Run `cd lib/cepaf_gleam && gleam run -m cepaf_gleam/tools/ui_report_quality_gate`.
   For a non-default bundle, set `C3I_UI_REPORT_DIR=/home/an/dev/ver/c3i/docs/journal/<bundle>` before running the gate.
3. Confirm the gate reports PASS before email or closure claims.
4. Inspect the generated `diagram-quality-report.md`; it must include `quality report write | PASS`, and it must be included in the email attachments. Use the absolute attachment paths listed in `email.md`.
5. Confirm every diagram row records `fresh_render_match=true`, `semantic_score=`, `contextual_score=`, `visual_design_score=`, `vector_cells=`, `unique_terms=`, and `evidence_refs=`. This proves semantic transmission, contextual correctness, readable PNG text survival, visual design score, and that the PNG is tied to the current SVG.
6. Confirm the parallel gate lanes cover diagrams, HTML embeddings, content files, integrity files, deep evidence, and governance surfaces. Treat a lane timeout as a hard failure.
7. Verify current web/runtime evidence when the server is running:
   - `/dashboard`
   - `/api/v1/pages`
   - `/ag-ui/health`
   - `/ag-ui/events`
   - shell runtime static asset
   - known no-dummy routes: federation 503, health_grid 501, unknown API 404.
8. Treat every architecture diagram as a hypothesis. Validate it against reality with observability tools, distributed tracing, infrastructure-as-code, live probes, recorded probes, and current source evidence before describing it as current.
9. Confirm every major conclusion has a claim-evidence tuple and that captions include reader takeaway, Claim, Evidence, Source, Risk, and Quality.
10. Confirm rules, STAMP, skills, agents, hooks, data path, control plane, fractal clients, source excerpts, startup/logging, and observability are present in the journal and HTML.
11. Confirm FMEA/FEMA risk evidence includes S,O,D,RPN, RPN_coverage, and FEMA response notes.
12. Confirm RETE-UL and ruliology evidence includes RETEULDomains, TotalRETERules, RETERuleSpace, the 15-dimensional rulial space, raster text survival, source evidence refs, and the P0->P1->P2->P3 production path.
13. Confirm `docs/architecture/UI_REPORT_QUALITY_GUARDRAIL_SPEC.md` and `specs/allium/ui_report_quality_gate.allium` are current, linked, and included in the email bundle.

## Hard Stops

- Do not send email if `ui_report_quality_gate` fails.
- Do not treat image existence as image quality.
- Do not accept textless PNGs; require vector-text cells, source evidence refs, and fresh render parity.
- Do not accept token-dense but low-information content; require semantic transmission, contextual correctness, visual design score, claim-evidence tuples, and reality validation.
- Do not use Python, Node, or ad hoc shell scripts for report validation; use Gleam gates.
- Do not claim a live source is successful unless its current status check passed.
- Do not omit FMEA/FEMA, RETE-UL, ruliology, AOR, STAMP, or Allium evidence from a UI closure pack.
- Do not generate, name, or publish report bundles without the mandatory `YYYYMMDD-HHSS-` timestamp prefix (`contracts/rules/timestamp-mandate.md`).

## Continuous Use Standard

Apply this five-level standard on every report-producing task:

1. One-line rule: every generated artifact must be current, source-backed, useful, visually informative, cross-artifact consistent, and gate-verified.
2. Core checklist: validate reality, reject low-information output, require Claim/Evidence/Source/Risk/Quality, cover all governance/runtime/report aspects, and block email on gate failure.
3. Operating procedure: generate with Gleam, verify runtime evidence, check all artifacts, prove visual readability, reconcile claim/report-aspect contracts, and run `ui_report_quality_gate`.
4. Quality gates: prove reality, information value, no-dummy truth, visual quality, governance parity, FMEA/FEMA, RETE-UL/ruliology, coverage math, fractal clients, and delivery readiness.
5. Permanent standard: artifact existence, image dimensions, word count, and attachment count are not quality proof; the artifact must transmit verified system knowledge.
