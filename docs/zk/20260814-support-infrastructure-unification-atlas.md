---
id: zigvm-support-infrastructure-unification-atlas
title: Support Infrastructure Unification & Capability Atlas
aliases: [Support Infra Atlas, Harness Bionic Migration Atlas]
status: published
type: decision
ktype: moc
maturity: evergreen
domain: system-architecture
topics: [support-infra, zk, wiki, km, atlas, formal-algebra, dependability, sandboxing, dashboards]
links: [moc-algebra-driven-ocaml-doctrine, 20260725-zk-wiki-system-architecture]
created: 2026-08-14
verified_by: Gemini
---

# Support Infrastructure Unification & Capability Atlas

## Context & Purpose

This Map of Content (MoC) establishes the ground truth, formal invariants, and architectural wiring for the 20 net-new support infrastructure, knowledge management, wiki/ZK, algebraic atlas, worker sandboxing, and high-assurance dependability capabilities unified from `harness-bionic` into `zigvm`.

## Subsystem Index & Mapped Capabilities

### 1. Database Durability & Concurrency Fencing (`WS-A`)
- **SQLite Lifecycle Model**: [`sqlite_lifecycle_model.ml`](file:///home/an/dev/ver/zigvm/harness/sqlite_lifecycle_model.ml) — 25 formal BFS laws, 19 mutants killed. Proves order-independence, atomicity, and read-your-writes.
- **Writer Lease & Epoch Fencing**: [`db_writer_lease.ml`](file:///home/an/dev/ver/zigvm/harness/db_writer_lease.ml) — Epoch fencing, monotonic LSN progression, lease heartbeat, and split-brain writer prevention.

### 2. Static Verification & Integrity Ratchets (`WS-B`)
- **External Access Census Scanner**: [`external_access_census.ml`](file:///home/an/dev/ver/zigvm/harness/external_access_census.ml) — AST-level lexical comment/string-aware scanner blocking rogue I/O.
- **Rule Title Sync Gate**: [`rule_title_sync_gate.ml`](file:///home/an/dev/ver/zigvm/harness/rule_title_sync_gate.ml) — Bidirectional synchronization between rule files and header declarations.
- **Substantive Justification Floor**: [`supervisor_memory.ml`](file:///home/an/dev/ver/zigvm/harness/supervisor_memory.ml) — Minimum $\ge 20$ characters non-trivial justification ratchet.

### 3. Algebraic Atlas & Living Ontology (`WS-C`)
- **Fractal FP Atlas Graph & Sweeper**: [`fractal_fp_atlas_graph.ml`](file:///home/an/dev/ver/zigvm/harness/fractal_fp_atlas_graph.ml) — DFS cycle detection, topological sorting, and transitive bypass sweepers.
- **Verdict Semilattice Prover**: [`fractal_fp_atlas.ml`](file:///home/an/dev/ver/zigvm/harness/fractal_fp_atlas.ml) — Bounded meet-semilattice with absorption zero (`Blocked < Divergent < Pass`).
- **Cryptographic Declaration Digests**: [`fractal_fp_atlas_registry.ml`](file:///home/an/dev/ver/zigvm/harness/fractal_fp_atlas_registry.ml) — Canonical SHA-256 declaration fingerprinting over 33 subsystems.
- **`onto_algebra` Schema Extension**: [`zigvm_harness.ml`](file:///home/an/dev/ver/zigvm/harness/zigvm_harness.ml) — 12/12 ontology audit laws passing over 3,625 nodes and 6,506 edges.

### 4. Wiki Sheaves, Visibility & Knowledge Management (`WS-D`)
- **3-State Page Visibility Matrix**: [`zk_page_visibility.ml`](file:///home/an/dev/ver/zigvm/harness/zk_page_visibility.ml) — Closed `Public | Restricted | Internal` state transitions.
- **Dependency Sheaf Renderer**: [`wiki_dep_sheaf.ml`](file:///home/an/dev/ver/zigvm/harness/wiki_dep_sheaf.ml) — Minimal closed sub-graph sheaf isolation with depth bounds.
- **Literate Doctest Runner**: [`zk_doctest_runner.ml`](file:///home/an/dev/ver/zigvm/harness/zk_doctest_runner.ml) — Literate code block extraction and AST verification.
- **MBSE Feature Projection**: [`zk_mbse_projection.ml`](file:///home/an/dev/ver/zigvm/harness/zk_mbse_projection.ml) — Bidirectional Markdown table round-trip to MBSE ledgers.

### 5. Worker Sandboxing, SOPs & Diagnostic Algebra (`WS-E`)
- **Solver Sandbox**: [`solver_sandbox.ml`](file:///home/an/dev/ver/zigvm/harness/solver_sandbox.ml) — Process group isolation (`setpgid`), strict timeouts, and SHA-256 I/O digests.
- **Generative SOP Engine**: [`sop_registry_engine.ml`](file:///home/an/dev/ver/zigvm/harness/sop_registry_engine.ml) — Living, drift-proof SOP document generation from typed registries.
- **Heuer ACH Diagnostic Algebra**: [`debug_algebra.ml`](file:///home/an/dev/ver/zigvm/harness/debug_algebra.ml) — Analysis of Competing Hypotheses for divergence-origin triage.

### 6. High-Assurance Dependability & SysML Foundations (`WS-DEP` & `WS-SYS`)
- **RFC 8032 Ed25519 Ticket Validator**: [`dependability_approval_crypto.ml`](file:///home/an/dev/ver/zigvm/harness/dependability_approval_crypto.ml) — Pure validation-only ticket verifier.
- **POSIX/Monotonic Clock Observers**: [`dependability_clock.ml`](file:///home/an/dev/ver/zigvm/harness/dependability_clock.ml) — Monotonic clock protection against wall-clock skew and rollback.
- **Dune Graph Cone Monoid Algebra**: [`dune_graph.ml`](file:///home/an/dev/ver/zigvm/harness/dune_graph.ml) — Reverse dependency cone algebra and SMT2 QF_LIA acyclicity encoding.
- **SysML v2 Categorical Transitions**: [`sysml_algebra.ml`](file:///home/an/dev/ver/zigvm/harness/sysml_algebra.ml) — Typed GADT state transitions and synchronous port communication.

## Dashboards & Web UI Projections

The system dynamically renders the following self-contained, typed HTML operational surfaces:
- **Ops Board**: [`docs/dashboards/ops_dashboard.html`](file:///home/an/dev/ver/zigvm/docs/dashboards/ops_dashboard.html) — Live harness runs, laws, baseline conformance, and task queues.
- **Strategic Board**: [`docs/dashboards/strategic_dashboard.html`](file:///home/an/dev/ver/zigvm/docs/dashboards/strategic_dashboard.html) — Six-axis as-is/to-be status, STPA risk envelopes, SRE/SDLC invariants, and Stan Bayesian drift models.
- **SLO Board**: [`docs/dashboards/slo_dashboard.html`](file:///home/an/dev/ver/zigvm/docs/dashboards/slo_dashboard.html) — Service level objectives, error budgets, and latency distributions.
- **Doc Lint Observability Dashboard**: [`docs/design/lint/lint_dashboard.html`](file:///home/an/dev/ver/zigvm/docs/design/lint/lint_dashboard.html) — Inline SVG charts, OTEL trace streams, and 24-rule lint analysis across 1,868 files.
- **Self-Contained Journal Web UI**: [`docs/journal/journal.html`](file:///home/an/dev/ver/zigvm/docs/journal/journal.html) — Typed OCaml rendered publication artifacts with SHA-256 disclosures.

## Verification & Parity Invariants

All 20 capabilities are covered by 18 test executables (122+ assertions) built directly into the harness suite manifest (`Db_suite_manifest.built` = 105, `Db_suite_manifest.runnable` = 103), passing all 8,979 wiki content-contract checks with 0 broken links and 0 errors.

## Cross-References
- [[moc-algebra-driven-ocaml-doctrine]]
- [[20260725-zk-wiki-system-architecture]]
- [[20260729-fractal-atlas]]
