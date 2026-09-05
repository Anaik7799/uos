---
id: a3a5e66d-18c5-ae83-c283-f9f7acfeca5d
status: draft
last_verified: 2026-09-04
verified_by: agent
---
# ADR-001: Closed RETE Fact Schema and Strict Typing Invariant

- **Tailscale Web FQDN**: [http://nas-1.tail55d152.ts.net:4100/docs/zk/20260904-150139-adr-001-closed-rete-fact-schema-and-strict-typing-invariant.md](http://nas-1.tail55d152.ts.net:4100/docs/zk/20260904-150139-adr-001-closed-rete-fact-schema-and-strict-typing-invariant.md)
- **Fractal Coordinates**: `#fractal-l5` `#fractal-l1`
- **Knowledge Tags**: `#rocha-semiotics` `#cybernetics` `#km-triad` `#zk-adr` `#zero-muda` `#tailscale-web`
- **Transclusions**: `[[zk:20260905-1801-moc-uos-unified-master]]` `[[wiki:20260905-1801-uos-zk-km-corpus-index]]`

_Decision record (ADR) — captured in the Zettelkasten as part of the SDLC/SRE loop._

## Context (as-is)

Codex Cycles 3 and 4 audit identified permissive fact parsing where unknown keys were accepted and malformed values silently coerced to false.

## Decision (to-be)

Enforce a strict closed schema allowing only watchdog, mesh_running, e_stop, high_drift, and divergent, with literal boolean validation and duplicate-key rejection fail-closed.

## Agent reasoning

Safety gates must adhere to fail-closed zero-trust invariants; unrecognized fact keys could conceal critical state or bypass emergency stop rules.

## Criteria · Architecture

OCaml 5.5.0 c3i_ocaml_bridge.ml validate_rete_kvs and parse_simple_kv

## Criteria · Test

Verified via Gleam test suite (test_unknown_key_fail_closed, test_invalid_boolean_fail_closed) and direct Erlang NIF probes.

## Criteria · Docs

Documented in 2026-09-04-source-backed-operational-catalogue.md and master design plan section 22.

## Tradeoffs

Requires producers to adhere strictly to the declared fact schema; prevents ad-hoc field injection without explicit schema evolution.

#decision #adr

---

## Navigation & Backlinks
- **Zettelkasten Master MOC**: [`docs/zk/20260905-1801-moc-uos-unified-master.md`](http://nas-1.tail55d152.ts.net:4100/zk)
- **Hermes Wiki Corpus Index**: [`docs/wiki/20260905-1801-uos-zk-km-corpus-index.md`](http://nas-1.tail55d152.ts.net:4100/wiki)
- **Review Tome**: [`docs/design/20260905-1845-uos-wiki-zk-km-synthesis-review-tome.md`](http://nas-1.tail55d152.ts.net:4100/docs/design/20260905-1845-uos-wiki-zk-km-synthesis-review-tome.md)
