# 20260909-1809 — Claude independent v9 successor review: blockers to LOCAL DEV MCP TEST

#fractal-l0 #fractal-l3 #fractal-l4 #fractal-l9 #zero-muda #stamp-stpa

**Live:** [http://nas-1.tail55d152.ts.net:4100/files/docs/reviews/20260909-1809-claude-successor-v9-dev-mcp-blockers.md](http://nas-1.tail55d152.ts.net:4100/files/docs/reviews/20260909-1809-claude-successor-v9-dev-mcp-blockers.md)

| | |
|---|---|
| Reviewer | **Claude Opus 5** (`claude-opus-5`), session `a65088e0-0f2b-497e-bd5c-97eeed9c3594`, pane `w2:p2` |
| Sa-plan | `uos/harness-admission-repair/20260909-1751` · `ADMISSION-CLAUDE-REVIEW` · worker `worker-claude-a65088e0` · **attempt 2** · lease to `2026-09-09T19:50:56Z` |
| Scope | **Source and evidence review only.** No build, no source edit, no VCS mutation, no MCP start, no paid model call. |
| Verdict scope | Blockers to **LOCAL DEV MCP TEST**. Not production admission, not full verification, not an admission vote. |
| Observed | `2026-09-09T18:53:09Z`, source frozen at v9 |

**This is not full verification.** Everything below is source reading plus digest arithmetic. Nothing was executed. Four findings are proved by construction (B1–B4); the rest are read-and-reasoned and marked so.

---

## 0. What checked out

Stated so the blockers are not read as a global negative.

- `proposal_sha256` `31bb8309…7613e` and `review_sha256` `4fa76e5b…a0b29` both **recompute exactly** against the files on disk.
- The v8→v9 counterexample is **genuine**: a retained `REVISE` review that v8 accepted is refused by v9. `admission.gleam:175-176` and `:215-216` both require `APPROVE_DEV_TEST_SCOPE`, so the verdict is gated twice on independent paths.
- Grant-equality preconditions all hold on the live files: reviewer session `abe9bd8d…` ≠ grant session `01a083d2…`, `grant_proposal.path`/`.sha256`/`.grant_id`/`.target_session`/`.target_worker` all bind.
- `same_object` (`admission.gleam:158-167`) is a correct set equality at the top level — equal length, unique keys on both sides, every key matching.
- Effect dedup is sound: durable intent before dispatch (`operations.gleam:126`), a pending intent without a result refuses rather than retries (`:113-114`), and `replay` (`:68-75`) refuses any non-`EXECUTED` saved receipt.

---

## B1 — BLOCKER — the stop line traps on errors that had no effect, and the session cannot recover

**Where:** `successor_mcp.gleam:171-174` (claim/attach), and the same shape at `:137-140` (reconcile), `:193-198` (release), `:200-203` (finish).

**What:** *every* error in the `selected` block sets `unresolved: True`, including pure argument-validation failures that dispatched nothing — `ops.text(args, "plan")` failing, or `a.lookup` returning `task_not_in_reviewed_grant` (`:168`).

**The deadlock, step by step:**

1. `harness_claim` with a mistyped `plan` → `a.lookup` fails → `:173` sets `unresolved: True`, `execution` stays `None`.
2. Next `harness_claim`, correct plan → `:160-162` — `execution` is `None`, `unresolved && name == "harness_claim"` is True → refused with `claim_outcome_requires_explicit_attach_reconciliation`.
3. `harness_attach` → `a.attach` → `admission.gleam:307` requires `row.state == "executing" && row.worker == Some(grant.worker)`. Nothing was ever claimed, so the row is `available` → `attach_requires_current_owned_attempt` → `:173` sets `unresolved: True` again.
4. `harness_reconcile` → `execution` is `None` → `ops.recover` → reads a **completion**-intent file that was never written → error → `:139` sets `unresolved: True`.

**The session can no longer claim anything, and only a process restart clears it. A typo is unrecoverable.**

**Falsifier:** start the successor, call `harness_claim` with `plan: "uos/does-not-exist"`, then call `harness_claim` with the correct plan. The second call is refused.

**Bounded fix:** the code already knows how to discriminate — `:210-211` sets `unresolved` only when the error starts with `effect_unverified:` or contains `unknown_effect_outcome`. Apply that same predicate at `:139`, `:173`, `:197`, `:202`, or gate on an explicit outcome-unknown allowlist (`claim_outcome_unknown`, `coordinator_claim_outcome_unknown`, `release_outcome_unknown`, `completion_outcome_unknown`, `effect_unverified:`). The stop line should mean *an outcome is unknown*, never *a request was refused*.

---

## B2 — BLOCKER — a dangling effect intent can never be reconciled through the MCP surface

**Where:** `operations.gleam:113-114` (the refusal) versus `:296-299` (`reconcile`) and `:333-337` (`recover`).

**What:** `effect()` refuses forever when an intent file exists without a result — correct, and exactly the no-automatic-retry rule. But **no tool clears that state**, because both reconciliation paths read a different file:

| Written by | Path |
|---|---|
| `effect()` `:126` | `…-<intent>-intent.json` |
| `reconcile()` reads `:299` | `…-<intent>-**completion**-intent.json` |
| `recover()` reads `:336` | `…-<intent>-**completion**-intent.json` |

After a transport restart mid-effect (or after any `halt(1)` — see B4), the effect intent is on disk, `state.unresolved` is gone with the process, and `harness_reconcile` fails on a missing completion-intent file. Every later `harness_write_file`/`build`/`test` with that intent id is refused permanently.

**Falsifier:** create `var/harness/effects/<grant-id>-probe-intent.json` with no matching `-result.json`, attach, call `harness_write_file` with `intent_id: "probe"` → `unknown_effect_outcome_requires_reconciliation`. Then call `harness_reconcile` with `intent_id: "probe"` → fails on the missing completion-intent path. No sequence of tool calls clears it.

**Bounded fix:** `harness_reconcile` should dispatch on which intent file exists. For a dangling **effect** intent: re-`capture` the scope, compare against the receipt's `input_manifest`, and write a terminal `-result.json` with `status: "FAILED_OR_UNVERIFIED"` and the reason — **never re-execute**. That preserves the no-retry rule while giving the state a legal exit.

---

## B3 — BLOCKER — root's temporal-authority question: **confirmed, with one path worse than described**

**Where:** `admission.gleam:140-145` (`validate_window`), `:342-345` (`fence`); `development.gleam fence_for:1-25`.

**The asymmetry.** `fence_for` horizon-checks both other authorities against the operation window — `validate_task_record(…, required_ms)` for the Sa-plan lease, and `coordinator_deadline > now + required_ms * 1000` (`fence_for:17-21`). `validate_window` checks the grant **point-in-time only**:

```
grant.expires_us > current.utc_us          -- no lower bound on remaining time
&& grant.expires_us - current.utc_us <= 86_400_000_000
```

So `admission.fence(execution, duration_ms)` passes `duration_ms + 5000` to the task and coordinator, and **nothing at all** to the grant. An operation may legally begin with 1 µs of grant validity remaining.

**Effects — detected, but the side effect is already committed.** `operations.gleam:117` fences for 60 s, `:128` runs a 60 s bounded backend, `:133` fences again with `a.fence(execution, 0)` — which re-runs `check` → `validate_window`. So an overrun **is** caught and the receipt records `FAILED_OR_UNVERIFIED`. But for `harness_write_file` the file was already replaced inside `perform` (`:85`) before that closing fence. The system correctly refuses to *claim* the effect; it does not undo it. Authority expired mid-operation and a file changed anyway.

**`harness_finish` — worse: no post-check at all.** `operations.gleam:238` fences 20 s, `:275` fences 10 s, then `:280` calls `sa.complete_sa_task`. Nothing re-validates the grant after `:275`. `:283` verifies the *row*, not the grant. **A canonical Sa-plan task completion can therefore be committed after the grant has expired**, and unlike the effect path there is no closing fence to notice.

**Falsifier:** set `expires_utc_us` to `now + 2_000_000` (2 s), attach, and call `harness_finish`. The 10 s fence at `:275` passes because the *task* lease covers it; the completion at `:280` lands after grant expiry and no error is raised.

**Bounded fix:** give `validate_window` a required-window argument and thread the operation window into it:

```
pub fn validate_window(grant, observed, required_us: Int) ->
  … && grant.expires_us - current.utc_us >= required_us …
```

with `admission.fence` passing `{duration_ms + 5000} * 1000`, so grant, task lease and coordinator lease are all fenced over the **same horizon**. Additionally add `a.check(execution.grant)` immediately after `operations.gleam:283` so completion has a closing fence like effects do.

*This is the same defect class as the rest of this review: two authorities checked against different observables, where the coarser one passes.*

---

## B4 — BLOCKER — `frame_bound` is unreachable; an oversize frame kills the transport

**Where:** `successor_mcp.gleam:61-62` versus `mcp.gleam serve_loop:20-23`.

Proved by construction:

```
serve_loop accepts a byte only while size < frame_limit        -> max line = 524288 bytes
handle() guard is   byte_size(line) <= frame_limit             -> 524288 <= 524288 = True
=> the False branch returning -32600 "frame_bound" can never be taken
```

`serve_loop` reaches `size == frame_limit` first and calls **`halt(1)`** (`:23`). The client gets EOF, not a protocol error. Same dead branch exists at `mcp.gleam:198-201`.

For a LOCAL DEV MCP TEST this matters twice over: one oversize request destroys the session, and it takes `state.execution` and `state.unresolved` with it — which then lands in B2, where the dangling effect intent has no reconciliation path.

**Falsifier:** send one 600 KB line. Expected `-32600 frame_bound`; actual process exit 1 with `harness: frame bound` on stderr.

**Bounded fix:** in `serve_loop`, on exceeding the bound, drain to the next newline and hand the handler a sentinel that produces the `-32600` reply, instead of halting. Keep `halt(1)` for invalid UTF-8 if desired, but not for a bound the protocol has an error code for.

---

## B5 — HIGH — the review's task binding is never checked, so a review of a *completed* task activates the grant

**Where:** `admission.gleam:188-198`.

`validate_review` binds `grant_id`, `target_session`, `target_worker`, the proposal path and digest, and requires `reviewer.session_id != grant.session`. It **never reads `reviewer.task_id`**.

The live v9 review carries `reviewer.task_id: "ADMISSION-REVIEW"` — the completed old task, as root already identified out of band. Nothing in the code would have caught it: the grant validates today.

**Falsifier:** the current files. `docs/reviews/20260909-1751-agy-successor-v9-grant-review.json` names a completed task and `admission.check` returns `Ok`.

**Bounded fix:** require `reviewer.task_id` to name a task that is **not `completed`** in canonical Sa-plan at check time, and require it to belong to the same plan as the scope under review. Note the trap: checking merely that the field is *present* would be a coarser observable than the property — the value has to be resolved against the store.

---

## B6 — MEDIUM — `harness_finish` is not gated by the stop line

`successor_mcp.gleam:200-203` runs `ops.finish` regardless of `state.unresolved`, while `:204-206` gates write/build/test. Partially mitigated: `successful_check` (`operations.gleam:219-229`) requires both receipts to be `EXECUTED` with a matching `input_manifest`, so an unverified *effect* cannot reach a completion. The residue is an `unresolved` set by a failed `release` or `assess` — the task then completes with an unreconciled coordinator/risk state. **Bounded fix:** apply the same `state.unresolved` guard to `harness_finish`, or state in the module header why finish is deliberately exempt.

## B7 — MEDIUM — grant equality is order-sensitive inside nested objects, and reports nothing useful when it trips

`same_object` (`admission.gleam:158-167`) is order-insensitive at the top level, but compares nested values with structural `==` on `value.Value`, whose `Object` is `List(#(String, Value))` (`value.gleam:10`). Two semantically identical `tasks[]` entries with different key order compare **unequal**. Fail-closed, so safe — but any re-serialization of the grant by a different writer breaks activation with the single opaque message `grant_differs_from_reviewed_proposal` and no indication of which field. **Bounded fix:** make the comparison structural-recursive with key-set semantics, and return the first differing key path in the error.

Related, low: `validate_review:179` reads `review_sha256` from the grant document and `:202` sets that same value into `expected`, so that one key's equality is a tautology. Harmless today because `check:211` binds it to the actual review bytes — but the guarantee lives entirely in that one line.

## B8 — LOW — `harness_clock` skips grant revalidation

`successor_mcp.gleam:128` calls `clock.observe()` directly. Every other tool re-runs `a.check`. A clock read therefore still answers after the grant expires or its file changes. Harmless in content, inconsistent in authority.

## B9 — LOW, and it is mine — `task claim` takes an unbounded duration with no sanity ceiling

Reported because it is a poka-yoke gap, and preserved as an incident per root's instruction.

I passed an **absolute** epoch-ns timestamp where `LEASE_NS` is a **duration**. Result: `lease_until_ns = 3577964911517363985` = `2083-05-19T15:08:31Z`, a **56.7-year lease**, accepted silently.

Released and reclaimed at root's instruction with `LEASE_NS=3600000000000`; now **attempt 2**, `lease_until_ns = 1788983456875493482` = `2026-09-09T19:50:56Z`, 60.0 minutes. `sa-plan help task` documents the parameter only as `LEASE_NS`, which reads equally as a deadline. **Bounded fix:** reject a duration above a policy ceiling (say 24 h), and rename the CLI parameter `LEASE_DURATION_NS`.

## B10 — observation, not a v9 defect — preflight was FAIL at review time

`bash tools/preflight` immediately before the reclaim: `FAIL (1 of 31): tracked/tools-tree 2 untracked, first: tools/telegram_client.cmi`. These are OCaml build intermediates from concurrent Telegram work, not v9 source. Reported, **not tidied** — `SC-WORKSPACE-ISO-001` INV-WS-02 makes another session's artifacts an incident to report, not to clean.

---

## Summary

| # | Severity | Blocks local dev MCP test | Proved by |
|---|---|---|---|
| B1 | BLOCKER | yes — a typo bricks the session | construction |
| B2 | BLOCKER | yes — no exit from a dangling effect intent | construction |
| B3 | BLOCKER | yes — effects and completions can outlive the grant | construction |
| B4 | BLOCKER | yes — oversize frame kills the transport | arithmetic |
| B5 | HIGH | grant activates on a review of a completed task | live files |
| B6 | MEDIUM | finish bypasses the stop line | reading |
| B7 | MEDIUM | brittle, undiagnosable equality failure | reading |
| B8 | LOW | clock tool skips revalidation | reading |
| B9 | LOW | unbounded lease duration (my own incident) | observed |
| B10 | observation | preflight FAIL, unrelated to v9 | observed |

**Limits.** Source and evidence only; nothing executed, no MCP started, no `84 passes` independently re-run — that figure is quoted from `test-v9.json`, not verified. No admission, no admission vote, no claim of full verification. Root owns `ADMISSION` attempt 2 and all source writes.

---

**UOS footer:** [nas-1.tail55d152.ts.net:4100](http://nas-1.tail55d152.ts.net:4100/) · Sa-plan is the sole execution authority; this review grants no admission and no effect authority.
