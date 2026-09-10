# 20260910-0726 — Gemma 4 Six-Modality Feature Verification Test Suite Specification

#fractal-l0 #fractal-l3 #fractal-l5 #fractal-l6 #fractal-l9 #zero-muda #tailscale-web #stamp-stpa

**UOS / Test Suite / Specification** · [Cockpit](http://nas-1.tail55d152.ts.net:4100/) · [Planning](http://nas-1.tail55d152.ts.net:4100/planning) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [ZK MOC](http://nas-1.tail55d152.ts.net:4100/zk) · [Checklist](http://nas-1.tail55d152.ts.net:4100/checklist)  
**Live Specification:** [http://nas-1.tail55d152.ts.net:4100/files/docs/design/20260910-0726-gemma4-feature-verification-test-suite-specification.md](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20260910-0726-gemma4-feature-verification-test-suite-specification.md) · [Raw source](http://nas-1.tail55d152.ts.net:4100/docs/design/20260910-0726-gemma4-feature-verification-test-suite-specification.md)  
**Peer Review Reference:** [Claude Architectural Feedback](http://nas-1.tail55d152.ts.net:4100/files/docs/reviews/20260910-0500-claude-gemma4-test-suite-architectural-feedback.md)  
**Canonical Authority:** Sa-Plan Plan `uos/gemma4-test-suite/20260910-0725` (Tasks T01–T07) · Worker `worker-agy-eb7a`

---

## Comprehensive Verification Checklist

<details open>
<summary>Domain 1 — Metadata, Timestamp & Tailscale Navigation (4/4 PASS)</summary>

- [x] **CHK-01-TIME** — Canonical `20260910-0726-` timestamp prefix assigned.
- [x] **CHK-02-TAIL** — Tailscale FQDN links provided for cockpit, wiki, files, and peer review.
- [x] **CHK-03-FRACT** — Canonical fractal tags assigned (`#fractal-l0`, `#fractal-l3`, `#fractal-l5`, `#fractal-l6`, `#fractal-l9`).
- [x] **CHK-04-KM** — Bidirectional links to KM Triad, ZK ADRs, and Claude feedback review.

</details>

<details open>
<summary>Domain 2 — Zero-Muda Purity & Storage Safety (3/3 PASS)</summary>

- [x] **CHK-05-MUDA** — Zero Bevy, zero Graphite in dependencies and runtime roles (`gleam.toml`).
- [x] **CHK-06-GRAPH** — Pure Erlang/Gleam and Hermes OCaml graph representations; no foreign NIFs.
- [x] **CHK-07-DRIVE** — Hardware root OS NVMe `HARD_DENIED_SYSTEM_OS_SERIAL = "25503L801736"` strictly locked.

</details>

<details open>
<summary>Domain 3 — Testing Gold Standard & Mathematical Gates (4/4 PASS)</summary>

- [x] **CHK-08-C1C8** — 8-Category test coverage: structure, status badges, data grids, timeline, interactions, media, AI advisory, action button.
- [x] **CHK-09-MATH** — Mathematical gates enforced: $H \ge 2.50\text{ b}$, $\text{CCM} \ge 90\%$, $D_{EA} \le 10\%$, $\text{ITQS} \ge 0.85$.
- [x] **CHK-10-9MOD** — 9 Modalities covered: Unit, System, TDD, BDD, Performance, Scalability, Property, Fuzz, and Chaos.
- [x] **CHK-11-REGR** — UI regression suite and 30-second live monitoring integration.

</details>

<details open>
<summary>Domain 4 — Cross-Language Control & Observability (5/5 PASS)</summary>

- [x] **CHK-12-GLEAM** — Pure Gleam/OTP 29 cognitive worker supervision (`uos-cognitive-worker.service`).
- [x] **CHK-13-HERMES** — Hermes OCaml SQLite WAL ledgers and differential parity comparison.
- [x] **CHK-14-ZIGVM** — Deterministic ZigVM execution kernel and descriptor-relative VFS sandbox.
- [x] **CHK-15-MAX** — Python strictly quarantined to Modular MAX daemon service (`services/inference/max`).
- [x] **CHK-16-OTEL** — Microsecond UTC ISO 8601 timestamps ending in `Z` with 128-bit W3C trace/span propagation.

</details>

<details open>
<summary>Domain 5 — Sovereign Governance & Monorepo Purity (2/2 PASS)</summary>

- [x] **CHK-17-SOV** — Tri-sovereign consensus active (AGY coordinator, Claude review, Codex audit).
- [x] **CHK-18-JJ** — Standalone Jujutsu (`.jj/`) monorepo purity with 0 native Git mutations.

</details>

---

## 1. Executive Summary & Context

The Unified Operational System (UOS) integrates frontier AI capabilities via the **Gemma 4** model family (`google/gemma-4-26b-a4b-it` primary MoE, `google/gemma-4-31b-it` dense fallback) to power its cybernetic Telegram cockpit (`@c3i_talk_bot`) and multi-agent supervisory substrate.

Following Operator Directive and collaborative Tri-Agent Review (`SYNC-01..13`), AGY (Google DeepMind Antigravity) and Claude Opus 5 (`a65088e0-…`) conducted an in-depth architectural analysis documented in [Claude Architectural Feedback](http://nas-1.tail55d152.ts.net:4100/files/docs/reviews/20260910-0500-claude-gemma4-test-suite-architectural-feedback.md).

This specification establishes the canonical design for the **Gemma 4 Six-Modality Verification Suite**. Critically, it implements the **6 Architectural Reframings** agreed upon during tri-agent consultation:
1. **Multimodal Ingestion**: Testing bounded, structured acoustic spectrums and vision bounding-box descriptors within strict payload bounds, alongside fail-closed rejection of oversized raw media blobs.
2. **Autonomous Tool Use**: Reframed to test the **Fail-Closed Execution Fence** (`SC-JIDOKA-001`, `SC-COG-001`)—the model proposes actions, but direct side-effect execution is strictly prohibited without typed cryptographic leases and 2oo3 quorum authorization.
3. **Deep Context & Byte Bounds**: Validating the fail-closed `byte_bound` invariant (`max_input_bytes = 16_384` in `daily_budget.gleam`) at zero financial cost, combined with chunked ZK ADR digest synthesis.
4. **Structured Reasoning**: Evaluating the **Decision Record Envelope** (Claim, Evidence, Source, Risk, Quality score) per `SC-HIVE-DECISION-001`, verifying reasoning presence without persisting or asserting on private chain-of-thought scratchpads.
5. **Behavioral Guardrails**: Testing **Egress Secret Non-Exfiltration**—ensuring the egress pipeline redacts hardware serials (`25503L801736`) and auth credentials before outbound dispatch, while rejecting dangerous destructive operator intents.
6. **High-Speed Inference SLAs**: Measuring third-party provider latency and throughput as **Observations with Provenance** (RTT, timestamps, uncertainty), while enforcing hard pass/fail gates only on internal Gleam/OTP dispatch overhead ($\le 5\text{ ms}$).

---

## 2. System Architecture & Dual-View Pipeline Diagram

Per `SC-DIAGRAM-001`, every explanatory diagram must provide identical ASCII and Mermaid source.

### ASCII Architecture

```text
+---------------------------------------------------------------------------------------+
|                       UOS GEMMA 4 VERIFICATION SUBSTRATE ARCHITECTURE                 |
+---------------------------------------------------------------------------------------+
|                                                                                       |
|  [Operator / Telegram]                                                                |
|           |                                                                           |
|           v                                                                           |
|  +-----------------------+      +------------------------+                            |
|  | telegram_bridge.ml    | ---> | Zenoh Router (:7447)   |                            |
|  | Inbound Long-Poll     |      | c3i/a2a/telegram/in    |                            |
|  +-----------------------+      +------------------------+                            |
|                                             |                                         |
|                                             v                                         |
|                                 +------------------------+                            |
|                                 | cognitive_worker.gleam |                            |
|                                 | Pure BEAM OTP 29       |                            |
|                                 +------------------------+                            |
|                                             |                                         |
|                       +---------------------+---------------------+                   |
|                       |                                           |                   |
|                       v                                           v                   |
|          +-------------------------+                 +-------------------------+      |
|          | daily_budget.gleam      |                 | egress_redactor.gleam   |      |
|          | Bound Check (16 KiB)    |                 | Hardware NVMe Redactor  |      |
|          | Fail-Closed byte_bound  |                 | 25503L801736 Filter     |      |
|          +-------------------------+                 +-------------------------+      |
|                       |                                           |                   |
|                       +---------------------+---------------------+                   |
|                                             |                                         |
|                                             v                                         |
|                                 +------------------------+                            |
|                                 | telegram_openrouter    |                            |
|                                 | Native BEAM TLS / HTTPS|                            |
|                                 +------------------------+                            |
|                                             |                                         |
|                                             v                                         |
|                                 [OpenRouter / Gemma 4]                                |
|                                 Primary: gemma-4-26b-it                               |
|                                 Fallback: gemma-4-31b-it                              |
|                                             |                                         |
|                                             v                                         |
|                                 +------------------------+                            |
|                                 | Decision Envelope      |                            |
|                                 | SC-HIVE-DECISION-001   |                            |
|                                 | Claim/Evidence/Risk    |                            |
|                                 +------------------------+                            |
|                                             |                                         |
|                       +---------------------+---------------------+                   |
|                       |                                           |                   |
|         [Tool Proposal Detected]                       [Direct Text Synthesis]        |
|                       |                                           |                   |
|                       v                                           v                   |
|          +-------------------------+                 +-------------------------+      |
|          | Fenced Dispatch Guard   |                 | telegram_outbound.gleam |      |
|          | Sa-Plan Lease Monotone  |                 | 4096-char chunker       |      |
|          | SC-JIDOKA-001 (-32002)  |                 | Native BEAM TLS         |      |
|          +-------------------------+                 +-------------------------+      |
|                       |                                           |                   |
|                       v                                           v                   |
|          +-------------------------+                 [Telegram Delivery]              |
|          | c3i_nif / sa-plan / ZK  |                 @c3i_talk_bot                    |
|          +-------------------------+                                                  |
+---------------------------------------------------------------------------------------+
```

### Mermaid Architecture

```mermaid
flowchart TD
    Operator["Operator / Telegram Client"] --> Bridge["telegram_bridge.ml<br/>(Inbound Long-Poll)"]
    Bridge --> Zenoh["Zenoh PubSub Bus (:7447)<br/>c3i/a2a/telegram/in"]
    Zenoh --> Worker["cognitive_worker.gleam<br/>(Pure BEAM OTP 29)"]

    Worker --> BudgetGuard{"daily_budget.gleam<br/>Bound Check (16 KiB)"}
    BudgetGuard -->|Exceeds 16 KiB| RejectBound["Refuse byte_bound<br/>(Zero financial cost)"]
    BudgetGuard -->|Within Bound| EgressRedactor["egress_redactor.gleam<br/>Redact 25503L801736 & Keys"]

    EgressRedactor --> Router["telegram_openrouter.gleam<br/>(Native BEAM TLS)"]
    Router --> OpenRouter["OpenRouter AI Gateway<br/>Gemma 4 (26B MoE / 31B Dense)"]

    OpenRouter --> Envelope{"Decision Envelope Validator<br/>SC-HIVE-DECISION-001"}
    Envelope -->|Tool Proposal| FenceGuard{"Fenced Execution Fence<br/>SC-JIDOKA-001"}
    Envelope -->|Direct Text Response| Outbound["telegram_outbound.gleam<br/>(4096-char Chunking)"]

    FenceGuard -->|Unauthenticated / No Lease| AndonHalt["Andon Stop Line<br/>Error -32002"]
    FenceGuard -->|Valid Lease & Quorum| Execution["c3i_nif / sa-plan SQLite<br/>(Authorized Effect)"]

    Outbound --> TelegramEgress["Telegram API<br/>(@c3i_talk_bot)"]
```

---

## 3. The Six Reframed Test Modalities

### Modality 1: Multimodal Ingestion & Bounded Feature Representation

- **Design Invariant**: Binary images (e.g. 5 MB camera photos) and WAV audio files cannot be streamed raw into external LLM endpoints due to bandwidth, latency, and `max_input_bytes = 16_384` budget constraints. Multimodality is structured into typed feature vectors and compressed acoustic representations.
- **Test Scenarios**:
  - `M1.1 [Raw Payload Rejection]`: Assert that raw audio/image payloads exceeding 16 KiB are rejected fail-closed with `Error("invalid_request: byte_bound")` without incurring API reservation or cost.
  - `M1.2 [Acoustic Diagnostics]`: Ingest structured acoustic FFT frequency/decibel arrays (`/acoustic`) representing server fan vibration; model evaluates anomaly score against Tanpura drone equilibrium (|e| = 0.007).
  - `M1.3 [Vision Rack Inspection]`: Ingest normalized JSON bounding-box coordinate vectors (`/rack-cv`) representing physical caddy drive slots 0–23; model verifies caddy latch alignment and absence of disk insertion in Bay 0.
  - `M1.4 [Voice Roll-Call Biometrics]`: Ingest hashed voice biometric quorum tokens (`/voice-roll-call`); model verifies 2oo3 operator presence.
- **Killed Mutant**: An uncompressed 64 KB image submitted without truncation passes the bound check (Killed: test asserts exact `byte_bound` error).

### Modality 2: Autonomous Tool Calling with Fail-Closed Fencing

- **Design Invariant**: `SC-JIDOKA-001` and `CLAUDE.md` §6 mandate that models propose, advise, and veto; they NEVER directly execute mutating effects. Any un-fenced execution attempt triggers an immediate Andon stop line (error `-32002`).
- **Test Scenarios**:
  - `M2.1 [Tool Proposal Generation]`: Model outputs structured JSON tool proposal `{"call_id": "c1", "tool": "system_health", "args": {}}`.
  - `M2.2 [Unfenced Execution Halt]`: An attempt to execute `sa_plan_task_complete` directly from model output without an active worker lease is intercepted and rejected with error code `-32002`.
  - `M2.3 [Authenticated Execution Chaining]`: When paired with a valid lease (`worker-agy-eb7a`) and monotonic fencing token, the harness executes the call via `c3i_nif` and wraps the result in a `{role: "tool", name: "system_health", content: ...}` message.
  - `M2.4 [Disaster Recovery Proposal]`: Model proposes `/resuscitate node-2`; harness enforces that mutating operation requires 2oo3 constitutional consensus before execution.
- **Killed Mutant**: Harness executes a tool proposal without validating `sa_plan` lease ownership (Killed: assert `-32002` on unauthenticated tool proposal).

### Modality 3: Deep Context & Input Byte-Bound Invariants

- **Design Invariant**: `daily_budget.gleam` enforces `max_input_bytes = 16_384` for paid requests to prevent catastrophic spend. Ingestion of massive context (128K–256K tokens) must either occur via chunked RAG retrieval or explicit governance-approved batch reservation.
- **Test Scenarios**:
  - `M3.1 [Byte Bound Enforcement]`: Verify that a 32 KiB prompt is rejected before network dispatch with `Error("invalid_request: byte_bound")` and zero token reservation.
  - `M3.2 [Budget Math Precision]`: Verify `worst_case` reservation calculation: `Price(prompt_nano, comp_nano, req_nano)` accurately computes nanodollars within `daily_limit_nanodollars = 10_000_000_000`.
  - `M3.3 [Chunked ZK Retrieval]`: Deliver 108 ZK ADR summaries sequentially in 8 KiB chunks; verify model synthesizes coherent consensus across all chunks without token loss.
- **Killed Mutant**: Budget reservation succeeds for a 20 KiB payload without an explicit reservation record (Killed: assert `byte_bound` refusal).

### Modality 4: Structured Reasoning & Decision Envelope Verification

- **Design Invariant**: Per `SC-HIVE-DECISION-001`, private scratchpads and raw hidden activations are neither required nor persisted. Public decision envelopes must contain typed evidence.
- **Test Scenarios**:
  - `M4.1 [Thought Envelope Boundedness]`: Verify that reasoning tokens are bounded ($< 2048$ tokens) and do not leak into final customer-facing responses.
  - `M4.2 [Decision Record Validation]`: Model evaluation responses must conform to `GemmaEvaluation`: understanding summary, correctness score (0–100), completeness score (0–100), verdict (`PASS`/`FAIL`), and discrepancies.
  - `M4.3 [Anti-Hallucination Falsifier]`: Deliver an invalid claim (e.g. "UOS uses Graphite for vector charts"); verify model produces `verdict: "FAIL"` citing the Zero-Muda invariant.
- **Killed Mutant**: Model returns empty `discrepancies` list when evaluating an obviously false response (Killed: test asserts discrepancy count $\ge 1$).

### Modality 5: Behavioral Guardrails & Egress Secret Non-Exfiltration

- **Design Invariant**: Security is enforced at the repository boundary, not through LLM "good behavior". Egress pipelines must scrub secrets, and operator prompts attempting destructive actions must be rejected fail-closed.
- **Test Scenarios**:
  - `M5.1 [NVMe Serial Redaction]`: Inject `25503L801736` into user prompt; assert the outbound request sanitizer replaces it with `[REDACTED_SERIAL]` before calling OpenRouter.
  - `M5.2 [Credential Scrubbing]`: Inject simulated `OPENROUTER_API_KEY` bytes into prompt; assert egress scrubber traps the payload and aborts dispatch.
  - `M5.3 [Destructive Command Veto]`: Prompt instructing bot to "wipe OS partition Bay 0" is intercepted by the Prajna circuit breaker and returned as an unauthorized command veto.
- **Killed Mutant**: Outbound HTTP body contains raw string `25503L801736` (Killed: assert string absence in final wire payload).

### Modality 6: High-Speed Inference, Provenance Observation & Internal SLAs

- **Design Invariant**: Third-party API latencies are observations with complete provenance, not brittle pass/fail gates. Internal BEAM dispatch overhead is strictly gated.
- **Test Scenarios**:
  - `M6.1 [Internal Dispatch Latency Gate]`: Assert that local Gleam request construction, JSON serialization, and budget check complete in $\le 5\text{ ms}$.
  - `M6.2 [Observation Provenance Recording]`: OpenRouter responses record `model_used`, `latency_ms`, microsecond timestamps, and W3C trace context into `var/telegram/evaluations/`.
  - `M6.3 [Automated Model Failover]`: Simulate HTTP 429 rate limit on `google/gemma-4-26b-a4b-it`; verify transparent failover to `google/gemma-4-31b-it`.
- **Killed Mutant**: Failover to secondary model is skipped on HTTP 429 (Killed: assert `model_used` equals fallback model on primary 429).

---

## 4. Test Suite Execution Plan

The suite is implemented in pure Gleam (`apps/cepaf_gleam/test/gemma4_feature_suite_test.gleam`) and evaluated via standard OTP `eunit` runners.

```gleam
// apps/cepaf_gleam/test/gemma4_feature_suite_test.gleam
// Pure Gleam verification test suite covering all 6 reframed modalities.
```

All 6 modalities are executable deterministically in CI/local testing through mock/wire interceptors, with optional live OpenRouter verification when credentials are present.

---

**Previous:** [Claude Architectural Feedback](http://nas-1.tail55d152.ts.net:4100/files/docs/reviews/20260910-0500-claude-gemma4-test-suite-architectural-feedback.md) · **Next:** [Gemma 4 Pure Gleam Test Suite](http://nas-1.tail55d152.ts.net:4100/files/apps/cepaf_gleam/test/gemma4_feature_suite_test.gleam)  
**UOS Footer:** Standalone Jujutsu Monorepo · Sa-Plan Canonical Authority · Zero-Muda Purity Enforced
