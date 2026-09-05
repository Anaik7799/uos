---
name: zk-knowledge-base
description: Operate, query, and maintain the zigvm Zettelkasten/wiki knowledge base — the harness's self-model. Use when searching or reading project knowledge over MCP/CLI, authoring notes or ADRs, running the currency loop (anomalies, MoCs, temporal history, vector index), healing orphans/structural holes, or reasoning about what the system knows about itself. ZK/wiki tooling is OCaml-only per docs/OCAML_SCRIPTING_SOP.md.
---

# The ZK knowledge base — the harness's self-model

The Zettelkasten/wiki is not documentation *about* the system; it is the system's
**queryable self-model**: every fractal layer — rulebooks, skills, safety packets,
formal registry, plans, journals, slip-box notes, episodic slice memory, community
MoCs — is a note in one law-tested graph, and the code itself is reachable through
the same search index (kind `code`). Program of record:
`docs/journal/20260729-1056-zk-wiki-mcp-ai-architecture-recommendations.md` (§6–§9).

*Context Update:* Phase 7 of the OCaml scripting program added a large ZK/wiki-focused fleet — `zk_*`/`wiki_*` standalone scripts under `scripts/` plus dune-linked harness modules (see `docs/OCAML_SCRIPTING_SOP.md`). HONESTY: the phase-7 harness modules are now REAL (DIVERGENCE 682) — the fleet split is **11 law-carrying guards + 44 report-only**, 0 dead stubs (some ZK modules, e.g. `zk_tag_laundering_preventer`, `zk_query_dsl_fuzzer`, graduated to law-carrying). A report-only module still may never be described as "enforcing"/"proving" anything; the live ZK enforcement mechanisms are documented below (CTRL-ZK-AUTHOR guards, projection law, Zero-Trust CLI). Promote report-only → law-carrying only via a law-carrying slice.

## Read surface (MCP tools ≡ CLI mirrors — CLI is the Zero-Trust evidence path)

| MCP | CLI | What |
|---|---|---|
| `zk_search` | `--zk-search Q [block]` | TF-IDF KNN + personalized-PageRank re-rank; `granularity=block` returns the exact `^id`-addressable chunk with an excerpt; kinds `note|html|code` |
| `zk_read_note` | `--zk-note KEY` | full metadata + typed edges + citation contexts (`backlinks_ctx`) + Dung `grounded` standing + `community` |
| `zk_neighborhood` | `--zk-neighborhood KEY [HOPS]` | labelled edges `out/back/typed:<rel>/mention`, hops ≤ 2 |
| `zk_query` | `--zk-query Q` | total zkquery DSL: `[from all\|type:T\|group:G\|tag:T] [where COND and …] [sort … asc\|desc] [limit N]` |
| `zk_anomalies` | `--zk-anomalies` | orphans · unlinked mentions · invalid types · unsupported claims · undermined/disputed arguments · embed cycles · structural holes (all REPORT-ONLY) |
| — | `--zk-temporal [N]` / `--zk-asof C` | git-mined bi-temporal edge history + point-in-time graph |

## Write surface (CTRL-ZK-AUTHOR guards: confined to docs/zk/, draft+agent, git-STAGED)

- `zk_author_note` (MCP) — title/body/tags; 64 KiB cap; CREATE-only.
- `zk_record_decision` (MCP) — full criteria-envelope ADR.
- `--zk-moc` (CLI) — draft/refresh per-community Map-of-Content notes
  (membership-hash memoized; human-promoted MoCs are FROZEN, never overwritten).
- Episodic memory is automatic: every successful CLI `record_cycle` writes
  `docs/zk/episodic/<slice>.md` (CTRL-ZK-EPISODIC; excluded from all analytics by
  the projection law).

## Note conventions

- Wiki-links `[[Title]]`/`[[slug]]`; typed edges `[[T|@supports]]`/`[[T|@opposes]]`
  (the `@opposes` graph feeds the grounded semantics); block anchors `text ^id`;
  transclusion `![[Note#^id]]` on its own line; discourse types via frontmatter
  `type: note|question|claim|evidence|decision`; embedded live queries in
  `zkquery` fences.

## The currency loop (keep the self-model always current)

After landing work: commit → the episodic note writes itself on `record_cycle`.
Periodically (or via the `zigvm-zk-maintain.timer` systemd user unit):

```sh
opam exec -- dune exec ./harness/zigvm_harness.exe -- --root "$PWD" \
  --wiki-audit --vector-index --zk-moc --zk-temporal 12
```

Then read `--zk-anomalies` and HEAL: link orphans from a thematic bridge note
(precedent: `docs/zk/20260729-zk-bridge-and-orphan-index.md`), bridge structural
holes with a note that is a member of one cluster linking the other, resolve
unlinked mentions into real `[[links]]`, and answer undermined/disputed claims
with `@supports` evidence. Never force: report-only anomalies prompt work, they
never gate.

## Discipline

New notes are files (or the guarded write tools) — never edit generated MoC/
episodic frontmatter except to PROMOTE (`status: published`, which freezes MoCs).
All ZK code changes follow `skills/algebraic-fractal-structures/SKILL.md` (laws +
≥2 mutants + gate); the mutation lesson of the program: a surviving mutant means
a non-discriminating fixture — sharpen the law, don't shrug.

## Reference models

`skills/wiki-design/SKILL.md` carries the FULL Notion (100% feature surface)
and Obsidian coverage matrices — the design reference for any wiki/ZK
extension. Rules: ✗ never silently becomes ◐; a promoted gap becomes a
law-carrying slice; SaaS/collab rows marked — are answered by the git/repo/
agent substrate, not missing.

The FORMAL specification of all four systems (common ontology signature K,
per-system ADTs, static invariants, dynamic transition systems incl. the MoC
fixpoint-immunity theorem, the fractal extension structure, and the
mechanization ledger): `docs/formal/knowledge-systems-algebra.md`.

Governance ring (spec §7): STPA/FMEA integration incl. FM-ZK-TAG-LAUNDER and
its class rule (generated aggregators must emit INERT forms of live syntax),
the Rete-UL no-gate-coupling stance + extension recipe, the Rocq/Aeon
mechanization ladder (each rung arms the formal gate — own slice each), the
ruliological frame (confluence-by-design at observation, rule-admitted
evolution at change), and the organism OODA loop with its evolution
invariant: note → kernel+laws+mutants → controller+packet → rule+proof.

Intelligence substrates (spec §7.7–7.8): Smtml = the SMT rung (triple-
agreement, LTS bounded checking, query lint — evidence and counterexamples,
never gate authority; consolidate on aeon_lang's Z3 path per
docs/SMTML_FRACTAL_ANALYSIS.md); OCANNL = the OCaml-native ML seam
(neural-embedding path now in-boundary, demand trigger unchanged; P(fail)
stays label-starved — no engine-swap make-work; any ML output is a
report-only SUGGESTION class).

Full sweeps with implication checks: docs/SMTML_FRACTAL_ANALYSIS.md (SMT,
NOW-substrate, P0 slices) + docs/OCANNL_FRACTAL_ANALYSIS.md (ML,
WHEN-substrate — every candidate trigger-gated; the SANDWICH doctrine:
ML suggests → SMT checks → laws admit; two NEXT rows have real labels
today: mutant-ranking and TIA cost prediction).

## Fractal FP atlas synchronization

When a governed journal, handoff, ontology, or projection changes, preserve the
prompt/evidence provenance and reciprocal links, regenerate all eleven Fractal
FP views, run `--selfcheck-fractal-fp-atlas` and `--wiki-audit`, then record
`phase:atlas_sync`. ZK pages are readable projections only: neither the phase
token nor a generated note may write or replace exact-head gate evidence.
