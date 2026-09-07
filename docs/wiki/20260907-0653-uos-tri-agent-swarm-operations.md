# 20260907-0653 — UOS three-agent swarm operating runbook

#fractal-l2 #fractal-l3 #fractal-l4 #fractal-l5 #zk-adr #zero-muda #tailscale-web

**UOS / Swarm operations** · [Cockpit](http://nas-1.tail55d152.ts.net:4100/) · [Planning](http://nas-1.tail55d152.ts.net:4100/planning) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk) · [Checklist](http://nas-1.tail55d152.ts.net:4100/checklist)  
**Live:** [http://nas-1.tail55d152.ts.net:4100/docs/wiki/20260907-0653-uos-tri-agent-swarm-operations.md](http://nas-1.tail55d152.ts.net:4100/docs/wiki/20260907-0653-uos-tri-agent-swarm-operations.md) · [Raw source](http://nas-1.tail55d152.ts.net:4100/files/docs/wiki/20260907-0653-uos-tri-agent-swarm-operations.md)

Created:2026-09-07T06:38:53Z. This is the **implementation-phase runbook**. Further implementation and automated swarm activation are paused by the operator. See [plan](http://nas-1.tail55d152.ts.net:4100/docs/plans/20260907-0653-uos-tri-agent-cheaper-mode-implementation-plan.md) and [formal system design](http://nas-1.tail55d152.ts.net:4100/docs/design/20260907-0653-uos-tri-agent-sdlc-sre-herdr-spec.md).

## Observe and orient

Use read-only observations first:

```sh
jj --ignore-working-copy status
jj --ignore-working-copy log -r '@ | main'
herdr agent list
tools/sa-plan --format json plan show tri-agent-sync-20260907
```

Herdr commands require an actual Herdr-managed caller. Its agent/session/pane IDs come from live discovery. A pane's declared project and foreground process directory are distinct observations: Claude currently runs from the exact NAS-setup parent; AGY's harness child runs from the known ZigVM installation while its project is UOS. Those exceptions are explicit target-validation flags, not permissions to edit external sources.

From `apps/uos_tui`, the bounded native adapter exposes:

```sh
env ERL_FLAGS='+S 4:4 +A 4' gleam run -m herdr_sync_cli -- discover
env ERL_FLAGS='+S 4:4 +A 4' gleam run -m herdr_sync_cli -- read PANE_ID EXPECTED_SESSION_ID
```

Use `--allow-parent` only for the exact Claude parent-directory case and `--allow-agy-runtime` only for the known AGY project/runtime case. The adapter never answers permission dialogs or retries uncertain prompts. Its pre/post session checks are not atomic; mandatory action fencing belongs at the UOS executor.

## Claims, heartbeats and message exchange

The prototype uses a private ignored directory such as `/home/an/NAS-setup/uos/var/coordination/tri-agent`. Register only the actual caller's observed session; do not create a simulated ACK under another peer's ID. The following syntax is a resume template, not evidence that these production registrations were performed:

```text
gleam run -m session_sync_cli -- STATE register SESSION CLIENT WORKSPACE REVISION REFS_CSV OP_ID
gleam run -m session_sync_cli -- STATE heartbeat SESSION REVISION REFS_CSV OP_ID
gleam run -m session_sync_cli -- STATE claim SESSION RESOURCE TTL_SECONDS OP_ID
gleam run -m session_sync_cli -- STATE check SESSION RESOURCE EPOCH
gleam run -m session_sync_cli -- STATE renew SESSION RESOURCE EPOCH TTL_SECONDS OP_ID
gleam run -m session_sync_cli -- STATE release SESSION RESOURCE EPOCH OP_ID
gleam run -m session_sync_cli -- STATE send FROM TO KIND TEXT REFS_CSV OP_ID
gleam run -m session_sync_cli -- STATE inbox SESSION
gleam run -m session_sync_cli -- STATE ack SESSION MESSAGE_ID OP_ID
gleam run -m session_sync_cli -- STATE status
```

Resource forms are `task:<id>`, `workspace:<path>`, `integration/main` and `runtime:<service>`. Canonical path exclusion and independent-process crash/recovery acceptance remain prerequisites. Use a fresh operation ID for a new command; an exact retry retains its old ID and body.

Sa-plan remains workflow authority. Session heartbeats/claims and board deliveries do not complete tasks. An ACK establishes receipt only. Keep the raw event history and record causal gaps; never fabricate the deleted original message ID to make a validator green.

## Herdr utilization through the SDLC and SRE

| Herdr capability | UOS use | Required guard |
|---|---|---|
| Discover agent/session state | Select real Claude/Codex/AGY participants | Expected session identity and project provenance |
| Pane/workspace layout | Isolated developer or test terminals | Disjoint JJ workspaces/paths and operator-approved topology |
| Prompt delivery | Send a compact bounded work packet | Current peer identity, permissible state, scope, deadline and budget |
| Lifecycle observations | Detect working, idle, blocked, done or unknown | Readiness is not task success; inspect evidence and ACK |
| Output reads | Collect bounded test/review responses | Preserve provenance; no secret transcript export |
| Session resumption | Recover a known task after interruption | Reconcile current revision, lease and uncertain effects first |
| Notifications | Surface Andon, review and incident status | Reports do not execute mitigations |

The current native adapter implements discover/read/prompt. Pane creation, session resumption, notifications and continuous scheduling are explicit future integrations; the installed Herdr CLI exposing them does not mean UOS already automates them.

## Integration and runtime operation

One live session claims integration/main, announces it and obtains actual peer acknowledgements. Record both parent revisions, preserve dirty work, use JJ to create a merge candidate, inspect conflicts and verify the changed candidate. Bookmark movement is local integration, not production admission. Peers refresh their JJ workspace and inbox before continuing.

For SRE, open a task/incident and claim the runtime target separately. Capture pre-state, proposal, exact artifact revision, policy authorization, rollback and post-state. Unknown side-effect outcome goes to reconciliation; an expiring lease or a Herdr process exit does not prove the remote operation stopped. Runtime commands and deployment are outside the current coordination CLI.

## Remote advisory work and recovery

OpenRouter `probe`, `models` and `estimate` expose capability/credential presence and current admission estimates without printing credential bytes. The fixed lease-invariant smoke test is sanitized. Free-only mode is default and can fail under account data-policy restrictions. Paid mode is an explicit per-task choice; production paid swarms await aggregate budget enforcement.

If the board is unavailable, retain pending durable events and retry transport only. If a process dies during a claim, verify clock/host/boot and owner status before recovery. If the model/provider result is ambiguous, retain liability and inspect the request record instead of duplicating spend. Stop only owned test/session processes; do not terminate another agent or shared service to make a gate pass.


## Comprehensive verification checklist

Document checks and production gates have different evidence scopes. Checked
items below refer only to this document package. All infrastructure runtime,
formal-proof and sovereign-admission obligations remain **UNRUN**.

<details>
<summary>Domain 1 — Metadata, timestamp and Tailscale navigation</summary>

- [x] **CHK-01-TIME** — Host-clock timestamp prefix and chrony receipt recorded.
- [x] **CHK-02-TAIL** — Full clickable Tailscale FQDN references provided; serving status is reported in the journal.
- [x] **CHK-03-FRACT** — Canonical L0–L9 fractal tags assigned.
- [x] **CHK-04-KM** — Specification, wiki, ADR, source review and journal cross-linked.

</details>

<details>
<summary>Domain 2 — Zero-Muda purity and storage safety</summary>

- [ ] **CHK-05-MUDA** — Production dependency/exclusion scan required.
- [ ] **CHK-06-GRAPH** — Pure BEAM/Hermes graph boundary must pass runtime checks.
- [ ] **CHK-07-DRIVE** — Denied OS serial `25503L801736` must pass real interlock tests.

</details>

<details>
<summary>Domain 3 — Testing Gold Standard and mathematical gates</summary>

- [ ] **CHK-08-C1C8** — Structure, health badges, data grids, timeline, interactions, dark cockpit, advisory and action interlock.
- [ ] **CHK-09-MATH** — H ≥ 2.50 bits, CCM ≥ 90.0%, D_EA ≤ 10.0%, ITQS ≥ 0.85 require declared metrics and fresh measurements.
- [ ] **CHK-10-9MOD** — Unit, system, TDD, BDD, performance, scalability, property, fuzz and chaos.
- [ ] **CHK-11-REGR** — Relevant UI regression suite and 30-second monitoring require execution.

</details>

<details>
<summary>Domain 4 — Cross-language control and observability</summary>

- [ ] **CHK-12-GLEAM** — Real OTP domain/actor supervision and restart evidence.
- [ ] **CHK-13-HERMES** — Authoritative WAL, bounded formal checks and evidence receipts.
- [ ] **CHK-14-ZIGVM** — Deterministic execution and descriptor-relative VFS evidence.
- [ ] **CHK-15-MAX** — Real inference through the isolated MAX boundary.
- [ ] **CHK-16-OTEL** — UTC microsecond timestamps and nonzero W3C trace/span IDs.

</details>

<details>
<summary>Domain 5 — Sovereign governance and standalone Jujutsu</summary>

- [ ] **CHK-17-SOV** — Tri-sovereign candidate review and authorized admission are outstanding.
- [x] **CHK-18-JJ** — Documentation authored in UOS using its standalone JJ discipline; no native Git mutations in UOS.

</details>


**Previous:** [Implementation handoff](http://nas-1.tail55d152.ts.net:4100/docs/plans/20260907-0653-uos-tri-agent-cheaper-mode-implementation-plan.md) · **Next:** [Master MOC](http://nas-1.tail55d152.ts.net:4100/docs/zk/20260905-1801-moc-uos-unified-master.md)  
**UOS footer:** Cooperative local coordination; implementation-phase instructions; no deployment authority granted.

