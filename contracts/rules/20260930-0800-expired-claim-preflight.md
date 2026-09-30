# 20260930-0800 — Expired same-worker claim preflight

#fractal-l0 #fractal-l2 #fractal-l4 #fractal-l8 #zk-adr #zero-muda

Addendum to SC-RISK-CHECK-001. Development repair under Sa-plan
`uos/claim-recovery/20260930-0758`; report-only, no runtime admission.
[Cockpit](http://nas-1.tail55d152.ts.net:4100/) ·
[Recovery dashboard](http://nas-1.tail55d152.ts.net:4100/static/20260930-0633-restoration-dashboard.html) ·
[Parent contract](http://nas-1.tail55d152.ts.net:4100/files/contracts/rules/20260907-1606-risk-checker-contract.md)

An expired executing attempt cannot pass ordinary preflight or active-check.
Canonical Sa-plan supports reclaiming it, but the original risk checker had no
way to assess that recovery transition. Ordinary behavior remains unchanged.

`bash tools/risk-priority-check --reclaim-preflight PORTFOLIO TASK WORKER PREVIOUS_ATTEMPT PREVIOUS_LEASE_NS`
is a read-only observation of one exact, expired, same-worker attempt. The
portfolio must truthfully retain its executing state. The checker binds the
actual previous worker, positive attempt, positive deadline, absent completion
and absent result. Only ranking projects that one task as available. Full-plan
agreement, dependencies, evidence, freshness, clocks, ordering and other-task
lease failures retain their vetoes. Original live rows and their digest remain
in the receipt; the observation is repeated before returning.

A `RECLAIM_PREFLIGHT_PASS` permits proceeding to the ordinary canonical Sa-plan
claim transition for that exact task. It grants no execution or deployment
authority and does not revive the expired attempt. Re-read the binding before
claiming, require the returned attempt to equal previous attempt plus one,
refresh the truthful portfolio, and obtain `--active-check` for the exact new
worker/attempt before work or completion. Changed ownership, state, attempt,
deadline or a failed active check requires stopping and re-observation. The
Sa-plan transaction remains responsible for effect-time lease exclusion.

Do not relabel old HOLD receipts, incomplete work, or actions after expiry as
authorized retrospectively. This extension cannot clear an unrelated HOLD.
No database mutation, direct SQL recovery, force flag, credential or paid
request is introduced.

## Comprehensive verification checklist

<details><summary>Domain 1 — Metadata and navigation</summary>

- CHK-01 TIME: synchronized host observed; source review receipt records time.
- CHK-02 TAIL: full Tailnet links above.
- CHK-03 FRACT: authority/control/implementation/evidence layers tagged.
- CHK-04 KM: parent contract linked; no new EV claim.

</details>
<details><summary>Domain 2 — Purity and storage</summary>

- CHK-05 MUDA: no added dependency.
- CHK-06 GRAPH: pure bounded OCaml observation; no NIF.
- CHK-07 DRIVE: storage devices untouched.

</details>
<details><summary>Domain 3 — Verification</summary>

- CHK-08 C1–C8: scoped validator tests; broad UI testing not applicable.
- CHK-09 MATH: existing DAG oracle; no new mathematical theorem claimed.
- CHK-10 MODES: positive, boundary and adversarial refusal tests.
- CHK-11 REGR: ordinary expired preflight still refuses.

</details>
<details><summary>Domain 4 — Runtime boundaries</summary>

- CHK-12 GLEAM: task operations remain through canonical Gleam ingress.
- CHK-13 HERMES: read-only checker; Sa-plan remains mutation authority.
- CHK-14 ZIGVM: unchanged.
- CHK-15 MAX: unchanged.
- CHK-16 OTEL: timestamped JSON observation; no global trace claim.

</details>
<details><summary>Domain 5 — Governance</summary>

- CHK-17 SOV: independent review required before use for recovery.
- CHK-18 JJ: isolated standalone Jujutsu development and preserved history.

</details>

UOS footer: observations do not replace task/runtime fencing or system admission.
