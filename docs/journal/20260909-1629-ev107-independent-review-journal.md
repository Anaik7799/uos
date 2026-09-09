# EV107 independent digest comparison review

Observed 2026-09-09 16:28 UTC. #fractal-l3 #zk-adr #zero-muda

1. Scope & Trigger

Parent requested independent review of four frozen files at 11eeca9df5c14961ed4b4b8fc990752ad7bccd46. Only digest comparison correctness is assessed.

2. Pre-State Assessment

The author preserved ignored-expectation RED failures and repaired canonical digest checks. EV101 source stayed frozen in this workspace.

3. Execution Detail

Separate canonical REVIEW attempt1, preflight and active observations preceded effects. Exact commit_id extraction, six private Dune builds and 13 native invocations succeeded.

4. Root Cause Analysis

Previously, verdict-kind agreement could ignore the supplied digest and differing passing digests. The candidate now requires exact payload expectation and both passing digest results.

5. Fix Taxonomy

Independent review only; no implementation changes. Four private mutants challenge primary digest, reference digest, rejection code and verdict-kind disagreement.

6. Patterns & Anti-Patterns Discovered

Matching rejection means comparison agreement, never dispatch permission. Shared filter helpers do not constitute an independent proof.

7. Verification Matrix

18 author cases rebuilt, 14 independent controls passed, four compiled disagreement mutants refused, and 14 controls passed with changed diagnostic prose. All 54 unique immutable author archive files, 87 actual recorded bindings and eight dependency hashes matched.

8. Files Modified

Only timestamped review risk, copied receipts/helpers, review index and this journal. The source at EV101 evidence e42c79197add2f893d3a88db9a6441f9e4f836d0 remains unchanged.

9. Architectural Observations

Caller search found tests and evidence driver only. The production MCP/Rete path was not established; historical module headers are not integration evidence.

10. Remaining Gaps

No formal solver, full EV107, dispatch safety, SQL-filter completeness, producer authentication or hermetic release closure. Historical bounded function name has no payload-size cap. Native argv and Dune trace were inspected; transitive compiler/linker execution was not traced.

11. Metrics Summary

Six independent variants; maximum fixture one million bytes; outer deadline180seconds and individual native children60seconds. Filesystem reads remain cooperative. Zero source edits.

12. STAMP & Constitutional Alignment

Sa-plan REVIEW authority and workspace epoch2 preserved; active at16:28:49. No live state, other tasks, admission ceiling or historical receipts changed.

13. Conclusion

APPROVED_BOUNDED_DIGEST_COMPARISON for exact candidate11eeca9; authority NONE and EV admission NOT_GRANTED. Machine-readable verdict and raw receipts are indexed alongside this journal.

[Review index](http://nas-1.tail55d152.ts.net:4100/files/.uos-workspaces/ev98-peer-loop-20260909/docs/reviews/20260909-1629-ev107-independent-index.json).

Verification checklist: metadata/time/navigation observed; Zero-Muda/storage preserved; component tests observed, mathematical gates unrun; native OCaml/domain boundary observed with transitive execution limit; Sa-plan/JJ governance observed; sovereign admission remains pending. Document presentation checklist is supplied by the file viewer; no UI change claimed.
