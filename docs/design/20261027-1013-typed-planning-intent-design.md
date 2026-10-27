# Typed planning intent development slice

#fractal-l0 #fractal-l3 #fractal-l4 #fractal-l9 #zk-adr #zero-muda

[Planning](http://nas-1.tail55d152.ts.net:4100/planning) · [Canonical policy](http://nas-1.tail55d152.ts.net:4100/files/AGENTS.md) · [Design](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20261027-1013-typed-planning-intent-design.md)

State: authorized bounded development design, not implementation or admission. Canonical task PLANNING_MCP in uos/hive-development/20261027-0532. Existing full user authorization governs; the coordinator selected this narrow design from the current source and peer advice.

## Purpose and boundary

First local-development planning MCP slice; standard sa_bridge_submit and production remain unavailable. The current standard sa_bridge_submit remains a truthful refusal. This first slice adds one tool to the private, reviewed development harness; it does not assert normal-client integration or full development readiness.

## Closed interface

```text
PlanningIntent = CreatePlan | CreateTask | PublishEvidence
PlanningOutcome = Applied | Replayed | Refused | Uncertain
```

Each intent has a stable logical ID. Trusted task/session identity comes from the serving execution, not the payload. Approved target plan: `uos/development/planning-proof/20261027-1013`. No multi-intent transaction is asserted.

1. Current trusted Execution supplies parent task/session/worker/attempt/epoch. Caller role, identity, SQL, shell and backend fields are refused.

2. Only an explicit immutable planning_targets allowlist in the reviewed grant authorizes sandbox plans; no arbitrary canonical targets. Evidence writes must be allowed md/json paths, never code/config.

3. Use actual sa_plan_bridge.run_sa_plan_cli literal argv and canonical JSON readback; do not use pure create_plan/create_task constructors as persistence.

4. Use one exclusive intent/result file pair per stable hash(parent plan, parent task, logical ID) in existing var/harness/effects; no shared JSONL append, no new directory requirement. Key excludes grant/attempt; payload hash conflicts refuse.

5. Never equate nonzero exit with pre-effect refusal. Only proven pre-dispatch validation refuses with no effect. Timeout/nonzero/readback failure is uncertain unless an operation-specific oracle reconciles it. Same logical ID pending never redispatches.

6. No cross-command atomicity or hostile-writer/production guarantee. Existing before/after bounded lease fences remain cooperative; report native transactional-fencing gap explicitly.

7. Register 14th private tool in operations names/schema and successor dispatch. Include the new interpreter in admission.control_modules for activation. Existing13 tools retain behavior.

8. Keep original six test modules so a fresh84-test baseline can run BEFORE edits; add planning tests to existing harness_successor_test. WatchRED before implementation, thenGREEN; test malformed/unknown/duplicate keys, scope, literal argv, replay/conflict/uncertainty and cross-grant stable IDs.

9. Real canonical sandbox create/read/publish and lost-reply checks happen only after separate candidate-bound activation review. Do not complete PLANNING_MCP from unit tests alone.

## Acceptance and decision rationale

Run a fresh original six-module control canary before editing. Preserve its14-source baseline except the explicitly scoped implementation files. Tests must distinguish prevalidation refusal from backend uncertainty, payload conflict from replay, and canonical observation from inferred success. A simulated missing transport reply must not duplicate a logical operation. Source-bound unit/property tests precede independent activation; actual sandbox create/read/publish is the runtime acceptance gate.

The utility is removal of repeated administrative bootstrap and concrete schema mistakes. Alternatives were repeating the bootstrap (waste) or exposing a generic command runner (excess authority). Source inspection shows the native Store has transactions and bridge receipts, but two CLI calls are not one transaction. Local cooperative fences and bounded process windows are retained; native atomic revocation/creation and full transitive binary provenance are not claimed. No new framework, package, external inference call or production change.

## Rollback and residuals

Stop only the owned development process, release exact current task/workspace fences, preserve all intent/results and return to the observed baseline. Unknown outcomes require operation-specific reconciliation; no blind reset, rollback or retry. Larger assessment scaling, standard-client registration, client adoption and full hive/Telegram acceptance remain separate open tasks.

## Comprehensive verification checklist

All entries are obligations; this design alone grants no pass.

<details>
<summary>Domain 1 — Metadata, timestamp and Tailscale navigation</summary>

- [ ] **CHK-01-TIME** — `YYYYMMDD-HHSS-` prefix present; host clock observed 2026-10-27.
- [ ] **CHK-02-TAIL** — Full Tailnet links provided above; live serving status not asserted here.
- [ ] **CHK-03-FRACT** — L0, L1, L3, L4, L9 tags assigned to the layers this contract governs.
- [ ] **CHK-04-KM** — ZK and wiki transclusions plus journal and review links resolve to existing artifacts.

</details>

<details>
<summary>Domain 2 — Zero-Muda purity and storage safety</summary>

- [ ] **CHK-05-MUDA** — Dependency exclusion scan UNRUN by this package; no dependency introduced.
- [ ] **CHK-06-GRAPH** — Pure BEAM/Hermes graph boundary UNRUN here.
- [ ] **CHK-07-DRIVE** — OS storage interlock execution UNRUN; no host serial appears in this document.

</details>

<details>
<summary>Domain 3 — Testing Gold Standard and mathematical gates</summary>

- [ ] **CHK-08-C1C8** — UI categories not applicable to this package; UNRUN.
- [ ] **CHK-09-MATH** — The four mathematical gates UNRUN here.
- [ ] **CHK-10-9MOD** — Nine test modalities UNRUN here.
- [ ] **CHK-11-REGR** — UI regression monitoring UNRUN here.

</details>

<details>
<summary>Domain 4 — Cross-language control and observability</summary>

- [ ] **CHK-12-GLEAM** — Supervision behaviour not observed by this package; the cited refusals are harness observations recorded in the linked journals.
- [ ] **CHK-13-HERMES** — Bounded analysis and evidence ledger behaviour UNRUN here.
- [ ] **CHK-14-ZIGVM** — Deterministic kernel and VFS UNRUN here.
- [ ] **CHK-15-MAX** — Isolated inference UNRUN here.
- [ ] **CHK-16-OTEL** — Runtime telemetry correlation UNRUN here.

</details>

<details>
<summary>Domain 5 — Sovereign governance and standalone Jujutsu</summary>

- [ ] **CHK-17-SOV** — Independent review of this document is OUTSTANDING; NOT_ADMITTED.
- [ ] **CHK-18-JJ** — Authored under standalone JJ discipline; no native Git mutation used.

</details>

<details>
<summary>Domain 6 — Provenance and admission integrity</summary>

- [ ] **CHK-19-CEIL** — EV ceiling 93 stated; EV-94..109 marked NOT_ADMITTED; no EV claim made.
- [ ] **CHK-20-INDEX** — KM index enumeration of this new record UNRUN.
- [ ] **CHK-21-PRESERVE** — Additive only; no historical artifact rewritten, and the v1 grant failure is preserved.
- [ ] **CHK-22-CHAIN** — Cycle-chain verification UNRUN by this package.
- [ ] **CHK-23-NOMINT** — No new EV number minted.
- [ ] **CHK-24-FAILCLOSED** — Metric-path fail-closed runtime behavior UNRUN in this documentation scope; no passing claim.

</details>

**UOS footer:** `nas-1.tail55d152.ts.net:4100` · Sa-plan is the sole execution authority; this contract grants no admission.
