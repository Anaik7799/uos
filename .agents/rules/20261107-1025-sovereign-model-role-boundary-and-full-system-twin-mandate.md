# 20261107-1025 — Sovereign Model Role Boundary & 100% Full-System-Code Digital Twin Mandate (`SC-MODEL-ROLE-TWIN-001`)

#fractal-l0 #fractal-l1 #fractal-l2 #fractal-l3 #fractal-l4 #fractal-l5 #fractal-l6 #fractal-l7 #fractal-l8 #fractal-l9 #km-triad #zero-muda #zk-adr

## 1. Sovereign Model Role Boundary (Minimized Supervisor / Maximized Execution)

1. **OpenRouter + Gemini + Argon (`Caste02` Pi Main Session — Supervisor & Analyst ONLY)**:
   - Strictly minimized to high-level supervision, Sa-Plan task orchestration (`var/sa-plan/uos.sqlite3`), cross-plane synthesis, and operator reporting.
   - Bulk code generation, deep codebase audits, SDLC/SRE execution, and artifact authoring are delegated to **Claude**, **Codex**, and **Local Qwen2.5-Coder-7B**.
2. **Claude Opus 4.6 (`Caste04` Scholar / Architect — `claude -p`)**:
   - Maximized for 5-Round Fractal Devil's Advocate & ACH reviews, architectural synthesis, oracle cache optimization, contract/rule authoring, and 13-section `SC-JOURNAL-v3` / Fractal Prompt generation.
3. **Codex GPT-5.4 (`Caste03` Sovereign Sentinel / Verifier — `codex exec`)**:
   - Maximized for Lean 4 theorem & Mojo oracle code generation, Gleam/Rust NIF bug fixes, EUnit/FMEA/mutation/falsifiability test execution, and skill/rule verification.
4. **Local Qwen2.5-Coder-7B (`Caste05` Local Inference — `http://razr15-1.tail55d152.ts.net:8000`)**:
   - Maximized for zero-burn local code synthesis, KPI verification, and 14-stage Dual-Plane telemetry probes (`remote_tokens_billed = 0`).

## 2. 100% Full-System-Code Lean 4 + Mojo + FPP + AI Agent Digital Twin Coverage

- **18/18 Lean 4 <-> Mojo Differential Pairs**: Governed by `tools/lean_mojo_differential.ml` and `formal/mojo/robustness_harness.mojo`, including Pair #18 (`formal/lean/UosFullSystemCodeUnifiedDigitalTwin.lean` <-> `formal/mojo/full_system_code_oracle.mojo`).
- **40/40 FPP Subsystem Actors (100.0% VERIFIED)**: Every subsystem in `apps/cepaf_gleam/src/cepaf_gleam/ecology/core_fpp_actor_twin_mesh.gleam` and `__fpp_mesh_itself__` is verified by live non-blind Mojo oracle checks in `governance/agents/policy/20261106-0428-uos-subsystem-twin-coverage-ledger.json` (`formal/mojo/twin_coverage_oracle.mojo`).
- **12/12 Code Domains, 11/11 Native NIFs & 113 Scripts**: Covered by `THM_FSYS_01..12` and `full_system_code_oracle.mojo` (68/68 checks).
- **Zero-Muda 3-Gate AK-47 Hot Path (36ms)**: Synchronous verification runs strictly through `Lean4_Kernel (16ms)` -> `Mojo_Differential_Oracle (18ms)` -> `AK47_SaPlan_SQLite (2ms)` (`116.7x` speedup vs 4,201ms 9-engine stack).

## 4. In-Process Lean 4 <-> Mojo C-ABI Interoperability & Multi-Agent Quota/Budget Failover

1. **In-Process Lean 4 <-> Mojo C-ABI Bridge (`formal/mojo/lean_ffi_bridge.mojo` <-> `var/zlp/libuos_lean_guard.so`)**:
   - `formal/lean/UosLeanRuntimeGuard.lean` exports 14 unboxed C-ABI functions (`@[export uos_lean_*]`, proved by `THM_GUARD_01..14`) compiled to `var/zlp/libuos_lean_guard.so` and `formal/lean/libuos_lean_guard.so` (`~49.5 ns/call`).
   - `formal/mojo/lean_ffi_bridge.mojo` loads `libuos_lean_guard.so` via Mojo `std.ffi.OwnedDLHandle` and verifies all 14 C-ABI exports plus 32/32 exhaustive state parity on `uos_lean_select_failover_agent`.
2. **Deterministic Quota/Budget/Outage Failover (`tools/uos-agent-failover`)**:
   - Proved in Lean 4 (`THM_FSYS_13..16`), mirrored in Gleam (`agent_ecology.select_failover_agent`), Mojo (`select_failover_code`), and OCaml (`tools/uos-agent-failover --selftest`, 16/16 PASS).
   - Automatically detects quota/budget exhaustion (`HTTP 429`, `HTTP 402`, `insufficient_quota`, `out of quota`, `rate_limit`, `budget exceeded`, `credit balance`), timeouts, non-zero exits, and empty outputs, cascading `Claude -> Codex -> LocalQwen` while never routing non-supervisor execution work to `OpenRouter+Gemini+Argon`.
