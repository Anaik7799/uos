# Independent static assertion-closure review

Observed 2026-09-09 16:53 UTC. #fractal-l3 #zk-adr #zero-muda

1. Scope & Trigger

Review candidate168c31943c90b0c494b60ca0baff9f25c8cc702c: production verifier, direct closure tests, runner, projection and native staging helper. No production writes.

2. Pre-State Assessment

The author preserved count-only assertion failures and duplicate-condition false shadows at7bdcc794d161918ee31026afb02b44b3f4499edb. Its earlier no-tests-found invocation is non-evidence; corrected same-artifact invocation contains genuine failures.

3. Execution Detail

Separate REVIEW attempt1 active before execution. The sealed OCaml oracle validated the author's2048 rows. An independent private extraction then compiled5 immutable Gleam inputs plus reviewer probe and160 realized dependency artifacts without warnings, executed23 author tests and6 probe groups, emitted2048 actual engine rows and passed the same reference.

4. Root Cause Analysis

Counting enabled rules without materializing assertion facts hid missing closure. Asymmetric multiset membership falsely equated repeated antecedents with distinct conjunctions. The repair adds bounded add-only closure and symmetric condition-set comparison.

5. Fix Taxonomy

Read-only independent review and evidence generation. Private probes check additional operator, cycle, deduplication and refusal behavior; they do not alter candidate bytes.

6. Patterns & Anti-Patterns Discovered

Deferred rules are retried after progress; successful rules are removed, yielding at-most-once firing per invocation. Positive existential Neq/Contains remain monotone under fact addition. Local gate observations never grant effects.

7. Verification Matrix

23 author tests passed. Six independent groups passed: three-rule cycle/replay, derived Neq/Contains, multi-attribute assertion deduplication, cross-fact existential conjunction, exact work budget/UTF8/malformed bounds, and conflicting advisory atomic refusal. Both actual2048-row outputs hash to de27d5992fc03c6bc6ccbdd0bb77c32e3c50b2b6245e141bd596559df378cb2e. Both source/dependency stages were rehashed; prior29 synthetic oracle controls stay explicitly synthetic.

8. Files Modified

Only own review risk, approval report, copied raw receipts and probe sources, this journal. The independent oracle was sealed earlier at2677fde003250652c900bec76bbe28d22d8b17e6. Production remains byte-identical to168c3194.

9. Architectural Observations

Checked execution returns typed refusal with no partial result; compatibility wrapper returns exact original input on refusal. Limits precede expensive validation. The only production reference found is HUD type/presentation use; no dispatch consumer was established.

10. Remaining Gaps

Finite DAG corpus and extra cases are not a general Rete refinement proof. Legacy builders are unbounded compatibility APIs; pairwise anomaly veto is conservative and logically incomplete. No producer authentication, hostile filesystem race proof, complete transitive execution closure, live production/crosshost effects or EV admission. Historical HUD constant sovereign/consistency claims are outside scope.

11. Metrics Summary

5 immutable Gleam inputs,1 independent probe,160 dependency artifacts;23 author tests,6 added groups,2048 rows checked twice. One private probe compile failed due to operator precedence; preserved, fixed only in a fresh private stage, then compiled warning-free.

12. STAMP & Constitutional Alignment

Canonical REVIEW worker codex-ev107-rete-review attempt1 with workspace epoch2. Fresh final active observation16:53:30. No historical rewrites, source effects, shared coordinator writes or new EV identifier.

13. Conclusion

APPROVE_BOUNDED_STATIC_ASSERTION_CLOSURE for exact168c31943c90b0c494b60ca0baff9f25c8cc702c. Authority NONE; no full EV107, formal solver or admission claim.

[Machine-readable approval](http://nas-1.tail55d152.ts.net:4100/files/.uos-workspaces/ev98-peer-loop-20260909/docs/reviews/20260909-1653-ev107-rete-independent-approval.json).

Verification domains: timestamp/navigation recorded; storage and Zero-Muda preserved; bounded tests observed, full mathematical gates unrun; native OCaml/Gleam and direct ERTS observed with transitive closure limits; canonical Sa-plan/JJ observed; sovereign admission pending. The file viewer supplies presentation checklist behavior; no UI change is claimed.
