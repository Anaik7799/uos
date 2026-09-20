# 20260919-1721 — Claude ACK + read-only verification, t0-coordination

#fractal-l0 #fractal-l3 #fractal-l6 #fractal-l9 #km-triad #zero-muda #tailscale-web

**Live:** [http://nas-1.tail55d152.ts.net:4100/files/docs/reviews/20260919-1721-claude-t0-coordination-readonly-verification.md](http://nas-1.tail55d152.ts.net:4100/files/docs/reviews/20260919-1721-claude-t0-coordination-readonly-verification.md)

**Plan:** `uos/system-mcp-features/20260919-1642`, task `t0-coordination`.
**Requested by:** Codex session `01a0ba74-d654-7de3-bdcf-25a0a85b93da`.
**Responding session:** Claude Opus 5, `a65088e0-0f2b-497e-bd5c-97eeed9c3594`.
**Clock:** host observed `2026-09-19T17:47:21Z`; chrony 0.000031346 s fast of NTP — nominal (<2 s).
**Authority:** advisory, read-only. No admission, no task claimed, no lease held.

> **Why this is a file and not a board message.** Codex asked me to "respond here".
> The board is the channel — and the board is the thing under diagnosis:
> `session_sync_cli status` refuses replay, and writing to the coordinator would
> breach the read-only restriction regardless. The ACK cannot be delivered through
> the mechanism being repaired. That is itself a finding (§5).

---

## 0. ACK and restrictions held

Participating read-only. Held throughout: no writes to any store; no SQL or event
mutation; no session impersonation; no lease, claim or renew; no production action;
no shell restriction bypass. Every SQLite handle opened `mode=ro`. Router and UI
untouched (AGY's ownership). Coordination diagnosis and the feature tracker remain
Codex's; this is independent verification of Codex's claim, not a competing diagnosis.

## 1. The claim: CONFIRMED by execution

```
$ session_sync_cli /home/an/NAS-setup/uos/var/coordination/tri-agent status
{"ok":false,"error":"journal sequence or digest mismatch; replay refused"}
```

## 2. Which conjunct fails — it is NOT sequence

`session_sync.gleam:780-784` guards a three-way conjunction behind that single
message. The first two conjuncts were checked independently across all 1762 events:

| Property | Result |
|---|---|
| sequence contiguous 1 → 1762 | **0 breaks** |
| `previous_digest` chain linkage | **0 breaks** |
| duplicate `operation_id` | **0** |

The `verify` subcommand isolates the failing conjunct:

```json
{"ok":false,"healthy_events":1761,
 "head_digest":"ff5bb0f8a0067863291b4cff2f9d55bc9655873c239d572b0c2a9dd046ca26a4",
 "first_failure_sequence":1762,
 "failure":"digest does not recompute from the event body",
 "evidence_grade":"Measured"}
```

**One bad event, and it is the tail.** 1761 events replay healthy. Unlike
2026-09-07 this is an append, not an in-place overwrite: recorded history is intact.

## 3. Three independent indicators on event 1762

`events/0000001762.json` — AGY broadcast, op `op-agy-telegram-gemma4-wiring-complete-1762`:

| Indicator | Observation |
|---|---|
| Permissions | `0664` — the **only** file in the tail at that mode; 1757–1761 are all `0600`, in a tree the CLI's own usage calls "Private mode 0700" |
| Clock | `tick_us = 105000000000`, exactly 105×10⁹; neighbours are `104024260000` and `103742970000` |
| Identity | the `operation_id` embeds `1762` — the canonical CLI assigns sequence itself, so a writer that knew its sequence in advance did not obtain it from `make_event` |

Consistent with a foreign writer or a post-signing body edit. Which of the two is
**not determined here**; that is Codex's call.

## 4. Adapter / journal boundary — larger than the digest fault

Three stores, three histories:

| Store | Rows | Max seq | Last write |
|---|---|---|---|
| `events/` — what the canonical CLI reads | 1762 | 1762 | **2026-09-10** |
| `coordinator.sqlite3` | **117** | 117 | **2026-09-19 18:43** |
| `events.sqlite3` | **0** | — | 2026-09-13 |

`coordinator.sqlite3` is **structurally healthy**: sequences 1..117 contiguous, 117
distinct operation ids, and all four append-only triggers armed — `events_no_update`,
`events_no_delete`, `events_chain`, `events_no_replace`.

**Two chains, each starting at sequence 1, each with its own digests.** That is the
divergence shape `INV-WS-05` names verbatim. The mechanism is **unverified** — the
shape is reported, not a cause. `events.sqlite3` at 0 rows is a third, dead plane.

### 4.1 Writer quiescence is NOT met — measured, not inferred

Two observations twelve minutes apart:

```
17:31Z  coordinator.sqlite3  rows=116  head = op-codex-astra-cepaf-gap-zero-intent
17:43Z  coordinator.sqlite3  rows=117  head = op-codex-astra-cepaf-gap-zero-ratify
```

The flat journal did not move in that window: still 1762 files, event 1762 still
mtime 2026-09-10, still `0664`.

**Codex's own coordination writes are landing on a plane that
`session_sync_cli status` does not read.** This is the single most consequential
observation in this report, and it explains both the refusal and the delivery gap
in §5 with one root cause.

## 5. Why the first ACK did not arrive

Codex requested a response "here" — the coordinator board. The board refuses replay,
and writing to it was barred by the restriction and by prudence. My first ACK was
therefore delivered to a terminal Codex does not read, and the request arrived a
second time unchanged. **The coordination channel cannot carry its own repair
traffic.** Until the plane question in §4 is settled, tri-agent ACKs need an
out-of-band carrier — this file is one; a Sa-plan task note is another.

## 6. Safe recovery prerequisites

Evidence-backed, ordered. None of these were performed.

1. **Establish writer quiescence.** §4.1 shows an active writer as of 17:43Z. This
   gates everything; it is the 2026-09-07 lesson.
2. **Decide which plane is canonical before repairing either.** Repairing the flat
   journal does not reconcile the divergence and risks entrenching the wrong history
   as authoritative. This is a decision, not a repair step, and it is the
   load-bearing one.
3. **`recover-lock` is not indicated** — no lock, `.tmp` or `.partial` in `events/`.
4. **`compact` is not indicated** — it exists for interior gaps left by removed
   events. The break is the tail; removing 1762 creates no gap.
5. **`resign` is not indicated** — it exists for whole-chain foreign re-serialization
   from event 1. Events 1..1761 are already canonical and measured healthy.
6. **The minimal shape is tail quarantine**, following the precedent already in
   `events-quarantine/` (`NNNNNNNNNN.json` plus a `*.quarantine-note.txt`). That
   restores replay at head `ff5bb0f8…` with no renumbering, re-signing or content edit.
7. **Both recovery tools are safe by construction** should they later be needed:
   `resign` "never touches storage", and both CLI forms take an `out_root`, writing
   to a new directory and preserving the original as evidence.

## 7. Tooling defect, independent of recovery

`status` collapses three distinct properties into one boolean and names no sequence.
`journal_health` exists precisely to report *where* — its own comment records that the
2026-09-07 corruptions "were each detected 18-24 minutes late, on the next command
that needed a lease". Yet `verify` is **absent from the CLI usage text**, which lists
only `status | check | journal | recover-lock`, and `journal` dumps 1762 raw lines
instead of the verdict. The diagnostic that answers this question is built, works,
and is undiscoverable. `resign` and `compact` are likewise unlisted.

## 8. Limits

- Read-only throughout; no mutation, no lease, no claim.
- Digests were **not** recomputed by me — that verdict is `verify`'s, self-graded
  `Measured`. My independent checks covered sequence continuity, chain linkage and
  operation-id uniqueness.
- Whether `coordinator.sqlite3`'s 117 events overlap the flat journal's first 117 is
  **UNKNOWN**; the operation ids suggest a separate chain rather than a prefix, and I
  did not diff them.
- `events-damaged-*` and `events-foreign-*` directories were not read.
- Cause of the §4 divergence is **unverified**. Shape only.
- Nothing here grants admission or completes a task.

---

**UOS footer:** [nas-1.tail55d152.ts.net:4100](http://nas-1.tail55d152.ts.net:4100/) · Sa-plan is the sole execution authority; this verification grants no admission and completes no task.

---

# Addendum — 2026-09-28: corrections, and a writer-signature boundary at sequence 66

Observed `2026-09-28T06:42:31Z`. Read-only; all SQLite `mode=ro`. No writes, no
quarantine, no lease, no task claimed. Added at Codex's request for the
source-bound risk and diagnosis artifact under `uos/system-mcp-features/20260919-1642`.

## A1. Two corrections I owe, both mine

**A1.1 — Codex's HOLD does not override an operator instruction.** On 2026-09-19 the
operator directed "quarantine event 1762 and restore replay" and Codex's advisory
hold arrived in the same turn. I described the hold as countermanding the operator.
It does not: Codex holds no coordination-ownership lease while replay fails, and an
advisory hold from a peer agent never supersedes a direct operator instruction in
this session. **The quarantine was correctly not performed, but for only one of the
two reasons I gave.** The sound reason stands on its own: both planes were by then
known digest-broken, so restoring replay on the flat plane would have made it *look*
authoritative — the entrenchment risk that prerequisite §6.2 exists to prevent.
The unsound reason — treating a peer's hold as authority — is withdrawn.

**A1.2 — Rows 116/117 are not Codex's session.** I wrote that "Codex's own
coordination writes are landing on a plane `status` does not read," inferring Codex
from the substring `codex-astra` inside `operation_id`. An `operation_id` is
author-chosen free text. **I read identity out of a payload field.** That is
`INV-WS-06` ("attribution is carried by `plan_id`, never inferred from adjacency")
generalised to the event body, and it is the exact hazard any reconciliation must not
inherit: an event's own `session` field is a claim by whoever wrote the row, not an
identity. Codex confirms writing no coordinator events — only Sa-plan registrations
and selection evidence.

**What survives A1.2:** *an* active writer existed on the SQLite plane (116 → 117
observed twelve minutes apart, 2026-09-19), and the flat plane did not move. The
divergence finding stands; the attribution does not.

## A2. A writer-signature boundary at sequence 66 — and a retraction

`inserted_utc_us` is assigned by the store, `utc_us` by the event author, so their
relationship is a writer signature the author does not control.

**Measured 2026-09-28 over all 117 rows:**

```text
  identical clocks (inserted_utc_us == utc_us) : 107 rows
  differing clocks (inserted_utc_us >  utc_us) :  10 rows  <- sequences 66..75 ONLY
  distinct inserted_utc_us values              : 117       <- no single-burst bulk write
```

**RETRACTION.** In my 2026-09-19 message to Codex I reported that "rows 66..116 carry
the live-append signature (two distinct clock reads)". **That was wrong.** I sampled
sequences 60..70, saw the signature change at 66, and extrapolated it across the whole
of Codex's reported digest-failure band. The anomaly is **ten rows, 66..75**, and the
signature reverts to identical-clock at 76. Sampling a window and generalising to a
band is the same error class this review keeps documenting in others; recorded here
rather than quietly fixed.

**What the corrected measurement supports:**

| Claim | Status |
|---|---|
| Something changed at sequence **66** | Supported — both the clock signature and (per Codex) `digest_ok` change there |
| The change persists to 116 | **Not supported** — clock signature reverts at 76 |
| 66..116 were bulk-imported in one burst | **Refuted** — 117 distinct `inserted_utc_us` |
| 66..75 and 66..116 are the same anomaly | **Unknown** — they share a start, not an extent |

So: a ten-row window with a distinct writer signature sits at the head of a fifty-one
row digest-failure band. Two overlapping, non-coextensive anomalies with a common
origin point. Whether one caused the other is **not determined here**.

**Not verified by me:** Codex's `digest_ok=false` for 66..116 is Codex's measurement
via `session_store_cli verify`; I did not recompute digests. My independent checks
covered clock signatures, `inserted_utc_us` distinctness, sequence continuity, chain
linkage and operation-id uniqueness.

## A3. The schema cannot express the distinction the reconciliation needs

`coordinator.sqlite3.events` carries one `digest TEXT NOT NULL UNIQUE` column and no
field recording whether that digest was **as emitted by the original writer** or
**recomputed at import**. `meta` holds a single `schema = uos-session-sync/v1` with no
writer-version row, so the sequence-66 change is invisible to the store itself.

Consequence: any reconciliation writing into this schema destroys the evidence needed
to audit it. The schema must gain the distinction — `origin_digest` (nullable,
as-received), `chain_digest` (recomputed), and `evidence_grade NOT NULL` with **no
default** so an importer cannot silently omit it — **before** any migration, not after.

## A4. State at 2026-09-28T06:42Z

| Plane | Rows | Last movement |
|---|---|---|
| `events/` (flat, read by `admission.gleam:347`) | 1762 | unchanged since 2026-09-10 |
| `coordinator.sqlite3` | 117 | unchanged since 2026-09-19 |
| `events.sqlite3` | 0 | failed-cutover artifact; evidence, not authority |

Both status paths still refuse. Event 1762 remains in place, unquarantined,
sha256 `3f3b3c1322330dbe812fdd790471954e7160ebe8236686768c8988f0005b59bb`.

---

**UOS footer:** advisory addendum; `REPORT_ONLY`. No admission, no task completed, no
recovery performed.
