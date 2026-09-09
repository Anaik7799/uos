# Fractal Layer Taxonomy — Single Source of Truth

- **Contract ID**: `SC-FRACTAL-TAXONOMY-001`
- **Domain**: Knowledge Management, Fractal Coordinates, Corpus Classification
- **Authority**: Operator directive (2026-09-09) "fix or resolve all issues"; tri-sovereign review [20260909-0648](http://nas-1.tail55d152.ts.net:4100/files/docs/reviews/20260909-0648-km-layers-usefulness-design-synthesis.md)
- **Status**: ACTIVE — reconciliation of existing definitions; supersedes neither document's other content

#fractal-l0 #fractal-l5 #zero-muda #km-triad #tailscale-web

---

## 1. Why this contract exists (Jidoka: stop the line at the defect)

`#fractal-lN` tags appear on 96 knowledge records and are gated by `CHK-03-FRACT`,
yet **the taxonomy they name had two incompatible definitions and no single owner**:

| Layer | `.claude/rules/full-symbiosis.md` — *gate* semantics (L0–L7 only) | `contracts/rules/20260908-0950-fractal-hive-cadence-and-observability-matrix.md` — *subsystem* semantics (L0–L9) |
|---|---|---|
| L2 | Component — skills/agents point to real files | `ha/homeostasis` breakers, PID loop, Lyapunov |
| L5 | Cognitive — journals and ZK capture decisions | `uos_swarm` OODA / MAX Mojo |
| L6 | Ecosystem — external docs, credentials | `session_sync` / Zenoh A2A swarm mesh |
| L8 | *undefined* | Biomorphic optimizer, evolutionary mutations |
| L9 | *undefined* | Lean 4 / ZK MOC / provenance / two-key gate |

Consequence, measured: 59% of ADRs claim **all ten** layers. When a taxonomy has two
incompatible readings and two members defined in only one of them, claiming everything
is the rational author response — and `KMP-ENTROPY` then reads that ritual as health.

**Poka-yoke:** this contract is the single source. Any future document defining
`#fractal-lN` must amend this file rather than restate the taxonomy.

## 2. The canonical taxonomy

The two readings are **not in conflict once separated**: one names the *concern* a
record governs, the other names the *subsystem* that enacts it at that layer. Both are
retained, as two columns of one definition.

| Tag | Concern (governing question) | Enacting subsystem |
|---|---|---|
| `#fractal-l0` | Constitutional — no rule bypass, no silent downgrade, no contradictory active guidance | `l0_constitutional` / quorum, consensus, invariants |
| `#fractal-l1` | Atomic — data, absence, error, panic and secret semantics typed and explicit | `engines/zigvm`, native VFS, arena watermark |
| `#fractal-l2` | Component — skills, agents and modules point at real files and current boundaries | `ha/homeostasis`, circuit breakers, PID loop, Lyapunov trend |
| `#fractal-l3` | Transaction — idempotent, timeout-bounded, non-secret-bearing; leases and durability | `sa_plan_job`, bridge leases, Oban dispatch |
| `#fractal-l4` | System — supervision, deployment topology, cross-surface agreement | `uos_sup` / Wisp / Zenohd, supervisor tree, ports |
| `#fractal-l5` | Cognitive — journals and ZK capture decisions, evidence and residual risk | `uos_swarm` OODA cycle, MAX/Mojo inference |
| `#fractal-l6` | Ecosystem — external sources, attribution, credentials, ingestion | `session_sync` / Zenoh A2A, swarm mesh cadence |
| `#fractal-l7` | Federation — cross-host and cross-tree changes, drift, replication | Tailscale mesh, CRDT delta, link latency |
| `#fractal-l8` | Evolutionary — adaptation, mutation, fitness, optimisation over time | Biomorphic optimizer, evolutionary mutations |
| `#fractal-l9` | Sovereign — provenance, formal proof, two-key admission | Lean 4 / ZK MOC / provenance, sovereign two-key gate |

**L8 and L9 are hereby defined for the first time in a governing document.** Their prior
absence from `full-symbiosis.md` is why `km_layers.ml` invented archetype vocabularies
for them that matched neither reading — its L9 vocabulary corresponded to this table's
**L8**, and its L8 vocabulary to nothing.

`#fractal-l10` and above **do not exist**. Eleven records carry `#fractal-l10`; it names
no layer and is counted as none. `Km_corpus.all_layers` enforces this with a digit-boundary
test pinned by laws `E9`/`E10` — before that fix a fixed-width read silently folded it into
`#fractal-l1`.

## 3. The ADR-010 granularity axis is ORTHOGONAL, not a conflict

[ADR-010](http://nas-1.tail55d152.ts.net:4100/docs/zk/20260904-155000-adr-010-seven-level-fractal-granularity-taxonomy-and-100-functional-mapping-kpis.md)
defines a **Seven-Level Fractal Granularity** axis — Level 1 mesh topology down to Level 7
machine/memory layout. It is a *scale* axis, not a *concern* axis, and it carries only
`#fractal-l5` and `#fractal-l8` as its own tags.

A review characterised this as a taxonomy collision. On inspection it is a **shorthand
collision**: ADR-010's prose writes "L1..L7" for granularity levels. To remove the hazard:

- **Fractal layers** are always written `#fractal-lN` or "layer LN".
- **Granularity levels** must be written "granularity level N", never bare "LN".

## 4. What a tag asserts, and what it does not

A `#fractal-lN` tag asserts that the record **addresses, constrains or is enacted at**
that layer. It is a claim about the record's *concern*, not evidence about behaviour.

- A tag is **not** admission evidence. Documented relevance ≠ verified behaviour.
- Tagging all ten is permitted but must be *earned*; ritual breadth is the failure this
  contract exists to make visible.
- Absence of vocabulary is **not** absence of relevance: a record may govern a layer
  through metadata or jurisdiction without naming it in prose. Any future automated
  auditor MUST abstain rather than report "unsupported" on lexical silence.

## 5. Machine enforcement, and its honest limits

1. `CHK-03-FRACT` — tags present and drawn from this table.
2. `tools/km-gate` — `KMP-ENTROPY` over **all** tags (not the first), floor 2.50.
3. `tools/km-gate --metrics-selftest` — 10 laws, including `E5` (a degenerate corpus must
   still fail) and `E9`/`E10` (out-of-range tags name no layer).

**Stated limit, not glossed:** tag-distribution entropy measures marginal diversity, not
whether a tag is earned. Tagging every document with all ten scores 3.3219 bits against a
3.3219 ceiling — maximal, and meaningless. A floor cannot detect ritual tagging. Closing
that gap requires a per-claim evidence audit, which is deliberately **not** created here:
under `SC-JIDOKA-001` it would need its own contract, law suite and acceptance evidence.

---

**Related:** [tri-sovereign review](http://nas-1.tail55d152.ts.net:4100/files/docs/reviews/20260909-0648-km-layers-usefulness-design-synthesis.md) · [[wiki:20260909-0525-uos-toolchain-preflight-guide]]
**UOS footer:** `nas-1.tail55d152.ts.net:4100` · Sa-plan is the sole execution authority; this contract grants no admission.
