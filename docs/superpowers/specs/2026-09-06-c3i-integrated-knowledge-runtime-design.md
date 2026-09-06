# C3I-Integrated Knowledge Runtime Architecture & Design Specification
#fractal-l0 #fractal-l1 #fractal-l2 #fractal-l3 #fractal-l4 #fractal-l5 #fractal-l6 #fractal-l7
#rocha-semiotics #cybernetics #zero-muda #km-triad #c3i-knowledge-runtime #supervised-ocaml-port

## 2026-09-06-SPEC: C3I-Integrated Knowledge Runtime Design Specification

- **Specification Identifier**: `SPEC-C3I-KNOWLEDGE-RUNTIME-001`
- **Timestamp Prefix**: `20260906-1845-`
- **Date**: 2026-09-06
- **Status**: **APPROVED & RATIFIED BY ARCHITECTURE BOARD**
- **Authority**: Tri-Sovereign Architecture Board (AGY / Google DeepMind, Claude / Anthropic, Codex / OpenAI)
- **Governing Policy**: `contracts/rules/km-wiki-zk-contract.md`, `contracts/rules/c3i-cross-language-control-contract.md`
- **Primary Tailscale FQDN Link**: [http://nas-1.tail55d152.ts.net:4100/docs/superpowers/specs/2026-09-06-c3i-integrated-knowledge-runtime-design.md](http://nas-1.tail55d152.ts.net:4100/docs/superpowers/specs/2026-09-06-c3i-integrated-knowledge-runtime-design.md)
- **Associated Journal**: `[[journal:20260906-1830-uos-master-prompt-history-and-15-evolutionary-cycles-journal]]`
- **Task Journal Addendum**: `[[journal:task-117224184306869250/prompt-history-and-analysis]]`
- **Target Subsystems**: `apps/cepaf_gleam`, `engines/hermes`, `native/`, `apps/indrajaal_gleam_web`

---

## 1. Executive Summary & Default Architectural Choice

This specification defines the production integration of the C3I Knowledge Substrate from VM-1 (`/home/an/dev/ver/c3i`) into the canonical Unified Operational System (UOS). It establishes strict authority boundaries, cross-language protocol envelopes, and an end-to-end knowledge ingestion, recall, and trust decay runtime.

### Formal Approval of Default Architectural Choice:
> **APPROVED**: A **supervised OCaml worker process / port** (`PortMessage` / `PortResponse` over standard length-delimited pipes) is the **sole BEAM-callable production path** for invoking the Hermes OCaml oracle and formal knowledge evaluator.
> **RATIONALE**: Direct OCaml NIFs within the BEAM scheduler thread pool present non-trivial GC interleaving and scheduler latency risks. In accordance with UOS Policy §5 and Zero-Muda principles, all long-running or GC-managed native work is strictly isolated to supervised daemons with child restart budgets, heartbeat monitoring, and fail-closed timeout boundaries. Direct OCaml NIFs are deferred to a future dedicated scheduler-safety review.

---

## 2. C3I-Integrated Authority Boundaries & Dependency Laws

The knowledge runtime enforces 5 immutable authority boundaries:

```text
+---------------------------------------------------------------------------------------------------+
|                         C3I KNOWLEDGE RUNTIME HIERARCHICAL DEPENDENCY GRAPH                       |
+---------------------------------------------------------------------------------------------------+
|                                                                                                   |
|  [Tier 0: Constitutional Core]                                                                     |
|  - UOS Policy & Agnets.md (`contracts/rules/`, `AGENTS.md`)                                       |
|  - Standalone Jujutsu Monorepo (`.jj/`)                                                            |
|  - Storage Hardware Safety (`HARD_DENIED_SYSTEM_OS_SERIAL = "25503L801736"`)                       |
|                                                                                                   |
|                                              | (Veto & Authorization)                             |
|                                              v                                                    |
|  [Tier 1: BEAM OTP Supervision & State Orchestration]                                             |
|  - Pure Gleam/OTP 29 Root Supervisor (`uos_sup.gleam`, `c3i_knowledge_sup.gleam`)                  |
|  - State Machines, Leases, Ingestion Pipelines, and Tripartite Presentation                        |
|                                                                                                   |
|                     |                                              |                              |
|                     | (Port / JSON-RPC)                            | (Bounded C-ABI)              |
|                     v                                              v                              |
|  [Tier 2: Hermes OCaml Formal Oracle]          [Tier 3: Rust Bounded Kernels]                     |
|  - Gospel behavioral contracts                 - Pure SIMD / Vector math                         |
|  - Z3 bounded solver workers                   - Non-blocking parser facades                     |
|  - Rete-UL forward-chaining                    - Hardware safety interlocks                      |
|                                                                                                   |
|                                              |                                                    |
|                                              v (Isolated IPC)                                     |
|  [Tier 4: Supervised External Ingestion Authority]                                                |
|  - Read-Only VM-1 C3I evidence plane (`/home/an/dev/ver/c3i`)                                      |
|  - Two-Key verified ingestion manifests (`governance/sources/`)                                   |
+---------------------------------------------------------------------------------------------------+
```

### Dependency Laws:
1. **Law of Ingestion Purity**: No source code from VM-1 C3I enters UOS without passing through the two-key ingestion pipeline: source quiescence check, secret byte scrubbing, and SHA-256 digest validation.
2. **Law of Supervised Isolation**: The BEAM VM never executes untrusted or potentially blocking C/OCaml foreign code directly in dirty schedulers without timeout traps ($T_{\text{timeout}} \le 100\text{ms}$).
3. **Law of Unidirectional Knowledge Flow**: Knowledge flows from raw evidence $\rightarrow$ canonical parsed notes $\rightarrow$ SQLite WAL ledger $\rightarrow$ OCaml verification $\rightarrow$ Gleam cache $\rightarrow$ Presentation surfaces. The reverse mutation requires constitutional consensus.

---

## 3. Typed Cross-Language Envelopes, Receipts & Error Taxonomy

All communications across Gleam, OCaml, and Rust utilize typed envelopes carrying W3C distributed tracing context:

### 3.1 CrossLanguageEnvelope
```gleam
pub type CrossLanguageEnvelope {
  CrossLanguageEnvelope(
    trace_id: String,
    span_id: String,
    actor_id: String,
    operation: String,
    payload_digest: String,
    payload_json: String,
    timestamp_usec: Int,
    idempotency_key: String,
  )
}
```

### 3.2 CrossLanguageReceipt
```gleam
pub type CrossLanguageReceipt {
  CrossLanguageReceipt(
    receipt_id: String,
    trace_id: String,
    idempotency_key: String,
    status: String,
    execution_time_usec: Int,
    oracle_verdict: String,
    error_code: Int,
    error_message: String,
  )
}
```

### 3.3 Error Taxonomy
| Code | Error Class | Description | Recovery Semantic |
|---|---|---|---|
| `0` | `Ok` | Successful execution with cryptographic proof | Commit state & emit OTel span |
| `-1` | `Timeout` | Worker failed to respond within turn budget ($100\text{ms}$) | Trip Prajna breaker, return degraded |
| `-2` | `NulByteTrap` | Ingress payload contained embedded NUL byte ($0\text{x}00$) | Immediate rejection; audit alert |
| `-3` | `SqlInjection` | Raw SQL statement detected in parameter string | Immediate rejection; fail-closed |
| `-4` | `AuthorityViolation`| Attempted mutation of constitutional or locked resource | SIL-6 Jidoka halt |
| `-5` | `TrustDecayed` | Knowledge artifact trust score decayed below threshold ($< 0.35$) | Exclude from citation; trigger refresh |

---

## 4. Journal, ZK, KM/Smriti, Wiki & Cited Recall Logic

### 4.1 Knowledge Substrate Unification:
The runtime unifies 4 distinct historical knowledge streams into a coherent graph:
1. **Journal Stream**: Chronological execution journals (`docs/journal/`) indexed by `YYYYMMDD-HHSS-` timestamp.
2. **ZK ADR Stream**: Permanent architectural decision records (`docs/zk/`) with invariant proofs.
3. **Smriti Knowledge Base**: Typed entity facts, relationship triples, and semantic coordinate embeddings.
4. **Wiki Knowledge Corpus**: Hierarchical explanatory articles (`docs/wiki/`) with `[[wiki:...]]` and `[[zk:...]]` transclusions.

### 4.2 Cited Recall with Trust & Exponential Decay:
Recall requests calculate relevance and validity using time-decayed Bayesian trust:
$$T(t) = T_0 \cdot e^{-\lambda (t - t_0)} \cdot \prod_{i} w_i$$
where:
- $T_0 \in [0.0, 1.0]$ is initial authority weight (Constitutional = 1.0, Journal = 0.9, Wiki = 0.8, Heuristic = 0.6).
- $\lambda$ is domain decay constant (half-life $\tau_{1/2} = 30$ days for runtime metrics, $\infty$ for constitutional ADRs).
- $w_i \in [0.0, 1.0]$ are verification attestations from recent test passes.

### 4.3 Anti-Pattern Logic:
Negative knowledge (anti-patterns discovered during operation) is indexed with explicit anti-patterns rules, preventing regression into known failure modes.

---

## 5. Wisp SSR, REST API, SSE & WebSocket Routing

The knowledge runtime exposes unified tripartite access on port 4100:

| Route | Method | Surface | Purpose |
|---|---|---|---|
| `/knowledge` | `GET` | Lustre SSR | Interactive knowledge explorer & citation viewer |
| `/api/knowledge/query` | `POST` | Wisp REST | Typed semantic and full-text knowledge query |
| `/api/knowledge/cited-recall` | `POST` | Wisp REST | Citation-backed context extraction for agents |
| `/api/knowledge/anti-patterns` | `GET` | Wisp REST | Active catalog of anti-patterns and mitigation rules |
| `/api/knowledge/events` | `GET` | SSE Stream | Real-time event stream of knowledge ingestion & decay |
| `/api/verify/c3i-knowledge` | `GET` | Telemetry | Conformance verification and health diagnostics |

---

## 6. L0–L7 Fractal Allocation & Verification Gates

| Layer | Subsystem Role | Invariant Enforced | Gate |
|---|---|---|---|
| **$L_0$** | Constitutional Safety & Storage Interlock | NVMe `25503L801736` locked, 0 Bevy, 0 Graphite | `G-ZERO-MUDA`, `G-DRIVE` |
| **$L_1$** | Traceability & Ingress Scrubbing | Embedded NUL byte trap, W3C 128-bit trace correlation | `G-TRACE` |
| **$L_2$** | Domain Components & Pure Vector Math | Pure Erlang `graphene_nif.erl`, 0 foreign NIFs | `G-GRAPHENE` |
| **$L_3$** | Durability & Atomic Commit | Descriptor-relative VFS (`openat`), SQLite WAL lease | `G-VFS` |
| **$L_4$** | Runtime Supervisor & State Orchestration | OTP 29 4-domain tree, Prajna circuit breakers | `G-SUPERVISION` |
| **$L_5$** | Supervised OCaml Oracle & Cognitive OODA | Length-delimited port, Gospel contract evaluation | `G-OCAML-PORT` |
| **$L_6$** | Knowledge Graph & Cited Recall Engine | Bayesian trust decay, anti-pattern suppression | `G-KNOWLEDGE` |
| **$L_7$** | Tripartite Presentation & Web Cockpit | Server-rendered Lustre HTML, Wisp JSON, ANSI TUI | `G-TRIPARTITE` |

---

## 7. Delivery Increments & Recommended First Vertical Slice

1. **Increment 1 (First Vertical Slice)**:
   - Supervised OCaml worker port protocol definition.
   - Gleam knowledge ingestion engine (`c3i_knowledge_runtime.gleam`).
   - Journal ingestion $\rightarrow$ Cited recall $\rightarrow$ OCaml oracle verification $\rightarrow$ Wisp REST API / Lustre SSR display.
2. **Increment 2**:
   - 7,918 VM-1 C3I file dry-run validation.
   - Anti-pattern indexing and negative knowledge filter.
3. **Increment 3**:
   - Live telemetry endpoint `/api/verify/c3i-knowledge` integrated into Cockpit dashboard.
4. **Increment 4**:
   - 15 evolutionary and functional cycles (`EV-40` through `EV-54`) operationalized in `omni_fractal_matrix_engine.gleam`.
   - Ratification on Jujutsu `main`.
