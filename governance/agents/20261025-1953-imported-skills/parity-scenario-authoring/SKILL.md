---
name: parity-scenario-authoring
description: Use when adding or authoring a scenario in the Hermes parity corpus, implementing an OCaml candidate against the frozen reference, or resolving a DIVERGENT or BLOCKED parity result — especially under pressure to reach green before broadening the corpus.
---

# Parity Scenario Authoring

The harness exists to find where the candidate differs from the frozen
reference. **Green is a proxy for "the candidate conforms to the reference."**
Any move that shifts the proxy without moving conformance is a regression
disguised as progress — and it spends the whole suite's trust to do it. An
honest 99% with a named gap is worth more than a fabricated 100%.

The single foundational rule: **the comparison schema is the reference
contract.** Project the candidate to the reference's schema, not to the
intersection of what both produce. A field the candidate lacks must **diverge**
— never be trimmed away (R10).

## Mandatory: this toolchain is OCaml, end to end

The candidate is OCaml. The reference is Python and is *run*, never
reimplemented in the harness, via the declared adapter. No Python tooling, no
`python3 - <<EOF` to shape a fixture.

## The workflow — do these in order

1. **Probe the frozen reference first. Never guess its output.** Capture the
   reference's *actual* output for the input into a digest-pinned fixture
   (`capture_reference_traces`), through the declared adapter. Writing the
   "expected" JSON by hand from what you believe the reference does is
   fabricating the thing you are measuring against — worse than having no
   reference (HZ-FIX-01).

2. **Implement the candidate faithfully from the frozen source.** Read what the
   reference actually does and reproduce it. Never tune the candidate to match a
   guess, and never tune it to pass. If it touches a `.mli` that carries a
   Gospel contract, re-lint it (`writing-gospel-specifications`).

3. **Let genuine gaps surface as divergences.** A divergence is a *successful
   measurement*, not a suite failure. Record it honestly. The corpus reporting
   "2/4, two real gaps" is the harness working.

## Resolving a DIVERGENT result — the decision tree

- **A real candidate gap** (the candidate is missing or wrong): fix the
  candidate faithfully from the frozen source. This is the default and usually
  small. Re-run and confirm it passes *because the values are equal*, not
  because they were ignored.
- **Genuinely run-varying noise** (timestamp, random id, session id): only then
  declare the path volatile. Test it: is the field nondeterministic on *both*
  sides? A field that is a deterministic function of the input (e.g.
  `total_tokens = prompt + completion`) is **not** volatile — eliding it
  redefines "volatile" to mean "unimplemented" and permanently blinds the suite
  to a *wrong* value, not just a missing one. Widening the volatile set
  invalidates existing fixture digests by design (HZ-NRM-01).
- **An unfair scenario** (the candidate is being compared against the wrong
  reference profile): exclude it, and say why. The generic reference transport
  ignores `reasoning_config` and treats `timeout` as a client param the
  candidate keeps out of the body; comparing the OpenRouter candidate against it
  manufactures divergences that reflect a profile mismatch, not a defect (L-04).
  Probe each scenario against the *right* reference profile before adding it.
- **Never**: elide a real field to pass; trim the schema to the intersection;
  hand-edit a committed fixture; delete or skip the failing scenario; or alter
  the frozen reference to flatter the candidate.

## Rationalizations — and why each is wrong

| Rationalization | Reality |
|---|---|
| "Just add the field to the elision list to get green." | The normalizer removes *non-determinism*. A deterministic field is not volatile; eliding it is turning off the sensor because it detected something. **HZ-NRM-01 — the H-1 realisation this whole system exists to prevent.** |
| "It's one field, and the deadline…" | Green is a proxy for conformance; a manufactured green hides one field *and* every future regression in it. An honest 99% with a named gap beats a fake 100%. |
| "I'll write the expected output from what I know the reference does." | Guessing the reference is not measuring it. Capture its actual output; a fabricated reference is worse than none (HZ-FIX-01). |
| "Trim the comparison to the fields we implement." | The schema is the reference contract; the intersection hides exactly the gaps you are here to find. |
| "Hand-edit the fixture so it matches." | Fixtures are re-digested on load; an edited trace is refused (HZ-FIX-01). |
| "This scenario always diverges — just exclude it." | Exclude only when it compares against the *wrong reference profile* (L-04), and record the reason. Excluding a real gap is hiding it. |

## Red flags — STOP

- Reaching for the normalizer or the volatile list to clear a divergence.
- Writing "expected" output by hand instead of capturing it from the reference.
- Editing a committed fixture.
- "Get to green" as the goal, instead of "conform to the reference."
- Adding a scenario without probing the reference first.

## Worked example — the `decode.usage` divergence

The candidate's `usage` lacks `total_tokens`; the reference includes it.

- **Right:** read the frozen `normalize_response`, see how it derives
  `total_tokens`, implement it in `Openrouter_transport` faithfully, re-lint
  `openrouter_transport.mli`. If it genuinely cannot land now, leave it as the
  real divergence it is — the corpus already reports `2/4` honestly.
- **Wrong:** add `usage.total_tokens` to the volatile set. That is HZ-NRM-01;
  the countermeasure is to *narrow* the volatile set, never widen it to pass.

## Cross-references

- Rule **R10**: only L4–L6 differential evidence grants parity.
- `Fractal_diagnostic` hazards **HZ-NRM-01** (over-elision), **HZ-FIX-01/02**
  (fixture integrity); `Fractal_countermeasures` for each.
- Learnings **L-04** (the profile boundary) in
  `docs/hermes/journal/2026-08-08-session-learnings.md`.
