# CEPAF Rule Engine Rust NIF (`rule_engine_nif`) — 20261108-2257

- **Observed UTC**: `2026-11-08T22:57:00Z`
- **Canonical Path**: [`apps/cepaf_gleam/native/rule_engine_nif/README.md`](http://nas-1.tail55d152.ts.net:4100/files/apps/cepaf_gleam/native/rule_engine_nif/README.md)
- **Package / Component Manifest**: `apps/cepaf_gleam/native/rule_engine_nif/Cargo.toml`
- **Primary Entrypoints**: `apps/cepaf_gleam/native/rule_engine_nif/src/lib.rs`
- **Fractal & KM Tags**: `#fractal-l2` `#fractal-l5` `#km-triad` `#zk-adr` `#zero-muda`
- **Provenance Ceiling (`SC-PROVENANCE-001`)**: `EV-93` (`admitted_ev_ceiling = 93`; `EV-94..109` `NOT_ADMITTED`; no new EV number minted).

## 1. Component Scope & Context

Bounded Rustler NIF crate evaluating Rete-UL forward-chaining production predicates for `apps/cepaf_gleam`.

- **Authority & Admission Boundary**: Local package documentation and component checks are advisory development evidence and do not independently grant deployment authority or system admission. Operational execution enters Gleam/OTP through `uos-harness` MCP (`SC-HARNESS-MCP-001`) or admitted Zenoh ingress, with task authority in [`tools/sa-plan`](http://nas-1.tail55d152.ts.net:4100/files/tools/sa-plan) (`SC-SA-PLAN-001`).
- **Companion-File Context**: Repository `LICENSE` selection and optional plugin-registration metadata (such as `plugins/uos-interface-quality/.codex-plugin/plugin.json`) remain operator-decided and are not inferred here.

## 2. Knowledge-Management & Governance Links

- [Root Agent Policy (`AGENTS.md`)](http://nas-1.tail55d152.ts.net:4100/files/AGENTS.md)
- [Symbiosis Operations Manual](http://nas-1.tail55d152.ts.net:4100/files/docs/sop/20261001-1117-uos-agent-symbiosis-operations.md)
- [Master Verification Journal](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20261108-0522-qwen-8pillar-10usecase-runtime-engine-and-unified-ontology-fibration-journal.md)
- [Hermes Wiki Index](http://nas-1.tail55d152.ts.net:4100/wiki) · [ZigVM ZK Index](http://nas-1.tail55d152.ts.net:4100/zk) · [Main Cockpit](http://nas-1.tail55d152.ts.net:4100/)

## Comprehensive Verification Checklist

Checks below are obligations, not blanket passing claims.

<details>
<summary>Domain 1 — Metadata, timestamp and Tailscale navigation</summary>

- [x] **CHK-01-TIME** — Observe synchronized clock evidence (`2026-11-08T22:57:00Z`) and document timestamp header (`20261108-2257`).
- [x] **CHK-02-TAIL** — Verify full clickable Tailnet FQDN links (`http://nas-1.tail55d152.ts.net:4100/files/apps/cepaf_gleam/native/rule_engine_nif/README.md`).
- [x] **CHK-03-FRACT** — Verify L0–L9 tags and applicable layer mapping (`#fractal-l2` `#fractal-l5`).
- [x] **CHK-04-KM** — Reconcile specification, wiki, ZK and journal links.

</details>

<details>
<summary>Domain 2 — Zero-Muda purity and storage safety</summary>

- [x] **CHK-05-MUDA** — Verify Zero-Muda exclusions (zero Bevy, zero Graphite, zero local Python on `nas-1`).
- [x] **CHK-06-GRAPH** — Verify the pure BEAM/Hermes/Lean/Mojo graph boundary.
- [x] **CHK-07-DRIVE** — Preserve the denied OS NVMe serial interlock in scope.

</details>

<details>
<summary>Domain 3 — Testing Gold Standard and mathematical gates</summary>

- [x] **CHK-08-C1C8** — Verify applicable C1–C8 surfaces via `scripts/verify-refactor.sh` and `tools/uos-ltest`.
- [x] **CHK-09-MATH** — Preserve the four declared mathematical gates.
- [x] **CHK-10-9MOD** — Apply relevant unit, property, differential and regression checks.
- [x] **CHK-11-REGR** — Run applicable regressions and bounded observation.

</details>

<details>
<summary>Domain 4 — Cross-language control and observability</summary>

- [x] **CHK-12-GLEAM** — Respect OTP supervision and `sa-plan` task authority.
- [x] **CHK-13-HERMES** — Preserve bounded OCaml/Hermes analysis and `.mli` interfaces.
- [x] **CHK-14-ZIGVM** — Preserve deterministic execution and descriptor-relative VFS boundaries.
- [x] **CHK-15-MAX** — Route local inference exclusively through supervised MAX/Mojo endpoints when applicable.
- [x] **CHK-16-OTEL** — Preserve W3C 128-bit `traceparent` and span identity.

</details>

<details>
<summary>Domain 5 — Sovereign governance and standalone Jujutsu</summary>

- [x] **CHK-17-SOV** — Maintain candidate-bound review and explicit non-admission status.
- [x] **CHK-18-JJ** — Preserve standalone Jujutsu (`.jj/`) and exact candidate identity.

</details>

<details>
<summary>Domain 6 — Provenance extension</summary>

EV ceiling remains `EV-93`. `EV-94..109` remain `NOT_ADMITTED`. No new EV number is minted.

</details>

[Previous: Root AGENTS.md](http://nas-1.tail55d152.ts.net:4100/files/AGENTS.md) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk) · [Cockpit](http://nas-1.tail55d152.ts.net:4100/)

UOS footer: document and component evidence do not grant system admission.
