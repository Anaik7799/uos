---
id: 7757cf28-c882-7f79-7e1d-4f8c6c7c54f3
status: draft
last_verified: 2026-09-04
verified_by: agent
---
# ADR-004: Supervised Persistent Zenoh Session Lifecycle in MoZ Client

- **Tailscale Web FQDN**: [http://nas-1.tail55d152.ts.net:4100/docs/zk/20260904-150151-adr-004-supervised-persistent-zenoh-session-lifecycle-in-moz-client.md](http://nas-1.tail55d152.ts.net:4100/docs/zk/20260904-150151-adr-004-supervised-persistent-zenoh-session-lifecycle-in-moz-client.md)
- **Fractal Coordinates**: `#fractal-l6` `#fractal-l3`
- **Knowledge Tags**: `#rocha-semiotics` `#cybernetics` `#km-triad` `#zk-adr` `#zero-muda` `#tailscale-web`
- **Transclusions**: `[[zk:20260905-1801-moc-uos-unified-master]]` `[[wiki:20260905-1801-uos-zk-km-corpus-index]]`

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

---

## Navigation & Backlinks
- **Zettelkasten Master MOC**: [`docs/zk/20260905-1801-moc-uos-unified-master.md`](http://nas-1.tail55d152.ts.net:4100/zk)
- **Hermes Wiki Corpus Index**: [`docs/wiki/20260905-1801-uos-zk-km-corpus-index.md`](http://nas-1.tail55d152.ts.net:4100/wiki)
- **Review Tome**: [`docs/design/20260905-1845-uos-wiki-zk-km-synthesis-review-tome.md`](http://nas-1.tail55d152.ts.net:4100/docs/design/20260905-1845-uos-wiki-zk-km-synthesis-review-tome.md)
