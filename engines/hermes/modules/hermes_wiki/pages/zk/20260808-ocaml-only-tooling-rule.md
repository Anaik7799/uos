---
migrated_from: docs/zk/20260808-ocaml-only-tooling-rule.md (zigvm-era tree, authored for Hermes)
---
# Architectural Decision: Harness Tooling Is OCaml, Enforced by a Guard

**Date:** August 8, 2026
**Topic:** Language boundary for harness tooling, and its enforcement

## Decision
Every tool in this workspace is written in OCaml. Python is never used to
implement harness tooling — not as a program, and not as a throwaway
`python3 - <<EOF` helper for editing files or parsing another tool's output.
The rule is enforced by `hermes_harness/ocaml_only_guard.ml`, exercised against
the real repository by `test_ocaml_only_guard.exe`, so a violation fails the
test suite rather than a review.

## Rationale
- **Unbuilt code is unverifiable code.** A shell heredoc is outside the build:
  nothing type-checks it, no test covers it, and it leaves no reviewable
  artifact. In a project whose entire premise is that only checked evidence
  counts, tooling that cannot itself be checked is a contradiction.
- **It had already produced a wrong answer.** The inline parser of the
  `bisect_ppx` coverage file mis-attributed uncovered points, and there was no
  test to catch it. As `coverage_points.ml` the same logic validates its header
  and every length it reads, and fails loudly instead of reporting a plausible
  wrong number.
- **A convention that is only written down decays.** The linter was already
  pure OCaml while the workflow around it was not, and that gap was invisible
  from the artifact alone. The guard closes it at the only place that cannot be
  skipped.
- **The rule is about authorship, not vocabulary.** Python is the language of
  the frozen reference. The guard therefore exempts `external/`, the inventory
  fixtures that stand in for it, the vendored trees the root dune already
  declares `data_only_dirs`, documentation prose, and OCaml that merely names
  the interpreter — which is how `bootstrap.ml` keeps probing for `python3` as
  a readiness check. Anything else needs an entry in `declared_exceptions` with
  a reason.

## Consequences
- Analysis that would previously have been a heredoc becomes a small OCaml
  executable in the dune project: built, typed, and testable.
- The exception list is the audit trail. Adding Python tooling is possible, but
  only by writing down why, which is the point.
- Detection uses substring containment rather than word boundaries, because an
  interpreter appears as `python`, `python3` and `python3.11`. Over-matching is
  the safe direction: a false positive is resolved by declaring it, a false
  negative is a silent hole.

## Related
- `docs/journal/20260808-ocaml-only-toolchain-hard-control.md`
- `docs/zk/20260807-hermes-fractal-compliance.md` — the same instinct applied to
  topology: constrain evolution structurally rather than by convention.
