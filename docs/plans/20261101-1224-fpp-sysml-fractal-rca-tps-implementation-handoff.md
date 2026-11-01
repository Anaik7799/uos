# 20261101-1224 — FPP and SysML fractal RCA, TPS and implementation handoff

**Observed:** 2026-11-01T12:36:24Z. The most recent chrony observation reported a normal leap state and approximately 0.00015 s system offset. Individual observations below retain their own times.  
**Status:** ADVISORY DRAFT / DEVELOPMENT WORK BLOCKED / NOT ADMITTED.  
**Purpose:** Preserve the operator's requested analysis and implementation plan. This document does not create a Sa-plan task, issue a grant, settle an effect, authorize deployment, or assert that the requested integration exists.  
**Scope:** FPP and SysML in Gleam/OTP and Lean, task-scoped agent control, MCP, Zenoh, system messaging, persistence and the required pinned development toolchain.

#fractal-l0 #fractal-l1 #fractal-l2 #fractal-l3 #fractal-l4 #fractal-l5 #fractal-l6 #fractal-l7 #fractal-l8 #fractal-l9 #km-triad #zk-adr #zero-muda

[UOS policy](http://nas-1.tail55d152.ts.net:4100/files/AGENTS.md) · [Risk SOP](http://nas-1.tail55d152.ts.net:4100/files/contracts/rules/20260907-1559-risk-prioritization-sop.md) · [Harness contract](http://nas-1.tail55d152.ts.net:4100/files/contracts/rules/20260909-0412-gleam-harness-agent-operation-contract.md) · [Recovery design candidate](http://nas-1.tail55d152.ts.net:4100/files/.uos-workspaces/codex-harness-recovery-20261101-0913/docs/design/20261101-0927-harness-recovery-and-fpp-sysml-integration.md) · [Recovery journal candidate](http://nas-1.tail55d152.ts.net:4100/files/.uos-workspaces/codex-harness-recovery-20261101-0913/docs/journal/20261101-0950-fpp-sysml-harness-recovery-journal.md) · [This handoff](http://nas-1.tail55d152.ts.net:4100/files/docs/plans/20261101-1224-fpp-sysml-fractal-rca-tps-implementation-handoff.md)

The links above are intended Tailnet locators; their live delivery and access to the isolated workspace have not been verified for this handoff. Knowledge references: [[wiki:20260905-1801-uos-zk-km-corpus-index]] and [[zk:20260905-1801-moc-uos-unified-master]]. Reciprocal registration, inventory update and publication remain pending.

## 1. Operator intent and constraints

Implement and test the supported FPP and SysML capabilities in Gleam and Lean; integrate them with MCP, Zenoh, applicable messaging and persistence; and provision the necessary compiler and related tools. Every development task should have a reviewed task-scoped grant covering all capabilities actually needed for that task, including source and knowledge access, build/test/proof, persistence, messaging and control of Codex, Claude, AGY and Pi. Define and test start, stop, status, cancellation, request/result, message delivery, recovery and applicable budget controls for each agent.

Sa-plan remains the sole task execution authority. Gleam/OTP owns supervision, control and policy; native and formal services remain bounded behind it. Use standalone Jujutsu, preserve existing candidate workspaces and the failed receipt, and provision packages through repository-pinned Nix/devenv inputs. External source trees remain read-only evidence. The admitted EV ceiling remains 93; EV-94 through EV-109 and ADR-071 through ADR-086 are not admission evidence. Mint no new EV number.

## 2. Current state and evidence

- The FPP/SysML plan is uos/fpp-sysml-integration/20261101-0852. Its REVIEW task is recorded complete and IMPLEMENT is recorded executing, but the 2026-11-01T12:15:58Z active risk check returned HOLD because the implementation lease expired and the assessments were stale.
- The harness-recovery plan is uos/harness-build-recovery/20261101-0913. Its REPAIR task is recorded executing and REVIEW is dependency-blocked. The 2026-11-01T12:23:08Z active check returned HOLD for an expired lease and stale assessments. State strings are not current execution authority.
- The original [build result](http://nas-1.tail55d152.ts.net:4100/files/var/harness/effects/20261101-fpp-sysml-dev@fpp-sysml-red-build@result.json) is FAILED_OR_UNVERIFIED. Its diagnostics show the esqlite build failing with cc: not found. The failed result lacks a post-effect manifest and end fence. Partial files and escaped processes cannot be ruled out from the exit status alone.
- The host has a compiler, but the canonical UOS Nix profile did not expose cc. The isolated recovery candidate profile resolved cc to Nix GCC 15.3.0; Gleam 1.16.0 and Lean 4.33.0 binaries responded to version probes. A prior candidate receipt records a successful C compile-and-run, but that does not repair or settle the original build.
- The default Jujutsu workspace parent was bc09f5d5d218 at the last observation. Existing uncommitted default-workspace changes included .codex/config.toml and docs/reviews/20261101-0854-fpp-sysml-grant-review.json. The FPP workspace contained two changed test files; those tests have not been observed running. The separate recovery workspace contained an unmerged source, toolchain, Lean and documentation candidate.
- The connected Gleam MCP system-health observation reported the KM brain healthy and the canonical triad intact. The private development MCP route was not exposed in this session; the uos_development configuration was disabled. Knowledge search did not expose the required limit parameter, while ZK transclusion was bounded to five results.
- At 2026-11-01T12:22:47Z, the local Zenoh observation reported reachable REST/TCP endpoints and a stopped subscriber, with degraded status. This does not prove end-to-end delivery or global Zenoh availability.
- A previous paid-model review reported an estimated USD 13.85694 against a configured USD 0.45 threshold. Its counters were internally inconsistent and actual provider charges were not independently reconciled. Keep further paid dispatch held until assembled-context measurement, a pre-dispatch spending bound and provider reconciliation are established.

## 3. Fractal root-cause analysis

| Layer | Observed or inferred failure | Falsifier or necessary follow-up |
|---|---|---|
| L0 governance | Required task authority and risk freshness are missing. | A fresh independently reviewed grant, Sa-plan lease and passing exact-owner active check establish the authorized scope. |
| L1 atomic effects | The failed build has no verified terminal post-effect fence. | Operation-specific evidence establishes outcome and containment without rewriting the receipt. |
| L2 components | The isolated profile omitted cc; the FPP parameter actor returns a count without durable storage; the SysML validator lacks several reference and direction checks. | Test the exact candidate profile, durable commit/readback and invalid model fixtures. |
| L3 transactions | A success response can precede persistence, and the failed-check path cannot safely classify unknown outcomes. | Crash, replay, duplicate and stale-fence tests show truthful outcomes. |
| L4 services | The private development route is unavailable and the observed Zenoh subscriber is stopped. | Observe connected task-scoped tools and acknowledged service delivery. |
| L5 agents | Agent client profiles do not prove start, stop, status, messaging or recovery through the task route. | Exercise each required operation for Codex, Claude, AGY and Pi under authenticated task identity. |
| L6 ecosystem | Gleam, Lean, persistence and transport contracts are not demonstrated as one implementation. | Candidate-bound shared fixtures and runtime evidence show the declared supported behavior. |
| L7 federation | Reachable endpoints do not establish authenticated, durable cross-host delivery. | Test addressed delivery, disconnect, replay, deduplication and recovery with actual participants. |
| L8 evolution | The compiler and recovery candidate are isolated; the original task remains held. | Review and test the exact candidate and its migration/recovery path before any authorized cutover. |
| L9 verification | Written FPP/SysML regressions were not run; abstract Lean results do not establish implementation refinement. | Fresh tests, proof checks and independent candidate-bound review cover the declared scope. |

Competing explanations: a missing compiler everywhere is contradicted by the host and candidate-profile observations. The narrower explanation, an incomplete restricted profile, is supported by the failed build receipt. If the correctly pinned compiler is visible inside the actual task-bound build and the same failure persists, investigate resolver, environment and process boundaries before changing packages again.

## 4. Criticality and FMEA

The following are preliminary analyst estimates, not measured probabilities or Sa-plan authorization. C is criticality, T is STPA exposure, F is the severity-floored FMEA band, Dep is dependency importance and I is impact. Each factor uses the local 1–5 rubric. O is unknown and ranges from 1 to 5; D is provisional. Score is C × T × F × Dep × I. Reassess against fresh source, exposure, effects and ownership before selecting tasks.

| Failure mode | S / O / D | RPN range | C / T / F / Dep / I | Score |
|---|---:|---:|---:|---:|
| Unknown effect or stale owner allowed to act | 5 / 1–5 / 4 | 20–100 | 4 / 4 / 5 / 5 / 5 | 2000 |
| Missing compiler or cold-build timeout | 4 / 1–5 / 3 | 12–60 | 4 / 3 / 4 / 5 / 4 | 960 |
| Save acknowledged before durable commit | 4 / 1–5 / 4 | 16–80 | 4 / 4 / 4–5 / 3 / 4 | 768–960 |
| Lost, duplicated or unauthorized messages | 4 / 1–5 / 4 | 16–80 | 3 / 4 / 4–5 / 4 / 4 | 768–960 |
| Invalid model or unsupported proof treated as verified | 5 / 1–5 / 4 | 20–100 | 3 / 4 / 5 / 3 / 4 | 720 |

Safety class and dependency readiness precede score. The ranges overlap and do not justify a forced order among independent eligible persistence, messaging and model slices. No current uncontrolled unsafe effect was established; treat the affected release and recovery boundaries as P1 holds. Raise or lower class only on fresh evidence. Record pre-control and residual ratings separately.

## 5. STPA and fractal TPS controls

| Unsafe control action | Example | Constraint and acceptance evidence |
|---|---|---|
| Required action not provided | A missing grant, unknown effect or unavailable durable store does not stop the operation. | Jidoka: refuse or hold; tests must show the stop and a retained reason. |
| Unsafe action provided | Save returns success before commit or an invalid model is reported valid. | Poka-yoke: typed failure and model validation; negative fixtures must fail. |
| Wrong timing or order | An effect runs after lease expiry or an acknowledgement precedes durable commit. | Fence at the effect boundary and commit before acknowledgement; inject expiry and crash faults. |
| Too long or stopped too soon | An agent, worker, grant or retry persists beyond its scope, or cleanup ends while children remain. | Bound deadlines and budgets; verify cancellation, containment and recovery. |

Use standardized task records, exact effect identities and single-flight bounded work. Heijunka pulls dependency-ready slices with limited work in progress. Zero-muda reuses the realized pinned compiler and prior valid evidence without treating historical receipts or heartbeats as current proof. Unknown outcomes never become successful or known-not-applied merely from a nonzero exit.

## 6. Proposed implementation sequence

These are descriptive slice labels, not registered Sa-plan task IDs. Obtain fresh risk evidence, current ownership and the complete reviewed task-scoped grant before each effect.

1. **P1 — Restore the development route and authority.** Connect the private development MCP or admitted Zenoh ingress. Refresh the complete risk assessment, establish the exact plan/task/worker/attempt and lease, and verify required full task-scoped capabilities and refusals. Do not use a heartbeat as a Sa-plan lease renewal.
2. **P1 — Preserve and recover the failed effect.** Hash and retain the original intent, result and partial workspace. Implement and independently review operation-specific adjudication, current ownership, containment and effect-time fencing. Inject stale lease, timeout, partial output, malformed receipt, duplicate intent and escaped-child scenarios. Keep the original effect held unless its actual outcome is established.
3. **P1 prerequisite — Provision and verify the toolchain.** Bind the Nix compiler, linker, OTP, rebar3, Gleam, Lean, lockfile and candidate hashes. Select and pin the required official FPP and SysML reference tools. Verify a real C compile, an esqlite port-driver build and a cold candidate build within an explicitly justified worker bound. The earlier isolated cold build was recorded at 82.17 s against a 60 s harness bound; do not substitute a warm-cache timing.
4. **P1/P2 — Make domain behavior truthful.** In the FPP parameter actor, fail closed while a durable owner is unavailable; propagate FPP actor initialization errors. In the SysML validator, reject duplicate IDs, missing subparts and requirement references, unresolved satisfaction references and incompatible port directions. Treat verification labels as declarations until bound evidence is checked. Run existing regression tests red, implement, then run them green.
5. **P1/P2 — Implement durable ownership.** Add a supervised, bounded persistence owner for parameters, models and message outbox state, using an assessed repository storage seam. Acknowledge only after an identified commit. Test concurrent updates, duplicate requests, crash before/after commit, restart/readback and ambiguous outcomes.
6. **P1/P2 — Formal and reference evidence.** Specify the supported FPP/SysML subset and invariants in Lean. Bind theorem statements, toolchain, sources, complete import closure and shared fixtures. Compare supported cases with pinned reference tools. The recorded imported-wrapper Lean audit has known adversarial false-pass paths; require trusted audit completion and kernel replay before treating it as a proof-admission mechanism. Abstract theorems alone do not prove Gleam refinement.
7. **P1/P2 — MCP, Zenoh and agent control.** Expose typed task-fenced model and persistence operations; add or qualify an admitted Zenoh bridge. Implement authenticated identities, addressed delivery, correlation, acknowledgements, stable idempotency, backpressure and recovery. Test start, stop, status, cancellation, request/result and messaging for all four named agents. A transport acknowledgement is not a durable commit.
8. **P1 release gate — End-to-end verification and documentation.** Run candidate-bound Gleam and Lean checks, reference comparisons, persistence fault/restart tests, MCP and Zenoh delivery tests, agent-control tests and relevant repository gates. Bind applicable 17-aspect, STPA/FMEA and two-key evidence. Update the task's 13-section journal, wiki/ZK/inventory references and the 18-core-check/provenance structure. Production cutover and recovery remain separately authorized.

The historical [isolated recovery precedent](http://nas-1.tail55d152.ts.net:4100/files/governance/planning/20261028-2310-pipe-recovery-scope.json) supports a separately reviewed task and fresh workspace while the old failure remains held. It does not authorize changing the old result, retrying the old logical effect, bypassing deduplication or assuming no remote effects.

## 7. Acceptance and stop conditions

Acceptance requires the exact candidate to demonstrate: task-bound grant and current lease; compiler provenance and functional build; honest save and restart behavior; invalid model rejection; Lean statement/import binding and proof checks; authenticated, acknowledged MCP/Zenoh communication; and complete agent lifecycle operations within the task scope. All required negative cases must refuse or remain unknown as specified.

Stop and retain evidence on a stale lease, changed candidate, unknown effect outcome, missing tool, unsupported model construct, incomplete proof audit, unacknowledged delivery, unverified commit or unknown paid-provider liability. Do not infer runtime admission from a task completion, a catalog, a review or a historical green count.

## 8. Six-domain verification checklist

This is a planning handoff, not a completion claim. Unchecked entries are pending.

<details><summary>Domain 1 — Metadata, timestamp and navigation</summary>

- [x] CHK-01-TIME — Host UTC and a chrony observation are recorded for this draft.
- [ ] CHK-02-TAIL — Verify live Tailnet delivery and exact bytes after authorized publication.
- [x] CHK-03-FRACT — Applicable L0–L9 layers are identified as analysis scope.
- [ ] CHK-04-KM — Register and verify reciprocal wiki, ZK, inventory and task-journal links.

</details>
<details><summary>Domain 2 — Zero-Muda and storage safety</summary>

- [ ] CHK-05-MUDA — Check excluded dependencies and source on the candidate.
- [ ] CHK-06-GRAPH — Verify language and native-kernel boundaries in scope.
- [ ] CHK-07-DRIVE — Verify relevant storage interlocks without affecting protected devices.

</details>
<details><summary>Domain 3 — Tests and mathematical gates</summary>

- [ ] CHK-08-C1C8 — Run applicable C1–C8 checks.
- [ ] CHK-09-MATH — Evaluate the applicable four mathematical gates.
- [ ] CHK-10-9MOD — Run applicable unit, property, integration, fault and performance modalities.
- [ ] CHK-11-REGR — Bind regressions and results to the exact candidate.

</details>
<details><summary>Domain 4 — Cross-language control and observability</summary>

- [ ] CHK-12-GLEAM — Observe OTP supervision and restart behavior.
- [ ] CHK-13-HERMES — Verify bounded analysis and evidence services in scope.
- [ ] CHK-14-ZIGVM — Verify kernel and VFS behavior where affected.
- [ ] CHK-15-MAX — Verify isolated inference and model access where affected.
- [ ] CHK-16-OTEL — Bind actual clock, trace and telemetry observations.

</details>
<details><summary>Domain 5 — Sovereign governance and Jujutsu</summary>

- [ ] CHK-17-SOV — Obtain applicable independent review and effect authority.
- [ ] CHK-18-JJ — Reconcile the final standalone JJ candidate and Sa-plan receipts.

</details>
<details><summary>Domain 6 — Provenance extension</summary>

- [x] Preserve EV-93 as the admitted ceiling; EV-94–109 and ADR-071–086 are not admission evidence. No new EV identifier is assigned by this document.
- [ ] Verify candidate-bound provenance and live publication before claiming completion.

</details>

[Planning cockpit](http://nas-1.tail55d152.ts.net:4100/planning) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk) · [Main cockpit](http://nas-1.tail55d152.ts.net:4100/)

## 20261101-1248 — Pi, AGY and temporary-quota preflight

Observed 2026-11-01T12:50:48Z. These are time-bounded observations, not task authority or production admission.

- Herdr identified an existing Pi session and an AGY session. The AGY session was working and its visible screen carried an Argon label. The Pi screen showed google/gemini-4-argon and was waiting for a project MCP-server approval prompt, despite Herdr reporting idle with screen detection skipped. No prompt response or new agent task was sent.
- The Pi prompt names the project server uos-gleam and the tools/uos-mcp-stdio executable. The inspected .mcp.json entry configures the public route; connecting it would not by itself provide the missing private development route, task grant or Sa-plan lease.
- Pi displayed a session cost indicator of USD 11.894. Its accounting period and actual provider charge were not verified. The earlier unresolved provider-liability and pre-dispatch budget holds remain in force.
- The current session still exposed no private development MCP tools. An attempted recovery risk check returned write(): Disk quota exceeded, so it did not produce a fresh passing observation. Earlier active checks recorded expired leases and stale assessments.
- At 2026-11-01T12:52:03Z the same report-only recovery check ran with its supported TMPDIR setting pointed inside the workspace. It returned HOLD for the expired lease and stale assessments. This bounded temporary-directory setting did not renew authority or repair the /tmp quota and sandbox failure.
- Filesystem inspection showed /tmp mounted as tmpfs with usrquota, approximately 4.4 GiB globally available, and about 17,887.6 MiB allocated to user-owned regular files that were accessible to the bounded scan. The quota utility was unavailable; the precise per-user limit and exact cause of the quota error were not established.
- The largest observed user-owned temporary directories included /tmp/uos-recovery-kernel-20261031 at about 1608 MiB, /tmp/uos-reclaim-store-20261031 at about 855 MiB, and /tmp/zigvm-call-ext-local at about 834 MiB. Their contents, liveness and disposability were not established. Nothing was deleted or moved.

Next: diagnose or adjust the temporary quota through its owner, preserve recovery evidence, establish the private task-scoped route and independently reviewed grant, refresh the complete risk assessment and lease, and only then dispatch Pi or AGY within their authorized scopes. A public MCP approval, a running peer, a session cost display or a status message is not an execution grant.

## 20261101-1320 — Operator request for a comprehensive development grant

Recorded 2026-11-01T13:03:20Z. The operator requested: “give broad comprehensive grant so that the full workpackage can be completed.” This is authorization to prepare the complete development scope, not a claim that a grant was issued, a review was completed, a lease is current, or production effects are admitted.

**Required work-package envelope:**

- Cover the full development and verification work: harness recovery and effect adjudication; pinned compiler, linker and reference-tool provisioning; FPP and SysML Gleam models; Lean specifications and proof checks; supervised persistence; MCP and Zenoh interfaces; system messaging; end-to-end tests; task evidence, journals and KM documentation.
- Cover the actual task-scoped operations needed to complete those slices: knowledge and source reads, candidate writes, builds, tests, proof checks, risk assessment, canonical planning operations, persistence and messaging, plus authorized start, stop, status, cancellation, request/result and recovery for Codex, Claude, AGY and Pi. Enumerate exact admitted operations and paths in each reviewed machine grant; do not silently drop an operation needed by the work package.
- Bind each materialized grant to the actual agent/session, worker, registered workspace, exact Sa-plan tasks and attempts, candidate/source hashes, review digest, host/boot identity, bounded expiry and current lease. Provide a reviewed renewal path. The current successor schema has one worker, session and workspace per grant, so a shared work-package authorization requires distinct bindings for different agents or workspaces.
- Keep the scope to this development work package. No grant in this handoff authorizes production cutover, secret export, unrelated resources, deletion of unknown artifacts, or bypass of effect-time fencing. The user-authorized work package and the executable machine grant must be reconciled before use.

**Observed obstacles to issuing an executable comprehensive grant:**

1. The prior reviewed grant 20261101-fpp-sysml-dev was issued for one Codex worker and a first FPP/SysML slice. It explicitly deferred a durable backend, Lean writes/proofs, Zenoh messaging and model access. Its grant expiry was 2026-11-01T12:57:20.374Z; its Sa-plan implementation lease expired at 10:10:00.876Z. Its narrow review cannot be reused as an approval of the broader proposal.
2. The private successor server is disabled in the inspected project configuration and no private development route was exposed in this session. Its configured grant path and digest variables were not present in the inspected process environment. The Pi approval prompt targets the public route and does not provide this binding.
3. In the inspected current successor source, grant writes are exact path lists and the validator admits only prepare, status and rollback as client actions. Its source-path rules do not admit Lean or Nix file writes needed by the requested envelope. The selected capsule source manifest matched the inspected admission and client-MCP source hashes; an end-to-end live negative grant test was not performed.
4. The isolated recovery candidate adds recognition of Lean and selected Nix/toolchain source paths, but remains unmerged and requires its own tests and independent review. Its existence is not proof that every requested client action or tool is supported.
5. The grant check requires a hash-bound reviewed proposal and a completed canonical Sa-plan review by a different worker and session. The recovery task is on HOLD for an expired lease and stale assessment. The original failed-build effect remains unresolved. There is no evidence here that the operator withheld authorization or why the private server was disabled.

**Poka-yoke and recovery sequence:** restore or establish a separately authorized issuer/review path; refresh source-bound risk and exact task ownership; implement and test the missing grant and agent-control capabilities in a bounded candidate; independently review the full enumerated proposal; issue the identity-bound grants and connect the private route; then verify positive and negative task-fence cases before execution. Preserve the old grant and failed effect as historical evidence. A broad request, draft scope, public MCP connection, or local configuration change is not itself an executable grant.

UOS footer: an advisory handoff and prior component observations do not grant task execution, production deployment or system admission.

