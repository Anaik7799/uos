---
trigger: always_on
---

# 20260905-1739- UOS Knowledge Management, Wiki & ZK Contract

## Contract Invariants

1. **KM Triad Unification**:
   - Hermes Wiki (`engines/hermes/modules/hermes_wiki`) governs AST parsing, Gospel contracts, transclusion, vector similarity, and TyXML rendering.
   - ZigVM Zettelkasten (`/home/an/dev/ver/zigvm/docs/zk/`) governs architectural decision records (`ADR-001` through `ADR-016`) and Maps of Content (`MOC`).
   - C3I Living Ontology (`/home/an/dev/ver/c3i/docs/`) governs STAMP/STPA safety lattices and 13D trace coordinates.

2. **Graphene Policy**:
   - **Graphene is not required.** All 2D vector geometry, path math, and graph operations are provided in pure Erlang/Gleam or Hermes OCaml.
   - Zero-Muda strictly forbids Bevy and Graphite foreign libraries and NIFs.

3. **Mandatory Timestamping**:
   - All newly generated documentation, ADRs, wiki pages, and journals MUST bear the canonical `YYYYMMDD-HHSS-` timestamp prefix.

4. **Bidirectional Wiki Tags**:
   - Articles must declare standardized tags: `#fractal-l0`..`#fractal-l9`, `#zk-adr`, `#zk-moc`, `#formal-lean4`, `#stamp-stpa`, `#c3i-control`, `#zero-muda`.
