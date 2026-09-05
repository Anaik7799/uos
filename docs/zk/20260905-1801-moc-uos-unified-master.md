# 20260905-1801-moc-uos-unified-master.md
# Map of Content: UOS Unified Master Knowledge Base & Triad Architecture

Tags: `#rocha-semiotics`, `#cybernetics`, `#fractal-l0`, `#fractal-l1`, `#fractal-l2`, `#fractal-l3`, `#fractal-l4`, `#fractal-l5`, `#fractal-l6`, `#fractal-l7`, `#fractal-l8`, `#fractal-l9`, `#zk-adr`, `#zero-muda`, `#km-triad`, `#moc`

## §1.0 Executive Architecture & Corpus Triad

The Unified Operational System (UOS) integrates three foundational corpora into an interconnected, bidirectional living knowledge graph:

```mermaid
graph TD
    subgraph TRIAD["UOS Knowledge Management Triad (#km-triad)"]
        HERMES_WIKI["Hermes Wiki Engine<br/>(engines/hermes/modules/hermes_wiki)<br/>AST, TyXML, Gospel, Similarity"]
        ZIGVM_ZK["ZigVM Zettelkasten<br/>(docs/zk/)<br/>ADR-001..016 & Maps of Content"]
        C3I_ONTOLOGY["C3I Living Ontology<br/>(docs/wiki/ & governance/)<br/>STAMP Lattices & 13D Trace Coordinates"]
    end

    HERMES_WIKI <-->|transclusion [[wiki:...]]| ZIGVM_ZK
    ZIGVM_ZK <-->|transclusion [[zk:...]]| C3I_ONTOLOGY
    C3I_ONTOLOGY <-->|SQLite Ledgers & 13D Coordinates| HERMES_WIKI
```

1. **Hermes Wiki Engine** (`engines/hermes/modules/hermes_wiki`):
   - Pure OCaml AST parsing, Gospel-specified contracts (`journal.gospel`, `wiki_lifecycle.mli`).
   - Bidirectional transclusion syntax `[[wiki:...]]` and similarity graph calculation (`wiki_similarity.ml`).
   - Server-side typed TyXML rendering without client JavaScript.
2. **ZigVM Zettelkasten** (`docs/zk/`):
   - Permanent Architectural Decision Records ([`ADR-001`](file:///home/an/NAS-setup/uos/docs/zk/20260904-150139-adr-001-closed-rete-fact-schema-and-strict-typing-invariant.md) through [`ADR-016`](file:///home/an/NAS-setup/uos/docs/zk/20260904-164632-adr-016-master-fractal-system-integration-7-level-granularity-closure-and-tripartite-ratification.md)).
   - Structural Maps of Content (MOCs) preserving algebra-driven doctrines and fractal layers.
3. **C3I Living Ontology & Evidence Plane** (`docs/wiki/`, `governance/`):
   - STAMP/STPA safety lattices, SQLite living catalogs, and 13D trace coordinates.
   - Dual-lattice STM non-interference proved in Lean 4 (`formal/lean/TwoLattice_STM.lean`).

---

## §2.0 Permanent Architectural Decision Records (ADR-001..ADR-016)

| ADR ID | Document File | Layer | Tailscale Live View | Core Invariant & Decision Summary |
|---|---|---|---|---|
| **ADR-001** | [`20260904-150139-adr-001-closed-rete-fact-schema-and-strict-typing-invariant.md`](file:///home/an/NAS-setup/uos/docs/zk/20260904-150139-adr-001-closed-rete-fact-schema-and-strict-typing-invariant.md) | <span class="badge badge-fractal">#fractal-l5</span> | [ADR-001 Live View](http://nas-1.tail55d152.ts.net:4100/docs/zk/20260904-150139-adr-001-closed-rete-fact-schema-and-strict-typing-invariant.md) | Closed Rete-UL fact schema; rejects dynamically shaped facts; strict compile-time typing. |
| **ADR-002** | [`20260904-150142-adr-002-embedded-nul-ingress-trap-and-memory-allocation-containment.md`](file:///home/an/NAS-setup/uos/docs/zk/20260904-150142-adr-002-embedded-nul-ingress-trap-and-memory-allocation-containment.md) | <span class="badge badge-fractal">#fractal-l6</span> | [ADR-002 Live View](http://nas-1.tail55d152.ts.net:4100/docs/zk/20260904-150142-adr-002-embedded-nul-ingress-trap-and-memory-allocation-containment.md) | Embedded NUL byte ingress trap in `agent_dispatch_hook.ml`; immediate abort with error code -2. |
| **ADR-003** | [`20260904-150145-adr-003-pure-100-byte-binary-sqlite-header-verification-rule-r31.md`](file:///home/an/NAS-setup/uos/docs/zk/20260904-150145-adr-003-pure-100-byte-binary-sqlite-header-verification-rule-r31.md) | <span class="badge badge-fractal">#fractal-l3</span> | [ADR-003 Live View](http://nas-1.tail55d152.ts.net:4100/docs/zk/20260904-150145-adr-003-pure-100-byte-binary-sqlite-header-verification-rule-r31.md) | Pure 100-byte SQLite binary header verification before opening database connection (Rule R31). |
| **ADR-004** | [`20260904-150151-adr-004-supervised-persistent-zenoh-session-lifecycle-in-moz-client.md`](file:///home/an/NAS-setup/uos/docs/zk/20260904-150151-adr-004-supervised-persistent-zenoh-session-lifecycle-in-moz-client.md) | <span class="badge badge-fractal">#fractal-l6</span> | [ADR-004 Live View](http://nas-1.tail55d152.ts.net:4100/docs/zk/20260904-150151-adr-004-supervised-persistent-zenoh-session-lifecycle-in-moz-client.md) | Supervised persistent Zenoh session lifecycle in MoZ client; eliminates reconnect flaps. |
| **ADR-005** | [`20260904-151412-adr-005-dual-host-unified-operational-system-topology-and-live-tailnet-wiki-integration.md`](file:///home/an/NAS-setup/uos/docs/zk/20260904-151412-adr-005-dual-host-unified-operational-system-topology-and-live-tailnet-wiki-integration.md) | <span class="badge badge-fractal">#fractal-l7</span> | [ADR-005 Live View](http://nas-1.tail55d152.ts.net:4100/docs/zk/20260904-151412-adr-005-dual-host-unified-operational-system-topology-and-live-tailnet-wiki-integration.md) | Dual-host (VM-1 / NAS-1) topology over secure Tailnet; unified Hermes wiki server integration. |
| **ADR-006** | [`20260904-153122-adr-006-twelve-pillar-fractal-architecture-composability-and-multi-paradigm-integration.md`](file:///home/an/NAS-setup/uos/docs/zk/20260904-153122-adr-006-twelve-pillar-fractal-architecture-composability-and-multi-paradigm-integration.md) | <span class="badge badge-fractal">#fractal-l0</span> | [ADR-006 Live View](http://nas-1.tail55d152.ts.net:4100/docs/zk/20260904-153122-adr-006-twelve-pillar-fractal-architecture-composability-and-multi-paradigm-integration.md) | 12-Pillar Fractal Architecture; composable functional holons; zero foreign mutation. |
| **ADR-007** | [`20260904-153714-adr-007-tripartite-cross-agent-multi-cycle-review-and-full-twelve-pillar-system-acceptance.md`](file:///home/an/NAS-setup/uos/docs/zk/20260904-153714-adr-007-tripartite-cross-agent-multi-cycle-review-and-full-twelve-pillar-system-acceptance.md) | <span class="badge badge-fractal">#fractal-l5</span> | [ADR-007 Live View](http://nas-1.tail55d152.ts.net:4100/docs/zk/20260904-153714-adr-007-tripartite-cross-agent-multi-cycle-review-and-full-twelve-pillar-system-acceptance.md) | Tripartite cross-agent consensus (Claude, Codex, AGY); 2oo3 voting on architecture reviews. |
| **ADR-008** | [`20260904-154335-adr-008-nas-1-codebase-unification-rust-ocaml-nif-conversion-and-gleam-migration-strategy.md`](file:///home/an/NAS-setup/uos/docs/zk/20260904-154335-adr-008-nas-1-codebase-unification-rust-ocaml-nif-conversion-and-gleam-migration-strategy.md) | <span class="badge badge-fractal">#fractal-l2</span> | [ADR-008 Live View](http://nas-1.tail55d152.ts.net:4100/docs/zk/20260904-154335-adr-008-nas-1-codebase-unification-rust-ocaml-nif-conversion-and-gleam-migration-strategy.md) | Relocation of crash-prone NIFs to isolated services; Gleam OTP supervision of all boundaries. |
| **ADR-009** | [`20260904-154524-adr-009-distinct-functional-relocation-from-ocaml-and-rust-into-native-gleam.md`](file:///home/an/NAS-setup/uos/docs/zk/20260904-154524-adr-009-distinct-functional-relocation-from-ocaml-and-rust-into-native-gleam.md) | <span class="badge badge-fractal">#fractal-l2</span> | [ADR-009 Live View](http://nas-1.tail55d152.ts.net:4100/docs/zk/20260904-154524-adr-009-distinct-functional-relocation-from-ocaml-and-rust-into-native-gleam.md) | Native Gleam migration of C3I control logic; pure Erlang math replacing foreign Graphene NIFs. |
| **ADR-010** | [`20260904-155000-adr-010-seven-level-fractal-granularity-taxonomy-and-100-functional-mapping-kpis.md`](file:///home/an/NAS-setup/uos/docs/zk/20260904-155000-adr-010-seven-level-fractal-granularity-taxonomy-and-100-functional-mapping-kpis.md) | <span class="badge badge-fractal">#fractal-l8</span> | [ADR-010 Live View](http://nas-1.tail55d152.ts.net:4100/docs/zk/20260904-155000-adr-010-seven-level-fractal-granularity-taxonomy-and-100-functional-mapping-kpis.md) | 7-Level fractal granularity taxonomy; machine-verified functional mapping KPIs. |
| **ADR-011** | [`20260904-155139-adr-011-tripartite-surface-system-architecture-and-inter-fractal-traceability-closure.md`](file:///home/an/NAS-setup/uos/docs/zk/20260904-155139-adr-011-tripartite-surface-system-architecture-and-inter-fractal-traceability-closure.md) | <span class="badge badge-fractal">#fractal-l4</span> | [ADR-011 Live View](http://nas-1.tail55d152.ts.net:4100/docs/zk/20260904-155139-adr-011-tripartite-surface-system-architecture-and-inter-fractal-traceability-closure.md) | Triple-interface surface parity (Lustre HTML, Wisp JSON, TUI ANSI) with 13D trace closure. |
| **ADR-012** | [`20260904-155425-adr-012-four-cycle-deep-tripartite-audit-and-sovereign-system-attestation.md`](file:///home/an/NAS-setup/uos/docs/zk/20260904-155425-adr-012-four-cycle-deep-tripartite-audit-and-sovereign-system-attestation.md) | <span class="badge badge-fractal">#fractal-l5</span> | [ADR-012 Live View](http://nas-1.tail55d152.ts.net:4100/docs/zk/20260904-155425-adr-012-four-cycle-deep-tripartite-audit-and-sovereign-system-attestation.md) | 4-Cycle deep tripartite audit; cryptographic signature verification for system attestation. |
| **ADR-013** | [`20260904-155835-adr-013-sovereign-tripartite-review-cycle-continuation-and-multi-domain-deep-verification.md`](file:///home/an/NAS-setup/uos/docs/zk/20260904-155835-adr-013-sovereign-tripartite-review-cycle-continuation-and-multi-domain-deep-verification.md) | <span class="badge badge-fractal">#fractal-l5</span> | [ADR-013 Live View](http://nas-1.tail55d152.ts.net:4100/docs/zk/20260904-155835-adr-013-sovereign-tripartite-review-cycle-continuation-and-multi-domain-deep-verification.md) | Multi-domain verification of Lean 4 theorems and Quint temporal logic specifications. |
| **ADR-014** | [`20260904-160005-adr-014-quad-cycle-iii-sovereign-tripartite-audit-and-comprehensive-kpi-integration-closure.md`](file:///home/an/NAS-setup/uos/docs/zk/20260904-160005-adr-014-quad-cycle-iii-sovereign-tripartite-audit-and-comprehensive-kpi-integration-closure.md) | <span class="badge badge-fractal">#fractal-l8</span> | [ADR-014 Live View](http://nas-1.tail55d152.ts.net:4100/docs/zk/20260904-160005-adr-014-quad-cycle-iii-sovereign-tripartite-audit-and-comprehensive-kpi-integration-closure.md) | Comprehensive KPI integration closure across SRE, SDLC, formal verification, and runtime metrics. |
| **ADR-015** | [`20260904-160159-adr-015-master-codex-session-handover-full-trajectory-archive-and-sovereign-operational-transfer.md`](file:///home/an/NAS-setup/uos/docs/zk/20260904-160159-adr-015-master-codex-session-handover-full-trajectory-archive-and-sovereign-operational-transfer.md) | <span class="badge badge-fractal">#fractal-l9</span> | [ADR-015 Live View](http://nas-1.tail55d152.ts.net:4100/docs/zk/20260904-160159-adr-015-master-codex-session-handover-full-trajectory-archive-and-sovereign-operational-transfer.md) | Sovereign operational transfer from C3I to standalone Jujutsu UOS repository. |
| **ADR-016** | [`20260904-164632-adr-016-master-fractal-system-integration-7-level-granularity-closure-and-tripartite-ratification.md`](file:///home/an/NAS-setup/uos/docs/zk/20260904-164632-adr-016-master-fractal-system-integration-7-level-granularity-closure-and-tripartite-ratification.md) | <span class="badge badge-fractal">#fractal-l0</span> | [ADR-016 Live View](http://nas-1.tail55d152.ts.net:4100/docs/zk/20260904-164632-adr-016-master-fractal-system-integration-7-level-granularity-closure-and-tripartite-ratification.md) | Final system ratification; 17 EV-cycle doctor gates operational; zero-muda guarantee. |

---

## §3.0 Maps of Content (MOCs)

- [`moc-algebra-driven-ocaml-doctrine.md`](file:///home/an/NAS-setup/uos/docs/zk/moc-algebra-driven-ocaml-doctrine.md): Initial and final encodings, signature-law-carrier triads, homomorphism property tests.
- [`moc-agents-codex-symbiosis-supervisor.md`](file:///home/an/NAS-setup/uos/docs/zk/moc-agents-codex-symbiosis-supervisor.md): Multi-layer agent supervision, shared MCP control plane, and SQLite WAL coordination.
- [`moc-agent-handover.md`](file:///home/an/NAS-setup/uos/docs/zk/moc-agent-handover.md): Zero-drift context preservation protocol and deterministic state recovery.
- [`20260729-fractal-atlas.md`](file:///home/an/NAS-setup/uos/docs/zk/20260729-fractal-atlas.md): Complete atlas mapping physical hardware, network interfaces, and fractal layers.
- [`20260725-zk-wiki-system-architecture.md`](file:///home/an/NAS-setup/uos/docs/zk/20260725-zk-wiki-system-architecture.md): Transclusion grammar, TyXML pipelines, and Gospel behavioral contracts.

---

## §4.0 Bi-Directional Transclusion & Cross-Links

- Master Wiki: `[[wiki:20260905-1721-uos-master-knowledge-graph-and-living-ontology]]`
- Corpus Index: `[[wiki:20260905-1801-uos-zk-km-corpus-index]]`
- Lean Invariants: `[[zk:TwoLattice_STM]]` (`formal/lean/TwoLattice_STM.lean`)
- Quint Temporal Frontier: `[[zk:parity_frontier]]` (`formal/quint/parity_frontier.qnt`)
- Zero-Trust Hook: `[[zk:agent_dispatch_hook]]` (`engines/hermes/modules/hermes_harness/agent_dispatch_hook.ml`)
- Storage Safety Interlock: `[[zk:hardware_serial_interlock]]` (`HARD_DENIED_SYSTEM_OS_SERIAL = "25503L801736"`)
- Zero-Muda Graphene Exclusion: `[[zk:pure_erlang_math]]` (`apps/cepaf_gleam/src/graphene_nif.erl`)
