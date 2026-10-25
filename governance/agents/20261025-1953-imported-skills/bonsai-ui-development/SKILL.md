---
name: bonsai-ui-development
description: Design, implement, review, and extend Bonsai web UI in this repository — the incremental OCaml UI framework behind harness/ui_web. Use for any frontend component, state model, collection rendering, effect or RPC wiring, performance question, migration from older Bonsai APIs, or review of authored Bonsai code. Enforces strong typing, the domain-first order of work, and the BONSAI-* lint rules.
---

# Bonsai UI development

Bonsai is an **incremental** framework: you build a dependency graph once and
only the parts whose inputs changed recompute. Every rule below follows from
that one fact. Code that consumes more than it needs pays the framework's cost
and forfeits its benefit.

Pin of record: `v0.18~preview.130.106+341`. When public material and the
installed interface disagree, the **interface wins**.

## Required reads

| Document | What it gives you |
|---|---|
| `docs/bonsai/BONSAI_ONTOLOGY.md` | vocabulary, layers, the domain-driven decomposition |
| `docs/bonsai/BONSAI_ALGEBRA.md` | signature, laws, frame dynamics, cost model |
| `docs/bonsai/BONSAI_GUIDE.md` | feature surface, patterns, anti-patterns, extension |
| `docs/bonsai/BONSAI_SOP.md` | the procedure, the CTRL-BONSAI-UI safety packet |

## The order of work — non-negotiable

1. **Domain first.** Types and a pure total `step : model -> action -> model`,
   with no Bonsai types in sight.
2. **Property-test `step`.** It is pure and total, so this is cheap and catches
   the most.
3. **Wire** with the weakest state shape that works: `state` → `state_machine`
   → `state_machine_with_input` → `actor` → `wrap`.
4. **Derive** named read-values; give each view fragment the value it reads.
5. **Lint and laws**, then **runtime-verify** through typed OCaml Playwright.

Writing the view first produces a model shaped by the markup. That is how state
explosion happens, and it is the origin of every finding in the repository
today.

## Strong typing is the mechanism

| Requirement | Failure it prevents |
|---|---|
| model is a record or variant, never loose primitives | two fields disagreeing |
| enumerations are variants, never strings | a typo becoming a silent no-op |
| numbers are numbers, never numeric strings | parse-and-swallow on every read |
| bundles are records or heterogeneous tuples, never positional lists | a silent behavioural swap on reorder |
| absence is `option`; inactivity is `Computation_status.t` | an ignored inactive branch |

If the compiler needs a catch-all arm, the encoding is wrong — fix the
encoding, not the arm.

## Applicative, not monadic

There is deliberately no `bind`. If you want the graph's *shape* to depend on a
value, the answer is `match%sub`, `enum`, `assoc`, `scope_model` or `Memo` —
never a bind, and never a rebuild. Looking for a bind is the single most common
wrong expectation.

## Mechanised rules

`--check-lint` runs these over authored OCaml; they are `Info` severity today
and promote to warnings when the frontend refactor lands.

| Rule | Fires on |
|---|---|
| `BONSAI-STATE-EXPLOSION` | more than eight separate states in one file |
| `BONSAI-POSITIONAL-BUNDLE` | bundling state into a positional list |
| `BONSAI-STRINGLY-STATE` | a state initialised to a numeric string |
| `BONSAI-MONOLITHIC-MAP` | a map spanning more than 120 lines |

## Do not

- Perform effects inside `apply_action` — schedule them through the context.
- Rebuild a list of components per change — use `assoc` over a domain-keyed map.
- Use `Clock.Expert.now` for display — use `approx_now ~tick_every`.
- Fetch on change without ordering — use `Edge.Poll`, which guarantees the
  last-scheduled result wins regardless of completion order.
- Reach for `Expert.*`, `Incr.compute` or `peek` without a comment naming what
  was measured and why the ordinary combinator was insufficient.
- Cite a rendered view as gate evidence. The UI can only misreport; the gate
  decides.

## Composes with

`skills/algebra-driven-ocaml` (the authored-OCaml doctrine),
`skills/mobile-first-adaptive-ui` (the five window classes),
`skills/ocaml-playwright-control` (the only runtime-appearance oracle),
`skills/stpa-safety-protocol` (CTRL-BONSAI-UI is an evidence-path controller).
