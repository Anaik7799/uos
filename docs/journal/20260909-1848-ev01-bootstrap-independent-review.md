# EV1 independent observer review

#fractal-l0 #fractal-l5 #zk-adr #zero-muda

[Review navigation](http://nas-1.tail55d152.ts.net:4100/files/docs/reviews/20260909-1848-ev01-bootstrap-independent-approval.json)

## 1. Scope & Trigger

Independent successor review after read-side mutation; bounded observer/G-BOOT1 only.

## 2. Pre-State Assessment

Old0a8 held; initial reviewer omitted cwd. Canonical observation paused and history preserved.

## 3. Execution Detail

Immutable staging, isolated RED/GREEN, missing-child refusal and retained 40-check campaign. Native OCamlrun/raw bytecode/direct ERTS.

## 4. Root Cause Analysis

JJ startup configuration used ambient cwd before -R; observer child now changes cwd to selected root before exec.

## 5. Fix Taxonomy

Author repair; reviewer source unchanged. Explicit child context and fail-closed chdir.

## 6. Patterns & Anti-Patterns Discovered

-R is not startup isolation. Reviewer fixtures must set private cwd, even when selected repository is private.

## 7. Verification Matrix

40 campaign checks/61 invocations, 2 compiled mutants, independent private RED/GREEN, author missing-cwd control; all fresh hashes verified.

## 8. Files Modified

Own timestamped review evidence and journal only; successor changes exactly observer.ml/.mli plus cwd test helper.

## 9. Architectural Observations

Read-only intent requires context matching before launching tool. Parent process cwd remains unchanged.

## 10. Remaining Gaps

No hostile concurrent filesystem proof, no broad process-tree guarantee, missing original lineage/full sovereign EV1 review.

## 11. Metrics Summary

135 source/dependency records, 17 artifacts, 7 tool files independently rehashed.

## 12. STAMP & Constitutional Alignment

AGY1833 advice hash-bound; canonical Sa review authority and root workspace lease; no admission or canonical observer effects.

## 13. Conclusion

Bounded component approval for exact3c13; old incident preserved, whole EV1 remains not approved.

Verification checklist: metadata/timestamp/navigation observed; storage and language safety scoped; tests/model observed; cross-language control scoped; governance and admission boundary retained. The full 18-checkpoint system checklist is not claimed by this component review.
