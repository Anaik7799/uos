---
id: e9bc7d52-28f9-dd4b-ae11-6a0613365ec4
status: draft
last_verified: 2026-09-04
verified_by: agent
---
# ADR-002: Embedded NUL Ingress Trap and Memory Allocation Containment

_Decision record (ADR) — captured in the Zettelkasten as part of the SDLC/SRE loop._

## Context (as-is)

Erlang binary terms can contain embedded NUL bytes which standard C-string functions truncate, silently dropping subsequent payload instructions or emergency stops.

## Decision (to-be)

Scan all binary inputs with memchr for embedded NUL characters and return -2 fail-closed. Validate all strdup and enif_make_new_binary allocations.

## Agent reasoning

Truncation of binary terms on NUL characters is a critical security vulnerability that allows evasion of high-salience safety controls.

## Criteria · Architecture

C-ABI Erlang NIF wrapper in c3i_ocaml_nif.c get_string_or_binary and make_binary_string

## Criteria · Test

Verified with Erlang binary <<"mesh_running=true,watchdog=true", 0, ",e_stop=true">> returning FAIL_CLOSED: embedded NUL character detected.

## Criteria · Docs

Documented in Section 22.1 of master design plan and operational catalogue CAP-C1-03.

## Tradeoffs

Slight additional pass over input binary bytes with memchr; negligible performance impact on 4KB buffers.

#decision #adr