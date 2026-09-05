---
id: hermes-imported-20260729-zk-audit-coherence-maintenance
status: published
type: reference
generated: false
allow_example_links: true
migrated_from: zigvm/docs/journal/20260729-zk-audit-coherence-maintenance.md
status: published
last_verified: 2026-07-29
verified_by: agent
ktype: source
maturity: incubating
domain: imported-journals
created: 2026-08-08
---
# ZK steady-state maintenance №1 — zk-audit-coherence (2026-07-29)

*The first maintenance journal under the closure rule of
[[journal--20260729-1056-zk-wiki-mcp-ai-architecture-recommendations]] §9.14:
the program is sealed; post-close ZK activity documents itself separately,
linking back.* Operating skill: [[skills--zk-knowledge-base--skill]].
#zettelkasten #maintenance #journal

## Trigger

The user asked to *verify the wiki-audit gate is green on the final state*. It
was green in the weak sense (exit 0) but reported `HEALTHY-WITH-WARNINGS` with
its own `NEXT-BEST-ACTION = fix-broken-links`. Honoring the audit's own decision
output became the `zk-audit-coherence` slice — two cycles, both closed under the
CAST-zk5 worktree-gate protocol.

## Cycle 1 — findings and fixes (commit `9d1bdc9`, worktree gate run 2565 ok)

1. **Real pre-existing renderer bug, exposed at scale by the community MoCs**:
   `inline_no_code` HTML-escapes the line *before* matching `[[..]]`, so every
   `[[Title & X]]` target arrived as `&amp;` and resolution silently failed
   (`znorm` keeps `-amp-`). Fixed by unescaping the *target* for resolution
   (display stays HTML-escaped). A second bug surfaced mid-fix:
   `Str.global_replace` between `matched_group` calls clobbers the match state
   (`Invalid_argument`) — groups are now extracted first.
   LAW `amp-title-resolves`; mutant MUT-AH-1 killed.
2. **MoC links hardened to `[[slug|Title]]`** — resolver-safe target regardless
   of title characters, pretty display. LAW `moc-slug-links`; MUT-AH-2 killed.
3. **Audit↔projection coherence**: the wiki-audit's orphan detector counted
   episodic notes (intentional non-graph citizens under the §8.2-M projection
   law) as defects forever — now excluded, so the autonomic loop stops paging
   on by-design state.
4. **Contract drift in the suite**: `real:mocs-are-top-degree` encoded the
   superseded global-degree heuristic and had passed only by coincidence until
   the Fractal Atlas reshaped the graph; rewritten as
   `real:mocs-are-community-entry-points` (top-degree *within its own
   community*, ties → slug).
5. **Garbage collection**: the superseded MoCs deleted per the §9.11 open tail;
   the [[20260729-fractal-atlas]] stops hard-linking churning MoC slugs (prose
   pointer instead — the audit caught exactly why hard links there are wrong);
   the three new system-principles docs ([[system-fractal-principles]] ·
   [[smtml-fractal-analysis]] · the other session's fresh work) linked in.

## Cycle 2 — the self-referential injection (commit `841fc59`, gate run 2578 ok)

The amp-fix *description itself* — literal `[[Title & X]]` in the immutable
record_cycle evidence notes and the commit message — propagated as pseudo-links
into three machine-quoting surfaces: this front's own episodic closure note and
the external C3I `journal.md`/`slide_deck.md` (which quote recent commits and
cycles; a foreign generator that can never carry the `allow-example-links`
marker, quoting rows that can never be edited). The audit's broken-link check
now scopes out machine-quoting surfaces — `is_episodic` pages and
`Generated:`-stamped artifacts — with the rationale inline: *machine-quoted
text is not curated hypertext and must not page the autonomic loop.*

## End state (verified)

`--wiki-audit`: **HEALTHY — 0 broken links, 0 orphans, 0 open self-repair
tasks, vitality thriving, NEXT-BEST-ACTION = steady**, re-confirmed after the
push and the service restarts (`zigvm-wiki` + backend on the fixed binary).
Suite green (89 docs-wiki checks), full gate green in the worktree on both
commits, both cycles Zero-Trust-admitted, episodic notes self-written, pushed
to `origin/master` (`43e7003`). Mutation trail in [[mutation-log]].

## Lessons this pass added to the ledger

- **Escape-order is a resolution semantic**: any pipeline that escapes before
  it links must unescape link *targets* — and the corpus had silently carried
  broken `&`-titles since the beginning; only linking them at scale surfaced it.
- **Coincidental laws rot**: a law that passes for the wrong reason
  (`mocs-are-top-degree`) is a false guarantee waiting for a graph reshape —
  the audit, not the suite, caught it.
- **Evidence text is link-hostile**: immutable quoted surfaces (episodic notes,
  generated digests) will eventually quote link syntax; scope them out of
  hypertext checks rather than sanitizing history.

## Appendix — deployment & use-case snapshot (2026-07-29, post-maintenance)

The state-of-the-system answer as given to the user, recorded so the snapshot
is queryable like everything else.

**Deployment in this environment.** Served: `zigvm-wiki.service` (Riot front,
:8088, Tailscale-reachable) + `zigvm-wiki-backend.service` (:8089), systemd
`--user` with linger, running the current binary (feature-by-feature verified,
main journal §9.13). Kept current: `zigvm-zk-maintain.timer`, 30-min cadence
(`--wiki-audit --vector-index --zk-moc --zk-temporal 12`); the audit's
autonomic loop self-opens/closes repair tasks — currently HEALTHY / steady /
0 defects. Agent access: the `zk_*` MCP tool family (h-mcp-staleness
fail-closes stale servers; reconnect after rebuilds) + always-current CLI
mirrors. State: SQLite (`note_vectors` 196n/12h/186c/7.9k blocks,
`zk_edge_history`, audit tables); notes on `origin/master`. Governance: 3 STPA
packets, [[skills--zk-knowledge-base--skill]] + [[skills--wiki-design--skill]],
the SDLC/SRE ZK section.

**UI-bearing features** (all live on :8088): contextual-backlink quotes, typed
edge + discourse-type badges, inline transclusion with provenance/error chips,
zkquery live tables, grounded/community/PageRank knowledge cards,
community-grounded Entry points + MoC pages, mention/anomaly panels,
note/block/code search page, episodic pages, and the navigation core
(grouped sidebar incl. skills/proofs/specs, breadcrumbs, prev/next, graph,
tags, serendipity). Non-UI: CLI mirrors, vector persistence, the temporal
miner (an "as-of graph view" is a natural future UI).

**Use cases — deployed here**: agent context retrieval (search→read→walk);
human whole-corpus browsing; structured queries; ADR/decision record-keeping;
automatic episodic memory (self-firing, 11+ harness-written notes);
knowledge-health curation (two healing passes done, all-zero anomalies);
point-in-time archaeology (`--zk-asof`).
**Deployed but dormant** (machinery live, corpus practice pending):
argumentation analysis over `@opposes` and discourse-typed knowledge building —
both light up the moment new ADRs start carrying `type:` frontmatter and
`@supports`/`@opposes` edges, zero code needed.
**Deliberately not deployed**: LLM-refined MoCs (optional Stratum-C agent pass
by design); parked with triggers — SAC-incremental builds, Irmin/MRDT storage,
neural embeddings (main journal §8.2-I).
