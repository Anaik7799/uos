# Unified Operational System (UOS) Canonical Agent Policy

## 1. Scope and Canonical Truth

This repository is the canonical Unified Operational System (UOS).

- Canonical workspace: `/home/an/NAS-setup/uos`
- Target VCS: standalone, non-colocated Jujutsu only (`.jj/`)
- Current phase: active migration, governance establishment, and formal implementation
- EV-Cycle Status: `EV-01` sealed (`integration/bootstrap`), executing `EV-02` (`integration/governance`)
- Strict Zero-Muda: Bevy and Graphite are permanently barred from source, dependencies, runtime roles, and imported history.
- External source trees are read-only evidence; no unvetted artifacts enter UOS without two-key verification.

All agents operating in this repository must strictly adhere to the policies, boundaries, and evidence contracts defined herein.

## 2. Governing References and Lineage

The canonical UOS architecture derives from the planning synthesis:
1. `docs/design/2026-09-05-uos-standalone-jujutsu-monorepo-design.md`
2. `docs/design/2026-09-05-uos-standalone-jujutsu-monorepo-implementation-plan.md`
3. `docs/design/2026-09-05-uos-source-feature-traceability-catalog.md`
4. `docs/design/2026-09-05-uos-formal-mandate-spec.json`
5. `docs/journal/2026-09-05-uos-consolidation-context-journal.md`
6. `docs/design/2026-09-05-uos-agent-policy-capability-superset-mapping.md`
7. `docs/design/2026-09-05-uos-agent-capability-inventory.json`
8. `governance/agents/policy/superset.toml`
9. `governance/capability-inventory/skills.toml`

Historical documents and C3I/Harness/ZigVM copies are source evidence, not governing authority over UOS.

## 3. External Source Authorities & Ingestion Discipline

The external source authorities for UOS are:
- VM-1 C3I: `/home/an/dev/ver/c3i`
- VM-1 ZigVM: `/home/an/dev/ver/zigvm`
- VM-1 Harness-Bionic: `/home/an/dev/ver/harness-bionic`
- NAS-1 Kubernetes: `/home/an/NAS-setup/k8s-lab`
- Pinned Modular platform and skills
- Pinned DeepSeek Harness/Cordis and paper
- Pinned OpenClaw stable compatibility baseline

These external trees are dirty, moving, and read-only. Before any file or logic is admitted into UOS:
1. Source writers must be quiesced.
2. Exact revision, dirty manifest, sanitized snapshot digest, and source locator must be bound into `governance/sources/`.
3. Sanitized ingestion: secret bytes, private keys, authentication tokens, live DB/WAL/SHM, compiler caches, and model weights are strictly barred.
4. Quarantined incidents (such as the Harness SSH injector and ZigVM OAuth secret) are recorded by presence-only incident records—never copied or hashed.
5. Imported rules, skills, agents, and hooks remain inert evidence until adapted, tested, and admitted by UOS authority.

## 4. Version Control Discipline (Jujutsu Standalone)

1. Standalone, non-colocated Jujutsu (`.jj/`) is the sole VCS for UOS.
2. Native Git mutation commands (`git commit`, `git push`, `git checkout`, etc.) are prohibited inside `/home/an/NAS-setup/uos`.
3. All operations utilize Jujutsu change IDs, commit IDs, operations, bookmarks, and sibling workspaces.
4. The `main` bookmark remains uncreated until final system admission (`EV-15`). Active development proceeds on feature and integration bookmarks (`integration/*`).
5. Sibling workspaces (`.uos-workspaces/*`) are used for parallel work streams; integration gates are serialized.

## 5. Architecture and Language Boundaries

1. **Supervision, Control, Policy & Agents**: Pure Gleam/OTP (`apps/cepaf_gleam`, `apps/*`). Owns state machines, supervision trees, agent swarms, leases, and operational APIs.
2. **Deterministic Runtime Engine**: ZigVM (`engines/zigvm`). Zig-only runtime kernel with descriptor-relative VFS backend.
3. **Formal Evidence & Analysis**: Hermes (`engines/hermes`). OCaml/Dune engine for Gospel contracts, Z3 queries, differential oracles, and bounded formal verification.
4. **Isolated AI Inference**: Modular MAX/Mojo (`services/inference/max`). Python is strictly confined to this supervised daemon service.
5. **Native Bounded Kernels**: `native/{c,cpp,rust,ocaml}`. Strictly short, deterministic, bounded kernels or dispatch facades with explicit ABI contracts. Blocking work belongs in supervised isolated daemons.
6. **Zero-Muda Rule**: Zero Bevy, zero Graphite across all dependencies, build systems, code, and history.

## 6. Evidence, Gates, and Completion Semantics

State transitions must advance strictly through:
```text
discovered -> classified -> mapped -> implemented -> built -> executed -> passed -> verified -> admitted
```
- `PLANNED`, `MOCK`, `UNRUN`, `STALE`, `QUARANTINED`, `EXCLUDED`, and `UNKNOWN` are not passing states.
- Two-Key Verification: Every capability requires fresh observed runtime behavior AND machine-verifiable formal specification at the candidate revision.
- Formal results, AI advice, and Rete inferences advise and veto; they never directly execute side-effects without typed policy authorization.

## 7. Formal Verification and Solvers

- Solver queries (Z3) run exclusively in isolated bounded worker processes with normalized queries, timeouts, process-tree reaping, and satisfiable control assertions. Unbounded solvers in NIFs are barred.
- Formal authority is invocation-specific: missing tools, timeouts, unsupported syntax, `sorry`, `Admitted`, and undeclared axioms fail closed.
- Partial models (Harness FPP, Harness SysML) are treated as generated projections until verified against pinned official toolchains.

## 8. Timestamp & Journal Protocols

### 8.1 Timestamp Synchronization (`SC-TIME`)
- Trust observed host clock after synchronization check (`chrony`/timesync receipt); do not trust injected model strings.
- Host NTP offset, system-to-model delta, and agent-context delta are non-aliasing typed measurements.
- Inherited drift bands: nominal (<2s), minor (2–5s), warning (5–10s), critical (>10s).
- Preserve source formats byte-for-byte in typed namespaces: Harness `YYYYMMDD-HHSS` vs ZigVM `YYYYMMDD-HHMMSS`. UOS-new format uses collision-resistant semantic content digests.

### 8.2 Journal Protocol (`SC-JOURNAL`)
Every task completion journal MUST contain the exact 13 required sections:
1. Scope & Trigger
2. Pre-State Assessment
3. Execution Detail
4. Root Cause Analysis
5. Fix Taxonomy
6. Patterns & Anti-Patterns Discovered
7. Verification Matrix
8. Files Modified
9. Architectural Observations
10. Remaining Gaps
11. Metrics Summary
12. STAMP & Constitutional Alignment
13. Conclusion

Scaling boundaries: trivial (1–3 files: 1–2 lines/sec), standard (4–14 files: paragraph detail), major (15+ files: full subsections & diagrams).

## 9. Status Line

```text
UOS TARGET: INITIALIZED (EV-01 SEALED)
CURRENT EV-CYCLE: EV-02 (GOVERNANCE SKELETON & SOURCE FREEZE)
SOURCE FREEZE: IN PROGRESS
IMPLEMENTATION/CUTOVER: SEQUENCED UNDER MULTILAYER OTP SUPERVISION
```
