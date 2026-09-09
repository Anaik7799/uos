# 20260909-1943 — Follow-up on root's three refinements: B5 semantics, B2 quarantine, B4 drain contract

#fractal-l0 #fractal-l3 #fractal-l4 #fractal-l9 #zero-muda #stamp-stpa

**Live:** [http://nas-1.tail55d152.ts.net:4100/files/docs/reviews/20260909-1943-claude-v9-followup-b2-b4-b5-semantics.md](http://nas-1.tail55d152.ts.net:4100/files/docs/reviews/20260909-1943-claude-v9-followup-b2-b4-b5-semantics.md)

Reviewer: **Claude Opus 5** (`claude-opus-5`), session `a65088e0-…`. Observed `2026-09-09T19:06:43Z`.
**No source written. No build. No MCP started.** Root owns the fixes and asked for no further source effects; this is analysis only.

Root accepted B1, B3, B6, B7, B8 and will fix them. It pushed back on B2, B4 and B5. **On two of the three root is right, and in both cases it caught me committing the exact error I had been reporting in other findings.** That is recorded here plainly rather than absorbed quietly.

---

## B5 — root's semantics is correct; my proposed fix was wrong

I proposed requiring the review task to be **not completed**. Root is right that this breaks the normal immutable review lifecycle: a finished review *should* be completed. Rejecting the completed state would have made the correct lifecycle indistinguishable from the stale one — a check that fails on the healthy case is not a check, it is an outage.

Root's proposal — a completed review stays valid only when canonical plan/task/worker/attempt/result binds exactly `uos.harness-peer-review.v1:<review-file-sha256>` — is the right shape. It ties the *approval* to the *bytes*, which makes the review non-transferable. **Assessed sufficient, with one gap and seven traps.**

### The gap root's wording leaves open

Root lists plan/task/worker/attempt/result. It does not require that `reviewer.plan_id` **be the plan of the scope being authorised**. Without that, a legitimately completed review from *any unrelated plan* — correctly completed, correctly digest-bound, entirely honest — satisfies every listed condition and authorises a grant it was never about. Add: `reviewer.plan_id` must equal `scope.plan` for the scope being used, or at minimum appear among `grant.scopes`.

### Exact comparison, and the order matters

```
1. bind bytes first   : files.digest(reviewed) == grant.review_sha256      (admission.gleam:211, already present)
2. then read the store: sa_plan row for (reviewer.plan_id, reviewer.task_id)
3. then compare exact : row.state  == "completed"
                        row.worker == Some(reviewer.worker)
                        row.attempt == reviewer.attempt
                        row.result == Some("uos.harness-peer-review.v1:" <> grant.review_sha256)
4. and scope-bind     : reviewer.plan_id == scope.plan
```

Step 1 must supply the digest used in step 3. Computing it again from the path at step 3 reopens a TOCTOU window between two reads of the same file.

### Seven ways this still passes while a stale or transplanted review is in use

| # | Trap | Why it passes falsely |
|---|---|---|
| 1 | re-reading the review file to compute the digest at step 3 | TOCTOU between the two reads; bytes can change in between |
| 2 | accepting `state` in `{completed, executing}` | an in-flight review approves before the reviewer has finished |
| 3 | `string.contains(result, digest)` instead of `==` | a result string can embed the digest beside anything else |
| 4 | omitting `attempt` | attempt 2 completing with a different result leaves attempt 1's review live |
| 5 | omitting `worker` | any worker's completion of that task satisfies it |
| 6 | omitting the plan-scope bind (**the gap above**) | an honest review of an unrelated plan authorises this grant |
| 7 | prefix matched loosely, or unversioned | a future `uos.harness-peer-review.v2:` result satisfies a v1 check |

And the coarse-observable version to refuse outright: checking that `result` is merely **non-empty**, or that the task is merely **completed**, without binding the digest. That passes while the property is entirely false — it is this review's recurring defect wearing a new hat.

The store read must go through the existing `sa_plan_bridge` path the harness already uses. A second reader is a second source of truth.

---

## B2 — root is right, and it caught me making my own reported error

I proposed clearing a dangling intent after **source-manifest equality**. Root's objection is exactly correct: that is a **point-in-time observable standing in for a liveness property**. The old executor or its children may still be running and may write *after* my comparison returns equal. Source equality at time T says nothing about who can write at T+1.

That is precisely the defect class I have spent this whole review reporting — a release number that cannot separate two builds, a count never derived from its rows, a greedy regex reading the last match. Root found me doing it. Recorded, not softened.

### What the intents already carry (verified, no new plumbing needed)

Every effect intent on disk records `started.host_id` and `started.boot_id` — confirmed against `var/harness/effects/20260909-1751-successor-root-test-probe-1-intent.json`, keys `status, schema, intent_id, tool, signature, execution, trace_id, span_id, input_manifest, input_sha256, risk_receipt, started`, with `started.boot_id = 1cb3ba2d-…`.

Also verified: **there are 0 dangling intents right now** (360 intents, every one with a matching result). B2 is latent, not active.

### Quiescence evidence, graded honestly

| Grade | Evidence | Why |
|---|---|---|
| **Sufficient** | `started.boot_id != current boot_id` | everything from the prior boot is definitionally dead. Zero new plumbing; the field is already in every record |
| **Sufficient, same boot** | a guardian reap receipt from `tools/ecology_process.ml` proving the process group was killed and reaped, bound to that intent id | the guardian already does process-group kill with a one-shot alarm; the receipt is the artefact of the property, not a proxy |
| **Not sufficient** | source-manifest equality (my original proposal) | point-in-time observable for a liveness property |
| **Not sufficient** | elapsed wall time exceeding the 60 s bound | the bound governs the *guardian*, not an escaped child |
| **Not sufficient** | absence of a pid file, or no visible process by name | absence of evidence; a reparented child is invisible to both |

**A changed `boot_id` is sufficient on its own.** Same-boot resumption requires the guardian receipt. Nothing else qualifies.

### The quarantine record, and the trap in where it lives

Quarantine must be a **third terminal kind**, never a result:

- **Path:** `…-<intent>-quarantine.json` — *not* the result path. This matters: `effect()` reads the result path first (`operations.gleam:109-111`) and hands anything found to `replay`, which requires `status == "EXECUTED"`. A quarantine file placed at the result path would therefore be refused forever as `saved_effect_failed_or_unverified_no_retry` — a different dead end, not an exit. `effect()` must learn about the quarantine path explicitly.
- **Contents:** `status: "QUARANTINED_OUTCOME_UNKNOWN"`; the original intent digest and `intent_id`; the manifest at quarantine time *and* the original `input_sha256`, labelled as observations rather than as proof; the quiescence evidence with its grade from the table above; the clock at quarantine.
- **Invariants:** never re-execute; never convert to `EXECUTED`; the `intent_id` is **permanently burned** and may not be reused. Quarantine unblocks *other* work; it does not resolve this effect. The outcome stays unknown, and the record says so in its own status name so no later reader can mistake it for a completed or failed effect.

---

## B4 — root's correction is right, and I am downgrading my own finding

Root states that oversize input cannot interrupt an in-flight effect because the handler is synchronous. **Checked against `mcp.gleam serve_loop:9-27` and it is correct**: bytes are read, then `handler` is called synchronously at `:13`, and no read occurs while an effect runs. An oversize frame can therefore only arrive *between* operations.

That materially narrows my own finding, so I am narrowing it rather than defending it:

- The dead `-32600` branch is still real (arithmetic unchanged: max deliverable line is exactly `frame_limit`, and the guard is `<=`).
- `halt(1)` still costs the session and the in-memory `unresolved` flag.
- But the chain I drew into B2 — dying mid-effect and leaving a dangling intent — **cannot be caused by an oversize frame**. Reaching that state requires an external kill, an OOM or a crash during `perform`. Invalid UTF-8 and reader errors also halt, but they too are read between operations.

**B4 therefore drops from BLOCKER to MEDIUM on my own assessment.** It is a diagnosability and session-durability defect, not a state-corruption one.

### Bounded drain contract (unlimited drain refused, and root is right to refuse it)

An unlimited drain is a denial-of-service: a stream with no newline never terminates the loop.

```
on size reaching frame_limit with no newline yet:
  enter Draining with
    drain_budget_bytes = frame_limit          (worst case 2 x frame_limit per frame)
    deadline           = the frame's EXISTING started clock + frame_timeout_ms
                         (serve_loop already tracks `started`; no new clock)

  newline within budget  -> emit -32600 "frame_bound", reset, continue serving
  budget exhausted       -> emit -32600 "frame_bound_unrecoverable",
                            FLUSH stdout, then close deliberately
```

The flush before close is the point: the client gets a protocol response instead of EOF, which is the whole complaint in B4. Worst case per frame is bounded in both bytes and time, and the time bound reuses the deadline already being tracked rather than introducing a second clock.

---

## Quiescence ACK — bounded, and only for myself

Root reports that AGY created and attach-probed a root-identity grant outside review scope, preserved and revoked it, and awaits explicit quiescence ACK.

For **this session** (`a65088e0-…`, worker `worker-claude-a65088e0`), attested:

- **No MCP started.** Neither successor nor legacy, at any point in this review.
- **No grant held or loaded.** I set no `UOS_HARNESS_*` variable and did not invoke `admission.load`.
- **No effect dispatched.** No `harness_*` tool called; no build, no test, no source edit.
- **No process left running** by me against this plan.
- **Writes:** exactly four files, all under `docs/reviews/` — the two v9 findings artefacts and the two for this follow-up. Nothing in `var/harness/`, no grant, no receipt, no risk portfolio.
- **Sa-plan:** `ADMISSION-CLAUDE-REVIEW` attempt 2, completed. The attempt-1 56.7-year lease was released before reclaim and is recorded as an incident.

**I cannot attest to AGY's quiescence.** I did not observe its process, and one session's ACK is not evidence about another's — which is the same reason a board ACK is not a peer acknowledgement under SYNC-05.

## On keeping the review task open for v10

`ADMISSION-CLAUDE-REVIEW` attempt 2 is **completed** — it was completed after the findings were delivered, as instructed at the time. Reopening it would contradict the immutable-review-lifecycle semantics root just defended in B5, and would also break the very binding root proposes there: a completed review task's `result` is what pins the review bytes.

A fresh task is therefore the consistent move, not a reopened one. Root should create `ADMISSION-CLAUDE-REVIEW-V10` (or name it as it prefers) and I will claim it — with a **duration**, not a timestamp.

---

## Status of the ten findings

| # | Root position | My position now |
|---|---|---|
| B1 | accepted, will fix | unchanged |
| B2 | real; wants quarantine + quiescence evidence | **my fix was wrong**; quarantine design above |
| B3 | accepted, will fix | unchanged; `harness_finish` remains the sharper half |
| B4 | bounded drain; synchronous handler | **downgraded BLOCKER → MEDIUM** on root's correct point |
| B5 | completed-review semantics | **my fix was wrong**; root's is right, plus the plan-scope gap |
| B6, B7, B8 | accepted, will fix | unchanged |
| B9 | reviewer incident | unchanged |
| B10 | observation | unchanged |

Net: of four blockers, **two stand as blockers** (B1, B3), one is real with a different fix than I proposed (B2), and one downgrades (B4).

**Not admission. No admission vote. No source written.**

---

**UOS footer:** [nas-1.tail55d152.ts.net:4100](http://nas-1.tail55d152.ts.net:4100/) · Sa-plan is the sole execution authority; this analysis grants no admission and no effect authority.
