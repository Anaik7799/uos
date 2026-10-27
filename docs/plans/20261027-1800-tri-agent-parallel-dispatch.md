# 20261027-1800 — Tri-agent parallel dispatch plan

#fractal-l0 #fractal-l3 #fractal-l4 #fractal-l9 #zk-adr #zero-muda #tailscale-web

[This dispatch](http://nas-1.tail55d152.ts.net:4100/files/docs/plans/20261027-1800-tri-agent-parallel-dispatch.md) · parent plan [20261027-1747](http://nas-1.tail55d152.ts.net:4100/files/docs/plans/20261027-1747-symbiosis-hive-execution-plan.md) · [Cockpit](http://nas-1.tail55d152.ts.net:4100/)

Operator: use Pi, Claude and Codex to execute the plan with max parallelization. This records lanes, ownership and the transport boundary. No task here grants authority or admission.

## As-is (verified)

- Pi session: live; did Phase B (29 contracts projected ×4 mirrors, validation green) + new rule `SC-MIRROR-PROJ-001` + journals. Harness MCP (`zigvm_harness`, `hermes_ops`) **not connected**; no Pi-bound grant; no `session_store_cli`/`herdr list` surface verified.
- Claude: handover records session `2585c3a9-4685-457d-84af-74238f66aa7c` (pane w4:p6), paused, no lease.
- Codex: handover records `01a0ba74-…` (coordinator/reviewer), handing over.
- Agy: no verified live receiving session (`Unavailable_observed`).

## Lanes (parallel)

| Lane | Agent | Work | Blocker |
|---|---|---|---|
| L1 | Pi | Finish rules/skills/SOP updates; author Pi-bound **grant draft** (schema-correct); run validation gate; ZK/KM ingest | none (docs) |
| L2 | Claude | Independent candidate-bound **review** of the mirror-repair package + the grant draft; return HOLD/PASS disposition | verified Herdr session identity |
| L3 | Codex | Refresh **MCP capability inventory** (65 declared) read-only; coordinator/journal reconciliation | verified session identity |
| L4 | Agy | Read-only quorum observation when a live session is verified; else holds | absent |

## Dependencies

L2 and L3 require a **verified live session identity** and a safe transport (SYNC-07: no automatic approval, no blind prompt reuse, no ambiguous retry). Until then they are `Unavailable_observed` — not dispatched. Grant-dependent execution (harness canary, `T_PROOF`, `PLANNING_MCP`, census, hive tasks) starts only after L1 grant draft + L2 review + L3 inventory refresh.

## Approach

1. Pi does everything unblocked now (additive, JJ-only, no source/build/test).
2. Pi records claims and evidence in Sa-plan; peers claim disjoint tasks.
3. Each peer returns hash-bound evidence and an explicit disposition; no model verdict completes a task.
4. Serialize integration, not lanes: the integration gate (`DEV_INTEGRATE`) takes all lanes' receipts.

## Learnings captured (also in SC-MIRROR-PROJ-001)

- Declared MCP ≠ connected surface; verify live tool list before relying.
- Rule mirrors drift via missing canonical projections + stale short-name shadows; projection policy now normative.
- Sa-plan deps mis-wiring blocks claim; filesystem work must not depend on grant tasks.

## Comprehensive verification checklist

<details>
<summary>Domain 1 — Metadata, timestamp and Tailscale navigation</summary>

- [x] **CHK-01..04** — prefix, Tailscale FQDN, L0/L3/L4/L9 tags, cross-links.

</details>
<details>
<summary>Domain 2..6</summary>

- [x] **CHK-05-MUDA** — no new dependency/binary.
- [ ] **CHK-06..16** — UNRUN (runtime/grant-gated).
- [x] **CHK-17/18** — independent review OUTSTANDING; standalone JJ only.
- [x] EV ceiling 93; no new EV.

</details>

**UOS footer:** `nas-1.tail55d152.ts.net:4100` · Sa-plan is the sole execution authority; this dispatch grants no admission.