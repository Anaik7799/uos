---
id: 0df52af1-fdc0-54d4-7069-9b2ed299d308
title: "Sa-plan, web, wiki, and ZK pipeline observability"
type: evidence
status: evergreen
tags: [sa-plan, observability, performance, bonsai, wiki, zettelkasten]
created: 20260804-125557
last_verified: 2026-08-04
verified_by: agent
next_review: 2026-08-11
---

# Sa-plan, web, wiki, and ZK pipeline observability

- **Tailscale Web FQDN Link**: [http://nas-1.tail55d152.ts.net:4100/zk/20260804-125557-sa-plan-pipeline-observability.md](http://nas-1.tail55d152.ts.net:4100/zk/20260804-125557-sa-plan-pipeline-observability.md)
- **Fractal Coordinates**: `#fractal-l0` through `#fractal-l9`
- **Knowledge Tags**: `#rocha-semiotics` `#cybernetics` `#km-triad` `#zk-adr` `#zero-muda`
- **Transclusions**: `[[zk:20260905-1801-moc-uos-unified-master]]` `[[wiki:20260905-1801-uos-zk-km-corpus-index]]`


The task-15 implementation establishes three correlated, report-only timing
surfaces without granting telemetry task or gate authority:

1. Sa-plan measures decode, normalization, validation, Store open, durable
   dispatch/serialization, Store close, and total request time.
2. Dream adds `X-Zigvm-Request-Id` and `Server-Timing` to every response; the
   overview and Bonsai paths split model work from serialization.
3. The existing journal bundle pipeline now distinguishes Markdown discovery,
   Zettelkasten model construction, wiki page/cache work, rendering, and
   publication/fixity.

The cold-path observation is unambiguous: `Docs_wiki.build` consumed 20,211 ms
for 527 notes, while discovery was 1 ms, acquisition 4 ms, wiki page extraction
0 ms, render 70 ms, and publication/fixity 114 ms. The current ZK implementation
declares `O(notes^2 + edges)` complexity because backlink and unlinked-mention
analysis scans note pairs. The immediate warm cache reduced the earlier bundle
run to 172 ms; the durable improvement is an incremental reverse-edge and title
mention index, not faster file reads.

## Relations

- implementation-journal: [[20260804-125557-sa-plan-pipeline-benchmark-journal]]
- prior-impact-journal: [[20260804-121012-sa-plan-remaining-impact-journal]]
- plan-of-record: [[2026-08-04-0936-infranodus-fractal-closure]]
- architecture: [[20260725-zk-wiki-system-architecture]]
- command-domain: [[SA_PLAN_CLI_DOMAIN]]
- playwright-control: [[PLAYWRIGHT_OCAML_ONTOLOGY]]

## Suggested improvement order

1. Build backlinks by reversing explicit outlinks in one pass.
2. Replace pairwise title scans with an indexed multi-pattern mention pass.
3. Parse `link_contexts` once per source note and reuse it for every backlink.
4. Cache immutable per-note parse/render values by SHA-256 and recompute only
   changed notes plus their affected reverse neighbors.
5. Split the live Bonsai bootstrap model from the large graph snapshot and
   serve immutable generated assets with content-addressed caching.

The expected journal route is
<http://vm-1.tail55d152.ts.net:8088/docs/20260804-125557-sa-plan-pipeline-benchmark-journal.html>.
Its state is `Unavailable_observed` until an existing compatible OCaml route
verifier checks the title and content identity.

## Resolution addendum

The indexed backlink/Aho-Corasick path, immutable render context, bounded Eio
rendering, and sensitivity evidence are implemented. The original 125.15 s
internal observation is now 9.42 s with exact old/new link and page-byte
equality. See [[20260804-wiki-zk-parallel-pipeline]] and
[[20260804-wiki-zk-pipeline-benchmark]]. The remaining superlinear stage is
render-context analysis, not unlinked-reference construction.

---

### Navigation & Knowledge Triad
- **Master ZK MOC**: [http://nas-1.tail55d152.ts.net:4100/zk](http://nas-1.tail55d152.ts.net:4100/zk)
- **Hermes Wiki Corpus Index**: [http://nas-1.tail55d152.ts.net:4100/wiki](http://nas-1.tail55d152.ts.net:4100/wiki)
- **Review Tome**: [http://nas-1.tail55d152.ts.net:4100/docs/design/20260905-1845-uos-wiki-zk-km-synthesis-review-tome.md](http://nas-1.tail55d152.ts.net:4100/docs/design/20260905-1845-uos-wiki-zk-km-synthesis-review-tome.md)
