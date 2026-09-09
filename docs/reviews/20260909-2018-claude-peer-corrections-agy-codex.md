# 20260909-2018 — Peer corrections from AGY and Codex: three more of my own claims were wrong

#fractal-l0 #fractal-l3 #fractal-l4 #fractal-l9 #zero-muda #stamp-stpa

**Live:** [http://nas-1.tail55d152.ts.net:4100/files/docs/reviews/20260909-2018-claude-peer-corrections-agy-codex.md](http://nas-1.tail55d152.ts.net:4100/files/docs/reviews/20260909-2018-claude-peer-corrections-agy-codex.md)

Relayed by **Claude Opus 5**, session `a65088e0-…`. **No source written.** Independent adversarial reviews commissioned at the operator's instruction: **AGY** (Gemini 3.8 Flash, plan mode, read-only — complete) and **Codex** (`gpt-6-astra`, read-only — partial at time of writing; its one delivered finding is verified below).

Mutation guard: `jj diff --summary` before and after the peer window shows **no writes by either reviewer**. All four v9 sources are byte-identical to the baseline I snapshotted (`admission aadfd544…`, `operations 64a70dd1…`, `successor_mcp eec42449…`, `mcp 9a1c9a75…`).

---

## 1. What the peers changed in my analysis

Both reviewers uphold B1, B3, B6, B7, B8, B9, B10 and agree with my B4 downgrade. The value is in what they corrected.

### 1.1 My B5 fix was worse than I admitted — it would have deadlocked the harness

I wrote that requiring the review task to be **not completed** was wrong because it breaks the immutable lifecycle. AGY found the sharper, mechanical reason:

`development.gleam:329` counts unfinished dependencies:

```sql
(SELECT count(*) FROM sa_plan_dependency d
 LEFT JOIN sa_plan_task t ON t.plan_id=d.plan_id AND t.id=d.dependency_id
 WHERE d.plan_id=p.plan_id AND d.task_id=p.id
   AND (t.state IS NULL OR t.state!='completed')) AS blocked
```

and `evaluate_task_window` requires `blocked == 0`. `ADMISSION` depends on its review task. Under my fix the review task must **not** be completed, so `blocked >= 1`, so **every `claim`, `attach` and `fence` fails**. The harness could not have executed a single step. My fix was not merely lifecycle-wrong; it was a deadlock.

### 1.2 The plan-scope gap I found is one case of a larger flaw

AGY names it the **self-selected judge**: if `validate_review` reads `plan_id` and `task_id` from the review document itself, **the review document chooses its own validator**. My plan-scope gap is one instance. AGY adds two more that I missed:

- **Worker disparity is unchecked.** `admission.gleam:197` compares only `peer_session != session`. The *same worker* under a different session id passes. Add `review.reviewer.worker != grant.worker`.
- **A task can review itself.** Nothing asserts `review.reviewer.task_id != scope.task`.

Combined requirement: `reviewer.plan_id == scope.plan`, `reviewer.task_id != scope.task`, `reviewer.worker != grant.worker`, `reviewer.session_id != grant.session`.

### 1.3 AGY's own falsifier #3 does not reproduce — I tested it

AGY proposed that a review task completed at attempt 1 and then **re-claimed** to attempt 2 would retain a stale `result`, so the binding would pass while the task is actively executing elsewhere.

Tested on an isolated copy of the store (no canonical write): create → claim → complete with `uos.harness-peer-review.v1:deadbeef` → re-claim.

```
after complete (attempt 1): completed|probe-worker|1|uos.harness-peer-review.v1:deadbeef
re-claim                  : sa-plan: Sa-plan task is not claimable: PROBE-RESULT-ZERO
after re-claim            : completed|probe-worker|1|uos.harness-peer-review.v1:deadbeef|<completed_at_ns>
```

**A completed task is not claimable through the canonical CLI**, so the race does not arise on that path. The residual is a raw `UPDATE` on `sa_plan_task`, which has no append-only trigger — but that is outside canonical authority and barred by policy, a different threat model. AGY's falsifier is refuted for the path that matters. Reported rather than relayed on trust.

### 1.4 My boot_id tier is sound about liveness and moot in practice

I said a changed `boot_id` is sufficient quiescence evidence on its own. AGY points out it is **operationally moot**: `validate_window` (`admission.gleam:142`) requires `grant.boot == current.domain.boot_id`, so if the boot id changed **the grant is already dead** and nothing can be resumed under it. Correct. Boot change proves the old executor is gone; it cannot be a *resume* path, only a reason the whole grant must be reissued.

### 1.5 Codex refutes my second tier, and the guardian's own header agrees

I proposed that a guardian reap receipt from `tools/ecology_process.ml` is sufficient same-boot quiescence evidence. Codex: *"The runner only kills a process group and waits for its direct child; its own source says children that create new sessions need separate cgroup containment. A 'guardian returned' receipt would therefore be too coarse to prove quiescence."*

Verified against the source. `tools/ecology_process.ml:3-7`, the file's own `@laws` block:

> *"@laws: The one-shot elapsed-time deadline never resets; every exit reaps the owned child and terminates its group before the PID can be reused. **Children that create new sessions require the service cgroup boundary; this helper alone does not contain deliberately escaping executables.**"*

The guardian `setsid()`s the child and `kill(-pid)`s that group (`:22`, `:33`, `:54`). A grandchild that calls `setsid` leaves the group and survives. The receipt attests that the *owned group* was reaped — not that no descendant is running. **My tier was a coarser observable than the property, for the third time in this exchange.**

### 1.6 The consequence, stated plainly

Removing my second tier leaves **no sufficient same-boot quiescence evidence in this system today**:

| Evidence | Verdict |
|---|---|
| `boot_id` changed | proves quiescence, but the grant dies with it — not a resume path |
| guardian reap receipt | **insufficient** — the guardian's own header disclaims escaping children |
| source-manifest equality | insufficient — point-in-time observable for a liveness property (my original error) |
| elapsed time past the 60 s bound | insufficient — the bound governs the guardian, not an escaped child |
| no pid file / no process by name | insufficient — a reparented child is invisible to both |
| **cgroup `cgroup.procs` empty, or `cgroup.kill`** | **sufficient — and does not exist here yet** |

**So B2's resume path cannot be closed with what the repository has.** Either add a service cgroup boundary around effect dispatch, or accept that a dangling intent is **terminal until reboot** and say so in the contract. Both reviewers converge on the cgroup as the only sufficient mechanism, and AGY adds coordinator-epoch revocation so a late write from the old worker is refused by the fence even if it does run.

That is a larger finding than B2 as I originally wrote it: it is not just that the reconciliation path reads the wrong filename, it is that **the system cannot currently prove the precondition that any safe reconciliation requires**.

---

## 2. Quarantine record — where the two reviewers agree, and what they add

AGY independently reached my conclusion that the record must **not** live at the result path, for exactly the reason I gave: `operations.gleam:109-111` hands anything found there to `replay`. It adds two refinements worth taking:

- **Atomically rename** the dangling intent to `…-intent.json.quarantined`, so `effect()`'s `pending == None` test at `:114` stops matching without deleting evidence.
- If the workspace manifest is **dirty** at quarantine time, `harness_reconcile` must leave `unresolved: True` and require restoration — quarantine clears the *intent*, never a mutated workspace.

Schema `uos.harness-successor-quarantine.v1`, status `QUARANTINED_UNRESOLVED_DISPATCH`, disposition `TERMINALLY_RETIRED_NEVER_REEXECUTE`, intent id permanently burned.

---

## 3. B4 — both reviewers confirm root, and AGY supplies the mechanism I had not checked

AGY verified root's synchronicity claim by a route I had not: the input reader (`mcp.gleam:44-71`) is **demand-driven** — it blocks on `process.receive_forever` and reads one byte per request, never ahead. While `handler` runs an effect, `next_byte` is never called and an oversize payload sits in the kernel pipe buffer. Root's claim is true, and now true for a stated reason rather than an inspected control flow.

Drain parameters, converging with mine but tighter on the budget: `OVERFLOW_DRAIN_BUDGET_BYTES = 65_536` (not a second `frame_limit`), discarded without allocation; deadline is the frame's existing `started` clock plus `FRAME_TIMEOUT_MS`; newline within budget emits `-32600 frame_bound` and **resumes**, preserving `state.execution`; budget or deadline exhausted emits `-32600 frame_bound_fatal` / `frame_timeout`, flushes, then closes cleanly so the client sees a protocol error rather than EOF. 64 KiB is the better number — it bounds the waste at one eighth of a frame instead of doubling it.

---

## 4. Running score of my own errors in this review

| # | My claim | Corrected by | Status |
|---|---|---|---|
| 1 | B5: require the review task to be *not completed* | root, then AGY with the deadlock mechanism | **wrong** |
| 2 | B2: clear on source-manifest equality | root | **wrong** — point-in-time observable for a liveness property |
| 3 | B4 strands in-flight effect intents | root, verified by AGY | **overstated** — downgraded BLOCKER → MEDIUM |
| 4 | boot_id change is a sufficient basis to resume | AGY | **moot** — the grant dies with the boot |
| 5 | guardian reap receipt is sufficient same-boot evidence | Codex, verified in the guardian's own header | **wrong** |
| — | AGY: reclaimed review task retains a stale result | **me**, tested on an isolated store copy | **refuted** |

Five of my claims corrected, one of theirs refuted. Findings B1, B3, B6, B7, B8, B9, B10 stand unchallenged by either reviewer.

**Not admission. No admission vote. No source written.** Codex's full report will be relayed when it lands, including anything in it that contradicts the above.

---

**UOS footer:** [nas-1.tail55d152.ts.net:4100](http://nas-1.tail55d152.ts.net:4100/) · Sa-plan is the sole execution authority; this analysis grants no admission and no effect authority.
