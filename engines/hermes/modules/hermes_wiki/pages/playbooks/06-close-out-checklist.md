# 06 — Close-out checklist (after a slice/feature lands)

Run this list top to bottom. Each row is independent; do them all.

| # | Action | VERIFY |
|---|---|---|
| 1 | Update `parity_dashboard.ml` KPI expectations (verified count, covered_slices, families_verified) | `dune exec hermes_harness/test_*` for the dashboard + visual check of the KPI table |
| 2 | Update `docs/hermes/declarative-configuration.md` if the mechanism's shape changed; refresh any quoted live output (trajectory/satisfied counts) | quoted output matches a fresh `auto_converge` run |
| 3 | Update `docs/hermes/HANDOVER.md`: state, counts, named gaps, next frontier | counts match the fresh compare summary |
| 4 | Journal: if the session produced a learning (a new L-xx) or followed a user directive worth recording verbatim, append to `docs/hermes/journal/` | file exists, linked from HANDOVER if significant |
| 5 | Ontology/atlas: if a NEW module landed, add its `fractal_ontology.ml` entry (level, algebra, all aspects) + atlas edges | `dune exec hermes_harness/test_fractal_ontology.exe` |
| 6 | zigvm overlap map: if a NEW harness concern was implemented, record the reuse/mirror decision in `docs/hermes/zigvm-overlap-map.md` (R14) | entry present |
| 7 | Full battery: compare + test_parity_compare + test_reference_capture + auto_converge + the slice's own tests | all green, exit 0 |
| 8 | Commit: one feature per commit; message `feat:`/`fix:`/`docs:` + what the evidence now shows; NEVER bulk-stage untracked legacy files — `git add` only the files you touched | `git status` shows no accidental staging |

## Commit message pattern

```
feat: <slice> VERIFIED — <one-line what the differential now proves>

- <the essential moves, 3-6 bullets>
- suites: compare N/N, test_parity_compare P/0, capture Q/0
```

## What NOT to close out

- Do not update dashboard counts for evidence that does not exist yet (R10 —
  the dashboard follows the store, never leads it).
- Do not mark a deferred divergence as done in HANDOVER — name it as a gap.
- Do not delete scratch/probe files that document how a probe was done if the
  journal references them; move the knowledge into the journal first.
