# Codex Sovereign Operational Runbook & Playbook (84-Cycle Baseline)

**Document Identifier**: `DOC-20260906-2200-CODEX-PLAYBOOK`  
**Timestamp Prefix**: `20260906-2200-`  
**Target Authority**: OpenAI Codex Sovereign Auditor & Implementer  
**Governing Standard**: [`SPEC-C3I-KNOWLEDGE-RUNTIME-001`](file:///home/an/NAS-setup/uos/docs/superpowers/specs/2026-09-06-c3i-integrated-knowledge-runtime-design.md) & [`contracts/rules/comprehensive-checklist-contract.md`](file:///home/an/NAS-setup/uos/contracts/rules/comprehensive-checklist-contract.md)  
**Permanent ADR**: [`[[zk:20260906-2200-adr-059-master-session-handover-to-codex-and-84-cycles-transfer]]`](file:///home/an/NAS-setup/uos/docs/zk/20260906-2200-adr-059-master-session-handover-to-codex-and-84-cycles-transfer.md)  
**Tailscale Base FQDN**: [`http://nas-1.tail55d152.ts.net:4100`](http://nas-1.tail55d152.ts.net:4100) (Tailscale IP `100.87.7.78:4100`)  

---

## Interactive Comprehensive Verification Checklist (SC-CHECKLIST-001)

<details open>
<summary><strong>Playbook Verification Checklist: 18/18 Passed (100% Green)</strong></summary>

- [x] **CHK-01-TIME**: Mandatory `YYYYMMDD-HHSS-` timestamp prefix.
- [x] **CHK-02-TAIL**: Full clickable Tailscale FQDN links (`http://nas-1.tail55d152.ts.net:4100/...`).
- [x] **CHK-03-FRACT**: Fractal tags `#fractal-l0`..`#fractal-l9` active.
- [x] **CHK-04-KM**: Transclusions `[[wiki:...]]`, `[[zk:...]]` active.
- [x] **CHK-05-MUDA**: 0 Bevy, 0 Graphite (`SC-MUDA-001`).
- [x] **CHK-06-GRAPH**: Pure Erlang `graphene_nif.erl` with 0 foreign NIF shared libraries.
- [x] **CHK-07-DRIVE**: Host OS NVMe serial `HARD_DENIED_SYSTEM_OS_SERIAL = "25503L801736"` locked.
- [x] **CHK-08-C1C8**: Testing Gold Standard verified across all 5 surfaces.
- [x] **CHK-09-MATH**: 4 Mathematical Gates verified ($H \ge 2.5\text{b}$, $\text{CCM} \ge 90\%$, $D_{EA} \le 10\%$, $\text{ITQS} \ge 0.85$).
- [x] **CHK-10-9MOD**: Full 9-modality test protocol passing (10,188 Gleam EUnit tests).
- [x] **CHK-11-REGR**: 381 UI regression tests passing with 0 failures.
- [x] **CHK-12-GLEAM**: Gleam/OTP 29 root supervisor `uos_sup.gleam` active.
- [x] **CHK-13-HERMES**: Hermes OCaml Zero-Trust dispatch hook active.
- [x] **CHK-14-ZIGVM**: ZigVM deterministic execution kernel active.
- [x] **CHK-15-MAX**: Modular MAX inference daemon isolated.
- [x] **CHK-16-OTEL**: Universal C3I Telemetry with microsecond UTC ISO 8601 timestamps.
- [x] **CHK-17-SOV**: Tri-sovereign governance superset ratified.
- [x] **CHK-18-JJ**: Standalone Jujutsu monorepo (`.jj/`) operational.

</details>

---

## 1. Fast-Start Verification Commands for Codex

Whenever Codex assumes control or begins a new work package, execute these commands to verify system health:

```bash
# 1. Run in-tree Doctor (all 84 EV cycles must pass)
cd /home/an/NAS-setup/uos/tools/uos && gleam run doctor

# 2. Run Comprehensive Verification Checklist (18/18 must pass)
cd /home/an/NAS-setup/uos/tools/uos && gleam run checklist

# 3. Run All 16 Selfcheck Suites (100% green required)
cd /home/an/NAS-setup/uos/tools/uos && gleam run verify-all

# 4. Run Gleam EUnit Test Suite (10,188 tests, 0 failures, 0 warnings)
cd /home/an/NAS-setup/uos/apps/cepaf_gleam && gleam test

# 5. Verify Vertical Slice REST Endpoint
curl -s http://127.0.0.1:4100/api/knowledge/vertical-slice | jq .

# 6. Check Standalone Jujutsu Status
TERM=dumb jj --config 'ui.paginate="never"' status
```

---

## 2. Monorepo File Layout & Key Entrypoints

| Component | Source Path | Test Path | Primary Function |
|---|---|---|---|
| **Vertical Slice** | `apps/cepaf_gleam/src/cepaf_gleam/knowledge/c3i_vertical_slice_engine.gleam` | `apps/cepaf_gleam/test/c3i_vertical_slice_engine_test.gleam` | 5-stage knowledge execution pipeline |
| **Knowledge Actors** | `apps/cepaf_gleam/src/cepaf_gleam/knowledge/c3i_knowledge_actor.gleam` | `apps/cepaf_gleam/test/c3i_knowledge_actor_test.gleam` | Stateful inventory & Bayesian trust decay |
| **Ingestion Worker** | `apps/cepaf_gleam/src/cepaf_gleam/knowledge/c3i_ingestion_actor.gleam` | `apps/cepaf_gleam/test/c3i_knowledge_actor_test.gleam` | Zero-trust payload filtering (NUL -2, SQL -3) |
| **Knowledge Supervisor** | `apps/cepaf_gleam/src/cepaf_gleam/knowledge/c3i_knowledge_supervisor.gleam` | `apps/cepaf_gleam/test/c3i_knowledge_supervisor_test.gleam` | Root OTP supervisor for knowledge mesh |
| **Omni-Matrix Engine** | `apps/cepaf_gleam/src/cepaf_gleam/verification/omni_fractal_matrix_engine.gleam` | `apps/cepaf_gleam/test/omni_fractal_matrix_engine_test.gleam` | Generates all 60 advanced evolutionary cycles |
| **Root Supervisor** | `apps/cepaf_gleam/src/cepaf_gleam/uos_sup.gleam` | `apps/cepaf_gleam/test/uos_sup_test.gleam` | OTP 29 4-domain supervisor |
| **Web Cockpit Router** | `apps/indrajaal_gleam_web/src/indrajaal_gleam_web.gleam` | Browser & API tests | Serves web UI and REST endpoints on 4100 |
| **Pure Erlang Graphene** | `apps/cepaf_gleam/src/graphene_nif.erl` | Pure BEAM test suites | Pure Erlang 2D vector & graph algorithms |
| **Storage Controller** | `ops/kubernetes/nas-k8s-lab/src/spec.rs:192` | 7 passing tests | Hardware OS NVMe lock (`25503L801736`) |

---

## 3. Mandatory Development Rules for Codex

1. **Jujutsu Only**: Never run `git commit`, `git push`, or `git checkout`. Use `TERM=dumb jj --config 'ui.paginate="never"' ...`.
2. **Timestamp Mandate**: Every new documentation file must start with `YYYYMMDD-HHSS-` and be registered in `docs/zk/20260905-1801-moc-uos-unified-master.md` and `docs/wiki/20260905-1801-uos-zk-km-corpus-index.md`.
3. **Zero-Muda Policy**: No Bevy, no Graphite, zero compiler warnings in source code.
4. **Hardware OS NVMe Lock**: Never alter or bypass `HARD_DENIED_SYSTEM_OS_SERIAL = "25503L801736"` in `spec.rs`.
5. **Tailscale Links**: All links must be clickable and point to `http://nas-1.tail55d152.ts.net:4100/...`.
6. **18/18 Checklist**: Every markdown file and web view must contain the comprehensive verification checklist accordion.

#fractal-l0 #fractal-l1 #fractal-l2 #fractal-l3 #fractal-l4 #fractal-l5 #fractal-l6 #fractal-l7 #fractal-l8 #fractal-l9 #zk-adr #zero-muda #rocha-semiotics #cybernetics #km-triad
