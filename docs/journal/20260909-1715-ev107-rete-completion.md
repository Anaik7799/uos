# 20260909-1715 EV107 bounded forward-chaining completion

Observed UTC: 2026-09-09T17:13:15Z. #fractal-l0 #fractal-l5 #zk-adr #zero-muda

[Planning](http://nas-1.tail55d152.ts.net:4100/planning) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [Evidence](http://nas-1.tail55d152.ts.net:4100/files/docs/reviews/20260909-1715-ev107-rete-completion.json). Private JJ evidence; live publication is unverified.


## 1. Scope & Trigger

Continue all existing EV work using Gleam, OCaml or Mojo and no Bash. Repair the EV107 verifier that reported rule firings without applying static assertions. Complete this bounded component after independent review; the programme and whole-EV admission remain open.

## 2. Pre-State Assessment

The legacy function only counted matching rules. Repeated conditions could falsely shadow a distinct conjunction, and identical conditions incorrectly shadowed different assertions. Public cached consistency fields and unbounded input lists needed an explicit checked execution boundary.

## 3. Execution Detail

The Gleam engine now validates bounded raw input, checks conservative rule warnings and evaluates add-only rounds. Every static rule fires at most once. Assertions enter working memory without duplicating existing attribute facts; later rules can consume derived facts. Typed errors return no partial result on malformed input, resource exhaustion or conflicting advisory verdicts. The compatibility projection preserves the original supplied state on refusal. Conditions retain existential matching across facts, with no variable binding or same-fact join claim.

The independent OCaml model computes reflexive transitive graph reachability. It checks the actual compiled Gleam output for every four-node DAG mask, seed set and two rule orders. A separate reviewer rebuilt the candidate and checked additional cycles, derived comparisons, deduplication and refusal boundaries.

## 4. Root Cause Analysis

Counting matches was substituted for executing assertions. One-sided condition membership with equal lengths was mistaken for conjunction equivalence, and equal conditions were mistaken for equal consequences. The first test invocation selected the wrong working directory and found no tests; the unchanged artifact then ran in the package directory and exposed three real failures. The final runner names its two EUnit modules explicitly. An intermediate compile refused an unavailable result.then API; the pinned library provides result.try.

## 5. Fix Taxonomy

Semantic implementation, symmetric conjunction comparison, valid assertion fan-out, bounded checked execution, atomic refusal, explicit test discovery and independently evaluated finite reference evidence. No runtime service was replaced.

## 6. Patterns & Anti-Patterns Discovered

A successful process exit with no tests is not a passing suite. A count is not a materialized state transition. Gate agreement does not authorize effects. Conservative static warnings must not be described as a complete consistency proof. Working-directory, compiler and model limits belong in the evidence record.

## 7. Verification Matrix

| Observation | Result | Scope |
|---|---|---|
| Baseline immutable private build | 6 tests passed,3 failed | Missing assertions, incomplete chain, false condition shadow |
| Final native compilation | Passed without warnings | Five Gleam inputs and160 realized dependencies |
| Author EUnit suite | All23 tests passed | Five retained and18 new cases |
| Independent private replay |23 author tests and6 additional groups passed | Actual rebuilt candidate |
| OCaml reference comparison |2048 actual cases matched on both builds | Four-node DAGs, seeds and two orders |
| Model-reader controls |29 synthetic controls passed | Carrier integrity and bounded refusal, not runtime evidence |
| Canonical RETE completion | Attempt1 completed after fresh ACTIVE observation | Component task only |
| Full EV107 admission | Not established | Gospel/Z3, production and sovereign obligations remain |

## 8. Files Modified

Production rete_ul_verifier.gleam; new ev107_rete_closure_test.gleam, ev107_rete_runner.gleam, ev107_rete_projection.gleam; OCaml private staging helper. The independently authored OCaml reference has its own immutable revision. This journal and companion manifest preserve actual receipts, the failed baseline source and independent approval.

## 9. Architectural Observations

Gleam performs pure bounded knowledge-state transitions. OCaml supplies the independent relation model and evidence checks. Direct native erlexec and ocamlrun launch the tests and tooling. The reference corpus is finite and narrower than the complete rule language. Source/tool bindings do not establish an authenticated transitive release closure.

## 10. Remaining Gaps

Legacy builders remain unbounded interfaces. Pairwise rule warnings are conservative and incomplete. Full formal refinement, authenticated runtime input, actual effect authorization and existing synthetic HUD claims remain outside this repair. EV1 bootstrap and EV2 governance verification are active separately. No new EV number or admission was created.

## 11. Metrics Summary

One production repair task and one independent review task completed.23 author tests,6 independent groups and2048 reference cases overlap in scope and are not added into an assurance score.160 dependency artifacts were rechecked. New EV admissions: zero; policy ceiling:93.

## 12. STAMP & Constitutional Alignment

Materialized assertions address omitted conclusions. Typed validation and advisory-only outputs constrain unsafe conclusions. Repeated rounds address order-dependent timing; per-rule and work bounds constrain excessive duration. Source identity, Sa-plan attempts and workspace ownership remain separate from report-only risk observations and system admission authority.

## 13. Conclusion

The bounded static-assertion component is implemented, executed, independently reviewed and canonically completed. The existing all-EV programme continues with the admitted ceiling unchanged.

## Comprehensive verification checklist

<details><summary>Domain1 — Metadata and navigation</summary>

- [x] CHK-01-TIME — Host UTC and synchronized active observation retained.
- [x] CHK-02-TAIL — Full Tailnet links supplied; publication unverified.
- [x] CHK-03-FRACT — Applicable fractal tags supplied.
- [x] CHK-04-KM — Source, model and evidence linked.

</details>
<details><summary>Domain2 — Purity and storage</summary>

- [x] CHK-05-MUDA — New code uses Gleam and OCaml, without Bash.
- [ ] CHK-06-GRAPH — Fleet-wide dependency purity is not established here.
- [ ] CHK-07-DRIVE — No hardware operation or interlock test in this task.

</details>
<details><summary>Domain3 — Tests and mathematics</summary>

- [ ] CHK-08-C1C8 — Full release categories remain open.
- [ ] CHK-09-MATH — Finite reference checked; general refinement remains open.
- [ ] CHK-10-9MOD — Whole EV107 acceptance remains open.
- [x] CHK-11-REGR — Retained tests, negative controls and independent probes executed.

</details>
<details><summary>Domain4 — Runtime and observability</summary>

- [x] CHK-12-GLEAM — Actual compiled ERTS observations retained.
- [x] CHK-13-HERMES — Independent OCaml model and evidence processing executed.
- [ ] CHK-14-ZIGVM — Kernel acceptance outside this task.
- [ ] CHK-15-MAX — Inference acceptance outside this task.
- [ ] CHK-16-OTEL — No production trace correlation established.

</details>
<details><summary>Domain5 — Governance and VCS</summary>

- [ ] CHK-17-SOV — No whole-EV sovereign admission claimed.
- [x] CHK-18-JJ — Immutable standalone JJ source and sibling evidence.

</details>
<details><summary>Domain6 — Provenance</summary>

All failures remain evidence of failure. An empty test discovery and an unsupported API compile are not positive runtime evidence. The programme remains executing, and no admitted ceiling or historical record was rewritten.

</details>

[Previous stage](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20260909-1514-completed-mesh-components.md) · [Planning](http://nas-1.tail55d152.ts.net:4100/planning). UOS footer: component completed; whole-EV admission pending.
