# ADR-UOS-AINF-001 — compose agentic infrastructure from UOS building blocks


[UOS Cockpit](http://nas-1.tail55d152.ts.net:4100/) / [Knowledge](http://nas-1.tail55d152.ts.net:4100/wiki) / [Agentic infrastructure](http://nas-1.tail55d152.ts.net:4100/docs/docs/design/20260907-0550-uos-agentic-infrastructure-17-aspect-formal-spec.md)

**Command & Control:** [Cockpit](http://nas-1.tail55d152.ts.net:4100/) · [Planning](http://nas-1.tail55d152.ts.net:4100/planning) · [Events](http://nas-1.tail55d152.ts.net:4100/ag-ui/events)  
**Knowledge Base:** [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk) · [Master MOC](http://nas-1.tail55d152.ts.net:4100/docs/docs/zk/20260905-1801-moc-uos-unified-master.md)  
**Repository & Governance:** [Files](http://nas-1.tail55d152.ts.net:4100/files/) · [Checklist](http://nas-1.tail55d152.ts.net:4100/checklist) · [AGENTS.md](http://nas-1.tail55d152.ts.net:4100/files/AGENTS.md)  
**View:** [Rendered document](http://nas-1.tail55d152.ts.net:4100/docs/docs/zk/20260907-0550-adr-uos-agentic-infrastructure-native-building-blocks.md) · [docs/zk/20260907-0550-adr-uos-agentic-infrastructure-native-building-blocks.md](http://nas-1.tail55d152.ts.net:4100/files/docs/zk/20260907-0550-adr-uos-agentic-infrastructure-native-building-blocks.md)

- **Created:** `2026-09-07T05:54:50Z`.
- **Status:** PROPOSED IMPLEMENTATION DECISION; NOT RATIFIED OR ADMITTED.
- **Specification:** [SPEC-UOS-AINF-001](http://nas-1.tail55d152.ts.net:4100/docs/docs/design/20260907-0550-uos-agentic-infrastructure-17-aspect-formal-spec.md).
- **Wiki:** [[wiki:20260907-0550-uos-agentic-infrastructure-building-blocks]].
- **Source review:** [C3I/Indrajaal, all 17 aspects](http://nas-1.tail55d152.ts.net:4100/docs/docs/reviews/20260907-0550-uos-c3i-indrajaal-17-aspect-infrastructure-source-review.md).

Tags: #fractal-l0 #fractal-l3 #fractal-l4 #fractal-l5 #fractal-l8 #zk-adr #zero-muda #km-triad

## Context

The operator supplied an enterprise agent-infrastructure capability list and
requested a formal specification using UOS building blocks and the 17-aspect
approach, informed by C3I/Indrajaal code and knowledge artifacts. Existing UOS
modules provide much of the vocabulary and integration surface but source
inspection exposes important gaps between declarations and observed execution.

## Decision

Compose the 21 infrastructure services from Gleam/OTP, IAM/Vault, Zenoh/MoZ,
Sa-Plan/Hermes-Bionic, Hermes evidence/graph/oracles, ZigVM and isolated MAX.
Retain Indrajaal as the HTTP/document edge and cepaf as the domain core.
Do not introduce the listed external vendor services as automatic dependencies.

Unify services with a typed tenant/principal/workflow envelope; permission
attenuation; durable pre-dispatch budget and intent transactions; bounded
execution; protected context; versioned protocol/provider adapters; and
candidate-bound runtime/formal receipts. Every service carries all 17 aspect
obligations, directly or through explicit dependency evidence.

## Alternatives considered

| Alternative | Assessment |
|---|---|
| Deploy the supplied vendor stack wholesale | Duplicates UOS ownership and persistence; increases operational burden and conflicts with language/source admission boundaries |
| Treat existing source and green registry flags as completion | Leaves identity, tenancy, budget, replay, inference and evidence gaps unresolved |
| Compose native carriers with explicit contracts and admission | Selected: reuses existing work while making remaining implementation measurable |

## Consequences

The design avoids a second workflow, broker, evidence or UI authority. It also
requires real work: wire root supervision, replace synthetic inference,
strengthen credential and tenant boundaries, close effect/replay crash windows,
implement bounded isolation, and replace static verdicts with current evidence.
The 18 invariants and 63 service cases guide that work.

External C3I trees remain read-only references. Their local and VM-1 revisions
differ; any future ingestion needs fresh quiescence, sanitization and two-key
verification. No new external source or model weights were imported.

## Admission and reversal

This decision authorizes no runtime cutover. Implementation proceeds through
the eight packages in the specification and candidate-bound review. A failed
canary pauses new effects and uses verified compatible rollback/reconciliation;
it does not erase reservations, outbox entries or irreversible-effect history.

The [completion journal](http://nas-1.tail55d152.ts.net:4100/docs/docs/journal/20260907-0550-uos-agentic-infrastructure-formal-spec-journal.md) records documentation checks.
Production runtime and formal checks remain UNRUN.


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


**Previous:** [Infrastructure wiki](http://nas-1.tail55d152.ts.net:4100/docs/docs/wiki/20260907-0550-uos-agentic-infrastructure-building-blocks.md) · **Next:** [Journal](http://nas-1.tail55d152.ts.net:4100/docs/docs/journal/20260907-0550-uos-agentic-infrastructure-formal-spec-journal.md)  
**UOS footer:** [nas-1 cockpit](http://nas-1.tail55d152.ts.net:4100/) · [vm-1 peer](http://vm-1.tail55d152.ts.net:8088) · PROPOSED / runtime UNRUN.
