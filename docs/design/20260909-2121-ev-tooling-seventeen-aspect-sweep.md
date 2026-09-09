# 20260909-2121 — EV tooling across all seventeen aspects

#fractal-l0 #fractal-l1 #fractal-l2 #fractal-l3 #fractal-l4 #fractal-l5 #fractal-l6 #fractal-l7 #fractal-l8 #fractal-l9 #zero-muda #stamp-stpa #km-triad

**Live:** [http://nas-1.tail55d152.ts.net:4100/files/docs/design/20260909-2121-ev-tooling-seventeen-aspect-sweep.md](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20260909-2121-ev-tooling-seventeen-aspect-sweep.md)

Companion to the L0–L9 decomposition in
[`20260909-2120-fractal-rca-ev-tooling.md`](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20260909-2120-fractal-rca-ev-tooling.md).
Aspect names are verbatim from formal spec §7. Observed `2026-09-09T21:42:21Z`.

**SYNC-10 bars a constant-true matrix, so every row below was probed.** Six aspects
turn out not to apply to this subsystem and say so with a reason; the sweep found
**four defects the layer decomposition missed**, two of which are now fixed.

---

## 1. The matrix

| # | Aspect (spec §7) | What was probed | Status |
|---|---|---|---|
| 1 | Substrate and hardware safety | grep for device paths and the denied NVMe serial in `tools/km_provenance/*.ml` | **NOT_APPLICABLE** — no device path; the subsystem is SQLite and files |
| 2 | Version control | `admit` requires `e.revision = at_revision`; ran `--ev-admission` with a fabricated string | **VIOLATED — D5** |
| 3 | Purity and provenance | append-only triggers exercised by raw `UPDATE`/`DELETE`; `recorded_by` traced; `--verify-chain` | **VIOLATED — D6, D7**; D1 fixed earlier today |
| 4 | Supervision | grep `uos_sup.gleam` for the gate | **NOT_APPLICABLE** — one-shot CLI, not a supervised child; correct for an audit tool |
| 5 | Deterministic runtime | grep ZigVM in the EV path | **NOT_APPLICABLE** — none, and none is called for |
| 6 | Evidence and analysis | this *is* the evidence plane: `km_ev.ml`, `ev_evidence`, `ev_verdict` | **HOLDS in design, EMPTY in fact** — 0 real rows |
| 7 | Mathematical authority | grep `formal/lean`, `formal/quint` for a model of admission | **UNKNOWN** — matches were the substring "admit" in unrelated theorems; **no Lean or Quint model of the admission algebra exists** |
| 8 | Feedback and homeostasis | `authority: REPORT_ONLY`, `runtime_admission: NOT_GRANTED` on every output | **HOLDS** — observation, decision and effect are cleanly separated |
| 9 | Inference | grep for model calls | **NOT_APPLICABLE** — no inference, correctly |
| 10 | Mesh and observability | grep `trace_id`/`span_id`/otel in the EV path | **GAP** — none emitted; the C3I OTel contract is unmet here |
| 11 | Agent events | grep AG-UI emission | **GAP** — no lifecycle or result event; the only trail is stdout JSON |
| 12 | Declarative UI | `/evolution` route exists (`ui/wisp/router.gleam:4460`) | **GAP** — a surface exists; **the computed verdict is not projected on it** |
| 13 | Interfaces | CLI only; no Wisp route, no MCP tool, no TUI view | **GAP** — one interface, so "same authority semantics" is untestable |
| 14 | Navigation | Tailnet links in the EV artifacts | **PARTIAL** — this file and the 2120 RCA carry them; the 2026-09-08 RCA carries **0** |
| 15 | Verification checklist | Domain 6, `CHK-19`..`CHK-24`, is the EV domain | **VIOLATED — D8**: `CHK-23-NOMINT` declared, implemented nowhere |
| 16 | Knowledge triad | `--gate` corpus health | **HOLDS** — 108 ADRs contiguous, entropy 3.309 vs floor 2.50, both indexes 1.0/1.0, 16 quarantine records marked |
| 17 | Durable execution | grep sa-plan binding in the EV path | **GAP** — no EV operation is bound to a Sa-plan task; the ledger and the task authority do not meet |

Six `NOT_APPLICABLE`, three `HOLDS`, six `GAP`, three `VIOLATED`, one `UNKNOWN`. Not a constant.

---

## 2. D5 — HIGH — admission is satisfiable at a revision that never existed

Aspect 2. The strongest finding in the sweep, and it sits in the core predicate.

`admit` reduces to:

```
String.trim at_revision <> ""          -- non-empty string
&& e.revision = at_revision            -- string equality of two caller-supplied strings
&& key_present runtime_ref             -- a relative path that exists
&& key_present formal_ref              -- a relative path that exists
```

Nothing binds `at_revision` to the workspace, and nothing binds either key to the
cycle it claims to evidence. **Demonstrated** on an isolated copy of the store
(`UOS_KM_DB` redirected; the canonical store was untouched and still holds its
single test row):

```
km-gate --ev-record 1 "fictional-revision-0000000000000000000000" \
        "AGENTS.md" "flake.nix" "claude-exploit-probe"
km-gate --ev-admission "fictional-revision-0000000000000000000000"

  candidate_revision : fictional-revision-0000000000000000000000
  ev_admitted        : 1
  derived_ceiling    : 1
  EV-1 verdict       : ADMITTED
```

EV-1 admitted at a revision that never existed, keyed to two files with no
relationship to it. `--ev-admission not-a-revision-at-all` is likewise accepted.

The prior RCA's limits section says *"an evidence row asserts that two artifacts
exist at a revision; it does not re-execute them"* — honest, but it understates
this: **"at a revision" is not established either.** The predicate is
`exists(a) ∧ exists(b) ∧ s = s`.

**Not fixed here** — it needs a design decision, not a patch: resolve the revision
through the pinned `jj` and refuse one the workspace is not at, and require each
key to be bound to its cycle rather than merely to exist. Both are the same
correction: replace an observable that is trivially satisfiable with one that
costs what the property costs.

## 3. D6 — HIGH — the gate was green over a broken chain · **FIXED**

Aspect 3. `SC-PROVENANCE-001` §4 lists *"Cycle chain digests recompute |
`CHAIN_BROKEN`"* among the gate's checks. The gate did not perform it:

| Command | Verdict, before |
|---|---|
| `km-gate --gate` | **PASS**, 0 findings |
| `km-gate --verify-chain` | **CHAIN_BROKEN**, 20 defects |

Same store, same moment, opposite answers — and the composite check, the one an
operator or contract cites, was the one that lied. A gate that omits a declared
rule is an observable coarser than the property it claims to enforce.

Fixed: the gate now runs the chain verification, reports `cycle_chain` in its
output and raises `CHAIN_BROKEN` as a finding. `--gate` now returns **HOLD** —
correctly, because the chain is broken.

## 4. D7 — MEDIUM — linkage is enforced at write time, content only at audit time

Aspect 3, and the mechanism behind D6's 20 defects.

```sql
CREATE TRIGGER cycle_chain BEFORE INSERT ON cycle
WHEN NOT ( NEW.sequence = MAX(sequence)+1
       AND NEW.previous_digest = <prior row's digest> )
BEGIN SELECT RAISE(ABORT, 'cycle chain broken: ...'); END
```

The trigger enforces that the chain **links**. It never checks that `NEW.digest`
is the correct hash of `NEW`'s own content. A writer whose canonical form differs
inserts silently, links correctly, and is only caught by an audit that the gate
did not run.

Which is exactly what happened. All 20 broken rows are `sequence` 333–352, all
from **one plan** — `uos/pure-gleam-intent-atlas-full-testing/20260908-1614` — all
stamped `2026-09-08T14:15:52Z`. One bulk write, one instant, twenty rows, and
`INV-WS-07` already warns that a burst sharing one `observed_utc` is a bulk write
rather than a timeline.

**Reported, not fixed.** The correction is to recompute the content digest in the
trigger, but the store is append-only and shared with live writers; changing its
schema is not a unilateral act. The 20 existing rows cannot be repaired either —
append-only means they stand as recorded, with the defect recorded beside them.

## 5. D8 — MEDIUM — `CHK-23-NOMINT` was declared and implemented nowhere · **FIXED**

Aspect 15. The checklist contract declares:

> `CHK-23-NOMINT`: No new EV number is minted while the range above the ceiling is under review (`INV-PROV-05`).

The gate implemented `KMP-CEILING`, `KMP-DUP`, `KMP-ENTROPY`, `KMP-GAP`,
`KMP-INCOMPLETE`, `KMP-INVALID`, `KMP-UNMARKED` — and **no NOMINT rule**. That is
why `governance/ev-manifest.tsv` could grow to EV-111 against a ceiling of 93
without anything objecting, including when **I** appended EV-110 and EV-111 in
commit `f752d3c9`.

Fixed: `KMP-NOMINT` reads the manifest's highest EV and raises a finding when it
exceeds `Km_metrics.admitted_ev_ceiling`. Negative-controlled — trimming the
manifest to ≤ 93 clears the finding and leaves `CHAIN_BROKEN` standing, so the
rule discriminates rather than always firing.

```
km-gate --gate   ->  HOLD
  CHAIN_BROKEN : 20 of 356 cycle rows do not recompute their content digest
  KMP-NOMINT   : ev-manifest.tsv lists EV-111 above the admitted ceiling of 93
```

Selftests after both changes: `--ev-selftest` 12/0, `--metrics-selftest` 10/0,
`--merge-selftest` 16/0, `--rete-selftest` 14/0.

---

## 6. What the sweep adds to the layer RCA

The L0–L9 decomposition found the root cause: *the verifier was replaced, the
incentive gradient was not.* The aspect sweep does not contradict that — it finds
that **the verifier itself is weaker than it appears**, in ways the layer axis did
not surface because they are not layer-shaped:

- **Aspect 2** exposed D5, which lives in the predicate, not in any layer.
- **Aspect 3** exposed D6 and D7 by asking about provenance rather than about a
  layer's responsibilities.
- **Aspect 15** exposed D8 by comparing a declared checklist item against the
  implemented rule set — a cross-artifact question no single layer owns.

The recurring shape, for the seventh time in this review: **an observable cheaper
than the property.** A string standing for a revision. A file's existence standing
for evidence about a cycle. A linkage check standing for content integrity. A
declared checklist item standing for an implemented rule.

## 7. Limits

- D5 and D7 are **reported, not fixed**, for stated reasons; D1, D4, D6, D8 are fixed.
- Aspect 7 is **UNKNOWN**, not absent: no Lean or Quint model of the admission
  algebra was found, and I did not search exhaustively.
- The exploit in §2 ran against an **isolated copy**. Canonical `ev_evidence`
  still holds exactly its one pre-existing test row; I added nothing.
- `--gate` now returns HOLD. That is a true report of a broken chain and a
  violated invariant, not a regression I introduced.
- No EV cycle is admitted. `ev_admitted` remains 0.

---

**UOS footer:** [nas-1.tail55d152.ts.net:4100](http://nas-1.tail55d152.ts.net:4100/) · Sa-plan is the sole execution authority; this analysis grants no admission and no effect authority.
