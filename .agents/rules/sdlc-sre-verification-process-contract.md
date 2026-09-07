# SDLC, SRE & Verification Process Contract (SC-SDLC-SRE-001)

- **Authority**: `UOS-CANONICAL-AGENT-POLICY`
- **Domain**: Software Development Life Cycle (SDLC), Site Reliability Engineering (SRE), and Multi-Paradigm Verification
- **Status**: ACTIVE & ENFORCED across all Agents, Engineers, and Toolchains
- **Lineage**: Transmuted from VM-1 `SDLC_SRE_PROCESS.md`, `ALGEBRAIC_FRACTAL_RULES.md`, `SAFETY_ANALYSIS.md`, and `docs/TESTING_DISCIPLINES.md`
- **Tailscale Web Link**: [http://nas-1.tail55d152.ts.net:4100/checklist](http://nas-1.tail55d152.ts.net:4100/checklist)
- **Tags**: `#sdlc`, `#sre`, `#verification`, `#fractal-l0`, `#fractal-l4`, `#zero-muda`, `#rocha-semiotics`, `#cybernetics`

---

## 1. The 5-Tier Fractal Lifecycle

Every software evolution and operational cycle within UOS must execute within one of the 5 fractal OODA loops:

| Loop Tier | SDLC Stage Mapping | Entry Artifact | Exit Criterion | Mandatory Gate |
|---|---|---|---|---|
| **Operation** | Code (TDD micro-cycle) | Failing law test | Law test green, zero leaks, 0 warnings | Compiler & EUnit |
| **Task** | Plan $\to$ Build $\to$ Review $\to$ Integrate | `sa-plan` task lease (`var/sa-plan/uos.sqlite3`) | Two review verdicts clean; gate green; `sa-plan complete` | Code Review & Gate |
| **Slice** | Feature lifecycle | `sa-plan` DAG + Safety packets | Named laws + $\ge 2$ killed mutants + docs synced + SQLite evidence | `MUTATION_LOG.md` |
| **Epoch** | Release cycle | Epoch charter (+ `sa-plan` milestone) | Exit gate + ratchets + baseline accepted + 13-section journal | `doctor` EV-cycles |
| **Pin** | Platform upgrade cycle | Re-pin ledger entry | Differential oracle green + full re-baseline | Parity suites |

### 1.1 Sa-Plan Exclusivity & Fractal Jidoka Mandate (SC-JIDOKA-001, SC-SA-PLAN-001)

`sa-plan` (`tools/sa-plan`, `var/sa-plan/uos.sqlite3`) is the sole canonical execution authority for all tasks, Oban jobs, and Temporal workflows across all SDLC and SRE phases.
Any task execution, claiming, or mutation attempted outside `sa-plan` triggers an immediate fail-closed **Andon Stop Line** (`SC-JIDOKA-001`), halting execution immediately with error code `-32002`. No shadow backlogs or phantom task states are permitted.


---

## 2. The 7-Step Mandatory Algebraic Loop

Every architectural slice and behavioral mutation must preserve the invariant sequence at every fractal layer ($L_0 \dots L_9$):

```text
semantic domain -> operations -> observations -> oracle -> final encoding
-> homomorphism/laws -> mutants -> docs -> harness evidence
```

1. **Semantic Domain**: State algebraic properties, representations, and domain types before authoring code.
2. **Operations & Observations**: Define pure functions and observational equality (never pointer/address identity).
3. **Oracle Specification**: Identify the reference oracle (pinned OTP, formal spec, or mathematical ground truth).
4. **Final Encoding**: Implement pure BEAM Gleam/OTP or deterministic ZigVM structures with zero muda.
5. **Homomorphism Laws**: Prove representation-switching and composition laws:
   $$\text{decode}(\text{op}(x)) = \text{op}'(\text{decode}(x))$$
6. **Mutant Injections**: Plant $\ge 2$ deliberate mutants per slice. Verify that test suites turn RED and kill the mutants. Record in `MUTATION_LOG.md`.
7. **Evidence & Documentation**: Synchronize ZK ADRs, wiki pages, living catalogs in SQLite, and commit via standalone Jujutsu.

---

## 3. STPA Safety & Reliability Envelope

Systems-Theoretic Process Analysis (STPA) governs system reliability:

### 3.1 Losses to Prevent (L-1 .. L-6)
- **L-1 (False Conformance)**: The system asserts conformance or parity that is mathematically unproven or unverified.
- **L-2 (Silent Regression)**: Test coverage, reliability, or equivalence decreases without immediate gate tripping.
- **L-3 (Evidence Contamination)**: SQLite WAL ledgers, baselines, or pins become corrupted, stale, or out-of-band mutated.
- **L-4 (Large-Scale Wasted Effort)**: Development proceeds on unreviewed, defective, or divergent foundational axioms.
- **L-5 (Boundary & Purity Loss)**: Language boundaries violated, foreign NIFs admitted, or zero-muda barred components introduced.
- **L-6 (Loss of Deterministic Execution Authority)**: Task state fragmentation, shadow registries, or un-ledgered agent workflows causing conflicting system mutations.

### 3.2 System-Level Hazards (H-1 .. H-6)
- **H-1**: The gate or verification protocol reports GREEN while an active defect exists.
- **H-2**: Ratchet, baseline, or quality thresholds are weakened, bypassed, or silenced.
- **H-3**: Telemetry or evidence store diverges from physical runtime reality.
- **H-4**: Hardware storage interlock on OS NVMe `25503L801736` is unverified or bypassed.
- **H-5**: Uncontrolled memory growth, runaway reductions, or actor mailbox deadlocks.
- **H-6**: An agent or automated subsystem executes changes without an admitted, leased task in `sa-plan` (`var/sa-plan/uos.sqlite3`).

### 3.3 Safety Constraints (SC-JIDOKA-001, SC-SA-PLAN-001)
- **SC-JIDOKA-001**: Immediate fail-closed Andon stop line (error code `-32002`) upon detection of any unledgered task execution, shadow queue, or bypass attempt.
- **SC-SA-PLAN-001**: Exclusive execution authority through `sa-plan` (`tools/sa-plan`, `var/sa-plan/uos.sqlite3`) across all fractal layers $L_0 \dots L_9$.

---

## 4. Multi-Paradigm Testing Disciplines

Every code component must satisfy the unified testing protocol:
1. **TDD (Law-Driven)**: Micro-cycles driven by failing algebraic property and homomorphism tests.
2. **BDD (Scenario-Driven)**: State machine transition sequences, LCA bubbling, and agent collaboration paths.
3. **Property-Based Testing**: Generative input fuzzing with seeded random generators and failure seed reporting.
4. **Chaos Testing**: Simulating network splits, actor crashes, delayed messages, and disk write errors.
5. **Mutation Adequacy**: All production laws must maintain a $>90\%$ mutant kill ratio.

---

## 5. Forecasting & Preflight Governance

1. **Pre-Brief Consumption**: Before initiating any task or slice loop, the agent or operator consumes the Bayesian duration and cost estimate.
2. **Cycle Receipt**: At loop completion, terminal resource consumption, reduction count, and duration are committed to the learning ledger.
3. **Fail-Closed Gate**: If predictive preflight indicates budget or quota exhaustion, execution halts fail-closed until authorized by operator consensus.

---

## 6. Fractal Toyota Production System (TPS) SDLC & SRE Integration

The 5 pillars of TPS govern all software engineering and operational loops across UOS:
1. **Poka-Yoke (Mistake-Proofing)**: Automatic parameter verification on every task, Oban job, and Temporal workflow prior to scheduling.
2. **Jidoka (Autonomation with a Human Touch)**: Autonomic stop line immediately terminating runaway, unledgered, or defective execution paths.
3. **Muda Elimination (Waste Reduction)**: Zero duplicate planning registries, shadow task queues, or dead code across the repository (`SC-MUDA-001`).
4. **Standardized Work**: Typed CLI and API schemas for Plan, Task, Oban Job, and Temporal Workflow guaranteeing deterministic reproducibility.
5. **Heijunka (Production Leveling)**: Leveled pull queues with monotonic leases (`claim WORKER PLAN LEASE_NS TASK_ID`), preventing task starvation, thundering herds, and resource contention.

