# 20260930-0839 — Expired claim recovery

#fractal-l0 #fractal-l2 #fractal-l4 #fractal-l8 #zk-adr #zero-muda

[Dashboard](http://nas-1.tail55d152.ts.net:4100/static/20260930-0633-restoration-dashboard.html) ·
[Contract](http://nas-1.tail55d152.ts.net:4100/files/contracts/rules/20260930-0800-expired-claim-preflight.md) ·
[Evidence](http://nas-1.tail55d152.ts.net:4100/files/governance/planning/20260930-0754-capability-evidence/claim-recovery-all.json)

## 1. Scope & Trigger

Canonical Sa-plan `uos/claim-recovery/20260930-0758`, task REPAIR, worker
`codex-claim-recovery-20260930`, attempt 1. Repair a read-only risk-checker
gap discovered during full recovery. No production service effect or global
admission is authorized by this repair.

## 2. Pre-State Assessment

Google AGY claimed AGY_FREE through a helper with a 30-second default lease.
Its isolated work outlasted attempt 1. The checker correctly held the expired
attempt, but also lacked a mode to evaluate the canonical reclaim transition.
Code was frozen at 6fc93af5. The recovered baseline remained live.

## 3. Execution Detail

The ordinary preflight and active check passed for this separate repair task
before implementation. Added exact same-worker expired-attempt projection for
ranking, retained original full-plan coherence and live snapshots, and added
adversarial regressions. Independent reviewer accepted source eec94435.
Google AGY repeated the reviewed read-only preflight, reclaimed through
canonical Gleam/Sa-plan with an explicit one-hour lease, received attempt 2,
and obtained a fresh active-check PASS before any resumed work.

## 4. Root Cause Analysis

ACH disconfirmation: H1, corrupted Sa-plan state, is contradicted by valid
canonical expired rows and the documented claim predicate. H2, missing recovery
semantics plus an unsuitable helper lease, matches the 30-second deadline,
refused release, and successful exact-attempt reclaim. The checker now evaluates
that transition without treating the expired attempt as executable.

A separate parent sequencing defect completed TRANSPORT before inspecting its
active-check HOLD. That receipt is retained as counterevidence. Later source
review and fresh checks establish current evidence; they do not retroactively
authorize that completion sequence.

## 5. Fix Taxonomy

Poka-Yoke: exact worker, attempt and deadline binding; no broad expired-task
exception. Jidoka: original HOLD preserved and downstream release stopped.
Muda removal: canonical reclaim is assessable without raw database repair.

## 6. Patterns & Anti-Patterns Discovered

Devil's Advocate falsification checks wrong worker, changed attempt/deadline,
live or missing lease, completed/result-bearing tasks, missing plan rows, changed
dependencies and unrelated expired tasks. A read-only observation does not
grant effect authority. Do not combine a checker invocation and a dependent
completion without inspecting the former result.

## 7. Verification Matrix

Admiralty/STANAG admissibility B2 is assigned to bounded direct observations
and independently repeated source/runtime checks below; not to global claims.

| Evidence | Result | Limit |
|---|---|---|
| Original repair-task preflight and active check | PASS | Separate development authority |
| Checker suite | 375 baseline, 32860 adversarial checks PASS | Includes 32768 DAG scenarios; not additive reliability |
| Exact real-plan reclaim observation | RECLAIM_PREFLIGHT_PASS | Read-only, no admission |
| Ordinary expired preflight | HOLD | Expected negative control retained |
| Wrong-worker reclaim | HOLD | Independently repeated |
| Actual AGY canonical reclaim | Attempt 2, one-hour lease | Replaces expired claim only |
| Exact attempt-2 active check | PASS | Current authority, not retrospective authorization |
| Independent source review | PASS eec94435 | Four-file checker/addendum scope |

## 8. Files Modified

Isolated Jujutsu change muxwkwmx modifies checker.ml, validate.ml,
adversarial.ml and the timestamped addendum. Canonical orchestration adds this
journal, risk assessment and receipts. Source hashes are bound in
20260930-0758-claim-recovery-risk.json. No native Git mutation occurred.

## 9. Architectural Observations

Hermes computes bounded observations; Gleam/Sa-plan owns task transitions.
Ranking a projected available task does not change the original executing
record. The projection preserves dependency structure and evidence references;
full-plan coherence is checked against original rows.

## 10. Remaining Gaps

Preflight and claim are separate observations. Re-read the exact binding
immediately before claim, require previous attempt plus one, and run the
new-attempt active check before execution. Canonical transactional lease
exclusion remains mandatory. No stale evidence or prior HOLD is erased.

## 11. Metrics Summary

One expired attempt recovered; no raw SQL mutation or production restart.
Bayesian Beta-Binomial reliability estimates are not calibrated from overlapping
tests. Trust remains scope-bound. Lyapunov dV/dt < 0 is an intended stability
condition, not a theorem established by these counts.

## 12. STAMP & Constitutional Alignment

Unsafe provision: block foreign/live claim takeover. Non-provision: permit
assessment of a legitimate expired same-worker recovery. Wrong timing: recheck
exact binding and require a fresh active lease. Excess duration: use explicit
bounded leases and retain expiry checks. EV ceiling 93 is unchanged.

<details><summary>Domain 1 — Metadata and navigation</summary>

- CHK-01 TIME: host UTC and synchronized checker clock receipts.
- CHK-02 TAIL: full Tailnet links.
- CHK-03 FRACT: layer tags provided.
- CHK-04 KM: contract/evidence/journal linked.

</details>
<details><summary>Domain 2 — Purity and storage</summary>

- CHK-05 MUDA: no new dependency.
- CHK-06 GRAPH: no NIF or foreign graph layer.
- CHK-07 DRIVE: no disk/device effects.

</details>
<details><summary>Domain 3 — Verification</summary>

- CHK-08 C1–C8: scoped checker tests; broad UI tests not applicable.
- CHK-09 MATH: existing DAG oracle; no new global proof.
- CHK-10 MODES: direct positive, negative and boundary observations.
- CHK-11 REGR: ordinary expired checks retain refusal.

</details>
<details><summary>Domain 4 — Runtime boundaries</summary>

- CHK-12 GLEAM: canonical task ingress used.
- CHK-13 HERMES: bounded read-only checker.
- CHK-14 ZIGVM: unchanged.
- CHK-15 MAX: unchanged.
- CHK-16 OTEL: structured timestamped receipts; global trace coverage not claimed.

</details>
<details><summary>Domain 5 — Governance</summary>

- CHK-17 SOV: independent exact-source review accepted.
- CHK-18 JJ: standalone history retained.

</details>

## 13. Conclusion

Forecast: for the next one-hour task lease, wrong-owner or stale-attempt active
checks will remain rejected and the new exact attempt can be assessed normally.
Horizon: 2026-09-30T09:02:16Z. Brier scoring is deferred until that horizon;
no calibrated success probability is asserted. The claim recovery is verified;
application integration and production release remain separate gated tasks.
