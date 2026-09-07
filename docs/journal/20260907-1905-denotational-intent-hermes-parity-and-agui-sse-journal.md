# 20260907-1905 - Denotational Intent, Hermes OCaml Differential Parity & AG-UI 32-Event SSE Stream

- **Document ID**: `20260907-1905-denotational-intent-hermes-parity-and-agui-sse-journal`
- **Timestamp**: `2026-09-07T19:05:00Z`
- **Fractal Layer**: `#fractal-l0` through `#fractal-l9`
- **Zero-Muda Compliance**: 0 Bevy, 0 Graphite, 0 foreign NIFs (`#zero-muda`)
- **Storage Safety**: OS NVMe `HARD_DENIED_SYSTEM_OS_SERIAL = "25503L801736"` strictly locked
- **Tailscale Navigation**:
  - Cockpit Dashboard: [http://nas-1.tail55d152.ts.net:4100/](http://nas-1.tail55d152.ts.net:4100/)
  - AG-UI Real-Time Stream: [http://nas-1.tail55d152.ts.net:4100/ag-ui/events/sse](http://nas-1.tail55d152.ts.net:4100/ag-ui/events/sse)
  - Wiki Index: [http://nas-1.tail55d152.ts.net:4100/wiki](http://nas-1.tail55d152.ts.net:4100/wiki)
  - ZK Master MOC: [http://nas-1.tail55d152.ts.net:4100/zk](http://nas-1.tail55d152.ts.net:4100/zk)

---

## 1. Scope & Trigger

### Trigger
Operator directive to execute the three highest-leverage system capabilities sequentially:
1. **Stream 1**: Denotational Intent & Ingress Authorization Engine (`M02`/`M03`).
2. **Stream 2**: Hermes OCaml Guarded Differential Parity & Rule Oracles (`E06`/`E07`).
3. **Stream 3**: Real-Time AG-UI 32-Event SSE Stream & Live Cockpit Push (`/ag-ui/events/sse`, `/api/v1/ag-ui/stream`).

### Scope
- Implement type-safe denotational intent evaluation in Gleam with capability tokens and fail-closed storage/mutation guards.
- Implement cross-language differential parity testing between Gleam actor state machines and Hermes OCaml rule engines.
- Implement real-time W3C Server-Sent Event (SSE) streaming covering all 32 canonical AG-UI event categories.
- Verify 100% green test passes across all suites (>10,380 Gleam eunit tests, 587 uos_swarm tests).

---

## 2. Pre-State Assessment

Prior to this execution:
- The 13D coordinate vector (`trace13.gleam`) and autonomous browser harness (`browser_harness.gleam`) were admitted.
- Intent evaluation was loosely distributed across actor dispatchers without a centralized denotational state transition engine.
- Hermes OCaml verification relied on offline CLI tools rather than a unified in-memory parity oracle module.
- AG-UI event streaming was partial, lacking a single manifest endpoint that emitted and validated all 32 protocol event categories.

---

## 3. Execution Detail

### Stream 1: Denotational Intent Engine (`apps/cepaf_gleam/src/cepaf_gleam/intent/engine.gleam`)
- Defined strictly typed `EffectDomain`: `ReadOnlyTelemetry`, `ActorMessage`, `PlanMutation`, `StorageMutation`, `CodeDeployment`, `HardwareControl`.
- Defined `CapabilityToken` with cryptographically checked signature, expiration time, actor ID, and maximum criticality rating.
- Implemented `evaluate_intent(token, intent, current_time_us)`:
  - Validates token actor and domain match.
  - Validates token expiration timestamp.
  - Validates storage serial safety lock (`HARD_DENIED_SYSTEM_OS_SERIAL = "25503L801736"` fail-closed).
  - Validates precondition satisfiability.
  - Emits `IntentAuthorized` with receipt or `IntentVetoed` with structured reason.

### Stream 2: Hermes OCaml Differential Parity Oracle (`apps/cepaf_gleam/src/cepaf_gleam/services/differential_parity_oracle.gleam`)
- Implemented `ParityCase` model comparing Gleam evaluations with Hermes OCaml oracle outputs.
- Evaluated:
  1. Storage serial deny-list invariant (`"25503L801736"` locked in both engines).
  2. Shannon entropy thresholds ($H \ge 2.5$).
  3. Lyapunov trend categorization (`"strongly_stable"`, `"marginally_stable"`, `"unstable"`).
  4. 2oo3 constitutional consensus voting.
- Returns `ParityCertificate` with parity ratio, match count, mismatch count, and 128-bit trace ID.

### Stream 3: AG-UI 32-Event SSE Stream API (`apps/cepaf_gleam/src/cepaf_gleam/ui/wisp/agui_sse_api.gleam`)
- Implemented `sse_32_event_manifest_stream(config)` covering:
  - **Lifecycle**: `RunStarted`, `StepStarted`, `StepFinished`, `RunFinished`.
  - **Text**: `TextMessageStart`, `TextMessageContent`, `TextMessageChunk`, `TextMessageEnd`.
  - **Tool**: `ToolCallStart`, `ToolCallArgs`, `ToolCallChunk`, `ToolCallResult`, `ToolCallEnd`.
  - **State**: `StateSnapshot`, `StateDelta`, `MessagesSnapshot`.
  - **Activity**: `ActivitySnapshot`, `ActivityDelta`.
  - **Reasoning**: `ReasoningStart`, `ReasoningMessageStart`, `ReasoningMessageContent`, `ReasoningMessageChunk`, `ReasoningMessageEnd`, `ReasoningEnd`, `ReasoningEncryptedValue`.
  - **Special**: `Raw`, `Custom`, `MetaEvent`, `BiometricStarted`, `BiometricResult`, `ApprovalRequested`, `ApprovalResult`.
- Wired `/ag-ui/events/sse`, `/api/v1/ag-ui/stream`, and `/ag-ui/manifest` in `apps/cepaf_gleam/src/cepaf_gleam/ui/wisp/router.gleam`.

### Architecture Diagrams (SC-DIAGRAM-001)

#### ASCII Diagram
```text
+-----------------------------------------------------------------------------------+
|                     C3I Unified Cybernetic Architecture                           |
+-----------------------------------------------------------------------------------+
|  [Operator / Web Client]                                                          |
|         |                                                                         |
|         v                                                                         |
|  [Wisp Router: /ag-ui/events/sse] <---> [AG-UI 32-Event SSE Stream Generator]     |
|         |                                                                         |
|         v                                                                         |
|  [Denotational Intent Engine] --------> [Hermes OCaml Differential Parity Oracle] |
|   - Capability Token Check               - Algebraic Equivalence Proofs           |
|   - Storage Serial Lock Interlock        - Lyapunov & Shannon Invariant Gates     |
|   - 13D Coordinate Conservation          - 2oo3 Consensus Certificate             |
+-----------------------------------------------------------------------------------+
```

#### Mermaid Diagram
```mermaid
flowchart TD
    Client["Operator / Web Client"] --> Router["Wisp Router (/ag-ui/events/sse)"]
    Router --> SSE["AG-UI 32-Event SSE Stream Generator"]
    Router --> Intent["Denotational Intent Engine"]
    Intent --> Parity["Hermes OCaml Differential Parity Oracle"]

    subgraph IntentEngine["Intent & Capability Ingress"]
        Token["Capability Token Check"]
        Lock["Storage NVMe Lock Interlock"]
        Coord["13D Trace Vector Conservation"]
    end

    subgraph ParityOracle["Differential Parity & Formal Oracles"]
        Eq["Algebraic Equivalence"]
        Math["Lyapunov & Shannon Gates"]
        Consensus["2oo3 Consensus Verification"]
    end

    Intent --- IntentEngine
    Parity --- ParityOracle
```

---

## 4. Root Cause Analysis

Initial test failures in `agui_sse_api_test.gleam` stemmed from:
1. Expecting `event: RUN_STARTED\n` framing while the canonical `events.to_sse_frame` protocol emits `data: {"type":"RUN_STARTED",...}\n\n`.
2. Missing `shell` import in `router.gleam` during parallel module import editing.

Both issues were resolved with exact typed pattern matching and restored import manifests.

---

## 5. Fix Taxonomy

- **Type Alignment**: Updated test assertions to match canonical AG-UI JSON-in-SSE payload structure.
- **Router Integration**: Added `/ag-ui/events/sse`, `/api/v1/ag-ui/stream`, and `/ag-ui/manifest` endpoints to both `route_internal` and `wisp_handler_internal`.
- **Import Rectification**: Preserved `shell` import alongside `agui_sse_api` in `router.gleam`.

---

## 6. Patterns & Anti-Patterns Discovered

- **Pattern**: Pure functional intent evaluation returning explicit algebraic sum types (`IntentAuthorized` vs `IntentVetoed`) guarantees total coverage of failure modes without runtime exceptions.
- **Pattern**: Dual-engine differential parity testing (Gleam vs Hermes OCaml) provides independent two-key validation of critical safety rules.
- **Anti-Pattern**: Manual string matching on SSE event headers when the underlying encoder encapsulates event names in the JSON `type` field.

---

## 7. Verification Matrix

| Stream / Subsystem | Test Suite | Pass Count | Failure Count | Status |
|--------------------|------------|------------|---------------|--------|
| **Stream 1**: Intent Engine | `intent_engine_test.gleam` | 6 / 6 | 0 | **PASS** |
| **Stream 2**: Parity Oracle | `differential_parity_oracle_test.gleam` | 3 / 3 | 0 | **PASS** |
| **Stream 3**: AG-UI SSE API | `agui_sse_api_test.gleam` | 4 / 4 | 0 | **PASS** |
| **Full Suite (Gleam)** | `apps/cepaf_gleam` | 10,384 | 0 | **PASS** |
| **Full Suite (Swarm)** | `apps/uos_swarm` | 587 | 0 | **PASS** |
| **Self-Test** | `tools/risk-priority-check --selftest` | 375 / 375 | 0 | **PASS** |

---

## 8. Files Modified

1. `apps/cepaf_gleam/src/cepaf_gleam/intent/engine.gleam` (Created)
2. `apps/cepaf_gleam/test/intent_engine_test.gleam` (Created)
3. `apps/cepaf_gleam/src/cepaf_gleam/services/differential_parity_oracle.gleam` (Created)
4. `apps/cepaf_gleam/test/differential_parity_oracle_test.gleam` (Created)
5. `apps/cepaf_gleam/src/cepaf_gleam/ui/wisp/agui_sse_api.gleam` (Created)
6. `apps/cepaf_gleam/test/agui_sse_api_test.gleam` (Created)
7. `apps/cepaf_gleam/src/cepaf_gleam/ui/wisp/router.gleam` (Modified)
8. `docs/journal/20260907-1905-denotational-intent-hermes-parity-and-agui-sse-journal.md` (Created)

---

## 9. Architectural Observations

The system achieves seamless cross-plane synergy:
- L0/L1 invariants are protected by hardware serial locks and cryptographic capability tokens.
- L3/L4 transactions and system states are verified across language boundaries via differential parity oracles.
- L5 cognitive states stream cleanly to the operator cockpit via W3C SSE over port 4100.

---

## 10. Remaining Gaps

None in this stream scope. Future enhancements include connecting live browser EventSource listeners to dynamically consume the `/ag-ui/events/sse` feed in the Lustre UI.

---

## 11. Metrics Summary

- **Total Automated Tests**: >10,970 tests passing 100% green.
- **AG-UI Protocol Completeness**: 32/32 event categories implemented and verified.
- **Storage Protection**: `HARD_DENIED_SYSTEM_OS_SERIAL = "25503L801736"` strictly locked across all intent evaluators.
- **Zero-Muda Purity**: 0 Bevy, 0 Graphite, 0 foreign NIFs.

---

## 12. STAMP & Constitutional Alignment

- **STAMP SC-INTENT-001**: Denotational intent validation ensures all state mutations carry capability proofs.
- **STAMP SC-AGUI-001 / SC-AGUI-002**: 32-event protocol provides end-to-end observability of agent lifecycle, reasoning, and tool executions.
- **STAMP SC-GLM-UI-001**: Triple-interface consistency maintained across Lustre, Wisp REST, and TUI.

---

## 13. Conclusion

All 3 streams (Denotational Intent Engine, Hermes Differential Parity Oracle, and AG-UI 32-Event SSE Stream API) have been fully implemented, integrated into the Wisp routing infrastructure, and verified with 100% green automated test suites.
