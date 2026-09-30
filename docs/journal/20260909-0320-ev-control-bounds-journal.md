# 20260909-0320 — Bounded proposal lifecycle and autoscaler arithmetic

#fractal-l0 #fractal-l2 #fractal-l4 #fractal-l5 #zk-adr #zero-muda

[UOS](http://nas-1.tail55d152.ts.net:4100/) · [Planning](http://nas-1.tail55d152.ts.net:4100/planning) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [Source](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20260909-0320-ev-control-bounds-journal.md)

Created from observed UTC 2026-09-09T03:42:20Z; filename prefix encodes hour and seconds. Canonical task `uos/ev-control-bounds/20260909` / `BOUNDS`, worker `codex-ev-control-bounds`, attempt1. Parent `uos/ev-admission/20260909-0210` / `PROGRAM`. Component implementation handoff only; **NOT_ADMITTED**.

## 1. Scope & Trigger

The parent relayed independent `homeostasis_change_review` approval of predecessor `31e238cb7cb440ec8d17e28df7e021522d6fb3a6` for bounded development integration, with8/8 source hashes validated and no blockers. Its P3 finding concerned unbounded pending proposals. The parent additionally requested EV106 fractional-refill, elapsed-time derivative and constructor-bound repairs. Original Sa-plan REPAIR was completed with that bounded outcome at03:33; no EV admission was recorded. New BOUNDS task was created and claimed separately.

## 2. Pre-State Assessment

The prior module retained every distinct pending or rejected proposal until a successful application. Token refill rounded independently per call and discarded fractions: ten100ms refills could produce0 tokens while a single1s refill produced1. The queue derivative used the raw queue delta. Constructors accepted negative budgets, reversed worker bounds and zero latency targets. Ten real failing tests were frozen at `75606a5402745a76ee7102cc77d38e4ff08e6b0f`, with production source identical to predecessor31e238cb.

## 3. Execution Detail

Preflight passed03:33:39Z; BOUNDS claim returned attempt1 and lease expiry1788932032190995668ns; active checks passed03:33:53Z and03:36:03Z. Ten regression tests failed before production implementation. Constructor tests initially demonstrated unsafe constructed fields; after the API gained typed rejection, the same invalid scenarios assert the specific error. An initial test compile used unavailable `list.range`; the failure was preserved and the helper changed to existing `list.repeat`/`index_map` before the red execution. A formatting attempt rejected parenthesized guard syntax; the guard was expressed as a named Boolean before compilation.

The repair adds a32-proposal intake cap and explicit retirement of exact terminal entries. Every issued proposal carries a monotonically increasing sequence retained in owned state. A replacement receives a new sequence even if its mutation, timestamp, generation and votes otherwise match a retired proposal. The actual OTP actor exposes the same retirement transition. No retired-ID tombstone list is needed.

Token buckets now carry an integer token-microsecond remainder. Forward refill divides accumulated credit by1,000,000 and retains the residual; saturation discards excess credit. Constructors return typed errors for invalid worker order/negative limits, negative capacity/refill rate, and nonpositive/nonfinite target latency. Zero worker pools and zero token capacity remain valid bounded configurations. The derivative uses seconds since the last queue observation, independently of token refill and last scaling action. Equal or backward observation times leave state unchanged.

## 4. Root Cause Analysis

The missing proposal lifecycle budget allowed terminal records to accumulate. Removing records alone would allow deterministic re-creation of the same registered snapshot, so retirement requires a non-reused instance identity. Refill error came from rounding each observation instead of conserving credit; queue-rate error came from lacking an observation clock; unsafe initial state came from unchecked constructor parameters.

## 5. Fix Taxonomy

Resource bound:32 pending entries and explicit slot recovery. Replay control: monotonic instance sequence and existing exact membership comparison. Conservation: integer fractional token carry and saturation reset. Dimensional correction: queue items per elapsed second. Domain guards: typed constructor errors; non-forward samples preserve owned state.

## 6. Patterns & Anti-Patterns Discovered

Record deletion is not sufficient replay protection when identical values can be reissued. A scalar high-water sequence avoids retaining all retired IDs. Conservation laws should be tested across partitions, including saturation and backward observations. An independent observation timestamp prevents token reads from changing queue-rate estimates. Constructor validation belongs before state construction rather than in downstream scaling heuristics.

## 7. Verification Matrix

| Observation | Result | Evidence |
|---|---|---|
| Immutable TDD red snapshot |10 failed,0 passed; exit1 |75606a54; `docs/reviews/20260909-0329-control-bounds-red-tests.txt` |
| Red compile |exit0 |`20260909-0329-control-bounds-red-build.txt` |
| Final local compile |exit0; unrelated existing warnings retained |`20260909-0343-control-bounds-green-build.txt` |
| Final affected regressions |79 passed,0 failed; exit0 |`20260909-0343-control-bounds-green-tests.txt` |
| New bounded-control module |15 tests, including actual actor intake/retirement |Same green receipt |
| Actual runtime |OTP29 / ERTS17.0.5 |Observed runtime identity in red/green receipts |
| Current source bound |6 changed source/test files |`20260909-0343-control-bounds-source-sha256.txt` |
| Risk observation |ACTIVE_OBSERVATION_PASS03:41:16Z |`20260909-0343-control-bounds-risk-green.json` |
| Formal refinement / sovereign admission |NOT_IMPLEMENTED / pending |No new formal or sovereign claim |

The79 tests span `ev_control_bounds_test`, the previous seven61-test modules, and `predictive_autoscaler_hud_test` (3 tests). Tests exercise capacity rejection, terminal retirement, ratified replay after identical resubmission, pending retirement rejection,100-way refill partitions with saturation, constructor errors and observation-time independence. Actual actor tests inspect final owned state and terminate the isolated actor.

Reproduction uses the predecessor journal’s realized Gleam1.16.0/OTP29.0.5 path and dependency manifests, with `ERL_FLAGS='+S 2:2'`,180s build timeout and60s EUnit timeout. EUnit module list:

```text
[ev_control_bounds_test, ev_control_boundary_test, multi_agent_quorum_test,
 predictive_autoscaler_test, predictive_autoscaler_hud_test,
 homeostasis_evolution_engine_test, tui_15_evolutionary_cycles_test,
 homeostasis_evolution_hud_test, multi_agent_quorum_hud_test]
```

## 8. Files Modified

Two HA modules: `homeostasis_evolution_engine.gleam`, `predictive_autoscaler.gleam`. Four tests: new `ev_control_bounds_test.gleam`, `ev_control_boundary_test.gleam`, `predictive_autoscaler_test.gleam`, `predictive_autoscaler_hud_test.gleam`. Narrow existing tests unpack the constructor’s typed result. Timestamped assessments, red/green receipts, source hashes and this journal accompany the implementation. No package manifest, shared runtime, historical ledger, admission ceiling or EV identifier changed.

## 9. Architectural Observations

Pending count is bounded; payload byte size and the existing applied-evolution history are separate resource dimensions. The sequence is in-memory actor state, not a persistent cross-restart epoch. Typed voter identities still do not authenticate remote workloads. Pure state records remain constructible by trusted in-process code. Reused dependencies are realized compiler inputs, not newly rebuilt or independently admitted packages.

## 10. Remaining Gaps

Independent candidate review remains required. Formal refinement of the bounded lifecycle and token-conservation transition, authenticated voters, durable incarnation/restart fencing, payload-size budgets, and live root-supervisor/deployment recovery remain outside this patch. The predecessor’s explicit17-aspect table remains applicable: local actor/unit/TUI/HUD behavior observed; authenticated IAM, formal runtime refinement, full root supervision, OTel, browser monitoring, kernel/inference/storage operations and live deployment remain UNRUN or NOT_IMPLEMENTED. No61/79-test count is a fleet coverage percentage.

## 11. Metrics Summary

Ten observed red failures, fifteen new bounded-control tests, seventy-nine affected tests passed. Pending proposal ceiling32;100-way partition checks at three time horizons, including saturation. Two BEAM schedulers; zero downloads, paid calls, deployments or new EV IDs. Six source/test files changed relative to predecessor31e238cb. The immutable red snapshot remains separately reviewable.

## 12. STAMP & Constitutional Alignment

Not-provided UCA: intake/constructor validation now exists. Unsafe-provided UCA: capacity overflow and invalid initialization return errors; retired snapshots cannot match replacements. Wrong-timing UCA: non-forward samples preserve state and retired instance sequences cannot be reused. Duration UCA: terminal retirement releases retained pending capacity; bounded tests and current Sa-plan ownership constrain execution. Assessment remains P1 for parent admission prerequisites; same-UID mutation and absent formal/authenticated integration remain residual risks.

## 13. Conclusion

The bounded follow-up passes its affected79-test suite. Parent independent review controls integration and task completion. Existing31e238cb and red75606a54 remain immutable; neither this journal nor its passing tests grant EV admission.

<details><summary>Domain 1 — Metadata and navigation</summary>

- [x] CHK-01-TIME — Host UTC observed and timestamp prefix applied.
- [x] CHK-02-TAIL — Tailscale FQDN references included; live delivery UNRUN.
- [x] CHK-03-FRACT — Scoped fractal tags included.
- [x] CHK-04-KM — Parent task, predecessor journal and evidence locators retained.

</details>
<details><summary>Domain 2 — Zero-Muda and storage safety</summary>

- [x] CHK-05-MUDA — No dependencies introduced; global scan UNRUN.
- [x] CHK-06-GRAPH — Pure Gleam control changes; no new NIF.
- [ ] CHK-07-DRIVE — No storage operation; interlock suite UNRUN.

</details>
<details><summary>Domain 3 — Tests and mathematics</summary>

- [ ] CHK-08-C1C8 — Full browser categories UNRUN.
- [ ] CHK-09-MATH — Runtime refinement and four mathematical gates UNRUN.
- [x] CHK-10-9MOD — Scoped TDD/unit/actor and finite partition checks observed; other modalities UNRUN.
- [ ] CHK-11-REGR — Live UI monitoring UNRUN; model HUD/TUI checks passed.

</details>
<details><summary>Domain 4 — Cross-language control and observability</summary>

- [x] CHK-12-GLEAM — Actual isolated OTP transitions observed; full supervision UNRUN.
- [ ] CHK-13-HERMES — Formal integration UNRUN.
- [ ] CHK-14-ZIGVM — Kernel unchanged; checks UNRUN.
- [ ] CHK-15-MAX — Inference unchanged; checks UNRUN.
- [ ] CHK-16-OTEL — Live correlation UNRUN.

</details>
<details><summary>Domain 5 — Governance and Jujutsu</summary>

- [ ] CHK-17-SOV — Independent review and admission pending.
- [x] CHK-18-JJ — Standalone JJ, immutable predecessor/red snapshot, isolated workspace.

</details>
<details><summary>Domain 6 — Provenance</summary>

No historical admission or ledger rewrite. The previous component task completed only after parent-relayed independent approval; BOUNDS is separately claimed and awaits its own review.

</details>

**UOS footer:** Bounded implementation, NOT_ADMITTED. [Previous journal](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20260909-0320-ev-homeostasis-repair-journal.md) · [Next: planning](http://nas-1.tail55d152.ts.net:4100/planning)
