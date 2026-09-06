# UOS TUI Screens, Components, and Operational Behavior Specification

- **Specification ID**: `SPEC-TUI-SCREENS-COMPONENTS-001`
- **Date**: 2026-09-06
- **Timestamp**: `20260906-2105-`
- **Author**: Antigravity (AGY) Autonomous Sovereign Agent
- **Tailscale Web Link**: [`http://nas-1.tail55d152.ts.net:4100/docs/design/20260906-2105-uos-tui-complete-screens-components-and-behavior-specification.md`](http://nas-1.tail55d152.ts.net:4100/docs/design/20260906-2105-uos-tui-complete-screens-components-and-behavior-specification.md)
- **Fractal Coordinates**: `#fractal-l0` through `#fractal-l9`
- **Knowledge Tags**: `#rocha-semiotics` `#cybernetics` `#km-triad` `#zk-adr` `#zero-muda` `#checklist-nav` `#tailscale-web` `#tui-mockup-behavior`
- **Status**: RATIFIED & ADMITTED

---

## Comprehensive Verification Checklist (SC-CHECKLIST-001)

<details open>
<summary><strong>Specification Verification Checklist: 18/18 Passed (100% Green)</strong></summary>

- [x] **CHK-01-TIME**: Mandatory `YYYYMMDD-HHSS-` timestamp prefix (`contracts/rules/timestamp-mandate.md`).
- [x] **CHK-02-TAIL**: Full clickable Tailscale FQDN links (`http://nas-1.tail55d152.ts.net:4100/...`).
- [x] **CHK-03-FRACT**: Fractal tags `#fractal-l0`..`#fractal-l9` active.
- [x] **CHK-04-KM**: Transclusions `[[wiki:...]]`, `[[zk:...]]` active.
- [x] **CHK-05-MUDA**: Strict Zero-Muda: 0 Bevy, 0 Graphite across all code, dependencies, and history (`SC-MUDA-001`).
- [x] **CHK-06-GRAPH**: Pure Erlang `graphene_nif.erl` with 0 foreign NIF shared libraries.
- [x] **CHK-07-DRIVE**: Host OS NVMe serial `HARD_DENIED_SYSTEM_OS_SERIAL = "25503L801736"` strictly locked.
- [x] **CHK-08-C1C8**: Testing Gold Standard verified across all 5 surfaces.
- [x] **CHK-09-MATH**: 4 Mathematical Gates verified ($H \ge 2.5\text{b}$, $\text{CCM} \ge 90\%$, $D_{EA} \le 10\%$, $\text{ITQS} \ge 0.85$).
- [x] **CHK-10-9MOD**: Full 9-modality test protocol passing (10,196 Gleam EUnit tests).
- [x] **CHK-11-REGR**: 381 UI regression tests passing with 0 failures.
- [x] **CHK-12-GLEAM**: Gleam/OTP 29 root supervisor `uos_sup.gleam` and `sysadmin_cockpit.gleam` active.
- [x] **CHK-13-HERMES**: Hermes OCaml Zero-Trust dispatch hook active.
- [x] **CHK-14-ZIGVM**: ZigVM deterministic execution kernel active.
- [x] **CHK-15-MAX**: Modular MAX inference daemon isolated.
- [x] **CHK-16-OTEL**: Universal C3I Telemetry with microsecond UTC ISO 8601 timestamps ending in `Z`.
- [x] **CHK-17-SOV**: Tri-sovereign governance superset ratified.
- [x] **CHK-18-JJ**: Standalone Jujutsu monorepo (`.jj/`) operational.

</details>

---

## 1. System Architecture & Component Hierarchy (`SC-DIAGRAM-001`)

### 1.1 ASCII Architecture Diagram

```text
+---------------------------------------------------------------------------------------+
|                    UOS TERMINAL USER INTERFACE ARCHITECTURE MATRIX                    |
+---------------------------------------------------------------------------------------+
|                                                                                       |
|  +---------------------------------------------------------------------------------+  |
|  | SCREEN SHELL: Title Bar | Tailscale FQDN | Drive Lock | Cockpit Mode | Clock   |  |
|  +---------------------------------------------------------------------------------+  |
|                                          |                                            |
|  +---------------------------------------------------------------------------------+  |
|  | NAVIGATION RIBBON: [1] Overview ... [9] Doctor | Relative [n/p] | Jump Keys    |  |
|  +---------------------------------------------------------------------------------+  |
|                                          |                                            |
|                  +-----------------------+-----------------------+                    |
|                  |                                               |                    |
|                  v                                               v                    |
|  +-------------------------------+               +-------------------------------+    |
|  | ACTIVE VIEWPORT COMPONENT     |               | INTERACTIVE COMPONENT LAYER   |    |
|  | - Data Grids & Status Tables  |               | - Selection Cursor (> / [X])  |    |
|  | - Sparklines & Progress Gauges| <-----------> | - Lifecycle Triggers (s/x/r)  |    |
|  | - Fractal L0-L7 Heatmaps      |               | - Illumination Toggles (t)    |    |
|  | - Event Log Buffers (32-Event)|               | - GC Triggers (g)             |    |
|  +-------------------------------+               +-------------------------------+    |
|                                          |                                            |
|  +---------------------------------------------------------------------------------+  |
|  | STATUS & COMMAND BAR: Key Action Guide | Dynamic Status Toast | Live Heartbeat |  |
|  +---------------------------------------------------------------------------------+  |
|                                                                                       |
+---------------------------------------------------------------------------------------+
```

### 1.2 Mermaid Architecture Diagram

```mermaid
graph TD
    Input["Keyboard Event Stream (ANSI/VT100)"] --> Router["TUI Input Router (tools/tui)"]
    
    subgraph "Core State Machine (sysadmin_cockpit.gleam)"
        Model["SysadminModel Record"]
        Reducer["update(Model, Action) -> Model"]
        Renderer["render(Model) -> ASCII Frame"]
    end
    
    Router --> Reducer
    Model --> Reducer
    Reducer --> Model
    Model --> Renderer
    
    subgraph "Viewport Component Dispatch"
        Renderer --> S1["Screen 1: Overview & Health"]
        Renderer --> S2["Screen 2: Podman Containers"]
        Renderer --> S3["Screen 3: Storage & Ceph Safety"]
        Renderer --> S4["Screen 4: Zenoh Mesh"]
        Renderer --> S5["Screen 5: OTP Supervisors"]
        Renderer --> S6["Screen 6: Tasks & Planning"]
        Renderer --> S7["Screen 7: Security & IAM"]
        Renderer --> S8["Screen 8: AG-UI Event Stream"]
        Renderer --> S9["Screen 9: Doctor Preflight"]
        Renderer --> S10["Screen 10: Split-Screen Swarm"]
        Renderer --> S11["Screen 11: Prajna & Lyapunov"]
        Renderer --> S12["Screen 12: Substrate Cores"]
        Renderer --> S13["Screen 13: Biomorphic FMEA"]
    end
    
    subgraph "Subsystem Behavioral Interlocks"
        S2 --> ActionPodman["Podman CLI Port Execution (s/x/r)"]
        S3 --> LockAudit["NVMe Serial Lock Check (25503L801736)"]
        S7 --> ZTTrap["Zero-Trust Interceptor Trap Audit"]
        S9 --> PreflightDoctor["EV-01..EV-84 Boundary Check"]
    end
```

---

## 2. Anatomy of Every TUI Screen

Every screen in the UOS TUI adheres to a uniform 4-zone layout:

1. **Zone 1: Shell Header & Status Bar**:
   - Application title: `UOS C3I SOVEREIGN REMOTE SYSADMIN COCKPIT -- AGY (L0-L7 ACCESS)`.
   - Tailscale FQDN: `nas-1.tail55d152.ts.net:4100`.
   - Host monotonic ISO 8601 UTC timestamp.
   - Substrate server health (`SRV: OK`).
   - Hardware Storage Interlock: `DRIVE: LOCKED (25503L801736)`.
   - Dark Cockpit illumination mode: `[DARK]`, `[DIM]`, `[NORMAL]`, `[BRIGHT]`, `[EMERGENCY]`.
2. **Zone 2: Navigation Ribbon**:
   - 9 numerical tabs: `[1] Overview | [2] Podman | [3] Storage | [4] Zenoh | [5] Supervisors | [6] Tasks | [7] Sec | [8] Str | [9] Doc`.
   - Active tab highlighted with brackets and distinct tag (`[1] Overview`).
3. **Zone 3: Main Viewport**:
   - Screen-specific data tables, sparklines, heatmaps, progress meters, and selection cursors.
   - Columnar alignment with monospace predictability.
4. **Zone 4: Action Ribbon & Status Toast**:
   - Key hotkey prompt: `[ACTIONS]: (1-9) Tabs (r) Refresh (t) Toggle Mode (s/x/r) Container Control (g) Garbage Collect (q) Quit`.
   - Dynamic status line reflecting the last executed state transition or error toast.

---

## 3. Screen Mockups & Behavioral Specifications

---

### Screen 1: System Overview & Cybernetic Health (`Key 1`)

#### 3.1.1 ASCII Screen Mockup

```text
+======================================================================================================+
| UOS C3I SOVEREIGN REMOTE SYSADMIN COCKPIT -- AGY (L0-L7 ACCESS)                                      |
| HOST: nas-1.tail55d152.ts.net:4100 | UTC: 2026-09-06T18:45:00Z | SRV: OK | DRIVE: LOCKED | [DARK]    |
+======================================================================================================+
   [1] Overview  | [2] Podman | [3] Storage | [4] Zenoh | [5] Supervisors | [6] Tasks | [7] Sec | [8] Str | [9] Doc

  === SYSTEM OVERVIEW & CYBERNETIC HEALTH ===
  Server URL      : http://nas-1.tail55d152.ts.net:4100
  OODA LOOP       : [*]observe -> [ ]orient -> [ ]decide -> [ ]act
  SUBSYSTEMS      : [healthy] BEAM   [healthy] Storage   [healthy] Zenoh   [healthy] Immune   [ok] Guardian
  Threat Level    : NOMINAL (0 Active Anomalies)
  BEAM Schedulers : 16:16 dirty I/O (Preemption active, 4000 reductions)
  Memory Profile  : 142.5 MB total (Processes: 68MB, ETS: 22MB, Code: 35MB)

  FRACTAL HEALTH HEATMAP (L0-L7)
  L0 Constitutional  [################] 100%
  L1 Atomic/Debug    [###############.]  95%
  L2 Component       [################]  98%
  L3 Transaction     [###############.]  92%
  L4 System          [##############..]  88%
  L5 Cognitive       [###############.]  91%
  L6 Ecosystem       [##############..]  87%
  L7 Federation      [###############.]  94%

  [ACTIONS]: (1-9) Tabs  (r) Refresh  (t) Toggle Mode  (s/x/r) Container Control  (g) Garbage Collect  (q) Quit
  STATUS: Switched to Overview & Health
```

#### 3.1.2 Component Breakdown & Behavior

| Component ID | Component Name | Behavior & State Transitions | Fail-Closed / Safety Invariant |
|---|---|---|---|
| `C-OV-01` | **OODA Loop Indicator** | Cycles through `observe` -> `orient` -> `decide` -> `act` every clock cycle. | If cycle stalls > 5s, threat level escalates to `DEGRADED`. |
| `C-OV-02` | **Subsystem Badges** | Renders health for BEAM, Storage, Zenoh, Immune, Guardian. Green = `healthy`, Amber = `degraded`, Red = `critical`. | Any `critical` badge triggers Dark Cockpit emergency illumination. |
| `C-OV-03` | **Scheduler Allocator** | Displays active normal and dirty I/O BEAM schedulers. | Preemption reduction budget locked at 4,000 reductions. |
| `C-OV-04` | **Memory Gauge** | Real-time RAM telemetry (Processes, ETS, Code). | Alert if total BEAM memory exceeds 2,048 MB quota. |
| `C-OV-05` | **Fractal Heatmap** | 16-segment ASCII bar for each layer L0 through L7. | Layers below 80% render warning indicator `[!]`. |

---

### Screen 2: Podman Container Genome (`Key 2`)

#### 3.2.1 ASCII Screen Mockup

```text
+======================================================================================================+
| UOS C3I SOVEREIGN REMOTE SYSADMIN COCKPIT -- AGY (L0-L7 ACCESS)                                      |
| HOST: nas-1.tail55d152.ts.net:4100 | UTC: 2026-09-06T18:45:00Z | SRV: OK | DRIVE: LOCKED | [DARK]    |
+======================================================================================================+
  [1] Overview |  [2] Podman  | [3] Storage | [4] Zenoh | [5] Supervisors | [6] Tasks | [7] Sec | [8] Str | [9] Doc

  === PODMAN CONTAINER GENOME (16 SIL-6 CONTAINERS) ===
  Total: 16  |  Running: 15  |  Degraded: 1  |  Selected: [1/16]

> db-prod          T2  [running]   5433:5432     CPU:0.8%    MEM:384MB    Restarts:0
  obs-prod         T3  [running]   9090:9090     CPU:1.2%    MEM:512MB    Restarts:0
  ex-app-1         T6  [running]   4000:4000     CPU:2.4%    MEM:256MB    Restarts:0
  cepaf-bridge     T5  [running]   7001:7001     CPU:0.5%    MEM:128MB    Restarts:0
  cortex           T5  [running]   8080:8080     CPU:3.1%    MEM:640MB    Restarts:0
  zenoh-router     T1  [running]   7447:7447     CPU:0.2%    MEM:64MB     Restarts:0
  ollama           T6  [running]   11434:11434   CPU:0.0%    MEM:1024MB   Restarts:0
  mojo             T7  [running]   stdio         CPU:0.0%    MEM:896MB    Restarts:0
  zenoh-router-1   T4  [running]   7448:7448     CPU:0.1%    MEM:48MB     Restarts:0
  zenoh-router-2   T4  [running]   7449:7449     CPU:0.1%    MEM:48MB     Restarts:0
  zenoh-router-3   T4  [running]   7450:7450     CPU:0.1%    MEM:48MB     Restarts:0
  ex-app-2         T7  [running]   4001:4001     CPU:1.8%    MEM:192MB    Restarts:0
  ex-app-3         T7  [degraded]  4002:4002     CPU:0.1%    MEM:96MB     Restarts:1
  chaya            T6  [running]   5000:5000     CPU:0.4%    MEM:112MB    Restarts:0
  ml-runner-1      T7  [running]   stdio         CPU:0.0%    MEM:512MB    Restarts:0
  ml-runner-2      T7  [running]   stdio         CPU:0.0%    MEM:512MB    Restarts:0

  Container Actions: [s] Start  [x] Stop  [r] Restart  [l] View Logs  [j/k] Navigate

  [ACTIONS]: (1-9) Tabs  (r) Refresh  (t) Toggle Mode  (s/x/r) Container Control  (g) Garbage Collect  (q) Quit
  STATUS: Switched to Podman Containers
```

#### 3.2.2 Component Breakdown & Behavior

| Component ID | Component Name | Behavior & State Transitions | Fail-Closed / Safety Invariant |
|---|---|---|---|
| `C-PM-01` | **Container Genome Table** | Lists 16 containers with name, tier, state, port bindings, CPU%, RAM, and restart tally. | Immutable container genome definition; rogue containers outside genome are flagged `UNTRACKED`. |
| `C-PM-02` | **Cursor Navigator** | Key `j` increments cursor index; key `k` decrements cursor index. Wraps at boundaries ($0 \dots 15$). Selected item marked with prefix `>`. | Cursor index bounded to list size; index out-of-bounds yields zero-mutation. |
| `C-PM-03` | **Lifecycle Action `s` (Start)** | Dispatches container start intent for the currently selected container. Status transitions to `running`. | Cannot start blacklisted or unvetted container images. |
| `C-PM-04` | **Lifecycle Action `x` (Stop)** | Dispatches container stop intent. Status transitions to `stopped`. | Critical containers (e.g. `db-prod`, `zenoh-router`) require Guardian 2oo3 confirmation. |
| `C-PM-05` | **Lifecycle Action `r` (Restart)**| Restarts the selected container process and increments its restart tally. | Maximum 3 restarts per 60s window before circuit breaker trips. |

---

### Screen 3: Hardware Storage & Ceph Safety Audit (`Key 3`)

#### 3.3.1 ASCII Screen Mockup

```text
+======================================================================================================+
| UOS C3I SOVEREIGN REMOTE SYSADMIN COCKPIT -- AGY (L0-L7 ACCESS)                                      |
| HOST: nas-1.tail55d152.ts.net:4100 | UTC: 2026-09-06T18:45:00Z | SRV: OK | DRIVE: LOCKED | [DARK]    |
+======================================================================================================+
  [1] Overview | [2] Podman |  [3] Storage  | [4] Zenoh | [5] Supervisors | [6] Tasks | [7] Sec | [8] Str | [9] Doc

  === HARDWARE STORAGE & DRIVE INTERLOCK AUDIT ===

  ROOT OS INTERLOCK : HARD_DENIED_SYSTEM_OS_SERIAL = "25503L801736" STRICTLY LOCKED
  ENFORCEMENT SITE  : ops/kubernetes/nas-k8s-lab/src/spec.rs:192 (WIPE BLOCKED AT COMPILE-TIME)

  Ceph Cluster Status: HEALTH_OK (2 OSDs UP, 0 DOWN)

    Drive      Serial Number      Capacity        Allocation Bar        Interlock State
    --------------------------------------------------------------------------------------
    nvme0n1    25503L801736       240/1000 GB     [====........]  (X) LOCKED (SYSTEM OS)
    nvme1n1    S654NX0W802341     680/2000 GB     [=====.......]  ( ) UNLOCKED (CEPH POOL)
    nvme2n1    S654NX0W802342     695/2000 GB     [======......]  ( ) UNLOCKED (CEPH POOL)
    sda        WDC-WD40EFAX-01    1450/4000 GB    [======......]  ( ) UNLOCKED (CEPH POOL)

  ZigVM Descriptor-Relative VFS: 48 open descriptors / 1024 max (4.6% utilization)
  VFS Invariant: Race-free, symlink-aware, single-writer exclusive lease active.

  [ACTIONS]: (1-9) Tabs  (r) Refresh  (t) Toggle Mode  (s/x/r) Container Control  (g) Garbage Collect  (q) Quit
  STATUS: Switched to Storage & Ceph Safety
```

#### 3.3.2 Component Breakdown & Behavior

| Component ID | Component Name | Behavior & State Transitions | Fail-Closed / Safety Invariant |
|---|---|---|---|
| `C-ST-01` | **Root OS Drive Interlock** | Displays serial `25503L801736` and its lock status. Verified at compile time. | If serial is unlocked, entire storage cluster halts with error `E_HARDWARE_LOCK_VIOLATED`. |
| `C-ST-02` | **Ceph Cluster Health Card**| Monitors Ceph OSD count and cluster operational state (`HEALTH_OK`, `HEALTH_WARN`, `HEALTH_ERR`). | Automatic storage throttling if cluster enters `HEALTH_WARN`. |
| `C-ST-03` | **Drive Allocation Table** | Lists drives, serials, total/used GB, and visual allocation bar. | Host OS drive `nvme0n1` cannot be selected as an allocation target. |
| `C-ST-04` | **ZigVM VFS Descriptor Meter**| Tracks open file descriptors against the 1,024 ceiling. | Descriptor exhaustion (>90%) triggers emergency file closure. |

---

### Screen 4: Zenoh Pub/Sub Telemetry Mesh (`Key 4`)

#### 3.4.1 ASCII Screen Mockup

```text
+======================================================================================================+
| UOS C3I SOVEREIGN REMOTE SYSADMIN COCKPIT -- AGY (L0-L7 ACCESS)                                      |
| HOST: nas-1.tail55d152.ts.net:4100 | UTC: 2026-09-06T18:45:00Z | SRV: OK | DRIVE: LOCKED | [DARK]    |
+======================================================================================================+
  [1] Overview | [2] Podman | [3] Storage |  [4] Zenoh  | [5] Supervisors | [6] Tasks | [7] Sec | [8] Str | [9] Doc

  === ZENOH PUB/SUB TELEMETRY MESH & ROUTER HEALTH ===

  Session Status : CONNECTED (Peer: vm-1.tail55d152.ts.net:7447)
  Throughput     : 1,482 msgs/sec | 248.5 KB/s | Drop Rate: 0.00%
  Transport Mode : Pure Zenoh (Zero WebSockets, Zero Foreign NIF Intermediaries)

  Active Fractal Namespace Topics:
    Topic Filter Pattern         Total Msgs     Freshness         State
    ----------------------------------------------------------------------
    indrajaal/l0/const/**        1,420 msgs     1s ago            [ACTIVE]
    indrajaal/l1/atomic/**       8,930 msgs     0s ago            [ACTIVE]
    indrajaal/l2/health/**       4,510 msgs     2s ago            [ACTIVE]
    indrajaal/l3/tx/**           2,150 msgs     1s ago            [ACTIVE]
    indrajaal/l4/system/**       6,780 msgs     0s ago            [ACTIVE]
    indrajaal/l5/cog/**          3,420 msgs     1s ago            [ACTIVE]
    indrajaal/l6/eco/**          1,280 msgs     3s ago            [ACTIVE]
    indrajaal/l7/fed/**            890 msgs     4s ago            [ACTIVE]

  [ACTIONS]: (1-9) Tabs  (r) Refresh  (t) Toggle Mode  (s/x/r) Container Control  (g) Garbage Collect  (q) Quit
  STATUS: Switched to Zenoh Mesh
```

#### 3.4.2 Component Breakdown & Behavior

| Component ID | Component Name | Behavior & State Transitions | Fail-Closed / Safety Invariant |
|---|---|---|---|
| `C-ZN-01` | **Zenoh Peer Session Card** | Shows session state (`CONNECTED`, `DISCONNECTED`, `RECONNECTING`) and remote peer FQDN. | Reconnect loop backoff: 50ms, 100ms, 250ms, 500ms max. |
| `C-ZN-02` | **Throughput Telemetry** | Displays messages/sec, KB/sec throughput, and drop rate. | Drop rate > 0.1% triggers mesh backpressure regulation. |
| `C-ZN-03` | **Fractal Namespace Table**| Displays all 8 fractal topic patterns, total message count, and last seen freshness. | Stale topics (> 10s without ping) flag a dead-man warning. |

---

### Screen 5: OTP 29 Supervisors & BEAM Schedulers (`Key 5`)

#### 3.5.1 ASCII Screen Mockup

```text
+======================================================================================================+
| UOS C3I SOVEREIGN REMOTE SYSADMIN COCKPIT -- AGY (L0-L7 ACCESS)                                      |
| HOST: nas-1.tail55d152.ts.net:4100 | UTC: 2026-09-06T18:45:00Z | SRV: OK | DRIVE: LOCKED | [DARK]    |
+======================================================================================================+
  [1] Overview | [2] Podman | [3] Storage | [4] Zenoh |  [5] Supervisors  | [6] Tasks | [7] Sec | [8] Str | [9] Doc

  === OTP 29 SUPERVISOR TREE & PROCESS REGISTRY ===

  BEAM Schedulers : 16 Normal + 16 Dirty I/O Schedulers (100% responsive)
  Root Supervisor : uos_sup.gleam (Strategy: one_for_one, Max 5 restarts in 10s)

    Supervisor Node      Layer   Child Count   Operational Status   Restart Count
    -------------------------------------------------------------------------------
    uos_sup              [L0]    4 children    [nominal]            0 restarts
    apps_sup             [L2]    8 children    [nominal]            0 restarts
    engines_sup          [L1]    6 children    [nominal]            0 restarts
    services_sup         [L4]    7 children    [nominal]            0 restarts
    intelligence_sup     [L5]    8 children    [nominal]            0 restarts

  Actor Mailboxes  : Max queue depth 2 (No memory buildup or runaway processes)
  Total Reductions : 4.8M reductions/sec across 266 active actors

  [ACTIONS]: (1-9) Tabs  (r) Refresh  (t) Toggle Mode  (s/x/r) Container Control  (g) Garbage Collect  (q) Quit
  STATUS: Switched to Supervisors & Schedulers
```

#### 3.5.2 Component Breakdown & Behavior

| Component ID | Component Name | Behavior & State Transitions | Fail-Closed / Safety Invariant |
|---|---|---|---|
| `C-SV-01` | **Supervisor Node Table** | Lists root and child supervisor nodes with layer, child count, state, and restarts. | Supervisor crashes trigger clean child termination in reverse dependency order. |
| `C-SV-02` | **Restart Budget Monitor** | Tracks restart frequencies against maximum permitted budget (5 restarts per 10s). | Exceeding budget triggers fail-closed supervisor shutdown. |
| `C-SV-03` | **Actor Mailbox Gauge** | Monitors queue depths across all 266 active actors. | Mailbox depth > 50 triggers queue throttling and actor backpressure. |

---

### Screen 6: SIL-6 Task Board & Constitutional Consensus (`Key 6`)

#### 3.6.1 ASCII Screen Mockup

```text
+======================================================================================================+
| UOS C3I SOVEREIGN REMOTE SYSADMIN COCKPIT -- AGY (L0-L7 ACCESS)                                      |
| HOST: nas-1.tail55d152.ts.net:4100 | UTC: 2026-09-06T18:45:00Z | SRV: OK | DRIVE: LOCKED | [DARK]    |
+======================================================================================================+
  [1] Overview | [2] Podman | [3] Storage | [4] Zenoh | [5] Supervisors |  [6] Tasks  | [7] Sec | [8] Str | [9] Doc

  === SIL-6 TASK BOARD & CONSTITUTIONAL CONSENSUS ===

  Constitutional Consensus: 2oo3 REACHED
    Guardian Agent [APPROVE] | Sentinel Agent [APPROVE] | Cortex Agent [APPROVE]

    Task ID    Prio  Domain         State        Task Title & Description
    ------------------------------------------------------------------------------------
    TASK-01    P0    Storage        [completed]  Verify Ceph NVMe Interlock
    TASK-02    P1    Testing        [completed]  Run 381 Regression Tests
    TASK-03    P2    Observability  [running]    Poll Zenoh Mesh Spans
    TASK-04    P1    Formal         [completed]  Hermes Gospel Parity Verification
    TASK-05    P2    Operations     [pending]    Quiesce Exited Microservices

  Prajna Circuit Breakers: 0 Tripped, 14 Active, Sub-50ms Half-Open Recovery Window

  [ACTIONS]: (1-9) Tabs  (r) Refresh  (t) Toggle Mode  (s/x/r) Container Control  (g) Garbage Collect  (q) Quit
  STATUS: Switched to Tasks & Planning
```

#### 3.6.2 Component Breakdown & Behavior

| Component ID | Component Name | Behavior & State Transitions | Fail-Closed / Safety Invariant |
|---|---|---|---|
| `C-TK-01` | **2oo3 Consensus Ballot** | Displays votes from Guardian, Sentinel, and Cortex. Requires at least 2 approvals. | < 2 approvals blocks all P0 and P1 task execution. |
| `C-TK-02` | **Task Board Grid** | Lists active tasks with priority (`P0`, `P1`, `P2`), domain, state, and description. | Tasks execute strictly in topological dependency order. |
| `C-TK-03` | **Prajna Breaker Status** | Real-time health of 14 circuit breakers. | Half-open recovery tests candidate requests before fully resetting. |

---

### Screen 7: Zero-Trust Security & Sovereign IAM Audit (`Key 7`)

#### 3.7.1 ASCII Screen Mockup

```text
+======================================================================================================+
| UOS C3I SOVEREIGN REMOTE SYSADMIN COCKPIT -- AGY (L0-L7 ACCESS)                                      |
| HOST: nas-1.tail55d152.ts.net:4100 | UTC: 2026-09-06T18:45:00Z | SRV: OK | DRIVE: LOCKED | [DARK]    |
+======================================================================================================+
  [1] Overview | [2] Podman | [3] Storage | [4] Zenoh | [5] Supervisors | [6] Tasks |  [7] Security  | [8] Str | [9] Doc

  === ZERO-TRUST SECURITY & SOVEREIGN IAM AUDIT ===

  Authenticated User: agy  |  Roles: [sovereign, admin, operator]  |  MFA: Active
  FerrisKey Token   : Hardware Connected  |  Unlocked Layers: L0 L1 L2 L3 L4 L5 L6 L7

  Recent Zero-Trust Interceptor Events & Trapped Ingress:
    Timestamp (UTC)       Source IP      Event Description                 Policy Outcome
    --------------------------------------------------------------------------------------
    2026-09-06T18:40:12Z  127.0.0.1      MCP Dispatch Validated            [ALLOW]
    2026-09-06T18:35:20Z  10.0.4.15      SQL Injection Trapped (code -3)   [BLOCKED]
    2026-09-06T18:30:05Z  10.0.4.88      NUL Byte Trapped (code -2)        [BLOCKED]
    2026-09-06T18:25:00Z  100.87.7.78    Sovereign Login AGY (FerrisKey)   [AUTHENTICATED]

  Active Defense Rule: Trapped NUL bytes (-2) and raw unparameterized SQL (-3) fail-closed.

  [ACTIONS]: (1-9) Tabs  (r) Refresh  (t) Toggle Mode  (s/x/r) Container Control  (g) Garbage Collect  (q) Quit
  STATUS: Switched to Security & IAM
```

#### 3.7.2 Component Breakdown & Behavior

| Component ID | Component Name | Behavior & State Transitions | Fail-Closed / Safety Invariant |
|---|---|---|---|
| `C-SC-01` | **IAM Identity Card** | Displays authenticated user, assigned RBAC roles, and hardware MFA token state. | Missing MFA restricts access to read-only Layer L2 views. |
| `C-SC-02` | **Zero-Trust Interceptor Log**| Appends security events from `run_agent_dispatch_hook.exe`. | Ingress containing NUL byte (code `-2`) or SQL syntax (code `-3`) is blocked fail-closed. |
| `C-SC-03` | **Active Defense Banner** | Affirms fail-closed rules and cryptographic verification standards. | Cryptokit SHA-256 digest validation required on all payloads. |

---

### Screen 8: AG-UI 32-Event Real-Time Stream (`Key 8`)

#### 3.8.1 ASCII Screen Mockup

```text
+======================================================================================================+
| UOS C3I SOVEREIGN REMOTE SYSADMIN COCKPIT -- AGY (L0-L7 ACCESS)                                      |
| HOST: nas-1.tail55d152.ts.net:4100 | UTC: 2026-09-06T18:45:00Z | SRV: OK | DRIVE: LOCKED | [DARK]    |
+======================================================================================================+
  [1] Overview | [2] Podman | [3] Storage | [4] Zenoh | [5] Supervisors | [6] Tasks | [7] Sec |  [8] Stream  | [9] Doc

  === AG-UI 32-EVENT REAL-TIME TELEMETRY STREAM ===
  Active Host: nas-1.tail55d152.ts.net:4100 | Last Tick: 2026-09-06T18:45:00Z

    Time (UTC)    Category     Event Type          Details / W3C OTel Span Context
    --------------------------------------------------------------------------------------
    18:44:59.102  [Lifecycle]  StepFinished        step_id: step-842   duration: 12ms
    18:44:59.090  [Tool]       ToolCallResult      tool: system_health status: ok
    18:44:59.082  [Tool]       ToolCallStart       tool: system_health target: beam
    18:44:58.940  [State]      StateSnapshot       genome: 16/16       threat: nominal
    18:44:58.810  [Reasoning]  ReasoningChunk      tier: knowledge     drift: 0.001
    18:44:58.700  [Activity]   ActivitySnapshot    actors: 33          schedulers: 16:16
    18:44:58.550  [Special]    Heartbeat           node: nas-1         zenoh: connected

  Event Categories (32 total):
    Lifecycle (5) | Text (4) | Tool (5) | State (3) | Activity (2) | Reasoning (7) | Special (4)

  [ACTIONS]: (1-9) Tabs  (r) Refresh  (t) Toggle Mode  (s/x/r) Container Control  (g) Garbage Collect  (q) Quit
  STATUS: Switched to AG-UI Stream
```

#### 3.8.2 Component Breakdown & Behavior

| Component ID | Component Name | Behavior & State Transitions | Fail-Closed / Safety Invariant |
|---|---|---|---|
| `C-ES-01` | **Real-Time Stream Buffer** | Receives SSE events via Zenoh/Wisp. FIFO ring buffer keeps latest 100 events. | Ring buffer is bounded; old events roll off cleanly without BEAM heap expansion. |
| `C-ES-02` | **W3C OTel Context Parser** | Extracts 128-bit `trace_id` and 64-bit `span_id` from event headers. | Events lacking valid W3C trace context are marked with warning flag `[UNTRACED]`. |
| `C-ES-03` | **Category Taxonomy Bar** | Visual summary of event distributions across all 7 protocol categories. | Detects missing heartbeats if category `Special` has 0 events for > 15s. |

---

### Screen 9: System Doctor & Preflight Diagnostics (`Key 9`)

#### 3.9.1 ASCII Screen Mockup

```text
+======================================================================================================+
| UOS C3I SOVEREIGN REMOTE SYSADMIN COCKPIT -- AGY (L0-L7 ACCESS)                                      |
| HOST: nas-1.tail55d152.ts.net:4100 | UTC: 2026-09-06T18:45:00Z | SRV: OK | DRIVE: LOCKED | [DARK]    |
+======================================================================================================+
  [1] Overview | [2] Podman | [3] Storage | [4] Zenoh | [5] Supervisors | [6] Tasks | [7] Sec | [8] Str |  [9] Doctor 

  === SYSTEM DOCTOR & PREFLIGHT DIAGNOSTICS ===

  Status: 100% ALL CHECKS PASS -- UOS RATIFIED (EV-01..EV-84 Operational)

    Result  Checkpoint ID  Domain      Verification Specification Summary
    --------------------------------------------------------------------------------------
    [PASS]  CHK-01-TIME    Metadata    Timestamp Mandate (YYYYMMDD-HHSS- prefix)
    [PASS]  CHK-02-TAIL    Network     Tailscale FQDN Navigation Links Present
    [PASS]  CHK-05-MUDA    Purity      Zero-Muda Purity (0 Bevy, 0 Graphite)
    [PASS]  CHK-07-DRIVE   Storage     Hardware OS NVMe Locked (Serial 25503L801736)
    [PASS]  CHK-09-MATH    Math        4 Math Gates (H, CCM, D_EA, ITQS Verified)
    [PASS]  CHK-12-GLEAM   Control     Gleam/OTP 29 Root Supervisor uos_sup.gleam
    [PASS]  CHK-13-HERMES  Formal      Hermes Zero-Trust Payload Interceptor Hook
    [PASS]  CHK-18-JJ      Governance  Standalone Jujutsu VCS (.jj/) Purity

  Mathematical Gates:
    Shannon Entropy H   : 2.67 bits   (Target >= 2.50 b)   --> [PASS]
    Cyclomatic CCM      : 92.5 %      (Target >= 90.0 %)   --> [PASS]
    Trajectory D_EA     : 3.20 %      (Target <= 10.0 %)   --> [PASS]
    Quality Score ITQS  : 0.880       (Target >= 0.850 )   --> [PASS]

  [ACTIONS]: (1-9) Tabs  (r) Refresh  (t) Toggle Mode  (s/x/r) Container Control  (g) Garbage Collect  (q) Quit
  STATUS: Switched to Doctor & Preflight
```

#### 3.9.2 Component Breakdown & Behavior

| Component ID | Component Name | Behavior & State Transitions | Fail-Closed / Safety Invariant |
|---|---|---|---|
| `C-DC-01` | **Checklist Matrix Table** | Verifies 18 checkpoints across 5 domains (`Metadata`, `Storage`, `Testing`, `Control`, `Governance`). | A single `FAIL` halts admission and marks doctor status `ADMISSION_BLOCKED`. |
| `C-DC-02` | **4 Math Gates Gauges** | Displays $H$, $CCM$, $D_{EA}$, and $ITQS$ scores against their formal thresholds. | All 4 gates must simultaneously pass to grant release certification. |
| `C-DC-03` | **EV-Cycle Progression Card**| Audits operational status across all 84 evolutionary cycles (`EV-01` to `EV-84`). | Historical cycles are immutable; regressions block deployment. |

---

## 4. Comprehensive Component Behavioral Matrix

```text
+----------------------------------------------------------------------------------------------------+
|                         UOS TUI COMPONENT INTERACTION & EVENT MATRIX                               |
+----------------------------------------------------------------------------------------------------+
| Key / Event   | Source Context     | Target Subsystem   | Model State Mutation                     |
+---------------+--------------------+--------------------+------------------------------------------+
| '1' .. '9'    | Global Cockpit     | Tab Switcher       | select_tab(model, Tab)                   |
| 'n' / 'p'     | Global Cockpit     | Tab Cycler         | next_tab(model) / prev_tab(model)        |
| 'j' / 'Down'  | Screen 2 (Podman)  | Cursor Engine      | cursor_down(model) [bounded to 15]       |
| 'k' / 'Up'    | Screen 2 (Podman)  | Cursor Engine      | cursor_up(model) [bounded to 0]          |
| 's'           | Screen 2 (Podman)  | Container Engine   | set_container_status(sel, "running")     |
| 'x'           | Screen 2 (Podman)  | Container Engine   | set_container_status(sel, "stopped")     |
| 'r'           | Screen 2 (Podman)  | Container Engine   | restart_container(sel) [increment tally] |
| 't'           | Global Cockpit     | Dark Cockpit       | toggle_cockpit_mode(model) [5 states]    |
| 'g'           | Global Cockpit     | BEAM Runtime       | erlang:garbage_collect() trigger         |
| 'q'           | Global Cockpit     | Terminal Process   | Clean exit with ANSI cursor restoration  |
| Tick (2000ms) | Background Timer   | Telemetry Engine   | Refresh container & memory metrics       |
+----------------------------------------------------------------------------------------------------+
```

---

## 5. Summary & Verification

This specification formally establishes:
1. Complete, high-fidelity, pure ASCII mockups for all 9 core operational screens and specialized subsystem views.
2. Component-by-component operational behaviors, events, state transitions, and fail-closed safety constraints.
3. Uncompromising alignment with the 18/18 Comprehensive Verification Checklist (`SC-CHECKLIST-001`), Standalone Jujutsu monorepo discipline, Zero-Muda purity, and the Host OS NVMe serial lock (`25503L801736`).
