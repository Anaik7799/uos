# EV98 closed campaign recipe: codec and synchronization obligations

Observed update: 2026-09-09T14:02:15Z. Task remains executing; final combined campaign and independent review are pending.

Tags: #fractal-l0 #fractal-l6 #fractal-l7 #zk-adr #zero-muda

Navigation: [Cockpit](http://nas-1.tail55d152.ts.net:4100/) · [Planning](http://nas-1.tail55d152.ts.net:4100/planning) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [Preliminary observations](http://nas-1.tail55d152.ts.net:4100/files/docs/reviews/20260909-1302-ev98-recipe-codec-preliminary.json).

## 1. Scope & Trigger

Parent PROGRAM authorized RECIPE_CODEC under Sa-plan `uos/ev98-wire-codec/20260909`, worker `codex-ev98-recipe-codec`, after completing CODEC. The reviewed codec adds a required source module, but the closed producer recipe still stages only the previous five modules and executes no codec cases. This task updates the fixed component campaign without granting execution, formal or sovereign admission authority.

## 2. Pre-State Assessment

Native recipe v1 has 42 fixed case IDs and three designated compiled mutants. The exact reviewed codec candidate requires `mesh_wire.gleam`; observing composed revision `9c590e75b87e2bca63adb4af966e465269203b4d` with v1 fails actual compilation with Unknown module. The original recipe digest is `412ab8bc2e203603f8fe8a5f57b8bf1359b59c82dce5fd37b523a64502cea6d8`. Root subsequently identified an acceptance assertion that incorrectly calls concurrent digest exchange synchronized before remote state arrives; that separate SYNC_STATUS repair is a dependency of final combined execution.

## 3. Execution Detail

The new canonical task was created only after preflight. The first create invocation used a nonhierarchical name and was refused; the corrected canonical name succeeded. Attempt 1 was claimed and active before source work. A later queued native observation began after its lease expired; that receipt is retained as private evidence without authority. Parent renewed the workspace at epoch 2, and exact canonical claim recovered the expired same-worker task as attempt 2. Fresh active validation passed at 13:50:01Z before further source work.

An authorized post-recovery v1 observation reproduced the missing-module compile failure. New producer tests first failed on omitted mesh_wire staging. Recipe v2 then explicitly added that sixth source, all 25 reviewed codec test cases and a physical-sample-loss mutation. The three modified OCaml files recovered after a concurrent Jujutsu stale-workspace resolution exactly match the bytes used for the passing preliminary build. No divergent revision was abandoned. The synthetic receipt fixture was copied with byte equality checks into private temporary storage after regression execution.

While waiting for final synchronization review, parent renewed workspace epoch 2 through approximately 15:31 UTC. A pre-release check correctly held on the earlier source assessment, which preceded the three recipe edits; that HOLD is preserved. Refreshing all 14 current source references passed at 14:32:44Z. Exact attempt 2 was released while quiescent, available preflight passed, and canonical claim returned attempt 3. Active validation passed at 14:33:34Z; task lease ends at 15:33:16Z. This is a bounded authority handoff, not task completion or admission.

## 4. Root Cause Analysis

A closed staging recipe is an executable dependency declaration. Integrating a source import without updating that declaration prevents the component campaign from executing, even when a separately staged codec suite passes. Acceptance hashes must also distinguish authorized requirement corrections from arbitrary test replacement. Preserving the original list and declaring old/new hashes with a reason keeps that distinction reviewable.

## 5. Fix Taxonomy

Recipe v2 retains the 42 baseline case IDs and baseline acceptance digests literally. Codec acceptance is an additive fixed file and explicit list of 25 calls. The acceptance-update carrier records the original digest, replacement digest and requirement rationale for each reviewed correction. The fourth mutant substitutes logical register time for physical sample time in the actual encoder; only the designated compiled roundtrip assertion failure qualifies as rejection.

## 6. Patterns & Anti-Patterns Discovered

Preserve actual missing-source compilation failures separately from semantic assertion failures. Never count a compile failure as a designated mutant rejection. Baseline identifiers are obligations, while an assertion that encodes incorrect behavior needs an explicit reviewed correction. Native direct ERTS launch selectors and pinned tool hashes remain unchanged. A task lease can expire while an approval is queued; an eventual private process result does not retroactively acquire authority.

## 7. Verification Matrix

| Observation | Actual result | Scope |
|---|---|---|
| Old recipe against composed codec | HOLD; actual Unknown module compilation | Preserved post-recovery red |
| New producer control against old recipe | Assertion failed: required mesh_wire source omitted | Preserved red |
| Updated producer unit/process controls | 25 PASS | Preliminary working bytes match private build |
| Receipt consistency regressions | 67 PASS | Private synthetic fixture |
| Static recipe completeness | 13 PASS | Direct v1 sequence/hash comparison, every codec export, closed import set, unchanged tool/dependency pins and unique mutation anchors |
| Combined codec and synchronization campaign | PENDING | Awaiting reviewed synchronization bytes |
| Independent recipe review | PENDING | Not an author approval |

<details><summary>18-checkpoint verification structure</summary>

| Domain | Checkpoint | Status |
|---|---|---|
| Metadata | Timestamp and clock evidence | PASS |
| Metadata | Tailscale navigation | PASS |
| Metadata | Final immutable source binding | PENDING |
| Purity/storage | Native OCaml producer | PASS |
| Purity/storage | No dependency provisioning | PASS |
| Purity/storage | Private fixtures only | PASS |
| Testing | Observed old-recipe failure | PASS |
| Testing | Exact combined positive denominator | PENDING |
| Testing | Compiled codec-loss negative | PENDING |
| Testing | Full formal proof | NOT ESTABLISHED |
| Observability | Actual child status and output preservation | PASS |
| Observability | Final tool/source/dependency/output hashes | PENDING |
| Observability | Live multi-host behavior | NOT ESTABLISHED |
| Governance | Canonical attempt 3 | PASS |
| Governance | Owned JJ sibling | PASS |
| Governance | Independent review | PENDING |
| Provenance | EV93 ceiling retained | PASS |
| Provenance | New admission | NOT GRANTED |

</details>

## 8. Files Modified

`tools/ev_receipts/ev98_recipe.ml` declares the reviewed codec source, acceptance bytes, case groups and explicit baseline corrections. `ev_campaign.ml` records recipe lineage and the designated encoder mutation. `campaign_test.ml` checks retained obligations, unique combined case IDs and explicit acceptance corrections. Timestamped risk manifests, native observations and this journal preserve execution history; no runtime or admission ledger is changed.

## 9. Architectural Observations

The producer remains closed to caller-selected policy, commands, coverage and supplied execution logs. It extracts exact commit_id bytes with the pinned native Jujutsu binary, stages the declared dependency closure, compiles and executes its own fixed runner, and rehashes artifacts and captured output. The expanded recipe changes what that fixed campaign observes, not the authority of an observation.

## 10. Remaining Gaps

Final SYNC_STATUS source/test integration, combined execution and independent review are pending. Pre-integration review identified three-peer coverage invalidation after an incoming merge and an existing watermark assertion that still expected no recovery response. Root additionally identified stale ACK/delta observations overwriting a previously learned remote frontier. Those findings remain with the separate source owner before final recipe pinning. Full EV98 deployed transport, authenticated producer invocation, effect-time fencing, complete formal semantics and sovereign admission remain outside this component recipe. Native executable hashes do not establish a reproducible dynamic-library release closure. The separate finite health-order formal slice retains its own invocation and applicability requirements.

Downstream integration obligation: `tools/generate_ev_recovery_runner.ml` lexically enumerates exported test functions in 16 modules and requires exactly 168. Added synchronization exports change that denominator, so regeneration needs a separate reviewed correction. The existing fixed 168-case runner can still execute. RECIPE_CODEC does not alter that generator, its cardinality guard, curated module set or runner.

## 11. Metrics Summary

The proposed source denominator changes from five modules to six. Positive obligations change from 42 to 67 before the separately reviewed synchronization additions. Designated mutants change from three to four. Preliminary producer controls are 25 passing cases; receipt consistency remains 67 passing synthetic cases. Final combined counts will be recorded only after actual execution.

## 12. STAMP & Constitutional Alignment

Omitted codec staging, weakened acceptance, stale source binding and overlong processes map to the four unsafe-control forms. Explicit immutable source/case declarations, preserved old/new digests, shared process budgets and post-execution rehashes constrain these failures. Sa-plan task ownership and the parent's workspace lease remain separate, current requirements. Expired observations are preserved without force-pass or retroactive authority.

## 13. Conclusion

The recipe update has observed red and preliminary green controls. RECIPE_CODEC remains executing at attempt 3, pending the combined immutable campaign and independent review. Formal_unavailable, Sovereign_pending and NOT_GRANTED remain explicit result fields.

Previous: [Codec journal](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20260909-1122-ev98-wire-codec-journal.md) · Next: [Preliminary observations](http://nas-1.tail55d152.ts.net:4100/files/docs/reviews/20260909-1302-ev98-recipe-codec-preliminary.json).

UOS evidence footer: bounded component work · authority NONE · EV93 admitted ceiling.
