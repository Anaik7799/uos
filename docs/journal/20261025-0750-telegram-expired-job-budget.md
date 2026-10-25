# 20261025-0750 — Telegram expired-job retry budgets

Observed 2026-10-25T07:27:50.297Z. #fractal-l0 #fractal-l1 #fractal-l2 #fractal-l3 #fractal-l4 #fractal-l5 #fractal-l6 #fractal-l7 #fractal-l8 #fractal-l9 #zk-adr #zero-muda

[Dashboard](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20261024-1044-telegram-completion-critical-path.md) · [Evidence](http://nas-1.tail55d152.ts.net:4100/files/var/recovery-runtime/20261025-0723-job-budget-green/final-source-manifest.json)

## 1. Scope & Trigger

MINI_API_IMPL attempt6; canonical mini-expired-budget0720 job. Prevent Telegram/native agent jobs from exceeding configured retry attempts after worker death. Candidate2ab401652a9f2122d58663157821ca7fde909254. Source-only development; no live binary/database repair.

## 2. Pre-State Assessment

claim_job selected expired executing rows without checking max_attempts. A fresh private max_attempts1 fixture received a second claim. Kalman state model UNRUN.

## 3. Execution Detail

Queue-local retirement marks at most64 expired exhausted executing rows discarded with execution_outcome_unknown in the existing IMMEDIATE transaction. Selection and CAS both reject valid exhausted attempts; live final attempts can still complete.

## 4. Root Cause Analysis

ACH H1: caller misuse disproved by the ordinary public Store API sequence. H2: budget enforced only on explicit Error completion, absent from expired-lease reclaim, supported by source and the red regression. New regression failed on old source and passes after both selector/write guards and bounded retirement.

## 5. Fix Taxonomy

Poka-Yoke: retry bound at selection and CAS. Jidoka: exhausted work becomes terminal with uncertain outcome explicit. Muda: ready jobs bypass deferred retirement backlog; reuse existing Sa-plan and ledger, no scheduler added.

## 6. Patterns & Anti-Patterns Discovered

Devil's Advocate / Popperian falsification: live final completion, exact expiry, restart, queue isolation,70-row backlog and competingconnections tested. Discard is scheduling closure, not remote cancellation or evidence of no external effect.

## 7. Verification Matrix

26 focused checks PASS; old source RED at secondclaim;3383 existing native regressions PASS; automatic dune runtest PASS.62 native sourcebindings match. AGY4384289d PASS logic, conditionalon greenregressions andautomaticregistration; AGY5093ed55 finalregistrationaddendum PASS. Admiralty B2/allsevenengines not established.

## 8. Files Modified

sa_plan_store.ml, test/test_sa_plan_job_budget.ml andtest/dune only. Candidate sourcehashes in var/recovery-runtime/20261025-0723-job-budget-green/final-source-manifest.json.

## 9. Architectural Observations

Native store transaction owns durable job state; Gleam remains operation/task authority.64limits changedrows, not universalSQLscan/wall-time performance. Category/sheaf verification UNRUN.

## 10. Remaining Gaps

Main advanced to 2ab401652a9f2122d58663157821ca7fde909254 at 2026-10-25T07:28:23.778Z after both independentreviews andgreenchecks. Live canonicalbinary stillold; activation belongs to independently reviewed release. Effects of previously crashedjobs remainunknown until native/provider reconciliation. RemainingTelegram features andglobaladmission open.

## 11. Metrics Summary

26 newchecks and3383regressions, no overall completionpercentage. Forecast p0.65 for reviewedhealth/mainlineproposal by07:15 realized, Brier0.1225; p0.70 reviewdisposition by07:20 realized, Brier0.09. Bayesian/Lyapunov models UNRUN.

## 12. STAMP & Constitutional Alignment

UCA notprovided: retain explicitunknownresult; unsafeprovided: no attempt beyondbudget; wrongtime: do notretire liveleases or acceptlatecompletion; duration: bounded64rowretirementperpull. AnalystFMEA duplicateeffect S5/O2/Det2RPN20, queuestarvation S3/O2/Det2RPN12; mitigate durableeffectreceipts andclaimfilters. No EVminting.

## 13. Conclusion

Fix closes a concrete Telegram crash-recovery/agent retry defect in source. Fullgoalremainsactive. Source-only increment is merged; productionactivation remainsopen. Forecast: Probability0.75 finalindependentreviewand source-only integration by2026-10-25T07:40:00Z; scoreafterhorizon.

## Comprehensive verification checklist

Checks below are obligations, not blanket passing claims.

<details>
<summary>Domain 1 — Metadata, timestamp and Tailscale navigation</summary>

- [ ] **CHK-01-TIME** — Observe synchronized clock evidence and document prefix.
- [ ] **CHK-02-TAIL** — Verify full Tailnet links and actual serving status.
- [ ] **CHK-03-FRACT** — Verify L0–L9 tags and applicable layer mapping.
- [ ] **CHK-04-KM** — Reconcile specification, wiki, ZK and journal links.

</details>

<details>
<summary>Domain 2 — Zero-Muda purity and storage safety</summary>

- [ ] **CHK-05-MUDA** — Verify exclusions against the candidate dependencies.
- [ ] **CHK-06-GRAPH** — Verify the pure BEAM/Hermes graph boundary.
- [ ] **CHK-07-DRIVE** — Preserve the denied OS serial and test real interlocks only in scope.

</details>

<details>
<summary>Domain 3 — Testing Gold Standard and mathematical gates</summary>

- [ ] **CHK-08-C1C8** — Verify all applicable C1–C8 surfaces.
- [ ] **CHK-09-MATH** — Measure the four declared mathematical gates.
- [ ] **CHK-10-9MOD** — Apply relevant unit, system, TDD, BDD, performance, scalability, property, fuzz and chaos checks.
- [ ] **CHK-11-REGR** — Run applicable regressions and bounded observation.

</details>

<details>
<summary>Domain 4 — Cross-language control and observability</summary>

- [ ] **CHK-12-GLEAM** — Observe actual OTP control/supervision behavior.
- [ ] **CHK-13-HERMES** — Observe bounded analysis and authoritative evidence.
- [ ] **CHK-14-ZIGVM** — Verify deterministic execution and descriptor-relative VFS.
- [ ] **CHK-15-MAX** — Observe actual isolated inference when applicable.
- [ ] **CHK-16-OTEL** — Verify clock and nonzero trace/span identity.

</details>

<details>
<summary>Domain 5 — Sovereign governance and standalone Jujutsu</summary>

- [ ] **CHK-17-SOV** — Obtain candidate-bound independent review and authorized admission.
- [ ] **CHK-18-JJ** — Preserve standalone JJ, source ownership and exact candidate identity.

</details>

<details>
<summary>Domain 6 — Provenance extension</summary>

EV ceiling remains 93. EV-94..109 remain NOT_ADMITTED. No new EV number is minted.

</details>

[Previous: formal specification](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20260909-0412-gleam-harness-symbiosis-formal-spec.md) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk) · [Cockpit](http://nas-1.tail55d152.ts.net:4100/)

UOS footer: document and component evidence do not grant system admission.
