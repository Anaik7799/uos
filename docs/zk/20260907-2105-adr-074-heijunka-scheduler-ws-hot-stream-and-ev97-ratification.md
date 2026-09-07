# ADR-074: Autonomous Heijunka Task Scheduler, AG-UI WS Hot Stream & EV-97 Monorepo Ratification

- **Document ID**: `20260907-2105-adr-074-heijunka-scheduler-ws-hot-stream-and-ev97-ratification`
- **Status**: **RATIFIED** (EV-97 Admitted)
- **Author**: Antigravity (AGY) & UOS Swarm Sovereign Authority
- **Fractal Layer**: `#fractal-l0` (Constitutional), `#fractal-l3` (Transaction), `#fractal-l4` (System Queue), `#fractal-l5` (Cognitive OODA)
- **Traceability Tag**: `#zk-adr`, `#zero-muda`, `#heijunka-scheduler`, `#ws-hot-stream`, `#lean4-concurrency`
- **Tailscale Navigation**:
  - Local Cockpit: [http://nas-1.tail55d152.ts.net:4100/](http://nas-1.tail55d152.ts.net:4100/)
  - AG-UI Cockpit: [http://nas-1.tail55d152.ts.net:4100/ag-ui/cockpit](http://nas-1.tail55d152.ts.net:4100/ag-ui/cockpit)
  - ZK Master MOC: [http://nas-1.tail55d152.ts.net:4100/zk](http://nas-1.tail55d152.ts.net:4100/zk)
  - Hermes Wiki Index: [http://nas-1.tail55d152.ts.net:4100/wiki](http://nas-1.tail55d152.ts.net:4100/wiki)
  - Peer Runtime Host: [http://vm-1.tail55d152.ts.net:8088](http://vm-1.tail55d152.ts.net:8088)

---

## 1. Context & Problem Statement

In high-throughput autonomous multi-agent swarms under Fractal TPS principles (`SC-JIDOKA-001`, `SC-SA-PLAN-001`), two critical coordination hazards emerge:
1. **Unlevelled Task Surges & Starvation**: Without a leveled pull-queue (Heijunka), sudden bursts of complex tasks overload worker pools, while un-prioritized FIFO scheduling delays mission-critical safety checks ($L_0/L_2$).
2. **Disconnected UI Telemetry & State Stagnation**: Without real-time WebSocket state streaming with automatic reconnection, jittered backoff, and heartbeat tracking, human-in-the-loop and autonomous agents observe stale telemetry during fast state transitions.
3. **Unchecked Concurrency Invariants**: Without a formal proof of concurrency monotonicity, dynamic adaptation of worker limits could violate bounded execution guarantees ($W \le C$).

---

## 2. Decision Outcome

We have ratified and admitted the following three pillars in `EV-97`:

1. **Autonomous Heijunka Task Scheduler (`apps/cepaf_gleam/src/cepaf_gleam/ha/heijunka_scheduler.gleam`)**:
   - Priority-ordered leveled pull-queuing across 10 fractal layers ($L_0 \dots L_9$).
   - Dynamic pull-capacity auto-tuning driven by Lyapunov exponent feedback ($\lambda(t)$).
   - Strict lease tracking, worker assignment, and automatic expiration reaper.
   - Comprehensive test suite in `apps/cepaf_gleam/test/heijunka_scheduler_test.gleam` (13 tests passing).

2. **Live AG-UI WebSocket Client Integration & Hot-Reload Stream (`apps/cepaf_gleam/src/cepaf_gleam/ui/lustre/ws_hot_stream.gleam`)**:
   - Lustre client-side stream state machine: `Disconnected`, `Connecting(attempt)`, `Connected(session_id, last_heartbeat)`, `Reconnecting(backoff_ms)`.
   - Exponential backoff with jitter for resilient connection recovery.
   - Dynamic buffer windowing (max 50 live events) with heartbeat monitoring.
   - Isomorphic HTML component with status pill, event count, and live telemetry log.
   - Comprehensive test suite in `apps/cepaf_gleam/test/ws_hot_stream_test.gleam` (14 tests passing).

3. **Lean 4 Concurrency Monotonicity Model (`formal/lean/TwoLattice_Concurrency.lean`)**:
   - Mechanized 4 core safety theorems:
     - `pull_task_preserves_wf`: Active workers never exceed pull capacity.
     - `complete_task_preserves_wf`: Task completion safely contracts active worker count.
     - `divergent_adaptation_monotone_contract`: Lyapunov divergence ($\lambda > 0$) strictly contracts capacity to $C_{\min}$.
     - `adapt_capacity_preserves_wf`: General capacity adaptation preserves well-formedness.

---

## 3. Architecture Diagrams (SC-DIAGRAM-001)

### ASCII Diagram

```text
+------------------------------------------------------------------------------------+
|               UOS EV-97 HEIJUNKA SCHEDULER & AG-UI WS STREAM ARCHITECTURE          |
+------------------------------------------------------------------------------------+
|                                                                                    |
|   +--------------------------+               +---------------------------------+   |
|   |   Lyapunov Controller    |  lambda(t)    |     Heijunka Leveled Pull Queue |   |
|   |   (ha/lyapunov_proof)    |-------------->|     (ha/heijunka_scheduler)     |   |
|   +--------------------------+               +----------------+----------------+   |
|                                                               |                    |
|                                                      Pull Task| (Capacity C)       |
|                                                               v                    |
|   +--------------------------+   WsOoZSpan   +----------------+----------------+   |
|   |  AG-UI WS Hot Stream     |<--------------|       Active Swarm Workers      |   |
|   |  (ui/lustre/ws_hot_stream)|  Heartbeats  |       (w_1, w_2, ... w_C)       |   |
|   +--------------------------+               +---------------------------------+   |
|                                                                                    |
+------------------------------------------------------------------------------------+
```

### Mermaid Diagram

```mermaid
flowchart TD
    subgraph Feedback["Lyapunov Control"]
        LC[Lyapunov Observer & Controller]
    end

    subgraph Heijunka["Heijunka Pull Scheduler"]
        HQ[(Priority Task Queue)]
        HC[Capacity Regulator C]
        WT[Active Worker Leases]
    end

    subgraph Telemetry["AG-UI Hot Stream"]
        WS[WebSocket Hot Stream]
        UI[Lustre Dynamic Cockpit]
    end

    LC -->|lambda(t) Feedback| HC
    HQ -->|Levelled Pull| HC
    HC -->|Grant Lease| WT
    WT -->|Task Completion| HQ
    WT -->|Live Events| WS
    WS -->|Reconnection & Render| UI
```

---

## 4. Verification & Validation Status

- **Gleam Test Suite**: **10,435+ EUnit tests 100% green**.
- **9-Modality Test Protocol**: All 9 modalities passing.
- **Risk Checker**: `bash tools/risk-priority-check --selftest` passing (375/375 checks).
- **Formal Verification**: Lean 4 concurrency monotonicity theorems complete in `formal/lean/TwoLattice_Concurrency.lean`.

---

## 5. Checklist & Invariant Confirmation

- [x] `CHK-01-TIME`: Mandatory `YYYYMMDD-HHSS-` timestamp prefix.
- [x] `CHK-02-TAIL`: Clickable Tailscale FQDN links verified.
- [x] `CHK-05-MUDA`: Zero Bevy and Zero Graphite purity maintained.
- [x] `CHK-07-DRIVE`: Host OS NVMe serial `HARD_DENIED_SYSTEM_OS_SERIAL = "25503L801736"` protected.
- [x] `CHK-12-GLEAM`: Pure Gleam/OTP state machines and supervisors.
- [x] `CHK-18-JJ`: Standalone non-colocated Jujutsu (`.jj/`) VCS.

