---
id: 20260904-functional-sre-catalog
title: "ZigVM functional, SDLC, SRE, and verification catalogue"
type: note
status: draft
tags: [zigvm, otp, sdlc, sre, testing, mcp, ooda, safety, catalog]
created: 20260904
verified_by: codex-root
---

# ZigVM functional, SDLC, SRE, and verification catalogue

- **Tailscale Web FQDN Link**: [http://nas-1.tail55d152.ts.net:4100/zk/20260904-zigvm-functional-sre-catalog.md](http://nas-1.tail55d152.ts.net:4100/zk/20260904-zigvm-functional-sre-catalog.md)
- **Fractal Coordinates**: `#fractal-l0` through `#fractal-l9`
- **Knowledge Tags**: `#rocha-semiotics` `#cybernetics` `#km-triad` `#zk-adr` `#zero-muda`
- **Transclusions**: `[[zk:20260905-1801-moc-uos-unified-master]]` `[[wiki:20260905-1801-uos-zk-km-corpus-index]]`


The source-backed operator catalogue is
[[ZIGVM_FUNCTIONAL_SRE_CATALOG]]. It groups the complete S1--S33 runtime map,
the OCaml harness control plane, MCP ingress, Sa-plan, forecast/SLO paths,
testing and admission requirements, and agent/skill references without
collapsing `implemented`, `planned`, `report-only`, and
`Unavailable_observed` into a single status.

## Relations

- runtime authority: [[CODEBASE_MAP]]
- lifecycle authority: [[SDLC_SRE_PROCESS]]
- control topology: [[FORECAST_CONTROL_PLANE]]
- testing doctrine: [[TESTING_DISCIPLINES]]
- safety: [[SAFETY_ANALYSIS]]
- agent operation: [[AGENT_HANDOVER]]
- durable record: [[Journal Index]]
- implementation context: [[20260903-072500-fractal-system-improvement-analysis]]

## Control relation

```text
Zig runtime -> normalized evidence -> OCaml Db actor -> read-only projections
Agent/MCP/CLI -> Sa-plan + Zero-Trust gate -> bounded authorised operation
```

The expected Tailnet wiki endpoint is <http://vm-1.tail55d152.ts.net:8088/wiki>.
It is a discovery link, not a verified publication claim in this note.

---

### Navigation & Knowledge Triad
- **Master ZK MOC**: [http://nas-1.tail55d152.ts.net:4100/zk](http://nas-1.tail55d152.ts.net:4100/zk)
- **Hermes Wiki Corpus Index**: [http://nas-1.tail55d152.ts.net:4100/wiki](http://nas-1.tail55d152.ts.net:4100/wiki)
- **Review Tome**: [http://nas-1.tail55d152.ts.net:4100/docs/design/20260905-1845-uos-wiki-zk-km-synthesis-review-tome.md](http://nas-1.tail55d152.ts.net:4100/docs/design/20260905-1845-uos-wiki-zk-km-synthesis-review-tome.md)
