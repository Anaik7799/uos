# EV98 closed campaign recipe: codec and synchronization obligations

Observed update: 2026-09-09T15:20:55Z. Source candidate: `dc2beed684a2b2ae4e34f69c9fd96420e2ca0f93`. Combined campaign passed; task remains executing pending independent recipe review.

Tags: #fractal-l0 #fractal-l6 #fractal-l7 #zk-adr #zero-muda

Navigation: [Cockpit](http://nas-1.tail55d152.ts.net:4100/) · [Planning](http://nas-1.tail55d152.ts.net:4100/planning) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [Final verification](http://nas-1.tail55d152.ts.net:4100/files/docs/reviews/20260909-1522-ev98-recipe-codec-verification.json).

## 1. Scope & Trigger

Parent PROGRAM authorized RECIPE_CODEC under Sa-plan `uos/ev98-wire-codec/20260909`, worker `codex-ev98-recipe-codec`, after completing CODEC. The reviewed codec adds a required source module, but the closed producer recipe still stages only the previous five modules and executes no codec cases. This task updates the fixed component campaign without granting execution, formal or sovereign admission authority.

## 2. Pre-State Assessment

Native recipe v1 has 42 fixed case IDs and three designated compiled mutants. The exact reviewed codec candidate requires `mesh_wire.gleam`; observing composed revision `9c590e75b87e2bca63adb4af966e465269203b4d` with v1 fails actual compilation with Unknown module. The original recipe digest is `412ab8bc2e203603f8fe8a5f57b8bf1359b59c82dce5fd37b523a64502cea6d8`. Root subsequently identified an acceptance assertion that incorrectly calls concurrent digest exchange synchronized before remote state arrives; that separate SYNC_STATUS repair is a dependency of final combined execution.

## 3. Execution Detail

The new canonical task was created only after preflight. The first create invocation used a nonhierarchical name and was refused; the corrected canonical name succeeded. Attempt 1 was claimed and active before source work. A later queued native observation began after its lease expired; that receipt is retained as private evidence without authority. Parent renewed the workspace at epoch 2, and exact canonical claim recovered the expired same-worker task as attempt 2. Fresh active validation passed at 13:50:01Z before further source work.

An authorized post-recovery v1 observation reproduced the missing-module compile failure. New producer tests first failed on omitted mesh_wire staging. Recipe v2 then explicitly added that sixth source, all 25 reviewed codec test cases and a physical-sample-loss mutation. The three modified OCaml files recovered after a concurrent Jujutsu stale-workspace resolution exactly match the bytes used for the passing preliminary build. No divergent revision was abandoned. The synthetic receipt fixture was copied with byte equality checks into private temporary storage after regression execution.

While waiting for final synchronization review, parent renewed workspace epoch 2 through approximately 15:31 UTC. A pre-release check correctly held on the earlier source assessment, which preceded the three recipe edits; that HOLD is preserved. Refreshing all 14 current source references passed at 14:32:44Z. Exact attempt 2 was released while quiescent, available preflight passed, and canonical claim returned attempt 3. Active validation passed at 14:33:34Z; task lease ends at 15:33:16Z. This is a bounded authority handoff, not task completion or admission.

Parent authorized composition after independent bounded approval of synchronization source `0d9bd0a8a8ecf26014904975a5e8e9a6c97d8d8d`. A new two-parent JJ change combined that immutable source with the preserved recipe change; neither shared parent was rewritten. The final binding verified exact engine/test bytes, retained every original public test function, and derived nine added synchronization exports. Only the engine acceptance file changed among original fixed inputs: old SHA-256 `1e48182f8a94c44a3a9885f58adde2de8628d9a130ab9420c077f4653028d13b`, reviewed replacement `de5dc4bcf33a89cc30adce1ed559c69b431e2bc063307345a861fde07fdc784f`. Its old/new pair and correction rationale are part of the recipe descriptor.

The final eight-file OCaml project was extracted from full commit_id selection into private storage and built natively. Active validation passed at 15:17:14Z with 14 source references and assessment SHA-256 `f53f2c92865fecfaf9e87faef63c08f792a802a6254a18593bddb92fa71ff27e`. The compiled producer ran 76 exact positive invocations and four separately compiled designated assertion failures. Its 43 recorded child invocations and 568 byte bindings include 15 candidate inputs and the unchanged 128-file realized dependency set. A syscall trace independently classified 189 successful execve calls over 12 paths; every successful executable resolved to ELF. Failed executable lookups numbered 167 and did not execute wrappers.

## 4. Root Cause Analysis

A closed staging recipe is an executable dependency declaration. Integrating a source import without updating that declaration prevents the component campaign from executing, even when a separately staged codec suite passes. Acceptance hashes must also distinguish authorized requirement corrections from arbitrary test replacement. Preserving the original list and declaring old/new hashes with a reason keeps that distinction reviewable.

## 5. Fix Taxonomy

Recipe v2 retains the 42 baseline case IDs and baseline acceptance digests literally. Codec acceptance is an additive fixed file and explicit list of 25 calls; nine reviewed synchronization calls are also explicit. The acceptance-update carrier records the original digest, replacement digest and requirement rationale for the engine-test correction. The fourth mutant substitutes logical register time for physical sample time in the actual encoder; only the designated compiled roundtrip assertion failure qualifies as rejection. Final recipe digest: `6f04ed07947f0823ba87a9af933da1dbf99b2b90d17151cea5d7ccaba51edb25`.

## 6. Patterns & Anti-Patterns Discovered

Preserve actual missing-source compilation failures separately from semantic assertion failures. Never count a compile failure as a designated mutant rejection. Baseline identifiers are obligations, while an assertion that encodes incorrect behavior needs an explicit reviewed correction. Native direct ERTS launch selectors and pinned tool hashes remain unchanged. A task lease can expire while an approval is queued; an eventual private process result does not retroactively acquire authority.

## 7. Verification Matrix

| Observation | Actual result | Scope |
|---|---|---|
| Old recipe against composed codec | HOLD; actual Unknown module compilation | Preserved post-recovery red |
| New producer control against old recipe | Assertion failed: required mesh_wire source omitted | Preserved red |
| Updated producer unit/process controls | 25 PASS | Fresh immutable native build |
| Receipt consistency regressions | 67 PASS | Private synthetic fixture |
| Static recipe completeness | 13 PASS | Direct v1 sequence/hash comparison, every codec export, closed import set, unchanged tool/dependency pins and unique mutation anchors |
| Combined codec and synchronization campaign | 76 PASS | Exact 42 baseline +25 codec +9 synchronization IDs |
| Designated mutants | 4 compiled and rejected by named assertions | Original three controls plus physical-sample codec loss |
| Native execution trace | 189 successful calls, 12 ELF paths | All successful traced execve paths resolve to ELF |
| Independent recipe review | PENDING | Not an author approval |

<details><summary>18-checkpoint verification structure</summary>

| Domain | Checkpoint | Status |
|---|---|---|
| Metadata | Timestamp and clock evidence | PASS |
| Metadata | Tailscale navigation | PASS |
| Metadata | Final immutable source binding | PASS |
| Purity/storage | Native OCaml producer | PASS |
| Purity/storage | No dependency provisioning | PASS |
| Purity/storage | Private fixtures only | PASS |
| Testing | Observed old-recipe failure | PASS |
| Testing | Exact combined positive denominator | PASS |
| Testing | Compiled codec-loss negative | PASS |
| Testing | Full formal proof | NOT ESTABLISHED |
| Observability | Actual child status and output preservation | PASS |
| Observability | Final tool/source/dependency/output hashes | PASS |
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

Editable ASCII source:

```text
[Recipe and revision] --select--> [Immutable bytes]
[Immutable bytes] --stage--> [Private native run]
[Private native run] --observe--> [Outputs and outcomes]
[Outputs and outcomes] --bind--> [Component report]
```

Editable Mermaid source with the same nodes, edges and labels:

```mermaid
flowchart LR
  A[Recipe and revision] -->|select| B[Immutable bytes]
  B -->|stage| C[Private native run]
  C -->|observe| D[Outputs and outcomes]
  D -->|bind| E[Component report]
```

## 10. Remaining Gaps

Independent recipe review is pending. Pre-integration review identified three-peer coverage invalidation after an incoming merge and an existing watermark assertion that still expected no recovery response. Root additionally identified stale ACK/delta observations overwriting a previously learned remote frontier. Those findings were repaired and independently reviewed in the separate synchronization source before final recipe binding. Full EV98 deployed transport, authenticated producer invocation, effect-time fencing, complete formal semantics and sovereign admission remain outside this component recipe. Native executable hashes do not establish a reproducible dynamic-library release closure. The separate finite health-order formal slice retains its own invocation and applicability requirements. Parent's transport work is separate and is not staged or credited by this producer.

Downstream integration obligation: `tools/generate_ev_recovery_runner.ml` lexically enumerates exported test functions in 16 modules and requires exactly 168. Added synchronization exports change that denominator, so regeneration needs a separate reviewed correction. The existing fixed 168-case runner can still execute. RECIPE_CODEC does not alter that generator, its cardinality guard, curated module set or runner.

## 11. Metrics Summary

The declared source set changes from five modules to six. Positive invocations change from 42 to 76: all 42 original IDs in their original order, 25 codec calls and nine synchronization additions. The old two-node entrypoint now invokes the full-exchange test, so 76 unique entrypoint IDs do not mean 76 independent properties. Designated mutants change from three to four. Twenty-five producer controls, 67 synthetic receipt regressions, seven CLI checks and 13 static completeness checks pass. Exact source/tool/dependency/output accounting contains 568 bindings and 43 campaign child invocations.

## 12. STAMP & Constitutional Alignment

Omitted codec staging, weakened acceptance, stale source binding and overlong processes map to the four unsafe-control forms. Explicit immutable source/case declarations, preserved old/new digests, shared process budgets and post-execution rehashes constrain these failures. Sa-plan task ownership and the parent's workspace lease remain separate, current requirements. Expired observations are preserved without force-pass or retroactive authority.

## 13. Conclusion

Candidate `dc2beed684a2b2ae4e34f69c9fd96420e2ca0f93` has actual combined native observations and preserved negative evidence. RECIPE_CODEC remains executing at attempt 3 pending independent recipe review and parent-owned completion. Formal_unavailable, Sovereign_pending and NOT_GRANTED remain explicit result fields.

Previous: [Codec journal](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20260909-1122-ev98-wire-codec-journal.md) · Next: [Final verification](http://nas-1.tail55d152.ts.net:4100/files/docs/reviews/20260909-1522-ev98-recipe-codec-verification.json).

UOS evidence footer: bounded component work · authority NONE · EV93 admitted ceiling.
