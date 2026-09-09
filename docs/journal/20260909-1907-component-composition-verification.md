# 20260909-1907 Component composition verification

Observed UTC: 2026-09-09T19:52:07Z. #fractal-l0 #fractal-l5 #zk-adr #zero-muda

[Planning](http://nas-1.tail55d152.ts.net:4100/planning) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [Evidence](http://nas-1.tail55d152.ts.net:4100/files/docs/reviews/20260909-1907-component-composition-verification.json). Private candidate evidence; live publication is unverified.


## 1. Scope & Trigger

Continue the existing EV programme with Gleam and OCaml and no Bash. Verify that the independently repaired graph, forward-chaining, remediation and payload-digest components work together at one immutable candidate.

## 2. Pre-State Assessment

The component repairs had separate observed tests and independent reviews. Moving shared dependency builds and shell-launching native OCaml recipes prevented assuming that a combined package invocation would reproduce those observations.

## 3. Execution Detail

The staging driver checks thirteen immutable source pairs and copies a fixed inventory of168 reviewed dependency artifacts. Its explicit Gleam runner selects five EUnit modules concurrently. The digest recipe produces raw OCaml bytecode with -without-runtime and invokes it through native ocamlrun. The independent reviewer recreated staging, checked the actual built artifacts and replayed the bound tests.

## 4. Root Cause Analysis

Separate passing components did not establish composition. Initial dependency-path validation refused valid BEAM basenames containing @; the correction permits that character only in private dependency paths drawn from the fixed approved inventory. Sandbox ptrace refusals were preserved before fresh permitted traces were taken. The independent report preserves its first parser refusal for zero-duration EUnit formatting.

## 5. Fix Taxonomy

Immutable source parity, isolated dependency staging, explicit nonempty test discovery, raw bytecode launch, observed process tracing and independent composition review. No production process was replaced.

## 6. Patterns & Anti-Patterns Discovered

Current shared build bytes cannot silently substitute for reviewed dependency bytes. A successful build trace observes executed paths; it does not prove all possible transitive executions or authenticate the producer. A test-output parser must accept the actual documented output variants without accepting empty discovery.

## 7. Verification Matrix

| Observation | Result | Scope |
|---|---|---|
| Candidate parity |13 files equal prior reviewed revisions | Production and tests selected by the driver |
| Private dependencies |168 artifacts equal the approved inventory | Fixed cooperative cache |
| Gleam composition |53 unique tests passed | Five explicitly selected concurrent modules |
| OCaml digest |18 named cases passed | Bound raw bytecode artifact |
| Build traces |21 successful ELF execs; one failed lookup | Observed compile invocations only |
| Independent controls |19 path controls and3 driver refusals passed | Selected path grammar and invocation guards |
| Independent REVIEW |Canonically completed attempt1 | Exact79a4 bounded composition |
| Whole EV admission |Not established | Programme remains executing |

## 8. Files Modified

The source change adds tools/ev_component_composition.ml and test/ev_component_composition_runner.gleam. All thirteen selected production/test files retain their reviewed bytes. This manifest and journal preserve source bindings, compiler/runtime records, traces, independent approval, completion and failed attempts.

## 9. Architectural Observations

Gleam owns pure control-state transitions; OCaml supplies digest checks and evidence processing. Tests run on actual native ERTS and ocamlrun. Existing automation archives and interpreter support remain declared dependencies, without an authenticated dynamic-library or full release closure claim.

## 10. Remaining Gaps

This does not establish global-suite success, live music playback, UI behavior, full EV101/104/107 acceptance, hostile-filesystem confinement or deployment readiness. EV1 Bootstrap retains lineage and sovereign acceptance gaps. EV2 evidence capture and EV86 music routes continue under separate tasks. No new EV number or admission was created.

## 11. Metrics Summary

Thirteen source pairs,168 private dependencies,53 Gleam tests,18 OCaml cases and22 independent controls were checked. The scopes overlap and are not combined into an assurance score. New EV admissions: zero; policy ceiling:93.

## 12. STAMP & Constitutional Alignment

Explicit source/dependency selection prevents substitution; nonempty test records constrain omitted execution evidence. Native deadlines and private stages bound these observations. Sa-plan task authority, workspace ownership and report-only risk observations remain distinct from runtime deployment and sovereign admission authority.

## 13. Conclusion

The selected component composition is executed and independently verified at79a4. The all-EV programme remains active with its admission ceiling unchanged.

## Comprehensive verification checklist

<details><summary>Domain1 — Metadata and navigation</summary>

- [x] CHK-01-TIME — Host UTC and fresh active observation retained.
- [x] CHK-02-TAIL — Full Tailnet links supplied; publication unverified.
- [x] CHK-03-FRACT — Fractal tags supplied.
- [x] CHK-04-KM — Immutable source and evidence references supplied.

</details>
<details><summary>Domain2 — Purity and storage</summary>

- [x] CHK-05-MUDA — New code uses Gleam and OCaml without Bash.
- [ ] CHK-06-GRAPH — Fleet-wide dependency purity remains outside this observation.
- [ ] CHK-07-DRIVE — No hardware interlock test in this task.

</details>
<details><summary>Domain3 — Tests and mathematics</summary>

- [ ] CHK-08-C1C8 — Full release categories remain open.
- [ ] CHK-09-MATH — General formal refinement remains open.
- [ ] CHK-10-9MOD — Whole-EV acceptance remains open.
- [x] CHK-11-REGR — Retained runtime and independent controls executed.

</details>
<details><summary>Domain4 — Runtime and observability</summary>

- [x] CHK-12-GLEAM — Actual ERTS test observations retained.
- [x] CHK-13-HERMES — Actual native OCaml bytecode tests retained.
- [ ] CHK-14-ZIGVM — Kernel acceptance outside this task.
- [ ] CHK-15-MAX — Inference acceptance outside this task.
- [ ] CHK-16-OTEL — No production trace correlation established.

</details>
<details><summary>Domain5 — Governance and VCS</summary>

- [ ] CHK-17-SOV — No whole-EV sovereign admission claimed.
- [x] CHK-18-JJ — Immutable standalone JJ source and independent evidence.

</details>
<details><summary>Domain6 — Provenance</summary>

Failed staging, sandbox tracing and parser attempts remain failures. A completed independent review is bound to its exact scope and candidate; it does not grant system admission.

</details>

[Previous component](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20260909-1715-ev107-rete-completion.md) · [Planning](http://nas-1.tail55d152.ts.net:4100/planning). UOS footer: bounded composition verified; whole-EV admission pending.
