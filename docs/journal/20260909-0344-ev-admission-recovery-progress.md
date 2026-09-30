# EV admission recovery — in progress

Observed: 2026-09-09T03:33:44Z. Sa-plan: `uos/ev-admission/20260909-0210`, task `PROGRAM`, worker `codex-ev-admission-01a08017`, attempt 1.
Tags: #fractal-l0 #fractal-l3 #fractal-l4 #zk-adr #zero-muda #tailscale-web #checklist-nav

Navigation: [Cockpit](http://nas-1.tail55d152.ts.net:4100/) · [Planning](http://nas-1.tail55d152.ts.net:4100/planning) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk).
This is an isolated candidate artifact; publication and system admission have not occurred.

## 1. Scope & Trigger

The operator requested completion and admission of all existing EV01–109. This ongoing programme repairs implementations and reconstructs candidate-bound evidence. It does not mint an EV or reinterpret a historical passing count as current evidence. The policy ceiling remains EV93; EV94–109 remain NOT_ADMITTED.

## 2. Pre-State Assessment

At baseline `337f99137673d7866b958a38bd490fb876b2880f`, legacy admission accepted any two present paths. Missing or duplicate EV identifiers violated the no-gap rule. Five SQLite tables allowed REPLACE to defeat append-only intent. The Mojo runner printed deployment PASS without observing services or authority.

The live chain observation identified noncanonical content hashes at C333–352; linkage alone was intact. The legacy EV evidence table contained only synthetic EV999. These historical records are preserved. The policy contract does not assert positive admission of EV01–93.

## 3. Execution Detail

Canonical Sa-plan and coordinator claims precede isolated work. Risk preflight passed against the canonical task store using scoped sibling-workspace paths; active observations bind current worker and attempt. Source workspaces for scheduler, homeostasis and receipt validation have separate cooperative leases under the authentic parent session.

Root added failing regressions before fixing legacy admission and SQLite replacement. The Mojo runner now exposes its actual finite component checks separately; automatic UI acceptance and deployment modes report HOLD. An injected failed-component mutant exits 1.

Two baseline reviews mapped EV scope and source defects. Independent review approved homeostasis candidate `31e238cb7cb440ec8d17e28df7e021522d6fb3a6` for bounded development integration only. AGY was discovered as actual session `abe9bd8d-f0be-4ea7-81a8-9cc6d3901e82` and began reviewing containment candidate `274ae46ac9cb242e1c3692331b72cfc81481d138`; a review result is not yet recorded here.

## 4. Root Cause Analysis

File existence, document labels and fixed arithmetic totals had been substituted for execution evidence and effect authority. The SQL schema prohibited UPDATE and DELETE without prohibiting replacement through unique-key insertion. Scheduler and evolution models trusted supplied records instead of preserving owned task/proposal state.

The scope inventory also exposed reused EV01–05 labels and a provisional EV86 association. They remain explicit uncertainties for sovereign scope review, rather than silent remapping.

## 5. Fix Taxonomy

- Evidence containment: legacy rows cannot admit; range is pinned to 1–109; malformed prefixes fail closed.
- Durability: insertion guards reject conflicting replacement on all five tables, tested in memory with recursive triggers disabled.
- Reporting: finite numeric/predicate checks report their actual scope; missing operational checks exit HOLD.
- Control state: separate candidate tracks proposal and vote state, rejects forged/stale applications, negative token debits and ineligible voters.

## 6. Patterns & Anti-Patterns Discovered

Preserve failures and test actual counterexamples. Never infer authority from a matching string, a PASS label, a board ACK or an arithmetic lemma. A source hash proves byte identity; it does not prove the author, execution or semantic completeness of the claimed acceptance criteria.

## 7. Verification Matrix

| Observation | Before | After | Limit |
|---|---|---|---|
| Legacy EV selftest | 5 new counterexamples fail | 17/17 checks pass | No positive sovereign admission capability |
| SQLite replacement | 5/5 tables replace historical rows in isolated DB | 5/5 replacement attempts refused, original rows preserved | Migration not applied to live ledger |
| Mojo component execution | Mixed with fabricated UI totals | 1115/1115 finite examples pass | Not a formal cohomology proof or runtime interlock |
| Mojo auto-test / preflight / full | Unsupported success claims | Each exits 2, HOLD | Operational acceptance remains UNRUN |
| Mojo failed-component mutant | Not measured by original summary | Exits 1, COMPONENT FAIL | Synthetic falsifier, never system evidence |
| Homeostasis repair | 11/11 new negatives fail | 61 scoped tests pass; independent review approved bounded change | Authentication, persistence, refinement and live deployment remain open |
| Scheduler repair | Capacity, identity and replay counterexamples fail | First three repaired; further replay/fencing controls in progress | No network transfer or Sa-plan effect integration asserted |
| Receipt validator | No content validation | Separate implementation in progress | Must never authenticate a self-written role or grant admission |

## 8. Files Modified

Root changes: `tools/km_provenance/km_ev.ml`, `km_gate.ml`, `km_chain.ml`, and `services/inference/max/uos_tui_webui_runner.mojo`. Timestamped risk observations and [scope inventory](../reviews/20260909-0306-ev-scope-inventory.json) accompany this journal. Child candidates preserve their own source/test manifests and observed output.

## 9. Architectural Observations

The majority of EV94–108 modules are models or renderers without production callers proving their advertised effects. EV109 has an OTP actor, but actor-local safeguards alone do not authenticate sovereign identities or provide durable effect fencing. Existing source/spec locations can be reused only with honest scope and current observed invocations.

## 10. Remaining Gaps

All EV obligations remain subject to current candidate evidence and independent review. Open requirements include authentic receipt producers and sovereign decisions, source-identity reconciliation, formal/runtime refinement, actual transport and recovery behavior, live UI acceptance, native ABI compatibility, operational isolation and tested rollback. The broken historical chain and KM entropy HOLD remain recorded.

All execution work stays in Sa-plan. This journal and its scope inventory are evidence, not another execution queue.

## 11. Metrics Summary

Requested identifiers: 109. New identifiers minted: 0. Policy ceiling: 93. Positive admissions established by this programme: 0. Root production files changed in this stage: 4. Isolated SQLite replacement regressions: 5. Homeostasis scoped tests: 61. Unobserved UI checks receive no passing credit.

## 12. STAMP & Constitutional Alignment

Raw FMEA: severity 5, occurrence 3, detection 4, RPN 60; admission risk class P1, selected score 2500. All four UCA types are addressed by requiring evidence, refusing unsupported clearance, checking current ownership/candidate, and bounding execution. Source/integration/runtime ownership remain separate. No historical row was rewritten and no storage effect was authorized by these checks.

| Assurance aspect | Current evidence / limit |
|---|---|
| 1 Scope | Existing EV01–109 inventoried; identity uncertainties disclosed |
| 2 Specification | Canonical provenance/release/risk contracts used; detailed semantic acceptance still incomplete |
| 3 Source identity | Isolated JJ baselines and child candidates recorded |
| 4 Build | Local OCaml and realized Mojo builds executed; child Gleam builds recorded |
| 5 Runtime identity | Child receipt observes OTP29 / ERTS17.0.5 |
| 6 Unit behavior | Scoped positive and negative tests executed |
| 7 Integration | Complete composed candidate has not been tested |
| 8 Formal analysis | Baseline review found abstraction/refinement gaps; no new formal admission claimed |
| 9 Negative controls | Actual directory/gap/replacement/forgery/replay failures preserved |
| 10 Process bounds | Existing realized tools and bounded subprocesses; no new package installation |
| 11 Data integrity | Replacement guards tested in isolated DB; historical chain defect preserved |
| 12 Security | Self-written names and file paths cannot supply sovereign authority |
| 13 Observability | Fixed positive summaries removed from the Mojo path |
| 14 Surface parity | Actual multi-surface acceptance remains UNRUN |
| 15 Performance | No latency, scaling or availability claim from component totals |
| 16 Recovery | No production cutover or rollback exercised |
| 17 Independent review | Baseline and homeostasis reviews recorded; AGY scoped review underway |

## 13. Conclusion

Work continues under Sa-plan. The current repairs close specific false-admission and state-integrity defects. They do not complete or admit the full EV programme.

<details>
<summary>Comprehensive verification checklist: 18 core checkpoints plus provenance</summary>

| Domain | Checkpoint | This artifact's status |
|---|---|---|
| 1 Metadata/navigation | CHK-01-TIME | Timestamp prefix and observed UTC included |
| 1 Metadata/navigation | CHK-02-TAIL | Full Tailnet navigation links included; artifact not yet published |
| 1 Metadata/navigation | CHK-03-FRACT | Fractal and knowledge tags included |
| 1 Metadata/navigation | CHK-04-KM | Scope inventory linked; knowledge integration pending |
| 2 Purity/storage | CHK-05-MUDA | No barred dependency added; whole-history audit not rerun |
| 2 Purity/storage | CHK-06-GRAPH | No foreign graph NIF introduced |
| 2 Purity/storage | CHK-07-DRIVE | No storage mutation; live interlock test UNRUN |
| 3 Testing/math | CHK-08-C1C8 | Complete UI/behavior acceptance UNRUN |
| 3 Testing/math | CHK-09-MATH | Historical math totals not adopted; KM entropy HOLD retained |
| 3 Testing/math | CHK-10-9MOD | Scoped TDD/falsifiers executed; full nine modalities incomplete |
| 3 Testing/math | CHK-11-REGR | Scoped regressions recorded; full UI regression UNRUN |
| 4 Control/observability | CHK-12-GLEAM | Child OTP29 component tests; live root verification pending |
| 4 Control/observability | CHK-13-HERMES | OCaml containment tests pass; full interceptor acceptance pending |
| 4 Control/observability | CHK-14-ZIGVM | Kernel/VFS acceptance not established by this stage |
| 4 Control/observability | CHK-15-MAX | Mojo finite examples executed; live inference supervision UNRUN |
| 4 Control/observability | CHK-16-OTEL | No end-to-end trace-conformance claim |
| 5 Governance/JJ | CHK-17-SOV | Actual independent review requested; system admission NOT_GRANTED |
| 5 Governance/JJ | CHK-18-JJ | Isolated standalone JJ workspaces; no native Git mutation |
| 6 Provenance | Policy ceiling | EV93 unchanged; EV94–109 NOT_ADMITTED |
| 6 Provenance | Historical chain | C333–352 content-hash mismatch retained |
| 6 Provenance | Evidence authority | Logs, counts and this journal are not admission decisions |

</details>

Previous: [Planning](http://nas-1.tail55d152.ts.net:4100/planning) · Next: [Verification](http://nas-1.tail55d152.ts.net:4100/verification).
System footer: UOS / Sa-plan execution authority / candidate evidence only / admission NOT_GRANTED.

