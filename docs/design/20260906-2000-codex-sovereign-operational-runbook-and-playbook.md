# Codex Sovereign Operational Runbook & Playbook
#fractal-l0 #fractal-l1 #fractal-l2 #fractal-l3 #fractal-l4 #fractal-l5 #fractal-l6 #fractal-l7 #fractal-l8 #fractal-l9
#rocha-semiotics #cybernetics #zero-muda #km-triad #codex-playbook #operational-runbook #ev-69-closure

## 20260906-2000-RUNBOOK: OpenAI Codex Sovereign Operational Runbook & Command Playbook

- **Document Identifier**: `RUNBOOK-20260906-2000-CODEX`
- **Timestamp Prefix**: `20260906-2000-`
- **Execution Date**: 2026-09-06
- **Status**: **ACTIVE OPERATIONAL SPECIFICATION**
- **Target Audience**: OpenAI Codex Sovereign Auditor & Implementer
- **Primary Tailscale FQDN Link**: [http://nas-1.tail55d152.ts.net:4100/docs/design/20260906-2000-codex-sovereign-operational-runbook-and-playbook.md](http://nas-1.tail55d152.ts.net:4100/docs/design/20260906-2000-codex-sovereign-operational-runbook-and-playbook.md)
- **Associated Handover Tome**: `[[design:20260906-2000-uos-tri-sovereign-master-session-handover-to-codex]]`
- **Permanent Decision Record**: `[[zk:20260906-2000-adr-057-master-session-handover-to-codex-and-69-cycles-transfer]]`

---

## 1. Quick-Start Orientation for Codex

Welcome, Codex. This runbook serves as your practical, step-by-step operating manual for navigating, diagnosing, testing, and expanding the **Unified Operational System (UOS)** at `/home/an/NAS-setup/uos`.

### 1.1 Golden Rule: Pager Suppression in CI & Non-Interactive Shells
Whenever invoking Jujutsu commands (`jj`), you **MUST** disable the interactive pager to prevent terminal hangs:
```bash
# Canonical JJ Command Invocation
TERM=dumb jj --config 'ui.paginate="never"' <command>
```

### 1.2 Non-Negotiable Invariants Checklist
Before touching code or committing any changes:
- [ ] Document Timestamp: Did you prefix newly authored documents with `YYYYMMDD-HHSS-`?
- [ ] Zero-Muda: Is the change free of Bevy, Graphite, and foreign NIF shared libraries?
- [ ] Storage Safety: Is OS NVMe root disk `25503L801736` protected?
- [ ] Tailscale FQDN: Are all web links formatted as `http://nas-1.tail55d152.ts.net:4100/...`?
- [ ] EUnit Tests: Did `gleam test` pass with 0 failures and 0 warnings in active source?
- [ ] In-Code Tooling: Did `tools/uos verify-all` pass with all 14 selfchecks green?

---

## 2. In-Code Diagnostic Tooling Runbook (`tools/uos`)

The primary command-line interface for system health verification is `tools/uos`:

```bash
cd /home/an/NAS-setup/uos/tools/uos

# 1. Run Complete System Verification (All 14 Selfchecks in Sequence)
gleam run verify-all

# 2. Run EV-Cycle Boundary Audit (EV-01 through EV-69)
gleam run doctor

# 3. Run Comprehensive Verification Checklist (5 Domains, 18 Checkpoints)
gleam run checklist

# 4. Run Wave 3 Evolutionary Cycles Check (EV-55 through EV-69)
gleam run selfcheck-wave3-cycles

# 5. Run C3I Knowledge Runtime Subsystem Check (10/10 Checks)
gleam run c3i-knowledge

# 6. Run Omni-Matrix Cartesian Tensor Check (13/13 Checks)
gleam run selfcheck-omni-matrix

# 7. Run 8 Canonical VFS Laws Check
gleam run selfcheck-vfs

# 8. Run Sa-Plan OCaml 12 Test Suites (235 Laws)
gleam run selfcheck-sa-plan

# 9. Run Hermes-Bionic Integration Check
gleam run selfcheck-hermes-bionic
```

---

## 3. Test Suites Execution Playbook

### 3.1 Gleam EUnit Test Suite (Primary Control Plane)
```bash
cd /home/an/NAS-setup/uos/apps/cepaf_gleam

# Run all tests (10,182 tests)
gleam test

# Run a specific targeted test module
gleam test -- --match c3i_knowledge_actor_test
gleam test -- --match c3i_knowledge_supervisor_test
gleam test -- --match omni_fractal_matrix_engine_test
gleam test -- --match master_comprehensive_system_verification_test

# Check code formatting
gleam format --check
```

### 3.2 Rust Kubernetes Safety Interlock Tests
```bash
cd /home/an/NAS-setup/uos/ops/kubernetes/nas-k8s-lab

# Run 7 storage safety unit tests
cargo test
```

### 3.3 Sa-Plan OCaml Formal Evidence Test Suites
```bash
cd /home/an/NAS-setup/uos/engines/hermes

# Run Sa-Plan OCaml suites via dune
dune runtest
```

---

## 4. Standalone Jujutsu VCS Workflow

All version control operations must strictly adhere to standalone Jujutsu (`.jj/`):

```bash
cd /home/an/NAS-setup/uos

# 1. Check Working Copy Status
TERM=dumb jj --config 'ui.paginate="never"' status

# 2. View Recent Commit Log
TERM=dumb jj --config 'ui.paginate="never"' log -n 5

# 3. Describe Current Working Copy Commit
TERM=dumb jj --config 'ui.paginate="never"' describe -m "feat(subsystem): brief summary (JRN-YYYYMMDD-HHSS-DESCRIPTOR)"

# 4. Advance Main Bookmark to Current Commit
TERM=dumb jj --config 'ui.paginate="never"' bookmark set main -r @

# 5. Create Tagged Bookmark for Ratified Milestone
TERM=dumb jj --config 'ui.paginate="never"' bookmark create tag/YYYYMMDD-HHSS-descriptor-ratified -r main

# 6. Open Fresh Working Copy for Next Task
TERM=dumb jj --config 'ui.paginate="never"' new
```

---

## 5. Web Cockpit & Telemetry Services

The web cockpit runs on port 4100 using Mist and Wisp:

- **Server Location**: `apps/indrajaal_gleam_web/src/indrajaal_gleam_web.gleam`
- **Port**: `4100` (bound to `0.0.0.0:4100`)
- **Main Cockpit**: `http://nas-1.tail55d152.ts.net:4100/`
- **Knowledge Verification API**: `http://nas-1.tail55d152.ts.net:4100/api/verify/c3i-knowledge`
- **Omni-Matrix Tensor API**: `http://nas-1.tail55d152.ts.net:4100/api/verify/omni-matrix`
- **Knowledge Cited Recall API**: `http://nas-1.tail55d152.ts.net:4100/api/knowledge/cited-recall`
- **Knowledge Query API**: `http://nas-1.tail55d152.ts.net:4100/api/knowledge/query`

If the web service needs to be restarted:
```bash
cd /home/an/NAS-setup/uos/apps/indrajaal_gleam_web
gleam run
```

---

## 6. How to Extend Evolutionary Cycles (Wave 4 Blueprint)

When creating Wave 4 evolutionary cycles (`EV-70` through `EV-84`):

1. **Open Engine**: `apps/cepaf_gleam/src/cepaf_gleam/verification/omni_fractal_matrix_engine.gleam`
2. **Implement Generator**: Define `pub fn generate_wave4_evolutionary_cycles() -> List(EvolutionaryCycleSpec)`
3. **Add Invariants**: For each cycle, specify id (`EV-70`..`EV-84`), name, surface, layer, invariant name (`INV-...`), status (`"OPERATIONAL"`), and `verified: True`.
4. **Update Unified List**: Append to `generate_all_evolutionary_cycles()` and update count in `OmniSystemMatrix`.
5. **Update In-Code Tooling**:
   - In `tools/uos/src/main.gleam`: Add `SelfcheckWave4Cycles`, update `Doctor` to check all 84 boundaries, and update `verify-all` count.
6. **Update Test Suite**:
   - In `apps/cepaf_gleam/test/omni_fractal_matrix_engine_test.gleam`: Add unit tests for wave 4 cycles and update cycle count assertion.
7. **Run Diagnostics**: Verify `tools/uos verify-all` and `gleam test` pass 100% green.
8. **Ratify with Journal & ADR**: Author completion journal, ZK ADR, and update indices.

---

## 7. Emergency Procedures & Safety Tripwires

### 7.1 Prajna Circuit Breaker Tripping
- If worker requests exceed timeout thresholds, the Prajna circuit breaker trips to `Open`.
- **Action**: Check background worker processes (`ps aux | grep max_worker` or `grep sa_plan`).
- Reset the breaker via the API: `POST http://nas-1.tail55d152.ts.net:4100/api/prajna/reset`.

### 7.2 Storage Safety Alert
- If an allocation command references `/dev/nvme0n1` or serial `25503L801736`, execution is blocked fail-closed with error `HARD_DENIED`.
- **Action**: Verify the candidate drive serial. Primary OS drives must never be touched. Only secondary storage disks (`/dev/nvme1n1`, `/dev/sda`) may be allocated.
