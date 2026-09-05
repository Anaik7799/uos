# 20260905-1721- UOS Master Knowledge Graph, Wiki, ZK & Living Ontology Specification

- **Tailscale Web FQDN**: [http://nas-1.tail55d152.ts.net:4100/docs/wiki/20260905-1721-uos-master-knowledge-graph-and-living-ontology.md](http://nas-1.tail55d152.ts.net:4100/docs/wiki/20260905-1721-uos-master-knowledge-graph-and-living-ontology.md)
- **Fractal Coordinates**: `#fractal-l0` `#fractal-l1` `#fractal-l2` `#fractal-l3` `#fractal-l4` `#fractal-l5`
- **Knowledge Tags**: `#rocha-semiotics` `#cybernetics` `#km-triad` `#zero-muda` `#tailscale-web`
- **Transclusions**: `[[zk:20260905-1801-moc-uos-unified-master]]` `[[wiki:20260905-1801-uos-zk-km-corpus-index]]`


## 1. Executive Summary & Knowledge Architecture

This document establishes the authoritative Unified Operational System (UOS) Knowledge Management (KM) Architecture, unifying three historically federated knowledge networks into a single, cohesive, bidirectional, and verified knowledge graph.

- **Authority**: UOS Architecture Board & Formal Mandate Spec (`docs/design/2026-09-05-uos-formal-mandate-spec.json`)
- **Ontology Alignment**: L0-L9 13D atomic trace coordinates $\langle \text{layer}, \text{component}, \text{feature}, \text{surface}, \text{interaction}, \text{plane}, \text{structure}, \text{formal\_profile} \rangle$
- **Zero-Muda Standard**: Strict 0 Bevy, 0 Graphite across all code, documentation, and AST parsers.
- **Graphene Exclusion**: **Graphene is not required.** All vector math, 2D transforms, and graph algorithms are implemented natively in pure Erlang/Gleam or Hermes OCaml with 0 external C/Rust NIF dependencies.
- **Mandatory Timestamp**: Strictly prefixed with canonical `YYYYMMDD-HHSS-` pattern.

---

## 2. Knowledge Triad: Sources, Locators & Ground Truth

The UOS knowledge plane unifies three foundational corpora:

```
+-----------------------------------------------------------------------------+
|                                 UOS KM TRIAD                                |
+-----------------------------------------------------------------------------+
|                                                                             |
|      +------------------------+             +------------------------+      |
|      |    1. Hermes Wiki      |             |   2. ZigVM ZK Engine   |      |
|      | engines/hermes/modules/|<----------->| /home/an/dev/ver/zigvm/|      |
|      |      hermes_wiki       |             |        docs/zk         |      |
|      | (TyXML, AST, Gospel,   |             | (ADR-001..016, MOCs,   |      |
|      |  Search, Transclusion) |             |  Fractal Atlas, OAIS)  |      |
|      +------------------------+             +------------------------+      |
|                   ^                                      ^                  |
|                   |                  +-------------------+                  |
|                   v                  v                                      |
|      +-------------------------------------------------------+              |
|      |                   3. C3I Living Ontology              |              |
|      |              /home/an/dev/ver/c3i/docs                |              |
|      |          (STAMP/STPA, SQLite Living Catalog,          |              |
|      |            Universal Fractal Observability)           |              |
|      +-------------------------------------------------------+              |
|                                                                             |
+-----------------------------------------------------------------------------+
```

### 2.1 Hermes Wiki Engine
- **Engine Path**: `engines/hermes/modules/hermes_wiki/`
- **Capabilities**:
  - Abstract Syntax Tree (`src/engine/wiki_ast.ml`, `wiki_ast.gospel`)
  - Directives & Callouts (`src/engine/wiki_directive.ml`, `src/engine/wiki_callout.ml`)
  - Transclusion & Datastore (`src/engine/wiki_transclude.ml`, `src/engine/wiki_datastore.ml`)
  - Graph Similarity & Vector Topology (`src/graph/wiki_similarity.ml`, `src/graph/wiki_graph.ml`)
  - TyXML Type-Safe Markup Generation (`src/render/wiki_tyxml.ml`)
  - Full-Text & Lexical Search (`src/search/wiki_search.ml`)
  - OTel & OpenTelemetry Traceability (`src/control/wiki_otel.ml`)

### 2.2 ZigVM Zettelkasten (ZK) Corpus
- **Repository Path**: `/home/an/dev/ver/zigvm/docs/zk/`
- **Key Artifacts & Decisions**:
  - `ADR-001`: Closed Rete-UL Fact Schema & Strict Typing Invariants (`#zk-adr-001`, `#rete-ul`)
  - `ADR-002`: Embedded NUL Ingress Trap & Allocation Containment (`#zk-adr-002`, `#zero-trust`)
  - `ADR-003`: Pure 100-Byte Binary SQLite Header Verification Rule R31 (`#zk-adr-003`, `#sqlite-wal`)
  - `ADR-004`: Persistent Zenoh Session Lifecycle in Moz Client (`#zk-adr-004`, `#zenoh-mesh`)
  - `ADR-005`: Dual-Host Unified Operational System Topology (`#zk-adr-005`, `#topology`)
  - `ADR-006` to `ADR-016`: Twelve-Pillar Fractal Architecture, Tripartite Acceptance, and Sovereign Attestation (`#fractal-l0-l9`)
  - `MOC` (Maps of Content):
    - `moc-algebra-driven-ocaml-doctrine.md`
    - `moc-agents-codex-symbiosis-supervisor.md`
    - `moc-agent-handover.md`

### 2.3 C3I Living Ontology & Observability Plane
- **Source Path**: `/home/an/dev/ver/c3i/docs/`
- **Database Plane**: SQLite Living Ontology Ledger (`sqlite/c3i_living_ontology.db`)
- **Key Artifacts**:
  - Universal Fractal Observability Specification (`contracts/evidence/c3i_fractal_observability_spec.json`)
  - STPA Control Actions & Hazard Loss Scenarios (`#stamp-stpa`, `#uca-mitigation`)
  - CEPAF-Gleam Supervised Subsystem Tree (`uos_sup.gleam`, `#gleam-otp`)

---

## 3. Bidirectional Wiki Tags & Taxonomy

To ensure semantic discoverability across all agents (AGY, Claude, Codex) and humans, the following standardized taxonomy of wiki tags is established:

| Tag Family | Example Tags | Semantics & Scope |
| :--- | :--- | :--- |
| **Fractal Layer** | `#fractal-l0`, `#fractal-l1`, `#fractal-l2`, `#fractal-l3`, `#fractal-l4`, `#fractal-l5`, `#fractal-l6`, `#fractal-l7`, `#fractal-l8`, `#fractal-l9` | Layer binding from Mathematical/Physical substrate up to Super-Swarm Ecosystem |
| **Knowledge / ZK** | `#zk-adr`, `#zk-moc`, `#zk-slipbox`, `#zk-permanent`, `#zk-transclusion` | Zettelkasten knowledge notes, architectural decision records, and structural indices |
| **Formal & Proof** | `#formal-lean4`, `#formal-quint`, `#formal-gospel`, `#formal-z3`, `#proof-0axiom` | Machine-checked specifications, non-interference theorems, and linearizability invariants |
| **Safety & STAMP** | `#stamp-stpa`, `#fmea-rank`, `#zero-trust`, `#fail-closed`, `#root-drive-denial` | Hazard analysis, unsafe control actions, hardware serial locks, and boundary guards |
| **Control Plane** | `#gleam-otp`, `#hermes-ocaml`, `#zigvm-kernel`, `#modular-max`, `#c3i-control` | Cross-language C3I implementation mapping across pure functional and deterministic domains |
| **Zero-Muda** | `#zero-muda`, `#bevy-purged`, `#graphite-excluded`, `#graphene-not-required` | Clean architectural footprint: 0 Bevy, 0 Graphite, 0 redundant NIF dependencies |

---

## 4. Transclusion and Cross-Reference Syntax

The UOS knowledge system supports structured transclusion directives recognized by both Hermes Wiki (`wiki_transclude.ml`) and ZK note parsers:

1. **Direct Wiki Page Link**:
   `[[wiki:20260905-1721-uos-master-knowledge-graph-and-living-ontology]]`
2. **ZK Note Reference**:
   `[[zk:adr-001-closed-rete-fact-schema]]`
3. **Formal Specification Cross-Reference**:
   `[[formal:TwoLattice_STM.lean#L25-L60]]`
   `[[formal:Traceability.lean#L10-L45]]`
   `[[formal:parity_frontier.qnt#L1-L35]]`
4. **Safety Control Cross-Reference**:
   `[[stamp:SC-SIL6-001]]`
   `[[hardware:25503L801736-ROOT-DRIVE-LOCK]]`

---

## 5. Architectural Non-Necessity of Graphene

Per explicit operational mandate:
> **"graphene is not required"**

### 5.1 Rationale
1. **Zero-Muda Alignment**: The historical `graphene_nif` crate in C3I pulled in `bevy_ecs`, `bevy_math`, `bevy_color`, and Graphite dependencies. Re-introducing or linking it violates the Zero-Muda standard.
2. **Computational Redundancy**: 2D vector mathematics (distances, interpolations, dot products, angles) and graph operations (BFS, DFS, topological sort, SCC) do not justify NIF overhead or unvetted foreign function pointers.
3. **OTP Native Purity**: All required vector geometry is provided by pure Erlang/Gleam algorithms in `apps/cepaf_gleam/src/graphene_nif.erl`, eliminating shared library load failures, memory corruption risks, and external build dependencies.

---

## 6. Living Knowledge Lifecycle (`#km-lifecycle`)

Every knowledge artifact undergoes the strict 9-state lifecycle:
$$\text{discovered} \longrightarrow \text{classified} \longrightarrow \text{mapped} \longrightarrow \text{implemented} \longrightarrow \text{built} \longrightarrow \text{executed} \longrightarrow \text{passed} \longrightarrow \text{verified} \longrightarrow \text{admitted}$$

No wiki note, ADR, or theorem is admitted to green operational status without:
1. Exact file digest (`sha256sum`).
2. Jujutsu commit and operation ID binding.
3. Sovereign verification receipts signed by Codex and Claude.
4. Continuous check by `tools/uos doctor` and `tools/uos gate G-CROSS-LANG`.
