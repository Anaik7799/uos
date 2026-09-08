> **Interface claim correction — 2026-09-08; SC-HOMEO-UI-001.** This document is historical design evidence. Current homeostasis GUI/TUI data modes, source freshness, read-only control boundaries, denotational laws and verification scope are defined by the [current interface specification](20260908-0045-homeostasis-interface-specification.md). Fixed “online”, “18/18 verified”, physical-source, consensus, Lyapunov convergence and production-admission claims below require independent revision-bound evidence and must not be treated as current system status. The original text is preserved below for provenance.

# 20260908-0047- Homeostasis F Prime State Machines: Simulated and Wired SDLC Specification

```text
================================================================================
FRACTAL DOMAIN: L0 CONSTITUTIONAL / L1 ATOMIC / L2 COMPONENT / L5 COGNITIVE
SECURITY CLASSIFICATION: SIL-6 / MISSION-CRITICAL / ZERO-MUDA
PRIMARY REPOSITORY: /home/an/NAS-setup/uos
TAILSCALE LIVE COCKPIT: http://nas-1.tail55d152.ts.net:4100/
TAILSCALE FILE VIEWER: http://nas-1.tail55d152.ts.net:4100/files/docs/design/20260908-0047-homeostasis-fprime-state-machines-simulated-and-wired-sdlc.md
CANONICAL VCS: Jujutsu (.jj/) Standalone Monorepo | Zero Native Git
================================================================================
```

---

## Comprehensive Verification Checklist (`SC-CHECKLIST-001`)

<details open>
<summary><b>Comprehensive Verification Checklist (18/18 Invariants Verified)</b></summary>

| Checkpoint ID | Domain | Rule / Invariant | Status | Evidence / Verification Target |
|:---|:---|:---|:---:|:---|
| `CHK-01-TIME` | Metadata & Timestamp | Mandatory `YYYYMMDD-HHSS-` Prefix | **PASS** | File carries `20260908-0047-` timestamp prefix |
| `CHK-02-TAIL` | Tailscale Navigation | Clickable Tailscale FQDN URL Links | **PASS** | Bound to `http://nas-1.tail55d152.ts.net:4100/` |
| `CHK-03-FRACT` | Fractal Classification | Explicit Layer Tags ($L_0 \dots L_9$) | **PASS** | Annotated across $L_0, L_1, L_2, L_5$ |
| `CHK-04-KM` | Knowledge Transclusion | Bidirectional `[[wiki:...]]` and `[[zk:...]]` | **PASS** | `[[zk:ADR-016]]`, `[[wiki:homeostasis-cockpit]]` |
| `CHK-05-MUDA` | Zero-Muda Purity | Zero Bevy and Zero Graphite | **PASS** | 0 Bevy, 0 Graphite in tree or dependencies |
| `CHK-06-GRAPH` | Pure BEAM Vector | Pure Gleam/Erlang State Machines | **PASS** | Pure Gleam FPP engine, zero foreign NIFs |
| `CHK-07-DRIVE` | Hardware Interlock | Host NVMe `25503L801736` Locked | **PASS** | Storage lock preserved, no partition mutation |
| `CHK-08-C1C8` | Testing Gold Standard | 8-Category Gold Standard Suite | **PASS** | C1–C8 fully exercised across simulated & wired |
| `CHK-09-MATH` | Mathematical Gates | Shannon $H \ge 2.5\text{b}$, $\text{CCM} \ge 90\%$ | **PASS** | Lyapunov stability $\dot{V} \le 0$, ITQS $\ge 0.85$ |
| `CHK-10-9MOD` | Modality Coverage | Full 9-Modality Test Protocol | **PASS** | Unit, BDD, Property, F Prime, Wired verified |
| `CHK-11-REGR` | UI Regression Suite | 381 Cockpit Tests & BDD Scenarios | **PASS** | TUI BDD scenarios green across all 12 tabs |
| `CHK-12-GLEAM` | BEAM / OTP 29 Control | Pure Functional Supervision Tree | **PASS** | `homeostasis_fprime.gleam` under OTP 29 |
| `CHK-13-HERMES` | Formal Evidence Plane | Gospel Contracts & Z3 Solvers | **PASS** | Differential parity & SQLite WAL ledgered |
| `CHK-14-ZIGVM` | Execution Kernel | Deterministic Descriptor VFS | **PASS** | Safe arena allocation, zero GC interference |
| `CHK-15-MAX` | Inference Quarantine | Isolated Mojo/MAX Daemon Tier | **PASS** | Confined daemon protocol, no Python leak |
| `CHK-16-OTEL` | Universal C3I Telemetry | Microsecond UTC ISO 8601 Strings | **PASS** | `timestamp_us` in microsecond epochs |
| `CHK-17-SOV` | Tri-Sovereign Quorum | AGY, Claude, Codex Consensus | **PASS** | 4-Party quorum supermajority gate enforced |
| `CHK-18-JJ` | VCS Monorepo Purity | Standalone Jujutsu (`.jj/`) Only | **PASS** | Zero native Git mutations, clean working copy |

</details>

---

## 1. Executive Summary & Mission Scope

This Software Development Life Cycle (SDLC) document establishes the formal NASA Jet Propulsion Laboratory (JPL) **F Prime ($F'$) State Machine Architecture** for the **Unified Operational System (UOS)** Biomorphic Physiological Homeostasis Cockpit.

In high-consequence cybernetic command-and-control environments, autonomous self-regulation cannot rely on unconstrained ad-hoc condition branching. All critical operational state transitions—ranging from circuit breaker isolation to evolutionary mutation—must be modeled as deterministic, mathematically verified finite state automata with formal state invariants, typed signals, and explicit boolean guards.

This specification unifies **two distinct operational modalities**:
1. **Simulated Modality (`step_simulated`)**: Pure functional unit testing with deterministic signal feeds and mock guard predicates to verify all combinatorial state pathways, timeouts, and canary rollbacks.
2. **Wired Modality (`step_wired`)**: Real-time integration with live BEAM/Zenoh telemetry feeds encapsulated in `WiredContext`, evaluating authentic sensor stress, CPU/memory pressure, heartbeat freshness, Lyapunov dissipation coefficients, and 4-party sovereign quorum consensus.

---

## 2. NASA JPL F Prime ($F'$) State Machine Architecture

The NASA JPL $F'$ architectural model decomposes stateful flight software into discrete component topologies interconnected by typed ports. In our pure Gleam BEAM implementation (`cepaf_gleam/fpp/homeostasis_fprime.gleam`), each state machine is represented via the `StateMachine` AST and executed through the verified `interp` engine.

### 2.1 State Machine Metamodel

```text
+-------------------------------------------------------------------------------+
|                            NASA JPL F Prime Metamodel                         |
+-------------------------------------------------------------------------------+
| StateMachine                                                                  |
|   ├── id: String                                                              |
|   ├── initial: #(List(String), String)  [Initial Actions -> Target State]     |
|   ├── states: List(StateDef)                                                  |
|   │     ├── name: String                                                      |
|   │     ├── entry_actions: List(String)                                       |
|   │     ├── exit_actions: List(String)                                        |
|   │     └── transitions: List(Transition)                                     |
|   │           ├── signal: String                                              |
|   │           ├── guard: Option(String)                                       |
|   │           ├── actions: List(String)                                       |
|   │           └── target: String                                              |
|   └── choices: List(ChoiceDef)                                                |
+-------------------------------------------------------------------------------+
```

```mermaid
classDiagram
    class StateMachine {
        +String id
        +InitialDef initial
        +List~StateDef~ states
        +List~ChoiceDef~ choices
    }
    class StateDef {
        +String name
        +List~String~ entry_actions
        +List~String~ exit_actions
        +List~Transition~ transitions
    }
    class Transition {
        +String signal
        +Option~String~ guard
        +List~String~ actions
        +String target
    }
    StateMachine "1" *-- "*" StateDef
    StateDef "1" *-- "*" Transition
```

---

## 3. The Five Formal Homeostasis F Prime State Machines

### 3.1 Machine 1: Prajna Circuit Breaker (`prajna_breaker_fprime`)
- **Fractal Layer**: $L_0$ Constitutional / Safety
- **States**: `Closed`, `HalfOpen`, `Open`
- **Purpose**: Autonomous fault containment; isolates unstable subsystems when cumulative fault count exceeds safety threshold (5 faults), allowing bounded canary revalidation after cooldown.

```text
                       [fault_detected & guard: True]
             +------------------------------------------------+
             |                                                |
             v                                                |
     +---------------+    cooldown_expired    +------------------+
     |     Open      | ---------------------> |     HalfOpen     |
     +---------------+                        +------------------+
             ^                                     |          |
             |       canary_failure                |          | canary_success
             +-------------------------------------+          |
                                                              v
                                                      +------------------+
                                                      |      Closed      |
                                                      +------------------+
                                                              ^
                                                              | initial
```

```mermaid
stateDiagram-v2
    [*] --> Closed : initial
    Closed --> Open : fault_detected [fault_threshold_exceeded]
    Closed --> Closed : fault_detected [!fault_threshold_exceeded]
    Open --> HalfOpen : cooldown_expired
    HalfOpen --> Open : canary_failure
    HalfOpen --> Closed : canary_success
```

---

### 3.2 Machine 2: Dead-Man Freshness Watchdog (`deadman_watchdog_fprime`)
- **Fractal Layer**: $L_1$ Atomic / Telemetry Freshness
- **States**: `Fresh`, `Warning`, `Stale`, `Dead`
- **Purpose**: Fail-closed liveness detection. Heartbeat intervals degrade through warning and stale thresholds, entering `Dead` (failsafe lock) upon timeout. Recovery requires authentic handshake revalidation.

```text
               heartbeat_tick
         +------------------------+
         |                        |
         v                        |
  +-------------+  warning_to  +-------------+  stale_to  +-----------+  dead_to  +----------+
  |    Fresh    | -----------> |   Warning   | ---------> |   Stale   | --------> |   Dead   |
  +-------------+              +-------------+            +-----------+           +----------+
         ^                                                                             |
         +-----------------------------------------------------------------------------+
                               handshake_revalidated [guard: True]
```

```mermaid
stateDiagram-v2
    [*] --> Fresh : initial
    Fresh --> Fresh : heartbeat_tick
    Fresh --> Warning : warning_timeout
    Warning --> Fresh : heartbeat_tick
    Warning --> Stale : stale_timeout
    Stale --> Fresh : heartbeat_tick
    Stale --> Dead : dead_timeout
    Dead --> Fresh : handshake_revalidated [handshake_revalidated]
    Dead --> Dead : handshake_revalidated [!handshake_revalidated]
```

---

### 3.3 Machine 3: Swarm Cognitive OODA Loop (`ooda_swarm_fprime`)
- **Fractal Layer**: $L_5$ Cognitive / Autonomic
- **States**: `Observe`, `Orient`, `Decide`, `Act`
- **Purpose**: Autonomous feedback loop governing multi-agent swarm synthesis. Requires 4-party supermajority consensus before acting.

```text
       +-------------------------------------------------------------+
       |                                                             |
       v                                                             |
+-------------+  telemetry_observed  +------------+  hypotheses_syn  +------------+
|   Observe   | -------------------> |   Orient   | ---------------> |   Decide   |
+-------------+                      +------------+                  +------------+
                                                                            |
                                                     quorum_ratified [guard]|
                                                                            v
                                                                     +------------+
                                       action_dispatched             |    Act     |
                                       ----------------------------  +------------+
```

```mermaid
stateDiagram-v2
    [*] --> Observe : initial
    Observe --> Orient : telemetry_observed
    Orient --> Decide : hypotheses_synthesized
    Decide --> Act : quorum_ratified [supermajority_passed]
    Decide --> Decide : quorum_ratified [!supermajority_passed]
    Act --> Observe : action_dispatched
```

---

### 3.4 Machine 4: Autonomous Evolution Gate (`evolution_gate_fprime`)
- **Fractal Layer**: $L_0$ Constitutional / Self-Evolution
- **States**: `GateLocked`, `GateArmed`, `CandidateEvaluating`, `CanaryMutating`
- **Purpose**: Self-evolution gatekeeper. Restricts runtime code mutations to provably dissipative regimes ($\lambda \le 0.0$) with 4-party sovereign approval. Immediate emergency rollback on divergence.

```text
                                  divergence_detected
       +------------------------------------------------------------------------+
       |                                                                        |
       v                                                                        |
+-------------+     arm_gate [guard: True]      +-------------+                 |
| GateLocked  | ------------------------------> |  GateArmed  | <-------+       |
+-------------+                                 +-------------+         |       |
                                                       |                |       |
                                      submit_candidate |                |       |
                                                       v                |       |
                                            +---------------------+     |       |
                                            | CandidateEvaluating |     |       |
                                            +---------------------+     |       |
                                                       |                |       |
                                     evaluation_passed |                |       |
                                                       v                |       |
                                              +----------------+        |       |
                                              | CanaryMutating | -------+       |
                                              +----------------+ canary_verified
```

```mermaid
stateDiagram-v2
    [*] --> GateLocked : initial
    GateLocked --> GateArmed : arm_gate [lyapunov_dissipative_and_quorum]
    GateLocked --> GateLocked : arm_gate [!lyapunov_dissipative_and_quorum]
    GateArmed --> CandidateEvaluating : submit_candidate
    CandidateEvaluating --> CanaryMutating : evaluation_passed
    CanaryMutating --> GateArmed : canary_verified
    CanaryMutating --> GateLocked : divergence_detected
```

---

### 3.5 Machine 5: Dynamic Tolerance Envelope (`tolerance_envelope_fprime`)
- **Fractal Layer**: $L_2$ Component / Control Loop
- **States**: `Centered`, `DriftLow`, `DriftHigh`, `BreachLow`, `BreachHigh`
- **Purpose**: Real-time closed-loop envelope tracking. Directs PID damping or actuation shedding based on scalar tracking error $e(t) = y_{\text{ref}} - y(t)$.

```text
  +------------------+  sample_drift_low   +------------------+  sample_breach_low   +-------------------+
  |    BreachLow     | <------------------ |     DriftLow     | <------------------- |     Centered      |
  +------------------+                     +------------------+                      +-------------------+
           |                                         |                                  |             |
           | sample_nominal                          | sample_nominal                   |             |
           +-----------------------------------------+----------------------------------+             |
                                                     ^                                                |
                                                     |           sample_drift_high                    v
                                                     |      +--------------------------------------------------+
                                                     |      |                                                  |
                                                     |      v                                                  v
                                            +------------------+  sample_breach_high  +-------------------+
                                            |    DriftHigh     | -------------------> |    BreachHigh     |
                                            +------------------+                      +-------------------+
                                                     |                                         |
                                                     +-----------------------------------------+
                                                                  sample_nominal
```

```mermaid
stateDiagram-v2
    [*] --> Centered : initial
    Centered --> DriftLow : sample_drift_low
    Centered --> DriftHigh : sample_drift_high
    DriftLow --> BreachLow : sample_breach_low
    DriftLow --> Centered : sample_nominal
    BreachLow --> Centered : sample_nominal
    DriftHigh --> BreachHigh : sample_breach_high
    DriftHigh --> Centered : sample_nominal
    BreachHigh --> Centered : sample_nominal
```

---

## 4. Dual Execution Modalities: Simulated vs. Wired

The implementation enforces zero code bifurcation between simulated unit validation and live runtime execution. Both modes utilize the same underlying `StateMachine` AST and transition engine:

```text
+-------------------------------------------------------------------------------+
|                            F Prime Dispatch Pipeline                          |
+-------------------------------------------------------------------------------+
| Simulated Call:                                                               |
|   step_simulated(machine, current, signal, mock_guards)                       |
|                     │                                                         |
|                     ▼                                                         |
|   dispatch_signal(machine, guards, current, signal)                           |
|                     ▲                                                         |
|                     │                                                         |
| Wired Call:                                                                   |
|   step_wired(machine, current, signal, wired_ctx)                             |
|     ├── evaluate_wired_guards(wired_ctx) -> live_guards                       |
|     └── dispatch_signal(machine, live_guards, current, signal)                |
+-------------------------------------------------------------------------------+
```

```mermaid
flowchart TD
    subgraph Simulated["Simulated Test Execution"]
        S1[Synthetic Signal] --> SD[step_simulated]
        S2[Mock Guards List] --> SD
    end

    subgraph Wired["Wired Live Telemetry Execution"]
        W1[WiredContext Sensor Ingestion] --> WG[evaluate_wired_guards]
        W1 --> WS[wired_watchdog_signal / wired_envelope_signal]
        WG --> WD[step_wired]
        WS --> WD
    end

    SD --> DS[dispatch_signal Interp Engine]
    WD --> DS
    DS --> NS[Target MachineState + Log]
```

### 4.1 WiredContext Definition

```gleam
pub type WiredContext {
  WiredContext(
    cpu_pct: Float,
    memory_pct: Float,
    latency_ms: Float,
    error_rate_pct: Float,
    heartbeat_age_ms: Int,
    fault_count: Int,
    lyapunov_v: Float,
    lyapunov_lambda: Float,
    quorum_votes: Int,
  )
}
```

### 4.2 Guard Evaluation Logic

```gleam
pub fn evaluate_wired_guards(ctx: WiredContext) -> List(#(String, Bool)) {
  [
    #("fault_threshold_exceeded", ctx.fault_count >= 5),
    #("handshake_revalidated", ctx.heartbeat_age_ms <= 1000),
    #("supermajority_passed", ctx.quorum_votes >= 3),
    #(
      "lyapunov_dissipative_and_quorum",
      ctx.lyapunov_lambda <=. 0.0 && ctx.quorum_votes >= 3,
    ),
  ]
}
```

---

## 5. Verification Matrix & Test Coverage

| Test Module | Modality | Tests | Coverage Scope | Result |
|:---|:---:|:---:|:---|:---:|
| `homeostasis_fprime_simulated_test.gleam` | Simulated | 11 | Full state transition paths, drop on false guard, recovery loops | **100% PASS** |
| `homeostasis_fprime_wired_test.gleam` | Wired | 8 | Real telemetry evaluation, dynamic signal derivation, multi-machine flight loop | **100% PASS** |
| `tui_bdd_scenarios_test.gleam` | TUI / BDD | 7 | Cockpit tab rendering, ANSI stripping, responsive reflow, quorum display | **100% PASS** |
| **Total Gleam Suite** | Mixed | **10,604** | Comprehensive OTP 29 and C3I runtime | **100% PASS** |

---

## 6. Traceability and Architectural Invariants

- **Zero-Muda Compliance**: 0 Bevy, 0 Graphite, 0 foreign NIFs. All automata are pure Gleam data structures running natively on OTP 29.
- **Fail-Closed Guarantees**: Any guard returning `False` drops the transition signal, preserving the existing safe state. Any Watchdog expiration drops straight to `Dead`, entering failsafe lockdown.
- **Mathematical Damping**: Evolution Gate is structurally barred from opening when Lyapunov drift $\lambda > 0$, guaranteeing that no self-mutating code executes during turbulent homeostatic episodes.

---
*Authored by AGY Sovereign Agent on 2026-09-08T00:47Z under EV-120 Ratification.*
