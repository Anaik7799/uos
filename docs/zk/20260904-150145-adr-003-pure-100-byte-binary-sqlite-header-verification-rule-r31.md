---
id: dcc12eca-1771-c477-e82e-dc4024c17fea
status: draft
last_verified: 2026-09-04
verified_by: agent
---
# ADR-003: Pure 100-Byte Binary SQLite Header Verification (Rule R31)

- **Tailscale Web FQDN**: [http://nas-1.tail55d152.ts.net:4100/docs/zk/20260904-150145-adr-003-pure-100-byte-binary-sqlite-header-verification-rule-r31.md](http://nas-1.tail55d152.ts.net:4100/docs/zk/20260904-150145-adr-003-pure-100-byte-binary-sqlite-header-verification-rule-r31.md)
- **Fractal Coordinates**: `#fractal-l3` `#fractal-l2`
- **Knowledge Tags**: `#rocha-semiotics` `#cybernetics` `#km-triad` `#zk-adr` `#zero-muda` `#tailscale-web`
- **Transclusions**: `[[zk:20260905-1801-moc-uos-unified-master]]` `[[wiki:20260905-1801-uos-zk-km-corpus-index]]`

_Decision record (ADR) — captured in the Zettelkasten as part of the SDLC/SRE loop._

## Context (as-is)

File size heuristics (>150KB) failed to verify SQLite database integrity, while spawning sqlite3 subprocesses inside NIF violates Rule R31.

## Decision (to-be)

Read the first 100 bytes of the evidence store directly in pure OCaml binary mode, asserting format magic SQLite format 3 and WAL mode bytes 0x02/0x02.

## Agent reasoning

Pure functional binary inspection guarantees zero side-effects, zero subprocess spawning, and mathematically verified format integrity.

## Criteria · Architecture

Pure OCaml check_sqlite_header in c3i_ocaml_bridge.ml with binary in_channel read

## Criteria · Test

Verified via ocaml_parity_check returning frozen_reference_intact: true on live evidence_store.sqlite.

## Criteria · Docs

Documented in Section 22.3 of master design plan and operational catalogue CAP-L5-09.

## Tradeoffs

Verifies header magic and WAL mode without full page btree traversal; leaves table-level checksumming to external verification tasks.

#decision #adr

---

## Navigation & Backlinks
- **Zettelkasten Master MOC**: [`docs/zk/20260905-1801-moc-uos-unified-master.md`](http://nas-1.tail55d152.ts.net:4100/zk)
- **Hermes Wiki Corpus Index**: [`docs/wiki/20260905-1801-uos-zk-km-corpus-index.md`](http://nas-1.tail55d152.ts.net:4100/wiki)
- **Review Tome**: [`docs/design/20260905-1845-uos-wiki-zk-km-synthesis-review-tome.md`](http://nas-1.tail55d152.ts.net:4100/docs/design/20260905-1845-uos-wiki-zk-km-synthesis-review-tome.md)
