---
id: f81bf14d-53fb-4bdd-9e79-48eaa9dd9553
status: draft
last_verified: 2026-08-05
verified_by: agent
---
# The ZK/wiki as the system's symbiotic memory & process surface

- **Tailscale Web FQDN**: [http://nas-1.tail55d152.ts.net:4100/docs/zk/20260725-zk-wiki-system-architecture.md](http://nas-1.tail55d152.ts.net:4100/docs/zk/20260725-zk-wiki-system-architecture.md)
- **Fractal Coordinates**: `#fractal-l0` `#fractal-l1` `#fractal-l2` `#fractal-l3` `#fractal-l4` `#fractal-l5`
- **Knowledge Tags**: `#rocha-semiotics` `#cybernetics` `#km-triad` `#zero-muda` `#tailscale-web`
- **Transclusions**: `[[zk:20260905-1801-moc-uos-unified-master]]` `[[wiki:20260905-1801-uos-zk-km-corpus-index]]`


_Decision record (ADR) — captured in the Zettelkasten as part of the SDLC/SRE loop._

## Context (as-is)

The project already had a strong verification substrate — the OCaml harness (Tier-1
judge), the SQLite ledger (verdicts, cycles, capabilities, safety), git history, and a
large body of design docs — but these lived in separate silos. The docs were static
Markdown; the ledger was queryable only by CLI; the agent's reasoning and the decision
envelope for each change were not captured anywhere durable. There was no single surface
where a user or developer could *see the whole system* and no way to *write into* the
knowledge base as part of the work.

## Decision (to-be)

Make the [[The Gate]]-verified wiki a fully functional Zettelkasten that doubles as the
system's living memory and process surface. The whole project corpus (concepts, SDLC/SRE,
system, porting, implementation-plan docs) becomes interlinked atomic notes; the harness
serves it over HTTP/Tailscale alongside a live System Memory view (git + SQLite) and a
comprehensive Opus+Harness fractal report. Every change is captured as a decision record
and weighed against an explicit criteria envelope.

## Agent reasoning

The design lever throughout was *pure kernel + impure shell*: every renderer and every
graph algorithm (PageRank, transitive closure, spanning tree, closure check) is a pure,
total, law-tested function; only the git/SQLite reads and the file writes live in the
harness shell. That let the whole system inherit the project's existing discipline —
laws + ≥2 mutants + the Zero-Trust gate — rather than becoming an untested UI. Honesty
was non-negotiable: the report renders the ledger's verdicts verbatim, the closure check
surfaces real open loops instead of hiding them, and no metric is a fabricated constant.

## Criteria · Architecture

Pure Model→View (Bonsai shape); a homomorphism between the corpus and each view (e.g.
the graph model is one node per note, one edge per link); Stratum boundaries respected —
`src/` stays Zig, `harness/` stays OCaml, runtime state stays SQLite; new controllers
(authoring writes, `CTRL-ZK-AUTHOR`) carry an STPA/UCA safety packet.

## Criteria · Test

Every pure kernel carries selftest laws; the numeric cores (PageRank, reachability,
closure) are QCheck property-tested in the deterministic environment (Σ=1 stochasticity,
transitivity, readiness-conjunction); ≥2 mutants per slice, killed or documented; a hang
is a failed law. The canonical gate stays green (839) at every step.

## Criteria · Docs

The module doc-comment is the spec; MUTATION_LOG records every mutant; SAFETY_ANALYSIS
carries the controller packet; each slice finishes with a green gate + a Zero-Trust
`record_cycle` citing the exact commit. The wiki itself is now a living doc surface.

## Tradeoffs

Inline SVG/CSS visualization over a richer charting library (Vg/Plotkic): accepted a
lower ceiling on chart polish to keep every page self-contained and CSP-safe with zero
external hosts. Per-page PageRank recomputation over memoization: accepted O(n) per render
for simplicity, cheap at the current 126-note scale. Virtual (live) system-memory over
persisted snapshots: accepted recompute-on-render so the memory is always current.

## Alternatives — what else could be done

A static site generator (mkdocs/gitbook) — rejected: not law-governed, not integral to
the harness, no live ledger. A separate web service — rejected: would break the OCaml-only
harness boundary. Embedding-based semantic search (ℝⁿ cosine similarity) — deferred: needs
a local embedding model; the link graph + full-text search + transitive inference cover
navigation for now. A JS charting CDN — rejected: blocked by CSP and violates the
self-contained rule.

## Implementation path

Law-carrying slices, each gated and Zero-Trust recorded (these are the cycles this
decision traces to):

- `gap-wiki-testsuite-realcorpus` — the suite over the real docs corpus.
- `gap-zk-fully-functional` — identity cards, serendipity, Maps of Content.
- `gap-zk-authoring` — live authoring + the full project corpus.
- `gap-zk-memory` — the ZK as system memory (git + SQLite).
- `gap-zk-graph-interactive` — the force-directed knowledge graph.
- `gap-system-report` — the Opus+Harness fractal report.
- `gap-zk-network-science` — PageRank / density / power-law.
- `gap-zk-spanning-inference` — spanning-tree reading order + ontology inference.
- `gap-fractal-map-closure` — the fractal map + closed-loop verifier.
- `gap-zk-decision-records` — decision records + criteria envelope.
- `gap-zk-knowledge-position` — per-note centrality cards.
- `gap-report-decisions-sdlc` — decisions threaded into the report.
- `gap-report-closed-loop` — the closed-loop diagram + this ADR.
- `gap-report-interactive-matrix` — the interactive dashboard filter.
- `gap-zk-semantic-similarity` — TF-IDF cosine similar-notes.
- `gap-report-traceability` — decision ⇄ cycle traceability.

Next: close the real VM parity gaps the report now surfaces (DIVERGENT verdicts,
ABSENT capabilities such as `gen_tcp_udp_sockets`).

#decision #adr

## PKM/OAIS/Logseq extension (2026-08-04)

The durable knowledge path now composes this architecture with
[[PKM_ARCHIVAL_ARCHITECTURE]], [[LOGSEQ_OCAML_SUPERSET_ARCHITECTURE]], and
[[2026-08-04-0859-oais-package-algebra]]. Journal capture promotes to atomic
stable-ID zettels and then Maps of Content without deleting provenance.
Approach B packages the source graph as an OAIS-inspired SIP/AIP/DIP and
recomputes SHA-256 across every published copy. The OCaml Logseq profile
round-trips open-file content and maps page/block/tag observations into this
wiki/ZK graph; external DB/RTC/mobile/plugin semantics remain explicit
residuals.
