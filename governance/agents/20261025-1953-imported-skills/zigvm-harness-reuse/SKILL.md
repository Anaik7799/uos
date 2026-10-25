---
name: zigvm-harness-reuse
description: Use when implementing ANY feature in the Hermes parity harness — a new module, test runner, report/dashboard, checker, evidence path, or capability — BEFORE writing new code. The prior zigvm harness likely already solved the same concern.
---

# zigvm harness reuse (R14)

The Hermes harness and the prior **zigvm harness** are the same kind of system:
a differential-parity engine that byte-compares a candidate against a
frozen/pinned oracle, records evidence append-only, and gates on determinacy.
Before implementing a harness feature, **find its zigvm counterpart and reuse or
mirror it — never reinvent.** This is rule R14.

## The method (do this first, every time)

1. **Search the zigvm harness for the concern** before writing anything:
   ```
   grep -nE "^module [A-Z]" zigvm_legacy/framework/zigvm_harness.ml          # the ~50 framework modules it composes
   grep -niE "<concern>" zigvm_legacy/framework/zigvm_harness.ml zigvm_legacy/framework/*.ml  # e.g. runner, report, replay, determinac, oracle
   ```
   The framework sources are the `Zigvm_harness_support` modules under `zigvm_legacy/framework/`
   (`db.ml`, `suite_runner.ml`, `slo_report.ml`, `decision_frame.ml`, `stan_*.ml`,
   `rete*.ml`, `conformance.ml`, `bench.ml`, `mcp_server.ml`, …).
2. **Consult the map:** `docs/hermes/zigvm-overlap-map.md` records the
   correspondence and the action (reuse / mirror / done / differ).
3. **Decide reuse vs mirror:**
   - **Reuse** (depend on the shared module) when it is domain-neutral and
     cleanly buildable from the tracked harness.
   - **Mirror** (adopt its structure, naming, algebra into `modules/hermes_harness/`)
     when a direct dependency is inappropriate — the distinct evidence-vs-runtime
     fractal (R9) or the untracked-legacy boundary. Mirror so a later
     consolidation is mechanical.
4. **Carry the proven patterns** (below) into the implementation.
5. **Update the overlap map** with the new entry.

## Proven patterns to carry (from zigvm)

- **Differential byte-EQ vs a pinned oracle.** Compare the candidate against a
  digest-pinned reference after canonical normalization; equality is the verdict.
- **Record the attempt honestly.** A divergence is a successful measurement, not
  a suite failure — record it, never elide it.
- **Determinacy gate (GATE-DETERMINACY).** Run twice (or under fixed seeds),
  byte-compare; any non-reproducible run is a defect fixed *constructively*,
  never by re-seeding or widening to hide it.
- **The proven-not-differential trap.** Always prove a passing test actually
  exercises the difference — e.g. a different recorded input must yield a
  different output. A test that can pass while exercising nothing is worse than
  no test. (This is why the replay test varies the recording, and why the
  message_hygiene surrogate boundary must be handled, not assumed.)

## Red flags — STOP

- Writing a new module for a harness concern (runner, report, evidence, replay,
  diagnosis, inference) **before** grepping the zigvm harness for it.
- "Hermes is different, so I'll build fresh" — the *domain* differs (Hermes
  capabilities vs Erlang/OTP); the *framework* overlaps. Reuse the framework.
- A new feature with no entry in the overlap map.

## Boundary (R9)

Reuse must not conflate the two fractals: `hermes_harness/` is fractal over
evidence (L0 product → L6 receipt); zigvm is fractal over runtime structure. Keep
the tracked harness self-contained — mirror the shape rather than cross-depend on
untracked legacy — but make the shapes match so overlap is maximal.

## Cross-references

- Rule **R14** (`docs/hermes/mandatory-rules.md`).
- The map: `docs/hermes/zigvm-overlap-map.md`.
- Applied already: the deterministic-replay track (`replay_executor`) mirrors
  zigvm's recorded/pinned-oracle execution and determinacy discipline.
