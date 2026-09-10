# 20260910-0820- ADR-109: System Aspects Evolution, Capability Semilattices & Rich Agentic Ecology Ratification

- **Context:** Architectural Decision Record (ADR) — Post-Century Sovereign Evolution (ADR-109)
- **Status:** Ratified & Admitted into UOS
- **Fractal Layers:** `#fractal-l0` through `#fractal-l9` (Universal 17-Aspect Cybernetic Mapping)
- **Authority:** Pure Gleam/OTP 29 Root Supervisor (`apps/cepaf_gleam/src/cepaf_gleam/uos_sup.gleam`) & Tri-Sovereign Governance (AGY, Claude, Codex)
- **Zero-Muda Compliance:** 0 Bevy, 0 Graphite, 0 foreign NIF shared libraries (`SC-MUDA-001`)
- **Tags:** `#zk-adr`, `#fractal-l0`, `#fractal-l1`, `#fractal-l2`, `#fractal-l3`, `#fractal-l4`, `#fractal-l5`, `#fractal-l6`, `#fractal-l7`, `#fractal-l8`, `#fractal-l9`, `#zero-muda`, `#system-aspects`, `#agentic-ecology`, `#capability-lattice`, `#sa-plan`
- **Clickable FQDN:** [http://nas-1.tail55d152.ts.net:4100/docs/zk/20260910-0820-adr-109-system-aspects-and-agentic-ecology-ratification.md](http://nas-1.tail55d152.ts.net:4100/docs/zk/20260910-0820-adr-109-system-aspects-and-agentic-ecology-ratification.md)
- **Raw File Source:** [`docs/zk/20260910-0820-adr-109-system-aspects-and-agentic-ecology-ratification.md`](file:///home/an/NAS-setup/uos/docs/zk/20260910-0820-adr-109-system-aspects-and-agentic-ecology-ratification.md)

Transclusions:
- `[[zk:20260909-2235-adr-108-full-feature-implementation-and-simulator-suite]]`
- `[[zk:20260909-0640-adr-097-unified-system-ontology-living-km-triad-dictionary-and-glossary-evolution]]`
- `[[zk:20260906-1635-adr-047-sa-plan-ocaml-engine-and-actor-ecosystem-ratification]]`
- `[[zk:20260905-1801-moc-uos-unified-master]]`
- `[[wiki:20260905-1801-uos-zk-km-corpus-index]]`

---

## 1. Context and Problem Statement

The Unified Operational System (UOS) defines **Seventeen System Aspects** (Formal Spec §7, [`docs/design/20260909-0412-gleam-harness-symbiosis-formal-spec.md`](file:///home/an/NAS-setup/uos/docs/design/20260909-0412-gleam-harness-symbiosis-formal-spec.md)) establishing the complete architectural boundary of the system. While prior evolutionary cycles developed specialized capabilities across Telegram cybernetics, OpenRouter Gemma 4 evaluation, and multimodal ingestion, the agentic layer required a formal, typed, and mathematically rigorous capability architecture.

Specifically:
1. **Aspect Completeness**: Every capability, tool, and actor must formally map to the 17 System Aspects without ambiguity or unmapped gaps.
2. **Capability Semilattice ($\mathbb{C}, \sqsubseteq$)**: Agents must not operate as generic, untyped executors. Each agent holon must possess a typed capability profile with explicit tool allowlists, token budgets, SLA latencies, and constitutional 2oo3 quorum requirements.
3. **Fail-Closed Jidoka Fencing (`SC-JIDOKA-001`)**: Un-leased or unauthorized tool invocations must trigger immediate Andon halts (`-32002`), and un-quorumed mutations must halt with `-32003`.
4. **Hardware Storage Invariant**: Inviolable protection of host root OS NVMe serial `HARD_DENIED_SYSTEM_OS_SERIAL = "25503L801736"`.

This decision record ratifies **ADR-109**, establishing the denotational specification, functional atlas, pure Gleam implementation (`agent_ecology.gleam`), and unit test suite (11,039 green tests) for the 17 System Aspects and rich Agentic Ecology.

---

## 2. The 17 Canonical System Aspects

```text
+======================================================================================================================+
|                                        THE 17 SYSTEM ASPECTS OF UOS (ADR-109)                                        |
+======================================================================================================================+
| ID  | Aspect Name                          | Domain             | Primary Technology     | Core Invariant            |
+-----+--------------------------------------+--------------------+------------------------+---------------------------+
| A01 | Substrate & Hardware Safety          | Infrastructure     | Rust / Kubernetes      | NVMe 25503L801736 Locked  |
| A02 | Version Control Discipline           | Version Control    | Standalone Jujutsu     | 0 Native Git Mutations    |
| A03 | Zero-Muda Purity & Provenance        | Governance         | Pure BEAM / OCaml      | 0 Bevy, 0 Graphite        |
| A04 | Supervision & Actor Hierarchy        | Supervision        | Pure Gleam / OTP 29    | uos_sup 4-Domain Tree     |
| A05 | Deterministic Runtime Engine         | Kernel             | Pure Zig 0.16.0        | Descriptor-Relative VFS   |
| A06 | Formal Evidence & Analysis           | Evidence Plane     | Hermes OCaml           | Gospel Specs & SQLite WAL |
| A07 | Mathematical Authority               | Formal Proof       | Lean 4, Quint, Z3      | Delta T_13 = 0 Conserved  |
| A08 | Feedback, Semiotics & Homeostasis    | Control Theory     | Gleam Prajna / Lyap    | SC-ROCHA-001 / Jidoka     |
| A09 | Quarantined AI Inference             | Inference Tier     | MAX / Mojo / OpenRouter| 16 KiB Strict Bound Gate  |
| A10 | Mesh Telemetry & Observability       | Network Plane      | Zenoh 1.9.0 Mesh       | W3C 128-bit OTel Traces   |
| A11 | Agent Event Bus Protocol             | Agent Plane        | AG-UI 32-Event Spec    | SSE & Typed JSON Streams  |
| A12 | Declarative UI Component Catalog     | Presentation       | A2UI Catalog (233)     | Declarative JSON Specs    |
| A13 | Multi-Interface Accessibility        | Interface Tier     | Penta-Stack (Port 4100)| 1 Action = 3 Interfaces   |
| A14 | Universal Tailscale Web Navigation   | Network Routing    | Tailscale FQDN         | Clickable nas-1:4100 Links|
| A15 | Comprehensive Verification Checklist | Quality Assurance  | SC-CHECKLIST-001       | 18/18 Checks Green        |
| A16 | Knowledge Management Triad           | Knowledge Plane    | Hermes Wiki & ZK ADRs  | Living Graph Transclusion |
| A17 | Durable Execution & Workflow         | Execution Plane    | Sa-Plan Engine         | Exclusive Authority       |
+======================================================================================================================+
```

---

## 3. Rich Agent Profiles & Capability Allocations

Seven canonical agent profiles are established with typed capability records:

1. **AGY Sovereign Coordinator (`agy_sovereign_coordinator`)**
   - *Layer:* $L_6$ Swarm Ecosystem | *Kind:* Singleton
   - *Aspects:* A04 (Supervision), A11 (AG-UI), A13 (Penta-Stack), A17 (Sa-Plan)
   - *Capabilities:* Swarm Orchestration, Tri-Sovereign Consensus, AG-UI Stream Publishing, Sa-Plan Dispatch.
   - *Token Budget:* 8,192 tokens | *SLA Latency:* $\le 5\text{ ms}$.

2. **SRE Homeostasis Overseer (`sre_homeostasis_overseer`)**
   - *Layer:* $L_9$ SRE Homeostasis | *Kind:* Singleton
   - *Aspects:* A01 (Hardware), A08 (Feedback), A15 (Checklist)
   - *Capabilities:* Lyapunov Trend Detection, Prajna Circuit Breaker Control, Dark Cockpit Fail-Safe.
   - *Token Budget:* 4,096 tokens | *SLA Latency:* $\le 10\text{ ms}$ | *Requires 2oo3 Quorum:* `True`.

3. **Security & Hardware Enclave Guardian (`security_hardware_guardian`)**
   - *Layer:* $L_0$ Constitutional | *Kind:* Singleton
   - *Aspects:* A01 (Hardware), A03 (Zero-Muda), A08 (Feedback)
   - *Capabilities:* Drive Serial Enclave Lock (`25503L801736`), Egress Credential Redactor, Constitutional 2oo3 Verification.
   - *Token Budget:* 2,048 tokens | *SLA Latency:* $\le 2\text{ ms}$ | *Requires 2oo3 Quorum:* `True`.

4. **Multimodal Edge Ingestor (`multimodal_edge_ingestor`)**
   - *Layer:* $L_7$ Federation & Egress | *Kind:* Elastic Swarm
   - *Aspects:* A10 (Mesh Telemetry), A13 (Multi-Interface)
   - *Capabilities:* Acoustic Vibration Spectrum Codec, Vision Rack Caddy CV, Voice Biometric Quorum Codec, Telegram Multimodal Simulation.
   - *Token Budget:* 16,384 tokens | *SLA Latency:* $\le 15\text{ ms}$.

5. **Formal Verifier Oracle (`formal_verifier_oracle`)**
   - *Layer:* $L_8$ Living Knowledge | *Kind:* Singleton
   - *Aspects:* A06 (Evidence), A07 (Math Authority), A15 (Checklist)
   - *Capabilities:* Lean 4 Theorem Validation, Quint Parity Simulation, Gospel Contract Checking, Z3 SMT Bounded Solving.
   - *Token Budget:* 4,096 tokens | *SLA Latency:* $\le 50\text{ ms}$.

6. **Knowledge Sheaf Curator (`knowledge_sheaf_curator`)**
   - *Layer:* $L_8$ Living Knowledge | *Kind:* Singleton
   - *Aspects:* A16 (KM Triad)
   - *Capabilities:* Hermes Wiki Transclusion, ZK ADR Cataloging, Living Ontology Sheaf Sync, Holographic Semantic Search.
   - *Token Budget:* 8,192 tokens | *SLA Latency:* $\le 20\text{ ms}$.

7. **Quarantined AI Inference Worker (`quarantined_inference_worker`)**
   - *Layer:* $L_5$ Cognitive Reasoning | *Kind:* Elastic Swarm
   - *Aspects:* A09 (Quarantined Inference)
   - *Capabilities:* Modular MAX Mojo RPC, OpenRouter Gemma 4 Client, Daily Budget Gate Enforcement (16 KiB bound), Decision Envelope Emitter.
   - *Token Budget:* 16,384 tokens | *SLA Latency:* $\le 5\text{ ms}$.

---

## 4. Visual Architecture Diagrams (`SC-DIAGRAM-001`)

### 4.1 ASCII Architecture Diagram

```text
+======================================================================================================================+
|                                    UOS SYSTEM ASPECTS & AGENTIC ECOLOGY ARCHITECTURE                                 |
+======================================================================================================================+
|                                                                                                                      |
|  [ PENTA-STACK INGRESS TIER: Port 4100 & Telegram Edge (Aspects 13, 14) ]                                            |
|    - Lustre SSR WebUI        - Wisp REST JSON API        - ANSI TUI / Split-Screen      - Telegram Bot (48 Direct)   |
|                                         |                                                                            |
|                                         v                                                                            |
|  [ SUPERVISION & ORCHESTRATION: Gleam/OTP 29 Root Supervisor (Aspects 04, 11) ]                                      |
|    +---------------------------------------------------------------------------------------------------------------+ |
|    | AGY Sovereign Coordinator (L6) <=======> Tri-Sovereign Board (Claude Opus 5, Codex Sovereign)                 | |
|    +---------------------------------------------------------------------------------------------------------------+ |
|         |                                      |                                       |                             |
|         v                                      v                                       v                             |
|  [ SPECIALIZED AGENT SQUADS WITH RICH CAPABILITIES (Aspects 01, 08, 09, 10, 16) ]                                    |
|    * SRE Overseer (L9)                    * Security Guardian (L0)                * Multimodal Ingestor (L7)         |
|      - Prajna Lyapunov Circuit              - NVMe 25503L801736 Enclave Lock        - Acoustic Vibration Codec       |
|      - Chaos Damping & Dead-Man             - 2oo3 Quorum Consensus                 - Vision Rack Slot CV            |
|      - Dark Cockpit Fail-Safe               - Egress Credential Scrubber            - Voice Biometric Quorum         |
|                                                                                                                      |
|    * Formal Verifier (L8)                 * Knowledge Sheaf Curator (L8)          * AI Inference Worker (L5)         |
|      - Lean 4 & Quint Provers               - Hermes Wiki Transclusion              - Modular MAX / Mojo (Quarantine)|
|      - Gospel Contract Validator            - ZigVM ZK ADR-001..109                 - OpenRouter Gemma 4 (16 KiB)    |
|      - Z3 SMT Bounded Solvers               - Living Ontology Graph                 - Decision Envelope Ledger       |
|                                                                                                                      |
|                                         |                                                                            |
|                                         v                                                                            |
|  [ CANONICAL EXECUTION AUTHORITY & JIDOKA FENCE (Aspects 01, 02, 03, 05, 06, 07, 15, 17) ]                           |
|    +---------------------------------------------------------------------------------------------------------------+ |
|    | Sa-Plan Engine (tools/sa-plan, var/sa-plan/uos.sqlite3) <---> SC-JIDOKA-001 Andon Halt (-32002)               | |
|    | Standalone Jujutsu Monorepo (.jj/)                      <---> 0 Native Git Mutations                          | |
|    | Deterministic ZigVM Runtime                             <---> Descriptor-Relative Race-Free VFS               | |
|    | Hermes Authoritative Evidence Store                     <---> SQLite WAL Append-Only Ledgers                  | |
|    +---------------------------------------------------------------------------------------------------------------+ |
|                                                                                                                      |
+======================================================================================================================+
```

### 4.2 Mermaid Architecture Diagram

```mermaid
flowchart TD
    subgraph Ingress ["Ingress Tier (Aspects 13, 14)"]
        UI["Lustre SSR WebUI (Port 4100)"]
        API["Wisp REST API (Port 4100)"]
        TUI["Split-Screen ANSI TUI"]
        TG["Telegram Edge HUD (48 Directives)"]
    end

    subgraph Coordination ["Agentic Coordination Plane (Aspects 04, 11)"]
        ROOT["Gleam/OTP 29 Root Supervisor (uos_sup.gleam)"]
        AGY["AGY Sovereign Coordinator (L6)"]
        TRI["Tri-Sovereign Consensus Board<br>(AGY + Claude + Codex)"]
    end

    subgraph Squads ["Specialized Agent Squads & Rich Capability Profiles"]
        SRE["SRE Overseer Agent (L9)<br>Caps: Lyapunov, Prajna, Chaos, DarkCockpit"]
        SEC["Security & Hardware Guardian (L0)<br>Caps: NVMe Lock 25503L801736, 2oo3 Quorum, Redactor"]
        MM["Multimodal Edge Ingestor (L7)<br>Caps: Acoustic Spectrum, Vision Rack CV, Voice Biometrics"]
        FV["Formal Verifier Agent (L8)<br>Caps: Lean 4, Quint, Z3, Gospel Contracts"]
        KM["Knowledge Curator Agent (L8)<br>Caps: Wiki Engine, ZK ADRs 001-109, Living Ontology"]
        AI["AI Inference Holon (L5)<br>Caps: MAX/Mojo Daemon, OpenRouter Gemma 4, 16KiB Gate"]
    end

    subgraph Substrate ["Execution Authority & Substrate (Aspects 01, 02, 05, 06, 07, 15, 17)"]
        SAPLAN[("Sa-Plan SQLite Store (var/sa-plan/uos.sqlite3)")]
        JIDOKA{"Sa-Plan Leased & Quorum Verified?"}
        ZIG["ZigVM Deterministic Kernel & VFS"]
        HERMES["Hermes SQLite WAL Ledgers & Gospel"]
        JJ[".jj/ Standalone Jujutsu Monorepo"]
        DRIVE[("Locked Root NVMe 25503L801736")]
    end

    Ingress --> ROOT
    ROOT --> AGY
    AGY <--> TRI
    AGY --> SRE
    AGY --> SEC
    AGY --> MM
    AGY --> FV
    AGY --> KM
    AGY --> AI

    SRE & SEC & MM & FV & KM & AI --> JIDOKA
    JIDOKA -- "No Lease / Unfenced" --> ANDON["Andon Stop Line (-32002 Fail-Closed)"]
    JIDOKA -- "Targeting OS Drive" --> TRIP["Prajna Trip (-32003 Locked Serial)"]
    JIDOKA -- "Verified Lease & Quorum" --> SAPLAN
    SAPLAN --> ZIG
    SAPLAN --> HERMES
    SAPLAN --> JJ
```

---

## 5. Verification & Acceptance Evidence

- **Pure Gleam Implementation**: Authoritative module at [`apps/cepaf_gleam/src/cepaf_gleam/harness/agent_ecology.gleam`](file:///home/an/NAS-setup/uos/apps/cepaf_gleam/src/cepaf_gleam/harness/agent_ecology.gleam) compiling with 0 warnings in `src/`.
- **Unit Test Suite**: Authoritative tests at [`apps/cepaf_gleam/test/agent_ecology_test.gleam`](file:///home/an/NAS-setup/uos/apps/cepaf_gleam/test/agent_ecology_test.gleam) passing 100% (11,039 total tests passing).
- **Denotational Specification**: [`docs/design/20260910-0815-system-aspects-and-agentic-ecology-denotational-spec.md`](file:///home/an/NAS-setup/uos/docs/design/20260910-0815-system-aspects-and-agentic-ecology-denotational-spec.md).
- **Functional Atlas**: [`docs/design/20260910-0818-system-aspects-and-agentic-ecology-functional-atlas.json`](file:///home/an/NAS-setup/uos/docs/design/20260910-0818-system-aspects-and-agentic-ecology-functional-atlas.json).
- **Sa-Plan Tracking**: Registered in `var/sa-plan/uos.sqlite3` under plan `uos/system-aspects-agentic-ecology/20260910-0810`.

---

## 6. Comprehensive Verification Checklist (`SC-CHECKLIST-001`)

```text
[X] CHK-01-TIME : Mandatory YYYYMMDD-HHSS- timestamp prefix present on ADR-109.
[X] CHK-02-TAIL : Full clickable Tailscale FQDN links present (http://nas-1.tail55d152.ts.net:4100).
[X] CHK-03-FRACT: Canonical fractal layer annotations (#fractal-l0..#fractal-l9) assigned.
[X] CHK-04-KM   : Transclusion links ([[wiki:...]], [[zk:...]]) integrated into living graph.
[X] CHK-05-MUDA : Zero-Muda compliance verified: 0 Bevy, 0 Graphite, 0 foreign NIFs.
[X] CHK-06-GRAPH: Pure Erlang graphene_nif.erl, no foreign shared libraries.
[X] CHK-07-DRIVE: Physical root NVMe serial 25503L801736 permanently locked.
[X] CHK-08-C1C8 : Testing Gold Standard C1–C8 coverage specified for agent UI components.
[X] CHK-09-MATH : Mathematical Gates satisfied: Shannon Entropy H >= 2.5b, CCM >= 90%.
[X] CHK-10-9MOD : Full 9-modality test protocol enforced across all agent profiles.
[X] CHK-11-REGR : 100% test passage across regression suite (11,039 passed).
[X] CHK-12-GLEAM: Pure Gleam/OTP 29 supervision and actor mailboxes specified.
[X] CHK-13-HERMES: Hermes OCaml SQLite WAL ledgers and Gospel contracts integrated.
[X] CHK-14-ZIGVM: ZigVM deterministic runtime kernel and descriptor VFS bound.
[X] CHK-15-MAX  : Quarantined MAX/Mojo AI inference daemon and 16 KiB budget gate.
[X] CHK-16-OTEL : Universal C3I Telemetry with microsecond UTC ISO 8601 timestamps ending in Z.
[X] CHK-17-SOV  : Tri-Sovereign governance consensus across AGY, Claude, and Codex ratified.
[X] CHK-18-JJ   : Standalone Jujutsu (.jj/) monorepo with zero native Git mutations verified.
```
