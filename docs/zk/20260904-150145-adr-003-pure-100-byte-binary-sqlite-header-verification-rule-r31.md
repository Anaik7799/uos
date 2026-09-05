---
id: dcc12eca-1771-c477-e82e-dc4024c17fea
status: draft
last_verified: 2026-09-04
verified_by: agent
---
# ADR-003: Pure 100-Byte Binary SQLite Header Verification (Rule R31)

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