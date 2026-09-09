# Canonical Review Reconciliation: UOS Harness Evolution Decisions (D01–D28)

- **Contract Reference**: `SC-HARNESS-MCP-001`, `SC-PROVENANCE-001`, `SC-CHECKLIST-001`
- **Reconciliation Timestamp**: `20260909-0815-`
- **Reviewer**: AGY (`abe9bd8d-f0be-4ea7-81a8-9cc6d3901e82`, `worker-agy-abe9bd8d`)
- **Addressed Root Coordinator**: `01a083d2-baa3-7783-8e45-5357cc9e96d8`
- **Review Request ID**: `agy-harness-1`
- **Canonical Sa-Plan Authority**: [`var/sa-plan/uos.sqlite3`](file:///home/an/NAS-setup/uos/var/sa-plan/uos.sqlite3) / Plan `uos/ecology-harness-agy-review/20260909-0730` / Task `AGY-HARNESS-REVIEW`
- **Prior Preserved Receipts**:
  1. [`docs/journal/20260909-0541-agy-harness-evolution-independent-review.json`](file:///home/an/NAS-setup/uos/docs/journal/20260909-0541-agy-harness-evolution-independent-review.json) (`87a3c653...`)
  2. [`docs/journal/20260909-0750-agy-harness-evolution-review-correction.json`](file:///home/an/NAS-setup/uos/docs/journal/20260909-0750-agy-harness-evolution-review-correction.json) (`4cff801f...`)
- **Admitted EV Ceiling**: `EV-93` (`SC-PROVENANCE-001`; `EV-94`..`EV-109` strictly `NOT_ADMITTED`)

---

## 1. Scope of Canonical Reconciliation

In response to direct review and guidance from Root Coordinator `01a083d2-baa3-7783-8e45-5357cc9e96d8`, this artifact reconciles the independent AGY harness evaluation against the exact, frozen row titles and scopes defined in `docs/design/20260909-0412-harness-evolution-review-packet.md` (lines 17–44).

Key corrections integrated herein:
1. **Exact Decision Mapping**: Every decision (D01–D28) is bound to its literal canonical scope title. No decision is renumbered or redefined.
2. **Census Reconciled**: **23 `ACCEPT_WITHIN_SCOPE`** and **5 `REVISE`** (D02, D04, D14, D21, D28).
3. **Durable Budget Verified**: Recognizes existing implementation of durable budget in `tools/ecology_budget.ml` + `daily_budget.gleam` (398 native checks passed; journal `20260909-0356-ecology-daily-budget-completion.md`). D20 is accepted within scope.
4. **Claude Live Dashboard Falsifier H1**: Records that the canonical 4100 cockpit AG-UI panel renders static demo fixtures (timestamp `01:42:10`) and a fixed `16/16` container indicator while actual host podman has 2 containers running. Rendered HTML is not measured runtime telemetry.
5. **17-Aspect Rigor & Explicit `UNKNOWN`s**: Partitions the 17 aspects into 4 `RUNTIME_VERIFIED`, 9 `DESIGN_AND_SOURCE_REVIEWED`, and 4 explicit `UNKNOWN`s (A08, A10, A12, A15).
6. **Isolation of Candidate Evidence**: Clarifies that the independent SQLite `e2bb` test conducted for Root `01a08017` is completely separate and does not confer harness admission for Root `01a083d2`.

---

## 2. Canonical Census of All 28 Decisions (D01–D28)

| ID | Canonical Decision & Scope (Frozen Packet Lines 17–44) | Verdict | Evidence, Observations & Falsifiers |
|---|---|---|---|
| **D01** | Canonical UOS reuses C3I/Indrajaal concepts and VM-1 as read-only evidence | `ACCEPT_WITHIN_SCOPE` | Source provenance checked; external trees read-only per policy §3; no unvetted imports. |
| **D02** | Agentic holons discover the full capability set and activate authorized subsets | **`REVISE`** | **Falsifier**: 4110 dashboard displays 26 participants, but external system bindings are uninstantiated stubs. Active authorization subsets must be explicitly declared and fenced. |
| **D03** | Gleam/OTP owns all agents, orchestration, policies, clock/check verdicts and backend choice | `ACCEPT_WITHIN_SCOPE` | `uos_sup.gleam` owns root supervision; native adapters confined behind port boundaries. |
| **D04** | MCP and admitted Zenoh share typed intents and receipts | **`REVISE`** | **Falsifier**: `development.gleam:533` reports `"zenoh": "UNAVAILABLE_NOT_VERIFIED"`. Topic trees and reply correlation deadlines unverified. |
| **D05** | All newly authored control implementation is Gleam | `ACCEPT_WITHIN_SCOPE` | Pure Gleam control plane adhered to; native adapters internal only. |
| **D06** | Native generation is proposed via a constrained typed kernel IR | `ACCEPT_WITHIN_SCOPE` | Scoped strictly to verified AST facades; no unverified general translation. |
| **D07** | Native ABI/runtime ownership gates preserve semantics | `ACCEPT_WITHIN_SCOPE` | MAX Mojo daemon isolated to supervised stdio pipe; pure Erlang Graphene facade. |
| **D08** | Sa-plan is sole task/job/workflow authority | `ACCEPT_WITHIN_SCOPE` | Enforced via `tools/sa_plan_main.exe` and `var/sa-plan/uos.sqlite3`. |
| **D09** | Fractal TPS/Jidoka limits scope and stops uncertain effects | `ACCEPT_WITHIN_SCOPE` | Fail-closed Andon stop line (error `-32002`) halts unledgered side-effects. |
| **D10** | Coordinator leases are cooperative; task/runtime/integration ownership differ | `ACCEPT_WITHIN_SCOPE` | Board leases and ACKs grant no deployment or system admission authority. |
| **D11** | Stable logical effect identity survives retries and task attempts | `ACCEPT_WITHIN_SCOPE` | Append-only triggers and unique idempotency keys verified in SQLite. |
| **D12** | Development edits use bounded files and cooperative compare/replace | `ACCEPT_WITHIN_SCOPE` | Atomic file writes, byte caps, and fsync sync verified. |
| **D13** | Existing legacy MCP UTF-8 reader and Sa-plan adapter are repaired | `ACCEPT_WITHIN_SCOPE` | Argv-only process creation and process status checks repaired. |
| **D14** | New finite stdio MCP development interface | **`REVISE`** | **Falsifier**: `harness_finish` argument schema mismatch between `mcp.gleam:159` and `development.gleam:580` (`DEF-03`). Finite bootstrap grant confirmed as intentional security mechanism bounding caller identity (`DEF-02`). |
| **D15** | Clock policy separates UTC, signed monotonic duration, boot coordinates, reference age and delivery age | `ACCEPT_WITHIN_SCOPE` | Separate non-aliasing clock types enforced; Chrony Stratum 3 host clock verified. |
| **D16** | Development, production primary and production standby are distinct roles | `ACCEPT_WITHIN_SCOPE` | Node role separation strictly declared; no silent promotion of dev to standby. |
| **D17** | Complete declared state requires explicit durability/replication | `ACCEPT_WITHIN_SCOPE` | SQLite durable stores and append-only event ledgers verified. |
| **D18** | Hot loading is conditional on candidate-bound migration/recovery | `ACCEPT_WITHIN_SCOPE` | Hot upgrades conditional on candidate-bound migration and recovery tests. |
| **D19** | OpenRouter coding profiles use paid GLM/Kimi/DeepSeek, decisions prefer Gemma 4 | `ACCEPT_WITHIN_SCOPE` | Price and capability eligibility tiers verified in `ecology_budget.ml`. |
| **D20** | OpenRouter aggregate budget is USD 10 per UTC day | `ACCEPT_WITHIN_SCOPE` | Durable reservation component implemented in `tools/ecology_budget.ml` + `daily_budget.gleam` (398 native checks passed in journal 0356); zero paid calls made. |
| **D21** | Adaptive routing optimizes for agent need and measured evidence | **`REVISE`** | **Falsifier**: Live production calibration and measured quality feedback loops are unverified; local heuristics lack empirical verification. |
| **D22** | Environment-specific evaluation includes Gleam, OCaml, Mojo, Lean, Quint, STM, Bayesian, Rete, STPA/FMEA | `ACCEPT_WITHIN_SCOPE` | Evaluation scope accepted; noted that Rete-UL forward-chaining and Bayesian models are synthetic cases rather than verified native algorithms. |
| **D23** | Formal authority is invocation/candidate-specific | `ACCEPT_WITHIN_SCOPE` | Invocation-bound formal checks fail closed; no undeclared axioms admitted. |
| **D24** | Existing ecology baseline remains separate from new harness admission | `ACCEPT_WITHIN_SCOPE` | Baseline local MAX/free OpenRouter loop does not imply external UCon bindings or new harness admission. |
| **D25** | Hooks are advisory until independently observed as enforcing | `ACCEPT_WITHIN_SCOPE` | Client-side hooks acknowledged as advisory; server/runtime enforcement required. |
| **D26** | Journal/wiki/ZK/KM and algebraic atlas preserve claims and uncertainty | `ACCEPT_WITHIN_SCOPE` | Standardized 13-section journals, timestamps, and matching diagrams upheld. |
| **D27** | Primary/backup SRE requires independent observations and tested recovery | `ACCEPT_WITHIN_SCOPE` | Runtime observation required; static component counts cannot substitute for recovery tests. |
| **D28** | Bootstrap completion requires observed finite service acceptance and peer reconciliation | **`REVISE`** | **Falsifier**: Root MCP tests currently observed 46 PASS at 05:52:52 with final tracking pending; bootstrap completion requires peer reconciliation and clean candidate test receipts. |

---

## 3. Strict 17-Aspect Categorization with Explicit `UNKNOWN`s

```
+-----+-----------------------------------+-----------------------------+-------------------------------------------------------------+
| Id  | Canonical Aspect                  | Verification State          | Nature of Candidate Evidence                                |
+-----+-----------------------------------+-----------------------------+-------------------------------------------------------------+
| A01 | Denotational Specification        | DESIGN_AND_SOURCE_REVIEWED  | Gospel contracts & Traceability.lean reviewed in source     |
| A02 | Algebraic Atlas & Laws            | DESIGN_AND_SOURCE_REVIEWED  | Harmonic sheaf laws in Century_Harmony.lean reviewed        |
| A03 | Deterministic Runtime Kernel      | DESIGN_AND_SOURCE_REVIEWED  | ZigVM VFS & arena allocator contracts reviewed in source    |
| A04 | Bounded Kernels & FFI Safety      | DESIGN_AND_SOURCE_REVIEWED  | graphene_nif.erl facade & NVMe lock spec reviewed           |
| A05 | Supervision & Authority Lifecycle | DESIGN_AND_SOURCE_REVIEWED  | uos_sup.gleam reviewed; process tree live on 4100; live     |
|     |                                   |                             | restart dynamics unexercised                                |
| A06 | Fractal Jidoka & TPS Stop Lines   | RUNTIME_VERIFIED            | sa_plan_main.exe pull queue, leases, and receipts verified  |
| A07 | Clock Synchronization Invariants  | RUNTIME_VERIFIED            | Chrony Stratum 3 tracking verified (offset -0.000181s)      |
| A08 | Replay Determinism & Parity       | UNKNOWN                     | Differential parity oracle unrun at candidate revision      |
| A09 | OpenRouter Daily Budget Guard     | DESIGN_AND_SOURCE_REVIEWED  | tools/ecology_budget.ml & daily_budget.gleam reviewed;      |
|     |                                   |                             | 398 checks pass in journal 0356; zero paid calls made       |
| A10 | Multi-Environment Evaluation      | UNKNOWN                     | Multi-environment evaluation suite unrun by reviewer;       |
|     |                                   |                             | blocked by DEF-01 in preflight                              |
| A11 | Dev / Prod / Standby Isolation    | DESIGN_AND_SOURCE_REVIEWED  | Bootstrap isolation boundary reviewed in source             |
| A12 | Standby Lifecycle & Hot Upgrade   | UNKNOWN                     | BEAM release upgrade design reviewed; live hot reload unrun |
| A13 | SDLC / SRE Release Assurance      | RUNTIME_VERIFIED            | Preflight executed 31/31 PASS; tools/lib/uos-toolchain.sh   |
| A14 | Multi-Surface Triple Interface    | DESIGN_AND_SOURCE_REVIEWED  | Rendered HTML inspected at 4100/4110; Falsifier H1 shows    |
|     |                                   |                             | 4100 uses static demo events                                |
| A15 | AG-UI 32-Event Protocol           | UNKNOWN                     | Schema reviewed in source; Falsifier H1 shows AG-UI panel   |
|     |                                   |                             | on 4100 renders static demo events                          |
| A16 | A2UI Declarative Component Catalog| DESIGN_AND_SOURCE_REVIEWED  | 233 component schemas & security allowlist reviewed         |
| A17 | Sovereign Provenance & Admission  | RUNTIME_VERIFIED            | SC-PROVENANCE-001 ceiling EV-93 enforced; EV94..109         |
|     |                                   |                             | confirmed NOT_ADMITTED                                      |
+-----+-----------------------------------+-----------------------------+-------------------------------------------------------------+
```

---

## 4. Live Dashboard Falsifiers

### Falsifier H1: Static Demo Fixtures on Canonical Cockpit (`http://nas-1.tail55d152.ts.net:4100/`)
- **Observed Surface**: C3I Dashboard AG-UI "Live" event panel displays events timestamped `01:42:10` and container grid displays `16/16 containers healthy`.
- **Ground Truth**: Actual host podman runtime reports 2 containers running. The AG-UI panel displays static `demo_events` fixtures rather than live OTP process telemetry.
- **Verdict**: Rendered web UI content on port 4100 cannot be cited as evidence of measured container health or BEAM OTP process identity.

### Falsifier H2: Local-Only Scope on Ecology Cockpit (`http://nas-1.tail55d152.ts.net:4110/ecology`)
- **Observed Surface**: Displays 26 participants and 11 capabilities, but explicitly discloses: *"Participant models share one ecology actor; external system bindings are absent. Local cognition and diagnostics; backend availability and system admission require separate evidence."*
- **Ground Truth**: Truthfully discloses its own diagnostic boundary. It marks 7 verification domains as `UNRUN in this view`, CHK-17 as `NOT_ADMITTED`, and CHK-PROV as `EV-93 ceiling`.

---

## 5. Summary & Handover Bounds

- **Harness Candidate Status**: **`UNDER_REVISION / NOT_ADMITTED`** (Root current MCP tests observed 46 PASS at 05:52:52 with final tracking integration pending).
- **SQLite Candidate `e2bb`**: Remains an independent evaluation for EV-admission Root `01a08017`, and confers no harness admission for Root `01a083d2`.
- **Sa-Plan Authority**: All task tracking conducted exclusively through `var/sa-plan/uos.sqlite3`. Zero producer source edits, zero database schema migrations, and zero system admissions executed by AGY.
