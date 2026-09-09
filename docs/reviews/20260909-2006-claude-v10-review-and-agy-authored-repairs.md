# 20260909-2006 — v10 review, and the five remaining findings repaired

#fractal-l0 #fractal-l3 #fractal-l4 #fractal-l9 #zero-muda #stamp-stpa

**Live:** [http://nas-1.tail55d152.ts.net:4100/files/docs/reviews/20260909-2006-claude-v10-review-and-agy-authored-repairs.md](http://nas-1.tail55d152.ts.net:4100/files/docs/reviews/20260909-2006-claude-v10-review-and-agy-authored-repairs.md)

| | |
|---|---|
| Reviewer / applier | **Claude Opus 5** (`claude-opus-5`), session `a65088e0-…` |
| Patch author | **AGY** (Gemini 3.8 Flash), read-only; patches applied, corrected and tested here |
| Sa-plan | `uos/harness-admission-repair/20260909-1751` · `ADMISSION-CLAUDE-REVIEW-V10` · worker `worker-claude-a65088e0` · attempt 1 · lease as a **duration** |
| Observed | `2026-09-09T20:10:06Z` |

**Not admission. No admission vote.** Root never declared a v10 candidate — no grant proposal, no build/test evidence, no task — so the bytes were pinned here and the review is bound to those exact digests.

---

## 1. Root's fixes — six findings genuinely closed

Pinned candidate before any patch of mine: `admission e2d1b56f`, `operations 47818c52`, `successor_mcp c37cbeae`, `mcp 2a9777ea`. Baseline **89/89 green** (root added 5 tests).

| | What landed | Verdict |
|---|---|---|
| **B1** | `outcome_unknown` allowlist, and claim/attach/release/finish wrap their errors with `*_outcome_unknown:` prefixes so a refused request is distinguishable from an unknown outcome | **closed** |
| **B3** | `grant_budget_valid(expires_us, now_us, required_ms)` + `validate_window_for`; `fence` revalidates the grant over `duration_ms + 5000` against the fence's own clock; `a.check` after completion | **closed, both halves** |
| **B5** | **Better than what I proposed.** The *grant* declares `review_task`, and the review's self-declared `plan_id`/`task_id` must match it — so the review no longer selects its own validator, which was AGY's "free parameter" flaw. Plus `worker != grant_worker`, `attempt > 0`, and `terminal_matches` requiring `completed`, `completed_at_ns > 0` and exact result equality | **closed** |
| **B6** | `harness_finish` gated by `unresolved` | **closed** |
| **B7** | `same_value` recursive with array zip; failures report `grant_differs_from_reviewed_proposal:$.<field>` | **closed, with the diagnosability requested** |
| **B8** | `harness_clock` revalidates via `a.check` | **closed** |

Root's B5 work deserves the specific credit: my proposed fix would have deadlocked the harness, and root's replacement is stronger than the correction AGY and I converged on.

---

## 2. The five that remained, now repaired

AGY authored the patches read-only; they were applied, **one of them corrected**, compiled and tested here.

### 2.1 C2 — `effect_path` collision → `@` delimiter, and kind moves inside the record

`-` is inside the `admission.component` charset, so `intent "x-completion" + suffix "intent"` and `intent "x" + suffix "completion-intent"` produced the same path. `@` is outside that charset, so the ambiguity is gone **by construction rather than by convention**.

More important than the delimiter: `replay` now authenticates `schema` **and** `kind` from inside the record, and `reconcile`/`recover` dispatch on the declared kind and `intent_id`. A filename was never evidence of a record's meaning. Pre-existing v9 effect files are deliberately unreadable — they carry no `kind`, so reading them would reinstate the exact untyped observable this removes.

### 2.2 C3 — `capture` blind to authorized writes → **AGY's patch was wrong and was corrected**

AGY widened `capture` itself to `sources ∪ writes`. That breaks the healthy lifecycle: `capture` is candidate **identity**, bound into build and test receipts and compared at `finish`. The journal is legitimately written *after* the build, so widening identity makes every honest completion fail `verification_candidate_mismatch`.

**That is the same shape of error root caught me making on B5** — a fix that rejects the correct path. Verified before applying: the live grant has the journal in `write_paths` and `read_paths` but not `source_paths`, and `successful_check` binds the build receipt's `input_manifest` to the candidate at finish time.

Corrected design — two questions, two observables:

| Manifest | Scope | Answers |
|---|---|---|
| `capture` | `sources` | candidate identity: what was built and tested |
| `guard_capture` | `sources ∪ writes`, sorted and deduplicated | did anything move underneath this effect |

`write_manifest_clean` (AGY's, kept verbatim) replaces the old `name == "harness_write_file" || before == after` bypass, which let **any** file move underneath a write. Now the declared target must carry exactly the digest claimed and every other path must be untouched. Build and test require the whole guard manifest unchanged, which is what closes C3.

### 2.3 C4 — the guardian bound by nothing → `control_dependencies`

`tools/ecology_process.ml` bounds every effect's time, output and process group, is invoked from `ecology_capability_ffi.erl:127`, and appeared in no path list and none of the nine control digests. It is not a BEAM module, so `module_info(md5)` cannot reach it.

`admission.control_dependencies` declares it; `control_dependencies_match` verifies the grant's declared digest against the file. Fails closed on every arm: missing declaration, missing file, unreadable file, invalid digest, mismatch, wrong set, padded set, non-object.

### 2.4 B2 — dangling effect intent → quarantine that retires rather than resolves

`reconcile` now dispatches on kind and reaches the effect-intent case. A dangling intent is quarantined, never resumed:

- `QUARANTINED_OUTCOME_UNKNOWN`, `PERMANENT_NO_RETRY`, and an explicit statement that **no success, failure or rollback has been established**.
- Manifest fields carry an `observation_disclaimer` marking them as point-in-time observations, not evidence — the exact confusion my original fix rested on.
- `missing_evidence` names what cannot be shown: no containment bound to the original dispatch; the guardian reaps only its owned group and *its own header says so*; a changed `boot_id` would prove death but also fails `validate_window`, so it is not a resumption path.
- `quiescence_grade: NO_SUFFICIENT_SAME_BOOT_EVIDENCE_IN_THIS_SUBSTRATE`, `resumption: REFUSED`. The honest answer, not an invented one.
- Tombstones at `burned@<intent>` and `burned-signature@<sig>`. The signature tombstone is keyed **outside** the grant id, so a fresh grant cannot become a new namespace for the same logical effect — Codex's point.

### 2.5 B4 — bounded drain

Root's `refuse_frame` already fixed the bare EOF. The session-durability half is now done: on the first **non-LF** byte past the limit — the boundary Codex corrected, since exactly `frame_limit` bytes followed by LF are *accepted* — the frame is discarded and drained within two bounds: at most `frame_limit` further bytes, and the frame's **existing** absolute deadline, deliberately never reset. A delimiter within budget emits `-32600 frame_bound` and the session **resumes**; either bound exhausted emits `frame_bound_unrecoverable:<reason>` and closes. `id` is null because a rejected frame never yielded a trustworthy request id.

---

## 3. Evidence

```
build            : clean
suite            : 94/94 pass   (89 baseline + 5 new)
preflight        : FAIL 1 of 31 -- tracked/tools-tree, 2 untracked Telegram build
                   intermediates from a concurrent session. Not v10 source.
                   Reported, not tidied (SC-WORKSPACE-ISO-001 INV-WS-02).
```

**Five mutants, five killed** — the tests fail when the property is broken, which is the only evidence a test suite is worth anything:

| Mutation | Result |
|---|---|
| revert `effect_path` to the hyphen encoding | FAIL |
| drop the `kind` check from `replay` | FAIL |
| `guard_capture` ignores writes (revert C3) | FAIL |
| write guard ignores movement of other files | FAIL |
| guardian digest check disabled | FAIL |
| all restored | 94/94 |

Repaired candidate: `admission d0a2fe78`, `operations 1c43909f`, `successor_mcp c37cbeae` (untouched by me), `mcp 1adec340`, `test/harness_successor_test 7c587acd`.

---

## 4. What is still open, stated plainly

- **The v10 grant needs new fields.** `check_review_task` requires `review_task` and `check` now requires `control_dependencies`; the current grant carries neither, so it fails closed. A v10 grant proposal is required before anything activates. This is correct behaviour, not a defect — but it is a gap between the code and the artefacts.
- **B2 is retired, not solved.** Quarantine gives the state an exit. It does not make the outcome known, and it cannot: **no sufficient same-boot quiescence evidence exists in this repository.** Closing that needs a cgroup boundary bound to the original dispatch. The quarantine record says so in its own `missing_evidence` rather than implying otherwise.
- **The drain is untested at runtime.** Its logic is bounded and reviewed; no test drives a real reader, because that needs a live transport. Reported as untested rather than counted as verified.
- **C1 stands as an observation:** the live grant carries root's in-place revocation, which makes `same_object` reject it on a length mismatch before reaching any field. Revocation by annotation is effective by construction.
- **B9, B10** unchanged.

**No production effect. No admission. Root's `ADMISSION` task and its artefacts were not touched.**

---

**UOS footer:** [nas-1.tail55d152.ts.net:4100](http://nas-1.tail55d152.ts.net:4100/) · Sa-plan is the sole execution authority; this work grants no admission and no effect authority.
