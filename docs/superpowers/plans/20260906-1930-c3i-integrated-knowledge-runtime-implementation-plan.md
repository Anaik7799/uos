# C3I-Integrated Knowledge Runtime Implementation Plan
#fractal-l0 #fractal-l1 #fractal-l2 #fractal-l3 #fractal-l4 #fractal-l5 #fractal-l6 #fractal-l7
#rocha-semiotics #cybernetics #zero-muda #km-triad #c3i-knowledge-runtime #supervised-ocaml-port

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement and ratify the complete production C3I-Integrated Knowledge Runtime in UOS, ingesting all artifacts from VM-1 C3I (`/home/an/dev/ver/c3i`) using the 17-aspect approach, operationalizing a fully agentic actor-supervisor architecture in pure Gleam/OTP 29 with supervised OCaml worker ports, executing 5 new evolutionary and functional cycles (`EV-55` through `EV-59`), and obtaining sovereign ratification from Claude and Codex.

**Architecture:** A distributed cybernetic knowledge plane unifying:
1. **Source Ingestion & Sanitization Plane**: 7,918 VM-1 C3I artifacts audited, secret-scrubbed, and cryptographically verified under two-key governance.
2. **Actor & Supervision Mesh (Gleam/OTP 29)**: Root-supervised actor pool (`c3i_knowledge_supervisor.gleam`, `c3i_knowledge_actor.gleam`, `c3i_ingestion_actor.gleam`) managing in-memory cache, Bayesian exponential trust decay, negative knowledge anti-pattern traps, and cited recall.
3. **Supervised OCaml Oracle Worker (Hermes)**: Length-delimited JSON-RPC over stdio pipes protecting BEAM reductions with fail-closed 100ms timeouts. Direct OCaml NIFs deferred to dedicated scheduler-safety review.
4. **Tripartite Presentation**: Live Wisp/Mist REST endpoints (`/api/verify/c3i-knowledge`, `/api/knowledge/query`, `/api/knowledge/cited-recall`), Lustre SSR views, and ANSI terminal reporting.
5. **Evolutionary & Functional Cycles (EV-55..EV-59)**: 5 advanced cycles verified by Claude and Codex sovereign subagents.

**Tech Stack:** Pure Gleam 1.0+, Erlang/OTP 29, Hermes OCaml 5.x / Dune, Wisp 2.2+, Mist 6.0+, Lustre 5.6+, Standalone Jujutsu (`.jj/`), Tailscale FQDN mesh (`http://nas-1.tail55d152.ts.net:4100`).

**Spec:** [`docs/superpowers/specs/2026-09-06-c3i-integrated-knowledge-runtime-design.md`](file:///home/an/NAS-setup/uos/docs/superpowers/specs/2026-09-06-c3i-integrated-knowledge-runtime-design.md) (`SPEC-C3I-KNOWLEDGE-RUNTIME-001`), [`contracts/rules/km-wiki-zk-contract.md`](file:///home/an/NAS-setup/uos/contracts/rules/km-wiki-zk-contract.md), [`contracts/rules/c3i-cross-language-control-contract.md`](file:///home/an/NAS-setup/uos/contracts/rules/c3i-cross-language-control-contract.md).

---

## Global Constraints & Architectural Invariants

- **Approved Default Choice**: Supervised OCaml worker/port (`supervised_port`) over stdio pipes is the initial BEAM-callable production path. Direct OCaml NIFs are deferred to a dedicated scheduler-safety review to safeguard BEAM reductions and preemption.
- **Mandatory Timestamp Rule**: All generated documents must carry `YYYYMMDD-HHSS-` timestamp prefix (`contracts/rules/timestamp-mandate.md`).
- **Zero-Muda Purity**: 0 Bevy, 0 Graphite, 0 foreign NIF shared libraries. Pure Erlang in [`apps/cepaf_gleam/src/graphene_nif.erl`](file:///home/an/NAS-setup/uos/apps/cepaf_gleam/src/graphene_nif.erl).
- **Storage Safety**: Root OS NVMe `HARD_DENIED_SYSTEM_OS_SERIAL = "25503L801736"` strictly locked fail-closed in [`ops/kubernetes/nas-k8s-lab/src/spec.rs:192`](file:///home/an/NAS-setup/uos/ops/kubernetes/nas-k8s-lab/src/spec.rs#L192).
- **18/18 Checklist**: 5 domains, 18/18 checks pass 100% green (`SC-CHECKLIST-001`).
- **Tailscale FQDN**: Universal clickable links to `http://nas-1.tail55d152.ts.net:4100` (`SC-TAILSCALE-WEB-001`).
- **VCS Discipline**: Standalone Jujutsu (`.jj/`) only. Zero native Git mutation commands.

---

## 17-Aspect Systemic Integration Matrix for VM-1 C3I Artifacts

| Aspect # | Aspect Domain | Specification & Concrete Implementation |
|:---:|:---|:---|
| **1** | Domain & Conceptual Boundary | Ingested VM-1 C3I ontology cleanly separated into read-only evidence vs canonical UOS authority (`SPEC-C3I-KNOWLEDGE-RUNTIME-001`). |
| **2** | Behavioral Type/Gospel Contracts | Pure Gleam types (`KnowledgeItem`, `TrustScore`, `RecallQuery`, `PortEnvelope`) and OCaml Gospel contracts. |
| **3** | State Invariants & Monotonicity | Monotonic state transitions `discovered -> classified -> mapped -> implemented -> built -> executed -> passed -> verified -> admitted`. |
| **4** | Data Flows & Storage Durability | SQLite WAL ledgers in `data/sqlite/uos_verification_tracking.sqlite3`, descriptor-relative VFS (`openat`), no dirty temp files. |
| **5** | Control Flows & Circuit Breakers | Prajna circuit breakers tripping on $>3$ timeouts ($100\text{ms}$ budget), sub-50ms half-open recovery. |
| **6** | Fault Recovery & Degraded Modes | Fail-closed security traps: NUL byte (`-2`), SQL injection (`-3`), trust decay drop (`-5`). |
| **7** | Formal Verification | Lean 4 traceability proof ($\Delta \vec{\mathcal{T}}_{13} \equiv \mathbf{0}$), Gospel contracts, Z3 bounded queries. |
| **8** | Observability & Telemetry | Universal C3I structured JSON logging with 128-bit W3C OTel `trace_id` and microsecond UTC ISO 8601 timestamps ending in `Z`. |
| **9** | SRE & Lyapunov Stability | Windowed error budget trend detectors ($\dot{V} \le 0$), dead-man freshness monitors ($\le 300\text{s}$). |
| **10** | Performance & Scalability | Sub-15ms P99 latency across all knowledge queries; lockless in-memory BEAM actor state. |
| **11** | Security & Zero-Trust Ingress | Immediate rejection of malicious payloads; root OS NVMe hardware interlock enforced. |
| **12** | Cross-Language Conformance | Typed cross-language JSON envelopes between Gleam, Hermes OCaml port, and Rust NIFs. |
| **13** | Tripartite Presentation | Feature parity across Lustre SSR Web (port 4100), Wisp REST API, and ANSI Terminal TUI. |
| **14** | Agentic Interaction & Swarm | Multi-agent collaboration with Claude Opus/Sonnet and OpenAI Codex sovereign subagents. |
| **15** | Negative Knowledge & Anti-Patterns | Explicit indexing and active rejection of known architectural anti-patterns (`AP-01`, `AP-02`, `AP-03`). |
| **16** | Comprehensive Test Protocol | 9 testing modalities (Unit, System, TDD, BDD, Performance, Scalability, Property, Fuzz, Chaos). |
| **17** | Provenance, Governance & Timestamps | Two-key cryptographic SHA-256 receipts in `governance/sources/`, mandatory `YYYYMMDD-HHSS-` prefixes. |

---

## File Structure & Decomposition

```text
uos/
├── apps/cepaf_gleam/
│   ├── src/cepaf_gleam/knowledge/
│   │   ├── c3i_knowledge_runtime.gleam       # Functional runtime (trust decay, security, recall)
│   │   ├── c3i_knowledge_actor.gleam         # OTP Stateful Actor (state, query, decay loop)
│   │   ├── c3i_ingestion_actor.gleam         # OTP Ingestion Worker (streaming, validation)
│   │   └── c3i_knowledge_supervisor.gleam    # OTP 29 Child Supervisor (isolated domain)
│   └── test/
│       ├── c3i_knowledge_runtime_test.gleam  # Runtime core tests
│       ├── c3i_knowledge_actor_test.gleam    # Actor state & query tests
│       └── c3i_knowledge_supervisor_test.gleam # Supervision tree tests
├── governance/
│   └── sources/
│       └── 20260906-1930-c3i-vm1-artifacts-ingestion-receipt.json # Authoritative source receipt
├── docs/
│   ├── superpowers/
│   │   ├── specs/2026-09-06-c3i-integrated-knowledge-runtime-design.md
│   │   └── plans/20260906-1930-c3i-integrated-knowledge-runtime-implementation-plan.md
│   ├── journal/
│   │   └── 20260906-1930-uos-c3i-artifacts-ingestion-and-5-evolutions-journal.md
│   ├── zk/
│   │   └── 20260906-1930-adr-056-c3i-artifacts-ingestion-and-5-evolutions-ratification.md
│   └── wiki/
│       └── 20260906-1930-uos-c3i-artifacts-ingestion-and-5-evolutions-wiki.md
```

---

## Execution Tasks

### Task 1: Ingestion Manifest & Two-Key Source Receipt
- [ ] Inspect and audit VM-1 C3I source artifacts (`/home/an/dev/ver/c3i`).
- [ ] Author `governance/sources/20260906-1930-c3i-vm1-artifacts-ingestion-receipt.json` capturing 7,918 files across docs, specs, ontology, data, and scripts.
- [ ] Verify zero secrets, zero private keys, zero model weights, zero live DB WALs admitted.

### Task 2: Pure Gleam OTP Knowledge Actor & Supervision Tree
- [ ] Create `apps/cepaf_gleam/src/cepaf_gleam/knowledge/c3i_knowledge_actor.gleam`.
  - Implements Erlang process / message loop for managing knowledge state, applying periodic trust decay, handling query and cited recall messages.
- [ ] Create `apps/cepaf_gleam/src/cepaf_gleam/knowledge/c3i_ingestion_actor.gleam`.
  - Implements artifact stream ingestion with SHA-256 validation and zero-trust payload filtering.
- [ ] Create `apps/cepaf_gleam/src/cepaf_gleam/knowledge/c3i_knowledge_supervisor.gleam`.
  - Implements OTP 29 supervisor managing actor lifecycle with bounded restart strategy (`one_for_all`, max 3 restarts in 10s).
- [ ] Write and run comprehensive EUnit tests:
  - `apps/cepaf_gleam/test/c3i_knowledge_actor_test.gleam`
  - `apps/cepaf_gleam/test/c3i_knowledge_supervisor_test.gleam`
  - Verify 100% pass with 0 warnings.

### Task 3: 5 Evolutionary & Functional Cycles (EV-55..EV-59)
- [ ] Update `omni_fractal_matrix_engine.gleam` to include `generate_wave3_evolutionary_cycles()` (`EV-55` through `EV-59`):
  - `EV-55`: C3I Agentic Ingestion & Sanitization Engine (`INV-AGENTIC-INGESTION-SANITIZED`)
  - `EV-56`: Supervised OCaml Port Pool & Reductions Protection (`INV-SUPERVISED-OCAML-PORT-POOL`)
  - `EV-57`: Dynamic Trust Decay & Negative Knowledge Actor Swarm (`INV-DYNAMIC-DECAY-ACTOR-SWARM`)
  - `EV-58`: Real-Time Tripartite Knowledge Presentation & SSE Mesh (`INV-TRIPARTITE-SSE-KNOWLEDGE-MESH`)
  - `EV-59`: Tri-Sovereign Autonomic Governance & Self-Healing Closure (`INV-TRI-SOVEREIGN-AUTONOMIC-CLOSURE`)
- [ ] Update `tools/uos` doctor and checklist to audit all 59 cycles (`EV-01`..`EV-59`).

### Task 4: Subagent Sovereigns Execution & Verification
- [ ] Spawn Claude Sovereign Subagent to review and ratify EV-55..EV-59 and knowledge actors.
- [ ] Spawn Codex Sovereign Subagent to run 5-run recursive audit and certify invariants.

### Task 5: Master KM Triad & Jujutsu Mainline Ratification
- [ ] Author Master Completion Journal `docs/journal/20260906-1930-uos-c3i-artifacts-ingestion-and-5-evolutions-journal.md`.
- [ ] Author Permanent ZK ADR-056 `docs/zk/20260906-1930-adr-056-c3i-artifacts-ingestion-and-5-evolutions-ratification.md`.
- [ ] Author Hermes Wiki Article `docs/wiki/20260906-1930-uos-c3i-artifacts-ingestion-and-5-evolutions-wiki.md`.
- [ ] Update Master ZK MOC and Wiki Corpus Index.
- [ ] Record verification run in `data/sqlite/uos_verification_tracking.sqlite3`.
- [ ] Update Section 9 Status Line in `AGENTS.md`.
- [ ] Execute `tools/uos verify-all` and confirm 100% Green.
- [ ] Mainline Jujutsu commit, bookmark `main`, tag `tag/20260906-1930-c3i-artifacts-ingestion-5-evolutions-ratified`, and advance working copy.
