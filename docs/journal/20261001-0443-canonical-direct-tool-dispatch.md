# Canonical direct tool dispatch and pending capability audit

Status: IN PROGRESS. Plan `uos/direct-dispatch/20261001-0440`; source and runtime acceptance are pending.
Created: 2026-10-01T04:50:43Z. #fractal-l0 #fractal-l3 #fractal-l4 #fractal-l5 #fractal-l9 #zk-adr #zero-muda

[Dashboard](http://nas-1.tail55d152.ts.net:4100/static/20260930-0633-restoration-dashboard.html) | [Planning](http://nas-1.tail55d152.ts.net:4100/planning) | [Specification](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20261001-0443-direct-tool-dispatch-invariants.json) | [Prior recovery](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20261001-0255-fractal-rca-mainline-recheck.md)

## 1. Scope & Trigger

The operator requested work with Google AGY, fractal RCA, correction of issues and stabilized branch integration into main, with direct tool dispatch as the new goal. Engine 5 requires executable authority invariants at the candidate; no global formal proof or admission is inferred. Baseline main is `fd4950eebf490b9972e204488e719978ee7a5522`.

## 2. Pre-State Assessment

Engine 7 prior is observed service state, not a numerical Kalman estimate. Four checked services remain active with zero automatic restarts; cognitive PID891443 runs reviewed capsule142d21d7. Ecology advances at cycle72168. Coordinator sequence178 has no live leases before this session. Direct /tool and /action deliberately refuse because no canonical authority is bound. Several broader helper branches still return static health or fabricated success.

## 3. Execution Detail

A new canonical Sa-plan separates this goal from the completed restoration. Actual Google AGY session954b9a82-15dc-4bd5-ae31-dd9670e583ca, pane w2:p9, owns AGY_IMPL attempt1 in an isolated sibling workspace. Parent owns integration/main epoch4; every typed heartbeat carries the plan and unique board actor reference. AGY proposed canonical row validation and a bounded local direct CLI, with Telegram payload authority rejected. Parent required reuse of existing Gleam task/coordinator fences, clock continuity, strict implemented-tool scope and before/after observation checks.

STATUS published the pending-items dashboard and verified parsed served-byte equality. First active-check correctly held because the assessment still declared available after claim; refreshing the canonical executing state passed. An initial dashboard serialization produced invalid UTF-8 from inherited Unicode; ASCII JSON was regenerated and served equality passed. The old smoke test expected RUNTIME_VERIFY, which is not a task in this plan; correcting the invocation's expectation to VERIFY passed. A separate temporary evaluator name collision failed before running the dashboard script and was corrected without changing product logic. These invocation failures are not evidence of dispatch acceptance.

## 4. Root Cause Analysis

Engine 1 Analysis of Competing Hypotheses (ACH):

| Hypothesis | Disconfirming test or observation | Current result |
|---|---|---|
| H1: Direct tools fail because the worker crashed | Active PID891443, zero restarts and advancing ecology | Disconfirmed for baseline |
| H2: A caller-provided lease is sufficient authority | Existing dispatcher accepts a Boolean and lease fields; neither reads canonical state | Disconfirmed as an authorization design |
| H3: Current refusal is an implementation regression | Last recovery deliberately installed fail-closed containment | Confirmed missing positive authority path |
| H4: Advertised tools have real executors | Static mutation-success and runtime-health strings observed in source | Disconfirmed for affected handlers |
| H5: Healthy process implies usable dispatch | Active worker still supplies None and False to the route | Disconfirmed |

Fractal causes recur at L0 identity, L3 task fencing, L4 ingress/delivery, L5 truthful feedback and L9 admission claims. A fix must preserve each boundary rather than merely change a Boolean.

## 5. Fix Taxonomy

Engine 6 Poka-Yoke: typed read-only scope, strict argument schema and canonical task/coordinator verification. Jidoka: unknown authority, unsupported tools and changed authority refuse. Muda: reuse existing Gleam bounded transport, clock and Sa-plan adapters; no package downloads or new native control plane. Implementation evidence remains pending.

## 6. Patterns & Anti-Patterns Discovered

Engine 4 Red Team Falsification targets success-shaped stubs, payload identity claims, stale leases, wrong attempts and source-only release claims. A locally trusted launcher is a cooperative Unix-account boundary, not cryptographic workload authentication. Read repeatability does not establish durable delivery or exactly-once effects.

## 7. Verification Matrix

Engine 2 Admiralty Grade B2 is the required acceptance threshold for independently repeated candidate-bound observations. Current baseline observations are scoped evidence; new dispatch tests, source review, release and loaded acceptance are UNRUN.

| Check | Current state |
|---|---|
| Baseline process and ecology observation | Observed healthy at intake |
| Canonical task/risk preflight and active checks | PASS after preserved assessment-state HOLD |
| Served dashboard JSON | Exact parsed equality PASS |
| Dashboard actual script smoke check | PASS with current task name; visual browser acceptance UNRUN |
| Direct dispatch positive/negative controls | UNRUN |
| Independent source/release/runtime review | PENDING |
| Branch consolidation | Baseline retained; new candidate not on main |

## 8. Files Modified

Parent owns risk/evidence, dashboard, this journal and invariant specification. AGY owns direct dispatch Gleam implementation, CLI, tool-truth corrections and focused tests in its sibling workspace. Exact candidate source accounting will replace this provisional list after quiescence. No live DB, secrets or credential bytes enter source history.

## 9. Architectural Observations

Engine 5 consistency requires a real trust boundary before canonical state validation. Sa-plan task ownership, coordinator resource ownership, synchronized clock evidence and read-tool scope are separate checks. Gleam owns policy and supervision; bounded native adapters observe state. Sheaf/category or Lean proof invocations are not claimed. The invariant JSON is a machine-readable test specification, not a completed theorem proof.

## 10. Remaining Gaps

Pending: direct dispatch implementation and release; authenticated Telegram authority handoff; durable per-request response acknowledgement; unavailable native subscriptions and broader native facade; variable external free-provider capacity; cross-host failover and long-duration reliability; browser visual acceptance; EV94-109 and global formal/system admission. Opening a read-only local tool path will not silently mark these complete.

## 11. Metrics Summary

Engine 3 reports observed counts without inventing a Bayesian posterior, decay rate or Lyapunov derivative. At intake, MCP catalog declares65 tools:12 unavailable and53 declared-unprobed. Catalog counts are not execution counts. Task completion is sourced from canonical Sa-plan; new dispatch test counts are pending and will not be summed with historical recovery counts.

## 12. STAMP & Constitutional Alignment

Raw FMEA S4 x O3 x Det3 =36, band4, describes plausible unauthorized execution or fabricated evidence under proposed dispatch exposure; occurrence is a scenario estimate. Four UCAs: omit required supported dispatch; provide execution from unverified claims; execute after authority expires or release before review; continue/replay after bounded ownership ends. Criticality4 x STPA4 x FMEA4 x dependency4 x impact3 =768 for the capability release path. Scores do not grant effect authority. EV93 ceiling remains; EV94-109 remain NOT_ADMITTED. No storage mutation is in scope.

| Release aspect | Evidence or limit |
|---|---|
| A01 storage | No drive effect; existing denied serial preserved |
| A02 JJ | Standalone sibling implementation, main advancement pending |
| A03 purity | No new dependency proposed; candidate check pending |
| A04 OTP | Existing pinned OTP29; new loaded identity pending |
| A05 ZigVM | No kernel change; global verification UNRUN |
| A06 Hermes | Canonical Sa-plan and bounded state observations |
| A07 mathematics | Invariant tests pending; global math gates UNRUN |
| A08 control | Task, coordinator, clock and scope fences required |
| A09 MAX | No inference service change |
| A10 Zenoh | Typed coordination only; no synthetic queued messages |
| A11 AG-UI | Full trace propagation UNRUN |
| A12 A2UI | Dashboard state projection only |
| A13 interfaces | Local direct route planned; Telegram authority unavailable |
| A14 Tailnet | Canonical FQDN links and served state verified |
| A15 checklist | Explicit18 checkpoints below |
| A16 KM | Prior recovery and failed evidence preserved |
| A17 Sa-plan | Sole canonical plan/task authority |

<details><summary>Comprehensive verification: 18 checkpoints, five domains plus provenance</summary>

- CHK-01 · TIME: NTP synchronized at intake
- CHK-02 · TAILNET: live state refresh checked separately
- CHK-03 · FRACTAL: L0 authority, L3 fencing, L4 delivery, L5 truth
- CHK-04 · KM: current plan and prior evidence preserved
- CHK-05 · ZERO-MUDA: candidate dependency check pending
- CHK-06 · GRAPH: no foreign graph dependency introduced
- CHK-07 · STORAGE: no storage effect in dispatch scope
- CHK-08 · C1-C8: focused interface acceptance pending
- CHK-09 · MATH: global gates UNRUN
- CHK-10 · TESTS: canonical positive and refusal controls pending
- CHK-11 · REGRESSION: prior baseline healthy; new candidate pending
- CHK-12 · GLEAM: implementation and reviewed runtime pending
- CHK-13 · HERMES: Sa-plan sole task authority
- CHK-14 · ZIGVM: no kernel change proposed
- CHK-15 · MAX: no inference change proposed
- CHK-16 · OTEL: typed board trace and fresh heartbeat retained
- CHK-17 · SOVEREIGN: source and release reviews pending
- CHK-18 · JJ: standalone workspace; main unchanged

Domain6 provenance: EV93 ceiling; no new EV; no historical journal replay.

</details>

## 13. Conclusion

Engine 7 Forecast was precommitted in intake evidence before implementation: Probability p=0.8 that bounded read-only canonical dispatch passes independent authority falsifiers; Horizon before this plan CLOSE. Brier score remains UNRESOLVED until the observed outcome. This is one uncalibrated analyst forecast and establishes no reliability bound. The direct-dispatch goal is not yet met.

[Previous](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20261001-0255-fractal-rca-mainline-recheck.md) | [Dashboard](http://nas-1.tail55d152.ts.net:4100/static/20260930-0633-restoration-dashboard.html) | [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) | [ZK](http://nas-1.tail55d152.ts.net:4100/zk)

UOS footer: bounded observations and source integration grant no universal admission.
