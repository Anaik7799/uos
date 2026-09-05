---
id: 7757cf28-c882-7f79-7e1d-4f8c6c7c54f3
status: draft
last_verified: 2026-09-04
verified_by: agent
---
# ADR-004: Supervised Persistent Zenoh Session Lifecycle in MoZ Client

_Decision record (ADR) — captured in the Zettelkasten as part of the SDLC/SRE loop._

## Context (as-is)

Prior implementation called zenoh.open on every request and query, causing high session teardown overhead and connection churn.

## Decision (to-be)

Store session: Option(zenoh.Session) inside MoZClientState, provide with_session, ensure_session, and invalidate_session, and reuse active session across calls.

## Agent reasoning

Persistent supervised sessions provide amortized zero connection setup latency, respect circuit-breaker backoff, and cleanly isolate transport faults.

## Criteria · Architecture

Gleam MoZ client state in src/cepaf_gleam/moz/client.gleam with Option(zenoh.Session)

## Criteria · Test

Verified in Gleam test suite with 9,767 passing tests and new lifecycle unit tests.

## Criteria · Docs

Documented in Section 22.4 of master design plan and operational catalogue CAP-MOZ-01..04.

## Tradeoffs

Requires explicit session invalidation when network errors occur; handled cleanly in send_request and send_query failure paths.

#decision #adr