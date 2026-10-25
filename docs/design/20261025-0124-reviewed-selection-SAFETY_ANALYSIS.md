# 20261025-0124 — Reviewed equal-score selection contract and safety analysis

Observed 2026-10-25T01:23:47.208Z. #fractal-l0 #fractal-l3 #fractal-l4 #fractal-l9 #zk-adr #zero-muda

[SOP](http://nas-1.tail55d152.ts.net:4100/files/contracts/rules/20260907-1559-risk-prioritization-sop.md) · [Telegram goal](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20261024-1044-telegram-completion-critical-path.md)

Scope: explicit --preflight-reviewed PORTFOLIO TASK REVIEW_FILE mode in existing report-only OCaml risk checker. Standard preflight, active and reclaim modes retain original semantics. No effect or scheduler authority.

## Formal obligations and executable falsifiers

- SEL-01: exact SHA256 of complete portfolio, plan and requested task match the review. Byte change or another plan/task refuses.
- SEL-02: reviewed sorted distinct IDs equal the entire top eligible equal-class/equal-score group of at least two tasks. No lower score/class, blocked task, omission, duplicate or extra ID is selected.
- SEL-03: only exact RP-COST-TIE findings generated for adjacent members of that group are discharged. Every unrelated finding remains blocking; source/coherence/clock checks still run.
- SEL-04: review has strict fields, bounded comparative benefit/cost justification for every tied member, and reviewer differs from all assessment actors. Cost bounds describe the next bounded packet, not a promise to finish the entire task.
- SEL-05: external AGY response bytes are digest-bound; SUCCESS, nonempty conversation ID, stable reviewer label, APPROVE and exact canonical proposal hash must match. The reviewer label is known before dispatch; the generated conversation ID is retained as provenance, avoiding a circular prelaunch identity requirement. This is consistency checking, not cryptographic reviewer authentication; provenance must be independently verified in the cooperative local account trust boundary.
- SEL-06: review is fresh at start and end, maximum one-hour lifetime; whole review and proof bytes are re-read with nonsymlink regular-file checks before reporting PASS.
- SEL-07: report only reorders chosen top-group member to first; stored task priority, state and ownership never change. Actual Sa-plan claim/active/effect fences remain required.

The37 reviewed_selection_test checks exercise these obligations, including changed files, symlink proof and expiry during verification. Existing375baseline checks and32953adversarial checks (including32768DAGscenarios) pass. These executable bounded contracts are not an unbounded proof or system admission.

## STPA and FMEA

UCA not provided: eligible work starves on permanent tie; add explicit reviewed choice. UCA unsafe provided: review clears hazards or selects lower class; retain all nonmatching findings and exact top group. UCA timing: stale review applied after portfolio change; bind both digests and start/end clocks. UCA duration: review survives indefinitely; <=1h and fresh recheck.

FMEA1–5 analyst estimates: stale/forged selection S4 O3 D3 RPN36; source drift S4 O3 D2 RPN24; permanent tie starvation S3 O4 D1 RPN12. Severity floor remains4 for evidence integrity. Residual: no cryptographic signer authentication, local privileged actors can rewrite both evidence files; no stronger boundary asserted. ToCTOU between report and real claim remains separate current-authority obligation.

## Use and limits

Proposal canonical hash is SHA256 of compact JSON with fixed key order: schema,plan_id,portfolio_sha256,selected_task,tied_tasks,observed_at,valid_until,reviewer,reason,comparisons. Evidence path/digest are excluded to avoid circularity. Actual AGY response must approve that hash. Missing review preserves ordinary HOLD; no numeric score inflation or force flag.

<details><summary>Verification domain 1</summary>

- [ ] CHK-01 Timestamp — scoped evidence above; no blanketPASS
- [ ] CHK-02 Tailnet navigation — scoped evidence above; no blanketPASS
- [ ] CHK-03 Fractal scope — scoped evidence above; no blanketPASS
- [ ] CHK-04 Knowledge links — scoped evidence above; no blanketPASS

</details>

<details><summary>Verification domain 2</summary>

- [ ] CHK-05 Dependency exclusions — scoped evidence above; no blanketPASS
- [ ] CHK-06 Pure graph boundary — scoped evidence above; no blanketPASS
- [ ] CHK-07 Storage safety — scoped evidence above; no blanketPASS

</details>

<details><summary>Verification domain 3</summary>

- [ ] CHK-08 C1-C8 — scoped evidence above; no blanketPASS
- [ ] CHK-09 Math gates — scoped evidence above; no blanketPASS
- [ ] CHK-10 Test modalities — scoped evidence above; no blanketPASS
- [ ] CHK-11 Regression — scoped evidence above; no blanketPASS

</details>

<details><summary>Verification domain 4</summary>

- [ ] CHK-12 GleamOTP — scoped evidence above; no blanketPASS
- [ ] CHK-13 Hermes — scoped evidence above; no blanketPASS
- [ ] CHK-14 ZigVM — scoped evidence above; no blanketPASS
- [ ] CHK-15 MAX — scoped evidence above; no blanketPASS
- [ ] CHK-16 Trace correlation — scoped evidence above; no blanketPASS

</details>

<details><summary>Verification domain 5</summary>

- [ ] CHK-17 Independentreview — scoped evidence above; no blanketPASS
- [ ] CHK-18 Jujutsu — scoped evidence above; no blanketPASS

</details>

Provenance: EV>93 NOT_ADMITTED.


[Previous](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20261024-2059-telegram-current-task-bridge.md) · [Next](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20261024-1044-telegram-completion-critical-path.md)

UOS footer: component evidence is not admission.
