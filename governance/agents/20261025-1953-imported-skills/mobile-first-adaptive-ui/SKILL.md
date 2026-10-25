---
name: mobile-first-adaptive-ui
description: Use when designing, implementing, reviewing, or verifying responsive/adaptive ZigVM web UI across phones, tablets, desktops, and large monitors, especially Bonsai/Virtual_dom frontend work served by Dream.
---

# Mobile-First Adaptive UI

Read `docs/PLAYWRIGHT_OCAML_ONTOLOGY.md` and use
`skills/ocaml-playwright-control/SKILL.md` for runtime verification.

## Window Algebra

- compact: `[0,600)`; one pane, stacked controls
- medium: `[600,840)`; one pane, wider flow
- expanded: `[840,1200)`; primary plus supporting pane
- large: `[1200,1600)`; denser split workspace
- extra-large: `[1600,infinity)`; bounded content measure, expanded graph

Base CSS is compact. Add capability with `@media(min-width:...)`; do not undo a
desktop layout with width `max-width` queries. Reflow, reveal, or replace
components at a class boundary instead of scaling the same composition.

## Binding Rules

- Keep all authored UI in OCaml/Bonsai; JavaScript is generated output only.
- Keep browser database access impossible; Dream uses the OCaml `Db` actor.
- Preserve safe-area insets, dynamic text, portrait/landscape, keyboard,
  pointer, and touch input.
- Every interactive target is at least 44x44 CSS px with visible focus.
- Use stable grids, aspect ratios, min/max constraints, wrapping, and bounded
  panes; no horizontal overflow or incoherent overlap.
- Support reduced motion, forced colors, light/dark schemes, and hover only
  behind `@media(hover:hover)`.
- Use Apple for clarity/familiarity/safe areas, Google for window classes and
  pane reflow, Meta for cross-device consistency/accessibility, and Microsoft
  for breakpoints/input/4px rhythm. Adapt principles; do not clone branding.

## Workflow

1. State the carrier, breakpoints, pane topology, control invariants, and
   longest-content cases.
2. Write a failing contract or runtime law.
3. Implement compact first, then ascending `min-width` enhancements.
4. Run the OCaml Playwright matrix at 390x844, 768x1024, 1440x900, and
   1920x1080.
5. Reject any overflow, target below 44x44, pane-relation error, missing tab,
   console/page error, or blank screenshot.
6. Inspect the generated PNGs and run the canonical gate.

## Laws

Breakpoint classes are total and disjoint. Layout is width-bounded. Controls
remain operable. Compact/medium panes stack; expanded and larger panes split.
Content truth is invariant across classes. A failed observation never becomes
PASS through retry or omission.
