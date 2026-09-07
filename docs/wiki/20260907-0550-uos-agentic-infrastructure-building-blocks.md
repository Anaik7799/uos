# UOS agentic infrastructure — building blocks and implementation map


[UOS Cockpit](http://nas-1.tail55d152.ts.net:4100/) / [Knowledge](http://nas-1.tail55d152.ts.net:4100/wiki) / [Agentic infrastructure](http://nas-1.tail55d152.ts.net:4100/docs/docs/design/20260907-0550-uos-agentic-infrastructure-17-aspect-formal-spec.md)

**Command & Control:** [Cockpit](http://nas-1.tail55d152.ts.net:4100/) · [Planning](http://nas-1.tail55d152.ts.net:4100/planning) · [Events](http://nas-1.tail55d152.ts.net:4100/ag-ui/events)  
**Knowledge Base:** [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk) · [Master MOC](http://nas-1.tail55d152.ts.net:4100/docs/docs/zk/20260905-1801-moc-uos-unified-master.md)  
**Repository & Governance:** [Files](http://nas-1.tail55d152.ts.net:4100/files/) · [Checklist](http://nas-1.tail55d152.ts.net:4100/checklist) · [AGENTS.md](http://nas-1.tail55d152.ts.net:4100/files/AGENTS.md)  
**View:** [Rendered document](http://nas-1.tail55d152.ts.net:4100/docs/docs/wiki/20260907-0550-uos-agentic-infrastructure-building-blocks.md) · [docs/wiki/20260907-0550-uos-agentic-infrastructure-building-blocks.md](http://nas-1.tail55d152.ts.net:4100/files/docs/wiki/20260907-0550-uos-agentic-infrastructure-building-blocks.md)

- **Created:** `2026-09-07T05:54:50Z`.
- **Status:** SPECIFIED; implementation UNRUN; NOT ADMITTED.
- **Authority:** [Formal specification SPEC-UOS-AINF-001](http://nas-1.tail55d152.ts.net:4100/docs/docs/design/20260907-0550-uos-agentic-infrastructure-17-aspect-formal-spec.md).
- **Decision:** [[zk:20260907-0550-adr-uos-agentic-infrastructure-native-building-blocks]].

Tags: #fractal-l0 #fractal-l2 #fractal-l3 #fractal-l4 #fractal-l5 #fractal-l8 #zk-adr #zero-muda #km-triad

## Purpose

The infrastructure composes existing UOS carriers into a tenant-scoped path from
authenticated intent to authorized execution and verifiable evidence. The
specification covers 21 services, 18 invariants, 63 service acceptance cases,
17 canonical aspects, 357 service/aspect obligations and eight implementation
packages. These are declared requirements; no runtime admission is claimed.

## Building block map

| Need | UOS carrier |
|---|---|
| Workload identity, delegated authority and secrets | Gleam IAM/Vault, policy types and opaque credential leases |
| Agent/tool discovery and invocation | Capability/ontology registry, MCP and MoZ adapters |
| Durable messaging | Zenoh plus Hermes transactional inbox/outbox and deduplication |
| Active memory | Tenant-scoped OTP/ETS working state |
| Retrieval and graph knowledge | Hermes wiki/graph kernels, KM triad, authorized index projections |
| Context and model routing | Gleam context/budget/provider types, isolated real MAX backend |
| Execution and recovery | ZigVM, isolated Hermes-Bionic, Sa-Plan leases and WAL history |
| Approval, loop control and quotas | Constitutional policy, Prajna, durable approval and budget records |
| Evidence and evaluation | Hermes ledger/oracles, Lean/Quint refinements and trajectory corpus |
| Operator surfaces | Indrajaal edge, cepaf Lustre/Wisp, TUI, AG-UI and A2UI |

## Read and implement

Start with [the C3I/Indrajaal source review](http://nas-1.tail55d152.ts.net:4100/docs/docs/reviews/20260907-0550-uos-c3i-indrajaal-17-aspect-infrastructure-source-review.md) to see reusable
code and the limits of historical claims. Then read
[the formal specification](http://nas-1.tail55d152.ts.net:4100/docs/docs/design/20260907-0550-uos-agentic-infrastructure-17-aspect-formal-spec.md) for typed interfaces, workflow
semantics, proof obligations, test IDs and operating limits. The
[docs/design/20260907-0550-uos-agentic-infrastructure-17-aspect-formal-spec.json](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20260907-0550-uos-agentic-infrastructure-17-aspect-formal-spec.json) companion is the structural traceability index.

The implementation order is candidate binding, identity/policy, durable
state/budgets, tool execution, knowledge/context/inference, semantic eval,
five-surface/aspect closure, then controlled admission. The main specification
includes matched editable ASCII and Mermaid diagrams.

## Evidence boundary

Source presence, generated flags, placeholder inference and historical “ratified”
text are not passing receipts. Real runtime behavior and machine-verifiable
formal evidence must match the same candidate before admission. The new source
review records concrete gaps in root startup, inference, durable replay,
identity and UI ingress.

**Knowledge graph edges:** this article explains [the specification](http://nas-1.tail55d152.ts.net:4100/docs/docs/design/20260907-0550-uos-agentic-infrastructure-17-aspect-formal-spec.md);
[the ADR](http://nas-1.tail55d152.ts.net:4100/docs/docs/zk/20260907-0550-adr-uos-agentic-infrastructure-native-building-blocks.md) motivates it; [the journal](http://nas-1.tail55d152.ts.net:4100/docs/docs/journal/20260907-0550-uos-agentic-infrastructure-formal-spec-journal.md) records
authoring and validation; [the master MOC](http://nas-1.tail55d152.ts.net:4100/docs/docs/zk/20260905-1801-moc-uos-unified-master.md) indexes the package.
Ontology/runtime publication remains an implementation obligation.


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


**Previous:** [Formal specification](http://nas-1.tail55d152.ts.net:4100/docs/docs/design/20260907-0550-uos-agentic-infrastructure-17-aspect-formal-spec.md) · **Next:** [Decision record](http://nas-1.tail55d152.ts.net:4100/docs/docs/zk/20260907-0550-adr-uos-agentic-infrastructure-native-building-blocks.md)  
**UOS footer:** [nas-1 cockpit](http://nas-1.tail55d152.ts.net:4100/) · [vm-1 peer](http://vm-1.tail55d152.ts.net:8088) · SPECIFIED / runtime UNRUN.
