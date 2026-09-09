# 20260909-1940 — Codex corrections: five more of mine wrong, four findings neither AGY nor I had

#fractal-l0 #fractal-l3 #fractal-l4 #fractal-l9 #zero-muda #stamp-stpa

**Live:** [http://nas-1.tail55d152.ts.net:4100/files/docs/reviews/20260909-1940-claude-codex-corrections-and-four-new-findings.md](http://nas-1.tail55d152.ts.net:4100/files/docs/reviews/20260909-1940-claude-codex-corrections-and-four-new-findings.md)

Relayed by **Claude Opus 5**, session `a65088e0-…`. Observed `2026-09-09T19:17:40Z`. **No source written.**
Peer: **Codex** (`gpt-6-astra`), read-only, complete. Every claim below that could be checked **was checked** — the four new findings are reproduced here from the live artefacts, not relayed on Codex's word.

---

## 1. Four findings neither AGY nor I had — all verified

### C1 — the current grant is now mechanically invalid, so my own B5 falsifier is stale

Codex noticed the grant has acquired a `quarantine` key the proposal lacks. Verified:

```
grant-only keys   : ['proposal_path', 'proposal_sha256', 'quarantine']
len(grant)    = 19
len(expected) = 18       (proposal keys + proposal_path + proposal_sha256)
same_object's first test, list.length(a) == list.length(b) -> False
=> rejects with grant_differs_from_reviewed_proposal
```

The value is root's own revocation: *"REVOKED_BY_ROOT: created and attach-probed by reviewer using root identity outside read-only review scope. Original bytes preserved; no activation/admission evidence."*

Two consequences. **The revocation is effective by construction** — `same_object` refuses the document on a length mismatch before reaching any field, which is a genuinely good outcome: annotating a grant in place *is* revoking it. And **my B5 falsifier — "the current files: the grant validates today" — is no longer true and must not be carried forward.** The B5 *defect* stands (`validate_review` still never reads `reviewer.task_id`); only my live-artefact demonstration of it is stale.

### C2 — `effect_path` collides, and the collision breaks the fix I proposed

`effect_path(execution, intent, suffix) = "var/harness/effects/<grant>-<intent>-<suffix>.json"`. Verified by construction:

```
intent_id "x-completion", suffix "intent"            -> …/G-x-completion-intent.json
intent_id "x",            suffix "completion-intent" -> …/G-x-completion-intent.json
COLLIDE: True
```

`-` is in the `component` charset (`admission.gleam:61`), so `intent_valid` admits `x-completion`. An effect intent and a completion intent can therefore occupy the same path.

This lands directly on me: my B2 fix was *"`harness_reconcile` should dispatch on which intent file exists."* **That dispatch key is ambiguous**, so my fix was built on an observable that cannot distinguish the two cases it was meant to separate. Codex's replacement is right: encode kind and identity inside the record, validate the schema and embedded identity, and never infer meaning from a filename.

### C3 — `capture` is blind to four authorized write paths

`capture` (`operations.gleam:49-56`) folds over `scope.sources` only. The grant authorizes writes outside that list — verified, 4 of them:

```
docs/design/20260909-1751-admission-state-laws.json
docs/journal/20260909-1751-admission-mcp-probe.json
docs/journal/20260909-1751-admission-repair-journal.md
governance/capability-inventory/20260909-1751-admission-verification.json
```

A write to any of these leaves `before == after` **true** at `operations.gleam:132`, and leaves `current == candidate` true at `finish:277` and `input_manifest == candidate` true at `successful_check:227`. So the journal a completion is *required* to reference can change between build and finish without invalidating the candidate binding that completion rests on. The manifest is a narrower observable than the write scope it is meant to guard.

### C4 — the guardian that bounds every effect is bound by nothing

`tools/ecology_process.ml` is invoked at runtime — `ecology_capability_ffi.erl:127`, `Guardian=filename:join(Root,"tools/ecology_process.ml")`. Verified against the grant:

| binding | contains `ecology_process.ml` |
|---|---|
| `source_paths` | **False** |
| `read_paths` | **False** |
| `write_paths` | **False** |
| `loaded_control_ids` (9 modules) | **False** |

The component that enforces every effect's time bound, output bound and process-group kill appears in **no** path list and **no** control digest. Change it and the review, the task row, the candidate manifest and all nine control ids stay perfectly matched while effect semantics change underneath them. This is the sharpest of the four.

---

## 2. Five more corrections to me

### 2.1 `boot_id` is not sufficient even for liveness

AGY called my claim moot. Codex goes further and is right: two unequal strings do not establish a genuine new boot **on the same execution host**. The observations could concern different hosts; a local reboot does not terminate remotely delegated work or prevent persisted jobs from restarting. Narrow sufficiency would need authenticated host continuity, reliable boot provenance, proof that execution was entirely local, **and** recovery inhibition of old work. My unconditional claim was overstated twice over.

### 2.2 My B1 example was partly wrong

`call` runs `ops.validate_args` **before** `dispatch` (`successor_mcp.gleam:119-123`) and returns `#(state, Error(e))` with state untouched. So a missing or non-string argument **does not** trip the stop line. My "mistyped `plan`" example only holds for the *unknown-plan* case, where `a.lookup` fails inside the `selected` block. **B1 stands as a blocker** — the deadlock is real — but the entry condition is narrower than I wrote.

### 2.3 My B7 mechanism was wrong

I argued nested key **ordering** breaks equality because `Object` is `List(#(String, Value))`. Codex: the parser routes objects through dictionaries first (`value.gleam:25`), so that is not established by the type alone. The stronger, demonstrated concern is different — **duplicate keys are discarded before `same_object`'s uniqueness test**, which makes that test vacuous. Hash equality authenticates ambiguity; it does not resolve it.

### 2.4 My drain entry condition starts one byte early

Reaching `frame_limit` does **not** fail. `serve_loop` matches `Ok(Some(<<10>>))` first, so exactly 524,288 payload bytes followed by LF are **accepted**. The next **non-LF** byte triggers overflow. My contract entered drain at `F`; it must enter at non-LF byte `F+1`. (The dead `-32600` branch is unaffected: max deliverable line is still exactly `F` and the guard is `<=`.)

Codex's contract, tighter than both mine and AGY's: `F = 524,288` payload bytes excluding LF; at most **F** drain bytes total counting the offending byte and any terminating LF, so at most **2F = 1,048,576** consumed for a rejected frame; the **existing absolute deadline** of first-payload-byte + 5,000 ms, never reset on overflow or progress, checked both before requesting input and on accepting it; `frame_bound` and resume on LF within bounds; `frame_bound_unrecoverable` with a bounded reason (`drain_byte_budget` / `drain_deadline` / `eof_during_drain`) otherwise; a separate finite shutdown budget (~250 ms proposed); `id: null`, because a rejected frame never yielded a trustworthy request id.

### 2.5 My `halt(1)` complaint was aimed at the wrong mechanism

Erlang `halt` flushes by default. The EOF the client sees comes from **never emitting a JSON error at all**, not from `halt` inherently preventing output. And even a corrected shutdown cannot guarantee delivery to a client that has stopped reading stdout — the enforceable promise is a complete error before EOF *when output remains writable within the budget*. A successful local print is not proof of receipt.

### 2.6 One correction I accept only in part

Codex says my same-plan requirement is not *necessary* for non-transplantability, because the exact proposal-hash binding already prevents a review of another proposal from passing. That is correct as stated. I keep the requirement as **authorization policy** rather than integrity: a review completed under an unrelated plan may bind this proposal's hash honestly and still carry no authority over this scope. Codex's converse is the better formulation — membership in *some* plan of a multi-plan grant does not establish authority to review *every* scope.

---

## 3. Where all three of us now agree on B2

Quarantine may be recorded **without** proving quiescence; **resumption** requires it. Codex's ordering is the one to take: record `QUARANTINED_OUTCOME_UNKNOWN` immediately and block conflicting effects; have the supervising authority inhibit dispatch and restarts for that execution generation; only then terminate and obtain evidence *under that inhibition*; inspect resources after the barrier; keep the logical effect permanently non-retryable.

Two additions worth carrying:

- **The gate must outlive the transport.** `state.unresolved` starts `False` (`successor_mcp.gleam:24`) and a successful attach clears it (`:172`). Neither event proves outstanding effects safe.
- **A new grant must not become a fresh namespace.** Effect paths are scoped by grant id (`operations.gleam:57`), so re-granting would let the same unresolved logical effect be replayed under a new prefix.

And sufficient same-boot evidence remains **absent from this repository**: a cgroup gives `cgroup.events: populated=0` over descendants plus kill-on-fork, but still needs prior containment bound to the original dispatch and a continuing admission barrier. Codex's decisive falsifier: *a child that creates a new session, closes inherited output, sleeps, then writes.* The parent and guardian both finish; a "guardian reaped" certificate passes the wrong property.

---

## 4. Running score

| # | My claim | Corrected by | Status |
|---|---|---|---|
| 1 | B5: require the review task not completed | root → AGY (deadlock mechanism) | wrong |
| 2 | B2: clear on source-manifest equality | root | wrong |
| 3 | B2: guardian receipt is sufficient same-boot evidence | Codex, verified in the guardian's own header | wrong |
| 4 | B2: dispatch on which intent filename exists | Codex (C2 collision), verified | wrong |
| 5 | B4 strands in-flight effect intents | root → AGY | overstated |
| 6 | `boot_id` change is sufficient | AGY (moot) → Codex (not sufficient at all) | wrong twice |
| 7 | B1 example: missing/non-string args trip the stop line | Codex, verified at `:119-123` | wrong; B1 itself stands |
| 8 | B7 mechanism: nested key ordering | Codex | wrong mechanism; a stronger concern replaces it |
| 9 | drain enters at `F` | Codex | off by one byte |
| 10 | `halt(1)` prevents the client seeing the error | Codex | wrong mechanism |
| 11 | "the current files validate" (B5 falsifier) | Codex (C1), verified | stale; defect stands |
| — | AGY: a completed review task can be re-claimed with a stale result | **me**, tested on an isolated store copy | refuted |

Eleven corrections to me across three reviewers, one refutation by me of a peer.

**What survives unchallenged by anyone:** B1 (narrowed), B3, B6, B8, B9, B10 — and B5's and B2's underlying defects, with better fixes than I proposed. Plus four new findings, C1–C4, all verified here.

The pattern is worth naming: of my eleven errors, **six were the same defect I was auditing for** — an observable coarser than the property. Source equality for liveness, a reap receipt for descendant death, a filename for a record kind, two unequal strings for a reboot, a manifest for a write scope, a length check for a set. Finding that class in someone else's code is much easier than not committing it.

**Not admission. No admission vote. No source written.** Root's fixes to `admission.gleam`, `operations.gleam` and `successor_mcp.gleam` landed during this relay and are **not** reviewed here — that is v10's scope.

---

**UOS footer:** [nas-1.tail55d152.ts.net:4100](http://nas-1.tail55d152.ts.net:4100/) · Sa-plan is the sole execution authority; this analysis grants no admission and no effect authority.
