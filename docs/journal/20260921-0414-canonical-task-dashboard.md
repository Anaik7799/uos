# 20260921-0414 — Canonical task dashboard and execution optimization

#fractal-l0 #fractal-l1 #fractal-l2 #fractal-l3 #fractal-l4 #fractal-l5 #fractal-l6 #fractal-l7 #fractal-l8 #fractal-l9 #zk-adr #zero-muda

**UOS / Planning / Execution progress** · [Cockpit](http://nas-1.tail55d152.ts.net:4100/) · [Planning](http://nas-1.tail55d152.ts.net:4100/planning) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk)

[Source](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20260921-0414-canonical-task-dashboard.md) · [Rendered](http://nas-1.tail55d152.ts.net:4100/docs/journal/20260921-0414-canonical-task-dashboard.md) · [Evidence](http://nas-1.tail55d152.ts.net:4100/files/governance/planning/20260921-0414-canonical-task-dashboard-evidence.json) · [Plan](http://nas-1.tail55d152.ts.net:4100/files/docs/plans/20260920-1438-hive-swarm-mcp-recovery-plan.md) · [Risk](http://nas-1.tail55d152.ts.net:4100/files/governance/planning/20260921-0338-execution-optimization-risk.json)

Observed source-binding time: 2026-09-21T04:21:14Z. Canonical plan `uos/system-mcp-features/20260919-1642`, task `r13-task-dashboard`, worker `codex-01a0ba74-feature-tracker`, attempt 1.
**Development verification PASSED; no deployment, connected-client acceptance or system admission.** Final source hashes observed at 2026-09-21T04:25:46Z.

## 1. Scope & Trigger

Operator explicitly requested continued completion, dashboard tasks and an execution plan based on optimization criteria. Added r13 through Sa-plan rather than inventing a separate scheduler. This slice repairs the development planning view/API and adds a fenced read-only MCP progress handler. It does not close the other recovery/feature/hive actions. Formal Lean/Gospel invocation remains UNRUN.

## 2. Pre-State Assessment

At intake 1 of 19 canonical tasks was completed. Adding the explicitly requested dashboard action makes 20, not a retroactive change to prior observations. The existing page called c3i_nif plan functions whose unavailable implementation returns zero counts and an empty task list. It also presented unconditional P0 100% and historical health/pass panels. These are not current evidence.

The new actual read at 04:08:13Z observed 20 tasks: 1 completed, 1 executing and 18 blocked by risk or dependencies. This is a dated observation, not a static dashboard fixture. Kalman forecasting is not calibrated for these discrete task states; uncertainty is explicit instead of a fabricated readiness prior.

## 3. Execution Detail

Fresh toolchain preflight passed all 31 checks with Gleam 1.16.0 and OTP 29. Risk preflight passed at 04:00:12Z. Exact Sa-plan claim acquired r13 attempt 1. The first active check held because the portfolio still said available after the canonical claim; state was refreshed and active check passed at 04:00:31Z. Later source-bound active checks passed at 04:14:11Z and 04:21:16Z. No force-pass was used.

Implemented pure graph/status/ranking projection, bounded read-only canonical SQLite observation, escaped Lustre task table, all 18 checklist obligations, and per-call-fenced MCP dispatch. The full legacy planning page was replaced rather than leaving contradictory claims beside a truthful panel. Task mutations in private integration fixtures use actual Sa-plan CLI operations.

Tests were authored before missing modules; the first failure was compilation, not a behavioral RED claim. Subsequent compiler errors were corrected. Initial full suite: 11,888 passed and four API compatibility-field failures. Restored summary aliases from canonical values; review then caught a count/list mismatch, corrected by deriving both pending count and pending list from ReadyForPreflight. The new semantic regression covers both known and unknown risk.

The internal reviewer used only Gleam MCP source reads under r13. No external Claude/AGY ACK, provider recovery, production holon enrollment or independent runtime observation is invented. Rete-UL execution of this packet remains UNRUN.

Closure correction: the two attempted workflow activities at 04:27Z were rejected with `hierarchical name requires at least two segments`. The shell used semicolons, so workflow completion and task completion still succeeded at 04:27:10Z. Readback at 04:30Z confirms the workflow contains only start and completion, not those activities. No terminal history is rewritten or backfilled. Actual source/test/review receipts and the task result remain the development evidence; future dependent command sequences must use success chaining and hierarchical activity names.

## 4. Root Cause Analysis

ACH disconfirmation matrix (1 contradicts hypothesis; 0 remains consistent):

| Observation | H1: zero/healthy fallback is sufficient | H2: read canonical state and preserve unknown |
|---|---:|---:|
| Sa-plan contains unfinished tasks while the shim returns zero | 1 | 0 |
| Hardcoded P0 100% has no candidate-bound receipt | 1 | 0 |
| Expired risk must not recommend work | 1 | 0 |
| Missing DB must not create an empty replacement | 1 | 0 |
| Total | 4 | 0 |

The underlying failure was conflating syntactically valid default JSON and historical UI decoration with actual operational evidence. A second boundary error in the first new MCP dispatch omitted its per-call fence; review identified it before closure. A third issue equated legacy pending rows with all available rows while the summary counted only eligible recommendations. Shared derived predicates remove that contradiction.

## 5. Fix Taxonomy

Poka-Yoke: strict bounded decoding, duplicate/foreign identity and graph validation, receipt-required completion, HTML escaping, fixed plan/query and strict MCP arguments. Jidoka: unavailable DB/clock and unknown or stale assessments stop readiness claims. Muda: one canonical SELECT and pure bounded reverse-topological urgency fold; no extra queue, database, dependency, daemon or speculative retry.

## 6. Patterns & Anti-Patterns Discovered

Devil's Advocate cases include cycles, missing dependencies, incomplete/foreign risk portfolios, future completion receipts, expired worker leases, inconsistent assessment state, malformed dates, uncertain factors, missing databases, injected MCP arguments and markup-bearing titles.

Conservation: completed + executing + blocked + unknown + preflight candidates equals total. Input permutations preserve observations. A simple independent three-node reference interpretation checks propagated priority across 27 safety-class combinations. Consumer urgency can prioritize a prerequisite but cannot make that consumer eligible. A passing catalog stage, task receipt or score is never system admission.

## 7. Verification Matrix

Admiralty B2 here means directly observed development commands corroborated by source inspection, not independent operational certification.

| Check | Observation | Boundary |
|---|---|---|
| Toolchain preflight | 31 PASS | Toolchain only |
| New focused tests | 22 PASS | Pure/fixture/read-only integration |
| Earlier related suite | 134 PASS | Before compatibility additions |
| Compatibility-related suite | 402 PASS | Before final semantic/checklist additions |
| First full suite | 11,888 passed / 4 failed | Preserved compatibility counterevidence |
| Second full suite | 11,894 passed / 0 failed | Before final checklist-only addition |
| Final full suite | 11,894 passed / 0 failed, exit 0 | Includes final checklist candidate |
| Internal source review | Fence and count/list findings addressed | Source-only, no independent execution |
| Browser, deployed MCP, production hive and release | UNRUN | No admission |
| Formal engines / mathematical gates | UNRUN | No theorem claim |

Source hashes are in the linked receipt. Formatting checks apply only to new/replaced Gleam modules/tests, not unrelated legacy formatting. Journal lint is mechanical/textual; seven engine labels do not mean seven independent engines ran.

## 8. Files Modified

- `apps/cepaf_gleam/src/cepaf_gleam/planning/execution_projection.gleam`: pure typed status, graph, freshness and ranking.
- `apps/cepaf_gleam/src/cepaf_gleam/planning/execution_observer.gleam`: fixed-plan bounded read-only SELECT, risk decoding, hashes and functional query.
- `apps/cepaf_gleam/src/cepaf_gleam/ui/web/pages/execution_progress.gleam`: honest task table, provenance and 18 obligations.
- `apps/cepaf_gleam/src/cepaf_gleam/ui/web/pages/planning_page.gleam`: replace misleading legacy rendering.
- `apps/cepaf_gleam/src/cepaf_gleam/ui/wisp/router.gleam`: canonical planning JSON projection.
- `apps/cepaf_gleam/src/cepaf_gleam/harness/mcp.gleam`: discoverable strict fenced progress tool.
- `apps/cepaf_gleam/test/execution_projection_test.gleam`, `apps/cepaf_gleam/test/execution_observer_test.gleam`: 22 tests.
- Current risk portfolio, remediation manifest, human plan, this journal and source-bound receipt.

No Git mutation, JJ commit/bookmark/push or runtime restart is performed. Existing dirty source work is preserved. No agent-rule/hook/global/external mirror is changed; full mirror parity remains unverified.

## 9. Architectural Observations

`project(tasks, risks, now_ns, now_utc) -> Result(Snapshot, String)` is pure; `read_tasks(path)` is the effectful observation. `query(args, fence, read)` makes deny-before-read sequencing explicit. Production dispatch supplies the real fence and observer; positive fixture tests do not grant a real identity.

The dashboard bounds 256 tasks, 256 dependencies per task, 4,096 edges, 1 MiB subprocess output and a 3-second SQL process deadline. It uses one SQLite SELECT for task/edge coherence; portfolio and clock remain separate observations. Ranking is advisory and does not revalidate every source hash; a source-bound risk preflight is mandatory before claim. Source hashes identify observed bytes, not authenticated provenance.

The existing explicit development bootstrap SQLite/chrony exceptions remain disclosed in adapter_scope; no new package is installed. The finite historical MCP launcher grant is not impersonated or broadened. All 17 AINF aspects remain parent-plan obligations: this slice exercises task evidence, Gleam control, read-only storage, UI/JSON and Sa-plan; inference, kernel, formal, distributed and deployed client aspects remain unobserved. Sheaf/category-wide consistency is not proved by local conservation tests.

## 10. Remaining Gaps

The new page/API is a development candidate, not an observed production deployment. The MCP handler is listed and denial-tested; successful connected use still requires restored coordinator/grant authority and r03/r09 acceptance. Old planning SSE, secondary planning routes and other static dashboard claims remain for r05/r09 reconciliation.

r02 actual-history acquisition/provenance, t1 complete DB feature tracker, t2 algebraic service contracts, identity enrollment, all-service adapters, hive/swarm campaign and release/admission remain open. No blocked action is silently completed. Visual browser/accessibility checks and full uniform-navigation conformance remain UNRUN.

## 11. Metrics Summary

22 new tests cover the development slice; 27 bounded reference combinations check priority propagation and permutation/conservation. Existing failing-before API assertions remained unchanged and passed after compatibility repair. Completed task counts always come from the current DB response, never a constant in the view.

Bayesian Beta-Binomial updates would be invalid with correlated development cases and no calibrated prior, so no posterior readiness percentage is fabricated. Evidence half-life is represented by explicit expiry, not admission credit. Lyapunov dV/dt and production hive stability remain NOT_ESTABLISHED. Resource observations showed approximately 781 GiB workspace free and 22 GiB temporary storage free; these are not runtime reservations.

## 12. STAMP & Constitutional Alignment

Four UCAs: missing progress hides unfinished work; falsely provided completion permits unsafe action; stale/early observations misprioritize work; unbounded or repeated observation/effects continue after expiry. Controls are explicit unknown states, canonical dependencies/receipts, finite freshness/resource bounds and existing MCP effect fences.

All work and evidence workflow are registered in Sa-plan. Pure Gleam owns policy and existing bounded backends remain internal. Source review is advisory; deployment authority stays separate. OS storage, shared coordinator history and external sources are untouched. EV ceiling 93 and EV-94..109 NOT_ADMITTED are retained; no new EV is minted.

## 13. Conclusion

The planning development candidate now shows real canonical task state rather than a zero-count shim or historical health labels. The optimization plan prioritizes safety and dependency readiness, propagates prerequisite urgency and keeps uncertain/cost-unmeasured ordering honest. This is progress toward the user's full goal, not completion of that goal.

Final tests and the internal source-review follow-up passed. Closure records only r13's scoped development acceptance; other tasks and deployment remain open. The reader-facing checklist contains obligations, not fabricated passing states.

Canonical read-only closure observation at 2026-09-21T04:31:11Z: **2/20 completed, 0 executing, 18 blocked, 0 unknown**. Task snapshot SHA-256 `14fbfccd537db25e6c990ecaf8cc5eed8e1372ca5f6f0484b6c0794767248d37`. This is a dated observation, not full-goal completion.

Forecast: conditional on unchanged final source hashes and pinned OTP 29, p=0.95 that the first rerun of the 22 new tests before Horizon 2026-09-22T04:21:14Z passes. Outcome and Brier score (p-outcome)^2 are PENDING; changed conditions must be recorded.

### Comprehensive verification checklist

<details><summary>Domain 1 — Metadata and navigation</summary>

- [x] CHK-01-TIME — Host UTC/chrony observations and source hashes recorded.
- [x] CHK-02-TAIL — Full Tailnet links supplied; live delivery UNVERIFIED.
- [x] CHK-03-FRACT — L0–L9 scope explicitly tagged.
- [x] CHK-04-KM — Plan, evidence and journal linked; full KM sync pending.

</details>
<details><summary>Domain 2 — Purity and storage</summary>

- [x] CHK-05-MUDA — No new dependency; fleet exclusion audit not rerun.
- [x] CHK-06-GRAPH — Gleam policy with existing bounded backend.
- [x] CHK-07-DRIVE — Private fixtures and read-only canonical DB; no storage reconfiguration.

</details>
<details><summary>Domain 3 — Tests and mathematics</summary>

- [ ] CHK-08-C1C8 — Complete client/browser campaign UNRUN.
- [ ] CHK-09-MATH — Four invocation-specific mathematical gates UNRUN.
- [x] CHK-10-9MOD — Scoped property/reference, negative, regression and integration cases observed.
- [x] CHK-11-REGR — Final checklist candidate: 11,894 passed / 0 failed; prior four API failures retained.

</details>
<details><summary>Domain 4 — Control and observability</summary>

- [ ] CHK-12-GLEAM — Development OTP tested; deployed supervision not admitted.
- [ ] CHK-13-HERMES — Formal/evidence admission UNRUN.
- [ ] CHK-14-ZIGVM — Runtime kernel/VFS campaign outside this slice.
- [ ] CHK-15-MAX — Inference recovery not performed.
- [ ] CHK-16-OTEL — End-to-end trace correlation UNRUN.

</details>
<details><summary>Domain 5 — Governance</summary>

- [ ] CHK-17-SOV — Source review is not sovereign admission.
- [x] CHK-18-JJ — Standalone JJ retained; no VCS mutation by this task.

</details>
<details><summary>Domain 6 — Provenance</summary>

EV ceiling 93. EV-94..109 NOT_ADMITTED. No new EV. Task completion, source integrity and production authority remain distinct.

</details>

[Previous: recovery foundation](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20260921-0203-recovery-staging-foundation.md) · [Next: execution plan](http://nas-1.tail55d152.ts.net:4100/files/docs/plans/20260920-1438-hive-swarm-mcp-recovery-plan.md)

UOS footer: development evidence, not deployed availability or full-goal completion.
