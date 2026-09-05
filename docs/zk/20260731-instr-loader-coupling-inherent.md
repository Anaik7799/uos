---
id: 20260731-1a57-4c0a-8e11-000000000003
pkm_id: 20260731-instr-loader-coupling-inherent
type: note
status: draft
last_verified: 2026-07-31
verified_by: harness
tags:
---

# S13 instruction ↔ loading/dispatch coupling is inherent, not a layering violation

- **Tailscale Web FQDN Link**: [http://nas-1.tail55d152.ts.net:4100/zk/20260731-instr-loader-coupling-inherent.md](http://nas-1.tail55d152.ts.net:4100/zk/20260731-instr-loader-coupling-inherent.md)
- **Fractal Coordinates**: `#fractal-l0` through `#fractal-l9`
- **Knowledge Tags**: `#rocha-semiotics` `#cybernetics` `#km-triad` `#zk-adr` `#zero-muda`
- **Transclusions**: `[[zk:20260905-1801-moc-uos-unified-master]]` `[[wiki:20260905-1801-uos-zk-km-corpus-index]]`


The `interface_cycle_sweeper` support module reports 17 intra-`src/` `@import`
cycles, several centred on `instr_algebra.zig` importing "upward" into
`beam_loader.zig`, `code_index.zig`, and (test-only) `cli.zig` — against the
linear "dependency spine" sketched in `CLAUDE.md`
(`… → instructions (instr_algebra) → processes/scheduling → loading/dispatch …`).
This note records the verification that the coupling is **domain-inherent and
benign**, so it is not re-litigated as a defect.

## Evidence (verified 2026-07-31)

- **`beam_loader` ↔ `instr_algebra`** — `instr_algebra` uses
  `beam_loader.{Operand, parse, translate, freeProg, computeMd, bsCommandsOf, …}`.
  This is the nature of a bytecode VM: **the loader translates on-disk bytecode
  into the interpreter's instruction/operand form**, and the interpreter
  references those loader-produced types. `CODEBASE_MAP.md` S13 documents this
  directly (E3.12b: `beam_loader.link` + `cli.runMulti` drive cross-module
  dispatch end-to-end).
- **`code_index` ↔ `instr_algebra`** — `instr_algebra` uses
  `code_index.{resolve, load, deleteModule, deinit}` because instruction dispatch
  resolves `module:func/arity → pc` through the code index. Inherent.
- **`cli` ↔ `instr_algebra`** — NOT a production dependency. Every `cli.run`/
  `cli.runMulti`/`cli.link`/`cli.dumpCaps` occurrence in `instr_algebra.zig` is a
  `///` doc-comment describing which loader sets which `Machine` field; the only
  real `@import("cli.zig")` is a **lazy import inside a `test` block** (the
  dump-caps totality law). Test-only.

## Conclusion

Zig legally permits mutual `@import` (comptime references resolve lazily), so
these cycles are not build errors, and `interface_cycle_sweeper` correctly reports
them as **structural coupling facts, not violations**. The `CLAUDE.md` spine is a
pedagogical linear ordering, not a strict DAG; the real instruction↔loading↔
dispatch relationship is legitimately bidirectional. **No refactor is warranted** —
a "no cycles in src/" guard would be wrong here (it would red on correct code), the
same reason `stratum_c_quarantine_auditor` guards the narrower CARDINAL rule (no
Stratum-A core `@import`s `substrate/`) rather than global acyclicity.

Related: `[[CODEBASE_MAP]]` S13; the `stratum-c-quarantine` guard (DIVERGENCE 673);
the `--check-guards` suite (DIVERGENCE 702).

---

### Navigation & Knowledge Triad
- **Master ZK MOC**: [http://nas-1.tail55d152.ts.net:4100/zk](http://nas-1.tail55d152.ts.net:4100/zk)
- **Hermes Wiki Corpus Index**: [http://nas-1.tail55d152.ts.net:4100/wiki](http://nas-1.tail55d152.ts.net:4100/wiki)
- **Review Tome**: [http://nas-1.tail55d152.ts.net:4100/docs/design/20260905-1845-uos-wiki-zk-km-synthesis-review-tome.md](http://nas-1.tail55d152.ts.net:4100/docs/design/20260905-1845-uos-wiki-zk-km-synthesis-review-tome.md)
