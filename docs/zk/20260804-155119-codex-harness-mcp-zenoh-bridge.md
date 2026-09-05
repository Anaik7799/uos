---
id: c74c0f90-6d42-b28f-71b3-bbcb6d734a62
title: MCP control plus Zenoh event transport for the Codex-harness bridge
type: architecture-note
status: draft
created: 20260804-155119
tags: [mcp, zenoh, sa-plan, codex, control-plane, event-sourcing]
relationships:
  - supports: 20260804-132421-ooda-sa-plan-control-plane-journal
  - elaborates: 20260804-155119-codex-harness-mcp-zenoh-bridge-journal
  - governed-by: docs/AUTONOMOUS_RUNBOOK.md
verified_by: agent
---

# MCP control plus Zenoh event transport

- **Tailscale Web FQDN Link**: [http://nas-1.tail55d152.ts.net:4100/zk/20260804-155119-codex-harness-mcp-zenoh-bridge.md](http://nas-1.tail55d152.ts.net:4100/zk/20260804-155119-codex-harness-mcp-zenoh-bridge.md)
- **Fractal Coordinates**: `#fractal-l0` through `#fractal-l9`
- **Knowledge Tags**: `#rocha-semiotics` `#cybernetics` `#km-triad` `#zk-adr` `#zero-muda`
- **Transclusions**: `[[zk:20260905-1801-moc-uos-unified-master]]` `[[wiki:20260905-1801-uos-zk-km-corpus-index]]`


Use MCP as the canonical typed command/query channel and Zenoh as an optional
asynchronous event, progress, receipt and telemetry channel. Both transports
terminate in the same OCaml command/event algebra. Only a production-rule-
mediated Sa-plan Store transaction can change task state.

The live assessment verified MCP protocol behavior, OODA/DB/rule laws,
Sa-plan durability and two independent Zenoh round-trips. It also found that
missing Zenoh values and duplicate publications are accepted, no durable
Zenoh-to-Codex event cursor exists, MCP remote identity authentication is
absent, and OODA cycle closure is not atomic with Sa-plan completion.

The honest contract is at-least-once transport plus exactly-once durable state
transitions derived from idempotency, expected versions, fencing, transactions
and acknowledgement cursors. Zenoh publication and MCP prose are never
evidence by themselves.

Full evidence: [[20260804-155119-codex-harness-mcp-zenoh-bridge-journal]].


---

### Navigation & Knowledge Triad
- **Master ZK MOC**: [http://nas-1.tail55d152.ts.net:4100/zk](http://nas-1.tail55d152.ts.net:4100/zk)
- **Hermes Wiki Corpus Index**: [http://nas-1.tail55d152.ts.net:4100/wiki](http://nas-1.tail55d152.ts.net:4100/wiki)
- **Review Tome**: [http://nas-1.tail55d152.ts.net:4100/docs/design/20260905-1845-uos-wiki-zk-km-synthesis-review-tome.md](http://nas-1.tail55d152.ts.net:4100/docs/design/20260905-1845-uos-wiki-zk-km-synthesis-review-tome.md)
