---
id: c4999658-fedd-1c5f-e49d-e30bd1cc8338
status: draft
last_verified: 2026-09-04
verified_by: agent
---
# ADR-005: Dual-Host Unified Operational System Topology and Live Tailnet Wiki Integration

- **Tailscale Web FQDN**: [http://nas-1.tail55d152.ts.net:4100/docs/zk/20260904-151412-adr-005-dual-host-unified-operational-system-topology-and-live-tailnet-wiki-integration.md](http://nas-1.tail55d152.ts.net:4100/docs/zk/20260904-151412-adr-005-dual-host-unified-operational-system-topology-and-live-tailnet-wiki-integration.md)
- **Fractal Coordinates**: `#fractal-l7` `#fractal-l4`
- **Knowledge Tags**: `#rocha-semiotics` `#cybernetics` `#km-triad` `#zk-adr` `#zero-muda` `#tailscale-web`
- **Transclusions**: `[[zk:20260905-1801-moc-uos-unified-master]]` `[[wiki:20260905-1801-uos-zk-km-corpus-index]]`

_Decision record (ADR) — captured in the Zettelkasten as part of the SDLC/SRE loop._

## Context (as-is)

ZigVM Functional and SRE catalogue and live wiki running on vm-1 required architectural incorporation and empirical route verification into the Unified Operational System on nas-1.

## Decision (to-be)

Incorporate ZIGVM_FUNCTIONAL_SRE_CATALOG.md as peer runtime authority, promote Tailnet wiki route from Unavailable_observed to Verified_active, wire telemetry into CEPAF Gleam router, and mirror across all 5 design directories.

## Agent reasoning

Empirical verification confirmed that vm-1:8088 serves valid HTML and telemetry (HEAD 00780de6, 1177 laws, 100% readiness). Establishing a dual-host operational topology enables distributed verification while preserving fail-closed zero-trust invariants.

## Criteria · Test

Empirical HTTP probes from nas-1 returning 200 OK across /wiki, /, /ops, /health. CEPAF Gleam test suite passes 9,767 tests (0 failures). Live /api/v1/zigvm/sre endpoint verified.

## Criteria · Docs

ZIGVM_FUNCTIONAL_SRE_CATALOG.md, 2026-09-04-unified-operational-system-design-plan.md Section 25, and 2026-09-04-source-backed-operational-catalogue.md Section 5.

## Tradeoffs

Requires Tailscale mesh connectivity between nas-1 and vm-1; relies on supervised fallbacks if either host becomes unreachable.

#decision #adr

---

## Navigation & Backlinks
- **Zettelkasten Master MOC**: [`docs/zk/20260905-1801-moc-uos-unified-master.md`](http://nas-1.tail55d152.ts.net:4100/zk)
- **Hermes Wiki Corpus Index**: [`docs/wiki/20260905-1801-uos-zk-km-corpus-index.md`](http://nas-1.tail55d152.ts.net:4100/wiki)
- **Review Tome**: [`docs/design/20260905-1845-uos-wiki-zk-km-synthesis-review-tome.md`](http://nas-1.tail55d152.ts.net:4100/docs/design/20260905-1845-uos-wiki-zk-km-synthesis-review-tome.md)
