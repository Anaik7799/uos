# EV01 Bootstrap child cwd repair

#fractal-l0 #zk-adr #zero-muda

[Dossier](http://nas-1.tail55d152.ts.net:4100/files/docs/reviews/20260909-1803-ev01-bootstrap-cwd-dossier.json) · [Planning](http://nas-1.tail55d152.ts.net:4100/planning)

## 1. Scope & Trigger

Independent P1 review showed source0a8 could observe private A from ambient B while JJ initialized B's config before applying -R. Readiness was withdrawn. This follow-up repairs that public observer defect under the existing EV01 task; it does not replace the full Bootstrap scope or grant admission.

## 2. Pre-State Assessment

Selected-root config preflight existed, but the forked child inherited caller cwd. The independent invocation induced the canonical side effect; it is not attributed to an unknown writer. Canonical probes stayed paused. Root relayed qualified AGY advice before author decision; exact raw advice and observation hashes are preserved.

## 3. Execution Detail

After attempt2 active/release, available preflight, exact attempt3 claim and active checks, the author used two fresh private JJ repositories and a private config directory. Old0a8 returned PASS while B and C changed; the preservation assertion exited2. Source3c13ba3b3e210e98c289147a2041aadcdcc72ebd changes cwd only after fork and before exec. The same GREEN assertion passes; missing child cwd fails closed, and parent cwd is unchanged.

## 4. Root Cause Analysis

-R selects the target after JJ startup configuration has considered ambient cwd. Selected preflight alone therefore left an unverified second repository context. Binding child cwd and -R to the same preflighted root removes this mismatch.

## 5. Fix Taxonomy

One production process-boundary repair, interface documentation, and an OCaml two-private-repository regression helper. Failed chdir exits127 before exec and is propagated as refusal. Existing inherited config context and secure-config preflight remain intact.

## 6. Patterns & Anti-Patterns Discovered

Command arguments do not define all ambient process authority. Parent cwd mutation would introduce cross-task races; child-only binding avoids that. AGY's ephemeral-XDG suggestion is confined to synthetic private fixtures, not production context overrides. Existing source0a8 and earlier side-effect/launcher findings remain preserved.

## 7. Verification Matrix

Two-private-repo RED/GREEN fingerprints include A, B and C inode/mode/size/mtime/ctime and regular-file hashes, excluding read-driven atime. Missing child cwd refusal passes without effects. All40 retained campaign checks and61 child invocations pass at the source, including the finite predicate and two compiled mutants. Native traces show321 successful executions/16 ELF paths for retained campaign and24/6 for cwd regression, with71 and14 failed lookups respectively. No canonical observer was invoked.

## 8. Files Modified

tools/bootstrap/bootstrap_observer.ml and .mli; tools/test_ev01_bootstrap_cwd.ml; timestamped advice, risk, receipts, lossless trace JSON archives, dossier and journal in the owned sibling. All compiled artifacts remain private and hash-bound.

## 9. Architectural Observations

The five-second/shared64KiB process bound is retained. A responsive cooperative filesystem is assumed. Child cwd refusal and post-observation fingerprints are bounded evidence, not a kernel sandbox or hostile-writer proof.

## 10. Remaining Gaps

Independent reviewer rerun; full authenticated Codex+AGY dossier review; parent-handled missing governing lineage; source-current canonical observation and release-closure limits. Prior canonical receipts remain source0a8 historical evidence. EV93 ceiling and NOT_ADMITTED range are unchanged.

## 11. Metrics Summary

One child chdir binding; three scoped source/helper files; one designated old assertion failure and new preservation pass;40 retained checks/61 invocations;22 source files checked by final active observation; zero canonical observer invocations in this follow-up.

## 12. STAMP & Constitutional Alignment

AGY advice markerAGY_ADVICE_EV_CWD_1833 was recorded before decision and later bound byte-for-byte (SHAa34dde1e…). P1 risk retains raw S4/O3/Det3 and all UCA forms. VERIFY attempt3 expires19:37:39; final active PASS18:44:06, assessment13abd5f8…. Workspace epoch2 was renewed by parent. No other writer identity, task completion or runtime authority was assumed.

## 13. Conclusion

The ambient-cwd defect is repaired and privately falsified at the immutable source. Independent review remains pending; no full EV1 or admission claim follows from this bounded change.

<details><summary>18-check verification structure</summary>

1. Host timestamp recorded. 2. Candidate bound. 3. Tailscale navigation present; rendering unrun. 4. No new excluded dependency. 5. Private fixtures only. 6. Failures preserved. 7. C1 actual observer. 8. C2 designated negative. 9. C3 exact replay. 10. C4 retained independent oracle. 11. C5 retained seeds. 12. C6 process bounds. 13. C7 two retained mutants. 14. C8 retained40 cases. 15. Finite model scope explicit. 16. Native cross-language trace. 17. Sa-plan/JJ fences. 18. Sovereign review pending.

</details>
