# 03 — Resolve a DIVERGENT result

A compare printed `DIVERGENT`. **This is a successful measurement.** Your job
is to classify it correctly and act — never to make it disappear.

## The decision tree (follow in order; stop at the first match)

### Q1. Is the candidate missing or computing the field differently?

CHECK: Read the diff the compare printed. Open the frozen source and find the
exact lines that produce the differing field.

- **YES (the usual case — a real candidate gap):**
  1. Fix `hermes_harness/⟨CANDIDATE⟩.ml` faithfully from the frozen source —
     translate what the reference DOES, not what seems better.
  2. Add/extend a unit test in `test_⟨CANDIDATE⟩.ml` reproducing the exact
     input that diverged. RED first, then GREEN.
  3. Re-run `dune exec hermes_harness/compare_reference_traces.exe`.
  VERIFY: the scenario is VERIFIED **because the values now match** — read the
  values, don't just read the verdict.
  IF the fix cannot land now: leave the divergence recorded. An honest
  DIVERGENT is a correct final state for the day.

### Q2. Only if Q1 was NO: is the field genuinely run-varying on BOTH sides?

TEST, don't assume: run the capture twice; run the candidate twice. The field
qualifies as volatile ONLY if it changes between identical runs on both sides
(timestamp, random id, session id).

- A field that is a **deterministic function of the input** (e.g.
  `total_tokens = prompt + completion`) is **NOT volatile** — eliding it would
  permanently blind the suite to wrong values. That is hazard **HZ-NRM-01**,
  the exact failure this harness exists to prevent.
- **YES, proven volatile on both sides:** add it to the normalizer's volatile
  set, note that this invalidates existing fixture digests BY DESIGN, re-capture,
  and record the justification in the commit message.

### Q3. Only if Q1 and Q2 were NO: is the scenario comparing against the wrong reference profile?

Example (L-04): the generic reference transport ignores `reasoning_config`;
comparing an OpenRouter-profile candidate against it manufactures a divergence
that is a profile mismatch, not a defect.

- **YES:** exclude the scenario from THAT corpus, write the reason next to the
  exclusion, and (if possible) re-add it against the right profile.
- **NO:** you have exhausted the tree → **STOP — jidoka.** Report the
  divergence verbatim with your Q1–Q3 evidence. Do not improvise a fourth
  category.

## Absolute prohibitions while resolving

| Temptation | Why it is forbidden |
|---|---|
| Add the field to the volatile list "to get green" | Turns off the sensor because it detected something (HZ-NRM-01) |
| Trim the comparison schema to fields both sides share | The reference schema IS the contract; the intersection hides exactly the gaps we hunt |
| Hand-edit the committed fixture | Fixtures are re-digested on load; the edit is refused (HZ-FIX-01) — and attempting it voids trust |
| Delete or skip the failing scenario | Hiding a real gap; only Q3 permits exclusion, with the reason recorded |
| Patch the frozen reference | The reference is frozen. Full stop. |
| Tune the candidate until green without reading the frozen source | You'd encode the fixture, not the behavior — the next input diverges again |

## Recording the outcome

Whatever branch you took, the result must be visible:

- Q1 fixed → new unit test + VERIFIED compare; mention the root cause in the
  commit message.
- Q1 deferred → the DIVERGENT stays in the summary; add one line to
  `docs/hermes/HANDOVER.md` naming the gap.
- Q2 → commit message carries the volatility proof (two-run evidence).
- Q3 → the exclusion comment carries the profile reason (cite L-04).
