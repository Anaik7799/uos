# 20260909-0648 — What `km_layers` would need to be useful: design synthesis

#fractal-l0 #fractal-l5 #fractal-l8 #zero-muda #km-triad #stamp-stpa #algebraic-atlas

**UOS / Reviews / Design Synthesis** · [Cockpit](http://nas-1.tail55d152.ts.net:4100/) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk) · [Checklist](http://nas-1.tail55d152.ts.net:4100/checklist)
**Subject:** `tools/km_provenance/km_layers.ml` · **Reviewers:** Claude (Opus 5), AGY (plan mode), Codex (read-only)
**Inputs:** [brief](20260909-0640-km-layers-design-brief.txt) · [AGY](20260909-0640-agy-design-review-km-layers-usefulness.md) · [prior round](20260909-0614-tri-sovereign-review-of-km-layers-synthesis.md)
**Status:** REPORT ONLY. Nothing built. No admission.

---

## 1. The finding that reframes the whole question

**The taxonomy `km_layers` classifies into is not well-defined in this repository.** Two governing documents give incompatible definitions, and no classifier — lexical, structural or otherwise — can be correct against an ambiguous target.

| Layer | `.claude/rules/full-symbiosis.md` (gate semantics) | `contracts/rules/20260908-0950-fractal-hive-cadence…` (subsystem semantics) | `km_layers` archetype |
|---|---|---|---|
| L2 | Component — skills/agents point to real files | **ha/homeostasis, breakers, PID loop, Lyapunov** | component, module, library, api surface |
| L5 | Cognitive — journals, ZK, evidence | **uos_swarm OODA / MAX Mojo** | cognitive, journal, zettelkasten, knowledge |
| L6 | Ecosystem — external docs, credentials | **session_sync / Zenoh A2A swarm mesh** | ecosystem, external, third party, vendor |
| L8 | *absent* | Biomorphic optimizer, evolutionary mutations | metric, kpi, telemetry, observability |
| L9 | *absent* | Lean 4 / ZK MOC / provenance / two-key gate | evolution, roadmap, lifecycle, maturity |

`km_layers`' header says L8 and L9 were "extended" by its author because `full-symbiosis` stops at L7. But L8/L9 *are* defined — in the cadence matrix — and the archetypes match **neither**: its L9 vocabulary (evolution, mutation) corresponds to the contract's **L8**, and its L8 vocabulary (telemetry) corresponds to nothing.

Neither reviewer found this. It explains the ritual tagging directly: **when a taxonomy has two incompatible definitions and two undefined members, tagging all ten is the rational author response**, and the entropy metric then reads that ritual as health.

**Fixing `km_layers` is downstream of fixing the taxonomy.** Any work on the classifier before the taxonomy is single-sourced is work against a moving target.

## 2. How the sibling trees actually use a KM layer

Surveyed directly, not asserted.

| Tree | Where layer membership lives | Health measure | Per-document layer tags |
|---|---|---|---|
| **ZigVM** | **One curated atlas note** — `docs/zk/20260729-fractal-atlas.md` links every object under layer headings, "reachable from here in ≤2 hops". `layer` is a field on the node type in `graph_intelligence.ml`, a property-graph algebra. | **Graph analytics**: PageRank, communities, reading order, orphans, structural-hole `gap` detection — surfaced by `zk_anomalies` and healed by authored bridge notes | **zero** `#fractal-lN` tags across 52 ZK files |
| **C3I** | **Typed ontology** — 12 entity types, 15 relations, 7 invariants, "intentionally minimal so it can be fully held in working memory by any agent". Content-addressed `zk-<hash>` citations (312 distinct) over a SQLite catalog behind `sa-plan-daemon`. | **Retrieval-loop compliance**: `SC-ZK-CLAUDE-001` — search the ZK *before* any task (`zk-recall`), ingest *after* (`zk-learn`) | **zero** — classification is by *deliverable shape* (pass class A–H: spec, impl, test, closure, RCA, enforcement, federation, ontology) |
| **Indrajaal** | none — Gleam web/planning; no KM modules of its own | — | none; it consumes |
| **UOS** | **replicated in every document** — 10 tags × 96 records = 960 assertions | tag-distribution entropy (a floor) | 96 records, 59% claiming all ten |

**UOS is the only one of the four that tags every document with a 10-way taxonomy and then measures the tag distribution.** Both mature siblings (a) put layer membership in **one** place, and (b) measure something an author can act on — an orphaned note, a missing bridge, a failed recall — rather than a distribution statistic.

The UOS master MOC has sections by *kind* (ADRs, MOCs, transclusions), not by layer. The atlas pattern is simply absent here.

### 2.1 ZigVM has already hit and solved the two hazards under discussion

- **Tag laundering.** `harness/zk_tag_laundering_preventer.ml` is a **law-carrying** module against `FM-ZK-TAG-LAUNDER`: generated aggregators must emit inert forms of live syntax, or a MoC re-files itself into the community it summarises. This is AGY's Goodhart hazard, already named and guarded upstream.
- **The coarse-observable defect, again.** That module's own header records: *"The DEFECT was in THIS module's earlier oracle: its liveness test treated only a preceding backslash as escaping … and reported **57 phantom laundering violations**."* Its remedy is law **L1 FIDELITY** — the module's predicate must equal the **real** indexer's regex, tested against the shipped implementation.

That is the same failure class as KMP-ENTROPY (a false-alarm observable) and the same remedy this session applied. ZigVM's discipline — *report-only modules may never be described as enforcing or proving anything; promote report-only → law-carrying only via a law-carrying slice* — is the governance model UOS should copy for anything like `km_layers`.

## 3. My proposal, and AGY's two successful attacks

**P1** was: stop asking "which layer is this?" and ask "of the layers this document claims, which are evidenced?" **AGY broke it twice, and both breaks hold.**

1. **Asymmetric blind spot.** A claims-auditor detects over-tagging only. It cannot see an ADR that establishes a real L1 invariant while carrying only `#fractal-l0`. An aid that cannot detect omissions "only ratifies negative selection." The output must be a 2×2 over {claimed} × {earned}: `VERIFIED`, `RITUAL_CLAIM`, `UNCREDITED_IMPACT`, `ABSTAIN`.
2. **Category error — subject vs jurisdiction.** ADR-002 is *about* an L1 memory trap, *enacted under* L0 policy, *protecting* an L4 runtime. Demanding lexical evidence in the body for every claimed layer penalises concise writing where jurisdiction lives in metadata, not prose. A layer claim can be true without vocabulary support.

## 4. What must be added — merged and prioritised

Necessity ordered by dependency. Items marked **†** are mine or empirically established here; the rest are agreed by AGY.

| # | Addition | Status |
|---|---|---|
| 0† | **Single-source the taxonomy.** Reconcile `full-symbiosis` and the cadence matrix; define L8/L9 once. | **BLOCKING** — everything else is void without it |
| 1 | **Structural evidence: paths + contract codes.** Verified feasible: **100%** of ADRs cite ≥1 repo path (mean 6.1), **91%** cite ≥1 `SC-*` contract (mean 3.4), **91%** cite both, **0** cite neither. Tamper-resistant; no synonymy or boilerplate noise. | NECESSARY, and the strongest signal available |
| 1a† | *Caveat:* AGY grounded this on `etc/rules/` and `docs/governance/` mapping contracts 1:1 to layers. **Neither directory exists**; no such mapping is documented. The dir→layer table must be **authored** — but that is ~12 directories in one file versus 960 tag assertions. | correction |
| 2 | **Boilerplate excision** — score only `## Context` / `## Decision` / `## Consequences`; drop nav, transclusion and checklist blocks that `SC-CHECKLIST-001` mandates in every file. | NECESSARY |
| 3 | **Tokenisation with morphological folding** — substring matching cannot see `NUL ≠ null`. | NECESSARY |
| 4 | **IDF / stopword floor** — `wiki` 99%, `system` 94%, `sovereign` 85% document-frequency currently carry full weight. | NECESSARY |
| 5 | **Independent per-layer scoring with its own threshold** — no argmax, no simplex; ten layers may all be evidenced. | NECESSARY |
| 6 | **Explicit ABSTAIN** — distinct from `UNSUPPORTED`, for low corpus coverage or short documents. | NECESSARY |
| 7 | **Corpus-driven vocabulary repair** — purge the 17–18 dead terms; seed from live code (`nif`, `alloc`, `bounds`, `wal`, `sqlite`, `crdt`), not from gate prose. | NECESSARY |
| 8 | **Drop "confidence"** — cosine against a 0/1 archetype is not a probability (median 0.323). Use `support_score` with calibrated cutoffs. | NECESSARY |
| 9 | **Saturation + distinct-marker requirement** — `min(count, 2)`; repeating one keyword earns nothing. Anti-Goodhart. | NECESSARY |
| 10 | **`--layer-selftest` law suite** — monotonicity, boilerplate invariance (Δ < ε), orthogonality (L1 content must not move the L4 score), fail-closed abstain. | NECESSARY |
| 11 | **Fix `--classify-layers`**, which still publishes the discredited `"current": 1.322` beside a now-meaningless single-label proposal entropy, and writes it to `layers.json` — which has no consumer. | NECESSARY (bug) |
| 12 | **Strict advisory status** — never a blocking gate. ZigVM precedent: report-only modules may not be described as enforcing anything. | NECESSARY |
| 13 | Mojo cosine differential oracle | **OBSOLETE** if the global cosine kernel is abandoned |

## 5. The hazard, if built badly

AGY names it best: **Goodhart / "prose laundering."** A gate that rejects unsupported layer claims will not produce fewer ritual tags; it will produce synthetic *"Layer Justification Blocks"* of keyword spam. The corpus degrades from *clean ADRs with lazy tags* into *corrupted ADRs polluted with keyword spam*. ZigVM's `zk_tag_laundering_preventer` exists because that recursion already happened there.

Secondary: **epistemic false authority.** An author using accurate terminology that misses the hardcoded vocabulary gets `UNSUPPORTED`, then either distrusts the toolchain or hunts for the synonyms that appease it.

## 6. Recommendation

**Do not rebuild `km_layers` as a classifier. Adopt the ZigVM shape, in this order:**

1. **Single-source the taxonomy** (blocking; a governance act, not code).
2. **Author a layer atlas** — one note, ~96 entries under 10 headings — replacing 960 replicated tag assertions with one reviewable source of truth. This is the smallest change with the largest effect and needs no classifier at all.
3. **Measure what an author can act on** — orphans, structural holes between communities, unlinked mentions, stale `last_verified` — as ZigVM's `zk_anomalies` does. Retire tag-distribution entropy from the health role it cannot fill: it cannot distinguish a well-spread corpus from an indiscriminately tagged one, since all-ten-everywhere scores 3.3219 against a 3.3219 ceiling.
4. **Then**, if still wanted, a *structural* layer auditor — paths and `SC-*` codes, present in 100% and 91% of ADRs — reporting the 2×2 with abstention, advisory only, under a law suite.

The lexical classifier is the weakest available signal for this corpus, aimed at an ambiguous target, guarded by nothing. Every stronger option is already demonstrated in a sibling tree.

## 7. Codex — [full review](20260909-0648-codex-design-review-km-layers-usefulness.md)

**Verdict: "Build a claim-to-witness auditor. P1 is the right direction; P2 overstates what lexical analysis can establish."**

### 7.1 Corrections to my analysis — four more

| Mine | Correction |
|---|---|
| "ADR-002 at the classifier's **second-highest confidence**" | **Wrong.** 2nd by *margin*, **13th of 97 by confidence**. Verified. |
| "the failure is **coverage, not boilerplate**" | **Too exclusive.** Codex: removing metadata/navigation alone flips ADR-002's winner to L1. Under my own stripping rule it does not flip — L5 0.4536→0.3651, L1 0.0792→**0.1754** — but the direction is unambiguous and the two factors interact. Codex is right that the stripping rule must be specified to be reproducible; neither of us did. |
| population statistics | **Mixed.** My 80-doc figures are ADR-017–096, excluding 16 six-digit-prefix files. Full 96: 47 all-ten, 22 two-tag, mean **6.51** (not 7.41), **17** dead terms. |
| taxonomy conflict is **two** documents | **Three.** ADR-010 defines a *seven-level* fractal granularity taxonomy calling **L1 "mesh topology"** where this module calls it atomic. |

### 7.2 A live bug Codex found in my own entropy fix

`km_corpus` reads a fixed 11 characters, so **`#fractal-l10` — present in 11 ADRs — is read as `#fractal-l1`**. A boundary error of exactly the class this session keeps diagnosing, in code I wrote and committed.

Measured impact today: **nil**. Every l10 document also carries a genuine l1 and the tag list is de-duplicated per document (0 documents have l10 without l1). **Masked is not fixed** — corrected, with laws **E9/E10** pinning it. `km-gate` PASS at 3.3079; metrics-selftest **10/10**.

### 7.3 Where Codex and AGY disagree

| Item | AGY | Codex |
|---|---|---|
| **(d) IDF / stopword floor** | **NECESSARY** — ubiquitous terms carry near-zero mutual information | **Optional** — "frequency measures discrimination, not evidential value; a ubiquitous term can still participate in a decisive contextual rule" |
| **(a) morphological folding** | NECESSARY | boundary-aware matching necessary; **general stemming optional** — `NUL` vs `null` needs domain concepts, and identifiers like `memchr` must be preserved |
| **(e) abstain eligibility** | drive from dead-term counts | dead-term counts **cannot** determine eligibility; use demonstrated per-layer performance |
| **Mojo oracle** | obsolete | conditional on retaining cosine; "agreement establishes arithmetic, not relevance" |

Codex is right on (d) and (e): both of AGY's rules are *proxies* for evidential value rather than measures of it — the same substitution error as the rest of this series.

### 7.4 Codex's own additions

- **A semantic contract must precede P1.** Define what claiming a layer *means* — *addresses*, *affects*, *constrains*, *implements* — because each needs different evidence.
- **"No lexical match" must ordinarily mean ABSTAIN, not UNSUPPORTED**, "otherwise P1 repackages vocabulary blindness as a negative judgment." This subsumes AGY's under-tagging attack and is the sharper statement of it.
- **Claim extraction is a missing prerequisite.** The scanner searches everywhere: a quoted tag or a checklist example becomes an author's claim.
- **The failure it most fears:** *"'evidenced' becoming admission evidence."* A document can describe a layer fluently while its implementation claims are false or quarantined. Consumers must preserve **documented relevance ≠ verified behaviour**. FMEA severity 5 under the repository rubric; occurrence and detection unmeasured.
- **Q5:** a versioned annotation table binding each layer relationship to rationale, passage and reviewer decision — pure OCaml checks references, hashes, completeness and invalidation. *"An existing anchor proves only that text exists."* Test against improved lexical retrieval before assuming the annotation cost pays off.
- **Q6 bar:** ≥95% observed precision per automatic verdict, ≥30% non-abstention, 20% reviewer-time reduction in a paired exercise; sparsely validated layers remain abstaining.
- Notes **ADR-097 appeared during the review**; the original 96 stayed byte-identical.

### 7.5 Mandate compliance

Both reviewers complied this round. My own guard **falsely reported `km_layers.ml` and `km_gate.ml` as mutated** — it looked for `km_layers.ml.guard` while the snapshot was saved as `km_layers.guard`. `jj status` showed no change; Codex told the truth and my checker was wrong. Recorded because it is the same defect class as everything else here, committed by the reviewer applying the lesson.

---

**UOS footer:** `nas-1.tail55d152.ts.net:4100` · Sa-plan is the sole execution authority; this review grants no admission.
