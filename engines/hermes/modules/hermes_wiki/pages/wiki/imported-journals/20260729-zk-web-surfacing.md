---
id: hermes-imported-20260729-zk-web-surfacing
status: published
type: reference
generated: false
allow_example_links: true
migrated_from: zigvm/docs/journal/20260729-zk-web-surfacing.md
status: published
last_verified: 2026-07-29
verified_by: agent
ktype: source
maturity: incubating
domain: imported-journals
created: 2026-08-08
---
# ZK web surfacing — every capability, one click away (2026-07-29)

*Feature journal per the closure rule of
[[journal--20260729-1056-zk-wiki-mcp-ai-architecture-recommendations]] §9.14.
Slice `zk-web-surfacing`; design in the session's wiki-vs-zk gap analysis;
operating context [[skills--zk-knowledge-base--skill]] · [[skills--wiki-design--skill]].*
#zettelkasten #wiki #journal

## What landed

The web became the third full VIEW of the ZK kernels (MCP and the CLI being the
others) — pure renderers, all read-only, no new semantics:

- **/docs/anomalies** — the autonomic loop's human face: all ten defect classes
  as linked chips with healing hints, and an explicit "All clear" steady state.
  Backed by the new `anomalies_model` (one derivation, two byte-stable
  encoders — the JSON contract unchanged under the existing shape laws).
- **/docs/query** — the interactive zkquery console (GET form), same
  parse/eval/table path as embedded ```zkquery fences.
- **/docs/timeline** — the bi-temporal browser: commit sparkline (inline SVG),
  as-of edge sets, churn hotspots — served from the timer-refreshed
  `zk_edge_history`, never mined per-request.
- **/docs/currency** — organism vitals: corpus/episodic/vector censuses, last
  audit verdict, per-community MoC freshness (fresh/stale/frozen).
- **Note pages** now carry the grounded-standing chip (⚖ in/out/undec), a
  community chip linking its MoC, and an expandable labelled neighborhood
  (1-hop edges + 2-hop count) — all previously API-only.
- **Search page** gained the semantic section: note/block granularity, kind
  chips (incl. `code`), a PPR graph-ranked strip — degrading gracefully in the
  static export (fetch-fail hides it).
- Footer navigation reaches all four new surfaces from every page.

## Evidence

Laws: board-linkage (every entry a live chip; holes as pairs; all-clear),
query console (rows/named-error/blank-hint), grounded/community/neighborhood
markup on note pages, semantic controls, timeline HALF-OPEN aliveness (gone at
the removal stamp), currency vitals/states, plus the untouched JSON-shape laws
proving the anomalies refactor byte-stable. Mutants MUT-WS-1/2/3 all killed —
MUT-WS-1 only after its first survival exposed the THIRD instance of the
CSS-in-page fixture trap (a bare class token matches the embedded stylesheet);
the standing rule is now recorded: assert the markup form, never the bare
token. Live on :8088: four pages 200, query returns ranked rows, note pages
show g-in/community/neighborhood, currency reads 6 fresh + 2 stale MoCs.
selfcheck-wiki 2060 checks over 202 pages.

## Follow-on candidates

An as-of GRAPH view (the timeline page rendering the circular SVG graph at the
selected commit); anomaly-board deep links pre-filling the authoring form for
bridge notes; a currency sparkline of anomaly counts over audit history.

## Closure evidence (added post-gate — this journal was written pre-closure)

Slice commit `34d640e` (4 files: the renderers + routes + laws in
`docs_wiki.ml`/`zigvm_harness.ml`, MUTATION_LOG entry, this journal) →
detached-worktree gate run **2649 `status=ok`** (`All 1011 tests passed`,
exit 0 — the suite grew with this slice's laws) → `--record-cycle
zk-web-surfacing ok` **Zero-Trust-admitted at HEAD `34d640e`** → the episodic
controller self-documented the closure
(`docs/zk/episodic/zk-web-surfacing.md`) → pushed to `origin/master`
(`1dc6269`) → `--wiki-audit` re-confirmed **HEALTHY** with the four new pages
being served. Services restarted mid-slice onto the new binary (both
executables rebuilt per the §9.13 lesson); the initial `000` probes were the
known ~20s Riot-front boot window, absorbed with retrying curls.

Ledger deltas this slice: mutants 36→**39 planted, 39 killed, 0 surviving**;
the CSS-in-page fixture trap promoted from a repeated incident to a STANDING
RULE (assert the markup form, never a bare class token — MUTATION_LOG.md);
kanban `zk-web-surfacing` done — the ZK front's cumulative count now 16 slices
(13 program + fractal-alignment + audit-coherence + web-surfacing), every one
gate-stamped and Zero-Trust-admitted.

## Post-deploy live verification (2026-07-29, feature-level probes on :8088)

Every claim checked against the RUNNING system, content-level not status-code:

| Surface | Probe evidence |
|---|---|
| `/docs/anomalies` | 200 (110 KB); live defect classes render as sections (unlinked mentions, unpublished); correctly NO "All clear" while informational classes are non-empty |
| `/docs/query` | blank-state hints; `from type:note where degree>=5 sort pagerank desc limit 4` → **4 rows**; `frobnicate` → the named-error chip (`zq-err`) |
| `/docs/timeline` | SVG sparkline + "edges alive" panel + churn hotspots; **as-of selection works** — picking `a453d9ce8` from the sparkline highlights it (`tl-c sel`) and renders that commit's graph |
| `/docs/currency` | Vitals with all four vector kinds (note/html/code/block) + live MoC states (fresh AND stale rendering) |
| Enriched notes | The Gate: `zk-grd g-in`, community chip, expandable **10-direct-edge** neighborhood |
| Semantic search | controls ship on the page; its exact API call round-trips — `granularity=block` returns an `^id`-addressable block hit with excerpt |
| Footer nav | an ordinary note links all four new surfaces |

Both services active; state consistent with `origin/master` `620aaa5`. Two
behavioral notes worth keeping: the anomalies board intentionally shows
INFORMATIONAL classes (unpublished, review stamps, mentions) that the audit's
HEALTHY verdict does not count as defects — the board is the superset view,
the audit the defect view; and the "All clear" banner appears only at a true
zero across ALL classes, so a HEALTHY audit with a busy board is a consistent,
honest state, not a contradiction.
