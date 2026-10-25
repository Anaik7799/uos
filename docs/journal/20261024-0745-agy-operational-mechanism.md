# AGY operational mechanism — development verification

Observed: 2026-10-24T07:02:45.981Z. #fractal-l0 #fractal-l3 #fractal-l5 #fractal-l9 #zk-adr #zero-muda

[Cockpit](http://nas-1.tail55d152.ts.net:4100/) · [Planning](http://nas-1.tail55d152.ts.net:4100/planning) · [Evidence](http://nas-1.tail55d152.ts.net:4100/files/governance/planning/20261024-0702-agy-dispatch-verification.json)

## 1. Scope & Trigger

Plan uos/agy-operations/20261024-0642, RUNNER attempt 1, worker codex-analysis-20261024. Deliver a reusable Gleam development interface for actual Gemini 4 Argon High jobs. Candidate c9b9c6a08d4a68fc2b1e13ec3628509a6209831b is independently reviewed; production and global admission are excluded.

## 2. Pre-State Assessment

A prior unrestricted AGY session wrote invalid coordinator events. The coordinator was independently restored with originals preserved. Separate CLI runs returned exit zero and SUCCESS despite timeout and empty response. Ad hoc launches therefore could not establish completion. Global MCP discovery also loaded 13 unnecessary server configurations.

## 3. Execution Detail

The new interface is agy_dispatch_cli with two operations: launch REQUEST_FILENAME and collect REQUEST_FILENAME. Request files reside only in the private pre-provisioned runtime directory /home/an/uos-agent-runtime/20261024-0555.

1. Create and claim a canonical Sa-plan job under the current parent task. Its arguments must bind plan, task, parent_worker, parent_attempt, workspace and mode.
2. Keep the parent coordinator session heartbeat fresh and acquire its hashed task resource plus the exact sibling workspace lease.
3. Supply a private request with plan/task/worker/attempt/session/epoch, job/job_worker/job_attempt, workspace/workspace_epoch, mode (review or code), seconds (30–900), and prompt (at most 65,536 bytes). Workspace is a single directory component under .uos-workspaces.
4. Launch through the compiled Gleam CLI. The only successful launch state is DISPATCHED_NOT_COMPLETE. No automatic retry follows ambiguous launch; active-job.json preserves the exact request.
5. Collect after the process exits. A current canonical parent/job claim and coordinator authority are required. MODEL_RESPONSE_COMPLETE_REVIEW_REQUIRED describes only a model response.
6. Independently inspect its source, tests or review verdict before explicit canonical job/task completion.

The verified invocation uses the pinned Erlang executable, cached library ebin paths, and fresh var/recovery-runtime/20261024-0651-agy-dispatch/build/ebin first. The precise invocation and outcomes are in the linked machine-readable receipt. The private profile contains authentication material and must never be copied into UOS.

Full automatic tool approval uses the supported accept-edits mode and --dangerously-skip-permissions. Named auto mode is unavailable on this installation. The host filesystem is read-only in the worker; code mode additionally binds only the selected workspace writable. Global .gemini configuration is hidden, and the actual isolated MCP inventory reports no configured servers. Filtered authentication IPC exposes only the secret service. Existing pinned/cached components are reused; no package installation occurred.

## 4. Root Cause Analysis

ACH — H1: CLI success proves completed work. Disconfirmed by the preserved empty SUCCESS timeout. H2: a valid nonempty result, actual process outcome, current authority and separate acceptance evidence are needed. Supported by the new classifier and live launch/collect test.

The initial dispatcher integration assumed the existing development helper allowed longer job windows. Its 70-second bound correctly refused launch. The fix retains that bound for the short launch operation, then explicitly checks UTC task and boot-domain coordinator leases cover the entire finite job plus margin. A stale heartbeat also refused execution. Both failures occurred before launch artifacts.

## 5. Fix Taxonomy

Poka-Yoke: identity, scope, path and byte bounds; canonical job-parent binding; exclusive request receipt; finite process-tree lifetime. Jidoka: stale/unknown/timeout outcomes remain nonpassing. Muda reduction: compact evidence packets, one active job, no unused global MCP servers, and no second agent framework.

## 6. Patterns & Anti-Patterns Discovered

Devil's Advocate: an isolated model can still return wrong code. AGY's test source omitted a type import; Codex repaired that import before tests ran. Model labels, process existence and formatted local telemetry are not proof of inference or goal completion.

The installed process_with_agy source function formats local telemetry with fixed confidence; it is distinct from this actual model dispatcher. No claim of globally optimal learning is made. Improvements are retained only with observed acceptance and preserved counterevidence.

## 7. Verification Matrix

Admiralty B2 applies to direct Codex observations below. AGY static review is clearly separate from execution.

| Check | Result | Scope |
|---|---|---|
| Fresh private Gleam build | PASS | Existing cached dependencies; transitive-dependency warnings recorded |
| Classifier and dispatcher regression suite | 14 PASS, 0 FAIL | Empty SUCCESS, timeouts, bad JSON, byte limits, identities, scopes and both lease clock domains |
| Wrong canonical job attempt | HOLD as required | No active-job receipt or model launch |
| Host write isolation probe | EROFS | Prior actual bwrap probe; owned workspace writable only in code mode |
| Private MCP inventory | No configured servers | Observed after global Gemini configuration was hidden |
| Actual launcher | DISPATCHED_NOT_COMPLETE | Job dispatch-review2, exact request digest |
| Actual collection | MODEL_RESPONSE_COMPLETE_REVIEW_REQUIRED | Current authority rechecked; durable receipt and unit cleanup |
| AGY independent review | PASS | Exact c9b9c6 candidate, no findings; static supplied-source scope |
| Model operation | 48.535 seconds; 23,810 tokens | Actual Gemini 4 Argon High conversation 1b7c9e5a-df5a-4b63-b996-ad9de1250f7b |
| Full application/global admission | NOT_GRANTED | Separate remaining goals |

## 8. Files Modified

Five owned sibling-workspace files: src/agy_dispatch_cli.gleam; src/cepaf_gleam/harness/agy_dispatch.gleam; src/cepaf_gleam/harness/agy_job_result.gleam; test/agy_dispatch_test.gleam; test/agy_job_result_test.gleam. AGY implemented the result module and tests; Codex integrated the dispatcher and corrected the test import. Source hashes are bound in the receipt. Standalone Jujutsu main remains unchanged.

## 9. Architectural Observations

Gleam owns validation, canonical observation, dispatch and result classification. Existing bounded OS adapters launch finite systemd/bwrap jobs. Sa-plan owns task/job state. No model result automatically completes a task or grants release authority. This is a finite development mechanism using an existing private profile, not a general production model service.

## 10. Remaining Gaps

Automatic 300-second/task-completion dashboard refresh and actual browser acceptance remain pending. Telegram's commands, media, gateway, Mini App, live acceptance and release remain incomplete. Same-user hostile host interference is outside this boundary. The caller maintains coordinator heartbeat; stale collection refuses successful classification. Recovery from an ambiguous launch requires explicit inspection of preserved receipts; no automatic retry is implemented.

## 11. Metrics Summary

The source-review packet workflow returned a usable review in 103 seconds and 20,408 tokens. The later coding task completed in 137 seconds and 43,920 tokens; the actual new-launcher review completed in 48.535 seconds and 23,810 tokens. These different tasks are not a controlled model benchmark. Bayesian calibration and a negative Lyapunov derivative are not established by these samples. No task-count percentage is presented as functional coverage.

## 12. STAMP & Constitutional Alignment

Not provided: refuse missing evidence instead of inventing success. Unsafe provision: deny mismatched task/job/workspace authority and canonical host writes in AGY. Wrong timing: check both clock domains and reject stale heartbeat/lease. Excess duration: finite process-tree lifetime and result collection. EV ceiling 93 remains unchanged; no new cycle or global admission is asserted. Independent release safeguards remain active.

<details><summary>Verification domain 1</summary>

- [ ] CHK-01 — Clock: observed chrony, timestamp present
- [ ] CHK-02 — Tailnet: current HTTP probes in receipt
- [ ] CHK-03 — Fractal: L0 policy,L3control,L5learning,L9evidence
- [ ] CHK-04 — Knowledge links: current/prior report linked

</details>

<details><summary>Verification domain 2</summary>

- [ ] CHK-05 — Zero-Muda: full scan UNRUN; new Python writer violates boundary
- [ ] CHK-06 — Pure graph boundary: unchanged, UNRUN
- [ ] CHK-07 — Storage interlock: no disk mutation; hardware validation UNRUN

</details>

<details><summary>Verification domain 3</summary>

- [ ] CHK-08 — C1-C8: full browser suite UNRUN
- [ ] CHK-09 — Mathematical gates: full set UNRUN
- [ ] CHK-10 — Test modalities:82scopedTelegram cases; not all modes
- [ ] CHK-11 — Regression: coordinator recovered; application release pending

</details>

<details><summary>Verification domain 4</summary>

- [ ] CHK-12 — Gleam: typed coordinator replay blocks; unauthorized writer bypass observed
- [ ] CHK-13 — Hermes: canonical Sa-plan status observed
- [ ] CHK-14 — ZigVM: current execution evidence UNKNOWN
- [ ] CHK-15 — MAX: live inference UNRUN
- [ ] CHK-16 — OTel: full trace correlation UNRUN

</details>

<details><summary>Verification domain 5</summary>

- [ ] CHK-17 — Sovereign: no release/system admission
- [ ] CHK-18 — JJ: main unchanged, no nativeGit mutation

</details>



## 13. Conclusion

The development mechanism has passed its scoped acceptance checks and a real model invocation. Forecast: the next admitted use should produce either a bounded model response or an explicit nonpassing result; this is an uncalibrated conditional prediction with a 15-minute Horizon after that invocation. No Brier score is assigned until an on-time outcome is observed.

[Previous dashboard](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20261024-0653-project-state-dashboard.md) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk)

UOS footer: development verification does not grant system admission.
