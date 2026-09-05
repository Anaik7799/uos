---
id: a9aad233-4198-e7b4-5c86-91de3d079a43
title: "Indexed and bounded-parallel wiki/Zettelkasten processing"
type: atomic
status: evergreen
tags: [wiki, zettelkasten, performance, eio, aho-corasick, quint, smtml]
created: 20260804-125532
last_verified: 2026-08-04
verified_by: codex
---

# Indexed and bounded-parallel wiki/Zettelkasten processing

- **Tailscale Web FQDN Link**: [http://nas-1.tail55d152.ts.net:4100/zk/20260804-wiki-zk-parallel-pipeline.md](http://nas-1.tail55d152.ts.net:4100/zk/20260804-wiki-zk-parallel-pipeline.md)
- **Fractal Coordinates**: `#fractal-l0` through `#fractal-l9`
- **Knowledge Tags**: `#rocha-semiotics` `#cybernetics` `#km-triad` `#zk-adr` `#zero-muda`
- **Transclusions**: `[[zk:20260905-1801-moc-uos-unified-master]]` `[[wiki:20260905-1801-uos-zk-km-corpus-index]]`


Wiki/ZK speedup is a two-level problem. First remove repeated global work:
invert explicit edges once, scan all title patterns with one Aho-Corasick
automaton, and prepare one immutable corpus render context. Only then dispatch
independent page rendering through a bounded Eio domain pool.

The scheduler uses guided self-scheduling. A successful CAS claims
`ceil(remaining/workers)` contiguous coordinates; workers write preallocated
slots; the ordered join requires exactly one visit per coordinate. Four workers
are the measured knee on the current host. Eight and nine regress, so available
core count is not a valid default by itself.

The final interpretation is admitted only when the retained all-pairs link
oracle returns no mismatch and every parallel page is byte-identical to the
sequential renderer. Quint checks the bounded concurrency shape, SMTML refutes
a bad observed visit vector, Rete proves report/gate isolation, and Stan remains
advisory. NUMA placement and hierarchical stealing remain unimplemented until
an allowed OCaml topology boundary and cross-socket evidence exist.

## Relations

- implementation journal: [[20260804-infranodus-design-superset-journal]]
- benchmark dashboard: [[20260804-wiki-zk-pipeline-benchmark]]
- earlier diagnosis: [[20260804-125557-sa-plan-pipeline-observability]]
- C3I admission: [[20260804-131604-sa-plan-c3i-admission-journal]]
- architecture: [[20260725-zk-wiki-system-architecture]]
- ontology: [[ONTOLOGY]]
- safety control: [[SAFETY_ANALYSIS]]

---

### Navigation & Knowledge Triad
- **Master ZK MOC**: [http://nas-1.tail55d152.ts.net:4100/zk](http://nas-1.tail55d152.ts.net:4100/zk)
- **Hermes Wiki Corpus Index**: [http://nas-1.tail55d152.ts.net:4100/wiki](http://nas-1.tail55d152.ts.net:4100/wiki)
- **Review Tome**: [http://nas-1.tail55d152.ts.net:4100/docs/design/20260905-1845-uos-wiki-zk-km-synthesis-review-tome.md](http://nas-1.tail55d152.ts.net:4100/docs/design/20260905-1845-uos-wiki-zk-km-synthesis-review-tome.md)
