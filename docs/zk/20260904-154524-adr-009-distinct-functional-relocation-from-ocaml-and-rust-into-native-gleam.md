---
id: 05b98af3-3805-0cad-f719-bd03ca7259f9
status: draft
last_verified: 2026-09-04
verified_by: agent
---
# ADR-009: Distinct Functional Relocation from OCaml and Rust into Native Gleam

- **Tailscale Web FQDN**: [http://nas-1.tail55d152.ts.net:4100/docs/zk/20260904-154524-adr-009-distinct-functional-relocation-from-ocaml-and-rust-into-native-gleam.md](http://nas-1.tail55d152.ts.net:4100/docs/zk/20260904-154524-adr-009-distinct-functional-relocation-from-ocaml-and-rust-into-native-gleam.md)
- **Fractal Coordinates**: `#fractal-l2` `#fractal-l1`
- **Knowledge Tags**: `#rocha-semiotics` `#cybernetics` `#km-triad` `#zk-adr` `#zero-muda` `#tailscale-web`
- **Transclusions**: `[[zk:20260905-1801-moc-uos-unified-master]]` `[[wiki:20260905-1801-uos-zk-km-corpus-index]]`

_Decision record (ADR) — captured in the Zettelkasten as part of the SDLC/SRE loop._

## Context (as-is)

Following the unification of nas-1, a granular audit was conducted to distinguish which specific components are migrated to pure native Gleam from OCaml versus from Rust, and which components remain in their respective native languages as NIFs.

## Decision (to-be)

Formally execute the dual-source migration: from OCaml to Gleam (Dream HTTP router -> Wisp port 4100, agent workers -> OTP supervisor trees, dependability clock -> Erlang timers, Markdown reports -> Gleam templates, Zenoh outbox -> Moz actor); from Rust to Gleam (planning daemon -> Gleam task manager, c3i system health -> lockless ETS cache, ferriskey RBAC -> Gleam decoders, env checker -> Gleam podman UDS client); retain formal proofs, autodiff, SMT sandboxing in OCaml NIFs, and TPM/storage in Rust NIFs.

## Agent reasoning

Migrating coordination and state machines to Gleam leverages BEAM green threads, fault-tolerant supervision, and immutability, while retaining heavy symbolic computation in OCaml NIFs and low-level hardware access in Rust NIFs eliminates 4 interpreter runtimes and achieves Zero Muda.

## Criteria · Architecture

Gleam supervisor tree managing Wisp router, task manager, and ETS cache; calling OCaml NIFs (c3i_ocaml, stan_ad, z3_sandbox) and Rust NIFs (rusty_vault, nas_setup, rule_engine) over dirty CPU schedulers.

## Criteria · Test

9,767 Gleam tests passing, all 6 port 4100 endpoints returning 200 OK under 1.2ms, C-ABI embedded NUL trap validated fail-closed, OCaml runtime lock acquire/release verified.

## Criteria · Docs

Documented in 2026-09-04-unified-operational-system-design-plan.md (Section 28.3), 2026-09-04-claude-codex-review-dossier.md (Section 14), and 2026-09-04-source-backed-operational-catalogue.md (Section 6).

## Tradeoffs

Requires maintaining type-accurate Gleam bindings for NIF interfaces; ensures memory-safe isolation via process sandboxes and dirty schedulers.

## Alternatives — what else could be done

Retaining separate background daemons for Dream and planning_daemon was rejected due to inter-process socket latency and operational drift.

#decision #adr

---

## Navigation & Backlinks
- **Zettelkasten Master MOC**: [`docs/zk/20260905-1801-moc-uos-unified-master.md`](http://nas-1.tail55d152.ts.net:4100/zk)
- **Hermes Wiki Corpus Index**: [`docs/wiki/20260905-1801-uos-zk-km-corpus-index.md`](http://nas-1.tail55d152.ts.net:4100/wiki)
- **Review Tome**: [`docs/design/20260905-1845-uos-wiki-zk-km-synthesis-review-tome.md`](http://nas-1.tail55d152.ts.net:4100/docs/design/20260905-1845-uos-wiki-zk-km-synthesis-review-tome.md)
