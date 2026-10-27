# 20261027-1747 — Symbiosis & hive execution plan (resume)

#fractal-l0 #fractal-l3 #fractal-l4 #fractal-l9 #zk-adr #zero-muda #tailscale-web

[This plan](http://nas-1.tail55d152.ts.net:4100/files/docs/plans/20261027-1747-symbiosis-hive-execution-plan.md) · [Cockpit](http://nas-1.tail55d152.ts.net:4100/) · [Planning](http://nas-1.tail55d152.ts.net:4100/planning) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk)

Operator: resume; create a plan to execute all items identified. Boundary: Sa-plan sole execution authority · standalone JJ · EV ceiling 93 (EV-94..109 NOT_ADMITTED) · no admission claim · Zero-Muda. Execution enters Gleam/OTP through MCP or admitted Zenoh; direct filesystem work is the documented development bootstrap only.

## Governing inputs

- Root `AGENTS.md`, `contracts/rules/20260909-0412-gleam-harness-agent-operation-contract.md`, `contracts/rules/20261027-0836-core-development-learnings.md`, `docs/sop/20261001-1117-uos-agent-symbiosis-operations.md`.
- Handover `docs/journal/20261027-1214-full-system-session-pi-handover.md` (candidate `95e817…4583f`, 104/104 tests, 44 artifacts).
- Existing canonical plan `uos/hive-development/20261027-0532` (31 tasks, 14 done). This plan **reuses** its tasks and adds only the genuinely new sub-tasks.

## Item inventory (all identified work)

### A. Already done (this session, additive, uncommitted)
- A1 `CODEX.md → AGENTS.md` (entrypoint parity).
- A2 8 canonical `contracts/rules/20260916-*` mirrored into `.claude/.codex/.gemini/rules`.
- A3 Journal `20261027-1741-agent-parity-mirror-sync-journal.md`.

### B. Rule / skill / SOP / plugin mirror completion (AGENT_PARITY + KNOWLEDGE_SYNC rule half)
- B1 **Projection policy decision** then project the ~22 canonical contracts absent from every mirror (e.g. `20260907-1606-risk-checker-contract.md`, `20260908-0912-provenance-integrity-contract.md`, `20260909-0412-gleam-harness-agent-operation-contract.md`, `20261027-0836-core-development-learnings.md`, `20260916-0455-*`, `20260916-2100-*`, sciviz 2030/2100).
- B2 **Reconcile 8 stale short-name shadows** → point at newer timestamped canonical contracts, preserve old bytes (`c3i-indrajaal-functional-mirroring.md`, `c3i-indrajaal-parity-superiority.md`, `swarm-monitoring-protocol.md`, `workspace-isolation-contract.md`, `provenance-integrity-contract.md`, `denotational-intent-algebraic-atlas-contract.md`, `indrajaal-constitution-migration.md`, `hive-synchrony-protocol.md`).
- B3 **Canonicalize 3 content-drifted vendor-local files** (`20260907-1330-iam-ferriskey-nif-rule.md`, `20260908-2142-determinate-nix-devenv-mandate.md`, `uos-governance.md`) — pick one canonical source; normalize vendor-path/frontmatter as vendor-specific, not substance.
- B4 **Validation gate** — JSON parse (settings/hooks/mcp/settings), skill frontmatter scan, broken-symlink check, 4-mirror isomorphism; `tools/journal-check`, `tools/diagram-check`, `tools/ui-skill-check`.
- B5 **Inventory truth** — superpowers/plugin surfaces catalogued, never blanket-updated; no writing through external symlinks.

### C. Live coordination + MCP runtime admission (AGENT_PARITY coordination half)
- C1 Verify live AGY / Claude / Codex receiving sessions (fresh identity, no inherited grants).
- C2 Refresh MCP capability inventory (65 declared / 53 unprobed / 12 unavailable) and reconcile.
- C3 Obtaining a **Pi-bound reviewed grant**; initialize the 14-tool private harness MCP; runtime admission of read + scoped claim/write.

### D. Harness canary + typed MCP planning (handover golden path)
- D1 Retain exact serving binaries before any build.
- D2 Bounded 6-module canary under reviewed MCP (source frozen).
- D3 Sandbox plan + `T_PROOF` task via typed `CreatePlan`/`CreateTask`/`PublishEvidence`.
- D4 `PLANNING_MCP` live acceptance (replay original planning ID, flat verification packet, independent peer review).
- D5 `READINESS_CENSUS` (bind requirement → source → backend → MCP → scenario → evidence).

### E. Hive completion (existing plan tasks)
- E1 `CAPABILITY_PARITY` · `SCHEDULER_GATES` · `NATIVE_BOUNDARY_REPAIR`
- E2 `SERVICE_VERIFY` · `FAULT_RECOVERY` · `PERF_SCALE`
- E3 `TELEGRAM_ACCEPT` (16-task plan, 1 done)
- E4 `COST_EFFICIENCY` · `FORMAL_EVIDENCE` · `KNOWLEDGE_SYNC`
- E5 `DEV_READY_REVIEW` → `DEV_INTEGRATE`

## Sequencing & dependencies

```text
P0 resume preflight ──► P1 identity+grant ──► [B (parallel) + C]
                                              │
                                              ▼
                                    D (canary→T_PROOF→PLANNING_MCP)
                                              │
                                              ▼
                                    E (census→capability→accept→integrate)
```

- B is filesystem/docs work: gated only on pause-lift + JJ discipline.
- C and D require the reviewed grant and the live harness (blocked until P1).
- E depends on D5 census + C coordination.

## Ownership

- **Pi (this session):** P0, B, C3 grant authoring, plan/task recording, journals.
- **Claude / Codex (peers):** independent candidate-bound review of any grant; disjoint task ownership; no shared-path writes.
- **AGY:** only a verified live receiving session; otherwise `Unavailable_observed`.

## Acceptance criteria (per item)

- Every B item: 4-mirror isomorphism verified mechanically; validation gate green; no broken symlink; no source/build/test run.
- C: observed live peer receipts + a reviewed grant with finite read/write paths and expiry (`expires_utc_us` decimal integral-microsecond string).
- D: receipts for canary build/test, `T_PROOF` created via typed MCP, `PLANNING_MCP` finished only if its actual acceptance is satisfied (independent review, no force-pass).
- E: per existing hive task acceptance; `NOT_ADMITTED`/`HOLD`/`UNRUN` preserved; no aggregate passing claim.

## Residual risk

No Pi-bound grant exists yet (C3). Live coordination (C1/C2) and MCP runtime admission (C3) are the hard blockers for D and E. B can proceed now. This plan grants no admission authority; it is a sequenced worklist recorded under Sa-plan.

## Comprehensive verification checklist

<details>
<summary>Domain 1 — Metadata, timestamp and Tailscale navigation</summary>

- [x] **CHK-01-TIME** — `20261027-1747` prefix; clock observed 2026-10-27T16:47:06Z (chrony nominal).
- [x] **CHK-02-TAIL** — Full Tailscale FQDN references provided.
- [x] **CHK-03-FRACT** — L0/L3/L4/L9 tags assigned.
- [x] **CHK-04-KM** — Spec, handover, journal and plan links cross-referenced.

</details>

<details>
<summary>Domain 2 — Zero-Muda purity and storage safety</summary>

- [x] **CHK-05-MUDA** — No dependency/registry/binary introduced by this plan.
- [ ] **CHK-06-GRAPH** — runtime check UNRUN.
- [ ] **CHK-07-DRIVE** — interlock test UNRUN.

</details>

<details>
<summary>Domain 3 — Testing Gold Standard and mathematical gates</summary>

- [ ] **CHK-08..11** — UNRUN until harness canary (Phase D).

</details>

<details>
<summary>Domain 4 — Cross-language control and observability</summary>

- [ ] **CHK-12..16** — UNRUN; subject to grant-gated runtime observation.

</details>

<details>
<summary>Domain 5 — Sovereign governance and standalone Jujutsu</summary>

- [ ] **CHK-17-SOV** — Independent review of this plan OUTSTANDING.
- [x] **CHK-18-JJ** — Standalone JJ; no native Git mutation.

</details>

<details>
<summary>Domain 6 — Provenance extension</summary>

- [x] EV ceiling 93; no new EV minted.

</details>

**UOS footer:** `nas-1.tail55d152.ts.net:4100` · Sa-plan is the sole execution authority; this plan grants no admission.